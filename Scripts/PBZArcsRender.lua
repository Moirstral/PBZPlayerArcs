-- PBZPlayerArcs: segmented UMG ink arcs for player HP and Sha-Chi.
-- Pure Lua. The game is cooked, so we reuse existing ink textures and tint them.
local Config = require('PBZArcsConfig')

local Render = {}
Render.__index = Render

local CLASS = {
  user = '/Script/UMG.UserWidget',
  tree = '/Script/UMG.WidgetTree',
  canvas = '/Script/UMG.CanvasPanel',
  image = '/Script/UMG.Image',
  border = '/Script/UMG.Border',
}

local seq = 0
local EPS = 0.0015
-- The afterimage trails the fill at GhostOpacity, and the fill's own colour at
-- that alpha is indistinguishable from the fill, so the ghost gets its own,
-- darker colour instead of a lightened copy.
local GHOST_DARKEN = 0.6
local function logSafe(fn, message)
  if fn then pcall(fn, message) end
end

local function valid(object)
  if object == nil then return false end
  local ok, answer = pcall(function() return object:IsValid() end)
  return ok and answer == true
end

local function cls(path) return StaticFindObject(path) end

local function loadAsset(paths)
  for _, path in ipairs(paths or {}) do
    if type(path) == 'string' and path ~= '' then
      local texture = StaticFindObject(path)
      if not valid(texture) then
        pcall(LoadAsset, path)
        texture = StaticFindObject(path)
      end
      if valid(texture) then return texture, path end
    end
  end
  return nil, nil
end

-- UMG Image can draw a UI material instead of a plain texture. The material carries
-- the ink-stroke alpha the game itself uses for its bars.
local function applyBrush(widget, brush)
  if brush == nil then return false end
  if valid(brush.material) then
    local ok = pcall(function() widget:SetBrushFromMaterial(brush.material) end)
    if ok then return true end
  end
  if valid(brush.texture) then
    local ok = pcall(function() widget:SetBrushFromTexture(brush.texture, false) end)
    if ok then return true end
  end
  return false
end

local function pseudo(seed)
  local value = math.sin(seed * 12.9898) * 43758.5453
  return value - math.floor(value)
end

local function colorAlpha(colour, alpha)
  return { R = colour.R or 1, G = colour.G or 1, B = colour.B or 1, A = alpha or 1 }
end

function Render.new(settings, log)
  return setmetatable({
    S = settings,
    log = log or function() end,
    root = nil,
    group = nil,
    bars = {},
    time = 0,
    uiScale = nil,
    anchorX = nil,
    anchorY = nil,
    master = nil,
    barShown = { hp = true, qi = true },
  }, Render)
end

function Render:cleanupOld(keep)
  local ok, list = pcall(function() return FindAllOf('UserWidget') end)
  if not ok or type(list) ~= 'table' then return end
  for i = 1, #list do
    local widget = list[i]
    if valid(widget) and widget ~= keep then
      local okName, name = pcall(function() return widget:GetFName():ToString() end)
      if okName and type(name) == 'string' and name:find('PBZArcs_Root_', 1, true) then
        pcall(function() widget:RemoveFromParent() end)
      end
    end
  end
end

local function addChild(parent, widget, x, y, w, h, z)
  local slot = parent:AddChildToCanvas(widget)
  if not valid(slot) then return nil end
  slot:SetAnchors({ Minimum = { X = 0, Y = 0 }, Maximum = { X = 0, Y = 0 } })
  slot:SetAlignment({ X = 0, Y = 0 })
  slot:SetPosition({ X = x or 0, Y = y or 0 })
  slot:SetAutoSize(false)
  slot:SetSize({ X = w or 0, Y = h or 0 })
  if z then slot:SetZOrder(z) end
  return slot
end

local function centredChild(parent, widget, x, y, w, h, z)
  local slot = parent:AddChildToCanvas(widget)
  if not valid(slot) then return nil end
  slot:SetAnchors({ Minimum = { X = 0, Y = 0 }, Maximum = { X = 0, Y = 0 } })
  slot:SetAlignment({ X = 0.5, Y = 0.5 })
  slot:SetPosition({ X = x or 0, Y = y or 0 })
  slot:SetAutoSize(false)
  slot:SetSize({ X = w or 0, Y = h or 0 })
  if z then slot:SetZOrder(z) end
  return slot
end

local function newCanvas(tree, parent, name)
  local canvas = StaticConstructObject(cls(CLASS.canvas), tree, FName(name))
  return canvas
end

local function setWidgetColor(widget, colour)
  pcall(function() widget:SetColorAndOpacity(colour) end)
  pcall(function() widget:SetBrushColor(colour) end)
end

function Render:createSegment(tree, parent, brush, colour, geom, thickness, z)
  local widget
  if brush ~= nil then
    widget = StaticConstructObject(cls(CLASS.image), tree)
    if not applyBrush(widget, brush) then widget = nil end
  end
  if widget == nil then
    widget = StaticConstructObject(cls(CLASS.border), tree)
    pcall(function() widget:SetPadding({ Left = 0, Top = 0, Right = 0, Bottom = 0 }) end)
  end
  if not valid(widget) then return nil end
  setWidgetColor(widget, colour)
  pcall(function() widget:SetRenderTransformPivot({ X = 0.5, Y = 0.5 }) end)
  pcall(function() widget:SetRenderTransformAngle(geom.rotation) end)
  local slot = centredChild(parent, widget, geom.x, geom.y, geom.length, thickness, z)
  if not valid(slot) then
    pcall(function() widget:RemoveFromParent() end)
    return nil
  end
  return { widget = widget, slot = slot, visible = true, alpha = 1, color = colour }
end

function Render:setVisible(segment, visible)
  if segment.visible == visible then return end
  segment.visible = visible
  pcall(function() segment.widget:SetVisibility(visible and 3 or 1) end)
end

function Render:setAlpha(segment, alpha)
  if math.abs((segment.alpha or 1) - alpha) < 0.01 then return end
  segment.alpha = alpha
  pcall(function() segment.widget:SetRenderOpacity(alpha) end)
end

function Render:setSegmentColor(segment, colour)
  segment.color = colour
  setWidgetColor(segment.widget, colour)
end

function Render:createBar(tree, group, name, side, colour, ghostColour, warnColour)
  local S = self.S
  local N = math.max(8, math.floor(tonumber(S.Segments) or 44))
  local radius = math.max(60, tonumber(S.Radius) or 150)
  local span = math.max(30, math.min(180, tonumber(S.ArcSpan) or 110))
  local thickness = math.max(2, tonumber(S.Thickness) or 7)
  -- The ink brush alpha covers only part of its box; scale the box so the visible
  -- stroke matches Thickness.
  local brushScale = valid(self.material) and 2.4 or 1.0
  local arcLength = math.rad(span) * radius
  -- Each segment repeats the whole brush, whose ink tapers to points at both ends.
  -- Overlapping many copies hides those points and keeps the outline continuous.
  local overlap = math.max(1, math.min(24, tonumber(S.StrokeOverlap) or 10))
  local segmentLength = math.max(6, (arcLength / math.max(1, N - 1)) * overlap)
  local left = (side == 'left')
  -- Both bars fill from the bottom of their arc towards the top.
  local startAngle = left and (math.rad(180) - math.rad(span) / 2) or (math.rad(span) / 2)
  local endAngle = left and (math.rad(180) + math.rad(span) / 2) or (-math.rad(span) / 2)

  local track = newCanvas(tree, group, name .. '_track')
  local ghost = newCanvas(tree, group, name .. '_ghost')
  local fill = newCanvas(tree, group, name .. '_fill')
  local trackSlot = addChild(group, track, 0, 0, radius * 2, radius * 2, 0)
  local ghostSlot = addChild(group, ghost, 0, 0, radius * 2, radius * 2, 1)
  local fillSlot = addChild(group, fill, 0, 0, radius * 2, radius * 2, 2)
  if not (valid(trackSlot) and valid(ghostSlot) and valid(fillSlot)) then
    return nil
  end
  track:SetVisibility(3)
  ghost:SetVisibility(3)
  fill:SetVisibility(3)

  local bar = {
    name = name,
    side = side,
    track = track,
    ghost = ghost,
    fill = fill,
    trackSlot = trackSlot,
    ghostSlot = ghostSlot,
    fillSlot = fillSlot,
    segments = {},
    trackSegments = {},
    ghostSegments = {},
    tip = nil,
    tipVisible = false,
    ratio = nil,
    ghostRatio = nil,
    warn = false,
    fillAlpha = {},
    ghostAlpha = {},
    lastFillOpacity = nil,
    lastGhostOpacity = nil,
    lastTrackOpacity = nil,
    fade = 1,
  }

  for i = 1, N do
    local t = (N == 1) and 0.5 or ((i - 1) / (N - 1))
    local angle = startAngle + (endAngle - startAngle) * t
    local jd = (pseudo(i * 7.13 + radius) - 0.5) * 2 * math.max(0, math.min(1, tonumber(S.BrushJitter) or 0))
    local jt = (pseudo(i * 3.71 + span) - 0.5) * 2 * math.max(0, math.min(1, tonumber(S.BrushJitter) or 0))
    local r = radius + jd * 0.9
    -- Brush strokes thin out towards both ends of the arc.
    local taper = 0.55 + 0.45 * math.sin(math.pi * t) ^ 0.5
    local geom = {
      x = radius + math.cos(angle) * r,
      y = radius + math.sin(angle) * r,
      length = segmentLength * (1 + jd * 0.10),
      rotation = math.deg(angle) + 90 + jt * 0.9,
      angle = angle,
    }
    local brush = self.brush
    local trackSeg = self:createSegment(tree, track, brush, self.trackColour, geom, math.max(2, thickness * taper * brushScale * 1.35), 0)
    local ghostSeg = self:createSegment(tree, ghost, brush, ghostColour, geom, math.max(2, thickness * taper * brushScale), 1)
    local fillSeg = self:createSegment(tree, fill, brush, colour, geom, math.max(2, thickness * taper * brushScale), 2)
    if not (trackSeg and ghostSeg and fillSeg) then return nil end
    bar.segments[i] = { geom = geom, track = trackSeg, ghost = ghostSeg, fill = fillSeg }
    bar.trackSegments[i] = trackSeg
    bar.ghostSegments[i] = ghostSeg
    self:setVisible(ghostSeg, false)
    self:setVisible(fillSeg, false)  end

  if S.ShowTip and valid(self.tipTexture) then
    local tipSize = thickness * 2.1
    local tip = StaticConstructObject(cls(CLASS.image), tree)
    if valid(tip) then
      local ok = pcall(function() tip:SetBrushFromTexture(self.tipTexture, false) end)
      if ok then
        pcall(function() tip:SetRenderTransformPivot({ X = 0.5, Y = 0.5 }) end)
        setWidgetColor(tip, self.tipColour)
        local slot = centredChild(fill, tip, 0, 0, tipSize, tipSize * 0.75, 10)
        if valid(slot) then
          bar.tip = { widget = tip, slot = slot, size = tipSize, colour = self.tipColour }
          pcall(function() tip:SetVisibility(1) end)
        end
      end
    end
  end

  bar.baseColour = colour
  bar.ghostColour = ghostColour
  bar.warnColour = warnColour
  self.bars[#self.bars + 1] = bar
  return bar
end

function Render:build()
  self:destroy()
  self:cleanupOld(nil)

  local engine = FindFirstOf('GameEngine') or FindFirstOf('Engine')
  if not valid(engine) then return false, 'GameEngine is not ready' end
  local gi = engine.GameInstance
  if not valid(gi) then return false, 'GameInstance is not ready' end

  seq = seq + 1
  local suffix = tostring(os.time()) .. '_' .. tostring(seq)
  local root = StaticConstructObject(cls(CLASS.user), gi, FName('PBZArcs_Root_' .. suffix))
  local tree = StaticConstructObject(cls(CLASS.tree), root, FName('PBZArcs_Tree_' .. suffix))
  if not (valid(root) and valid(tree)) then return false, 'cannot create the HUD root' end
  root.WidgetTree = tree
  local canvas = newCanvas(tree, nil, 'PBZArcs_Canvas_' .. suffix)
  tree.RootWidget = canvas
  root:SetVisibility(3)
  root:SetRenderOpacity(0)

  local radius = math.max(60, tonumber(self.S.Radius) or 150)
  local group = newCanvas(tree, nil, 'PBZArcs_Group_' .. suffix)
  local groupSlot = addChild(canvas, group, 0, 0, radius * 2, radius * 2, 0)
  if not valid(groupSlot) then return false, 'cannot create the arc group' end
  group:SetRenderTransformPivot({ X = 0.5, Y = 0.5 })

  self.material, self.materialPath = loadAsset({
    self.S.InkMaterial,
    '/Game/PBZContent/VFX/SceneFX/UI/Common/M_UI_InkBar_A_002_Inst2.M_UI_InkBar_A_002_Inst2',
  })
  self.texture, self.texturePath = loadAsset({
    self.S.Texture,
    '/Game/PBZContent/VFX/SceneFX/UI/Common/Assets/T_UI_Common_InkBar_003.T_UI_Common_InkBar_003',
    '/Game/PBZContent/VFX/SceneFX/UI/Common/Assets/T_UI_Common_InkBar_001.T_UI_Common_InkBar_001',
  })
  self.tipTexture, self.tipTexturePath = loadAsset({
    self.S.TipTexture,
    '/Game/PBZContent/UI/Hud/Art/Hud_Blood_End.Hud_Blood_End',
    '/Game/PBZContent/UI/Hud/Art/Hud_Blood_End_2.Hud_Blood_End_2',
  })
  self.brush = { material = self.material, texture = self.texture }
  if valid(self.material) then
    self.log('ink material: ' .. tostring(self.materialPath))
  elseif valid(self.texture) then
    self.log('ink texture: ' .. tostring(self.texturePath))
  else
    self.log('no ink brush; arcs use solid colour')
  end

  self.world = nil
  self.sliceOK = false

  self.baseHpColour = Config.hexToLinear(self.S.HpColor)
  self.baseQiColour = Config.hexToLinear(self.S.QiColor)
  self.trackColour = Config.hexToLinear(self.S.TrackColor)
  self.warnColour = Config.hexToLinear(self.S.WarnColor)
  self.hpGhostColour = Config.lighten(self.baseHpColour, GHOST_DARKEN)
  self.qiGhostColour = Config.lighten(self.baseQiColour, GHOST_DARKEN)
  self.tipColour = Config.lighten(self.baseHpColour, 1.65)

  local hpSide = self.S.HpOnLeft and 'left' or 'right'
  local qiSide = self.S.HpOnLeft and 'right' or 'left'
  local hp = self:createBar(tree, group, 'HP', hpSide, self.baseHpColour, self.hpGhostColour, self.warnColour)
  if not hp then return false, 'cannot create the health arc' end
  self.hpBar = hp
  local qi = self:createBar(tree, group, 'QI', qiSide, self.baseQiColour, self.qiGhostColour, self.warnColour)
  if not qi then return false, 'cannot create the Sha-Chi arc' end
  self.qiBar = qi

  root:AddToViewport(50)
  self.root, self.tree, self.canvas, self.group, self.groupSlot = root, tree, canvas, group, groupSlot
  self.uiScale = nil
  self.anchorX, self.anchorY = nil, nil
  self.master = nil
  self.log('HUD built: radius=' .. tostring(radius) .. ' segments=' .. tostring(self.S.Segments))
  self:applyColours()
  return true
end

function Render:destroy()
  if self.root ~= nil and valid(self.root) then
    pcall(function() self.root:RemoveFromParent() end)
  end
  self.root, self.tree, self.canvas, self.group, self.groupSlot = nil, nil, nil, nil, nil
  self.hpBar, self.qiBar = nil, nil
  self.bars = {}
  self.anchorX, self.anchorY = nil, nil
  self.master = nil
  self.barShown = { hp = true, qi = true }
end

function Render:applyColours()
  self.baseHpColour = Config.hexToLinear(self.S.HpColor)
  self.baseQiColour = Config.hexToLinear(self.S.QiColor)
  self.trackColour = Config.hexToLinear(self.S.TrackColor)
  self.warnColour = Config.hexToLinear(self.S.WarnColor)
  self.hpGhostColour = Config.lighten(self.baseHpColour, GHOST_DARKEN)
  self.qiGhostColour = Config.lighten(self.baseQiColour, GHOST_DARKEN)
  if not valid(self.root) then return end
  if self.hpBar then
    self.hpBar.baseColour = self.baseHpColour
    self.hpBar.ghostColour = self.hpGhostColour
    self.hpBar.warnColour = self.warnColour
    self:applyBarColours(self.hpBar)
  end
  if self.qiBar then
    self.qiBar.baseColour = self.baseQiColour
    self.qiBar.ghostColour = self.qiGhostColour
    self.qiBar.warnColour = self.warnColour
    self:applyBarColours(self.qiBar)
  end
end

function Render:applyBarColours(bar)
  local fillColour = bar.warn and bar.warnColour or bar.baseColour
  local ghostColour = bar.ghostColour
  for i = 1, #bar.segments do
    local seg = bar.segments[i]
    self:setSegmentColor(seg.track, self.trackColour)
    self:setSegmentColor(seg.ghost, ghostColour)
    self:setSegmentColor(seg.fill, fillColour)
  end
  if bar.tip then
    setWidgetColor(bar.tip.widget, Config.lighten(fillColour, 1.55))
    bar.tip.colour = fillColour
  end
  bar.lastFillOpacity = nil
  bar.lastGhostOpacity = nil
  bar.lastTrackOpacity = nil
end

function Render:setMaster(alpha)
  if not valid(self.root) then return end
  alpha = math.max(0, math.min(1, alpha or 0))
  if self.master ~= nil and math.abs(self.master - alpha) < 0.01 then return end
  self.master = alpha
  pcall(function() self.root:SetRenderOpacity(alpha) end)
end

-- Per-arc visibility, so dynamic hiding can drop HP and Qi independently.
function Render:setBarShown(key, shown)
  if self.barShown == nil then self.barShown = { hp = true, qi = true } end
  self.barShown[key] = shown and true or false
end

-- Scale and position both live in the render transform: unlike a canvas slot
-- SetPosition this does not run the layout pass, which matters at 60 fps.
function Render:applyTransform()
  if not valid(self.group) then return end
  local scale = self.uiScale or 1
  local radius = math.max(60, tonumber(self.S.Radius) or 150)
  local x = self.anchorX or radius
  local y = self.anchorY or radius
  pcall(function()
    self.group:SetRenderTransform({
      Translation = { X = x - radius, Y = y - radius },
      Scale = { X = scale, Y = scale },
      Shear = { X = 0, Y = 0 },
      Angle = 0,
    })
  end)
end

function Render:setUiScale(scale)
  if not valid(self.group) then return end
  scale = math.max(0.2, math.min(4, scale or 1))
  if self.uiScale ~= nil and math.abs(self.uiScale - scale) < 0.002 then return end
  self.uiScale = scale
  self:applyTransform()
end

function Render:setAnchor(x, y)
  if not valid(self.groupSlot) then return end
  if x == nil or y == nil then return end
  if self.anchorX ~= nil and math.abs(self.anchorX - x) < 0.05 and math.abs(self.anchorY - y) < 0.05 then return end
  self.anchorX, self.anchorY = x, y
  self:applyTransform()
end

function Render:updateTip(bar, ratio)
  if not bar.tip then return end
  -- The tip also stays at an empty bar's start point, so a zeroed bar still
  -- flashes its warning colour instead of disappearing completely.
  local visible = self.S.ShowTip and ratio < 0.995
  if not visible then
    if bar.tipVisible then
      bar.tipVisible = false
      pcall(function() bar.tip.widget:SetVisibility(1) end)
    end
    return
  end
  local N = #bar.segments
  local left = (bar.side == 'left')
  local span = math.rad(math.max(30, math.min(180, tonumber(self.S.ArcSpan) or 110)))
  local startAngle = left and (math.rad(180) - span / 2) or (span / 2)
  local endAngle = left and (math.rad(180) + span / 2) or (-span / 2)
  local angle = startAngle + (endAngle - startAngle) * ratio
  local radius = math.max(60, tonumber(self.S.Radius) or 150)
  local x = radius + math.cos(angle) * radius
  local y = radius + math.sin(angle) * radius
  local size = math.max(2, tonumber(self.S.Thickness) or 7) * 2.1 * math.max(0.3, math.min(3, tonumber(self.S.TipScale) or 1))
  local tipAngle = math.deg(angle) + 90 + (tonumber(self.S.TipAngle) or -15)
  -- The tip only moves when the ratio moves; skip the layout call when idle.
  if not bar.tipVisible or math.abs((bar.tipX or -9999) - x) > 0.05
    or math.abs((bar.tipY or -9999) - y) > 0.05 then
    bar.tipX, bar.tipY = x, y
    pcall(function() bar.tip.slot:SetPosition({ X = x, Y = y }) end)
  end
  if bar.tipSize ~= size then
    bar.tipSize = size
    pcall(function() bar.tip.slot:SetSize({ X = size, Y = size * 0.75 }) end)
  end
  if bar.tipAngle == nil or math.abs(bar.tipAngle - tipAngle) > 0.05 then
    bar.tipAngle = tipAngle
    pcall(function() bar.tip.widget:SetRenderTransformAngle(tipAngle) end)
  end
  if not bar.tipVisible then
    pcall(function()
      bar.tip.widget:SetRenderOpacity(1)
      bar.tip.widget:SetVisibility(3)
    end)
    bar.tipVisible = true
  end
end

function Render:updateBar(bar, ratio, ghost, dt)
  local N = #bar.segments
  if not ratio or N == 0 then
    self:setBarEnabled(bar, false)
    return
  end
  self:setBarEnabled(bar, true)
  ratio = math.max(0, math.min(1, ratio))
  ghost = math.max(ratio, math.min(1, ghost or ratio))

  local key = (bar == self.hpBar) and 'hp' or 'qi'
  local target = (self.barShown[key] ~= false) and 1 or 0
  bar.fade = bar.fade + (target - bar.fade) * math.min(1, dt * 12)
  if math.abs(bar.fade - target) < 0.005 then bar.fade = target end

  local threshold = (bar == self.hpBar) and (tonumber(self.S.WarnThresholdHp) or 0)
    or (tonumber(self.S.WarnThresholdQi) or 0)
  local warn = threshold > 0 and ratio <= threshold
  if warn ~= bar.warn then
    bar.warn = warn
    self:applyBarColours(bar)
  end

  local filled = ratio * N
  local fillCount = math.floor(filled)
  local fillFrac = filled - fillCount
  if fillCount >= N then fillCount, fillFrac = N, 0 end
  local ghostFilled = ghost * N
  local ghostCount = math.floor(ghostFilled)
  local ghostFrac = ghostFilled - ghostCount
  if ghostCount >= N then ghostCount, ghostFrac = N, 0 end

  for i = 1, N do
    local visible = i <= fillCount or (i == fillCount + 1 and fillFrac > 0.002)
    self:setVisible(bar.segments[i].fill, visible)
    local alpha = (i == fillCount + 1) and fillFrac or 1
    self:setAlpha(bar.segments[i].fill, visible and alpha or 0)
  end
  if self.S.ShowGhost then
    for i = 1, N do
      local visible = i <= ghostCount or (i == ghostCount + 1 and ghostFrac > 0.002)
      self:setVisible(bar.segments[i].ghost, visible)
      local alpha = (i == ghostCount + 1) and ghostFrac or 1
      self:setAlpha(bar.segments[i].ghost, visible and alpha or 0)
    end
  else
    for i = 1, N do self:setVisible(bar.segments[i].ghost, false) end
  end

  local flash = 1
  if warn then
    local amount = math.max(0, math.min(1, tonumber(self.S.WarnFlashAmount) or 0))
    local speed = math.max(0.2, tonumber(self.S.WarnFlashSpeed) or 1.8)
    local phase = self.time * speed * math.pi * 2
    flash = 1 - amount * (0.5 + 0.5 * math.sin(phase))
  end
  local barOpacity = math.max(0.05, math.min(1, tonumber(self.S.BarOpacity) or 1)) * bar.fade
  local fillOpacity = barOpacity * flash
  local ghostOpacity = math.max(0, math.min(1, tonumber(self.S.GhostOpacity) or 0)) * barOpacity
  local trackOpacity = math.max(0, math.min(1, tonumber(self.S.TrackOpacity) or 0)) * barOpacity
  if bar.lastFillOpacity == nil or math.abs(bar.lastFillOpacity - fillOpacity) > 0.005 then
    bar.lastFillOpacity = fillOpacity
    pcall(function() bar.fill:SetRenderOpacity(fillOpacity) end)
  end
  if bar.lastGhostOpacity == nil or math.abs(bar.lastGhostOpacity - ghostOpacity) > 0.005 then
    bar.lastGhostOpacity = ghostOpacity
    pcall(function() bar.ghost:SetRenderOpacity(ghostOpacity) end)
  end
  if bar.lastTrackOpacity == nil or math.abs(bar.lastTrackOpacity - trackOpacity) > 0.005 then
    bar.lastTrackOpacity = trackOpacity
    pcall(function() bar.track:SetRenderOpacity(trackOpacity) end)
  end

  bar.ratio = ratio
  bar.ghostRatio = ghost
  self:updateTip(bar, ratio)
end

function Render:setBarEnabled(bar, enabled)
  if bar.enabled == enabled then return end
  bar.enabled = enabled
  pcall(function()
    bar.track:SetVisibility(enabled and 3 or 1)
    bar.ghost:SetVisibility(enabled and 3 or 1)
    bar.fill:SetVisibility(enabled and 3 or 1)
  end)
  if not enabled and bar.tip then
    bar.tipVisible = false
    pcall(function() bar.tip.widget:SetVisibility(1) end)
  end
end

function Render:update(snapshot, dt)
  if not valid(self.root) then return false end
  dt = math.max(0, math.min(0.2, dt or 0.016))
  self.time = self.time + dt
  local mode = tostring(self.S.DisplayMode or 'both'):lower()
  local showHp = mode ~= 'qi'
  local showQi = mode ~= 'hp'
  if showHp and snapshot.hp and snapshot.hpMax and snapshot.hpMax > 0 then
    local ratio = snapshot.hp / snapshot.hpMax
    if self.hpBar.ghostRatio == nil then self.hpBar.ghostRatio = ratio end
    local ghost = self.hpBar.ghostRatio
    if ratio >= ghost then ghost = ratio
    else ghost = ratio + (ghost - ratio) * math.exp(-dt / math.max(0.01, tonumber(self.S.GhostSpeed) or 0.1)) end
    if ghost - ratio < 0.002 then ghost = ratio end
    self.hpBar.ghostRatio = ghost
    self:updateBar(self.hpBar, ratio, ghost, dt)
  else
    self:setBarEnabled(self.hpBar, false)
  end
  if showQi and snapshot.qi and snapshot.qiMax and snapshot.qiMax > 0 then
    local ratio = snapshot.qi / snapshot.qiMax
    if self.qiBar.ghostRatio == nil then self.qiBar.ghostRatio = ratio end
    local ghost = self.qiBar.ghostRatio
    if ratio >= ghost then ghost = ratio
    else ghost = ratio + (ghost - ratio) * math.exp(-dt / math.max(0.01, tonumber(self.S.GhostSpeed) or 0.1)) end
    if ghost - ratio < 0.002 then ghost = ratio end
    self.qiBar.ghostRatio = ghost
    self:updateBar(self.qiBar, ratio, ghost, dt)
  else
    self:setBarEnabled(self.qiBar, false)
  end
  return true
end

return Render
