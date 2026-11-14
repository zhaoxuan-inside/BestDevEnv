---
name: bestdevenv-init
version: 0.0.2
description: BestDevEnv 新机初始化——装完 OS 后从空白到 devenv doctor 全绿的一条命令构建；交互确认、进度落盘可续建、全量幂等。当任务涉及：新机器、装完系统初始化、init.sh、构建进度与续建时使用。
---

# 新机初始化（init.sh 全量管道）

单一职责：把一台空白 VM 构建到 `devenv doctor` 全绿。日常局部改动不属于本 Skill（回主 Skill 路由）。

## 执行

```bash
source "$HOME/.config/devspace/env.sh"
BDE="$COMMON/code/BestDevEnv"
cd "$BDE" && ./init.sh          # 交互询问：开发者角色（回车=跳过）→ vibecoding 工具（回车=不装——装什么开发者显式决定，可多选 claude-code/codex/zcode/arkcli/gemini-cli/opencode/copilot）→ 语言栈（回车=node,python）；非交互 bootstrap 取兜底集并在构建计划明示；会话内执行先与用户确认清单，经 --profile/--langs/--tools 显式传入
./init.sh --profile ml-trainer  # 按角色装配（java-web/python/go/cpp/ml-trainer/fullstack；展开为栈并集）
```

- 交互契约：构建计划（OS/语言栈/工具/阶段）确认后才动手；`--yes`/非交互终端自动取默认（bootstrap 免疫）；EOF（Ctrl+D）一律不开工

- 共享盘未挂载先按 ③ `storage.toml` 档案手动挂一次（hgfs 后端示例：`sudo mkdir -p /Share/Common /Share/Local && sudo vmhgfs-fuse .host:/Common /Share/Common -o allow_other`；local/passthrough 后端无需挂载，直接构建即可）
- 仓库缺失时先 clone：`git clone git@github.com:zhaoxuan-inside/BestDevEnv.git "$COMMON/code/BestDevEnv"`

## 进度管理

```bash
./init.sh --dry-run --profile cpp   # 预览构建计划（family/角色/语言栈/工具/阶段），不询问不执行
./init.sh --status    # 各阶段最近状态（状态文件 ~/DevEnv/docs/progress/<机器名>.state）
./init.sh --resume    # 跳过 done 阶段，失败阶段重跑
./init.sh --rerun     # 强制全量
```

阶段顺序：M2 目录 → M1 系统基线（按 OS 检测选变体）→ M1.5 config → M3 语言栈 → M4 工具+AGENTS/SKILL → M6 IDE → M5 报告。

## 失败处理

1. 全量日志：`~/DevEnv/docs/progress/init-<时间戳>.log`
2. 状态文件中 failed 阶段 → 排除原因后 `--resume`
3. 批量 pending 且涉及 sudo → 检查 sudo 免密（脚本写操作依赖 `sudo -n`）
4. `--machine <名>` 指定机器名（克隆 VM hostname 相同时必用，避免 hosts.toml/进度文件互撞）

## 完成动作

`devenv doctor` 全绿 → 检查 `$COMMON/config` 是否已 commit/push → 向用户报告验收清单与人工项（apt 源切换、`im-config -n fcitx5` 输入法启用）。
