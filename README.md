# BestDevEnv —— 虚拟机统一开发环境构建工程

> 一句话：把《虚拟机统一开发环境设计方案》（devspace-design.md **v10.3**）从纸面变成
> **一条命令 + 交互确认** 的可执行构建工程——四台虚拟机（ubuntu24 / ubuntu26 / arch / win11）
> 从"装完系统"到"`devenv doctor` 全绿"，中间没有任何手工步骤。

| 项 | 值 |
|---|---|
| 版本 | v0.15（**部署层一致性**：doctor +3 巡检——分发器就绪/正本 gen 指纹/机器登记；zcode skill 双根去重走 ~/.agents 枢纽；node 镜像覆盖口 `BDE_NODE_DIST_MIRROR`；doctor 19 项） |
| 日期 | 2026-11-08 |
| 上游宪法 | devspace-design.md **v10.3**（位于 `/Share/Common/docs/dev-env/design.md`）；MCP/会话/Skill 统一为 §10.9 延伸、配置治理落实 §19.3，提请宪法增补 |
| 适用范围 | **跨系统：Linux（Ubuntu/Arch）/ macOS / Windows 为目标**；Common/Local 为逻辑目录（本机盘/宿主机盘/云盘皆可为后端）。**当前生产实装 = Ubuntu 系**（ubuntu.sh）；Arch/Windows/macOS 为占位适配器（P2/P3 里程碑，实机验证后才算数） |
| 远端 | `git@github.com:zhaoxuan-inside/BestDevEnv.git` |

---

## 1. 项目定位

本仓库有**三重身份**：

1. **安装器**——`init.sh` / `init.ps1` 交互式引导，从空白 VM 构建完整开发环境；
2. **配置源**——`config/` 即 chezmoi 源（按主题平铺），安装时初始化 `/Share/Common/config`；
3. **生成器**——生成 `AGENTS.md`（AI 协作统一指令）与**环境描述文档**（机器现状报告）。

**边界**：只管环境，不碰业务仓库内容（宪法原则 7——环境与业务代码分离）。
本仓库自身是业务代码，位于 `/home/hardstone/Share/Common/CodeSpace/BestDevEnv`
（CodeSpace 为既有代码区；P4 归位时可平移至 `/Share/Common/code/`，迁移后以 git 远端为准）。

## 2. 设计哲学（需求 1：环境的搭建设计哲学）

哲学不是口号，每一条都直接约束脚本的写法：

| # | 哲学 | 工程约束 |
|---|---|---|
| 1 | **路径即契约** | 锚点常量（`DEV`/`SHARE`/`COMMON`/`LOCAL`）唯一出处是 `lib/paths.sh`；任何脚本禁止硬编码散路径 |
| 2 | **可再生性分离** | 能再生的（缓存/产物/安装包）→ 脚本内重定向到 `/Share`；不可再生的（DB/工作区）→ 留本机 |
| 3 | **环境即代码** | 零手工步骤；所有写操作走幂等原语 `ensure_*`，任何模块可重复执行不出错 |
| 4 | **单一事实源** | 配置源 = 本仓库 `config/` + `/Share/Common/config` 镜像；机器数据唯一出处 = `hosts.toml` |
| 5 | **外置优先** | 目录模块默认把大件（缓存/模型/XDG 用户目录）落在 `/Share`，VM 盘只留工具链与活状态 |
| 6 | **数据与视图分离** | 目录只存数据：config 主题平铺 + `.chezmoiignore` 规则；分组/标签由 `repos.toml` 与工具承载 |
| 7 | **环境与业务代码分离** | `DevEnv` 100% 环境；业务代码住 `/Share/Common/code`（热区 `~/Code`）；互不掺杂 |
| 8 | **用户空间优先** | 可再生内容一律落 ①②③ 用户空间；系统目录只留 OS 必需。验收：重装系统后凭 ①②③ + config 仓库完整重建 |
| 9 | **锚点是逻辑目录** | `Common`/`Local` 不绑定介质——本机盘/宿主机盘/云盘皆可为后端；路径恒定，差异收敛在挂载适配器 |
| 10 | **服务三分离** | 安装体（①可再生）／配置（③ config 仓库版本化）／数据（②本机或③共享）——恢复=重装+应用配置+回灌数据 |
| 11 | **构建十分离** | IDE 工具/IDE 配置/IDE 数据/代码/代码输出/代码日志/打包工具/打包配置/缓存包/打包结果 十类各归其位，任一目录可独立清空（宪法 §19.4） |

另有一条**物理边界**（来自实测，写进每个模块的守卫）：

> HGFS 共享盘：无 symlink、不区分大小写、权限恒 777 root——依赖实体类内容（node_modules/venv）
> 一律落 VM 盘（`DevEnv/deps`），bind mount 接回共享盘项目；涉及 symlink 的写操作禁止指向共享盘。
> 且**单文件名/深层路径长度超 HGFS 上限**（实测 gradle/flutter 构建缓存放不进）——此类缓存留本机盘或删重建；挂载选项只用 `allow_other`（vmhgfs-fuse 拒绝 defaults）。

## 3. 总体架构：执行模型与工程结构

```text
执行模型：
  init（交互确认）→ M0 lib → M1 os → M2 dirs → M3 lang(按所选) → M4 agent(按所选) → M5 doc → doctor 全绿
  （任何一步可单独重跑——幂等）
```

### 工程结构（仓库目录树）

```text
BestDevEnv/
├── README.md                        本文件：项目描述（工程宪法）
├── LICENSE
├── init.sh                          Linux 总入口（交互式，Ubuntu/Arch 通用）
├── init.ps1                         Windows 总入口（交互式）
├── lib/                             M0 公共库
│   ├── paths.sh                     锚点常量唯一出处：DEV/SHARE/COMMON/LOCAL（作用域派生自 storage.sh）
│   ├── storage.sh                   L0 存储抽象层：作用域→后端解析（passthrough/hgfs/local；档案 storage.toml）
│   ├── common.sh                    交互菜单（whiptail 优先/read 兜底）、颜色、日志、确认
│   ├── ensure.sh                    幂等原语：ensure_pkg / ensure_dir / ensure_line / ensure_fstab / ensure_symlink
│   └── probe.sh                     环境探针（doctor / report / AGENTS.md 三方共用的唯一数据源）
├── hosts.toml                       机器数据表（与 /Share/Common/config/hosts.toml 同源同步）
├── modules/
│   ├── os/                          M1 系统基线与优化（需求 2）
│   │   ├── ubuntu.sh
│   │   ├── arch.sh
│   │   └── windows.ps1
│   ├── dirs/                        M2 目录架构创建（需求 3，交互选择）
│   │   ├── linux.sh
│   │   └── windows.ps1
│   ├── cfg/                         M1.6 统一配置治理（宪法 §19.3；devenv cfg / devenv svc）
│   │   ├── cfg.sh                   治理器：list/apply/diff/adopt（正本→应用层，漂移巡检）
│   │   └── cfg-map.tsv              配置登记表（name|类|正本|应用层|机制|root|备注）
│   ├── lang/                        M3 语言开发环境（需求 4）
│   │   ├── node.sh  python.sh  rust.sh  go.sh  flutter.sh  java.sh  ai.sh
│   │   └── windows/
│   │       ├── node.ps1  python.ps1  rust.ps1 …
│   ├── agent/                       M4 vibecoding Runtime 统一管理（需求 5）
│   │   ├── tools.sh                 幂等安装/登记（npm/curl/snap；GUI 类登记）
│   │   ├── agents-md.sh             正本生成器（AGENTS.md + SKILL 家族再生）
│   │   ├── runtime.sh               Runtime 接线器（记忆/Skill/MCP/会话；devenv runtime + vibe 入口）
│   │   ├── runtimes.tsv             Runtime 注册表（name|binary|渠道|memory|skills|mcp|sessions|note）
│   │   └── mcp.seed.json            MCP 正本种子（播种到 ~/.config/devspace/agents/mcp.json）
│   ├── ide/                         M6 IDE 统一
│   │   └── ide.sh                   VS Code 离线安装/语言扩展档案/JetBrains 需求推导/settings 收编
│   ├── tidy.sh                      可再生缓存清理（devenv tidy，SAFE 清单）
│   ├── home-map.sh                  隐藏目录注册表视图（devenv map，看门人）
│   ├── orch/                        编排进度日志（devenv orch：主 Skill 长任务落盘续做）
│   └── doc/                         M5 环境描述文档（需求 6）
│       └── report.sh
├── config/                          chezmoi 源（主题平铺，宪法 §9 结构）
│   ├── .chezmoi.toml.tmpl  .chezmoiignore  hosts.toml
│   ├── dot_gitconfig  env.sh  dot_zshrc  dot_npmrc
│   ├── dot_config/{starship,fcitx5,konsole,user-dirs.dirs}
│   └── apt/  pacman/  windows/
├── templates/
│   ├── AGENTS.md.tmpl               统一 Agent 指令模板（常驻摘要）
│   └── skills/                      Skill 家族模板（主调度 + 8 子域，agents-md.sh 再生）
│       ├── bestdevenv/              主 Skill：探环境 → 拆需求 → 调度 → 验收
│       ├── bestdevenv-init/         新机初始化全管道（init.sh）
│       ├── bestdevenv-dirs/         三档目录与挂载（M2）
│       ├── bestdevenv-optimize/     系统基线与参数优化（M1）
│       ├── bestdevenv-config/       配置规范与漂移治理（M1.5 + config 仓库）
│       ├── bestdevenv-dev/          语言栈/agent 工具/IDE（M3+M4+M6）
│       ├── bestdevenv-runtime/      Runtime 统一管理：记忆/Skill/MCP/会话（M4 扩展）
│       ├── bestdevenv-workflow/     共享盘仓库日常（工作流四件套）
│       └── bestdevenv-health/       自检/报告/清理/看门
└── verify/
    └── doctor.sh                    devenv doctor 本体（安装时分发到 ~/DevEnv/bin）
```

**`config/` 与 `/Share/Common/config` 的关系（防双源漂移）**：`config/` 只是**种子**——
仅当 `/Share/Common/config` 不存在时用其初始化（git init + 首次 apply）；一旦存在，以
`/Share/Common/config` 为准（本机改动 → push GitHub → 其他机 pull），种子不再参与。

## 4. 模块总览（需求 2–6 的映射）

| 需求 | 模块 | 产物 | 验收 |
|---|---|---|---|
| 2. OS 配置优化方案+脚本 | M1 `modules/os/` | 系统基线就绪（源/locale/内核参数/docker） | probe 各项 ✓ |
| 3. 目录架构方案+创建脚本（交互） | M2 `modules/dirs/` | `/Share` 锚点+骨架+XDG 重定向+fstab | doctor 挂载检查 ✓ |
| 4. 语言开发环境方案+脚本 | M3 `modules/lang/` | 各语言工具链+镜像+重定向生效 | 各语言 `--version` 且缓存路径 ✓ |
| 5. vibecoding 工具 + AGENTS.md 统一构建 | M4 `modules/agent/` | 工具装好 + `~/AGENTS.md`（及 CLAUDE.md/GEMINI.md 别名） | 各工具 `--version`；AGENTS.md 含环境地图 |
| 6. 环境描述文档构建脚本 | M5 `modules/doc/` | `devenv report` markdown → `/Share/Common/docs/env/` | 报告生成且 doctor 无 error |
| 7. IDE 统一（VS Code/Antigravity/JetBrains） | M6 `modules/ide/` | 离线 deb 安装 + 语言扩展档案（base+7 语言）+ settings 收编 | doctor「IDE 就绪」✓ |
| 8. 隐藏目录治理 | `modules/home-map.sh` | 注册表（35 项）+ `devenv map` 看门人 + `devenv tidy` SAFE 清单 | `devenv map` 全登记 ✓ |

### M1 系统基线与优化（需求 2）

- `ubuntu.sh`：apt 国内源 → locale `zh_CN.UTF-8` / 时区 `Asia/Shanghai` → 基础包
  （openssh-server / build-essential / curl / git / whiptail）→ **内核参数优化**
  （`fs.inotify.max_user_watches` 调高——前端 watch 必需）→ docker（daemon.json 国内 mirror + 日志轮转）→
  GNOME 微调（默认终端 Konsole、Ctrl+Alt+T 绑定、dock 固定）→ fcitx5 全家桶安装。
- `arch.sh`：镜像（mirrorlist/reflector）→ base-devel → pacman 清单 → yay → 同上内核参数与 docker。
- `windows.ps1`：winget 清单 → 开发者模式 → 长路径启用 → PowerShell 7 → 执行策略 → mklink 前置检查。

### M2 目录架构创建（需求 3，交互选择）

- `linux.sh`：清理死挂载 → 建 `/Share` 锚点 → fstab 持久挂载（`.host:/Common`、`.host:/Local`）→
  旧挂载 `/home/hardstone/Share` 切换 → Common 八区骨架（code/config/install/cache/data/exchange/docs/templates/archive）
  → Local 结构（build/cache/data/docs + XDG 八目录）→ `DevEnv` 补齐（deps/code/data/bin/docs/tmp）→
  XDG 重定向（user-dirs.dirs）+ home 兼容 symlink → 归位提示（现有内容对号入座的检查清单）。
- `windows.ps1`：`C:\Dev` 骨架 → mklink 指向 `\\vmware-host\Shared Folders\{Local,Common}` → S:/L: 兼容盘符。
- **交互选择点**：锚点路径确认（默认 `/Share`）｜是否迁移旧挂载｜XDG 重定向开关（默认开）｜
  是否生成全骨架（默认全量）。

### M3 语言开发环境（需求 4）

每语言一个脚本，内部分四步：**安装**（版本管理器）→ **镜像**（国内源写入）→ **重定向**
（缓存/依赖路径写入 env / .npmrc）→ **校验**（版本 + 缓存路径探测）：

| 脚本 | 安装 | 镜像 | 重定向 |
|---|---|---|---|
| `node.sh` | mise（nvm 兼容期收编） | npmmirror | store/cache → `/Share/Common/cache/linux`；实体 → `DevEnv/deps` |
| `python.sh` | uv | 阿里 pypi | venv → `DevEnv/virtualenvs`；cache → `Common/cache/linux` |
| `rust.sh` | rustup | rsproxy.cn | `CARGO_HOME=$DEV/cargo`；target → `$LOCAL/build`（hardlink 基准校验） |
| `go.sh` | 官方 tarball | goproxy.cn | `GOPATH=$DEV/go` |
| `flutter.sh` | 沿用 `DevEnv/flutter` | flutter-io.cn | `PUB_CACHE=$DEV/pub-cache`；gradle → `$LOCAL/cache/gradle` |
| `java.sh` | mise temurin | aliyun maven | `GRADLE_USER_HOME=$LOCAL/cache/gradle` |
| `ai.sh` | hf/modelscope CLI | hf-mirror | 权重 → `/Share/Common/data/models`（`HF_HOME`） |

脚本自动适配 apt/pacman（检测包管理器），交互选中的语言才执行；Windows 侧对应 `windows/*.ps1`。

### M1.6 统一配置治理（宪法 §19.3 服务三分离落地）

装任何服务/软件/工具，其配置文件三问统一回答（`modules/cfg/cfg.sh`，入口 `devenv cfg` / `devenv svc`）：

| 问 | 答案 |
|---|---|
| 正本在哪 | `modules/cfg/cfg-map.tsv` 登记；内容住 `$COMMON/config/{services,apt,dot_config}/`（git 版本化） |
| 怎么应用 | `devenv cfg apply`——copy（备份+整文件落位）/ append（fstab 片段逐行）/ chezmoi（归事实源） |
| 漂移怎么发现 | `devenv cfg diff` ＋ doctor「系统/服务配置无漂移」「config 仓库干净」巡检 |

- **收编**：新装软件 `devenv cfg adopt <name> <路径>` → 拷为正本 + 登记一行；改配置 = 改正本 → commit → apply
- **已收编**：sysctl 99-devspace、docker daemon.json（补 §10.6 日志轮转）、fstab hgfs 片段、apt ubuntu.sources、user-dirs.dirs（归 chezmoi，M2 不再直写）
- 服务生命周期（enable/start）归安装体——配置与安装体分离（宪法 §19.3）

### M4 vibecoding Runtime 统一管理（需求 5）

**工具清单**（`tools.sh` 幂等安装/登记；`runtimes.tsv` 全量注册）：

```text
claude-code  codex  gemini-cli  opencode  zcode  trae/trae-cn  antigravity  qoder  copilot  arkcli
```

**Runtime 统一管理层**（`runtime.sh`，宪法 §10.9 延伸）：操作系统可能装很多 vibecoding 工具，
它们只是**可替换的 Runtime**——记忆、Skill、MCP、会话四域由本工程统一承载，切换工具不再丢失环境：

| 域 | 正本（应用层） | 工具落点 | 命令 |
|---|---|---|---|
| 记忆 | `~/.config/devspace/agents/AGENTS.md` | 各工具约定路径 symlink（claude/codex/gemini/opencode/zcode/arkcli） | `devenv runtime wire` |
| Skill | `~/.config/devspace/agents/skill/<name>/` | `~/.claude/skills`、`~/.agents/skills`（zcode/arkcli 共用枢纽——ZCode 原生扫描该目录，~/.zcode/skills 双根曾致同名 skill 重复注册，2026-11-08 实证）逐项 symlink | `devenv runtime wire` |
| MCP | `~/.config/devspace/agents/mcp.json`（播种后归用户） | claude `~/.claude.json`、codex TOML 托管块、gemini/opencode/copilot JSON 合并、zcode/arkcli 走 `~/.agents/mcp.json` 兜底 | `devenv runtime mcp sync` |
| 会话 | 工具私有（注册表登记） | 只调查不迁移；跨工具续做走 `devenv orch` | `devenv runtime sessions` |

- **注册表**：`modules/agent/runtimes.tsv` 是唯一事实源（新 runtime = 加一行）；接线器只按注册表干活
- **统一入口**：`vibe <tool> [args]`（`$DEV/bin/vibe`）——任何 runtime 都拿到同一份 env.sh 契约
- **绝不覆盖工具真实配置**：已有真实文件 → 备份 + pending 人工合并；工具自有状态只受控合并
- doctor「Runtime 统一接线」项验收三正本 + 枢纽兜底；「正本 gen 指纹」项验收正本与模板同代

**AGENTS.md 正本生成**（`agents-md.sh`，只生成不接线）：单一模板 `templates/AGENTS.md.tmpl`
+ probe 快照 → `~/.config/devspace/agents/AGENTS.md`（环境地图 + 放置规则 + Runtime 统一契约 +
常用命令 + 工具链现状表）。业务仓库内的 AGENTS.md 由各项目自写（仓库层），本工程只负责**全局层**统一。

**SKILL 家族**（同一生成器 `agents-md.sh`）：`templates/skills/<name>/SKILL.md.tmpl`——
`bestdevenv` 主 Skill 是路由器（探环境 → 拆需求 → 按 deps 顺序调度 → doctor 验收），
8 个子 Skill 各管一件事（init / dirs / optimize / config / dev / runtime / workflow / health）。
正本落 `~/.config/devspace/agents/skill/<name>/`，工具侧接线由 `runtime.sh` 按注册表执行。
改模板后重跑生成器即再生，勿手改正本。
主 Skill 对多步长任务用 `devenv orch`（`modules/orch/orch.sh`）把编排进度落盘
`$DEV/docs/progress/orch-*.md`（机器/OS/doctor 快照 + 计划清单 + 续做指针），跨会话可续做。

### M5 环境描述文档构建（需求 6）

**数据/视图三层**（宪法 §19.5）：`lib/probe.sh` 是唯一采集器（L1），产出 schema 化 JSON 快照
（`$DEV/docs/state/probe.json`，schema `bde.probe/1`）；doctor / report / AGENTS+SKILL / map 全部是
L3 纯视图，只消费快照与登记数据（L2），绝不自行采集。视图可随时删除重建，数据永远在家。

```text
probe.sh ──→ $DEV/docs/state/probe.json ──→ doctor.sh（校验视图，--json 出 bde.doctor/1）
                                        ──→ report.sh（报告视图 → Common/docs/env/）
                                        ──→ agents-md.sh（指令视图 → AGENTS/SKILL 家族）
```

报告内容：OS/内核 → 工具链版本表（node/python/rust/go/flutter/java/docker 及各 agent 工具）→
挂载健康（Common 可写、fstab 就位）→ 重定向生效（缓存/依赖路径探测）→ 配置漂移
（config HEAD vs 应用层）→ 占用标记陈旧项 → 根盘水位。

## 5. 交互设计（需求 3 的"支持交互选择"）

`init` 的交互问题清单（均有默认值，一路回车 = 全默认）：

| # | 问题 | 默认值 | 影响 |
|---|---|---|---|
| 1 | OS 确认（自动检测 + 人工确认） | 检测结果 | 选择 M1/M2/M3/M4 的脚本变体 |
| 2 | 机器名 | 当前 hostname | 写入 hosts.toml；.claimed-by/提示符引用 |
| 3 | 目录锚点 | `/Share`（Windows: `C:\Dev` + mklink） | M2 全部路径 |
| 4 | 是否迁移旧挂载 `/home/hardstone/Share` | 是 | fstab 写法与历史路径兼容 symlink |
| 5 | XDG 用户目录重定向 | 开 | M2 的 user-dirs + 兼容 symlink |
| 6 | 语言栈（多选） | node python | M3 执行集合 |
| 7 | vibecoding 工具（多选） | claude-code codex zcode arkcli | M4 执行集合 |
| 8 | 镜像源区域 | cn | M1/M3 的镜像清单 |

实现：Linux 优先 `whiptail`（GNOME 自带），无则 `read` 菜单兜底；Windows 用 `Read-Host` +
可选 `Out-GridView`。**最后一步输出执行摘要，确认后才动手**。

## 6. 执行流程全景（新机 bootstrap）

```text
装 OS（建用户 hardstone、设唯一 hostname）→ 宿主机开 VMware 共享（Local、Common）
  → clone 本仓库 → ./init.sh（或 init.ps1）
  → 交互确认（§5 八项）→ M1 系统基线 → M2 目录架构 → M3 语言栈 → M4 工具+AGENTS.md → M5 报告
  → devenv doctor 全绿 → 完成（此后日常演进走 /Share/Common/config 的 git）
```

## 6.1 执行进度记录（可续建）

构建过程**逐阶段落盘**，中断后可继续执行：

- **状态文件**：`~/DevEnv/docs/progress/<机器名>.state`（本机；行格式 `阶段|状态|时间|计数`，同阶段取最近一条）
- **运行日志**：`~/DevEnv/docs/progress/init-<时间戳>.log`（全量输出留痕，`--no-log` 关闭）
- **命令**：
  - `./init.sh --status` 查看各阶段进度
  - `./init.sh --resume` **续建**：跳过 done 阶段，只执行未完成/失败阶段
  - `./init.sh --rerun` 强制全量重跑（默认也是全量幂等）
  - `./init.sh --reset` 清空进度
- **阶段清单**：`M2` → `M1` → `M1.5:config` → `M1.6:cfg` → `M3:<语言>`（逐语言）→ `M4:tools` → `M4:agents-md` → `M4:runtime` → `M6:ide`（`--no-jetbrains` 可跳过）→ `M5`
- 环境报告（M5）自动携带「构建进度」节；失败阶段在 `--resume` 时自动重跑

## 7. 与上游设计文档的关系

`devspace-design.md` 是**宪法**（结构与规则），本工程是**施工队**（落实与自动化）。
实现与宪法冲突时：以宪法为准，并提请修订宪法后再改实现；本 README 的每次实质变更
注明所依宪法版本。当前依赖：**v10.3**（锚点 `/Share` 逻辑化、L0 存储抽象 `lib/storage.sh`、主题平铺 config、`hosts.toml` 数据表、用户空间优先、服务三分离、构建十分离）。

## 8. 验收标准

1. **同构**：同一项目在四台 VM `clone → build → run` 全绿；
2. **一条命令**：新 VM 从空白到 doctor 全绿 = 装 OS + `init` 一次；
3. **幂等**：任何模块重复执行无副作用、无重复安装；
4. **可描述**：`devenv report` 随时生成当前环境现状，doctor 无 error。

## 9. 里程碑与当前状态

- [x] **0. 项目描述**（本 README）
- [x] 1. `lib/`：paths / common / ensure / probe
- [x] 2. M2 `dirs/linux.sh`（本机验证：/Share 挂载 + fstab + 骨架 43 目录 + XDG 重定向）
- [x] 3. M1 `os/ubuntu.sh` + `apply-config.sh`（本机验证：chezmoi apply、inotify、konsole、zsh、starship）
- [x] 4. M3 语言栈七件（node/python/rust/go/flutter/java/ai；本机验证 node/python/rust/go/flutter/ai）
- [x] 5. M4 工具安装 + `agents-md.sh`（本机验证：~/AGENTS.md 生成）
- [x] 10. **Runtime 统一管理层** `agent/runtime.sh` + `runtimes.tsv` + `mcp.seed.json`（记忆/Skill/MCP/会话四域正本+接线；doctor「Runtime 统一接线」项）
- [x] 11. **统一配置治理** `cfg/cfg.sh` + `cfg-map.tsv`（正本落位/漂移巡检/收编；宪法 §19.3 服务三分离；doctor 第 15/16 项；存量 5 项收编）
- [x] 6. M5 `report.sh` + `verify/doctor.sh`（本机验证：doctor 19 项全绿、报告落 Common/docs/env/）
- [x] 8. M6 `ide/ide.sh`（语言档案 + JetBrains 需求推导：本机实装 PyCharm Pro 2026.3）
- [x] 9. 工作流四件套 `workflow/{code-open,code-close,code-nm,code-out}.sh` + Maven settings.xml（端到端验证：产物物理分离）
- [ ] 7. P2/P3 推广：arch / win11（arch.sh 与 windows.ps1 为占位）
