#!/usr/bin/env bash
# lib/paths.sh — 锚点常量唯一出处（宪法原则 1 + §20：作用域派生，介质无感）
# 三作用域由 lib/storage.sh 解析：shared(③ COMMON) / host(② LOCAL) / user(① DEV)
# 上层代码只允许使用 COMMON/LOCAL/DEV/SHARE，永远不出现介质名词（hgfs/nfs/…）

BDE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export BDE_ROOT
source "$BDE_ROOT/lib/storage.sh"
bde_storage_load

DEV="${DEV:-$BDE_SCOPE_USER_ROOT}"            # ① 用户级（本机本用户）
COMMON="${COMMON:-$BDE_SCOPE_SHARED_ROOT}"    # ③ 跨主机级（多机多用户）
LOCAL="${LOCAL:-$BDE_SCOPE_HOST_ROOT}"        # ② 主机级（同机多用户）

# SHARE 兼容别名：两根同父则取父目录，否则取 COMMON
if [ "$(dirname "$COMMON")" = "$(dirname "$LOCAL")" ]; then
    SHARE="$(dirname "$COMMON")"
else
    SHARE="$COMMON"
fi

BDE_SHARE_STATE="pending"
if [ -d "$COMMON" ] && [ -d "$LOCAL" ] && [ -w "$COMMON" ]; then
    BDE_SHARE_STATE="ok"
elif [ -d "$HOME/Share/Common" ]; then
    BDE_SHARE_STATE="fallback"                # 旧挂载点回退（迁移完成前）
fi

# 机器名小写归一（hosts.toml/storage.toml 机器段与进度文件统一按小写键匹配）
BDE_MACHINE="$(printf '%s' "${BDE_MACHINE:-$(hostname)}" | tr '[:upper:]' '[:lower:]')"
export SHARE COMMON LOCAL DEV BDE_MACHINE BDE_SHARE_STATE

# 锚点变量展开（cfg-map copy-expand 机制用）：③ 共享正本里的 ${DEV}/${COMMON}/${LOCAL}/
# ${SHARE}/${HOME} → 本机锚点值。用户名/主机差异永不住共享正本——机器数据只走锚点，
# 换用户/换机器/换挂载点后同一份正本自然指向正确落位（home 由用户指定，不写死）。
bde_expand_anchors() {  # <file> → stdout（展开后内容）
    local _c
    _c="$(<"$1")"
    _c="${_c//'${DEV}'/$DEV}"
    _c="${_c//'${COMMON}'/$COMMON}"
    _c="${_c//'${LOCAL}'/$LOCAL}"
    _c="${_c//'${SHARE}'/$SHARE}"
    _c="${_c//'${HOME}'/$HOME}"
    printf '%s\n' "$_c"
}
