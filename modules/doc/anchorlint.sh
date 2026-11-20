#!/usr/bin/env bash
# modules/doc/anchorlint.sh — 锚点可解析性校验（L1 派生事实：文档里写死的路径必须真的存在）
# 动机：代码有 doctor 兜底，文档没有——重命名后 Skill/AGENTS 里的旧锚点会静默腐坏
#       （2026-11-20 实测：`$COMMON/code/BestDevEnv` 在 7 个 Skill 中失效，首步直接 127）
# 范围：③ Skill 正本 SKILL.md + ① AGENTS.md 正本（Agent 真正读到的两份文本）
# 数据源：锚点来自 env.sh（DEV/COMMON/LOCAL/SHARE/BDE_ROOT/HOME）
# 例外：Registry/anchor-ignore.tsv（`路径|原因`，按需登记——数据驱动，不改代码）
# 用法：devenv lint [--json|--count] ｜ 退出码 0=全可解析 1=有失效 2=环境问题
[ -n "${BDE_ROOT:-}" ] || BDE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$BDE_ROOT/lib/paths.sh"
source "$BDE_ROOT/lib/common.sh"

case "${1:-}" in
    "")        MODE=human ;;
    --count)   MODE=count ;;
    --json)    MODE=json ;;
    *) echo "用法: devenv lint [--json|--count]"; exit 2 ;;
esac

IGNORE="$COMMON/10_Config/Registry/anchor-ignore.tsv"
[ -f "$IGNORE" ] || IGNORE="$BDE_ROOT/config/Registry/anchor-ignore.tsv"

MODE="$MODE" IGNORE="$IGNORE" \
AGENTS_CANON="$HOME/.config/devspace/agents/AGENTS.md" \
SKILL_CANON="$BDE_AGENTS_CANON/skill" \
python3 <<'PYEOF'
import os, re, sys, glob, json

mode = os.environ.get("MODE", "human")
anchors = {k: os.environ.get(k, "") for k in ("DEV", "COMMON", "LOCAL", "SHARE", "BDE_ROOT", "HOME")}
anchors = {k: v for k, v in anchors.items() if v}

# 例外清单：路径前缀级豁免（登记过的"按需存在"路径，不制造噪音）
ign = []
p = os.environ.get("IGNORE", "")
if p and os.path.exists(p):
    for line in open(p, encoding="utf-8"):
        line = line.rstrip("\n")
        if not line or line.startswith("#"):
            continue
        path = line.split("|", 1)[0].strip()
        if path:
            ign.append(path)

sources = []
src_state = os.environ["AGENTS_CANON"]
if os.path.exists(src_state):
    sources.append(src_state)
sources += sorted(glob.glob(os.path.join(os.environ["SKILL_CANON"], "*", "SKILL.md")))

# 只认"显式锚点 + 具体路径段"：`$COMMON/xxx`；排除 glob/占位符/变量拼接（`$COMMON/$name`、`<repo>`、`*.md`）
pat = re.compile(r"\$(?:COMMON|DEV|LOCAL|SHARE|BDE_ROOT|HOME)(?:/[A-Za-z0-9_.@+-]+)+")
# 渲染后的正本（AGENTS.md）是绝对路径——同一套锚点值再扫一遍，防"渲染即失明"
abs_pat = re.compile(
    "(?:" + "|".join(re.escape(v) for v in sorted(set(anchors.values()), key=len, reverse=True)) + r")(?:/[A-Za-z0-9_.@+-]+)+"
) if anchors else None
tail = ".,;:!?)]}>\"'`）】、，。：；"

checked = 0
stale = {}   # path -> [file:line]

def _ref(f, ln):
    home = os.path.expanduser("~/")
    return f"{os.path.relpath(f, home)}:{ln}" if f.startswith(home) else f"{f}:{ln}"

def _check(tok, real, f, ln):
    global checked
    if any(tok == i or tok.startswith(i.rstrip("/") + "/") for i in ign):
        return
    checked += 1
    if os.path.exists(real):
        return
    stale.setdefault(tok, []).append(_ref(f, ln))

for f in sources:
    try:
        text = open(f, encoding="utf-8").read()
    except Exception:
        continue
    for ln, line in enumerate(text.splitlines(), 1):
        # ① 变量式锚点（Skill 正本写法）：$COMMON/xxx
        for m in pat.finditer(line):
            tok = m.group(0).rstrip(tail)
            if not tok or tok.endswith("/"):
                continue
            if any(ch in tok for ch in ("*", "<", ">", "{", "}", "…")):
                continue
            if "$" in tok[1:]:      # 变量拼接（$COMMON/$name）不判——运行时才知道
                continue
            real = None
            for k in sorted(anchors, key=len, reverse=True):
                if tok.startswith("$" + k + "/"):
                    real = anchors[k] + tok[len(k) + 1:]
                    break
            if real is not None:
                _check(tok, real, f, ln)
        # ② 渲染后的绝对路径（AGENTS.md 写法）
        if abs_pat:
            for m in abs_pat.finditer(line):
                tok = m.group(0).rstrip(tail)
                if not tok or tok.endswith("/"):
                    continue
                if any(ch in tok for ch in ("*", "<", ">", "{", "}", "…")):
                    continue
                _check(tok, tok, f, ln)

total = len(stale)
if mode == "count":
    print(total)
    sys.exit(0)

if mode == "json":
    print(json.dumps({
        "schema": "bde.anchorlint/1",
        "anchors": anchors,
        "sources": len(sources),
        "checked": checked,
        "stale": [{"path": k, "refs": v} for k, v in sorted(stale.items())],
        "stale_count": total,
    }, ensure_ascii=False, indent=2))
    sys.exit(0 if total == 0 else 1)

if not sources:
    print("✗ 无可校验正本（Skill 正本 / AGENTS.md 均缺失）——先 devenv gen")
    sys.exit(2)

G, R, Y, Z = ("\033[32m", "\033[31m", "\033[33m", "\033[0m") if sys.stdout.isatty() else ("", "", "", "")
print("== 锚点可解析性（Skill 正本 + AGENTS.md 中写死的路径）==")
for path, refs in sorted(stale.items()):
    print(f"  {R}[✗]{Z} {path}")
    for r in refs[:3]:
        print(f"      ← {r}")
    if len(refs) > 3:
        print(f"      ← …共 {len(refs)} 处引用")
if total == 0:
    print(f"  {G}[✓]{Z} {checked} 处锚点引用全部可解析（{len(sources)} 份正本）")
else:
    print(f"{Y}[i]{Z} {total} 个失效锚点 / {checked} 处引用——改正本（templates/）后 devenv gen 再生；"
          f"按需例外登记 {os.environ['IGNORE']}")
sys.exit(0 if total == 0 else 1)
PYEOF
