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

BDE_MACHINE="${BDE_MACHINE:-$(hostname)}"
export SHARE COMMON LOCAL DEV BDE_MACHINE BDE_SHARE_STATE
