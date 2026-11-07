--[[
  PBZPlayerArcs - 弧形血条/杀气条（水墨风格，跟随人物）

  只读游戏数据，不修改玩家状态。
  画法：UMG 自带的笔触贴图沿弧线分段旋转，左右各一条。
  F2 打开设置菜单。设置写在同目录 settings.ini。
]]

local Config = require('PBZArcsConfig')
local Stats = require('PBZArcsStats')
local Follow = require('PBZArcsFollow')
local Render = require('PBZArcsRender')
local Menu = require('PBZArcsMenu')
local Icons = require('PBZArcsIcons')
local HudBars = require('PBZArcsHudBars')

-- 状态轨迹只在 Debug 打开时写；真正的问题走 alert，任何时候都写。
local debugOn = false
local function rawLog(message) Config.log('[main] ' .. tostring(message)) end
local function log(message) if debugOn then rawLog(message) end end
local function alert(message) rawLog(message) end

local Util = require('PBZArcsUtil')
local valid, prop, unwrap = Util.valid, Util.prop, Util.unwrap
local VIS = Util.VIS

---------------------------------------------------------------------------------------------------
-- 窗口 / HUD 辅助函数

local cachedPC = nil
local function localPC()
  if valid(cachedPC) then return cachedPC end
  local engine = FindFirstOf('GameEngine') or FindFirstOf('Engine')
  if not valid(engine) then return nil end
  local gi = prop(engine, 'GameInstance')
  if not valid(gi) then return nil end
  local players = prop(gi, 'LocalPlayers')
  if not players or #players < 1 then return nil end
  local localPlayer = unwrap(players[1])
  if not valid(localPlayer) then return nil end
  local pc = prop(localPlayer, 'PlayerController')
  if valid(pc) then
    cachedPC = pc
    return pc
  end
  return nil
end

local function cleanupWidgets(prefix)
  local ok, list = pcall(function() return FindAllOf('UserWidget') end)
  if not ok or type(list) ~= 'table' then return end
  for i = 1, #list do
    local widget = list[i]
    if valid(widget) then
      local okName, name = pcall(function() return widget:GetFName():ToString() end)
      if okName and type(name) == 'string' and name:find(prefix, 1, true) == 1 then
        pcall(function() widget:RemoveFromParent() end)
      end
    end
  end
end

local function widgetChainVisible(widget, skipViewportCheck)
  local cur = widget
  local root = widget
  local factor = 1
  for _ = 1, 8 do
    if not valid(cur) then return false, 0, true end
    local okV, visibility = pcall(function() return cur.Visibility end)
    -- 第三个返回值是「硬隐藏」：只认 Visibility 的 Collapsed/Hidden，
    -- 不看 RenderOpacity。常态显示需要忽略淡出，但必须尊重这个状态。
    if okV and (visibility == VIS.Collapsed or visibility == VIS.Hidden) then return false, 0, true end
    -- factor 是游戏 HUD 当前的「连续不透明度」。RenderOpacity 刚从 1 掉下来的
    -- 那一帧就是游戏开始淡出的最早信号，比 Visibility 变 Hidden 早一整段动画。
    local okO, opacity = pcall(function() return cur.RenderOpacity end)
    if okO and type(opacity) == 'number' then
      factor = math.min(factor, math.max(0, math.min(1, opacity)))
    end
    local okP, parent = pcall(function() return cur:GetParent() end)
    if not okP or not valid(parent) then break end
    cur = parent
    root = parent
  end
  if not skipViewportCheck then
    -- 游戏一次性构建并缓存的控件（地图、背包、菜单）即使脱离视口后仍标记为
    -- 可见，所以这条链必须最终落在一个位于视口内的控件上。
    local okIn, inViewport = pcall(function() return root:IsInViewport() end)
    if okIn and inViewport ~= true then return false, 0, false end
  end
  return factor > 0.01, factor, false
end

-- HUD 显隐探测。FindAllOf 要遍历全部 UObject，是全 MOD 单次最贵的操作，
-- 而 hudVisible() 常态下每秒要问 20 次，所以候选控件只扫描一次并留下清单。
--
-- 两件事必须分开记：
--   · 清单（留一次扫描结果）可以缓存，否则每帧都要遍历全部 UObject；
--   · 结论（此刻算不算显示）绝不能缓存，游戏换 HUD 实例之后旧实例往往仍然
--     valid()、类名也对，只是已经离场，父链不透明度恒为 0 —— 一旦把「上次选中
--     的那个控件」当成结论钉死，「HUD 隐藏」就再也不变，弧线和图标只在菜单
--     打开（强制显示）时才出现。
--
-- 分层是硬要求：血条控件命中就用血条控件，只有它一个有效实例都没有时才退到
-- 前台布局。两者不能放进同一个「或」里 —— 前台布局在游戏里常驻可见，混在
-- 一起会让 MOD 永远认为 HUD 在显示，从而不再跟着 HUD 一起隐藏。
local HUD_TIERS = { 'WB_PlayerHPBar_V1_C', 'W_FrontEndHUDLayout_C' }
-- 隐藏状态下重扫清单的最小间隔。只有「清单空了 / 候选失效 / PC-Pawn 换了 /
-- 隐藏超过 HUD_LIST_TTL」才重扫，光「这一刻不可见」不算理由 —— 否则常态满血
-- 隐藏时每秒要扫 4~5 次，既浪费又正好和读档换世界撞在一起。
local HUD_RESCAN_GAP = 0.25
local HUD_LIST_TTL = 1.0
-- 关卡加载期间完全不碰游戏控件：这时候旧世界的 UObject 正在被销毁，
-- 读它们的属性会直接崩在引擎里（crash dump 就是 UE4SS 层的 ACCESS_VIOLATION，
-- 读到的地址是野指针）。PreHook 一进来就清空清单并挂起探测，
-- PostHook 恢复；万一 PostHook 没来，最多 LOAD_GUARD_MAX 秒后自动解开。
local LOAD_GUARD_MAX = 20
-- PostHook 之后新世界的 UMG 还在搭建，且引擎的垃圾回收往往在这之后才把旧世界的
-- 对象真正释放。这段时间照旧什么都不读，让世界先落定。
local LOAD_SETTLE = 1.0
-- 沉降之后的第二道门：图标与原生条要做「遍历控件树、读材质标量数组」这类重活。
-- 判据是「游戏 HUD 此刻在不在屏幕上」——不是「出现了多久」。
--   · HUD 在渲染，说明新世界的 UMG 已经构建完毕，控件是稳定的；
--   · 反过来，控件存在但 HUD 还没显示，正是「构建中 / 即将被回收」的中间态，
--     崩溃就发生在这段时间（旧版实测拆的 dump：TArray 越界检查里读到坏指针）。
-- 这里故意不留观察窗口：试过「连续可见 1.5 秒」「连续可见 3 帧」，玩家都能看见
-- 原生条在眼前从游戏长度缩到钉住长度（HUD 出现的那一刻正是他开始看它的时刻）。
-- HUD 一出现就是安全的，所以当帧放行。
-- 兜底时长：停在主界面 / 菜单里 HUD 一直不出现时，不能让重模块永远不干活。
local SETTLE_FALLBACK = 10.0
local hudPick = { tiers = { {}, {} }, count = 0, at = -HUD_RESCAN_GAP, ready = false,
  dirty = true, stale = false, loading = false, loadingAt = 0, settleAt = 0,
  pc = nil, pawn = nil }
-- 重模块（图标 / 原生条）是否已恢复；heavyHeld 记录「上锁时已经把图标收过一次」。
local heavyReady, heavyHeld = true, false

local function clearHudPick()
  for t = 1, #hudPick.tiers do
    local tier = hudPick.tiers[t]
    for i = #tier, 1, -1 do tier[i] = nil end
  end
  hudPick.count, hudPick.ready, hudPick.dirty, hudPick.stale = 0, false, true, false
  hudPick.pc, hudPick.pawn = nil, nil
end

local function collectTier(cls, pcName, out)
  local ok, list = pcall(function() return FindAllOf(cls) end)
  if not ok or type(list) ~= 'table' then return end
  local items, scores = {}, {}
  for _, widget in ipairs(list) do
    if valid(widget) then
      local okN, name = pcall(function() return widget:GetFullName() end)
      if okN and type(name) == 'string' and not name:find('Default__', 1, true) then
        -- 打分只用来排顺序：属于本机 PlayerController 的优先（2 分），
        -- 此刻没被 Collapsed/Hidden 的次之（1 分）。是否真的可见由 probeTier
        -- 逐个走父链确认，这个启发式不参与结论。
        local score = 0
        if pcName ~= nil then
          local okO, owner = pcall(function() return widget:GetOwningPlayer() end)
          if okO and valid(owner) then
            local okON, ownerName = pcall(function() return owner:GetFullName() end)
            if okON and ownerName == pcName then score = 2 end
          end
        end
        local okV, vis = pcall(function() return widget.Visibility end)
        if okV and not (vis == VIS.Collapsed or vis == VIS.Hidden) then
          score = score + 1
        end
        items[#items + 1] = widget
        scores[#scores + 1] = score
      end
    end
  end
  -- 插入排序按分数降序。候选只有个位数，不值得为它起一个比较闭包。
  for i = 2, #items do
    local widget, score = items[i], scores[i]
    local j = i - 1
    while j >= 1 and scores[j] < score do
      items[j + 1], scores[j + 1] = items[j], scores[j]
      j = j - 1
    end
    items[j + 1], scores[j + 1] = widget, score
  end
  for i = 1, #items do out[i] = items[i] end
end

local function buildHudList()
  local pc = localPC()
  local pcName = nil
  if valid(pc) then
    local ok, name = pcall(function() return pc:GetFullName() end)
    if ok then pcName = name end
  end
  local total = 0
  for t = 1, #HUD_TIERS do
    local tier = hudPick.tiers[t] or {}
    for i = #tier, 1, -1 do tier[i] = nil end
    collectTier(HUD_TIERS[t], pcName, tier)
    hudPick.tiers[t] = tier
    total = total + #tier
  end
  hudPick.count, hudPick.at, hudPick.ready = total, os.clock(), true
  hudPick.dirty = false
  hudPick.pc, hudPick.pawn = pc, prop(pc, 'Pawn')
  if debugOn then
    log('hud pick: ' .. #hudPick.tiers[1] .. '+' .. #hudPick.tiers[2] .. ' candidate(s)')
  end
end

-- 同一层里按分数顺序取「第一个没被硬隐藏（Collapsed / Hidden）的候选」：
-- 常态下就是第一个，一次父链检查就够；游戏换了实例时旧实例先 Collapsed，
-- 自然落到新实例上。返回第 4 个值表示这一层到底有没有有效实例，
-- 用来决定要不要退到下一层；顺手把「有候选已经失效」记到 stale 上。
local function probeTier(items)
  local firstVisible, firstFactor, firstHidden = nil, 0, true
  local any = false
  for i = 1, #items do
    local widget = items[i]
    if valid(widget) then
      any = true
      local visible, factor, hardHidden = widgetChainVisible(widget, true)
      if not hardHidden then return visible, factor, hardHidden, true end
      if firstVisible == nil then firstVisible, firstFactor, firstHidden = visible, factor, hardHidden end
    else
      hudPick.stale = true
    end
  end
  if firstVisible ~= nil then return firstVisible, firstFactor, firstHidden, true end
  return nil, 0, true, any
end

-- 返回：是否显示 / 连续不透明度 / 是否被硬隐藏（Collapsed、Hidden）。
-- 第一个返回值为 nil 表示连候选控件都没有（读图、进游戏前）。
local function probeHud(now)
  if hudPick.loading then
    -- 加载中：清单已经清空，绝不回去读旧对象的任何属性。
    if now - hudPick.loadingAt > LOAD_GUARD_MAX then hudPick.loading = false end
    return nil, 0, true
  end
  if now < hudPick.settleAt then return nil, 0, true end

  if hudPick.ready then
    -- 换了 PlayerController 或 Pawn（读图、复活、切场景）必然换了 HUD 实例，
    -- 直接作废清单，不必等可见性验证失败。
    local pc = localPC()
    local pawn = valid(pc) and prop(pc, 'Pawn') or nil
    if pc ~= hudPick.pc or pawn ~= hudPick.pawn then hudPick.dirty = true end
  end
  if (not hudPick.ready or hudPick.dirty) and now - hudPick.at >= HUD_RESCAN_GAP then
    pcall(buildHudList)
  end

  hudPick.stale = false
  for t = 1, #HUD_TIERS do
    local visible, factor, hardHidden, any = probeTier(hudPick.tiers[t])
    if any then
      -- 只有隐藏状态下才按 TTL 定期重扫：隐藏时游戏可能换了新实例，
      -- 而常态显示时一个候选就够用，不必再花 FindAllOf 的钱。
      hudPick.dirty = hudPick.stale
        or (not visible and now - hudPick.at >= HUD_LIST_TTL)
      return visible, factor, hardHidden
    end
  end
  hudPick.dirty = true
  return nil, 0, true
end

---------------------------------------------------------------------------------------------------
-- 设置与模块

Config.initLog()
local existingIni = io.open(Config.INI, 'r')
if existingIni then existingIni:close() end
local S, firstUse = Config.load()
debugOn = S.Debug == true
-- 首次运行，或文件里还没有语言项：回写一次，把这个选择保存下来。
if not existingIni or firstUse then Config.save(S) end
Config.log('loaded settings (' .. Config.INI .. ')')

local stats = Stats.new()
local follow = Follow.new(S, log)
local render = Render.new(S, rawLog)

local pendingRebuildAt = nil
local REBUILD_KEYS = {
  Radius = true, Thickness = true, ArcSpan = true, Segments = true, BrushJitter = true,
  HpOnLeft = true, ShowTip = true, Texture = true, TipTexture = true,
  StrokeOverlap = true,
  -- 换一个预设等于同时换掉一批设置，整组弧线重建一次最省事。
  Preset = true,
}
local COLOUR_KEYS = { HpColor = true, QiColor = true, TrackColor = true, WarnColor = true }

local function onChange(key)
  debugOn = S.Debug == true
  if REBUILD_KEYS[key] then
    pendingRebuildAt = os.clock() + 0.25
  elseif COLOUR_KEYS[key] then
    pcall(function() render:applyColours() end)
  end
end

local menu = Menu.new(S, { log = log, alert = alert, onChange = onChange })
local icons = Icons.new(S, rawLog)
local hudBars = HudBars.new(S, rawLog)
-- 选「关闭原生条」时读数要挂在弧形条上，所以把 Render 交给它。它只读
-- group / tree 和每条弧的淡出值，不会反过来驱动弧线。
hudBars:setArcs(render)

-- 崩溃现场定位用：只在 Debug 打开时，按「子系统切换」打一行。真崩了以后
-- 日志最后一行就是崩之前正在跑的子系统，比事后猜便宜得多。
local lastMark = nil
local function mark(name)
  if not debugOn or name == lastMark then return end
  lastMark = name
  log('phase: ' .. name)
end

---------------------------------------------------------------------------------------------------
-- 运行时状态

if PBZARCS_RUNTIME and PBZARCS_RUNTIME.shutdown then
  pcall(PBZARCS_RUNTIME.shutdown)
end

local RT = { alive = true, lastTick = nil }
PBZARCS_RUNTIME = RT

-- 读档 / 过图的保护期。别在这里读任何游戏控件：旧世界的 UObject 正在被销毁，
-- 读属性会把野指针交给引擎（实测就是读档瞬间 ACCESS_VIOLATION 崩在 UE4SS.dll）。
-- 只有「有 PostHook 能放行」时才挂起探测，否则宁可不清也不要把自己锁在隐藏状态。
local loadPostAvailable = RegisterLoadMapPostHook ~= nil
if RegisterLoadMapPreHook then
  local ok, err = pcall(function()
    RegisterLoadMapPreHook(function()
      -- 这个回调在引擎的 LoadMap 里跑，只做纯 Lua 的记账：丢掉候选清单、
      -- 挂起探测。真正的隐藏交给下一个 step tick，别在这个时机动 UMG。
      hudPick.loading, hudPick.loadingAt = loadPostAvailable, os.clock()
      -- 万一这个版本没有 PostHook，就从这里开始算沉降，别让保护期一解开
      -- 就立刻去重建。PostHook 来了会再刷新一次。
      hudPick.settleAt = os.clock() + LOAD_SETTLE
      -- 图标和原生条重新上锁：这次的崩溃就是它们在新世界刚落地时去遍历
      -- 控件树撞上旧对象回收。等新世界的 HUD 重新出现在屏幕上再放行。
      heavyReady, heavyHeld = false, false
      clearHudPick()
      -- 统计模块 / 图标 / 游戏条里的缓存同样全是旧世界的对象，一起作废。
      -- 只丢引用，不还原、不 RemoveFromParent：那些控件此刻可能正在被销毁。
      if RT.onWorldTeardown then RT.onWorldTeardown() end
      log('hud pick: cleared (map load start)')
    end)
  end)
  if not ok then alert('LoadMapPreHook failed: ' .. tostring(err)) end
end
if RegisterLoadMapPostHook then
  local ok, err = pcall(function()
    RegisterLoadMapPostHook(function()
      hudPick.loading = false
      -- 新世界的 HUD 要过一会儿才真正建好；这段时间照样什么都不读，
      -- 免得在「半初始化」的控件上取属性。
      hudPick.settleAt = os.clock() + LOAD_SETTLE
      heavyReady, heavyHeld = false, false
      clearHudPick()
      log('hud pick: resumed (map load done)')
    end)
  end)
  if not ok then alert('LoadMapPostHook failed: ' .. tostring(err)) end
end

local master = 0
local lastScale = 1
local nextBuildTry = 0
local heldSnapshot, heldAt = nil, nil
local lastStatsWarn = -100
local lastDebugAt = -100
local lastIconsError = -100
local lastBarsError = -100
local hudSeenVisible = false
local hudHiddenSince = nil
local fullSince = { hp = nil, qi = nil }
local FULL_RATIO = 0.995
-- 统计读数短暂沿用上一帧的最长时间（只用于盖住复活这种一两帧空档）。
local HOLD_SNAPSHOT_MAX = 0.5
-- 实机结论：0.2 有明显延迟；0.05 一直跟手；再压到 0.01 会让常态几乎每帧
-- 都跑一次全量 FindAllOf，帧耗时抖动 + 采样周期逼近帧间隔（60fps≈16.7ms）
-- 造成相位不稳，反而偶发不跟手。固定 0.05，别再调这个值。
-- 淡出/淡入期间由下面的自适应分支逐帧镜像，跟手程度不再由它决定；
-- 它只负责「常态」采样，以及发现游戏 HUD 开始隐藏的起点延迟。
local HUD_POLL_INTERVAL = 0.05
local HUD_FADE_MIN, HUD_FADE_MAX = 0.01, 0.999
-- 观测到的游戏 HUD 常态不透明度。镜像时按它归一化，这样即便游戏把 HUD
-- 整体设成 0.9，MOD 常态仍是满亮，跟随的只是「相对淡出进度」。
local hudBaseAlpha = 0
local hudCacheAt = -1
local hudCacheVisible, hudCacheFactor, hudCacheHidden = nil, 1, false
local lastMenuOpen = false
local traceTicks = 0
local pending = { toggle = false, click = false, rclick = false, mclick = false,
  close = false }

-- 换世界时把「跨帧持有的旧对象」全部作废。这一步是这次崩溃的正解：
-- 上一版只清了 HUD 候选清单，统计模块的快照、图标缓存的槽位控件、
-- 游戏条绑定的材质都还指着旧世界；换图后引擎把它们销毁，我们再去做
-- ProcessEvent / 读属性，就是 ACCESS_VIOLATION（crash dump 落在 UE4SS.dll）。
-- 这里只做 Lua 侧的引用清理，不调用任何 UObject 方法。
RT.onWorldTeardown = function()
  heldSnapshot, heldAt = nil, nil
  pcall(function() stats:forget() end)
  pcall(function() icons:forget() end)
  pcall(function() hudBars:forget() end)
  follow.pawn = nil
  follow.viewport, follow.viewportAt = nil, -100
  hudCacheAt = -1
  hudSeenVisible, hudHiddenSince = false, nil
  hudBaseAlpha = 0
  fullSince.hp, fullSince.qi = nil, nil
end

cleanupWidgets('PBZArcs_Root_')
cleanupWidgets('PBZArcs_Menu')
cleanupWidgets('PBZArcs_Icons')
pcall(function() render:cleanupOld(nil) end)

local function renderAlive()
  return valid(render.root)
end

local function rebuild()
  local ok, result, err = pcall(function() return render:build() end)
  if not ok then
    pendingRebuildAt = os.clock() + 1.0
    return false, result
  end
  if result == false then
    pendingRebuildAt = os.clock() + 1.0
    return false, err
  end
  pendingRebuildAt = nil
  master = 0
  return true
end

local function readSnapshot(now)
  local snapshot, err = stats:read()
  if snapshot then
    heldSnapshot, heldAt = snapshot, nil
    return snapshot
  end
  -- 短暂沿用上一帧的读数，只为了盖住复活、属性集重建那种一两帧的空档。
  -- 绝不能让它顺着换世界活下来：快照里存着 PlayerController 和 Pawn，
  -- 旧世界一销毁它们就是野指针，Follow 还会拿 Pawn 去调 K2_GetActorLocation
  -- （ProcessEvent），那就是硬崩。
  if heldSnapshot and valid(heldSnapshot.pc) and valid(heldSnapshot.pawn) then
    if heldAt == nil then heldAt = now end
    if now - heldAt < HOLD_SNAPSHOT_MAX then return heldSnapshot, err end
  end
  heldSnapshot, heldAt = nil, nil
  return nil, err
end

local function hudVisible(force)
  local now = os.clock()
  -- 淡出/淡入过程中逐帧重算；常态才走 0.05s 缓存。
  -- force 用于「重模块还在等 HUD 出现」的那段时间：HUD 可能是硬切出现的（没有淡入），
  -- 走 0.05s 缓存会晚 3 帧才认出来，那 3 帧足够让玩家看见原生条在缩短。
  local base = hudBaseAlpha > HUD_FADE_MIN and hudBaseAlpha or 1
  local fading = hudCacheFactor ~= nil and hudCacheFactor > HUD_FADE_MIN
    and hudCacheFactor < base * HUD_FADE_MAX
  if not force and not fading and now - hudCacheAt < HUD_POLL_INTERVAL then
    return hudCacheVisible, hudCacheFactor, hudCacheHidden
  end
  hudCacheAt = now
  local visible, factor, hardHidden = probeHud(now)
  hudCacheVisible, hudCacheFactor, hudCacheHidden = visible, factor, hardHidden
  return visible, factor, hardHidden
end

---------------------------------------------------------------------------------------------------
-- 每帧

local function step(dt)
  if not RT.alive then return true end
  local now = os.clock()

  if pending.toggle then
    pending.toggle = false
    pcall(function() menu:toggle() end)
  end
  if pending.close then
    pending.close = false
    -- 只在菜单接管输入时拦截 ESC；其余时候把 ESC 留给游戏。
    if menu.open then pcall(function() menu:toggle() end) end
  end
  if pending.click then
    pending.click = false
    if menu.open then
      local ok, handled = pcall(function() return icons:press(menu, 'lmb') end)
      if not ok or not handled then pcall(function() menu:click() end) end
    end
  end
  if pending.rclick then
    pending.rclick = false
    if menu.open then pcall(function() icons:press(menu, 'rmb') end) end
  end
  if pending.mclick then
    pending.mclick = false
    if menu.open then
      -- 读数区域上的中键归图标所有；按在别处则把指针下的
      -- 滑块重置为该条目的默认值。
      local ok, handled = pcall(function() return icons:press(menu, 'mmb') end)
      if not ok or not handled then pcall(function() menu:middleClick() end) end
    end
  end

  -- 拖动一组图标期间，面板保持压在读数下方，
  -- 这样图标就不会滑到面板后面。
  pcall(function() menu:poll(dt, icons.dragging ~= nil) end)
  pcall(function() icons:poll(dt) end)

  -- 菜单开合立刻改变 HUD 的显隐需求（step 末尾会读 hudVisible）。
  -- 这里强制下一次采样重算，覆盖 F2 / ESC / 点击关闭等所有开合路径。
  if menu.open ~= lastMenuOpen then
    lastMenuOpen = menu.open
    hudCacheAt = -1
  end

  -- 读档 / 过图期间什么都不读：旧世界的 UObject 正在被销毁，这时候读属性会把
  -- 野指针交给引擎（实测 crash dump 就是 UE4SS 层的 ACCESS_VIOLATION）。
  -- PostHook 之后还留一段沉降期：新世界的 HUD 还没搭完，引擎的回收也常在
  -- 这时才把旧世界的对象真正释放。只把弧线自己收掉 —— 菜单、图标都是 MOD
  -- 自己的控件，不受世界影响。
  if hudPick.loading and now - hudPick.loadingAt > LOAD_GUARD_MAX then
    -- PostHook 没来（或来晚了）：解开保护期的同时重新起算沉降，
    -- 否则这里会立刻去重建，正好撞上引擎回收旧对象的那一段。
    hudPick.loading = false
    hudPick.settleAt = now + LOAD_SETTLE
    heavyReady, heavyHeld = false, false
  end
  if hudPick.loading or now < hudPick.settleAt then
    master = 0
    if renderAlive() then
      render:setMaster(0)
      render:setBarShown('hp', false)
      render:setBarShown('qi', false)
    end
    pcall(function() icons:setShown(false, 0) end)
    return false
  end

  if not renderAlive() then
    if now >= nextBuildTry then
      nextBuildTry = now + 1.0
      local ok, err = rebuild()
      if not ok then alert('HUD build failed: ' .. tostring(err)) end
    end
  elseif pendingRebuildAt ~= nil and now >= pendingRebuildAt then
    local ok, err = rebuild()
    if not ok then alert('HUD rebuild failed: ' .. tostring(err)) end
  end

  mark('stats')
  local snapshot, statsError = readSnapshot(now)
  local trace = S.Debug and snapshot ~= nil and traceTicks < 3
  if trace then
    traceTicks = traceTicks + 1
    log('trace ' .. traceTicks .. ': stats ok')
  end

  mark('follow')
  local anchorX, anchorY, onscreen
  if snapshot then
    local fx, fy, visible, _, scale = follow:update(snapshot, dt)
    if fx ~= nil then anchorX, anchorY = fx, fy end
    if scale then lastScale = scale end
    if visible ~= nil then onscreen = visible end
  else
    anchorX, anchorY = follow.x, follow.y
    onscreen = false
  end
  if trace then log(string.format('trace %d: follow %.0f,%.0f on=%s', traceTicks, anchorX or -1, anchorY or -1, tostring(onscreen))) end
  if renderAlive() then
    render:setUiScale(lastScale)
    if trace then log('trace ' .. traceTicks .. ': scale ' .. string.format('%.3f', lastScale)) end
    if anchorX ~= nil then render:setAnchor(anchorX, anchorY) end
    if trace then log('trace ' .. traceTicks .. ': anchor') end
  end

  local hpRatio, qiRatio, ultRatio
  if snapshot then
    if snapshot.hpMax and snapshot.hpMax > 0 then hpRatio = snapshot.hp / snapshot.hpMax end
    if snapshot.qiMax and snapshot.qiMax > 0 then qiRatio = snapshot.qi / snapshot.qiMax end
    if snapshot.ult and snapshot.ultMax and snapshot.ultMax > 0 then
      ultRatio = snapshot.ult / snapshot.ultMax
    end
  end

  mark('hud')
  -- 等门期间不用 0.05s 采样缓存：HUD 硬切出现时要当帧就认出来。
  local hudShown, hudOpacity = hudVisible(not heavyReady)
  -- 游戏 HUD 的连续不透明度就是「淡出开始」的最早状态：RenderOpacity 刚从
  -- 1 掉下来的那一帧游戏才启动淡出，等到 Visibility 变 Hidden 已经是动画结束，
  -- 那时才让 MOD 开始自己的淡出，必然比游戏晚一整段动画。这里全程镜像这条曲线。
  -- hudShown == nil 表示 HUD 控件根本不存在（读图/主界面），按 0 处理。
  local hudAlpha = (hudShown == nil) and 0
    or math.max(0, math.min(1, tonumber(hudOpacity) or 0))
  if hudAlpha > hudBaseAlpha then hudBaseAlpha = hudAlpha end
  -- 归一化后的淡出进度：游戏从常态淡到 0，MOD 就从 1 淡到 0。
  local hudMirror = hudBaseAlpha > HUD_FADE_MIN
    and math.min(1, hudAlpha / hudBaseAlpha) or hudAlpha
  if hudShown == true then
    hudSeenVisible = true
    hudHiddenSince = nil
  elseif hudShown == false and hudSeenVisible then
    if hudHiddenSince == nil then hudHiddenSince = now end
  end
  local hudOn = hudShown == true
  local hudDimmed = not hudOn and hudSeenVisible
  local hudFaded = hudDimmed and hudHiddenSince ~= nil and (now - hudHiddenSince) > 1.2

  local visible = true
  local hudFactor = 1
  local hpShown, qiShown = true, true
  local visibility = tostring(S.Visibility or 'dynamic'):lower()
  -- 只看 HUD 此刻有没有在显示：HUD 还没出现过（刚进游戏、读图中）也算没显示，
  -- 弧线和图标不再先亮一下再等第一次隐藏。动态隐藏连淡出的 1.2 秒宽限都不等，
  -- HUD 一收起来就立刻跟着消失，HideDelay 只负责「值满」那一种情况。
  local hudGone = not hudOn and (visibility == 'dynamic' or not hudSeenVisible or hudFaded)
  if visibility == 'hud' then
    visible = not hudGone
    hudFactor = hudMirror
    fullSince.hp, fullSince.qi = nil, nil
  else
    -- 动态隐藏（默认）：每条弧线单独计时。满值持续时间达到 HideDelay 后
    -- 只隐藏那一条，掉下来立刻恢复；未满时仍跟随游戏 HUD 显隐。
    local delay = math.max(0, tonumber(S.HideDelay) or 3)
    local function fullFor(ratio, key)
      if ratio == nil or ratio < FULL_RATIO then
        fullSince[key] = nil
        return false
      end
      if fullSince[key] == nil then fullSince[key] = now end
      return (now - fullSince[key]) >= delay
    end
    local hideHp = fullFor(hpRatio, 'hp')
    local hideQi = fullFor(qiRatio, 'qi')
    hpShown, qiShown = not hideHp, not hideQi
    visible = not hudGone and (hpShown or qiShown)
    hudFactor = hudMirror
  end
  if menu.open then
    visible = true
    hudFactor = 1
    hpShown, qiShown = true, true
  end
  if trace then log('trace ' .. traceTicks .. ': visible ' .. tostring(visible)) end

  -- 重模块门控。沉降期只是「按时间等」，这一段是「按信号等」：判据是游戏 HUD
  -- 此刻在不在屏幕上（不是它在屏幕上多久）。HUD 在渲染就说明新世界的 UMG 已经
  -- 搭好、控件稳定；反过来「控件存在但 HUD 没显示」才是构建中/即将回收的中间态。
  -- 没过门之前，图标与原生条一律不碰游戏控件（它们上一次的缓存已经在
  -- onWorldTeardown 里丢干净了）。
  if not heavyReady then
    if hudOn then
      -- 当帧放行：下面紧接着就会跑 icons / bars，玩家看到的第一帧原生条
      -- 已经是钉好的长度，不会出现「先长后短」。
      heavyReady = true
      log(string.format('heavy modules resumed (hud on, after %.2fs)',
        now - hudPick.settleAt))
    elseif now - hudPick.settleAt >= SETTLE_FALLBACK then
      -- 兜底：主界面 / 菜单里 HUD 一直不出现，也不能让原生条永远不干活。
      heavyReady = true
      log('heavy modules resumed (fallback)')
    end
  end

  mark('icons')
  if heavyReady then
    local iconsOk, iconsErr = pcall(function()
      icons:update(dt, {
        menuOpen = menu.open,
        -- 图标与弧线共用同一条游戏 HUD 淡出曲线，不再等「完全隐藏」这个布尔量。
        hudShown = menu.open or hudMirror > 0.01,
        hudFade = menu.open and 1 or hudMirror,
        -- 精纯杀气的充能比例（UltimateCharge / Max），图标模块用它画充能条。
        ultRatio = ultRatio,
      })
    end)
    if not iconsOk and now - lastIconsError > 5 then
      lastIconsError = now
      alert('icons update: ' .. tostring(iconsErr))
    end
  elseif not heavyHeld then
    -- 只在刚上锁时收一次，别每帧都去动自己的控件。
    heavyHeld = true
    pcall(function() icons:setShown(false, 0) end)
  end

  mark('bars')
  if heavyReady then
    local barsOk, barsErr = pcall(function() hudBars:update(dt, snapshot) end)
    if not barsOk and now - lastBarsError > 5 then
      lastBarsError = now
      alert('hud bars update: ' .. tostring(barsErr))
    end
  end

  if renderAlive() then render:setBarShown('hp', hpShown); render:setBarShown('qi', qiShown) end

  local target = (snapshot ~= nil and anchorX ~= nil and onscreen and visible)
    and hudFactor or 0
  if target <= master then
    -- 游戏 HUD 的淡出曲线本身已经平滑过；再叠一次指数滤波等于又晚一拍。
    -- 淡出方向直接镜像，只有淡入方向保留缓动，避免骤然出现。
    master = target
  else
    master = master + (target - master) * math.min(1, math.max(0, dt) * 12)
  end
  if master < 0.01 and target == 0 then master = 0 end

  mark('render')
  if renderAlive() then
    render:setMaster(master)
    if trace then log('trace ' .. traceTicks .. ': master ' .. string.format('%.2f', master)) end
    render:update(snapshot or {}, dt)
    if trace then log('trace ' .. traceTicks .. ': update ok') end
  end

  if S.Debug and now - lastDebugAt > 5 then
    lastDebugAt = now
    local hb, qb = render.hpBar, render.qiBar
    local function barInfo(bar)
      if not bar then return 'nil' end
      local seg = bar.segments and bar.segments[1]
      local alpha, col = 1, nil
      if seg and seg.fill then
        alpha = seg.fill.alpha or 1
        col = seg.fill.color
      end
      local cstr = '?'
      if col then
        cstr = string.format('%.2f/%.2f/%.2f', col.R or -1, col.G or -1, col.B or -1)
      end
      local vis = '?'
      if seg and seg.fill and seg.fill.widget then
        local ok, value = pcall(function() return seg.fill.widget.Visibility end)
        if ok then vis = tostring(value) end
      end
      return string.format('warn=%s ratio=%.2f a=%.2f col=%s vis=%s fo=%.2f to=%.2f',
        tostring(bar.warn), bar.ratio or -1, alpha, cstr, vis,
        bar.lastFillOpacity or -1, bar.lastTrackOpacity or -1)
    end
    log(string.format(
      'hp=%.3f qi=%.3f anchor=%s,%s scale=%.3f master=%.2f onscreen=%s visible=%s vis=%s shown=%s/%s delay=%.1f hud=%s proj=%s',
      hpRatio or -1, qiRatio or -1,
      anchorX and string.format('%.0f', anchorX) or '?',
      anchorY and string.format('%.0f', anchorY) or '?',
      lastScale, master, tostring(onscreen), tostring(visible), tostring(visibility),
      tostring(hpShown), tostring(qiShown), tonumber(S.HideDelay) or 3,
      -- HUD 的显隐和它当前的淡出程度分开打，图标跟着 HUD 走时能看出滞后在哪一侧。
      -- cand 是当前候选清单里的控件数，带 * 表示这次的结论让它作废、等着重扫，
      -- 带 L 表示正处在读档 / 过图的保护期（这段时间不碰游戏控件）。
      string.format('%s/%.2f cand=%d%s%s', tostring(hudShown), tonumber(hudOpacity) or -1,
        hudPick.count, hudPick.dirty and '*' or '', hudPick.loading and 'L' or ''),
      tostring(follow.methodIndex)))
    log('bars hp[' .. barInfo(hb) .. '] qi[' .. barInfo(qb) .. '] th=' .. tostring(S.Thickness) ..
      ' hpcol=' .. tostring(S.HpColor) .. ' qicol=' .. tostring(S.QiColor))
  end

  if snapshot == nil and statsError and now - lastStatsWarn > 10 then
    lastStatsWarn = now
    log('stats unavailable: ' .. tostring(statsError))
  end

  if trace then log('trace ' .. traceTicks .. ': end') end

  return false
end

---------------------------------------------------------------------------------------------------
-- 按键

if RegisterKeyBind and Key then
  local function bind(key, flag)
    if key == nil then return end
    local ok, err = pcall(function() RegisterKeyBind(key, function() pending[flag] = true end) end)
    if not ok then alert('keybind ' .. tostring(flag) .. ' failed: ' .. tostring(err)) end
  end
  local function bindByName(name, flag)
    local keyName = tostring(name or ''):upper()
    local key = keyName ~= '' and Key[keyName] or nil
    if key == nil then
      alert('keybind ' .. tostring(flag) .. ': unknown key "' .. keyName .. '"')
      return
    end
    bind(key, flag)
  end
  bindByName(S.MenuKey or 'F2', 'toggle')
  bind(Key.ESCAPE, 'close')
  bind(Key.LEFT_MOUSE_BUTTON, 'click')
  bindByName('RIGHT_MOUSE_BUTTON', 'rclick')
  bindByName('MIDDLE_MOUSE_BUTTON', 'mclick')
end

---------------------------------------------------------------------------------------------------
-- 主循环与看门狗

function RT.shutdown()
  RT.alive = false
  -- 卸载 / 热重载时把候选控件全部丢掉，别把 UObject 引用带出这次运行。
  clearHudPick()
  -- 没打开过菜单就不要动输入状态：主界面热重载时无条件 setInput(false)
  -- 一样会把 bShowMouseCursor 清掉、把输入切成 GameOnly，让主界面失去鼠标。
  if menu.open then pcall(function() menu:setInput(false) end) end
  pcall(function() menu:destroy() end)
  pcall(function() render:destroy() end)
  pcall(function() icons:destroy() end)
  pcall(function() hudBars:destroy() end)
  cleanupWidgets('PBZArcs_Root_')
  cleanupWidgets('PBZArcs_Menu')
  cleanupWidgets('PBZArcs_Icons')
  -- 日志句柄常驻复用（Config.log），卸载/热重载时放开，避免句柄泄漏。
  pcall(function() Config.closeLog() end)
end

-- MOD 每次 step 的工作量是固定的（约 0.3ms），而游戏帧率越高，每秒就要跑越多次：
-- 744fps 时一秒跑 744 次，120fps 时只跑 120 次，画面上看不出任何区别 ——
-- 弧线跟的锚点本身已经过 0.10s 的平滑，读数也只在 60Hz 量级变化。
-- 所以把更新频率和帧率解绑：两次真正执行之间至少间隔 6ms（≈165fps），
-- dt 取「距上次真正执行」的累计时间，动画 / 淡出 / 残影的时间轴因此完全不变。
-- 6ms 是刻意选在 165fps 帧时间（6.06ms）之下：120/144/165 这类常见刷新率
-- 一帧都不跳，只有更高帧率才会被压到 120~150Hz 的更新频率。
-- 菜单打开时不节流：拖动读数、拖动滑块要跟手。
local UPDATE_INTERVAL = 0.006

local lastClock = nil
local function safeStep()
  if not RT.alive then return true end
  local now = os.clock()
  RT.lastTick = now
  local dt = lastClock and math.max(0, now - lastClock) or 0.016
  if not menu.open and dt < UPDATE_INTERVAL then return false end
  lastClock = now
  dt = math.min(0.2, dt)
  local ok, err = pcall(step, dt)
  if not ok then alert('step: ' .. tostring(err)) end
  return false
end

local function startFrameLoop()
  if RT.loopOn then return end
  RT.loopOn = true
  if LoopInGameThreadAfterFrames then
    LoopInGameThreadAfterFrames(1, safeStep)
  elseif LoopInGameThreadWithDelay then
    LoopInGameThreadWithDelay(16, safeStep)
  end
end

if LoopAsync then
  LoopAsync(900, function()
    if not RT.alive then return true end
    local stale = (RT.lastTick == nil) or (os.clock() - RT.lastTick > 1.2)
    if stale then
      RT.loopOn = false
      ExecuteInGameThread(startFrameLoop)
    end
    return false
  end)
else
  startFrameLoop()
end

log('v' .. Config.VERSION .. ' loaded; ' .. tostring(S.MenuKey) .. ' menu')
