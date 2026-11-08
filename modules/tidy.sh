#!/usr/bin/env bash
# tidy —— 可再生缓存清理（SAFE 清单；工具运行时/浏览器配置/用户数据/未知目录绝不碰）
# 运行：devenv tidy
[ -n "${BDE_ROOT:-}" ] || BDE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$BDE_ROOT/lib/paths.sh"
source "$BDE_ROOT/lib/common.sh"

bde_info "devenv tidy —— 可再生缓存清理（SAFE 清单）"
_before="$(df -BG / 2>/dev/null | awk 'NR==2{gsub("G","",$4);print $4}')"

tidy_rm() {
    local p=$1 label=$2 sz
    [ -e "$p" ] || { bde_skip "$label（不存在）"; return; }
    sz="$(du -sh "$p" 2>/dev/null | cut -f1)"
    if rm -rf "$p" 2>/dev/null; then bde_ok "清理 $label（$sz）"; else bde_fail "清理失败 $label"; fi
}

# —— SAFE 清单（全部可再生；新缓存随工具自动重建，走已配置的共享盘/镜像）——
tidy_rm "$HOME/.cache/gradle"                     "gradle 构建缓存（深层长名，不上共享盘）"
tidy_rm "$HOME/.cache/npm"                        "npm 旧缓存（已重定向共享盘）"
tidy_rm "$HOME/.cache/pnpm"                       "pnpm 旧缓存"
tidy_rm "$HOME/.cache/go-build"                   "go 构建缓存"
tidy_rm "$HOME/.cache/@opencodedesktop-updater"   "opencode 桌面更新包"
tidy_rm "$HOME/.cache/@opencode-aidesktop-updater" "opencode 桌面更新包（-aide 变体，2026-11-08 实测发现）"
tidy_rm "$HOME/.cache/@zcodedesktop-updater"      "zcode 桌面更新包"
tidy_rm "$HOME/.cache/node-gyp"                   "node-gyp 头文件缓存（可再生）"
tidy_rm "$HOME/.cache/vmware/drag_and_drop"       "VMware 拖拽暂存"
tidy_rm "$HOME/.cache/tracker3"                   "桌面索引缓存（tracker）"
tidy_rm "$HOME/.zcompdump"                        "zsh 补全缓存（可再生）"
tidy_rm "$HOME/.xsession-errors"                  "X 会话错误日志（可再生）"
tidy_rm "$HOME/.local/share/pnpm/store"           "pnpm 旧 store（已重定向共享盘）"
tidy_rm "$HOME/.dartServer"                       "dart 分析缓存"
tidy_rm "$HOME/.npm/_cacache"                     "npm 旧 cache（已重定向共享盘）"

# —— Electron 系应用 + 浏览器：定向清理标准缓存子目录（不碰登录态/会话/配置）——
# .config 侧（Electron 应用与浏览器 profile）与 .cache 侧（浏览器 HTTP 缓存，2026-11-08 纳入）
_el() { for sub in Cache "Code Cache" GPUCache DawnGraphiteCache DawnWebGPUCache GrShaderCache ShaderCache "Service Worker/CacheStorage"; do rm -rf "$1/$sub" 2>/dev/null; done; }
for _app in "Trae CN" ZCode Code Electron Codex ai.opencode.desktop; do
    [ -d "$HOME/.config/$_app" ] && { _el "$HOME/.config/$_app"; bde_ok "清理 Electron 缓存：$_app"; }
done
for _bc in ~/.cache/google-chrome/*/ ~/.cache/microsoft-edge/*/ ~/.cache/google-chrome-headless/*/; do
    [ -d "$_bc" ] && _el "$_bc"
done
for _b in google-chrome microsoft-edge; do
    for _prof in "$HOME/.config/$_b"/*/; do
        [ -d "$_prof" ] && _el "$_prof"
    done
done
bde_ok "浏览器缓存已清（.config profile + .cache HTTP 缓存；chrome/edge/headless）"

# —— vscode-server：多版本 server 只保留最新（按 mtime）——
if [ -d "$HOME/.vscode-server/cli/servers" ]; then
    (cd "$HOME/.vscode-server/cli/servers" && ls -t | tail -n +2 | while read -r _v; do rm -rf "$_v"; done)
    bde_ok "vscode-server 旧版本清理（保留最新）"
fi
if [ -d "$HOME/.local/share/Trash/files" ]; then
    rm -rf "$HOME/.local/share/Trash/files"/* "$HOME/.local/share/Trash/info"/* 2>/dev/null \
        && bde_ok "清理回收站"
fi
if sudo -n journalctl --vacuum-size=100M >/dev/null 2>&1; then
    bde_ok "系统日志压缩至 100M"
fi

# —— 保留项（工具运行时 / 用户数据 / 未知——绝不自动碰）——
bde_info "保留项（不在 SAFE 清单）：codex-runtimes（运行时）、JetBrains（索引）、GitKraken、fcitx5（用户词库）；浏览器登录态在 .config 不碰；ia-ui/vmware/opencode.db 已于 2026-11-08 治理清除外置"

_after="$(df -BG / 2>/dev/null | awk 'NR==2{gsub("G","",$4);print $4}')"
bde_ok "根盘释放约 $(( _after - _before ))G（现余 ${_after}G）"
