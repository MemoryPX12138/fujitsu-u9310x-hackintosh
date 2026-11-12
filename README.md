# Fujitsu LIFEBOOK U9310X · macOS 15 Sequoia 黑苹果 EFI

> 项目名：**`fujitsu-u9310x-hackintosh`**
>
> 一台以「无内屏 / 无电池 / 无摄像头」形态使用的富士通 LIFEBOOK U9310X，跑 macOS 15.8.3，
> 用 OpenCore 1.0.8 + WhateverGreen 把 HDMI(LSPCON) 输出拱到 **2560×1440 @ 120Hz / 24-bit**。
> 本仓库是这台机器**唯一可开机**的 EFI、全部调试结论与踩坑档案。

![status](https://img.shields.io/badge/macOS-15.8.3%20(24H241)-brightgreen)
![OpenCore](https://img.shields.io/badge/OpenCore-1.0.8%20REL-blue)
![SMBIOS](https://img.shields.io/badge/SMBIOS-MacBookPro16%2C1-lightgrey)
![state](https://img.shields.io/badge/状态-日常可用-success)
![form](https://img.shields.io/badge/形态-无头骑士（无屏/无电池）-orange)

---

> ## ⚠️ 适用范围：**只适用于「无头骑士」形态的 U9310X**
>
> 本 EFI 是按 **无内屏 / 无电池 / 无摄像头** 的模组形态调的（外接 HDMI 显示器 + USB/蓝牙键鼠）。
> **原装笔记本形态不要直接套用**：电池电量、睡眠/唤醒、内屏亮度、内置键盘触控板、合盖休眠
> 这些功能在本 EFI 里**一个都没有适配**（对应 kext 与 SSDT 全部 `Enabled=false` 或不存在），
> 完整清单与补齐方法见 [docs/requirements.md §0](docs/requirements.md#0-仅适用于无头骑士形态最重要的一条)。
>
> 一句话定位：**把 U9310X 主板当台式机用**，不是「修好一台笔记本」。

---

## 1. 这台机器现在是什么状态

| 项目 | 状态 | 说明 |
|---|---|---|
| 安装 / 启动 | ✅ | macOS 15.8.3 (24H241)，单系统，整盘 APFS |
| 图形加速 | ✅ | UHD 620 / Metal 3，`AAPL,ig-platform-id=00009B3E` |
| 显示输出 | ✅ | HDMI(LSPCON) → 2560×1440@120 / 24-bit ARGB8888 |
| 音频 | ⚠️ | ALC255，`layout-id=3`：**喇叭 / 麦克风正常**；**3.5mm 插拔自动切换未修复**（插耳机不出现 Headphones、不切换），详见 [audio](docs/audio.md) |
| 有线网卡 | ✅ | I219-LM，IntelMausi，en0 |
| 无线 | ✅ | AX201 + AirportItlwm 2.4.0，802.11ac 1300 Mbps |
| 蓝牙 | ✅ | AX201 (USB 8087:0026)，键鼠可用 |
| CPU 电源管理 | ✅ | XCPM，P-State 4900 MHz 已验证 |
| NVMe | ✅ | 512 GB NVMe，TRIM 开启，NVMeFix 加载 |
| USB | ⚠️ | 可用，但**未做端口映射**（26 口中只暴露 14 口） |
| 睡眠 / 唤醒 | ⚠️ | 未验收；当前**主动禁用睡眠**（无电池的模组形态） |
| OTA 增量更新 | ❌ | 系统内 `bluetoothd` 被改过 → 只能**全量安装**升级，见 [known-issues](docs/known-issues.md#1-bluetoothd-被修改导致-ota-只能全量安装) |
| iMessage / App Store | ❌ | SMBIOS 是占位值，需自己生成三码 |

> 本 EFI 的 `config.plist` SHA-256：
> `01b757f65211b656c89e9edddb13eba23ea54d3fd733785b49d21a5be9fd2e04`
> （上一版 r16：`dbda3b73b27596533a425bfab7ab9405218a9fdcd23f80c0eddab9ac75b4dc40`）

---

## 2. 硬件真值表（全部为实测，不是推测）

| 部件 | 实测值 | 结论 |
|---|---|---|
| 机型 | Fujitsu LIFEBOOK **U9310X** | 以无内屏、无电池、无摄像头形态使用 |
| CPU | **i7-10610U** Comet Lake-U42，4C8T，1.8 GHz 基频 / 4.9 GHz 睿频 | 不需要 CPUID 伪装 |
| 内存 | 16 GB（2×8 GB **LPDDR3-2133**，板载） | — |
| 硬盘 | NVMe SSD 512 GB（PCIe x4 @ 8 GT/s） | TRIM 正常 |
| iGPU | **UHD 620**，`8086:9b41`，GFX0 `_ADR 0x20000` | 伪装 `device-id=9B3E` |
| 显示链路 | HDMI 经 **LSPCON** 转换（Linux 下该口报 `DP-1`） | 必须开 WEG 的 LSPCON/HDMI2.0 参数 |
| 外接显示器 | 2560×1440 原生 144 Hz，HDMI Forum VSDB max TMDS 600 MHz，含 FreeSync VSDB（48–144 Hz） | 见 [display](docs/display.md) |
| 声卡 | **Realtek ALC255**（cAVS `8086:02c8`），喇叭 node `0x14`、耳机 node `0x21` | `layout-id=3`；喇叭/麦克风正常，**3.5mm 切换未修复** |
| 有线 | **I219-LM** `8086:0d4e` | IntelMausi |
| 无线 | **AX201 CNVi** `8086:02f0` | AirportItlwm（Sequoia 构建） |
| 蓝牙 | **AX201 BT** USB `8087:0026` | IntelBluetoothFirmware + BTPatcher + BlueToolFixup |
| USB 控制器 | PCH-LP XHCI `8086:02ed`，HS01–HS14 / SS01–SS10 / USR1–USR2 = **26 口** | macOS 上限 15 口 |
| 雷电 | Titan Ridge **JHL7540**（桥 `15ea` / NHI `15eb` / USB `15ec`） | 未做 SSDT，热插拔无解 |
| SD 读卡器 | **O2 Micro OZ777** `1217:8520` | **macOS 无驱动，永久不可用** |
| 固件 | Insyde，OEM ID `FJNB2DB`，DSDT 287,634 字节 | EC 已叫 `EC`，禁止再加载 SSDT-EC |

完整清单与 PCI/USB ID：[docs/hardware.md](docs/hardware.md)

---

## 3. 快速开始（最短路径）

```bash
# 1) 备份你自己现有的 ESP（务必）
diskutil list                       # 找到 200MB 的 EFI 分区，例如 disk0s1
sudo diskutil mount disk0s1
cp -R /Volumes/EFI/EFI ~/Desktop/EFI-backup-$(date +%H%M)

# 2) 换成仓库里的 EFI
rm -rf /Volumes/EFI/EFI
cp -R ./EFI /Volumes/EFI/
sync && diskutil unmount /Volumes/EFI
```

三件**必须自己改**的事：

1. **SMBIOS 三码** —— 用 [GenSMBIOS](https://github.com/corpnewt/GenSMBIOS) 生成 `MacBookPro16,1` 的
   Serial / MLB / SystemUUID，ROM 用**有线网卡真实 MAC**。
   仓库里的 `W00000000001` / `M0000000000000001` / `112233445566` / 全零 UUID 是占位值，
   不换就等于把别人的身份拿去登录 iCloud（也登不上）。
2. **BIOS 设置**（见 [docs/install.md](docs/install.md#2-bios-设置)）：关 Secure Boot / Fast Boot / CSM。
3. **机型与形态匹配** —— 只对「无头骑士」形态的 U9310X（Comet Lake-U + LSPCON HDMI + ALC255 + AX201）负责；
   原装笔记本（有屏/有电池/内置键盘）不要直接用，见 [requirements §0](docs/requirements.md#0-仅适用于无头骑士形态最重要的一条)。

替换后第一次开机请保留一个 U 盘 PE / 可启动备份，EFI 改坏了还能救。

---

## 4. EFI 里到底有什么

```
EFI/
├─ BOOT/BOOTx64.efi
└─ OC/
   ├─ OpenCore.efi                    OpenCore 1.0.8 RELEASE (REL-108-2026-09-27)
   ├─ config.plist                    ← 唯一需要关心的文件
   ├─ ACPI/                           4 个（启用 3 个）
   │  ├─ SSDT-PLUG-DRTNIA.aml         CPU 电源管理（\_SB.PR00 命中）
   │  ├─ SSDT-USBX.aml                USB 供电属性
   │  ├─ SSDT-AWAC.aml                强制 legacy RTC（本机 DSDT 的 STAS 是 FieldUnit）
   │  └─ SSDT-XOSI.aml                （禁用，本机无 I2C 触摸）
   ├─ Kexts/                          33 个 bundle，启用 14 个
   ├─ Drivers/                        HfsPlus / OpenRuntime / OpenCanopy
   ├─ Resources/                      OpenCanopy 图标与字体
   └─ Tools/                          OpenShell / CleanNvram（菜单按空格可见）
```

启用 kext（14）：Lilu 1.7.2、VirtualSMC 1.3.8、SMCProcessor、WhateverGreen 1.7.1、
AppleALC 1.9.8、**VerbStub 1.0.4**、IntelMausi 1.0.8、NVMeFix 1.1.3、RestrictEvents 1.1.6、
CpuTscSync 1.1.2、AirportItlwm 2.4.0、IntelBluetoothFirmware 2.5.1、IntelBTPatcher 2.5.1、
BlueToolFixup 2.7.2。

> 其余 28 个（VoodooPS2/VoodooI2C/Brcm 系列/CPUFriend/HibernationFixup…）在 config 里以
> `Enabled=false` 保留，方便改配置时直接打开，不额外占运行内存。

关键参数速查：[docs/config-reference.md](docs/config-reference.md)

---

## 5. 三条最值钱的经验

1. **显示**：LSPCON 口必须同时给 `enable-lspcon-support` / `framebuffer-con1-has-lspcon` /
   `framebuffer-con1-preferred-lspcon-mode` / `framebuffer-con1-type=00080000`，
   平台 id 用**笔记本的 `00009B3E`**，不是桌面的 `07009B3E`。
   带宽是硬上限：**30-bit 最高 120Hz，24-bit 才能 144Hz**（显示器 TMDS 600 MHz）。
2. **音频**：ALC255 用 `layout-id=3` 才能让喇叭/麦克风正常；**3.5mm 插拔切换至今没修好**——
   `VerbStub` + verb 参数只能让 codec 稳定出声，jack sense 事件没有进程接，插耳机不会切输出。
   别再在这上面反复换 layout，先看 [audio.md](docs/audio.md) 的验证步骤。
3. **不要碰**：`igfxfw=2`（必死机）、`stolenmem ≥ 64MB`（超 DVMT）、`SSDT-EC`（与固件 EC 撞名）、
   `Macmini8,1 + 07009B3E`（从未成功开机）。完整失败档案：[docs/troubleshooting.md](docs/troubleshooting.md)

---

## 6. 文档索引

| 文档 | 内容 |
|---|---|
| [docs/requirements.md](docs/requirements.md) | **系统要求与适用范围**（硬件/软件/前置条件/验收清单） |
| [docs/hardware.md](docs/hardware.md) | 硬件真值表、PCI/USB ID、ACPI 设备路径 |
| [docs/firmware-acpi.md](docs/firmware-acpi.md) | Insyde 固件、DSDT 分析、SSDT 为什么这么写 |
| [docs/config-reference.md](docs/config-reference.md) | config.plist 逐项说明（boot-args / DeviceProperties / Quirks / ScanPolicy） |
| [docs/display.md](docs/display.md) | LSPCON、带宽账、120/144Hz、HiDPI 为什么放弃 |
| [docs/audio.md](docs/audio.md) | ALC255、layout 3、VerbStub、ComboJack |
| [docs/network.md](docs/network.md) | AX201 无线/蓝牙、AirportItlwm、能做什么不能做什么 |
| [docs/power-thermal.md](docs/power-thermal.md) | XCPM、P-State、PL1/PL2 为什么改不了、睡眠策略 |
| [docs/known-issues.md](docs/known-issues.md) | **缺陷与限制清单**（含证据与规避） |
| [docs/troubleshooting.md](docs/troubleshooting.md) | 失败实验档案：别再重复踩 |
| [docs/build-and-verify.md](docs/build-and-verify.md) | 校验 EFI、生成发布版、签名与哈希 |
| [docs/install.md](docs/install.md) | BIOS 设置、安装流程、替换/回滚 |
| [docs/changelog.md](docs/changelog.md) | R1 → R17 版本历史 |
| [docs/faq.md](docs/faq.md) | 常见问题 |

---

## 7. 适用边界（先看这段再决定要不要用）

- **只对「无头骑士」形态的 U9310X / 同平台（Comet Lake-U + LSPCON HDMI + ALC255 + AX201）负责。**
  换机型、换屏、换无线卡都要重做对应部分，别整套照抄。
- 适合：把笔记本主板当**桌面主机**用（外接 HDMI 显示器 + USB/蓝牙键鼠）。
- **不适合原装笔记本**：内屏点亮/亮度、电池电量、睡眠唤醒、合盖、内置键盘触控板
  **一个都没适配**（见 [requirements §0](docs/requirements.md#0-仅适用于无头骑士形态最重要的一条)）。
- 不适合：需要摄像头、SD 卡、雷电热插拔、AirDrop 接收、随航、3.5mm 插拔切换的场景。
- 系统上限：**macOS 15.x**。macOS 26 起 Intel 无线没有可用驱动，需要 OCLP root patch，更新即失效。

---

## 8. 许可与致谢

- 本仓库的**文档与脚本**：MIT（见 [LICENSE](LICENSE)）。
- `EFI/` 内的 OpenCore、kext、OpenCanopy 资源**各自遵循上游许可**（BSD-3 / MIT / GPL 等），
  版权归原作者；本仓库只做「这一台机器的可用组合」。
- `VerbStub.kext`（`com.XPS.VerbStub`）为第三方闭源 kext，随 EFI 分发仅为可用性，
  如原作者有异议请开 issue，会立刻移除。
- 感谢 Acidanthera（OpenCore / Lilu / WhateverGreen / VirtualSMC / AppleALC）、
  zxystd（itlwm / IntelBluetoothFirmware）、laobamac（AirportItlwm Sequoia 构建）、
  OpenIntelWireless 社区，以及所有把踩坑写进 wiki 的人。

> 本项目记录的是**单台机器的工程结论**，不是通用教程。刷 EFI 前先备份，改坏了能回滚。
