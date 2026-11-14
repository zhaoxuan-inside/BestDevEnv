---
name: bestdevenv-config
version: 0.0.1
description: BestDevEnv 配置规范与漂移治理——改用户配置（zshrc/env.sh/gitconfig/npmrc/starship）、chezmoi apply、系统/服务配置（devenv cfg）、配置漂移排查与收编、config 仓库 commit/push 时使用。触发：改配置、chezmoi、配置漂移、config 仓库、装服务/软件后的配置纳管。
---

# 配置规范与漂移治理（M1.5 chezmoi + M1.6 统一配置治理 + config 仓库）

单一职责：配置的规范变更与漂移回收。唯一事实源：**`$COMMON/config`**（git 仓库。宪法：配置永远改仓库，备份永远靠 push）。

## 标准变更流（chezmoi 管的应用层 dotfile）

```bash
source "$HOME/.config/devspace/env.sh"
CFG="$COMMON/config"
$EDITOR "$CFG/dot_zshrc"                                # 例：改某一配置源文件
git -C "$CFG" add -A && git -C "$CFG" commit -m "..." && git -C "$CFG" push
chezmoi apply -S "$CFG" --destination "$HOME" --force   # 应用到本机（改前自动备份 ~/.zshrc ~/.gitconfig）
```

或直接跑工程封装（含 hosts.toml 同步）：
`bash "$COMMON/code/BestDevEnv/modules/os/apply-config.sh"`

## 统一配置治理（M1.6：系统/服务配置，宪法 §19.3）

任何服务/软件/工具的配置文件都有登记表：BestDevEnv `modules/cfg/cfg-map.tsv`；
正本住 `$COMMON/config/{services,apt,dot_config}/`（git 版本化），应用层由正本再生：

```bash
devenv cfg list                # 清单：项|类|正本|应用层|机制|漂移（devenv svc 只看服务类）
devenv cfg diff                # 全量漂移检测（非零退出 = 有漂移；doctor 亦巡检）
devenv cfg apply [name]        # 正本 → 应用层（copy/copy-expand: 备份+落位；append: 逐行追加；hosts: 动态片段；幂等）
                               # 落位成功自动触发生效动作（sysctl --system / journald 重启）
devenv cfg adopt <name> <应用层路径> [类] [root]   # 新装软件的配置收编：拷为正本 + 登记一行
devenv cfg snapshot            # 备份：③ 正本 → 工程仓库 config/ seed 快照 + commit（工程仓库 git push 即异地备份）
devenv cfg restore [name] [dry]   # 回退/重建：seed → ③ 正本（snapshot 的逆通道；落盘前自动备份 ③ 现状 → ① backup；
                               # 不带 --delete，③ 独有文件如密钥 .env 不清除；dry=只预览；③ 缺失=灾后重建）
```

改系统/服务配置的标准动作 = **改正本 → commit/push → `devenv cfg apply`**；
服务生命周期（enable/start）归安装体，不归本工程。

## 备份通道（config 正本的异地备份）

config 正本（③）跨机同步靠共享盘；**异地备份 = `devenv cfg snapshot`**：③ → 工程仓库 `config/` seed
快照（rsync 镜像 + commit）→ 工程仓库 `git push` 到 GitHub。改动 ③ 后跑一次 snapshot，doctor
「config 备份通道」项巡检 seed 在册且工程仓库有 remote。

**回退/重建 = `devenv cfg restore`**（snapshot 的逆通道）：seed → ③ 正本回灌。回任意历史时点：
`git -C "$COMMON/code/BestDevEnv" checkout <commit> -- config` 后再 restore。回灌不动应用层——
生效走 `devenv cfg apply`、核对走 `devenv cfg diff`。单项回退 `restore <name>`，整树回退/灾后重建
`restore`（③ 正本整体缺失时即重建通道，新机器可凭工程仓库 seed 直接拉起 ③ config）。

## 漂移治理（应用层 ≠ config 时）

1. `devenv cfg diff`（系统/服务配置）或 `diff`（chezmoi dotfile）定位差异
2. **以 config 为准收编**：手改是有价值的改进 → 写回正本（chezmoi 源或 services/ 正本）并 commit；手改是误操作 → `devenv cfg apply` / chezmoi apply 覆盖
3. 重新 apply，向用户说明收编决定
4. 绝不允许"手改应用层了事"——那是漂移的来源，不是修复

## 机器数据表

`$CFG/hosts.toml`：与工程仓库同源，由 apply-config 单向同步；改机器数据去工程仓库 `hosts.toml`。

**/etc/hosts 生成（v0.19）**：cfg-map `hosts-fragment` 动态机制——`devenv cfg apply` 从 hosts.toml
生成带标记块（`# >>> generated-by-BestDevEnv >>>`）的片段幂等替换进 /etc/hosts（ip 空的机器段跳过、
块外内容永不触碰）。给机器分配 ip = 改 hosts.toml `ip` 字段 → apply。hostname 漂移（登记 vs 实际）
由 doctor 报警，不自动改（克隆 VM 场景防误改；对齐命令 `sudo hostnamectl set-hostname <登记名>`）。

## 验收

`devenv doctor` 的「config 就绪」「env.sh 已应用」「系统/服务配置无漂移」「config 仓库干净」项 ✓；任何 config 改动提醒 commit + push（远端未挂时提醒用户）。
