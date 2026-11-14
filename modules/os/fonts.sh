#!/usr/bin/env bash
# modules/os/fonts.sh — 开发者字体统一（JetBrainsMono Nerd Font；用户级安装，不碰系统目录）
# 落位链（宪法 §19.4 十分离）：③ install/fonts 本地投放（内网/离线优先）→ ② cache/fonts 网络兜底
# → 安装体经 fonts 能力落平台字体目录（debian: ~/.local/share/fonts + fc-cache）。
[ -n "${BDE_ROOT:-}" ] || BDE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$BDE_ROOT/lib/paths.sh"
source "$BDE_ROOT/lib/common.sh"
source "$BDE_ROOT/lib/ensure.sh"
source "$BDE_ROOT/lib/cap.sh"

bde_info "M1.9 字体统一（JetBrainsMono Nerd Font）"

# 站点网络画像接入（下载走站点代理/镜像契约，不写死网络字面量）
[ -f "$DEV/docs/state/network.env" ] && . "$DEV/docs/state/network.env"

FONT_ID="JetBrainsMono-NF"
NF_URL="https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.tar.xz"

# 1) 源解析：③ 手工投放 → ② 下载缓存（幂等）
_src=""
ensure_dir "$LOCAL/10_Cache/fonts" 2>/dev/null || true
if [ -d "$COMMON/install/fonts/$FONT_ID" ] && ls "$COMMON/install/fonts/$FONT_ID"/*.ttf >/dev/null 2>&1; then
    _src="$COMMON/install/fonts/$FONT_ID"
    bde_skip "字体源：③ 本地投放 $_src"
else
    _cache="$LOCAL/10_Cache/fonts/$FONT_ID"
    if ls "$_cache"/*.ttf >/dev/null 2>&1; then
        _src="$_cache"
        bde_skip "字体源：② 缓存 $_cache"
    elif curl -fsSL --max-time 180 "$NF_URL" -o "$LOCAL/10_Cache/fonts/JetBrainsMono.tar.xz" 2>/dev/null \
         && mkdir -p "$_cache" \
         && tar -xJf "$LOCAL/10_Cache/fonts/JetBrainsMono.tar.xz" -C "$_cache" 2>/dev/null \
         && ls "$_cache"/*.ttf >/dev/null 2>&1; then
        rm -f "$LOCAL/10_Cache/fonts/JetBrainsMono.tar.xz"
        _src="$_cache"
        bde_ok "字体下载解包 → $_cache"
    else
        rm -f "$LOCAL/10_Cache/fonts/JetBrainsMono.tar.xz" 2>/dev/null
        bde_pending "Nerd Font 下载失败（github 可达性；可手工投放 ttf → $COMMON/install/fonts/$FONT_ID 后重跑）"
    fi
fi

# 2) 安装体 → fonts 能力（平台差异在适配器）
if [ -n "$_src" ]; then
    cap_run fonts ensure "$_src" || true
fi
