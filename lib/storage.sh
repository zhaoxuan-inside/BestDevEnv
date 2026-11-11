#!/usr/bin/env bash
# lib/storage.sh — L0 存储抽象层（宪法 §20）：作用域 → 后端解析，屏蔽底层介质差异
# 作用域（数据的共享边界，一等概念）：
#   shared  跨主机级（多机多用户共享）   ← 兼容别名 ③ COMMON
#   host    主机级  （同机多用户共享）   ← 兼容别名 ② LOCAL
#   user    用户级  （本机本用户）       ← 兼容别名 ① DEV
# 后端：passthrough（已有挂载）| hgfs | local | nfs | smb（options 键携带 credentials 等）| rclone（云盘）
# 档案解析顺序（bootstrap 免疫）：$BDE_STORAGE_PROFILE → ① docs/state/storage.toml
#   → ③ 正本 config/data/storage.toml（可达则用）→ 内置默认（auto 探测）
# 本文件不依赖 paths.sh/common.sh；对上层只暴露 bde_storage_load / bde_storage_ensure /
# bde_storage_anchors_emit / BDE_SCOPE_* / BDE_STORAGE_PROFILE_ERROR
# 机器段匹配按小写归一（hostname 大小写不敏感；克隆 VM / 大写主机名场景不丢段）

[ -n "${BDE_STORAGE_LOADED:-}" ] && return 0 2>/dev/null || true
BDE_STORAGE_LOADED=1
[ -n "${BDE_ROOT:-}" ] || BDE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export BDE_ROOT

bde_storage_sudo() { sudo -n true 2>/dev/null && echo "sudo -n" || echo ""; }

# —— 档案定位：返回生效 toml 路径（或空 = 内置默认）——
bde_storage_profile() {
    if [ -n "${BDE_STORAGE_PROFILE:-}" ] && [ -f "$BDE_STORAGE_PROFILE" ]; then
        echo "$BDE_STORAGE_PROFILE"; return
    fi
    local local_copy="${BDE_STORAGE_STATE:-$HOME/DevEnv/docs/state/storage.toml}"
    [ -f "$local_copy" ] && { echo "$local_copy"; return; }
    if [ -f /Share/Common/config/data/storage.toml ]; then echo /Share/Common/config/data/storage.toml; return; fi
    echo ""
}

# —— 后端探测（auto 用）：优先已有挂载 → hgfs → local ——
bde_storage_detect() {  # <mount> <source> → echo 后端名
    local m=$1 src=$2 S; S="$(bde_storage_sudo)"
    mountpoint -q "$m" 2>/dev/null && { echo passthrough; return; }
    if command -v vmhgfs-fuse >/dev/null 2>&1 && [ -n "$S" ] && $S vmhgfs-fuse "$src" "$m" -o allow_other 2>/dev/null; then
        echo hgfs; return
    fi
    echo local
}

# —— 档案加载：解析三作用域根/后端/源/期望（机器段覆盖默认段；机器名小写归一）——
bde_storage_load() {
    [ -n "${BDE_STORAGE_RESOLVED:-}" ] && return 0
    local prof; prof="$(bde_storage_profile)"
    local machine; machine="$(printf '%s' "${BDE_MACHINE:-$(hostname)}" | tr '[:upper:]' '[:lower:]')"

    # tomllib 守卫（P1-4）：python3 <3.11 时档案静默失效是生产事故源——必须响亮 + 显式错误位
    BDE_STORAGE_PROFILE_ERROR=""
    if [ -n "$prof" ] && ! python3 -c 'import tomllib' 2>/dev/null; then
        BDE_STORAGE_PROFILE_ERROR="python3 缺少 tomllib（需 ≥3.11）——storage.toml 未生效，改用内置默认"
        printf '[!] %s\n' "$BDE_STORAGE_PROFILE_ERROR" >&2
        prof=""
    fi

    if [ -n "$prof" ]; then
        eval "$(BDE_STORAGE_PROFILE_FILE="$prof" BDE_STORAGE_MACHINE="$machine" python3 <<'PY'
import os, tomllib, shlex
prof, machine = os.environ["BDE_STORAGE_PROFILE_FILE"], os.environ["BDE_STORAGE_MACHINE"]
try:
    with open(prof, "rb") as fh:
        d = tomllib.load(fh)
except Exception as e:
    print("BDE_STORAGE_PROFILE_ERROR=" + shlex.quote(f"storage.toml 解析失败（{e}）——档案未生效，改用内置默认"))
    d = {}
def get(scope, key, dft):
    # [machine.scope] 在 TOML 中解析为嵌套表 d[machine][scope]
    ms = d.get(machine, {}).get(scope, {})
    ds = d.get(scope, {})
    return ms.get(key) or ds.get(key, dft)
def abspath(v):  # 绝对路径原样；相对路径相对 $HOME（用户空间优先）
    v = os.path.expanduser(v)
    return v if v.startswith("/") else os.path.join(os.path.expanduser("~"), v)
for scope, dmnt, dsrc in (("shared", "/Share/Common", ".host:/Common"),
                          ("host",   "/Share/Local",  ".host:/Local")):
    backend = get(scope, "backend", "auto")
    mount   = abspath(get(scope, "mount",   dmnt))
    source  = get(scope, "source",  dsrc)
    options = get(scope, "options", "")   # smb credentials/vers、rclone 额外旗标等后端私有选项
    print(f"BDE_SCOPE_{scope.upper()}_BACKEND={shlex.quote(backend)}")
    print(f"BDE_SCOPE_{scope.upper()}_MOUNT={shlex.quote(mount)}")
    print(f"BDE_SCOPE_{scope.upper()}_SOURCE={shlex.quote(source)}")
    print(f"BDE_SCOPE_{scope.upper()}_OPTIONS={shlex.quote(options)}")
u_root = abspath(d.get(f"{machine}.user", {}).get("root") or d.get("user", {}).get("root", "DevEnv"))
print(f"BDE_SCOPE_USER_ROOT={shlex.quote(u_root)}")
PY
)"
    else
        # 内置默认：shared/host 走 auto 探测，user 走 $HOME/DevEnv
        BDE_SCOPE_SHARED_BACKEND=auto; BDE_SCOPE_SHARED_MOUNT=/Share/Common; BDE_SCOPE_SHARED_SOURCE=.host:/Common; BDE_SCOPE_SHARED_OPTIONS=""
        BDE_SCOPE_HOST_BACKEND=auto;   BDE_SCOPE_HOST_MOUNT=/Share/Local;  BDE_SCOPE_HOST_SOURCE=.host:/Local;  BDE_SCOPE_HOST_OPTIONS=""
        BDE_SCOPE_USER_ROOT="$HOME/DevEnv"
    fi
    # auto → 探测（含挂载动作）
    for scope in shared host; do
        local U="${scope^^}"    # 变量名统一大写（曾因大小写不一致读到空值，2026-11-08）
        eval "local backend=\$BDE_SCOPE_${U}_BACKEND mount=\$BDE_SCOPE_${U}_MOUNT source=\$BDE_SCOPE_${U}_SOURCE"
        if [ "$backend" = "auto" ]; then
            backend="$(bde_storage_detect "$mount" "$source")"
            eval "BDE_SCOPE_${U}_BACKEND=\$backend"
        fi
        eval "BDE_SCOPE_${U}_ROOT=\$mount"
    done
    BDE_SCOPE_USER_ROOT="${BDE_SCOPE_USER_ROOT:-$HOME/DevEnv}"
    BDE_STORAGE_RESOLVED=1
    export BDE_SCOPE_SHARED_ROOT BDE_SCOPE_SHARED_BACKEND \
           BDE_SCOPE_HOST_ROOT BDE_SCOPE_HOST_BACKEND \
           BDE_SCOPE_USER_ROOT BDE_STORAGE_RESOLVED BDE_STORAGE_PROFILE_ERROR
}

# —— 后端 ensure（幂等；上层只调这个，永远不接触介质细节）——
bde_storage_ensure() {  # <shared|host>
    bde_storage_load
    local scope=$1
    local U="${scope^^}"
    eval "local root=\$BDE_SCOPE_${U}_ROOT backend=\$BDE_SCOPE_${U}_BACKEND source=\$BDE_SCOPE_${U}_SOURCE options=\${BDE_SCOPE_${U}_OPTIONS:-}"
    local S; S="$(bde_storage_sudo)"
    if [ -d "$root" ] && [ -w "$root" ]; then
        if [ "$backend" = "local" ] || mountpoint -q "$root" 2>/dev/null; then
            echo "skip $scope@$root（$backend）"; return 0
        fi
    fi
    case "$backend" in
        passthrough)
            echo "fail $scope 期望已挂载但 $root 不在线"; return 1 ;;
        hgfs)
            [ -n "$S" ] || { echo "fail $scope 需 sudo 免密"; return 1; }
            $S mkdir -p "$root" 2>/dev/null
            if $S vmhgfs-fuse "$source" "$root" -o allow_other 2>/dev/null; then
                echo "ok $scope hgfs 挂载 $root"
                local _fl="$source $root fuse.vmhgfs-fuse allow_other 0 0"
                grep -qF -- "$_fl" /etc/fstab 2>/dev/null \
                    || echo "$_fl" | $S tee -a /etc/fstab >/dev/null 2>&1 \
                    || echo "pending $scope fstab 写入失败"
                return 0
            fi
            echo "fail $scope hgfs 挂载失败"; return 1 ;;
        local)
            # host 作用域 = 同机多用户共享：/tmp 式 1777（sticky）让第二用户也能建自己的子区；
            # 属主给当前用户（单用户机主流场景），多用户细分权限按需人工收窄
            if [ -n "$S" ]; then $S mkdir -p "$root" && $S chown "$(id -un):$(id -gn)" "$root" 2>/dev/null; fi
            mkdir -p "$root" 2>/dev/null
            chmod 1777 "$root" 2>/dev/null
            [ -d "$root" ] && [ -w "$root" ] && { echo "ok $scope local 目录 $root（1777）"; return 0; }
            echo "fail $scope local 目录创建失败"; return 1 ;;
        nfs)
            [ -n "$S" ] || { echo "fail $scope 需 sudo 免密"; return 1; }
            $S mkdir -p "$root" 2>/dev/null
            if $S mount -t nfs "$source" "$root" 2>/dev/null; then
                echo "ok $scope nfs 挂载 $root"
                _fl="$source $root nfs defaults,_netdev,nofail 0 0"
                grep -qF -- "$_fl" /etc/fstab 2>/dev/null \
                    || echo "$_fl" | $S tee -a /etc/fstab >/dev/null 2>&1 \
                    || echo "pending $scope fstab 写入失败"
                return 0
            fi
            echo "fail $scope nfs 挂载失败（服务端可达？showmount -e <server> 检查）"; return 1 ;;
        smb)
            [ -n "$S" ] || { echo "fail $scope 需 sudo 免密"; return 1; }
            $S mkdir -p "$root" 2>/dev/null
            # options 键携带 vers/credentials 等（正本 storage.toml options="vers=3.0,credentials=/path,…"）；
            # 未配置时用保守默认（uid/gid 映射当前用户）
            [ -n "$options" ] || options="vers=3.0,uid=$(id -u),gid=$(id -g),file_mode=0664,dir_mode=0775"
            if $S mount -t cifs -o "$options" "$source" "$root" 2>/dev/null; then
                echo "ok $scope smb 挂载 $root"
                _fl="$source $root cifs $options,_netdev,nofail 0 0"
                grep -qF -- "$_fl" /etc/fstab 2>/dev/null \
                    || echo "$_fl" | $S tee -a /etc/fstab >/dev/null 2>&1 \
                    || echo "pending $scope fstab 写入失败"
                return 0
            fi
            echo "fail $scope smb 挂载失败（credentials 文件/vers 检查；options 见 storage.toml 注释示例）"; return 1 ;;
        rclone)
            # 云盘（webdav/s3/onedrive…）：rclone remote 由运维预配置（密钥绝不入 ③ 正本）
            command -v rclone >/dev/null 2>&1 || { echo "fail $scope rclone 未安装（ops 预装）"; return 1; }
            mkdir -p "$root" 2>/dev/null
            if rclone mount "$source" "$root" --daemon --vfs-cache-mode writes 2>/dev/null; then
                echo "ok $scope rclone 挂载 $root（daemon；--vfs-cache-mode writes）"
                echo "pending $scope 持久化：重启后需重新挂载——建议 systemd 用户单元（rclone mount …）或 fstab+mount.rclone 链接，见 bestdevenv-dirs skill"
                return 0
            fi
            echo "fail $scope rclone 挂载失败（remote 已配置？rclone listremotes 检查）"; return 1 ;;
        *)
            echo "fail $scope 未知后端: $backend"; return 1 ;;
    esac
}

# —— 锚点正本输出（state-env 消费，生成 ① anchors.env；env.sh 自动 source）——
# SHARE 语义与 paths.sh 一致：两根同父取父目录，否则取 COMMON
bde_storage_anchors_emit() {
    bde_storage_load
    local share="$BDE_SCOPE_SHARED_ROOT"
    [ "$(dirname "$BDE_SCOPE_SHARED_ROOT")" = "$(dirname "$BDE_SCOPE_HOST_ROOT")" ] \
        && share="$(dirname "$BDE_SCOPE_SHARED_ROOT")"
    printf 'export DEV=%q\n'    "$BDE_SCOPE_USER_ROOT"
    printf 'export SHARE=%q\n'  "$share"
    printf 'export COMMON=%q\n' "$BDE_SCOPE_SHARED_ROOT"
    printf 'export LOCAL=%q\n'  "$BDE_SCOPE_HOST_ROOT"
}
