#!/usr/bin/env bash
# lib/network.sh — L0 网络画像层（与 lib/storage.sh 同构）：站点 → 镜像/出口解析，屏蔽网络环境差异
# 镜像与代理是"站点属性"（家庭 LAN / 办公室 / 云主机），不是机器属性——差异只存在于档案本文件
# 档案：③ 正本 config/data/network.toml（[default] 基线 + [hostname] 机器段覆盖）
# 语义：https_proxy 留空 = 直连（不导出任何代理变量）；镜像键留空 = 不导出该镜像变量
# 解析失败（无 python3≥3.11 / toml 损坏）→ 输出为空，调用方走 env.sh 内置兜底（bootstrap 免疫）
# 对上层只暴露：bde_network_emit（stdout = network.env 内容；空输出 = 档案未生效）

[ -n "${BDE_NETWORK_LOADED:-}" ] && return 0 2>/dev/null || true
BDE_NETWORK_LOADED=1

bde_network_profile() {  # 档案定位（或空 = 无档案）
    if [ -n "${BDE_NETWORK_PROFILE:-}" ] && [ -f "$BDE_NETWORK_PROFILE" ]; then
        echo "$BDE_NETWORK_PROFILE"; return
    fi
    # bootstrap 免疫：③ 正本可能尚未挂载——路径写死与本文件头注释一致
    [ -f /Share/Common/config/data/network.toml ] && { echo /Share/Common/config/data/network.toml; return; }
    echo ""
}

# —— 生成 network.env 内容（stdout；空输出 = 档案未生效/解析失败，调用方回退 env.sh 兜底）——
bde_network_emit() {  # $1 = 生成日期备注（可选）
    local prof; prof="$(bde_network_profile)"
    [ -n "$prof" ] || { echo "[bde-network] 无网络档案（network.toml）——回退 env.sh 内置兜底" >&2; return 1; }
    python3 -c 'import tomllib' 2>/dev/null || { echo "[bde-network] python3 缺少 tomllib（需 ≥3.11）——回退 env.sh 内置兜底" >&2; return 1; }

    BDE_NETWORK_PROFILE_FILE="$prof" \
    BDE_NETWORK_MACHINE="$(printf '%s' "${BDE_MACHINE:-$(hostname)}" | tr '[:upper:]' '[:lower:]')" \
    BDE_NETWORK_DATE="${1:-$(date '+%F %T')}" \
    python3 <<'PY'
import os, sys, tomllib, shlex
prof, machine = os.environ["BDE_NETWORK_PROFILE_FILE"], os.environ["BDE_NETWORK_MACHINE"]
try:
    with open(prof, "rb") as fh:
        d = tomllib.load(fh)
except Exception as e:
    print(f"[bde-network] network.toml 解析失败（{e}）——回退 env.sh 内置兜底", file=sys.stderr)
    sys.exit(1)

def get(key, dft=""):
    ms = d.get(machine, {})
    return ms.get(key) or d.get("default", {}).get(key, dft)

def emit(k, v):
    if v:
        print(f"export {k}={shlex.quote(str(v))}")

NO_PROXY_DFT = "localhost,127.0.0.1,::1,192.168.0.0/16,10.0.0.0/8,172.16.0.0/12,.aliyuncs.com,.aliyun.com,.cn"
print(f"# network.env — 网络画像（由 BestDevEnv/lib/network.sh 生成于 {os.environ['BDE_NETWORK_DATE']}；机器 {machine}）")
print("# 正本 ③ config/data/network.toml ｜ 再生: devenv state-env ｜ 勿手改（手改会被再生覆盖）")

emit("BDE_NODE_DIST_MIRROR",        get("node_dist_mirror"))
emit("PIP_INDEX_URL",               get("pip_index_url"))
emit("RUSTUP_DIST_SERVER",          get("rustup_dist_server"))
emit("RUSTUP_UPDATE_ROOT",          get("rustup_update_root"))
emit("GOPROXY",                     get("goproxy"))
emit("PUB_HOSTED_URL",              get("pub_hosted_url"))
emit("FLUTTER_STORAGE_BASE_URL",    get("flutter_storage_base_url"))
emit("HF_ENDPOINT",                 get("hf_endpoint"))

hp = get("https_proxy")
if hp:
    emit("https_proxy", hp); emit("http_proxy", hp); emit("all_proxy", hp)
    emit("HTTPS_PROXY", hp); emit("HTTP_PROXY", hp); emit("ALL_PROXY", hp)
    np = get("no_proxy", NO_PROXY_DFT)
    emit("NO_PROXY", np); emit("no_proxy", np)
PY
}
