#!/usr/bin/env bash
# M3: Dart/Flutter —— 沿用 DevEnv/flutter；PUB_CACHE 重定向；gradle 缓存外置
[ -n "${BDE_ROOT:-}" ] || BDE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$BDE_ROOT/lib/paths.sh"
source "$BDE_ROOT/lib/common.sh"
source "$BDE_ROOT/lib/ensure.sh"

bde_info "M3 flutter"

if [ -d "$DEV/flutter" ] && command -v flutter >/dev/null 2>&1; then
    bde_ok "flutter 已装：$(flutter --version 2>/dev/null | head -1)"
elif [ -d "$DEV/flutter" ]; then
    bde_pending "DevEnv/flutter 存在但不在 PATH（检查 .zshrc/profile）"
else
    bde_pending "flutter 未安装（git clone 到 DevEnv/flutter，FLUTTER_STORAGE_BASE_URL 已就绪）"
fi

ensure_dir "$DEV/pub-cache" 2>/dev/null || true
ensure_dir "$LOCAL/10_Cache/gradle" 2>/dev/null || true
bde_ok "PUB_CACHE → $DEV/pub-cache ｜ gradle → $LOCAL/10_Cache/gradle"
