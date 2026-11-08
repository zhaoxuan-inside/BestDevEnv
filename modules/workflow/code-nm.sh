#!/usr/bin/env bash
# code-nm <repo> —— JS 依赖实体外置：node_modules 物理落 ① 本机盘，接回共享盘项目
# 接回策略按 probe 能力事实分支（宪法 §19.5：执行层消费探测事实，不按最差硬件一刀切）：
#   共享盘支持 symlink（P_CAP_SYMLINK=1）→ ln -s 直链（免 sudo，重启无需恢复）
#   不支持（如 HGFS）→ bind mount 接回（登记 bindmounts.list，code-open 恢复）
# （实体在本机盘才可装依赖；忘接时 npm 报 symlink 错=响亮失败）
[ -n "${BDE_ROOT:-}" ] || BDE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$BDE_ROOT/lib/paths.sh"
source "$BDE_ROOT/lib/common.sh"

REPO="${1:?用法: code-nm <repo>}"
bde_require_linux || exit 1
DIR="$COMMON/code/$REPO"
[ -d "$DIR" ] || { bde_fail "仓库不存在: $DIR"; exit 1; }
[ -f "$DIR/package.json" ] || { bde_fail "$REPO 不是 JS/TS 项目（无 package.json）"; exit 1; }

REAL="$DEV/deps/$REPO/node_modules"
MP="$DIR/node_modules"
LIST="${BDE_BINDMOUNTS:-$DEV/docs/bindmounts.list}"
ROOT="$(bde_root)"

mkdir -p "$REAL" || { bde_fail "无法创建实体目录 $REAL"; exit 1; }

# ── 能力事实：先读 probe 快照（M2/主调度采集），快照过期/缺失时现场复测兜底 ──
_cap_link=0
_pj="${BDE_PROBE_STATE_DIR:-$DEV/docs/state}/probe.json"   # 尊循 probe.sh 状态目录契约（可注入测试）
if [ -f "$_pj" ] && command -v python3 >/dev/null 2>&1; then
    _cap_link="$(BDE_PROBE_JSON="$_pj" python3 -c 'import json,os;print(json.load(open(os.environ["BDE_PROBE_JSON"])).get("share_caps",{}).get("symlink",0))' 2>/dev/null || echo 0)"
fi
if [ "$_cap_link" != "1" ]; then
    _t="$DIR/.bde-symlink-probe.$$"
    { ln -s . "$_t" 2>/dev/null && [ -L "$_t" ]; } 2>/dev/null && _cap_link=1
    rm -f "$_t" 2>/dev/null
fi

# ── 策略分支 ──
if mountpoint -q "$MP" 2>/dev/null; then
    bde_skip "bind 已在位: $REPO/node_modules"
elif [ -L "$MP" ] && [ "$(readlink "$MP")" = "$REAL" ]; then
    bde_skip "symlink 已在位: $REPO/node_modules"
elif [ "$_cap_link" = "1" ] && { [ ! -e "$MP" ] || [ -L "$MP" ] || { [ -d "$MP" ] && [ -z "$(ls -A "$MP" 2>/dev/null)" ]; }; }; then
    # symlink 策略：占位目录/旧符号链接先清；此前 bind 登记行同步除名（避免 code-open 恢复误挂）
    [ -d "$MP" ] && rmdir "$MP" 2>/dev/null
    rm -f "$MP" 2>/dev/null
    if [ -n "${LIST:-}" ] && [ -f "$LIST" ]; then
        grep -vF -- "$REPO|node_modules|" "$LIST" > "$LIST.tmp" 2>/dev/null || true
        mv "$LIST.tmp" "$LIST"
    fi
    if ln -s "$REAL" "$MP" 2>/dev/null; then
        bde_ok "symlink: $REPO/node_modules → $REAL（共享盘支持 symlink，免 bind）"
        bde_info "依赖实体: $REAL ｜ pnpm store: $COMMON/cache/linux/pnpm-store（copy 导入）"
        exit 0
    fi
    bde_info "symlink 落位失败，回退 bind 策略"
    mkdir -p "$MP" 2>/dev/null
fi

# ── bind 策略（symlink 不可用后端的既定通道）──
if [ ! -d "$MP" ] && ! [ -L "$MP" ]; then
    mkdir -p "$MP" 2>/dev/null
fi
if mountpoint -q "$MP" 2>/dev/null; then
    bde_skip "bind 已在位: $REPO/node_modules"
elif [ -n "$ROOT" ] && $ROOT mount --bind "$REAL" "$MP" 2>/dev/null; then
    bde_ok "bind: $REPO/node_modules → $REAL"
else
    bde_fail "接回失败（需 sudo 免密或共享盘 symlink 不可用）——npm 会因 symlink 报错（响亮失败，符合设计）"
    exit 1
fi

LINE="$REPO|node_modules|$REAL"
grep -qF -- "$LINE" "$LIST" 2>/dev/null || printf '%s\n' "$LINE" >> "$LIST"
bde_info "依赖实体: $REAL ｜ pnpm store: $COMMON/cache/linux/pnpm-store（copy 导入）"
