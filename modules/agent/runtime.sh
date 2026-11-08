#!/usr/bin/env bash
# modules/agent/runtime.sh — Runtime 统一接线器（M4 扩展，依宪法 §10.9 延伸）
# 契约：所有 vibecoding 工具 = 可替换 Runtime；记忆/Skill/MCP/会话四域由本工程统一承载
#   记忆   正本 ~/.config/devspace/agents/AGENTS.md → 各工具约定路径 symlink
#   Skill  正本 ~/.config/devspace/agents/skill/<name>/ → 各工具 skills 目录逐项 symlink
#   MCP    正本 ~/.config/devspace/agents/mcp.json → 各工具投影（工具本地条目永不覆盖）
#   会话   工具私有，只登记调查（devenv runtime sessions）；跨工具长任务续做走 devenv orch
# 用法：source（init M4:runtime）→ 全量接线；独立执行 → 子命令（见 usage）
[ -n "${BDE_RUNTIME_LOADED:-}" ] && return 0 2>/dev/null || true
BDE_RUNTIME_LOADED=1

[ -n "${BDE_ROOT:-}" ] || BDE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$BDE_ROOT/lib/paths.sh"
source "$BDE_ROOT/lib/common.sh"
source "$BDE_ROOT/lib/ensure.sh"

REG="$BDE_ROOT/modules/agent/runtimes.tsv"
CANON_DIR="$HOME/.config/devspace/agents"
CANON_MEM="$CANON_DIR/AGENTS.md"
CANON_MCP="$CANON_DIR/mcp.json"
SKILL_CANON_BASE="$CANON_DIR/skill"
MCP_SEED="$BDE_ROOT/modules/agent/mcp.seed.json"

_rt_usage() {
    cat <<'EOF'
用法: runtime.sh list|wire|mcp sync|mcp list|sessions|launch <tool> [args...]
  list        全 runtime 接线现状视图
  wire        幂等接线（memory + skills + mcp）
  mcp sync    MCP 正本 → 各工具投影（工具本地条目保留）
  mcp list    MCP 正本内容
  sessions    会话库调查（只读）
  launch      统一启动：source env.sh 后 exec 工具（vibe 入口）
EOF
}

# ── 注册表 ────────────────────────────────────────────────────────────────
_reg_rows() { grep -v '^[[:space:]#]' "$REG" 2>/dev/null | grep -v '^[[:space:]]*$'; }

# 存在性判定：binary 命中 或 任一域路径已存在（"$1"=binary，"$2"=以|拼接的路径，支持 $HOME 前缀）
_rt_present() {
    local bin="$1" paths="$2" p _ps
    command -v "$bin" >/dev/null 2>&1 && return 0
    IFS='|' read -ra _ps <<<"$paths"
    for p in "${_ps[@]}"; do
        p="${p/#\$HOME/$HOME}"
        [ -n "$p" ] && { [ -e "$p" ] || [ -L "$p" ]; } && return 0
    done
    return 1
}

# ── 记忆接线 ──────────────────────────────────────────────────────────────
_rt_wire_memory() {
    local name="$1" mem="${2/#\$HOME/$HOME}"
    [ -n "$mem" ] || return 0
    [ -f "$CANON_MEM" ] || { bde_pending "$name 记忆正本缺失（先跑 M4:agents-md）"; return 0; }
    ensure_dir "$(dirname "$mem")" || { bde_fail "$name 记忆目录不可建：$mem"; return 0; }
    if [ -f "$mem" ] && [ ! -L "$mem" ]; then
        ensure_backup "$mem"
        bde_pending "$mem 已有真实内容（已备份）——人工合并后替换为 symlink"
        return 0
    fi
    ensure_symlink "$mem" "$CANON_MEM"
}

# ── Skill 接线（逐 skill symlink；正本由 agents-md.sh 再生）────────────────
_rt_wire_skills() {
    local name="$1" sdir="${2/#\$HOME/$HOME}" _n _dir
    [ -n "$sdir" ] || return 0
    [ -d "$SKILL_CANON_BASE" ] || { bde_pending "$name skill 正本缺失（先跑 M4:agents-md）"; return 0; }
    ensure_dir "$sdir" || { bde_fail "$name skills 目录不可建：$sdir"; return 0; }
    for _dir in "$SKILL_CANON_BASE"/*/; do
        [ -d "$_dir" ] || continue
        _n="$(basename "$_dir")"
        if [ -e "$sdir/$_n" ] && [ ! -L "$sdir/$_n" ]; then
            bde_pending "$sdir/$_n 已有真实内容——人工确认后替换为 symlink"
            continue
        fi
        ensure_symlink "$sdir/$_n" "$SKILL_CANON_BASE/$_n"
    done
}

# ── MCP：正本播种 + 枢纽兜底 + 各工具投影 ─────────────────────────────────
_rt_mcp_seed() {
    if [ ! -f "$CANON_MCP" ]; then
        ensure_dir "$CANON_DIR" && cp "$MCP_SEED" "$CANON_MCP" \
            && bde_ok "MCP 正本播种 ~/.config/devspace/agents/mcp.json"
    fi
    # ~/.agents/mcp.json 兜底接线：zcode 兜底读取 + arkcli 枢纽（agent-standard 惯例）
    ensure_dir "$HOME/.agents"
    ensure_symlink "$HOME/.agents/mcp.json" "$CANON_MCP"
}

_mcp_count() {
    python3 -c 'import json,sys
try: print(len(json.load(open(sys.argv[1])).get("mcpServers",{})))
except Exception: print(0)' "$CANON_MCP" 2>/dev/null || echo 0
}

_mcp_list() {
    local n; n="$(_mcp_count)"
    bde_info "MCP 正本：$CANON_MCP（$n 个 server）"
    [ "$n" -eq 0 ] && bde_info "（空——编辑正本加入 server 后 devenv runtime mcp sync 投影）"
    python3 -c 'import json,sys
try:
    d=json.load(open(sys.argv[1])).get("mcpServers",{})
    for k,v in d.items():
        if "url" in v: print(f"  {k}  remote  {v[\"url\"]}")
        else: print(f"  {k}  {v.get(\"command\",\"\")} {\" \".join(v.get(\"args\",[]))}")
except Exception: pass' "$CANON_MCP" 2>/dev/null
}

# 按工具格式转换正本条目 → name<TAB>json 行文件（$1=格式 $2=输出文件）
_mcp_convert() {
    python3 - "$CANON_MCP" "$1" "$2" <<'PY'
import json,sys
src,fmt,out=sys.argv[1],sys.argv[2],sys.argv[3]
try: servers=json.load(open(src)).get("mcpServers",{})
except Exception: servers={}
res={}
for n,v in servers.items():
    if fmt in ("claude","gemini","copilot"):
        res[n]=v
    elif fmt=="opencode":
        if "url" in v:
            res[n]={"type":"remote","url":v["url"],"enabled":True}
        else:
            e={"type":"local","command":[v.get("command","")]+list(v.get("args",[])),"enabled":True}
            if v.get("env"): e["environment"]=v["env"]
            res[n]=e
with open(out,"w") as f:
    for n,v in res.items(): f.write(f"{n}\t{json.dumps(v,ensure_ascii=False)}\n")
PY
}

# JSON 深路径合并（薄包装：公共原语 ensure_json_merge 在 lib/ensure.sh；此处仅记账）
_json_merge() {
    local f="$1" key="$2"
    if ensure_json_merge "$@"; then
        bde_ok "MCP 投影 ${f/#$HOME/~}（键 $key）"
    else
        bde_fail "JSON 合并失败：$f（该文件未改动）"
    fi
}

# codex：TOML 托管块（BEGIN/END 之间由本工程再生；工具本地条目在块外不动）
_codex_mcp() {
    local f="$HOME/.codex/config.toml" tmp
    local begin="# BEGIN BestDevEnv MCP（托管块：canonical ~/.config/devspace/agents/mcp.json → devenv runtime mcp sync 再生）"
    local end="# END BestDevEnv MCP"
    ensure_dir "$HOME/.codex" || { bde_fail "codex 目录不可建"; return 0; }
    tmp="$(mktemp)"
    if [ -f "$f" ]; then
        awk -v b="$begin" -v e="$end" 'index($0,b)==1{skip=1;next} index($0,e)==1{skip=0;next} !skip' "$f" > "$tmp"
    fi
    { cat "$tmp"; echo "$begin"
      python3 - "$CANON_MCP" <<'PY'
import json,sys
try: servers=json.load(open(sys.argv[1])).get("mcpServers",{})
except Exception: servers={}
for n,v in servers.items():
    if "url" in v:
        print(f"# [mcp_servers.{n}] 远程型条目——codex 适配待定，未投影"); continue
    print(f"[mcp_servers.{n}]")
    print(f'command = {json.dumps(v.get("command",""))}')
    if v.get("args"): print(f"args = {json.dumps(v['args'],ensure_ascii=False)}")
    if v.get("env"):
        env=",".join(f'{json.dumps(k)} = {json.dumps(val)}' for k,val in v["env"].items())
        print(f"env = {{ {env} }}")
PY
      echo "$end"
    } > "$f.new" && mv "$f.new" "$f"
    rm -f "$tmp"
    bde_ok "MCP 投影 ~/.codex/config.toml（TOML 托管块）"
}

_rt_mcp_sync() {
    _rt_mcp_seed
    local n; n="$(_mcp_count)"
    bde_info "MCP 投影：正本 $CANON_MCP（$n 个 server）→ 各工具"
    local T; T="$(mktemp -d)"
    mapfile -t _rows < <(_reg_rows)
    local _r name bin mem sk mc sess p
    for _r in "${_rows[@]}"; do
        IFS='|' read -r name bin _inst mem sk mc sess _note <<<"$_r"
        [ -n "$mc" ] || continue
        p="${mc/#\$HOME/$HOME}"
        _rt_present "$bin" "$mem|$sk|$mc|$sess" || continue
        case "$name" in
            claude-code) _mcp_convert claude "$T/c"; _json_merge "$HOME/.claude.json" mcpServers "$T/c" ;;
            codex)       _codex_mcp ;;
            gemini-cli)  _mcp_convert gemini "$T/g"; _json_merge "$HOME/.gemini/settings.json" mcpServers "$T/g" ;;
            opencode)    _mcp_convert opencode "$T/o"; _json_merge "$HOME/.config/opencode/opencode.json" mcp "$T/o" ;;
            copilot)     _mcp_convert copilot "$T/cp"; _json_merge "$HOME/.copilot/mcp-config.json" mcpServers "$T/cp" ;;
            zcode)
                # 正本已由 ~/.agents/mcp.json 兜底 symlink 接入；仅当工具配置已有本地 servers 时受控合并
                local zf="$HOME/.zcode/cli/config.json"
                if [ -f "$zf" ] && [ "$(python3 -c 'import json,sys
try: print(len(json.load(open(sys.argv[1])).get("mcp",{}).get("servers",{})))
except Exception: print(0)' "$zf" 2>/dev/null || echo 0)" -gt 0 ]; then
                    _mcp_convert claude "$T/z"; _json_merge "$zf" mcp.servers "$T/z"
                else
                    bde_skip "zcode MCP：config.json 无本地 servers（走 ~/.agents/mcp.json 兜底，不动工具配置）"
                fi ;;
            arkcli)      bde_skip "arkcli MCP：走 ~/.agents/mcp.json 枢纽 symlink" ;;
            *)           bde_pending "MCP 投影适配待定：$name（登记）" ;;
        esac
    done
    rm -rf "$T"
    [ "$n" -eq 0 ] && bde_info "正本为空：本次仅枢纽接线，未写任何工具配置"
}

# ── 会话调查（只读；工具私有，不迁移不清理）────────────────────────────────
_rt_sessions() {
    bde_info "会话库调查（只读；治理政策见 \$COMMON/config/data/home-map.tsv）"
    mapfile -t _rows < <(_reg_rows)
    local _r name sess p
    for _r in "${_rows[@]}"; do
        IFS='|' read -r name _bin _inst _mem _sk _mc sess _note <<<"$_r"
        [ -n "$sess" ] || continue
        p="${sess/#\$HOME/$HOME}"
        [ -e "$p" ] || continue
        printf "  %-12s %8s  %s\n" "$name" "$(du -sh "$p" 2>/dev/null | cut -f1)" "$p"
    done
    bde_info "跨工具长任务续做一律走 devenv orch（journal：\$DEV/docs/progress/orch-*.md）"
}

# ── 现状视图 ──────────────────────────────────────────────────────────────
_rt_list() {
    _rt_mcp_seed >/dev/null 2>&1
    local n; n="$(_mcp_count)"
    bde_info "Runtime 接线现状（正本：记忆 $CANON_MEM ｜ MCP $CANON_MCP=$n ｜ Skill $SKILL_CANON_BASE）"
    printf "  %-12s %-4s %-14s %-14s %-10s %s\n" "RUNTIME" "状态" "记忆" "Skill" "MCP" "会话"
    mapfile -t _rows < <(_reg_rows)
    local _r name bin mem sk mc sess p st ms ss
    for _r in "${_rows[@]}"; do
        IFS='|' read -r name bin _inst mem sk mc sess _note <<<"$_r"
        _rt_present "$bin" "$mem|$sk|$mc|$sess" && st="✓装" || st="—缺"
        p="${mem/#\$HOME/$HOME}"
        if [ -n "$mem" ]; then
            if [ -L "$p" ]; then ms="→正本"; elif [ -f "$p" ]; then ms="真实文件"; else ms="未接"; fi
        else ms="-"; fi
        p="${sk/#\$HOME/$HOME}"
        if [ -n "$sk" ]; then
            if [ -d "$p" ]; then
                ss="$(find "$p" -maxdepth 1 -type l 2>/dev/null | wc -l)链"
            else ss="未接"; fi
        else ss="-"; fi
        p="${mc/#\$HOME/$HOME}"
        [ -n "$mc" ] && { [ -e "$p" ] || [ -L "$p" ]; } && mcst="就绪" || mcst="-"
        p="${sess/#\$HOME/$HOME}"
        [ -n "$sess" ] && [ -e "$p" ] && sst="$(du -sh "$p" 2>/dev/null | cut -f1)" || sst="-"
        printf "  %-12s %-4s %-14s %-14s %-10s %s\n" "$name" "$st" "$ms" "$ss" "$mcst" "$sst"
    done
    bde_info "接线动作：devenv runtime wire（幂等）｜MCP 投影：devenv runtime mcp sync"
}

# ── 全量接线（init sourced 入口）─────────────────────────────────────────
_rt_wire_all() {
    bde_info "M4 Runtime 统一接线（记忆 / Skill / MCP / 会话契约）"
    [ -f "$REG" ] || { bde_pending "runtime 注册表缺失：$REG"; return 0; }
    _rt_mcp_seed
    mapfile -t _rows < <(_reg_rows)
    local _r name bin inst mem sk mc sess note
    for _r in "${_rows[@]}"; do
        IFS='|' read -r name bin inst mem sk mc sess note <<<"$_r"
        if ! _rt_present "$bin" "$mem|$sk|$mc|$sess"; then
            bde_skip "runtime 未装，跳过 $name（注册表在册）"
            continue
        fi
        _rt_wire_memory "$name" "$mem"
        _rt_wire_skills "$name" "$sk"
    done
    _rt_mcp_sync
    bde_info "会话契约：各工具会话库私有（devenv runtime sessions 调查）；跨工具续做走 devenv orch"
}

# ── 统一启动（vibe 入口）──────────────────────────────────────────────────
_rt_launch() {
    local t="${1:-}"
    [ -n "$t" ] || { _rt_usage; return 2; }
    shift
    local b; b="$(_reg_rows | awk -F'|' -v t="$t" '$1==t{print $2; exit}')"
    [ -n "$b" ] || b="$t"
    if command -v "$b" >/dev/null 2>&1; then
        [ -f "$HOME/.config/devspace/env.sh" ] && . "$HOME/.config/devspace/env.sh"
        exec "$b" "$@"
    fi
    bde_fail "runtime 未找到：$t（devenv runtime list 查看；注册表 $REG）"
    return 1
}

# ── 入口 ─────────────────────────────────────────────────────────────────
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    _cmd="${1:-list}"; [ $# -gt 0 ] && shift
    case "$_cmd" in
        list)     _rt_list ;;
        wire)     _rt_wire_all ;;
        mcp)      case "${1:-sync}" in
                      sync) shift 2>/dev/null; _rt_mcp_sync ;;
                      list) shift 2>/dev/null; _mcp_list ;;
                      *) _rt_usage; exit 2 ;;
                  esac ;;
        sessions) _rt_sessions ;;
        launch)   _rt_launch "$@" ;;
        *)        _rt_usage; exit 2 ;;
    esac
else
    _rt_wire_all
fi
