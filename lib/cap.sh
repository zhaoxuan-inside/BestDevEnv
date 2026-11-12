#!/usr/bin/env bash
# lib/cap.sh — L2 能力总线（宪法延伸：先抽象能力，再按平台实现）
# 分层契约：
#   L1 probe    事实采集（不变）
#   L2 cap      能力契约注册 + 分派 + 优雅降级   ← 本文件
#      adapters modules/os/adapters/<family>.sh 平台实现（apt/dnf/pacman/zypper/brew 只出现在这里）
#   L3 编排     modules/os/baseline.sh 等上层只调 cap_run/cap_pkg_install，零平台字面量
#   L4 治理     cfg-map（声明式文件落地）+ doctor/report（消费能力矩阵与事实）
# 分工铁律：正本文件归 cfg-map（数据），生效动作归能力总线（行为），平台字面量只出现在适配器。
#
# 对上层只暴露：
#   cap_load            按本机 OS 家族加载适配器（幂等；BDE_OS_FAMILY 可注入——测试钩子）
#   cap_run <cap> <op> [args…]   分派到适配器 cap__<cap>_<op>；未实现 → pending 降级返回 1，绝不硬崩
#   cap_has <cap> <op>  能力探测（无日志；输出捕获场景先探测再调用）
#   cap_list            能力矩阵视图（doctor/report 消费）
#   cap_pkg_install <语义名…>    语义包安装（别名解析 + 幂等 skip/ok 日志）
# 直接执行：cap.sh list

[ -n "${BDE_CAP_LIB_LOADED:-}" ] && return 0 2>/dev/null || true
BDE_CAP_LIB_LOADED=1
[ -n "${BDE_ROOT:-}" ] || BDE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$BDE_ROOT/lib/common.sh"   # bde_os_id / bde_os_family / 日志原语
source "$BDE_ROOT/lib/paths.sh"    # 锚点上下文自洽（适配器正本路径依赖 $COMMON/$LOCAL——独立执行 cap 也正确）

# 能力契约注册表（cap:op,op,…；新增能力 = 适配器实现函数 + 此处登记一行）
# 注意：op 用下划线命名（bash 函数名无连字符——check_source 曾写作 check-source 致分派失配）
CAP_KNOWN="pkg:installed,install,check_source svc:ensure,active kernel:ensure,get limits:ensure logs:ensure trim:ensure timesync:check,ensure locale:ensure,get zram:ensure power:ensure hostname:get,set fonts:ensure shell:get,set im:ensure terminal:ensure group:ensure"

# —— 适配器加载（幂等；family 归并在 lib/common.sh bde_os_family）——
cap_load() {
    local fam; fam="$(bde_os_family)"
    [ "${BDE_CAP_FAMILY:-}" = "$fam" ] && return 0
    local ad="$BDE_ROOT/modules/os/adapters/$fam.sh"
    if [ -f "$ad" ]; then
        # shellcheck disable=SC1090
        source "$ad"
        BDE_CAP_FAMILY="$fam"
        export BDE_CAP_FAMILY
        return 0
    fi
    BDE_CAP_FAMILY="unknown"
    export BDE_CAP_FAMILY
    bde_pending "无能力适配器：family=$fam（支持 debian/fedora/arch/suse/darwin；windows 走 init.ps1，P3）"
    return 1
}

# —— 能力分派（优雅降级：未实现 → pending + 1；调用方不因平台缺能力而崩）——
cap_run() {  # <cap> <op> [args…]
    cap_load || return 1
    local cap=$1 op=$2; shift 2
    local fn="cap__${cap}_${op}"
    if declare -F "$fn" >/dev/null 2>&1; then
        "$fn" "$@"
        return $?
    fi
    bde_pending "能力未实现：${cap}.${op}（适配器 $BDE_CAP_FAMILY）——诚实降级，不阻塞其他项"
    return 1
}

cap_has() {  # <cap> <op> → 0=已实现（无日志；命令替换捕获输出前先探测）
    cap_load >/dev/null 2>&1 || return 1
    declare -F "cap__${1}_${2}" >/dev/null 2>&1
}

# —— 语义包安装（别名解析收敛在适配器；幂等 skip；多语义名逐个记账）——
cap_pkg_install() {
    cap_load || return 1
    local _rc=0 p pl q all
    for p in "$@"; do
        if declare -F cap__pkg_alias >/dev/null 2>&1; then pl="$(cap__pkg_alias "$p")"; else pl="$p"; fi
        [ -n "$pl" ] || { bde_pending "语义包别名解析为空：$p"; _rc=1; continue; }
        all=1
        for q in $pl; do
            if declare -F cap__pkg_installed >/dev/null 2>&1 && cap__pkg_installed "$q"; then continue; fi
            all=0; break
        done
        if [ "$all" = "1" ]; then bde_skip "软件包已装 $p"; continue; fi
        if cap__pkg_install $pl; then
            bde_ok "安装软件包 $p"
        else
            bde_pending "安装 $p 失败（需检查网络/源/sudo 免密）"
            _rc=1
        fi
    done
    return $_rc
}

# —— 能力矩阵视图（doctor/report 消费；新增能力自动出现在矩阵）——
cap_list() {
    cap_load || true
    bde_info "能力矩阵（适配器：${BDE_CAP_FAMILY:-未加载}）——✓=已实现 -=未实现（降级 pending）"
    local spec cap ops op fn
    for spec in $CAP_KNOWN; do
        cap="${spec%%:*}"; ops="${spec#*:}"
        printf "  %-10s" "$cap"
        local _ifs="$IFS"; IFS=','
        for op in $ops; do
            fn="cap__${cap}_${op}"
            if declare -F "$fn" >/dev/null 2>&1; then printf " %s=✓" "$op"; else printf " %s=-" "$op"; fi
        done
        IFS="$_ifs"
        printf "\n"
    done
}

# 直接执行：cap.sh list
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    case "${1:-list}" in
        list) cap_list ;;
        *)    echo "用法: cap.sh list"; exit 2 ;;
    esac
fi
