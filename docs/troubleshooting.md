# 失败档案：别再重复踩

> 这一页比「成功配置」更值钱。所有条目都是**本机真实跑过**的，不是猜的。

## 1. 成功的基线（三次跃迁）

| 编号 | 改了什么 | 结果 |
|---|---|---|
| **R7-CLONE** | 参考 EFI 的显示参数（LSPCON 全开 + `con1=HDMI` + `00009B3E`）+ 它的 4 个 Booter 参数 + `MacBookPro16,1` + 自制 `SSDT-PLUG/AWAC/USBX` | **首次成功开机并完成安装** |
| **R10-4GB** | R7 + `stolenmem=32MB` / `fbmem=9MB` + `unifiedmem=0xFFFFFFFF` + `itlwm_cc=CN` | 长期基线 |
| **R17** | R16 + 去调试启动参数 + 关 OC 调试输出 + 删 HiDPI override + 无电池电源策略 | **当前发布版** |

## 2. 失败清单

### 2.1 显示相关

| 实验 | 做法 | 现象 | 归因 |
|---|---|---|---|
| `sequoia-module` | `Macmini8,1` + `07009B3E`（桌面平台）+ `stolenmem=19MB`，**无 LSPCON 参数** | 卡 `ASP: initializing bastion sandbox callback`，光标闪 | 显示链路（LSPCON/平台 id）与机型组合不对 |
| TEST-A | 上面那套 + `-igfxvesa`（直接关核显驱动） | **仍卡同一行** | 说明瓶颈不只是显卡驱动 → 指向 Booter/机型 |
| TEST-B | 只把平台 id 换 `00009B3E`，仍无 LSPCON 参数 | 卡住 | **LSPCON 那 5 个键是必需项** |
| R9-A | `stolenmem=64MB` + `fbmem=18MB` | 不开机 | 超过本机 DVMT 实际值（32 MB） |
| R9-B | `stolenmem=32MB` + `fbmem=9MB`（与 R10 只差 `unifiedmem`） | 当时报「不开机」，**存疑** | 很可能是复制不完整 / NVRAM 残留；R10 证明这组参数本身没问题 |
| `igfxfw=2` | 强制加载 GuC 固件 | **死机** | 本机 GuC 路径不可用，永久排除 |
| 30-bit @144Hz | 10 bit/通道 + 144 Hz | 黑屏/闪 | 需 ~733 MHz > 链路 600 MHz |
| 30-bit @120Hz | 10 bit/通道 + 120 Hz | 能显示，但**切 App 掉帧** | 带宽吃到 ~98%，动画帧来不及扫描输出 |
| HiDPI 三档 | 1280×720 / 1600×900 / 1920×1080 override | 60 Hz 也掉帧 | UHD 620 填充率不足 |

**结论**：平台 id 用 `00009B3E`（笔记本），LSPCON 五个键必须给，`stolenmem` 不能超 32 MB，
`unifiedmem` 只影响显示值，24-bit 才是高刷的正解。

### 2.2 ACPI 相关

| 实验 | 现象 | 归因 |
|---|---|---|
| 加载 Dortania 通用 `SSDT-EC` | ACPI 报重复设备，开机随机卡 | 本机 EC **已经叫 `EC`**，撞名 |
| 用 Dortania 通用 `SSDT-AWAC`（`STAS` 声明成 `IntObj`） | 编译过、运行不生效 | 本机 `STAS` 是 **FieldUnit**，类型不匹配 |
| 加载 `SSDT-XOSI` + `_OSI→XOSI` 补丁 | 无收益 | 本机没有 I2C 触摸设备（触控板是 PS/2，且内屏不存在） |

**结论**：ACPI 必须按本机 DSDT 定制，通用模板抄一半会出事。

### 2.3 机型 / 三码相关

| 实验 | 现象 | 归因 |
|---|---|---|
| `Macmini8,1` | 从未成功开机 | 机型与笔记本平台 id / 电源管理路径不匹配 |
| `iMac20,1` | 未进入安装 | 同上 |
| `MacBookPro16,1` + `00009B3E` | ✅ 稳定 | 保留 |

**结论**：**不要换机型**，`MacBookPro16,1` 是这台机器唯一验证过能开机的。

### 2.4 构建流程踩的坑（已经修好，写下来免得重犯）

1. 交付包漏拷 `Drivers/*.efi` → `Driver HfsPlus.efi at 0 cannot be found! Halting on critical error`。
2. 构建到新目录时 ACPI 补丁列表为空（脚本从输出目录找源文件）→ 改为固定从 `efi/EFI/OC/ACPI` 取。
3. `--extra-arg -igfxvesa` 被 argparse 当成选项 → 必须写 `--extra-arg=-igfxvesa`。

## 3. 常见启动故障速查

| 屏幕/日志 | 大概率原因 | 处理 |
|---|---|---|
| `OCB: LoadImage failed - Not Found` | `BOOTx64.efi` 或 `OpenCore.efi` 缺失/路径不对 | 用仓库 EFI 覆盖，别手工拼 |
| `Driver HfsPlus.efi at 0 cannot be found` | `Drivers/` 没拷全 | 补齐 3 个 `.efi` |
| 卡 `EXITBS:START` | Booter quirks 不对 | 保持仓库给出的 4 个键（见 config-reference §3），别乱开 `DevirtualiseMmio` |
| 卡 `ASP: initializing bastion sandbox callback` | 显示链路/机型不对 | 检查 LSPCON 五键 + `00009B3E` + `MacBookPro16,1` |
| 卡 `[EB|LOG:EXITBS:START]` 后黑屏 | 显卡 framebuffer 参数错 | 先 `-igfxvesa` 确认能不能进系统，再逐项排查 |
| 苹果 logo 进度条走到一半重启 | kext 版本不匹配 / 缺 Lilu | 确认 14 个启用 kext 的版本与 README 一致 |
| 进系统但没声音 | layout / VerbStub | 见 [audio.md](audio.md)（先看「实测现象」，再按「真要修好」四步走） |
| 进系统但 Wi-Fi 灰 | AirportItlwm 未加载 / 与 itlwm 冲突 | `kextstat | grep -i airport`，确认 itlwm 是 `Enabled=false` |
| 启动菜单看不见 macOS 卷 | `ScanPolicy` 太严 / 卷不是 APFS | 临时把 `ScanPolicy` 改 `0` |

## 4. 怎么让 OpenCore 说话（排错时才开）

默认发布版是**静默**的（`Misc.Debug.Target=0`）。卡住时这样开日志：

```
Misc → Debug → Target = 67          # 0x43：Console + DataHub + 文件
Misc → Debug → DisplayLevel = 2147483650
Misc → Debug → AppleDebug = true
boot-args 加 -v debug=0x100 keepsyms=1
```

然后从 ESP 根目录取 `opencore-*.txt` 看最后 50 行。
**排完记得改回去**（`Target=0`、去掉调试 boot-args），否则每次开机都往 ESP 写日志。

## 5. 一句话版「不要做」

- 不要 `igfxfw=2`；
- 不要 `stolenmem ≥ 64MB`；
- 不要 `SSDT-EC`；
- 不要 `Macmini8,1` / `07009B3E`；
- 不要 30-bit + 144Hz；
- 不要 HiDPI 缩放；
- 不要从系统里 `nvram boot-args=...`（SIP 会拒，改 config 就行）；
- 不要一次改多个变量再重启（4K/睡眠/无线的问题会互相掩盖）。
