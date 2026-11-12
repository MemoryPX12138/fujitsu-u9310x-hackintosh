# 网络：AX201 无线 + 蓝牙 + 有线

## 1. 有线：I219-LM

| 项 | 值 |
|---|---|
| PCI | `8086:0d4e` |
| 驱动 | IntelMausi 1.0.8 |
| 接口 | `en0` |
| MAC | 真实 MAC（GenSMBIOS 的 `ROM` 就用它，6 字节 hex，去掉冒号） |

有线是**最稳的一条**：不需要任何 boot-arg，也没有已知断流问题。建议日常把它当主链路，
无线只做备份——这也是 `ROM` 取有线 MAC 的原因。

## 2. 无线：AX201（CNVi）

| 项 | 值 |
|---|---|
| PCI | `8086:02f0`（Comet Lake CNVi，板载，**不可更换**） |
| 驱动 | **AirportItlwm 2.4.0**（laobamac 的 Sequoia 构建，`com.zxystd.AirportItlwm`） |
| 固件 | `itlwm: 2.4.0_7204c69  fw: 68.01d30b0c.0` |
| 接口 | `en1` |
| 实测 | 802.11ac / 5 GHz / 160 MHz / **1300 Mbps**，WPA2-Personal |
| 国家码 | `itlwm_cc=CN`（boot-arg） |

笔记：

- AirportItlwm 是**原生菜单**方案（系统右上角 Wi-Fi 图标、系统设置里直接选网），
  不是 itlwm + HeliPort 那种第三方 App 方案。本机采用的是前者。
- `AirportItlwm` 与 `itlwm.kext` **互斥**：config 里 itlwm 是 `Enabled=false`，别同时开。
- 显示的 MAC 是**本地管理地址**（`02:` 开头那一类），不是厂牌 MAC。
  所以三码里的 `ROM` **必须用有线网卡的 MAC**，别抄这个。

### 能做什么 / 不能做什么（AX201 的硬限制）

| 功能 | 状态 | 原因 |
|---|---|---|
| Wi-Fi 上网 | ✅ | — |
| 个人热点连接 / 2.4G+5G | ✅ | — |
| AirDrop **发送** | ⚠️ 部分可用 | 缺 AWDL 的完整实现 |
| AirDrop **接收** | ❌ | 同上 |
| 接力 Handoff / 通用剪贴板 | ⚠️ 时好时坏 | 依赖 AWDL |
| 随航 Sidecar / 通用控制 | ❌ | 依赖 AWDL + 连续互通 |
| Apple Watch 解锁 | ❌ | 依赖 AWDL |
| 隔空播放接收（AirPlay 接收端） | ❌ | 依赖 AWDL |

**如果一定要这些功能**：换 BCM94360NG / DW1560 之类免驱卡。U9310X 的 CNVi 是板载，
换卡要动 M.2 + 天线，且本机已装进模组，实际不可行。替代方案：`LocalSend`（跨平台文件互传）。

## 3. 蓝牙：AX201 BT

| 项 | 值 |
|---|---|
| USB | `8087:0026`（Intel），Transport: USB，Built-In: Yes |
| 驱动三件套 | IntelBluetoothFirmware 2.5.1 → IntelBTPatcher 2.5.1 → BlueToolFixup 2.7.2 |
| 固件 | `v8787 c8787` |
| 系统识别 | `Chipset: THIRD_PARTY_DONGLE`，Vendor ID 显示 `0x004C (Apple)` —— **正常现象**，是 BlueToolFixup 的伪装 |
| 服务 | HFP / AVRCP / A2DP / HID / Braille / LEA / AACP / GATT / SerialPort |

实测可用：蓝牙键鼠、蓝牙耳机（A2DP）、BLE 设备。
**不可用**：基于 BLE 的「连续互通」类功能（同上，缺 AWDL 生态）。

### 已知问题：`bluetoothd` 被改过

系统里的 `/usr/sbin/bluetoothd` **x86_64 切片签名无效**（arm64e 切片正常），
导致 macOS 更新只能全量安装。这条不影响蓝牙功能，只影响 OTA 增量包。

证据与修复路径见 [known-issues.md §1](known-issues.md#1-bluetoothd-被修改导致-ota-只能全量安装)。

## 4. 那个奇怪的 `pci-serial22`（PPP）

`系统设置 → 网络` 里会出现一个 `PCI Serial Adapter (22)` / PPP 接口，这是
Comet Lake LPSS UART 被 macOS 当成调制解调器枚举的结果，**不影响联网**，属于显示噪音。
想彻底消掉需要改 DeviceProperties 屏蔽对应 PCI 设备（未做，收益太低）。

## 5. 排错

```bash
# 无线
kextstat | grep -i airportitlwm
ifconfig en1
system_profiler SPAirPortDataType | head -40
log show --last 5m --predicate 'eventMessage CONTAINS "itlwm"' | tail -20

# 断流时先看这个（deauth / beacon lost / scan 超时）
log show --last 10m --predicate 'process == "kernel" AND eventMessage CONTAINS[c] "itlwm"' | tail -40

# 蓝牙
kextstat | grep -Ei "IntelBluetooth|BlueTool|IntelBTPatcher"
system_profiler SPBluetoothDataType
```

| 现象 | 处理 |
|---|---|
| 开机后 Wi-Fi 图标灰、要等一会才连上 | `itlwm_cc=CN` 已在用；仍出现就改用有线优先，或换 `itlwm + HeliPort` 方案 |
| 5 GHz 扫不到 | 国家码不对：`itlwm_cc` 改成实际所在国 |
| 蓝牙键鼠开机时连不上 | 正常，进系统后 3–10 秒才恢复；需要 BIOS 级键鼠请用 USB |
| 蓝牙耳机有声音但麦克风不可用 | A2DP 独占，切 HFP 才能用麦（音质会降） |
