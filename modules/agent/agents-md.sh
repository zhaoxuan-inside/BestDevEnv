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

bde_info "M4 AGENTS.md 统一构建（指令视图：消费 probe.json 快照——纯视图零采集，§19.5）"
bde_probe_save >/dev/null     # 采集+落快照（唯一采集入口；渲染一律取自快照文件）
F_PROBE_JSON="${BDE_PROBE_STATE_DIR:-$DEV/docs/state}/probe.json"

# 物理边界事实从快照渲染（曾从活采集的 P_* shell 变量渲染——同一进程两次采集，结构上是旁路）。
# 快照只出"原料"（probed/backend/constraints），成句在 bash 侧做——日期要冻结（见下），句子模板只留一处。
# ⚠ 历史缺陷（2026-11-12 实证）：旧实现把输出路径变量 full 在 python 里复用为文本内容，
#   open(full,"w") 拿整段文本当文件名 → 崩溃 → date 文件缺失 → cat 报错、@DATE@ 渲染为空。
_phys_dir="$(mktemp -d "${TMPDIR:-/tmp}/bde-phys.XXXXXX")"
BDE_PROBE_JSON="$F_PROBE_JSON" BDE_PHYS_DIR="$_phys_dir" python3 - <<'PY'
import json, os
d = json.load(open(os.environ["BDE_PROBE_JSON"]))
caps, be = d["share_caps"], d["storage"]["backend_common"]
pd = os.environ["BDE_PHYS_DIR"]
def w(name, text):
    open(os.path.join(pd, name), "w").write(text)
cons = []
if caps["probed"] == 1:
    if not caps["symlink"]:        cons.append("无 symlink")
    if not caps["hardlink"]:       cons.append("无 hardlink")
    if not caps["case_sensitive"]: cons.append("不区分大小写")
    if not caps["perm"]:           cons.append("权限恒 777")
    if not caps["name255"]:        cons.append("文件名上限 255B")
w("probed", str(caps["probed"]))
w("backend", be)
w("constraints", "\n".join(cons) + ("\n" if cons else ""))
w("os", d.get("os", ""))
PY
_p_probed="$(cat "$_phys_dir/probed" 2>/dev/null || echo 0)"
_be="$(cat "$_phys_dir/backend" 2>/dev/null || echo unknown)"
P_OS="$(cat "$_phys_dir/os" 2>/dev/null)"
P_DATE="$(date '+%F %T')"   # @DATE@ 仅 AGENTS.md（① 每机器生成物）使用——SKILL 模板已除名（日期进 ③ 正文=每次 gen 提交噪音）
_constraints=()
while IFS= read -r _c; do [ -n "$_c" ] && _constraints+=("$_c"); done < "$_phys_dir/constraints"
rm -rf "$_phys_dir"

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

# ── 物理边界渲染（P1-3：probe 能力探测 → 事实化文本）──
# 换后端不再需要人工重测改模板：probe 实测 symlink/hardlink/大小写/权限/文件名长度，视图按事实渲染。
# 日期冻结（gen 幂等）：日期戳渲染进 ③ SKILL 正文（@PHYSICAL_BRIEF@），曾致跨日 gen 产生
# "纯日期 diff"提交噪音（2026-11-12→13 实证）——日期只在能力集合/后端变化时更新，否则沿用 ① state 原值。
_caps_key="probed=$_p_probed backend=$_be $(printf '%s ' "${_constraints[@]}")"
_caps_state="$DEV/docs/state/share-caps-date"
mkdir -p "$(dirname "$_caps_state")" 2>/dev/null
_old_key=""; _old_date=""
[ -f "$_caps_state" ] && { _old_key="$(sed -n 's/^caps_key=//p' "$_caps_state" | head -1)"; _old_date="$(sed -n 's/^date=//p' "$_caps_state" | head -1)"; }
_phys_date="$(date '+%F')"
if [ -n "$_old_date" ] && [ "$_old_key" = "$_caps_key" ]; then
    _phys_date="$_old_date"
else
    printf 'caps_key=%s\ndate=%s\n' "$_caps_key" "$_phys_date" > "$_caps_state"
fi
if [ "$_p_probed" = "1" ]; then
    if [ "${#_constraints[@]}" -gt 0 ]; then
        _cl="$(printf '%s · ' "${_constraints[@]}")"; _cl="${_cl% · }"
        _PHYS_BRIEF="物理红线（能力探测 $_phys_date · 后端 $_be）：$_cl——依赖实体与私钥绝不上去；文件/代码命名小写 kebab-case；①②③ 自建目录走 naming.toml 规范（NN_ 前缀/首字母大写/4-6 字符/禁中文/同级等长优先——devenv namecheck 校验）"
        _PHYS_FULL=""
        for _c in "${_constraints[@]}"; do _PHYS_FULL+="\- $_c（probe 实测）"$'\n'; done
    else
        _PHYS_BRIEF="共享盘能力（探测 $_phys_date · 后端 $_be）：symlink/hardlink/大小写/权限/长文件名均可用——依赖实体仍住 ①（跨机一致），命名仍小写 kebab-case"
        _PHYS_FULL="- 共享盘能力探测全部可用（symlink/hardlink/大小写/权限/文件名 ≥255B）"$'\n'
    fi
    _PHYS_FULL+="- 依赖实体（node_modules/venv）与私钥绝不放共享盘——住 ①（跨机一致性；bind 接回）"$'\n'
    printf '%s\n' "${_constraints[@]}" | grep -q "文件名上限 255B" && _PHYS_FULL+="- 单文件名/深层路径超 255B 上限——gradle/flutter 类缓存留本机盘"$'\n'
    _PHYS_FULL+="- 文件/代码命名小写 kebab-case；①②③ 自建目录走 naming.toml 规范（NN_ 前缀/首字母大写/4-6 字符/禁中文/同级等长优先——devenv namecheck 校验）"
else
    _PHYS_BRIEF="物理红线（能力未探测——共享盘当前不可写，按最保守假设）：无 symlink/不分大小写/权限 777——依赖实体与私钥绝不上去；文件/代码命名小写 kebab-case；①②③ 自建目录走 naming.toml 规范（NN_ 前缀/首字母大写/4-6 字符/禁中文/同级等长优先——devenv namecheck 校验）"
    _PHYS_FULL="- 共享盘能力未探测（probe 时共享盘不可写）——按最保守假设对待：无 symlink、不区分大小写、权限 777"$'\n'
    _PHYS_FULL+="- 依赖实体（node_modules/venv）与私钥绝不放共享盘——住 ①（bind 接回）"$'\n'
    _PHYS_FULL+="- 文件/代码命名小写 kebab-case；①②③ 自建目录走 naming.toml 规范（NN_ 前缀/首字母大写/4-6 字符/禁中文/同级等长优先——devenv namecheck 校验）"
fi

# ── SKILL 数值来源（@CFGVAL@ 渲染：③ 正本优先，seed 兜底——文档零复述，改值必经正本+再生）──
_cfg_src() {  # <③ 相对路径 config/...> → 实际可读正本路径
    local f="$COMMON/config/${1#config/}"
    [ -f "$f" ] && { printf '%s\n' "$f"; return; }
    printf '%s\n' "$BDE_ROOT/$1"
}
_V_INOTIFY="$(bde_cfgval "$(_cfg_src config/services/sysctl/99-devspace.conf)" '^fs\.inotify\.max_user_watches')"
_V_SWAP="$(bde_cfgval "$(_cfg_src config/services/sysctl/99-devspace.conf)" '^vm\.swappiness')"
_V_JMAX="$(bde_cfgval "$(_cfg_src config/services/systemd/journald-devspace.conf)" '^SystemMaxUse')"
_V_JKEEP="$(bde_cfgval "$(_cfg_src config/services/systemd/journald-devspace.conf)" '^SystemKeepFree')"
_V_JRET="$(bde_cfgval "$(_cfg_src config/services/systemd/journald-devspace.conf)" '^MaxRetentionSec')"
_V_NOFILE="$(bde_cfgval "$(_cfg_src config/services/limits/99-devspace.conf)" '^root hard nofile')"
_V_ZRAM_PCT="$(bde_cfgval "$(_cfg_src config/services/zram/zramswap)" '^PERCENT')"
_V_ZRAM_ALGO="$(bde_cfgval "$(_cfg_src config/services/zram/zramswap)" '^ALGO')"
_missing=0
for _v in "$_V_INOTIFY" "$_V_SWAP" "$_V_JMAX" "$_V_JKEEP" "$_V_JRET" "$_V_NOFILE" "$_V_ZRAM_PCT" "$_V_ZRAM_ALGO"; do
    [ -n "$_v" ] || { _missing=$((_missing+1)); bde_pending "SKILL 数值来源缺失（cfgval 取空——③ 正本未就绪？gen 后需复查）"; break; }
done

# ── 统一占位符渲染（AGENTS.md 与 SKILL.md 同一套；锚点/物理边界/CFGVAL 数值）──
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
    _c="${_c//@CFG_INOTIFY@/$_V_INOTIFY}"
    _c="${_c//@CFG_SWAP@/$_V_SWAP}"
    _c="${_c//@CFG_JMAX@/$_V_JMAX}"
    _c="${_c//@CFG_JKEEP@/$_V_JKEEP}"
    _c="${_c//@CFG_JRET@/$_V_JRET}"
    _c="${_c//@CFG_NOFILE@/$_V_NOFILE}"
    _c="${_c//@CFG_ZRAM_PCT@/$_V_ZRAM_PCT}"
    _c="${_c//@CFG_ZRAM_ALGO@/$_V_ZRAM_ALGO}"
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
    echo "cfg_sources_hash=$(bde_cfg_sources_hash)"
    echo "bde_commit=$(git -C "$BDE_ROOT" rev-parse --short HEAD 2>/dev/null || echo none)"
    echo "machine=${BDE_MACHINE:-$(hostname)}"
    echo "date=$(date '+%F %T')"
} > "$DEV/docs/state/gen-fingerprint" && bde_ok "生成指纹（模板+CFGVAL 来源正本）→ gen-fingerprint（doctor 巡检代际）"
