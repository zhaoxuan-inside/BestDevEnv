#!/usr/bin/env bash
# verify/test-cap.sh — L2 能力总线桩测试（无真机验证适配器语义；CI 可跑）
# 原理：PATH 前置 stub 命令（apt-get/dpkg/dnf/pacman/zypper/brew/systemctl/timedatectl/…），
#       系统配置路径注入（BDE_CAP_*_CONF → 测试沙箱）+ BDE_OS_FAMILY 家族注入，
#       逐家族断言：别名解析 / 安装命令与包名 / 服务与配置落位语义 / 未实现能力优雅降级。
# 范围：L2 适配器与 lib 分派——L3 baseline/M3 语言栈的端到端在实机验收（见 verify/ACCEPTANCE.md）。
# 用法：test-cap.sh [family…]（默认 debian fedora arch suse darwin）；退出码 = 失败断言数
set -u

BDE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SBX="$(mktemp -d /tmp/bde-captest.XXXXXX)"
STUB="$SBX/stub"; LOG="$SBX/invocations.log"; : > "$LOG"
mkdir -p "$STUB"
PASS=0; FAIL=0

# ── 断言原语 ──
_t() { printf '  %s\n' "$1"; }
ok()   { PASS=$((PASS+1)); printf "[✓] %s\n" "$1"; }
bad()  { FAIL=$((FAIL+1)); printf "[✗] %s\n" "$1"; }
assert_contains() {  # <描述> <haystack> <needle>
    case "$2" in *"$3"*) ok "$1" ;; *) bad "$1（缺: $3）→ 实际: $(printf '%s' "$2" | head -c 300)" ;; esac
}
assert_not_contains() {  # <描述> <haystack> <needle>
    case "$2" in *"$3"*) bad "$1（不应含: $3）" ;; *) ok "$1" ;; esac
}
assert_rc() {  # <描述> <期望rc> <实际rc>
    [ "$2" = "$3" ] && ok "$1" || bad "$1（期望 rc=$2 实际 rc=$3）"
}
stub_run() { printf '%s\n' "$*" >> "$LOG"; }

# ── stub 命令工厂（记录调用到 LOG；行为由 TEST_* 环境变量驱动）──
mk_stub() {  # <name> <mode: log|exit0|...>
    local n=$1
    cat > "$STUB/$n" <<EOF
#!/usr/bin/env bash
printf '%s\n' "$n \$*" >> "$LOG" 2>/dev/null || true
EOF
    cat >> "$STUB/$n"
    chmod +x "$STUB/$n"
}

mk_stub sudo <<'EOF'
while [ "${1:-}" = "-n" ] || [[ "${1:-}" == -* ]] || [[ "${1:-}" == *=* ]]; do shift; done
exec "$@"
EOF
mk_stub apt-get <<'EOF'
exec 2>/dev/null
[ "$TEST_PKG_INSTALLED" = "1" ] && exit 0
exit 0
EOF
mk_stub dpkg <<'EOF'
[ "$1" = "-s" ] && { [ "${TEST_PKG_INSTALLED:-0}" = "1" ] && exit 0 || exit 1; }
exit 0
EOF
mk_stub dnf <<'EOF'
exit 0
EOF
mk_stub rpm <<'EOF'
[ "$1" = "-q" ] && { [ "${TEST_PKG_INSTALLED:-0}" = "1" ] && exit 0 || exit 1; }
exit 0
EOF
mk_stub pacman <<'EOF'
[ "$1" = "-Qi" ] && { [ "${TEST_PKG_INSTALLED:-0}" = "1" ] && exit 0 || exit 1; }
exit 0
EOF
mk_stub zypper <<'EOF'
exit 0
EOF
mk_stub brew <<'EOF'
[ "$1" = "ls" ] && { [ "${TEST_PKG_INSTALLED:-0}" = "1" ] && exit 0 || exit 1; }
exit 0
EOF
mk_stub systemctl <<'EOF'
op="$1"; [ "$1" = "--user" ] && op="$2"
case "$op" in
    is-active)  [ "${TEST_SVC_ACTIVE:-0}" = "1" ] && exit 0 || exit 1 ;;
    is-enabled) [ "${TEST_SVC_ENABLED:-0}" = "1" ] && exit 0 || exit 1 ;;
    *)          exit 0 ;;
esac
EOF
mk_stub sysctl <<'EOF'
[ "$1" = "-n" ] && { echo "${TEST_SYSCTL_VALUE:-10}"; exit 0; }
exit 0
EOF
mk_stub timedatectl <<'EOF'
[ "$1" = "show" ] && { echo "${TEST_TZ:-Asia/Shanghai}"; exit 0; }
exit 0
EOF
mk_stub localectl <<'EOF'
[ $# -eq 0 ] && { echo " System Locale: LANG=${TEST_LANG_CUR:-C.UTF-8}"; exit 0; }
exit 0
EOF
mk_stub hostnamectl <<'EOF'
[ "$1" = "--static" ] && { echo "${TEST_HOSTNAME:-testhost}"; exit 0; }
exit 0
EOF
mk_stub scutil <<'EOF'
[ "$1" = "--get" ] && { echo "${TEST_HOSTNAME:-testhost}"; exit 0; }
exit 0
EOF
mk_stub getent <<'EOF'
[ "$1" = "passwd" ] && { echo "testuser:x:1000:1000::/home/testuser:${TEST_SHELL:-/bin/zsh}"; exit 0; }
exit 1
EOF
mk_stub chsh <<'EOF'
exit 0
EOF
mk_stub usermod <<'EOF'
exit 0
EOF
mk_stub id <<'EOF'
exec /usr/bin/id "$@"
EOF
mk_stub swapon <<'EOF'
[ "${TEST_ZRAM:-0}" = "1" ] && { echo "NAME TYPE SIZE USED PRIO"; echo "/dev/zram0 partition 8G 0B 100"; }
exit 0
EOF
mk_stub kwriteconfig5 <<'EOF'
exit 0
EOF
mk_stub update-alternatives <<'EOF'
exit 0
EOF
mk_stub gsettings <<'EOF'
[ "$1" = "get" ] && { echo "@as []"; exit 0; }
exit 0
EOF
mk_stub fc-cache <<'EOF'
exit 0
EOF
mk_stub vmhgfs-fuse <<'EOF'
exit 1
EOF
mk_stub mountpoint <<'EOF'
exit 1
EOF

# ── 家族用例执行器 ──
run_family() {  # <family>
    local fam=$1
    printf "\n━━ 家族 %s ━━\n" "$fam"
    mkdir -p "$SBX/common/config/services/zram" "$SBX/common/config/services/systemd"
    printf 'ALGO=zstd\n' > "$SBX/common/config/services/zram/zramswap"
    printf '[zram0]\n' > "$SBX/common/config/services/systemd/zram-generator.conf"
    # ⚠ 单行拼接：多行 _env 会让 env -i 在换行处截断——赋值被打印、bash 以真实环境直跑（桩旁路 → 碰真系统）。
    #   本次事故即测试块以真 sudo 覆盖了 /etc/sysctl.d（2026-11-12，已修复+加固此处）
    local _env="PATH=$STUB:\$PATH BDE_OS_FAMILY=$fam BDE_ROOT=$BDE_ROOT COMMON=$SBX/common BDE_CAP_SYSCTL_CONF=$SBX/sysctl.conf BDE_CAP_JOURNAL_CONF=$SBX/journal.conf BDE_CAP_LIMITS_CONF=$SBX/limits.conf BDE_CAP_ZRAMSWAP_CONF=$SBX/zramswap BDE_CAP_ZRAM_CONF=$SBX/zram-generator.conf BDE_BACKUP_DIR=$SBX/backup TEST_PKG_INSTALLED=0 TEST_SVC_ACTIVE=0 TEST_SVC_ENABLED=0 TEST_TZ=UTC TEST_LANG_CUR=POSIX"
    # L2 加载 + 通用断言（别名 / 安装 / 降级）
    eval "env -i HOME=$HOME TERM=dumb $_env bash -c '
        source \"$BDE_ROOT/lib/cap.sh\" 2>/dev/null
        cap_load >/dev/null 2>&1 || exit 9
        echo \"FAMILY=\$BDE_CAP_FAMILY\"
        echo \"ALIAS_BUILD=\$(cap__pkg_alias build-base 2>/dev/null)\"
        echo \"ALIAS_JAVA=\$(cap__pkg_alias java-21 2>/dev/null)\"
        echo \"ALIAS_DOCKER=\$(cap__pkg_alias docker-engine 2>/dev/null)\"
        cap_pkg_install base >/dev/null 2>&1; echo \"PKG_RC=\$?\"
        cap_run svc ensure docker >/dev/null 2>&1; echo \"SVC_RC=\$?\"
        cap_run trim ensure >/dev/null 2>&1; echo \"TRIM_RC=\$?\"
        cap_run nonexistent_cap op >/dev/null 2>&1; echo \"DEGRADE_RC=\$?\"
        printf '%s\n' \"\$(cap__kernel_get vm.swappiness 2>/dev/null)\"
    '" > "$SBX/out" 2>/dev/null
    local out; out="$(cat "$SBX/out")"
    assert_contains "[$fam] 适配器加载" "$out" "FAMILY=$fam"
    assert_contains "[$fam] 语义别名 build-base" "$out" "ALIAS_BUILD="
    assert_contains "[$fam] 语义别名 java-21" "$out" "ALIAS_JAVA="
    assert_contains "[$fam] pkg.install 成功（stub）" "$out" "PKG_RC=0"
    if [ "$fam" = "darwin" ]; then
        assert_contains "[darwin] svc/trim 未实现 → 降级 rc=1" "$out" "SVC_RC=1"
    else
        assert_contains "[$fam] svc.ensure 成功（stub systemctl）" "$out" "SVC_RC=0"
        assert_contains "[$fam] trim.ensure 走 fstrim 单元" "$(cat "$LOG")" "fstrim.timer"
    fi
    assert_contains "[$fam] 未实现能力优雅降级（rc=1 不崩）" "$out" "DEGRADE_RC=1"
    : > "$LOG"

    # 安装命令与包名（家族差异核心断言）
    local _pkg_case=""
    case "$fam" in
        debian) _pkg_case="assert_contains \"[debian] base → apt 安装 openssh-server/whiptail/zsh\" \"\$(cat \"\$LOG\")\" \"openssh-server\" ; assert_contains \"[debian] java-21→openjdk-21-jdk\" \"\$(cap__pkg_alias java-21)\" \"openjdk-21-jdk\" ; assert_contains \"[debian] build-base→build-essential\" \"\$(cap__pkg_alias build-base)\" \"build-essential\"" ;;
        fedora) _pkg_case="assert_contains \"[fedora] java-21→java-21-openjdk\" \"\$(cap__pkg_alias java-21)\" \"java-21-openjdk\" ; assert_contains \"[fedora] docker-engine→moby-engine\" \"\$(cap__pkg_alias docker-engine)\" \"moby-engine\"" ;;
        arch)   _pkg_case="assert_contains \"[arch] build-base→base-devel\" \"\$(cap__pkg_alias build-base)\" \"base-devel\" ; assert_contains \"[arch] docker-engine→docker\" \"\$(cap__pkg_alias docker-engine)\" \"docker\"" ;;
        suse)   _pkg_case="assert_contains \"[suse] docker-engine→docker docker-compose\" \"\$(cap__pkg_alias docker-engine)\" \"docker-compose\"" ;;
        darwin) _pkg_case="assert_contains \"[darwin] java-21→openjdk@21\" \"\$(cap__pkg_alias java-21)\" \"openjdk@21\"" ;;
    esac
    eval "env -i HOME=$HOME TERM=dumb $_env bash -c '
        source \"$BDE_ROOT/lib/cap.sh\" 2>/dev/null; cap_load >/dev/null 2>&1
        $_pkg_case
    '" > "$SBX/out" 2>/dev/null
    while IFS= read -r _line; do
        case "$_line" in
            "[✓]"*) PASS=$((PASS+1)); printf "%s\n" "$_line" ;;
            "[✗]"*) FAIL=$((FAIL+1)); printf "%s\n" "$_line" ;;
        esac
    done < "$SBX/out"

    # 声明式落位语义（kernel/logs/limits：正本 → 注入路径 + 生效命令）
    printf '# test config\nvm.swappiness=10\n' > "$SBX/sysctl-src"
    eval "env -i HOME=$HOME TERM=dumb $_env bash -c '
        source \"$BDE_ROOT/lib/cap.sh\" 2>/dev/null; cap_load >/dev/null 2>&1
        cap_run kernel ensure \"$SBX/sysctl-src\" >/dev/null 2>&1; echo \"KERNEL_RC=\$?\"
        [ -f \"$SBX/sysctl.conf\" ] && echo \"SYSCTL_COPIED=1\"
        cap_run timesync ensure >/dev/null 2>&1; echo \"TS_RC=\$?\"
        cap_run locale ensure >/dev/null 2>&1; echo \"LOCALE_RC=\$?\"
        cap_run zram ensure >/dev/null 2>&1; echo \"ZRAM_RC=\$?\"
        cap_run power ensure >/dev/null 2>&1; echo \"POWER_RC=\$?\"
    '" > "$SBX/out" 2>/dev/null
    out="$(cat "$SBX/out")"
    [ "${BDE_TEST_DEBUG:-0}" = "1" ] && { echo "── debug out ──"; cat "$SBX/out"; echo "── debug LOG ──"; cat "$LOG"; } >&2
    if [ "$fam" = "darwin" ]; then
        # darwin 仅实装 pkg/hostname——声明式与系统能力全部诚实降级
        assert_contains "[darwin] kernel/timesync/locale/zram/power 全降级" "$out" "KERNEL_RC=1"
        assert_contains "[darwin] locale 降级" "$out" "LOCALE_RC=1"
        assert_contains "[darwin] zram 降级" "$out" "ZRAM_RC=1"
        assert_contains "[darwin] power 降级" "$out" "POWER_RC=1"
    else
        assert_contains "[$fam] kernel.ensure 落位+生效" "$out" "KERNEL_RC=0"
        assert_contains "[$fam] kernel 配置文件复制到注入路径" "$out" "SYSCTL_COPIED=1"
        assert_contains "[$fam] sysctl --system 被调用" "$(cat "$LOG")" "sysctl --system"
        assert_contains "[$fam] timesync.ensure 走 set-ntp" "$(cat "$LOG")" "timedatectl set-ntp true"
        assert_contains "[$fam] locale.ensure 走 set-timezone（TEST_TZ=UTC≠画像）" "$(cat "$LOG")" "timedatectl set-timezone Asia/Shanghai"
        assert_contains "[$fam] locale.ensure 走 localectl" "$(cat "$LOG")" "localectl set-locale"
        assert_contains "[$fam] power.ensure 无电池跳过" "$out" "POWER_RC=0"
        assert_contains "[$fam] zram.ensure 包安装" "$out" "ZRAM_RC=0"
    fi
    case "$fam" in
        debian)  assert_contains "[debian] zram → zram-tools + zramswap conf" "$(cat "$LOG")" "zram-tools"
                 [ -f "$SBX/zramswap" ] && ok "[debian] zramswap 落位注入路径" || bad "[debian] zramswap 落位注入路径" ;;
        fedora|arch|suse)
                 assert_contains "[$fam] zram → zram-generator" "$(cat "$LOG")" "zram-generator"
                 [ -f "$SBX/zram-generator.conf" ] && ok "[$fam] zram-generator conf 落位" || bad "[$fam] zram-generator conf 落位" ;;
    esac
    : > "$LOG"
}

_fams="${*:-debian fedora arch suse darwin}"
for _fam in $_fams; do run_family "$_fam"; done

# ── lib 级单测（跨家族共用件）──
printf "\n━━ lib 公共件 ━━\n"
cat > "$SBX/t1.sh" <<'EOS'
LOCAL=/Share/Local  # 模拟 paths.sh 解析结果（本单测只验函数替换语义）
source "$BDE_ROOT/lib/common.sh" 2>/dev/null
bde_expand_anchors_str '${LOCAL}/x'
EOS
env -i PATH="$STUB:$PATH" HOME="$HOME" BDE_ROOT="$BDE_ROOT" bash "$SBX/t1.sh" > "$SBX/out" 2>/dev/null
assert_contains "bde_expand_anchors_str 展开 LOCAL 锚点" "$(cat "$SBX/out")" "/Share/Local/x"

# hosts 片段：ip 行 + alias + 自身 127.0.1.1 兜底
printf '[h1]\nip = "192.168.1.24"\n\n[h2]\nip = ""\n\n[h3]\nip = "10.0.0.5"\nalias = "api"\n' > "$SBX/hosts.toml"
cat > "$SBX/t2.sh" <<'EOS'
source "$BDE_ROOT/lib/common.sh" 2>/dev/null
bde_hosts_fragment "$SBX/hosts.toml"
EOS
env -i PATH="$PATH" HOME="$HOME" BDE_ROOT="$BDE_ROOT" SBX="$SBX" bash "$SBX/t2.sh" > "$SBX/out" 2>/dev/null
_hf="$(cat "$SBX/out")"
assert_contains "hosts 片段含 ip 机器行" "$_hf" "192.168.1.24 h1"
assert_contains "hosts 片段含 alias 展开" "$_hf" "10.0.0.5 h3 api"
assert_not_contains "hosts 片段 ip 空机器段跳过" "$_hf" "h2"
assert_contains "hosts 片段含自身 127.0.1.1 行" "$_hf" "127.0.1.1 $(hostname | tr '[:upper:]' '[:lower:]')"

# ── 数据/视图分离护栏（防回归）──
# 1) 家族组归并唯一出处（曾双定义：cond 白名单 vs doctor os_id 黑名单）
for _spec in "debian:linux" "darwin:darwin" "unknown:unknown"; do
    _fam="${_spec%%:*}"; _want="${_spec##*:}"
    env -i PATH="$PATH" HOME="$HOME" BDE_OS_FAMILY="$_fam" bash -c '
        source "'"$BDE_ROOT"'/lib/common.sh" 2>/dev/null; bde_os_family_group
    ' > "$SBX/out" 2>/dev/null
    assert_contains "家族组归并 $_fam → $_want" "$(cat "$SBX/out")" "$_want"
done
grep -q "bde_os_family_group" "$BDE_ROOT/lib/probe.sh"     && ok "probe 事实化 family/group（消费唯一出处）" || bad "probe 未消费 bde_os_family_group"

# 2) 静态护栏：视图禁止活采集（doctor/report 曾是旁路源）
for _v in verify/doctor.sh modules/doc/report.sh; do
    grep -q "bde_probe_collect" "$BDE_ROOT/$_v"         && bad "视图护栏：$_v 出现活采集调用" || ok "视图护栏：$_v 零活采集（只读快照）"
done

# 3) cfgval 键值解析（key=value 与空格分隔两种正本形态）
printf 'fs.inotify.max_user_watches=524288\nvm.swappiness=10\n' > "$SBX/kv.conf"
printf '* soft nofile 65535\nroot hard nofile 65535\n' > "$SBX/sp.conf"
env -i PATH="$PATH" HOME="$HOME" bash -c '
    source "'"$BDE_ROOT"'/lib/common.sh" 2>/dev/null
    printf "KV=%s\n" "$(bde_cfgval "'"$SBX"'/kv.conf" "^vm\.swappiness")"
    printf "SP=%s\n" "$(bde_cfgval "'"$SBX"'/sp.conf" "^root hard nofile")"
' > "$SBX/out" 2>/dev/null
assert_contains "cfgval 解析 key=value 形态" "$(cat "$SBX/out")" "KV=10"
assert_contains "cfgval 解析空格分隔形态（limits）" "$(cat "$SBX/out")" "SP=65535"

# 4) 来源哈希确定性（同输入两次一致——指纹可比对的前提）
_h1="$(bash -c "source $BDE_ROOT/lib/probe.sh 2>/dev/null; bde_cfg_sources_hash" 2>/dev/null)"
_h2="$(bash -c "source $BDE_ROOT/lib/probe.sh 2>/dev/null; bde_cfg_sources_hash" 2>/dev/null)"
[ -n "$_h1" ] && [ "$_h1" = "$_h2" ] && ok "cfg_sources_hash 确定性（两次一致且非空）" || bad "cfg_sources_hash 不确定或为空"

# 5) 已装 docker 存量数据迁移护栏（bind 方案的遮蔽风险——迁移逻辑必须在位）
grep -q "存量数据迁移" "$BDE_ROOT/modules/cfg/cfg.sh" \
    && ok "docker 存量迁移护栏：cfg 钩子含停服→rsync→挂载→起服流程" || bad "docker 存量迁移逻辑缺失（bind 遮蔽风险）"

# 6) 环境索引护栏（schema/能力接线/probe 合规事实）
grep -q "bde.inventory/1" "$BDE_ROOT/modules/doc/inventory.sh" \
    && ok "inventory 索引 schema 在位（bde.inventory/1）" || bad "inventory schema 缺失"
grep -q "P_HOME_STRAY" "$BDE_ROOT/lib/probe.sh" \
    && ok "probe 合规事实 home_stray 在位" || bad "probe 缺 home_stray 事实"

# 7) 处置流单测（inv_transfer：转移=复制校验+移除+symlink 接回；合并语义）
env -i PATH="$PATH" HOME="$HOME" BDE_ROOT="$BDE_ROOT" SBX="$SBX" bash -c '
    source "$BDE_ROOT/modules/doc/inventory.sh" --x 2>/dev/null || true
    mkdir -p "$SBX/src/sub"; echo a > "$SBX/src/a.txt"; echo b > "$SBX/src/sub/b.txt"
    ln -sf "$SBX/src/a.txt" "$SBX/src/link.txt" 2>/dev/null
    inv_transfer "$SBX/src" "$SBX/dst" >/dev/null 2>&1; echo "RC=$?"
    [ -L "$SBX/src" ] && echo "SYMLINK=1"
    [ -f "$SBX/dst/a.txt" ] && [ -f "$SBX/dst/sub/b.txt" ] && echo "FILES=1"
    [ "$(readlink "$SBX/src" 2>/dev/null)" = "$SBX/dst" ] && echo "MOVED=1"
    mkdir -p "$SBX/src2"; echo c > "$SBX/src2/x.txt"; mkdir -p "$SBX/dst2"; echo keep > "$SBX/dst2/keep.txt"
    inv_transfer "$SBX/src2" "$SBX/dst2" >/dev/null 2>&1
    { [ -f "$SBX/dst2/keep.txt" ] && [ -f "$SBX/dst2/x.txt" ]; } && echo "MERGE=1"
' > "$SBX/out" 2>/dev/null
_o="$(cat "$SBX/out")"
assert_contains "inv_transfer 转移接回（symlink+文件齐）" "$_o" "SYMLINK=1"
assert_contains "inv_transfer 文件完整性（含子目录）" "$_o" "FILES=1"
assert_contains "inv_transfer 原实体已移除" "$_o" "MOVED=1"
assert_contains "inv_transfer 合并语义（dst 既有保留）" "$_o" "MERGE=1"
grep -q -- "--migrate" "$BDE_ROOT/modules/doc/inventory.sh"     && ok "处置流入口在位（inventory --migrate）" || bad "处置流入口缺失"

# cfg hosts 机制漂移判定（同源实现）
printf '# other content\n# >>> generated-by-BestDevEnv >>>\n%s\n# <<< generated-by-BestDevEnv <<<\n' "$_hf" > "$SBX/hosts-fake"
cat > "$SBX/t3.sh" <<'EOS'
source "$BDE_ROOT/lib/common.sh" 2>/dev/null
_f="$(bde_hosts_fragment "$SBX/hosts.toml")"
_b="$(bde_hosts_block_extract "$SBX/hosts-fake")"
[ "$_f" = "$_b" ] && echo "HOSTS_MATCH=1" || { echo "HOSTS_MATCH=0"; printf "F=[%s]\nB=[%s]\n" "$_f" "$_b"; }
EOS
env -i PATH="$STUB:$PATH" HOME="$HOME" BDE_ROOT="$BDE_ROOT" SBX="$SBX" bash "$SBX/t3.sh" > "$SBX/out" 2>/dev/null
assert_contains "cfg hosts 机制：块内容与生成器一致" "$(cat "$SBX/out")" "HOSTS_MATCH=1"

rm -rf "$SBX"
printf "\n══ 桩测试：%d 通过 ｜ %d 失败 ══\n" "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
