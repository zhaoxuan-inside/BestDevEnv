#!/usr/bin/env bash
# code-out <repo> [subdir] —— 构建产物目录外置：物理落 ② 本机专享盘，bind mount 接回项目
# 默认 subdir=target（Maven）；Gradle 用 build；前端用 dist。代码与产物物理分离（宪法原则）
[ -n "${BDE_ROOT:-}" ] || BDE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$BDE_ROOT/lib/paths.sh"
source "$BDE_ROOT/lib/common.sh"

REPO="${1:?用法: code-out <repo> [subdir=target|build|dist]}"
SUB="${2:-target}"
DIR="$COMMON/code/$REPO"
[ -d "$DIR" ] || { bde_fail "仓库不存在: $DIR"; exit 1; }

REAL="$LOCAL/build/$REPO/$SUB"
MP="$DIR/$SUB"
LIST="${BDE_BINDMOUNTS:-$DEV/docs/bindmounts.list}"
ROOT="$(bde_root)"

mkdir -p "$REAL" || { bde_fail "无法创建 $REAL"; exit 1; }
mkdir -p "$MP" 2>/dev/null

if mountpoint -q "$MP"; then
    bde_skip "bind 已在位: $REPO/$SUB"
elif [ -n "$ROOT" ] && $ROOT mount --bind "$REAL" "$MP" 2>/dev/null; then
    bde_ok "bind: $REPO/$SUB → $REAL"
else
    bde_fail "bind 失败（需 sudo 免密）"
    exit 1
fi

LINE="$REPO|$SUB|$REAL"
grep -qF -- "$LINE" "$LIST" 2>/dev/null || printf '%s\n' "$LINE" >> "$LIST"
bde_info "产物落点: $REAL ｜ 跨机成品 → /Share/Common/exchange/$REPO/"
