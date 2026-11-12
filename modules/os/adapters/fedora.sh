#!/usr/bin/env bash
# modules/os/adapters/fedora.sh — L2 平台适配器：dnf 系（fedora/rhel/centos/rocky/alma）
# 机制同构能力继承 _linux-systemd.sh 基座；本文件：dnf 包管理 + 语义别名 + 桌面差异。
# ⚠ 未实机验证（当前无 dnf 实装机）——代码就绪，验证后按 doctor/实机反馈修订（宪法：实机验证才算数）。
[ -n "${BDE_ROOT:-}" ] || BDE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/_linux-systemd.sh"

CAP_FAMILY="fedora"

# ── 语义包别名（→ dnf 包名；未知名透传）──
cap__pkg_alias() {
    case "$1" in
        base)          echo "openssh-server zsh" ;;
        build-base)    echo "gcc gcc-c++ make" ;;
        java-21)       echo "java-21-openjdk java-21-openjdk-devel" ;;
        docker-engine) echo "moby-engine" ;;   # docker-ce 需上游 repo——M1 用官方仓 moby；ce repo 收编见 cfg 待办
        terminal)      echo "konsole" ;;
        im-suite)      echo "fcitx5 fcitx5-rime fcitx5-configtool fcitx5-frontend-gtk3 fcitx5-frontend-gtk4 fcitx5-qt5" ;;
        zram)          echo \"zram-generator\" ;;
        power-suite)   echo \"tlp\" ;;
        *)             echo "$1" ;;
    esac
}

# ── pkg（dnf）──
cap__pkg_installed() { rpm -q "$1" >/dev/null 2>&1; }
cap__pkg_update_index() {
    [ -f "/tmp/bde-dnf-updated-$(date +%F)" ] && return 0
    sudo -n dnf makecache --refresh -q >/dev/null 2>&1 && touch "/tmp/bde-dnf-updated-$(date +%F)"
}
cap__pkg_install() {
    cap__pkg_update_index || true
    sudo -n dnf install -y -q "$@" >/dev/null 2>&1
}
cap__pkg_check_source() {
    if grep -qsE 'tuna|ustc|aliyun|mirrors\.' /etc/yum.repos.d/*.repo 2>/dev/null; then
        bde_ok "dnf 源已是国内镜像"
        return 0
    fi
    bde_pending "dnf 源为官方（人工确认后切清华/中科大——/etc/yum.repos.d/）"
    return 1
}

# ── zram（zram-generator 机制：conf 落位 + daemon-reload；setup@zram0 启动或重启后生效）──
cap__zram_ensure() {
    cap_pkg_install zram || return 1
    local src="$COMMON/config/services/systemd/zram-generator.conf" dst="${BDE_CAP_ZRAM_CONF:-/etc/systemd/zram-generator.conf}"
    [ -f "$src" ] || { bde_pending "zram-generator 正本缺失：$src"; return 1; }
    sudo -n mkdir -p "$(dirname "$dst")" 2>/dev/null
    if ! cmp -s "$src" "$dst" 2>/dev/null; then
        ensure_backup "$dst"
        sudo -n cp "$src" "$dst" && bde_ok "zram-generator conf 落位（正本为准）" \
            || { bde_pending "zram-generator 写入失败（需 sudo）"; return 1; }
    else
        bde_skip "zram-generator conf 已一致"
    fi
    if sudo -n systemctl daemon-reload 2>/dev/null \
       && (systemctl is-active --quiet systemd-zram-setup@zram0 2>/dev/null \
           || sudo -n systemctl start systemd-zram-setup@zram0 2>/dev/null); then
        bde_ok "zram 已启用（systemd-zram-setup@zram0）"
    else
        bde_pending "zram setup 未 active（重启后由 generator 自动建；或人工 start systemd-zram-setup@zram0）"
    fi
}
