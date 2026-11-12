# 音频：ALC255 · layout 3 · **3.5mm 插拔切换未修复**

## 0. 先看结论

| 功能 | 状态 | 说明 |
|---|---|---|
| 内置喇叭 | ✅ 正常 | 默认输出，`Internal Speakers` |
| 内置麦克风 | ✅ 正常 | 默认输入，2 ch / 44100 Hz |
| 3.5mm 耳机**出声** | ⚠️ 不稳定 | 依赖手动操作，重启/重插即失效 |
| 3.5mm **插拔自动切换**（喇叭 ↔ 耳机） | ❌ **未修复** | 插上耳机系统不会出现 `Headphones` 输出设备，仍从喇叭出声 |

这是本机**目前最明确的一个未解决问题**，不要把它当成「配置没调好」——
下面把现象、原因、试过的东西、以及真正要修需要做什么全部写清楚。

## 1. 实测现象

```
$ system_profiler SPAudioDataType
    Devices:
        Built-in Microphone:      ← 只有输入
          Input Source: Internal Microphone
        Built-in Output:          ← 只有输出
          Output Source: Internal Speakers
```

关键点：**设备列表里没有 `Headphones`**。

- 正常工作的黑苹果笔记本，插上耳机后这里会多出一个 `Headphones` 输出设备，
  或者 `Built-in Output` 的 `Output Source` 会在 `Internal Speakers` / `Headphones` 之间切换。
- 本机插拔 3.5mm 时，`system_profiler` 与「声音 → 输出」列表**都没有任何变化**，
  声音继续从内置喇叭出来（用户实机确认）。
- 也就是说：**codec 能出声，但 jack sense（插孔检测）这条链路没通**。

当前加载状态（用来排除「驱动没装」这种低级原因）：

```
$ kextstat | grep -i verbstub
com.XPS.VerbStub (1.0.4)          ← 已加载
$ kextstat | grep -i applealc
as.vit9696.AppleALC (1.9.8)       ← 已加载
$ ioreg -rn HDEF | grep layout-id
"layout-id" = 3                    ← 生效
boot-args: ... alcid=3 ... alcverbs=1 alcdelay=1000 alctsel=1
```

**驱动、layout、verb 参数全部在位，切换依然不工作。**

## 2. 为什么这件事比「让喇叭出声」难得多

ALC255 的耳机口是 pin complex **0x21**（HP out）。要让它工作，需要三段同时成立：

| 段 | 内容 | 本机状态 |
|---|---|---|
| ① codec 配置 | pin 0x21 被配置成 HP out + jack detect（pin default / config override） | ✅ layout 3 已包含 |
| ② 硬件回报 | 插入耳机时 codec 通过 **unsolicited response**（`0x021707xx` 一类 verb / pin sense）上报插拔事件 | ❓ **未验证**（关键未知项） |
| ③ 软件响应 | 有东西持续监听这个事件，并把默认输出切到耳机、同时静音喇叭 | ❌ **没有**：`ComboJack` 没有常驻守护进程，`VerbStub` 只维持 verb，不做切换 |

`AppleALC` 只负责 ①（把 codec 点亮）；③ 需要一个用户态守护进程
（ComboJack 那类）或驱动层的 jack 处理。**本机 ③ 是空的**，所以插拔不会有任何反应。

> 换句话说：不是「layout 选错了」，而是「插拔事件没人接」。

## 3. 试过的东西（别重复）

| 尝试 | 结果 |
|---|---|
| layout 3 / 11 / 13 / 27 / 28 / 56 / 66 / 71 / 99 | 只有 **3** 能让喇叭/麦克风正常；其余要么无声，要么只有喇叭 |
| `VerbStub.kext` 1.0.4 | 加载正常，喇叭更稳，但**插拔仍无反应** |
| `alcverbs=1` / `alcdelay=1000` / `alctsel=1` | 同上，属于 verb 时序调参，不解决设备切换 |
| 安装 `ComboJack` + `hda-verb` | 文件在 `/usr/local/sbin/`，但**没有 LaunchDaemon，等于没运行** |
| 手动 `hda-verb 0x21 SET_EAPD 0x02` 之类 | 偶尔能让耳机响一次，重启/重插即失效，不能当方案 |
| 换 `layout-id` 后重启复测 | 每换一次都要重启，且没找到既能出声又能切换的 layout |

## 4. 现在能怎么用

| 方案 | 说明 |
|---|---|
| **USB / USB-C 声卡或耳机** | 最省事，免驱，插上就是一个独立输出设备（推荐） |
| 蓝牙耳机 | 已验证可用（A2DP），代价是延迟与麦克风降级到 HFP |
| 继续用喇叭 | 当前默认行为 |
| 想继续攻这个坑 | 见下一节，需要 codec 级调试，不是改两个键能解决的 |

## 5. 真要修好，需要按这个顺序做

1. **确认硬件是否回报插拔**（决定性一步）：
   ```bash
   # 插着/拔着各跑一次，看 pin sense 是否变化
   sudo /usr/local/sbin/hda-verb 0x21 GET_PIN_SENSE 0
   ```
   - 返回值随插拔变化 → ② 通，问题在 ③，写守护进程即可；
   - 返回值不变 → ② 就不通，需要改 layout 里 0x21 的 pin default（`0x21 0x71C...`），
     重新编译 AppleALC layout，再回到第 1 步。
2. 若 ② 通：写一个 LaunchDaemon 跑 `ComboJack`（或自己写个监听 verb 的小程序），
   在插拔时切默认输出 + 静音喇叭。
3. 若 ② 不通：需要拿到本机 ALC255 的完整 pin config（`hda-verb 0x21 GET_CONFIG_DEFAULT`），
   对照同型号机器的已知 layout 改 `ConfigData`，这一步没有捷径。
4. 全程要保留一份「能出声」的 EFI 备份 —— 改 layout 很容易把喇叭也弄哑。

> 本项目**没有**走到第 2/3 步，所以现在的结论只能是「未修复」，
> 而不是「已经修好但你没配对」。

## 6. HDMI 音频

`hda-gfx = onboard-1` 同时写在 iGPU 与 HDEF 上，用来把 HDMI 音频路由到核显的 HDA 控制器。
外接显示器若带喇叭，切换输出时会出现对应设备；这条链路与 3.5mm 无关，**不要因为耳机问题去动它**。

## 7. 排错命令合集

```bash
# 设备列表（看有没有 Headphones）
system_profiler SPAudioDataType | grep -E "Built-in|Headphones|Output Source|Input Source"

# 驱动与 layout
kextstat | grep -Ei "AppleALC|VerbStub|AppleHDA"
ioreg -rn HDEF | grep -i layout-id
nvram boot-args | tr ' ' '\n' | grep -E "alcid|alcverbs|alcdelay|alctsel"

# 手动探测插孔（需要 root；插着/拔着各跑一次对比）
sudo /usr/local/sbin/hda-verb 0x21 GET_PIN_SENSE 0
sudo /usr/local/sbin/hda-verb 0x21 GET_CONFIG_DEFAULT 0

# 重启音频服务（改完 layout 或唤醒后没声时）
sudo killall coreaudiod
```

## 8. 已知限制

- 耳机口的**线控/耳麦麦克风**未验证（连耳机输出都还没稳定）。
- `VerbStub.kext` 是第三方闭源 kext，不能保证未来系统版本继续可用。
- 没有内屏，所以「内建麦克风阵列波束成形」这类依赖内屏模组的功能不存在。
