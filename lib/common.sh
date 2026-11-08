#!/usr/bin/env bash
# lib/common.sh — 日志 / 交互 / 计数 / 摘要（M0）
[ -n "${BDE_COMMON_LOADED:-}" ] && return 0
BDE_COMMON_LOADED=1

if [ -t 1 ]; then
    C_G=$'\e[32m'; C_Y=$'\e[33m'; C_R=$'\e[31m'; C_B=$'\e[36m'; C_0=$'\e[0m'
else
    C_G=""; C_Y=""; C_R=""; C_B=""; C_0=""
fi

BDE_DONE=0; BDE_SKIP=0; BDE_FAIL=0
BDE_PENDINGS=(); BDE_PENDING_N=0

bde_info()  { printf "%s[*]%s %s\n" "$C_B" "$C_0" "$*"; }
bde_ok()    { printf "%s[✓]%s %s\n" "$C_G" "$C_0" "$*"; BDE_DONE=$((BDE_DONE+1)); }
bde_skip()  { printf "%s[=]%s %s\n"  "$C_Y" "$C_0" "$*"; BDE_SKIP=$((BDE_SKIP+1)); }
bde_fail()  { printf "%s[✗]%s %s\n" "$C_R" "$C_0" "$*"; BDE_FAIL=$((BDE_FAIL+1)); }
bde_pending() { printf "%s[⏳]%s %s\n" "$C_Y" "$C_0" "$*"; BDE_PENDINGS+=("$*"); BDE_PENDING_N=$((BDE_PENDING_N+1)); }

# 单值询问：bde_ask 变量名 提示 默认值（非交互/--yes 时取默认）
bde_ask() {
    local __var=$1 __q=$2 __d=$3 __a=""
    if [ "${BDE_ASSUME_YES:-0}" = "1" ] || [ ! -t 0 ]; then
        printf -v "$__var" "%s" "$__d"; return
    fi
    read -r -p "$__q [$__d] " __a || __a="$__d"
    printf -v "$__var" "%s" "${__a:-$__d}"
}

# 列表询问：bde_ask_multi 变量名 提示 默认csv
bde_ask_multi() {
    local __var=$1 __q=$2 __d=$3 __a=""
    if [ "${BDE_ASSUME_YES:-0}" = "1" ] || [ ! -t 0 ]; then
        printf -v "$__var" "%s" "$__d"; return
    fi
    bde_info "$__q（逗号分隔，回车=默认：$__d）"
    read -r -p "> " __a || __a="$__d"
    printf -v "$__var" "%s" "${__a:-$__d}"
}

# root 命令前缀（sudo 免密可用时返回 "sudo -n"，否则空串）
bde_root() {
    if sudo -n true 2>/dev/null; then echo "sudo -n"; else echo ""; fi
}

bde_summary() {
    echo
    bde_info "========== 执行摘要 =========="
    printf "完成 %d ｜ 跳过 %d ｜ 待办 %d ｜ 失败 %d\n" "$BDE_DONE" "$BDE_SKIP" "$BDE_PENDING_N" "$BDE_FAIL"
    if [ "$BDE_PENDING_N" -gt 0 ]; then
        bde_info "待办清单："
        local p; for p in "${BDE_PENDINGS[@]}"; do printf "  - %s\n" "$p"; done
    fi
    [ "$BDE_FAIL" -eq 0 ]
}

# ===== 执行进度记录（可续建）=====
# 状态文件：~/DevEnv/docs/progress/<机器名>.state，行格式：阶段|状态|时间|done=n,skip=n,pending=n,fail=n
# 状态：done / failed；同阶段多次记录取最近一条
bde_progress_file() {
    printf "%s/%s.state" "${BDE_PROGRESS_DIR:-$DEV/docs/progress}" "${BDE_MACHINE:-$(hostname)}"
}

bde_phase_begin() {
    local p=$1
    mkdir -p "${BDE_PROGRESS_DIR:-$DEV/docs/progress}" 2>/dev/null || true
    BDE_PHASE_BASE_FAIL=$BDE_FAIL;      BDE_PHASE_BASE_DONE=$BDE_DONE
    BDE_PHASE_BASE_SKIP=$BDE_SKIP;      BDE_PHASE_BASE_PENDING=$BDE_PENDING_N
    bde_info "▶ 阶段 $p 开始"
}

bde_phase_end() {
    local p=$1 status="done"
    local d_fail=$((BDE_FAIL - ${BDE_PHASE_BASE_FAIL:-0}))
    [ "$d_fail" -gt 0 ] && status="failed"
    printf '%s|%s|%s|done=%d,skip=%d,pending=%d,fail=%d\n' "$p" "$status" "$(date '+%F %T')" \
        "$((BDE_DONE - ${BDE_PHASE_BASE_DONE:-0}))" "$((BDE_SKIP - ${BDE_PHASE_BASE_SKIP:-0}))" \
        "$((BDE_PENDING_N - ${BDE_PHASE_BASE_PENDING:-0}))" "$d_fail" >> "$(bde_progress_file)" \
        && { [ "$status" = "done" ] && bde_ok "阶段 $p 记入进度（done）" || bde_fail "阶段 $p 记入进度（failed）"; }
}

bde_phase_status() {
    local p=$1 f; f="$(bde_progress_file)"
    [ -f "$f" ] || { echo ""; return; }
    awk -F'|' -v _p="$p" '$1==_p{print $2}' "$f" | tail -1
}

bde_progress_show() {
    local f; f="$(bde_progress_file)"
    if [ ! -f "$f" ]; then bde_info "进度：尚无记录（全新构建）"; return; fi
    bde_info "进度（各阶段最近一次状态）："
    awk -F'|' '{s[$1]=$0} END{for(k in s) print k}' "$f" | sort | while read -r _k; do
        local _line _st _d _c
        _line="$(awk -F'|' -v _kk="$_k" '$1==_kk{print $0}' "$f" | tail -1)"
        _st="$(printf '%s' "$_line" | cut -d'|' -f2)"
        _d="$(printf '%s' "$_line" | cut -d'|' -f3)"
        _c="$(printf '%s' "$_line" | cut -d'|' -f4)"
        case "$_st" in
            done)   printf "%s[✓]%s %-16s %s  %s\n" "$C_G" "$C_0" "$_k" "$_d" "$_c" ;;
            failed) printf "%s[✗]%s %-16s %s  %s\n" "$C_R" "$C_0" "$_k" "$_d" "$_c" ;;
            *)      printf "%s[?]%s %-16s %s  %s\n" "$C_Y" "$C_0" "$_k" "$_d" "$_c" ;;
        esac
    done
}

# 是否应执行该阶段（--resume 时跳过 done；--rerun 强制）
bde_should_run() {
    local p=$1
    if [ "${BDE_RESUME:-0}" = "1" ] && [ "${BDE_RERUN:-0}" != "1" ] \
       && [ "$(bde_phase_status "$p")" = "done" ]; then
        bde_skip "阶段 $p 已完成（--resume 跳过；--rerun 强制重跑）"
        return 1
    fi
    return 0
}
