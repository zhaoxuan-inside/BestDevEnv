#!/usr/bin/env bash
# M2: 目录架构创建（linux）
# 被 init source；亦可独立运行：BDE_MACHINE=x BDE_XDG=y bash modules/dirs/linux.sh
[ -n "${BDE_ROOT:-}" ] || BDE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$BDE_ROOT/lib/paths.sh"
source "$BDE_ROOT/lib/common.sh"
source "$BDE_ROOT/lib/ensure.sh"

MACHINE="${BDE_MACHINE:-$(hostname)}"
XDG="${BDE_XDG:-y}"
ROOT="$(bde_root)"

bde_info "M2 目录架构（机器: $MACHINE ｜ 目标锚点: $BDE_SHARE_ROOT）"

# 1) 死挂载清理（清单制：③ 10_Config/Registry/mount-fixups.tsv——机器差异进数据，代码不背单机历史）
_fixups="$COMMON/10_Config/Registry/mount-fixups.tsv"
if [ -f "$_fixups" ]; then
    while IFS='|' read -r _m _mp _note; do
        case "${_m:-}" in ''|'#'*) continue ;; esac
        [ "$_m" = "*" ] || [ "$_m" = "$BDE_MACHINE" ] || continue
        if grep -q " ${_mp} " /proc/mounts 2>/dev/null; then
            if [ -n "$ROOT" ] && $ROOT umount -l "$_mp" 2>/dev/null; then
                bde_ok "卸载死挂载 $_mp（$_note）"
            else
                bde_pending "死挂载 $_mp 卸载失败（需 sudo）——$_note"
            fi
        else
            bde_skip "无死挂载 $_mp"
        fi
    done < "$_fixups"
else
    bde_skip "无 mount-fixups 清单（③ 10_Config/Registry/mount-fixups.tsv）"
fi

# 2) 作用域就绪——存储抽象层（宪法 §20：M2 不感知介质；作用域→后端解析见 lib/storage.sh + ③ storage.toml）
bde_storage_ensure shared || bde_pending "③ shared 就绪失败（见上）"
bde_storage_ensure host   || bde_pending "② host 就绪失败（见上）"
if [ -w "$COMMON" ]; then bde_ok "③ shared（跨主机级）就绪：$COMMON（后端 $BDE_SCOPE_SHARED_BACKEND）"; else bde_fail "③ shared 不可写：$COMMON"; fi
if [ -w "$LOCAL" ]; then bde_ok "② host（主机级）就绪：$LOCAL（后端 $BDE_SCOPE_HOST_BACKEND）"; else bde_fail "② host 不可写：$LOCAL"; fi
# 存储档案健康显性化（P1-4：tomllib 缺失/解析失败不再静默降级）
[ -n "${BDE_STORAGE_PROFILE_ERROR:-}" ] && bde_pending "存储档案未生效：$BDE_STORAGE_PROFILE_ERROR（devenv state-env 可复现）"

# 2.5) 每机器状态 env（P0-1：锚点/网络画像 → ① state 正本；env.sh 自动 source，机器差异不再写死共享 env.sh）
if bash "$BDE_ROOT/modules/dirs/state-env.sh"; then
    : # 生成器内部已逐项 ok/pending
else
    bde_pending "state-env 生成失败（见上）"
fi

# 3) 骨架目录（Common 八区 / Local / DevEnv / 业务热区）
_bde_dirs=(
    "$COMMON/40_CodeSpace" "$COMMON/10_Config" "$COMMON/10_Config/Services"
    "$COMMON/60_Installers/iso" "$COMMON/60_Installers/win" "$COMMON/60_Installers/linux" "$COMMON/60_Installers/fonts"
    "$COMMON/cache/linux/npm" "$COMMON/cache/linux/pnpm-store" "$COMMON/cache/linux/pip" "$COMMON/cache/linux/uv"
    "$COMMON/cache/windows"
    "$COMMON/30_DataSpace/Models/gguf" "$COMMON/30_DataSpace/Models/huggingface" "$COMMON/30_DataSpace/Models/modelscope"
    "$COMMON/30_DataSpace/Datasets" "$COMMON/30_DataSpace/Fixtures"
    "$COMMON/50_Exchange" "$COMMON/docs/Handbook" "$COMMON/docs/Hostmap" "$COMMON/docs/Envstate"
    "$COMMON/70_Templates" "$COMMON/90_Archive"
    "$LOCAL/20_Build" "$LOCAL/10_Cache/gradle" "$LOCAL/10_Cache/m2"
    "$LOCAL/40_IdeRun" "$LOCAL/30_Logs"
    "$LOCAL/00_Data/Dump" "$LOCAL/00_Data/Export"
    "$LOCAL/Desktop" "$LOCAL/Documents" "$LOCAL/Downloads" "$LOCAL/Music"
    "$LOCAL/Pictures" "$LOCAL/Public" "$LOCAL/Templates" "$LOCAL/Videos"
    "$DEV/20_Deps" "$DEV/30_VirtualEnv" "$DEV/00_Exec" "$DEV/80_Records" "$DEV/90_Scratch" "$DEV/40_Toolchain/PubCache"
    "$DEV/50_Services" "$DEV/ide" "$DEV/10_Apps/agent" "$DEV/10_Apps/ide"
    "$HOME/Code"
)
_miss=0
for _d in "${_bde_dirs[@]}"; do ensure_dir "$_d" || _miss=$((_miss+1)); done
if [ "$_miss" = "0" ]; then
    bde_ok "骨架目录就绪（${#_bde_dirs[@]} 个）"
else
    bde_fail "骨架目录缺失 $_miss 个"
fi

# 3.5) app 实体分类归位（家目录=链接层；实体按分类住 apps/<分类>/ —— 宪法 §19.6/§20.2）
# 配置点：③ 10_Config/Registry/apps-classify.tsv 一张清单即分类（agent=vibecoding / ide=编辑器 / dev=语言与开发工具链）
# 双来源迁移：apps 顶层旧位 → 分类 ｜ 家目录真实目录 → 分类（收编，mv 同盘瞬时+链接接回）
_migrate_app() {  # <name> <分类>
    local n=$1 cat=$2
    local old="$DEV/10_Apps/.$n" dst="$DEV/10_Apps/$cat/.$n" link="$HOME/.$n"   # 拆行：同句 local 的展开先于赋值（$n 会读空）
    mkdir -p "$DEV/10_Apps/$cat" 2>/dev/null || return 0
    [ -e "$dst" ] && return 0
    if [ -d "$old" ] && [ -L "$link" ]; then
        mv "$old" "$dst" && ln -sfn "$dst" "$link"
    elif [ -d "$link" ] && [ ! -L "$link" ]; then
        mv "$link" "$dst" && ln -sfn "$dst" "$link"
    else
        return 0
    fi
    APPS_MOVED=$((APPS_MOVED+1))
}
APPS_MOVED=0
_applist="$COMMON/10_Config/Registry/apps-classify.tsv"
if [ -f "$_applist" ]; then
    while IFS='|' read -r _cat _n; do
        case "${_cat:-}" in ''|'#'*) continue ;; esac
        _n="$(printf '%s' "${_n:-}" | tr -d '[:space:]')"
        [ -n "$_n" ] && _migrate_app "$_n" "$_cat"
    done < "$_applist"
    [ "$APPS_MOVED" -gt 0 ] && bde_ok "app 实体分类归位（$APPS_MOVED 个，清单 $_applist）" || bde_skip "app 实体分类已是最新"
else
    bde_pending "无 apps-classify 清单（③ 10_Config/Registry/apps-classify.tsv）——app 归位跳过"
fi

# 4) config 种子（仅当共享盘尚无 config —— 防双源漂移）
if [ ! -e "$COMMON/10_Config/.chezmoiignore" ]; then
    cp -r "$BDE_ROOT/config/." "$COMMON/10_Config/" && bde_ok "config 种子 → $COMMON/10_Config"
else
    bde_skip "config 已存在（以共享盘为准，种子不参与）"
fi

# 5) 命令入口再生（devenv / code-* 四件套 / vibe；实现住 modules/dirs/exec-gen.sh）
# M2 只负责"该有入口"，入口内容由生成器统一维护（独立执行 exec-gen.sh 可单独刷新，不动目录/挂载）
if bash "$BDE_ROOT/modules/dirs/exec-gen.sh"; then
    : # 生成器内部已报 ok
else
    bde_pending "命令入口再生失败（见上）"
fi

# 6) XDG 用户目录重定向 + home 兼容 symlink
# user-dirs.dirs 正本已收编进 config 事实源（dot_config/user-dirs.dirs，chezmoi 再生；cfg-map 登记）——
# 此处不再直写（消除"手改被静默覆盖"缺口）；首次构建缺失时提示走 M1.5 apply。
if [ "$XDG" = "y" ]; then
    if [ -d "$LOCAL" ] && [ -w "$LOCAL" ]; then
        if [ -f "$HOME/.config/user-dirs.dirs" ]; then
            bde_ok "user-dirs.dirs 就绪（chezmoi 再生；漂移由 devenv cfg diff 巡检）"
        else
            bde_pending "user-dirs.dirs 缺失（M1.5 chezmoi apply 后再生 → \$LOCAL）"
        fi
        shopt -s dotglob nullglob
        for _name in Desktop Documents Downloads Music Pictures Public Templates Videos; do
            _src="$HOME/$_name"; _tgt="$LOCAL/$_name"
            if [ -d "$_src" ] && [ ! -L "$_src" ]; then
                for _item in "$_src"/*; do
                    mv "$_item" "$_tgt"/ 2>/dev/null || bde_pending "迁移失败: $_item"
                done
                rmdir "$_src" 2>/dev/null || { bde_pending "~/${_name} 无法移除（非空或占用）"; continue; }
            fi
            ensure_symlink "$_src" "$_tgt"
        done
        shopt -u dotglob nullglob
        # 6.5) 系统密钥环兼容链路（GNOME Keyring / Secret Service 支撑）
        # XDG_DATA_HOME 重定向至 85_XdgRoot/local，gnome-keyring-daemon 与 PAM/Secret Service
        # 依赖 ~/.local/share/keyrings 兼容链路与 85_XdgRoot/local/keyrings 双向对齐
        ensure_dir "$DEV/85_XdgRoot/local/keyrings"
        ensure_dir "$HOME/.local/share"
        ensure_symlink "$HOME/.local/share/keyrings" "$DEV/85_XdgRoot/local/keyrings"
        if [ -d "$DEV/xdg/local" ]; then
            ensure_symlink "$DEV/xdg/local/keyrings" "$DEV/85_XdgRoot/local/keyrings"
        fi
    else
        bde_pending "Local 不可写，跳过 XDG 重定向"
    fi
else
    bde_skip "XDG 重定向已关闭（--no-xdg）"
fi

# 7) 收尾：旧挂载与归位清单（只提示，不自动搬数据）
bde_pending "旧挂载 $HOME/Share/{Common,Local} 本次不卸载（会话安全）；重启后 fstab 接管 /Share，旧路径可清理"
for _d in CodeSpace Models Caches Packages Data Component Docker keycompute; do
    [ -d "$HOME/Share/Common/$_d" ] && bde_pending "归位待办: Common/$_d → 按宪法 §13 对号入座"
done
bde_ok "M2 完成"
