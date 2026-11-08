#!/usr/bin/env bash
# verify/doctor.sh — L3 校验视图：消费 probe 事实逐项判定（宪法 §19.5 数据/视图分层）
# 本文件不含任何采集逻辑；新增检查 = 在 CHECKS 表加一行（事实键 + 判定式）。
# 用法：devenv doctor ｜ doctor.sh [--json]
BDE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$BDE_ROOT/lib/paths.sh"
source "$BDE_ROOT/lib/probe.sh"

bde_probe_collect
BDE_DOCTOR_JSON="${BDE_DOCTOR_JSON:-0}"
[ "${1:-}" = "--json" ] && BDE_DOCTOR_JSON=1
JSON="$(bde_probe_json)"
[ -n "$JSON" ] || { echo "✗ probe 采集失败"; exit 2; }

JSON="$JSON" BDE_DOCTOR_JSON="$BDE_DOCTOR_JSON" python3 - <<'PYEOF'
import os, json, sys

doc = json.loads(os.environ["JSON"])
f, v = doc["facts"], doc["values"]
free = v["disk_root_free_g"]

CHECKS = [
    ("Common 可写",                        f["common_writable"] == 1),
    ("Local 可写",                         f["local_writable"] == 1),
    ("fstab 已持久化后端挂载",              f["fstab_backend"] >= 1),
    ("config 就绪（config/.chezmoiignore 或 env.sh）", f["config_ready"] == 1),
    ("env.sh 已应用到应用层",               f["env_sh_applied"] == 1),
    ("目录骨架就绪",                        f["skeleton_ready"] == 1),
    ("AGENTS.md 已生成",                   f["agents_md"] == 1),
    ("Runtime 统一接线（AGENTS.md/MCP/Skills）", f["runtime_wired"] == 1),
    ("系统/服务配置无漂移（cfg-map）", f["cfg_drift"] == 0),
    ("config 仓库干净（无未提交变更）", f["cfg_dirty"] == 0),
    ("IDE 就绪（code + settings + 语言档案）", f["ide_ready"] == 1),
    ("XDG 用户目录已重定向",                f["xdg_redirect"] == 1),
    ("inotify 上限已调高",                  f["inotify_ok"] == 1),
    ("挂载无叠层（/Share/Common 恰一层）",   f["layer_common"] == 1),
    ("挂载无叠层（/Share/Local 恰一层）",    f["layer_local"] == 1),
    (f"根盘余量 > 15G（现余 {free}G）",      free > 15),
    ("分发器就绪（devenv 在位，旧 env 已除名）", f["dispatcher_ok"] == 1),
    ("Skill/AGENTS 正本与模板同代（gen 指纹）",  f["gen_fresh"] == 1),
    ("本机已登记 hosts.toml（机器数据表）",      f["host_registered"] == 1),
]

passed = sum(1 for _, ok, *_ in CHECKS if ok)
failed = len(CHECKS) - passed

if os.environ.get("BDE_DOCTOR_JSON") == "1":
    print(json.dumps({
        "schema": "bde.doctor/1",
        "machine": doc["machine"], "date": doc["date"],
        "probe_schema": doc["schema"],
        "pass": passed, "fail": failed,
        "checks": [{"name": n, "ok": ok} for n, ok, *_ in CHECKS],
    }, ensure_ascii=False, indent=2))
    sys.exit(0 if failed == 0 else 1)

tty = sys.stdout.isatty()
G, R, Z = ("\033[32m", "\033[31m", "\033[0m") if tty else ("", "", "")
print(f"devenv doctor — 机器 {doc['machine']} @ {doc['date']}")
for name, ok, *_ in CHECKS:
    print(f"{G if ok else R}[{'✓' if ok else '✗'}]{Z} {name}")
print(f"\ndoctor：{passed} 项通过 ｜ {failed} 项失败")
sys.exit(0 if failed == 0 else 1)
PYEOF
exit $?
