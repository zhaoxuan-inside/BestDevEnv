# env.sh — 环境变量契约（宪法 §6.1；唯一权威块，BestDevEnv/config 种子）
# 由 ~/.zshrc / ~/.bashrc source；机器差异查 hosts.toml，不写死在这

# ── 三档锚点 ─────────────────────────────────────────────
export DEV="$HOME/DevEnv"                                # ① 本机文件系统
SHARE="${SHARE:-/Share}"                                 # 外部存储锚点
[ -d "$SHARE/Common" ] || SHARE="$HOME/Share"            # 迁移前回退（旧挂载）
export SHARE
export COMMON="$SHARE/Common"                            # ③ 多机共享
export LOCAL="$SHARE/Local"                              # ② 本机专享
export XDG_CONFIG_HOME="$DEV/xdg/config"
export XDG_DATA_HOME="$DEV/xdg/local"
export XDG_CACHE_HOME="$DEV/xdg/cache"
export PATH="$DEV/bin:$DEV/npm-global/bin:$HOME/.local/bin:$HOME/.opencode/bin:$PATH"    # 个人脚本优先

# ── 工具链与依赖态（①，VM 盘）────────────────────────────
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
export CLAUDE_CONFIG_DIR="$DEV/apps/agent/.claude"    # 实体 ①（.claude.json 随迁已实测；~/.claude 链接保留供交叉工具）
export CODEX_HOME="$DEV/apps/agent/.codex"            # 实体 ①（~/.codex 链接保留供交叉工具）

# ── 国内镜像（统一清单，一处改全机生效）──────────────────
export PIP_INDEX_URL=https://mirrors.aliyun.com/pypi/simple/
export RUSTUP_DIST_SERVER=https://rsproxy.cn
export RUSTUP_UPDATE_ROOT=https://rsproxy.cn/rustup
export GOPROXY=https://goproxy.cn,direct
export PUB_HOSTED_URL=https://pub.flutter-io.cn
export FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn
export HF_ENDPOINT=https://hf-mirror.com
