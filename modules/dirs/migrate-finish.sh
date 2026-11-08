#!/usr/bin/env bash
# 旧挂载收尾（迁移最后一步）：
# 前提：旧 $HOME/Share/{Common,Local} 挂载已消失（重启后天然消失——它们是手动挂载）
# 终态：$HOME/Share → /Share（symlink）
# 运行：devenv migrate-finish
BDE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$BDE_ROOT/lib/paths.sh"
source "$BDE_ROOT/lib/common.sh"

OLD="$HOME/Share"

# 1) 守卫：旧挂载必须已不在线（精确匹配 /proc/mounts 中的旧路径；
#    不能用 mountpoint —— ~/Share/Common 已是指向 /Share/Common 的 symlink，会误判为新挂载）
if grep -qE " (${OLD}/Common|${OLD}/Local) " /proc/mounts 2>/dev/null; then
    bde_fail "旧挂载仍在线（未重启或仍有进程占用）——先重启或释放后重试"
    exit 1
fi
bde_ok "旧挂载已不在线"

# 2) 守卫：旧目录内容必须可安全删除（仅允许：指向 /Share 的链接、空目录）
if [ -e "$OLD" ] && [ ! -L "$OLD" ]; then
    shopt -s dotglob nullglob
    for _p in "$OLD"/*; do
        _n="$(basename "$_p")"
        if [ -L "$_p" ]; then
            case "$(readlink "$_p")" in
                /Share/*) continue ;;
                *) bde_fail "$_p 指向非预期目标 $(readlink "$_p")，中止"; exit 1 ;;
            esac
        elif [ -d "$_p" ] && [ -z "$(ls -A "$_p" 2>/dev/null)" ]; then
            continue
        else
            bde_fail "$_p 内容非预期（非空目录/非链接），中止——请人工确认"
            exit 1
        fi
    done
    shopt -u dotglob nullglob
    rm -rf "$OLD" && bde_ok "旧目录 $OLD 已清理"
fi

# 3) 终态：~/Share → /Share
if [ -L "$OLD" ] && [ "$(readlink "$OLD")" = "/Share" ]; then
    bde_skip "~/Share → /Share 已就绪"
else
    ln -s /Share "$OLD" && bde_ok "~/Share → /Share（迁移收尾完成）"
fi
bde_info "此后旧路径（~/Share/Common/...）经 symlink 继续可用，新代码请统一使用 /Share/..."
