#!/bin/ash
# post-sc-update.sh - ShellCrash 脚本更新后的修复与验收
# 官方 tarball 只覆盖 init.sh/menu.sh/start.sh/version/lang/menus/libs/starts + 默认列表，
# 其中 starts/ 里有 3 个文件带本地补丁，更新后必须恢复：
#   clash_modify.sh    -> rules-mid / rules-cnip / reorder-groups 钩子 + sniffer skip-domain + TLS override
#   fw_nftables.sh     -> FCM 5228/DoQ 19302 走代理 + 剔除 203.208.32.0/19 + QUIC reject
#   start_legacy_wd.sh -> mkdir -p /tmp/ShellCrash + 陈旧锁自愈 + pidof 存活短路
# 用法：sh /etc/ShellCrash/post-sc-update.sh

CRASHDIR=/etc/ShellCrash
PATCHDIR=$CRASHDIR/local-patches
LOG=/root/post-sc-update.log
: > "$LOG"
log(){ printf '%s\n' "$*" | tee -a "$LOG"; }
section(){ log ""; log "===== $* ====="; }

restore_file(){
    f=$1; marker=$2
    if grep -q "$marker" "$CRASHDIR/starts/$f" 2>/dev/null; then
        log "OK: starts/$f 已含标记 [$marker]"
    elif [ -f "$PATCHDIR/$f" ]; then
        cp -f "$CRASHDIR/starts/$f" "$CRASHDIR/starts/$f.upstream.$(date +%Y%m%d-%H%M%S)" 2>/dev/null
        cp -f "$PATCHDIR/$f" "$CRASHDIR/starts/$f"
        chmod 755 "$CRASHDIR/starts/$f"
        log "FIX: starts/$f 已从 local-patches 恢复（官方版另存为 .upstream.*）"
    else
        log "!! starts/$f 缺标记 [$marker] 且 local-patches 没有备份"
    fi
}

section "1. 恢复 starts/ 本地补丁"
restore_file clash_modify.sh 'rules-mid.sh'
restore_file fw_nftables.sh 'QUIC_BLOCK_MARKER'
restore_file start_legacy_wd.sh 'mkdir -p /tmp/ShellCrash'
sh -n "$CRASHDIR/starts/clash_modify.sh" && log "clash_modify.sh 语法 OK" || log "!! clash_modify.sh 语法错误"
sh -n "$CRASHDIR/starts/fw_nftables.sh" && log "fw_nftables.sh 语法 OK" || log "!! fw_nftables.sh 语法错误"
sh -n "$CRASHDIR/starts/start_legacy_wd.sh" && log "start_legacy_wd.sh 语法 OK" || log "!! start_legacy_wd.sh 语法错误"

section "2. 补回 cron 生命线"
if ! grep -q 'start_legacy_wd.sh' /etc/crontabs/root 2>/dev/null; then
    echo '* * * * * /bin/ash /etc/ShellCrash/starts/start_legacy_wd.sh shellcrash #ShellCrash保守模式守护进程' >> /etc/crontabs/root
    log "FIX: 补回 legacy 看门狗 cron"
else
    log "OK: legacy 看门狗 cron 在"
fi
if ! grep -q 'task/task.sh 106' /etc/crontabs/root 2>/dev/null; then
    echo '*/10 * * * * /etc/ShellCrash/task/task.sh 106 #运行时每10分钟自动保存面板配置' >> /etc/crontabs/root
    log "FIX: 补回面板配置保存 cron"
else
    log "OK: 面板配置保存 cron 在"
fi
crontab /etc/crontabs/root 2>/dev/null

section "3. 启动链路兜底检查"
if grep -q 'mkdir -p /tmp/ShellCrash' /etc/rc.local 2>/dev/null; then
    log "OK: rc.local 建目录在"
else
    awk 'NR==1{print; print ""; print "# ShellCrash: /tmp is tmpfs, create runtime dir before S99shellcrash"; print "mkdir -p /tmp/ShellCrash"; next} {print}' \
        /etc/rc.local > /tmp/rc.local.new && cat /tmp/rc.local.new > /etc/rc.local && rm -f /tmp/rc.local.new
    log "FIX: rc.local 已补 mkdir"
fi
if grep -q 'mkdir -p /tmp/ShellCrash' "$CRASHDIR/guardian.sh" 2>/dev/null; then
    log "OK: guardian 建目录在"
else
    log "!! guardian.sh 缺 mkdir（guardian.sh 是用户文件，理论上不会被更新覆盖）"
fi
if grep -q 'cron lifeline' "$CRASHDIR/guardian.sh" 2>/dev/null; then
    log "OK: guardian cron 自愈在"
else
    log "!! guardian.sh 缺 cron lifeline"
fi
if /etc/init.d/shellcrash enabled 2>/dev/null; then
    log "FIX: init.d/shellcrash 被启用（start_old=ON 下会产生双实例），已 disable"
    /etc/init.d/shellcrash disable
else
    log "OK: init.d/shellcrash 保持 disabled（legacy 模式）"
fi

section "4. 启动"
mkdir -p /tmp/ShellCrash
if pidof CrashCore >/dev/null 2>&1 && netstat -lntp 2>/dev/null | grep -q ':7892'; then
    log "已在运行，跳过启动"
else
    sh "$CRASHDIR/start.sh" start 2>&1 | tail -25 | tee -a "$LOG"
    i=0
    while [ "$i" -lt 30 ]; do
        pidof CrashCore >/dev/null 2>&1 && netstat -lntp 2>/dev/null | grep -q ':7892' && break
        sleep 1; i=$((i+1))
    done
fi
pidof CrashCore >/dev/null 2>&1 && log "CrashCore 已运行" || log "!! CrashCore 未起来"

section "5. 验收"
RCFG=/tmp/ShellCrash/config.yaml
if [ -s "$RCFG" ]; then
    "$CRASHDIR"/CrashCore.raw -t -d "$CRASHDIR" -f "$RCFG" 2>&1 | tail -3 | tee -a "$LOG"
    log "分组数：$(grep -c '^  - name:' "$RCFG")"
    log "RULE-SET,cn：$(grep -c 'RULE-SET,cn,' "$RCFG")"
    grep -Fq '🤖 AI接口' "$RCFG" && log "自定义组：OK" || log "!! 自定义组缺失"
else
    log "!! 运行态配置不存在"
fi
curl -s --max-time 8 -o /dev/null -w 'baidu=%{http_code} ' http://www.baidu.com | tee -a "$LOG"
curl -s --max-time 12 -x http://127.0.0.1:7890 -o /dev/null -w 'google=%{http_code} ' https://www.google.com | tee -a "$LOG"
curl -s --max-time 12 -x http://127.0.0.1:7890 -o /dev/null -w 'opencode=%{http_code}\n' https://opencode.ai | tee -a "$LOG"

log ""
log "日志：$LOG"
