#!/usr/bin/env bash
# 归位迁移：Common 旧内容 → 宪法 §13 目标位置
# 幂等（已迁移即跳过）；同文件系统内 rename，可回退；不认识的留在原地并登记
# 注意：本脚本排除 BestDevEnv 自身（避免移动正在执行的脚本所在目录），由最后一步单独移动
[ -n "${BDE_ROOT:-}" ] || BDE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$BDE_ROOT/lib/paths.sh"
source "$BDE_ROOT/lib/common.sh"
source "$BDE_ROOT/lib/ensure.sh"

bde_info "归位迁移（Common 旧内容 → 宪法 §13）"

# 同文件系统内容合并：src 的所有内容（含隐藏）移入 tgt，清空后删除 src
merge_dir() {
    local src=$1 tgt=$2 n=0
    [ -d "$src" ] || return 0
    ensure_dir "$tgt" || { bde_pending "目标不可用: $tgt"; return 1; }
    shopt -s dotglob nullglob
    for f in "$src"/*; do
        mv "$f" "$tgt"/ 2>/dev/null && n=$((n+1)) || bde_pending "迁移失败: $f"
    done
    shopt -u dotglob nullglob
    rmdir "$src" 2>/dev/null \
        && bde_ok "${src#$COMMON/} → ${tgt#$COMMON/}（$n 项）" \
        || { bde_pending "源未清空: ${src#$COMMON/}"; return 1; }
}

# 整目录改名
move_dir() {
    local src=$1 tgt=$2
    [ -d "$src" ] || return 0
    if [ -e "$tgt" ]; then bde_pending "目标已存在，跳过: ${tgt#$COMMON/}"; return 1; fi
    mv "$src" "$tgt" && bde_ok "${src#$COMMON/} → ${tgt#$COMMON/}"
}

# 1) CodeSpace git 仓库 → code/（平铺；排除 BestDevEnv 自身）
ensure_dir "$COMMON/code" 2>/dev/null || true
_repo=0
for d in "$COMMON/CodeSpace"/*/; do
    _name="$(basename "$d")"
    [ "$_name" = "BestDevEnv" ] && continue
    [ -d "${d}.git" ] || continue
    if [ -e "$COMMON/code/$_name" ]; then bde_skip "code/$_name 已存在"; continue; fi
    mv "$d" "$COMMON/code/$_name" && _repo=$((_repo+1)) || bde_pending "迁移失败: $_name"
done
[ "$_repo" -gt 0 ] && bde_ok "CodeSpace 仓库 → code/（$_repo 个）"

# 2) keycompute（Rust 项目，无 .git）→ code/
if [ -d "$COMMON/keycompute" ] && [ ! -e "$COMMON/code/keycompute" ]; then
    move_dir "$COMMON/keycompute" "$COMMON/code/keycompute" \
        && bde_pending "code/keycompute 无 .git（建议 git init 后推远端）"
fi

# 3) Models/GGUF → data/models/gguf
if [ -d "$COMMON/Models/GGUF" ]; then
    merge_dir "$COMMON/Models/GGUF" "$COMMON/data/models/gguf"
    rmdir "$COMMON/Models" 2>/dev/null && bde_ok "Models 已清空移除"
fi

# 4) Caches 对号入座
merge_dir "$COMMON/Caches/go-mod"      "$COMMON/cache/linux/go-mod"
merge_dir "$COMMON/Caches/huggingface" "$COMMON/data/models/huggingface"
merge_dir "$COMMON/Caches/modelscope"  "$COMMON/data/models/modelscope"
merge_dir "$COMMON/Caches/pip"         "$COMMON/cache/linux/pip"
merge_dir "$COMMON/Caches/pub-cache"   "$COMMON/cache/linux/pub-cache"
if [ -d "$COMMON/Caches" ]; then
    _left="$(ls -A "$COMMON/Caches" 2>/dev/null | wc -l)"
    if [ "$_left" -eq 0 ]; then
        rmdir "$COMMON/Caches" && bde_ok "Caches 已清空移除"
    else
        ensure_dir "$COMMON/archive/caches-legacy" 2>/dev/null
        shopt -s dotglob nullglob
        for f in "$COMMON/Caches"/*; do mv "$f" "$COMMON/archive/caches-legacy/"; done
        shopt -u dotglob nullglob
        rmdir "$COMMON/Caches" && bde_pending "Caches 未识别项 → archive/caches-legacy"
    fi
fi

# 5) Packages → install/（按扩展名：exe/msi → win，其余 → linux）
if [ -d "$COMMON/Packages" ]; then
    shopt -s nullglob
    for f in "$COMMON/Packages"/*; do
        case "$(basename "${f,,}")" in
            *.exe|*.msi) _t="$COMMON/install/win" ;;
            *)           _t="$COMMON/install/linux" ;;
        esac
        ensure_dir "$_t" 2>/dev/null
        mv "$f" "$_t"/ 2>/dev/null || bde_pending "Packages 迁移失败: $(basename "$f")"
    done
    shopt -u nullglob
    rmdir "$COMMON/Packages" 2>/dev/null && bde_ok "Packages → install/{win,linux}"
fi

# 6) Data 对号入座
merge_dir "$COMMON/Data/datasets" "$COMMON/data/datasets"
merge_dir "$COMMON/Data/fixtures" "$COMMON/data/fixtures"
move_dir  "$COMMON/Data/android"  "$COMMON/data/android"
move_dir  "$COMMON/Data/business" "$COMMON/data/business"
move_dir  "$COMMON/Data/databases" "$COMMON/data/databases"
move_dir  "$COMMON/Data/Backups"  "$COMMON/archive/Backups"

# 7) Component → install/components（服务组件介质）
if [ -d "$COMMON/Component" ]; then
    ensure_dir "$COMMON/install/components" 2>/dev/null
    shopt -s dotglob nullglob
    for f in "$COMMON/Component"/*; do
        mv "$f" "$COMMON/install/components"/ 2>/dev/null || bde_pending "Component 迁移失败: $(basename "$f")"
    done
    shopt -u dotglob nullglob
    rmdir "$COMMON/Component" 2>/dev/null && bde_ok "Component → install/components"
fi

# 8) Docker → data/docker（镜像/数据归属数据区）
move_dir "$COMMON/Docker" "$COMMON/data/docker"

# 9) 收尾报告：剩余未识别项（不盲动）
bde_info "剩余未识别项（留在原地，请人工判定）："
for d in "$COMMON"/*/; do
    _n="$(basename "$d")"
    case "${_n,,}" in
        code|config|install|cache|data|exchange|docs|templates|archive|.trash-1000) continue ;;
    esac
    [ -d "$d" ] && bde_pending "$_n/（含 $(ls -A "$d" 2>/dev/null | wc -l) 项）"
done
for d in "$COMMON/CodeSpace"/*/; do
    _n="$(basename "$d")"
    [ -d "${d}.git" ] || bde_pending "CodeSpace/$_n（非 git 仓库，人工判定）"
done
[ -d "$COMMON/CodeSpace" ] || bde_ok "CodeSpace 已清空移除"
bde_ok "归位迁移完成"
