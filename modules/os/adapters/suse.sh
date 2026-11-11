#!/usr/bin/env bash
# modules/os/adapters/suse.sh — L2 平台适配器：SUSE 系（opensuse-leap/opensuse-tumbleweed/sles）
# 机制同构能力继承 _linux-systemd.sh 基座；本文件：zypper 包管理 + 语义别名。
# ⚠ 未实机验证——代码就绪，实机验证后修订（宪法：实机验证才算数）。
[ -n "${BDE_ROOT:-}" ] || BDE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/_linux-systemd.sh"

CAP_FAMILY="suse"

# ── 语义包别名（→ zypper 包名；未知名透传）──
cap__pkg_alias() {
    case "$1" in
        base)          echo "openssh zsh" ;;
        build-base)    echo "gcc gcc-c++ make" ;;
        java-21)       echo "java-21-openjdk java-21-openjdk-devel" ;;
        docker-engine) echo "docker docker-compose" ;;
        terminal)      echo "konsole" ;;
        im-suite)      echo "fcitx5 fcitx5-rime fcitx5-configtool fcitx5-qt5" ;;
        *)             echo "$1" ;;
    esac
}

# ── pkg（zypper）──
cap__pkg_installed() { rpm -q "$1" >/dev/null 2>&1; }
cap__pkg_update_index() {
    [ -f "/tmp/bde-zypp-updated-$(date +%F)" ] && return 0
    sudo -n zypper -q refresh >/dev/null 2>&1 && touch "/tmp/bde-zypp-updated-$(date +%F)"
}
cap__pkg_install() {
    cap__pkg_update_index || true
    sudo -n zypper -q --non-interactive install "$@" >/dev/null 2>&1
}
cap__pkg_check_source() {
    bde_pending "zypper 源镜像检查未实装——人工核对仓库（mirror 阿里云/清华 opensuse 源）"
    return 1
}
