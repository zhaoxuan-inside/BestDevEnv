#!/usr/bin/env bash
# M3: Node/TypeScript —— nvm 兼容期保留；mise 接管预备；npm 镜像与共享缓存
[ -n "${BDE_ROOT:-}" ] || BDE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$BDE_ROOT/lib/paths.sh"
source "$BDE_ROOT/lib/common.sh"
source "$BDE_ROOT/lib/ensure.sh"

bde_info "M3 node"

# 1) mise 安装（node 接管的预备；装在 node 现状检查前，供无 nvm 机器直接接管）
if command -v mise >/dev/null 2>&1; then
    bde_skip "mise 已装：$(mise --version 2>/dev/null | head -1)"
elif curl -fsSL --max-time 120 https://mise.run | MISE_INSTALL_PATH="$HOME/.local/bin/mise" bash >/dev/null 2>&1 \
     && [ -x "$HOME/.local/bin/mise" ]; then
    bde_ok "mise 安装（~/.local/bin）"
else
    bde_pending "mise 安装失败"
fi

# 2) node 现状（nvm 存在→兼容期只提示；nvm 不在→mise 接管安装 LTS）
if command -v node >/dev/null 2>&1; then
    bde_ok "node 已装：$(node --version)"
else
    if [ -s "${NVM_DIR:-$HOME/DevEnv/nvm}/nvm.sh" ]; then
        bde_pending "node 未安装（nvm 兼容期：nvm install --lts 或改用 mise use -g node@lts）"
    elif command -v mise >/dev/null 2>&1 || [ -x "$HOME/.local/bin/mise" ]; then
        _mise="$(command -v mise || echo "$HOME/.local/bin/mise")"
        if "$_mise" use -g node@lts >/dev/null 2>&1; then
            export PATH="$HOME/.local/share/mise/shims:$PATH"
            bde_ok "mise 接管：node LTS 就绪（$(node --version 2>/dev/null || echo '待新 shell 生效')）"
        else
            bde_pending "mise 安装 node 失败"
        fi
    else
        bde_pending "node 未安装且 mise 未就绪"
    fi
fi

# 3) npm 配置（.npmrc 由 config apply 下发：registry/cache/store → 共享盘）
if [ -f "$HOME/.npmrc" ]; then
    bde_ok ".npmrc 就绪（registry/cache/store-dir → /Share/Common/cache/linux）"
else
    bde_pending ".npmrc 缺失（先完成 M1.5 apply-config）"
fi
