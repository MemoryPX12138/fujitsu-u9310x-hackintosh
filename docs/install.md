# 安装 / 替换 / 回滚

> 本机已经是装好的状态。这一页是给「换一块盘重装」或「想复刻一台」用的。
>
> ⚠️ **只适用于「无头骑士」形态**（无内屏 / 无电池 / 无摄像头 + 外接 HDMI 显示器）。
> 原装笔记本要先补电池、背光、睡眠、内置键鼠，见 [requirements.md §0](requirements.md#0-仅适用于无头骑士形态最重要的一条)。

## 1. 准备

| 东西 | 说明 |
|---|---|
| macOS 15.8.3 安装盘 | `InstallAssistant.pkg` → 生成 `Install macOS Sequoia.app` → 写入 ≥16 GB U 盘 |
| 本仓库的 EFI | 装完系统前后都用同一份，别中途换 |
| 一个能启动的备用设备 | U 盘 PE / 另一块装了系统的盘，EFI 改坏时用来救 |
| 有线网 | 安装阶段没有无线驱动（`AirportItlwm` 要进系统才加载），装完再配 Wi-Fi |

制作安装盘（在 macOS 上）：

```bash
sudo /Applications/Install\ macOS\ Sequoia.app/Contents/Resources/createinstallmedia \
     --volume /Volumes/USB
```

然后把本仓库 `EFI/` 拷到 U 盘的 EFI 分区（`diskutil mount diskXs1`）。
**注意**：安装阶段要把 `ScanPolicy` 临时改成 `0`，否则菜单里可能看不见安装盘/其他分区。

## 2. BIOS 设置

U9310X 是 Insyde 固件，菜单项名称各家一致。**必须/建议**这样设：

| 项 | 值 | 为什么 |
|---|---|---|
| Secure Boot | **Disabled** | 黑苹果不签 OpenCore |
| Fast Boot | **Disabled** | 快启会跳过 USB 初始化，安装盘经常认不到 |
| CSM / Legacy Boot | **Disabled**（纯 UEFI） | 混合模式会让 `SetupVirtualMap` 行为不确定 |
| VT-d | **Enabled**（保持默认） | 靠 `DisableIoMapper=true` 处理，不用进 BIOS 关 |
| CFG Lock | 有就关，没有就算了 | U9310X 的 Insyde 通常**不暴露**这一项，靠 `AppleXcpmCfgLock=true` |
| DVMT Pre-Allocated | 有就设 **32 MB** | 与 `framebuffer-stolenmem=32MB` 对齐；设不了也不影响（OC 会补） |
| 雷电安全级别 | 有就设 **No Security / SL0** | 想以后折腾雷电时少一层障碍 |
| 网络启动 / PXE | Disabled | 减少启动噪音 |
| 硬盘模式 | AHCI（NVMe 无此项） | — |

> 这些是本项目实际使用的值 + 通用黑苹果要求。你的机器如果选项名不同，按语义对应即可。

## 3. 安装流程（单系统 / 整盘 macOS）

1. U 盘启动 → OpenCanopy 菜单 → 选 **Install macOS Sequoia**。
2. 磁盘工具：抹掉整块 NVMe 为 **APFS / GUID**，命名随意（本机叫「未命名」，卷名不影响 EFI）。
3. 安装（约 20–40 分钟，中间会重启 2–3 次）。**每次重启都要从 U 盘启动**，
   在菜单里选 `macOS Installer` 继续，直到出现设置向导。
4. 进系统后先别急着配 Wi-Fi，先把 EFI 从 U 盘拷到**内置盘 ESP**：
   ```bash
   diskutil list                        # 找 200MB 的 EFI，通常 disk0s1
   sudo diskutil mount disk0s1
   cp -R /Volumes/USB/EFI /Volumes/EFI/  # 或按 install 脚本走
   ```
5. 拔 U 盘重启，确认能从内置盘启动。

## 4. 装完必做的四件事

### 4.1 三码（否则 iMessage / App Store 用不了）

```bash
# 用 GenSMBIOS（仓库不带，去 GitHub 下）
# 1) 选 3) Generate SMBIOS
# 2) 机型输入 MacBookPro16,1
# 3) 把 Serial / MLB / SystemUUID 抄进 config.plist → PlatformInfo → Generic
# 4) ROM 用有线网卡真实 MAC（6 字节 hex，去掉冒号）
```

改完用 `scripts/verify-efi.sh` 校验再重启。

### 4.2 显示模式持久化

```bash
# 1) 装 displayplacer（brew 或官方 release 二进制，放 /usr/local/bin）
# 2) 看当前显示器 id 和目标模式
/usr/local/bin/displayplacer list
# 3) 写 LaunchAgent（把 id 换成你的）
mkdir -p ~/Library/LaunchAgents
cat > ~/Library/LaunchAgents/com.local.displaymode.plist <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>com.local.displaymode</string>
  <key>ProgramArguments</key>
  <array>
    <string>/usr/local/bin/displayplacer</string>
    <string>id:你的ID res:2560x1440 hz:120 color_depth:4 scaling:off</string>
  </array>
  <key>RunAtLoad</key><true/>
  <key>LimitLoadToSessionType</key><string>Aqua</string>
</dict></plist>
PLIST
launchctl load ~/Library/LaunchAgents/com.local.displaymode.plist
```

### 4.3 电源策略（无电池形态）

```bash
sudo pmset -a sleep 0 displaysleep 0 hibernatemode 0 standby 0 autopoweroff 0 powernap 0
```

### 4.4 先验收，再改别的

| 验收项 | 命令 / 方法 | 期望 |
|---|---|---|
| 显卡 | `system_profiler SPDisplaysDataType` | Metal 3，24-Bit，分辨率/刷新率正确 |
| 声音 | 放首歌 | 喇叭 + 麦克风正常（**3.5mm 插拔切换未修复**，见 [known-issues #0](known-issues.md#0-35mm-耳机插拔切换未修复)） |
| 有线 | `ifconfig en0` | 有 IP |
| 无线 | 菜单栏 Wi-Fi | 能连 5GHz |
| 蓝牙 | 连一个蓝牙键鼠 | 能用 |
| 睿频 | `sysctl machdep.xcpm.mode` | `1` |

四项都过了再折腾 USB 映射 / 睡眠这些「进阶项」。

## 5. 替换 EFI（日常改配置）

```bash
sudo ./scripts/apply-to-esp.sh ./EFI disk0s1
```

脚本会：挂载 → 备份到 `~/Desktop/EFI-backup-<时间>` → 覆盖 → **校验 SHA-256** → 卸载。
手写命令的版本：

```bash
sudo diskutil mount disk0s1
cp -R /Volumes/EFI/EFI ~/Desktop/EFI-backup-$(date +%H%M)
rm -rf /Volumes/EFI/EFI && cp -R ./EFI /Volumes/EFI/
sync && diskutil unmount /Volumes/EFI
```

## 6. 回滚

| 场景 | 做法 |
|---|---|
| 还能进系统 | `cp -R ~/Desktop/EFI-backup-xxxx/EFI /Volumes/EFI/` |
| 进不了系统 | U 盘启动（U 盘里放同一份能用的 EFI）→ 把备份拷回内置盘 ESP |
| 连菜单都进不去 | 拔盘接到另一台 Mac，挂载 ESP 覆盖；或用 U 盘 EFI 引导后修 |

**永远保留一份「上次能开机」的 EFI 压缩包**，这是黑苹果唯一的保险。

## 7. 升级系统时

1. 先备份 EFI 和当前系统（Time Machine 或整盘克隆）。
2. `revpatch=sbvmm` 会只提供**全量安装包**，12–15 GB，正常。
3. 装完第一次启动仍然用同一份 EFI；如果卡住，先在菜单里选旧系统分区确认 EFI 没坏。
4. 升级后重跑一遍 `scripts/diagnose-macos.sh`，对比升级前的输出——**差异就是问题**。
