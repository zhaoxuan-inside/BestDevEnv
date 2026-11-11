#!/usr/bin/env bash
# modules/os/adapters/arch.sh — L2 平台适配器：Arch 系（arch/manjaro/endeavouros/garuda）
# 机制同构能力继承 _linux-systemd.sh 基座；本文件：pacman 包管理 + 语义别名。
# ⚠ 未实机验证（hosts.toml 已登记 arch 实验机，P2 里程碑实机验证后修订）。
[ -n "${BDE_ROOT:-}" ] || BDE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/_linux-systemd.sh"

CAP_FAMILY="arch"

# ── 语义包别名（→ pacman 包名；未知名透传）──
cap__pkg_alias() {
    case "$1" in
        base)          echo "openssh zsh" ;;
        build-base)    echo "base-devel" ;;          # pacman 包组
        java-21)       echo "jdk21-openjdk" ;;
        docker-engine) echo "docker docker-compose" ;;
        terminal)      echo "konsole" ;;
        im-suite)      echo "fcitx5-im fcitx5-rime fcitx5-configtool" ;;  # fcitx5-im 为包组
        *)             echo "$1" ;;
    esac
}

# ── pkg（pacman）──
cap__pkg_installed() { pacman -Qi "$1" >/dev/null 2>&1; }
cap__pkg_install() {
    # Arch 滚动发行：安装前同步索引是常规（-y 轻量；失败不阻塞——包可能在缓存中）
    sudo -n pacman -Sy --noconfirm --needed "$@" >/dev/null 2>&1
}
cap__pkg_check_source() {
    bde_pending "pacman 镜像检查未实装——人工核对 /etc/pacman.d/mirrorlist（清华/中科大在列首）"
    return 1
}
