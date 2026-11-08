#!/usr/bin/env bash
# code-open <repo> —— 占用共享盘仓库 + 恢复该仓库的全部 bind mounts（依赖实体/产物目录）
[ -n "${BDE_ROOT:-}" ] || BDE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$BDE_ROOT/lib/paths.sh"
source "$BDE_ROOT/lib/common.sh"

REPO="${1:?用法: code-open <repo>}"
DIR="$COMMON/code/$REPO"
[ -d "$DIR" ] || { bde_fail "仓库不存在: $DIR"; exit 1; }
LIST="${BDE_BINDMOUNTS:-$DEV/docs/bindmounts.list}"
MACHINE="${BDE_MACHINE:-$(hostname)}"
ROOT="$(bde_root)"

# 1) 占用标记（制度：一仓同时只开一台）
CLAIM="$DIR/.claimed-by"
if [ -f "$CLAIM" ] && ! grep -q "^${MACHINE}|" "$CLAIM"; then
    bde_fail "仓库被占用：$(cat "$CLAIM")（对方 code-close 后再开）"
    exit 1
fi
printf '%s|%s\n' "$MACHINE" "$(date '+%F %T')" > "$CLAIM" && bde_ok "占用标记 → $REPO"

# 2) 恢复该仓库登记的全部 bind mounts（node_modules / target / dist …）
if [ -f "$LIST" ]; then
    while IFS='|' read -r r sub real; do
        [ "$r" = "$REPO" ] || continue
        mp="$DIR/$sub"
        mkdir -p "$real" 2>/dev/null; mkdir -p "$mp" 2>/dev/null
        if mountpoint -q "$mp"; then
            bde_skip "bind 已在位: $REPO/$sub"
        elif [ -n "$ROOT" ] && $ROOT mount --bind "$real" "$mp" 2>/dev/null; then
            bde_ok "bind 恢复: $REPO/$sub → ${real/#$HOME/\~}"
        else
            bde_pending "bind 恢复失败: $REPO/$sub（需 sudo 免密）"
        fi
    done < "$LIST"
fi
bde_info "已打开 $REPO（结束请 code-close $REPO）"
