#!/usr/bin/env bash
# init.sh — BestDevEnv 总入口
# 模式：默认全量幂等执行；--resume 续建（跳过已完成阶段）；--status 查看进度；--reset 清空进度
# 用法：./init.sh [--yes] [--resume|--rerun] [--status] [--reset]
#             [--machine X] [--langs node,python] [--tools a,b] [--no-xdg] [--no-log]
set -uo pipefail

BDE_ROOT="$(cd "$(dirname "$0")" && pwd)"
source "$BDE_ROOT/lib/paths.sh"
source "$BDE_ROOT/lib/common.sh"
source "$BDE_ROOT/lib/ensure.sh"

BDE_ASSUME_YES="${BDE_ASSUME_YES:-0}"
BDE_RESUME=0; BDE_RERUN=0; BDE_STATUS_ONLY=0; BDE_RESET=0
BDE_MACHINE="${BDE_MACHINE:-$(hostname)}"
BDE_LANGS="node,python"
BDE_TOOLS="claude-code,codex,zcode,arkcli"
BDE_XDG="y"
BDE_JB_SKIP="${BDE_JB_SKIP:-0}"

while [ $# -gt 0 ]; do
    case "$1" in
        --yes)     BDE_ASSUME_YES=1 ;;
        --resume)  BDE_RESUME=1 ;;
        --rerun)   BDE_RERUN=1; BDE_RESUME=0 ;;
        --status)  BDE_STATUS_ONLY=1 ;;
        --reset)   BDE_RESET=1 ;;
        --machine) shift; BDE_MACHINE=$1 ;;
        --langs)   shift; BDE_LANGS=$1 ;;
        --tools)   shift; BDE_TOOLS=$1 ;;
        --no-xdg)  BDE_XDG="n" ;;
        --no-jetbrains) BDE_JB_SKIP=1 ;;
        --no-log)  BDE_NO_LOG=1 ;;
        *) echo "未知参数：$1"; echo "可用：--yes --resume --rerun --status --reset --machine --langs --tools --no-xdg --no-jetbrains --no-log"; exit 2 ;;
    esac
    shift
done
export BDE_ASSUME_YES BDE_MACHINE BDE_RESUME BDE_RERUN BDE_LANGS BDE_TOOLS BDE_XDG BDE_JB_SKIP

# OS 检测（选择 M1 脚本变体；M2 linux.sh 为 Linux 通用，不分支）
BDE_OS_ID="$(. /etc/os-release 2>/dev/null; printf '%s' "${ID:-unknown}")"
case "$BDE_OS_ID" in
    ubuntu|debian|linuxmint)            BDE_OS_SCRIPT="ubuntu.sh" ;;
    arch|manjaro|endeavouros|garuda)    BDE_OS_SCRIPT="arch.sh" ;;
    *)                                  BDE_OS_SCRIPT="" ;;
esac
export BDE_OS_ID

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

bde_info "BestDevEnv init ｜ 宪法 devspace-design.md v8.4 ｜ 锚点: $SHARE（$BDE_SHARE_STATE）｜ OS: $BDE_OS_ID"
bde_info "模式: $([ "$BDE_RESUME" = "1" ] && echo '续建（跳过已完成阶段）' || echo '全量幂等')"
bde_progress_show
bde_ask BDE_GO "开始构建？(y/n)" "y"
[ "$BDE_GO" = "y" ] || { bde_info "已取消"; exit 0; }

# ===== 阶段执行（--resume 时跳过 done 阶段；计数经 lib include guard 跨阶段累计）=====
if bde_should_run M2; then
    bde_phase_begin M2
    source "$BDE_ROOT/modules/dirs/linux.sh"
    bde_phase_end M2
fi

source "$BDE_ROOT/lib/paths.sh"   # 重新解析锚点（M2 已建 /Share）

if bde_should_run M1; then
    bde_phase_begin M1
    if [ -n "$BDE_OS_SCRIPT" ] && [ -f "$BDE_ROOT/modules/os/$BDE_OS_SCRIPT" ]; then
        source "$BDE_ROOT/modules/os/$BDE_OS_SCRIPT"
    else
        bde_pending "OS 未支持（$BDE_OS_ID）：M1 系统基线跳过（支持：ubuntu/debian/arch 系）"
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
