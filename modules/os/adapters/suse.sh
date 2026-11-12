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
        zram)          echo \"zram-generator\" ;;
        power-suite)   echo \"tlp\" ;;
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
    if grep -qsE 'tuna|ustc|aliyun|mirrors' /etc/zypp/repos.d/*.repo 2>/dev/null; then
        bde_ok "zypper 源已是国内镜像"
        return 0
    fi
    bde_pending "zypper 源为官方（人工确认后切阿里云/清华 opensuse 镜像）"
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
