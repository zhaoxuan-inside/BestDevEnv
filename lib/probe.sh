#!/usr/bin/env bash
# lib/probe.sh — L1 采集器：环境事实的唯一来源（宪法 §19.5 数据/视图分层）
# 职责：只采集，不渲染。产出 schema 化 JSON 快照 → $DEV/docs/state/probe.json
# 视图（doctor/report/AGENTS/SKILL）一律消费快照，绝不自行采集。
# 用法：source 后调 bde_probe_collect（取 P_ 变量）/ bde_probe_save（落快照）；
#       直接执行：probe.sh [--json|--save|--human]

[ -n "${BDE_ROOT:-}" ] || BDE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$BDE_ROOT/lib/paths.sh"

BDE_PROBE_STATE_DIR="${BDE_PROBE_STATE_DIR:-$DEV/docs/state}"

bde_probe_collect() {
    P_OS="$(grep -m1 PRETTY_NAME /etc/os-release 2>/dev/null | cut -d'"' -f2)"
    P_OS_ID="$(. /etc/os-release 2>/dev/null; echo "${ID:-unknown}")"
    P_KERNEL="$(uname -r)"
    P_HOST="$(hostname)"
    P_USER="$(id -un)"
    P_DATE="$(date '+%Y-%m-%d %H:%M')"
    P_DISK_ROOT_USE="$(df -h / 2>/dev/null | awk 'NR==2{print $5}')"
    P_DISK_ROOT_FREE="$(df -BG / 2>/dev/null | awk 'NR==2{gsub("G","",$4);print $4}')"

    # 锚点与挂载
    P_SHARE_STATE="${BDE_SHARE_STATE:-unknown}"
    P_COMMON_WRITABLE=0; P_LOCAL_WRITABLE=0
    if [ -d "$COMMON" ] && touch "$COMMON/.bde_write_test" 2>/dev/null; then
        rm -f "$COMMON/.bde_write_test"; P_COMMON_WRITABLE=1
    fi
    if [ -d "$LOCAL" ] && touch "$LOCAL/.bde_write_test" 2>/dev/null; then
        rm -f "$LOCAL/.bde_write_test"; P_LOCAL_WRITABLE=1
    fi
    P_FSTAB_HGFS="$(grep -c 'vmhgfs-fuse' /etc/fstab 2>/dev/null || echo 0)"
    P_LAYER_COMMON="$(mount 2>/dev/null | grep -c " $COMMON ")"
    P_LAYER_LOCAL="$(mount 2>/dev/null | grep -c " $LOCAL ")"

    # 配置 / 骨架 / 接线
    P_CONFIG_OK=0; { [ -f "$COMMON/config/.chezmoiignore" ] || [ -f "$HOME/.config/devspace/env.sh" ]; } && P_CONFIG_OK=1
    P_ENV_SH=0; [ -f "$HOME/.config/devspace/env.sh" ] && P_ENV_SH=1
    P_XDG_DOC=""; grep -m1 'XDG_DOCUMENTS_DIR' "$HOME/.config/user-dirs.dirs" 2>/dev/null | grep -q 'Share/Local' && P_XDG_DOC="重定向"
    P_AGENTS_MD=0; [ -f "$HOME/.config/devspace/agents/AGENTS.md" ] && P_AGENTS_MD=1
    P_SKELETON=0; [ -d "$COMMON/data/models" ] && [ -d "$LOCAL/build" ] && P_SKELETON=1
    P_IDE_OK=0; { [ -f "$HOME/.config/Code/User/settings.json" ] && [ -f "$COMMON/config/ide/vscode/base.txt" ] \
        && command -v code >/dev/null 2>&1; } && P_IDE_OK=1

    # Runtime 统一接线（M4 扩展：记忆/MCP/Skill 三正本 + ~/.agents 枢纽兜底）
    P_MCP_CANON=0; [ -f "$HOME/.config/devspace/agents/mcp.json" ] && P_MCP_CANON=1
    P_RUNTIME_OK=0
    if [ "$P_AGENTS_MD" = "1" ] && [ "$P_MCP_CANON" = "1" ] \
       && [ -L "$HOME/.agents/mcp.json" ] \
       && [ -L "$HOME/.agents/skills/bestdevenv" ]; then
        P_RUNTIME_OK=1
    fi

    # 配置治理漂移（M1.6：cfg-map 逐项；正本缺失不计漂移——只提示未收编）
    P_CFG_DRIFT=0
    if [ -f "$BDE_ROOT/modules/cfg/cfg-map.tsv" ]; then
        while IFS='|' read -r _cn _cc _cs _cd _cm _cr _cnote; do
            [ -n "$_cn" ] || continue
            _cs="${_cs/#\$COMMON/$COMMON}"; _cd="${_cd/#\$HOME/$HOME}"
            [ -f "$_cs" ] || continue
            case "$_cm" in
                append)
                    while IFS= read -r _cl; do
                        [ -n "$_cl" ] || continue
                        grep -qF -- "$_cl" "$_cd" 2>/dev/null || { P_CFG_DRIFT=$((P_CFG_DRIFT+1)); break; }
                    done < "$_cs" ;;
                *) [ -f "$_cd" ] && ! cmp -s "$_cs" "$_cd" && P_CFG_DRIFT=$((P_CFG_DRIFT+1)) ;;
            esac
        done < <(grep -v '^[[:space:]#]' "$BDE_ROOT/modules/cfg/cfg-map.tsv" | grep -v '^[[:space:]]*$')
    fi
    # config 事实源仓库干净度（未提交/未收编变更）
    P_CFG_DIRTY=0
    if command -v git >/dev/null 2>&1 && [ -d "$COMMON/config/.git" ]; then
        [ -n "$(git -C "$COMMON/config" status --porcelain 2>/dev/null | head -1)" ] && P_CFG_DIRTY=1
    fi

    # 内核参数
    P_INOTIFY_W="$(cat /proc/sys/fs/inotify/max_user_watches 2>/dev/null || echo 0)"
    P_INOTIFY_OK=0; [ "${P_INOTIFY_W:-0}" -ge 524288 ] 2>/dev/null && P_INOTIFY_OK=1

    # 工具链版本表（存在才列；15s 超时——网络劣化时 CLI 版本探测可能挂起）
    P_TOOL_ROWS=""
    _v() {
        # 落盘捕获而非管道：工具派生的子进程（如 zcode crash-capture）会持有 stdout 管道，
        # head 等 EOF 永久阻塞——timeout 只杀父进程救不了管道（2026-11-08 实测挂起）
        local c=$1; shift; local out f
        f="$(mktemp)"
        if command -v timeout >/dev/null 2>&1; then
            timeout -k 2 15 "$c" "$@" >"$f" 2>/dev/null
        else
            "$c" "$@" >"$f" 2>/dev/null
        fi
        out="$(head -1 "$f" 2>/dev/null)"
        rm -f "$f"
        [ -n "$out" ] && printf "%s|%s\n" "$c" "$out"
    }
    P_TOOL_ROWS+="$( _v git    --version )"$'\n'
    P_TOOL_ROWS+="$( _v docker --version )"$'\n'
    P_TOOL_ROWS+="$( _v node   --version )"$'\n'
    P_TOOL_ROWS+="$( _v npm    --version )"$'\n'
    P_TOOL_ROWS+="$( _v python3 --version )"$'\n'
    P_TOOL_ROWS+="$( _v uv     --version )"$'\n'
    P_TOOL_ROWS+="$( _v cargo  --version )"$'\n'
    P_TOOL_ROWS+="$( _v go     version )"$'\n'
    P_TOOL_ROWS+="$( _v flutter --version 2>/dev/null | head -1 )"$'\n'
    P_TOOL_ROWS+="$( _v mise   --version 2>/dev/null | head -1 )"$'\n'
    P_TOOL_ROWS+="$( _v chezmoi --version 2>/dev/null | head -1 )"$'\n'
    P_TOOL_ROWS+="$( _v starship --version 2>/dev/null | head -1 )"$'\n'
    P_TOOL_ROWS+="$( _v code --version 2>/dev/null | head -1 )"$'\n'
    P_TOOL_ROWS+="$( _v claude   --version 2>/dev/null | head -1 )"$'\n'
    P_TOOL_ROWS+="$( _v codex    --version 2>/dev/null | head -1 )"$'\n'
    P_TOOL_ROWS+="$( _v gemini  --version 2>/dev/null | head -1 )"$'\n'
    P_TOOL_ROWS+="$( _v opencode --version 2>/dev/null | head -1 )"$'\n'
    P_TOOL_ROWS+="$( _v arkcli  --version 2>/dev/null | head -1 )"$'\n'
    P_TOOL_ROWS+="$( _v zcode  --version 2>/dev/null | head -1 )"$'\n'
    P_TOOL_ROWS+="$( _v trae  --version 2>/dev/null | head -1 )"$'\n'
    P_TOOL_ROWS+="$( _v antigravity --version 2>/dev/null | head -1 )"$'\n'
    P_TOOL_ROWS+="$( _v qoder --version 2>/dev/null | head -1 )"$'\n'
    P_TOOL_ROWS+="$( _v copilot --version 2>/dev/null | head -1 )"$'\n'
    P_TOOL_ROWS="$(printf '%s' "$P_TOOL_ROWS" | grep -v '^$')"
}

bde_probe_export() {  # 导出全部事实为环境变量（JSON 构建器消费）
    local v
    for v in ${!P_@}; do export "$v"; done
}

bde_probe_json() {  # L2 模型：schema 化 JSON（唯一机器接口）
    bde_probe_export
    python3 - <<'PYEOF'
import os, json, sys

def i(k, d=0):
    try:
        return int(os.environ.get(k, d) or d)
    except ValueError:
        return d

p = {k[2:]: v for k, v in os.environ.items() if k.startswith("P_")}
tools = {}
for line in (p.get("TOOL_ROWS") or "").splitlines():
    if "|" in line:
        t, v = line.split("|", 1)
        tools[t.strip()] = v.strip()

doc = {
    "schema": "bde.probe/1",
    "machine": p.get("HOST", ""),
    "os": p.get("OS", ""),
    "os_id": p.get("OS_ID", ""),
    "kernel": p.get("KERNEL", ""),
    "user": p.get("USER", ""),
    "date": p.get("DATE", ""),
    "anchors": {
        "dev": os.environ.get("DEV", ""),
        "share": os.environ.get("SHARE", ""),
        "common": os.environ.get("COMMON", ""),
        "local": os.environ.get("LOCAL", ""),
        "state": p.get("SHARE_STATE", "unknown"),
    },
    "facts": {
        "common_writable": i("P_COMMON_WRITABLE"),
        "local_writable": i("P_LOCAL_WRITABLE"),
        "fstab_backend": i("P_FSTAB_HGFS"),
        "layer_common": i("P_LAYER_COMMON"),
        "layer_local": i("P_LAYER_LOCAL"),
        "config_ready": i("P_CONFIG_OK"),
        "env_sh_applied": i("P_ENV_SH"),
        "skeleton_ready": i("P_SKELETON"),
        "agents_md": i("P_AGENTS_MD"),
        "mcp_canon": i("P_MCP_CANON"),
        "runtime_wired": i("P_RUNTIME_OK"),
        "cfg_drift": i("P_CFG_DRIFT"),
        "cfg_dirty": i("P_CFG_DIRTY"),
        "ide_ready": i("P_IDE_OK"),
        "xdg_redirect": 1 if p.get("XDG_DOC") else 0,
        "inotify_ok": i("P_INOTIFY_OK"),
    },
    "values": {
        "disk_root_used": p.get("DISK_ROOT_USE", ""),
        "disk_root_free_g": i("P_DISK_ROOT_FREE"),
        "inotify_watches": i("P_INOTIFY_W"),
        "xdg_doc": p.get("XDG_DOC", ""),
    },
    "tools": tools,
}
json.dump(doc, sys.stdout, ensure_ascii=False, indent=2)
print()
PYEOF
}

bde_probe_save() {  # 落快照（原子写）——视图从这里读
    bde_probe_collect
    mkdir -p "$BDE_PROBE_STATE_DIR" 2>/dev/null
    local f="$BDE_PROBE_STATE_DIR/probe.json"   # 分两行声明：同语句内 $f 展开在赋值前，set -u 下会 unbound
    local t="$f.tmp"
    bde_probe_json > "$t" && mv "$t" "$f" && printf '%s\n' "$f"
}

bde_probe_print() {  # 人类速览（正式视图在 doctor/report）
    echo "机器: $P_HOST ｜ $P_OS (kernel $P_KERNEL) ｜ probe $P_DATE"
    echo "锚点: $SHARE（$P_SHARE_STATE）｜ Common可写:$P_COMMON_WRITABLE Local可写:$P_LOCAL_WRITABLE ｜ 根盘: $P_DISK_ROOT_USE（剩 ${P_DISK_ROOT_FREE}G）"
    printf '%s\n' "$P_TOOL_ROWS" | while IFS='|' read -r t v; do
        [ -n "$t" ] && printf "  %-10s %s\n" "$t" "$v"
    done
}

# 直接执行：probe.sh [--json|--save|--human]
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    case "${1:-}" in
        --json)        bde_probe_collect; bde_probe_json ;;
        --save)        bde_probe_save ;;
        --human|"")    bde_probe_collect; bde_probe_print ;;
        *) echo "用法: probe.sh [--json|--save|--human]"; exit 2 ;;
    esac
fi
