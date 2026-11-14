#!/usr/bin/env bash
# lib/probe.sh — L1 采集器：环境事实的唯一来源（宪法 §19.5 数据/视图分层）
# 职责：只采集，不渲染。产出 schema 化 JSON 快照 → $DEV/docs/state/probe.json
# 视图（doctor/report/AGENTS/SKILL）一律消费快照，绝不自行采集。
# 硬件/OS 差异在这里转为事实：存储后端/持久化/期望对账、共享盘能力探测（symlink/
# hardlink/大小写/权限/文件名长度）——视图层按事实渲染，不硬编码介质名词。
# 用法：source 后调 bde_probe_collect（取 P_ 变量）/ bde_probe_save（落快照）；
#       直接执行：probe.sh [--json|--save|--human]

[ -n "${BDE_ROOT:-}" ] || BDE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$BDE_ROOT/lib/paths.sh"
source "$BDE_ROOT/lib/common.sh"   # bde_os_id/bde_cfg_cond_ok（cfg 漂移条件列）——含 include 守卫，重复 source 幂等

BDE_PROBE_STATE_DIR="${BDE_PROBE_STATE_DIR:-$DEV/docs/state}"

# 部署层指纹：templates/ 目录内容哈希——agents-md.sh 生成正本时落 gen-fingerprint，
# doctor 以此比对"正本代际 vs 模板现状"（env→devenv 重命名未重放致全链路漂移，2026-11-08 实证）
bde_templates_hash() {
    (cd "$BDE_ROOT" && find templates -type f -print0 2>/dev/null | LC_ALL=C sort -z \
        | xargs -0 sha256sum 2>/dev/null | sha256sum | cut -d' ' -f1)
}

# SKILL 数值来源正本哈希（gen 指纹第二分量）：@CFGVAL@ 占位符渲染所消费的 ③ 正本集合——
# 改值未重跑 devenv gen = 代际漂移，doctor「正本与模板同代」项检出（闭环：数据变更必经再生）
bde_cfg_sources_hash() {
    for f in \
        "$COMMON/config/services/sysctl/99-devspace.conf" \
        "$COMMON/config/services/systemd/journald-devspace.conf" \
        "$COMMON/config/services/limits/99-devspace.conf" \
        "$COMMON/config/services/zram/zramswap"; do
        [ -f "$f" ] && sha256sum "$f" 2>/dev/null
    done | LC_ALL=C sort | sha256sum | cut -d' ' -f1
}

# —— 挂载判定（便携）：mountpoint 是 util-linux 命令，mac/BSD 没有——缺失时回退解析 mount 输出
# （Linux 格式 "src on /path type …"；mac 格式 "src on /path (…"——" on <path> " 两端空格精确匹配，
#  嵌套路径 /path/sub 不会误命中 /path）
bde_is_mounted() {  # <path> → 0/1
    if command -v mountpoint >/dev/null 2>&1; then
        mountpoint -q "$1" 2>/dev/null && return 0 || return 1
    fi
    mount 2>/dev/null | grep -q " on $1 " && return 0 || return 1
}

# —— 存储持久化判定（按后端语义，不硬编码介质）——
#   local        本机目录，天然持久
#   passthrough  外部管理（已在位即视为受管）
#   hgfs/nfs/smb 等 fstab 型后端：fstab 中存在该挂载点行 = 重启后自动恢复
#   （fstab 是 Linux 机制——非 Linux 平台 doctor 不判此项，OS 条件化见 verify/doctor.sh）
bde_persist_probe() {  # <backend> <mount> → 0/1
    case "$1" in
        local|passthrough) echo 1 ;;
        *) awk -v m="$2" '$2==m{f=1} END{print (f?1:0)}' /etc/fstab 2>/dev/null || echo 0 ;;
    esac
}

# —— 共享盘能力探测（P1-3：物理红线从静态文档变为机器自证）——
# 临时目录做完即清；仅 Common 可写时执行。结果供视图按事实渲染物理边界段。
# 全部动作静默（2>/dev/null）：探测失败是"事实"（如 HGFS 255B 上限）不是错误，不污染输出
bde_caps_probe() {  # 设置 P_CAP_* 变量
    P_CAP_PROBED=0; P_CAP_SYMLINK=0; P_CAP_HARDLINK=0; P_CAP_CASE=0; P_CAP_PERM=0; P_CAP_NAME255=0
    [ "$P_COMMON_WRITABLE" = "1" ] || return 0
    local _cap="$COMMON/.bde-capprobe.$$"
    mkdir "$_cap" 2>/dev/null || return 0
    P_CAP_PROBED=1
    # symlink
    if { ln -s . "$_cap/t.symlink" 2>/dev/null && [ -L "$_cap/t.symlink" ]; } 2>/dev/null; then P_CAP_SYMLINK=1; fi
    # hardlink
    if { : > "$_cap/t.h1" 2>/dev/null && ln "$_cap/t.h1" "$_cap/t.h2" 2>/dev/null; } 2>/dev/null; then P_CAP_HARDLINK=1; fi
    # 大小写敏感（两个路径 -ef 同一 inode = 不区分大小写）
    if { : > "$_cap/t.case-a" 2>/dev/null && : > "$_cap/t.case-A" 2>/dev/null \
       && [ ! "$_cap/t.case-a" -ef "$_cap/t.case-A" ]; } 2>/dev/null; then P_CAP_CASE=1; fi
    # 权限语义（chmod 是否真生效；恒 777 的共享盘 chmod 静默无效）
    if { : > "$_cap/t.perm" 2>/dev/null && chmod 700 "$_cap/t.perm" 2>/dev/null; } 2>/dev/null; then
        local _pm; _pm="$(stat -c %a "$_cap/t.perm" 2>/dev/null || stat -f '%Lp' "$_cap/t.perm" 2>/dev/null)"
        [ "$_pm" = "700" ] && P_CAP_PERM=1
    fi
    # 255 字节文件名（HGFS 上限实测项；成功 = 可放深层缓存名）
    local _n255; _n255="$(printf '%0255d' 0 | tr '0' 'n')"
    if { : > "$_cap/$_n255" 2>/dev/null; } 2>/dev/null; then P_CAP_NAME255=1; fi
    rm -rf "$_cap" 2>/dev/null
}

bde_probe_collect() {
    P_OS="$(grep -m1 PRETTY_NAME /etc/os-release 2>/dev/null | cut -d'"' -f2)"
    P_OS_ID="$(. /etc/os-release 2>/dev/null; echo "${ID:-unknown}")"
    P_OS_FAMILY="$(bde_os_family)"                # 适配器家族（debian/fedora/arch/suse/darwin/unknown）
    P_OS_FAMILY_GROUP="$(bde_os_family_group)"    # 平台组归并（linux/darwin/unknown——视图消费的唯一语义）
    P_KERNEL="$(uname -r)"
    P_HOST="$(hostname)"
    P_USER="$(id -un)"
    P_DATE="$(date '+%Y-%m-%d %H:%M')"
    # POSIX 格式（-kP：Linux/mac/BSD 通用；GNU -BG 在 BSD 系无此旗标会静默失败）
    # 余量用 MB 精度（-BG 向上取整/int GB 取整都会让 ">15G" 阈值误判——实测 15.41G 曾被两种取整判成 16G/15G）
    P_DISK_ROOT_USE="$(df -kP / 2>/dev/null | awk 'NR==2{print $5}')"
    P_DISK_ROOT_FREE_MB="$(df -kP / 2>/dev/null | awk 'NR==2{print int($4/1024)}')"

    # 锚点与挂载
    P_SHARE_STATE="${BDE_SHARE_STATE:-unknown}"
    P_COMMON_WRITABLE=0; P_LOCAL_WRITABLE=0
    if [ -d "$COMMON" ] && touch "$COMMON/.bde_write_test" 2>/dev/null; then
        rm -f "$COMMON/.bde_write_test"; P_COMMON_WRITABLE=1
    fi
    if [ -d "$LOCAL" ] && touch "$LOCAL/.bde_write_test" 2>/dev/null; then
        rm -f "$LOCAL/.bde_write_test"; P_LOCAL_WRITABLE=1
    fi
    # 存储后端事实（L0 解析层给出声明值；probe 另测实际形态供 doctor 对账"声明 vs 实际"）
    P_BACKEND_COMMON="${BDE_SCOPE_SHARED_BACKEND:-unknown}"
    P_BACKEND_HOST="${BDE_SCOPE_HOST_BACKEND:-unknown}"
    P_MOUNTED_COMMON=0; bde_is_mounted "$COMMON" && P_MOUNTED_COMMON=1
    P_MOUNTED_HOST=0;   bde_is_mounted "$LOCAL"  && P_MOUNTED_HOST=1
    P_PERSIST_COMMON="$(bde_persist_probe "$P_BACKEND_COMMON" "$COMMON")"
    P_PERSIST_HOST="$(bde_persist_probe "$P_BACKEND_HOST" "$LOCAL")"
    P_LAYER_COMMON="$(mount 2>/dev/null | grep -c " $COMMON ")"
    P_LAYER_LOCAL="$(mount 2>/dev/null | grep -c " $LOCAL ")"
    bde_caps_probe
    # 存储档案健康（storage.sh 解析层置位；0=档案生效）
    P_PROFILE_ERR="${BDE_STORAGE_PROFILE_ERROR:+1}"
    P_PROFILE_ERR="${P_PROFILE_ERR:-0}"
    P_PROFILE_ERR_MSG="${BDE_STORAGE_PROFILE_ERROR:-}"

    # 配置 / 骨架 / 接线
    P_CONFIG_OK=0; { [ -f "$COMMON/config/.chezmoiignore" ] || [ -f "$HOME/.config/devspace/env.sh" ]; } && P_CONFIG_OK=1
    P_ENV_SH=0; [ -f "$HOME/.config/devspace/env.sh" ] && P_ENV_SH=1
    P_XDG_DOC=""; grep -m1 'XDG_DOCUMENTS_DIR' "$HOME/.config/user-dirs.dirs" 2>/dev/null | grep -q 'Share/Local' && P_XDG_DOC="重定向"
    P_AGENTS_MD=0; [ -f "$HOME/.config/devspace/agents/AGENTS.md" ] && P_AGENTS_MD=1
    P_SKELETON=0; [ -d "$COMMON/data/models" ] && [ -d "$LOCAL/20_Build" ] && P_SKELETON=1
    P_IDE_OK=0; { [ -f "$HOME/.config/Code/User/settings.json" ] && [ -f "$COMMON/config/ide/vscode/base.txt" ] \
        && command -v code >/dev/null 2>&1; } && P_IDE_OK=1

    # 部署层一致性（分发器 / 正本同代指纹 / 机器登记）
    P_DISPATCHER_OK=0
    { [ -x "$DEV/bin/devenv" ] && [ ! -e "$DEV/bin/env" ]; } && P_DISPATCHER_OK=1
    P_HOST_REG=0
    if [ -f "$BDE_ROOT/hosts.toml" ] && grep -qi "^\[$BDE_MACHINE\]" "$BDE_ROOT/hosts.toml" 2>/dev/null; then
        P_HOST_REG=1
    fi
    P_GEN_FRESH=0
    P_GEN_STALE=""
    _gen_state="$DEV/docs/state/gen-fingerprint"
    if [ -f "$_gen_state" ] && [ -n "$(bde_templates_hash)" ]; then
        _gen_ok=0
        _stale_t=0; _stale_c=0
        [ "$(bde_templates_hash)" = "$(sed -n 's/^templates_hash=//p' "$_gen_state" | head -1)" ] && _gen_ok=1 || _stale_t=1
        # 第二分量：CFGVAL 数值来源正本（改值未重跑 gen = 代际漂移，检出——旧指纹无此键则宽限期跳过）
        if [ "$_gen_ok" = "1" ] && grep -q '^cfg_sources_hash=' "$_gen_state" 2>/dev/null; then
            [ "$(bde_cfg_sources_hash)" = "$(sed -n 's/^cfg_sources_hash=//p' "$_gen_state" | head -1)" ] || { _gen_ok=0; _stale_c=1; }
        fi
        [ "$_gen_ok" = "1" ] && P_GEN_FRESH=1 || P_GEN_STALE="$([ "$_stale_t" = "1" ] && printf 'templates')$([ "$_stale_t" = "1" ] && [ "$_stale_c" = "1" ] && printf '+')$([ "$_stale_c" = "1" ] && printf 'cfg_sources')——跑 devenv gen 再生"
    fi

    # Runtime 统一接线（M4 扩展：记忆/MCP/Skill 三正本 + ~/.agents 枢纽兜底）
    P_MCP_CANON=0; [ -f "$HOME/.config/devspace/agents/mcp.json" ] && P_MCP_CANON=1
    P_RUNTIME_OK=0
    if [ "$P_AGENTS_MD" = "1" ] && [ "$P_MCP_CANON" = "1" ] \
       && [ -L "$HOME/.agents/mcp.json" ] \
       && [ -L "$HOME/.agents/skills/bestdevenv" ]; then
        P_RUNTIME_OK=1
    fi

    # Runtime 注册表应装未装（非人工渠道；opencode 曾缺失 5 天无人发现——接线视图之外
    # doctor 也要看得见。登记表是全局的、机器各有取舍 → 只警示不计 doctor 失败）
    P_RUNTIME_MISSING=""
    if [ -f "$BDE_ROOT/modules/agent/runtimes.tsv" ]; then
        while IFS='|' read -r _rn _rb _rch _rrest; do
            [ -n "$_rn" ] || continue
            case "$_rch" in 人工*) continue ;; esac
            [ -n "$_rb" ] || continue
            command -v "$_rb" >/dev/null 2>&1 || P_RUNTIME_MISSING+="$_rn "
        done < <(grep -v '^[[:space:]#]' "$BDE_ROOT/modules/agent/runtimes.tsv" | grep -v '^[[:space:]]*$')
    fi
    P_RUNTIME_MISSING="${P_RUNTIME_MISSING% }"

    # 配置治理漂移（M1.6：cfg-map 逐项；判定唯一实现在 bde_cfg_diff_one——与 cfg.sh diff/apply 同源 §19.5；
    # 正本缺失不计漂移——只提示未收编；条件不适用项本机缺席不计漂移）
    P_CFG_DRIFT=0
    if [ -f "$BDE_ROOT/modules/cfg/cfg-map.tsv" ]; then
        while IFS='|' read -r _cn _cc _cs _cd _cm _cr _ccond _cnote; do
            [ -n "$_cn" ] || continue
            [ -f "${_cs/#\$COMMON/$COMMON}" ] || continue
            _d="$(bde_cfg_diff_one "$_cn" "$_cc" "$_cs" "$_cd" "$_cm" "$_ccond")"
            [ -n "$_d" ] && P_CFG_DRIFT=$((P_CFG_DRIFT+1))
        done < <(grep -v '^[[:space:]#]' "$BDE_ROOT/modules/cfg/cfg-map.tsv" | grep -v '^[[:space:]]*$')
    fi
    # config 事实源仓库干净度（未提交/未收编变更）
    P_CFG_DIRTY=0
    if command -v git >/dev/null 2>&1 && [ -d "$COMMON/config/.git" ]; then
        [ -n "$(git -C "$COMMON/config" status --porcelain 2>/dev/null | head -1)" ] && P_CFG_DIRTY=1
    fi
    # config 备份通道就绪（seed 快照随工程仓库 push = 异地备份；snapshot 机制见 devenv cfg snapshot）
    P_CFG_BACKUP=0
    if [ -d "$BDE_ROOT/config" ] \
       && git -C "$BDE_ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1 \
       && [ -n "$(git -C "$BDE_ROOT" remote 2>/dev/null | head -1)" ] \
       && [ -n "$(git -C "$BDE_ROOT" ls-files config/ 2>/dev/null | head -1)" ]; then
        P_CFG_BACKUP=1
    fi
    # agents 正本 ③ 版本化（Skill/MCP 正本入 config 仓库——跨机器复用；非 git 环境判 0 不误报）
    P_AGENTS_CANON=0
    if [ -d "$COMMON/config/agents/skill" ] \
       && command -v git >/dev/null 2>&1 && [ -d "$COMMON/config/.git" ] \
       && [ -n "$(git -C "$COMMON/config" ls-files agents 2>/dev/null | head -1)" ]; then
        P_AGENTS_CANON=1
    fi

    # 内核参数
    P_INOTIFY_W="$(cat /proc/sys/fs/inotify/max_user_watches 2>/dev/null || echo 0)"
    P_INOTIFY_OK=0; [ "${P_INOTIFY_W:-0}" -ge 524288 ] 2>/dev/null && P_INOTIFY_OK=1

    # 系统优化运行态事实（v0.19 默认集；文件落位漂移由 cfg-map 巡检覆盖，这里只测"生效值"——
    # 文件落位 ≠ 已生效：sysctl 需 sysctl --system、timer 需 enable。非 Linux 时各项为 0，doctor OS 条件化缺席）
    P_SYSCTL_SWAP="$(cat /proc/sys/vm/swappiness 2>/dev/null || echo 0)"
    P_SYSCTL_OK=0; [ -n "$P_SYSCTL_SWAP" ] && [ "$P_SYSCTL_SWAP" -le 10 ] 2>/dev/null && P_SYSCTL_OK=1
    P_FSTRIM_OK=0; systemctl is-enabled --quiet fstrim.timer 2>/dev/null && P_FSTRIM_OK=1
    P_TIMESYNC_OK=0
    if systemctl is-active --quiet systemd-timesyncd 2>/dev/null \
       || systemctl is-active --quiet chronyd 2>/dev/null \
       || systemctl is-active --quiet chrony 2>/dev/null; then
        P_TIMESYNC_OK=1
    fi
    # 家目录契约路径合规（登记制：real+未登记=流浪实体；数据源 home-map.tsv——登记是合规的唯一豁免）
    P_HOME_STRAY=0
    _hm="$COMMON/config/data/home-map.tsv"; [ -f "$_hm" ] || _hm="$BDE_ROOT/config/data/home-map.tsv"
    for _sp in .cache .cargo .rustup .claude .codex .zcode .opencode .gradle .m2 .conda Desktop Documents Downloads Music Pictures Public Templates Videos; do
        _pp="$HOME/$_sp"
        { [ -d "$_pp" ] || [ -f "$_pp" ]; } && [ ! -L "$_pp" ] || continue
        grep -qs "^${_sp}|" "$_hm" || P_HOME_STRAY=$((P_HOME_STRAY+1))
    done

    # 作用域锚点已按机器登记（用户指定制：storage.toml 机器节；未登记=初始化首问未完成）
    P_ANCHOR_REG=0
    _stf="$COMMON/config/data/storage.toml"; [ -f "$_stf" ] || _stf="$BDE_ROOT/config/data/storage.toml"
    [ -f "$_stf" ] && grep -qs "^\[${BDE_MACHINE,,}\." "$_stf" && P_ANCHOR_REG=1

    # 目录登记制 + 命名规范（单实现委托 namecheck：静默扫描三锚点一级 + dir-map，harvest 计数）
    # 校验器异常时不堵塞 doctor（计数归 0 通过——③ 档案缺失会先红在更基础的巡检项上）
    P_DIR_UNREG=0; P_NAME_LEGACY=0
    if BDE_NAMECHECK_QUIET=1 bash "$BDE_ROOT/modules/doc/namecheck.sh" >/dev/null 2>&1 \
       && [ -f "$DEV/docs/state/namecheck.json" ]; then
        eval "$(python3 - "$DEV/docs/state/namecheck.json" <<'PY'
import json, sys, os, shlex
try:
    s = json.load(open(sys.argv[1]))["summary"]
    print(f"P_DIR_UNREG={shlex.quote(str(s.get('hard', 0)))}")
    print(f"P_NAME_LEGACY={shlex.quote(str(s.get('legacy', 0)))}")
except Exception:
    pass
PY
)" || true
    fi

    # 应用档案覆盖缺口（已管集合 apps-classify ∪ home-map 所属应用 ∪ inventory 软件名 vs 档案数）
    P_APP_NOARCH=0
    eval "$(APPS_DIR_T="$COMMON/config/apps" CLASSIFY_T="$COMMON/config/data/apps-classify.tsv" \
            HOME_MAP_T="$COMMON/config/data/home-map.tsv" INV_JSON_T="$DEV/docs/state/inventory.json" \
            python3 <<'PY'
import os, json, glob, tomllib, shlex

def norm(n):
    n = (n or "").strip().lower()
    return n

def cands(n):
    n = norm(n)
    return [n] + ([n.split(".")[0]] if "." in n else [])

man = set()
for f in glob.glob(os.path.join(os.environ["APPS_DIR_T"], "*.toml")):
    try:
        man.add(norm(tomllib.load(open(f, "rb"))["meta"]["name"]))
    except Exception:
        pass

managed = []
try:
    for line in open(os.environ["CLASSIFY_T"]):
        p = line.rstrip("\n").split("|")
        if len(p) >= 2 and p[1].strip() and not p[1].startswith("#"):
            managed.append(p[1])
except Exception:
    pass
try:
    for line in open(os.environ["HOME_MAP_T"]):
        p = line.rstrip("\n").split("|")
        if len(p) >= 2 and p[1].strip() and p[1] != "XDG" and not p[0].startswith("#"):
            managed.append(p[1])
except Exception:
    pass
try:
    inv = json.load(open(os.environ["INV_JSON_T"]))
    managed += [t.get("name", "") for t in inv.get("tools", [])]
    managed += [x.get("name", "") for x in inv.get("discovered", [])]
except Exception:
    pass

miss = 0
seen_m = set()
for n in managed:
    n2 = norm(n)
    if not n2 or n2 in seen_m:
        continue
    seen_m.add(n2)
    if not any(c in man for c in cands(n2)):
        miss += 1
print(f"P_APP_NOARCH={shlex.quote(str(miss))}")
PY
)" || true

    # docker 数据根 bind 实态（① services/docker → /var/lib/docker；已装 docker 的机器才判，否则视图缺席）
    P_DOCKER_PRESENT=0; command -v docker >/dev/null 2>&1 && P_DOCKER_PRESENT=1
    P_DOCKER_ROOT_BIND=0; bde_is_mounted /var/lib/docker && P_DOCKER_ROOT_BIND=1

    # 时区与站点画像一致（画像值：① network.env BDE_TIMEZONE——state-env 再生；缺失回退 Asia/Shanghai 与生成器默认同源）
    [ -f "$DEV/docs/state/network.env" ] && . "$DEV/docs/state/network.env"
    P_TZ_CUR="$(timedatectl show -p Timezone --value 2>/dev/null)"
    P_TZ_WANT="${BDE_TIMEZONE:-Asia/Shanghai}"
    P_TZ_OK=0; { [ -n "$P_TZ_CUR" ] && [ "$P_TZ_CUR" = "$P_TZ_WANT" ]; } && P_TZ_OK=1
    # zram 压缩内存交换（swapon 视角；zramswap/zram-generator 两种机制统一按结果判定）
    P_ZRAM_OK=0; swapon --show --noheadings 2>/dev/null | grep -q zram && P_ZRAM_OK=1

    # 工具链版本表（存在才列；15s 超时——网络劣化时 CLI 版本探测可能挂起）
    P_TOOL_ROWS=""
    _v() {
        # 落盘捕获而非管道：工具派生的子进程（如 zcode crash-capture）会持有 stdout 管道，
        # head 等 EOF 永久阻塞——timeout 只杀父进程救不了管道（2026-11-08 实测挂起）
        local c=$1; shift; local out f
        f="$(mktemp)"
        if command -v timeout >/dev/null 2>&1; then
            timeout -k 2 15 "$c" "$@" >"$f" 2>/dev/null
        else
            "$c" "$@" >"$f" 2>/dev/null
        fi
        out="$(head -1 "$f" 2>/dev/null)"
        rm -f "$f"
        [ -n "$out" ] && printf "%s|%s\n" "$c" "$out"
    }
    # 版本行扫描版：Electron 系 CLI（zcode 等）--version 先吐运行日志再吐版本——
    # head -1 抓到的是日志行而非版本（2026-11-12 实证）；全文扫首个版本号模式
    _v_scan() {
        local c=$1; shift; local out f
        f="$(mktemp)"
        if command -v timeout >/dev/null 2>&1; then
            timeout -k 2 15 "$c" "$@" >"$f" 2>/dev/null
        else
            "$c" "$@" >"$f" 2>/dev/null
        fi
        out="$(grep -Eom1 '(^|[[:space:]])[vV]?[0-9]+(\.[0-9]+)+[^[:space:]]*' "$f" 2>/dev/null | head -1 | sed 's/^[[:space:]]*//')"
        rm -f "$f"
        [ -n "$out" ] && printf "%s|%s\n" "$c" "$out"
    }
    # GUI snap IDE（trae/antigravity/qoder）绝不执行二进制——--version 会真启动 IDE，
    # 15s 超时后被 timeout 杀掉，用户侧表现为 IDE 反复重启（2026-11-12 实证）；改读 snap 元数据
    _v_snap() {
        local c=$1 out
        out="$(snap list "$c" 2>/dev/null | awk 'NR==2{print $2" (snap)"}')"
        [ -n "$out" ] && printf "%s|%s\n" "$c" "$out"
    }
    P_TOOL_ROWS+="$( _v git    --version )"$'\n'
    P_TOOL_ROWS+="$( _v docker --version )"$'\n'
    P_TOOL_ROWS+="$( _v node   --version )"$'\n'
    P_TOOL_ROWS+="$( _v npm    --version )"$'\n'
    P_TOOL_ROWS+="$( _v python3 --version )"$'\n'
    P_TOOL_ROWS+="$( _v uv     --version )"$'\n'
    P_TOOL_ROWS+="$( _v cargo  --version )"$'\n'
    P_TOOL_ROWS+="$( _v go     version )"$'\n'
    P_TOOL_ROWS+="$( _v flutter --version 2>/dev/null | head -1 )"$'\n'
    P_TOOL_ROWS+="$( _v mise   --version 2>/dev/null | head -1 )"$'\n'
    P_TOOL_ROWS+="$( _v chezmoi --version 2>/dev/null | head -1 )"$'\n'
    P_TOOL_ROWS+="$( _v starship --version 2>/dev/null | head -1 )"$'\n'
    P_TOOL_ROWS+="$( _v code --version 2>/dev/null | head -1 )"$'\n'
    P_TOOL_ROWS+="$( _v claude   --version 2>/dev/null | head -1 )"$'\n'
    P_TOOL_ROWS+="$( _v codex    --version 2>/dev/null | head -1 )"$'\n'
    P_TOOL_ROWS+="$( _v gemini  --version 2>/dev/null | head -1 )"$'\n'
    P_TOOL_ROWS+="$( _v opencode --version 2>/dev/null | head -1 )"$'\n'
    P_TOOL_ROWS+="$( _v arkcli  --version 2>/dev/null | head -1 )"$'\n'
    P_TOOL_ROWS+="$( _v_scan zcode  --version )"$'\n'
    P_TOOL_ROWS+="$( _v_snap trae )"$'\n'
    P_TOOL_ROWS+="$( _v_snap antigravity )"$'\n'
    P_TOOL_ROWS+="$( _v_snap qoder )"$'\n'
    P_TOOL_ROWS+="$( _v copilot --version 2>/dev/null | head -1 )"$'\n'
    P_TOOL_ROWS="$(printf '%s' "$P_TOOL_ROWS" | grep -v '^$')"
}

bde_probe_export() {  # 导出全部事实为环境变量（JSON 构建器消费）
    local v
    for v in ${!P_@}; do export "$v"; done
}

bde_probe_json() {  # L2 模型：schema 化 JSON（唯一机器接口）
    bde_probe_export
    python3 - <<'PYEOF'
import os, json, sys

def i(k, d=0):
    try:
        return int(os.environ.get(k, d) or d)
    except ValueError:
        return d

p = {k[2:]: v for k, v in os.environ.items() if k.startswith("P_")}
tools = {}
for line in (p.get("TOOL_ROWS") or "").splitlines():
    if "|" in line:
        t, v = line.split("|", 1)
        tools[t.strip()] = v.strip()

# ⚠ doc 曾缩进在 for 循环体内：TOOL_ROWS 为空时 for 体不执行 → doc 未定义 NameError，
#   probe --json 全挂（潜阀事故）；循环外构建，空表也要出完整快照
doc = {
        "schema": "bde.probe/2",
        "machine": p.get("HOST", ""),
        "os": p.get("OS", ""),
        "os_id": p.get("OS_ID", ""),
        "os_family": p.get("OS_FAMILY", "unknown"),
        "os_family_group": p.get("OS_FAMILY_GROUP", "unknown"),
        "kernel": p.get("KERNEL", ""),
    "user": p.get("USER", ""),
    "date": p.get("DATE", ""),
    "anchors": {
        "dev": os.environ.get("DEV", ""),
        "share": os.environ.get("SHARE", ""),
        "common": os.environ.get("COMMON", ""),
        "local": os.environ.get("LOCAL", ""),
        "state": p.get("SHARE_STATE", "unknown"),
    },
    "facts": {
        "common_writable": i("P_COMMON_WRITABLE"),
        "local_writable": i("P_LOCAL_WRITABLE"),
        "layer_common": i("P_LAYER_COMMON"),
        "layer_local": i("P_LAYER_LOCAL"),
        "config_ready": i("P_CONFIG_OK"),
        "env_sh_applied": i("P_ENV_SH"),
        "skeleton_ready": i("P_SKELETON"),
        "agents_md": i("P_AGENTS_MD"),
        "dispatcher_ok": i("P_DISPATCHER_OK"),
        "gen_fresh": i("P_GEN_FRESH"),
        "gen_stale": p.get("GEN_STALE", ""),
        "runtime_missing": (p.get("RUNTIME_MISSING", "") or "").strip(),
        "host_registered": i("P_HOST_REG"),
        "mcp_canon": i("P_MCP_CANON"),
        "runtime_wired": i("P_RUNTIME_OK"),
        "cfg_drift": i("P_CFG_DRIFT"),
        "cfg_dirty": i("P_CFG_DIRTY"),
        "cfg_backup": i("P_CFG_BACKUP"),
        "agents_canon": i("P_AGENTS_CANON"),
        "ide_ready": i("P_IDE_OK"),
        "xdg_redirect": 1 if p.get("XDG_DOC") else 0,
        "inotify_ok": i("P_INOTIFY_OK"),
        "sysctl_ok": i("P_SYSCTL_OK"),
        "fstrim_ok": i("P_FSTRIM_OK"),
        "timesync_ok": i("P_TIMESYNC_OK"),
        "tz_ok": i("P_TZ_OK"),
        "zram_ok": i("P_ZRAM_OK"),
        "docker_present": i("P_DOCKER_PRESENT"),
        "home_stray": i("P_HOME_STRAY"),
        "anchor_reg": i("P_ANCHOR_REG"),
        "dir_unreg": i("P_DIR_UNREG"),
        "name_legacy": i("P_NAME_LEGACY"),
        "app_noarch": i("P_APP_NOARCH"),
        "docker_root_bind": i("P_DOCKER_ROOT_BIND"),
    },
    "storage": {
        "backend_common": p.get("BACKEND_COMMON", "unknown"),
        "backend_host": p.get("BACKEND_HOST", "unknown"),
        "mounted_common": i("P_MOUNTED_COMMON"),
        "mounted_host": i("P_MOUNTED_HOST"),
        "persisted_common": i("P_PERSIST_COMMON"),
        "persisted_host": i("P_PERSIST_HOST"),
        "profile_error": i("P_PROFILE_ERR"),
        "profile_error_msg": p.get("PROFILE_ERR_MSG", ""),
    },
    "share_caps": {
        "probed": i("P_CAP_PROBED"),
        "symlink": i("P_CAP_SYMLINK"),
        "hardlink": i("P_CAP_HARDLINK"),
        "case_sensitive": i("P_CAP_CASE"),
        "perm": i("P_CAP_PERM"),
        "name255": i("P_CAP_NAME255"),
    },
    "values": {
        "disk_root_used": p.get("DISK_ROOT_USE", ""),
        "disk_root_free_mb": i("P_DISK_ROOT_FREE_MB"),
        "inotify_watches": i("P_INOTIFY_W"),
        "swappiness": i("P_SYSCTL_SWAP"),
        "timezone": p.get("TZ_CUR", ""),
        "timezone_want": p.get("TZ_WANT", ""),
        "xdg_doc": p.get("XDG_DOC", ""),
    },
    "tools": tools,
}
json.dump(doc, sys.stdout, ensure_ascii=False, indent=2)
print()
PYEOF
}

bde_probe_save() {  # 落快照（原子写）——视图从这里读
    bde_probe_collect
    mkdir -p "$BDE_PROBE_STATE_DIR" 2>/dev/null
    local f="$BDE_PROBE_STATE_DIR/probe.json"   # 分两行声明：同语句内 $f 展开在赋值前，set -u 下会 unbound
    local t="$f.tmp"
    bde_probe_json > "$t" && mv "$t" "$f" && printf '%s\n' "$f"
}

bde_probe_print() {  # 人类速览（正式视图在 doctor/report）
    echo "机器: $P_HOST ｜ $P_OS (kernel $P_KERNEL) ｜ probe $P_DATE"
    echo "锚点: $SHARE（$P_SHARE_STATE）｜ ③ $COMMON（$P_BACKEND_COMMON）② $LOCAL（$P_BACKEND_HOST）｜ 根盘: $P_DISK_ROOT_USE（剩 $(awk "BEGIN{printf \"%.1f\", $P_DISK_ROOT_FREE_MB/1024}")G）"
    if [ "$P_CAP_PROBED" = "1" ]; then
        echo "共享盘能力: symlink=$P_CAP_SYMLINK hardlink=$P_CAP_HARDLINK 大小写敏感=$P_CAP_CASE 权限=$P_CAP_PERM 文件名255B=$P_CAP_NAME255"
    fi
    printf '%s\n' "$P_TOOL_ROWS" | while IFS='|' read -r t v; do
        [ -n "$t" ] && printf "  %-10s %s\n" "$t" "$v"
    done
}

# 直接执行：probe.sh [--json|--save|--human]
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    case "${1:-}" in
        --json)        bde_probe_collect; bde_probe_json ;;
        --save)        bde_probe_save ;;
        --human|"")    bde_probe_collect; bde_probe_print ;;
        *) echo "用法: probe.sh [--json|--save|--human]"; exit 2 ;;
    esac
fi
