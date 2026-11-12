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
# EOF（Ctrl+D/输入流关闭）≠ 确认——返回空串由调用方决定，绝不静默取默认开工
bde_ask() {
    local __var=$1 __q=$2 __d=$3 __a=""
    if [ "${BDE_ASSUME_YES:-0}" = "1" ] || [ ! -t 0 ]; then
        printf -v "$__var" "%s" "$__d"; return
    fi
    if ! read -r -p "$__q [$__d] " __a; then
        printf -v "$__var" ""
        return
    fi
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

# OS 识别（BDE_OS_ID 可外部注入——测试钩子；init.sh 亦导出同语义变量）
bde_os_id() {
    if [ -n "${BDE_OS_ID:-}" ]; then printf '%s\n' "$BDE_OS_ID"; return; fi
    local _id=""; _id="$(. /etc/os-release 2>/dev/null; printf '%s' "${ID:-}")"
    printf '%s\n' "${_id:-unknown}"
}

# cfg-map 机制感知的"生效正本"（probe 漂移巡检与 cfg.sh diff/apply 共用同一判定——宪法 §19.5 同源）：
#   copy-expand → bde_expand_anchors 展开锚点（mktemp 落盘供 cmp）
#   chezmoi(.tmpl) → chezmoi execute-template 用本机数据渲染
#   其余机制 → 原样路径。工具缺失/展开失败返回空串（调用方决定语义）。
# 依赖调用方先 source paths.sh（锚点变量；bde_expand_anchors 所在）。
bde_cfg_effective_src() {  # <src> <mech> → echo 路径（可能为空）
    local src="$1" mech="$2" _t
    case "$mech" in
        copy-expand)
            _t="$(mktemp "${TMPDIR:-/tmp}/bde-cfg-x.XXXXXX" 2>/dev/null)" || return 0
            if bde_expand_anchors "$src" > "$_t" 2>/dev/null; then
                printf '%s\n' "$_t"
            else
                rm -f "$_t"
            fi ;;
        chezmoi)
            if [[ "$src" == *.tmpl ]] && command -v chezmoi >/dev/null 2>&1; then
                _t="$(mktemp "${TMPDIR:-/tmp}/bde-cfg-x.XXXXXX" 2>/dev/null)" || return 0
                # 模板数据正本：state-env 双落位的 chezmoi.toml（缺它 .tmpl 键渲染失败——曾致 user-dirs 假漂移）
                _czc=""
                for _c in "$DEV/xdg/config/chezmoi/chezmoi.toml" \
                          "${XDG_CONFIG_HOME:-$HOME/.config}/chezmoi/chezmoi.toml" \
                          "$HOME/.config/chezmoi/chezmoi.toml"; do
                    [ -f "$_c" ] && { _czc="$_c"; break; }
                done
                if [ -n "$_czc" ] && chezmoi execute-template --config "$_czc" < "$src" > "$_t" 2>/dev/null && [ -s "$_t" ]; then
                    printf '%s\n' "$_t"
                else
                    rm -f "$_t"
                fi
            else
                printf '%s\n' "$src"
            fi ;;
        *) printf '%s\n' "$src" ;;
    esac
}

# OS 家族归并（能力适配器选择 + cfg cond os_family 键共用；BDE_OS_FAMILY 可外部注入——测试钩子）
# 家族 = 能力实现等价类：包管理器/服务管理/内核参数机制相同 → 同一适配器
bde_os_family() {
    if [ -n "${BDE_OS_FAMILY:-}" ]; then printf '%s\n' "$BDE_OS_FAMILY"; return; fi
    case "$(uname -s)" in
        Darwin) printf 'darwin\n'; return ;;
    esac
    case "$(bde_os_id)" in
        ubuntu|debian|linuxmint|pop|kali)       printf 'debian\n' ;;
        fedora|rhel|centos|rocky|alma)          printf 'fedora\n' ;;
        arch|manjaro|endeavouros|garuda)        printf 'arch\n' ;;
        opensuse-leap|opensuse-tumbleweed|sles) printf 'suse\n' ;;
        *)                                      printf 'unknown\n' ;;
    esac
}

# cfg-map 条件列判定（G3/G5：登记表支持按 OS/存储后端条件生效，非适用机器自动缺席不误报）
# 语法：空 = 无条件；`&` 连接多个子句；子句 `key=v1,v2`。key ∈ os | os_family | backend_common | backend_host
#   os=ubuntu,debian,linuxmint        ← bde_os_id（OS 变体）
#   os_family=linux,darwin            ← bde_os_family（能力家族：debian/fedora/arch/suse/darwin/unknown 归并为 linux 系）
#   backend_common=hgfs               ← BDE_SCOPE_SHARED_BACKEND（存储档案解析值）
# 依赖调用方先 source paths.sh（后端变量由 L0 解析层导出）
bde_cfg_cond_ok() {  # <cond> → 0=适用
    [ -z "${1:-}" ] && return 0
    local _tok _k _v _val _c _ok
    local _toks=()
    IFS='&' read -ra _toks <<<"$1"
    for _tok in "${_toks[@]}"; do
        _k="${_tok%%=*}"; _v="${_tok#*=}"
        case "$_k" in
            os)             _val="$(bde_os_id)" ;;
            os_family)      _val="$(bde_os_family)"
                            case "$_val" in debian|fedora|arch|suse) _val="linux" ;; esac ;;
            backend_common) _val="${BDE_SCOPE_SHARED_BACKEND:-unknown}" ;;
            backend_host)   _val="${BDE_SCOPE_HOST_BACKEND:-unknown}" ;;
            *) bde_pending "cfg-map 条件键未知: $_k（支持 os/os_family/backend_common/backend_host）"; return 1 ;;
        esac
        _ok=0
        local _vs=()
        IFS=',' read -ra _vs <<<"$_v"
        for _c in "${_vs[@]}"; do [ "$_c" = "$_val" ] && _ok=1; done
        [ "$_ok" = "1" ] || return 1
    done
    return 0
}

# 锚点变量展开·字符串版（cfg-map 登记行中的应用层路径用——dst 含 ${LOCAL}/${DEV} 等；
# 文件内容版见 lib/paths.sh bde_expand_anchors）
bde_expand_anchors_str() {  # <string> → stdout（展开后）
    local s="$1"
    s="${s//'${DEV}'/$DEV}"
    s="${s//'${COMMON}'/$COMMON}"
    s="${s//'${LOCAL}'/$LOCAL}"
    s="${s//'${SHARE}'/$SHARE}"
    s="${s//'$DEV'/$DEV}"
    s="${s//'$COMMON'/$COMMON}"
    s="${s//'$LOCAL'/$LOCAL}"
    s="${s//'$SHARE'/$SHARE}"
    s="${s/'$HOME'/$HOME}"
    printf '%s\n' "$s"
}

# cfg-map 逐行漂移判定（宪法 §19.5 同源：cfg.sh diff/apply 与 probe 巡检共用同一套判定——
# 曾经双实现漂移判定语义漂移，2026-11-11 收敛为唯一出处）
# 输入：name|类|正本|应用层|机制|cond → echo 漂移描述（空=一致）；不产生日志
bde_cfg_diff_one() {
    local name="$1" src="${3/#\$COMMON/$COMMON}" dst="$4" mech="$5" cond="$6"
    dst="$(bde_expand_anchors_str "$dst")"
    bde_cfg_cond_ok "$cond" || return 0          # 条件不适用：本机自动缺席，不计漂移
    [ -f "$src" ] || { echo "$name:正本缺失"; return 0; }
    case "$mech" in
        hosts)   # 动态机制：正本列=hosts.toml 数据源 → 生成片段 vs /etc/hosts 标记块
            local _frag _blk
            _frag="$(bde_hosts_fragment "$src")" || { echo "$name:hosts.toml 解析失败"; return 0; }
            _blk="$(bde_hosts_block_extract "$dst")"
            [ -z "$_frag" ] && [ -z "$_blk" ] && return 0
            [ "$_frag" = "$_blk" ] || echo "$name:hosts 片段漂移" ;;
        append)
            local _l
            while IFS= read -r _l; do
                [ -n "$_l" ] || continue
                grep -qF -- "$_l" "$dst" 2>/dev/null || { echo "$name:缺行[$_l]"; return 0; }
            done < "$src" ;;
        *)
            [ -f "$dst" ] || { echo "$name:应用层缺失"; return 0; }
            local _es; _es="$(bde_cfg_effective_src "$src" "$mech")"
            if [ -z "$_es" ]; then
                [[ "$mech" == "copy-expand" ]] || echo "$name:展开/渲染失败（工具缺失？）"
                return 0
            fi
            cmp -s "$_es" "$dst" || echo "$name:内容漂移"
            [[ "$_es" == "${TMPDIR:-/tmp}/bde-cfg-x."* ]] && rm -f "$_es" ;;
    esac
    return 0
}

# hosts.toml → /etc/hosts 片段（唯一生成器：cfg hosts 机制与 probe 事实共用）
# 产出两类行：① 登记了 ip 的机器段行（ip 空 = 暂不分配，跳过不误报）
#            ② 自身主机 → 127.0.1.1（Debian 惯例：自身主机名必须可解析；未被站点 ip 覆盖时补）
# 空输出 = 无事可做（理论上自身行保证非空）
bde_hosts_fragment() {  # [toml 路径] → stdout（片段行，默认 $BDE_ROOT/hosts.toml）；失败响亮退非零
    command -v python3 >/dev/null 2>&1 || { echo "python3 缺失" >&2; return 1; }
    python3 -c 'import tomllib' 2>/dev/null || { echo "python3 缺少 tomllib（需 ≥3.11）" >&2; return 1; }
    python3 - "${1:-${BDE_ROOT:-/Share/Common/code/BestDevEnv}/hosts.toml}" <<'PY'
import os, sys, tomllib
try:
    with open(sys.argv[1], "rb") as fh:
        d = tomllib.load(fh)
except Exception as e:
    sys.exit(f"hosts.toml 解析失败: {e}")
covered = set()
for host, sec in d.items():
    if not isinstance(sec, dict):
        continue
    ip = str(sec.get("ip") or "").strip()
    if not ip:
        continue
    names = [host] + [a.strip() for a in str(sec.get("alias") or "").split(",") if a.strip()]
    covered.update(names)
    print(f"{ip} " + " ".join(names))
me = os.uname().nodename.lower()
if me and me not in covered:
    print(f"127.0.1.1 {me}")
PY
}

BDE_HOSTS_TAG="generated-by-BestDevEnv"

# /etc/hosts 标记块提取（cfg hosts 机制漂移比对用）：无块 → 空；有块 → 块内容
bde_hosts_block_extract() {  # <hosts 文件> → stdout
    awk -v b="$BDE_HOSTS_TAG" \
        'index($0, "# >>> " b)==1 {inblk=1; next}
         index($0, "# <<< " b)==1 {inblk=0; next}
         inblk {print}' "$1" 2>/dev/null
}

# Linux 专属操作守卫（bind mount 等内核机制；非 Linux 响亮 pending，不静默错乱）
bde_require_linux() {
    case "$(bde_os_id)" in
        ubuntu|debian|linuxmint|arch|manjaro|endeavouros|garuda|fedora|rhel|centos|rocky|alma|opensuse*|alpine|nixos|gentoo|void|pop|kali) return 0 ;;
        *) bde_pending "本操作需 Linux（bind mount 等）；当前 OS: $(bde_os_id)——mac/win 对应物为里程碑项（宪法 §10）"; return 1 ;;
    esac
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
