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
          -- 打分只用一次 Visibility 读取。以前这里对**每个候选**都跑
          -- widgetChainVisible（最多 8 层父链 × 3 次反射 ≈ 24 次 pcall），
          -- 只为了给 score 加 1；真正的可见性判定由 hudVisible() 在选中
          -- 的那个 widget 上做一次完整链检查，结果不受这个排序启发式影响。
          local shown = false
          local okV, vis = pcall(function() return widget.Visibility end)
          if okV then shown = not (vis == VIS.Collapsed or vis == VIS.Hidden) end
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
local hudSeenVisible = false
local hudHiddenSince = nil
local fullSince = { hp = nil, qi = nil }
local FULL_RATIO = 0.995
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
  -- 淡出/淡入过程中逐帧重算；常态才走 0.05s 缓存。
  local base = hudBaseAlpha > HUD_FADE_MIN and hudBaseAlpha or 1
  local fading = hudCacheFactor ~= nil and hudCacheFactor > HUD_FADE_MIN
    and hudCacheFactor < base * HUD_FADE_MAX
  if not fading and now - hudCacheAt < HUD_POLL_INTERVAL then
    return hudCacheVisible, hudCacheFactor, hudCacheHidden
  end
  hudCacheAt = now
  local widget = findHudWidget()
  if not valid(widget) then
    -- HUD 容器不存在（读图、进游戏前）按隐藏处理。
    hudCacheVisible, hudCacheFactor, hudCacheHidden = nil, 1, true
    return nil, 1, true
  end
  local visible, factor, hardHidden = widgetChainVisible(widget, true)
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

  local barsOk, barsErr = pcall(function() hudBars:update(dt, snapshot) end)
  if not barsOk and now - lastBarsError > 5 then
    lastBarsError = now
    alert('hud bars update: ' .. tostring(barsErr))
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
      string.format('%s/%.2f', tostring(hudShown), tonumber(hudOpacity) or -1),
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
