#!/usr/bin/env bash
# modules/os/adapters/debian.sh — L2 平台适配器：Debian 系（ubuntu/debian/linuxmint/pop/kali）
# 机制同构能力（svc/kernel/limits/logs/trim/timesync/hostname/fonts/shell/group）继承基座
# _linux-systemd.sh；本文件只保留 Debian 专属：apt 包管理 + 语义别名 + im/terminal 桌面机制。
# 本机实装验证机（Ubuntu 24.04）。
[ -n "${BDE_ROOT:-}" ] || BDE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/_linux-systemd.sh"

CAP_FAMILY="debian"

# ── 语义包别名（→ apt 包名；未知名透传）──
cap__pkg_alias() {
    case "$1" in
        base)          echo "openssh-server whiptail zsh" ;;
        build-base)    echo "build-essential" ;;
        java-21)       echo "openjdk-21-jdk" ;;
        docker-engine) echo "docker.io" ;;
        terminal)      echo "konsole" ;;
        im-suite)      echo "fcitx5 fcitx5-rime fcitx5-configtool fcitx5-frontend-gtk3 fcitx5-frontend-gtk4 fcitx5-frontend-qt5" ;;
        zram)          echo "zram-tools" ;;
        power-suite)   echo "tlp tlp-rdw" ;;
        *)             echo "$1" ;;
    esac
}

# ── pkg（apt）──
cap__pkg_installed() { dpkg -s "$1" >/dev/null 2>&1; }
cap__pkg_update_index() {
    [ -f "/tmp/bde-apt-updated-$(date +%F)" ] && return 0
    sudo -n apt-get update -qq >/dev/null 2>&1 && touch "/tmp/bde-apt-updated-$(date +%F)"
}
cap__pkg_install() {
    cap__pkg_update_index || true
    sudo -n DEBIAN_FRONTEND=noninteractive apt-get install -y "$@" >/dev/null 2>&1
}
cap__pkg_check_source() {  # 只报告不盲切（宪法：人工确认后才动源）
    if grep -rqsE 'aliyun|tuna|ustc|mirrors\.' /etc/apt/sources.list /etc/apt/sources.list.d/ 2>/dev/null; then
        bde_ok "apt 源已是国内镜像"
        return 0
    fi
    bde_pending "apt 源为官方（人工确认后切阿里/清华；正本 config/apt/ubuntu.sources 可经 devenv cfg apply 落位）"
    return 1
}

# ── im（fcitx5 全家桶 + 皮肤 + 启用提示）──
cap__im_ensure() {
    cap_pkg_install im-suite
    bash "$BDE_ROOT/modules/os/fcitx5-theme.sh"
    bde_pending "启用 fcitx5：im-config -n fcitx5 后注销重登（人工执行；IM 环境变量由 config 仓库 environment.d 下发，不要写 .profile）"
    bde_pending "GNOME Wayland 限制：Wayland 原生客户端（Chromium/Electron 的 ozone-wayland、GNOME Shell 自身界面）无法用 fcitx5，需该客户端走 XWayland 或改用 IBus"
    bde_pending "rime-ice 雾凇方案（可选大词库）：github.com/amzxyz/rime-ice → $HOME/DevEnv/xdg/local/fcitx5/rime/（人工）"
}

# ── zram（压缩内存交换；zram-tools + /etc/default/zramswap 正本，cfg-map zramswap 同步治理）──
cap__zram_ensure() {
    cap_pkg_install zram || return 1
    local src="$COMMON/config/services/zram/zramswap" dst="${BDE_CAP_ZRAMSWAP_CONF:-/etc/default/zramswap}"
    [ -f "$src" ] || { bde_pending "zramswap 正本缺失：$src"; return 1; }
    sudo -n mkdir -p "$(dirname "$dst")" 2>/dev/null
    if ! cmp -s "$src" "$dst" 2>/dev/null; then
        ensure_backup "$dst"
        sudo -n cp "$src" "$dst" && bde_ok "zramswap 参数落位（正本为准）" \
            || { bde_pending "zramswap 写入失败（需 sudo）"; return 1; }
    else
        bde_skip "zramswap 参数已一致"
    fi
    if cap__svc_ensure zramswap; then
        bde_ok "zram 已启用（swapon --show 可见 zram0）"
    else
        bde_pending "zramswap 服务启用失败"
        return 1
    fi
}

# ── terminal（konsole + update-alternatives + Ctrl+Alt+T + 统一 profile 指针）──
cap__terminal_ensure() {
    cap_pkg_install terminal
    if command -v konsole >/dev/null 2>&1; then
        if sudo -n update-alternatives --set x-terminal-emulator /usr/bin/konsole >/dev/null 2>&1; then
            bde_ok "默认终端 → konsole"
        else
            bde_pending "x-terminal-emulator 设置失败"
        fi
        # 统一 profile 指针（profile 本体由 cfg-map konsole-profile 落 XDG_DATA_HOME；
        # konsolerc 显式指 XDG_CONFIG_HOME 契约位——M1 上下文无 env.sh，不能依赖相对查找）
        if command -v kwriteconfig5 >/dev/null 2>&1; then
            kwriteconfig5 --file "${XDG_CONFIG_HOME:-$DEV/xdg/config}/konsolerc" --group General --key DefaultProfile devspace.profile \
                && bde_ok "konsole 默认 profile → devspace（字体/外观统一）"
        else
            bde_pending "kwriteconfig5 缺失：人工执行 kwriteconfig5 --file konsolerc --group General --key DefaultProfile devspace.profile"
        fi
        if command -v gsettings >/dev/null 2>&1; then
            local _kb _p
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
}
