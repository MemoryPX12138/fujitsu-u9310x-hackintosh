# config.plist 逐项说明

> 基准：`EFI/OC/config.plist`，SHA-256
> `01b757f65211b656c89e9edddb13eba23ea54d3fd733785b49d21a5be9fd2e04`
> 生成器：OpenCore 1.0.8 `Docs/Sample.plist` 起步 + 就地覆盖，`ocvalidate` 0 错误。

## 1. boot-args

```
-lilubetaall alcid=3 igfxonln=1 revpatch=sbvmm itlwm_cc=CN igfxrpsc=1 \
ipc_control_port_options=0 -igfxmlr alcverbs=1 alcdelay=1000 alctsel=1
```

| 参数 | 归属 | 作用 | 能不能删 |
|---|---|---|---|
| `-lilubetaall` | Lilu | 允许 Lilu 及其插件在「未声明支持」的系统版本上加载 | 15.x 上可删，保留是为了小版本更新后不会突然掉驱动 |
| `alcid=3` | AppleALC | 指定 layout 3（与 `DeviceProperties layout-id` 双保险） | **不能删**，除非同步改 layout-id |
| `igfxonln=1` | WhateverGreen | 强制所有显示口 online；LSPCON/HDMI 在唤醒或热插拔后不黑屏 | **建议保留** |
| `revpatch=sbvmm` | RestrictEvents | 让 `softwareupdate` 只提供**全量安装包**（绕过机型/固件校验） | 要 OTA 就留着 |
| `itlwm_cc=CN` | AirportItlwm | 国家码 CN（5 GHz 信道与功率表按 CN 走） | 出国可改成 `US`/`JP` |
| `igfxrpsc=1` | WhateverGreen | RPS 控制相关调参（本项目显示链路实验保留项） | 改前先做 A/B |
| `ipc_control_port_options=0` | 系统 | 修 macOS 15 上部分 App（含 Electron 系）因 IPC 端口限制崩溃 | **建议保留** |
| `-igfxmlr` | WhateverGreen | 与 DP 链路速率（MLR）相关的实验开关，本机 LSPCON 链路上保留 | 改前先做 A/B |
| `alcverbs=1` | AppleALC | 启用 codec verb 处理（耳机口 EAPD 相关） | 与 `VerbStub` 配套；**但它并不能让插拔切换工作**，见 [audio](audio.md) |
| `alcdelay=1000` | AppleALC | codec 初始化延时 1000 ms | 可试 `500` |
| `alctsel=1` | AppleALC | codec 初始化时序调参 | 与上面两项配套 |

> r17 之前这里还有 `-v debug=0x100 keepsyms=1`（调试三件套），已移除：
> 它们只增加开机滚屏与 panic 符号，对功能零贡献，且会拖慢启动。

## 2. DeviceProperties

### 2.1 iGPU `PciRoot(0x0)/Pci(0x2,0x0)`

| 键 | 值 | 说明 |
|---|---|---|
| `AAPL,ig-platform-id` | `00009B3E` | **笔记本**平台 id（UHD 620）。桌面 `07009B3E` 在本机从未成功开机 |
| `device-id` | `9B3E0000` | 真值 `9B41`，伪装成 natively 支持的 `9B3E` |
| `framebuffer-patch-enable` | `01000000` | 打开 framebuffer 补丁总开关 |
| `framebuffer-stolenmem` | `00000002` | 32 MB（**DVMT 实际就是 32 MB，给 64 MB 会开不了机**） |
| `framebuffer-fbmem` | `00009000` | 9 MB |
| `framebuffer-unifiedmem` | `FFFFFFFF` | 显存「显示值」上限 ≈ 4095 MB，只影响系统信息显示，不提升性能 |
| `enable-lspcon-support` | `01000000` | **必需**：HDMI 走 LSPCON 转换 |
| `enable-hdmi20` | `01000000` | **必需**：打开 HDMI 2.0（否则 1440p 高刷上不去） |
| `framebuffer-con1-enable` | `01000000` | 启用 con1 端口补丁 |
| `framebuffer-con1-type` | `00080000` | con1 = HDMI |
| `framebuffer-con1-busid` | `01000000` | con1 bus id = 1 |
| `framebuffer-con1-has-lspcon` | `01000000` | **必需**：con1 是 LSPCON 口 |
| `framebuffer-con1-preferred-lspcon-mode` | `01000000` | LSPCON 工作在 HDMI2.0 模式 |
| `dpcd-max-link-rate` | `0A000000` | DPCD 最大链路速率 0x0A（HBR3 档） |
| `enable-dpcd-max-link-rate-fix` | `01000000` | 配合上一条 |
| `hda-gfx` | `onboard-1` | 与 HDEF 的 `hda-gfx` 配对，保证 HDMI 音频路由 |

> 这 5 个 LSPCON/HDMI2.0 键是「能不能开机 + 能不能高刷」的分水岭。
> 只改 `ig-platform-id` 不加 LSPCON 参数 → 卡 `ASP: initializing bastion sandbox callback`。

### 2.2 声卡 `PciRoot(0x0)/Pci(0x1F,0x3)`

| 键 | 值 |
|---|---|
| `layout-id` | `03000000`（= 3，ALC255） |

## 3. Booter

| 键 | 值 | 原因 |
|---|---|---|
| `EnableWriteUnprotector` | `true` | Insyde 固件必须走这条路线（配合 `RebuildAppleMemoryMap=false`） |
| `RebuildAppleMemoryMap` | `false` | 上面那条的互斥项，二者只能开一个 |
| `SetupVirtualMap` | `true` | 老固件需要的虚拟地址映射 |
| `SyncRuntimePermissions` | `true` | 修 macOS 10.15+ 的 runtime 权限 |
| `ProvideCustomSlide` | `true` | KASLR slide 冲突时兜底 |
| `FixupAppleEfiImages` | `true` | OC 1.0.x 对 macOS 14+ 的 EFI 映像修补（不修会随机卡 `EXITBS`） |
| `DevirtualiseMmio` | `false` | 本机不需要（开了反而可能丢 MMIO 区域） |
| `ProtectUefiServices` | `false` | 同上 |
| `ResizeAppleGpuBars` | `-1` | 不碰 Resizable BAR |

## 4. Kernel

### 4.1 Quirks

| 键 | 值 | 原因 |
|---|---|---|
| `AppleXcpmCfgLock` | `true` | **必需**：BIOS 没解 CFG Lock |
| `DisableIoMapper` | `true` | **必需**：VT-d 保持开启时绕过 DMA 保护 |
| `PanicNoKextDump` | `true` | panic 时不 dump kext 列表，日志更短 |
| `PowerTimeoutKernelPanic` | `true` | 修电源超时导致的 panic（Sequoia 常见） |
| `DisableLinkeditJettison` | `true` | 修 `kextcache`/linkedit 相关的启动失败 |
| `SetApfsTrimTimeout` | `-1` | 交给系统默认（本机 NVMe TRIM 正常，不需要强制） |
| `XhciPortLimit` | `false` | **不做端口限制破解**：靠 15 口上限跑，见 known-issues |
| 其余 | `false` | 未使用 |

### 4.2 启用顺序（14 个）

```
Lilu → VirtualSMC → SMCProcessor → WhateverGreen → AppleALC → VerbStub
→ IntelMausi → NVMeFix → RestrictEvents → CpuTscSync
→ AirportItlwm → IntelBluetoothFirmware → IntelBTPatcher → BlueToolFixup
```

- Lilu 必须最先；VirtualSMC 紧跟。
- `VerbStub` 必须在 `AppleALC` 之后（它 hook `IOHDACodecFunction`）。
- 蓝牙三件套顺序：`IntelBluetoothFirmware` → `IntelBTPatcher` → `BlueToolFixup`。
- `itlwm.kext`（以太网模式）与 `AirportItlwm` **互斥**，当前 itlwm 为 `Enabled=false`。

> ⚠️ 另外 28 个 `Enabled=false` 里，**电池**（`SMCBatteryManager` / `ECEnabler`）、
> **亮度键**（`BrightnessKeys`）、**内置键鼠**（`VoodooPS2Controller` / `VoodooI2C*`）、
> **睡眠**（`HibernationFixup`）是**专门因为「无头骑士」形态才关掉的**，不是它们坏了。
> 原装笔记本要按 [requirements.md §0](requirements.md#0-仅适用于无头骑士形态最重要的一条) 逐项打开并验证。

## 5. Misc

| 项 | 值 | 说明 |
|---|---|---|
| `Boot.PickerMode` | `External` | OpenCanopy 图形菜单 |
| `Boot.PickerAttributes` | `17` | 卷标 + 自定义图标 |
| `Boot.Timeout` | `5` | 5 秒自动进系统 |
| `Boot.HideAuxiliary` | `false` | 辅助项（Recovery / CleanNvram / Shell）默认可见 |
| `Security.ScanPolicy` | `787203` = **`0xC0303`** | 见下方拆解 |
| `Security.SecureBootModel` | `Disabled` | 黑苹果必须 |
| `Security.Vault` | `Optional` | 不校验 vault |
| `Security.DmgLoading` | `Signed` | 只从签名 DMG 恢复 |
| `Security.BlacklistAppleUpdate` | `true` | 屏蔽固件更新载荷（避免 EFI 固件被写坏） |
| `Debug.Target` | `0` | **不再往 ESP 写 `opencore-*.txt`**（r17 改） |
| `Debug.SysReport` | `false` | **不再每次开机生成 SysReport**（r17 改） |
| `Debug.AppleDebug` | `false` | 不显示 Apple 引导日志（r17 改） |
| `Debug.ApplePanic` | `true` | 保留 panic 记录到 NVRAM（排错用） |

### ScanPolicy `0xC0303` 拆解（位定义取自 OpenCore 官方 Configuration.pdf）

| 位 | 值 | 含义 |
|---|---|---|
| bit0 | `0x00000001` | `OC_SCAN_FILE_SYSTEM_LOCK`：只扫描策略里点名的文件系统 |
| bit1 | `0x00000002` | `OC_SCAN_DEVICE_LOCK`：只扫描策略里点名的设备类型 |
| bit8 | `0x00000100` | `OC_SCAN_ALLOW_FS_APFS` |
| bit9 | `0x00000200` | `OC_SCAN_ALLOW_FS_HFS` |
| bit18 | `0x00040000` | `OC_SCAN_ALLOW_DEVICE_SCSI` |
| bit19 | `0x00080000` | `OC_SCAN_ALLOW_DEVICE_NVME` |

效果：启动菜单里**只剩 NVMe/SCSI 上的 APFS/HFS 卷**。
ESP（那个 `NO NAME`）、U 盘、NTFS 分区、恢复分区之外的杂物全部不显示 —— 这就是「菜单干净」的原因。
想临时插 U 盘装系统：把 `ScanPolicy` 改 `0`，或开机按空格看辅助项。

## 6. PlatformInfo（**必须自己改**）

| 键 | 仓库里的值 | 你要改成 |
|---|---|---|
| `SystemProductName` | `MacBookPro16,1` | 保持（换机型大概率开不了机） |
| `SystemSerialNumber` | `W00000000001` | GenSMBIOS 生成的真实格式序列号 |
| `MLB` | `M0000000000000001` | 同上 |
| `SystemUUID` | `00000000-0000-0000-0000-000000000000` | 生成一个（建议与序列号同批） |
| `ROM` | `112233445566` | **有线网卡真实 MAC**（`ifconfig en0` 里的那 6 字节，去掉冒号） |
| `SpoofVendor` | `true` | 保持 |
| `UpdateSMBIOSMode` | `Create` | 保持 |

> 不改的后果：iMessage / FaceTime / App Store 登录异常，甚至触发风控。
> 仓库**故意**只放占位值，避免任何人拿同一套三码互相打架。

## 7. NVRAM

| 键 | 值 | 说明 |
|---|---|---|
| `boot-args` | 见 §1 | `WriteFlash=true`，每次开机由 OC 覆写 |
| `csr-active-config` | `00000000` | **SIP 全开**（不需要 root patch，也不需要关 SIP） |
| `prev-lang:kbd` | `656e2d55533a30` | `en-US:0` |
| `SystemAudioVolume` | `46` | 开机音量 |
| `run-efi-updater` | `No` | 阻止固件更新 |
| `DefaultBackgroundColor` | `00000000` | 启动背景黑（OpenCanopy 下不明显） |

> `Delete` 里同时列了 `boot-args` / `csr-active-config`，保证 NVRAM 里的旧值一定被新值覆盖，
> 不会出现「改了 config 但参数没生效」的经典坑。

## 8. 想改配置时

1. 改完**必须**跑校验：
   ```bash
   ./scripts/verify-efi.sh EFI
   # 等价于
   tools/opencore-release/Utilities/ocvalidate/ocvalidate EFI/OC/config.plist
   ```
2. 一次只改一个变量，重启验收，再改下一个（4K/睡眠/无线这种组合问题一次改多处必然误判）。
3. 改坏了：`backup/` 里有历史 EFI，或直接 `cp -R` 回滚，见 [install.md](install.md)。
