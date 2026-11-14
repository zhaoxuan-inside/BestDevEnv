#!/usr/bin/env bash
# modules/doc/namecheck.sh — 目录命名规范校验器（七条规范的数据化执行；宪法 §19.5 L1→L2→L3 同构）
# 规范（naming.toml 档案驱动）：NN_ 前缀 + 首字母大写 + 6-10 字符 + 禁中文 + 名实登记 + 同级等长优先
# 判定分级：未登记 = 硬违规（exit 1）；已登记目录样式违规 = 存量违规（提示级——只报不改，--migrate 授权处置）；
#          同级等长 = 优先级提示（永不失败）。XDG 等协议固定名走档案豁免名单。
# 扫描范围：三锚点（①②③，路径由用户指定见 storage.toml）一级目录 + dir-map.tsv 深层登记项
# 用法: devenv namecheck [--json] [--migrate] ｜ JSON: ① docs/state/namecheck.json（bde.namecheck/1，原子写）
[ -n "${BDE_ROOT:-}" ] || BDE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$BDE_ROOT/lib/paths.sh"
source "$BDE_ROOT/lib/common.sh"
source "$BDE_ROOT/lib/ensure.sh"

DIR_MAP="${BDE_DIR_MAP:-$COMMON/config/data/dir-map.tsv}"
[ -f "$DIR_MAP" ] || DIR_MAP="$BDE_ROOT/config/data/dir-map.tsv"
OUT_JSON="${BDE_NAMECHECK_JSON:-$DEV/docs/state/namecheck.json}"

# ── naming.toml 档案解析（storage.sh 同款：python tomllib → eval；作用域覆写）──
_naming_load() {
    local prof="${BDE_NAMING_PROFILE:-$COMMON/config/data/naming.toml}"
    [ -f "$prof" ] || prof="$BDE_ROOT/config/data/naming.toml"
    [ -f "$prof" ] || { bde_fail "命名档案缺失：naming.toml"; return 1; }
    eval "$(BDE_NAMING_PROFILE_FILE="$prof" python3 <<'PY'
import os, tomllib, shlex
d = tomllib.load(open(os.environ["BDE_NAMING_PROFILE_FILE"], "rb"))
df = d.get("default", {})
for k in ("case", "min_len", "max_len", "prefix", "charset", "equal_len"):
    print(f"BDE_NAMING_{k.upper()}={shlex.quote(str(df.get(k, '')))}")
ex = d.get("exempt", {}).get("names", [])
print("BDE_NAMING_EXEMPT=" + shlex.quote("\n".join(ex)))
for sname, vals in d.get("scope", {}).items():
    for k, v in vals.items():
        print(f"BDE_NAMING_SCOPE_{sname.upper()}_{k.upper()}={shlex.quote(str(v))}")
PY
)" || { bde_fail "naming.toml 解析失败"; return 1; }
}
_naming_get() {  # <scope> <key> → 作用域覆写优先，缺省回 default
    local v=""
    eval "v=\"\${BDE_NAMING_SCOPE_${1^^}_${2^^}:-}\""
    if [ -n "$v" ]; then printf '%s' "$v"; return; fi
    eval "printf '%s' \"\${BDE_NAMING_${2^^}:-}\""
}

# ── L1 扫描：锚点一级目录 + dir-map 深层登记项 → TSV: scope<TAB>rel<TAB>reg(1|0|target) ──
_scan_collect() {
    local scope anchor root s p tgt desc cat note
    for scope in shared host user; do
        anchor="COMMON"; [ "$scope" = "host" ] && anchor="LOCAL"; [ "$scope" = "user" ] && anchor="DEV"
        eval "root=\"\${$anchor:-}\""; [ -n "$root" ] && [ -d "$root" ] || continue
        while IFS= read -r d; do
            local rel="${d#"$root"/}"
            local reg=0; grep -qs "^${scope}|${rel}|" "$DIR_MAP" && reg=1
            printf '%s\t%s\t%s\n' "$scope" "$rel" "$reg"
        done < <(find "$root" -mindepth 1 -maxdepth 1 -type d ! -name '.*' 2>/dev/null | sort)
        while IFS='|' read -r s p tgt desc cat note; do
            case "${s:-}" in ''|'#'*) continue ;; esac
            [ "$s" = "$scope" ] || continue
            case "$p" in */*) [ -d "$root/$p" ] && printf '%s\t%s\t1\n' "$scope" "$p" \
                          || printf '%s\t%s\ttarget\n' "$scope" "$p" ;; esac
        done < "$DIR_MAP"
    done | sort -u
}

# ── 判定：单条目录 → violations（| 分隔；空=合规）──
_check_one() {  # <scope> <relpath>
    local scope=$1 rel=$2 b body v="" case_ minl maxl prefix charset l
    b="$(basename "$rel")"
    printf '%s\n' "$BDE_NAMING_EXEMPT" | grep -qxs "$b" && { echo ""; return; }
    case_="$(_naming_get "$scope" case)"; minl="$(_naming_get "$scope" min_len)"
    maxl="$(_naming_get "$scope" max_len)"; prefix="$(_naming_get "$scope" prefix)"
    charset="$(_naming_get "$scope" charset)"
    body="$b"
    if [ "$prefix" = "NN_" ]; then
        [[ "$b" =~ ^[0-9]{2}_ ]] || v="$v|无 NN_ 前缀"
        body="${b#[0-9][0-9]_}"
    fi
    l=${#body}
    [ -n "$minl" ] && [ "$l" -lt "$minl" ] && v="$v|长度 ${l} <${minl}"
    [ -n "$maxl" ] && [ "$l" -gt "$maxl" ] && v="$v|长度 ${l} >${maxl}"
    case "$case_" in
        capital) [[ "$body" =~ ^[A-Z] ]] || v="$v|非大写开头" ;;
        lower)   [[ "$body" =~ ^[a-z] ]] || v="$v|非小写开头" ;;
    esac
    case "$charset" in
        word) [[ "$b" =~ ^[A-Za-z0-9_-]+$ ]] || v="$v|含非法字符（中文/空白）" ;;
    esac
    v="${v#|}"
    echo "$v"
}

case "${1:-}" in ""|--json) DO_MIGRATE=0 ;; --migrate) DO_MIGRATE=1 ;;
    *) echo "用法: devenv namecheck [--json] [--migrate]"; exit 2 ;; esac

_naming_load || exit 2
[ -f "$DIR_MAP" ] || { bde_fail "目录登记表缺失：$DIR_MAP"; exit 2; }

TMPD="$(mktemp -d "${TMPDIR:-/tmp}/bde-namecheck.XXXXXX")"
trap 'rm -rf "$TMPD"' EXIT
SCAN="$TMPD/scan.tsv"; VIOL="$TMPD/viol.tsv"; SIB="$TMPD/sib.tsv"
_scan_collect > "$SCAN"

# 逐条判定
: > "$VIOL"
while IFS=$'\t' read -r scope rel reg; do
    [ -n "$scope" ] || continue
    v="$(_check_one "$scope" "$rel")"
    case "$reg" in
        target) sev="target" ;;
        1)      [ -n "$v" ] && sev="legacy" || sev="ok" ;;
        *)      sev="hard" ;;
    esac
    printf '%s\t%s\t%s\t%s\t%s\n' "$scope" "$rel" "$reg" "$sev" "$v" >> "$VIOL"
done < "$SCAN"

# 同级等长统计（prefer：仅提示；只统计已存在且已登记的目录，target/hard 不计入）
awk -F'\t' '$4=="ok" || $4=="legacy" {
    b=$2; sub(/.*\//, "", b); sub(/^[0-9][0-9]_/, "", b)
    parent=$2; sub(/\/[^/]*$/, "", parent); if (parent==$2) parent="(锚点根)"
    g=$1 "|" parent; n[g]++; L[g]=L[g] (L[g]?",":"") length(b); nm[g]=nm[g] (nm[g]?",":"") b
}
END { for (k in n) if (n[k]>=2) { m=split(L[k],a,","); u=1
      for(i=2;i<=m;i++) if(a[i]!=a[1]) u=0
      if (!u) print k "\t" L[k] "\t" nm[k] } }' "$VIOL" > "$SIB"

_n_hard=$(awk -F'\t' '$4=="hard"' "$VIOL" | wc -l)
_n_legacy=$(awk -F'\t' '$4=="legacy"' "$VIOL" | wc -l)
_n_ok=$(awk -F'\t' '$4=="ok"' "$VIOL" | wc -l)
_n_target=$(awk -F'\t' '$4=="target"' "$VIOL" | wc -l)
_n_sib=$(wc -l < "$SIB")

# ── L2 落盘（原子写）──
INV_MACHINE="${BDE_MACHINE:-$(hostname)}" INV_VIOL="$VIOL" INV_SIB="$SIB" \
INV_HARD="$_n_hard" INV_LEGACY="$_n_legacy" INV_OK="$_n_ok" \
INV_TARGET="$_n_target" INV_SIBN="$_n_sib" INV_OUT="$OUT_JSON" \
BDE_NAMECHECK_QUIET="$DO_MIGRATE" \
python3 <<'PYEOF'
import os, json, datetime, tempfile
rows = [l.rstrip("\n").split("\t") for l in open(os.environ["INV_VIOL"]) if l.strip()]
sibl = [l.rstrip("\n").split("\t") for l in open(os.environ["INV_SIB"]) if l.strip()]
doc = {
    "schema": "bde.namecheck/1",
    "machine": os.environ["INV_MACHINE"],
    "date": datetime.datetime.now().strftime("%Y-%m-%d %H:%M"),
    "entries": [
        {"scope": r[0], "path": r[1], "registered": r[2], "severity": r[3],
         "violations": [x for x in (r[4].split("|") if len(r) > 4 and r[4] else [])]}
        for r in rows
    ],
    "siblings_unequal": [{"group": s[0], "lengths": s[1], "names": s[2] if len(s) > 2 else ""} for s in sibl],
}
doc["summary"] = {"hard": int(os.environ["INV_HARD"]), "legacy": int(os.environ["INV_LEGACY"]),
                  "ok": int(os.environ["INV_OK"]), "target_pending": int(os.environ["INV_TARGET"]),
                  "unequal_groups": int(os.environ["INV_SIBN"])}
fd, tmp = tempfile.mkstemp(dir=os.path.dirname(os.environ["INV_OUT"]) or ".", prefix=".namecheck.")
with os.fdopen(fd, "w") as f:
    json.dump(doc, f, ensure_ascii=False, indent=1)
os.replace(tmp, os.environ["INV_OUT"])
if os.environ.get("BDE_NAMECHECK_QUIET") != "1":
    print(f"[✓] 索引落盘 {os.environ['INV_OUT']}（硬 {doc['summary']['hard']} / 存量 "
          f"{doc['summary']['legacy']} / 合规 {doc['summary']['ok']}）")
PYEOF

# ── --migrate：存量/未登记逐项授权处置（改名→回写 dir-map；未登记→补登记）──
if [ "$DO_MIGRATE" = "1" ]; then
    echo "== 处置流（逐项确认；改名同步回写 dir-map；引用核对按各项提示）=="
    _changed=0
    # 循环输入走 fd 3：交互读（bde_ask/职责补录）保持真实 stdin，不吞清单行
    while IFS=$'\t' read -r scope rel reg sev v <&3; do
        case "$sev" in legacy|hard) ;; *) continue ;; esac
        anchor="COMMON"; [ "$scope" = "host" ] && anchor="LOCAL"; [ "$scope" = "user" ] && anchor="DEV"
        eval "root=\"\${$anchor:-}\""
        if [ "$sev" = "hard" ]; then
            bde_ask act "未登记 [$scope] $rel —— 补登记[d·推荐]/豁免登记[e]/跳过[s]" "d"
            case "$act" in
                d) _desc=""; read -r -p "  一句话职责: " _desc; _desc="${_desc:-未登记补录}"
                   ensure_line "$DIR_MAP" "$scope|$rel||$_desc|补录|$(date '+%F') namecheck 补登记" \
                       && _changed=1 && echo "  [✓] 已登记 $scope|$rel" ;;
                e) ensure_line "$DIR_MAP" "$scope|$rel||豁免（namecheck 确认）|豁免|$(date '+%F') 豁免" \
                       && _changed=1 && echo "  [✓] 已豁免登记 $rel" ;;
                *) echo "  跳过 $rel" ;;
            esac
            continue
        fi
        tgt="$(awk -F'|' -v s="$scope" -v p="$rel" '$1==s && $2==p {print $3; exit}' "$DIR_MAP")"
        _sug=""; [ -n "$tgt" ] && _sug="建议目标: $tgt（登记表已定）" || _sug="无登记目标——手工输入新名或豁免"
        echo "存量违规 [$scope] $rel ｜ ${v:-（待处置行）} ｜ $_sug"
        bde_ask act "  按建议改名[m]/输入新名[n]/豁免登记[e]/跳过[s]" "s"
        case "$act" in
            m) [ -n "$tgt" ] || { echo "  无建议目标，跳过"; continue; }; newname="$tgt" ;;
            n) read -r -p "  新路径（锚点下相对）: " newname; [ -n "$newname" ] || continue ;;
            e) ensure_line "$DIR_MAP" "$scope|$rel||豁免（namecheck 确认）|豁免|$(date '+%F') 豁免" \
                   && _changed=1 && echo "  [✓] 已豁免登记 $rel"; continue ;;
            *) echo "  跳过 $rel"; continue ;;
        esac
        if [ -e "$root/$newname" ]; then echo "  [!] 目标已存在：$newname——跳过"; continue; fi
        ensure_dir "$(dirname "$root/$newname")"
        mv "$root/$rel" "$root/$newname"
        if [ ! -d "$root/$newname" ]; then echo "  [✗] 改名失败：$rel"; continue; fi
        _t="$TMPD/dm.new"
        awk -F'|' -v s="$scope" -v p="$rel" -v n="$newname" 'BEGIN{OFS="|"} { if ($1==s && $2==p) { $2=n; $3=""; print } else { print } }' "$DIR_MAP" > "$_t" && mv "$_t" "$DIR_MAP"
        _changed=1
        _oldbase="$(basename "$rel")"
        echo "  [✓] 已改名: $rel → $newname（dir-map 已回写）"
        echo "  ↳ 引用核对: grep -rn '$_oldbase' cfg-map.tsv skill 模板 env 契约——确认后批量替换"
    done 3< "$VIOL"
    if [ "$_changed" = "1" ]; then
        echo "== 复核（重扫）=="
        "$0" | tail -2
    fi
    exit 0
fi

# ── L3 人类视图 ──
echo "== 目录命名校验（档案 naming.toml ｜ 登记表 ${DIR_MAP/#$COMMON//③}）=="
awk -F'\t' '$4=="hard"   {printf "  [硬]   [%s] %s —— %s\n", $1, $2, ($5==""?"未登记":$5)}' "$VIOL"
awk -F'\t' '$4=="legacy" {printf "  [存量] [%s] %s —— %s\n", $1, $2, $5}' "$VIOL"
awk -F'\t' '$4=="target" {printf "  [目标] [%s] %s —— 登记目标未落地（待迁移）\n", $1, $2}' "$VIOL"
if [ -s "$SIB" ]; then
    echo "-- 同级等长建议（prefer，仅提示）--"
    while IFS=$'\t' read -r g l n; do printf "  %s —— 长度[%s]\n" "$g" "$l"; done < "$SIB"
fi
echo "namecheck：硬 $_n_hard ｜ 存量 $_n_legacy ｜ 合规 $_n_ok ｜ 等长建议组 $_n_sib ｜ JSON: ${OUT_JSON/#$HOME/\~}"
[ "$_n_hard" -gt 0 ] && exit 1
exit 0
