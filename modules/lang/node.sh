#!/usr/bin/env bash
# M3: Node/TypeScript —— 来源三态判定（mise/nvm/系统）；npm 镜像与共享缓存
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

# 2) node 现状——按来源三态判定（command -v node 无法区分 nvm/mise/系统来源，2026-11-08 nvm 误判实证）
_mise="$(command -v mise || echo "$HOME/.local/bin/mise")"
_mise_installs="${XDG_DATA_HOME:-$HOME/.local/share}/mise/installs"
if compgen -G "$_mise_installs/node/*" >/dev/null 2>&1; then
    bde_ok "node 已由 mise 接管（$("$_mise" exec node -- node --version 2>/dev/null || echo '待 mise 解析')）"
elif [ -s "${NVM_DIR:-$HOME/DevEnv/nvm}/nvm.sh" ]; then
    if command -v node >/dev/null 2>&1; then
        bde_pending "nvm 兼容期（node $(node --version) 来自 nvm）——接管：mise settings set node.mirror_url 'https://cdn.npmmirror.com/binaries/node/' && mise use -g node@22.22.1，并退役 zshrc 的 nvm 块"
    else
        bde_pending "nvm 实体在但 PATH 无 node——nvm install --lts 或按上条接管"
    fi
elif command -v node >/dev/null 2>&1; then
    bde_ok "node 系统级安装：$(node --version)（来源 $(command -v node)）"
elif [ -x "$_mise" ]; then
    # npmmirror 镜像；尾斜杠必留——缺了拼接丢 node 段 404（2026-11-08 实证）
    "$_mise" settings set node.mirror_url 'https://cdn.npmmirror.com/binaries/node/' >/dev/null 2>&1
    if "$_mise" use -g node@lts >/dev/null 2>&1; then
        export PATH="${XDG_DATA_HOME:-$HOME/.local/share}/mise/shims:$PATH"
        bde_ok "mise 接管：node LTS 就绪（$(node --version 2>/dev/null || echo '待新 shell 生效')）"
    else
        bde_pending "mise 安装 node 失败"
    fi
else
    bde_pending "node 未安装且 mise 未就绪"
fi

# 3) npm 配置（.npmrc 由 config apply 下发：registry/cache/store → 共享盘）
if [ -f "$HOME/.npmrc" ]; then
    bde_ok ".npmrc 就绪（registry/cache/store-dir → /Share/Common/cache/linux）"
else
    bde_pending ".npmrc 缺失（先完成 M1.5 apply-config）"
fi
