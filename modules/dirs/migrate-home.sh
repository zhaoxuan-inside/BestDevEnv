#!/usr/bin/env bash
# 归位迁移（home 残留）：build_app / Execute / .pub-cache / .gradle → 宪法位置
# 幂等；跨文件系统 mv 自动 copy+rm（home=ext4 → 共享=fuse，大目录需数分钟）
[ -n "${BDE_ROOT:-}" ] || BDE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$BDE_ROOT/lib/paths.sh"
source "$BDE_ROOT/lib/common.sh"
source "$BDE_ROOT/lib/ensure.sh"

bde_info "归位迁移（home 残留 → 宪法位置）"

# 内容合并（跨盘：mv 自动 copy+rm；重名加 .legacy-home 后缀，不覆盖任何数据）
merge_from_home() {
    local src=$1 tgt=$2 n=0
    [ -d "$src" ] || return 0
    ensure_dir "$tgt" || { bde_pending "目标不可用: $tgt"; return 1; }
    shopt -s dotglob nullglob
    for f in "$src"/*; do
        _n="$(basename "$f")"
        if [ -e "$tgt/$_n" ]; then
            mv "$f" "$tgt/$_n.legacy-home" 2>/dev/null && bde_info "  $_n → $_n.legacy-home（重名）" \
                || bde_pending "迁移失败: $f"
        else
            mv "$f" "$tgt/" 2>/dev/null && n=$((n+1)) || bde_pending "迁移失败: $f"
        fi
    done
    shopt -u dotglob nullglob
    rmdir "$src" 2>/dev/null \
        && bde_ok "${src/#$HOME/\~} → ${tgt#$COMMON/}（$n 项）" \
        || { bde_pending "源未清空: ${src/#$HOME/\~}"; return 1; }
}

# 1) build_app（Flutter 业务仓库）→ code/
if [ -d "$HOME/build_app" ] && [ ! -e "$COMMON/code/build_app" ]; then
    mv "$HOME/build_app" "$COMMON/code/build_app" \
        && bde_ok "build_app → code/build_app" \
        || bde_pending "build_app 迁移失败"
elif [ -d "$HOME/build_app" ]; then
    bde_pending "code/build_app 已存在，home/build_app 留原地待判"
fi

# 2) Execute/* → code/（项目物：llama-cpp 等）
if [ -d "$HOME/Execute" ]; then
    shopt -s dotglob nullglob
    for item in "$HOME/Execute"/*; do
        _n="$(basename "$item")"
        if [ -e "$COMMON/code/$_n" ]; then
            bde_pending "code/$_n 已存在，Execute/$_n 留原地"
            continue
        fi
        mv "$item" "$COMMON/code/$_n" && bde_ok "Execute/$_n → code/$_n" || bde_pending "迁移失败: $_n"
    done
    shopt -u dotglob nullglob
    rmdir "$HOME/Execute" 2>/dev/null && bde_ok "Execute 已清空移除" || bde_pending "Execute 未清空"
fi

# 3) ~/.pub-cache（旧缓存 177M）→ Common cache（PUB_CACHE 现指向 DevEnv/pub-cache）
if [ -d "$HOME/.pub-cache" ]; then
    merge_from_home "$HOME/.pub-cache" "$COMMON/cache/linux/pub-cache"
fi

# 4) ~/.gradle —— 实测教训：gradle caches 深层长文件名超 HGFS 上限（File name too long），
#    物理放不进共享盘，且 100% 可再生 → 删除 caches；其余小件（daemon/wrapper）合并到 Local cache
if [ -d "$HOME/.gradle" ]; then
    if [ -d "$HOME/.gradle/caches" ]; then
        _sz="$(du -sh "$HOME/.gradle/caches" 2>/dev/null | cut -f1)"
        rm -rf "$HOME/.gradle/caches" \
            && bde_ok "删除 ~/.gradle/caches（${_sz:-?}，可再生；长文件名无法上共享盘，下次构建自动重建）" \
            || bde_pending "caches 删除失败"
    fi
    merge_from_home "$HOME/.gradle" "$LOCAL/cache/gradle"
fi

# 5) 终审：home 可见目录应只剩 DevEnv / Code / Share(symlink) / XDG 链接
bde_info "home 可见目录终审："
shopt -s nullglob
for p in "$HOME"/*/; do
    _n="$(basename "$p")"
    case "$_n" in
        DevEnv|Code|Share) continue ;;
        Desktop|Documents|Downloads|Music|Pictures|Public|Templates|Videos)
            [ -L "${p%/}" ] && continue
            bde_pending "$_n/ 未重定向（应为 symlink）" ;;
        *)
            [ -d "$p" ] && bde_pending "$_n/（残留，人工判定）" ;;
    esac
done
shopt -u nullglob
bde_ok "home 归位迁移完成"
