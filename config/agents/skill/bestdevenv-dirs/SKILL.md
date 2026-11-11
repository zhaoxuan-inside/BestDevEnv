---
name: bestdevenv-dirs
version: 0.0.1
description: BestDevEnv 三档目录架构与挂载——/Share 锚点、挂载与 fstab（后端按 ③ storage.toml 档案：hgfs/local/nfs/smb/rclone，介质无感——NAS/云盘示例见 storage.toml 注释）、Common 八区骨架、XDG 用户目录重定向、旧挂载迁移收尾时使用。触发：挂载消失、fstab、NAS/云盘挂载、目录骨架、XDG 重定向、迁移。
---

# 目录架构与挂载（M2）

单一职责：锚点/挂载/骨架/XDG。系统参数归 `bestdevenv-optimize`，配置文件归 `bestdevenv-config`。

## 执行（幂等，可单独重跑）

```bash
source "$HOME/.config/devspace/env.sh"
bash "$COMMON/code/BestDevEnv/modules/dirs/linux.sh"
```

内容：死挂载清理（清单制 ③ `config/data/mount-fixups.tsv`）→ 作用域就绪（**L0 存储抽象层** `lib/storage.sh`：`bde_storage_ensure shared/host`——M2 不感知介质；后端由 ③ `storage.toml` 档案决定：已挂载任意后端直接就绪 ｜ hgfs ｜ local 本机目录，锚点恒定）→ **每机器状态 env**（`state-env.sh` → ① `anchors.env` 锚点正本 + `network.env` 网络画像，env.sh 自动 source）→ **共享盘能力探测**（symlink/hardlink/大小写/权限/文件名长度 → probe 事实，物理边界按事实渲染）→ 骨架 50 目录 → app 实体归位（清单制 ③ `config/data/apps-classify.tsv`）→ config 种子（仅共享盘无 config 时）→ `~/DevEnv/bin/devenv`（含 `state-env` 子命令）与 code-* 四件套分发 → XDG 用户目录重定向（先搬家后 symlink）。

## 物理边界（本机实测，由 probe 能力探测生成；换后端自动重测）

\- 无 symlink（probe 实测）
\- 无 hardlink（probe 实测）
\- 权限恒 777（probe 实测）
\- 文件名上限 255B（probe 实测）
- 依赖实体（node_modules/venv）与私钥绝不放共享盘——住 ①（跨机一致性；bind 接回）
- 单文件名/深层路径超 255B 上限——gradle/flutter 类缓存留本机盘
- 命名一律小写 kebab-case

## 状态 env 再生（改档案后）

```bash
devenv state-env          # 再生 ① anchors.env / network.env；重开 shell 生效
```

## 迁移收尾（仅迁移期）

```bash
devenv migrate-finish     # 旧 ~/Share 挂载下线后：守卫检查 → 清理旧目录 → ~/Share → /Share symlink
```

## 验收

`devenv doctor` 中 Common/Local 可写、存储持久化（按后端）、后端符合档案预期、共享盘能力已探测、骨架就绪、XDG 重定向各项 ✓。
