#!/usr/bin/env bash
# verify/doctor.sh — L3 校验视图：消费 probe 事实逐项判定（宪法 §19.5 数据/视图分层）
# 本文件不含任何采集逻辑；新增检查 = 在 CHECKS 表加一行（事实键 + 判定式）。
# 后端无关：存储项按 probe 的 backend/persisted/expected 事实判定，不硬编码介质名词；
# 挂载对账便携化：mountpoint（util-linux）缺失时回退 mount 输出解析（mac/BSD 可用）；
# OS 条件化：Linux 专属项（持久化 fstab/IDE/XDG/inotify）仅在 Linux 系执行，非 Linux 不误报。
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
st, caps = doc["storage"], doc["share_caps"]
free_mb = v["disk_root_free_mb"]
# OS 条件化：/etc/os-release 缺失（mac/windows）或明确非 Linux 系时，跳过 Linux 专属项
is_linux = doc["os_id"] not in ("", "unknown", "darwin", "macos", "windows", "win32")

CHECKS = [
    ("Common 可写",                        f["common_writable"] == 1),
    ("Local 可写",                         f["local_writable"] == 1),
    ("存储后端与实际形态一致（声明 vs 挂载）",
        (st["backend_common"] == "local") == (st["mounted_common"] == 0)
        and (st["backend_host"] == "local") == (st["mounted_host"] == 0)),
    ("存储档案解析正常",                    st["profile_error"] == 0),
    ("共享盘能力已探测（物理边界事实化）",
        f["common_writable"] == 0 or caps["probed"] == 1),
    ("config 就绪（config/.chezmoiignore 或 env.sh）", f["config_ready"] == 1),
    ("env.sh 已应用到应用层",               f["env_sh_applied"] == 1),
    ("目录骨架就绪",                        f["skeleton_ready"] == 1),
    ("AGENTS.md 已生成",                   f["agents_md"] == 1),
    ("Runtime 统一接线（AGENTS.md/MCP/Skills）", f["runtime_wired"] == 1),
    ("系统/服务配置无漂移（cfg-map）", f["cfg_drift"] == 0),
    ("config 仓库干净（无未提交变更）", f["cfg_dirty"] == 0),
    ("config 备份通道（seed 快照随工程仓库 push）", f["cfg_backup"] == 1),
    ("agents 正本已入 ③ config 仓库（Skill/MCP 版本化）", f["agents_canon"] == 1),
    ("分发器就绪（devenv 在位，旧 env 已除名）", f["dispatcher_ok"] == 1),
    ("Skill/AGENTS 正本与模板同代（gen 指纹）",  f["gen_fresh"] == 1),
    ("本机已登记 hosts.toml（机器数据表）",      f["host_registered"] == 1),
    (f"根盘余量 > 15G（现余 {free_mb/1024:.1f}G）", free_mb > 15 * 1024),
]

# Linux 专属项（非 Linux 系自动缺席，不误报）：
# - 持久化：fstab 是 Linux 机制（mac/win 无此概念，对应物为里程碑适配器）
# - IDE/XDG/inotify：Linux 桌面开发栈专属
# - 系统优化默认集运行态（v0.19）：文件落位漂移已由 cfg-map 巡检覆盖，此处只验"生效值"
if is_linux:
    CHECKS += [
        (f"存储已持久化（③ {st['backend_common']}）",  st["persisted_common"] == 1),
        (f"存储已持久化（② {st['backend_host']}）",    st["persisted_host"] == 1),
        ("IDE 就绪（code + settings + 语言档案）", f["ide_ready"] == 1),
        ("XDG 用户目录已重定向",                f["xdg_redirect"] == 1),
        ("inotify 上限已调高",                  f["inotify_ok"] == 1),
        ("vm.swappiness ≤ 10（换页保守，现值见 probe）", f["sysctl_ok"] == 1),
        ("fstrim.timer 已启用（SSD 周期 TRIM）",  f["fstrim_ok"] == 1),
        ("时间同步服务运行中",                  f["timesync_ok"] == 1),
        ("时区与站点画像一致",                  f["tz_ok"] == 1),
        ("zram 压缩内存交换已启用",             f["zram_ok"] == 1),
    ]

# 叠层检查仅挂载型后端有意义（local 目录无挂载点概念）
if st["backend_common"] != "local":
    CHECKS.append(("挂载无叠层（③ 恰一层）",  f["layer_common"] == 1))
if st["backend_host"] != "local":
    CHECKS.append(("挂载无叠层（② 恰一层）",  f["layer_local"] == 1))

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
if st["profile_error"]:
    print(f"{R}[!]{Z} 存储档案：{st['profile_error_msg']}")
print(f"\ndoctor：{passed} 项通过 ｜ {failed} 项失败")
sys.exit(0 if failed == 0 else 1)
PYEOF
exit $?
