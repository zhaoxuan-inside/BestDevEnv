#!/usr/bin/env bash
# modules/os/adapters/_linux-systemd.sh — L2 适配器基座：systemd 系 Linux 共有能力实现
# 由 debian.sh / fedora.sh / arch.sh / suse.sh source（下划线前缀 = 非家族，cap_load 永不直接加载）。
# 覆盖机制同构的能力：svc/kernel/limits/logs/trim/timesync/hostname/fonts/shell/group；
# 机制相异的 pkg 与桌面类（im/terminal）由各家适配器自行实现——未实现者由总线优雅降级。
[ -n "${BDE_ROOT:-}" ] || BDE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$BDE_ROOT/lib/ensure.sh"   # ensure_dir/ensure_backup 幂等原语

_CAP_SYSCTL_CONF="/etc/sysctl.d/99-devspace.conf"
_CAP_JOURNAL_CONF="/etc/systemd/journald.conf.d/99-devspace.conf"
_CAP_LIMITS_CONF="/etc/security/limits.d/99-devspace.conf"

# 正本落位通用件（备份 + cmp 幂等 + sudo；内容归 ③ 正本/cfg-map 治理，这里只搬）
_cap_copy_conf() {  # <正本> <目标> <描述> → 0=一致或落位成功
    local src=$1 dst=$2 desc=$3
    [ -f "$src" ] || { bde_pending "$desc 正本缺失：$src（M2 已建 config seed？）"; return 1; }
    sudo -n mkdir -p "$(dirname "$dst")" 2>/dev/null
    if cmp -s "$src" "$dst" 2>/dev/null; then
        bde_skip "$desc 已一致（$dst）"
        return 0
    fi
    ensure_backup "$dst"
    sudo -n cp "$src" "$dst" && bde_ok "$desc 落位 $dst（正本为准）" \
        || { bde_pending "$desc 写入失败（需 sudo 免密）"; return 1; }
}

# ── svc（systemd）──
cap__svc_ensure() {
    cap__svc_active "$1" && return 0
    sudo -n systemctl enable --now "$1" >/dev/null 2>&1
}
cap__svc_active() { systemctl is-active --quiet "$1" 2>/dev/null; }

# ── kernel（sysctl.d）──
cap__kernel_ensure() {
    _cap_copy_conf "$1" "$_CAP_SYSCTL_CONF" "内核参数" || return 1
    if sudo -n sysctl --system >/dev/null 2>&1; then
        bde_ok "sysctl --system 生效"
    else
        bde_pending "sysctl --system 失败（人工执行）"
        return 1
    fi
}
cap__kernel_get() { sysctl -n "$1" 2>/dev/null; }

# ── limits（nofile；登录会话生效）──
cap__limits_ensure() { _cap_copy_conf "$1" "$_CAP_LIMITS_CONF" "nofile 上限"; }

# ── logs（journald drop-in）──
cap__logs_ensure() {
    _cap_copy_conf "$1" "$_CAP_JOURNAL_CONF" "journald 上限" || return 1
    if sudo -n systemctl restart systemd-journald >/dev/null 2>&1; then
        bde_ok "systemd-journald 重启生效"
    else
        bde_pending "journald 重启失败（下次重启生效）"
    fi
}

# ── trim（fstrim.timer 对机械盘无操作=无害）──
cap__trim_ensure() {
    if cap__svc_ensure fstrim.timer; then
        bde_ok "fstrim.timer 已启用（SSD 周期 TRIM）"
    else
        bde_pending "fstrim.timer 启用失败（util-linux 未带该单元？）"
        return 1
    fi
}

# ── timesync（只查不装：不盲改时间同步）──
cap__timesync_check() {
    if cap__svc_active systemd-timesyncd || cap__svc_active chronyd || cap__svc_active chrony || cap__svc_active ntpd; then
        bde_ok "时间同步服务运行中"
        return 0
    fi
    bde_pending "时间同步未运行（timedatectl set-ntp true 或装 chrony——人工确认后执行）"
    return 1
}

# ── hostname ──
cap__hostname_get() {
    if command -v hostnamectl >/dev/null 2>&1; then hostnamectl --static 2>/dev/null || hostname; else hostname; fi
}
cap__hostname_set() {
    sudo -n hostnamectl set-hostname "$1" 2>/dev/null && bde_ok "hostname → $1"
}

# ── fonts（用户级 fontconfig；桌面非桌面机都可用）──
cap__fonts_ensure() {  # <src-dir 含 ttf/otf>
    local src=$1 dst="$HOME/.local/share/fonts/devspace" n=0 f
    ensure_dir "$dst" || { bde_pending "字体目录不可建：$dst"; return 1; }
    for f in "$src"/*.ttf "$src"/*.otf; do
        [ -f "$f" ] || continue
        if [ -f "$dst/$(basename "$f")" ] && cmp -s "$f" "$dst/$(basename "$f")"; then continue; fi
        cp "$f" "$dst/" && n=$((n+1))
    done
    if [ "$n" -gt 0 ]; then
        command -v fc-cache >/dev/null 2>&1 && fc-cache -f "$dst" >/dev/null 2>&1
        bde_ok "字体安装 $n 个 → ${dst/#$HOME/\~}"
    else
        bde_skip "字体已一致"
    fi
}

# ── shell ──
cap__shell_get() { getent passwd "$(id -un)" | cut -d: -f7; }
cap__shell_set() { sudo -n chsh -s "$1" "$(id -un)" >/dev/null 2>&1; }

# ── group ──
cap__group_ensure() {  # <user> <group>
    id -nG "$1" 2>/dev/null | grep -qw "$2" && return 0
    sudo -n usermod -aG "$2" "$1" >/dev/null 2>&1
}

# im/terminal 机制各家相异（im-config 是 debian 专属、update-alternatives debian 专属）——
# 基座不实现：总线自动 pending 降级，各家适配器按真实机制补齐。
