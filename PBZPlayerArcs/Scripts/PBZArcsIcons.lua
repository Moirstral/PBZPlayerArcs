-- PBZPlayerArcs: flat medicine / ultimate readouts mirrored from the live HUD.
-- The game keeps these counts in HUD widgets, not in the attribute set, so the
-- medicine icons come from WB_quickslot_C and the numbers from W_WeaponUI_C.
local Config = require('PBZArcsConfig')

local Icons = {}
Icons.__index = Icons

local CLASS = {
  user = '/Script/UMG.UserWidget',
  tree = '/Script/UMG.WidgetTree',
  canvas = '/Script/UMG.CanvasPanel',
  image = '/Script/UMG.Image',
  text = '/Script/UMG.TextBlock',
}

-- These are the pixels IconScale = 1 renders at; the slider grows them together.
local ICON_H = 42
local NUM_GAP = 8
local ENTRY_GAP = 25
local GROUP_GAP = 56
local BOTTOM_MARGIN = 152
local NUM_FONT = 18
local NUM_LINE = 1.2
-- What the digits are assumed to be built at when Font.Size cannot be read back.
-- 27 is the size the theme uses, so the 18/27 render scale is two thirds of it.
local NUM_ASSUMED_PX = 27
local NUM_CHAR_W = 13
local NUM_MIN_W = 20
local STILL_TIME = 0.12
local READ_INTERVAL = 0.10
local SCAN_INTERVAL = 0.50

-- IconScale multiplies these base pixels, so the icons, their numbers and the gaps
-- between them all grow together. NUM_FONT is the height the digits end up drawing
-- at; the text widget itself is resized through its render scale, because that is
-- the only text property UMG repaints on.
local function px(base, scale) return math.floor(base * scale + 0.5) end

local NUM_COLOUR = { R = 0.93, G = 0.90, B = 0.84, A = 1 }
local ICON_GREY = { R = 0.42, G = 0.42, B = 0.42, A = 0.85 }
local ICON_WHITE = { R = 1, G = 1, B = 1, A = 1 }
local ULT_TINT = { R = 0.62, G = 0.30, B = 1, A = 1 }
local ULT_DIM = 0.34

-- The 精纯杀气 charge is drawn into the icon itself: the icon keeps its original
-- single tint, and a copy of it at full brightness is clipped to the charged
-- fraction of its own height, so the icon fills from the bottom up.
-- CLIP is FWidgetClipping::ClipToBounds.
local CLIP_TO_BOUNDS = 1

-- The game draws the ultimate as a Niagara flame and the ammo as a swirl whose
-- fill is a material, so those brushes are not usable. These two textures are
-- the static stand-ins: a flame silhouette tinted purple, and the swirl art.
local ULT_ART = {
  ultimate = '/Game/PBZContent/UI/Hud/Art/Icon_Hud_JingChun_Fire.Icon_Hud_JingChun_Fire',
  bullet = '/Game/PBZContent/VFX/SceneFX/UI/BattleSystem/Assets/T_UI_ShaChiBullet_001_FG.T_UI_ShaChiBullet_001_FG',
}

local function valid(object)
  if object == nil then return false end
  local ok, answer = pcall(function() return object:IsValid() end)
  return ok and answer == true
end

local function cls(path) return StaticFindObject(path) end

local function prop(object, name)
  local ok, value = pcall(function() return object[name] end)
  if ok then return value end
  return nil
end

local function unwrap(value)
  if value == nil then return nil end
  local ok, inner = pcall(function() return value:get() end)
  if ok and inner ~= nil then return inner end
  return value
end

local function fullName(object)
  if not valid(object) then return '?' end
  local ok, name = pcall(function() return object:GetFullName() end)
  if ok and type(name) == 'string' then return name end
  return '?'
end

local function className(object)
  if not valid(object) then return '?' end
  local ok, name = pcall(function() return object:GetClass():GetFName():ToString() end)
  if ok and type(name) == 'string' then return name end
  return '?'
end

local function textValue(value)
  if value == nil then return nil end
  if type(value) == 'string' then return value end
  local ok, answer = pcall(function() return value:ToString() end)
  if ok and type(answer) == 'string' then return answer end
  return nil
end

-- The count a readout's text carries, or nil when the text holds no digits.
local function digitsOf(text)
  if type(text) ~= 'string' then return nil end
  return tonumber(text:match('%d+'))
end

local function ownVisible(widget)
  if not valid(widget) then return false end
  local ok, value = pcall(function() return widget.Visibility end)
  if not ok then return true end
  return value ~= 1 and value ~= 2
end

-- A slot can be hidden by its own flag or by one of the overlays the game
-- collapses for an unequipped slot, so the whole short chain has to agree.
local function chainVisible(widget)
  local cur = widget
  for _ = 1, 6 do
    if not valid(cur) then return false end
    local okV, visibility = pcall(function() return cur.Visibility end)
    if okV and (visibility == 1 or visibility == 2) then return false end
    local okO, opacity = pcall(function() return cur.RenderOpacity end)
    if okO and type(opacity) == 'number' and opacity <= 0.01 then return false end
    local okP, parent = pcall(function() return cur:GetParent() end)
    if not okP or not valid(parent) then break end
    cur = parent
  end
  return true
end

-- Whether the game still draws the icon a readout belongs to: its own image widget
-- when the HUD has one, otherwise the row that holds the digits. Either being up is
-- enough; the digits collapsed with the icon still drawn is how a zero looks.
local function iconPresent(num, icon)
  if valid(icon) and chainVisible(icon) then return true end
  if not valid(num) then return false end
  local ok, parent = pcall(function() return num:GetParent() end)
  return ok and valid(parent) and chainVisible(parent)
end

local function inViewport(widget)
  if not valid(widget) then return false end
  local ok, answer = pcall(function() return widget:IsInViewport() end)
  return ok and answer == true
end

local function brushInfoFromStruct(brush)
  if brush == nil then return nil end
  local resource = nil
  local okR, raw = pcall(function() return brush.ResourceObject end)
  if okR then resource = unwrap(raw) end
  if not valid(resource) then resource = nil end
  local name = nil
  local okN, rawName = pcall(function() return brush.ResourceName end)
  if okN and rawName ~= nil then
    if type(rawName) == 'string' then
      name = rawName
    else
      local okS, text = pcall(function() return rawName:ToString() end)
      if okS and type(text) == 'string' then name = text end
    end
  end
  if resource == nil and (name == nil or name == '' or name == 'None') then return nil end
  local sizeX, sizeY = 0, 0
  local okX, x = pcall(function() return brush.ImageSize.X end)
  local okY, y = pcall(function() return brush.ImageSize.Y end)
  if okX and type(x) == 'number' then sizeX = x end
  if okY and type(y) == 'number' then sizeY = y end
  local key = name or ''
  if valid(resource) then key = fullName(resource) end
  return {
    resource = resource,
    name = name,
    class = className(resource),
    key = key,
    w = sizeX,
    h = sizeY,
  }
end

local function brushInfo(image)
  if not valid(image) then return nil end
  local ok, brush = pcall(function() return image.Brush end)
  if not ok then return nil end
  return brushInfoFromStruct(brush)
end

local function applyBrush(image, info)
  if not (valid(image) and info and valid(info.resource)) then return false end
  if pcall(function() image:SetBrushResourceObject(info.resource) end) then return true end
  local class = info.class or ''
  if class:find('Material', 1, true) then
    if pcall(function() image:SetBrushFromMaterial(info.resource) end) then return true end
  end
  return pcall(function() image:SetBrushFromTexture(info.resource, false) end)
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

local cachedPC = nil
local function playerController()
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

local function mousePosition()
  local pc = playerController()
  if not valid(pc) then return nil end
  local okWorld, world = pcall(function() return pc:GetWorld() end)
  if not okWorld then world = nil end
  local lib = StaticFindObject('/Script/UMG.Default__WidgetLayoutLibrary')
  if valid(lib) and valid(world) then
    local ok, pos = pcall(function() return lib:GetMousePositionOnViewport(world) end)
    if ok and pos then
      local x, y = pos.X or pos.x, pos.Y or pos.y
      if type(x) == 'number' and type(y) == 'number' then return x, y end
    end
  end
  local ok, x, y = pcall(function() return pc:GetMousePosition() end)
  if ok and type(x) == 'number' and type(y) == 'number' then return x, y end
  return nil
end

local function hasAnyChild(widget, names)
  if not valid(widget) then return false end
  for _, name in ipairs(names) do
    if valid(unwrap(prop(widget, name))) then return true end
  end
  return false
end

-- Several instances share the class name: the CDO, a child of the front-end
-- layout that never gets its graphs bound, and the real in-game HUD. Only the
-- last one owns the Icon/Num children, so pick by children first.
local function findLive(shortName, names)
  local ok, list = pcall(function() return FindAllOf(shortName) end)
  if not ok or type(list) ~= 'table' then return nil end
  local best, bestScore = nil, nil
  for i = 1, #list do
    local widget = list[i]
    if valid(widget) then
      local name = fullName(widget)
      if not name:find('Default__', 1, true) then
        local score = 0
        if names ~= nil and hasAnyChild(widget, names) then score = score + 100 end
        if inViewport(widget) then score = score + 10 end
        if name:find('W_FrontEndHUDLayout', 1, true) then score = score - 20 end
        if bestScore == nil or score > bestScore then
          best, bestScore = widget, score
        end
      end
    end
  end
  return best
end

local QUICK_CHILDREN = {
  'Icon', 'Icon_next', 'BottomMedicineNum', 'TopMedicineNum',
}
local WEAPON_CHILDREN = { 'PureShachiImage', 'PureShachiNum' }

function Icons.new(settings, log)
  return setmetatable({
    S = settings,
    log = log or function() end,
    root = nil,
    tree = nil,
    canvas = nil,
    medEntries = {},
    ultEntries = {},
    quickslot = nil,
    weapon = nil,
    bulletNum = nil,
    buildAt = 0,
    scanAt = -1,
    readAt = -1,
    viewportAt = -1,
    viewportCache = nil,
    medVisible = false,
    ultVisible = false,
    medW = 0,
    ultW = 0,
    medX = 0,
    medY = 0,
    ultX = 0,
    ultY = 0,
    shownValue = nil,
    shownOpacity = nil,
    ultRatio = nil,
    dragging = nil,
    still = 0,
    lastX = nil,
    lastY = nil,
    moved = false,
    lastSignature = nil,
  }, Icons)
end

function Icons:viewport()
  local now = os.clock()
  if self.viewportCache and now - self.viewportAt < 0.5 then
    return self.viewportCache.w, self.viewportCache.h
  end
  self.viewportAt = now
  local w, h = 1920, 1080
  local pc = playerController()
  if valid(pc) then
    local okWorld, world = pcall(function() return pc:GetWorld() end)
    local lib = StaticFindObject('/Script/UMG.Default__WidgetLayoutLibrary')
    if valid(lib) and okWorld and valid(world) then
      local ok, size = pcall(function() return lib:GetViewportSize(world) end)
      local okS, scale = pcall(function() return lib:GetViewportScale(world) end)
      if ok and size then
        local sw, sh = size.X or size.x, size.Y or size.y
        local dpi = (okS and type(scale) == 'number' and scale > 0.1) and scale or 1
        if type(sw) == 'number' and type(sh) == 'number' and sw > 0 and sh > 0 then
          w, h = sw / dpi, sh / dpi
        end
      end
    end
  end
  self.viewportCache = { w = w, h = h }
  return w, h
end

function Icons:scale()
  return tonumber(self.S.IconScale) or 1
end

-- UTextBlock reads Font once when its Slate widget is built, and SetRenderScale is
-- the property that repaints, so IconScale grows the numbers through the transform.
-- The scale is measured against the size the widget really built with, so the
-- digits land on NUM_FONT even when the theme's own font is a different size.
function Icons:applyTextScale(scale)
  if self.textScale == scale then return end
  self.textScale = scale
  for _, list in ipairs({ self.medEntries, self.ultEntries }) do
    for _, entry in ipairs(list) do
      local base = entry.fontPx or NUM_ASSUMED_PX
      local k = (NUM_FONT * scale) / base
      pcall(function() entry.text:SetRenderScale({ X = k, Y = k }) end)
      -- The pivot is the slot's mid-height, so the slot has to be exactly as tall as
      -- the unscaled glyphs. A taller slot drags them above the icon's mid-line as
      -- soon as the scale is above 1, which is what made the numbers sit too high.
      entry.numH = math.floor(base * NUM_LINE + 0.5)
    end
  end
end

function Icons:createEntry(name, z, canGrey)
  local tree = self.tree
  local image = StaticConstructObject(cls(CLASS.image), tree, FName('PBZArcs_Icons_' .. name .. '_icon'))
  local text = StaticConstructObject(cls(CLASS.text), tree, FName('PBZArcs_Icons_' .. name .. '_num'))
  if not (valid(image) and valid(text)) then return nil end
  pcall(function() text.Font.Size = NUM_FONT end)
  -- Reading the size back tells us what the widget really built with. If the read
  -- fails we assume the theme's own size, which makes the scale below two thirds.
  local okFont, fontPx = pcall(function() return tonumber(text.Font.Size) end)
  if not (okFont and fontPx and fontPx > 0) then fontPx = NUM_ASSUMED_PX end
  pcall(function() text.Justification = 0 end)
  -- IconScale is applied as a render scale, so the digits have to grow around the
  -- row's mid-line: the slot is centred on it and the pivot is its own mid-height.
  pcall(function() text:SetRenderTransformOrigin({ X = 0, Y = 0.5 }) end)
  pcall(function() text:SetShadowOffset({ X = 1, Y = 1 }) end)
  pcall(function() text:SetShadowColorAndOpacity({ R = 0, G = 0, B = 0, A = 0.85 }) end)
  pcall(function() text:SetColorAndOpacity({ SpecifiedColor = NUM_COLOUR, ColorUseRule = 0 }) end)
  pcall(function() image:SetColorAndOpacity(ICON_WHITE) end)
  local imageSlot = addChild(self.canvas, image, 0, 0, ICON_H, ICON_H, z)
  local textSlot = addChild(self.canvas, text, 0, 0, NUM_MIN_W, ICON_H, z)
  if not (valid(imageSlot) and valid(textSlot)) then
    pcall(function() image:RemoveFromParent() end)
    pcall(function() text:RemoveFromParent() end)
    return nil
  end
  pcall(function() image:SetVisibility(1) end)
  pcall(function() text:SetVisibility(1) end)
  return {
    image = image,
    imageSlot = imageSlot,
    text = text,
    textSlot = textSlot,
    canGrey = canGrey == true,
    offId = name,
    staticPath = nil,
    tint = ICON_WHITE,
    dimAtZero = false,
    iconAlpha = nil,
    lastAlpha = nil,
    hasValue = false,
    shown = false,
    equipped = false,
    grey = false,
    warn = false,
    colourKey = nil,
    showNum = false,
    numText = nil,
    numW = 0,
    fontPx = fontPx,
    numH = math.floor(fontPx * NUM_LINE + 0.5),
    baseW = ICON_H,
    baseH = ICON_H,
    iconW = 0,
    iconH = ICON_H,
    offset = 0,
    width = 0,
    brushKey = nil,
    brush = nil,
    count = nil,
    debugOn = nil,
    debugNum = nil,
    liveBrush = false,
    lastPx = nil,
    lastPy = nil,
  }
end

function Icons:build()
  self:destroy()
  local engine = FindFirstOf('GameEngine') or FindFirstOf('Engine')
  if not valid(engine) then return false end
  local gi = prop(engine, 'GameInstance')
  if not valid(gi) then return false end
  local suffix = tostring(os.time()) .. '_' .. tostring(math.random(1000, 9999))
  local root = StaticConstructObject(cls(CLASS.user), gi, FName('PBZArcs_Icons_' .. suffix))
  local tree = StaticConstructObject(cls(CLASS.tree), root, FName('PBZArcs_IconsTree_' .. suffix))
  if not (valid(root) and valid(tree)) then return false end
  root.WidgetTree = tree
  local canvas = StaticConstructObject(cls(CLASS.canvas), tree, FName('PBZArcs_IconsCanvas_' .. suffix))
  tree.RootWidget = canvas
  self.root, self.tree, self.canvas = root, tree, canvas
  self.textScale = nil
  self.medEntries = {}
  for index = 1, 2 do
    local entry = self:createEntry('Med' .. index, 1, true)
    if entry then self.medEntries[#self.medEntries + 1] = entry end
  end
  self.ultEntries = {}
  local ultimate = self:createEntry('Ult', 2, false)
  if ultimate then
    ultimate.offId = 'Ult1'
    ultimate.staticPath = ULT_ART.ultimate
    ultimate.tint = ULT_TINT
    ultimate.dimAtZero = true
    self:applyStaticBrush(ultimate)
    -- Only the 精纯杀气 icon carries a charge fill; the bullet count has no
    -- progress in the attribute set to drive one.
    ultimate.fill = self:buildFill(ultimate, 'Ult', 3)
    self.ultEntries[#self.ultEntries + 1] = ultimate
  end
  local bullet = self:createEntry('Bullet', 2, false)
  if bullet then
    bullet.offId = 'Ult2'
    bullet.staticPath = ULT_ART.bullet
    bullet.dimAtZero = true
    self:applyStaticBrush(bullet)
    self.ultEntries[#self.ultEntries + 1] = bullet
  end
  if #self.medEntries == 0 and #self.ultEntries == 0 then
    self:destroy()
    return false
  end
  root:AddToViewport(55)
  pcall(function() root:SetVisibility(1) end)
  self.shownValue = false
  self.log('icons built')
  return true
end

function Icons:childNamed(widget, name)
  if not valid(widget) then return nil end
  local tree = unwrap(prop(widget, 'WidgetTree'))
  local root = valid(tree) and unwrap(prop(tree, 'RootWidget')) or nil
  local found = nil
  local function walk(node, depth)
    if found ~= nil or depth > 6 then return end
    local okN, count = pcall(function() return node:GetChildrenCount() end)
    if not okN or type(count) ~= 'number' then return end
    for i = 0, count - 1 do
      local okC, child = pcall(function() return node:GetChildAt(i) end)
      child = okC and unwrap(child) or nil
      if valid(child) then
        local okName, fname = pcall(function() return child:GetFName():ToString() end)
        if okName and fname == name then
          found = child
          return
        end
        walk(child, depth + 1)
        if found ~= nil then return end
      end
    end
  end
  walk(root, 0)
  return found
end

function Icons:applyStaticBrush(entry)
  if not entry.staticPath then return end
  local texture = unwrap(StaticFindObject(entry.staticPath))
  if not valid(texture) then return end
  if applyBrush(entry.image, { resource = texture, class = 'Texture2D', key = entry.staticPath }) then
    entry.brushKey = entry.staticPath
  end
  pcall(function() entry.image:SetColorAndOpacity(entry.tint) end)
end

-- The fill is a copy of the icon clipped to the charged part of its own height. The
-- panel is sized to that part and clips its children to its bounds, so the copy is
-- cut off at the charge line instead of being stretched, and the flame fills from
-- the bottom up over the icon itself.
function Icons:buildFill(entry, name, z)
  if not entry.staticPath then return nil end
  local resource = unwrap(StaticFindObject(entry.staticPath))
  if not valid(resource) then return nil end
  local panel = StaticConstructObject(cls(CLASS.canvas), self.tree, FName('PBZArcs_Icons_' .. name .. '_fill'))
  local icon = StaticConstructObject(cls(CLASS.image), self.tree, FName('PBZArcs_Icons_' .. name .. '_fillIcon'))
  if not (valid(panel) and valid(icon)) then return nil end
  if not applyBrush(icon, { resource = resource, class = 'Texture2D', key = entry.staticPath }) then
    return nil
  end
  pcall(function() icon:SetColorAndOpacity(entry.tint) end)
  local panelSlot = addChild(self.canvas, panel, 0, 0, 0, 0, z)
  local iconSlot = valid(panelSlot) and addChild(panel, icon, 0, 0, 0, 0, 0) or nil
  if not valid(iconSlot) then
    pcall(function() icon:RemoveFromParent() end)
    pcall(function() panel:RemoveFromParent() end)
    return nil
  end
  local wrote = pcall(function() panel.Clipping = CLIP_TO_BOUNDS end)
  local readBack
  pcall(function() readBack = panel.Clipping end)
  if tostring(readBack) ~= tostring(CLIP_TO_BOUNDS) then
    pcall(function() panel:SetClipping(CLIP_TO_BOUNDS) end)
    pcall(function() readBack = panel.Clipping end)
  end
  pcall(function() panel:SetVisibility(1) end)
  -- Whether the clip actually took is only visible in game, so the value written back
  -- is logged once; if it reads empty the fill shows as a whole bright icon.
  self.log(string.format('icons fill clip wrote=%s read=%s', tostring(wrote), tostring(readBack)))
  return {
    panel = panel, panelSlot = panelSlot,
    icon = icon, iconSlot = iconSlot,
    shown = nil, x = nil, y = nil, w = nil, h = nil, innerY = nil,
  }
end

function Icons:destroy()
  if self.root ~= nil and valid(self.root) then
    pcall(function() self.root:RemoveFromParent() end)
  end
  self.root, self.tree, self.canvas = nil, nil, nil
  self.medEntries = {}
  self.ultEntries = {}
  self.quickslot, self.weapon = nil, nil
  self.shownValue = nil
  self.dragging = nil
end

function Icons:scan()
  local function adopt(old, shortName, names, label)
    if valid(old) and hasAnyChild(old, names) then return old end
    local found = findLive(shortName, names)
    if not valid(found) then return old end
    if valid(old) and fullName(old) == fullName(found) then return old end
    self.log('icons source ' .. label .. ': ' .. fullName(found))
    return found
  end
  local previous = self.weapon
  self.quickslot = adopt(self.quickslot, 'WB_quickslot_C', QUICK_CHILDREN, 'quick')
  self.weapon = adopt(self.weapon, 'W_WeaponUI_C', WEAPON_CHILDREN, 'weapon')
  if self.weapon ~= previous then self.bulletNum = nil end
end

local function slotState(icon, num)
  local info = valid(icon) and brushInfo(icon) or nil
  local iconOn = valid(icon) and chainVisible(icon)
  local numOn = valid(num) and chainVisible(num)
  local text = valid(num) and textValue(prop(num, 'Text')) or nil
  local count = nil
  if type(text) == 'string' then
    local digits = text:match('%d+')
    if digits then count = tonumber(digits) end
  end
  -- Own visibility decides "equipped": the game hides the whole slot when the
  -- medicine type is not equipped, and keeps the icon when the charges run out.
  local equipped = iconOn
  if not equipped and numOn and count ~= nil and count > 0 then equipped = true end
  return {
    equipped = equipped,
    iconOn = iconOn,
    numOn = numOn,
    count = count,
    text = text,
    info = info,
  }
end

local EMPTY_STATE = {
  equipped = false, iconOn = false, numOn = false,
  count = nil, text = nil, info = nil,
}

-- One rule for every readout: show whatever the game counted, and when the game
-- hides the count but leaves the icon up the answer is zero.
local function resolveCount(text, live, hasIcon)
  local count = (live == true) and digitsOf(text) or nil
  if count ~= nil then
    local shown = (type(text) == 'string' and text ~= '') and text or tostring(count)
    return count, shown
  end
  if hasIcon ~= true then return nil, '' end
  return 0, '0'
end

function Icons:warnColour()
  local hex = tostring(self.S.WarnColor or '')
  if self._warnHex ~= hex then
    self._warnHex = hex
    self._warnRGB = Config.hexToLinear(hex)
  end
  return self._warnRGB, self._warnHex
end

-- Zero counts take the arcs' warning colour, so turning WarnColor up or down
-- reaches the digits on the next read instead of waiting for the number to move.
function Icons:applyTextColour(entry)
  local warnRGB, warnHex = self:warnColour()
  local colour = entry.warn and warnRGB or NUM_COLOUR
  local key = entry.warn and ('warn' .. warnHex) or 'plain'
  if entry.colourKey == key then return end
  entry.colourKey = key
  pcall(function()
    entry.text:SetColorAndOpacity({ SpecifiedColor = colour, ColorUseRule = 0 })
  end)
end

function Icons:applySlot(entry, state)
  entry.equipped = state.equipped == true
  local count, numText = resolveCount(state.text, state.numOn, entry.equipped)
  entry.count = count
  entry.warn = count ~= nil and count <= 0
  entry.grey = entry.canGrey and entry.equipped and entry.warn == true
  entry.numText = numText
  entry.showNum = count ~= nil
  entry.debugOn = state.iconOn
  entry.debugNum = state.numOn
  entry.liveBrush = state.info ~= nil
  if entry.equipped and state.info ~= nil then
    if entry.brushKey ~= state.info.key then
      if applyBrush(entry.image, state.info) then
        entry.brushKey = state.info.key
      end
    end
    entry.brush = state.info
    local ratio = 1
    if state.info.w and state.info.h and state.info.h > 0 then
      ratio = state.info.w / state.info.h
    end
    local sc = self:scale()
    entry.iconW = math.max(px(28, sc), math.min(px(64, sc), px(ICON_H * ratio, sc)))
  end
  pcall(function() entry.image:SetColorAndOpacity(entry.grey and ICON_GREY or ICON_WHITE) end)
  pcall(function() entry.text:SetText(FText(numText)) end)
  self:applyTextColour(entry)
end

function Icons:applyValue(entry, text, live, iconOn)
  -- live is the game's own visibility for that readout, iconOn whether the icon it
  -- belongs to is still drawn: the swirl is collapsed whenever the ammo is not
  -- equipped, and a collapsed count with a live icon is a count of zero.
  local count, numText = resolveCount(text, live, iconOn)
  local changed = entry.numText ~= numText
  entry.hasValue = count ~= nil
  entry.equipped = count ~= nil
  entry.count = count
  entry.warn = count ~= nil and count <= 0
  entry.numText = numText
  entry.showNum = count ~= nil
  entry.debugNum = live == true
  if entry.dimAtZero then
    -- A count of zero dims the icon; one or more restores it to full brightness.
    entry.iconAlpha = ULT_DIM + (1 - ULT_DIM) * math.min(1, count or 0)
  end
  if changed then
    pcall(function()
      entry.text:SetText(FText(numText))
    end)
  end
  self:applyTextColour(entry)
end

function Icons:read()
  local q = self.quickslot
  if valid(q) then
    -- BottomMedicineNum first, then TopMedicineNum.
    if self.medEntries[1] ~= nil then
      local num = unwrap(prop(q, 'BottomMedicineNum'))
      local state = slotState(unwrap(prop(q, 'Icon')), num)
      -- The unbound front-end copy carries a menu-icon brush in IconBrush, so
      -- the property is only a fallback once the slot itself is alive.
      if state.info == nil and valid(num) then
        state.info = brushInfoFromStruct(unwrap(prop(q, 'IconBrush')))
      end
      self:applySlot(self.medEntries[1], state)
    end
    if self.medEntries[2] ~= nil then
      self:applySlot(self.medEntries[2], slotState(
        unwrap(prop(q, 'Icon_next')), unwrap(prop(q, 'TopMedicineNum'))))
    end
  else
    for _, entry in ipairs(self.medEntries) do
      self:applySlot(entry, EMPTY_STATE)
    end
  end

  local w = self.weapon
  if #self.ultEntries > 0 then
    if valid(w) then
      local pureNum = unwrap(prop(w, 'PureShachiNum'))
      if self.ultEntries[1] then
        self:applyValue(self.ultEntries[1], textValue(prop(pureNum, 'Text')),
          chainVisible(pureNum), iconPresent(pureNum, unwrap(prop(w, 'PureShachiImage'))))
      end
      -- BulletNum sits deeper in the tree than the other named widgets.
      if not valid(self.bulletNum) then
        self.bulletNum = unwrap(prop(w, 'BulletNum')) or self:childNamed(w, 'BulletNum')
      end
      if self.ultEntries[2] then
        self:applyValue(self.ultEntries[2], textValue(prop(self.bulletNum, 'Text')),
          chainVisible(self.bulletNum), iconPresent(self.bulletNum, nil))
      end
    else
      for _, entry in ipairs(self.ultEntries) do self:applyValue(entry, nil) end
    end
  end

  if self.S.Debug then
    local parts = {}
    for index, entry in ipairs(self.medEntries) do
      parts[#parts + 1] = string.format('med%d icon=%s num=%s count=%s shown=%s warn=%s live=%s cached=%s',
        index, tostring(entry.debugOn), tostring(entry.debugNum),
        tostring(entry.count), tostring(entry.shown), tostring(entry.warn),
        tostring(entry.liveBrush), tostring(entry.brushKey ~= nil))
    end
    for index, entry in ipairs(self.ultEntries) do
      parts[#parts + 1] = string.format('ult%d text=%s live=%s count=%s shown=%s warn=%s brush=%s',
        index, tostring(entry.numText), tostring(entry.debugNum), tostring(entry.count),
        tostring(entry.shown), tostring(entry.warn), tostring(entry.brushKey ~= nil))
    end
    local signature = table.concat(parts, ' | ')
    if self.ultEntries[1] ~= nil then
      signature = signature .. string.format(' | ratio=%s', tostring(self.ultRatio))
    end
    if signature ~= self.lastSignature then
      self.lastSignature = signature
      self.log('icons state: ' .. signature)
    end
  end
end

function Icons:computeLayout()
  local S = self.S
  local vw, vh = self:viewport()
  local medOn = S.MedicineHud ~= false
  local sc = self:scale()
  self:applyTextScale(sc)
  local rowH = px(ICON_H, sc)
  local numGap = px(NUM_GAP, sc)
  local entryGap = px(ENTRY_GAP, sc)
  local charW = px(NUM_CHAR_W, sc)
  local minNumW = px(NUM_MIN_W, sc)
  self.rowH, self.numGap = rowH, numGap

  -- Static icons only get a size from the layout; the medicine brushes keep the
  -- aspect ratio read from the live HUD widget.
  for _, list in ipairs({ self.medEntries, self.ultEntries }) do
    for _, entry in ipairs(list) do
      entry.iconH = px(entry.baseH, sc)
      if entry.staticPath ~= nil then entry.iconW = px(entry.baseW, sc) end
    end
  end

  local x = 0
  local medVisible = false
  for _, entry in ipairs(self.medEntries) do
    entry.shown = medOn and entry.equipped
    if entry.shown then
      local numW = entry.showNum and math.max(minNumW, charW * #entry.numText) or 0
      entry.numW = math.floor(numW)
      entry.offset = x
      local width = entry.iconW
      if entry.numW > 0 then
        width = width + (entry.iconW > 0 and numGap or 0) + entry.numW
      end
      entry.width = width
      x = x + width + entryGap
      medVisible = true
    else
      entry.numW = 0
      entry.width = 0
      entry.offset = 0
    end
  end
  local medW = medVisible and math.max(0, x - entryGap) or 0

  local ultOn = S.UltHud ~= false
  local ultVisible = false
  local ux = 0
  for _, entry in ipairs(self.ultEntries) do
    entry.shown = ultOn and entry.hasValue
    if entry.shown then
      local numW = entry.showNum and math.max(minNumW, charW * #entry.numText) or 0
      entry.numW = math.floor(numW)
      entry.offset = ux
      local width = entry.iconW
      if entry.numW > 0 then
        width = width + (entry.iconW > 0 and numGap or 0) + entry.numW
      end
      entry.width = width
      ux = ux + width + entryGap
      ultVisible = true
    else
      entry.numW = 0
      entry.width = 0
      entry.offset = 0
    end
  end
  local ultW = ultVisible and math.max(0, ux - entryGap) or 0

  local medAutoX = (tonumber(S.MedicineHudX) or -1) < 0
  local ultAutoX = (tonumber(S.UltHudX) or -1) < 0
  local medAutoY = (tonumber(S.MedicineHudY) or -1) < 0
  local ultAutoY = (tonumber(S.UltHudY) or -1) < 0
  -- The margin is a screen distance, not part of the icon row: a bigger IconScale
  -- grows the row upwards and keeps its bottom edge on the same line.
  local yDefault = math.max(10, vh - BOTTOM_MARGIN - rowH)

  if medVisible and ultVisible and medAutoX and ultAutoX then
    local total = medW + px(GROUP_GAP, sc) + ultW
    self.medX = math.floor(vw / 2 - total / 2 + 0.5)
    self.ultX = self.medX + medW + px(GROUP_GAP, sc)
  else
    self.medX = medAutoX and math.floor(vw / 2 - medW / 2 + 0.5) or (tonumber(S.MedicineHudX) or 0)
    self.ultX = ultAutoX and math.floor(vw / 2 - ultW / 2 + 0.5) or (tonumber(S.UltHudX) or 0)
  end
  self.medY = medAutoY and yDefault or (tonumber(S.MedicineHudY) or 0)
  self.ultY = ultAutoY and yDefault or (tonumber(S.UltHudY) or 0)
  self.medW, self.ultW = medW, ultW
  self.medVisible, self.ultVisible = medVisible, ultVisible
end

function Icons:entryOff(entry)
  local id = entry.offId
  if type(id) ~= 'string' then return 0, 0 end
  return math.floor(tonumber(self.S[id .. 'OffX']) or 0),
    math.floor(tonumber(self.S[id .. 'OffY']) or 0)
end

-- The panel's rect is the bottom slice of the icon, so the copy inside it is offset
-- up by exactly what the slice left out and lines up with the icon underneath; the
-- clip cuts the rest. The copy stays at full brightness, so the charged part reads
-- as the plain tinted icon and the rest keeps the game's own dimming.
function Icons:placeFill(entry, x, y)
  local fill = entry.fill
  if fill == nil then return end
  local ratio = tonumber(self.ultRatio)
  local active = ratio ~= nil and self.S.UltChargeBar ~= false
  local show = entry.shown and active and entry.iconW > 0
  local h = math.floor(entry.iconH)
  local fillH = show and math.floor(h * math.max(0, math.min(1, ratio)) + 0.5) or 0
  if fillH <= 0 then
    if fill.shown ~= false then
      fill.shown = false
      pcall(function() fill.panel:SetVisibility(1) end)
    end
    return
  end
  local w = math.floor(entry.iconW)
  local iconY = math.floor(y + (self.rowH - entry.iconH) / 2)
  local panelY = iconY + h - fillH
  local innerY = iconY - panelY
  if fill.shown ~= true then
    fill.shown = true
    pcall(function() fill.panel:SetVisibility(0) end)
    fill.x, fill.y, fill.w, fill.h, fill.innerY = nil, nil, nil, nil, nil
  end
  if fill.x ~= x or fill.y ~= panelY or fill.w ~= w or fill.h ~= fillH then
    fill.x, fill.y, fill.w, fill.h = x, panelY, w, fillH
    pcall(function() fill.panelSlot:SetPosition({ X = x, Y = panelY }) end)
    pcall(function() fill.panelSlot:SetSize({ X = w, Y = fillH }) end)
    pcall(function() fill.iconSlot:SetSize({ X = w, Y = h }) end)
    fill.innerY = nil
  end
  if fill.innerY ~= innerY then
    fill.innerY = innerY
    pcall(function() fill.iconSlot:SetPosition({ X = 0, Y = innerY }) end)
  end
end

function Icons:placeEntry(entry, gx, gy)
  if not entry.shown then
    if entry.lastPx ~= nil then
      pcall(function() entry.image:SetVisibility(1) end)
      pcall(function() entry.text:SetVisibility(1) end)
      entry.lastPx = nil
      entry.lastW = nil
    end
    self:placeFill(entry, 0, 0)
    return
  end
  local ox, oy = self:entryOff(entry)
  local x = gx + entry.offset + ox
  local y = gy + oy
  local rowH = self.rowH
  if entry.iconW > 0 then
    local h = entry.iconH
    local iconY = y + (rowH - h) / 2
    if entry.lastPx ~= x or entry.lastPy ~= y or entry.lastW ~= entry.iconW or entry.lastH ~= h then
      pcall(function() entry.imageSlot:SetPosition({ X = x, Y = iconY }) end)
      pcall(function() entry.imageSlot:SetSize({ X = entry.iconW, Y = h }) end)
      entry.lastW = entry.iconW
      entry.lastH = h
    end
    pcall(function() entry.image:SetVisibility(0) end)
    if entry.iconAlpha ~= nil and entry.lastAlpha ~= entry.iconAlpha then
      entry.lastAlpha = entry.iconAlpha
      pcall(function() entry.image:SetRenderOpacity(entry.iconAlpha) end)
    end
  else
    pcall(function() entry.image:SetVisibility(1) end)
  end
  if entry.numW > 0 and entry.showNum then
    -- entry.numH stays in unscaled glyph pixels: the render pivot is the slot's
    -- mid-height, so centring the slot on the row centres the digits on the icon.
    local numH = entry.numH
    local tx = x + (entry.iconW > 0 and (entry.iconW + self.numGap) or 0)
    pcall(function() entry.textSlot:SetPosition({ X = tx, Y = y + (rowH - numH) / 2 }) end)
    pcall(function() entry.textSlot:SetSize({ X = entry.numW, Y = numH }) end)
    pcall(function() entry.text:SetVisibility(0) end)
  else
    pcall(function() entry.text:SetVisibility(1) end)
  end
  entry.lastPx, entry.lastPy = x, y
  self:placeFill(entry, x, y)
end

function Icons:applyPositions()
  for _, entry in ipairs(self.medEntries) do
    self:placeEntry(entry, self.medX, self.medY)
  end
  for _, entry in ipairs(self.ultEntries) do
    self:placeEntry(entry, self.ultX, self.ultY)
  end
end

function Icons:setShown(shown, opacity)
  shown = shown and true or false
  opacity = math.max(0, math.min(1, tonumber(opacity) or 1))
  if opacity <= 0.01 then shown, opacity = false, 0 end
  if not shown then opacity = 0 end
  if self.shownValue == shown and self.shownOpacity == opacity then return end
  self.shownValue, self.shownOpacity = shown, opacity
  if valid(self.root) then
    -- Self-hit-test-invisible: the readouts never intercept the mouse, the
    -- module does its own cursor hit testing while the menu is open.
    pcall(function() self.root:SetVisibility(shown and 4 or 1) end)
    pcall(function() self.root:SetRenderOpacity(opacity) end)
  end
end

function Icons:update(dt, ctx)
  ctx = ctx or {}
  -- 精纯杀气的充能比例由 main.lua 从属性里读好交进来；nil 表示读不到，充能条不出现。
  self.ultRatio = tonumber(ctx.ultRatio)
  local now = os.clock()
  if not valid(self.root) then
    if now >= self.buildAt then
      self.buildAt = now + 1.0
      self:build()
    end
    if not valid(self.root) then return end
  end

  if self.dragging ~= nil and not ctx.menuOpen then self:endDrag() end

  if now - self.scanAt >= SCAN_INTERVAL then
    self.scanAt = now
    self:scan()
  end
  if now - self.readAt >= READ_INTERVAL then
    self.readAt = now
    self:read()
  end

  self:computeLayout()
  local any = self.medVisible or self.ultVisible
  -- The readouts follow the arcs' display setting; the full-value hide of dynamic
  -- belongs to the bars, so here dynamic behaves like hud. ctx.hudFade carries the
  -- HUD's own opacity so a fading HUD takes the readouts along instead of leaving
  -- them lit until the HUD is reported fully gone.
  local shown = any and (ctx.menuOpen or (ctx.enabled and not ctx.uiOpen and ctx.hudShown))
  self:setShown(shown, tonumber(ctx.hudFade) or 1)
  self:applyPositions()
end

local function inRect(x, y, rx, ry, rw, rh)
  return x >= rx and x <= rx + rw and y >= ry and y <= ry + rh
end

local function clampi(v, lo, hi)
  if v < lo then return lo end
  if v > hi then return hi end
  return v
end

local GROUP_KEYS = {
  med = { x = 'MedicineHudX', y = 'MedicineHudY' },
  ult = { x = 'UltHudX', y = 'UltHudY' },
}

function Icons:groupOrigin(group)
  if group == 'med' then return self.medX, self.medY, self.medW end
  return self.ultX, self.ultY, self.ultW
end

function Icons:groupEntries(group)
  return (group == 'med') and self.medEntries or self.ultEntries
end

-- Keep a group inside the screen and write its position back to the settings.
function Icons:setGroupAt(group, x, y)
  local vw, vh = self:viewport()
  local width = (group == 'med') and self.medW or self.ultW
  local nx = math.max(-width + 20, math.min(vw - 20, x))
  local ny = math.max(0, math.min(vh - 10, y))
  if group == 'med' then
    self.medX, self.medY = nx, ny
    self.S.MedicineHudX, self.S.MedicineHudY = math.floor(nx + 0.5), math.floor(ny + 0.5)
  else
    self.ultX, self.ultY = nx, ny
    self.S.UltHudX, self.S.UltHudY = math.floor(nx + 0.5), math.floor(ny + 0.5)
  end
end

-- Returns the group, the entry and the entry's top-left corner under the cursor.
function Icons:hitAt(x, y)
  local sc = self:scale()
  local padX, padY = px(4, sc), px(7, sc)
  local groups = {
    { name = 'med', entries = self.medEntries, shown = self.medVisible },
    { name = 'ult', entries = self.ultEntries, shown = self.ultVisible },
  }
  for _, candidate in ipairs(groups) do
    if candidate.shown then
      local gx, gy = self:groupOrigin(candidate.name)
      for _, entry in ipairs(candidate.entries) do
        if entry.shown then
          local ox, oy = self:entryOff(entry)
          local ex, ey = gx + entry.offset + ox, gy + oy
          if inRect(x, y, ex - padX, ey - padY, entry.width + 2 * padX, self.rowH + 2 * padY) then
            return candidate.name, entry, ex, ey
          end
        end
      end
    end
  end
  return nil
end

-- Middle button: every icon goes back to the automatic layout and each one loses
-- its hand-placed shift.
function Icons:resetSet()
  for _, group in ipairs({ 'med', 'ult' }) do
    local keys = GROUP_KEYS[group]
    self.S[keys.x], self.S[keys.y] = -1, -1
    for _, entry in ipairs(self:groupEntries(group)) do
      if type(entry.offId) == 'string' then
        self.S[entry.offId .. 'OffX'] = 0
        self.S[entry.offId .. 'OffY'] = 0
      end
    end
  end
  Config.save(self.S)
  self:computeLayout()
  self:applyPositions()
  self.log('icons set reset')
end

-- Left button drags every icon as one set, right button drags the single icon under
-- the cursor, middle button resets the whole set.
function Icons:press(menu, button)
  if not valid(self.root) or not self.shownValue then return false end
  local x, y = mousePosition()
  if x == nil or y == nil then return false end
  if menu and menu.hitPanel and menu:hitPanel(x, y) then return false end
  -- A press edge always follows a release, so whatever was held is finished.
  if self.dragging ~= nil then self:endDrag() end
  local group, entry, ex, ey = self:hitAt(x, y)
  if group == nil then return false end
  if button == 'mmb' then
    self:resetSet()
    return true
  end
  local single = (button == 'rmb') and entry or nil
  local gx, gy = self:groupOrigin(group)
  local drag = {
    group = single and group or 'all',
    anchor = group,
    entry = single,
    menu = menu,
    hold = { button = single and 'rmb' or 'lmb' },
  }
  if drag.group == 'all' then
    drag.start = {
      med = { x = self.medX, y = self.medY },
      ult = { x = self.ultX, y = self.ultY },
    }
  end
  if drag.menu == nil or not drag.menu.checkHold then drag.hold.reliable = false end
  if single then
    drag.dx, drag.dy = x - ex, y - ey
  else
    drag.dx, drag.dy = x - gx, y - gy
  end
  self.dragging = drag
  self.still = 0
  self.lastX, self.lastY = x, y
  self.moved = false
  return true
end

function Icons:endDrag()
  local drag = self.dragging
  self.dragging = nil
  self.still = 0
  self.lastX, self.lastY = nil, nil
  if drag == nil or not self.moved then return end
  self.moved = false
  Config.save(self.S)
  if drag.entry then
    local ox, oy = self:entryOff(drag.entry)
    self.log(string.format('icons %s shifted %d,%d', drag.entry.offId or '?', ox, oy))
  else
    local gx, gy = self:groupOrigin(drag.anchor)
    self.log(string.format('icons set at %.0f,%.0f', gx, gy))
  end
end

function Icons:poll(dt)
  local drag = self.dragging
  if drag == nil then return end
  local x, y = mousePosition()
  if x == nil or y == nil then return end
  local held = nil
  if drag.menu ~= nil and drag.menu.checkHold then held = drag.menu:checkHold(drag.hold, dt) end
  local moved = self.lastX == nil
    or math.abs(self.lastX - x) > 0.5 or math.abs(self.lastY - y) > 0.5
  if held == false then
    self:endDrag()
    return
  end
  if not moved and held ~= true then
    -- Only fall back to the still cursor once the hold probe has made up its mind.
    if held == nil and drag.hold.reliable ~= nil then
      self.still = self.still + (tonumber(dt) or 0.016)
      if self.still > STILL_TIME then self:endDrag() end
    end
    return
  end
  self.lastX, self.lastY = x, y
  self.still = 0
  self.moved = true
  local gx, gy = self:groupOrigin(drag.anchor)
  if drag.entry then
    local ox = clampi(math.floor((x - drag.dx) - gx - drag.entry.offset + 0.5), -800, 800)
    local oy = clampi(math.floor((y - drag.dy) - gy + 0.5), -800, 800)
    if type(drag.entry.offId) == 'string' then
      self.S[drag.entry.offId .. 'OffX'] = ox
      self.S[drag.entry.offId .. 'OffY'] = oy
    end
  else
    local anchor = drag.start[drag.anchor]
    local dx = (x - drag.dx) - anchor.x
    local dy = (y - drag.dy) - anchor.y
    for _, name in ipairs({ 'med', 'ult' }) do
      local origin = drag.start[name]
      self:setGroupAt(name, origin.x + dx, origin.y + dy)
    end
  end
  self:applyPositions()
end

return Icons
