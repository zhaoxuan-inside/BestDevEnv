#!/usr/bin/env bash
# M4: vibecoding 工具安装部署（幂等：已装则登记版本）
[ -n "${BDE_ROOT:-}" ] || BDE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$BDE_ROOT/lib/paths.sh"
source "$BDE_ROOT/lib/common.sh"
source "$BDE_ROOT/lib/ensure.sh"

TOOLS_CSV="${BDE_TOOLS:-}"
# 无清单不动手（询问开发者的硬协议：清单必须显式传入——init 交互选择或 BDE_TOOLS/--tools；独立执行同规则）
[ -n "$TOOLS_CSV" ] || { bde_skip "未选择 vibecoding 工具（BDE_TOOLS 空——后续可经 bestdevenv-dev 单独装配）"; return 0 2>/dev/null || exit 0; }
bde_info "M4 vibecoding 工具（$TOOLS_CSV）"

_have_npm() { command -v npm >/dev/null 2>&1; }

_install_tool() {
    local t=$1
    # 探测 15s / 安装 300s 超时——网络劣化时快速失败而非挂起（2026-11-07 实测 zcode --version 挂起引出）
    case "$t" in
        claude-code)
            if command -v claude >/dev/null 2>&1; then bde_skip "claude-code 已装：$(timeout 15 claude --version 2>/dev/null | head -1)"
            elif _have_npm && timeout 300 npm install -g @anthropic-ai/claude-code >/dev/null 2>&1; then bde_ok "claude-code 安装"
            else bde_pending "claude-code 安装失败（需 npm）"; fi ;;
        codex)
            if command -v codex >/dev/null 2>&1; then bde_skip "codex 已装：$(timeout 15 codex --version 2>/dev/null | head -1)"
            elif _have_npm && timeout 300 npm install -g @openai/codex >/dev/null 2>&1; then bde_ok "codex 安装"
            else bde_pending "codex 安装失败（需 npm）"; fi ;;
        gemini-cli)
            if command -v gemini >/dev/null 2>&1; then bde_skip "gemini-cli 已装：$(timeout 15 gemini --version 2>/dev/null | head -1)"
            elif _have_npm && timeout 300 npm install -g @google/gemini-cli >/dev/null 2>&1; then bde_ok "gemini-cli 安装"
            else bde_pending "gemini-cli 安装失败（需 npm）"; fi ;;
        opencode)
            # 契约位：实体 ① $DEV/apps/agent/.opencode/bin（env.sh PATH 预置 + OPENCODE_CONFIG_DIR 同指 ①）
            # installer 默认落 ~/.opencode/bin——不在契约 PATH 时 command -v 永远失败（幂等判定失效）
            local _oc="$DEV/apps/agent/.opencode/bin/opencode"
            if command -v opencode >/dev/null 2>&1 || [ -x "$_oc" ]; then
                bde_skip "opencode 已装：$(timeout 15 opencode --version 2>/dev/null | head -1 || timeout 15 "$_oc" --version 2>/dev/null | head -1)"
            elif [ -x "$HOME/.opencode/bin/opencode" ]; then
                # 已装但不在 PATH（旧默认位）：归位 ① 契约位即可，不重装
                mkdir -p "$(dirname "$_oc")"
                mv "$HOME/.opencode/bin/opencode" "$_oc" && rmdir "$HOME/.opencode/bin" 2>/dev/null
                bde_ok "opencode 归位 ① 契约位（原 ~/.opencode/bin 不在 PATH）"
            else
                # curl|bash 管道退出码取 bash——截断脚本照样 exit 0（假成功，2026-11-12 实测）：
                # 先落盘再执行，下载与执行 rc 全程真实；--no-modify-path 防 installer 写 chezmoi 托管的 shell rc
                local _ins="$DEV/tmp/opencode-install.sh"
                ensure_dir "$(dirname "$_ins")"
                if curl -fsSL --max-time 120 https://opencode.ai/install -o "$_ins" \
                   && bash "$_ins" --no-modify-path >/dev/null 2>&1; then
                    if [ -x "$HOME/.opencode/bin/opencode" ]; then
                        mkdir -p "$(dirname "$_oc")"
                        mv "$HOME/.opencode/bin/opencode" "$_oc" && rmdir "$HOME/.opencode/bin" 2>/dev/null
                    fi
                    if [ -x "$_oc" ]; then bde_ok "opencode 安装（① 契约位）"
                    else bde_pending "opencode 安装后未找到二进制（检查 installer 输出）"; fi
                else
                    bde_pending "opencode 安装失败（下载/执行失败，可重跑）"
                fi
                rm -f "$_ins"
            fi ;;
        zcode)
            if command -v zcode >/dev/null 2>&1; then bde_skip "zcode 已装：$(timeout 15 zcode --version 2>/dev/null | head -1)"
            else bde_pending "zcode 走系统安装渠道（未装）"; fi ;;
        arkcli)
            if command -v arkcli >/dev/null 2>&1; then bde_skip "arkcli 已装：$(timeout 15 arkcli --version 2>/dev/null | head -1)"
            else bde_pending "arkcli 为自有工具（未装，人工安装）"; fi ;;
        trae|trae-cn|antigravity|qoder|copilot)
            if command -v "$t" >/dev/null 2>&1; then bde_skip "$t 已装"
            else bde_pending "$t 安装方式待定（GUI 类工具人工安装）"; fi ;;
        *) bde_pending "未知工具: $t（合法集见 modules/agent/runtimes.tsv；注意 BDE_TOOLS 为逗号分隔 CSV——空格分隔会被拼成一个名字）" ;;
    esac
}

IFS=',' read -ra _tools <<< "$TOOLS_CSV"
for _t in "${_tools[@]}"; do
    _install_tool "$(echo "$_t" | tr -d ' ')"
done
