#!/usr/bin/env bash
# M4: AGENTS.md 统一构建（数据与视图分离：模板 + hosts.toml + probe → 视图）
# 正本分层（宪法 §10.9 延伸 + §20 作用域）：
#   Memory（AGENTS.md）→ ① 每机器渲染产物（含本机 probe 环境地图，不跨机器共享；可复用的是模板）
#   Skill 家族         → ③ $BDE_AGENTS_CANON/skill（config 仓库 git 版本化，push/pull 即跨机器复用）
# 接线：各工具约定路径（~/.claude/CLAUDE.md、~/.gemini/GEMINI.md 等）symlink 指向正本（runtime.sh 按注册表执行）
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

CANON_DIR="$BDE_AGENTS_LOCAL"      # ① 生成物区（AGENTS.md）；skill/mcp 正本已上移 ③（paths.sh 定义）
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

# ── 物理边界渲染（P1-3：probe 能力探测 → 事实化文本；取代旧"HGFS 后端实测"静态段）──
# 换后端不再需要人工重测改模板：M2/probe 实测 symlink/hardlink/大小写/权限/文件名长度，视图按事实渲染
_phys_date="$(date '+%F')"
_be="${BDE_SCOPE_SHARED_BACKEND:-unknown}"
if [ "${P_CAP_PROBED:-0}" = "1" ]; then
    _constraints=()
    [ "${P_CAP_SYMLINK:-0}" = "0" ]  && _constraints+=("无 symlink")
    [ "${P_CAP_HARDLINK:-0}" = "0" ] && _constraints+=("无 hardlink")
    [ "${P_CAP_CASE:-0}" = "0" ]     && _constraints+=("不区分大小写")
    [ "${P_CAP_PERM:-0}" = "0" ]     && _constraints+=("权限恒 777")
    [ "${P_CAP_NAME255:-0}" = "0" ]  && _constraints+=("文件名上限 255B")
    if [ "${#_constraints[@]}" -gt 0 ]; then
        _cl="$(printf '%s · ' "${_constraints[@]}")"; _cl="${_cl% · }"
        _PHYS_BRIEF="物理红线（能力探测 $_phys_date · 后端 $_be）：$_cl——依赖实体与私钥绝不上去；命名一律小写 kebab-case"
        _PHYS_FULL=""
        for _c in "${_constraints[@]}"; do _PHYS_FULL+="\- $_c（probe 实测）"$'\n'; done
    else
        _PHYS_BRIEF="共享盘能力（探测 $_phys_date · 后端 $_be）：symlink/hardlink/大小写/权限/长文件名均可用——依赖实体仍住 ①（跨机一致），命名仍小写 kebab-case"
        _PHYS_FULL="- 共享盘能力探测全部可用（symlink/hardlink/大小写/权限/文件名 ≥255B）"$'\n'
    fi
    _PHYS_FULL+="- 依赖实体（node_modules/venv）与私钥绝不放共享盘——住 ①（跨机一致性；bind 接回）"$'\n'
    [ "${P_CAP_NAME255:-0}" = "0" ] && _PHYS_FULL+="- 单文件名/深层路径超 255B 上限——gradle/flutter 类缓存留本机盘"$'\n'
    _PHYS_FULL+="- 命名一律小写 kebab-case"
else
    _PHYS_BRIEF="物理红线（能力未探测——共享盘当前不可写，按最保守假设）：无 symlink/不分大小写/权限 777——依赖实体与私钥绝不上去；命名一律小写 kebab-case"
    _PHYS_FULL="- 共享盘能力未探测（probe 时共享盘不可写）——按最保守假设对待：无 symlink、不区分大小写、权限 777"$'\n'
    _PHYS_FULL+="- 依赖实体（node_modules/venv）与私钥绝不放共享盘——住 ①（bind 接回）"$'\n'
    _PHYS_FULL+="- 命名一律小写 kebab-case"
fi

# ── 统一占位符渲染（AGENTS.md 与 SKILL.md 同一套；新增锚点/物理边界占位符）──
bde_tpl_render() {  # <模板内容> → stdout
    local _c="$1"
    _c="${_c//@MACHINE@/${BDE_MACHINE:-$(hostname)}}"
    _c="${_c//@OS@/$P_OS}"
    _c="${_c//@DATE@/$P_DATE}"
    _c="${_c//@ANCHORS@/$_anchors}"
    _c="${_c//@COMMON@/$COMMON}"
    _c="${_c//@LOCAL@/$LOCAL}"
    _c="${_c//@DEV@/$DEV}"
    _c="${_c//@SHARE@/$SHARE}"
    _c="${_c//@PHYSICAL@/$_PHYS_FULL}"
    _c="${_c//@PHYSICAL_BRIEF@/$_PHYS_BRIEF}"
    _c="${_c//@TOOLS_TABLE@/$_tools}"
    printf '%s' "$_c"
}

content="$(<"$TPL")"
content="$(bde_tpl_render "$content")"

mkdir -p "$CANON_DIR"
printf '%s\n' "$content" > "$CANON" && bde_ok "生成正本 ~/.config/devspace/agents/AGENTS.md"

# 家目录根的三份生成物移除（内容已由正本再生；工具路径接线统一由 runtime.sh 按注册表执行）
for _f in "$HOME/AGENTS.md" "$HOME/CLAUDE.md" "$HOME/GEMINI.md"; do
    if [ -f "$_f" ] && [ ! -L "$_f" ]; then rm -f "$_f" && bde_ok "移除家目录生成物 ${_f/#$HOME/~}"; fi
done

# ── SKILL 家族：主 Skill（调度）+ 子 Skill（单一职责），templates/skills/<name>/ 统一再生 ──
SKILLS_SRC="$BDE_ROOT/templates/skills"
SKILL_CANON_BASE="$BDE_AGENTS_CANON/skill"   # 正本 ③（config 仓库版本化，跨机器复用）
if [ -d "$SKILLS_SRC" ]; then
    mkdir -p "$SKILL_CANON_BASE"
    # 旧单体 skill 正本清理（v0.x 生成物 BestDevEnv/，已被 skills/ 家族取代）
    if [ -d "$SKILL_CANON_BASE/BestDevEnv" ] && [ ! -L "$SKILL_CANON_BASE/BestDevEnv" ]; then
        rm -rf "$SKILL_CANON_BASE/BestDevEnv" && bde_ok "清理旧单体 skill 正本 skill/BestDevEnv/"
    fi
    # 逐模板生成正本（占位符与 AGENTS.md 同一套——bde_tpl_render 统一渲染）
    for _tpl in "$SKILLS_SRC"/*/SKILL.md.tmpl; do
        [ -f "$_tpl" ] || { bde_pending "skills/ 下无模板"; break; }
        _name="$(basename "$(dirname "$_tpl")")"
        mkdir -p "$SKILL_CANON_BASE/$_name"
        _scontent="$(<"$_tpl")"
        _scontent="$(bde_tpl_render "$_scontent")"
        printf '%s\n' "$_scontent" > "$SKILL_CANON_BASE/$_name/SKILL.md" \
            && bde_ok "生成 skill: $_name（③ 版本化）" || bde_pending "skill 生成失败（③ 不可写？）: $_name"
    done
    # ── 旧 ① 正本区迁移：~/.config/devspace/agents/skill 真实目录 → 目录级 symlink → ③ ──
    # 正本上移 ③ 版本化，① 区降级为兼容接线层；diff 检测防手改正本丢失——有差异先整目录备份
    if [ -d "$CANON_DIR/skill" ] && [ ! -L "$CANON_DIR/skill" ]; then
        _migrate=1; _drift=0
        for _od in "$CANON_DIR/skill"/*/; do
            [ -d "$_od" ] || continue
            _on="$(basename "$_od")"
            cmp -s "$_od/SKILL.md" "$SKILL_CANON_BASE/$_on/SKILL.md" 2>/dev/null || { _drift=1; break; }
        done
        if [ "$_drift" = "1" ]; then
            _bk="$DEV/docs/backup/$(date +%Y%m%d)-agents-skill-old"
            mkdir -p "$DEV/docs/backup" 2>/dev/null
            if cp -r "$CANON_DIR/skill" "$_bk" 2>/dev/null; then
                bde_pending "旧 skill 正本与再生产物有差异——整目录已备份 $_bk（人工对账后可清）"
            else
                bde_pending "旧 skill 正本备份失败，跳过迁移（保留 $CANON_DIR/skill）"
                _migrate=0
            fi
        fi
        if [ "$_migrate" = "1" ]; then
            rm -rf "$CANON_DIR/skill" && ln -sfn "$SKILL_CANON_BASE" "$CANON_DIR/skill" \
                && bde_ok "旧 ① skill 正本区 → 目录级 symlink（正本住 ③ $SKILL_CANON_BASE）"
        fi
    fi
    # 接线（~/.claude/skills、~/.agents/skills、~/.hermes/skills 等）统一由 runtime.sh
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
