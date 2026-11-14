#!/usr/bin/env bash
# lib/ensure.sh — 幂等原语（宪法原则 3：环境即代码，所有写操作必须可重跑）
[ -n "${BDE_ENSURE_LOADED:-}" ] && return 0
BDE_ENSURE_LOADED=1
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

# 确保目录存在（成功返回 0；失败计入 fail）
ensure_dir() {
    local d=$1
    if [ -d "$d" ]; then return 0; fi
    if mkdir -p "$d" 2>/dev/null; then return 0; fi
    local r; r="$(bde_root)"
    if [ -n "$r" ] && $r mkdir -p "$d" 2>/dev/null; then return 0; fi
    return 1
}

# 确保软件包已安装（委托 L2 能力总线 pkg.install——apt/dnf/pacman/zypper/brew 差异收敛在适配器；
# 语义包名经适配器别名表解析，未知名原样透传。惰性 source cap.sh 防循环依赖）
ensure_pkg() {
    [ -n "${BDE_ROOT:-}" ] || BDE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    # shellcheck disable=SC1091
    source "$BDE_ROOT/lib/cap.sh"
    local _rc=0 p
    for p in "$@"; do
        cap_pkg_install "$p" || _rc=1
    done
    return $_rc
}

# 确保文件中存在一行（幂等追加）
ensure_line() {
    local f=$1 line=$2
    if [ -f "$f" ] && grep -qF -- "$line" "$f"; then return 0; fi
    mkdir -p "$(dirname "$f")" 2>/dev/null
    printf "%s\n" "$line" >> "$f" && return 0
    return 1
}

# 确保 symlink（仅指向本机盘；共享盘无 symlink —— 宪法物理边界）
ensure_symlink() {
    local link=$1 target=$2
    if [ -L "$link" ] && [ "$(readlink "$link")" = "$target" ]; then
        bde_skip "链接已就绪 ${link/#$HOME/~}"; return 0
    fi
    if [ -e "$link" ] && [ ! -L "$link" ]; then
        if [ -d "$link" ] && [ -z "$(ls -A "$link" 2>/dev/null)" ]; then
            rmdir "$link" || { bde_fail "无法移除空目录 $link"; return 1; }
        else
            bde_fail "$link 已存在且非空，需人工处理"; return 1
        fi
    fi
    ln -sfn "$target" "$link" && bde_ok "链接 ${link/#$HOME/~} → $target"
}

# 确保 fstab 条目（幂等追加，需 sudo）
ensure_fstab() {
    local line=$1
    if grep -qF -- "$line" /etc/fstab 2>/dev/null; then
        bde_skip "fstab 条目已存在"; return 0
    fi
    if echo "$line" | sudo -n tee -a /etc/fstab >/dev/null 2>&1; then
        bde_ok "写入 fstab：$line"; return 0
    fi
    bde_pending "fstab 写入失败（需 sudo 免密）"; return 1
}

# 修改前备份（时间戳版本化：内容与最近一份一致则不重复留痕，内容变化即新版本——
# 同日多次修改的中间态全保留（旧版"同日同名只备一次"会丢中间态）；幂等重跑零垃圾）
ensure_backup() {
    local f=$1
    local bdir="${BDE_BACKUP_DIR:-$DEV/docs/backup}"
    [ -f "$f" ] || { return 0; }
    ensure_dir "$bdir" || { bde_pending "备份目录不可用：$bdir"; return 1; }
    local _name; _name="$(basename "$f")"
    # 与本 basename 最近一份备份逐字节比对（两代命名兼容：<日期>-名 与 <日期-时分秒>-名）
    local _last
    _last="$(ls -1t "$bdir"/[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]-[0-9][0-9][0-9][0-9][0-9][0-9]-"$_name" \
                   "$bdir"/[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]-"$_name" 2>/dev/null | head -1)"
    if [ -n "$_last" ] && [ -f "$_last" ] && cmp -s "$f" "$_last"; then return 0; fi
    local b="$bdir/$(date +%Y%m%d-%H%M%S)-$_name"
    [ -e "$b" ] && { sleep 1; b="$bdir/$(date +%Y%m%d-%H%M%S)-$_name"; }  # 同秒撞名：等 1s 重取时间戳
    cp "$f" "$b" && bde_ok "备份 $(basename "$f") → ${b/#$HOME/~}"
}

# 结构化 JSON 深路径键现状比对（幂等预检：无日志——调用方记账）
# 用法：ensure_json_key_equal <文件> <点分键> <payload 行文件> → 0=键现状与 payload 全等（无需写）｜1=有差异/文件缺失/解析失败
# 配套 ensure_json_merge 使用：先判等跳过（投影行无变化报 [=]，满足"二次 wire 全 skip"验收），
# 有差异先 ensure_backup 再 merge（投影改既有文件前留痕——正本为空时需可自证未清工具本地键）
ensure_json_key_equal() {
    local f="$1" key="$2" pay="$3"
    python3 - "$f" "$key" "$pay" <<'PY'
import json,sys,os
f,key,pay=sys.argv[1],sys.argv[2],sys.argv[3]
try:
    payload={}
    for line in open(pay):
        line=line.rstrip("\n")
        if not line: continue
        n,j=line.split("\t",1); payload[n]=json.loads(j)
except Exception:
    sys.exit(1)
if not (os.path.exists(f) and os.path.getsize(f)>0):
    sys.exit(1)
try: data=json.load(open(f))
except Exception:
    sys.exit(1)
cur=data
for p in key.split("."):
    if not isinstance(cur,dict) or p not in cur:
        sys.exit(1)
    cur=cur[p]
sys.exit(0 if cur==payload else 1)
PY
}

# 结构化 JSON 深路径合并（保留既有键，仅更新 payload 命名项；无日志——调用方记账）
# 用法：ensure_json_merge <文件> <点分键如 mcp.servers> <payload 行文件：name<TAB>json>
ensure_json_merge() {
    local f="$1" key="$2" pay="$3"
    python3 - "$f" "$key" "$pay" <<'PY'
import json,sys,os
f,key,pay=sys.argv[1],sys.argv[2],sys.argv[3]
try:
    payload={}
    for line in open(pay):
        line=line.rstrip("\n")
        if not line: continue
        n,j=line.split("\t",1); payload[n]=json.loads(j)
except Exception as e:
    sys.exit(f"payload 解析失败: {e}")
data={}
if os.path.exists(f) and os.path.getsize(f)>0:
    with open(f) as fh:
        try: data=json.load(fh)
        except Exception as e: sys.exit(f"{f} JSON 解析失败（不动该文件）: {e}")
cur=data
parts=key.split(".")
for p in parts[:-1]: cur=cur.setdefault(p,{})
cur=cur.setdefault(parts[-1],{})
cur.update(payload)
os.makedirs(os.path.dirname(f) or ".",exist_ok=True)
with open(f,"w") as fh: json.dump(data,fh,indent=2,ensure_ascii=False)
PY
}
