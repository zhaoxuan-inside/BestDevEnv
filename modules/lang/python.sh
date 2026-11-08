#!/usr/bin/env bash
# M3: Python —— uv 为主，venv 重定向 DevEnv/virtualenvs
[ -n "${BDE_ROOT:-}" ] || BDE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$BDE_ROOT/lib/paths.sh"
source "$BDE_ROOT/lib/common.sh"
source "$BDE_ROOT/lib/ensure.sh"

bde_info "M3 python"

# 1) uv
if command -v uv >/dev/null 2>&1; then
    bde_ok "uv 已装：$(uv --version | head -1)"
elif curl -LsSf --max-time 120 https://astral.sh/uv/install.sh | sh >/dev/null 2>&1 \
     && command -v uv >/dev/null 2>&1; then
    bde_ok "uv 安装"
else
    bde_pending "uv 安装失败"
fi

# 2) venv 根目录与缓存
ensure_dir "$DEV/virtualenvs" && bde_ok "venv 根：$DEV/virtualenvs"
ensure_dir "$COMMON/cache/linux/uv" 2>/dev/null || true
ensure_dir "$COMMON/cache/linux/pip" 2>/dev/null || true

# 3) 环境变量校验（env.sh 已定义 UV_CACHE_DIR / PIP_INDEX_URL）
if [ -f "$HOME/.config/devspace/env.sh" ]; then
    bde_ok "python 环境变量就绪（UV_CACHE_DIR/PIP_INDEX_URL → env.sh）"
else
    bde_pending "env.sh 缺失（先完成 M1.5 apply-config）"
fi
