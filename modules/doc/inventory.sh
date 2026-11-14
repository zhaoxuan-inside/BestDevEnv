#!/usr/bin/env bash
# modules/doc/inventory.sh — 系统环境索引（L1 采集 → L2 落盘 → L3 视图；宪法 §19.5 同构）
# 采集：已装软件（名称/版本/路径/真实路径/渠道）+ 家目录契约路径实态（登记制判定）+ 受管服务实态
# 索引：① $DEV/docs/state/inventory.json（schema bde.inventory/1，原子写）——了解系统环境的唯一入口
# 视图：默认人类表格；--json 机器输出（读索引文件，不重采——与 report/doctor 同一数据契约）
# 合规范范（判定依据）：实体/依赖住 ①、缓存住 ②③、家目录=入口层（symlink/登记）——数据源 home-map.tsv
# 用法：devenv inventory ｜ inventory.sh [--json] [--refresh]
[ -n "${BDE_ROOT:-}" ] || BDE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$BDE_ROOT/lib/paths.sh"
source "$BDE_ROOT/lib/common.sh"
source "$BDE_ROOT/lib/ensure.sh"
source "$BDE_ROOT/lib/probe.sh"   # bde_is_mounted（docker bind 实态判定）

INV_PATH="${BDE_INVENTORY_PATH:-$DEV/docs/state/inventory.json}"

# ── L1 采集 ──────────────────────────────────────────────────────────────
_v() {  # <cmd…> → 首行版本（15s 超时；落盘捕获防管道挂起——probe 同款）
    local f; f="$(mktemp)"
    if command -v timeout >/dev/null 2>&1; then timeout -k 2 15 "$@" >"$f" 2>&1; else "$@" >"$f" 2>&1; fi
    head -1 "$f" 2>/dev/null; rm -f "$f"
}

_inv_channel() {  # <realpath> → 渠道标签（包管理器归属 → 路径前缀归类；共享盘=违规）
    local p=$1 pkg
    case "$p" in
        "$COMMON"/*) echo "共享盘实体(违规——实体住①)"; return ;;
        "$LOCAL"/*)  echo "②Local"; return ;;
        "$DEV"/xdg/local/mise/*) echo "mise(①)"; return ;;
        "$DEV"/*)    echo "①DevEnv"; return ;;
    esac
    if command -v dpkg >/dev/null 2>&1 && pkg="$(dpkg -S "$p" 2>/dev/null | head -1 | cut -d: -f1)" && [ -n "$pkg" ]; then
        echo "apt:$pkg"; return
    fi
    if command -v pacman >/dev/null 2>&1 && pkg="$(pacman -Qo "$p" 2>/dev/null | awk '{print $NF}')" && [ -n "$pkg" ]; then
        echo "pacman:$pkg"; return
    fi
    if command -v rpm >/dev/null 2>&1 && pkg="$(rpm -qf "$p" 2>/dev/null)" && [ -n "$pkg" ]; then
        echo "rpm:$pkg"; return
    fi
    case "$p" in
        "$HOME"/.local/*) echo "user:~/.local" ;;
        /usr/local/*)     echo "manual:/usr/local" ;;
        /opt/*)           echo "opt:/opt" ;;
        /snap/*)          echo "snap" ;;
        *)                echo "外部路径" ;;
    esac
}

_inv_collect() {  # 采集到 TSV 暂存（tools/paths/services/discovered），供 JSON 组装与人类视图共用
    _INV_T="$(mktemp)"; _INV_P="$(mktemp)"; _INV_S="$(mktemp)"; _INV_A="$(mktemp)"
    local _n _vc _p _r _ch _ver
    while IFS='|' read -r _n _vc; do
        [ -n "$_n" ] || continue
        _p="$(command -v "$_n" 2>/dev/null)" || continue
        _ver="$(_v $_vc 2>/dev/null)"
        _r="$(readlink -f "$_p" 2>/dev/null || echo "$_p")"
        _ch="$(_inv_channel "$_r")"
        printf '%s\t%s\t%s\t%s\t%s\n' "$_n" "$_ver" "$_p" "$_r" "$_ch" >> "$_INV_T"
    done <<'EOF'
claude|claude --version
codex|codex --version
zcode|zcode --version
opencode|opencode --version
gemini|gemini --version
arkcli|arkcli --version
node|node --version
npm|npm --version
python3|python3 --version
uv|uv --version
cargo|cargo --version
go|go version
java|java -version
flutter|flutter --version
mise|mise --version
docker|docker --version
git|git --version
code|code --version
conda|conda --version
starship|starship --version
chezmoi|chezmoi --version
EOF
    # 全量层：多渠道枚举（每源容错——命令缺失/超时静默跳过；重点层之上补盲区）
    # 源：apt-manual/snap/flatpak/npm-global/pip-user/mise/cargo-install/manual:/usr/local/opt:/opt
    {
        apt-mark showmanual 2>/dev/null | while IFS= read -r _n; do
            [ -n "$_n" ] && printf '%s\tapt-manual\t-\n' "$_n"
        done
        command -v snap >/dev/null 2>&1 && snap list 2>/dev/null | tail -n +2 | awk 'NF{print $1 "\tsnap\t" $2}'
        command -v flatpak >/dev/null 2>&1 && flatpak list --app --columns=application 2>/dev/null | awk 'NF{print $1 "\tflatpak\t-"}'
        command -v npm >/dev/null 2>&1 && npm ls -g --depth=0 2>/dev/null | tail -n +2 \
            | sed 's/^[├└│─| ]*//; s/@[^@]*$//' | awk 'NF{print $1 "\tnpm-global\t-"}'
        command -v pip3 >/dev/null 2>&1 && pip3 list --user --format=freeze 2>/dev/null | awk -F'==' 'NF && $1!=""{print $1 "\tpip-user\t-"}'
        command -v mise >/dev/null 2>&1 && mise ls 2>/dev/null | awk 'NF && $1!="Tool" {print $1 "\tmise\t-"}'
        command -v cargo >/dev/null 2>&1 && cargo install --list 2>/dev/null | awk '/^[A-Za-z0-9_.-]+ v/{print $1 "\tcargo-install\t-"}'
        find /usr/local/bin -maxdepth 1 -type f 2>/dev/null | sed 's|.*/||' | while IFS= read -r _n; do
            [ -n "$_n" ] && printf '%s\tmanual:/usr/local\t-\n' "$_n"
        done
        find /opt -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sed 's|.*/||' | while IFS= read -r _n; do
            [ -n "$_n" ] && printf '%s\topt:/opt\t-\n' "$_n"
        done
    } | awk -F'\t' '$1 != "" && !seen[$1]++' | sort > "$_INV_A"
    # 家目录契约路径：path|kind → state(absent/symlink/real) + verdict（登记制：real+未登记=warn）
    local _hm="$COMMON/config/data/home-map.tsv"
    [ -f "$_hm" ] || _hm="$BDE_ROOT/config/data/home-map.tsv"
    local _e _kind _pp _st _tgt _vd
    while read -r _e _kind; do
        [ -n "$_e" ] || continue
        _pp="$HOME/$_e"
        if [ -L "$_pp" ]; then
            _st="symlink"; _tgt="$(readlink "$_pp")"; _vd="ok"
        elif [ -d "$_pp" ] || [ -f "$_pp" ]; then
            _st="real"; _tgt=""
            if grep -qs "^${_e}|" "$_hm"; then
                _vd="info"      # 登记保留（home-map 在册——合规，附政策备注）
            else
                _vd="warn"      # 未登记实体（看门人：补登记或收敛）
            fi
        else
            _st="absent"; _tgt=""; _vd="ok"
        fi
        printf '%s\t%s\t%s\t%s\t%s\n' "$_e" "$_kind" "$_st" "$_tgt" "$_vd" >> "$_INV_P"
    done <<'EOF'
.cache	cache
.cargo	entity
.rustup	entity
.nvm	entity-legacy
.claude	app
.codex	app
.zcode	app
.opencode	app
.gradle	cache
.m2	cache
.conda	entity
Desktop	xdg
Documents	xdg
Downloads	xdg
Music	xdg
Pictures	xdg
Public	xdg
Templates	xdg
Videos	xdg
EOF
    # 受管服务实态：name|state|detail
    local _s _st _d
    _s="docker";      _st="absent"; _d="未安装"
    command -v docker >/dev/null 2>&1 && { _st="installed"; _d="$(_v docker --version)"; bde_is_mounted /var/lib/docker && { _st="bind"; _d="$_d · 数据根 bind ①"; }; }
    printf '%s\t%s\t%s\n' "$_s" "$_st" "$_d" >> "$_INV_S"
    _s="miniconda3";  [ -x "$DEV/services/miniconda3/bin/conda" ] && { _st="installed"; _d="$DEV/services/miniconda3（① 安装体）"; } || { _st="absent"; _d="未安装"; }
    printf '%s\t%s\t%s\n' "$_s" "$_st" "$_d" >> "$_INV_S"
    _s="fstrim.timer";   systemctl is-enabled --quiet fstrim.timer 2>/dev/null && { _st="enabled"; _d="SSD 周期 TRIM"; } || { _st="off"; _d="未启用"; }
    printf '%s\t%s\t%s\n' "$_s" "$_st" "$_d" >> "$_INV_S"
    _s="zramswap";       systemctl is-active --quiet zramswap 2>/dev/null && { _st="active"; _d="压缩内存交换"; } || { _st="off"; _d="未启用"; }
    printf '%s\t%s\t%s\n' "$_s" "$_st" "$_d" >> "$_INV_S"
    _s="journald 上限";  [ -f /etc/systemd/journald.conf.d/99-devspace.conf ] && { _st="on"; _d="drop-in（cfg-map）"; } || { _st="off"; _d="未落位"; }
    printf '%s\t%s\t%s\n' "$_s" "$_st" "$_d" >> "$_INV_S"
    _s="environment.d";  [ -f "$DEV/xdg/config/environment.d/50-devspace.conf" ] && { _st="on"; _d="IM 环境变量契约"; } || { _st="off"; _d="未落位"; }
    printf '%s\t%s\t%s\n' "$_s" "$_st" "$_d" >> "$_INV_S"
}

# ── L2 索引落盘（bde.inventory/2：重点层 tools + 全量层 discovered，原子写）──
_inv_save() {
    _inv_collect
    mkdir -p "$(dirname "$INV_PATH")" 2>/dev/null
    BDE_INV_T="$_INV_T" BDE_INV_P="$_INV_P" BDE_INV_S="$_INV_S" BDE_INV_A="$_INV_A" \
    BDE_INV_OUT="$INV_PATH" BDE_INV_MACHINE="${BDE_MACHINE:-$(hostname)}" python3 - <<'PY'
import json, os, datetime
def rows(p):
    out = []
    if os.path.exists(p):
        for line in open(p):
            line = line.rstrip("\n")
            if line:
                out.append(line.split("\t"))
    return out
doc = {
    "schema": "bde.inventory/2",
    "machine": os.environ["BDE_INV_MACHINE"],
    "date": datetime.datetime.now().strftime("%Y-%m-%d %H:%M"),
    "tools": [
        {"name": r[0], "version": r[1] if len(r) > 1 else "", "path": r[2] if len(r) > 2 else "",
         "real": r[3] if len(r) > 3 else "", "channel": r[4] if len(r) > 4 else "", "origin": "重点层"}
        for r in rows(os.environ["BDE_INV_T"])
    ],
    "discovered": [
        {"name": r[0], "source": r[1] if len(r) > 1 else "", "detail": r[2] if len(r) > 2 else "",
         "origin": r[1] if len(r) > 1 else ""}
        for r in rows(os.environ["BDE_INV_A"])
    ],
    "paths": [
        {"path": r[0], "kind": r[1] if len(r) > 1 else "", "state": r[2] if len(r) > 2 else "",
         "target": r[3] if len(r) > 3 else "", "verdict": r[4] if len(r) > 4 else ""}
        for r in rows(os.environ["BDE_INV_P"])
    ],
    "services": [
        {"name": r[0], "state": r[1] if len(r) > 1 else "", "detail": r[2] if len(r) > 2 else ""}
        for r in rows(os.environ["BDE_INV_S"])
    ],
}
doc["summary"] = {
    "tools_n": len(doc["tools"]),
    "tools_all_n": len({t["name"] for t in doc["tools"]} | {x["name"] for x in doc["discovered"]}),
    "paths_warn": sum(1 for p in doc["paths"] if p["verdict"] == "warn"),
    "paths_registered": sum(1 for p in doc["paths"] if p["verdict"] == "info"),
    "tools_off_share": sum(1 for t in doc["tools"] if "违规" not in t["channel"]),
}
t = os.environ["BDE_INV_OUT"] + ".tmp"
json.dump(doc, open(t, "w"), ensure_ascii=False, indent=2)
os.replace(t, os.environ["BDE_INV_OUT"])
PY
    rm -f "$_INV_T" "$_INV_P" "$_INV_S" "$_INV_A"
    printf '%s\n' "$INV_PATH"
}

# ── L3 视图 ──────────────────────────────────────────────────────────────
_inv_view() {  # <json 文件> → 人类表格
    BDE_INV_JSON="$1" python3 - <<'PY'
import json, os, sys
d = json.load(open(os.environ["BDE_INV_JSON"]))
G, Y, R, Z = ("\033[32m", "\033[33m", "\033[31m", "\033[0m") if sys.stdout.isatty() else ("", "", "", "")
print(f"系统环境索引 — {d['machine']} @ {d['date']}（schema {d['schema']}）")
print(f"\n── 已装软件（{len(d['tools'])}；路径/渠道=合规审计）──")
print(f"  {'软件':<12} {'渠道':<26} 路径")
for t in d["tools"]:
    ch = t["channel"]
    mark = f"{R}✗{Z}" if "违规" in ch else (f"{Y}ℹ{Z}" if ch in ("外部路径",) else f"{G}✓{Z}")
    print(f"  {t['name']:<12} {mark} {ch:<24} {t['path']}")
disc = d.get("discovered", [])
if disc:
    from collections import Counter
    hist = Counter(x["source"] for x in disc)
    hist_s = " ｜ ".join(f"{k}:{v}" for k, v in sorted(hist.items()))
    uniq = len({x["name"] for x in disc})
    print(f"\n── 全量软件（{uniq} 名去重；多渠道枚举——建档覆盖跑 devenv app --audit）──")
    print(f"  {hist_s}")
print(f"\n── 家目录契约路径（登记制：real+未登记=⚠；数据源 home-map.tsv）──")
for p in d["paths"]:
    if p["state"] == "absent":
        continue
    v = p["verdict"]
    mark = f"{G}✓{Z}" if v == "ok" else (f"{Y}ℹ{Z}" if v == "info" else f"{R}⚠{Z}")
    note = "登记保留" if v == "info" else ("未登记实体——map 补登记或收敛" if v == "warn" else "")
    tgt = f" → {p['target']}" if p["state"] == "symlink" else "（实体）"
    print(f"  {mark} {p['path']:<14} {p['state']:<8}{tgt}  {note}")
skipped = sum(1 for p in d["paths"] if p["state"] == "absent")
print(f"  （absent {skipped} 项省略——无实体无残留）")
print(f"\n── 受管服务 ──")
for s in d["services"]:
    print(f"  {s['name']:<14} {s['state']:<10} {s['detail']}")
w = d["summary"]["paths_warn"]
all_n = d["summary"].get("tools_all_n", d["summary"]["tools_n"])
print(f"\n索引：软件 {all_n}（重点 {d['summary']['tools_n']}）｜ 契约路径 ⚠{w}/ℹ{d['summary']['paths_registered']} ｜ 落盘 $DEV/docs/state/inventory.json")
if w:
    print(f"{Y}  ⚠ {w} 项待处置 → devenv inventory --migrate（逐项询问：转移并接回/登记保留/跳过）{Z}")
sys.exit(0)
PY
}

# ── 处置流（--migrate）：违规项逐项询问开发者——转移并接回/登记保留/跳过 ──
# 转移 = 复制校验后移除原实体 + symlink 接回（家目录回归"入口层"，宪法 §20.5）；
# 推荐目标按 kind 契约：app→① apps/agent、entity→①（env.sh 契约位）、cache→②、xdg→②、legacy→①
inv_transfer() {  # <src> <dst> → 0=已转移并接回（可单测：不依赖 $HOME）
    local src=$1 dst=$2
    [ -e "$src" ] || { bde_skip "无实体可转移：$src"; return 0; }
    if [ -e "$dst" ]; then
        bde_info "目标已存在，合并内容（dst 既有文件保留）"
    fi
    ensure_dir "$dst" || { bde_fail "目标目录不可建：$dst"; return 1; }
    local _s1 _d1
    _s1="$(du -sk "$src" 2>/dev/null | cut -f1)"
    if ! rsync -aHAX "$src/" "$dst/" >/dev/null 2>&1; then
        bde_fail "rsync 迁移失败：$src → $dst"; return 1
    fi
    _d1="$(du -sk "$dst" 2>/dev/null | cut -f1)"
    if [ "${_s1:-0}" -gt 0 ] && [ "${_d1:-0}" -lt "$_s1" ]; then
        bde_fail "体量校验不足（src=${_s1}K dst=${_d1}K）——保留原实体，人工核查"; return 1
    fi
    rm -rf "$src" && ln -sfn "$dst" "$src" \
        && bde_ok "转移接回 ${src/#$HOME/\~} → ${dst/#$HOME/\~}" \
        || { bde_fail "原实体移除/接回失败：$src"; return 1; }
}

_inv_migrate_targets() {  # <name> <kind> → echo 推荐目标（契约落点）
    case "$2" in
        app)          echo "$DEV/apps/agent/$1" ;;
        entity)       case "$1" in .cargo) echo "$DEV/cargo" ;; .rustup) echo "$DEV/rustup" ;; *) echo "$DEV/$1" ;; esac ;;
        entity-legacy) echo "$DEV/$1" ;;
        cache)        case "$1" in .gradle) echo "$LOCAL/cache/gradle" ;; .m2) echo "$LOCAL/cache/m2" ;; *) echo "$DEV/xdg/cache/$1" ;; esac ;;
        xdg)          echo "$LOCAL/$1" ;;
        *)            echo "$DEV/apps/agent/$1" ;;
    esac
}

_inv_migrate() {  # 处置流：消费索引中的 warn 项（+登记保留可选项），逐项询问
    [ -f "$INV_PATH" ] || { _inv_save >/dev/null; }
    local _warns
    _warns="$(BDE_INV_JSON="$INV_PATH" python3 -c '
import json, os
d = json.load(open(os.environ["BDE_INV_JSON"]))
for p in d["paths"]:
    if p["verdict"] == "warn":
        print(f"{p[\"path\"]}|{p[\"kind\"]}")')"
    if [ -z "$_warns" ]; then
        bde_ok "无未登记实体（合规；登记保留项见 inventory 视图 ℹ）"
        return 0
    fi
    bde_info "处置流：以下实体不符合家目录契约（real+未登记）——逐项询问（转移并接回[t·推荐] / 登记保留[r] / 跳过[s]）"
    local _hm="$COMMON/config/data/home-map.tsv"
    [ -f "$_hm" ] || _hm="$BDE_ROOT/config/data/home-map.tsv"
    local _line _name _kind _tgt _a
    while IFS='|' read -r _name _kind; do
        [ -n "$_name" ] || continue
        _tgt="$(_inv_migrate_targets "$_name" "$_kind")"
        bde_ask _a "【$_name】(kind=$_kind) 转移 → ${_tgt/#$HOME/\~} 并 symlink 接回？[t/r/s]" "t"
        case "$_a" in
            t)
                if inv_transfer "$HOME/$_name" "$_tgt"; then
                    ensure_line "$_hm" "${_name}|inventory|处置|keep|已转移 → ${_tgt/#$HOME/\~/}（symlink 接回；$(date +%F)）" \
                        && bde_ok "$_name 已转移（登记行已补）"
                fi ;;
            r)
                ensure_line "$_hm" "${_name}|inventory|处置|keep|登记保留（$(date +%F) 处置流确认）" \
                    && bde_ok "$_name 登记保留（下次扫描 verdict=info）" ;;
            *)
                bde_pending "$_name 跳过（保持现状；下次扫描仍为 ⚠）" ;;
        esac
    done <<< "$_warns"
    # 刷新索引反映处置结果
    _inv_save >/dev/null
    bde_ok "处置完成——索引已刷新：$INV_PATH"
}

# ── 入口 ─────────────────────────────────────────────────────────────────
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    case "${1:-}" in
        --json)
            [ -f "$INV_PATH" ] || bde_probe_save >/dev/null 2>&1
            if [ -f "$INV_PATH" ]; then cat "$INV_PATH"; else _inv_save >/dev/null; cat "$INV_PATH"; fi ;;
        --migrate)
            _inv_migrate
            _inv_view "$INV_PATH" ;;
        --refresh|"")
            _f="$(_inv_save)"
            _inv_view "$_f" ;;
        *) echo "用法: inventory.sh [--json|--refresh]"; exit 2 ;;
    esac
fi
