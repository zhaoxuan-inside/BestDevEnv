---
name: bestdevenv-dev
version: 0.0.2
description: BestDevEnv 部署开发环境——语言栈（node/python/rust/go/java/flutter/ai：安装+国内镜像+缓存重定向）、vibecoding 工具（claude-code/codex/gemini/opencode/zcode/arkcli）、VS Code 离线安装与语言扩展档案、JetBrains 需求推导时使用。触发：装语言、装 agent 工具、装 IDE、扩展档案。
---

# 部署开发环境（M3 语言栈 + M4 工具 + M6 IDE）

单一职责：装语言/工具/IDE 并落镜像与重定向。每个脚本幂等，内部分四步：安装 → 镜像 → 重定向 → 校验。

## 先确认再装（硬协议）

执行任何安装前，必须先向用户列出可选清单并确认，**不得按默认静默安装**：

- **语言栈**（七选 N，合法集以 `modules/lang/` 脚本为准）：node / python / rust / go / java / flutter / ai
- **vibecoding 工具**（合法集以 `modules/agent/runtimes.tsv` 注册表为准）：claude-code / codex / gemini-cli / opencode / zcode / arkcli / copilot / antigravity / trae / qoder / hermes

用户确认后才执行；确认结果经 `BDE_LANGS`/`BDE_TOOLS` 显式传参落位。两个例外场景不必二次确认：
init.sh 全量管道（自带交互询问与校验）、用户在本次会话已明确给出清单。

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
| java | mise temurin（aliyun maven） | GRADLE_USER_HOME=Local/cache/gradle |
| flutter | DevEnv/flutter（flutter-io.cn） | PUB_CACHE=DevEnv/pub-cache |
| ai | hf/modelscope（hf-mirror） | HF_HOME → Common/data/models |

## vibecoding 工具与 IDE

```bash
BDE_TOOLS="<用户确认的清单>" bash "$BDE/modules/agent/tools.sh"   # 幂等，已装只登记；合法集见 runtimes.tsv
devenv gen                                 # 再生 AGENTS.md + SKILL 正本（= bash "$BDE/modules/agent/agents-md.sh"）
bash "$BDE/modules/agent/runtime.sh"      # Runtime 统一接线（记忆/Skill/MCP/会话，按 runtimes.tsv）
bash "$BDE/modules/ide/ide.sh"            # VS Code 离线 deb + 扩展档案（BDE_LANGS）+ JetBrains 推导（--no-jetbrains 可跳过）
```

- 扩展档案在 `$COMMON/config/ide/vscode/{base,<语言>}.txt`——新装扩展未入档案时 ide.sh 会提示补录
- GUI 类工具（trae/antigravity/qoder）走人工安装，脚本只登记
- **装服务/软件/工具后**：配置文件用 `devenv cfg adopt <name> <路径>` 收编进 `$COMMON/config/services/`（版本化 + `devenv cfg apply` 落位 + doctor 巡检漂移）；Runtime 类工具另走 runtimes.tsv 登记 + `devenv runtime wire`

## 验收

`devenv report` 版本表出现所装工具；缓存路径探测指向 Common/DevEnv（非默认 `~/.cache`）；共享盘 JS 项目可正常 `npm install`（依赖实体在本机盘 ①）。
