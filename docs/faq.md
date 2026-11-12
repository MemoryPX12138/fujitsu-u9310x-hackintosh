# FAQ

### 能装到原装的 U9310X（有屏有电池）上吗？

**不建议，而且大概率「能开机但不像一台笔记本」。**

这份 EFI 是按**无内屏 / 无电池 / 无摄像头**的形态调的，原装笔记本需要的这些东西全部没做：

| 功能 | 现状 |
|---|---|
| 电池电量 / 充电状态 | ❌ `SMCBatteryManager`、`ECEnabler` 禁用 |
| 内屏亮度调节 | ❌ 无 `SSDT-PNLF`，`BrightnessKeys` 禁用 |
| 睡眠 / 唤醒 / 合盖 | ❌ 未做 GPRW/PTSWAK，且 `pmset sleep 0`、`hibernatemode 0` |
| 内置键盘 / 触控板 | ❌ `VoodooPS2Controller`、`VoodooI2C*` 禁用 |

补齐清单见 [requirements.md §0](requirements.md#0-仅适用于无头骑士形态最重要的一条)。

### 这套 EFI 能直接拿去装别的机器吗？

不能。它只对 **U9310X（Comet Lake-U + LSPCON HDMI + ALC255 + AX201）** 负责。
同系列（U9311X 等）可能能用，但要逐项核对：ACPI 设备名、EC 命名、显示链路、codec、网卡。
拿别的机器直接刷，最坏的结果是开不了机（数据不丢，EFI 在独立分区里）。

### 为什么不用 macOS 26（Tahoe）？

三个硬阻塞：

1. Intel 无线（AirportItlwm）只到 Sequoia，26 需要 OCLP root patch 注回旧驱动，**每次更新失效**；
2. 内置声卡要走 AppleHDA 回注（同样 root patch）；
3. root patch 会让 SIP/SSV 状态更复杂，OTA 更不可控。

15.8.x 是这台机器的「最后一代原生可用」版本。

### 为什么开机不再滚屏了？是不是坏了？

不是。r17 去掉了 `-v debug=0x100 keepsyms=1`，现在只显示 Apple logo + 进度条。
排错时想恢复滚屏，见 [troubleshooting.md §4](troubleshooting.md#4-怎么让-opencore-说话排错时才开)。

### 为什么升级系统一定要下 12 GB 全量包？

两个原因叠加：

1. `revpatch=sbvmm` 让 `softwareupdate` 只提供全量包（黑苹果通用做法）；
2. 系统里 `bluetoothd` 的 x86_64 切片被改过，BOM 校验不过 → 增量补丁被系统自己拒绝（`FullReplacementRequired`）。

见 [known-issues.md #1](known-issues.md#1-bluetoothd-被修改导致-ota-只能全量安装)。

### 能开 AirDrop / 随航 / 通用控制吗？

不能。AX201 是 CNVi 网卡，缺 AWDL 的完整实现，这些功能全部依赖 AWDL。
文件互传用 `LocalSend`，剪贴板同步用第三方工具。

### 为什么系统信息里显卡叫 `Intel HD Graphics CFL CRB`？

因为没人给 iGPU 注入 `model` 属性。纯显示问题，不影响性能。
想改就在 iGPU 的 DeviceProperties 里加 `model = "Intel UHD Graphics 620"`（未在本机验证）。

### 为什么显示的是 2.3 GHz，CPU 不是 1.8 GHz 吗？

`MacBookPro16,1` 这个 SMBIOS 模板里写的是 2.3 GHz（i9 机型），
系统信息读的是 SMBIOS 而不是真实频率。**实际睿频能到 4.9 GHz**（`sysctl machdep.xcpm.mode` = 1）。
改这个要动 PlatformInfo 自定义，收益为零，没做。

### 插某个 USB 口没反应？

大概率是 **USB 端口没映射**：控制器有 26 个口，macOS 只放 15 个，超出的口直接不存在。
见 [known-issues.md #3](known-issues.md#3-usb-端口映射没做26-口--只暴露-14-口)。

### 睡眠唤醒能行吗？

没验收。当前策略是**永不睡眠**（无电池、无内屏的模组形态，等价台式机）。
要当笔记本用必须重做睡眠链路（GPRW/PTSWAK + hibernatemode 3 + 反复压测）。
见 [power-thermal.md §3](power-thermal.md#3-睡眠主动禁用不是坏了)。

### 为什么 PL1/PL2 改不了？

MSR 0x610 被 Insyde 固件在 SMM 里锁了，EC 也没暴露可写寄存器。
`VoltageShift` / `CPUFriend` / 改 BIOS 都试过，**软件层无解**。
睿频能上 4.9 GHz，但持续负载按原厂功耗墙走。见 [power-thermal.md §2](power-thermal.md#2-pl1--pl2改不了别再试)。

### 声音正常但耳机插上没反应？

**这是已知且未修复的缺陷**，不是你配置错了。

- `system_profiler SPAudioDataType` 里只有 `Built-in Output / Internal Speakers`，
  **没有 `Headphones`**；插拔耳机不会切换输出。
- 驱动侧（AppleALC 1.9.8 + `layout-id=3` + `VerbStub` + `alcverbs=1`）全部在位，
  缺的是「监听插拔事件并切换设备」的那一环（ComboJack 没有常驻守护进程）。
- 现状：用 USB / USB-C 声卡或蓝牙耳机；想继续攻见 [audio.md §5](audio.md#5-真要修好需要按这个顺序做)。

不要靠反复换 layout 来解决：本项目试过 3/11/13/27/28/56/66/71/99，只有 3 能正常出声。

### 屏幕切 App 掉帧怎么办？

确认是 **24-bit** 而不是 30-bit：

```bash
system_profiler SPDisplaysDataType | grep Depth     # 要 24-Bit Color (ARGB8888)
```

不是的话用 `displayplacer ... color_depth:4` 强制。
30-bit @120Hz 会吃满 LSPCON 链路，动画必掉帧。见 [display.md](display.md)。

### 能上 144 Hz 吗？

能，24-bit 下 1440p144 的像素时钟约 586.6 MHz，链路是 600 MHz，跑得动但只剩 2% 余量。
仓库默认 120 Hz 是为了留余量。切换命令在 [display.md §5](display.md#5-想要-144hz-怎么办)。

### 改完 config 开不了机怎么办？

1. 别慌，数据都在 APFS 分区里，EFI 是独立分区；
2. 用 U 盘启动（U 盘里放一份能用的 EFI）；
3. 把备份覆盖回去：`cp -R ~/Desktop/EFI-backup-xxxx/EFI /Volumes/EFI/`；
4. 复盘：一次只改一个变量，`scripts/verify-efi.sh` 必须过。

### 为什么仓库里的 EFI 有 57 MB？

`IntelBluetoothFirmware`（11 MB）+ `AirportItlwm`（15 MB）+ `itlwm`（15 MB，备选但禁用）
+ `AppleALC`（4 MB）+ `BrcmFirmwareData`（2.7 MB，禁用）都是带固件/多架构的大家伙。
想瘦身就删掉 `Enabled=false` 的 kext 目录（省约 20 MB）。

### ocvalidate 报一堆错，但机器能开机？

版本不匹配。`ocvalidate` 必须和 OpenCore **同版本**（本仓库是 1.0.8 配套版，
在 `tools/ocvalidate/`）。用 1.0.9 的校验器去校验 1.0.8 的 config 会报假错。

### 可以商用 / 二次分发吗？

文档与脚本 MIT。`EFI/` 里的 OpenCore / kext 各自遵循上游许可（BSD-3 / MIT / GPL），
分发时保留版权声明即可。`VerbStub.kext` 是第三方闭源，介意就从 EFI 里删掉
（代价：喇叭稳定性可能下降；它和 3.5mm 切换无关——那条本来就没修好）。
