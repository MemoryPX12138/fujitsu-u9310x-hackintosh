# 硬件真值表

> 全部数据来自本机实测（`system_profiler` / `ioreg` / `acpidump` / Linux live 交叉验证），
> 不是从网上抄的「同型号应该长这样」。

## 1. 整机

| 项 | 值 | 采集方式 |
|---|---|---|
| 型号 | Fujitsu LIFEBOOK **U9310X**（13.3" 商务本主板） | 机身 / DMI |
| 固件 | **Insyde**，ACPI OEM ID `FJNB2DB` | `acpidump` |
| DSDT | 287,634 字节 | `logs/acpi/acpi2/DSDT.dsl` |
| 形态 | **「无头骑士」形态**：无内屏 / 无电池 / 无摄像头 / 无内置键盘（本 EFI 只按这个形态适配，原装笔记本功能未做） | 实机 |
| 系统 | macOS 15.8.3 (24H241) | `sw_vers` |

## 2. 计算与存储

| 部件 | 实测 | 备注 |
|---|---|---|
| CPU | **Intel Core i7-10610U**（Comet Lake-U42，model 142） | 4C8T，1.8 GHz 基频 / **4.9 GHz 睿频**（已验证 P-State） |
| 内存 | **16 GB** = 2 × 8 GB **LPDDR3-2133**，板载不可换 | `SPMemoryDataType` |
| 硬盘 | NVMe SSD **512 GB**（DRAM-less） | PCIe **x4 @ 8 GT/s**，TRIM: Yes，SMART: Verified |
| 硬盘固件 | 未记录（与 EFI 无关） | — |

## 3. 显示

| 项 | 值 |
|---|---|
| iGPU | **Intel UHD Graphics 620**，PCI `8086:9b41`，ACPI `GFX0`（`_ADR 0x20000`） |
| 伪装 device-id | `9B3E`（真值 `9B41`，UHD 620 的 macOS 可用 id） |
| 平台 id | `AAPL,ig-platform-id = 00009B3E`（**笔记本**平台） |
| 显存 | `IOFBMemorySize = 256 MB`，系统显示「VRAM 4095 MB」（`framebuffer-unifiedmem=0xFFFFFFFF` 只是显示值） |
| 输出口 | HDMI，**经 LSPCON 转换**（Linux 下报 `DP-1`） |
| 外接显示器 | 2560×1440 **原生 144 Hz**，HDMI Forum VSDB max TMDS 600 MHz，含 AMD FreeSync VSDB（48–144 Hz） |
| 内屏 | **不存在**（i915 日志 `disabling eDP`）→ 不需要 PNLF / 背光补丁 |

## 4. 音频

| 项 | 值 |
|---|---|
| 控制器 | Intel cAVS，PCI `8086:02c8`，ACPI `HDAS`（DeviceProperties 用 `PciRoot(0x0)/Pci(0x1F,0x3)`） |
| Codec | **Realtek ALC255** |
| 喇叭 | node `0x14` |
| 耳机 | node `0x21`；**插拔检测未打通**（见 [known-issues #0](known-issues.md#0-35mm-耳机插拔切换未修复)） |
| 麦克风 | 内置阵列，可用 |
| layout | `layout-id = 3`（AppleALC ALC255 layout 3） |

## 5. 网络

| 部件 | 实测 | 驱动 |
|---|---|---|
| 有线 | **I219-LM** `8086:0d4e`，en0，真实 MAC `xx:xx:xx:xx:xx:xx` | IntelMausi 1.0.8 |
| 无线 | **AX201 CNVi** `8086:02f0`（Comet Lake CNVi） | AirportItlwm 2.4.0（laobamac Sequoia 构建），固件 `itlwm: 2.4.0 / fw 68.01d30b0c.0` |
| 无线能力 | 802.11 a/b/g/n/ac，2.4G + 5G，实测 802.11ac 5GHz 160MHz **1300 Mbps** | — |
| 蓝牙 | **AX201 Bluetooth** USB `8087:0026`，Transport: USB，Firmware `v8787 c8787` | IntelBluetoothFirmware 2.5.1 + IntelBTPatcher 2.5.1 + BlueToolFixup 2.7.2 |

## 6. 总线与外设

| 部件 | 实测 | 状态 |
|---|---|---|
| USB 控制器 | PCH-LP XHCI `8086:02ed` | 26 个端口（HS01–HS14 / SS01–SS10 / USR1 / USR2），macOS 只放 15 个 |
| 雷电 | Titan Ridge **JHL7540**：桥 `15ea`、NHI `15eb`、USB `15ec` | 无 SSDT，热插拔不可用 |
| SD 读卡器 | **O2 Micro OZ777** `1217:8520` | **无 macOS 驱动，永久不可用** |
| 摄像头 | 无（USB 列表不存在） | 不参与验收 |
| 电池 | 无（只有 AC + UCSI） | 不需要 SMCBatteryManager / ECEnabler |

## 7. ACPI 设备路径（写 SSDT 时要对得上）

| 设备 | 路径 | 说明 |
|---|---|---|
| EC | `\_SB.PCI0.LPCB.EC`（PNP0C09，IO `0x62/0x66`，GPE `0x22`） | **名字已经叫 `EC`**，再加载 SSDT-EC 会撞名 |
| 时钟 | `AWAC`(ACPI000E) + `RTC`(PNP0B00)，由 NVS 字段 `STAS` 决定 | `STAS=0` 用 AWAC；Darwin 下要强制 `STAS=1` |
| CPU | `Processor (PR00..PR0F)` 位于 `\_SB` | 标准 `SSDT-PLUG-DRTNIA.aml` 正好命中 `\_SB.PR00` |
| 声卡 | `Device (HDAS)` | codec ALC255 |
| 雷电 | 不在 DSDT，在 `SSDT (INSYDE TbtTypeC)` | 另有 `UsbCTabl` / `Rtd3Ssdt` / `Win8Ssdt` / `CpuSsdt` / `SaSsdt` / `Tpm2Tabl` / `PcdTabl` |

## 8. 怎么自己复核一遍

```bash
# PCI / 显卡 / 显示
system_profiler SPDisplaysDataType
ioreg -l | grep -E "AAPL,ig-platform-id|IOFBMemorySize|MetalPluginName"

# 声卡
system_profiler SPAudioDataType
ioreg -rn HDEF | grep -i layout

# 无线 / 蓝牙
system_profiler SPAirPortDataType
system_profiler SPBluetoothDataType
kextstat | grep -Ei "AirportItlwm|IntelBluetooth|BlueTool"

# 硬盘 TRIM
system_profiler SPNVMeDataType | grep -i trim

# CPU 电源管理
sysctl machdep.xcpm.mode machdep.xcpm.vectors_loaded_count

# USB 端口
ioreg -r -c AppleUSBXHCIPCI -w0 | grep -oE "HS[0-9]+|SS[0-9]+|USR[0-9]+" | sort -u
```
