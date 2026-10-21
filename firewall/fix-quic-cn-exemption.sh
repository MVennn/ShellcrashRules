#!/bin/sh
# fix-quic-cn-exemption.sh - SUPERSEDED on 2026-10-21, kept as a pointer.
#
# The original version emitted "ip daddr @inet shellcrash cn_ip return".
# nftables v1.1.6 on the AX3000T rejects that syntax (and every other
# cross-table set reference variant), so it could never be deployed.
# The working implementation is firewall/quicguard-sync.sh: it mirrors
# ShellCrash's cn_ip / cn_ip6 into sets owned by the quicguard table and
# generates a self-contained /etc/quicguard.nft.
#
# Deploy from the PC (one command, installs + runs the generator):
#
#   ssh -i ~/.ssh/owrt_ax3000t root@10.0.0.1 \
#       'cat > /etc/quicguard-sync.sh && chmod 755 /etc/quicguard-sync.sh && sh /etc/quicguard-sync.sh' \
#       < firewall/quicguard-sync.sh
#
# Verify:
#   ssh root@10.0.0.1 'nft list chain inet quicguard prerouting | head -5'
#   (expect: ip daddr @cn_ip_mirror return / ip6 daddr @cn_ip6_mirror return)
#
# Re-run the same command after a subscription update or ShellCrash restart,
# because ShellCrash rebuilds cn_ip / cn_ip6 at that point.

echo "This script is superseded - use firewall/quicguard-sync.sh (see the header of this file)." >&2
exit 2
