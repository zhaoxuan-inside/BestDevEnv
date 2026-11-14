#!/usr/bin/env bash
# modules/app/app.sh — 应用视图（宪法 §20.3）：把散落各作用域的应用数据映射成一张卡
# 数据层按作用域分散（安装体/配置/数据/留档各有其家），本视图按应用聚合——"让一个东西看起来在一起"
# 受管五要素：安装位置/配置位置/日志位置/数据缓存位置/产出位置——缺一即未受管（--audit 审计）
# 用法: devenv app            # 应用清单
#       devenv app <name>     # 单应用卡（实测：命令/安装位实态/配置一致性/数据体量/服务状态）
#       devenv app --audit    # 覆盖审计：已装未建档 × 安装位置违规 × 孤儿档案
#       devenv app --migrate  # 处置流（逐项授权）：建档四问 / 实体迁移（搬入受管根+链接接回）
[ -n "${BDE_ROOT:-}" ] || BDE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$BDE_ROOT/lib/paths.sh"
source "$BDE_ROOT/lib/common.sh"
source "$BDE_ROOT/lib/ensure.sh"

APPS_DIR="${BDE_APPS_DIR:-$COMMON/config/apps}"
CLASSIFY_TSV="$COMMON/config/data/apps-classify.tsv"
HOME_MAP="$COMMON/config/data/home-map.tsv"
INV_JSON="${BDE_INVENTORY_JSON:-$DEV/docs/state/inventory.json}"

bde_app_render() {  # <manifest 绝对路径>
    BDE_APP_MANIFEST="$1" \
    BDE_SHARED_ROOT="$BDE_SCOPE_SHARED_ROOT" BDE_HOST_ROOT="$BDE_SCOPE_HOST_ROOT" \
    BDE_USER_ROOT="$BDE_SCOPE_USER_ROOT" BDE_MACHINE_N="${BDE_MACHINE:-$(hostname)}" \
    python3 <<'PY'
import os, subprocess, tomllib, shlex

m = tomllib.load(open(os.environ["BDE_APP_MANIFEST"], "rb"))
name, kind = m["meta"]["name"], m["meta"].get("kind", "app")
roots = {"shared": os.environ["BDE_SHARED_ROOT"], "host": os.environ["BDE_HOST_ROOT"],
         "user": os.environ["BDE_USER_ROOT"], "system": "/"}

def spath(spec):  # "host:services/docker" 或绝对/~路径
    s, _, p = spec.partition(":")
    if s in roots and p:
        return os.path.join(roots[s], p)
    return os.path.expanduser(spec)

def run(cmd, timeout=20):
    try:
        return subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=timeout)
    except Exception:
        return None

print(f"── {name}（{kind}）{'· ' + m['meta']['summary'] if m['meta'].get('summary') else ''} " + "─" * 20)

def _cmp_ok(a, b):
    try:
        return subprocess.run(["cmp", "-s", a, b]).returncode == 0
    except Exception:
        return False

# 安装体 + 安装位置实态对照（受管根 = 系统包管理器 / ①②③ 锚点；家目录散装与共享盘实体 = 违规）
ins = m.get("install", {})
v = run(ins.get("verify", "true")).stdout.strip().splitlines()
print(f"  安装体  [{ins.get('scope', '?')}] via {ins.get('via', '-')} ｜ {v[0] if v else '未检出'}")
at = ins.get("at", "")
if ins.get("scope", "") == "system" or ins.get("scope", "") == "":
    print("  安装位  系统包管理器管辖（scope=system，at 豁免）" if not at else f"  安装位  声明 {spath(at)}")
elif not at:
    print("  安装位  ⚠ 未声明（受管根必填：user:/host:/shared: 相对路径）")
else:
    p = spath(at)
    managed = any(p.startswith(r.rstrip("/") + "/") or p == r.rstrip("/") for r in roots.values() if r != "/") \
        or p.startswith("/usr/") or p.startswith("/opt/") or p.startswith("/snap/")
    if not os.path.isdir(p):
        print(f"  安装位  {p} ｜ ⚠ 声明位置缺失（安装体未按档案落位——漂移）")
    elif managed:
        print(f"  安装位  {p} ｜ 就绪（受管根）")
    else:
        print(f"  安装位  {p} ｜ ⚠ 就绪但未受管（家目录散装——devenv app --migrate 授权迁移）")
# 配置（正本 vs 应用层一致性）
cfg = m.get("config", {})
if cfg.get("manifest"):
    src = os.path.join(roots["shared"], "config", cfg["manifest"])
    dst = os.path.expanduser(cfg.get("applied", ""))
    state = "应用层缺失" if not os.path.exists(dst) else ("一致" if _cmp_ok(src, dst) else "漂移")
    print(f"  配置    ③ config/{cfg['manifest']} → {dst} ｜ {state}（via {cfg.get('via', '-')}；devenv cfg diff 巡检）")
# 数据（作用域 + 体量）
dat = m.get("data", {})
if dat.get("path") or dat.get("at"):
    logical = dat.get("scope", "host")
    phys = spath(dat.get("at") or f"{logical}:{dat.get('path', '')}")
    r = run(f"sudo -n du -sh {shlex.quote(phys)} 2>/dev/null || du -sh {shlex.quote(phys)} 2>/dev/null", 60)  # 服务数据多 root 属主，sudo 优先
    sz = r.stdout.strip().split("\t")[0] if r and r.stdout else "?"
    print(f"  数据    逻辑[{logical}] {phys} ｜ {sz}" + (f" ｜ 留档 {spath(dat['dump']) if dat.get('dump') else ''}" if dat.get("dump") else ""))
# 服务状态
svc = m.get("service", {})
if svc.get("unit"):
    st = run(f"systemctl is-active {svc['unit']}").stdout.strip()
    print(f"  服务    systemctl unit={svc['unit']} ｜ {st}")
# doctor 关联项
doc = m.get("doctor", {}).get("check", "")
if doc:
    print(f"  巡检    doctor/cfg-map 项：{doc}（devenv cfg diff）")
PY
}

bde_app_list() {
    echo "应用视图清单（档案：$APPS_DIR）"
    for f in "$APPS_DIR"/*.toml; do
        [ -f "$f" ] || { echo "  （无档案——新应用在 $APPS_DIR 建 <name>.toml；devenv app --audit 看缺档清单）"; return; }
        BDE_APP_MANIFEST="$f" python3 <<'PY'
import os, tomllib
m = tomllib.load(open(os.environ["BDE_APP_MANIFEST"], "rb"))
mt = m["meta"]
print(f"  {mt['name']:12s} {mt.get('kind', 'app'):10s} {mt.get('summary', '')}")
PY
    done
}

# ── 覆盖审计（规则 1：所有软件受管）──
# 已管集合 = apps-classify.tsv ∪ home-map 所属应用 ∪ inventory.json 软件名（在则）
# 对照 config/apps/*.toml → 未建档清单（启发式归一：a.b.c 取首段）；孤儿档案反报
_app_missing() {  # <输出文件>：name<TAB>source 行（未建档清单）
    local out="$1"
    : > "$out"
    local mts="$TMPD/managed.tsv"; : > "$mts"
    if [ -f "$CLASSIFY_TSV" ]; then
        while IFS='|' read -r cat name; do
            case "${cat:-}" in ''|'#'*) continue ;; esac
            case "${name:-}" in ''|'#'*) continue ;; esac
            printf '%s\t%s\n' "$name" "apps-classify" >> "$mts"
        done < "$CLASSIFY_TSV"
    fi
    if [ -f "$HOME_MAP" ]; then
        while IFS='|' read -r item app cat pol note; do
            case "${app:-}" in ''|'#'*|XDG) continue ;; esac
            printf '%s\t%s\n' "$app" "home-map" >> "$mts"
        done < "$HOME_MAP"
    fi
    if [ -f "$INV_JSON" ]; then
        INV_IN="$INV_JSON" MANAGED="$mts" python3 <<'PY'
import os, json
try:
    inv = json.load(open(os.environ["INV_IN"]))
except Exception:
    raise SystemExit
with open(os.environ["MANAGED"], "a") as f:
    for t in inv.get("tools", []):
        f.write(f"{t['name']}\tinventory({t.get('channel', '')})\n")
    for x in inv.get("discovered", []):
        f.write(f"{x['name']}\tinventory/{x.get('source', '')}\n")
PY
    fi
    MANAGED="$mts" APPS_DIR="$APPS_DIR" OUT="$out" python3 <<'PY'
import os, glob, tomllib

def candidates(n):
    n = n.strip().lower()
    c = [n]
    if "." in n:
        c.append(n.split(".")[0])
    return c

man_names = {}
for f in glob.glob(os.path.join(os.environ["APPS_DIR"], "*.toml")):
    try:
        m = tomllib.load(open(f, "rb"))
        man_names[m["meta"]["name"].lower()] = f
    except Exception:
        pass

seen, missing = {}, {}
with open(os.environ["OUT"], "w") as out:
    for line in open(os.environ["MANAGED"]):
        parts = line.rstrip("\n").split("\t")
        if len(parts) < 2 or not parts[0]:
            continue
        name, src = parts[0], parts[1]
        hit = next((n for n in candidates(name) if n in man_names), None)
        if hit:
            seen.setdefault(hit, set()).add(src)
        else:
            k = name.strip().lower()
            if k not in missing:
                missing[k] = []
                out.write(f"{name}\t{src}\n")
            missing[k].append(src)
PY
}

bde_app_audit() {
    TMPD="$(mktemp -d "${TMPDIR:-/tmp}/bde-app-audit.XXXXXX")"
    trap 'rm -rf "$TMPD"' EXIT
    _app_missing "$TMPD/missing.tsv" || return 2
    local _n; _n="$(wc -l < "$TMPD/missing.tsv")"
    echo "== 应用档案覆盖审计（档案：$APPS_DIR）=="
    if [ "$_n" -gt 0 ]; then
        echo "-- 已管未建档 $_n 个（收编：devenv app --migrate 逐项授权建档）--"
        while IFS=$'\t' read -r name src; do
            printf '  %-16s 来源: %s\n' "$name" "$src"
        done < "$TMPD/missing.tsv"
    else
        echo "-- 已管未建档 0 个（全量建档 ✓）--"
    fi
    echo "-- 孤儿档案核对：档案名无登记来源对应者由 --migrate/人工核对（apps-classify ∪ home-map ∪ inventory 为已管集合）--"
}

# ── 处置流（逐项授权）：未建档软件 → 四问建档 + 配置收编 ──
bde_app_migrate() {
    TMPD="$(mktemp -d "${TMPDIR:-/tmp}/bde-app-migrate.XXXXXX")"
    trap 'rm -rf "$TMPD"' EXIT
    _app_missing "$TMPD/missing.tsv"
    mapfile -t _rows < "$TMPD/missing.tsv"
    echo "== 应用档案处置流（逐项授权；四问未答不建档）=="
    [ "${#_rows[@]}" -gt 0 ] || { echo "无未建档软件（audit 归零 ✓）"; return 0; }
    for _row in "${_rows[@]}"; do
        name="${_row%%$'\t'*}"
        bde_ask act "[$name] 建档[a]/跳过[s]" "s"
        [ "$act" = "a" ] || { echo "  跳过 $name"; continue; }
        # 四问（装前四问的建档落点；回车=暂缺，档案可后补）
        read -r -p "  ①安装位置（受管根相对，如 user:Apps/$name；回车=system 豁免）: " at
        read -r -p "  ②配置应用层路径（回车=暂无）: " cfgp
        read -r -p "  ③数据/缓存位置（如 host:Cache/$name；回车=暂无）: " datp
        read -r -p "  ④日志位置（如 host:Logs/$name；回车=暂无）: " logp
        _mf="$APPS_DIR/$name.toml"
        if [ -f "$_mf" ]; then echo "  [!] 档案已存在：$_mf——跳过"; continue; fi
        {
            echo "# 应用档案：$name（devenv app --migrate 四问建档 $(date '+%F')）"
            echo "[meta]"
            echo "name = \"$name\""
            echo "summary = \"（待补）\""
            echo ""
            echo "[install]"
            if [ -n "$at" ]; then
                echo "scope = \"${at%%:*}\""
                echo "at = \"$at\""
            else
                echo "scope = \"system\""
            fi
            echo "verify = \"command -v $name\""
            echo ""
            echo "[config]"
            echo "via = \"待收编\""
        } > "$_mf" || { echo "  [✗] 档案写入失败"; continue; }
        echo "  [✓] 建档 $_mf（五要素后补：config.manifest/data/logs/产出，字段见 docker.toml）"
        if [ -n "$cfgp" ] && [ -f "$cfgp" ]; then
            bde_ask act2 "  配置收编：cfg adopt $name ← $cfgp [y]" "y"
            [ "$act2" = "y" ] && bash "$BDE_ROOT/modules/cfg/cfg.sh" adopt "$name" "$cfgp" system n
        fi
    done
    echo "== 复核 =="; bde_app_audit | tail -2
}

case "${1:-}" in
    ""|--all) bde_app_list ;;
    --audit) bde_app_audit ;;
    --migrate) bde_app_migrate ;;
    -h|--help) echo "用法: devenv app [name|--audit|--migrate] ｜ 档案: $APPS_DIR/<name>.toml" ;;
    *) f="$APPS_DIR/$1.toml"
       [ -f "$f" ] || { echo "无档案: $f（收编：devenv app --migrate 建档，或手工建 <name>.toml 字段见 docker.toml）"; exit 1; }
       bde_app_render "$f" ;;
esac
