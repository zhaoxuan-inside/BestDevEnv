#!/usr/bin/env bash
# modules/doc/brief.sh — 会话速览（一次 probe 采集的固定摘要；主 Skill「探环境」首选命令）
# 设计：把人肉串起来的多条只读命令（probe/doctor/cfg list/app --all）压成一条——
#       Agent 每会话都要付的固定成本从 ~30s 降到 ~6s；要逐项 ✓/✗ 再看 devenv doctor
# 纯视图：不含采集逻辑（bde_probe_save 即唯一数据源，宪法 §19.5）
[ -n "${BDE_ROOT:-}" ] || BDE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$BDE_ROOT/lib/paths.sh"
source "$BDE_ROOT/lib/probe.sh"

bde_probe_save >/dev/null || { echo "✗ probe 采集失败——devenv doctor 看细节"; exit 1; }

# 编排续做指针（长任务跨会话：有账本就报最后一条）
_orch="$(ls -1t "$DEV/80_Records/00_Progress"/orch-*.md 2>/dev/null | head -1)"
_orch_txt="（无编排日志）"
if [ -n "$_orch" ]; then
    _done="$(grep -cE '^- \[x\] [0-9]+\.' "$_orch" 2>/dev/null)"
    _all="$(grep -cE '^- \[.\] [0-9]+\.' "$_orch" 2>/dev/null)"
    _ptr="$(grep '^> 续做:' "$_orch" 2>/dev/null | head -1 | sed 's/^> 续做: //')"
    _orch_txt="$_done/$_all 完成$([ -n "$_ptr" ] && printf ' ｜ 续做 %s' "$_ptr")"
fi

_legacy="${P_NAME_LEGACY:-0}"
_gen="$([ "${P_GEN_FRESH:-0}" = "1" ] && echo "同代 ✓" || echo "过期（devenv gen）")"
_alert=0
for _v in "${P_CFG_DRIFT:-0}" "${P_DIR_UNREG:-0}" "${P_ANCHOR_STALE:-0}" "${P_HOME_STRAY:-0}"; do
    [ "${_v:-0}" -gt 0 ] 2>/dev/null && _alert=$((_alert+1))
done
[ "${P_GEN_FRESH:-0}" != "1" ] && _alert=$((_alert+1))

printf 'devenv brief — %s @ %s（%s ｜ 内核 %s）\n' "$P_HOST" "$P_DATE" "$P_OS" "$P_KERNEL"
printf '③ %s（%s%s）｜② %s（%s%s）｜① %s\n' \
    "$COMMON" "$P_BACKEND_COMMON" "$([ "$P_PERSIST_COMMON" = "1" ] && echo '·已持久化')" \
    "$LOCAL" "$P_BACKEND_HOST" "$([ "$P_PERSIST_HOST" = "1" ] && echo '·已持久化')" "$DEV"
printf '工程根 %s ｜ 根盘剩 %.1fG\n' "$BDE_ROOT" "$(awk "BEGIN{printf \"%.1f\", ${P_DISK_ROOT_FREE_MB:-0}/1024}")"
if [ "${P_CAP_PROBED:-0}" = "1" ]; then
    printf '共享盘能力 symlink=%s hardlink=%s 大小写敏感=%s 权限=%s 文件名255B=%s\n' \
        "$P_CAP_SYMLINK" "$P_CAP_HARDLINK" "$P_CAP_CASE" "$P_CAP_PERM" "$P_CAP_NAME255"
fi
printf '待处置 配置漂移 %s ｜ 未登记目录 %s ｜ 存量命名 %s ｜ 锚点失效 %s ｜ gen %s\n' \
    "${P_CFG_DRIFT:-0}" "${P_DIR_UNREG:-0}" "$_legacy" "${P_ANCHOR_STALE:-0}" "$_gen"
[ -n "${P_RUNTIME_MISSING:-}" ] && printf '应装未装 runtime：%s\n' "$P_RUNTIME_MISSING"
printf '编排 %s\n' "$_orch_txt"
if [ "$_alert" -gt 0 ]; then
    printf '→ 有事项待处置：devenv doctor（逐项）/ devenv lint（锚点明细）/ devenv cfg diff\n'
else
    printf '→ 环境无待处置项；需要逐项验收时 devenv doctor\n'
fi
