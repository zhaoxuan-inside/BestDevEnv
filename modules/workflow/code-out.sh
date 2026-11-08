#!/usr/bin/env bash
# code-out <repo> [subdir] —— 构建产物目录外置：物理落 ② 本机专享盘，接回项目
# 接回策略按 probe 能力事实分支（与 code-nm 同一套）：
#   共享盘支持 symlink → ln -s 直链（免 sudo，重启无需恢复）；否则 bind mount + 登记恢复
# 默认 subdir=target（Maven）；Gradle 用 build；前端用 dist。代码与产物物理分离（宪法原则）
[ -n "${BDE_ROOT:-}" ] || BDE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$BDE_ROOT/lib/paths.sh"
source "$BDE_ROOT/lib/common.sh"

REPO="${1:?用法: code-out <repo> [subdir=target|build|dist]}"
bde_require_linux || exit 1
SUB="${2:-target}"
DIR="$COMMON/code/$REPO"
[ -d "$DIR" ] || { bde_fail "仓库不存在: $DIR"; exit 1; }

REAL="$LOCAL/build/$REPO/$SUB"
MP="$DIR/$SUB"
LIST="${BDE_BINDMOUNTS:-$DEV/docs/bindmounts.list}"
ROOT="$(bde_root)"

mkdir -p "$REAL" || { bde_fail "无法创建 $REAL"; exit 1; }

# ── 能力事实：probe 快照优先，过期/缺失时现场复测兜底 ──
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

if mountpoint -q "$MP" 2>/dev/null; then
    bde_skip "bind 已在位: $REPO/$SUB"
elif [ -L "$MP" ] && [ "$(readlink "$MP")" = "$REAL" ]; then
    bde_skip "symlink 已在位: $REPO/$SUB"
elif [ "$_cap_link" = "1" ] && { [ ! -e "$MP" ] || [ -L "$MP" ] || { [ -d "$MP" ] && [ -z "$(ls -A "$MP" 2>/dev/null)" ]; }; }; then
    [ -d "$MP" ] && rmdir "$MP" 2>/dev/null
    rm -f "$MP" 2>/dev/null
    if [ -n "${LIST:-}" ] && [ -f "$LIST" ]; then
        grep -vF -- "$REPO|$SUB|" "$LIST" > "$LIST.tmp" 2>/dev/null || true
        mv "$LIST.tmp" "$LIST"
    fi
    if ln -s "$REAL" "$MP" 2>/dev/null; then
        bde_ok "symlink: $REPO/$SUB → $REAL（共享盘支持 symlink，免 bind）"
        bde_info "产物落点: $REAL ｜ 跨机成品 → $COMMON/exchange/$REPO/"
        exit 0
    fi
    bde_info "symlink 落位失败，回退 bind 策略"
fi

# ── bind 策略 ──
if [ ! -d "$MP" ] && ! [ -L "$MP" ]; then
    mkdir -p "$MP" 2>/dev/null
fi
if mountpoint -q "$MP" 2>/dev/null; then
    bde_skip "bind 已在位: $REPO/$SUB"
elif [ -n "$ROOT" ] && $ROOT mount --bind "$REAL" "$MP" 2>/dev/null; then
    bde_ok "bind: $REPO/$SUB → $REAL"
else
    bde_fail "接回失败（需 sudo 免密或共享盘 symlink 不可用）"
    exit 1
fi

LINE="$REPO|$SUB|$REAL"
grep -qF -- "$LINE" "$LIST" 2>/dev/null || printf '%s\n' "$LINE" >> "$LIST"
bde_info "产物落点: $REAL ｜ 跨机成品 → $COMMON/exchange/$REPO/"
