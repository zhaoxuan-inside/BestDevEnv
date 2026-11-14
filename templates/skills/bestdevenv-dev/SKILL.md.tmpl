---
name: bestdevenv-dev
version: 0.0.2
description: BestDevEnv 部署开发环境——按开发者角色（profiles.tsv：java-web/python/go/cpp/ml-trainer/fullstack）或语言栈（node/python/rust/go/java/flutter/ai/cpp：安装+国内镜像+缓存重定向）、vibecoding 工具（claude-code/codex/gemini/opencode/zcode/arkcli）、VS Code 离线安装与语言扩展档案、JetBrains 需求推导时使用。触发：装语言、装 agent 工具、装 IDE、按角色配环境、扩展档案。
---

# 部署开发环境（M3 语言栈 + M4 工具 + M6 IDE）

单一职责：装语言/工具/IDE 并落镜像与重定向。每个脚本幂等，内部分四步：安装 → 镜像 → 重定向 → 校验。

## 先确认再装（硬协议）

执行任何安装前，必须先向用户列出可选清单并确认，**不得按默认静默安装**：

- **开发者角色**（首选；`modules/lang/profiles.tsv` 数据驱动）：java-web / python / go / cpp / ml-trainer / fullstack——角色展开为栈集合并集，`./init.sh --profile ml-trainer` 或交互首问
- **语言栈**（八选 N，合法集以 `modules/lang/` 脚本为准）：node / python / rust / go / java / flutter / ai / cpp
- **vibecoding 工具**（合法集以 `modules/agent/runtimes.tsv` 注册表为准）：claude-code / codex / gemini-cli / opencode / zcode / arkcli / copilot / antigravity / trae / qoder / hermes

用户确认后才执行；确认结果经 `BDE_LANGS`/`BDE_TOOLS` 显式传参落位。两个例外场景不必二次确认：
init.sh 全量管道（自带交互询问与校验）、用户在本次会话已明确给出清单。

## 装前四问（硬协议：任何安装动作前必须逐项回答，未答不装）

1. **安装位置→受管根**：实体只落 系统包管理器 / ① DevEnv（Apps/Deps/Tool）/ ② Local——**禁止家目录散装与 ③ 共享盘实体**（inventory 渠道审计判违规）；版本管理器工具链（mise/nvm/cargo…）优先
2. **配置位置→③**：配置正本收编 `$COMMON/config`（`devenv cfg adopt`），严禁默认配置散落家目录
3. **日志位置→②**：运行/构建日志约定落 `② $LOCAL/Logs/<名称>/`
4. **数据缓存/产出**：数据与缓存按作用域落 ②③（锁敏感→②，可共享→③）；打包产出交付 `③ Relay/<名称>/`

## 装后四步（验收前逐项过）

1. **建档**：`$COMMON/config/apps/<名称>.toml`（安装位置 at / 配置 / 数据 / 日志五要素，字段见 docker.toml）
2. **配置收编**：`devenv cfg adopt` + `cfg apply`——一切优化（镜像源/缓存重定向/服务参数/日志轮转）以受管配置正本落地，**不另立优化文档**；未落正本的优化=漂移
3. **登记**：新目录先登记 dir-map（`③ config/data/dir-map.tsv`，命名按 NN_ 大写 4-6 规范）；Runtime 类工具 runtimes.tsv + `devenv runtime wire`
4. **复核**：`devenv app --audit` 覆盖缺口与 `devenv doctor` 巡检

## 语言栈（按需选装，幂等）

```bash
source "$HOME/.config/devspace/env.sh"
BDE="$COMMON/code/BestDevEnv"
bash "$BDE/modules/lang/node.sh"      # 或 python/rust/go/java/flutter/ai.sh
```

| 语言 | 版本管理器 | 缓存/依赖落点 |
|---|---|---|
| node | mise（nvm 兼容期） | store/cache → Common/cache/linux；实体 → DevEnv/deps |
| python | uv | venv → DevEnv/virtualenvs；cache → Common/cache/linux |
| rust | rustup（rsproxy） | CARGO_HOME=DevEnv/cargo；target → Local/build |
| go | 官方 tarball（goproxy.cn） | GOPATH=DevEnv/go |
| java | 语义包 java-21（适配器别名，apt=openjdk-21-jdk） | GRADLE_USER_HOME=Local/cache/gradle + gradle-properties 正本 |
| flutter | DevEnv/flutter（flutter-io.cn） | PUB_CACHE=DevEnv/pub-cache |
| cpp | 语义包 build-base + cmake/ninja/gdb/ccache/clangd | CCACHE_DIR=Local/cache/ccache |
| ai | Miniconda（tuna → DevEnv/services/miniconda3；.condarc 正本：envs/pkgs → DevEnv/deps/conda）+ CUDA 体检 | HF_HOME/MODELSCOPE_CACHE → Common/data/models |

## vibecoding 工具与 IDE

```bash
BDE_TOOLS="claude-code,codex,zcode" bash "$BDE/modules/agent/tools.sh"   # 幂等，已装只登记；合法集见 runtimes.tsv
devenv gen                                 # 再生 AGENTS.md + SKILL 正本（= bash "$BDE/modules/agent/agents-md.sh"）
bash "$BDE/modules/agent/runtime.sh"      # Runtime 统一接线（记忆/Skill/MCP/会话，按 runtimes.tsv）
bash "$BDE/modules/ide/ide.sh" --no-jetbrains   # VS Code 离线 deb + 扩展档案（BDE_LANGS）；--no-jetbrains 跳过 JetBrains 推导
```

- **BDE_TOOLS/BDE_LANGS 均为逗号分隔 CSV**——空格分隔会被拼成一个非法名字（2026-11-12 实测）
- opencode 实体契约位 = ① `$DEV/apps/agent/.opencode/bin`（env.sh PATH 预置）：installer 默认落 `~/.opencode/bin`，tools.sh 安装/发现时自动归位 ①；已装判 `command -v` 与契约位双查
- 扩展档案在 `$COMMON/config/ide/vscode/{base,<语言>}.txt`——新装扩展未入档案时 ide.sh 会提示补录
- GUI 类工具（trae/antigravity/qoder）走人工安装，脚本只登记
- **装服务/软件/工具后**：按「装后四步」走——建档（apps/<name>.toml）+ `devenv cfg adopt <name> <路径>` 收编进 `$COMMON/config/services/`（版本化 + `devenv cfg apply` 落位 + doctor 巡检漂移）；Runtime 类工具另走 runtimes.tsv 登记 + `devenv runtime wire`
- **存量软件受管化**：位置违规的已装软件用 `devenv app --migrate` 处置——先展示影响（体积/引用/服务），**逐项经用户授权后**实体搬入受管根 + 原位 symlink 接回，迁移后验证可用

## 验收

`devenv report` 版本表出现所装工具；缓存路径探测指向 Common/DevEnv（非默认 `~/.cache`）；共享盘 JS 项目可正常 `npm install`（依赖实体在本机盘 ①）。
