#!/usr/bin/env bash
# init.sh — BestDevEnv 总入口
# 模式：默认全量幂等执行；--resume 续建（跳过已完成阶段）；--status 查看进度；--reset 清空进度
# 用法：./init.sh [--yes] [--resume|--rerun] [--status] [--reset] [--dry-run]
#             [--machine X] [--profile ml-trainer,…] [--langs node,python] [--tools a,b]
#             [--no-xdg] [--no-log]
# 交互：角色/语言栈与 vibecoding 工具未显式传旗标时交互询问（--yes/非 tty 自动取默认——bootstrap 免疫）
set -uo pipefail

BDE_ROOT="$(cd "$(dirname "$0")" && pwd)"
source "$BDE_ROOT/lib/paths.sh"
source "$BDE_ROOT/lib/common.sh"
source "$BDE_ROOT/lib/ensure.sh"
source "$BDE_ROOT/lib/cap.sh"

BDE_ASSUME_YES="${BDE_ASSUME_YES:-0}"
BDE_RESUME=0; BDE_RERUN=0; BDE_STATUS_ONLY=0; BDE_RESET=0
BDE_MACHINE="${BDE_MACHINE:-$(hostname)}"
# 机器名小写归一（hosts.toml/storage.toml 机器段与进度文件统一按小写键匹配）
BDE_MACHINE="$(printf '%s' "$BDE_MACHINE" | tr '[:upper:]' '[:lower:]')"
BDE_PROFILE=""
BDE_LANGS="node,python"
BDE_TOOLS="claude-code,codex,zcode,arkcli"
BDE_PROFILE_SET=0; BDE_LANGS_SET=0; BDE_TOOLS_SET=0   # 旗标显式传入标记（显式 = 跳过询问，仍走校验）
BDE_DRY_RUN=0
BDE_XDG="y"
BDE_JB_SKIP="${BDE_JB_SKIP:-0}"

while [ $# -gt 0 ]; do
    case "$1" in
        --yes)     BDE_ASSUME_YES=1 ;;
        --resume)  BDE_RESUME=1 ;;
        --rerun)   BDE_RERUN=1; BDE_RESUME=0 ;;
        --status)  BDE_STATUS_ONLY=1 ;;
        --reset)   BDE_RESET=1 ;;
        --dry-run) BDE_DRY_RUN=1 ;;
        --machine) shift; BDE_MACHINE=$1 ;;
        --profile) shift; BDE_PROFILE=$1; BDE_PROFILE_SET=1 ;;
        --langs)   shift; BDE_LANGS=$1; BDE_LANGS_SET=1 ;;
        --tools)   shift; BDE_TOOLS=$1; BDE_TOOLS_SET=1 ;;
        --no-xdg)  BDE_XDG="n" ;;
        --no-jetbrains) BDE_JB_SKIP=1 ;;
        --no-log)  BDE_NO_LOG=1 ;;
        *) echo "未知参数：$1"; echo "可用：--yes --resume --rerun --status --reset --dry-run --machine --profile --langs --tools --no-xdg --no-jetbrains --no-log"; exit 2 ;;
    esac
    shift
done
export BDE_ASSUME_YES BDE_MACHINE BDE_RESUME BDE_RERUN BDE_PROFILE BDE_LANGS BDE_TOOLS BDE_XDG BDE_JB_SKIP

# ===== 需求校验（按开发者需求安装：合法集取事实源，非法项响亮剔除）=====
# 语言合法集 = modules/lang/*.sh；工具合法集 = modules/agent/runtimes.tsv 注册表 name 列
bde_csv_validate() {  # <csv> <默认csv> <类别名> <合法项...> → echo 清洗后 csv（空则回退默认）
    # 注意：本函数在命令替换内执行——日志必须走 stderr，否则会污染捕获的返回值
    local csv=$1 dft=$2 label=$3 _list
    shift 3
    local out="" t hit v
    IFS=',' read -ra _bde_csv_items <<< "$csv"
    for t in "${_bde_csv_items[@]}"; do
        t="$(printf '%s' "$t" | tr -d '[:space:]')"
        [ -n "$t" ] || continue
        hit=0
        for v in "$@"; do [ "$t" = "$v" ] && hit=1 && break; done
        if [ "$hit" != "1" ]; then
            _list="$(printf '%s/' "$@")"
            bde_pending "$label 非法项已剔除: $t（可选: ${_list%/}）——已按其余项继续" >&2
            continue
        fi
        case ",$out," in *",$t,"*) continue ;; esac   # 去重（重复项靠幂等无害，但计划显示不干净）
        out="${out:+$out,}$t"
    done
    [ -n "$out" ] || { bde_pending "$label 全部非法，回退默认: $dft" >&2; out="$dft"; }
    printf '%s\n' "$out"
}

# OS 检测（能力家族归并：M1 编排平台无关，差异全部在 adapters/<family>.sh——宪法延伸）
BDE_OS_ID="$(. /etc/os-release 2>/dev/null; printf '%s' "${ID:-unknown}")"
BDE_CAP_FAMILY="$(bde_os_family)"
case "$BDE_CAP_FAMILY" in
    debian|fedora|arch|suse|darwin) BDE_OS_READY=1 ;;
    *)                              BDE_OS_READY=0 ;;
esac
export BDE_OS_ID BDE_CAP_FAMILY

BDE_PROGRESS_DIR="${BDE_PROGRESS_DIR:-$DEV/docs/progress}"
mkdir -p "$BDE_PROGRESS_DIR" 2>/dev/null || true

# 执行留痕（全量输出落日志，便于事后排查；--no-log 关闭）
if [ "${BDE_NO_LOG:-0}" != "1" ]; then
    BDE_LOG="$BDE_PROGRESS_DIR/init-$(date +%F-%H%M%S).log"
    exec > >(tee -a "$BDE_LOG") 2>&1
fi

# --reset / --status 快速通道
if [ "$BDE_RESET" = "1" ]; then
    rm -f "$(bde_progress_file)" && bde_ok "进度已清空：$(bde_progress_file)"
fi
if [ "$BDE_STATUS_ONLY" = "1" ]; then
    bde_info "构建进度（状态文件：$(bde_progress_file)）"
    bde_progress_show
    exit 0
fi

BDE_CONST_V="$(sed -n 's/^| 版本 | \*\*v\([0-9.]*\).*/\1/p' "$COMMON/docs/dev-env/design.md" 2>/dev/null | head -1)"
bde_info "BestDevEnv init ｜ 宪法 devspace-design.md ${BDE_CONST_V:-未知（design.md 未达，动态读取）} ｜ 锚点: $SHARE（$BDE_SHARE_STATE）｜ OS: $BDE_OS_ID"
bde_info "模式: $([ "$BDE_RESUME" = "1" ] && echo '续建（跳过已完成阶段）' || echo '全量幂等')"
bde_progress_show

# ===== 需求解析：交互询问（未显式传旗标时）→ 合法集校验 =====
# 角色档案（profiles.tsv：开发者类型 → 语言栈集合，数据驱动注册表）优先于裸栈名——
# 问"你是什么开发者"比问"要装哪些栈"更贴近需求；--langs 仍可叠加/覆盖。
_lang_valid=""
for _f in "$BDE_ROOT"/modules/lang/*.sh; do
    [ -f "$_f" ] || continue
    _lang_valid+="$(basename "$_f" .sh) "
done
_tool_valid=""
while IFS='|' read -r _n _rest; do
    case "${_n:-}" in ''|'#'*) continue ;; esac
    _tool_valid+="$_n "
done < "$BDE_ROOT/modules/agent/runtimes.tsv"
_profile_valid=""
while IFS='|' read -r _r _rest; do
    case "${_r:-}" in ''|'#'*) continue ;; esac
    _profile_valid+="$_r "
done < "$BDE_ROOT/modules/lang/profiles.tsv"

if [ "$BDE_DRY_RUN" != "1" ] && [ -t 0 ] && [ "$BDE_ASSUME_YES" != "1" ]; then
    if [ "$BDE_PROFILE_SET" != "1" ]; then
        _list="$(printf '%s/' $_profile_valid)"
        bde_info "开发者角色: ${_list%/}（回车=不按角色，直接选栈）"
        bde_ask_multi BDE_PROFILE "你是什么开发者（逗号分隔多选）" ""
    fi
    if [ "$BDE_TOOLS_SET" != "1" ]; then
        _list="$(printf '%s/' $_tool_valid)"
        bde_info "可选 vibecoding 工具: ${_list%/}（回车=默认 $BDE_TOOLS）"
        bde_ask_multi BDE_TOOLS "要安装的 vibecoding 工具（逗号分隔多选）" "$BDE_TOOLS"
    fi
elif [ "$BDE_DRY_RUN" != "1" ]; then
    bde_info "非交互模式：角色/语言栈/工具取旗标或默认（角色: ${BDE_PROFILE:-无} ｜ 语言栈: $BDE_LANGS ｜ 工具: $BDE_TOOLS）"
fi
BDE_PROFILE="$(bde_csv_validate "$BDE_PROFILE" "" "开发者角色" $_profile_valid)"

# 角色展开 → 语言栈集合并集（profiles.tsv 第 3 列；角色给了栈则替代裸默认，--langs 显式叠加）
_profile_stacks=""
if [ -n "$BDE_PROFILE" ]; then
    IFS=',' read -ra _bde_profs <<< "$BDE_PROFILE"
    for _p in "${_bde_profs[@]}"; do
        _p="$(echo "$_p" | tr -d ' ')"
        [ -n "$_p" ] || continue
        _ps="$(awk -F'|' -v r="$_p" '$1==r{print $3}' "$BDE_ROOT/modules/lang/profiles.tsv" 2>/dev/null)"
        [ -n "$_ps" ] || continue
        IFS=',' read -ra _psa <<< "$_ps"
        for _s in "${_psa[@]}"; do
            _s="$(echo "$_s" | tr -d ' ')"
            [ -n "$_s" ] || continue
            case ",$_profile_stacks," in *",$_s,"*) continue ;; esac
            _profile_stacks="${_profile_stacks:+$_profile_stacks,}$_s"
        done
    done
fi
if [ -n "$_profile_stacks" ] && [ "$BDE_LANGS_SET" != "1" ]; then
    BDE_LANGS="$_profile_stacks"
elif [ -n "$_profile_stacks" ]; then
    BDE_LANGS="$_profile_stacks,$BDE_LANGS"
fi

if [ "$BDE_DRY_RUN" != "1" ] && [ -t 0 ] && [ "$BDE_ASSUME_YES" != "1" ] && [ "$BDE_LANGS_SET" != "1" ]; then
    _list="$(printf '%s/' $_lang_valid)"
    bde_info "可选语言栈: ${_list%/}（回车=默认 $BDE_LANGS）"
    bde_ask_multi BDE_LANGS "要安装的语言栈（逗号分隔多选，可叠加）" "$BDE_LANGS"
fi
BDE_LANGS="$(bde_csv_validate "$BDE_LANGS" "node,python" "语言栈" $_lang_valid)"
BDE_TOOLS="$(bde_csv_validate "$BDE_TOOLS" "claude-code,codex,zcode,arkcli" "vibecoding 工具" $_tool_valid)"
export BDE_LANGS BDE_TOOLS

# ===== 构建计划（确认摘要；--dry-run 只预览不执行）=====
bde_info "构建计划：OS=$BDE_OS_ID（M1: family=$BDE_CAP_FAMILY $([ "$BDE_OS_READY" = "1" ] && echo 'baseline.sh' || echo '跳过——OS 未支持')）｜ 角色: $(printf '%s' "${BDE_PROFILE:-无}" | tr ',' ' ') ｜ 语言栈: $(printf '%s' "$BDE_LANGS" | tr ',' ' ') ｜ 工具: $(printf '%s' "$BDE_TOOLS" | tr ',' ' ')"
if [ "$BDE_DRY_RUN" = "1" ]; then
    bde_info "dry-run 结束（未执行任何阶段；实际构建去掉 --dry-run，或先 --status 查看续建进度）"
    exit 0
fi

bde_ask BDE_GO "开始构建？(y/n)" "y"
[ "$BDE_GO" = "y" ] || { bde_info "已取消（EOF/非 y 均不开工；回车=y 保持全默认）"; exit 0; }

# ===== 阶段执行（--resume 时跳过 done 阶段；计数经 lib include guard 跨阶段累计）=====
if bde_should_run M2; then
    bde_phase_begin M2
    source "$BDE_ROOT/modules/dirs/linux.sh"
    bde_phase_end M2
fi

source "$BDE_ROOT/lib/paths.sh"   # 重新解析锚点（M2 已建 /Share）

if bde_should_run M1; then
    bde_phase_begin M1
    if [ "$BDE_OS_READY" = "1" ]; then
        source "$BDE_ROOT/modules/os/baseline.sh"
    else
        bde_pending "OS 未支持（$BDE_OS_ID，family=$BDE_CAP_FAMILY）：M1 系统基线跳过（支持：debian/fedora/arch/suse 家族 + darwin 基础；windows 走 init.ps1）"
    fi
    bde_phase_end M1
fi
if bde_should_run "M1.5:config"; then
    bde_phase_begin "M1.5:config"
    source "$BDE_ROOT/modules/os/apply-config.sh"
    bde_phase_end "M1.5:config"
fi
if bde_should_run "M1.6:cfg"; then
    bde_phase_begin "M1.6:cfg"
    source "$BDE_ROOT/modules/cfg/cfg.sh"
    bde_phase_end "M1.6:cfg"
fi

IFS=',' read -ra _bde_langs <<< "$BDE_LANGS"
for _l in "${_bde_langs[@]}"; do
    _l="$(echo "$_l" | tr -d ' ')"
    if [ ! -f "$BDE_ROOT/modules/lang/$_l.sh" ]; then
        bde_pending "语言脚本不存在: $_l"
        continue
    fi
    if bde_should_run "M3:$_l"; then
        bde_phase_begin "M3:$_l"
        source "$BDE_ROOT/modules/lang/$_l.sh"
        bde_phase_end "M3:$_l"
    fi
done

if bde_should_run "M4:tools"; then
    bde_phase_begin "M4:tools"
    source "$BDE_ROOT/modules/agent/tools.sh"
    bde_phase_end "M4:tools"
fi
if bde_should_run "M4:agents-md"; then
    bde_phase_begin "M4:agents-md"
    source "$BDE_ROOT/modules/agent/agents-md.sh"
    bde_phase_end "M4:agents-md"
fi
if bde_should_run "M4:runtime"; then
    bde_phase_begin "M4:runtime"
    source "$BDE_ROOT/modules/agent/runtime.sh"
    bde_phase_end "M4:runtime"
fi
if bde_should_run "M6:ide"; then
    bde_phase_begin "M6:ide"
    source "$BDE_ROOT/modules/ide/ide.sh"
    bde_phase_end "M6:ide"
fi
if bde_should_run M5; then
    bde_phase_begin M5
    source "$BDE_ROOT/modules/doc/report.sh"
    bde_phase_end M5
fi

bde_summary
bde_info "进度文件：$(bde_progress_file)（--status 查看 ｜ --resume 续建 ｜ --reset 重置）"
