#!/usr/bin/env bash
# orch — 编排进度日志（主 Skill 专用：多子 Skill 长任务的进度落盘与跨会话续做）
# 日志位置：$DEV/docs/progress/orch-<时间戳>.md（本机活状态住 DevEnv；markdown 便于人读+LLM 读写）
# 用法: devenv orch <cmd> [args]
#   new <目标>                创建编排日志（自动记录机器/OS/doctor 快照），输出日志路径
#   add <子skill> <职责>      追加计划步骤（自动编号，按依赖顺序逐条登记）
#   done <序号> <结果说明>    标记第 n 步完成（附说明与 doctor 复查结论）
#   fail <序号> <结果说明>    标记第 n 步失败（附原因与已尝试动作）
#   next [说明]               无参=查看续做指针；有参=设置续做指针（调度每步前写）
#   status [日志文件]         查看进度（默认最新一份；未完成时给出续做指引）
#   list                      列出全部编排日志（最新优先）
[ -n "${BDE_ROOT:-}" ] || BDE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$BDE_ROOT/lib/paths.sh"

ORCH_DIR="${BDE_ORCH_DIR:-$DEV/docs/progress}"
mkdir -p "$ORCH_DIR" 2>/dev/null

_latest()  { ls -1t "$ORCH_DIR"/orch-*.md 2>/dev/null | head -1; }
_doctor()  { bash "$BDE_ROOT/verify/doctor.sh" 2>/dev/null | tail -1 | sed 's/doctor：/doctor /'; }
_num_ok()  { [ -n "$1" ] && [ "${1//[!0-9]/}" = "$1" ]; }

case "${1:-}" in
    new)
        _goal="${2:-未描述目标}"
        _f="$ORCH_DIR/orch-$(date +%Y%m%d-%H%M%S).md"
        _os="$(. /etc/os-release 2>/dev/null; echo "${ID:-unknown}")"
        {
            echo "# 编排：$_goal"
            echo "- 开始: $(date '+%F %T') ｜ 机器: ${BDE_MACHINE:-$(hostname)} ｜ OS: $_os ｜ 锚点: $SHARE（$BDE_SHARE_STATE）"
            echo "- 探环境: $(_doctor)"
            echo
            echo "## 计划"
            echo "## 记录"
            echo "## 续做指针"
        } > "$_f"
        echo "$_f"
        ;;
    add)
        _f="$(_latest)"; [ -n "$_f" ] || { echo "无编排日志——先 devenv orch new"; exit 1; }
        [ -n "${2:-}" ] && [ -n "${3:-}" ] || { echo "用法: orch add <子skill> <一句话职责>"; exit 2; }
        _n="$(grep -cE '^- \[.\] [0-9]+\.' "$_f" 2>/dev/null)"; _n=$((_n+1))
        printf -- "- [ ] %d. %s —— %s\n" "$_n" "$2" "$3" >> "$_f"
        echo "已登记步骤 $_n: $2（$3）"
        ;;
    done|fail)
        _f="$(_latest)"; [ -n "$_f" ] || { echo "无编排日志"; exit 1; }
        _num_ok "${2:-}" || { echo "用法: orch $1 <序号> <说明>"; exit 2; }
        _mark="x"; _tag="完成"; [ "$1" = "fail" ] && { _mark="!"; _tag="失败"; }
        # GNU sed -i 专属（mac 需 'sed -i ''' 语法）——编排日志仅 Linux 机器维护
        sed -i "s|^- \[.\] ${2}\. |- [$_mark] ${2}. |" "$_f" \
            && printf -- "  ↳ %s（%s）: %s ｜ %s\n" "$_tag" "$(date '+%F %T')" "${3:-}" "$(_doctor)" >> "$_f"
        echo "步骤 ${2} 已记 $_tag"
        ;;
    next)
        _f="$(_latest)"; [ -n "$_f" ] || { echo "无编排日志"; exit 1; }
        if [ -n "${2:-}" ]; then
            sed -i '/^> 续做:/d' "$_f"
            printf -- "> 续做: %s（%s）\n" "$2" "$(date '+%F %T')" >> "$_f"
            echo "续做指针已更新"
        else
            grep '^> 续做:' "$_f" || echo "（未设置续做指针）"
        fi
        ;;
    status)
        _f="${2:-$(_latest)}"; [ -n "$_f" ] && [ -f "$_f" ] || { echo "无编排日志——先 devenv orch new"; exit 1; }
        _t="$(grep -cE '^- \[.\] [0-9]+\.' "$_f")"; _d="$(grep -cE '^- \[x\] [0-9]+\.' "$_f")"
        _e="$(grep -cE '^- \[!\] [0-9]+\.' "$_f")"; _p="$(grep -cE '^- \[ \] [0-9]+\.' "$_f")"
        echo "== $(head -1 "$_f") =="
        echo "日志: $_f"
        echo "进度: $_d/$_t 完成 ｜ 失败 $_e ｜ 待做 $_p"
        [ "$_e" -gt 0 ] && { echo "失败步骤（需先修复或改判）:"; grep -E '^- \[!\] [0-9]+\.' "$_f" | sed 's/^- \[!\] /  /'; }
        grep '^> 续做:' "$_f" 2>/dev/null
        if [ "$_p" -gt 0 ]; then
            echo "下一未完成步骤: $(grep -E '^- \[ \] [0-9]+\.' "$_f" | head -1 | sed 's/^- \[ \] //')"
            echo "续做动作：先重跑探环境（devenv doctor），再从上述步骤调度对应子 Skill（已完成的幂等跳过）"
        elif [ "$_t" -gt 0 ]; then
            echo "编排已全部完成——doctor 终验后向用户报告"
        fi
        ;;
    list)
        _found=0
        for _f in $(ls -1t "$ORCH_DIR"/orch-*.md 2>/dev/null); do
            _found=1
            _d="$(grep -cE '^- \[x\] [0-9]+\.' "$_f")"; _t="$(grep -cE '^- \[.\] [0-9]+\.' "$_f")"
            printf -- "%s ｜ %d/%d ｜ %s\n" "$(basename "$_f")" "$_d" "$_t" "$(head -1 "$_f")"
        done
        [ "$_found" = "0" ] && echo "（无编排日志）"
        ;;
    *)
        echo "用法: devenv orch new|add|done|fail|next|status|list"; exit 2 ;;
esac
