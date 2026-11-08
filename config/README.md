# BestDevEnv 配置事实源（chezmoi 源）

唯一权威配置：本目录。机器应用层（`~/.zshrc`、`~/.config/devspace/env.sh` 等）全部由这里再生。

## 改配置的标准动作

```bash
$EDITOR dot_zshrc                                   # 例：改配置源文件
git add -A && git commit -m "..." && git push       # 跨机分发：其他机器 pull 后 apply
chezmoi apply -S . --destination "$HOME" --force    # 应用到本机（改前自动备份到 ~/DevEnv/docs/backup）
```

规则：绝不手改应用层了事；发现漂移以本仓库为准收编。工程仓库：`/Share/Common/code/BestDevEnv`。
