#!/usr/bin/env bash
# M3: Java —— openjdk（后续可切 mise temurin）；gradle/maven 缓存外置
[ -n "${BDE_ROOT:-}" ] || BDE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$BDE_ROOT/lib/paths.sh"
source "$BDE_ROOT/lib/common.sh"
source "$BDE_ROOT/lib/ensure.sh"

bde_info "M3 java"

if command -v java >/dev/null 2>&1; then
    bde_ok "java 已装：$(java -version 2>&1 | head -1)"
else
    ensure_pkg "openjdk-21-jdk"
    command -v java >/dev/null 2>&1 && bde_ok "java 安装：$(java -version 2>&1 | head -1)"
fi

ensure_dir "$LOCAL/cache/gradle" 2>/dev/null || true
ensure_dir "$LOCAL/cache/m2" 2>/dev/null || true
bde_ok "gradle/maven 缓存 → $LOCAL/cache（按机隔离，防锁冲突）"
