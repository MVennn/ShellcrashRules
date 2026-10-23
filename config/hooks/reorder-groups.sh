#!/bin/sh
# 调整 proxy-groups 顺序：常用组排前面
# 用法: reorder-groups.sh /path/to/config.yaml
# 由 starts/clash_modify.sh 在配置合并后、校验前调用
#
# 排序规则正本：docs/ARCHITECTURE.md「代理组排序规则（新增组必须遵守）」。
# 新增 / 改名 / 删除组时：
#   1) 把组名加进「组顺序」order[] 的对应分段；
#   2) 需要出现在 🚀 节点选择 的，再加进「成员顺序」order[]；
#   3) 节点需要排序的组，加进 node-order pass 的目标列表，新地区补 rank()。
# 漏加不会报错，组会按原顺序追加到面板最后。
#
# 【第一遍：proxy-groups 同名去重】
# 背景：ShellCrash 的 merger_yaml 把用户自定义组（yamls/proxy-groups.yaml）追加进
#       订阅基础配置。基础配置本身是"上一次合并结果"的快照，可能已含同名组；
#       一旦去重标记(#自定义策略组开始/结束)失配，同名组会带重复 YAML key，
#       mihomo 拒载 -> ShellCrash 静默回退基础配置 -> 全部自定义 AI/Google 分流消失。
# 策略：同名组保留"第一次出现"的定义（merger_yaml 把用户最新定义放在最前），
#       丢弃后续重复项（来自基础配置的陈旧副本）。
# 由 starts/clash_modify.sh 在配置合并后、校验前调用

CFG="$1"
# MIXED_PORT_NORMALIZE 归一 mixed-port：
#   ShellCrash 多次生成时可能把它叠成 127.0.0.1:127.0.0.1:7890 → mihomo 校验失败
#   → ShellCrash 静默回退基础配置 → 自定义代理组全丢（2026-10-20 09:18 实测）
MP_PORT=$(grep -m1 -E "^mixed-port:" "$CFG" 2>/dev/null | grep -oE "[0-9]+$")
if [ -n "$MP_PORT" ]; then
  sed -i -E "s|^mixed-port:.*$|mixed-port: $MP_PORT|" "$CFG"
fi
[ -f "$CFG" ] || { echo "no config: $CFG" >&2; exit 1; }


# ---- 第一遍：proxy-groups 清洗（同名组去重 + 组内重复 key 清理）----
# 背景：ShellCrash 的 merger_yaml 把用户自定义组（yamls/proxy-groups.yaml）并入订阅基础配置。
#       基础配置本身是"上一次合并结果"的快照，会残留上一轮的自定义组；而上一轮跑过的
#       reorder-groups.sh 会把组重排，打散 "#自定义策略组开始/结束" 标记的配对，
#       导致下一轮官方去重 sed 漏掉残留组。残留组再次并入后，YAML 出现
#       "mapping key \"type\" already defined" —— mihomo 拒载整个配置，
#       ShellCrash 静默回退到基础配置，自定义 AI/Google 分流全部消失（2026-10-20 02:33 实测发生）。
# 处理：同名组保留第一次出现（merger_yaml 把用户最新定义放在最前），丢弃后续重复项；
#       同一组块内重复出现的 key 也一并丢弃（YAML 本身不允许重复 key）。
awk '
function flush() {
	if (cur == "") return
	# 纯中转组：默认出口就是 🚀 节点选择 / DIRECT，删组后在规则里直接改指目标。
	if (curname in drop) { cur = ""; return }
	if (curname in seen) { dropped++; cur = ""; return }
	seen[curname] = 1
	print cur
	cur = ""
}
function resetkeys() { delete keyseen }
BEGIN {
	inpg = 0; cur = ""; curname = ""; dropped = 0; dupkey = 0
	drop["📲 电报消息"] = 1
	drop["📢 谷歌FCM"] = 1
	drop["Ⓜ️ 微软服务"] = 1
	drop["🍎 苹果服务"] = 1
}
/^proxy-groups:/ { inpg = 1; print; next }
inpg && /^[a-zA-Z]/ { flush(); inpg = 0; print; next }
inpg {
	if ($0 ~ /^  - name: /) {
		flush(); resetkeys()
		cur = $0
		curname = substr($0, 11)
		sub(/[ \t]+#.*$/, "", curname)
		sub(/^[ \t]+/, "", curname)
		sub(/[ \t]+$/, "", curname)
		next
	}
	if ($0 ~ /^  - \{name: /) {
		flush(); resetkeys()
		cur = $0
		curname = $0
		sub(/^  - \{name: /, "", curname)
		sub(/[, \t].*$/, "", curname)
		sub(/^[ \t]+/, "", curname)
		sub(/[ \t]+$/, "", curname)
		next
	}
	# 组内 key 行: 记录 (缩进,key名)，重复即丢弃
	if (match($0, /^[ ]+[A-Za-z0-9_.-]+:/)) {
		ind = index($0, ":")
		kk = substr($0, 1, ind - 1)
		keyname = kk
		sub(/^[ ]+/, "", keyname)
		indent = length(kk) - length(keyname)
		if ((indent SUBSEP keyname) in keyseen) { dupkey++; next }
		keyseen[indent SUBSEP keyname] = 1
	}
	if (cur != "") { cur = cur "\n" $0; next }
	print
	next
}
{ print }
END {
	if (inpg) flush()
	if (dropped > 0) print "[reorder-groups] 丢弃重复 proxy-group: " dropped " 个" > "/dev/stderr"
	if (dupkey > 0) print "[reorder-groups] 丢弃组内重复 key: " dupkey " 行" > "/dev/stderr"
}
' "$CFG" > "$CFG.dedup" && mv -f "$CFG.dedup" "$CFG"

awk '
function flush() {
	if (cur == "") return
	if (curname in seen) { dropped++; cur = ""; return }
	seen[curname] = 1
	print cur
	cur = ""
}
BEGIN { inpg = 0; cur = ""; curname = ""; dropped = 0 }
/^proxy-groups:/ { inpg = 1; print; next }
inpg && /^[a-zA-Z]/ { flush(); inpg = 0; print; next }
inpg {
	if ($0 ~ /^  - name: /) {
		flush()
		cur = $0
		curname = substr($0, 11)
		sub(/[ \t]+#.*$/, "", curname)
		sub(/^[ \t]+/, "", curname)
		sub(/[ \t]+$/, "", curname)
		next
	}
	if ($0 ~ /^  - \{name: /) {
		flush()
		cur = $0
		curname = $0
		sub(/^  - \{name: /, "", curname)
		sub(/[, \t].*$/, "", curname)
		sub(/^[ \t]+/, "", curname)
		sub(/[ \t]+$/, "", curname)
		next
	}
	if (cur != "") { cur = cur "\n" $0; next }
	print
	next
}
{ print }
END {
	if (inpg) flush()
	if (dropped > 0) print "[reorder-groups] 丢弃重复 proxy-group: " dropped " 个" > "/dev/stderr"
}
' "$CFG" > "$CFG.dedup" && mv -f "$CFG.dedup" "$CFG"

# ---- 第二遍前：剔除机场伪节点（2026-10-23）----
# 机场把「剩余流量 / 套餐到期 / 过滤掉N条线路」也写成真节点形状；其中
# 「过滤掉14条线路」与「日本-优化」同 server/port/uuid，会被 url-test 选中，
# 健康检查一抖就把 🛟 主备自动 整组切到公共池（2026-10-23 实测）。
# 从 proxies 定义与所有 proxy-groups 成员里一起删除；只删 flow 形式定义，
# block 形式（多行）不碰，避免留下孤儿字段。
awk '
BEGIN { inp = 0; ing = 0; dropped = 0 }
/^proxies:/ { inp = 1; ing = 0; print; next }
/^proxy-groups:/ { ing = 1; inp = 0; print; next }
inp && /^[a-zA-Z]/ { inp = 0 }
ing && /^[a-zA-Z]/ { ing = 0 }
inp && /^ *- *\{ *name: / && $0 ~ /(剩余流量|套餐|到期|过滤掉|官网)/ { dropped++; next }
ing && /^      - / {
	nm = $0
	sub(/^      - /, "", nm)
	sub(/[ \t]+#.*$/, "", nm)
	if (nm ~ /(剩余流量|套餐|到期|过滤掉|官网)/) { dropped++; next }
}
{ print }
END { if (dropped > 0) print "[reorder-groups] 丢弃机场伪节点定义/成员: " dropped " 行" > "/dev/stderr" }
' "$CFG" > "$CFG.decoy" && mv -f "$CFG.decoy" "$CFG"

# 纯中转组已删除：把它们的规则改指当前实际出口，行为保持不变。
# 用 awk 按字段重写，避免 sed 对 4 字节 emoji 的匹配差异。
awk '
BEGIN {
	drop["📲 电报消息"] = 1
	drop["📢 谷歌FCM"] = 1
	drop["Ⓜ️ 微软服务"] = 1
	drop["🍎 苹果服务"] = 1
}
{
	# 组员引用：已删组直接去掉
	if ($0 ~ /^      - /) {
		name = $0
		sub(/^      - /, "", name)
		sub(/[ \t]+#.*$/, "", name)
		if (name in drop) next
	}
	# 规则目标：- TYPE,payload,target[,no-resolve] [#comment]
	if ($0 ~ /^[[:space:]]*-[[:space:]]/) {
		line = $0
		comment = ""
		if (match(line, /[[:space:]]+#/)) {
			comment = substr(line, RSTART)
			line = substr(line, 1, RSTART - 1)
		}
		n = split(line, a, ",")
		if (n >= 3) {
			t = a[3]
			sub(/[[:space:]]+$/, "", t)
			if (t == "📲 电报消息" || t == "📢 谷歌FCM") a[3] = "🚀 节点选择"
			else if (t == "Ⓜ️ 微软服务" || t == "🍎 苹果服务") a[3] = "DIRECT"
			line = a[1]
			for (i = 2; i <= n; i++) line = line "," a[i]
		}
		print line comment
		next
	}
	print
}
' "$CFG" > "$CFG.remap" && mv -f "$CFG.remap" "$CFG"

awk '
function flush() {
	if (cur != "") { n++; name[n]=curname; buf[n]=cur; cur="" }
}
BEGIN {
	# 代理组展示顺序：常用入口 → 专用出口 → 地区组 → 兜底/工具 → 内部子组。
	# 未知组（模板更新新增）由 flush 末尾按原顺序补在后面，不会被丢掉。
	order[1]="🚀 节点选择"
	order[2]="🛟 主备自动"
	order[3]="♻️ 自动选择"
	order[4]="🚀 手动切换"
	order[5]="🤖 AI接口"
	order[6]="🤖 人工智能"
	order[7]="🤖 AI网页"
	order[8]="🤖 干净出口"
	order[9]="🔗 GitHub 出口"
	order[10]="🎬 B站解锁"
	order[11]="𝕏 媒体"
	order[12]="📺 大流量"
	order[13]="🆓 公共备用"
	order[14]="🇭🇰 香港节点"
	order[15]="🇯🇵 日韩节点"
	order[16]="🇨🇳 台湾节点"
	order[17]="🇸🇬 新加坡节点"
	order[18]="🇺🇲 美国节点"
	order[19]="🇮🇳 印度节点"
	order[20]="🇨🇦 加拿大节点"
	order[21]="🇩🇪 德国节点"
	order[22]="🇬🇧 英国节点"
	order[23]="🎥 NETFLIX"
	order[24]="🎥 DisneyP"
	order[25]="🌍 国外媒体"
	order[26]="🛑 广告拦截"
	order[27]="🎯 全球直连"
	order[28]="🐟 漏网之鱼"
	order[29]="𝕏 媒体-HY2"
	order[30]="𝕏 媒体-备用"
	norder=30
}
/^proxy-groups:/ { inpg=1; print; next }
inpg && /^[a-z]/ {
	flush()
	for (i=1;i<=norder;i++) for (j=1;j<=n;j++) if (name[j]==order[i]) { print buf[j]; used[j]=1 }
	for (j=1;j<=n;j++) if (!used[j]) print buf[j]
	delete used
	n=0
	inpg=0
	print
	next
}
inpg {
	if ($0 ~ /^  - name: /) {
		flush()
		cur=$0
		curname=$0
		sub(/^  - name: /,"",curname)
		next
	}
	if (cur != "") cur = cur "\n" $0
	else print
	next
}
{ print }
END {
	if (inpg) {
		flush()
		for (i=1;i<=norder;i++) for (j=1;j<=n;j++) if (name[j]==order[i]) { print buf[j]; used[j]=1 }
		for (j=1;j<=n;j++) if (!used[j]) print buf[j]
	}
}
' "$CFG" > "$CFG.reorder" && mv -f "$CFG.reorder" "$CFG"

# 第二遍：重排 🚀 节点选择 的成员顺序（主备自动/自动选择置顶）
has_fallback=0
grep -q "  - name: 🛟 主备自动" "$CFG" && has_fallback=1
has_public=0
grep -q "  - name: 🆓 公共备用" "$CFG" && has_public=1
has_bulk=0
grep -q "  - name: 📺 大流量" "$CFG" && has_bulk=1
has_github=0
grep -q "  - name: 🔗 GitHub 出口" "$CFG" && has_github=1
awk -v has_fallback="$has_fallback" -v has_public="$has_public" -v has_bulk="$has_bulk" -v has_github="$has_github" '
function flush_members() {
	if (cnt > 0) {
		for (i = 1; i <= norder; i++)
			for (j = 1; j <= cnt; j++)
				if (names[j] == order[i] && !used[j]) { print items[j]; used[j] = 1 }
		for (j = 1; j <= cnt; j++) if (!used[j]) print items[j]
		# 兜底：如果 clash_modify 的组插入失效，补上受管成员
		for (i = 1; i <= nwant; i++)
			if (has[want[i]] && !present[want[i]]) print "      - " want[i] " #自定义策略组"
		delete used
		delete present
		cnt = 0
	}
}
BEGIN {
	# 主选择器成员顺序：先「自动/手动」，再专用出口，再地区组，DIRECT 最后。
	# 地区组放后面是因为日常更常用「手动切换」进具体节点；专用组则常被手动切换。
	order[1] = "🛟 主备自动"
	order[2] = "♻️ 自动选择"
	order[3] = "🚀 手动切换"
	order[4] = "🤖 AI接口"
	order[5] = "🔗 GitHub 出口"
	order[6] = "🎬 B站解锁"
	order[7] = "𝕏 媒体"
	order[8] = "📺 大流量"
	order[9] = "🆓 公共备用"
	order[10] = "🇭🇰 香港节点"
	order[11] = "🇯🇵 日韩节点"
	order[12] = "🇨🇳 台湾节点"
	order[13] = "🇸🇬 新加坡节点"
	order[14] = "🇺🇲 美国节点"
	order[15] = "🇮🇳 印度节点"
	order[16] = "🇨🇦 加拿大节点"
	order[17] = "🇩🇪 德国节点"
	order[18] = "🇬🇧 英国节点"
	order[19] = "DIRECT"
	norder = 19
	want[1] = "🛟 主备自动"
	want[2] = "🆓 公共备用"
	want[3] = "📺 大流量"
	want[4] = "🔗 GitHub 出口"
	nwant = 4
	has["🛟 主备自动"] = has_fallback
	has["🆓 公共备用"] = has_public
	has["📺 大流量"] = has_bulk
	has["🔗 GitHub 出口"] = has_github
}
$0 == "  - name: 🚀 节点选择" { inblock = 1; print; next }
inblock && $0 ~ /^  - name: / && $0 != "  - name: 🚀 节点选择" { inblock = 0 }
inblock && /^    proxies:[ ]*$/ { print; inlist = 1; next }
inlist {
	if ($0 ~ /^      - /) {
		cnt++
		items[cnt] = $0
		nm = $0
		sub(/^      - /, "", nm)
		sub(/[ \t]+#.*$/, "", nm)
		names[cnt] = nm
		present[nm] = 1
		next
	}
	flush_members()
	inlist = 0
}
{ print }
END { flush_members() }
' "$CFG" > "$CFG.reorder-members" && mv -f "$CFG.reorder-members" "$CFG"

# 第三遍：🚀 手动切换 / ♻️ 自动选择 的节点按地区排序
# 目的：手动选节点时先看到常用地区，而不是订阅顺序（日本→新加坡→香港…随机）。
# 稳定排序：同地区内保持订阅原顺序；未知地区排最后。
awk '
function rank(n) {
	if (n ~ /香港|HK|Hong Kong/) return 1
	if (n ~ /日本|JP|Japan|日韩|韩国|KR|Korea/) return 2
	if (n ~ /台湾|TW|Taiwan/) return 3
	if (n ~ /新加坡|SG|Singapore/) return 4
	if (n ~ /美国|US-|LA-|United States/) return 5
	if (n ~ /印度|India|孟买|Mumbai/) return 6
	if (n ~ /加拿大|Canada|多伦多|Toronto|温哥华|Vancouver/) return 7
	if (n ~ /德国|Germany|法兰克福|Frankfurt/) return 8
	if (n ~ /英国|United Kingdom|London|伦敦|UK|GB/) return 9
	return 99
}
function flush_list() {
	for (i = 2; i <= cnt; i++) {
		key = items[i]; kr = r[i]; j = i - 1
		while (j >= 1 && r[j] > kr) { items[j+1] = items[j]; r[j+1] = r[j]; j-- }
		items[j+1] = key; r[j+1] = kr
	}
	for (i = 1; i <= cnt; i++) print items[i]
	delete items; delete r; cnt = 0
}
$0 ~ /^  - name: / {
	if (inlist) { flush_list(); inlist = 0 }
	if (inblock) { flush_list(); inblock = 0 }
	if (index($0, "  - name: 🚀 手动切换") == 1 || index($0, "  - name: ♻️ 自动选择") == 1) {
		inblock = 1
		print
		next
	}
	print
	next
}
inblock && /^[a-zA-Z]/ {
	if (inlist) { flush_list(); inlist = 0 }
	flush_list()
	inblock = 0
	print
	next
}
inblock && /^    proxies:[ ]*$/ { print; inlist = 1; next }
inlist {
	if ($0 ~ /^      - /) {
		cnt++
		items[cnt] = $0
		nm = $0
		sub(/^      - /, "", nm)
		sub(/[ \t]+#.*$/, "", nm)
		r[cnt] = rank(nm)
		next
	}
	flush_list()
	inlist = 0
}
{ print }
END { if (inblock || inlist) flush_list() }
' "$CFG" > "$CFG.node-order" && mv -f "$CFG.node-order" "$CFG"

# 第四遍：🐟 漏网之鱼 的 DIRECT 收尾（模板默认把 DIRECT 夹在地区组中间）
awk '
$0 == "  - name: 🐟 漏网之鱼" { inblock = 1; print; next }
inblock && /^  - name: / {
	if (direct != "") { print direct; direct = "" }
	inblock = 0
}
inblock && /^[a-zA-Z]/ {
	if (direct != "") { print direct; direct = "" }
	inblock = 0
}
inblock && /^      - DIRECT$/ { direct = $0; next }
{ print }
END { if (inblock && direct != "") print direct }
' "$CFG" > "$CFG.fish-order" && mv -f "$CFG.fish-order" "$CFG"
