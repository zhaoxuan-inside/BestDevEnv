#!/usr/bin/env bash
# M4: AGENTS.md 统一构建（数据与视图分离：模板 + hosts.toml + probe → 视图）
# 正本：~/.config/devspace/agents/AGENTS.md（应用层规范位置）
# 接线：各工具约定路径（~/.claude/CLAUDE.md、~/.gemini/GEMINI.md、~/.codex/AGENTS.md 等）symlink 指向正本
[ -n "${BDE_ROOT:-}" ] || BDE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$BDE_ROOT/lib/paths.sh"
source "$BDE_ROOT/lib/common.sh"
source "$BDE_ROOT/lib/ensure.sh"
source "$BDE_ROOT/lib/probe.sh"

bde_info "M4 AGENTS.md 统一构建（指令视图：消费 probe.json 快照）"
bde_probe_collect             # P_* 事实进当前 shell（占位符渲染用；子命令替换会丢变量）
bde_probe_save >/dev/null     # 落快照（内部幂等再采集）
F_PROBE_JSON="${BDE_PROBE_STATE_DIR:-$DEV/docs/state}/probe.json"

TPL="$BDE_ROOT/templates/AGENTS.md.tmpl"
if [ ! -f "$TPL" ]; then bde_pending "AGENTS.md 模板缺失：$TPL"; return 0; fi

CANON_DIR="$HOME/.config/devspace/agents"
CANON="$CANON_DIR/AGENTS.md"

_anchors="| 档 | 作用域 | 路径 |
|---|---|---|
| ① DevEnv | user 用户级（本机本用户） | \`$DEV\` |
| ② Local | host 主机级（同机多用户） | \`$LOCAL\` |
| ③ Common | shared 跨主机级（多机多用户） | \`$COMMON\` |"

# 工具表从 probe.json 快照渲染（视图不采集——宪法 §19.5）
_tools="$(BDE_TOOLS_JSON="$F_PROBE_JSON" python3 -c '
import json, sys, os
t = json.load(open(os.environ["BDE_TOOLS_JSON"]))["tools"]
sys.stdout.write("\n".join(f"| {k} | {v} |" for k, v in sorted(t.items())))
')"

content="$(<"$TPL")"
content="${content//@MACHINE@/${BDE_MACHINE:-$(hostname)}}"
content="${content//@OS@/$P_OS}"
content="${content//@DATE@/$P_DATE}"
content="${content//@ANCHORS@/$_anchors}"
content="${content//@TOOLS_TABLE@/$_tools}"
content="${content//@RULES@/见上方放置规则与物理边界}"

mkdir -p "$CANON_DIR"
printf '%s\n' "$content" > "$CANON" && bde_ok "生成正本 ~/.config/devspace/agents/AGENTS.md"

# 家目录根的三份生成物移除（内容已由正本再生；工具路径接线统一由 runtime.sh 按注册表执行）
for _f in "$HOME/AGENTS.md" "$HOME/CLAUDE.md" "$HOME/GEMINI.md"; do
    if [ -f "$_f" ] && [ ! -L "$_f" ]; then rm -f "$_f" && bde_ok "移除家目录生成物 ${_f/#$HOME/~}"; fi
done

# ── SKILL 家族：主 Skill（调度）+ 子 Skill（单一职责），templates/skills/<name>/ 统一再生 ──
SKILLS_SRC="$BDE_ROOT/templates/skills"
SKILL_CANON_BASE="$CANON_DIR/skill"
if [ -d "$SKILLS_SRC" ]; then
    # 旧单体 skill 正本清理（v0.x 生成物 BestDevEnv/，已被 skills/ 家族取代）
    if [ -d "$SKILL_CANON_BASE/BestDevEnv" ] && [ ! -L "$SKILL_CANON_BASE/BestDevEnv" ]; then
        rm -rf "$SKILL_CANON_BASE/BestDevEnv" && bde_ok "清理旧单体 skill 正本 skill/BestDevEnv/"
    fi
    # 逐模板生成正本（占位符与 AGENTS.md 同一套）
    for _tpl in "$SKILLS_SRC"/*/SKILL.md.tmpl; do
        [ -f "$_tpl" ] || { bde_pending "skills/ 下无模板"; break; }
        _name="$(basename "$(dirname "$_tpl")")"
        mkdir -p "$SKILL_CANON_BASE/$_name"
        _scontent="$(<"$_tpl")"
        _scontent="${_scontent//@MACHINE@/${BDE_MACHINE:-$(hostname)}}"
        _scontent="${_scontent//@OS@/$P_OS}"
        _scontent="${_scontent//@DATE@/$P_DATE}"
        _scontent="${_scontent//@ANCHORS@/$_anchors}"
        printf '%s\n' "$_scontent" > "$SKILL_CANON_BASE/$_name/SKILL.md" \
            && bde_ok "生成 skill: $_name"
    done
    # 接线（~/.claude/skills、~/.agents/skills、~/.zcode/skills 等）统一由 runtime.sh
    # 按 modules/agent/runtimes.tsv 注册表执行——本脚本只负责正本再生
else
    bde_pending "skill 模板目录缺失：$SKILLS_SRC"
fi

# ── 生成指纹落盘（doctor 巡检部署层代际：正本生成时的 templates 哈希 vs 当前哈希）──
mkdir -p "$DEV/docs/state" 2>/dev/null
{
    echo "templates_hash=$(bde_templates_hash)"
    echo "bde_commit=$(git -C "$BDE_ROOT" rev-parse --short HEAD 2>/dev/null || echo none)"
    echo "machine=${BDE_MACHINE:-$(hostname)}"
    echo "date=$(date '+%F %T')"
} > "$DEV/docs/state/gen-fingerprint" && bde_ok "生成指纹 → $DEV/docs/state/gen-fingerprint（doctor 巡检代际）"
