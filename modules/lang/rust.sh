#!/usr/bin/env bash
# M3: Rust —— rustup 现有；target 外置 hardlink 基准校验
[ -n "${BDE_ROOT:-}" ] || BDE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$BDE_ROOT/lib/paths.sh"
source "$BDE_ROOT/lib/common.sh"
source "$BDE_ROOT/lib/ensure.sh"

bde_info "M3 rust"

# 1) rustup/cargo 现状
if command -v cargo >/dev/null 2>&1; then
    bde_ok "cargo 已装：$(cargo --version)"
else
    bde_pending "cargo 未安装（rustup + rsproxy，见宪法 §11）"
fi

# 2) hardlink 基准（宪法 §15：决定 cargo target 是否外置 ② Local/build）
# 介质中性：播报探测事实 + 后端名（取自 L0 解析层），不硬编码介质名词（换后端文案自动正确）
ensure_dir "$LOCAL/20_Build" 2>/dev/null || true
_t="$LOCAL/20_Build/.bde-hardlink-test"
_be="${BDE_SCOPE_HOST_BACKEND:-unknown}"
if touch "$_t" 2>/dev/null; then
    if ln "$_t" "$_t.lnk" 2>/dev/null; then
        bde_ok "② Local（$_be）支持 hardlink（cargo target 外置可行）"
        rm -f "$_t.lnk"
    else
        bde_info "② Local（$_be）不支持 hardlink（probe 事实，预期内）→ cargo target 外置后需真实项目验证；异常则回退 ~/DevEnv/build"
        bde_pending "cargo target hardlink 行为待真实项目验证"
    fi
    rm -f "$_t"
else
    bde_pending "$LOCAL/20_Build 不可写，hardlink 基准未执行"
fi
