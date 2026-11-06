影之刃零 · 弧形血条/杀气条（PBZPlayerArcs）
================================================

在玩家角色两侧各画一条弧形条：默认左边血量、右边杀气。
另外把药瓶、精纯杀气和暗源的数量平铺显示在屏幕下方（图标 + 数字）。
只读取玩家数值，不修改任何游戏数据。

本 mod 基于影之刃零 1.0.1 版本制作，兼容 11.4 的最新更新。
Lua Mod 且只读取玩家数值及游戏基础资产，理论兼容后续任何更新。

安装
----
1. 确认游戏已安装 UE4SS。
2. 把整个 PBZPlayerArcs 文件夹放到：
   ...\PBZ\platform\steam\ue4ss\Mods\PBZPlayerArcs
   最终应能看到：
   ...\Mods\PBZPlayerArcs\enabled.txt
   ...\Mods\PBZPlayerArcs\Scripts\main.lua
   ...\Mods\PBZPlayerArcs\Scripts\settings.ini
   ...\Mods\PBZPlayerArcs\Scripts\preset\preset1.ini
3. 启动游戏，读取存档、进入可操作状态后弧形条才会出现。
   不需要修改 mods.txt，放置 enabled.txt 即可启用。


按键
----
F2        打开 / 关闭设置菜单（改完自动保存到 settings.ini）
          想换键就改 settings.ini 里的 MenuKey，例如 MenuKey = F8
ESC       菜单打开时保存并关闭菜单；菜单没开时这个键仍然交给游戏（固定，不可改）
鼠标左键  在菜单里按住滑块左右拖动；点击开关按钮和下拉框
          菜单打开时按住任意图标，所有图标一起移动
鼠标右键  菜单打开时按住某个图标，只移动这一个
鼠标滚轮  在菜单里把指针停在滑条上，滚动微调数值（整数 ±1，小数 ±0.1）
鼠标中键  在菜单里把指针停在滑条上，点一下把该项恢复成内置默认值
          菜单打开时点击图标，全部图标回到默认位置


菜单与配置文件
--------------
菜单和 settings.ini 读写的是同一份文件：Scripts\settings.ini。
菜单里改动会立刻生效，并在约 0.35 秒后写回文件；
关闭菜单时也会保存一次。也可以直接在游戏外编辑该文件，重启游戏后生效。
写回时只替换数值，文件里的中文注释和空行会原样保留。
settings.ini 最上面是 Lang（菜单语言）和 MenuKey（菜单键），后面才是预设名和各项数值。

菜单右上角是语言下拉框：左边是「语言 / Language」标签，点右侧按钮展开可选语言，
展开时按钮上的箭头会翻转，选完或点在别处都会收起。
菜单里的文字都存在 Scripts\lang 下的语言文件里（zh-Hans.ini 中文、en.ini English），
一行一个「键 = 显示文字」，改完保存、重新按 F2 打开菜单就能看到。
文件名就是游戏的语种代号（en-US 这类带地区的代号会退回 en 去找文件）；
第一次启动时菜单会直接用游戏的语言，并写进 settings.ini 的 Lang。
下拉框列出哪几种语言由 Scripts\lang\languages.ini 决定：一行一个语言文件名（不带 .ini），
按文件里的顺序排。别的语种想加自己的语言，复制一份改名为例如 fr.ini，改掉置顶的
lang.name（下拉框显示的就是它），再在 languages.ini 里加一行 fr 即可，不用改 mod 代码。
「全部显示 / 仅血条 / 仅杀气 / 关闭弧线」也是下拉框，在弹出的选项里选即可。
开关按钮排成两行，每行六个：第一行是跟随人物、残影、笔锋、药瓶、绝招、固定原生条；
第二行是显示时机、显示范围、血左杀右、显示数字、数值样式（上下显示 / 居中显示）、恢复默认。
第一行里「药瓶显示 / 药瓶隐藏」「显示绝招 / 隐藏绝招」分别控制两组图标。
鼠标停在滑条、开关或下拉框上时，旁边会浮出一句说明，告诉你这一项控制什么。

预设
----
菜单右上角、语言栏左边是预设下拉框，显示当前预设名；它右边是「保存」「新建」
两个小按钮，再往右才是语言栏。

- 下拉框：先以出厂默认值为基地，再套用预设文件里写出的差异项，整套换成当前值，
  立刻生效并写回 settings.ini。预设文件里没写的项一律回到默认值。
- 保存：只把「与默认值不同」的项写进当前预设文件；改回默认值的项会自动从文件里
  消失，所以预设文件记录的是一份差异清单，不是完整快照。
- 新建：用当前设置的差异项新建一个预设，名字顺延（预设 3、预设 4…），并切换过去。
- 恢复默认：恢复成「当前预设」里存的值（默认值 + 该预设的差异项），不是出厂默认值。
  单项也可以在滑条上用中键点一下，回到内置默认值。

预设存放在 mod 的 Scripts\preset 文件夹里，一个预设一个文件：preset1.ini、preset2.ini…
编号必须连续（中间缺一个就到此为止）。每个文件只记录相对默认值的差异，格式和
settings.ini 一样，可以直接在游戏外改，写出的项覆盖默认值。文件里的 Preset 一行
就是这个预设的名字，改成什么菜单里就显示什么，mod 不会改写它。Lang 和 MenuKey
属于玩家配置，只存在 settings.ini，预设文件里的同名行会被忽略。settings.ini 里的
Preset 一行记的是当前预设的文件名（例如 preset2，不带 .ini），只按文件名对应，
所以改了显示名也不会跟丢；文件名对应的预设不存在时，菜单会把它当成还没保存过的
新配置。

settings.ini 是例外：游戏内保存时始终写全量（完整的一份设置），方便配置界面打不开
时直接手改；只有预设文件是差异文件。

自带两份：预设 1 就是出厂默认配置（settings.ini 的初始值、单项恢复默认用的内置默认值都是它），
预设 2 = 另一套更细的笔触。

菜单顶部提示里的按键名会跟着 MenuKey 变化：把 MenuKey 改成 F8，提示就显示 F8。

菜单里使用的是系统自带的箭头光标，可以移动到面板外的任意位置。


固定游戏原生血条 / 杀气条（可选）
--------------------------------
游戏自己左下角的血条和杀气条会随着上限变长，后期越拉越长。打开「固定原生条」后，
这两条会回到游戏最初给它们设定的长度上，不再变长。
默认打开（预设 1 就是打开状态），关着的时候原生条完全不受影响。

「显示数字」是单独的开关，不固定原生条也能显示，固定的条和游戏原本的条都可以用：
- 上下显示：血量的数字在条的正上方，杀气的数字在条的正下方，颜色跟随 HpColor / QiColor。
- 居中显示：数字用白字显示在每条条身的正中间，内容同样是「当前值 / 最大值」，
  字号固定得很小，保证在游戏那两条细条里也放得下。
打开「固定原生条」时会同时打开「显示数字」，之后可以用「显示数字」单独关掉。
数字的样式用第二行的数值样式下拉框切换。

长度取自游戏最初给这两条设定的长度，和你什么时候打开开关无关；血条和杀气条各自保留
自己的长度比例。也可以在 settings.ini 里把 HudBarWidth 写成一个具体数值，两条都会固定
成这个长度（-1 表示各用各自的初值，日志会打印这两个值）。
如果游戏里找不到这两条的长度控件，就不去改原生条，只在日志里说明。
数字用的是游戏原来的字体和条上的同一层，所以过场、菜单里隐藏 HUD 时数字跟着一起消失。

如果同时还装着别的移动或缩放原生血条的 mod，两边都会去改同一条控件，会互相覆盖，
只能用其中一个。


设置项说明（数值以 1080p 为基准，分辨率变化时自动缩放）
----------------------------------------------------
Preset               当前预设的文件名（不带 .ini），对应 Scripts/preset/ 里的 presetN.ini
FollowCharacter      true = 跟随人物；false = 使用固定屏幕位置
FollowSmoothing      跟随平滑，0 = 完全贴合，越大越柔和
FixedAnchorX/Y       不跟随时使用的屏幕相对位置（0~1）
AnchorHeight         读取人物位置时向上抬高的距离（厘米）
AnchorOffsetX/Y      双弧整体偏移，单位是 1080p 像素

Radius               弧半径，默认 195（越大离身体越远）
Thickness            笔触粗细，默认 12
ArcSpan              弧线张开角度，默认 60 度
Segments             分段数量，默认 45；越多越圆滑，也越耗性能
HpOnLeft             true = 血左杀右；false = 杀左血右
BrushJitter          笔触的随机抖动，默认 0（边缘最干净）；
                     调大会让每段笔触随机偏移，更像手绘，但弧线边缘会出现细碎毛刺
StrokeOverlap        每段笔触画成多少倍分段长度，默认 9.5；
                     越大相邻段重叠越多、越连贯，越小越能看到一节的接缝

BarOpacity           双弧整体不透明度
TrackOpacity         底槽（空槽）不透明度
GhostOpacity         残影透明度；残影显示刚被扣掉的那一段，颜色比真实弧线暗，
                     方便和当前血量区分开
GhostSpeed           残影回收速度，越大回收越快
ShowGhost            是否显示残影
ShowTip              是否显示弧线末端的笔锋（默认开启）
TipScale / TipAngle  笔锋大小与角度

HpColor / QiColor    血量 / 杀气主色，默认取自游戏 HUD（银白 / 金）
TrackColor           底槽颜色
WarnColor            低量警告颜色，默认红色

WarnThresholdHp      低血量阈值，0.30 表示 30%
WarnThresholdQi      低杀气阈值，0.25 表示 25%
WarnFlashSpeed       闪烁速度（每秒次数）
WarnFlashAmount      闪烁幅度，0 = 不闪，1 = 完全明暗交替

Visibility           显示时机（菜单里是同名的下拉框）：
                     hud = 跟随游戏 HUD 的显示 / 隐藏（过场、菜单时一起淡出）
                     dynamic = 动态隐藏（默认）：血条、杀气条分别判断，
                     某一条满了并持续 HideDelay 秒后隐藏那一条，掉下来立刻恢复；
                     没满时跟随游戏 HUD，HUD 一隐藏就立刻一起隐藏、不再等延迟
HideDelay            动态隐藏延迟（秒），默认 3.0，0 = 满了立刻隐藏
DisplayMode          显示范围：both = 血条和杀气都显示（默认）/
                     hp = 只显示血条 / qi = 只显示杀气 / off = 两条弧线都不显示
                     （药瓶、绝招等图标不受影响）；左右位置仍由 HpOnLeft 决定

MedicineHud          true = 显示药瓶图标和剩余数量；false = 隐藏
UltHud               true = 显示绝招层数和暗源数量；false = 隐藏
MedicineHudX/Y       药瓶图标的屏幕坐标（1080p 基准像素）；
                     -1 = 自动放在屏幕下方中间、距离底边 152 像素的位置。
                     在菜单打开时拖动图标会自动写入实际坐标
UltHudX/Y            绝招一组图标的屏幕坐标，规则同上
Med1OffX/Med1OffY    单个图标在组内的偏移（像素），0 = 按顺序自动排列；
Med2OffX/Med2OffY    右键拖动单个图标会自动写入，中键点击图标清零
Ult1OffX/Ult1OffY
Ult2OffX/Ult2OffY
IconScale            图标整体大小（0.5 ~ 3），默认 1.0；图标、数字和它们的间距
                     一起放大，整排图标的底边位置不变
UltChargeBar         true = 精纯杀气的充能进度直接填充在绝招图标上（从下往上）；false = 隐藏

PinHudBars           true = 把游戏原生血条 / 杀气条固定在游戏最初设定的长度
HudBarWidth          固定长度（以游戏 UI 自身的单位计，日志会打印两条各自的初值）；-1 = 各用各自的初值
HudNumbers           true = 在原生条上显示「当前值 / 最大值」，不固定条也能打开
HudNumberStyle       side = 血条上方 / 杀气下方；center = 白字居中在每条条身上

MenuKey              按键名，例如 F2、F8；改名后菜单提示会同步
Lang                 菜单语言，取 Scripts\lang 下的语言文件名（如 zh-Hans、en）；
                     留空 = 第一次启动时按游戏语言自动填上

InkMaterial          笔刷材质路径，默认用游戏血条同款的水墨材质，会响应 HpColor/QiColor 着色
Texture              备用笔触贴图路径：材质加载不到时改用这张贴图
TipTexture           笔锋贴图路径

Debug                true 时每 5 秒往日志写一行状态，排查问题用


显示逻辑
--------
- 弧线默认跟随人物在屏幕上的投影位置；人物走出屏幕时会隐藏。
- 如果投影接口不可用，会自动退回到 FixedAnchorX/Y 的固定位置。
- 显示时机由 Visibility 决定：
  hud = 跟随游戏 HUD 显隐；dynamic = 动态隐藏，血条和杀气条
  各自计时，满值持续 HideDelay 秒后只隐藏那一条，数值掉下来后重新出现，没满时
  仍跟随游戏 HUD 显隐；HUD 本身一隐藏（脱战、过场）弧线和图标就立刻一起隐藏，
  不再等 HideDelay。
  三种设置在打开地图、设置、背包、主菜单时都会隐藏，菜单里编辑时除外。
- 低量警告只影响颜色和闪烁，不改变显示时机。
- 低量时弧线变为 WarnColor 并闪烁；两条弧的阈值可以分开设置。
- 数值归零时弧线主体为空，但开启笔锋（ShowTip）的情况下笔锋仍留在起点
  并继续闪烁，方便看出该条已经见底。

- 药瓶图标直接取自游戏 HUD，所以图标样式与游戏内一致：
  按「下方、上方」的顺序排列，只装备一个时只显示那一个；
  数量用完后游戏会收起数字，此时仍显示 0（图标变灰），
  没有装备的药瓶不显示。
- 绝招一组由两个数字组成：左边是绝招层数（紫色气焰图标），右边是暗源数量
  （红白漩涡图标）。两个数字共用「显示绝招 / 隐藏绝招」开关，一起出现、一起隐藏。
  数值为 0 时数字同样显示 0，图标变暗；游戏界面上没有暗源（未装备）时，
  暗源那一项不显示。
- 精纯杀气的充能进度直接填在绝招图标里（和药瓶一样是图标本体填充，不是单独一条
  进度条）：攒到的部分按正常亮度显示，没攒到的部分保持图标原来的样子，填充从图标
  底部往上长，不额外改变图标颜色。它跟着图标一起显隐、一起被 IconScale 放大；
  不需要的时候在 settings.ini 里把 UltChargeBar 改成 false，图标就完全不受进度
  影响。暗源没有对应的进度数据，所以只有绝招这一项有填充。
- 图标后面的数字只要为 0 就用警示色（与弧线低量警告同一个颜色，
  在 settings.ini 的 WarnColor 里改），有数量时保持原本的浅色。
- 两组图标默认排在屏幕下方中间、距离底边 152 像素，整体大小由 IconScale 调整；
  打开 F2 菜单后按住左键，所有图标作为一个整体一起移动，
  按住右键只移动指针下的那一个，点一下中键全部图标回到默认位置；松开鼠标后位置
  写回 settings.ini。打开地图、背包、设置或主菜单时不显示。
- 图标的显隐跟随游戏 HUD；动态隐藏的「值满隐藏」只作用于弧线，不影响图标。
- 打开 F2 菜单时，弧线和图标排在菜单的暗色遮罩之上，调位置、调大小的同时仍然
  能看清自己的数值；鼠标移进面板时面板才浮到最上层，移出后面板回到弧线和图标之下。


已知限制
--------
- 弧线由多段笔触重叠拼成，用来盖住接缝；分段太少或 StrokeOverlap 太小时
  会重新露出“一节一节”的边缘。
- 游戏内容已打包，未额外制作贴图，只复用游戏现有的水墨材质并着色。
- 绝招图标是游戏 UI 里的静态火苗剪影染成紫色，不是游戏内那团粒子气焰。
- 图标本体的充能填充按矩形边界裁切，明暗分界线是一条水平直线，不会跟着火苗的
  轮廓走。
- 菜单使用游戏鼠标位置，极少数 UI 缩放设置下可能需要重新打开一次菜单校准。
- 原生条的固定长度以游戏 UI 自身的单位计（日志会打印两条各自的初值，可以照着填
  HudBarWidth）。
- 只支持单人玩家自己的数值，不显示敌人或队友（未测试联机MOD兼容性）。


排查
----
- 没有任何弧线：先确认 UE4SS 本身已注入；再看
  Scripts\PBZArcs.log 里是否出现 “v0.3.0 loaded”。
- 有日志但没有弧线：确认已读取存档并进入可操作状态。
- 想反馈问题：把 Debug 改成 true，重启游戏，复现后提供
  Scripts\PBZArcs.log。


EN：
====
Phantom Blade Zero · Arc HP / Sha-Chi Bars (PBZPlayerArcs)
=====================================================

Draws an arc bar on each side of the player character: HP on the left and Sha-Chi on
the right by default. It also lays out the potion, Sha-Chi Essence and Dark Source
counts along the bottom of the screen (icon + number). It only reads player values and
does not modify any game data.

This mod is built for Phantom Blade Zero 1.0.1 and is compatible with the latest 11.4
update. It is a Lua mod that only reads player values and the game's base assets, so it
should in theory stay compatible with any future update.


Installation
------------
1. Make sure UE4SS is installed.
2. Put the whole PBZPlayerArcs folder into:
   ...\PBZ\platform\steam\ue4ss\Mods\PBZPlayerArcs
   You should end up with:
   ...\Mods\PBZPlayerArcs\enabled.txt
   ...\Mods\PBZPlayerArcs\Scripts\main.lua
   ...\Mods\PBZPlayerArcs\Scripts\settings.ini
   ...\Mods\PBZPlayerArcs\Scripts\preset\preset1.ini
3. Start the game. The arc bars appear once you load a save and gain control of the
   character. You do not need to edit mods.txt; having enabled.txt is enough to
   enable the mod.


Keys
----
F2        Open / close the settings menu (changes are saved to settings.ini
          automatically). To rebind, change MenuKey in settings.ini, for example
          MenuKey = F8
ESC       While the menu is open, save and close it; while the menu is closed the key
          still goes to the game (fixed, cannot be rebound)
LMB       In the menu, hold a slider and drag it left/right; click the toggle buttons
          and drop-downs. With the menu open, hold anywhere on the icons to move all
          icons together
RMB       With the menu open, hold one icon to move only that icon
Mouse wheel  In the menu, with the pointer over a slider, scroll to fine-tune the
          value (1 per notch, 0.1 on decimal sliders)
MMB       In the menu, with the pointer over a slider, click to restore that item's
          built-in default. With the menu open, click an icon to return all icons to
          their default position


Menu and config file
--------------------
The menu and settings.ini read and write the same file: Scripts\settings.ini.
Changes made in the menu take effect immediately and are written back about 0.35 s
later; the file is also saved once when the menu closes. You can also edit the file
outside the game, and it takes effect after restarting the game. When writing back,
only the values are replaced, so the Chinese comments and blank lines in the file are
kept exactly as they are.
settings.ini starts with Lang (menu language) and MenuKey (menu key); the preset name
and the values follow.

In the top-right corner of the menu is the language drop-down: the "语言 / Language"
label on the left, and the button on the right expands the list of languages. While it
is open the arrow on the button flips, and it closes after you pick a language or click
somewhere else.
All menu text lives in language files under Scripts\lang (zh-Hans.ini Chinese, en.ini
English), one "key = displayed text" per line. Edit and save the file, then press F2
again to see the change in the menu.
The file name is the game's own language code (a region-tagged code such as en-US
falls back to en when looking for the file); on the first launch the menu simply
uses the game's language and stores it in Lang.
Which languages the drop-down lists is decided by Scripts\lang\languages.ini: one
language file name per line (without .ini), in the order they appear in the file. To
add your own language, copy a file and rename it to something like fr.ini, change
lang.name at the top (that is what the drop-down shows), then add a line fr to
languages.ini. No code changes needed.
"All / HP only / Sha-Chi only / No arcs" is also a drop-down; pick an option from the
pop-up list.
The buttons are arranged in two rows of six: the first row is follow character, ghost
trail, brush tip, potions, ultimate, pin HUD bars; the second row is display timing,
display scope, HP left / Sha-Chi left, show numbers, number style (above / below or
inside bars), reset to default.
On the first row, "potions shown / potions hidden" and "ultimate shown / ultimate
hidden" control the two icon groups respectively.
Hovering a slider, toggle or drop-down floats a short note next to the pointer
explaining what that item controls.


Presets
-------
In the top-right corner of the menu, to the left of the language bar, is the preset
drop-down showing the current preset name; to its right are the two small buttons
"Save" and "New", and then the language bar.

- Drop-down: starts from the factory defaults, overlays the differences written in the
  preset file, and replaces the whole set of settings; it takes effect immediately and
  is written back to settings.ini. Any key the preset file does not mention reverts to
  its default value.
- Save: writes only the entries that differ from the defaults into the currently
  selected preset file; entries changed back to their default disappear from the file.
  A preset file is therefore a list of differences, not a full snapshot.
- New: creates a new preset from the current differences, named in sequence (preset 3,
  preset 4, ...) and switches to it.
- Reset to default: restores the values stored in the *current preset* (defaults plus
  that preset's differences), not the factory defaults. A single item can also be reset
  to its built-in default with a middle click on its slider.

Presets live in the mod's Scripts\preset folder, one file per preset: preset1.ini,
preset2.ini, ... The numbering must be contiguous (the list stops at the first gap).
Each file records only the differences from the defaults, in the same format as
settings.ini, and can be edited outside the game; entries written there override the
defaults. The Preset line in the file is the preset's name: whatever you put there is
what the menu shows, and the mod never rewrites it. Lang and MenuKey are player settings
and live only in settings.ini; the same lines in a preset file are ignored. The Preset
line in settings.ini records the file name of the current preset (for example preset2,
without .ini); matching is by file name only, so changing the display name will not lose
track. If no preset exists for that file name, the menu treats it as a configuration
that has never been saved.

settings.ini is the exception: saving in game always writes every key (a complete set),
so the file stays hand-editable when the menu itself cannot be opened. Only preset files
are difference files.

Two presets ship with the mod: preset 1 is the factory default (it is what settings.ini
starts with, and what a single item resets to), preset 2 is another set with finer
strokes.

The key name in the hint at the top of the menu follows MenuKey: set MenuKey to F8 and
the hint shows F8.

The menu uses the system arrow cursor, which can move anywhere outside the panel.


Pinning the game's own HP / Sha-Chi bars (optional)
---------------------------------------------------
The game's own HP and Sha-Chi bars in the lower-left corner stretch as the maximum
values grow, getting longer and longer late in the game. Switching on "Pin HUD bars"
puts both bars back at the length the game itself gives them. It is on by default
(preset 1 has it on); while it is off the native bars are completely untouched.

"Show numbers" is a separate switch and works without pinning, on both the pinned bars
and the game's own:
- Above / below: the HP number sits above its bar and the Sha-Chi number below it,
  coloured with HpColor / QiColor.
- Inside bars: white text in the middle of each bar (not tied to the filled part), again
  "current / max". The font is deliberately small so it fits the game's thin bars.
Turning on "Pin HUD bars" also turns on "Show numbers"; the numbers switch can then be
turned off on its own. The number style is chosen by the drop-down in the second row.

The length is the one the game gives the two bars when a save starts, so it does not
depend on when you switch the toggle on; the HP and Sha-Chi bars keep their own
proportions. You can also put a value into HudBarWidth in settings.ini to use one length
for both bars, in the same units the game's UI uses (-1 means each bar keeps its own
initial length; the log prints both). If the game's length controls cannot be found, the
native bars are left untouched and the log says so. The numbers live on the same widget
layer as the bars, so they disappear with the HUD in cutscenes and menus.

If you also run another mod that moves or scales the native bars, both write to the
same widget and overwrite each other; use only one of them.


Settings reference (values are based on 1080p and scale with resolution)
-----------------------------------------------------------------------
Preset               File name of the current preset (without .ini), matching the
                     presetN.ini in Scripts/preset/
FollowCharacter      true = follow the character; false = use a fixed screen position
FollowSmoothing      Follow smoothing, 0 = glued to the character, higher = softer
FixedAnchorX/Y       Relative screen position used when not following (0-1)
AnchorHeight         How far to raise the reading above the character position (cm)
AnchorOffsetX/Y      Overall offset of both arc bars, in 1080p pixels

Radius               Arc radius, default 195 (larger = further from the body)
Thickness            Stroke thickness, default 12
ArcSpan              Arc opening angle, default 60 degrees
Segments             Number of segments, default 45; more is smoother, but costs more
                     performance
HpOnLeft             true = HP left, Sha-Chi right; false = Sha-Chi left, HP right
BrushJitter          Random jitter of the brush strokes, default 0 (cleanest edges);
                     raising it randomises each stroke for a more hand-drawn look, at
                     the cost of fine stray hairs along the arc edge
StrokeOverlap        How many times the segment length each stroke is drawn, default
                     9.5; larger overlaps neighbouring strokes for a more continuous
                     line, smaller makes the joints between segments visible

BarOpacity           Overall opacity of both arc bars
TrackOpacity         Opacity of the background track (empty slot)
GhostOpacity         Ghost trail opacity. The trail shows the segment that was just
                     lost, in a dimmer colour than the real arc, so it is easy to tell
                     apart from the current value
GhostSpeed           How fast the ghost trail retracts; higher is faster
ShowGhost            Whether to show the ghost trail
ShowTip              Whether to show the brush tip at the end of the arc (on by
                     default)
TipScale / TipAngle  Brush tip size and angle

HpColor / QiColor    Main HP / Sha-Chi colour, by default taken from the game HUD
                     (silver-white / gold)
TrackColor           Track colour
WarnColor            Low-level warning colour, red by default

WarnThresholdHp      Low HP threshold, 0.30 = 30%
WarnThresholdQi      Low Sha-Chi threshold, 0.25 = 25%
WarnFlashSpeed       Blink speed (times per second)
WarnFlashAmount      Blink amount, 0 = no blink, 1 = full bright/dim alternation

Visibility           Display timing (same-named drop-down in the menu):
                     hud = follow the game HUD show/hide (fades out with cutscenes and
                     menus)
                     dynamic = dynamic hiding (default): the HP bar and the Sha-Chi
                     bar are judged separately; a bar that stays full for HideDelay
                     seconds is hidden, and reappears as soon as its value drops;
                     while not full it follows the game HUD and hides with it
                     immediately, without waiting
HideDelay            Dynamic-hide delay (seconds), default 3.0; 0 = hide immediately
                     when full
DisplayMode          Display scope: both = HP and Sha-Chi (default) / hp = HP only /
                     qi = Sha-Chi only / off = neither arc (icons are unaffected);
                     the left/right position is still set by HpOnLeft

MedicineHud          true = show potion icons and remaining counts; false = hide
UltHud               true = show ultimate stacks and Dark Source count; false = hide
MedicineHudX/Y       Screen position of the potion icons (1080p pixels);
                     -1 = place them automatically bottom-centre, 152 pixels from the
                     bottom edge. Dragging the icons while the menu is open writes the
                     actual position
UltHudX/Y            Screen position of the ultimate icon group, same rules as above
Med1OffX/Med1OffY    Offset of a single icon inside its group (pixels), 0 = arrange
Med2OffX/Med2OffY    automatically in order; right-dragging a single icon writes it,
Ult1OffX/Ult1OffY    middle-clicking an icon clears it
Ult2OffX/Ult2OffY
IconScale            Overall icon size (0.5-3), default 1.0; icons, numbers and the
                     spacing between them scale together while the bottom edge of the
                     row stays where it is
UltChargeBar         true = the Sha-Chi Essence charge fills the ultimate icon
                     directly (bottom to top); false = hide

PinHudBars           true = put the game's own HP / Sha-Chi bars back at the length the
                     game gives them
HudBarWidth          Fixed length in the game UI's own units (the log prints both
                     initial values); -1 = each bar keeps its own initial length
HudNumbers           true = show "current / max" on the native bars; works without the
                     pin as well
HudNumberStyle       side = HP above / Sha-Chi below; center = white text centred in
                     each bar

MenuKey              Key name, for example F2 or F8; the menu hint follows the new name
Lang                 Menu language, a language file name under Scripts\lang
                     (for example zh-Hans, en); empty = taken from the game's
                     language on the first launch

InkMaterial          Brush material path; by default the same ink material as the
                     game's HP bar, which responds to HpColor/QiColor tinting
Texture              Fallback stroke texture path, used when the material cannot be
                     loaded
TipTexture           Brush tip texture path

Debug                When true, writes one status line to the log every 5 seconds, for
                     troubleshooting


Display logic
-------------
- The arc bars follow the character's projected position on screen by default; they
  hide when the character leaves the screen.
- If the projection interface is unavailable, the mod falls back to the fixed position
  from FixedAnchorX/Y.
- Display timing is decided by Visibility:
  hud = follow the game HUD show/hide; dynamic = dynamic
  hiding, where the HP bar and the Sha-Chi bar are timed separately, and a bar that
  stays full for HideDelay seconds is the only one hidden, coming back as soon as its
  value drops; while not full they still follow the game HUD, and as soon as the HUD
  itself hides (out of combat, cutscene) the bars and icons hide with it immediately,
  without waiting for HideDelay.
  All three settings hide the bars and icons while the map, settings, inventory or main
  menu is open, except while editing in the menu.
- The low-level warning only changes colour and blinking; it does not change the
  display timing.
- When a value runs low the bar turns WarnColor and blinks; the thresholds of the two
  bars are set separately.
- When a value reaches zero the body of the bar is empty, but with the brush tip
  (ShowTip) enabled the tip stays at the starting point and keeps blinking, so you can
  see that the bar has hit bottom.

- Potion icons come straight from the game HUD, so they look exactly like the in-game
  ones: ordered bottom then top, and with only one equipped only that one is shown;
  when the count runs out the game hides the number, but 0 is still displayed (the icon
  greys out), and potions you do not have equipped are not shown.
- The ultimate group is made of two numbers: on the left the ultimate stacks (purple
  flame icon), on the right the Dark Source count (red-and-white vortex icon). Both
  numbers share the "ultimate shown / ultimate hidden" toggle and appear and hide
  together. At 0 the number still shows 0 and the icon dims; when there is no Dark
  Source in the game UI (not equipped), that entry is not shown.
- The Sha-Chi Essence charge fills the ultimate icon itself (an icon-body fill just
  like the potions, not a separate progress bar): the charged part is shown at normal
  brightness, the uncharged part keeps the icon's original look, and the fill grows
  from the bottom of the icon upwards without changing the icon's colour. It shows and
  hides with the icon and scales with IconScale; if you do not want it, set
  UltChargeBar to false in settings.ini and the icon is completely unaffected by the
  charge. The Dark Source has no corresponding charge data, so only the ultimate entry
  has a fill.
- The number behind an icon uses the warning colour whenever it is 0 (the same colour
  as the bar's low warning; change it with WarnColor in settings.ini), and keeps its
  original light colour while it has a count.
- Both icon groups sit bottom-centre of the screen by default, 152 pixels from the
  bottom edge, and their overall size is set by IconScale. With the F2 menu open,
  holding the left button moves all icons together as one, holding the right button
  moves only the one under the pointer, and a middle click returns all icons to their
  default position; on release the position is written back to settings.ini. They are
  not shown while the map, inventory, settings or main menu is open.
- Icon visibility follows the game HUD; dynamic hiding's "hide when full" applies only
  to the arcs, not the icons.
- While the F2 menu is open the bars and icons sit above the menu's dark backdrop, so
  you can still read your own values while moving and resizing them; the panel only
  comes to the front when the cursor moves into it, and drops back below the bars and
  icons when the cursor leaves.


Known limitations
-----------------
- The bars are built from overlapping strokes that cover the seams; too few segments
  or too small a StrokeOverlap makes the "section by section" edges visible again.
- The game content is already packaged and no extra textures are made; the mod only
  reuses the game's existing ink material and tints it.
- The ultimate icon is a static flame silhouette from the game UI tinted purple, not
  the in-game particle flame.
- The icon-body charge fill is clipped to a rectangle, so the line between bright and
  dim is a straight horizontal one and does not follow the flame's outline.
- The menu uses the game's cursor position; with a few unusual UI-scale settings you
  may need to reopen the menu once to recalibrate.
- The pinned length is in the game UI's own units (the log prints both initial values,
  so you can copy one into HudBarWidth).
- Only the single player's own values are supported; enemy and ally values are not
  shown (compatibility with multiplayer mods is untested).


Troubleshooting
---------------
- No bars at all: first check that UE4SS itself is injected, then whether
  "v0.3.0 loaded" appears in Scripts\PBZArcs.log.
- A log exists but there are no bars: make sure you have loaded a save and are in
  control of the character.
- To report a problem: set Debug to true, restart the game, reproduce the issue and
  provide Scripts\PBZArcs.log.

