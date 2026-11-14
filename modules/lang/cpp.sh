#!/usr/bin/env bash
# M3: C++ —— 构建链/调试器/编译缓存（语义包名：平台包名差异收敛在适配器别名表）
[ -n "${BDE_ROOT:-}" ] || BDE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$BDE_ROOT/lib/paths.sh"
source "$BDE_ROOT/lib/common.sh"
source "$BDE_ROOT/lib/ensure.sh"
source "$BDE_ROOT/lib/cap.sh"

bde_info "M3 cpp"

# 1) 构建链与工具（build-base 语义名 → 适配器别名：debian=build-essential / fedora=gcc gcc-c++ make / arch=base-devel）
for _p in build-base cmake ninja-build gdb ccache clang clangd; do
    ensure_pkg "$_p"
done

# 1.5) clangd 无版本符号链接（Debian 系只出 clangd-XX 版本化二进制——统一 `clangd` 入口，用户级免 sudo）
if ! command -v clangd >/dev/null 2>&1; then
    _clangd_bin="$(ls /usr/bin/clangd-* 2>/dev/null | sort -V | tail -1)"
    if [ -n "$_clangd_bin" ]; then
        mkdir -p "$HOME/.local/bin" && ln -sf "$_clangd_bin" "$HOME/.local/bin/clangd" \
            && bde_ok "clangd 入口 → $HOME/.local/bin/clangd（→ $(basename "$_clangd_bin")）"
    fi
fi

# 2) ccache 缓存 → ②（按机隔离防锁；CCACHE_DIR 由 env.sh 契约下发）
ensure_dir "$LOCAL/10_Cache/ccache" 2>/dev/null || true
bde_ok "ccache 缓存 → $LOCAL/10_Cache/ccache（CCACHE_DIR → env.sh）"

# 3) 使用提示（不盲改任何项目工程文件）
bde_pending "clangd 需 compile_commands.json：CMake 项目加 -DCMAKE_EXPORT_COMPILE_COMMANDS=ON，软链到仓库根"
