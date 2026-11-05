-- PBZPlayerArcs：把游戏自带的血量 / 杀气条保持固定长度，
-- 并在其上绘制“当前 / 上限”。条会随上限增长；长度就是游戏自带
-- 进度条控件上的宽度参数，所以本模块把该参数改回蓝图出厂时的取值。
-- 数字是独立的开关，可以位于条的上方 / 下方，
-- 或画在条的内部。

local Config = require('PBZArcsConfig')

local HudBars = {}
HudBars.__index = HudBars

local CLASS = {
  text = '/Script/UMG.TextBlock',
}

local BAR_CLASS = 'WB_PlayerHPBar_V1_C'
local BAR_PACKAGE = '/Game/PBZContent/UI/FrontEnd/WB_PlayerHPBar_V1.WB_PlayerHPBar_V1_C'
local HOOK_PATH = BAR_PACKAGE .. ':Construct'

local SCAN_INTERVAL = 0.5
local WARN_INTERVAL = 5
local NUM_FONT = 13
local NUM_CHAR_W = 10
local NUM_MIN_W = 24
local ROW_OFFSET = 13        -- 像素，属于条自身的空间，从条中心到它的数字
local ROW_DOWN = 7           -- 这一对数字位于控件中心下方，夹在两条之间
-- 每个条的上边缘在控件中的位置，从控件中心量起。条内数字的居中方式
-- 是再加上条带绘制高度的一半。
local BAR_TOP_Y = { hp = -2, qi = 15 }
-- 条内样式绘制的是小号白字；游戏里的条很细，所以字号是固定值，
-- 而不是从条带高度推算。
local CENTER_FONT = 8
-- 两种数字样式都带黑色描边；浅色血量条上的白字最需要它，
-- 侧边数字在游戏画面上也因此获得更好的对比度。
local OUTLINE_SIZE = 1
local WHITE = '#FFFFFF'
local MIN_BAR_LEN = 48       -- 比这更短就不算一条
local WATCH_INTERVAL = 2     -- 进度条取值采样之间的秒数
-- 进度条自身的宽度参数（BarX），单位是游戏的 UI 单位。新存档从这些长度
-- 起步；只有在蓝图的取值读不到时才用它们。
local BAR_X_BY_CLASS = {
  PBZAnimProgressBar1_C = 269.08,
  PBZAnimProgressBar2_C = 213.77,
}
local BAR_X_TOLERANCE = 1
-- 存档开始时条覆盖背景的比例，即游戏在新存档上设定的值；只有蓝图和条控件
-- 都答不出来时才用它。
local SHOW_UP_BY_CLASS = {
  PBZAnimProgressBar1_C = 0.200,
  PBZAnimProgressBar2_C = 0.160,
}
local SHOW_UP_TOLERANCE = 0.002

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

local function objectName(object)
  if not valid(object) then return '?' end
  -- 这个版本里访问不到 GetName()；完整名的结尾就是同一个名字。
  local name = fullName(object):match('([^%.:]+)$')
  if name and name ~= '' then return name end
  return '?'
end

-- FVector2D 返回的形式有两种：带 X/Y 的 Lua 表，或一个结构体句柄。
local function pair(value)
  if value == nil then return nil end
  local x = value.X or value.x or value[1]
  local y = value.Y or value.y or value[2]
  if type(x) ~= 'number' then
    local okX, inner = pcall(function() return value.X end)
    if okX then x = inner end
    local okY, innerY = pcall(function() return value.Y end)
    if okY then y = innerY end
  end
  if type(x) ~= 'number' then return nil end
  return x, y
end

local function clamp(value, lo, hi)
  if value < lo then return lo end
  if value > hi then return hi end
  return value
end

local function near(value, want, tolerance)
  return value ~= nil and math.abs(value - want) <= tolerance
end

local function numberText(value)
  if type(value) ~= 'number' then return nil end
  return string.format('%d', math.floor(value + 0.5))
end

local function fmt3(value)
  if type(value) ~= 'number' then return '-' end
  return string.format('%.3f', value)
end

---------------------------------------------------------------------------------------------------
-- 控件测量。这里会依次尝试多个 getter，因为这个引擎版本并未暴露同一套
-- 接口；哪个生效了会记录一次日志，方便核对。

-- 控件被分配的布局尺寸。DesiredSize 是应用笔刷与渲染缩放之前的布局盒
-- （这里是 32 x 32）；缓存的几何只能作为兜底，因为它可能已经把渲染缩放
-- 烘进去了。
local function measuredSize(widget)
  local ok, size = pcall(function() return widget:GetDesiredSize() end)
  if ok then
    local w, h = pair(size)
    if w and w > 0 then return w, h, 'GetDesiredSize' end
  end
  local w, h = pair(prop(widget, 'DesiredSize'))
  if w and w > 0 then return w, h, 'DesiredSize' end
  local okGeo, geometry = pcall(function() return widget:GetCachedGeometry() end)
  if okGeo and geometry then
    local okLocal, localSize = pcall(function() return geometry:GetLocalSize() end)
    if okLocal then
      w, h = pair(localSize)
      if w and w > 0 then return w, h, 'geometry' end
    end
  end
  return nil, nil, nil
end

-- slot 知道自己被分配的尺寸，而真正驱动条的就是这个数字。
local function slotSize(widget)
  local slot = prop(widget, 'Slot')
  if not valid(slot) then return nil, nil, nil end
  local ok, size = pcall(function() return slot:GetSize() end)
  if ok then
    local w, h = pair(size)
    if w and w > 0 then return w, h, 'slot' end
  end
  local layout = prop(slot, 'LayoutData')
  if layout ~= nil then
    local w, h = pair(prop(layout, 'Size'))
    if w and w > 0 then return w, h, 'layout' end
  end
  local w, h = pair(prop(slot, 'Size'))
  if w and w > 0 then return w, h, 'slotSize' end
  return nil, nil, nil
end

-- 控件实际被绘制时的尺寸（含渲染变换），以及它在屏幕上的绘制位置。
-- 纯粹用于诊断：不参与任何判断。
local function paintedSize(widget)
  local ok, geometry = pcall(function() return widget:GetCachedGeometry() end)
  local method = 'cached'
  if not ok or not geometry then
    ok, geometry = pcall(function() return widget:GetTickSpaceGeometry() end)
    method = 'tick'
  end
  if not ok or not geometry then return nil end
  local okSize, size = pcall(function() return geometry:GetLocalSize() end)
  if not okSize then return nil end
  local w, h = pair(size)
  if not w or w <= 0 then return nil end
  local x, y = nil, nil
  local okPos, position = pcall(function() return geometry:GetAbsolutePosition() end)
  if okPos and position then x, y = pair(position) end
  return w, h, method, x, y
end

-- TArray 的元素可能被包在句柄里；get() 负责解开这些包装。
local function unwrap(value)
  local ok, inner = pcall(function() return value:get() end)
  if ok and inner ~= nil then return inner end
  return value
end

-- 一张 Image 用什么来绘制：UE5 把纹理或材质放在 ResourceObject 里，旧属性名
-- 也仍然会试，因为这个版本两种都可能暴露。
local function brushOf(widget)
  local brush = prop(widget, 'Brush')
  if brush == nil then return nil, nil end
  local resource = prop(brush, 'ResourceObject')
  if not valid(resource) then resource = prop(brush, 'Resource') end
  if valid(resource) then return brush, resource end
  return brush, nil
end

local function numProp(object, name)
  if object == nil then return nil end
  local value = prop(object, name)
  if type(value) == 'number' then return value end
  if value ~= nil then
    local inner = unwrap(value)
    if type(inner) == 'number' then return inner end
  end
  return nil
end

-- 材质实例把它的标量列成结构体；这个版本只能从它们里面读到值，参数自己的
-- 描述必须另外去问。
local function scalarList(resource)
  local list = prop(resource, 'ScalarParameterValues')
  if list == nil then return nil, 0 end
  local count = 0
  pcall(function() count = #list end)
  if type(count) ~= 'number' or count <= 0 then return nil, 0 end
  return list, count
end

local function scalarAt(list, index)
  local item, value = nil, nil
  pcall(function() item = list[index] end)
  if item ~= nil then pcall(function() value = item.ParameterValue end) end
  if type(value) ~= 'number' then value = nil end
  return item, value
end

local function fnameText(value)
  if value == nil then return nil end
  if type(value) == 'string' then return value ~= '' and value or nil end
  local text = nil
  pcall(function() text = value:ToString() end)
  if type(text) ~= 'string' then pcall(function() text = value:GetFName():ToString() end) end
  if type(text) ~= 'string' or text == '' then return nil end
  return text
end

-- 一张 Image 绘制它自身四边形多大比例。对条的图来说，这个比例就是填充比，
-- 以标量形式存在笔刷的材质上；纯纹理则绘制全部。
local function drawnFraction(node)
  local _, resource = brushOf(node)
  if not valid(resource) then return 1 end
  if not className(resource):find('MaterialInstance', 1, true) then return 1 end
  local list, count = scalarList(resource)
  if list == nil then return 1 end
  local best, partial = nil, false
  for i = 1, count do
    local _, value = scalarAt(list, i)
    if value and value >= 0 and value < 0.999 then
      partial = true
      if best == nil or value > best then best = value end
    end
  end
  if not partial then return 1 end
  return best or 0
end

local function childrenOf(panel)
  local kids = {}
  local ok, list = pcall(function() return panel:GetChildren() end)
  if ok and type(list) == 'table' then
    for i = 1, #list do
      local child = unwrap(list[i])
      if valid(child) then kids[#kids + 1] = child end
    end
    if #kids > 0 then return kids end
  end
  local slots = prop(panel, 'Slots')
  if slots ~= nil then
    local okLen, len = pcall(function() return #slots end)
    if okLen and type(len) == 'number' then
      for i = 1, len do
        local slot = unwrap(slots[i])
        local child = valid(slot) and prop(slot, 'Content') or nil
        if valid(child) then kids[#kids + 1] = child end
      end
    end
  end
  return kids
end

-- 条的根控件只有 32 px 宽，所以给它屏幕尺寸的东西在它更上层。先试 GetParent，
-- 再试 slot 的持有者；GetOuter 是最后手段（它除了控件还会返回 widget tree，
-- 用于 dump 没问题）。
local function parentOf(widget)
  local ok, parent = pcall(function() return widget:GetParent() end)
  if ok and valid(parent) then return parent end
  local slot = prop(widget, 'Slot')
  if valid(slot) then
    local owner = prop(slot, 'Parent')
    if valid(owner) then return owner end
  end
  local okOuter, outer = pcall(function() return widget:GetOuter() end)
  if okOuter and valid(outer) then return outer end
  return nil
end

-- 根之下的每个控件及其父级，这样条的绘制可以按它是什么来找，
-- 而不是按这个版本读不到的名字来找。
local function indexTree(root)
  local nodes = {}
  local function visit(node, parent, depth)
    if #nodes >= 300 then return end
    nodes[#nodes + 1] = { node = node, parent = parent, depth = depth }
    if depth < 8 then
      local kids = childrenOf(node)
      for i = 1, #kids do visit(kids[i], node, depth + 1) end
    end
  end
  if valid(root) then pcall(visit, root, nil, 0) end
  return nodes
end

-- 控件渲染变换的缩放与轴心。UMG 把轴心单独放在 RenderTransformPivot 里，
-- 与变换分开，而未设置的轴心就是控件的左上角。
local function transformOf(widget)
  local sx, sy, px = 1, 1, 0
  pcall(function()
    local transform = widget.RenderTransform
    if transform == nil then return end
    local scale = transform.Scale
    local x = scale and (scale.X or scale.x)
    local y = scale and (scale.Y or scale.y)
    if type(x) == 'number' and x ~= 0 then sx = math.abs(x) end
    if type(y) == 'number' and y ~= 0 then sy = math.abs(y) end
    local pivot = widget.RenderTransformPivot
    local pivotX = pivot and (pivot.X or pivot.x)
    if type(pivotX) == 'number' then px = pivotX end
  end)
  return sx, sy, px
end

-- 控件的渲染变换把它平移到了哪里（填充可能被平移而不是被改尺寸）。
local function translationOf(widget)
  local x, y = nil, nil
  pcall(function()
    local transform = widget.RenderTransform
    if transform == nil then return end
    local moved = transform.Translation
    if moved == nil then return end
    x = moved.X or moved.x
    y = moved.Y or moved.y
  end)
  return x, y
end

local function brushSize(image)
  local brush = prop(image, 'Brush')
  if brush == nil then return nil, nil end
  local size = prop(brush, 'ImageSize')
  if size == nil then return nil, nil end
  local w, h = pair(size)
  if type(w) ~= 'number' then w = numProp(size, 'X') end
  if type(h) ~= 'number' then h = numProp(size, 'Y') end
  return w, h
end

-- 条的图就是按渲染缩放拉伸的笔刷：它绘制的长度等于布局宽度乘 X 缩放，
-- 而材质只画出其中的比例。它从轴心开始增长，所以轴心右侧的部分
-- 保持其偏移，其余部分被缩放：
-- 即 right = length * (1 - pivot) + pivot * width。
local function imageLength(node)
  local sx, sy, px = transformOf(node)
  local w, h, how = measuredSize(node)
  local bw, bh = brushSize(node)
  local baseW = (w and w > 0) and w or bw
  if not baseW or baseW <= 0 then return nil end
  local baseH = (h and h > 0) and h or bh or baseW
  local length = baseW * sx * drawnFraction(node)
  if length < MIN_BAR_LEN then return nil end
  local right = length * (1 - px) + px * baseW
  return length, right, baseH * sy, sx, baseW, px, how or 'brush'
end

-- 最长的 Image 就是条。它的长度和右边缘位于条的根布局所用的空间里，
-- 数字也放在同一个空间。
local function barGeometry(root)
  local best, thickest = nil, 0
  for _, item in ipairs(indexTree(root)) do
    local node = item.node
    if valid(node) and className(node):find('Image', 1, true) then
      local length, right, thickness, sx, baseW, px, how = imageLength(node)
      if length then
        if thickness and thickness > thickest then thickest = thickness end
        if best == nil or length > best.len then
          best = { len = length, right = right, scaleX = sx, imageW = baseW,
                   pivot = px, via = how, name = objectName(node) }
        end
      end
    end
  end
  if best then
    best.thickness = thickest
    best.left = best.right - best.len
  end
  return best
end

local function scaleYOf(widget)
  local y = nil
  pcall(function()
    local transform = widget.RenderTransform
    if transform ~= nil then
      local scale = transform.Scale
      local value = scale and (scale.Y or scale.y or scale[2])
      if type(value) == 'number' and value > 0 then y = value end
    end
  end)
  return y or 1
end

-- 当前生效的 X 缩放；读不到变换时返回 nil。
local function scaleXOf(widget)
  local x = nil
  pcall(function()
    local transform = widget.RenderTransform
    if transform ~= nil then
      local scale = transform.Scale
      local value = scale and (scale.X or scale.x or scale[1])
      if type(value) == 'number' and value > 0 then x = value end
    end
  end)
  return x
end

---------------------------------------------------------------------------------------------------
-- 条的根控件查找

local function rootOf(inst)
  local root = prop(inst, 'RootWidget')
  if valid(root) then return root end
  local tree = prop(inst, 'WidgetTree')
  if valid(tree) then
    root = prop(tree, 'RootWidget')
    if valid(root) then return root end
  end
  return nil
end

local function liveBars()
  local found = {}
  local ok, list = pcall(function() return FindAllOf(BAR_CLASS) end)
  if not ok or type(list) ~= 'table' then return found end
  for i = 1, #list do
    local inst = list[i]
    if valid(inst) then
      local full = fullName(inst)
      if full:find('Transient', 1, true) then
        local root = rootOf(inst)
        if valid(root) then
          found[#found + 1] = { inst = inst, root = root, name = full }
        end
      end
    end
  end
  return found
end

---------------------------------------------------------------------------------------------------
-- 画在条上的数字

local seq = 0

local function newText(tree, root, name)
  seq = seq + 1
  local created, text = pcall(function()
    return StaticConstructObject(cls(CLASS.text), tree, FName('PBZArcs_HudNum_' .. name .. '_' .. seq))
  end)
  if not created or not valid(text) then return nil end
  pcall(function() text.Font.Size = NUM_FONT end)
  pcall(function() text.Justification = 0 end)
  pcall(function() text:SetShadowOffset({ X = 1, Y = 1 }) end)
  pcall(function() text:SetShadowColorAndOpacity({ R = 0, G = 0, B = 0, A = 0.9 }) end)
  pcall(function() text:SetRenderTransformPivot({ X = 0, Y = 0.5 }) end)
  local slot = nil
  pcall(function() slot = root:AddChildToOverlay(text) end)
  if not valid(slot) then
    pcall(function() slot = root:AddChild(text) end)
  end
  if not valid(slot) then
    pcall(function() text:RemoveFromParent() end)
    return nil
  end
  -- Overlay 的 slot 认这两个对齐字段；canvas 的 slot 则接受一个位置。
  local isCanvas = className(slot):find('CanvasPanelSlot', 1, true) ~= nil
  if not isCanvas then
    pcall(function() slot.HorizontalAlignment = 1 end)  -- 左
    pcall(function() slot.VerticalAlignment = 2 end)    -- 居中
  end
  pcall(function() slot:SetZOrder(60) end)
  return { widget = text, slot = slot, canvas = isCanvas, value = nil, x = nil, y = nil, scale = nil }
end

-- localX 属于条根控件自身的空间，也就是条的图像被绘制的那个空间。
local function placeNumber(entry, localX, offsetY, boxW)
  local text = entry.widget
  local offsetX = localX
  local moved = entry.x ~= offsetX or entry.y ~= offsetY
  local resized = entry.boxW ~= boxW
  if not moved and not resized then return end
  entry.x, entry.y, entry.boxW = offsetX, offsetY, boxW
  if entry.canvas then
    pcall(function() entry.slot:SetPosition({ X = offsetX, Y = offsetY }) end)
    pcall(function() entry.slot:SetSize({ X = boxW, Y = NUM_FONT + 6 }) end)
  else
    pcall(function() text:SetRenderTranslation({ X = offsetX, Y = offsetY }) end)
  end
end

local function showNumber(entry, text, colour)
  if text == nil then
    if entry.shown ~= false then
      entry.shown = false
      pcall(function() entry.widget:SetVisibility(1) end)
    end
    return
  end
  if entry.value ~= text then
    entry.value = text
    pcall(function() entry.widget:SetText(FText(text)) end)
    pcall(function()
      entry.widget:SetColorAndOpacity({ SpecifiedColor = colour, ColorUseRule = 0 })
    end)
  end
  if entry.shown ~= true then
    entry.shown = true
    pcall(function() entry.widget:SetVisibility(4) end)
  end
end

---------------------------------------------------------------------------------------------------
-- 模块

function HudBars.new(settings, log)
  local write = log or function() end
  return setmetatable({
    S = settings,
    -- alert 任何时候都写，log 只在 Debug 打开时写。
    alert = write,
    log = function(message) if settings.Debug then write(message) end end,
    clock = 0,
    entries = {},
    nextScan = 0,
    hooked = false,
    lastWarn = -100,
  }, HudBars)
end

function HudBars:warn(now, message)
  if now - self.lastWarn < WARN_INTERVAL then return end
  self.lastWarn = now
  self.alert('hud bars: ' .. tostring(message))
end

-- 玩家的上限变化时游戏会重建这个控件，加在它上面的东西会全部丢失；
-- 钩子就在重建之后立刻重新施加。
function HudBars:hook()
  if self.hooked then return end
  self.hooked = true
  if type(RegisterHook) ~= 'function' then
    self.log('hud bars: RegisterHook unavailable, polling only')
    return
  end
  local ok, err = pcall(function()
    RegisterHook(HOOK_PATH, function()
      self.nextScan = 0
    end)
  end)
  if not ok then
    self.alert('hud bars: hook failed: ' .. tostring(err))
  end
end

function HudBars:release()
  for _, entry in ipairs(self.entries) do
    -- 条的长度和它填充底板的比例都被改写过，所以要在恢复底图之前先还原它们；
    -- 否则游戏自带的 HUD 会一直停在钉住的状态，而且再次打开钉住时也没有
    -- 已经增长过的值可以拿来作为测量基准。
    pcall(function() self:restoreBars(entry) end)
    for _, num in ipairs(entry.numbers or {}) do
      pcall(function() num.widget:RemoveFromParent() end)
    end
    -- 底图的长度是写进它们材质里的，所以必须还原。
    self:restoreBackdrops(entry)
  end
  self.entries = {}
  self.lastCount = nil
  -- 下次打开开关时重新读取。
  self.initialX, self.initialShow, self.overrideLogged = nil, nil, nil
end

-- 关掉数字只需移除它们的控件；条的条目保留，因为钉住可能还开着。
-- 钉住的另一个方向在 applyEntry 里交还。
function HudBars:dropNumbers(entry)
  if #(entry.numbers or {}) == 0 then return end
  for _, number in ipairs(entry.numbers) do
    pcall(function() number.widget:RemoveFromParent() end)
  end
  entry.numbers, entry.numbersTriedAt = {}, nil
end

function HudBars:scan()
  local found = liveBars()
  local kept = {}
  local byName = {}
  for _, entry in ipairs(self.entries) do byName[entry.name] = entry end
  for _, item in ipairs(found) do
    local entry = byName[item.name]
    if entry == nil then entry = { name = item.name, numbers = {} } end
    -- 被重建的控件会把它的 overlay 子控件一起带走。同一根 = 同一批数字；
    -- 这里比较的是名字而不是对象本身，因为对象本身每次访问都会变。
    local rootName = fullName(item.root)
    if entry.rootName ~= nil and entry.rootName ~= rootName then
      for _, number in ipairs(entry.numbers or {}) do
        pcall(function() number.widget:RemoveFromParent() end)
      end
      entry.numbers, entry.numbersTriedAt = {}, nil
      -- 被重建的控件会带来新的进度条和新的底图。
      entry.progress = nil
      entry.backdropPins = nil
      entry.stripH = nil
    end
    entry.rootName = rootName
    entry.inst, entry.root = item.inst, item.root
    kept[#kept + 1] = entry
  end
  -- 丢掉随控件一起消失的那些条上的数字。
  for _, entry in ipairs(self.entries) do
    local alive = false
    for _, item in ipairs(kept) do
      if item == entry then alive = true break end
    end
    if not alive then
      for _, num in ipairs(entry.numbers or {}) do
        pcall(function() num.widget:RemoveFromParent() end)
      end
    end
  end
  self.entries = kept
  if #kept ~= self.lastCount then
    self.lastCount = #kept
    self.log('hud bars: ' .. #kept .. ' bar widget(s)')
  end
end

function HudBars:ensureNumbers(entry, now)
  -- 游戏重建过的控件会把子控件一起带走，所以先丢掉已死的，只创建缺失的
  -- 读数。失败的尝试不会比扫描更快地重试。
  local kept = {}
  for _, number in ipairs(entry.numbers or {}) do
    if valid(number.widget) then kept[#kept + 1] = number end
  end
  entry.numbers = kept
  local have = {}
  for _, number in ipairs(kept) do have[number.key] = true end
  if have.hp and have.qi then return end
  if entry.numbersTriedAt and now - entry.numbersTriedAt < SCAN_INTERVAL then return end
  entry.numbersTriedAt = now
  local tree = prop(entry.inst, 'WidgetTree')
  if not valid(tree) then return end
  local made = 0
  for _, item in ipairs({ { key = 'hp', colour = Config.hexToLinear(self.S.HpColor) },
                           { key = 'qi', colour = Config.hexToLinear(self.S.QiColor) } }) do
    if not have[item.key] then
      local number = newText(tree, entry.root, entry.name:gsub('[^%w]', '_') .. '_' .. item.key)
      if number then
        number.key = item.key
        number.colour = item.colour
        kept[#kept + 1] = number
        made = made + 1
      end
    end
  end
  if made > 0 then
    self.log('hud bars: numbers attached (' .. #kept .. ')')
  else
    self:warn(now, 'cannot add numbers to the bar widget')
  end
end

function HudBars:applyEntry(entry, now)
  local root = entry.root
  if not valid(root) then return end
  local geo = barGeometry(root)
  if geo == nil then
    self:warn(now, 'no bar image found in the widget')
    return
  end
  entry.geometry = geo
  -- 每当条的长度真的发生变化就记一次日志，这样不开 Debug 也能在日志里
  -- 看到一次增长。
  if self.loggedLen == nil or math.abs(geo.len - self.loggedLen) > math.max(2, self.loggedLen * 0.02) then
    if (self.lenLogAt or 0) + WARN_INTERVAL <= now then
      self.lenLogAt, self.loggedLen = now, geo.len
      self.log(string.format('hud bars: bar is %.0f long (image %s, %.1f x %.0f)',
        geo.len, geo.name, geo.scaleX, geo.imageW))
    end
  end
  -- 控件结构探针只在 Debug 打开时跑一次，平时不往日志里写这些 dump。
  if self.S.Debug and not self.probed then
    self.probed = true
    self:probe(entry, geo)
  end
  -- watch 日志是调试辅助：采样它每帧每条都要拼一个字符串，所以只在
  -- 打开 Debug 时才运行。
  if self.S.Debug then self:watchEntry(entry, now) end
  if self.S.PinHudBars then
    entry.pinned = true
    self:pinLength(entry, now)
    self:pinShowUp(entry, now)
    self:pinBackdrops(entry, now)
  elseif entry.pinned then
    -- 数字还开着的时候钉住被关掉了：把条交还一次。
    pcall(function() self:restoreBars(entry) end)
    self:restoreBackdrops(entry)
    entry.backdropPins = nil
    entry.pinned = false
    self.log('hud bars: pin off, bars handed back')
  end
  if self.S.HudNumbers then
    self:ensureNumbers(entry, now)
  else
    self:dropNumbers(entry)
  end
end

---------------------------------------------------------------------------------------------------
-- 游戏自己给条的长度。WidgetBlueprint 把作者编辑的控件树
-- 保存在生成的类上（以及它的类默认对象上），
-- 不受游戏运行时后来喂给它的值影响，
-- 所以那棵树里保存的是初始长度。

function HudBars:classDefaults()
  if valid(self.cdo) then return self.cdo end
  local class = StaticFindObject(BAR_PACKAGE)
  if not valid(class) then return nil end
  local cdo = nil
  pcall(function() cdo = class:GetDefaultObject() end)
  if not valid(cdo) then
    cdo = StaticFindObject('/Game/PBZContent/UI/FrontEnd/WB_PlayerHPBar_V1.Default__WB_PlayerHPBar_V1_C')
  end
  if not valid(cdo) then return nil end
  self.cdo = cdo
  return cdo
end

-- 作者编辑的几棵树，最权威的在前：生成的类，然后是它的 CDO。
function HudBars:authoredRoots()
  local out = {}
  local class = StaticFindObject(BAR_PACKAGE)
  if valid(class) then
    local tree = prop(class, 'WidgetTree')
    local root = valid(tree) and prop(tree, 'RootWidget') or nil
    if valid(root) then out[#out + 1] = { label = 'class', root = root } end
  end
  local cdo = self:classDefaults()
  if valid(cdo) then
    local tree = prop(cdo, 'WidgetTree')
    local root = valid(tree) and prop(tree, 'RootWidget') or nil
    if valid(root) then out[#out + 1] = { label = 'default', root = root } end
  end
  return out
end

-- 进度条是由什么绘制的：它自己的控件树，而条根看不到这棵树。
local function innerNodesOf(node)
  local out = {}
  local tree = prop(node, 'WidgetTree')
  local root = valid(tree) and prop(tree, 'RootWidget') or nil
  if valid(root) then
    for _, item in ipairs(indexTree(root)) do
      if item.depth > 0 then out[#out + 1] = item.node end
    end
  end
  return out
end

-- 活着的条控件内部的那些进度条；长度在它们身上，而不在图像上
-- （图像在任何存档里都保持蓝图里的缩放）。
function HudBars:progressNodes(entry)
  if entry.progress == nil then
    entry.progress = {}
    for _, item in ipairs(indexTree(entry.root)) do
      local class = className(item.node)
      if class:find('Progress', 1, true) then
        entry.progress[#entry.progress + 1] = { node = item.node, class = class }
      end
    end
  end
  return entry.progress
end

-- 蓝图沿着条滑动的那顶小盖子。它是一个普通 Image，只查找一次，
-- 因为条的重建会带来一个新的。
local function littleBarOf(item)
  if valid(item.cap) then return item.cap end
  item.cap = nil
  for _, node in ipairs(innerNodesOf(item.node)) do
    if objectName(node) == 'LittleBar' and className(node):find('Image', 1, true) then
      item.cap = node
      return node
    end
  end
  return nil
end

-- 快照里的哪个字段喂给每个进度条。
local VALUE_BY_CLASS = {
  PBZAnimProgressBar1_C = 'hp',
  PBZAnimProgressBar2_C = 'qi',
}

local function barValue(snapshot, class)
  local key = VALUE_BY_CLASS[class]
  if key == nil or snapshot == nil then return nil, nil end
  local value, max = snapshot[key], snapshot[key .. 'Max']
  if type(value) ~= 'number' or type(max) ~= 'number' or max <= 0 then return nil, nil end
  return value, max
end

-- 一条覆盖的跨度，单位和条的几何相同：游戏给这条在底板上的覆盖比例，
-- 乘以底板自身四边形的全长。两条长度不同，所以每个数字居中在各自的条上。
function HudBars:barSpan(entry, key)
  local geo = entry.geometry
  local base = geo and geo.imageW and geo.scaleX and geo.imageW * geo.scaleX
  if not base or base <= 0 then return nil end
  for _, item in ipairs(self:progressNodes(entry)) do
    if VALUE_BY_CLASS[item.class] == key then
      local show = numProp(item.node, 'CachedShowUp')
      if show and show > 0 and show <= 1 then return show * base end
      break
    end
  end
  return nil
end

-- 每条绘制在其上的条带。它的顶部是 BAR_TOP_Y；这里给出条带被绘制的
-- 高度，按控件树缓存，这样数字可以居中在条带上，而不是居中在其顶部。
local STRIP_BY_KEY = { hp = 'Image_HpBG', qi = 'Image_ShaChiBarBG' }

local function imageHeight(node)
  local _, sy = transformOf(node)
  local _, h = measuredSize(node)
  local _, bh = brushSize(node)
  local base = (h and h > 0) and h or bh
  if not base then return nil end
  return base * (sy or 1)
end

function HudBars:stripDrawnHeight(entry, key)
  entry.stripH = entry.stripH or {}
  local cached = entry.stripH[key]
  if cached ~= nil then return cached end
  local want = STRIP_BY_KEY[key]
  if want == nil or not valid(entry.root) then return nil end
  for _, item in ipairs(indexTree(entry.root)) do
    if objectName(item.node) == want then
      local height = imageHeight(item.node)
      if height and height > 0 then
        entry.stripH[key] = height
        return height
      end
    end
  end
  return nil
end

-- 新存档起步的长度，从蓝图自己的控件树读取；测量值只是那棵树读不到时
-- 的兜底。
function HudBars:initialBarX(class)
  self.initialX = self.initialX or {}
  local cached = self.initialX[class]
  if cached ~= nil then return cached end
  local value, from = nil, nil
  for _, source in ipairs(self:authoredRoots()) do
    for _, item in ipairs(indexTree(source.root)) do
      if className(item.node) == class then
        local x = numProp(item.node, 'BarX')
        if x and x >= MIN_BAR_LEN then
          value, from = x, source.label
          break
        end
      end
    end
    if value then break end
  end
  if value == nil then
    value, from = BAR_X_BY_CLASS[class], 'measured'
  end
  if value == nil then return nil end
  self.initialX[class] = value
  self.log(string.format('hud bars: initial length for %s is %.1f (%s)', class, value, from))
  return value
end

-- HudBarWidth 用一个长度覆盖两条；否则每条保持自己的长度。
function HudBars:targetBarX(class)
  local fixed = tonumber(self.S.HudBarWidth) or -1
  if fixed >= MIN_BAR_LEN then
    if not self.overrideLogged then
      self.overrideLogged = true
      self.log(string.format('hud bars: fixed length %d from settings', fixed))
    end
    return fixed
  end
  return self:initialBarX(class)
end

-- 条开始时覆盖背景的填充比例。优先用蓝图自己的取值；条控件也把同一个
-- 比例作为一个常量带着。
function HudBars:initialShowUp(class)
  self.initialShow = self.initialShow or {}
  local cached = self.initialShow[class]
  if cached ~= nil then return cached end
  local value, from = nil, nil
  -- 条控件把起始比例作为一个常量带着，不受存档影响。
  local field = (class == 'PBZAnimProgressBar2_C') and 'ShachiBarRatio' or 'HPBarInitRatio'
  for _, entry in ipairs(self.entries) do
    local x = prop(entry.inst, field)
    if type(x) == 'number' and x > 0 and x < 1 then value, from = x, field break end
  end
  if value == nil then
    for _, source in ipairs(self:authoredRoots()) do
      for _, item in ipairs(indexTree(source.root)) do
        if className(item.node) == class then
          local x = numProp(item.node, 'CachedShowUp')
          if x and x > 0 and x < 1 then value, from = x, source.label break end
        end
      end
      if value then break end
    end
  end
  if value == nil then value, from = SHOW_UP_BY_CLASS[class], 'measured' end
  if value == nil then return nil end
  self.initialShow[class] = value
  self.log(string.format('hud bars: initial fill ratio for %s is %.4f (%s)', class, value, from))
  return value
end

-- HudBarWidth 用的是条自身的单位，所以要通过同一个类的配对值来换算。
function HudBars:targetShowUp(class)
  local initial = self:initialShowUp(class)
  if initial == nil then return nil end
  local fixed = tonumber(self.S.HudBarWidth) or -1
  if fixed >= MIN_BAR_LEN then
    local base = self:initialBarX(class)
    if base and base > 0 then return initial * fixed / base end
  end
  return initial
end

-- 游戏画在条后面的那些图像，以及它们各自绘制的条。它们自身的缩放
-- 从不改变；绘制长度是笔刷材质上的一个标量，与条的填充比例之间
-- 是固定偏移：外层底板 +0.010，条带 +0.005，杀气闪光 -0.005。
-- 改写这个标量能让图案变短而不变形，而缩放图像做不到这一点：
-- 底板是用一张图画出两条的。
local BACKDROPS = {
  Image_OverallBG = { bars = { 'PBZAnimProgressBar1_C', 'PBZAnimProgressBar2_C' }, offset = 0.010 },
  Image_HpBG = { bars = { 'PBZAnimProgressBar1_C' }, offset = 0.005 },
  Image_ShaChiBarBG = { bars = { 'PBZAnimProgressBar2_C' }, offset = 0.005 },
  Image_ShaChiBarRedGlow = { bars = { 'PBZAnimProgressBar2_C' }, offset = -0.005 },
}
local SCALAR_TOLERANCE = 0.001
local FNAME_CACHE = {}

local function nameObject(text)
  if type(text) ~= 'string' or text == '' then return nil end
  local cached = FNAME_CACHE[text]
  if cached == nil then
    local ok, made = pcall(function() return FName(text) end)
    if not ok or made == nil then return nil end
    cached = made
    FNAME_CACHE[text] = cached
  end
  return cached
end

-- 标量声明时使用的名字：参数自己的描述是这个版本唯一保存它的地方，
-- 普通的名字字段仍会为旧布局试一下。
local function parameterNameOf(item)
  local info = prop(item, 'ParameterInfo')
  if info ~= nil then
    local text = fnameText(prop(info, 'Name'))
    if text then return text end
  end
  return fnameText(prop(item, 'ParameterName'))
      or fnameText(prop(item, 'ParameterName_DEPRECATED'))
end

-- 设置材质实例的一个标量。这些 setter 接受 FName；在这里传普通
-- Lua 字符串会让 UE4SS 崩掉，所以名字总是被包成 FName。读不到名字时，
-- 改用参数自己的描述来携带它。只有读回来的值才算数：
-- 调用返回了但值没变就是失败。
local function setScalar(resource, list, index, item, want, name)
  local lastError = nil
  if name == nil and item ~= nil then name = parameterNameOf(item) end
  if name then
    local fname = nameObject(name)
    if fname then
      local ok = pcall(function() resource:SetScalarParameterValue(fname, want) end)
      if not ok then
        local okAlt, errAlt = pcall(function() resource:K2_SetScalarParameterValue(fname, want) end)
        if not okAlt then lastError = tostring(errAlt) end
      end
      local _, after = scalarAt(list, index)
      if after and math.abs(after - want) <= SCALAR_TOLERANCE then return 'name', name end
    else
      lastError = 'no FName for ' .. tostring(name)
    end
  end
  if item ~= nil then
    local info = prop(item, 'ParameterInfo')
    if info ~= nil then
      local ok, err = pcall(function() resource:SetScalarParameterValueByInfo(info, want) end)
      if not ok then lastError = tostring(err) end
      local _, after = scalarAt(list, index)
      if after and math.abs(after - want) <= SCALAR_TOLERANCE then return 'info', name end
    elseif lastError == nil then
      lastError = 'no parameter name'
    end
  end
  return nil, name, lastError
end

-- 底图的一个标量属于哪条：增长后的比例加上本层的偏移等于该值的那一条。
-- 底板同时带两条，条带只带一条。
local function matchBackdropScalar(spec, bars, have)
  local match, best = nil, 0.004
  for _, class in ipairs(spec.bars) do
    local bar = bars[class]
    if bar and bar.grown then
      local diff = math.abs(have - (bar.grown + spec.offset))
      if diff < best then match, best = class, diff end
    end
  end
  return match
end

-- CachedShowUp 是条绘制在其上的背景比例，这就是条会随上限增长的原因。
-- 条是从它重绘的，所以把它放回去就够了。
function HudBars:pinShowUp(entry, now)
  for _, item in ipairs(self:progressNodes(entry)) do
    if valid(item.node) then
      local want = self:targetShowUp(item.class)
      local have = numProp(item.node, 'CachedShowUp')
      if want then item.want = want end
      if want and have and math.abs(have - want) > SHOW_UP_TOLERANCE then
        -- 在写入之前记录：底图的各层是按同一个倍数增长的。这里写入的值
        -- 不是增长后的值，所以它永远不会成为参照。
        local own = item.pinnedTo and math.abs(have - item.pinnedTo) <= SHOW_UP_TOLERANCE
        if not own then item.grown = have end
        pcall(function() item.node.CachedShowUp = want end)
        local after = numProp(item.node, 'CachedShowUp')
        if after == nil or math.abs(after - want) > SHOW_UP_TOLERANCE then
          pcall(function() item.node:SetShowUpRatio(want) end)
          after = numProp(item.node, 'CachedShowUp')
        elseif not item.showUpKicked then
          -- 蓝图可能只从它自己的 setter 重绘；在这里推它一次。
          item.showUpKicked = true
          pcall(function() item.node:SetShowUpRatio(want) end)
          after = numProp(item.node, 'CachedShowUp') or after
        end
        item.pinnedTo = want
        if (self.showUpLogAt or 0) + WATCH_INTERVAL <= now then
          self.showUpLogAt = now
          if after and math.abs(after - want) <= SHOW_UP_TOLERANCE then
            self.log(string.format('hud bars: %s fill ratio pinned %.3f -> %.3f',
              objectName(item.node), have, after))
          else
            self.alert(string.format('hud bars: cannot set %s fill ratio (%.3f, want %.3f)',
              objectName(item.node), have, want))
          end
          if self.S.Debug and not item.materialDumped then
            item.materialDumped = true
            self:dumpMaterial('after pin ' .. objectName(item.node),
              prop(item.node, 'MID_Bar'))
          end
        end
      end
    end
  end
end

-- 游戏把这个长度参数抬高时，把它改回条自身的长度。改写参数（而不是缩放
-- 控件）能让条的形状与作者设定完全一致。
function HudBars:pinLength(entry, now)
  for _, item in ipairs(self:progressNodes(entry)) do
    if valid(item.node) then
      local want = self:targetBarX(item.class)
      local have = numProp(item.node, 'BarX')
      if want and have then
        if item.logged == nil then
          item.logged = true
          self.log(string.format('hud bars: %s length %.1f, target %.1f',
            objectName(item.node), have, want))
        end
        if math.abs(have - want) > BAR_X_TOLERANCE then
          -- 在写入之前记录，这样关掉钉住时能把游戏自己的长度放回去。
          -- 与本函数上次写入的值相等的值不算增长后的值。
          local own = item.pinnedXTo and math.abs(have - item.pinnedXTo) <= BAR_X_TOLERANCE
          if not own then item.grownX = have end
          pcall(function() item.node.BarX = want end)
          local after = numProp(item.node, 'BarX')
          if after == nil or math.abs(after - want) > BAR_X_TOLERANCE then
            pcall(function() item.node:SetPropertyValue('BarX', want) end)
            after = numProp(item.node, 'BarX')
          end
          item.pinnedXTo = want
          if (self.pinLogAt or 0) + WATCH_INTERVAL <= now then
            self.pinLogAt = now
            if after and math.abs(after - want) <= BAR_X_TOLERANCE then
              self.log(string.format('hud bars: %s length pinned %.1f -> %.1f',
                objectName(item.node), have, after))
            else
              self.alert(string.format('hud bars: cannot set %s length (%.1f, want %.1f)',
                objectName(item.node), have, want))
            end
          end
        end
      end
    end
  end
end

-- 每条后面的条带也和条一样随上限增长，所以它自己的长度标量
-- 要改回钉住后的条在新存档上会画出的比例。
-- 每个标量按图像和下标记住，因为一旦被钉住，
-- 它就不再与游戏留在材质里的增长比例相匹配。
function HudBars:pinBackdrops(entry, now)
  local bars = {}
  for _, item in ipairs(self:progressNodes(entry)) do bars[item.class] = item end
  entry.backdropPins = entry.backdropPins or {}
  for _, item in ipairs(indexTree(entry.root)) do
    local node = item.node
    local name = objectName(node)
    local spec = BACKDROPS[name]
    if spec and className(node):find('Image', 1, true) then
      local _, resource = brushOf(node)
      if valid(resource) and className(resource):find('MaterialInstance', 1, true) then
        local pins = entry.backdropPins[name]
        if pins == nil then
          pins = { node = node, slots = {} }
          entry.backdropPins[name] = pins
        end
        local list, count = scalarList(resource)
        if list ~= nil then
          for index = 1, count do
            local scalarItem, have = scalarAt(list, index)
            if have then
              local slot = pins.slots[index]
              if slot == nil then
                local class = matchBackdropScalar(spec, bars, have)
                if class then
                  slot = { bar = class, offset = spec.offset, grown = bars[class].grown }
                  pins.slots[index] = slot
                end
              end
              local bar = slot and bars[slot.bar] or nil
              if slot and bar and bar.want then
                if bar.grown then slot.grown = bar.grown end
                local grown = slot.grown + slot.offset
                local want = bar.want + slot.offset
                if math.abs(have - want) > SCALAR_TOLERANCE then
                  local via, byName, err = setScalar(resource, list, index, scalarItem, want, slot.name)
                  if via then
                    slot.name = slot.name or byName
                    if not slot.logged then
                      slot.logged = true
                      self.log(string.format('hud bars: %s scalar %d %.3f -> %.3f for %s (%s%s)',
                        name, index, have, want, slot.bar, via,
                        byName and (' ' .. byName) or ''))
                    end
                  elseif not slot.warned then
                    slot.warned = true
                    self.alert(string.format('hud bars: cannot set %s scalar %d (%.3f, want %.3f, grew from %.3f: %s)',
                      name, index, have, want, grown, tostring(err)))
                  end
                end
              end
            end
          end
        end
      end
    end
  end
end

-- 把底图的标量改回游戏原本放在里面的值，这样关掉钉住时能恢复条原来的
-- 背景。
function HudBars:restoreBackdrops(entry)
  for name, pins in pairs(entry.backdropPins or {}) do
    local node = pins.node
    if valid(node) then
      local _, resource = brushOf(node)
      if valid(resource) and className(resource):find('MaterialInstance', 1, true) then
        local list, count = scalarList(resource)
        if list ~= nil then
          for index, slot in pairs(pins.slots) do
            if index <= count and slot.grown then
              local want = slot.grown + slot.offset
              local scalarItem, have = scalarAt(list, index)
              if have and math.abs(have - want) > SCALAR_TOLERANCE then
                if setScalar(resource, list, index, scalarItem, want, slot.name) then
                  self.log(string.format('hud bars: %s scalar %d restored to %.3f', name, index, want))
                end
              end
            end
          end
        end
      end
    end
  end
end

-- 蓝图把小盖子留在一个很小的偏移上，从不把它收起来，所以空条在起点还会
-- 留一段有颜色的头。值是空的唯一依据，所以这时把它收起来，等条里重新有
-- 东西后再完全按原来的样子恢复。
local CAP_HIDDEN = 1 -- EVisibility 枚举取值 collapsed（收起）
local CAP_SHOWN = 4  -- 盖子没有可读的可见性时的兜底
-- 小盖子跟在填充的边缘之后；接近满值时蓝图把它停到边缘之外，
-- 让它挂在条的末端外面。
local CAP_FULL = 0.99

-- 把游戏自己的值放回条上：它增长到的长度、条绘制在底板上的比例，
-- 以及任何在这里被收起来的小盖子。
function HudBars:restoreBars(entry)
  for _, item in ipairs(self:progressNodes(entry)) do
    if valid(item.node) then
      if item.grownX and not near(numProp(item.node, 'BarX'), item.grownX, BAR_X_TOLERANCE) then
        pcall(function() item.node.BarX = item.grownX end)
        if not near(numProp(item.node, 'BarX'), item.grownX, BAR_X_TOLERANCE) then
          pcall(function() item.node:SetPropertyValue('BarX', item.grownX) end)
        end
        self.log(string.format('hud bars: %s length restored to %.1f', objectName(item.node), item.grownX))
      end
      if item.grown and not near(numProp(item.node, 'CachedShowUp'), item.grown, SHOW_UP_TOLERANCE) then
        pcall(function() item.node:SetShowUpRatio(item.grown) end)
        if not near(numProp(item.node, 'CachedShowUp'), item.grown, SHOW_UP_TOLERANCE) then
          pcall(function() item.node.CachedShowUp = item.grown end)
        end
        self.log(string.format('hud bars: %s fill ratio restored to %.3f', objectName(item.node), item.grown))
      end
      local cap = littleBarOf(item)
      if valid(cap) and item.capHidden then
        pcall(function() cap:SetVisibility(item.capWas or CAP_SHOWN) end)
        item.capHidden = nil
      end
      -- 忘掉在这里记录的增长：条又属于游戏了，下一次钉住必须去测量
      -- 那时游戏已经达到的长度。
      item.grownX, item.pinnedXTo = nil, nil
      item.grown, item.pinnedTo, item.showUpKicked = nil, nil, nil
    end
  end
end

function HudBars:updateLittleBars(entry, snapshot)
  for _, item in ipairs(self:progressNodes(entry)) do
    local value, max = barValue(snapshot, item.class)
    if value and max then
      local node = littleBarOf(item)
      if valid(node) then
        if value < max * CAP_FULL then
          if item.capHidden then
            local was = item.capWas or CAP_SHOWN
            if pcall(function() node:SetVisibility(was) end) then
              item.capHidden = nil
              self.log(string.format('hud bars: %s cap shown again (%d)', objectName(item.node), was))
            end
          end
        else
          -- 满条没有尾随边缘，但蓝图会把小盖子停到填充之外；在那里把它
          -- 收起来并反复重申，让它保持消失。
          local have = numProp(node, 'Visibility')
          if have ~= nil and item.capWas == nil then item.capWas = have end
          if have == nil or have ~= CAP_HIDDEN then
            if pcall(function() node:SetVisibility(CAP_HIDDEN) end) and not item.capHidden then
              item.capHidden = true
              self.log(string.format('hud bars: %s cap hidden (full, %.4f)',
                objectName(item.node), value / max))
            end
          end
        end
      end
    end
  end
end

local function describeNode(node, depth)
  local parts = { string.rep(' ', depth), className(node), objectName(node) }
  local class = className(node)
  local slot = prop(node, 'Slot')
  if valid(slot) then
    parts[#parts + 1] = 'slot=' .. className(slot)
    local w, h, how = slotSize(node)
    if w then parts[#parts + 1] = string.format('size=%.0fx%.0f(%s)', w, h or -1, tostring(how)) end
    local layout = prop(slot, 'LayoutData')
    local offsets = layout ~= nil and prop(layout, 'Offsets') or nil
    if offsets ~= nil then
      parts[#parts + 1] = string.format('offsets=%.0f,%.0f,%.0f,%.0f',
        numProp(offsets, 'Left') or -1, numProp(offsets, 'Top') or -1,
        numProp(offsets, 'Right') or -1, numProp(offsets, 'Bottom') or -1)
    end
  end
  local dw, dh, dp = measuredSize(node)
  if dw then parts[#parts + 1] = string.format('desired=%.0fx%.0f(%s)', dw, dh or -1, tostring(dp)) end
  local pw, ph, pm, px, py = paintedSize(node)
  if pw then
    parts[#parts + 1] = string.format('painted=%.0fx%.0f(%s)', pw, ph or -1, tostring(pm))
    if px then parts[#parts + 1] = string.format('at=%.0f,%.0f', px, py or -1) end
  end
  local sx, sy = scaleXOf(node) or 1, scaleYOf(node)
  if sx ~= 1 or sy ~= 1 then parts[#parts + 1] = string.format('scale=%.2f,%.2f', sx, sy) end
  local _, _, pivotX = transformOf(node)
  if pivotX ~= 0 then parts[#parts + 1] = string.format('pivot=%.2f', pivotX) end
  local tx, ty = translationOf(node)
  if tx and (tx ~= 0 or ty ~= 0) then
    parts[#parts + 1] = string.format('move=%.1f,%.1f', tx, ty or 0)
  end
  if class:find('SizeBox', 1, true) then
    parts[#parts + 1] = string.format('widthOverride=%s on=%s',
      tostring(numProp(node, 'WidthOverride')), tostring(prop(node, 'bOverride_WidthOverride')))
  end
  if class:find('ScaleBox', 1, true) then
    parts[#parts + 1] = string.format('userScale=%s', tostring(numProp(node, 'UserSpecifiedScale')))
  end
  if class:find('Image', 1, true) then
    local brush, resource = brushOf(node)
    if brush ~= nil then
      local size = prop(brush, 'ImageSize')
      parts[#parts + 1] = string.format('imageSize=%sx%s drawAs=%s',
        tostring(numProp(size, 'X')), tostring(numProp(size, 'Y')), tostring(prop(brush, 'DrawAs')))
      if resource ~= nil then
        parts[#parts + 1] = string.format('brush=%s:%s', className(resource), objectName(resource))
      end
    end
  end
  return table.concat(parts, ' ')
end

-- 这个类的函数：如果长度是通过某个蓝图调用施加的，它的名字就在这里。
function HudBars:dumpFunctions(label, object)
  if not valid(object) then return end
  local class = nil
  pcall(function() class = object:GetClass() end)
  if not valid(class) then return end
  local names = {}
  pcall(function()
    class:ForEachFunction(function(first, second)
      local entry = first
      if type(first) == 'string' then entry = second end
      if entry == nil then return end
      local ok, name = pcall(function() return entry:GetFName():ToString() end)
      if ok and type(name) == 'string' and name ~= '' then names[#names + 1] = name end
    end)
  end)
  table.sort(names)
  self.log(string.format('hud bars: %s functions (%d) %s', label, #names, table.concat(names, ' ')))
end

-- 每个属性名，这样条绘制时经由的对象（一个笔刷、一个材质、一个内部
-- Image）即使取值读不到也能被看见。
function HudBars:dumpPropNames(label, object)
  if not valid(object) then return end
  local class = nil
  pcall(function() class = object:GetClass() end)
  if not valid(class) then return end
  local names = {}
  pcall(function()
    class:ForEachProperty(function(first, second)
      local entry = first
      if type(first) == 'string' then entry = second end
      if entry == nil or #names >= 90 then return end
      local ok, name = pcall(function() return entry:GetFName():ToString() end)
      if ok and type(name) == 'string' and name ~= '' then names[#names + 1] = name end
    end)
  end)
  table.sort(names)
  self.log(string.format('hud bars: %s properties (%d) %s', label, #names, table.concat(names, ' ')))
end

-- 材质实例携带的参数：当填充图自身保持固定缩放时，条被绘制的长度
-- 就是其中之一。
function HudBars:dumpMaterial(label, object)
  if not valid(object) then
    self.log('hud bars: ' .. label .. ' material is nil')
    return
  end
  self.log('hud bars: ' .. label .. ' material ' .. fullName(object))
  local listed = 0
  for _, field in ipairs({ 'ScalarParameterValues', 'VectorParameterValues', 'TextureParameterValues' }) do
    local list = prop(object, field)
    if list ~= nil then
      local count = nil
      pcall(function() count = #list end)
      if type(count) == 'number' then
        listed = listed + count
        self.log(string.format('hud bars: %s %s n=%d', label, field, count))
        for i = 1, math.min(count, 24) do
          local item = nil
          pcall(function() item = list[i] end)
          if item ~= nil then
            local text = parameterNameOf(item)
            local value = nil
            pcall(function() value = item.ParameterValue end)
            self.log(string.format('hud bars: %s %s[%d] %s = %s',
              label, field, i, tostring(text), tostring(value)))
          end
        end
      end
    end
  end
  -- 没有覆盖项的实例什么也不显示；父材质仍然会列出它声明过的参数
  -- 及其默认值。
  if listed == 0 then
    local parent = prop(object, 'Parent')
    if valid(parent) then
      self.log('hud bars: ' .. label .. ' parent ' .. fullName(parent))
      for _, field in ipairs({ 'ScalarParameters', 'VectorParameters' }) do
        local list = prop(parent, field)
        if list ~= nil then
          local count = nil
          pcall(function() count = #list end)
          if type(count) == 'number' and count > 0 then
            self.log(string.format('hud bars: %s parent %s n=%d', label, field, count))
            for i = 1, math.min(count, 24) do
              local item = nil
              pcall(function() item = list[i] end)
              if item ~= nil then
                local value = nil
                pcall(function() value = item.ParameterValue end)
                local info = prop(item, 'ParameterInfo')
                local text = nil
                pcall(function() text = info.Name:ToString() end)
                if text == nil then
                  pcall(function() text = prop(item, 'ParameterName') end)
                  if text ~= nil then text = tostring(text) end
                end
                self.log(string.format('hud bars: %s parent %s[%d] %s = %s',
                  label, field, i, tostring(text), tostring(value)))
              end
            end
          end
        end
      end
    end
  end
end

-- 一张 Image 实际用什么来绘制。填充后面那条暗色条带在每次存档里都保持
-- 自己的缩放，所以如果它绘制的长度变了，决定它的就是这个笔刷（纹理或
-- 材质），而由材质驱动的笔刷是唯一能把长度藏起来的地方。
function HudBars:dumpBrush(label, widget)
  local brush, resource = brushOf(widget)
  if brush == nil then
    self.log('hud bars: ' .. label .. ' brush nil')
    return
  end
  local size = prop(brush, 'ImageSize')
  local tint = prop(brush, 'TintColor')
  self.log(string.format('hud bars: %s brush drawAs=%s size=%sx%s tint=%s,%s,%s,%s',
    label, tostring(prop(brush, 'DrawAs')),
    tostring(numProp(size, 'X')), tostring(numProp(size, 'Y')),
    tostring(numProp(tint, 'R')), tostring(numProp(tint, 'G')),
    tostring(numProp(tint, 'B')), tostring(numProp(tint, 'A'))))
  local margin = prop(brush, 'Margin')
  if margin ~= nil then
    self.log(string.format('hud bars: %s brush margin %s,%s,%s,%s', label,
      tostring(numProp(margin, 'Left')), tostring(numProp(margin, 'Top')),
      tostring(numProp(margin, 'Right')), tostring(numProp(margin, 'Bottom'))))
  end
  if resource == nil then
    self.log('hud bars: ' .. label .. ' brush resource nil')
    return
  end
  local class = className(resource)
  self.log(string.format('hud bars: %s brush resource %s %s', label, class, fullName(resource)))
  if class:find('Material', 1, true) then
    self:dumpMaterial(label .. ' brush', resource)
  end
end

-- 树往上到底哪个方向真的走得通；条之上的遍历依赖它。
function HudBars:dumpParent(label, widget)
  local out = {}
  local ok, parent = pcall(function() return widget:GetParent() end)
  out[#out + 1] = 'GetParent=' .. (ok and (valid(parent) and className(parent) or 'nil') or 'error')
  local slot = prop(widget, 'Slot')
  out[#out + 1] = 'Slot=' .. (valid(slot) and className(slot) or 'nil')
  if valid(slot) then
    local owner = prop(slot, 'Parent')
    out[#out + 1] = 'Slot.Parent=' .. (valid(owner) and className(owner) or 'nil')
  end
  local okOuter, outer = pcall(function() return widget:GetOuter() end)
  out[#out + 1] = 'GetOuter=' .. (okOuter and (valid(outer) and fullName(outer) or 'nil') or 'error')
  self.log(string.format('hud bars: %s parent %s', label, table.concat(out, ' ')))
end

function HudBars:dumpTree(label, root)
  local stack = { { node = root, depth = 0 } }
  local seen = 0
  while #stack > 0 and seen < 40 do
    local item = table.remove(stack)
    seen = seen + 1
    self.log('hud bars: ' .. label .. ' ' .. describeNode(item.node, item.depth))
    if item.depth < 4 then
      local kids = childrenOf(item.node)
      for i = #kids, 1, -1 do stack[#stack + 1] = { node = kids[i], depth = item.depth + 1 } end
    end
  end
end

-- 名字看起来像尺寸的浮点数：控件可能带着长度，也可能带着它的基准。
function HudBars:dumpNumbers(label, object)
  if not valid(object) then return end
  local class = nil
  pcall(function() class = object:GetClass() end)
  if not valid(class) then return end
  local names = {}
  pcall(function()
    class:ForEachProperty(function(first, second)
      local entry = first
      if type(first) == 'string' then entry = second end
      if entry == nil then return end
      local ok, name = pcall(function() return entry:GetFName():ToString() end)
      if ok and type(name) == 'string' and name ~= '' then names[#names + 1] = name end
    end)
  end)
  local keys = { 'width', 'length', 'max', 'scale', 'size', 'percent' }
  local line = {}
  for _, name in ipairs(names) do
    local lower = name:lower()
    for _, key in ipairs(keys) do
      if lower:find(key, 1, true) then
        local value = numProp(object, name)
        if value then line[#line + 1] = string.format('%s=%.3f', name, value) end
        break
      end
    end
  end
  if #line > 0 then
    self.log(string.format('hud bars: %s numbers %s', label, table.concat(line, ' ')))
  end
end

-- 每个数值属性，不过滤名字：条的长度可能是个名字毫无提示的变量。
function HudBars:dumpAllNumbers(label, object)
  if not valid(object) then return end
  local class = nil
  pcall(function() class = object:GetClass() end)
  if not valid(class) then return end
  local line = {}
  pcall(function()
    class:ForEachProperty(function(first, second)
      local entry = first
      if type(first) == 'string' then entry = second end
      if entry == nil or #line >= 60 then return end
      local ok, name = pcall(function() return entry:GetFName():ToString() end)
      if not ok or type(name) ~= 'string' or name == '' then return end
      local value = numProp(object, name)
      if value then line[#line + 1] = string.format('%s=%.3f', name, value) end
    end)
  end)
  self.log(string.format('hud bars: %s all numbers [%s]', label, table.concat(line, ' ')))
end

-- 控件在父面板里所处的位置：一个数值长度会在这里表现为偏移、锚点矩形
-- 或 slot 尺寸。
function HudBars:dumpSlot(label, object)
  local slot = prop(object, 'Slot')
  if not valid(slot) then
    self.log('hud bars: ' .. label .. ' has no slot')
    return
  end
  local parts = { className(slot) }
  local okSize, size = pcall(function() return slot:GetSize() end)
  if okSize then
    local w, h = pair(size)
    if w then parts[#parts + 1] = string.format('size=%.0fx%.0f', w, h or -1) end
  end
  local layout = prop(slot, 'LayoutData')
  if layout ~= nil then
    local offsets = prop(layout, 'Offsets')
    if offsets ~= nil then
      parts[#parts + 1] = string.format('offsets=%.0f,%.0f,%.0f,%.0f',
        numProp(offsets, 'Left') or -1, numProp(offsets, 'Top') or -1,
        numProp(offsets, 'Right') or -1, numProp(offsets, 'Bottom') or -1)
    end
    local anchors = prop(layout, 'Anchors')
    if anchors ~= nil then
      local minX, minY = pair(prop(anchors, 'Minimum'))
      local maxX, maxY = pair(prop(anchors, 'Maximum'))
      if minX then
        parts[#parts + 1] = string.format('anchors=%.2f,%.2f-%.2f,%.2f',
          minX, minY or -1, maxX or -1, maxY or -1)
      end
    end
    local alignX, alignY = pair(prop(layout, 'Alignment'))
    if alignX then
      parts[#parts + 1] = string.format('align=%.2f,%.2f', alignX, alignY or -1)
    end
    local padL = numProp(prop(layout, 'Padding'), 'Left')
    if padL then parts[#parts + 1] = string.format('padL=%.0f', padL) end
  end
  local z = numProp(slot, 'ZOrder')
  if z then parts[#parts + 1] = string.format('zorder=%.0f', z) end
  self.log(string.format('hud bars: %s slot %s', label, table.concat(parts, ' ')))
end

-- 进度条带着自己的数值宽度。在整个会话里采样可以看出在钉住之下游戏
-- 会不会重写它，以及游玩时这个长度的行为。
function HudBars:watchEntry(entry, now)
  local parts, innerChanged, changed = {}, {}, false
  for _, item in ipairs(self:progressNodes(entry)) do
    if valid(item.node) then
      local line = string.format('%s BarX=%s Scope=%s CurPercent=%s ShowUp=%s',
        objectName(item.node), fmt3(numProp(item.node, 'BarX')),
        fmt3(numProp(item.node, 'Scope')), fmt3(numProp(item.node, 'CurPercent')),
        fmt3(numProp(item.node, 'CachedShowUp')))
      -- 同一瞬间的玩家数值：可以看出 ShowUp 携带的是当前比例，还是只有
      -- 条的长度，所以任一变化都会被记录。
      local snap = self.snapshot
      local extra = ''
      if snap then
        extra = string.format(' hp=%s/%s qi=%s/%s', tostring(snap.hp), tostring(snap.hpMax),
          tostring(snap.qi), tostring(snap.qiMax))
      end
      if item.last ~= line .. extra then
        item.last, changed = line .. extra, true
      end
      parts[#parts + 1] = line .. extra
      -- 条内部的控件在它绘制的长度变化时会移动或重新缩放；把与上次采样
      -- 不同的那些记下来，就能看出是哪个值在驱动绘制。
      item.inner = item.inner or innerNodesOf(item.node)
      item.innerLines = item.innerLines or {}
      for i, node in ipairs(item.inner) do
        if valid(node) then
          local innerLine = describeNode(node, 0)
          if item.innerLines[i] ~= innerLine then
            item.innerLines[i] = innerLine
            innerChanged[#innerChanged + 1] = innerLine
            changed = true
          end
        end
      end
    end
  end
  if not changed then return end
  if (self.watchAt or 0) + WATCH_INTERVAL > now then return end
  self.watchAt = now
  if #parts > 0 then
    self.log('hud bars: watch ' .. table.concat(parts, ' | '))
  end
  for _, line in ipairs(innerChanged) do
    self.log('hud bars: watch inner ' .. line)
  end
end

-- 每个会话只 dump 一次：活着的条是由什么绘制的，以及游戏自己的控件树
-- 说这条应该是什么样。
-- 一个有问题的对象不能把 dump 的其余部分截短：调用方看不到错误。
function HudBars:probeStep(label, fn)
  local ok, err = pcall(fn)
  if not ok then
    self.log('hud bars: probe step ' .. label .. ' failed: ' .. tostring(err))
  end
end

function HudBars:probe(entry, geo)
  self.log(string.format('hud bars: root %s %s  clip=%s/%s',
    className(entry.root), (fullName(entry.root):gsub('^.*:', '')),
    tostring(prop(entry.root, 'Clipping')), tostring(prop(entry.inst, 'Clipping'))))
  self.log(string.format('hud bars: bar image %s via %s: %.0f x %.0f, right=%.0f left=%.0f pivot=%.2f W=%.0f',
    geo.name, geo.via, geo.len, geo.thickness, geo.right, geo.left, geo.pivot, geo.imageW))
  self:dumpTree('live', entry.root)
  self:dumpNumbers('live', entry.inst)
  self:dumpAllNumbers('bar', entry.inst)
  self:dumpSlot('bar', entry.inst)
  -- 把 32 px 的盒子变成约 330 px 的条的那个东西，就在这个根的上面某处。
  self:dumpParent('root', entry.root)
  self:probeStep('parents', function()
    local up = parentOf(entry.root)
    local level = 0
    while valid(up) and level < 6 do
      level = level + 1
      self.log('hud bars: up ' .. level .. ' ' .. describeNode(up, 0))
      self:dumpSlot('up ' .. level, up)
      up = parentOf(up)
    end
  end)
  -- 自定义的进度条最可能是数值长度所在的地方。
  for _, item in ipairs(self:progressNodes(entry)) do
    local label = 'node ' .. objectName(item.node)
    self:probeStep(label .. ' numbers', function() self:dumpAllNumbers(label, item.node) end)
    self:probeStep(label .. ' slot', function() self:dumpSlot(label, item.node) end)
    self:probeStep(label .. ' properties', function() self:dumpPropNames(label, item.node) end)
    self:probeStep(label .. ' functions', function() self:dumpFunctions(label, item.node) end)
    self:probeStep(label .. ' material', function()
      self:dumpMaterial(label, prop(item.node, 'MID_Bar'))
    end)
    self:probeStep(label .. ' parent', function() self:dumpParent(label, item.node) end)
    -- 填充是由进度条内部的控件绘制的，而不是由条的根控件。
    self:probeStep(label .. ' inner', function()
      local inner = innerNodesOf(item.node)
      self.log(string.format('hud bars: %s inner widgets (%d)', label, #inner))
      for _, node in ipairs(inner) do
        self:probeStep(label .. ' in ' .. objectName(node), function()
          self.log('hud bars: ' .. label .. ' in ' .. describeNode(node, 0))
          self:dumpAllNumbers(label .. ' in ' .. objectName(node), node)
          self:dumpSlot(label .. ' in ' .. objectName(node), node)
        end)
      end
    end)
    self.log(string.format('hud bars: %s BarX=%.1f target=%.1f', item.class,
      numProp(item.node, 'BarX') or -1, self:targetBarX(item.class) or -1))
  end
  -- 条里的每一张 Image，以及它绘制什么：画那条暗色条带的必须能从它的
  -- 笔刷辨认出来，因为它的缩放从不改变。
  self:probeStep('brushes', function()
    for _, item in ipairs(indexTree(entry.root)) do
      if className(item.node):find('Image', 1, true) then
        self:dumpBrush('live ' .. objectName(item.node), item.node)
      end
    end
    for _, item in ipairs(self:progressNodes(entry)) do
      for _, node in ipairs(innerNodesOf(item.node)) do
        if className(node):find('Image', 1, true) then
          self:dumpBrush(objectName(item.node) .. ' in ' .. objectName(node), node)
        end
      end
    end
  end)
  local cdo = self:classDefaults()
  if valid(cdo) then self:dumpNumbers('default', cdo) end
  local roots = self:authoredRoots()
  if #roots == 0 then
    self.log('hud bars: the game has no authored widget tree for ' .. BAR_PACKAGE)
  end
  -- 蓝图自己的 BarX 就是新存档起步的长度。
  for _, source in ipairs(roots) do
    self:probeStep(source.label .. ' tree', function() self:dumpTree(source.label, source.root) end)
    for _, item in ipairs(indexTree(source.root)) do
      local class = className(item.node)
      local x = class:find('Progress', 1, true) and numProp(item.node, 'BarX')
      if x then
        self.log(string.format('hud bars: %s %s BarX=%.1f', source.label, class, x))
        -- 与游戏改动之前相同的那些控件：由某个控件（而不是 BarX）定尺寸
        -- 的填充，会在这里显示出它的原始尺寸。
        self:probeStep(source.label .. ' inner', function()
          for _, node in ipairs(innerNodesOf(item.node)) do
            self.log('hud bars: ' .. source.label .. ' in ' .. describeNode(node, 0))
            self:dumpAllNumbers(source.label .. ' in ' .. objectName(node), node)
          end
        end)
        self:probeStep(source.label .. ' functions', function()
          self:dumpFunctions(source.label .. ' ' .. class, item.node)
        end)
      end
    end
  end
  for _, name in ipairs({ 'HPBarWhiteRatio', 'ShachiBarRatio' }) do
    local value = prop(entry.inst, name)
    if type(value) == 'number' then
      self.log(string.format('hud bars:   %s = %.4f', name, value))
    end
  end
  pcall(function()
    local transform = entry.root.RenderTransform
    local scale = transform and transform.Scale
    local tx = transform and transform.Translation and transform.Translation.X
    local sx = scale and (scale.X or scale.x)
    local sy = scale and (scale.Y or scale.y)
    self.log(string.format('hud bars:   transform pos=%s scale=%s,%s', tostring(tx), tostring(sx), tostring(sy)))
  end)
end

-- 条内样式用自己的字号，所以切换样式必须重新测量文本；
-- 清掉摆放结果就能让下一次更新把它放回去。
-- 真正让 Slate 按新字号重建文本的是 SetFont ——只写 Font.Size 改的是
-- 一份副本。描边也在字体结构体里，
-- 所以同一次调用顺带把它带上。
local function setNumberFont(number, size)
  if number.font == size then return end
  number.font = size
  local ok = pcall(function()
    local font = number.widget.Font
    font.Size = size
    local settings = font.OutlineSettings
    if settings == nil then settings = {} end
    settings.OutlineSize = OUTLINE_SIZE
    settings.OutlineColor = { R = 0, G = 0, B = 0, A = 1 }
    font.OutlineSettings = settings
    number.widget:SetFont(font)
  end)
  if not ok then
    pcall(function() number.widget.Font.Size = size end)
  end
  number.value = nil
  number.x, number.y, number.boxW = nil, nil, nil
end

function HudBars:updateNumbers(snapshot)
  local hpText, qiText
  if snapshot then
    local hp, hpMax = numberText(snapshot.hp), numberText(snapshot.hpMax)
    if hp and hpMax then hpText = hp .. ' / ' .. hpMax end
    local qi, qiMax = numberText(snapshot.qi), numberText(snapshot.qiMax)
    if qi and qiMax then qiText = qi .. ' / ' .. qiMax end
  end
  local center = self.S.HudNumberStyle == 'center'
  -- 条内的文字是白色的，与参考的数值 HUD 一致；在条的上方和下方
  -- 则保持弧线的颜色。
  if self.centerColour == nil then self.centerColour = Config.hexToLinear(WHITE) end
  -- 颜色跟随弧线设置，所以除非 HpColor / QiColor 真的在菜单里变了，
  -- 重新读取只是一次字符串比较。
  if self.hpHexSrc ~= self.S.HpColor then
    self.hpHexSrc, self.hpHex = self.S.HpColor, Config.normalizeHex(self.S.HpColor, '#FFFFFF')
  end
  if self.qiHexSrc ~= self.S.QiColor then
    self.qiHexSrc, self.qiHex = self.S.QiColor, Config.normalizeHex(self.S.QiColor, '#FFFFFF')
  end
  for _, entry in ipairs(self.entries) do
    local geo = entry.geometry
    if geo and #(entry.numbers or {}) > 0 then
      -- 上方和下方：每个数字在自己的条上，血量在上、杀气在下，这样两者都
      -- 不会盖住填充。偏移属于条自身的空间。
      local row = clamp(geo.thickness / 2 + NUM_FONT / 2 + 2, ROW_OFFSET, 60)
      local hpSpan = self:barSpan(entry, 'hp')
      local qiSpan = self:barSpan(entry, 'qi')
      for _, number in ipairs(entry.numbers) do
        local key = number.key
        local text = (key == 'hp') and hpText or qiText
        if text == nil then
          showNumber(number, nil)
        else
          local span = (key == 'hp') and hpSpan or qiSpan
          if span == nil then span = geo.right - geo.left end
          if center then
            -- 样式变化时强制重绘，因为颜色也不同。
            if number.style ~= 'center' then
              number.style, number.value = 'center', nil
              number.x, number.y = nil, nil
            end
            if number.colour ~= self.centerColour then
              number.colour, number.value = self.centerColour, nil
            end
            local font = CENTER_FONT
            setNumberFont(number, font)
            showNumber(number, text, number.colour)
            -- 居中在条自身的跨度上，而不是居中在已填充的部分上，这样数值变小
            -- 不会把数字往左拽。宽度是在文本设置好之后测量的。
            local measured = measuredSize(number.widget)
            local boxW = (measured and measured > 0) and measured
              or math.max(NUM_MIN_W, #text * font * 0.62)
            local left = geo.left + span / 2 - boxW / 2
            -- 文本是从 offsetY 向下绘制的，所以条的中线等于条带顶部加上它
            -- 高度的一半，再减去半行文字。
            local offsetY = (BAR_TOP_Y[key] or 0) + (self:stripDrawnHeight(entry, key) or 0) / 2
              - font / 2
            if number.styleLogged ~= 'center' then
              number.styleLogged = 'center'
              -- 把描边读回来：这是判断字体结构体有没有留住它的唯一办法，
              -- 因为从这里没有别的途径可以检查。
              local edge = 'n/a'
              pcall(function()
                edge = tostring(number.widget.Font.OutlineSettings.OutlineSize)
              end)
              self.log(string.format(
                'hud bars: %s number inside the bar (font %.0f, bar %.0f..%.0f, span %.0f, y %.1f, outline %s)',
                key, font, geo.left, geo.right, span, offsetY, edge))
            end
            placeNumber(number, left, offsetY, boxW)
          else
            if number.style ~= 'side' then
              number.style, number.value = 'side', nil
              number.hex = nil
              setNumberFont(number, NUM_FONT)
            end
            local hex = (key == 'hp') and self.hpHex or self.qiHex
            if number.hex ~= hex then
              number.hex = hex
              number.colour = Config.hexToLinear(hex)
              number.value = nil -- 用新颜色重绘
            end
            local boxW = math.max(NUM_MIN_W, #text * NUM_CHAR_W)
            local left = geo.left + span / 2 - boxW / 2
            local offsetY = ((key == 'hp') and -row or row) + ROW_DOWN
            if number.logged == nil then
              number.logged = true
              self.log(string.format(
                'hud bars: %s number above / below (bar %.0f..%.0f, span %.0f, %.0f wide, row %.0f)',
                key, geo.left, geo.right, span, boxW, offsetY))
            end
            placeNumber(number, left, offsetY, boxW)
            showNumber(number, text, number.colour)
          end
        end
      end
    end
  end
end

function HudBars:update(dt, snapshot)
  local pin, numbers = self.S.PinHudBars, self.S.HudNumbers
  if not pin and not numbers then
    if #self.entries > 0 then self:release() end
    return
  end
  if not self.hooked then self:hook() end
  self.clock = self.clock + (dt or 0)
  local now = self.clock
  local alive = #self.entries > 0
  if alive then
    for _, entry in ipairs(self.entries) do
      if not valid(entry.root) then alive = false break end
    end
  end
  if now >= self.nextScan or not alive then
    self.nextScan = now + SCAN_INTERVAL
    self:scan()
  end
  self.snapshot = snapshot
  for _, entry in ipairs(self.entries) do
    pcall(function() self:applyEntry(entry, now) end)
    -- 只有在条被保持固定长度时小盖子才需要盯着；否则它就是游戏自己的
    -- 控件，遵循游戏自己的规则。
    if pin then pcall(function() self:updateLittleBars(entry, snapshot) end) end
  end
  -- Debug 会在上限变化时（很少见：升级、换装备）记录条自身的长度，
  -- 以及它被钉住的目标长度。
  if self.S.Debug and snapshot and snapshot.hpMax ~= self.lastDebugMax then
    self.lastDebugMax = snapshot.hpMax
    for _, entry in ipairs(self.entries) do
      for _, item in ipairs(self:progressNodes(entry)) do
        self.log(string.format('hud bars: hpMax=%s %s BarX=%.1f target=%.1f',
          tostring(snapshot.hpMax), objectName(item.node),
          numProp(item.node, 'BarX') or -1, self:targetBarX(item.class) or -1))
      end
    end
  end
  if numbers then self:updateNumbers(snapshot) end
end

function HudBars:destroy()
  self:release()
end

return HudBars
