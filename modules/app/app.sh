#!/usr/bin/env bash
# modules/app/app.sh — 应用视图（宪法 §20.3）：把散落各作用域的应用数据映射成一张卡
# 数据层按作用域分散（安装体/配置/数据/留档各有其家），本视图按应用聚合——"让一个东西看起来在一起"
# 用法: devenv app            # 应用清单
#       devenv app <name>     # 单应用卡（实测：命令/配置一致性/数据体量/服务状态）
[ -n "${BDE_ROOT:-}" ] || BDE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$BDE_ROOT/lib/paths.sh"

APPS_DIR="${BDE_APPS_DIR:-$COMMON/config/apps}"

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

# 安装体
ins = m.get("install", {})
v = run(ins.get("verify", "true")).stdout.strip().splitlines()
print(f"  安装体  [{ins.get('scope', '?')}] via {ins.get('via', '-')} ｜ {v[0] if v else '未检出'}")
# 配置（正本 vs 应用层一致性）
cfg = m.get("config", {})
if cfg.get("manifest"):
    src = os.path.join(roots["shared"], "config", cfg["manifest"])
    dst = os.path.expanduser(cfg.get("applied", ""))
    state = "应用层缺失" if not os.path.exists(dst) else ("一致" if _cmp_ok(src, dst) else "漂移")
    print(f"  配置    ③ config/{cfg['manifest']} → {dst} ｜ {state}（via {cfg.get('via', '-')}; devenv cfg diff 巡检）")
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
        [ -f "$f" ] || { echo "  （无档案——新应用在 $APPS_DIR 建 <name>.toml）"; return; }
        BDE_APP_MANIFEST="$f" python3 <<'PY'
import os, tomllib
m = tomllib.load(open(os.environ["BDE_APP_MANIFEST"], "rb"))
mt = m["meta"]
print(f"  {mt['name']:12s} {mt.get('kind', 'app'):10s} {mt.get('summary', '')}")
PY
    done
}

case "${1:-}" in
    ""|--all) bde_app_list ;;
    -h|--help) echo "用法: devenv app [name] ｜ 档案: $APPS_DIR/<name>.toml" ;;
    *) f="$APPS_DIR/$1.toml"
       [ -f "$f" ] || { echo "无档案: $f（收编：建 <name>.toml，字段见 docker.toml）"; exit 1; }
       bde_app_render "$f" ;;
esac
