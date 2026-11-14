#!/usr/bin/env bash
# modules/doc/dirindex.sh — 系统内容索引（devenv index；宪法 §19.5 L1→L2→L3 同构）
# 聚合四层登记：dir-map.tsv（①②③ 树级"位置+职责"）+ home-map.tsv（$HOME 隐藏层）
#             + config/apps/*.toml（应用档案）+ inventory.json（软件层，在则纳入）
# 用法: devenv index [--json] ｜ JSON: ① docs/state/dirindex.json（bde.dirindex/1，原子写）
[ -n "${BDE_ROOT:-}" ] || BDE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$BDE_ROOT/lib/paths.sh"
source "$BDE_ROOT/lib/common.sh"

DIR_MAP="${BDE_DIR_MAP:-$COMMON/config/data/dir-map.tsv}"
[ -f "$DIR_MAP" ] || DIR_MAP="$BDE_ROOT/config/data/dir-map.tsv"
HOME_MAP="${BDE_HOME_MAP:-$COMMON/config/data/home-map.tsv}"
[ -f "$HOME_MAP" ] || HOME_MAP="$BDE_ROOT/config/data/home-map.tsv"
APPS_DIR="${BDE_APPS_DIR:-$COMMON/config/apps}"
INV_JSON="${BDE_INVENTORY_JSON:-$DEV/docs/state/inventory.json}"
OUT_JSON="${BDE_DIRINDEX_JSON:-$DEV/docs/state/dirindex.json}"

TMPD="$(mktemp -d "${TMPDIR:-/tmp}/bde-dirindex.XXXXXX")"
trap 'rm -rf "$TMPD"' EXIT

# L1 收集：树级登记（含迁移目标名）+ $HOME 层 + 应用档案
: > "$TMPD/dirs.tsv"
while IFS='|' read -r s p tgt desc cat note; do
    case "${s:-}" in ''|'#'*) continue ;; esac
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$s" "$p" "$tgt" "$desc" "$cat" "$note" >> "$TMPD/dirs.tsv"
done < "$DIR_MAP"
: > "$TMPD/home.tsv"
while IFS='|' read -r n app cat pol note; do
    case "${n:-}" in ''|'#'*) continue ;; esac
    printf '%s\t%s\t%s\t%s\t%s\n' "$n" "$app" "$cat" "$pol" "$note" >> "$TMPD/home.tsv"
done < "$HOME_MAP"
: > "$TMPD/apps.tsv"
for f in "$APPS_DIR"/*.toml; do
    [ -f "$f" ] || continue
    python3 - "$f" >> "$TMPD/apps.tsv" <<'PY'
import sys, tomllib
m = tomllib.load(open(sys.argv[1], "rb"))
meta = m.get("meta", {})
print("\t".join([meta.get("name", ""), meta.get("kind", "app"), meta.get("summary", ""),
                 m.get("install", {}).get("at", ""), m.get("install", {}).get("scope", "")]))
PY
done

# L2 落盘 + L3 视图（一份 python 完成两态）
DIR_INDEX_MACHINE="${BDE_MACHINE:-$(hostname)}" \
DIR_DIRS="$TMPD/dirs.tsv" DIR_HOME="$TMPD/home.tsv" DIR_APPS="$TMPD/apps.tsv" \
DIR_INV="$INV_JSON" DIR_OUT="$OUT_JSON" DIR_COMMON="$COMMON" \
python3 <<'PYEOF'
import os, json, datetime, tempfile

dirs = [l.rstrip("\n").split("\t") for l in open(os.environ["DIR_DIRS"]) if l.strip()]
home = [l.rstrip("\n").split("\t") for l in open(os.environ["DIR_HOME"]) if l.strip()]
apps = [l.rstrip("\n").split("\t") for l in open(os.environ["DIR_APPS"]) if l.strip()]
inv = None
if os.path.exists(os.environ["DIR_INV"]) and os.path.getsize(os.environ["DIR_INV"]) > 0:
    try:
        inv = json.load(open(os.environ["DIR_INV"]))
    except Exception:
        inv = None

SC = {"shared": "③ 跨主机共享", "host": "② 主机内共享", "user": "① 用户独占"}
doc = {
    "schema": "bde.dirindex/1",
    "machine": os.environ["DIR_INDEX_MACHINE"],
    "date": datetime.datetime.now().strftime("%Y-%m-%d %H:%M"),
    "tree": [
        {"scope": r[0], "path": r[1], "target": r[2] if len(r) > 2 else "", "desc": r[3] if len(r) > 3 else "",
         "category": r[4] if len(r) > 4 else "", "note": r[5] if len(r) > 5 else ""} for r in dirs
    ],
    "home": [
        {"name": r[0], "app": r[1] if len(r) > 1 else "", "category": r[2] if len(r) > 2 else "",
         "policy": r[3] if len(r) > 3 else "", "note": r[4] if len(r) > 4 else ""} for r in home
    ],
    "apps": [
        {"name": r[0], "kind": r[1] if len(r) > 1 else "", "summary": r[2] if len(r) > 2 else "",
         "install_at": r[3] if len(r) > 3 else "", "install_scope": r[4] if len(r) > 4 else ""} for r in apps
    ],
    "inventory_summary": inv.get("summary") if inv else None,
}
doc["summary"] = {"tree_n": len(doc["tree"]), "home_n": len(doc["home"]), "apps_n": len(doc["apps"]),
                  "pending_rename": sum(1 for t in doc["tree"] if t["target"])}

fd, tmp = tempfile.mkstemp(dir=os.path.dirname(os.environ["DIR_OUT"]) or ".", prefix=".dirindex.")
with os.fdopen(fd, "w") as f:
    json.dump(doc, f, ensure_ascii=False, indent=1)
os.replace(tmp, os.environ["DIR_OUT"])

# —— L3 人类视图 ——
print("== 系统内容索引（每目录是什么、放什么；机器 %s @ %s）==" % (doc["machine"], doc["date"]))
for s in ("shared", "host", "user"):
    rows = [r for r in dirs if r[0] == s]
    if not rows:
        continue
    print(f"\n-- {SC.get(s, s)}（{len(rows)} 项登记）--")
    print("  %-28s %-6s %-38s %s" % ("路径", "分类", "职责", "迁移目标/备注"))
    for r in rows:
        tail = r[2] if len(r) > 2 and r[2] else ""
        if len(r) > 5 and r[5] and not tail:
            tail = r[5]
        elif len(r) > 5 and r[5]:
            tail = tail + " ｜ " + r[5]
        print("  %-28s %-6s %-38s %s" % (r[1], r[4] if len(r) > 4 else "", r[3] if len(r) > 3 else "", tail))
print(f"\n-- $HOME 隐藏层（home-map 登记制，{len(home)} 项）--")
for r in home[:1000]:
    print("  %-16s %-14s %-8s %-9s %s" % (r[0], r[1] if len(r) > 1 else "", r[2] if len(r) > 2 else "",
                                          r[3] if len(r) > 3 else "", r[4] if len(r) > 4 else ""))
print(f"\n-- 应用档案（{len(apps)} 份；缺档软件跑 devenv app --audit）--")
for r in apps:
    print("  %-14s %-10s %s%s" % (r[0], r[1] if len(r) > 1 else "", r[2] if len(r) > 2 else "",
                                  f" ｜ 安装位: {r[3]}" if len(r) > 3 and r[3] else ""))
if inv:
    s = inv.get("summary", {})
    print(f"\n-- 软件层（inventory.json：{s.get('tools_n', '?')} 重点工具 ｜ "
          f"全量 {s.get('tools_all_n', s.get('tools_n', '?'))} ｜ 契约路径 ⚠{s.get('paths_warn', 0)}）--")
print(f"\n索引：树 {doc['summary']['tree_n']} ｜ HOME {doc['summary']['home_n']} ｜ 档案 {doc['summary']['apps_n']} ｜ "
      f"待改名 {doc['summary']['pending_rename']} ｜ JSON: {os.environ['DIR_OUT'].replace(os.path.expanduser('~'), '~')}")
PYEOF
