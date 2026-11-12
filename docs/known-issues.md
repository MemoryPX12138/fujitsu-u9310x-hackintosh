# 缺陷与限制清单

> 分四类：**A. 需要你动手/尚未解决的**、**B. 能解决但没做/不值得做**、**C. 硬件层面的死路**、**D. 纯外观**。
> 每条都带「证据 / 影响 / 怎么办」，不接受「据说不行」。
>
> ⚠️ **形态限定**：本 EFI 只服务「无头骑士」（无内屏 / 无电池 / 无摄像头）。
> 原装笔记本的**电池、睡眠、内屏亮度、内置键盘触控板、合盖**等功能**未适配**，
> 不在这份清单里逐条列，统一见 [requirements.md §0](requirements.md#0-仅适用于无头骑士形态最重要的一条)。

---

## A. 需要你动手才能解决的

### 0. 3.5mm 耳机插拔切换**未修复**

**现象**

- 插上 3.5mm 耳机后，`系统设置 → 声音 → 输出` 里**不会多出 `Headphones`**，
  声音继续从内置喇叭出来；
- `system_profiler SPAudioDataType` 只有 `Built-in Output / Output Source: Internal Speakers`，
  插拔前后完全一样；
- 手动用 `hda-verb` 强开耳机功放偶尔能响一次，**重启或重插即失效**，不能当方案。

**证据（本机实测）**

```
$ system_profiler SPAudioDataType | grep -E "Built-in|Output Source|Input Source"
        Built-in Microphone:
          Input Source: Internal Microphone
        Built-in Output:
          Output Source: Internal Speakers        ← 没有 Headphones

$ kextstat | grep -i verbstub
com.XPS.VerbStub (1.0.4)                          ← 已加载
$ ioreg -rn HDEF | grep layout-id
"layout-id" = 3                                   ← 生效
```

即：**驱动/layout/verb 参数全部在位，插拔检测这条链路仍然不通**。

**影响**

- 耳机口不能当日常输出用（每次都要手动折腾，且随时失效）；
- 不影响喇叭、麦克风、蓝牙耳机、HDMI 音频。

**为什么难**（三段链路，第三段是空的）

| 段 | 内容 | 状态 |
|---|---|---|
| ① | codec pin `0x21` 配成 HP out + jack detect（AppleALC layout 3） | ✅ |
| ② | 插拔时 codec 通过 unsolicited response 上报事件 | ❓ 未验证 |
| ③ | 有进程监听事件并切换默认输出 + 静音喇叭 | ❌ **没有**（ComboJack 无常驻守护进程） |

**怎么办**

1. 临时：用 USB / USB-C 声卡，或蓝牙耳机；
2. 想真修：先验证 ②，再补 ③ —— 完整步骤见 [audio.md §5](audio.md#5-真要修好需要按这个顺序做)；
3. 在修好之前，**不要**再靠反复换 `layout-id` 试图解决（本项目已试过 9 个 layout，只有 3 能出声）。


### 1. `bluetoothd` 被修改，导致 OTA 只能全量安装

**现象**

- 系统更新里下载**增量包**一定失败，报 `Full replacement is required`；
- 只有「全量安装包」（约 12–15 GB）能装成功。

**证据（本机实测）**

```bash
$ codesign --verify --verbose=2 /usr/sbin/bluetoothd
/usr/sbin/bluetoothd: invalid signature (code or signature have been modified)
In architecture: x86_64

$ codesign --verify --arch arm64 /usr/sbin/bluetoothd
（无输出 = 通过）
```

软件更新留下的错误原文（`/Library/Preferences/com.apple.SoftwareUpdate`）：

```
MSU_ERR_FILESYSTEM_DOESNT_VERIFY
'./usr/sbin/bluetoothd' does not verify
contents of '/usr/sbin/bluetoothd' don't match bom (9b69595b vs 5a62fcc4)
SUMacControllerErrorIndicationsMask = 2  → FullReplacementRequired
```

**结论**：`bluetoothd` 的 **x86_64 切片被改过**（arm64e 切片完好），
系统 BOM 校验不过 → 更新器拒绝打增量补丁，只能整包替换。

**影响**

- 只影响「增量 OTA」，**不影响任何功能**：蓝牙键鼠、A2DP、BLE 都正常；
- 每次升级要下 12–15 GB 全量包，装完还要重打 EFI（EFI 在 ESP，不受影响）。

**怎么办（三选一）**

1. **就这样用**（推荐）：`revpatch=sbvmm` 本来就让系统只提供全量包，装完照常。
   本项目至今的 15.8.3 就是这么装的。
2. **还原原始 bluetoothd**（需要同版本 15.8.3 / 24H241 的安装镜像）：
   ```bash
   # 从 InstallAssistant 的 SharedSupport 里取出原始文件，然后：
   csrutil authenticated-root disable         # 1. Recovery 里关掉 SSV
   sudo mount -uw /System/Volumes/Data        # 2. 可写挂载
   sudo cp /path/to/pristine/bluetoothd /usr/sbin/bluetoothd
   sudo chown root:wheel /usr/sbin/bluetoothd && sudo chmod 755 /usr/sbin/bluetoothd
   sudo bless --folder /System/Library/CoreServices --bootefi --create-snapshot   # 3. 重新封卷
   csrutil authenticated-root enable          # 4. Recovery 里再打开
   ```
   风险：重封卷失败会开不了机，务必先做 Time Machine。
3. **干净重装**：用 15.8.3 全量安装盘抹盘重装，不施加任何 bluetoothd 补丁。

> 为什么会变成这样：早期为了让 Intel 蓝牙在 Sequoia 上工作，曾对 `bluetoothd` 打过二进制补丁。
> 现在蓝牙已由 `IntelBluetoothFirmware + IntelBTPatcher + BlueToolFixup` 三件套接管，
> **不需要**再改系统文件。这条补丁属于历史遗留。

---

### 2. SMBIOS 是占位值（iMessage / App Store 不可用）

**证据**：`system_profiler SPHardwareDataType` → `Serial Number (system): W00000000001`，
`ROM: 112233445566`，`SystemUUID: 00000000-...`。

**影响**

- iMessage / FaceTime / App Store 登录异常或直接被拒；
- 「查找我的 Mac」不可用；
- 不影响系统更新（更新走 `revpatch=sbvmm`，与三码无关）。

**怎么办**：GenSMBIOS 生成 `MacBookPro16,1` 三码，写进 `PlatformInfo → Generic`：

| 键 | 取值 |
|---|---|
| `SystemSerialNumber` | GenSMBIOS 生成 |
| `MLB` | 同上 |
| `SystemUUID` | 同上（或随机 UUID） |
| `ROM` | **有线网卡真实 MAC 的 6 字节 hex**（本机 `xx:xx:xx:xx:xx:xx` → `xxxxxxxxxxxx`） |

⚠️ 别抄别人的三码——会互相踢下线，也可能被 Apple 风控。

---

### 3. USB 端口映射没做（26 口 → 只暴露 14 口）

**证据**

```bash
$ ioreg -r -c AppleUSBXHCIPCI -w0 | grep -oE "HS[0-9]+|SS[0-9]+|USR[0-9]+" | sort -u
HS01..HS10  SS01  SS02  USR1  USR2      # 共 14 个
```

控制器 `8086:02ed` 实际有 **26 个端口**（HS01–HS14 / SS01–SS10 / USR1 / USR2），
macOS 上限 15 个，`XhciPortLimit=false` 时按枚举顺序取前 15 个。

**影响**

- 部分 USB-C / 后置口**可能完全没反应**（取决于它们排在第几位）；
- 本机用 VIA/Genesys Hub 外接键鼠，实测这些口都能用，所以没被当回事；
- 但**如果你插某个口没反应，先怀疑这里**。

**怎么办**：用 USBToolBox（Windows 或 macOS 版）在**本机**扫一遍，生成 `USBPorts.kext`
（或 `UTBMap.kext`），只保留实际用到的 15 个口，加进 config 的 Kexts 并启用。
参考 EFI 里有个同系列的 `UTBMap.kext` 可以当起点，但**必须逐口核对**。

---

## B. 能解决但没做 / 不值得做

### 4. 睡眠 / 唤醒未验收

当前 `pmset sleep 0`，从不睡眠。见 [power-thermal.md §3](power-thermal.md#3-睡眠主动禁用不是坏了)。
无内屏无电池的模组形态下，睡眠链路的两个主要故障点不存在，测了也不代表别的机器。

### 5. 雷电 3 热插拔（JHL7540）

- 控制器在 `SSDT (INSYDE TbtTypeC)` 里而不是 DSDT，通用 `SSDT-TB3` 模板对不上；
- 现状：**没做 SSDT，没验证过任何雷电设备**；
- 想在 macOS 下用雷电扩展坞，需要按本机 ACPI 手写 SSDT + 验证 NHI 的 `_DSM`，工作量大、收益低。

### 6. HiDPI 缩放

已实测三档全部掉帧（1280×720 / 1600×900 / 1920×1080，60Hz 也掉）。
override 已删除，系统设置里不会再出现这些档位。见 [display.md §4](display.md#4-hidpi试过放弃已清理)。

### 7. 30-bit 高刷 / 可变刷新率

- 30-bit 最高 120 Hz（144 需要 ~733 MHz > 链路 600 MHz）；
- macOS 的 Intel 驱动**不支持 FreeSync/VRR**，显示器支持也没用。

### 8. 无用 kext 占体积

`EFI/OC/Kexts` 里有 33 个 bundle，只启用 14 个。剩下 19 个（VoodooPS2 / VoodooI2C / Brcm 系列 /
CPUFriend / HibernationFixup / itlwm…）是「留着方便切换」的备胎，**不加载、不占内存**，只占 57 MB 里的约 20 MB。
想瘦身就把 `Enabled=false` 的条目连同目录一起删掉，`config.plist` 里对应条目也删（或留着，OC 会跳过）。

### 9. 那个 PPP 串口（`pci-serial22`）

LPSS UART 被枚举成调制解调器，网络设置里多一个灰项。不影响联网，未处理。

### 10. 从 macOS 内部写 `nvram boot-args` 会被 SIP 拒绝

`csr-active-config=00000000`（SIP 全开），所以 `sudo nvram boot-args=...` 报
`(iokit/common) not permitted`。
**这是设计如此**：boot-args 由 OpenCore 在开机时按 config 覆写（`WriteFlash=true` + `Delete` 列表），
改 config 就够了，不需要也不应该从系统里改 NVRAM。

---

## C. 硬件层面的死路（别再花时间）

### 11. SD 读卡器（O2 Micro OZ777，`1217:8520`）

macOS **没有**任何可用驱动（Realtek 系列有第三方驱动，O2 Micro 没有）。
插卡无反应是必然的，不是配置问题。

### 12. AirDrop 接收 / 随航 / 通用控制 / Apple Watch 解锁

AX201 是 CNVi 网卡，**缺 AWDL 的完整实现**。这些功能全部依赖 AWDL。
发送方向的 AirDrop 偶尔可用，接收方向从来不行。替代：LocalSend / 局域网 SMB。

### 13. 摄像头 / 内屏 / 电池

物理不存在（模组化成无屏无电池无摄像头）：

- 内屏：`i915` 日志 `disabling eDP` → 不需要 PNLF、不需要背光；
- 电池：只有 AC + UCSI → `SMCBatteryManager` / `ECEnabler` 保持禁用；
- 摄像头：USB 列表里没有。

### 14. `igfxfw=2` 必死机

强制加载 GuC 固件在本机 UHD 620 + LSPCON 组合上直接挂死。**永久排除**，不要「再试一次」。

### 15. macOS 26（Tahoe）没有 Intel 无线驱动

AirportItlwm 只到 Sequoia；26 上只能 OCLP root patch 注回旧驱动，**每次系统更新都会失效**。
本项目锁定 macOS 15.x。

---

## D. 纯外观问题（不影响功能，改不改随意）

| 现象 | 原因 | 想改的话 |
|---|---|---|
| 显卡名显示 `Intel HD Graphics CFL CRB` | 没人给 `model` 属性 | 在 iGPU DeviceProperties 加 `model = "Intel UHD Graphics 620"`（纯显示，未在本机验证） |
| 处理器速度显示 `2.3 GHz` | SMBIOS `MacBookPro16,1` 的模板值（真实 1.8 GHz 基频） | 不通过 SMBIOS 改就得动 `PlatformInfo` 自定义，收益为零 |
| 显示器连接类型显示 `Thunderbolt/DisplayPort` | 前面是 LSPCON（DP→HDMI） | 无解，也不影响 |
| 启动菜单偶尔出现 `NO NAME` | `ScanPolicy` 已挡掉 ESP，出现说明你在按空格看辅助项 | 正常 |

---

## E. 一句话总结

这台机器**日常可用**：显示 1440p120、喇叭/麦克风、有线/无线/蓝牙、NVMe、睿频都正常。
**两个明确的缺口**：① 3.5mm 耳机插拔切换未修复（插耳机不会切输出，需 USB 声卡或蓝牙耳机替代）；
② `bluetoothd` 被改过 → 系统升级只能走全量包。
其余不能用的部分是**硬件决定的**（SD 卡、AirDrop 接收、雷电热插拔）或**需要你自己补的**（三码、USB 映射）。
