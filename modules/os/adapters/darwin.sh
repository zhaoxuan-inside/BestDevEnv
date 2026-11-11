#!/usr/bin/env bash
# modules/os/adapters/darwin.sh — L2 平台适配器：macOS（darwin）
# 最小实装：pkg（brew）。svc/kernel/limits/logs/trim/timesync/im/terminal/group 为 P2 里程碑
# 占位（launchd/sysctl/newsyslog/dscl 机制未实机验证——诚实降级，总线自动 pending）。
# 注意：macOS 自带 bash 3.2——本适配器及基座不使用关联数组等 bash4+ 特性。
[ -n "${BDE_ROOT:-}" ] || BDE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$BDE_ROOT/lib/ensure.sh"

CAP_FAMILY="darwin"

# ── 语义包别名（→ brew 名；未知名透传）──
cap__pkg_alias() {
    case "$1" in
        base)          echo "openssh zsh" ;;
        build-base)    echo "cmake" ;;
        java-21)       echo "openjdk@21" ;;
        docker-engine) echo "--cask docker" ;;     # cask 形态：brew install --cask docker
        terminal)      echo "" ;;                 # 桌面统一 = P2 里程碑（Terminal.app/iTerm 待定）
        im-suite)      echo "" ;;                 # macOS 输入法 = P2 里程碑
        *)             echo "$1" ;;
    esac
}

# ── pkg（brew）──
_brew_bin() { [ -x /opt/homebrew/bin/brew ] && echo /opt/homebrew/bin/brew || echo /usr/local/bin/brew; }
cap__pkg_installed() {
    local b; b="$(_brew_bin)"
    [ -x "$b" ] || return 1
    "$b" ls --versions "$1" >/dev/null 2>&1
}
cap__pkg_install() {
    local b; b="$(_brew_bin)"
    [ -x "$b" ] || { bde_pending "brew 未安装（先装 Homebrew）"; return 1; }
    "$b" install "$@"
}
cap__pkg_check_source() {
    bde_pending "brew 源检查未实装（USTC/TUNA brew 镜像可人工配置）"
    return 1
}

# ── hostname（mac 机制：scutil；get 可用，set 走 sudo 需交互密码——降级 pending）──
cap__hostname_get() { scutil --get LocalHostName 2>/dev/null || hostname; }
