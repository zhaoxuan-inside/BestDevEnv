# env.sh — 环境变量契约（宪法 §6.1；唯一权威块，BestDevEnv/config 种子）
# 由 ~/.zshrc / ~/.bashrc / ~/.profile / ~/.zshenv source；装载守卫防重复 source（PATH 增重）
# 机器/站点差异不写死在本文件：
#   锚点 → ① $DEV/docs/state/anchors.env（devenv state-env 由 ③ storage.toml 再生）
#   网络 → ① $DEV/docs/state/network.env（devenv state-env 由 ③ network.toml 再生）
#   机器数据 → hosts.toml（工程仓库，apply-config 单向同步）
# 下方字面值均为 bootstrap 兜底（状态 env 缺失时生效，如全新机器 M2 之前/状态丢失）

[ -n "${BDE_ENV_SH_LOADED:-}" ] && return 0 2>/dev/null || BDE_ENV_SH_LOADED=1

# ── 三档锚点 ─────────────────────────────────────────────
DEV="${DEV:-$HOME/DevEnv}"                               # ① 先定位状态正本所在
if [ -f "$DEV/docs/state/anchors.env" ]; then
    . "$DEV/docs/state/anchors.env"                      # 每机器锚点正本（无条件覆盖；挂载下线由 doctor 报告，不静默改道）
else
    # bootstrap 兜底（M2 之前）：静态锚点 + 旧挂载回退（迁移完成前）
    SHARE="${SHARE:-/Share}"
    [ -d "$SHARE/Common" ] || SHARE="$HOME/Share"
    COMMON="$SHARE/Common"; LOCAL="$SHARE/Local"
fi
export DEV SHARE COMMON LOCAL
export XDG_CONFIG_HOME="$DEV/xdg/config"
export XDG_DATA_HOME="$DEV/xdg/local"
export XDG_STATE_HOME="$DEV/xdg/local/state"
export PYTHONUSERBASE="$DEV/xdg/local"  # pip --user 落点
export XDG_CACHE_HOME="$DEV/xdg/cache"
export PATH="$DEV/bin:$HOME/.local/bin:$DEV/cargo/bin:$DEV/npm-global/bin:$DEV/xdg/local/bin:$DEV/apps/agent/.opencode/bin:$PATH"    # 个人脚本优先（~/.local/bin：starship/uv/chezmoi/mise；cargo/bin：rust 工具链 ① 收敛落点）

# ── 工具链与依赖态（① 本机盘，symlink 需要）────────────────
export RUSTUP_HOME="$DEV/rustup"
export CARGO_HOME="$DEV/cargo"
export GOPATH="$DEV/go"
export PUB_CACHE="$DEV/pub-cache"
# 构建缓存落点契约（宪法 §19.4 十分离：缓存包 → ②③，绝不落家目录）
export GRADLE_USER_HOME="$LOCAL/cache/gradle"                            # Gradle 缓存 → ②（全局化，替代未落地的 direnv 注入）
export MAVEN_OPTS="${MAVEN_OPTS:+$MAVEN_OPTS }-Dmaven.repo.local=$LOCAL/cache/m2"  # Maven 仓库双保险（settings.xml 已指 Local/cache/m2）
# 以下两个仍为"按项目"变量（路径含仓库名），由 direnv/.envrc 注入（templates/project.envrc 待落地）：
#   UV_PROJECT_ENVIRONMENT=$DEV/virtualenvs/<repo>
#   CARGO_TARGET_DIR=$LOCAL/build/<repo>

# ── 下载缓存与模型（③，linux 域三机共享）─────────────────
export PIP_CACHE_DIR="$COMMON/cache/linux/pip"
export UV_CACHE_DIR="$COMMON/cache/linux/uv"
export HF_HOME="$COMMON/data/models/huggingface"
export MODELSCOPE_CACHE="$COMMON/data/models/modelscope"

# ── 家目录收敛契约（宪法 §20.5：支持原生重定向的工具，入口一律迁出家目录）──
export IPYTHONDIR="$DEV/apps/dev/.ipython"            # 实体 ①（家目录 .ipython 链接退役）
export JUPYTER_CONFIG_DIR="$DEV/apps/dev/.jupyter"    # 实体 ①
export ANDROID_USER_HOME="$DEV/apps/dev/.android"     # 实体 ①（adb 密钥）
export DOCKER_CONFIG="$DEV/apps/dev/.docker"          # 实体 ①（CLI 登录态；daemon 配置另在 /etc）
export VSCODE_EXTENSIONS="$DEV/apps/ide/vscode/home/extensions"  # VS Code 扩展（实测被尊重）
export VSCODE_AGENT_FOLDER="$DEV/apps/ide/vscode/server"         # 远程服务端安装位
export CLAUDE_CONFIG_DIR="$DEV/apps/agent/.claude"    # 实体 ①（.claude.json 随迁已实测；~/.claude 链接保留供交叉工具）
export CODEX_HOME="$DEV/apps/agent/.codex"            # 实体 ①
export ZCODE_CONFIG_DIR="$DEV/apps/agent/.zcode"      # zcode（JS 内 41 处引用，实测支持）
export OPENCODE_CONFIG_DIR="$DEV/apps/agent/.opencode"  # opencode 根（含 bin/）
export HISTFILE="$DEV/history/bash"                   # bash 历史 → ①（用户活状态）

# ── 网络画像（镜像清单 + 代理出口；站点差异查 ③ network.toml 档案，不写死在这）──
if [ -f "$DEV/docs/state/network.env" ]; then
    . "$DEV/docs/state/network.env"                      # 每机器网络正本（devenv state-env 再生）
else
    # bootstrap 兜底（家庭 LAN 站点基线；network.env 生成后本段不参与）
    # OpenAI/Codex 仅在此出口下可用；国内镜像/内网段走 no_proxy 直连
    export BDE_NODE_DIST_MIRROR=https://cdn.npmmirror.com/binaries/node/  # node 发行镜像（node.sh 消费；尾斜杠必留）
    export PIP_INDEX_URL=https://mirrors.aliyun.com/pypi/simple/
    export RUSTUP_DIST_SERVER=https://rsproxy.cn
    export RUSTUP_UPDATE_ROOT=https://rsproxy.cn/rustup
    export GOPROXY=https://goproxy.cn,direct
    export PUB_HOSTED_URL=https://pub.flutter-io.cn
    export FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn
    export HF_ENDPOINT=https://hf-mirror.com
    export https_proxy="http://192.168.1.100:7890"
    export http_proxy="$https_proxy"
    export all_proxy="$https_proxy"
    export HTTPS_PROXY="$https_proxy" HTTP_PROXY="$http_proxy" ALL_PROXY="$all_proxy"
    export NO_PROXY="localhost,127.0.0.1,::1,192.168.0.0/16,10.0.0.0/8,172.16.0.0/12,.aliyuncs.com,.aliyun.com,.cn"
    export no_proxy="$NO_PROXY"
fi
