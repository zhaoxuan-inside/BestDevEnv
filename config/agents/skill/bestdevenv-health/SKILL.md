---
name: bestdevenv-health
version: 0.1.0
description: BestDevEnv 环境健康——devenv doctor 环境自检、devenv report 环境报告、devenv tidy 清理可再生缓存、devenv map 隐藏目录看门、devenv inventory 系统环境索引（已装软件路径/渠道合规 + 家目录登记制判定 + 受管服务实态）、违规处置流（inventory --migrate）时使用。触发：自检、环境报告、清缓存、磁盘满、未登记目录、装了什么、装哪了、路径合规、软件索引。
---

# 环境健康（doctor / report / tidy / map）

单一职责：诊断、留痕、清理。**修复动作路由回对应子 Skill**（挂载→bestdevenv-dirs；配置→bestdevenv-config；系统参数→bestdevenv-optimize），本 Skill 不跨界修。

**反触发**：诊断出问题后**不跨界修**——挂载→`dirs`、配置→`config`、系统参数→`optimize`、语言/工具→`dev`。本 Skill 只诊断、留痕、清缓存。

## 命令清单（速览 → 逐项 → 处置）

```bash
source "$HOME/.config/devspace/env.sh"
devenv brief       # 会话速览（一次采集：锚点/后端/能力/根盘/待处置/编排指针）——先看这条
devenv doctor      # 逐项自检：存储（后端/持久化/档案对账）/共享盘能力/分发器/正本 gen 指纹/锚点可解析/机器登记/env.sh/骨架/AGENTS.md/Runtime 接线/cfg 漂移/config 仓库干净/备份通道/IDE/XDG/inotify（Linux 项）/叠层/根盘水位；--json 出 bde.doctor/1
devenv lint        # 文档锚点校验：Skill/AGENTS 正本里写死的路径是否仍存在（失效 → 列文件:行）
devenv map         # 隐藏目录注册表 + 未登记/失踪检测（--sizes 附体量与最近使用，较慢）
devenv tidy        # 清可再生缓存（SAFE 清单，~10G 级）
devenv report      # markdown 报告 → $COMMON/20_DocSpace/Envstate/<机器名>-<时间>.md
devenv namecheck   # 目录命名规范（硬=未登记；存量=已登记样式；--migrate 逐项授权）
devenv cfg         # 配置治理：清单/漂移/apply/adopt（详见 bestdevenv-config）
```

## 诊断顺序

1. `devenv brief` 拿总览 → 有待处置项再 `devenv doctor` 逐项定位 → 按域路由修复 → doctor 复查。**[i] 警示行不计失败但要处置**：`runtime 注册表应装未装`（补装对应渠道工具）｜`gen 指纹过期分型`（templates 还是 cfg_sources 过期 → 直接 `devenv gen`）｜`目录存量命名违规`（`devenv namecheck --migrate` 逐项授权）
2. 锚点失效（doctor 红在「锚点全部可解析」）→ `devenv lint` 看文件:行 → 改 `templates/` 正本 → `devenv gen` 再生；按需例外登记 `$COMMON/10_Config/Registry/anchor-ignore.tsv`
3. 磁盘紧张 → `devenv map --sizes` 看大头 → `devenv tidy` → doctor 复查根盘 >15G。**tidy 回收≈0 ≠ tidy 失效**——缓存已按架构重定向 ②③，回收≈0 恰证重定向成功；根盘红分型输出会提示走"结构性"处方（map 定位 → 构建十分离外置/扩容），别反复 tidy（2026-11-12 实测）
4. 症状不明 → `devenv report` 留痕，再按失败项路由（或回主 Skill 编排）

## tidy 边界（SAFE 清单纪律）

- **清**：gradle/npm/pnpm/go-build 缓存、Electron/浏览器标准缓存子目录（不碰登录态）、vscode-server 旧版本、Trash、journal 压至 100M
- **绝不碰**：工具运行时（codex-runtimes）、浏览器配置/登录态、JetBrains 索引、用户会话数据（opencode.db）、未知目录
- 新隐藏目录出现 → `devenv map` 报未登记 → 在 `$COMMON/10_Config/Registry/home-map.tsv` 补一行并 commit（登记数据进 config 仓库）

## 验收

处理完必跑 `devenv doctor` 复查，向用户报告前后对比（✗→✓ 清单）。
