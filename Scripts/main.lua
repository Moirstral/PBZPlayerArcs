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

local function valid(object)
  if object == nil then return false end
  local ok, answer = pcall(function() return object:IsValid() end)
  return ok and answer == true
end

local function prop(object, name)
  local ok, value = pcall(function() return object[name] end)
  if ok then return value end
  return nil
end

local function unwrap(value)
  local ok, inner = pcall(function() return value:get() end)
  if ok and inner ~= nil then return inner end
  return value
end

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
    if not valid(cur) then return false, 0 end
    local okV, visibility = pcall(function() return cur.Visibility end)
    if okV and (visibility == 1 or visibility == 2) then return false, 0 end
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
    if okIn and inViewport ~= true then return false, 0 end
  end
  return factor > 0.01, factor
end

local function findHudWidget()
  local pc = localPC()
  local pcName = nil
  if valid(pc) then
    local ok, name = pcall(function() return pc:GetFullName() end)
    if ok then pcName = name end
  end
  local function pick(list)
    local best, bestScore = nil, -1
    for _, widget in ipairs(list or {}) do
      if valid(widget) then
        local ok, name = pcall(function() return widget:GetFullName() end)
        if ok and type(name) == 'string' and not name:find('Default__', 1, true) then
          local owned = false
          if pcName ~= nil then
            local okO, owner = pcall(function() return widget:GetOwningPlayer() end)
            if okO and valid(owner) then
              local okN, ownerName = pcall(function() return owner:GetFullName() end)
              owned = okN and ownerName == pcName
            end
          end
          local shown = widgetChainVisible(widget, true)
          local score = (owned and 2 or 0) + (shown and 1 or 0)
          if score > bestScore then best, bestScore = widget, score end
        end
      end
    end
    return best
  end
  local widget = pick(FindAllOf('WB_PlayerHPBar_V1_C'))
  if valid(widget) then return widget end
  return pick(FindAllOf('W_FrontEndHUDLayout_C'))
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

---------------------------------------------------------------------------------------------------
-- 运行时状态

if PBZARCS_RUNTIME and PBZARCS_RUNTIME.shutdown then
  pcall(PBZARCS_RUNTIME.shutdown)
end

local RT = { alive = true, lastTick = nil }
PBZARCS_RUNTIME = RT

local master = 0
local lastScale = 1
local nextBuildTry = 0
local heldSnapshot, heldAt = nil, nil
local lastStatsWarn = -100
local lastDebugAt = -100
local lastIconsError = -100
local lastBarsError = -100
local attributesDumped = false
local hudSeenVisible = false
local hudHiddenSince = nil
local fullSince = { hp = nil, qi = nil }
local FULL_RATIO = 0.995
local hudCacheAt = -1
local hudCacheVisible, hudCacheFactor = nil, 1
local traceTicks = 0
local pending = { toggle = false, click = false, rclick = false, mclick = false,
  close = false }

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
  if heldSnapshot then
    if heldAt == nil then heldAt = now end
    if now - heldAt < 1.0 then return heldSnapshot, err end
    heldSnapshot, heldAt = nil, nil
  end
  return nil, err
end

local function hudVisible()
  local now = os.clock()
  if now - hudCacheAt < 0.05 then return hudCacheVisible, hudCacheFactor end
  hudCacheAt = now
  local widget = findHudWidget()
  if not valid(widget) then
    hudCacheVisible, hudCacheFactor = nil, 1
    return nil, 1
  end
  local visible, factor = widgetChainVisible(widget, true)
  hudCacheVisible, hudCacheFactor = visible, factor
  return visible, factor
end

-- 全屏游戏界面（地图、设置、背包、暂停）绘制在 HUD 之上，而 HUD 仍在底下
-- 继续渲染，所以光看 HUD 的可见性区分不开它们。硬件光标标志是第二个、
-- 独立的信号：游戏过程中光标隐藏，这些界面则会显示光标。
local UI_SCREEN_CLASSES = { 'WB_MapNew_C', 'W_PBZSettingPanel_C', 'WB_Inventory_C', 'WB_StartMenu_V2_C' }
local uiProbeAt, uiProbeResult = nil, false
local function gameUIOpen(now)
  if uiProbeAt ~= nil and now - uiProbeAt < 0.25 then return uiProbeResult end
  uiProbeAt = now
  uiProbeResult = false
  for _, name in ipairs(UI_SCREEN_CLASSES) do
    local ok, list = pcall(function() return FindAllOf(name) end)
    if ok and type(list) == 'table' then
      for i = 1, #list do
        if valid(list[i]) and widgetChainVisible(list[i]) then
          uiProbeResult = true
          return true
        end
      end
    end
  end
  local pc = localPC()
  if valid(pc) then
    local ok, shown = pcall(function() return pc.bShowMouseCursor end)
    if ok and shown == true then uiProbeResult = true end
  end
  return uiProbeResult
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

  local snapshot, statsError = readSnapshot(now)
  if S.Debug and snapshot ~= nil and not attributesDumped then
    local lines = stats:describeAttributes()
    if #lines > 0 then
      attributesDumped = true
      log('attr dump start (' .. #lines .. ' lines)')
      for _, line in ipairs(lines) do log('attr ' .. line) end
      log('attr dump end')
    end
  end
  local trace = S.Debug and snapshot ~= nil and traceTicks < 3
  if trace then
    traceTicks = traceTicks + 1
    log('trace ' .. traceTicks .. ': stats ok')
  end

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

  local hudShown, hudOpacity = hudVisible()
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
    hudFactor = hudDimmed and (hudOpacity or 1) or 1
    fullSince.hp, fullSince.qi = nil, nil
  elseif visibility == 'dynamic' then
    -- 动态隐藏：每条弧线单独计时。满值持续时间达到 HideDelay 后只隐藏那一条，
    -- 掉下来立刻恢复；未满时仍跟随游戏 HUD 显隐。
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
    hudFactor = hudDimmed and (hudOpacity or 1) or 1
  else
    hudHiddenSince = nil
    fullSince.hp, fullSince.qi = nil, nil
  end
  local uiOpen = gameUIOpen(now)
  if uiOpen then
    visible = false
    hudFactor = 1
  end
  if menu.open then
    visible = true
    hudFactor = 1
    hpShown, qiShown = true, true
  end
  if trace then log('trace ' .. traceTicks .. ': visible ' .. tostring(visible)) end

  local iconsOk, iconsErr = pcall(function()
    icons:update(dt, {
      menuOpen = menu.open,
      uiOpen = uiOpen,
      -- 图标读数跟随显示设置；dynamic 的「值满隐藏」只作用于弧线。
      hudShown = visibility == 'always' or not hudGone,
      -- HUD 淡出时把它当前的不透明度一起交给图标，让读数跟着 HUD 一起变暗、
      -- 一起消失，而不是等 HUD 完全收起后才一次性隐藏。
      hudFade = (visibility == 'always' or menu.open) and 1
        or math.max(0, math.min(1, tonumber(hudOpacity) or 1)),
      -- 精纯杀气的充能比例（UltimateCharge / Max），图标模块用它画充能条。
      ultRatio = ultRatio,
    })
  end)
  if not iconsOk and now - lastIconsError > 5 then
    lastIconsError = now
    alert('icons update: ' .. tostring(iconsErr))
  end

  local barsOk, barsErr = pcall(function() hudBars:update(dt, snapshot) end)
  if not barsOk and now - lastBarsError > 5 then
    lastBarsError = now
    alert('hud bars update: ' .. tostring(barsErr))
  end

  if renderAlive() then render:setBarShown('hp', hpShown); render:setBarShown('qi', qiShown) end

  local target = (snapshot ~= nil and anchorX ~= nil and onscreen and visible)
    and hudFactor or 0
  master = master + (target - master) * math.min(1, math.max(0, dt) * 12)
  if master < 0.01 and target == 0 then master = 0 end

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
      'hp=%.3f qi=%.3f anchor=%s,%s scale=%.3f master=%.2f onscreen=%s visible=%s vis=%s shown=%s/%s delay=%.1f hud=%s ui=%s proj=%s',
      hpRatio or -1, qiRatio or -1,
      anchorX and string.format('%.0f', anchorX) or '?',
      anchorY and string.format('%.0f', anchorY) or '?',
      lastScale, master, tostring(onscreen), tostring(visible), tostring(visibility),
      tostring(hpShown), tostring(qiShown), tonumber(S.HideDelay) or 3,
      -- HUD 的显隐和它当前的淡出程度分开打，图标跟着 HUD 走时能看出滞后在哪一侧。
      string.format('%s/%.2f', tostring(hudShown), tonumber(hudOpacity) or -1),
      tostring(uiOpen), tostring(follow.methodIndex)))
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
  pcall(function() menu:setInput(false) end)
  pcall(function() menu:destroy() end)
  pcall(function() render:destroy() end)
  pcall(function() icons:destroy() end)
  pcall(function() hudBars:destroy() end)
  cleanupWidgets('PBZArcs_Root_')
  cleanupWidgets('PBZArcs_Menu')
  cleanupWidgets('PBZArcs_Icons')
end

local lastClock = nil
local function safeStep()
  if not RT.alive then return true end
  RT.lastTick = os.clock()
  local now = os.clock()
  local dt = lastClock and math.max(0, math.min(0.2, now - lastClock)) or 0.016
  lastClock = now
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
