#!/usr/bin/env bash
# home-map —— 隐藏目录治理视图（数据=home-map.tsv，视图=本脚本）
# 用法: devenv map [--sizes]
#   - 默认：注册表清单 + 未登记项检测（快）
#   - --sizes：附加每项目前体量与最近使用（较慢，全量扫描）
[ -n "${BDE_ROOT:-}" ] || BDE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$BDE_ROOT/lib/paths.sh"
source "$BDE_ROOT/lib/common.sh"

MAP="${BDE_HOME_MAP:-$COMMON/config/data/home-map.tsv}"
[ -f "$MAP" ] || { bde_fail "注册表缺失：$MAP"; exit 1; }

# 1) 注册表视图
printf "%-20s %-22s %-10s %-12s %s\n" "目录" "应用" "分类" "政策" "备注"
printf -- "---------------------------------------------------------------------------------------------\n"
while IFS='|' read -r d app cat pol note; do
    case "$d" in \#*|"") continue ;; esac
    printf "%-20s %-22s %-10s %-12s %s\n" "$d" "$app" "$cat" "$pol" "$note"
done < "$MAP"

# 2) 未登记项检测（看门人：新目录必须登记一行）
bde_info "未登记检测："
_unreg=0
shopt -s nullglob
for p in "$HOME"/.[!.]*; do
    _n="$(basename "$p")"
    grep -q "^${_n}|" "$MAP" 2>/dev/null || { _unreg=$((_unreg+1)); bde_pending "$_n —— 新目录未登记，请在 home-map.tsv 补一行"; }
done
shopt -u nullglob
[ "$_unreg" = "0" ] && bde_ok "全部已登记"

# 3) 失踪检测（登记了但目录没了 → 更新注册表）
while IFS='|' read -r d app cat pol note; do
    case "$d" in \#*|"") continue ;; esac
    [ -e "$HOME/$d" ] || bde_pending "$d 已不存在（应用可能卸载）——请更新/删除注册表行"
done < "$MAP"

# 4) --sizes：体量与最近使用（慢）
if [ "${1:-}" = "--sizes" ]; then
    echo
    printf "%-20s %-10s %-10s %s\n" "目录" "体量" "最近使用" "分类"
    while IFS='|' read -r d app cat pol note; do
        case "$d" in \#*|"") continue ;; esac
        p="$HOME/$d"
        [ -d "$p" ] || continue
        sz="$(du -sh "$p" 2>/dev/null | cut -f1)"
        # GNU find -printf 专属（mac/BSD 无此旗标）——--sizes 明细路径仅 Linux 支持
        lu="$(find "$p" -type f -printf '%TY-%Tm-%Td\n' 2>/dev/null | sort -r | head -1)"
        [ -z "$lu" ] && lu="-"
        printf "%-20s %-10s %-10s %s\n" "$d" "$sz" "$lu" "$cat"
    done < "$MAP"
fi
