# 游戏接口还原（读源码）常态化方案

## 一句话结论

**拿不到原始源码，但能拿到「头文件级」的游戏结构。** 这个游戏的资产容器是加密的
（`ProjectPBZ-Windows.utoc` 的 `ContainerFlags = 0xb` = Compressed | Encrypted | Indexed），
离线拆包这条路被密钥挡住；但 UE4SS 在运行时拿到的反射数据是**游戏自己解密后的**，
所以改为「运行时导出 → 静态查阅」，精度反而更高（偏移、大小、函数签名都是真的）。

## 三条路线，为什么选第三条

| 路线 | 可行性 | 能拿到 | 卡点 |
|---|---|---|---|
| 离线拆 `.ucas` 再反序列化 `.uasset` | ✗ 当前不可行 | 蓝图属性默认值、UMG 控件树、蓝图字节码 | 容器加密，需要 AES 密钥；没有密钥连目录索引都解不开 |
| 反编译 `.exe` / 游戏 DLL | △ 只能到函数级 | 机器码函数边界、字符串引用、调用图 | Shipping 构建，无符号无调试信息，读不出「源码」语义；成本极高、收益低 |
| **运行时反射导出（本方案）** | ✓ 已落地 | 类继承、属性名/类型/偏移/大小、UFunction 签名、枚举、结构体 | 只有**声明**，没有**实现体**；蓝图函数的函数体拿不到 |

也就是说：**能读到「这个类有哪些成员、长什么样、能调什么」，读不到「这个函数内部怎么写的」。**
对写 Mod 来说，前者是 90% 的需求（我现在改 HUD、改条、找属性名，靠的就是它）；
后者只有做逻辑复刻时才需要，而那种需求本来就该用 hook 观察行为，而不是读代码。

## 工具组成

### 1. `PBZDevSDK` —— 开发期导出 Mod（不进玩家版）

装在 `platform/steam/ue4ss/Mods/PBZDevSDK/`，源码在本仓库 `tools/game-sdk/PBZDevSDK/`。

按顺序调用 UE4SS 暴露的五个 Lua 导出函数，每个间隔 4 秒，全部 pcall 包裹并写日志：

| 调用 | 产物（相对 `platform/steam/dump/`） | 用途 |
|---|---|---|
| `GenerateUHTCompatibleHeaders()` | `UHTHeaderDump/<模块>/Public/*.h` | C++ 模块的 UHT 风格头文件，**只有引擎和游戏 C++ 类** |
| `GenerateSDK()` | `CXXHeaderDump/*.hpp` | **含全部蓝图类**（`UWB_*_C`）与成员偏移，查 HUD 主要靠它 |
| `GenerateLuaTypes()` | `types/*.lua` | Lua 侧类型（属性名/方法名），写 Mod 时对照 |
| `DumpUSMAP(true)` | `ProjectPBZ-<版本>.usmap` | 若将来拿到密钥，外部工具拆包要用 |
| `DumpAllObjects()` | `UE4SS_ObjectDump.txt` | 全 UObject 清单（75 MB），最后跑 |

**产物落点是 `platform/steam/dump/`，不是 ue4ss 目录里面。** UE4SS 本身把文件写在 DLL 旁边
（路径硬编码，`UE4SS-settings.ini` 里没有能改的项——`[SDKGenerator] OutputPath` 只管另一套
`UE4SS_SDK`，管不到这几个），所以 DevSDK 在导出跑完后自动搬一层出去：

```
平台目录/
├── ue4ss/                 ← 升级或重装时整个被替换
│   └── Mods/PBZDevSDK/    ← 只留 dump.log / done.flag / move_dump.bat / move.log
└── dump/                  ← 产物在这里，删 ue4ss 不影响
    ├── UHTHeaderDump/  CXXHeaderDump/  types/
    ├── UE4SS_ObjectDump.txt
    └── ProjectPBZ-<版本>.usmap
```

搬移用 `move_dump.bat`（由 Mod 自动生成在 `Mods/PBZDevSDK/`）：cmd 的 `md` 能建整棵目录树，
`move` 移目录是同分卷瞬时改名；Lua 里既没有 `mkdir`，逐个 `os.rename` 两万多个文件也不现实。
脚本路径全用 `%~dp0` 相对推导，游戏装在带空格或中文的目录里也不受影响。搬移过程会卡几秒，
记录写在同目录 `move.log`。**要手动补：双击 `move_dump.bat` 即可。**

实测一次（2026-11-07）：CXXHeaderDump 2497 个 hpp / 17 MB，UHTHeaderDump 19230 个 h /
72 MB，Lua types 2497 个，对象清单 75 MB；`GenerateUHTCompatibleHeaders` 是最重的一步
（33 秒），其余各 2 秒内。合计 17919 个类/结构体进索引。

触发方式：

- **自动**：本局检测到 HUD 血条控件已加载（说明 UI 蓝图包已被读过），等 2 秒跑一遍，
  跑完写 `done.flag`，之后每局不再自动跑。
- **手动**：`F10` 随时补跑（改了设置、想看最新世界状态时）。

日志：`Mods/PBZDevSDK/dump.log`；要重新自动跑一次，删掉同目录的 `done.flag`。
重跑时 dump 目录里的同名旧产物会被先删掉再替换（每次导出都是完整快照，旧的没有保留价值）。

> 踩过的坑：UE4SS 里 Lua 的 `io` 相对路径基准是**游戏工作目录**
> `ProjectPBZ/Binaries/Win64`，不是 Mod 目录。早期版本 `debug.getinfo` 推不出 Mod 路径，
> 日志就写到了 `Binaries/Win64/dump.log`。现已在 `modRoot()` 里加了候选目录探测
> （`Mods/PBZDevSDK`、`../../../platform/steam/ue4ss/Mods/PBZDevSDK`），
> 并且启动时会把日志的基准目录打出来。

注意：导出是同步重活，执行时会明显卡顿几十秒，属正常。

### 2. `tools/sdk_query.py` —— 查源码的动作

```bash
python tools/sdk_query.py stats                          # 导出了多少类、来自哪个 dump
python tools/sdk_query.py find hpbar                     # 按名字找类
python tools/sdk_query.py class WB_PlayerHPBar_V1_C      # 类定义（含继承链、成员数）
python tools/sdk_query.py props WB_PlayerHPBar_V1_C      # 属性 + 偏移 + 大小
python tools/sdk_query.py funcs WB_PlayerHPBar_V1_C      # 函数签名
python tools/sdk_query.py base PBZAnimProgressBar1_C     # 继承链
python tools/sdk_query.py grep "ShowUpPercentage"        # 全文搜（找事件名、材质参数名）
```

两个细节，踩过：

- **名字对不上**：Lua 反射里叫 `WB_PlayerHPBar_V1_C`，C++ 头文件里叫 `UWB_PlayerHPBar_V1_C`。
  查询会自动在 `U` / `A` 前缀间回退，两种写法都能查到。
- **两种 dump 语法不同**：CXX 的 `class X : public Y` 花括号换到下一行，UHT 的同行。
  解析器两者都吃，同时还挡掉了 `class UFoo;` 前置声明和 `class UImage* Image;` 成员声明
  被误认成类定义的情况。

`--root` 可指向任意导出目录；`--selftest` 用内置样本验证解析逻辑（改动解析器后必跑）。

## 用它替代「拍脑袋探针」的具体做法

以后做功能，顺序固定为：

1. `sdk_query.py find <关键词>` 定位相关类；
2. `props` / `funcs` 看有哪些成员可读可调，**先确认属性名真的存在**再写 Lua；
3. 拿不准的行为（比如「这个条什么时候被重置」）再上 hook 观察，而不是靠猜；
4. 需要跨帧持有的对象，在头文件里确认它是 `UObject*` 还是裸结构体，决定要不要做失效检查。

## 第一次用它的结论（2026-11-07）

导出跑完后拿现有代码反向核对了一遍，两件事：

1. **现有代码里没有「猜出来的」属性名**。`Scripts/` 里访问的
   `PureShachiImage` / `PureShachiNum`（`W_WeaponUI`，0x0408/0x0410）、
   `Image_ShaChiBarBG` / `Image_ShaChiBarRedGlow` / `ShachiBarRatio` /
   `HPBarInitRatio`（`WB_PlayerHPBar_V1_C`）在头文件里都能对上。
   唯一查不到的 `T_UI_ShaChiBullet_001_FG` 是贴图资源路径，不是控件名，本来就该查不到。
2. **血条类自带显隐接口**：`UWB_PlayerHPBar_V1_C` 有 `HPBarShowHUD(bool PlayHitAnim)` 和
   `HPBarHideHUD()`。我们现在靠 UMG `Visibility` + 父链门控来跟随 HUD 显隐，属于绕行；
   后续可以考虑直接走这两个函数，少一层猜测。代价是要先确认它们与游戏 HUD 状态的
   耦合程度（是否会改动画/材质），所以先记下来，不在修复期动。

## 能不能 hook 进原生 HUD 显隐逻辑（已结论：不能，保持轮询）

目标是「游戏一调显隐就通知我」，替掉现在的 0.05s 轮询。两个候选都试过了，都不成立。

| 候选 hook 点 | 类型 | 结论 |
|---|---|---|
| `WB_PlayerHPBar_V1_C::HPBarShowHUD(bool)` / `HPBarHideHUD()` | 蓝图事件 | **hook 不到**。dump 里多一行同名委托属性是蓝图事件标记，没有 native 函数体 |
| `UPBZHUDLayout::ApplyCharacterStateVisibility(EPBZHUDVisibility)` | native | **能 hook，但没人调**。实测 93 秒内 0 次 |
| `UWidget::SetVisibility(ESlateVisibility)` | native，全局 | **覆盖 100%，但一 hook 就崩**，见下 |

判据（已做进工具）：`sdk_query.py funcs` 遇到「同名委托属性 + 函数声明」成对出现的，标
`[蓝图事件，hook 不到]`；只有函数声明的才是 native。

### 实测 1：ApplyCharacterStateVisibility 不参与日常显隐

hook 注册成功（`pre=5 post=6`），93 秒里调用 **0 次**；同一时段主 Mod 的日志显示血条显隐
实际翻转了 12 次，中间还开过菜单、切过 3 次图。结论：它只在设置项（`HUDCharacterStateMode`）
变化时被调，日常脱战/开菜单的显隐根本不经过它。它管的是「模式/意图」，不是「这一帧显示没有」。

### 实测 2：SetVisibility 是唯一入口，但 hook 它必崩

`ESlateVisibility` 只有一个设置入口，覆盖率必然是 100%，理论上完美。实测代价是崩溃：

- 无此 hook 的版本（`probe_run1.log`）跑 93 秒、跨 3 次切图，**一次没崩**；
- 加上它之后 **12 秒就崩**，正是在读档进图那一刻；
- dump：`0xC0000005` **读取** `0xFFFFFFFFFFFFFFFF`，RIP 在 `UE4SS.dll+0x2DD8B8`——
  崩在 UE4SS 自己内部，不是游戏代码。签名和历史上「碰到正在销毁的 UObject」完全一致。
- 该函数每秒被调 200+ 次（`setVis=0/217`），每次 UE4SS 都要把 Context（任意 UMG 控件）
  转成 Lua 对象，解引用对象头。进图时大量控件正在构造/销毁，必然踩到已释放的实例。
  Lua 侧 `pcall` 拦不住 C++ 层越界，所以这是硬崩。

**结论：覆盖率与安全性在这里不可兼得。放弃 hook 方案，保留现有轮询 + 门控。**

这个取舍值得记住：轮询看着"笨"，但它只在明确知道对象有效时去读（有 HUD 可见信号 +
加载沉降门控），而全局 hook 会把「任意时刻的任意对象」塞到你面前，其中一部分是死的。
在 UE4SS 这种进程内注入的环境里，后者是必崩路径。

### 探针 `PBZProbe`（一次性，已停用）

源码 `tools/game-sdk/PBZProbe/`，装在 `Mods/PBZProbe/`。**当前 `mods.txt` 里是 `PBZProbe : 0`**，
保留代码是为了以后有新假设时能快速再测，但默认不加载。

`SetVisibility` 那段 hook 已从代码里**删除**，并在原位置留了注释说明为什么不能加回来。
仍然可以使用的部分：`ApplyCharacterStateVisibility` 的 pre/post 记录、血条 `Construct` 记录、
0.05s 可见性采样（带 `LoadMap` 门控 + 1.5s 沉降）。

分析：

```bash
python tools/analyze_probe.py "E:/SteamLibrary/steamapps/common/PBZ/platform/steam/ue4ss/Mods/PBZProbe/probe_run1.log"
```

## 已知边界

- **蓝图函数体拿不到**：`WB_PlayerHPBar_V1_C::UpdateHP` 这种只有签名，没有实现。
- **UMG 控件树拿不到静态版本**：它存在 `.uasset` 里（加密）。要看层级只能用运行时遍历
  （现有 Mod 的 `childrenOf` 干的就是这件事），或等离线路线解锁。
- **导出内容取决于「当时加载了什么」**：`LoadAllAssetsBeforeDumpingObjects` 保持 0，
  所以只导出已加载的包。进过游戏、开过 HUD、看过的界面，类才全。
- **加密资产不会因此被解开**：本方案不解密、不修改游戏文件，只是把游戏自己已经解密的内存结构写成文本。
