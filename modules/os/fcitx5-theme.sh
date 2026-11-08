#!/usr/bin/env bash
# M1 补充: fcitx5 macOS 皮肤（macos12 light/dark）+ rime 简体默认——幂等落位
# 主题/rime 实体 → ① $DEV/xdg/local/fcitx5/（XDG_DATA_HOME 重定向落点，GUI 会话一致）
# 皮肤选择在 config 仓库 dot_config/fcitx5/conf/classicui.conf（chezmoi 下发，本脚本不碰）
# 拉取链路: git clone → jsDelivr CDN → api.github.com contents（2026-11-08 实证主站被 RST 时 API 仍通）
[ -n "${BDE_ROOT:-}" ] || BDE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$BDE_ROOT/lib/paths.sh"
source "$BDE_ROOT/lib/common.sh"

REPO="witt-bit/fcitx5-theme-macos12"
DIRS=(macos12-light macos12-dark)
FILES=(theme.conf panel.svg highlight.svg)
THEMES_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/fcitx5/themes"
RIME_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/fcitx5/rime"

bde_info "fcitx5 macOS 皮肤（macos12）+ rime 简体默认"

_theme_complete() {
    local d
    for d in "${DIRS[@]}"; do [ -s "$THEMES_DIR/$d/theme.conf" ] || return 1; done
    return 0
}

_fetch_all() { # $1=git|jsdelivr|api —— 全文件成功才返回 0，失败文件由后续链路覆写
    local m="$1" d f ok=0
    for d in "${DIRS[@]}"; do
        mkdir -p "$THEMES_DIR/$d"
        for f in "${FILES[@]}"; do
            case "$m" in
                git)     cp "$_td/repo/$d/$f" "$THEMES_DIR/$d/$f" 2>/dev/null ;;
                jsdelivr) curl -fsSL --max-time 15 "https://cdn.jsdelivr.net/gh/$REPO@main/$d/$f" -o "$THEMES_DIR/$d/$f" 2>/dev/null ;;
                api)     curl -fsSL --max-time 15 "https://api.github.com/repos/$REPO/contents/$d/$f" 2>/dev/null \
                            | python3 -c "import json,sys,base64;sys.stdout.buffer.write(base64.b64decode(json.load(sys.stdin)['content']))" \
                            > "$THEMES_DIR/$d/$f" 2>/dev/null ;;
            esac && ok=$((ok+1))
        done
    done
    [ "$ok" -eq $((${#DIRS[@]} * ${#FILES[@]})) ]
}

if _theme_complete; then
    bde_skip "macos12 皮肤已就位（$THEMES_DIR）"
else
    _td="$(mktemp -d)"
    if git clone -q --depth 1 "https://github.com/$REPO.git" "$_td/repo" 2>/dev/null && _fetch_all git; then
        bde_ok "macos12 皮肤拉取（git clone）"
    elif _fetch_all jsdelivr; then
        bde_ok "macos12 皮肤拉取（jsDelivr CDN）"
    elif _fetch_all api; then
        bde_ok "macos12 皮肤拉取（api.github.com）"
    else
        bde_pending "macos12 皮肤拉取失败（三链路均不通）——网络恢复后重跑 bash $BDE_ROOT/modules/os/fcitx5-theme.sh"
    fi
    rm -rf "$_td"
fi

# rime 简体默认（零下载内置方案 luna_pinyin_simp；已有定制不覆盖——雾凇 rime-ice 属人工可选）
if [ ! -s "$RIME_DIR/default.custom.yaml" ]; then
    mkdir -p "$RIME_DIR"
    printf '# rime 全局定制——默认唯一方案：朙月拼音·简化字（零下载内置方案）\npatch:\n  schema_list:\n    - schema: luna_pinyin_simp\n' \
        > "$RIME_DIR/default.custom.yaml" \
        && bde_ok "rime 简体默认落位（$RIME_DIR/default.custom.yaml）" \
        || bde_pending "rime 默认方案写入失败"
else
    bde_skip "rime 定制已存在（$RIME_DIR/default.custom.yaml）"
fi

bde_ok "皮肤选择：config 仓库 classicui.conf（Theme=macos12-light/dark，chezmoi 下发）"
