# 实机验收清单（跨平台里程碑）

> 桩测试（`verify/test-cap.sh`）验证的是**适配器语义**（别名/命令形态/落位路径/降级行为）；
> 真机才能验证的是**平台事实**（包名存在于该发行版仓库、服务单元名、内核行为）。本清单 =
> 各平台真机到位后的标准验收流程——跑完全绿，该平台才从"代码就绪"升级为"生产实装"（宪法：实机验证才算数）。

## 通用流程（任何新平台机器）

1. 装系统 → 手动挂载共享盘（按 storage.toml 档案）→ clone 工程仓库
2. `./init.sh`（交互选角色/栈）→ 全阶段跑完
3. `devenv cap` —— 对照本表"预期矩阵"核对
4. `verify/test-cap.sh <family>` —— 桩测试全过
5. `devenv doctor` —— 全绿
6. 本平台专属项（见下）逐条人工确认
7. 结果回写 README 适用范围行 + 本清单勾选

## arch（hosts.toml 已登记实验机）

- [ ] `pacman -Qi zram-generator` —— 别名 zram → zram-generator 包名存在
- [ ] `systemd-zram-setup@zram0` start 后 `swapon --show` 出现 zram
- [ ] `pacman -Sy --needed fcitx5-im` 包组可装（别名 im-suite）
- [ ] `jdk21-openjdk` / `base-devel` 包名存在（java-21/build-base 别名）
- [ ] `/etc/pacman.d/mirrorlist` 国内源检查路径正确（cap pkg check_source）
- [ ] `chsh -s zsh` 与 `localectl set-locale` 行为正常（systemd 版本差异）
- [ ] `devenv doctor` 的 inotify/sysctl/fstrim/zram/timesync/tz 全绿

## fedora（或 rhel/centos/rocky/alma 任一）

- [ ] `moby-engine` 可装（docker-engine 别名；如需 docker-ce 上游 repo，收编进 cfg 治理）
- [ ] `java-21-openjdk` / `gcc gcc-c++ make` / `konsole` / fcitx5 五件套包名存在
- [ ] zram-generator：conf 落位后 `systemd-zram-setup@zram0` 生效
- [ ] `/etc/yum.repos.d/*.repo` 镜像检查路径正确
- [ ] tlp 可装可启（如为笔记本）

## suse（opensuse-leap/tumbleweed）

- [ ] `docker docker-compose` / `java-21-openjdk` / `konsole` 包名存在
- [ ] `zypper refresh/install` 非交互旗标正确（`-q --non-interactive install`）
- [ ] zram-generator conf 生效；`/etc/zypp/repos.d/*.repo` 镜像检查路径正确

## darwin（多版本 macOS 各一台）

- [ ] brew 在 PATH 或默认位（`_brew_bin` 三级回退）
- [ ] `brew install openjdk@21` / `--cask docker` 语义正确（cask 形态别名）
- [ ] `scutil --get LocalHostName` 与 hostname 对账语义（doctor host_registered）
- [ ] 明确 P2 剩余项：svc/launchd、fonts（~/Library/Fonts）、shell（dscl）、locale（systemsetup）——按能力契约逐项实装

## windows（win11，P3）

- [ ] init.ps1 从零编写（winget 清单 + mklink 目录接线 + C:\Dev 骨架）
- [ ] storage.toml passthrough 指向 `\\vmware-host\Shared Folders\` UNC
- [ ] 能力总线对偶实现：PS 侧 cap 等价物或直接 winget 清单驱动（立项时定）

## 桩测试的边界（为什么真机验收不可省）

| 桩测试覆盖 | 真机才能发现 |
|---|---|
| 命令形态/参数、语义包别名映射、配置落位路径、降级语义 | 包名在该发行版是否存在、版本冲突、服务单元名差异、内核参数取值边界、桌面会话行为 |
