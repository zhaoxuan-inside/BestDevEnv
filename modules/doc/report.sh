#!/usr/bin/env bash
# modules/doc/report.sh — L3 报告视图：probe.json → markdown → $COMMON/docs/env/
# 纯渲染：数据来自 L1 快照（bde_probe_save），本文件不含采集逻辑（宪法 §19.5）
[ -n "${BDE_ROOT:-}" ] || BDE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$BDE_ROOT/lib/paths.sh"
source "$BDE_ROOT/lib/common.sh"
source "$BDE_ROOT/lib/ensure.sh"
source "$BDE_ROOT/lib/probe.sh"

bde_info "M5 环境描述文档（报告视图）"
F_JSON="$(bde_probe_save)" || { bde_pending "probe 快照失败"; exit 1; }

ensure_dir "$COMMON/docs/env" || { echo "报告目录不可用：$COMMON/docs/env"; exit 1; }

_machine="${BDE_MACHINE:-$(hostname)}"
_f="$COMMON/docs/env/${_machine}-$(date +%Y%m%d-%H%M).md"
PROGRESS="$(bde_progress_show 2>/dev/null || true)"
PENDING_TXT=""
[ "${BDE_PENDING_N:-0}" -gt 0 ] && PENDING_TXT="$(printf -- '- [ ] %s\n' "${BDE_PENDINGS[@]}")"

BDE_REPORT_JSON="$F_JSON" BDE_OUT="$_f" BDE_PROGRESS="$PROGRESS" \
BDE_PENDING_TXT="$PENDING_TXT" BDE_MACHINE_N="$_machine" python3 - <<'PYEOF'
import os, json

doc = json.load(open(os.environ["BDE_REPORT_JSON"]))
a, f, v, t = doc["anchors"], doc["facts"], doc["values"], doc["tools"]
L = []
L.append(f"# 开发环境报告 — {os.environ['BDE_MACHINE_N']}")
L.append("")
L.append(f"## 环境现状（probe @ {doc['date']}，schema {doc['schema']}）")
L.append("")
L.append("| 项 | 值 |")
L.append("|---|---|")
L.append(f"| 机器 | {doc['machine']} |")
L.append(f"| 系统 | {doc['os']}（内核 {doc['kernel']}）|")
L.append(f"| 共享锚点 | {a['share']}（状态 {a['state']}）|")
L.append(f"| Common 可写 | {f['common_writable']} ｜ Local 可写 | {f['local_writable']} |")
L.append(f"| fstab 后端条目 | {f['fstab_backend']} |")
L.append(f"| config/env.sh | {f['env_sh_applied']} ｜ 骨架 | {f['skeleton_ready']} ｜ AGENTS.md | {f['agents_md']} ｜ IDE | {f['ide_ready']} |")
L.append(f"| XDG | {v['xdg_doc'] or '未重定向'} |")
L.append(f"| 根盘 | 已用 {v['disk_root_used']}（剩 {v['disk_root_free_g']}G）|")
L.append("")
L.append("| 工具 | 版本 |")
L.append("|---|---|")
for k in sorted(t):
    L.append(f"| {k} | {t[k]} |")
L.append("")
L.append("## 构建进度")
L.append("")
L.append("```")
L.append(os.environ.get("BDE_PROGRESS", "").rstrip())
L.append("```")
L.append("")
pending = os.environ.get("BDE_PENDING_TXT", "").rstrip()
L.append("## 待办（pending）")
L.append("")
L.append(pending if pending else "- 无（init 全默认执行）")
L.append("")
L.append("## 数据快照")
L.append("")
L.append(f"- 本报告数据源：`$DEV/docs/state/probe.json`（schema {doc['schema']}，视图唯一数据源）")
with open(os.environ["BDE_OUT"], "w") as fh:
    fh.write("\n".join(L) + "\n")
print(f"[✓] 报告 → {os.environ['BDE_OUT']}")
PYEOF
