---
name: bestdevenv
version: 0.2.3
description: BestDevEnv 开发环境总调度——用户提出环境类需求但不属于单一子域、或需要先探明本机现状再编排多步工作时使用：探环境（devenv doctor）→拆需求→按依赖顺序调度 bestdevenv-* 子 Skill→devenv doctor 验收。单一明确子域（如仅清缓存）直接用对应子 Skill，不经本 Skill。
---

# BestDevEnv 环境总调度（主 Skill）

角色：**路由器 + 验收者**。不亲自执行子域工作（探针除外）——每件事交给一个 bestdevenv-* 子 Skill 完成后再验收。

## 环境地图

本机：**hardstone**（Ubuntu 24.04.5 LTS）

| 档 | 作用域 | 路径 |
|---|---|---|
| ① DevEnv | user 用户级（本机本用户） | `/home/hardstone/DevEnv` |
| ② Local | host 主机级（同机多用户） | `/Share/Local` |
| ③ Common | shared 跨主机级（多机多用户） | `/Share/Common` |

> 公货 `/Share/Common`，私货 `/Share/Local`，工具链和活状态 `/home/hardstone/DevEnv`；
> 实体住 `/home/hardstone/DevEnv/apps/<分类>/`（vibecoding 工具 → `apps/agent/`；家目录=入口层：链接 + 原生重定向，收敛路线见宪法 §20.5），bind mount 接回去；配置永远改仓库（`$COMMON/config`）；备份永远靠 push。
> 物理红线（能力探测 2026-11-14 · 后端 hgfs）：无 symlink · 无 hardlink · 权限恒 777 · 文件名上限 255B——依赖实体与私钥绝不上去；文件/代码命名小写 kebab-case；①②③ 自建目录走 naming.toml 规范（NN_ 前缀/首字母大写/4-6 字符/禁中文/同级等长优先——devenv namecheck 校验）

### 分离法则（宪法 v10.3，调度时必须遵守）

1. **用户空间优先**：可再生内容一律落 ①②③，系统目录只留 OS 必需（重装后凭 ①②③ + config 仓库重建）
2. **存储介质与结构解耦**：只说作用域（shared 跨主机/host 主机/user 用户），介质差异收敛在 L0 存储抽象层（`lib/storage.sh` + `config/data/storage.toml` 档案制，跨系统 macOS/Linux/Windows 同一套原则）
3. **服务三分离**：安装体→①（可再生）｜配置→③ config/services（版本化）｜数据→② Local/data（共享→③）；恢复=重装+应用配置+回灌数据
4. **构建十分离**：IDE 工具①｜IDE 配置③｜IDE 运行数据②｜代码③｜代码输出②｜代码日志②｜打包工具①｜打包配置③｜缓存包③｜打包结果③exchange——清理只落 ② 与缓存/结果目录

## 第一步永远是探环境（只读，不改任何东西）

```bash
source "$HOME/.config/devspace/env.sh"     # DEV/SHARE/COMMON/LOCAL 锚点变量
BDE="$COMMON/code/BestDevEnv"
bash "$BDE/lib/probe.sh" --json            # L1 环境事实快照（schema bde.probe/2：含存储后端/共享盘能力，机器可读）
bash "$BDE/verify/doctor.sh"               # L3 校验视图（✓/✗ 全项；--json 出 bde.doctor/1）
devenv cfg list / devenv cfg diff                # 配置治理视图（cfg-map 清单 + 漂移检测）
devenv app --all                              # 应用视图（安装/配置/数据按应用聚合，§20.3）
. /etc/os-release; echo "$ID"              # OS 变体（ubuntu 实装；arch/windows/mac 为适配器待建项）
```

## 需求 → 子 Skill 路由表

| 用户意图（示例问句） | 调度 |
|---|---|
| 新机器/装完系统从零构建 | `bestdevenv-init` |
| 挂载没了、fstab、目录骨架、XDG、迁移 | `bestdevenv-dirs` |
| 优化系统参数/内核参数/docker/终端/镜像源 | `bestdevenv-optimize` |
| 改配置、chezmoi、配置漂移、config 仓库 | `bestdevenv-config` |
| 装语言栈/agent 工具/IDE | `bestdevenv-dev` |
| 新增/接线 runtime、统一记忆/MCP/Skill/会话、切换工具不适 | `bestdevenv-runtime` |
| code-open/close/nm/out、依赖产物拆分、文件放哪 | `bestdevenv-workflow` |
| 自检/报告/清缓存/看门/磁盘紧张 | `bestdevenv-health` |
| 目录命名违规/要内容索引/软件未建档收编/目录未登记 | 直查类命令：`devenv namecheck [--migrate]`（存量改名逐项授权）/ `devenv index`（①②③ 内容索引）/ `devenv app --audit|--migrate`（建档收编逐项授权）|
| 症状含糊（"环境好像坏了"） | 先 `bestdevenv-health` 诊断，按失败项再路由 |

## 编排规则

1. **计划先行（硬协议，先于一切执行）**：动系统之前先向用户展示「执行前确认卡」（格式见下节）——**用户明确同意后才动手**；未展示计划就执行 = 违规。改系统类任务（改名/迁移/清理/安装）全部适用，只读查询（doctor/index/list）可免
2. **确认语境**：确认卡「待确认」段必含两项语境问题——**开发语言**（实际在写什么语言/框架，决定装什么）与**特殊非通用安装**（公司内部工具、私有源、定制版本——用户不提就不装）；**桌面个性化默认集**（终端 konsole/输入法 fcitx5+雾凇/starship/字体）同属个人选择，随卡确认要不要；dev 调度的语言栈/工具清单确认并入本卡，确认结果经 `--langs`/`--tools` 显式传入。**写回制**：卡上用户确认的语境/决定/偏好，默认当场写回 `③ config/agents/user-context.toml`（正本 → gen 渲染进 AGENTS.md → 全体 Agent 共享；cfg snapshot 同步）
3. **依赖顺序**：dirs → optimize → config → dev（装语言前先有目录与基线）；health 可随时插队诊断
4. **幂等**：所有子 Skill 底层脚本可重复执行；中断的 init 用 `--resume` 续建
5. **多子域任务**：先建编排日志（见下节），逐个调度并逐步记账；不要并行改系统
6. **组合示例**：「部署开发环境」＝ 确认卡（语言栈/特殊安装）→ config（确认基线）→ dev；「这台机器不对劲」＝ health 诊断 → 按失败项再路由

## 执行前确认卡（人类优先：简洁优雅，拒绝日志式倾倒）

**质量标准（三段分类强制，缺一不可）**：
- **要做什么**：逐项明细——≥3 项的清单必须表格化（项/动作/影响文件/量级），按批次拆节，禁止长行连排
- **做成后是什么样子**：可验收的终态（树/数字/行为变化）+ 验收清单（命令/预期输出，逐项可执行）
- **有哪些风险**：表格式（风险/触发条件/影响/缓解/回退），不与计划混排
- **选项先解释后选择**：凡待确认含选项，每个选项先说清"做了什么/不做会怎样/影响面/代价"，解释完才出题，禁止只报名词
- **卡先于题（强制顺序）**：先完整展示卡，本轮不附选择框，用户回复中直接说选项或干预即视为已读确认；未展示卡不得出题、不得开工
- 简洁 ≠ 省略：简洁靠表格与分类，不靠砍掉必要明细；禁止原始输出倾倒

```markdown
**做什么**：一句话目标
**计划**：① 步骤（量级） ② 步骤 ③ 步骤
**完成后**：你会得到 …；系统变化 …
**风险**：⚠ …（影响 …）→ 回退：…
**待确认**：开发语言 …？特殊安装（内部工具/私有源）…？范围/选项 …？
**干预**：计划可编辑——改某步/删某步/换序/调范围，直接说"改 ①：…"即可
```

**用户干预（计划可编辑——卡是草稿，不是单向门）**：
1. **干预入口**：对卡上任何内容直接提修改——"改 ②：换成 X" / "去掉 ③" / "先做 ② 再 ①" / "范围只做 …" / "参数用 …"
2. **修订流程**：收到干预 → `orch edit/drop` 留痕 → 出**修订卡**（v2，标注 Δ 相对上一版的变化）→ 用户确认 → 执行；小改（单步描述）口头确认即可，大改（步骤增删/目标变化）必须重新出卡
3. **执行中叫停**：随时打断——orch 账本已保进度，续做按修订后的新卡重新确认
4. **留痕**：所有修订经 orch 账本记录（旧值→新值），跨会话可续

示例（目录改名）：

> **做什么**：② Local 六个受管目录按批准树改名（build→20_Build 等）
> **计划**：① 逐项改名+登记回写（秒级/项） ② 引用同步 ~14 处（gradle/maven 正本重落位） ③ doctor 复验
> **完成后**：② 目录树对齐规范、namecheck 转绿；构建缓存路径一步到位
> **风险**：⚠ gradle/maven 缓存路径漂移（首次构建重拉依赖）→ 回退：git+dir-map 双回退，5 分钟可逆
> **待确认**（选项先解释后选）：
> - **三批连做**：①③ 一次改到位，全程几十分钟；B2 动 chezmoi/seed 通道风险最高，但每批有 doctor 门禁、批间可停——适合一次收尾且能盯全程
> - **只做 B1**：仅 ③ 顶层 8+深层 11 项，引用面最轻（~10 文件）；B2/B3 下次——适合想先看 ③ 效果再决定
> - **B1+B2**：③ 全部（含 config→10_Config，24 处引用+配置应用链路），① 另次——适合先收共享盘侧
> - **暂缓**：机制已就绪，不执行——适合现在没空盯
> **干预**：如"去掉 ② 正本重落位，先只改名"或"③ config 一起改"——直接说即可

## 编排进度（长任务跨会话可续建）

编排可能耗时很长、甚至跨越多个会话——**每一步进度必须落盘**（`devenv orch` → `~/DevEnv/docs/progress/orch-*.md`），任何时刻中断都能无损续做：

```bash
J="$(devenv orch new "<任务目标>")"            # 开工：创建编排日志（自动记录探环境快照）
devenv orch add bestdevenv-dirs "修复挂载"      # 逐条登记计划（按依赖顺序）
devenv orch next "1. bestdevenv-dirs（开始）"   # 每步调度前写续做指针
devenv orch done 1 "挂载转绿；doctor 复查 ✓"    # 每步完成/失败立即记账（先落盘再继续）
devenv orch status                              # 查进度与续做指引
```

协议（严格执行）：
1. **开工**：`orch new` → `orch add` 逐条登记；≥2 步的任务必须建日志，单步小任务可免
2. **每步**：调度前 `orch next` 写指针 → 调度子 Skill → `orch done/fail <n> "<结果>｜doctor 复查结论"`
3. **干预**：用户对计划提修改 → `orch edit <n> <新职责>` / `orch drop <n>` 留痕 → 修订卡（标注 Δ）再确认；执行中叫停随时有效，续做按新卡走
4. **改判/回退**：步骤做错或方向变更 → `orch revert <n> "<原因>"` 改判回待做（自动打印回退素材指引：① backup 时间戳备份 / config 正本 git 历史 / seed restore）；失败步骤修复后 `orch done <n>` 改判完成
5. **续做**（用户说"继续/接着上次的来"）：`orch status` 取最新日志 → **先重跑探环境**（前置条件可能已变）→ 从第一个未完成步骤继续，已完成的靠幂等跳过、绝不重做
6. **收尾**：全部 done → doctor 终验 → 向用户报告（附 journal 路径）

## 验收与收尾

- 完成后必跑 `devenv doctor` 复查，向用户报告 ✓/✗ 清单
- 动过 `$COMMON/config` 就提醒 commit + push；动过系统参数提醒需重启生效项
- 需要留痕时 `devenv report`（→ `$COMMON/docs/env/`）

## 子 Skill 维护（改模板 → 重新生成）

模板：`$BDE/templates/skills/<name>/SKILL.md.tmpl`；正本由 `devenv gen`（即 `agents-md.sh`）
统一再生，工具接线由 `bash "$BDE/modules/agent/runtime.sh"` 按注册表（runtimes.tsv）执行。
勿手改正本，勿手改 `~/.claude/skills`、`~/.agents/skills`（zcode/arkcli 共用枢纽）下的链接。
doctor「正本与模板同代（gen 指纹）」项红 = 改了模板未再生 → 跑 `devenv gen`。
