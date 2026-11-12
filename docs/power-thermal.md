# 电源与散热

> ⚠️ 本章的策略是**为无电池的「无头骑士」形态**定的（永不睡眠、不写 sleepimage）。
> 原装笔记本请勿照搬，电池与睡眠需要补 `SMCBatteryManager` + `ECEnabler` + GPRW/PTSWAK，见 [requirements.md §0](requirements.md#0-仅适用于无头骑士形态最重要的一条)。

## 1. CPU 电源管理（XCPM）

| 项 | 值 | 说明 |
|---|---|---|
| `SSDT-PLUG-DRTNIA.aml` | 启用 | 给 `\_SB.PR00` 注入 `plugin-type=1` |
| `machdep.xcpm.mode` | `1` | XCPM 已接管（不是 legacy ACPI_SMC_PlatformPlugin） |
| 最高 P-State | **4900 MHz** | i7-10610U 的单核睿频上限，实测可到 |
| `CpuTscSync.kext` 1.1.2 | 启用 | 4C8T 的 TSC 同步，缺了会随机卡死/时钟漂移 |
| `AppleXcpmCfgLock` | `true` | BIOS 没解 CFG Lock，必须靠 quirk 绕 |

验收命令：

```bash
sysctl machdep.xcpm.mode machdep.xcpm.vectors_loaded_count
pmset -g therm
# 想看实时频率/功耗（需要 root）：
sudo powermetrics --samplers cpu_power -n 3 -i 1000
```

> 注意：`powermetrics` 在黑苹果上有时拿不到 package power（SMC 是虚拟的），
> 拿不到不代表睿频没生效——以 `xcpm.mode=1` + 实际负载跑分为准。

**不需要** `CPUFriend`：i7-10610U 的 `plugin-type=1` 走原生 XCPM 就能出全部 P-State，
`CPUFriend.kext` 在 config 里是 `Enabled=false`。

## 2. PL1 / PL2：改不了，别再试

Comet Lake-U 的长期/短期功耗墙由 **MSR 0x610** 与 EC/BIOS 共同决定。
本机实测：

- MSR 可读，但**写入被固件拦截**（Insyde 在 SMM 里锁了）；
- EC 侧也没有暴露可写的功耗寄存器（`EC` 设备里没有对应 field）；
- 结果：`PL1/PL2` 维持出厂值，**macOS 侧没有任何软件方案能改**。

已知的几条路都走不通：

| 方案 | 结果 |
|---|---|
| `VoltageShift` 改电压/功耗 | 能读到值，写入无效或被 SMM 吃掉 |
| 改 `MSR 0x610` | 被锁，写 0 |
| `CPUFriend` + `CPUFriendDataProvider` | 只能改频率表/EPP，改不了功耗墙 |
| BIOS 里找 PL1/PL2 | U9310X 的 Insyde 菜单**没有暴露**这两项 |

所以本机是「**睿频能上 4.9 GHz，但持续负载会被固件按原厂 PL 限制**」。
这不是 EFI 的问题，换 EFI 也解决不了。

## 3. 睡眠：主动禁用（不是坏了）

这台机器是「无内屏 / 无电池」的模组形态，等价于一台台式机，所以策略是**不睡**：

```bash
pmset -a sleep 0 displaysleep 0 hibernatemode 0 standby 0 autopoweroff 0 powernap 0
```

| 键 | 值 | 原因 |
|---|---|---|
| `sleep` | `0` | 永不系统睡眠 |
| `displaysleep` | `0` | 显示器不自动关（避免唤醒后 LSPCON 黑屏） |
| `hibernatemode` | `0` | **无电池**，写 16 GB `sleepimage` 毫无意义 |
| `standby` / `autopoweroff` | `0` | 同上，避免进入待机写盘 |
| `powernap` | `0` | 关掉后台唤醒（减少 LSPCON 重连） |
| `womp` | `1` | 保留网络唤醒（可选） |

**睡眠/唤醒本身未做完整验收**：没有内屏、没有电池，睡眠链路里最容易出问题的两段
（内屏背光恢复、电池充放电状态机）在本机不存在，测了也不能代表别的 U9310X。
如果要把这块主板当笔记本用，**必须**重新做：

1. `SSDT-GPRW` + `SSDT-PTSWAK`（或 `HibernationFixup`）处理 GPE 唤醒；
2. `hibernatemode 3` 并验证 `sleepimage` 能写能读；
3. 反复 `pmset sleepnow` 20 次看有没有 1/10 概率卡死。

## 4. 散热与温度

- 风扇由 EC 控制，macOS 不参与；`SMCSuperIO` / `SMCDellSensors` 在本机**不启用**
  （富士通 EC 不在支持列表里，开了也读不到风扇转速）。
- 想看温度只能用第三方工具走 SMC 的 CPU 温度键（`SMCProcessor` 已启用，能出 CPU 核心温度）。
- 因为没有内屏、机身敞开，散热条件比原装笔记本好，**长时间满载也不会撞温度墙**。

## 5. 电源相关的已知噪音

| 现象 | 说明 |
|---|---|
| 系统信息里没有「电池」 | 无电池，正常 |
| `pmset -g` 里 `hibernatefile` 仍指向 `/var/vm/sleepimage` | 配置项残留，`hibernatemode 0` 下不会真的写 |
| `UCSI` 相关日志报错 | 无电池 + 无 USB-C PD 设备时的正常噪音 |
| 关机变重启 | 少数 Insyde 固件 + `FadtEnableReset=false` 会这样；本机未复现 |
