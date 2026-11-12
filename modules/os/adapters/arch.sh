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
        zram)          echo "zram-generator" ;;
        power-suite)   echo "tlp" ;;
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
    if grep -qsE 'tuna|ustc|aliyun' /etc/pacman.d/mirrorlist 2>/dev/null; then
        bde_ok "pacman 镜像已为国内（mirrorlist）"
        return 0
    fi
    bde_pending "pacman 镜像未配置国内源（/etc/pacman.d/mirrorlist 置清华/中科大于行首）"
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
