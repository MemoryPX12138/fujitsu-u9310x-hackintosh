# 系统要求与适用范围

> 一句话：**这不是通用 EFI，也不是「一台完整笔记本」的 EFI**。
> 它只服务「无头骑士」形态的 U9310X —— 下面每一条都是「满足才能照抄」的硬条件。

## 0. 仅适用于「无头骑士」形态（最重要的一条）

> **本 EFI 是把 U9310X 主板当台式机用的产物。**
> 适用前提：**无内屏 / 无电池 / 无摄像头**，外接 HDMI 显示器 + USB 或蓝牙键鼠。

原装笔记本形态下，下列功能在本 EFI 里**没有适配、也没有验证**
（对应 kext 与 SSDT 全部处于 `Enabled=false` 或根本不存在）：

| 原装笔记本功能 | 本 EFI 现状 | 原因 / 需要补什么 |
|---|---|---|
| 内屏点亮（eDP） | ⚠️ 未适配 | 本机无内屏，`con0` 没做任何 framebuffer 补丁；接内屏要重新验证 `00009B3E` 的 eDP 行为 |
| 内屏亮度调节 | ❌ **未适配** | 没有 `SSDT-PNLF`；`BrightnessKeys.kext` 是 `Enabled=false`；NVRAM 无 `backlight-level` |
| 电池电量 / 充电状态 | ❌ **未适配** | `SMCBatteryManager.kext`、`ECEnabler.kext` 都是 `Enabled=false`；富士通 EC 字段未验证 |
| 睡眠 / 唤醒 / 合盖休眠 | ❌ **未适配，且主动禁用** | 无 `SSDT-GPRW` / `SSDT-PTSWAK`；`HibernationFixup` 禁用；`pmset sleep 0`、`hibernatemode 0` |
| 内置键盘 / 触控板 | ❌ **未适配** | `VoodooPS2Controller`、`VoodooI2C*`（含 HID/Synaptics/ELAN）全部 `Enabled=false`，本机用外接键鼠 |
| 风扇转速 / 温度传感器 | ⚠️ 部分 | `SMCSuperIO` 禁用（富士通 EC 不在其支持列表），只能拿 `SMCProcessor` 的 CPU 温度 |
| 摄像头 | 未验证 | 若为 USB UVC 通常免驱；本机无摄像头，无法验证 |
| 读卡器 | ❌ 硬件无解 | O2 Micro OZ777 `1217:8520` 无 macOS 驱动 |
| 亮度快捷键 | ❌ 未适配 | `BrightnessKeys` 禁用 |
| 合盖 / 开盖事件 | ❌ 未适配 | 无 lid 相关 SSDT，`lidwake` 行为未验证 |

**结论**：如果目标机是**完整原装笔记本**（有内屏、电池、内置键盘），
这份 EFI 只能当参考基线。至少要补齐：

1. `SSDT-PNLF` + `BrightnessKeys` + 背光设备属性；
2. `SMCBatteryManager` + `ECEnabler`，并确认 EC 字段可读；
3. `SSDT-GPRW` / `SSDT-PTSWAK`（或 `HibernationFixup`），`hibernatemode 3`，把 `pmset` 改回笔记本策略；
4. `VoodooPS2Controller`（或 `VoodooI2C` + `VoodooI2CHID`）；
5. eDP / `con0` 的 framebuffer 参数重新验证。

**在这些做完之前，别把这份 EFI 直接装到有屏有电池的机器上并期待「开箱即用」。**

## 1. 硬件要求（必须对得上）

### 1.1 最低匹配（同型号最稳）

| 项 | 要求 | 差一点会怎样 |
|---|---|---|
| 机型 | **Fujitsu LIFEBOOK U9310X** | 同系列 U9311X 需逐项核对 ACPI/EC/显示链路 |
| 平台 | Intel **Comet Lake-U**（10 代低压） | 换代 → CPU 电源管理/ACPI 全要重做 |
| iGPU | **UHD 620**（`8086:9b41`） | 别的 id 需换 `ig-platform-id` + `device-id` |
| 显示链路 | **HDMI 经 LSPCON**（DP→HDMI 转换） | 直连 HDMI 的机器去掉 5 个 LSPCON 键即可，但要重测 |
| 声卡 | **Realtek ALC255**（cAVS `8086:02c8`） | 别的 codec 要换 layout，VerbStub 可能不适用 |
| 无线 | **AX201 CNVi**（`8086:02f0`） | 换 BCM 卡要整套换成 AirportBrcmFixup |
| 蓝牙 | **AX201 BT**（USB `8087:0026`） | 同上 |
| 有线 | **I219-LM**（`8086:0d4e`） | 少数 I219-V 也能用，但 MAC/PHY 行为不同 |
| 存储 | NVMe SSD | SATA 盘要去掉 NVMeFix、加 SATA 相关补丁 |
| 固件 | **Insyde**（OEM ID `FJNB2DB`） | 换 AMI / Phoenix 要重做 Booter quirks |

### 1.2 形态要求（决定电源/显示策略）

本 EFI 是按「**无内屏 / 无电池 / 无摄像头，外接 HDMI 显示器 + USB/蓝牙键鼠**」调的：

- 没有内屏 → 不含 `SSDT-PNLF`、不配背光、`BrightnessKeys` 禁用；
- 没有电池 → `SMCBatteryManager` / `ECEnabler` 禁用，`hibernatemode 0`，`sleep 0`；
- 没有内置键盘 → `VoodooPS2Controller` / `VoodooI2C*` 禁用；
- 没有摄像头 → 不涉及摄像头相关补丁。

**带内屏 / 带电池的原装笔记本要补的清单见 §0。**

## 2. 软件要求

| 项 | 版本 | 说明 |
|---|---|---|
| macOS | **15.x Sequoia**（本机 15.8.3 / 24H241） | 26 起 Intel 无线无驱动，需 OCLP root patch |
| OpenCore | **1.0.8 RELEASE** | `config.plist` 与该版本严格对应，换版本必须重跑 ocvalidate |
| ocvalidate | **1.0.8 配套版** | 仓库 `tools/ocvalidate/` 自带 |
| Python（可选） | 3.8+ | 只有 `make-release.py` 需要 |
| 磁盘 | ≥ 64 GB（系统 + 常用软件） | 本机 512 GB |
| 内存 | ≥ 8 GB（推荐 16 GB） | 本机 16 GB LPDDR3 |
| 安装介质 | ≥ 16 GB U 盘 | 制作见 [install.md](install.md) |

## 3. 你必须自己完成的前置

| 事项 | 为什么不能替你做好 |
|---|---|
| **SMBIOS 三码**（Serial / MLB / SystemUUID / ROM） | 三码是身份，共用会互相踢下线；仓库只放占位值 |
| **BIOS 设置**（Secure Boot / Fast Boot / CSM 关闭） | 固件设置无法通过 EFI 传递 |
| **USB 端口映射**（可选） | 必须在本机逐口实测才能生成 `USBPorts.kext` |
| **备份现有 EFI** | 唯一可靠的后悔药 |

## 4. 不适用 / 不要用的情况

| 场景 | 原因 |
|---|---|
| **原装笔记本形态（有内屏 / 电池 / 内置键盘）** | **电池、睡眠、背光、键鼠都没适配，见 §0** |
| Apple Silicon Mac | 完全不同的引导体系 |
| 需要 AirDrop 接收 / 随航 / 通用控制 | AX201 缺 AWDL，硬件级无解 |
| 需要 SD 卡读卡器 | O2 Micro OZ777 无 macOS 驱动 |
| 需要雷电热插拔 | 未做 SSDT，NHI 未验证 |
| 需要 iMessage / App Store 开箱即用 | 必须先自己生成三码 |
| 需要 3.5mm 耳机插拔自动切换 | **已知未修复**，见 [known-issues #0](known-issues.md#0-35mm-耳机插拔切换未修复) |
| 需要 OTA 增量更新 | `bluetoothd` 被改过，只能全量安装 |
| 生产环境 / 唯一工作机 | 黑苹果升级不可控，至少准备一个可回滚的备份 |

## 5. 验收清单（装完逐项打勾）

- [ ] `system_profiler SPDisplaysDataType` → Metal 3 + 24-Bit + 目标分辨率/刷新率
- [ ] 喇叭出声、麦克风有输入（**3.5mm 插拔切换是已知未修复项**，不作为验收门槛）
- [ ] `ifconfig en0` 有 IP（有线）
- [ ] Wi-Fi 能连 5 GHz，速率 ≥ 800 Mbps
- [ ] 蓝牙键鼠可用
- [ ] `sysctl machdep.xcpm.mode` = 1
- [ ] `system_profiler SPNVMeDataType | grep -i trim` → Yes
- [ ] `scripts/verify-efi.sh` 全绿
- [ ] Time Machine / 整盘备份已就绪

> 注意：这份清单**只针对无头骑士形态**。原装笔记本还要额外验收电池、亮度、睡眠、内置键鼠
> —— 而那几项本 EFI 根本没做。
