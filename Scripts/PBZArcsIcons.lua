-- PBZPlayerArcs：从实时 HUD 镜像出来的扁平化药品 / 绝招数值读数。
-- 游戏把这些计数放在 HUD 控件里而不是属性集里，所以药品图标
-- 取自 WB_quickslot_C，数字取自 W_WeaponUI_C。
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

-- 这些是 IconScale = 1 时渲染出的像素值；滑块会让它们一起放大。
local ICON_H = 42
local NUM_GAP = 8
local ENTRY_GAP = 25
local BOTTOM_MARGIN = 152
local NUM_FONT = 18
local NUM_LINE = 1.2
-- 静态贴图里的画面位于其包围盒中线偏上，而实时瓶身画面偏下，因此静态图标
-- 要下移，才能与瓶子共用同一条中线。该值取自截图测量，随 IconScale 缩放。
local STATIC_ART_DROP = 3
-- 计数上的黑色描边，与进度条数字的处理方式一致。
local NUM_OUTLINE = 1
-- 当 Font.Size 读不回来时，假定数字是按这个尺寸构建的。
-- 27 是主题所用的尺寸，所以 18/27 的渲染比例正好是它的三分之二。
local NUM_ASSUMED_PX = 27
local NUM_CHAR_W = 13
local NUM_MIN_W = 20
local STILL_TIME = 0.12
local READ_INTERVAL = 0.10
local SCAN_INTERVAL = 0.50

-- IconScale 会乘上这些基础像素值，因此图标、它们的数字以及彼此之间的间隙
-- 都会一起放大。NUM_FONT 是数字最终绘制出来的高度；文本控件本身则通过它的
-- 渲染缩放来调整大小，因为那是 UMG 唯一会重绘的文本属性。
local function px(base, scale) return math.floor(base * scale + 0.5) end

local NUM_COLOUR = { R = 0.93, G = 0.90, B = 0.84, A = 1 }
local ICON_GREY = { R = 0.42, G = 0.42, B = 0.42, A = 0.85 }
local ICON_WHITE = { R = 1, G = 1, B = 1, A = 1 }
local ULT_TINT = { R = 0.62, G = 0.30, B = 1, A = 1 }
local ULT_DIM = 0.34

-- 精纯杀气的充能直接画进图标本身：图标保持原有的单一着色，
-- 再把它的一份全亮副本按其自身高度的充能比例裁剪，
-- 于是图标从底部向上填充。
-- CLIP 即 FWidgetClipping::ClipToBounds。
local CLIP_TO_BOUNDS = 1

-- 游戏把绝招画成 Niagara 火焰、把弹药画成以材质填充的漩涡，所以那些笔刷
-- 用不了。这两张贴图是静态替代品：一个染成紫色的火焰轮廓，以及漩涡图案。
local ULT_ART = {
  ultimate = '/Game/PBZContent/UI/Hud/Art/Icon_Hud_JingChun_Fire.Icon_Hud_JingChun_Fire',
  bullet = '/Game/PBZContent/VFX/SceneFX/UI/BattleSystem/Assets/T_UI_ShaChiBullet_001_FG.T_UI_ShaChiBullet_001_FG',
}

local Util = require('PBZArcsUtil')
local valid, prop, unwrap, cls = Util.valid, Util.prop, Util.unwrap, Util.cls
local VIS, Z = Util.VIS, Util.Z

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

-- 某个读数文本所带的计数；文本中没有数字时返回 nil。
local function digitsOf(text)
  if type(text) ~= 'string' then return nil end
  return tonumber(text:match('%d+'))
end

-- 槽位可能被它自己的标志隐藏，也可能被游戏为未装备槽位而折叠的
-- 某一层覆盖物隐藏，所以整条短链都必须一致。
local function chainVisible(widget)
  local cur = widget
  for _ = 1, 6 do
    if not valid(cur) then return false end
    local okV, visibility = pcall(function() return cur.Visibility end)
    if okV and (visibility == VIS.Collapsed or visibility == VIS.Hidden) then return false end
    local okO, opacity = pcall(function() return cur.RenderOpacity end)
    if okO and type(opacity) == 'number' and opacity <= 0.01 then return false end
    local okP, parent = pcall(function() return cur:GetParent() end)
    if not okP or not valid(parent) then break end
    cur = parent
  end
  return true
end

-- 游戏是否仍在绘制某读数所属的图标：HUD 有它自己的图像控件时就用那个，
-- 否则用承载数字的那一行。两者任一存在即可；数字随图标折叠而图标仍在
-- 绘制，就是零的样子。
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

-- 有多个实例共用这个类名：CDO、前端布局里一个图表从未绑定的子控件，
-- 以及真正的游戏内 HUD。只有最后一个拥有 Icon/Num 子控件，
-- 所以先按子控件来挑。
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
  local write = log or function() end
  return setmetatable({
    S = settings,
    -- log 只在 Debug 打开时写。
    log = function(message) if settings.Debug then write(message) end end,
    root = nil,
    tree = nil,
    canvas = nil,
    medEntries = {},
    ultEntries = {},
    quickslot = nil,
    weapon = nil,
    bulletNum = nil,
    staticDrop = 0,
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

-- UTextBlock 在构建 Slate 控件时只读一次 Font，而 SetRenderScale 才是会
-- 触发重绘的属性，所以 IconScale 通过变换来放大数字。
-- 缩放是相对控件实际构建时的尺寸来算的，因此即使主题自己的字体
-- 尺寸不同，数字也会落在 NUM_FONT 上。
function Icons:applyTextScale(scale)
  if self.textScale == scale then return end
  self.textScale = scale
  for _, list in ipairs({ self.medEntries, self.ultEntries }) do
    for _, entry in ipairs(list) do
      local base = entry.fontPx or NUM_ASSUMED_PX
      local k = (NUM_FONT * scale) / base
      pcall(function() entry.text:SetRenderScale({ X = k, Y = k }) end)
      -- 轴心是槽位的中线高度，所以槽位必须与未缩放的
      -- 字形高度完全一致。槽位若更高，缩放一旦超过 1 就会把数字
      -- 拖到图标中线之上，这正是数字位置偏高的原因。
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
  -- 把尺寸读回来能告诉我们控件实际是按什么尺寸构建的。若读取
  -- 失败，就假定是主题自己的尺寸，这会让下面的缩放变成三分之二。
  local okFont, fontPx = pcall(function() return tonumber(text.Font.Size) end)
  if not (okFont and fontPx and fontPx > 0) then fontPx = NUM_ASSUMED_PX end
  -- 描边存在于字体结构体中，只有通过 SetFont 才会生效。它在控件
  -- 加入树之前就应用，所以运行时没有开销，而下面的渲染缩放
  -- 仍然决定数字的绘制尺寸。
  pcall(function()
    local font = text.Font
    local settings = font.OutlineSettings
    if settings == nil then settings = {} end
    settings.OutlineSize = NUM_OUTLINE
    settings.OutlineColor = { R = 0, G = 0, B = 0, A = 1 }
    font.OutlineSettings = settings
    text:SetFont(font)
  end)
  pcall(function() text.Justification = 0 end)
  -- IconScale 以渲染缩放的方式应用。轴心是槽位的左中：槽位对齐到
  -- 整行的中线，而从左边缘放大能在任何尺寸下都把数字留在图标
  -- 右侧。UMG 默认的居中会在缩放变大时把它们推回图标上方。
  pcall(function() text:SetRenderTransformPivot({ X = 0, Y = 0.5 }) end)
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
  pcall(function() image:SetVisibility(VIS.Collapsed) end)
  pcall(function() text:SetVisibility(VIS.Collapsed) end)
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
    -- 在共同尺寸下这幅画面看起来比其他图标更重，所以画得比它们
    -- 小一些；行布局直接用画面宽度，因此它两侧不会留下
    -- 空白。
    ultimate.baseW = 32
    ultimate.baseH = 32
    self:applyStaticBrush(ultimate)
    -- 只有精纯杀气图标带充能填充；弹药计数在属性集里
    -- 没有可驱动的进度。
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
  root:AddToViewport(Z.Icons)
  pcall(function() root:SetVisibility(VIS.Collapsed) end)
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

-- 填充是图标的一份副本，被裁剪到其自身高度的充能部分。面板被
-- 调整到该部分的大小，并把子控件裁剪到自己的边界，因此副本是在
-- 充能线处被切断而不是被拉伸，火焰便在图标本身之上
-- 从底部向上填充。
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
  pcall(function() panel:SetVisibility(VIS.Collapsed) end)
  -- 裁剪是否真的生效只能在游戏里看出来，所以把回读的值
  -- 记录一次；若读到空值，填充会显示成一整个亮色图标。
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
  -- 自身的可见性决定"已装备"：药品类型未装备时游戏会隐藏整个槽位，
  -- 而在充能耗尽时保留图标。
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

-- 所有读数共用一条规则：游戏数出什么就显示什么；当游戏隐藏了计数
-- 却留下图标时，答案就是零。
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

-- 零计数采用弧线的警告色，所以调高或调低 WarnColor 会在下一次
-- 读取时就作用到数字上，而不必等数字本身变化。
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
  -- 哨兵保证首次一定写：grey / numText 都可能是 nil，不能用 nil 当「未变」。
  if entry.greyPainted ~= true or entry.lastGrey ~= entry.grey then
    entry.greyPainted, entry.lastGrey = true, entry.grey
    pcall(function() entry.image:SetColorAndOpacity(entry.grey and ICON_GREY or ICON_WHITE) end)
  end
  if entry.textPainted ~= true or entry.lastSlotText ~= numText then
    entry.textPainted, entry.lastSlotText = true, numText
    pcall(function() entry.text:SetText(FText(numText)) end)
  end
  self:applyTextColour(entry)
end

function Icons:applyValue(entry, text, live, iconOn)
  -- live 是该读数在游戏里的可见性，iconOn 是它所属的图标是否仍被绘制：
  -- 弹药未装备时漩涡会被折叠，而计数被折叠、图标仍在，就代表计数为零。
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
    -- 计数为零会让图标变暗；一以上则恢复到全亮。
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
  if self.S.MedicineHud == false then
    -- 该组已关闭：在重新开启之前不要动它的控件。
  elseif valid(q) then
    -- 先 BottomMedicineNum，再 TopMedicineNum。
    if self.medEntries[1] ~= nil then
      local num = unwrap(prop(q, 'BottomMedicineNum'))
      local state = slotState(unwrap(prop(q, 'Icon')), num)
      -- 未绑定的前端副本会在 IconBrush 里带一个菜单图标笔刷，所以
      -- 该属性只在槽位本身存活时才作为后备。
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
  if self.S.UltHud ~= false and #self.ultEntries > 0 then
    if valid(w) then
      local pureNum = unwrap(prop(w, 'PureShachiNum'))
      if self.ultEntries[1] then
        self:applyValue(self.ultEntries[1], textValue(prop(pureNum, 'Text')),
          chainVisible(pureNum), iconPresent(pureNum, unwrap(prop(w, 'PureShachiImage'))))
      end
      -- BulletNum 在树中比其它具名控件更深。
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
  self.staticDrop = px(STATIC_ART_DROP, sc)

  -- 静态图标只由布局给定尺寸；药品笔刷则保留从实时 HUD 控件上
  -- 读到的长宽比。
  for _, list in ipairs({ self.medEntries, self.ultEntries }) do
    for _, entry in ipairs(list) do
      entry.iconH = px(entry.baseH, sc)
      if entry.staticPath ~= nil then
        entry.iconW = px(entry.baseW, sc)
      end
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
        width = width + (width > 0 and numGap or 0) + entry.numW
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
        width = width + (width > 0 and numGap or 0) + entry.numW
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
  -- 边距是屏幕距离，不属于图标行本身：IconScale 变大会让整行
  -- 向上生长，而底边保持在同一线上。
  local yDefault = math.max(10, vh - BOTTOM_MARGIN - rowH)

  if medVisible and ultVisible and medAutoX and ultAutoX then
    local total = medW + entryGap + ultW
    self.medX = math.floor(vw / 2 - total / 2 + 0.5)
    self.ultX = self.medX + medW + entryGap
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

function Icons:artTop(entry, y)
  local drop = entry.staticPath ~= nil and (self.staticDrop or 0) or 0
  return y + (self.rowH - entry.iconH) / 2 + drop
end

-- 面板的矩形是图标的底部切片，所以里面的副本要向上偏移
-- 恰好是切片略去的高度，从而与下面的图标对齐；其余部分由
-- 裁剪切掉。副本保持全亮，于是充能部分看起来就是普通着色
-- 的图标，其余部分保留游戏自身的变暗效果。
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
      pcall(function() fill.panel:SetVisibility(VIS.Collapsed) end)
    end
    return
  end
  local w = math.floor(entry.iconW)
  local artX = math.floor(x)
  local iconY = math.floor(self:artTop(entry, y))
  local panelY = iconY + h - fillH
  local innerY = iconY - panelY
  if fill.shown ~= true then
    fill.shown = true
    pcall(function() fill.panel:SetVisibility(VIS.Visible) end)
    fill.x, fill.y, fill.w, fill.h, fill.innerY = nil, nil, nil, nil, nil
  end
  if fill.x ~= artX or fill.y ~= panelY or fill.w ~= w or fill.h ~= fillH then
    fill.x, fill.y, fill.w, fill.h = artX, panelY, w, fillH
    pcall(function() fill.panelSlot:SetPosition({ X = artX, Y = panelY }) end)
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
      pcall(function() entry.image:SetVisibility(VIS.Collapsed) end)
      pcall(function() entry.text:SetVisibility(VIS.Collapsed) end)
      entry.lastPx = nil
      entry.lastW = nil
      entry.lastTx, entry.lastTy = nil, nil
      entry.lastNumW, entry.lastNumH = nil, nil
      entry.lastImageVis, entry.lastTextVis = nil, nil
    end
    self:placeFill(entry, 0, 0)
    return
  end
  local ox, oy = self:entryOff(entry)
  local x = gx + entry.offset + ox
  local y = gy + oy
  local rowH = self.rowH
  local artX = x
  if entry.iconW > 0 then
    local h = entry.iconH
    local iconY = self:artTop(entry, y)
    if entry.lastPx ~= x or entry.lastPy ~= y or entry.lastW ~= entry.iconW
      or entry.lastH ~= h then
      pcall(function() entry.imageSlot:SetPosition({ X = artX, Y = iconY }) end)
      pcall(function() entry.imageSlot:SetSize({ X = entry.iconW, Y = h }) end)
      entry.lastW = entry.iconW
      entry.lastH = h
    end
    if entry.lastImageVis ~= true then
      entry.lastImageVis = true
      pcall(function() entry.image:SetVisibility(VIS.Visible) end)
    end
    if entry.iconAlpha ~= nil and entry.lastAlpha ~= entry.iconAlpha then
      entry.lastAlpha = entry.iconAlpha
      pcall(function() entry.image:SetRenderOpacity(entry.iconAlpha) end)
    end
  else
    if entry.lastImageVis ~= false then
      entry.lastImageVis = false
      pcall(function() entry.image:SetVisibility(VIS.Collapsed) end)
    end
  end
  if entry.numW > 0 and entry.showNum then
    -- entry.numH 保持未缩放的字形像素：渲染轴心是槽位的中线
    -- 高度，所以把槽位在行上居中就能让数字在图标上居中。
    local numH = entry.numH
    local tx = x + (entry.iconW > 0 and (entry.iconW + self.numGap) or 0)
    local ty = y + (rowH - numH) / 2
    if entry.lastTx ~= tx or entry.lastTy ~= ty or entry.lastNumW ~= entry.numW
      or entry.lastNumH ~= numH then
      entry.lastTx, entry.lastTy = tx, ty
      entry.lastNumW, entry.lastNumH = entry.numW, numH
      pcall(function() entry.textSlot:SetPosition({ X = tx, Y = ty }) end)
      pcall(function() entry.textSlot:SetSize({ X = entry.numW, Y = numH }) end)
    end
    if entry.lastTextVis ~= true then
      entry.lastTextVis = true
      pcall(function() entry.text:SetVisibility(VIS.Visible) end)
    end
  else
    if entry.lastTextVis ~= false then
      entry.lastTextVis = false
      pcall(function() entry.text:SetVisibility(VIS.Collapsed) end)
    end
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
    -- 自身不参与命中测试：读数永不拦截鼠标，
    -- 菜单打开时由模块自己做光标命中测试。
    pcall(function() self.root:SetVisibility(shown and VIS.SelfHitTestInvisible or VIS.Collapsed) end)
    pcall(function() self.root:SetRenderOpacity(opacity) end)
  end
end

function Icons:update(dt, ctx)
  ctx = ctx or {}
  local now = os.clock()
  -- 两组读数都关闭：不构建、不读取、不布局也不绘制。根控件隐藏
  -- 一次，之后每一帧都在做任何工作之前返回。
  if self.S.MedicineHud == false and self.S.UltHud == false then
    if self.dragging ~= nil then self:endDrag() end
    self.medVisible, self.ultVisible = false, false
    if valid(self.root) then self:setShown(false, 1) end
    return
  end
  -- 精纯杀气的充能比例由 main.lua 从属性里读好交进来；nil 表示读不到，充能条不出现。
  self.ultRatio = tonumber(ctx.ultRatio)
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
  -- 读数跟随弧线的显示设置；dynamic 的满值隐藏属于进度条，
  -- 所以这里 dynamic 的行为与 hud 一致。ctx.hudFade 携带 HUD 自身的
  -- 透明度，使渐隐的 HUD 会带着读数一起淡出，而不是让它们
  -- 一直亮着直到 HUD 被报告完全消失。
  local shown = any and (ctx.menuOpen or ctx.hudShown)
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

-- 让某个组保持在屏幕内，并把它的位置写回设置。
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

-- 返回组、条目，以及该条目在光标下的左上角。
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

-- 中键：每个图标都回到自动布局，并失去各自
-- 手动摆放的偏移。
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

-- 左键把每个图标当作一整组拖动，右键拖动光标下的单个图标，
-- 中键重置整组。
function Icons:press(menu, button)
  if not valid(self.root) or not self.shownValue then return false end
  local x, y = mousePosition()
  if x == nil or y == nil then return false end
  if menu and menu.hitPanel and menu:hitPanel(x, y) then return false end
  -- 一次按下之前必定有一次松开，所以按着的东西先结束掉。
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
  if not moved then
    -- 明确按住但光标没动：不重算布局、不写 UMG，也不把 moved 置真。
    if held == true then
      self.still = 0
    elseif held == nil and drag.hold.reliable ~= nil then
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
  -- 拖动只改状态；本帧稍后的 update 会统一摆放，避免同帧写两次。
end

return Icons
