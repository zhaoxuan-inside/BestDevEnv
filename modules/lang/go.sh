#!/usr/bin/env bash
# M3: Go —— apt 安装 + goproxy + GOPATH
[ -n "${BDE_ROOT:-}" ] || BDE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$BDE_ROOT/lib/paths.sh"
source "$BDE_ROOT/lib/common.sh"
source "$BDE_ROOT/lib/ensure.sh"

bde_info "M3 go"

if command -v go >/dev/null 2>&1; then
    bde_ok "go 已装：$(go version 2>/dev/null)"
else
    ensure_pkg "golang-go"
    command -v go >/dev/null 2>&1 && bde_ok "go 安装：$(go version)"
fi

ensure_dir "$DEV/go" 2>/dev/null || true
[ -f "$HOME/.config/devspace/env.sh" ] && bde_ok "GOPROXY/GOPATH → env.sh 就绪"
