#!/bin/sh
LC_ALL=C
export LC_ALL
# urldecode_run <string> : prints the percent decoded bytes of a query value.
#
# The decoding happens inside awk and the raw bytes are printed directly. An
# earlier version escaped every byte as an octal sequence and let printf
# expand it again; that round trip silently produced an empty string when the
# script ran under uhttpd, which broke every group name lookup.
# The byte table covers 0..255 so UTF-8 names (emoji, flags) survive.
urldecode_run() {
	printf '%s' "$1" | awk '
	function hexval(c) { return index("0123456789abcdef", tolower(c)) - 1 }
	BEGIN { for (i = 0; i < 256; i++) ord[sprintf("%c", i)] = i }
	{
		s = $0
		n = length(s)
		out = ""
		i = 1
		while (i <= n) {
			c = substr(s, i, 1)
			if (c == "%") {
				if (i + 2 > n) exit 2
				v = hexval(substr(s, i + 1, 1)) * 16 + hexval(substr(s, i + 2, 1))
				if (v < 0) exit 2
				if (v < 32 || v == 127) exit 2
				out = out sprintf("%c", v)
				i += 3
			} else if (c == "+") {
				out = out " "
				i++
			} else {
				v = ord[c]
				if (v == "") exit 2
				out = out sprintf("%c", v)
				i++
			}
		}
		printf "%s", out
	}'
}


for v in "/proxies/GLOBAL" "/proxies/%F0%9F%87%AF%F0%9F%87%B5%20%E6%97%A5%E6%9C%AC/%E4%BC%98%E5%8C%96/delay" "/proxies/%E2%9C%93%20%E8%87%AA%E5%8A%A8%E9%80%89%E6%8B%A9"; do
  out=$(urldecode_run "$v")
  printf 'in=[%s]
out=[%s] len=%s

' "$v" "$out" "$(printf '%s' "$out" | wc -c)"
done
