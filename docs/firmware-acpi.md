# 固件与 ACPI

## 1. 固件

| 项 | 值 |
|---|---|
| 厂商 | **Insyde** |
| OEM ID | `FJNB2DB`（富士通定制） |
| DSDT | 287,634 字节（反编译后 `DSDT.dsl` 约 2 MB） |
| 表数量 | 22 张（1 DSDT + 21 SSDT） |
| 采集方式 | Linux live 下 `acpidump -b`，`iasl` 反编译 |

反编译产物在本机 `logs/acpi/acpi2/`（未随仓库分发，含机器唯一标识）。

## 2. 三条硬结论（决定了整份 EFI 的写法）

### 2.1 EC 已经叫 `EC` —— **绝对不要加载 SSDT-EC**

```
\_SB.PCI0.LPCB.EC   PNP0C09   IO 0x62/0x66   GPE 0x22
```

macOS 需要 `EC` 这个名字才认（否则 AppleACPIEC / 电池 / 热区全废）。本机固件**本来就是 `EC`**，
额外塞一个 `SSDT-EC` 反而会撞名 → ACPI 报错、开机随机卡住。

同理：**没有电池**，`SMCBatteryManager.kext` / `ECEnabler.kext` 保持 `Enabled=false`。

### 2.2 时钟：`STAS` 是 FieldUnit，不是 Integer

DSDT 同时定义了 `AWAC`(ACPI000E) 与 `RTC`(PNP0B00)，由 NVS 字段 `STAS` 决定谁生效：

- `STAS = 0` → 用 AWAC（现代固件默认）
- `STAS = 1` → 用 legacy RTC（macOS 需要这个）

Dortania 的通用 `SSDT-AWAC.aml` 把 `STAS` 声明成 `IntObj`，**在本机类型不匹配**（编译能过、运行不生效）。
本机用的是定制版：

```asl
DefinitionBlock ("", "SSDT", 2, "AWAC", "AWAC", 0)
{
    External (STAS, FieldUnitObj)          // ← 关键：FieldUnitObj
    Scope (\_SB)
    {
        If (_OSI ("Darwin"))
        {
            STAS = One
        }
    }
}
```

编译产物 74 字节，`strings` 可以看到 `\STAS` / `\_SB_` / `_OSI` / `Darwin` 四段，说明结构正确。

### 2.3 CPU 对象在 `\_SB.PR00`

`Processor (PR00..PR0F)` 位于 `\_SB`（不在 `\_PR`），所以用标准 **`SSDT-PLUG-DRTNIA.aml`**
（Dortania 那份多路径探测版，同时声明 `\._SB_CPU0` / `\._PR_CPU0` / `\._PR_C000` / `\._PR_P000` / `\._SB_PR00`）
正好命中。产物 693 字节，`strings` 里能看到上述五条路径。

作用：给 `\_SB.PR00` 注入 `plugin-type = 1`，让 `X86PlatformPlugin` 接管 → XCPM 生效、睿频可用。

## 3. 当前启用的 ACPI 表

| 文件 | 启用 | 作用 |
|---|---|---|
| `SSDT-PLUG-DRTNIA.aml` | ✅ | CPU 电源管理（plugin-type=1） |
| `SSDT-USBX.aml` | ✅ | USB 供电属性（`kUSBSleepPowerSupply` 等），让 USB 设备在睡眠/唤醒时不被断电 |
| `SSDT-AWAC.aml` | ✅ | 强制 `STAS=1`，把 RTC 从 AWAC 抢回来 |
| `SSDT-XOSI.aml` | ❌ | 本机没有 I2C 触摸设备，加载无意义；配套的 `_OSI → XOSI` ACPI Patch 也保持关闭 |

**没有** `SSDT-PNLF`（无内屏）、**没有** `SSDT-EC`（见 2.1）、**没有** `SSDT-TB3`（雷电未做）、
**没有** `SSDT-GPRW/UPRW/PTSWAK`（睡眠未验收，暂不引入额外变量）。

## 4. ACPI Quirks

| 键 | 值 | 原因 |
|---|---|---|
| `ResetLogoStatus` | `true` | Insyde 固件会在启动时画厂牌 logo，挡 OpenCanopy；置 true 让 OC 清掉 |
| `FadtEnableReset` | `false` | 本机 reset 由 OC 处理，不需要改 FADT |
| `NormalizeHeaders` | `false` | 表头正常，不需要重写 |
| `RebaseRegions` | `false` | 未做 region 重定位 |
| `SyncTableIds` | `false` | 未遇到表 ID 冲突 |

`ACPI → Patch` 里只有一条 `_OSI → XOSI`，**`Enabled=false`**（与 `SSDT-XOSI.aml` 配套，两个都关）。

## 5. 固件层面的已知怪癖

1. **DVMT 实际值 32 MB**。`framebuffer-stolenmem=32MB` 刚好卡在边界上，**64 MB 会开不了机**。
2. **CFG Lock 未解锁**（BIOS 里没有选项），靠 `Kernel → Quirks → AppleXcpmCfgLock=true` 绕过。
3. **VT-d 保持开启**，靠 `DisableIoMapper=true` 规避 DMA 保护问题（比进 BIOS 关 VT-d 更省事）。
4. **雷电控制器不在 DSDT**，而在 `SSDT (INSYDE TbtTypeC)` 里，因此通用 SSDT-TB3 模板对不上，
   目前完全没做热插拔。
5. **没有内屏**：`i915` 日志明确 `disabling eDP`，所以背光、PNLF、`backlight-level` 全都不需要。

## 6. 复核命令

```bash
# 当前加载了哪些 ACPI 表（含 OC 注入的 SSDT）
ioreg -lw0 | grep -i "ACPI" | head
# 或者
log show --last 5m --predicate 'eventMessage CONTAINS "ACPI"' | grep -i ssdt | head

# 确认 CPU 电源管理接上了
sysctl machdep.xcpm.mode          # 1 = XCPM 生效
sysctl machdep.xcpm.vectors_loaded_count
```
