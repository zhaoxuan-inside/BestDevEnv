#!/usr/bin/env bash
# M1.5: chezmoi 安装 + config 应用（种子 → /Share/Common/config → 应用层）
[ -n "${BDE_ROOT:-}" ] || BDE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$BDE_ROOT/lib/paths.sh"
source "$BDE_ROOT/lib/common.sh"
source "$BDE_ROOT/lib/ensure.sh"

bde_info "M1.5 config 应用"

# 1) 机器数据表同步（config 源中 hosts.toml 与工程根保持一致）
if [ -d "$COMMON/config" ] && [ -f "$BDE_ROOT/hosts.toml" ]; then
    cp "$BDE_ROOT/hosts.toml" "$COMMON/config/hosts.toml" && bde_ok "hosts.toml 同步 → config"
fi

# 2) chezmoi 安装（curl 优先用户级，snap 兜底）
if command -v chezmoi >/dev/null 2>&1; then
    bde_skip "chezmoi 已装：$(chezmoi --version 2>/dev/null | head -1)"
elif curl -fsSL --max-time 120 https://get.chezmoi.io -o /tmp/bde-chezmoi-install.sh 2>/dev/null \
     && sh /tmp/bde-chezmoi-install.sh -b "$HOME/.local/bin" >/dev/null 2>&1; then
    bde_ok "chezmoi 安装（~/.local/bin）"
elif sudo -n snap install chezmoi --classic >/dev/null 2>&1; then
    bde_ok "chezmoi 安装（snap）"
else
    bde_pending "chezmoi 安装失败"
    return 0
fi

# 3) 备份 + 应用（宪法：应用层由事实源再生，但改前必须留底）
ensure_backup "$HOME/.zshrc"
ensure_backup "$HOME/.gitconfig"
if [ -f "$COMMON/config/.chezmoiignore" ]; then
    if chezmoi apply -S "$COMMON/config" --destination "$HOME" --force >/dev/null 2>&1; then
        bde_ok "chezmoi apply 完成（config → 应用层）"
    else
        bde_pending "chezmoi apply 失败"
    fi
else
    bde_pending "config 源缺失：$COMMON/config"
fi
