#!/usr/bin/env bash
# code-close <repo> —— 释放占用标记（未提交变更会提醒）
[ -n "${BDE_ROOT:-}" ] || BDE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$BDE_ROOT/lib/paths.sh"
source "$BDE_ROOT/lib/common.sh"

REPO="${1:?用法: code-close <repo>}"
DIR="$COMMON/code/$REPO"
MACHINE="${BDE_MACHINE:-$(hostname)}"
CLAIM="$DIR/.claimed-by"

# bind 拆除（与 code-open 恢复对偶）：占用释放后残留挂载 = dirs 域 mount-fixups 的"死挂载"
# 来源，且他机占用期间本机挂载会指向过期实体（2026-11-12 实测：close 后 node_modules 仍是
# mountpoint）。依赖实体按设计留 ① deps——只拆挂载，不删实体；symlink 策略无需拆除。
# 拆挂是本机局部清理，置于占用判定之前：无占用记录的孤儿 bind（nm 后未 open/换机后残留）同样回收。
LIST="${BDE_BINDMOUNTS:-$DEV/docs/bindmounts.list}"
ROOT="$(bde_root)"
if [ -f "$LIST" ] && bde_require_linux; then
    while IFS='|' read -r r sub real; do
        [ "$r" = "$REPO" ] || continue
        mp="$DIR/$sub"
        mountpoint -q "$mp" 2>/dev/null || continue
        if [ -n "$ROOT" ] && $ROOT umount "$mp" 2>/dev/null; then
            bde_ok "bind 拆除: $REPO/$sub（实体留 ${real/#$HOME/\~}）"
        else
            bde_pending "bind 拆除失败: $REPO/$sub（文件被占用或需 sudo；sudo umount $mp）"
        fi
    done < "$LIST"
fi

if [ -f "$CLAIM" ] && grep -q "^${MACHINE}|" "$CLAIM"; then
    if [ -d "$DIR/.git" ] && [ -n "$(git -C "$DIR" status --porcelain 2>/dev/null)" ]; then
        bde_pending "$REPO 有未提交变更——记得 push（工作副本不是备份）"
    fi
    # grep -v 全过滤（单机自释放，最常见场景）时 rc=1——不能作为 mv 的前置条件（2026-11-08 实测修复）
    grep -v "^${MACHINE}|" "$CLAIM" > "$CLAIM.tmp" 2>/dev/null || true
    mv "$CLAIM.tmp" "$CLAIM"
    [ -s "$CLAIM" ] || rm -f "$CLAIM"
    bde_ok "释放占用 → $REPO"
else
    bde_skip "$REPO 未被本机占用"
fi
