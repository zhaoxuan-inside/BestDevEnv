---
name: bestdevenv-runtime
version: 0.0.3
description: BestDevEnv runtime 统一管理层——所有 vibecoding 工具视为可替换 Runtime，统一接线记忆（AGENTS.md 正本）、Skill（正本分发）、MCP（mcp.json 正本投影）、会话治理（登记+orch 续做）。当任务涉及：新增/接线 runtime、切换工具的环境不适、MCP server 增删同步、skills 分发、会话库调查治理时使用。
---

# Runtime 统一管理（记忆 / Skill / MCP / 会话）

单一职责：让任何 vibecoding 工具接上**同一份记忆、同一套 Skill、同一组 MCP、同一个任务续做协议**——工具只是运行时，环境由 BestDevEnv 承载。

## 四域正本与落点

分层：**Skill/MCP 正本住 ③**（`$COMMON/config/agents/`，config 仓库 git 版本化——push/pull 即跨机器复用）；**记忆住 ①**（每机器 probe 渲染产物，可复用的是模板）；路径锚点（`${DEV}` 等）在投影时按本机展开。

| 域 | 正本 | 各工具落点（symlink/投影） | 动作 |
|---|---|---|---|
| 记忆 | ① `~/.config/devspace/agents/AGENTS.md` | `~/.claude/CLAUDE.md`、`~/.codex/AGENTS.md`、`~/.gemini/GEMINI.md`、`~/.config/opencode/AGENTS.md`、`~/.zcode/AGENTS.md`、`~/.agents/AGENTS.md`（arkcli） | `devenv runtime wire` |
| Skill | ③ `$COMMON/config/agents/skill/<name>/` | `~/.claude/skills`、`~/.agents/skills`（zcode/arkcli 共用枢纽，ZCode 原生扫描）逐项 symlink | `devenv runtime wire` |
| MCP | ③ `$COMMON/config/agents/mcp.json`（锚点按本机展开） | claude `~/.claude.json`、codex `config.toml` 托管块、gemini `settings.json`、opencode `opencode.json`、copilot `mcp-config.json`、zcode/arkcli 走 `~/.agents/mcp.json` 兜底 | `devenv runtime mcp sync` |
| 会话 | 工具私有（登记于 `modules/agent/runtimes.tsv`） | 各工具自管 | `devenv runtime sessions`（只读调查） |

## 执行

```bash
source "$HOME/.config/devspace/env.sh"
BDE="$COMMON/code/BestDevEnv"
bash "$BDE/modules/agent/runtime.sh" list        # 全 runtime 接线现状视图
bash "$BDE/modules/agent/runtime.sh" wire        # 幂等接线（memory + skills + mcp）
bash "$BDE/modules/agent/runtime.sh" skill adopt <name> <路径>   # 枢纽真实技能目录收编进 ③ 正本
bash "$BDE/modules/agent/runtime.sh" mcp sync    # MCP 正本（锚点展开）→ 各工具投影
bash "$BDE/modules/agent/runtime.sh" mcp list    # 正本内容
bash "$BDE/modules/agent/runtime.sh" sessions    # 会话库调查（只读，不迁移不清理）
vibe <tool> [args]                               # 统一启动（source env.sh 后 exec 工具）
```

## 规则

1. **注册表是唯一事实源**：`$BDE/modules/agent/runtimes.tsv`——新 runtime 先登记一行，再 `wire`；域留空 = 约定不明，登记待定
2. **模板类正本勿手改**：AGENTS.md/SKILL.md 改 `$BDE/templates/` 后由 `agents-md.sh` 再生；**MCP ③ 正本可直接编辑**（编辑后 commit——它随 config 仓库跨机器同步；鉴权/密钥不入此文件）
3. **绝不覆盖工具真实配置**：已有真实文件 → `ensure_backup` + pending 人工合并；工具自有状态（如 `~/.zcode/cli/config.json`）只在已有非空 `mcp.servers` 时受控合并。**投影写前必留痕**：`ensure_json_key_equal` 判等跳过（无变化报 [=]），有差异先 `ensure_backup` 再合并——正本为空时也要能自证"未清工具本地键"（2026-11-12 实测：投影曾无条件重写报 ✓，与幂等验收矛盾且无备份可查）
4. **会话库永不迁移/清理**（home-map 政策为准）；跨工具任务续做 = `devenv orch`（journal 落 `$DEV/docs/progress/`）
5. **收编**：工具内手动加的 MCP server 属工具本地——要全局生效就抄进 ③ `mcp.json` 正本再 `mcp sync`；枢纽出现的真实技能目录（如工具自更新重建）→ `skill adopt` 收编回 ③，防散落
6. 验收：`devenv doctor`「Runtime 统一接线」项 ✓ + 「agents 正本已入 ③ config 仓库」项 ✓ + `devenv runtime wire` 二次执行全 skip（幂等；投影行无变化必须 [=] 而非 ✓——[✓] 仅代表真实写入）

## 长任务编排

多步接线/批量接入新工具时走 `devenv orch`（见主 Skill 编排协议）：`orch new` 建日志 → 逐步 `wire`/`mcp sync` → `orch done` 记账 → doctor 终验。
