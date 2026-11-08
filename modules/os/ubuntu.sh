#!/usr/bin/env bash
# M1: Ubuntu 系统基线与优化
[ -n "${BDE_ROOT:-}" ] || BDE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$BDE_ROOT/lib/paths.sh"
source "$BDE_ROOT/lib/common.sh"
source "$BDE_ROOT/lib/ensure.sh"

# 模块级 OS 自检（防御纵深：不依赖调用方 dispatch——单独执行本模块也绝不跑错包管理器）
_bde_os="$(bde_os_id)"
case "$_bde_os" in
    ubuntu|debian|linuxmint) : ;;
    *) bde_pending "ubuntu.sh 为 Debian 系适配器，当前 OS: $_bde_os——单独执行已拦截（apt 系命令未运行）；对应适配器见 modules/os/（arch.sh 为里程碑占位）"
       return 0 2>/dev/null || exit 0 ;;
esac

bde_info "M1 系统基线与优化（Ubuntu）"

# 1) 包索引（当日一次）
if sudo -n true 2>/dev/null && [ ! -f "/tmp/bde-apt-updated-$(date +%F)" ]; then
    sudo -n apt-get update -qq >/dev/null 2>&1 && touch "/tmp/bde-apt-updated-$(date +%F)"
fi

# 2) 基础包（zsh 为默认 shell 目标；konsole 为统一终端）
for _p in openssh-server build-essential whiptail zsh konsole; do ensure_pkg "$_p"; done
for _p in fcitx5 fcitx5-rime fcitx5-configtool fcitx5-frontend-gtk3 fcitx5-frontend-gtk4 fcitx5-frontend-qt5; do
    ensure_pkg "$_p"
done

# 3) 内核参数：inotify 上限（前端 watch 必需）
if [ ! -f /etc/sysctl.d/99-devspace.conf ]; then
    if printf 'fs.inotify.max_user_watches=524288\nfs.inotify.max_user_instances=1024\n' \
            | sudo -n tee /etc/sysctl.d/99-devspace.conf >/dev/null 2>&1 \
            && sudo -n sysctl -qw fs.inotify.max_user_watches=524288 fs.inotify.max_user_instances=1024 2>/dev/null; then
        bde_ok "内核参数：inotify 上限调高"
    else
        bde_pending "内核参数写入失败（需 sudo）"
    fi
else
    bde_skip "内核参数文件已存在"
fi

# 4) apt 源检查（只报告，不自动切）
if grep -rqsE 'aliyun|tuna|ustc|mirrors\.' /etc/apt/sources.list /etc/apt/sources.list.d/ 2>/dev/null; then
    bde_ok "apt 源已是国内镜像"
else
    bde_pending "apt 源为官方（人工确认后切阿里/清华，避免脚本盲改）"
fi

# 4.5) docker 服务三分离（宪法 §19.3：安装体 ① 包管理+enable+组；配置 ③ cfg-map docker-daemon；数据根 data-root → ① services/docker）
if command -v docker >/dev/null 2>&1; then
    bde_skip "docker 已装：$(timeout 10 docker --version 2>/dev/null | head -1)"
else
    ensure_pkg docker.io && bde_ok "docker.io 安装（apt 渠道）"
fi
if command -v docker >/dev/null 2>&1; then
    systemctl is-active --quiet docker 2>/dev/null         && bde_skip "docker 服务运行中"         || { sudo -n systemctl enable --now docker >/dev/null 2>&1 && bde_ok "docker enable --now"; }
    id -nG "$(id -un)" 2>/dev/null | grep -qw docker         && bde_skip "$(id -un) 已在 docker 组"         || { sudo -n usermod -aG docker "$(id -un)" 2>/dev/null && bde_ok "$(id -un) 加入 docker 组（重登生效）"; }
fi

# 5) docker daemon.json（仅缺失时创建，不覆盖既有；已有 cfg-map 收编版则跳过）
if [ ! -f /etc/docker/daemon.json ]; then
    if sudo -n mkdir -p /etc/docker 2>/dev/null \
       && printf '%s' '{
  "registry-mirrors": ["https://docker.1ms.run"],
  "log-driver": "json-file",
  "log-opts": {"max-size": "10m", "max-file": "3"}
}' | sudo -n tee /etc/docker/daemon.json >/dev/null 2>&1; then
        bde_ok "docker daemon.json 已创建（重启 docker 生效）"
    else
        bde_pending "docker daemon.json 写入失败"
    fi
else
    bde_skip "docker daemon.json 已存在（不覆盖）"
fi

# 6) 终端：默认 konsole + Ctrl+Alt+T
if command -v konsole >/dev/null 2>&1; then
    if sudo -n update-alternatives --set x-terminal-emulator /usr/bin/konsole >/dev/null 2>&1; then
        bde_ok "默认终端 → konsole"
    else
        bde_pending "x-terminal-emulator 设置失败"
    fi
    if command -v gsettings >/dev/null 2>&1; then
        _kb="$(gsettings get org.gnome.settings-daemon.plugins.media-keys custom-keybindings 2>/dev/null || echo '@as []')"
        if [ "$_kb" = "@as []" ]; then
            _p="/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0/"
            gsettings set org.gnome.settings-daemon.plugins.media-keys custom-keybindings "[$_p]" 2>/dev/null \
                && gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:$_p name 'Konsole' 2>/dev/null \
                && gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:$_p command 'konsole' 2>/dev/null \
                && gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:$_p binding '<Primary><Alt>t' 2>/dev/null \
                && bde_ok "Ctrl+Alt+T → konsole"
        else
            bde_skip "已存在自定义快捷键（不覆盖）"
        fi
    fi
else
    bde_pending "konsole 未安装，终端统一跳过"
fi

# 7) shell：默认 zsh + bash 兼容 env
if command -v zsh >/dev/null 2>&1; then
    _cur_shell="$(getent passwd "$(id -un)" | cut -d: -f7)"
    if [ "$_cur_shell" != "$(command -v zsh)" ]; then
        if sudo -n chsh -s "$(command -v zsh)" "$(id -un)" 2>/dev/null; then
            bde_ok "默认 shell → zsh（下次登录生效）"
        else
            bde_pending "chsh 失败"
        fi
    else
        bde_skip "默认 shell 已是 zsh"
    fi
fi
if ensure_line "$HOME/.bashrc" '[ -f "$HOME/.config/devspace/env.sh" ] && . "$HOME/.config/devspace/env.sh"  # devspace'; then
    bde_ok ".bashrc 已接 env.sh"
else
    bde_pending ".bashrc 追加失败"
fi

# 8) starship（用户级安装，免 sudo）
if command -v starship >/dev/null 2>&1; then
    bde_skip "starship 已装"
elif curl -fsSL --max-time 90 https://starship.rs/install.sh | sh -s -- --bin-dir "$HOME/.local/bin" --yes >/dev/null 2>&1; then
    bde_ok "starship 安装（~/.local/bin）"
else
    bde_pending "starship 安装失败"
fi

# 9) 输入法：皮肤与 rime 简体默认自动落位（幂等，三链路拉取）；启用切换仍人工
bash "$BDE_ROOT/modules/os/fcitx5-theme.sh"
bde_pending "启用 fcitx5：im-config -n fcitx5 后注销重登（人工执行；IM 环境变量由 config 仓库 environment.d 下发，不要写 .profile）"
bde_pending "GNOME Wayland 限制：Wayland 原生客户端（Chromium/Electron 的 ozone-wayland、GNOME Shell 自身界面）无法用 fcitx5，需该客户端走 XWayland 或改用 IBus"
bde_pending "rime-ice 雾凇方案（可选大词库）：github.com/amzxyz/rime-ice → $HOME/DevEnv/xdg/local/fcitx5/rime/（人工）"

bde_ok "M1 完成"
