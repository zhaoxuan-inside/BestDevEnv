#!/usr/bin/env bash
# orch — 编排进度日志（主 Skill 专用：多子 Skill 长任务的进度落盘、跨会话续做与步骤改判回退）
# 日志位置：$DEV/docs/progress/orch-<时间戳>.md（本机活状态住 DevEnv；markdown 便于人读+LLM 读写）
# 账本结构（三分区各归其位）：
#   ## 计划    —— 步骤复选框行（- [ ] N. 子skill —— 职责；add 落此区）
#   ## 记录    —— 时间线备注行（↳ [步骤N] 完成/失败/改判；done/fail/revert 落此区）
#   ## 续做指针 —— 续做指针行（> 续做: ...；next 落此区，全文件最后一节）
# 用法: devenv orch <cmd> [args]
#   new <目标>                创建编排日志（自动记录机器/OS/doctor 快照），输出日志路径
#   add <子skill> <职责>      追加计划步骤（自动编号，按依赖顺序逐条登记）
#   done <序号> <结果说明>    标记第 n 步完成（附说明与 doctor 复查结论）
#   fail <序号> <结果说明>    标记第 n 步失败（附原因与已尝试动作）
#   revert <序号> <原因>      步骤改判回待做（撤销标记 + 记录原因 + 打印该步可用的回退素材指引）
#   edit <序号> <新职责>      计划修订（改步骤描述并重置待做；留痕记录旧值→新值）
#   drop <序号> [原因]        计划裁剪（[-] 标记保留历史；status 单列计数）
#   next [说明]               无参=查看续做指针；有参=设置续做指针（调度每步前写）
#   status [日志文件]         查看进度（默认最新一份；未完成时给出续做/改判指引）
#   list                      列出全部编排日志（最新优先）
[ -n "${BDE_ROOT:-}" ] || BDE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$BDE_ROOT/lib/paths.sh"

ORCH_DIR="${BDE_ORCH_DIR:-$DEV/docs/progress}"
mkdir -p "$ORCH_DIR" 2>/dev/null

_latest()  { ls -1t "$ORCH_DIR"/orch-*.md 2>/dev/null | head -1; }
_doctor()  { bash "$BDE_ROOT/verify/doctor.sh" 2>/dev/null | tail -1 | sed 's/doctor：/doctor /'; }
_num_ok()  { [ -n "$1" ] && [ "${1//[!0-9]/}" = "$1" ]; }

# 分区插入：把一行插到首个与标题整行相等的行之前；无匹配则落文件尾（兼容旧版无分区账本）。
# 用 ENVIRON 传值而非 awk -v：ENVIRON 原样透传，说明文字里的反斜杠/换行不会被 awk 转义吃掉。
_ins_before() {  # <文件> <行内容(无换行)> <标题> [备用标题]
    local _f="$1" _line="$2"; shift 2
    local _t; _t="$(mktemp "$ORCH_DIR/.tmp.XXXXXX")"
    if _line="$_line" _h1="${1:-}" _h2="${2:-}" awk '
        { if (!_ins && ($0 == ENVIRON["_h1"] || (ENVIRON["_h2"] != "" && $0 == ENVIRON["_h2"]))) { print ENVIRON["_line"]; _ins=1 } }
        { print }
        END { if (!_ins) print ENVIRON["_line"] }
    ' "$_f" > "$_t"; then
        mv "$_t" "$_f"
    else
        rm -f "$_t"; return 1
    fi
}

# 记录区追加一行（↳ 时间线备注：插在续做指针节之前；旧账本无该节则落文件尾）
_ins_record() { _ins_before "$1" "$2" "## 续做指针"; }

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
        _ins_before "$_f" "$(printf -- '- [ ] %d. %s —— %s' "$_n" "$2" "$3")" "## 记录" "## 续做指针"
        echo "已登记步骤 $_n: $2（$3）"
        ;;
    done|fail)
        _f="$(_latest)"; [ -n "$_f" ] || { echo "无编排日志"; exit 1; }
        _num_ok "${2:-}" || { echo "用法: orch $1 <序号> <说明>"; exit 2; }
        _mark="x"; _tag="完成"; [ "$1" = "fail" ] && { _mark="!"; _tag="失败"; }
        # GNU sed -i 专属（mac 需 'sed -i ''' 语法）——编排日志仅 Linux 机器维护
        sed -i "s|^- \[.\] ${2}\. |- [$_mark] ${2}. |" "$_f" \
            && _ins_record "$_f" "$(printf -- '  ↳ [步骤%s] %s（%s）: %s ｜ %s' "$2" "$_tag" "$(date '+%F %T')" "${3:-}" "$(_doctor)")"
        echo "步骤 ${2} 已记 $_tag"
        ;;
    edit)
        _f="$(_latest)"; [ -n "$_f" ] || { echo "无编排日志"; exit 1; }
        _num_ok "${2:-}" && [ -n "${3:-}" ] || { echo "用法: orch edit <序号> <新职责>"; exit 2; }
        grep -qE "^- \[.\] ${2}\. " "$_f" || { echo "步骤 ${2} 不存在于账本：$_f"; exit 1; }
        _old="$(grep -E "^- \[.\] ${2}\. " "$_f" | head -1 | sed 's/^- \[.\] [0-9]*\. //')"
        _t="$ORCH_DIR/.tmp.XXXXXX"; _t="$(mktemp "$_t")"
        _n="$2" _new="$3" awk '
            $0 ~ "^- \\[.\\] " ENVIRON["_n"] "\\. " { print "- [ ] " ENVIRON["_n"] ". " ENVIRON["_new"]; next }
            { print }
        ' "$_f" > "$_t" && mv "$_t" "$_f" \
            && _ins_record "$_f" "$(printf -- '  ↳ [步骤%s] 计划修订（%s）: %s → %s' "$2" "$(date '+%F %T')" "$_old" "$3")" \
            && echo "步骤 ${2} 已修订: $3"
        ;;
    drop)
        _f="$(_latest)"; [ -n "$_f" ] || { echo "无编排日志"; exit 1; }
        _num_ok "${2:-}" || { echo "用法: orch drop <序号> [原因]"; exit 2; }
        grep -qE "^- \[.\] ${2}\. " "$_f" || { echo "步骤 ${2} 不存在于账本：$_f"; exit 1; }
        sed -i "s|^- \[.\] ${2}\. |- [-] ${2}. |" "$_f" \
            && _ins_record "$_f" "$(printf -- '  ↳ [步骤%s] 计划裁剪（%s）: %s' "$2" "$(date '+%F %T')" "${3:-未说明原因}")" \
            && echo "步骤 ${2} 已裁剪（[-] 标记，保留历史）"
        ;;
    revert)
        _f="$(_latest)"; [ -n "$_f" ] || { echo "无编排日志"; exit 1; }
        _num_ok "${2:-}" || { echo "用法: orch revert <序号> <原因>"; exit 2; }
        grep -qE "^- \[.\] ${2}\. " "$_f" || { echo "步骤 ${2} 不存在于账本：$_f"; exit 1; }
        sed -i "s|^- \[.\] ${2}\. |- [ ] ${2}. |" "$_f" \
            && _ins_record "$_f" "$(printf -- '  ↳ [步骤%s] 改判待做（%s）: %s ｜ %s' "$2" "$(date '+%F %T')" "${3:-}" "$(_doctor)")"
        echo "步骤 ${2} 已改判回待做。该步已产生写入时的回退素材（按需取用）:"
        echo "  - 修改前文件备份: $DEV/docs/backup/（ensure_backup 时间戳版本，取该步改动前的最近一份）"
        echo "  - 配置正本历史: git -C $COMMON/config log/diff；更早时点: git -C $BDE_ROOT checkout <commit> -- config && devenv cfg restore"
        echo "  - 改后核对: devenv doctor ｜ devenv cfg diff（确认回到预期实态再重新调度本步）"
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
        _c="$(grep -cE '^- \[-\] [0-9]+\.' "$_f")"
        echo "== $(head -1 "$_f") =="
        echo "日志: $_f"
        echo "进度: $_d/$_t 完成 ｜ 失败 $_e ｜ 待做 $_p ｜ 裁剪 $_c"
        if [ "$_e" -gt 0 ]; then
            echo "失败步骤（修复后 orch done 改判完成；方向错了 orch revert 改判回待做）:"
            grep -E '^- \[!\] [0-9]+\.' "$_f" | sed 's/^- \[!\] /  /'
        fi
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
        echo "用法: devenv orch new|add|done|fail|revert|edit|drop|next|status|list"; exit 2 ;;
esac
