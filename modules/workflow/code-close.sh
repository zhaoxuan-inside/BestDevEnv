#!/usr/bin/env bash
# code-close <repo> —— 释放占用标记（未提交变更会提醒）
[ -n "${BDE_ROOT:-}" ] || BDE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$BDE_ROOT/lib/paths.sh"
source "$BDE_ROOT/lib/common.sh"

REPO="${1:?用法: code-close <repo>}"
DIR="$COMMON/code/$REPO"
MACHINE="${BDE_MACHINE:-$(hostname)}"
CLAIM="$DIR/.claimed-by"

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
