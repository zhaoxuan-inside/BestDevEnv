#!/usr/bin/env bash
# modules/os/baseline.sh — M1 系统基线与优化（L3 平台无关编排）
# 本文件零平台字面量：一切系统动作经 lib/cap.sh 能力总线分派到 modules/os/adapters/<family>.sh。
# 分工铁律（宪法延伸：先抽象能力，再按平台实现）：
#   声明式文件（sysctl/journald/limits/daemon.json/…）不经本层直写——正本由 cfg-map 治理（M1.6 落位），
#   能力层只做"生效动作"；服务生命周期归 svc 能力；包名差异收敛在适配器别名表（语义包名）。
[ -n "${BDE_ROOT:-}" ] || BDE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$BDE_ROOT/lib/paths.sh"
source "$BDE_ROOT/lib/common.sh"
source "$BDE_ROOT/lib/ensure.sh"
source "$BDE_ROOT/lib/cap.sh"

# 模块级自检（防御纵深：单独执行本模块也不会跑错平台）
if ! cap_load; then
    bde_pending "能力适配器未加载（family=$(bde_os_family)），M1 跳过"
    return 0 2>/dev/null || exit 0
fi
bde_info "M1 系统基线与优化（family=$BDE_CAP_FAMILY）"

# 站点网络画像接入（本层有外网下载点——starship/字体；代理与镜像由 ③ network.toml 契约，不写死）
[ -f "$DEV/docs/state/network.env" ] && . "$DEV/docs/state/network.env"

# 1) 基础包 + 构建链（语义包名；平台包名差异收敛在适配器别名表）
cap_pkg_install base
cap_pkg_install build-base
cap_run pkg check_source || true

# 2) docker：安装体 → 服务 → 用户组（daemon.json 归 cfg-map docker-daemon，M1.6 落位）
if cap_pkg_install docker-engine; then
    if cap_run svc ensure docker; then
        bde_ok "docker 服务 enable --now"
    else
        bde_pending "docker 服务启用失败"
    fi
    if cap_run group ensure "$(id -un)" docker; then
        bde_skip "$(id -un) 在 docker 组（或已加入，重登生效）"
    else
        bde_pending "$(id -un) 加入 docker 组失败"
    fi
    if command -v docker >/dev/null 2>&1; then
        bde_skip "docker 就绪：$(timeout 10 docker --version 2>/dev/null | head -1)"
    fi
fi

# 3) 终端 / 输入法（桌面能力；无桌面环境时适配器自行降级）
cap_run terminal ensure || true
cap_run im ensure || true

# 4) shell：默认 zsh + bash 兼容 env 接线
_zsh="$(command -v zsh 2>/dev/null)"
if [ -n "$_zsh" ]; then
    if cap_has shell get; then
        _cur_shell="$(cap_run shell get)"
        if [ "$_cur_shell" = "$_zsh" ]; then
            bde_skip "默认 shell 已是 zsh"
        elif cap_run shell set "$_zsh"; then
            bde_ok "默认 shell → zsh（下次登录生效）"
        else
            bde_pending "默认 shell 设置失败"
        fi
    fi
else
    bde_pending "zsh 未安装，默认 shell 切换跳过"
fi
if ensure_line "$HOME/.bashrc" '[ -f "$HOME/.config/devspace/env.sh" ] && . "$HOME/.config/devspace/env.sh"  # devspace'; then
    bde_ok ".bashrc 已接 env.sh"
else
    bde_pending ".bashrc 追加失败"
fi

# 5) starship 提示符（用户级安装，全平台同一渠道，免 sudo）
if command -v starship >/dev/null 2>&1; then
    bde_skip "starship 已装"
elif curl -fsSL --max-time 90 https://starship.rs/install.sh | sh -s -- --bin-dir "$HOME/.local/bin" --yes >/dev/null 2>&1; then
    bde_ok "starship 安装（~/.local/bin）"
else
    bde_pending "starship 安装失败"
fi

# 6) 声明式系统配置：正本 → 能力生效（正本缺失只提示——config seed 由 M2 建立）
cap_run kernel ensure "$COMMON/config/services/sysctl/99-devspace.conf" || true
cap_run logs   ensure "$COMMON/config/services/systemd/journald-devspace.conf" || true
cap_run limits ensure "$COMMON/config/services/limits/99-devspace.conf" || true

# 7) SSD 周期 TRIM / 时间同步 / 时区画像 / zram / 笔记本电源（各能力自带条件化与降级）
cap_run trim ensure || true
cap_run timesync ensure || true
cap_run locale ensure || true
cap_run zram ensure || true
cap_run power ensure || true

# 8) 开发者字体统一（JetBrainsMono Nerd Font；③ 本地投放优先，网络兜底）
source "$BDE_ROOT/modules/os/fonts.sh"

bde_ok "M1 完成"
