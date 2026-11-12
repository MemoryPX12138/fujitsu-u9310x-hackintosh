# 显示：LSPCON、带宽、120/144Hz、HiDPI

> ⚠️ 本文只讨论**外接 HDMI 显示器**这条链路。本机是「无头骑士」形态（无内屏），
> **内屏（eDP）点亮与亮度调节未适配**，有屏机器请先看 [requirements.md §0](requirements.md#0-仅适用于无头骑士形态最重要的一条)。

## 1. 链路长什么样

```
UHD 620 (8086:9b41)
   └─ DDI → LSPCON（MegaChips 类芯片，DP→HDMI 2.0 转换）
          └─ HDMI → 外接显示器（2560×1440@144 原生）
```

- macOS 把它识别成 **`Connection Type: Thunderbolt/DisplayPort`** —— 因为 LSPCON 之前是 DP 链路，
  这是正常的，不是故障。
- Linux 下同一个口报 `DP-1`，可反证 LSPCON 的存在。
- 显示器 EDID 里 HDMI Forum VSDB 的 **max TMDS character rate = 600 MHz**，这是本机刷新率的硬天花板。

## 2. 带宽账（所有结论的来源）

| 模式 | 像素时钟（CVT-RB） | 24-bit 需求 | 30-bit 需求 | 600 MHz 内？ |
|---|---|---|---|---|
| 2560×1440@60 | ~241 MHz | ~241 | ~301 | ✅ |
| 2560×1440@120 | ~490 MHz | ~490 | ~612 | ✅ 24-bit / ⚠️ 30-bit 刚好压线 |
| 2560×1440@144 | **~586.6 MHz** | ~586.6（98%） | ~733 | ✅ 24-bit / ❌ 30-bit |

结论：

- **24-bit（ARGB8888）最高 144 Hz**；
- **30-bit（ARGB2101010）最高 120 Hz**，且已经吃掉绝大部分链路预算；
- 30-bit + 120Hz 虽然能出画面，但**切 App / 窗口动画会掉帧**——不是 GPU 不行，是扫描输出来不及。

### 当前配置

**2560×1440 @ 120 Hz / 24-bit ARGB8888**（`system_profiler` 实测：`Framebuffer Depth: 24-Bit Color (ARGB8888)`）。

为什么不是 144：144 也能跑，但只剩 2% 链路余量，任何一点时钟抖动或线材差异都会变成偶发闪屏/掉帧；
120 留了约 18% 余量，**日常更稳**。想试 144 见 §5。

## 3. 怎么持久化（开机自动套用）

显示器接在 LSPCON 上时，macOS 会记住上次模式，但不是 100% 可靠（尤其换线/换口后）。
本机用 `displayplacer` + LaunchAgent 强制：

```
/usr/local/bin/displayplacer
~/Library/LaunchAgents/com.local.displaymode.plist      # RunAtLoad + LimitLoadToSessionType=Aqua
```

内容：

```xml
<key>ProgramArguments</key>
<array>
  <string>/usr/local/bin/displayplacer</string>
  <string>id:<你的DISPLAY_ID> res:2560x1440 hz:120 color_depth:4 scaling:off</string>
</array>
<key>RunAtLoad</key><true/>
<key>LimitLoadToSessionType</key><string>Aqua</string>
```

> `id:` 是 displayplacer 的 persistent id，**换显示器/换口会变**。
> 用 `/usr/local/bin/displayplacer list` 查当前值，末尾那行 `displayplacer "id:..."` 就是可直接用的命令。

**color_depth 实测映射**（displayplacer 的数字不是「每通道位数」，别按直觉填）：

| 值 | 实际输出 | `system_profiler` 显示 |
|---|---|---|
| `color_depth:4` | 8 bit/通道 | **24-Bit Color (ARGB8888)** |
| `color_depth:8` | 10 bit/通道 | 30-Bit Color (ARGB2101010) |

## 4. HiDPI：试过，放弃，已清理

试过的三档缩放（都是 2× 渲染）：

| 缩放 | 渲染分辨率 | 结果 |
|---|---|---|
| 1280×720 | 2560×1440 | ❌ 60Hz 也掉帧 |
| 1600×900 | 3200×1800 | ❌ 掉帧更明显 |
| 1920×1080 | 3840×2160 | ❌ 最严重 |

原因：UHD 620 要把 2× 的画面渲染到 3840×2160 再缩放输出，iGPU 的填充率扛不住 LSPCON 链路；
**这不是 macOS 设置问题，是硬件算力问题**，换参数救不回来。

遗留的 override 文件（`/Library/Displays/Contents/Resources/Overrides/DisplayVendorID-<VENDOR>/DisplayProductID-<PID>`）
已在 r17 删除。注意：

- **删掉后不会立刻生效**，WindowServer 会缓存到本次登录结束；
  下次登录/重启后，系统设置里那几档 HiDPI 缩放才会消失。
- 删除命令（需要 root）：
  ```bash
  sudo rm -rf /Library/Displays
  ```
- 删掉后默认就是原生 2560×1440，`displayplacer` 的 120Hz/24-bit 设置不受影响（那是原生模式，不依赖 override）。

## 5. 想要 144Hz 怎么办

```bash
# 手动切一次
/usr/local/bin/displayplacer "id:<你的id> res:2560x1440 hz:144 color_depth:4 scaling:off"

# 或把 LaunchAgent 里的 hz:120 改成 hz:144
```

自检：切完看 `system_profiler SPDisplaysDataType`，确认还是 **24-Bit**；
如果变成 30-Bit，说明系统选了另一条模式，手动加 `color_depth:4` 再试。

> 仓库里还留了一个 `/usr/local/bin/refresh-by-power.sh`（AC→144 / 电池→60），
> 但本机没有电池，**没有对应的 LaunchAgent，属于未接线的备用脚本**，不影响开机。

## 6. 可变刷新率（FreeSync / VRR）

- 显示器 EDID 里有 **AMD FreeSync VSDB**（OUI `00-00-1A`，48–144 Hz），硬件支持 Adaptive-Sync。
- **macOS 的 Intel iGPU 驱动不支持 FreeSync/VRR**，WhateverGreen 也没有相关开关，
  系统设置里没有可变刷新率选项。
- 所以本机**做不到逐帧自适应刷新率**。能做的只有脚本切固定档位，别被「显示器支持 FreeSync」误导。

## 7. 明确不要做的三件事

| 尝试 | 结果 | 原因 |
|---|---|---|
| `igfxfw=2`（强制加载 GuC 固件） | **死机** | 本机 GuC 路径不可用，永久排除 |
| 30-bit + 120Hz 以上 | 掉帧 / 黑屏 | 超 TMDS 预算 |
| HiDPI 缩放（任意档） | 掉帧 | iGPU 填充率不够 |

## 8. 复核

```bash
system_profiler SPDisplaysDataType | grep -E "Resolution|Depth|UI Looks"
/usr/local/bin/displayplacer list | tail -5
ls -la /Library/Displays 2>&1          # 应该 No such file or directory
```
