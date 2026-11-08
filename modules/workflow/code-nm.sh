#!/usr/bin/env bash
# code-nm <repo> —— JS 依赖实体外置：node_modules 物理落 VM 盘，bind mount 接回共享盘项目
# （HGFS 无 symlink → npm/pnpm 装不了依赖；实体在 ext4 才可装。忘挂时 npm 报 symlink 错=响亮失败）
[ -n "${BDE_ROOT:-}" ] || BDE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$BDE_ROOT/lib/paths.sh"
source "$BDE_ROOT/lib/common.sh"

REPO="${1:?用法: code-nm <repo>}"
DIR="$COMMON/code/$REPO"
[ -d "$DIR" ] || { bde_fail "仓库不存在: $DIR"; exit 1; }
[ -f "$DIR/package.json" ] || { bde_fail "$REPO 不是 JS/TS 项目（无 package.json）"; exit 1; }

REAL="$DEV/deps/$REPO/node_modules"
MP="$DIR/node_modules"
LIST="${BDE_BINDMOUNTS:-$DEV/docs/bindmounts.list}"
ROOT="$(bde_root)"

mkdir -p "$REAL" || { bde_fail "无法创建实体目录 $REAL"; exit 1; }
mkdir -p "$MP" 2>/dev/null

if mountpoint -q "$MP"; then
    bde_skip "bind 已在位: $REPO/node_modules"
elif [ -n "$ROOT" ] && $ROOT mount --bind "$REAL" "$MP" 2>/dev/null; then
    bde_ok "bind: $REPO/node_modules → $REAL"
else
    bde_fail "bind 失败（需 sudo 免密）——npm 会因 symlink 报错（响亮失败，符合设计）"
    exit 1
fi

LINE="$REPO|node_modules|$REAL"
grep -qF -- "$LINE" "$LIST" 2>/dev/null || printf '%s\n' "$LINE" >> "$LIST"
bde_info "依赖实体: $REAL ｜ pnpm store: /Share/Common/cache/linux/pnpm-store（copy 导入）"
