#!/usr/bin/env bash
# modules/dirs/state-env.sh — 每机器状态 env 生成器（① $DEV/docs/state/{anchors,network}.env）
# 数据源：L0 存储档案 storage.toml + 网络档案 network.toml（③，机器段覆盖默认段）
# 消费方：env.sh 自动 source 两文件（机器差异不再写死在共享的 env.sh 里）
# 再生命令：devenv state-env（M2 自动执行；改档案后手动重跑 + 重开 shell 生效）
# 幂等：每次全量再生（原子写）；network 解析失败时保留既有文件 + pending（env.sh 兜底把关）
[ -n "${BDE_ROOT:-}" ] || BDE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$BDE_ROOT/lib/paths.sh"
source "$BDE_ROOT/lib/common.sh"
source "$BDE_ROOT/lib/ensure.sh"
source "$BDE_ROOT/lib/network.sh"

STATE_DIR="$DEV/docs/state"
ensure_dir "$STATE_DIR" || { bde_fail "状态目录不可建：$STATE_DIR"; exit 1; }

# ── anchors.env：三档锚点正本（存储解析层发射，机器差异的唯一出口）──
_a="$STATE_DIR/anchors.env"
if bde_storage_anchors_emit > "$_a.tmp" && [ -s "$_a.tmp" ]; then
    mv "$_a.tmp" "$_a" && bde_ok "锚点正本 → ${_a/#$HOME/~}（③=$COMMON ②=$LOCAL ①=$DEV）"
else
    rm -f "$_a.tmp"; bde_fail "锚点发射失败（storage.sh 异常）"; exit 1
fi

# ── network.env：网络画像（镜像清单 + 代理出口）──
_n="$STATE_DIR/network.env"
if bde_network_emit "$(date '+%F %T')" > "$_n.tmp" 2>/tmp/bde-network-err && [ -s "$_n.tmp" ]; then
    mv "$_n.tmp" "$_n" && bde_ok "网络画像 → ${_n/#$HOME/~}（代理/镜像按档案再生）"
else
    rm -f "$_n.tmp"
    _err="$(cat /tmp/bde-network-err 2>/dev/null | head -1)"; rm -f /tmp/bde-network-err
    if [ -e "$_n" ]; then
        bde_skip "网络画像解析失败（${_err:-未知}），保留既有 $_n"
    else
        bde_pending "网络画像未生成（${_err:-无档案/解析失败}）——env.sh 走内置兜底"
    fi
fi

# ── chezmoi.toml：模板数据正本（① 每机器状态；③ config 的 .tmpl 种子按此渲染）──
# 双落位：chezmoi 配置查找随 XDG_CONFIG_HOME 漂移（env.sh 重定向 → $DEV/xdg/config），
# 未 source env.sh 的上下文又回落 ~/.config/chezmoi——两处同写，任何上下文数据一致，
# 行为不再由"调用方是否 source 过 env.sh"决定（差异屏蔽：上下文无关）。
# config 种子里的锚点差异（XDG → ② Local 等）不再写字面量——换用户/换挂载点后
# `devenv state-env` 重跑 + `chezmoi apply` 即再对齐，正本零修改。
_cz_content="$(cat <<EOF
# 由 devenv state-env 再生（① 每机器状态——③ config .tmpl 种子的锚点数据源；勿手改）
[data]
machine = "${BDE_MACHINE}"
dev = "${DEV}"
common = "${COMMON}"
local = "${LOCAL}"
share = "${SHARE}"
EOF
)"
_cz_ok=0 _cz_miss=""
for _czdir in "${XDG_CONFIG_HOME:-$HOME/.config}/chezmoi" "$HOME/.config/chezmoi"; do
    if mkdir -p "$_czdir" 2>/dev/null && printf '%s\n' "$_cz_content" > "$_czdir/chezmoi.toml"; then
        _cz_ok=$((_cz_ok+1))
    else
        _cz_miss="$_cz_miss ${_czdir/#$HOME/~}"
    fi
done
if [ "$_cz_ok" -eq 2 ]; then
    bde_ok "chezmoi 模板数据双落位（machine/dev/common/local/share：XDG 位 + 兜底位）"
else
    bde_pending "chezmoi 模板数据部分落位（不可写:$_cz_miss）——.tmpl 种子在对应上下文将无数据源"
fi
