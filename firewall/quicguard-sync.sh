#!/bin/sh
# quicguard-sync.sh
#
# Regenerate /etc/quicguard.nft with a domestic (CN) QUIC exemption.
#
# WHY A MIRROR SET:
#   nftables on this router (v1.1.6) rejects every cross-table set reference
#   syntax ("ip daddr @inet shellcrash cn_ip" -> syntax error, "@cn_ip" ->
#   "did you mean set 'cn_ip' in table inet 'shellcrash'"). So the CN IP set
#   that ShellCrash maintains cannot be used from the quicguard table directly.
#   Instead this script copies its elements into sets owned by quicguard and
#   rewrites the table file, which makes the file SELF-CONTAINED: rc.local and
#   guardian.sh can reload it before/without ShellCrash running.
#
# USAGE:
#   sh /etc/quicguard-sync.sh              # generate + validate + install + load
#   sh /etc/quicguard-sync.sh --dry-run    # generate + validate only, touch nothing
#
# WHEN TO RUN:
#   - once, to install
#   - again after a subscription update or ShellCrash restart, because
#     ShellCrash rebuilds cn_ip / cn_ip6 at that point
#   Safe to run any time: idempotent, validates before touching the live table,
#   and reloads only when the generated file actually changed.
#
# ASCII only on purpose (piped from Windows).

set -u
DRY=0
[ "${1:-}" = "--dry-run" ] && DRY=1
NFT=/usr/sbin/nft
OUT=/etc/quicguard.nft
TMP=/tmp/quicguard.nft.new.$$
CHK=/tmp/quicguard.chk.$$

say() { echo "[quicguard-sync] $*"; }
die() {
	echo "[quicguard-sync] ERROR: $*" >&2
	rm -f "$TMP" "$CHK"
	exit 1
}

[ -x "$NFT" ] || die "nft not found at $NFT"
$NFT list set inet shellcrash cn_ip >/dev/null 2>&1 \
	|| die "set inet shellcrash cn_ip not found - start ShellCrash first"

# Print the element list of a set as one comma-separated line.
extract() {
	$NFT list set inet shellcrash "$1" 2>/dev/null \
		| sed -n '/elements = {/,$p' \
		| sed -e '1s/.*elements = {[[:space:]]*//' -e 's/}.*//' \
		| tr '\n\t' '  ' \
		| sed -e 's/[[:space:]][[:space:]]*/ /g' \
		      -e 's/[[:space:]]*$//' \
		      -e 's/,[[:space:]]*$//'
}

CN4=$(extract cn_ip)
[ -n "$CN4" ] || die "could not extract elements from cn_ip (empty result), live table untouched"
CN6=$(extract cn_ip6)
[ -n "$CN6" ] || CN6=""

CN4N=$(printf '%s' "$CN4" | tr -cd ',' | wc -c)
CN4N=$((CN4N + 1))
CN6N=0
[ -n "$CN6" ] && CN6N=$(printf '%s' "$CN6" | tr -cd ',' | wc -c) && CN6N=$((CN6N + 1))
say "cn_ip elements: $CN4N  cn_ip6 elements: $CN6N"

# One element per line keeps the generated file readable and avoids very long
# lines in nft's input buffer.
fmt() { sed 's/,[[:space:]]*/&\n\t\t\t     /g'; }

{
	cat <<'HDR'
# QUIC fast-fail for mihomo, with a domestic (CN) exemption.
#
# GENERATED FILE - do not edit by hand. Regenerate with:
#     sh /etc/quicguard-sync.sh
# Source of the CN ranges: ShellCrash's sets inet shellcrash cn_ip / cn_ip6
# (mirrored here because nft 1.1.6 cannot reference sets across tables).
#
# Why the exemption:
#   cn-rule-set domains resolve to REAL CDN IPs (mix DNS mode), and those
#   targets are DIRECT anyway. Blocking their QUIC only makes Android apps
#   (QQ/WeChat image CDNs) wait for the QUIC handshake timeout before falling
#   back to TCP -> thumbnails stay blank for seconds.
#   Foreign targets keep getting QUIC rejected, so no Chinese exit IP can
#   reach them over HTTP/3.
#   Google's China edge (203.208.32.0/19, 2401:3800::/32) is excluded from
#   ShellCrash's cn_ip sets, so Google never matches the exemption below.

table inet quicguard {
	set cn_ip_mirror {
		type ipv4_addr
		flags interval
		auto-merge
		elements = {
HDR
	printf '%s\n' "$CN4" | fmt
	echo "		}"
	if [ -n "$CN6" ]; then
		cat <<'HDR6'
	}
	set cn_ip6_mirror {
		type ipv6_addr
		flags interval
		auto-merge
		elements = {
HDR6
		printf '%s\n' "$CN6" | fmt
		echo "		}"
	fi
	cat <<'BODY'
	}

	chain prerouting {
		type filter hook prerouting priority -150; policy accept;

		# Bilibili API: QUIC would leave with the CN IP (CN exemption below).
		#   Reject it so the app falls back to TCP, where Redir + the domain
		#   rules (api/cm.bilibili.com -> B站 group) can take over.
		ip daddr { 157.148.134.0/24, 27.37.206.0/24 } udp dport { 443, 8443 } counter reject with icmpx type port-unreachable
		ip6 daddr 2408:8756::/31 udp dport { 443, 8443 } counter reject with icmpx type port-unreachable

		# 0) Domestic targets: DIRECT anyway -> QUIC may leave directly.
		ip daddr @cn_ip_mirror return
		ip6 daddr @cn_ip6_mirror return

		# 1) fake IP ranges (mihomo fake IPv4 / fake IPv6) and Google's China edge
		ip daddr 198.18.0.0/15 udp dport { 443, 8443 } counter reject with icmpx type port-unreachable
		ip6 daddr fc00::/16 udp dport { 443, 8443 } counter reject with icmpx type port-unreachable
		ip daddr 203.208.32.0/19 udp dport { 443, 8443 } counter reject with icmpx type port-unreachable
		ip6 daddr 2401:3800::/32 udp dport { 443, 8443 } counter reject with icmpx type port-unreachable

		# 2) other QUIC/DoQ ports (FCM 5228 / DoQ 19302 etc) - UDP cannot be proxied
		udp dport { 4433, 5226, 5228, 8081, 8883, 19302 } counter reject with icmpx type port-unreachable

		# 3) global QUIC block - only non-CN targets reach this point
		udp dport { 443, 8443 } counter reject with icmpx type port-unreachable
	}
}
BODY
} > "$TMP" || die "failed to write $TMP"

[ -s "$TMP" ] || die "generated file is empty"

# Validate under a throwaway table name: a syntax or interval error must never
# reach the live ruleset.
sed 's/table inet quicguard {/table inet quicguard_chk {/' "$TMP" > "$CHK"
if ! $NFT -c -f "$CHK" 2>/tmp/quicguard.chk.err; then
	say "validation FAILED:"
	cat /tmp/quicguard.chk.err >&2
	rm -f /tmp/quicguard.chk.err
	if [ "$DRY" = "1" ]; then
		say "--- generated file around the end of cn_ip_mirror ---"
		sed -n '4520,4545p' "$TMP"
	fi
	die "generated table is invalid, live table untouched"
fi
rm -f "$CHK" /tmp/quicguard.chk.err
say "validation OK"

if [ "$DRY" = "1" ]; then
	say "dry-run: generated $TMP ($(wc -c < "$TMP") bytes), live table untouched"
	sed -n '1,25p' "$TMP"
	say "--- last 20 lines ---"
	tail -20 "$TMP"
	rm -f "$TMP"
	exit 0
fi

changed=0
if [ -f "$OUT" ] && cmp -s "$TMP" "$OUT"; then
	say "generated file unchanged"
else
	[ -f "$OUT" ] && cp -f "$OUT" "$OUT.bak.$(date +%Y%m%d-%H%M%S)" 2>/dev/null && say "backed up old $OUT"
	cp -f "$TMP" "$OUT.new" && mv -f "$OUT.new" "$OUT" || die "cannot install $OUT"
	changed=1
	say "installed $OUT"
fi
rm -f "$TMP"

live=0
if $NFT list table inet quicguard >/dev/null 2>&1 && \
   $NFT list table inet quicguard 2>/dev/null | grep -q '@cn_ip_mirror'; then
	live=1
fi

if [ "$changed" = "1" ] || [ "$live" = "0" ]; then
	# "add table" semantics never replace an existing table, so drop it first.
	# Window without QUIC fast-fail rules: a few milliseconds.
	$NFT destroy table inet quicguard 2>/dev/null
	if ! $NFT -f "$OUT" 2>/tmp/quicguard.load.err; then
		say "load FAILED:"
		cat /tmp/quicguard.load.err >&2
		rm -f /tmp/quicguard.load.err
		die "quicguard NOT loaded"
	fi
	rm -f /tmp/quicguard.load.err
	say "table inet quicguard reloaded"
else
	say "live table already up to date (counters preserved)"
fi

# Survive sysupgrade.
for f in /etc/quicguard.nft /etc/quicguard-sync.sh; do
	if grep -qx "$f" /etc/sysupgrade.conf 2>/dev/null; then
		:
	else
		echo "$f" >> /etc/sysupgrade.conf
		say "added $f to sysupgrade.conf"
	fi
done

say "live sets: cn_ip_mirror=$(nft list set inet quicguard cn_ip_mirror 2>/dev/null | wc -l) lines, cn_ip6_mirror=$(nft list set inet quicguard cn_ip6_mirror 2>/dev/null | wc -l) lines"
say "done"
exit 0
