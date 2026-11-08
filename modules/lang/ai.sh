#!/usr/bin/env bash
# M3: AI/LLM —— 模型权重单份共享（Common/data/models）；HF 走国内镜像
[ -n "${BDE_ROOT:-}" ] || BDE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$BDE_ROOT/lib/paths.sh"
source "$BDE_ROOT/lib/common.sh"
source "$BDE_ROOT/lib/ensure.sh"

bde_info "M3 ai"

for d in "$COMMON/data/models/gguf" "$COMMON/data/models/huggingface" "$COMMON/data/models/modelscope"; do
    ensure_dir "$d" 2>/dev/null || true
done
bde_ok "模型权重目录 → $COMMON/data/models（单份全机共享）"

[ -f "$HOME/.config/devspace/env.sh" ] && bde_ok "HF_HOME/HF_ENDPOINT → env.sh 就绪"

if command -v uv >/dev/null 2>&1; then
    bde_skip "uv 就绪（模型类 Python 工具用 uv tool 装，缓存已共享）"
fi
