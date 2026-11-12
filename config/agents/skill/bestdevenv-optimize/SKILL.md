---
name: bestdevenv-optimize
version: 0.0.1
description: BestDevEnv 系统基线与参数优化——经能力总线（lib/cap.sh）落地的系统优化默认集（inotify/swappiness/journald 上限/nofile/fstrim）、docker 三件套、apt 源检测、默认终端 konsole/shell zsh、fcitx5、starship、Nerd Font 的落地与幂等重放时使用。触发：优化系统参数、内核参数、swappiness、日志上限、文件句柄、docker 配置、镜像源、终端、输入法、字体。
---

# 系统基线与参数优化（M1）

单一职责：OS 层基线与参数。目录/挂载归 `bestdevenv-dirs`，用户配置文件归 `bestdevenv-config`。

## 执行（幂等；L3 编排平台无关——平台差异全部在 adapters/<family>.sh）

```bash
source "$HOME/.config/devspace/env.sh"
BDE="$COMMON/code/BestDevEnv"
bash "$BDE/modules/os/baseline.sh"   # 内部 cap_load 按本机加载适配器（debian/fedora/arch/suse/darwin）
```

分层契约（v0.19 起）：先抽象能力（`lib/cap.sh` 能力总线：pkg/svc/kernel/limits/logs/trim/timesync/hostname/fonts/shell/im/terminal/group），
再按平台实现（`modules/os/adapters/`）——`devenv cap` 看本机能力矩阵；上层编排零平台字面量。

## 已落盘参数清单（重跑即重放）

| 项 | 落点 | 验收 |
|---|---|---|
| 内核参数 | 正本 ③ `config/services/sysctl/99-devspace.conf` → `/etc/sysctl.d/`（inotify=524288 / swappiness=10 / vfs_cache_pressure / file-max；cfg-map `sysctl-devspace`，落位后自动 `sysctl --system`） | `sysctl vm.swappiness` ｜ doctor |
| journald 上限 | 正本 ③ `config/services/systemd/journald-devspace.conf` → drop-in（SystemMaxUse=512M / KeepFree=1G / Retention=14day；落位后自动重启 journald） | `ls /etc/systemd/journald.conf.d/` |
| nofile 上限 | 正本 ③ `config/services/limits/99-devspace.conf` → `/etc/security/limits.d/`（nofile=65535，登录会话生效） | `ulimit -n`（新会话） |
| SSD TRIM | `fstrim.timer` enable --now（对机械盘无操作=无害） | `systemctl is-enabled fstrim.timer` |
| zram 压缩内存交换 | 语义包 zram（debian=zram-tools+`/etc/default/zramswap`；fedora/arch/suse=zram-generator conf）；zstd/50% RAM | `swapon --show`（zram0） |
| 笔记本电源 | 语义包 power-suite（tlp[+tlp-rdw]）；**无电池自动跳过**（台式机/VM） | `systemctl is-active tlp`（仅电池机） |
| 时区/locale | 站点画像驱动（③ network.toml `timezone`/`lang` → network.env → locale 能力 timedatectl/localectl） | `timedatectl show -p Timezone` ｜ doctor「时区与画像一致」 |
| 时间同步 | 只体检不装（timesyncd/chronyd 运行态 → doctor 项） | doctor「时间同步服务运行中」 |
| 开发者字体 | JetBrainsMono Nerd Font 用户级（③ install/fonts 本地投放优先 → ② 缓存网络兜底 → fonts 能力落位） | `fc-list \| grep -c JetBrains` |
| inotify 上限 | 同内核参数行（watches=524288 / instances=1024） | `sysctl fs.inotify.max_user_watches` |
| docker 配置 | cfg-map 收编：正本 ③ `config/services/docker/daemon.json` → `/etc/docker/daemon.json`（`devenv cfg apply`） | `devenv cfg diff` ｜ `docker info` |
| docker 数据根 | ① `DevEnv/services/docker`，经 `var-lib-docker.mount` bind 成 `/var/lib/docker` 给 dockerd（数据仍在 ①；挂载点必须在 `$HOME` 外，否则容器的 rootfs/overlayfs/\<id\> 会被 gvfs 当可卸载假卷） | `findmnt /var/lib/docker` ｜ `docker info` Docker Root Dir=`/var/lib/docker` ｜ `docker system df` |
| docker 安装体 | 语义包 `docker-engine`（适配器别名：apt=docker.io）+ svc ensure + group ensure | `systemctl is-active docker` |
| apt 源 | 只检测报告，不自动切（人工切阿里/清华） | 执行输出 pending 项 |
| 默认终端/shell | konsole + Ctrl+Alt+T；zsh；`.bashrc` 接 env.sh | `echo $SHELL` |
| 输入法 | fcitx5 全家桶 + **macOS12 皮肤**（macos12-light/dark → ① `$DEV/xdg/local/fcitx5/themes/`，git→jsDelivr→API 三链路拉取）+ rime 简体默认；皮肤选择在 config 仓库 `classicui.conf`（macOS12 双主题：`Theme=macos12-light/dark` 手动切，`UseDarkTheme=True` 跟随系统亮暗；**fcitx5 GUI 改设置会重写该文件并剥注释——收编走 `devenv cfg adopt`（正本=应用层原样），绝不用 `cfg apply` 覆盖，切换语义存 cfg-map 备注列**）；**IM 环境变量由 config 仓库 `dot_config/environment.d/50-devspace.conf.tmpl` 下发**（GTK/QT/XMODIFIERS → fcitx：GNOME Wayland 的 Mutter 只支持 IBus，必须让客户端自己加载 fcitx 模块直连 D-Bus）；启用/雾凇为人工 | `im-config -n fcitx5` + 重登；`systemctl --user show-environment \| grep IM_MODULE` 应为 fcitx ｜ 皮肤重放：`bash modules/os/fcitx5-theme.sh` |
| 提示符 | starship（`~/.local/bin` 用户级安装） | `starship --version` |

> 本表数值（@CFG_*@ 占位符）由 `devenv gen` **从 ③ 正本实时渲染**——零复述双源；来源正本哈希入 gen 指纹，改值未再生 → doctor「正本与模板同代」项检出。改值流程：只改正本 → `devenv cfg apply` → `devenv gen`。

## 边界

- 写操作依赖 `sudo -n` 免密——批量 pending 先查 sudo
- locale/时区不在脚本内盲改（人工确认后手改；doctor/report 提示建议值）
- GNOME Wayland 下 Mutter 只认 IBus：不走 GTK/Qt IM 模块的客户端（`--ozone-platform=wayland` 的 Chromium/Electron、GNOME Shell 自身界面）用不了 fcitx5；需要中文输入时让该客户端走 XWayland（`--ozone-platform=x11`），或整体改用 IBus
- 改内核参数只改 ③ 正本再 `devenv cfg apply`（落位即自动生效）——绝不手改应用层
- **建议集（不自动，需人工确认）**：仅剩 DNS（systemd-resolved 改写）与静态 IP/netplan——网络行为相关，盲改是生产事故源；需要时经 cfg 治理通道收编后手动 apply
- **桩测试**：`verify/test-cap.sh`（84 断言，五家族语义验证，CI 可跑）；真机验收清单 `verify/ACCEPTANCE.md`——fedora/arch/suse/darwin 从"代码就绪"升级"生产实装"的唯一通道
