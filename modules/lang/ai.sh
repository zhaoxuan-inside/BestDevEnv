#!/usr/bin/env bash
# M3: AI/LLM —— 模型训练师栈（v0.19 充实：Miniconda + 镜像 + 权重共享 + CUDA 体检）
# 分工：conda 安装体 → ① services（本机盘）；.condarc 正本 → cfg-map condarc（镜像/缓存落 ①）；
#       模型权重 → ③ data/models（全机单份共享）；驱动/CUDA → 只体检不安装（生产驱动人工管控）
[ -n "${BDE_ROOT:-}" ] || BDE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$BDE_ROOT/lib/paths.sh"
source "$BDE_ROOT/lib/common.sh"
source "$BDE_ROOT/lib/ensure.sh"
source "$BDE_ROOT/lib/cap.sh"

bde_info "M3 ai（模型训练栈）"

# 站点网络画像接入（Miniconda 拉取走站点代理/镜像契约）
[ -f "$DEV/docs/state/network.env" ] && . "$DEV/docs/state/network.env"

# 1) 模型权重目录 → ③（单份全机共享；HF/ModelScope 镜像与落点由 env.sh/network.toml 契约）
for d in "$COMMON/data/models/gguf" "$COMMON/data/models/huggingface" "$COMMON/data/models/modelscope"; do
    ensure_dir "$d" 2>/dev/null || true
done
bde_ok "模型权重目录 → $COMMON/data/models（单份全机共享）"

# 2) conda 环境/包缓存目录 → ①（symlink 需要；.condarc 已指此）
ensure_dir "$DEV/deps/conda/envs" 2>/dev/null || true
ensure_dir "$DEV/deps/conda/pkgs" 2>/dev/null || true

# 3) Miniconda（清华镜像静默安装 → ① services；幂等）
MCONDA="$DEV/services/miniconda3"
if command -v conda >/dev/null 2>&1 || [ -x "$MCONDA/bin/conda" ]; then
    bde_skip "conda 已就绪（$MCONDA）"
elif command -v python3 >/dev/null 2>&1 && uname -m | grep -q x86_64; then
    _mi="$LOCAL/cache/miniconda.sh"
    if curl -fsSL --max-time 300 -o "$_mi" \
        "https://mirrors.tuna.tsinghua.edu.cn/anaconda/miniconda/Miniconda3-latest-Linux-x86_64.sh" 2>/dev/null \
       && bash "$_mi" -b -p "$MCONDA" >/dev/null 2>&1; then
        rm -f "$_mi"
        bde_ok "Miniconda 安装 → $MCONDA（清华镜像）"
    else
        bde_pending "Miniconda 安装失败（tuna 可达性；可人工下载安装后重跑）"
    fi
else
    bde_pending "Miniconda 跳过（非 x86_64：人工按架构安装 ARM 版）"
fi

# 4) .condarc 正本就绪提示（镜像/envs/pkgs 落点 → cfg-map condarc，M1.6/devenv cfg apply 落位）
if [ -f "$HOME/.condarc" ]; then
    bde_skip ".condarc 已应用（cfg-map condarc；tuna 镜像 + envs/pkgs → ① deps/conda）"
else
    bde_pending ".condarc 未落位（devenv cfg apply condarc）"
fi

# 5) shell 接入提示（conda.sh hook 已入 dot_zshrc 正本；base 不自动激活）
[ -f "$HOME/.config/devspace/env.sh" ] && bde_ok "HF_HOME/HF_ENDPOINT/MODELSCOPE_CACHE → env.sh 就绪"

# 6) CUDA 体检（只报告不安装：驱动归生产管控）
if command -v nvidia-smi >/dev/null 2>&1; then
    bde_ok "NVIDIA 驱动：$(nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null | head -1)"
else
    bde_pending "无 NVIDIA 驱动（GPU 训练机人工装驱动；容器方案 nvidia-container-toolkit 见 bestdevenv-dev skill）"
fi
if [ -d /usr/local/cuda ]; then
    bde_ok "CUDA Toolkit：$(cat /usr/local/cuda/version.* 2>/dev/null | grep -oE '[0-9]+\.[0-9]+' | head -1 || basename "$(readlink /usr/local/cuda)")"
else
    bde_skip "无系统级 CUDA Toolkit（conda/容器内自带的按环境管理，正常）"
fi
