#!/usr/bin/env bash
# modules/cfg/cfg.sh — 统一配置治理器（M1.6；宪法 §19.3 服务三分离 + 单一事实源）
# 契约：安装任何服务/软件/工具，其配置文件三问皆有统一答案——
#   正本在哪  → modules/cfg/cfg-map.tsv 登记（内容住 $COMMON/config/{services,apt}/ 版本化）
#   怎么应用  → 机制列：copy（备份+落位）/ append（逐行追加）/ chezmoi（事实源 apply，本模块只查漂移）
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
用法: cfg.sh list|apply [name]|diff|adopt <name> <target> [类=system] [root=y|n]   （--svc 前缀=只看 service 类）
  list              配置清单视图（项|类|正本|应用层|机制|漂移）
  apply [name]      正本 → 应用层（幂等；root 项走 sudo -n）
  diff              全量漂移检测（非零退出 = 有漂移）
  adopt             收编：应用层现有文件 → $COMMON/config/services/<name>/ 正本并登记
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

_cfg_diff_one() {  # $1=name $2=类 $3=正本 $4=应用层 $5=机制 → echo 漂移描述（空=一致）
    local name="$1" cls="$2" src="${3/#\$COMMON/$COMMON}" dst="$4" mech="$5"
    dst="${dst/#\$HOME/$HOME}"
    [ -f "$src" ] || { echo "$name:正本缺失"; return; }
    case "$mech" in
        append)
            while IFS= read -r _l; do
                [ -n "$_l" ] || continue
                grep -qF -- "$_l" "$dst" 2>/dev/null || { echo "$name:缺行[$_l]"; return; }
            done < "$src" ;;
        *)
            [ -f "$dst" ] || { echo "$name:应用层缺失"; return; }
            cmp -s "$src" "$dst" || echo "$name:内容漂移" ;;
    esac
}

# ── apply：正本 → 应用层（幂等）──────────────────────────────────────────
_cfg_apply_one() {
    local name="$1" cls="$2" src="${3/#\$COMMON/$COMMON}" dst="$4" mech="$5" root="$6"
    dst="${dst/#\$HOME/$HOME}"
    [ -f "$src" ] || { bde_pending "$name 正本缺失（先收编或手工放置）：$src"; return 0; }
    case "$mech" in
        copy)
            ensure_dir "$(dirname "$dst")"
            if cmp -s "$src" "$dst" 2>/dev/null; then
                bde_skip "$name 已一致（${dst/#$HOME/~}）"
            else
                ensure_backup "$dst"
                if [ "$root" = "y" ]; then
                    sudo -n cp "$src" "$dst" && bde_ok "$name 落位 ${dst/#$HOME/~}（root）" \
                        || bde_fail "$name 落位失败（需 sudo 免密）"
                else
                    cp "$src" "$dst" && bde_ok "$name 落位 ${dst/#$HOME/~}"
                fi
            fi ;;
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
                || bde_ok "$name 追加 $_miss 行 → ${dst/#$HOME/~}" ;;
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
    local line="${name}|${cls}|\$COMMON/config/services/${name}/$(basename "$target")|${target/#$HOME/\$HOME}|copy|${root}|adopt 收编"
    if grep -qF -- "${name}|" "$CFG_MAP" 2>/dev/null; then
        bde_pending "登记表已有 $name 行（不重复登记）"
    else
        ensure_line "$CFG_MAP" "$line" && bde_ok "登记 $name → cfg-map.tsv"
    fi
}

# ── 视图 ─────────────────────────────────────────────────────────────────
_cfg_list() {
    bde_info "配置治理清单（正本根：$CFG_SRC_SERVICES ｜ $CFG_SRC_APT）"
    printf "  %-16s %-8s %-46s %-38s %-8s %s\n" "NAME" "类" "正本" "应用层" "机制" "漂移"
    mapfile -t _rows < <(_cfg_rows)
    local _r name cls src dst mech root note d
    for _r in "${_rows[@]}"; do
        IFS='|' read -r name cls src dst mech root note <<<"$_r"
        d="$(_cfg_diff_one "$name" "$cls" "$src" "$dst" "$mech")"
        printf "  %-16s %-8s %-46s %-38s %-8s %s\n" "$name" "$cls" \
            "${src/#\$COMMON//\$C}" "${dst/#\$HOME/\~}" "$mech" "${d:-一致}"
    done
    bde_info "动作：devenv cfg apply（幂等落位）｜devenv cfg diff（漂移检测）｜doctor 巡检"
}

_cfg_diff_all() {
    mapfile -t _rows < <(_cfg_rows)
    local _r name cls src dst mech root note d _n=0
    for _r in "${_rows[@]}"; do
        IFS='|' read -r name cls src dst mech root note <<<"$_r"
        d="$(_cfg_diff_one "$name" "$cls" "$src" "$dst" "$mech")"
        [ -n "$d" ] && { bde_fail "漂移：$d"; _n=$((_n+1)); }
    done
    if [ "$_n" -eq 0 ]; then
        bde_ok "配置无漂移（${#_rows[@]} 项登记全一致）"
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
                   [ -n "$_row" ] && { IFS='|' read -r name cls src dst mech root note <<<"$_row"; _cfg_apply_one "$name" "$cls" "$src" "$dst" "$mech" "$root"; } \
                       || { bde_fail "cfg-map 无此项：$1"; exit 2; }
               else
                   mapfile -t _rows < <(_cfg_rows)
                   for _r in "${_rows[@]}"; do
                       IFS='|' read -r name cls src dst mech root note <<<"$_r"
                       _cfg_apply_one "$name" "$cls" "$src" "$dst" "$mech" "$root"
                   done
               fi ;;
        diff)  shift 2>/dev/null; _cfg_diff_all ;;
        adopt) shift; _cfg_adopt "$@" ;;
        *)     _cfg_usage; exit 2 ;;
    esac
else
    # init M1.6:cfg sourced：全量落位（正本为准；缺失正本只提示不失败）
    bde_info "M1.6 配置治理（正本 → 应用层；漂移由 devenv cfg diff / doctor 巡检）"
    mapfile -t _rows < <(_cfg_rows)
    local_rc=0
    for _r in "${_rows[@]}"; do
        IFS='|' read -r name cls src dst mech root note <<<"$_r"
        _cfg_apply_one "$name" "$cls" "$src" "$dst" "$mech" "$root"
    done
fi
