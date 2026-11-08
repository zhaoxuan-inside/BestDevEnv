#!/usr/bin/env bash
# M6: IDE 统一 —— 宪法 §10.9
# VS Code = 默认 IDE：离线 deb + 扩展按"语言档案"安装（base + 所选语言）+ settings 收编
# JetBrains 系 = 受支持可选项（Toolbox / tarball，GUI 为主）
[ -n "${BDE_ROOT:-}" ] || BDE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$BDE_ROOT/lib/paths.sh"
source "$BDE_ROOT/lib/common.sh"
source "$BDE_ROOT/lib/ensure.sh"

bde_info "M6 IDE 统一（默认 VS Code ｜ 语言档案: ${BDE_LANGS:-node,python}）"

# ── 1) VS Code：已装→登记；未装→Common/install/linux 最新 deb 离线安装 ──
if command -v code >/dev/null 2>&1; then
    bde_ok "VS Code 已装：$(code --version 2>/dev/null | head -1)"
else
    _deb="$(ls -t "$COMMON"/install/linux/code_*.deb 2>/dev/null | head -1)"
    if [ -n "$_deb" ] && sudo -n dpkg -i "$_deb" >/dev/null 2>&1; then
        bde_ok "VS Code 离线安装：$(basename "$_deb")"
    else
        bde_pending "VS Code 未装且离线 deb 不可用"
    fi
fi

# ── 2) settings.json 收编（种子缺失时从现状收编，防 apply 覆盖丢配置）──
_set="$HOME/.config/Code/User/settings.json"
_seed="$COMMON/config/dot_config/Code/User/settings.json"
if [ -f "$_set" ] && [ ! -f "$_seed" ]; then
    mkdir -p "$(dirname "$_seed")"
    cp "$_set" "$_seed" && bde_ok "settings.json 收编 → config 种子"
fi
[ -f "$_set" ] && bde_ok "settings.json 应用层就绪" || bde_pending "settings.json 缺失（先 M1.5 apply-config）"
if [ -f "$_set" ] && [ -f "$_seed" ] && ! diff -q "$_set" "$_seed" >/dev/null 2>&1; then
    ensure_backup "$_set"
    bde_pending "settings.json 与 config 种子有差异（已备份）——请人工合并回 config 仓库"
fi

# ── 3) 扩展：按语言档案安装（base + 所选语言；幂等；未入清单的现装扩展只提示）──
_vdir="$COMMON/config/ide/vscode"
if [ -d "$_vdir" ] && command -v code >/dev/null 2>&1; then
    _list="$HOME/DevEnv/tmp/.vscode-ext-merged.txt"
    mkdir -p "$(dirname "$_list")"
    cat "$_vdir/base.txt" > "$_list" 2>/dev/null || touch "$_list"
    IFS=',' read -ra _langs <<< "${BDE_LANGS:-node,python}"
    for _l in "${_langs[@]}"; do
        _l="$(echo "$_l" | tr -d ' ')"
        [ -f "$_vdir/$_l.txt" ] && cat "$_vdir/$_l.txt" >> "$_list"
    done
    _installed="$(code --list-extensions 2>/dev/null)"
    while IFS= read -r _e; do
        [ -z "$_e" ] && continue
        if printf '%s' "$_installed" | grep -qi "^${_e}\$"; then
            bde_skip "扩展已装 $_e"
        elif code --install-extension "$_e" >/dev/null 2>&1; then
            bde_ok "安装扩展 $_e"
        else
            bde_pending "扩展安装失败 $_e"
        fi
    done < "$_list"
    printf '%s' "$_installed" | while IFS= read -r _e; do
        [ -z "$_e" ] && continue
        grep -qi "^${_e}\$" "$_list" || bde_pending "扩展未入档案（补进 config/ide/vscode/）: $_e"
    done
else
    bde_pending "语言档案缺失：$_vdir（base.txt）"
fi

# ── 4) Antigravity（snap）──
if command -v antigravity >/dev/null 2>&1; then
    bde_skip "antigravity 已装（snap）"
elif sudo -n snap install antigravity --classic >/dev/null 2>&1; then
    bde_ok "antigravity 安装（snap）"
else
    bde_pending "antigravity 安装失败"
fi

# ── 5) JetBrains 系：按开发需求自动推导（映射表驱动，不点名；--no-jetbrains 跳过）──
# 需求(BDE_LANGS) → jetbrains.map → 产品 → 版本发现(JetBrains releases API)
# → 介质入库 Common/install/linux/jetbrains/（离线复用）→ 解压 ~/DevEnv/ide/ → 桌面入口
_jb_map="$COMMON/config/ide/jetbrains.map"
_edition="${BDE_JB_EDITION:-ultimate}"
if [ "${BDE_JB_SKIP:-0}" = "1" ]; then
    bde_skip "JetBrains 跳过（--no-jetbrains；随时可重跑补装，介质与入口均幂等）"
elif [ ! -f "$_jb_map" ]; then
    bde_pending "JetBrains 映射表缺失：$_jb_map"
else
    IFS=',' read -ra _jb_langs <<< "${BDE_LANGS:-node,python}"
    for _l in "${_jb_langs[@]}"; do
        _l="$(echo "$_l" | tr -d ' ')"
        _row="$(grep "^${_l}|" "$_jb_map" 2>/dev/null | head -1)"
        [ -z "$_row" ] && continue   # 该需求无 JetBrains 对应产品（如 node → VS Code 足够）
        _code="$(echo "$_row" | cut -d'|' -f2)"
        _pname="$(echo "$_row" | cut -d'|' -f3)"
        _bin="$(echo "$_row" | cut -d'|' -f4)"
        [ "$_edition" = "community" ] && _code="${_code/U/C}" && _code="${_code/PCP/PCC}"
        _ide_root="$DEV/ide"
        _have="$(ls -d "$_ide_root"/${_bin}* 2>/dev/null | head -1)"
        if [ -n "$_have" ]; then
            bde_skip "$_pname 已装（$_have）"
            continue
        fi
        # 版本发现
        _meta="$(curl -fsSL --max-time 30 "https://data.services.jetbrains.com/products/releases?code=${_code}&latest=true&type=release" 2>/dev/null || true)"
        _read="$(printf '%s' "$_meta" | python3 -c 'import sys,json
d=json.load(sys.stdin); k=list(d)[0]; r=d[k][0]
print(r["version"], r["downloads"]["linux"]["link"])' 2>/dev/null || true)"
        _ver="${_read%% *}"; _url="${_read#* }"
        if [ -z "$_url" ]; then
            bde_pending "$_pname 版本发现失败（API 不可达）"
            continue
        fi
        # 介质入库（断点续传；已存在则跳过下载）
        _tgz="$COMMON/install/linux/jetbrains/${_bin}-${_ver}.tar.gz"
        mkdir -p "$(dirname "$_tgz")"
        if [ ! -s "$_tgz" ]; then
            bde_info "下载 $_pname $_ver → ${_tgz#$COMMON/}（约 1GB，断点续传）"
            curl -fSL -C - --max-time 480 -o "$_tgz" "$_url" 2>/dev/null \
                || { bde_pending "$_pname 下载未完成（下次运行自动续传）"; continue; }
        else
            bde_skip "介质已入库：$(basename "$_tgz")"
        fi
        # 解压到 ① 本机盘 + 桌面入口
        ensure_dir "$_ide_root" || { bde_pending "解压目录不可用"; continue; }
        tar -xzf "$_tgz" -C "$_ide_root" 2>/dev/null
        _ide_dir="$(ls -d "$_ide_root"/${_bin}* 2>/dev/null | head -1)"
        if [ -n "$_ide_dir" ] && [ -f "$_ide_dir/bin/${_bin}.sh" ]; then
            mkdir -p "$HOME/.local/share/applications"
            cat > "$HOME/.local/share/applications/${_bin}.desktop" <<EOF
[Desktop Entry]
Name=$_pname
Exec=$_ide_dir/bin/${_bin}.sh
Icon=$_ide_dir/bin/${_bin}.svg
Type=Application
Categories=Development;IDE;
EOF
            bde_ok "$_pname $_ver → $_ide_dir（桌面入口已生成）"
        else
            bde_pending "$_pname 解压/入口生成异常"
        fi
    done
    # flutter 需求 → Android Studio（Google 系，走 snap，非 JetBrains API）
    for _l in "${_jb_langs[@]}"; do
        [ "$(echo "$_l" | tr -d ' ')" = "flutter" ] || continue
        if command -v studio >/dev/null 2>&1 || snap list android-studio >/dev/null 2>&1; then
            bde_skip "android-studio 已装（snap）"
        elif sudo -n snap install android-studio --classic >/dev/null 2>&1; then
            bde_ok "android-studio 安装（snap，flutter 需求推导）"
        else
            bde_pending "android-studio 安装失败（flutter 需求）"
        fi
    done
fi

bde_ok "M6 完成"
