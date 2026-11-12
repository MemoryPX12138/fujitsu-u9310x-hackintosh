# 版本历史

> 时间线：2026-11-10 ~ 11-12。目录名对应构建产物（`efi-rXX-*/EFI`）。
> 只有标 ✅ 的版本是「实机开机验收过」的。

## r17 — 2026-11-12 · 发布清理

**目标**：把调试期留下的东西全部清掉，得到一份适合公开的 EFI。

| 项 | 改动 |
|---|---|
| boot-args | 移除 `-v` `debug=0x100` `keepsyms=1`（只影响开机滚屏与 panic 符号，无功能价值） |
| `Misc.Debug.Target` | `67` → `0`（不再每次开机往 ESP 写 `opencore-*.txt`） |
| `Misc.Debug.SysReport` | `true` → `false`（不再生成 SysReport 目录） |
| `Misc.Debug.AppleDebug` | `true` → `false`（不显示 Apple 引导日志） |
| `Misc.Entries` | 删除 1 条 `Enabled=false` 的占位条目 |
| 系统层 | 删除 `/Library/Displays`（HiDPI override 残留，下次登录生效） |
| 电源 | `pmset` 调整为无电池形态：`hibernatemode 0` / `standby 0` / `autopoweroff 0` |
| 产物 | `efi-r17-clean/EFI`，`config.plist` = `01b757f6...`，`ocvalidate` 0 错误 |
| 文档口径 | 更正音频结论：**3.5mm 耳机插拔切换未修复**（只保证喇叭/麦克风） |
| 文档口径 | 全仓库补充**形态限定**：仅适用于「无头骑士」（无屏/无电池/无摄像头），原装笔记本的电池、睡眠、亮度、内置键鼠均未适配 |
| 归档 | 变更前的 ESP 完整备份：`backup/EFI-ESP-20261112-1115`（= r16，`dbda3b73...`） |

**遗留确认**：`bluetoothd` x86_64 签名无效（OTA 只能全量安装），SMBIOS 仍是占位值，
USB 端口未映射，睡眠未验收，PL1/PL2 受固件限制 —— 详见 [known-issues.md](known-issues.md)。

---

## r16 — 2026-11-12 · 显示定型

- ✅ 2560×1440 @ **120 Hz / 24-bit ARGB8888** 定为默认（掉帧修复）。
- 发现根因：30-bit（ARGB2101010）在 1440p120 下把链路预算吃到 ~98%，切 App 动画掉帧。
- 试过 1440p144 @24-bit 也能跑（约 98% 预算），但余量太薄，未采用。
- 试过 HiDPI 1280×720 / 1600×900 / 1920×1080：**60 Hz 也掉帧** → 写 override 又删掉，
  结论是 UHD 620 填充率不够，不是设置问题。
- 全量安装 15.8.3 (24H241) 完成。
- 结论落地：`displayplacer` + LaunchAgent 持久化 24-bit/120Hz。

## r15 — 2026-11-11 · OpenCanopy

- ✅ 启用 `PickerMode=External` + `OpenCanopy.efi` + `Resources/`，图形化启动菜单。
- `ScanPolicy=0xC0303`（只扫 NVMe/SCSI 上的 APFS/HFS）→ 菜单里的 `NO NAME`（ESP）消失。

## r14 — 2026-11-11 · 音频定型

- ✅ `layout-id=3` + `alcid=3`，ALC255 **喇叭/麦克风**可用。
- ⚠️ 当时判断「耳机口可用」是**错的**：3.5mm 插拔切换从未真正跑通，r17 已改口径，见 [known-issues #0](known-issues.md#0-35mm-耳机插拔切换未修复)。
- 引入 `VerbStub.kext` 1.0.4 + AppleALC verb 参数（`alcverbs=1` / `alcdelay=1000` / `alctsel=1`）。
- 装 `ComboJack` / `hda-verb` 作排错工具（无常驻进程）。

## r13 — 2026-11-11 · 合并

- 把显示链路（LSPCON）与音频/蓝牙/无线三块合并到同一份 config，✅ 开机验收。

## r12 — 2026-11-11 · GUI / VerbStub 两个分支

- `efi-r12-gui`：OpenCanopy 试验。
- `efi-r12-verbstub`：音频 verb 试验（耳机口）。

## r11 — 2026-11-11 · 迭代测试

- `r11-test` / `r11b` / `r11c` / `r11d` / `r11e-native`：逐项试 USBX、AWAC、PLUG、蓝牙三件套的组合。
- ✅ `r11e-native` 稳定。

## r10 — 2026-11-11 · 显存参数

- `r10-2g`：`unifiedmem` = 2048 MB（未采用）。
- ✅ `r10-4g`：`unifiedmem=0xFFFFFFFF` + `stolenmem=32MB` + `fbmem=9MB`，长期基线。

## r9 — 2026-11-10 · 失败与存疑

- `r9a`：`stolenmem=64MB` + `fbmem=18MB` → **不开机**（超 DVMT 32 MB）。
- `r9b`：`stolenmem=32MB`（与 r10 只差 `unifiedmem`）→ 当时报不开机，**存疑**（大概率是复制/NVRAM 残留）。

## r8 — 2026-11-10 · 无线备选

- `efi-stablewifi`：itlwm（以太网模式）+ HeliPort 方案，未采用（本机选 AirportItlwm 原生菜单）。

## r7 — 2026-11-10 · 首次成功

- ✅ **R7-CLONE**：参考 EFI 的显示参数（LSPCON 五键 + `con1=HDMI` + `00009B3E`）+ `MacBookPro16,1`
  + 自制 `SSDT-PLUG/AWAC/USBX` → 首次成功开机并完成安装。

## r5 / r6 — 2026-11-10 · 早期失败

- `sequoia-module` 方案（`Macmini8,1` + `07009B3E` + 无 LSPCON）→ 卡
  `ASP: initializing bastion sandbox callback`。
- 加 `-igfxvesa` 仍卡同一行 → 证明瓶颈在机型/Booter，不只是显卡驱动。
- 这些失败直接催生了 r7 的正确参数。

---

## 版本命名约定

```
efi-r<N>-<关键词>/
├─ EFI/            ← 完整可启动树
└─ （可选）notes   ← 这一版为什么这么做
```

- `r<N>` 递增，不复用；
- 关键词写「这一版的主变量」，例如 `layout`（音频）、`gpu`（显示）、`clean`（发布清理）；
- **失败版本也保留**，它们是 `troubleshooting.md` 的证据来源。
