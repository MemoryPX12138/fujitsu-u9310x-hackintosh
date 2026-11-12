# 构建、校验与发布

## 1. 这个 EFI 是怎么来的

不是「下载别人的 EFI 改两下」，而是：

1. 从 **OpenCore 1.0.8 官方 `Docs/Sample.plist`** 起步；
2. 按本机 DSDT/硬件逐项覆盖需要的键（只改必要项，没提到的保持官方默认，避免漏键）；
3. kext 按 **固定版本** 放入 `EFI/OC/Kexts`，config 里的 `BundlePath` 与实际文件一一对应；
4. 每一轮用 `ocvalidate` 校验 → 打包 → 实机开机验收；
5. 验收通过的整棵 EFI 树直接作为产物（**产物即源码**，不做二次生成，减少「脚本和实物不一致」的坑）。

`scripts/make-release.py` 负责最后一步的**发布化**（去调试参数/调试输出），
它是幂等的，跑两遍结果一样。

## 2. 版本锁定

| 组件 | 版本 | 备注 |
|---|---|---|
| OpenCore | **1.0.8 RELEASE** | `REL-108-2026-09-27`，配套 `ocvalidate` 必须同版本 |
| Lilu | 1.7.2 | |
| VirtualSMC | 1.3.8 | 只用 `VirtualSMC` + `SMCProcessor` |
| WhateverGreen | 1.7.1 | LSPCON / HDMI2.0 |
| AppleALC | 1.9.8 | layout 3 |
| VerbStub | 1.0.4 | 第三方（`com.XPS.VerbStub`） |
| IntelMausi | 1.0.8 | |
| NVMeFix | 1.1.3 | |
| RestrictEvents | 1.1.6 | `revpatch=sbvmm` |
| CpuTscSync | 1.1.2 | |
| AirportItlwm | 2.4.0（Sequoia 构建） | laobamac fork |
| IntelBluetoothFirmware / IntelBTPatcher | 2.5.1 | zxystd |
| BlueToolFixup | 2.7.2 | Acidanthera |

> **不要随意升级 kext**。这套版本是「能开机 + 全部功能可用」的组合，
> 升级前先复制一份 EFI 出来做对照实验。

## 3. 校验（改完必跑）

```bash
./scripts/verify-efi.sh ./EFI
```

它会做 6 件事：

1. 结构（`BOOT/BOOTx64.efi`、`OC/OpenCore.efi`、`config.plist`、`ACPI/Kexts/Drivers` 目录）；
2. `config.plist` 能否解析；
3. **引用完整性**：config 里点名的 ACPI / Driver / 启用 kext / Tools 是否真的存在；
4. 发布卫生：boot-args 有没有残留 `-v`、`Target` 是不是 0、SMBIOS 是不是占位值；
5. `ocvalidate`（`tools/ocvalidate/ocvalidate`，OpenCore 1.0.8 配套版）；
6. 打印 `config.plist` 的 SHA-256、EFI 体积、kext 数量。

单独跑 ocvalidate：

```bash
./tools/ocvalidate/ocvalidate ./EFI/OC/config.plist
# 必须输出：No issues found.
```

> ocvalidate 是**版本敏感**的：1.0.8 的校验器遇到 1.0.9 的 config 会报一堆假错。
> 仓库里带的就是 1.0.8 配套版。

## 4. 从调试版生成发布版

```bash
# 调试版（带 -v debug=0x100 keepsyms=1、Target=67、SysReport=true）
python3 scripts/make-release.py --in ./EFI-work --out ./EFI
```

它会：

| 动作 | 前 | 后 |
|---|---|---|
| boot-args | `-v debug=0x100 keepsyms=1 ...` | 去掉这三个 token |
| `Misc.Debug.Target` | `67` | `0` |
| `Misc.Debug.SysReport` | `true` | `false` |
| `Misc.Debug.AppleDebug` | `true` | `false` |
| `Misc.Entries` | 含 `Enabled=false` 的占位条目 | 删除占位条目 |

**不动** DeviceProperties / Quirks / kext 列表 / SMBIOS —— 这些是功能性的，
发布版和调试版必须完全一致。

可复现性检查（本仓库实测）：

```bash
python3 scripts/make-release.py --in <r16 调试版 EFI> --out /tmp/r17
shasum -a 256 /tmp/r17/OC/config.plist
# 01b757f65211b656c89e9edddb13eba23ea54d3fd733785b49d21a5be9fd2e04
```

和仓库里的 `EFI/OC/config.plist` **逐字节一致**（不是"语义一致"，是同一个 SHA）。

## 5. 打包与发布

```bash
# 目录树直接进 git（推荐，便于 review 与 diff）
git add EFI && git commit -m "EFI: r17 clean release"

# 同时给一个可直接下载的 zip
cd . && zip -r -X EFI-u9310x-r17.zip EFI -x "*.DS_Store"
shasum -a 256 EFI-u9310x-r17.zip > EFI-u9310x-r17.zip.sha256
```

发布说明模板：

```
## r17 (2026-11-12)
- 移除调试启动参数 -v debug=0x100 keepsyms=1
- OpenCore 调试输出关闭（Target=0 / SysReport=false / AppleDebug=false）
- 删除 HiDPI override（/Library/Displays）
- 无电池形态电源策略（hibernatemode 0 / standby 0）
- config.plist SHA-256: 01b757f6...
```

## 6. 仓库里放什么、不放什么

| 放 | 不放 |
|---|---|
| `EFI/`（可开机产物，57 MB） | `dist/` 历史测试包（1 GB） |
| 文档、脚本、`tools/ocvalidate` | 安装镜像 / `dl/`（本机 16 GB） |
| 失败实验的**结论** | 个人三码、MAC、UUID、IP、SSID |
| ACPI 的 `.aml` | `logs/acpi/*.dsl`（含机器唯一标识，且 2 MB+） |

`.gitignore` 已经把大目录排除。**提交前先跑一遍**：

```bash
grep -rInE "W00000000001|112233445566|[0-9A-Fa-f]{2}(:[0-9A-Fa-f]{2}){5}" . --exclude-dir=.git
```

占位值出现是正常的（仓库故意保留 `W00000000001`），**真实三码/MAC 出现就必须删掉再提交**。

## 7. 提交信息约定（可选但推荐）

```
efi:     只改 EFI/config
docs:    只改文档
fix:     修 bug（附现象）
test:    实验结果（不管成功失败都值得记）
```

失败实验也要提交——`docs/troubleshooting.md` 里每一条都值钱。
