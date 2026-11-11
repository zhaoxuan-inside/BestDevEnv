#!/usr/bin/env bash
# modules/cfg/cfg.sh — 统一配置治理器（M1.6；宪法 §19.3 服务三分离 + 单一事实源）
# 契约：安装任何服务/软件/工具，其配置文件三问皆有统一答案——
#   正本在哪  → modules/cfg/cfg-map.tsv 登记（内容住 $COMMON/config/{services,apt}/ 版本化）
#   怎么应用  → 机制列：copy（备份+落位）/ copy-expand（锚点变量展开后落位）/ append（逐行追加）/
#               chezmoi（事实源 apply，本模块只查漂移；.tmpl 正本按本机数据渲染比对）
#   何处生效  → 条件列：os=<ids> / backend_common=<b> / backend_host=<b>（& 连接；空=无条件）——
#               非适用机器自动缺席，不误报漂移（OS/后端差异收敛在登记数据，不散落代码）
#   漂移怎么发现 → devenv cfg diff ＋ doctor「系统/服务配置无漂移」巡检
# 服务生命周期（enable/start）不在本模块——安装体动作归服务自身（配置与安装体分离）。
# 用法：source（init M1.6:cfg）→ 全量 apply；独立执行 → list|apply [name]|diff|adopt <name> <target> [类] [root]
[ -n "${BDE_CFG_LOADED:-}" ] && return 0 2>/dev/null || true
BDE_CFG_LOADED=1

[ -n "${BDE_ROOT:-}" ] || BDE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$BDE_ROOT/lib/paths.sh"
source "$BDE_ROOT/lib/common.sh"
source "$BDE_ROOT/lib/ensure.sh"

CFG_MAP="$BDE_ROOT/modules/cfg/cfg-map.tsv"
CFG_SRC_SERVICES="$COMMON/config/services"
CFG_SRC_APT="$COMMON/config/apt"

_cfg_usage() {
    cat <<'EOF'
用法: cfg.sh list|apply [name]|diff|adopt <name> <target> [类=system] [root=y|n]|snapshot   （--svc 前缀=只看 service 类）
  list              配置清单视图（项|类|正本|应用层|机制|漂移）
  apply [name]      正本 → 应用层（幂等；root 项走 sudo -n；copy-expand 按本机锚点展开；
                    落位后自动触发该文件类型的生效动作——sysctl --system / journald 重启）
  diff              全量漂移检测（非零退出 = 有漂移；条件不适用项自动缺席）
  adopt             收编：应用层现有文件 → $COMMON/config/services/<name>/ 正本并登记
  snapshot          备份：③ 正本 → 工程仓库 config/ seed 快照（rsync 镜像 + commit；工程 git push 即异地备份）
机制列: copy（整文件落位）/ copy-expand（锚点展开落位）/ append（逐行追加）/ chezmoi（chezmoi 事实源）/
        hosts（动态：hosts.toml 数据源 → /etc/hosts 标记块幂等替换，块外内容永不触碰）
EOF
}

# 登记表行（跳过注释/空行；--svc 过滤 service 类）
_cfg_rows() {
    local rows
    rows="$(grep -v '^[[:space:]#]' "$CFG_MAP" 2>/dev/null | grep -v '^[[:space:]]*$')"
    if [ "${CFG_FILTER:-}" = "svc" ]; then
        printf '%s\n' "$rows" | awk -F'|' '$2=="service"'
    else
        printf '%s\n' "$rows"
    fi
}

# 漂移比对用的"生效正本"：统一委托 lib/common.sh（probe 巡检与 cfg diff/apply 同一套判定）
_cfg_effective_src() { bde_cfg_effective_src "$1" "$2"; }

# 生效动作（声明落位后的 activate）：文件归 cfg 治理、行为归能力总线；
# 此处只登记"该文件类型的已知生效方式"——落位成功后自动触发，skip（已一致）不触发。
_cfg_post_apply() {  # <name>
    case "$1" in
        sysctl-devspace)
            sudo -n sysctl --system >/dev/null 2>&1 \
                && bde_ok "sysctl --system 生效" \
                || bde_pending "sysctl --system 失败（人工执行或重跑 M1 kernel.ensure）" ;;
        journald-devspace)
            sudo -n systemctl restart systemd-journald >/dev/null 2>&1 \
                && bde_ok "systemd-journald 重启生效" \
                || bde_pending "journald 重启失败（人工执行或下次重启生效）" ;;
    esac
}

_cfg_diff_one() {  # 逐行漂移判定（唯一实现在 lib/common.sh bde_cfg_diff_one——§19.5 同源）
    bde_cfg_diff_one "$@"
}

# ── apply：正本 → 应用层（幂等）──────────────────────────────────────────
_cfg_apply_one() {
    local name="$1" cls="$2" src="${3/#\$COMMON/$COMMON}" dst="$4" mech="$5" root="$6" cond="$7"
    dst="$(bde_expand_anchors_str "$dst")"
    if ! bde_cfg_cond_ok "$cond"; then
        bde_skip "$name 条件不适用（$cond；本机 os=$(bde_os_id) family=$(bde_os_family) ③=$BDE_SCOPE_SHARED_BACKEND ②=$BDE_SCOPE_HOST_BACKEND），跳过"
        return 0
    fi
    [ -f "$src" ] || { bde_pending "$name 正本缺失（先收编或手工放置）：$src"; return 0; }
    case "$mech" in
        hosts)   # 动态机制：hosts.toml → 生成片段 → /etc/hosts 标记块幂等替换（块外内容永不触碰）
            local _frag _tmp
            _frag="$(bde_hosts_fragment "$src")" || { bde_fail "$name hosts.toml 解析失败"; return 0; }
            if [ -z "$_frag" ]; then
                bde_skip "$name 无 ip 登记（片段为空，无事可做）"
                return 0
            fi
            _tmp="$(mktemp "${TMPDIR:-/tmp}/bde-hosts.XXXXXX")"
            if grep -q "# >>> $BDE_HOSTS_TAG" "$dst" 2>/dev/null; then
                awk -v b="$BDE_HOSTS_TAG" \
                    'index($0, "# >>> " b)==1 {inblk=1; next}
                     index($0, "# <<< " b)==1 {inblk=0; next}
                     !inblk {print}' "$dst" > "$_tmp"
            elif [ -f "$dst" ]; then
                cp "$dst" "$_tmp"
            else
                : > "$_tmp"
            fi
            { echo "# >>> $BDE_HOSTS_TAG >>>"; printf '%s\n' "$_frag"; echo "# <<< $BDE_HOSTS_TAG <<<"; } >> "$_tmp"
            if [ "$root" = "y" ]; then
                sudo -n cp "$_tmp" "$dst" \
                    && bde_ok "$name hosts 片段已同步（标记块幂等，块外内容不动）" \
                    || bde_fail "$name hosts 写入失败（需 sudo 免密）"
            else
                cp "$_tmp" "$dst" && bde_ok "$name hosts 片段已同步"
            fi
            rm -f "$_tmp" ;;
        copy|copy-expand)
            local _es _chg=0; _es="$(_cfg_effective_src "$src" "$mech")"
            if [ -z "$_es" ]; then bde_fail "$name 正本展开/渲染失败"; return 0; fi
            ensure_dir "$(dirname "$dst")"
            if cmp -s "$_es" "$dst" 2>/dev/null; then
                bde_skip "$name 已一致（${dst/#$HOME/~}）"
            else
                ensure_backup "$dst"
                if [ "$root" = "y" ]; then
                    sudo -n cp "$_es" "$dst" && { bde_ok "$name 落位 ${dst/#$HOME/~}（root${mech:+·$mech}）"; _chg=1; } \
                        || bde_fail "$name 落位失败（需 sudo 免密）"
                else
                    cp "$_es" "$dst" && { bde_ok "$name 落位 ${dst/#$HOME/~}"; _chg=1; }
                fi
            fi
            [ "$_chg" = "1" ] && _cfg_post_apply "$name"
            [[ "$_es" == "${TMPDIR:-/tmp}/bde-cfg-x."* ]] && rm -f "$_es" ;;
        append)
            local _miss=0 _l
            while IFS= read -r _l; do
                [ -n "$_l" ] || continue
                grep -qF -- "$_l" "$dst" 2>/dev/null && continue
                _miss=$((_miss+1))
                if [ "$root" = "y" ]; then
                    printf '%s\n' "$_l" | sudo -n tee -a "$dst" >/dev/null 2>&1 || bde_fail "$name 追加失败：$_l"
                else
                    printf '%s\n' "$_l" >> "$dst" || bde_fail "$name 追加失败：$_l"
                fi
            done < "$src"
            [ "$_miss" -eq 0 ] && bde_skip "$name 已一致（append ${dst/#$HOME/~}）" \
                || { bde_ok "$name 追加 $_miss 行 → ${dst/#$HOME/~}"; _cfg_post_apply "$name"; } ;;
        chezmoi)
            bde_skip "$name 归 chezmoi 事实源管（apply 走 chezmoi apply；本模块只查漂移）" ;;
        *)
            bde_pending "$name 机制未知：$mech" ;;
    esac
}

# ── adopt：应用层 → 正本（收编）──────────────────────────────────────────
_cfg_adopt() {
    local name="$1" target="$2" cls="${3:-system}" root="${4:-y}"
    [ -n "$name" ] && [ -n "$target" ] || { _cfg_usage; return 2; }
    target="${target/#\$HOME/$HOME}"
    [ -f "$target" ] || { bde_fail "收编目标不存在：$target"; return 1; }
    local srcdir="$CFG_SRC_SERVICES/$name"
    ensure_dir "$srcdir" || { bde_fail "正本目录不可建：$srcdir"; return 1; }
    local src="$srcdir/$(basename "$target")"
    if [ -f "$src" ]; then
        bde_pending "正本已存在（不覆盖）：$src——人工确认后合并"
    else
        if [ "$root" = "y" ]; then sudo -n cp "$target" "$src" || { bde_fail "收编失败（需 sudo）"; return 1; }
        else cp "$target" "$src" || { bde_fail "收编失败"; return 1; } fi
        bde_ok "收编正本 $src"
    fi
    local line="${name}|${cls}|\$COMMON/config/services/${name}/$(basename "$target")|${target/#$HOME/\$HOME}|copy|${root}||adopt 收编"
    if grep -qF -- "${name}|" "$CFG_MAP" 2>/dev/null; then
        bde_pending "登记表已有 $name 行（不重复登记）"
    else
        ensure_line "$CFG_MAP" "$line" && bde_ok "登记 $name → cfg-map.tsv"
    fi
}

# ── snapshot：③ 正本 → 工程仓库 seed 快照（备份通道；config 正本无独立远端时的异地备份实现）──
# 链路：③ config（正本，跨机同步靠共享盘）→ rsync 镜像到 $BDE_ROOT/config/（seed）→ 工程仓库 commit → push GitHub
# doctor「config 备份通道」项巡检：seed 在册且工程仓库有 remote。config 正本将来配独立远端后，本命令仍是快照留痕手段。
_cfg_snapshot() {
    [ -d "$COMMON/config" ] || { bde_fail "config 正本缺失：$COMMON/config"; return 1; }
    command -v rsync >/dev/null 2>&1 || { bde_fail "rsync 不可用（apt install rsync）"; return 1; }
    mkdir -p "$BDE_ROOT/config"
    # -rlt：保留链接/权限位忽略（HGFS 恒 777，不追 perm）+ 时间戳增量；--delete 保真镜像；.git 不进 seed
    # 密钥不入 seed：.env 类（技能自管 API key，如 arkcli byted-web-search）磁盘中留在 ③，仓库面除名（GitHub Push Protection 实证，2026-11-11）
    local _err; _err="$(mktemp)"
    if rsync -rlt --delete --exclude '.git/' --exclude '.env' "$COMMON/config/" "$BDE_ROOT/config/" 2>"$_err"; then
        [ -s "$_err" ] && bde_info "rsync 提示: $(head -2 "$_err")"
        bde_ok "seed 快照镜像 → $BDE_ROOT/config/（③ 正本，--delete 保真）"
    else
        bde_fail "seed 快照同步失败: $(head -2 "$_err")"; rm -f "$_err"; return 1
    fi
    rm -f "$_err"
    if [ -n "$(git -C "$BDE_ROOT" status --porcelain -- config 2>/dev/null | head -1)" ]; then
        git -C "$BDE_ROOT" add config \
            && git -C "$BDE_ROOT" commit -m "chore(config): seed 快照同步（devenv cfg snapshot；③ 正本 → 工程仓库，push 即异地备份）" --quiet \
            && bde_ok "seed 快照已 commit——记得 git push 完成异地备份"
    else
        bde_skip "seed 快照与 ③ 正本一致（无新变更）"
    fi
}

# ── 视图 ─────────────────────────────────────────────────────────────────
_cfg_list() {
    bde_info "配置治理清单（正本根：$CFG_SRC_SERVICES ｜ $CFG_SRC_APT）"
    printf "  %-16s %-8s %-46s %-38s %-11s %s\n" "NAME" "类" "正本" "应用层" "机制/条件" "漂移"
    mapfile -t _rows < <(_cfg_rows)
    local _r name cls src dst mech root cond note d
    for _r in "${_rows[@]}"; do
        IFS='|' read -r name cls src dst mech root cond note <<<"$_r"
        d="$(_cfg_diff_one "$name" "$cls" "$src" "$dst" "$mech" "$cond")"
        if ! bde_cfg_cond_ok "$cond"; then d="不适用($cond)"; fi
        printf "  %-16s %-8s %-46s %-38s %-11s %s\n" "$name" "$cls" \
            "${src/#\$COMMON//\$C}" "${dst/#\$HOME/\~}" "$mech${cond:+·$cond}" "${d:-一致}"
    done
    bde_info "动作：devenv cfg apply（幂等落位）｜devenv cfg diff（漂移检测）｜doctor 巡检"
}

_cfg_diff_all() {
    mapfile -t _rows < <(_cfg_rows)
    local _r name cls src dst mech root cond note d _n=0
    for _r in "${_rows[@]}"; do
        IFS='|' read -r name cls src dst mech root cond note <<<"$_r"
        d="$(_cfg_diff_one "$name" "$cls" "$src" "$dst" "$mech" "$cond")"
        [ -n "$d" ] && { bde_fail "漂移：$d"; _n=$((_n+1)); }
    done
    if [ "$_n" -eq 0 ]; then
        bde_ok "配置无漂移（${#_rows[@]} 项登记全一致；条件不适用项已缺席）"
    else
        bde_info "$_n 项漂移 → devenv cfg apply 还原（正本为准收编）"
    fi
    return "$_n"
}

# ── 入口 ─────────────────────────────────────────────────────────────────
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    if [ "${1:-}" = "--svc" ]; then CFG_FILTER=svc; shift; fi
    case "${1:-list}" in
        list)  shift 2>/dev/null; _cfg_list ;;
        apply) shift 2>/dev/null
               if [ -n "${1:-}" ]; then
                   _row="$(grep "^$1|" "$CFG_MAP" | head -1)"
                   [ -n "$_row" ] && { IFS='|' read -r name cls src dst mech root cond note <<<"$_row"; _cfg_apply_one "$name" "$cls" "$src" "$dst" "$mech" "$root" "$cond"; } \
                       || { bde_fail "cfg-map 无此项：$1"; exit 2; }
               else
                   mapfile -t _rows < <(_cfg_rows)
                   for _r in "${_rows[@]}"; do
                       IFS='|' read -r name cls src dst mech root cond note <<<"$_r"
                       _cfg_apply_one "$name" "$cls" "$src" "$dst" "$mech" "$root" "$cond"
                   done
               fi ;;
        diff)  shift 2>/dev/null; _cfg_diff_all ;;
        adopt) shift; _cfg_adopt "$@" ;;
        snapshot) shift 2>/dev/null; _cfg_snapshot ;;
        *)     _cfg_usage; exit 2 ;;
    esac
else
    # init M1.6:cfg sourced：全量落位（正本为准；缺失正本只提示不失败）
    bde_info "M1.6 配置治理（正本 → 应用层；漂移由 devenv cfg diff / doctor 巡检）"
    mapfile -t _rows < <(_cfg_rows)
    local_rc=0
    for _r in "${_rows[@]}"; do
        IFS='|' read -r name cls src dst mech root cond note <<<"$_r"
        _cfg_apply_one "$name" "$cls" "$src" "$dst" "$mech" "$root" "$cond"
    done
fi
