#!/usr/bin/env bash
# modules/dirs/exec-gen.sh — ① 命令入口再生器（devenv / code-* 四件套 / vibe）
# 单一实现：M2（modules/dirs/linux.sh）调用；独立执行 = 只再生入口，不碰目录/挂载
# 契约：入口住 ①（本机盘，共享盘掉线仍可诊断）；BDE_ROOT 写生成时的真值 + 候选回退（迁移期兼容）
[ -n "${BDE_ROOT:-}" ] || BDE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$BDE_ROOT/lib/paths.sh"
source "$BDE_ROOT/lib/common.sh"
source "$BDE_ROOT/lib/ensure.sh"

EXEC="$DEV/00_Exec"
ensure_dir "$EXEC" || { bde_fail "入口目录不可建：$EXEC"; exit 1; }

# 候选回退：生成时的真值失效（仓库搬家/共享盘未挂）时按序探测——分发器永不因搬家失联
_cands="\"$BDE_ROOT\" \"/Share/Common/40_CodeSpace/BestDevEnv\" \"$COMMON/code/BestDevEnv\" \"\$HOME/Share/Common/40_CodeSpace/BestDevEnv\""

# ── devenv：统一分发器（子命令 → 模块脚本）──
cat > "$EXEC/devenv" <<EOF
#!/usr/bin/env bash
# devenv — 开发环境入口（由 BestDevEnv/modules/dirs/exec-gen.sh 生成于 $(date +%F)）
BDE_ROOT="$BDE_ROOT"
if [ ! -d "\$BDE_ROOT/lib" ]; then
    for _cand in $_cands; do
        if [ -d "\$_cand/lib" ]; then BDE_ROOT="\$_cand"; break; fi
    done
fi
_usage() {
    cat <<'USAGE'
用法: devenv <命令> [参数]

  探环境  brief（一次采集速览）｜doctor（逐项 ✓/✗）｜report（markdown 留痕）
  治理    cfg [list|diff|apply|adopt|snapshot|restore]｜svc｜state-env
          namecheck [--migrate]｜lint（文档锚点可解析）｜index｜map [--sizes]
          app [名称|--all|--audit|--migrate]｜inventory [--migrate]
  维护    tidy（清可再生缓存）｜runtime [list|wire|mcp|skill|sessions]
          gen（再生 AGENTS.md + SKILL 正本）｜migrate-finish｜cap（能力矩阵）
  元信息  root（工程根）｜version
  orch    new|add|next|done|fail|edit|drop|revert|status|list（长任务账本）
USAGE
}
case "\${1:-}" in
    brief)      shift; exec bash "\$BDE_ROOT/modules/doc/brief.sh" "\$@" ;;
    doctor)     shift; exec bash "\$BDE_ROOT/verify/doctor.sh" "\$@" ;;
    report)     shift; exec bash "\$BDE_ROOT/modules/doc/report.sh" "\$@" ;;
    lint)       shift; exec bash "\$BDE_ROOT/modules/doc/anchorlint.sh" "\$@" ;;
    tidy)       shift; exec bash "\$BDE_ROOT/modules/tidy.sh" "\$@" ;;
    map)        shift; exec bash "\$BDE_ROOT/modules/home-map.sh" "\$@" ;;
    orch)       shift; exec bash "\$BDE_ROOT/modules/orch/orch.sh" "\$@" ;;
    runtime)    shift; exec bash "\$BDE_ROOT/modules/agent/runtime.sh" "\$@" ;;
    cfg)        shift; exec bash "\$BDE_ROOT/modules/cfg/cfg.sh" "\$@" ;;
    svc)        shift; exec bash "\$BDE_ROOT/modules/cfg/cfg.sh" --svc "\$@" ;;
    cap)        shift; exec bash "\$BDE_ROOT/lib/cap.sh" "\$@" ;;
    inventory)  shift; exec bash "\$BDE_ROOT/modules/doc/inventory.sh" "\$@" ;;
    app)        shift; exec bash "\$BDE_ROOT/modules/app/app.sh" "\$@" ;;
    index)      shift; exec bash "\$BDE_ROOT/modules/doc/dirindex.sh" "\$@" ;;
    namecheck)  shift; exec bash "\$BDE_ROOT/modules/doc/namecheck.sh" "\$@" ;;
    gen)        shift; exec bash "\$BDE_ROOT/modules/agent/agents-md.sh" "\$@" ;;
    state-env)  shift; exec bash "\$BDE_ROOT/modules/dirs/state-env.sh" "\$@" ;;
    migrate-finish) shift; exec bash "\$BDE_ROOT/modules/dirs/migrate-finish.sh" "\$@" ;;
    root)       printf '%s\n' "\$BDE_ROOT" ;;
    version)    printf 'devenv %s ｜ 机器 %s ｜ 工程根 %s\n' \\
                    "\$(git -C "\$BDE_ROOT" rev-parse --short HEAD 2>/dev/null || echo unknown)" \\
                    "\$(hostname)" "\$BDE_ROOT" ;;
    help|-h|--help|"") _usage ;;
    *) _usage; exit 2 ;;
esac
EOF
chmod +x "$EXEC/devenv"

# ── code-* 四件套：仓库日常（code-open/close/nm/out）──
for _w in code-open code-close code-nm code-out; do
    cat > "$EXEC/$_w" <<EOF
#!/usr/bin/env bash
# $_w — 由 BestDevEnv/modules/dirs/exec-gen.sh 生成（实现：modules/workflow/$_w.sh）
BDE_ROOT="$BDE_ROOT"
if [ ! -d "\$BDE_ROOT/lib" ]; then
    for _cand in $_cands; do
        if [ -d "\$_cand/lib" ]; then BDE_ROOT="\$_cand"; break; fi
    done
fi
exec bash "\$BDE_ROOT/modules/workflow/$_w.sh" "\$@"
EOF
    chmod +x "$EXEC/$_w"
done

# ── vibe：Runtime 统一启动入口（先接 env.sh 契约再 exec）──
cat > "$EXEC/vibe" <<EOF
#!/usr/bin/env bash
# vibe — Runtime 统一启动（source env.sh 后 exec；实现：modules/agent/runtime.sh）
. "\$HOME/.config/devspace/env.sh" 2>/dev/null
BDE_ROOT="\${BDE_ROOT:-$BDE_ROOT}"
if [ ! -d "\$BDE_ROOT/lib" ]; then
    for _cand in $_cands; do
        if [ -d "\$_cand/lib" ]; then BDE_ROOT="\$_cand"; break; fi
    done
fi
exec bash "\$BDE_ROOT/modules/agent/runtime.sh" "\$@"
EOF
chmod +x "$EXEC/vibe"

rm -f "$EXEC/env"   # 旧分发器除名（曾遮蔽 coreutils env——命名规范 §20.4）
bde_ok "入口再生：devenv（brief/doctor/lint/…）+ code-open/close/nm/out + vibe；旧 env 已除名"
