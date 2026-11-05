-- PBZPlayerArcs：游戏内 F2 设置菜单。读写同一个 settings.ini。
local Config = require('PBZArcsConfig')
local Lang = require('PBZArcsLang')

local Menu = {}
Menu.__index = Menu

local CLASS = {
  user = '/Script/UMG.UserWidget',
  tree = '/Script/UMG.WidgetTree',
  canvas = '/Script/UMG.CanvasPanel',
  border = '/Script/UMG.Border',
  button = '/Script/UMG.Button',
  text = '/Script/UMG.TextBlock',
}

local PANEL_W, PANEL_H = 1000, 612
local ROW_H = 28
local ROW_TOP = 92
local COL_A_LABEL, COL_A_SLIDER, COL_A_VALUE = 24, 178, 444
local COL_B_LABEL, COL_B_SLIDER, COL_B_VALUE = 512, 666, 932
local SLIDER_W = 250

-- 图标在 55、弧形在 50，所以遮罩必须位于两者之下：
-- 打开菜单应该压暗游戏 HUD，而不是正在被编辑的那些读数。
local DIM_Z = 44
-- 面板通常待在弧形和图标之下。只有当指针在它里面时才会跳到
-- 最上层，因为压在它上面的控件会吞掉滑块和图标拖动所依赖的
-- 鼠标事件。
local MENU_Z, MENU_TOP_Z = 45, 300

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
  local ok, inner = pcall(function() return value:get() end)
  if ok and inner ~= nil then return inner end
  return value
end

-- FindFirstOf 会遍历所有对象，所以每帧走的路径必须复用结果。
-- 已销毁的 controller 会 IsValid() 失败，并在下次调用时重新查找。
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

local cachedLayoutLib = nil
local function layoutLibrary()
  if valid(cachedLayoutLib) then return cachedLayoutLib end
  local lib = StaticFindObject('/Script/UMG.Default__WidgetLibrary')
  if not valid(lib) then lib = StaticFindObject('/Script/UMG.Default__WidgetLayoutLibrary') end
  if valid(lib) then cachedLayoutLib = lib end
  return valid(lib) and lib or nil
end

local function cleanupOld(prefix)
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

local function viewportSize()
  local pc = playerController()
  if not valid(pc) then return 1920, 1080, 1 end
  local world = prop(pc, 'GetWorld') and pc:GetWorld() or nil
  local lib = StaticFindObject('/Script/UMG.Default__WidgetLayoutLibrary')
  if valid(lib) and valid(world) then
    local ok, size = pcall(function() return lib:GetViewportSize(world) end)
    local ok2, scale = pcall(function() return lib:GetViewportScale(world) end)
    if ok and size then
      local w = size.X or size.x
      local h = size.Y or size.y
      local dpi = (ok2 and type(scale) == 'number' and scale > 0.1) and scale or 1
      if type(w) == 'number' and type(h) == 'number' and w > 0 and h > 0 then
        return w / dpi, h / dpi, dpi
      end
    end
  end
  return 1920, 1080, 1
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

local function toLinear(colour)
  if type(colour) ~= 'table' then return { R = 1, G = 1, B = 1, A = 1 } end
  return { R = colour.R or colour[1] or 0, G = colour.G or colour[2] or 0,
           B = colour.B or colour[3] or 0, A = colour.A or colour[4] or 1 }
end

local function addBorder(tree, parent, x, y, w, h, colour, z)
  local border = StaticConstructObject(cls(CLASS.border), parent)
  if not valid(border) then return nil, nil end
  pcall(function() border:SetBrushColor(toLinear(colour)) end)
  pcall(function() border:SetPadding({ Left = 0, Top = 0, Right = 0, Bottom = 0 }) end)
  local slot = addChild(parent, border, x, y, w, h, z)
  if not valid(slot) then
    pcall(function() border:RemoveFromParent() end)
    return nil, nil
  end
  return border, slot
end

local function addText(tree, parent, name, value, x, y, w, h, size, colour, z)
  local text = StaticConstructObject(cls(CLASS.text), tree, FName(name))
  if not valid(text) then return nil end
  pcall(function() text:SetText(FText(tostring(value))) end)
  pcall(function() text.Font.Size = size or 14 end)
  local col = toLinear(colour)
  pcall(function()
    text:SetColorAndOpacity({
      SpecifiedColor = { R = col.R, G = col.G, B = col.B, A = col.A },
      ColorUseRule = 0,
    })
  end)
  local slot = addChild(parent, text, x, y, w, h, z)
  if not slot then return nil end
  return text, slot
end

-- 渲染变换旋转是不用贴图画出箭头的唯一办法。
-- 如果结构体写入被拒绝，调用方会退回使用文字字形。
local function setAngle(widget, angle)
  if not valid(widget) then return false end
  return pcall(function()
    widget:SetRenderTransform({
      Translation = { X = 0, Y = 0 },
      Scale = { X = 1, Y = 1 },
      Sheart = { X = 0, Y = 0 },
      Angle = angle,
    })
  end)
end

local function C(hex, alpha)
  local c = Config.hexToLinear(hex)
  c.A = alpha or 1
  return c
end
local GOLD = C('#E8B54B')
local WHITE = C('#D8D2C4')
local DIM = C('#8A8377')
local TRACK = C('#1E1F1C')
local PANEL_BG = C('#0A0B0C', 0.96)
local TOOLTIP_BG = C('#16171A', 0.98)
local BUTTON_BG = C('#24262A')
local BUTTON_ON = C('#6E5420')
local CURSOR = C('#FFF0C8')
-- 提示行换行前允许达到的最大宽度；框本身按结果自适应。
local TIP_WRAP = 430

local function formatValue(def, value)
  if def.integer then return tostring(math.floor(value + 0.5)) end
  return string.format('%.2f', value)
end

-- 行定义。颜色行读写 HSL 通道，但在 S 里存的是十六进制颜色。
local ROWS_A = {
  { key = 'Radius', id = 'row.radius', min = 60, max = 400, step = 1, integer = true },
  { key = 'Thickness', id = 'row.thickness', min = 2, max = 30, step = 1, integer = true },
  { key = 'ArcSpan', id = 'row.arcSpan', min = 30, max = 180, step = 1, integer = true },
  { key = 'Segments', id = 'row.segments', min = 8, max = 96, step = 1, integer = true },
  { key = 'BrushJitter', id = 'row.brushJitter', min = 0, max = 1, step = 0.01 },
  { key = 'StrokeOverlap', id = 'row.strokeOverlap', min = 1, max = 24, step = 0.1 },
  { key = 'AnchorHeight', id = 'row.anchorHeight', min = -50, max = 250, step = 1, integer = true },
  { key = 'AnchorOffsetX', id = 'row.anchorOffsetX', min = -400, max = 400, step = 1, integer = true },
  { key = 'AnchorOffsetY', id = 'row.anchorOffsetY', min = -400, max = 400, step = 1, integer = true },
  { key = 'BarOpacity', id = 'row.barOpacity', min = 0.05, max = 1, step = 0.01 },
  { key = 'TrackOpacity', id = 'row.trackOpacity', min = 0, max = 1, step = 0.01 },
  { key = 'GhostOpacity', id = 'row.ghostOpacity', min = 0, max = 1, step = 0.01 },
  { key = 'GhostSpeed', id = 'row.ghostSpeed', min = 0.02, max = 3, step = 0.01 },
  { key = 'FollowSmoothing', id = 'row.followSmoothing', min = 0, max = 0.4, step = 0.01 },
}

local ROWS_B = {
  { key = 'HpColor', colour = true, channel = 'h', tip = 'tip.hpColor', id = 'row.hpColorH', min = 0, max = 360, step = 1, integer = true },
  { key = 'HpColor', colour = true, channel = 's', tip = 'tip.hpColor', id = 'row.hpColorS', min = 0, max = 100, step = 1, integer = true },
  { key = 'HpColor', colour = true, channel = 'l', tip = 'tip.hpColor', id = 'row.hpColorL', min = 0, max = 100, step = 1, integer = true },
  { key = 'QiColor', colour = true, channel = 'h', tip = 'tip.qiColor', id = 'row.qiColorH', min = 0, max = 360, step = 1, integer = true },
  { key = 'QiColor', colour = true, channel = 's', tip = 'tip.qiColor', id = 'row.qiColorS', min = 0, max = 100, step = 1, integer = true },
  { key = 'QiColor', colour = true, channel = 'l', tip = 'tip.qiColor', id = 'row.qiColorL', min = 0, max = 100, step = 1, integer = true },
  { key = 'WarnThresholdHp', id = 'row.warnThresholdHp', min = 0, max = 1, step = 0.01 },
  { key = 'WarnThresholdQi', id = 'row.warnThresholdQi', min = 0, max = 1, step = 0.01 },
  { key = 'WarnFlashSpeed', id = 'row.warnFlashSpeed', min = 0.2, max = 8, step = 0.1 },
  { key = 'WarnFlashAmount', id = 'row.warnFlashAmount', min = 0, max = 1, step = 0.01 },
  { key = 'TipScale', id = 'row.tipScale', min = 0.3, max = 3, step = 0.05 },
  { key = 'TipAngle', id = 'row.tipAngle', min = -90, max = 90, step = 1, integer = true },
  { key = 'HideDelay', id = 'row.hideDelay', min = 0, max = 10, step = 0.1 },
  { key = 'IconScale', id = 'row.iconScale', min = 0.5, max = 3, step = 0.05 },
}

local function rowGet(S, row)
  if row.colour then
    local h, s, l = Config.hexToHsl(S[row.key])
    if row.channel == 'h' then return h end
    if row.channel == 's' then return s end
    return l
  end
  local value = tonumber(S[row.key])
  if value == nil then value = row.min end
  return value
end

local function rowSet(S, row, value)
  if row.colour then
    local h, s, l = Config.hexToHsl(S[row.key])
    if row.channel == 'h' then h = value
    elseif row.channel == 's' then s = value
    else l = value end
    S[row.key] = Config.hslToHex(h, s, l)
    return
  end
  if row.step and row.step > 0 then
    value = row.min + math.floor((value - row.min) / row.step + 0.5) * row.step
  end
  if row.integer then value = math.floor(value + 0.5) end
  value = math.max(row.min, math.min(row.max, value))
  S[row.key] = value
end

function Menu.new(settings, callbacks)
  local self = setmetatable({
    S = settings,
    callbacks = callbacks or {},
    root = nil,
    canvas = nil,
    tree = nil,
    open = false,
    rows = {},
    buttons = {},
    labels = {},
    dragRow = nil,
    dropdowns = {},
    panelX = 0,
    panelY = 0,
    lastSave = 0,
    lastToggle = -100,
    hover = nil,
    hoverSlot = nil,
    cursorH = nil,
    cursorV = nil,
    pointerX = nil,
    pointerY = nil,
    mouseX = nil,
    mouseY = nil,
    stillTime = 0,
    lastMoveX = nil,
    lastMoveY = nil,
    text = nil,
    textLang = nil,
    hoverKey = nil,
    tipRoot = nil,
    tipText = nil,
    tipKey = nil,
  }, Menu)
  return self
end

local function keyLabel(S)
  local name = tostring(S.MenuKey or 'F2'):upper()
  if name == '' then name = 'F2' end
  return name
end

function Menu:t(id)
  if id == nil then return '' end
  if self.text == nil or self.textLang ~= self.S.Lang then
    self.text = Lang.load(self.S.Lang)
    self.textLang = self.S.Lang
  end
  local value = self.text[id]
  if type(value) == 'string' and value ~= '' then
    if value:find('{menu}', 1, true) then
      value = value:gsub('%{menu%}', function() return keyLabel(self.S) end)
    end
    return value
  end
  return id
end

function Menu:saveSoon(force)
  local now = os.clock()
  if not force and now - self.lastSave < 0.35 then return end
  self.lastSave = now
  Config.save(self.S)
end

function Menu:changed(key)
  if self.callbacks.onChange then pcall(self.callbacks.onChange, key) end
  self:saveSoon(false)
end

function Menu:buildButton(parent, tree, x, y, w, h, key, id)
  local bg, slot = addBorder(tree, parent, x, y, w, h, BUTTON_BG, 1)
  if not bg then return nil end
  local text, textSlot = addText(tree, parent, 'PBZArcs_Btn_' .. key .. '_' .. tostring(#self.buttons),
    self:t(id), x + 6, y + 5, w - 12, h - 8, 14, GOLD, 2)
  if not text then return nil end
  local button = {
    key = key,
    x = x, y = y, w = w, h = h,
    bg = bg,
    text = text,
    textSlot = textSlot,
    id = id,
  }
  self.buttons[#self.buttons + 1] = button
  return button
end

function Menu:buildChevron(parent, tree, x, y, w, h, z)
  local armW = math.max(6, math.floor(w * 0.62))
  local barY = y + math.floor(h * 0.42)
  local left = addBorder(tree, parent, x, barY, armW, 2, GOLD, z)
  local right = addBorder(tree, parent, x + w - armW, barY, armW, 2, GOLD, z)
  if not (valid(left) and valid(right)) then return nil end
  if not (setAngle(left, 45) and setAngle(right, -45)) then
    pcall(function() left:RemoveFromParent() end)
    pcall(function() right:RemoveFromParent() end)
    local glyph = addText(tree, parent, 'PBZArcs_MenuChevron_' .. tostring(math.random(1000000)),
      'v', x, y - 2, w, h, 12, GOLD, z)
    if not glyph then return nil end
    return { glyph = glyph }
  end
  return { left = left, right = right }
end

function Menu:setChevron(chevron, open)
  if chevron == nil then return end
  if chevron.glyph then
    pcall(function() chevron.glyph:SetText(FText(open and '^' or 'v')) end)
    return
  end
  setAngle(chevron.left, open and -45 or 45)
  setAngle(chevron.right, open and 45 or -45)
end

-- def: key, x, y, w, h, up, options[{ value, id?, label? }], value(), set(v), text()
-- 选项行是从头重建的，因为菜单保持打开时下拉框可能被重新填充，
-- 所以行数无法预先确定。
local dropSeq = 0

function Menu:fillDropdownMenu(dd, options)
  if valid(dd.menu) then
    pcall(function() dd.menu:RemoveFromParent() end)
    dd.menu = nil
  end
  dd.items = {}
  dropSeq = dropSeq + 1
  local tag = tostring(dropSeq)
  local menuH = math.max(1, #options * 27 - 1)
  local menuY = dd.up and (dd.y - 4 - menuH) or (dd.y + dd.h + 4)
  local menu = StaticConstructObject(cls(CLASS.canvas), dd.tree,
    FName('PBZArcs_MenuDrop_' .. dd.key .. '_' .. tag))
  if not valid(menu) then return end
  addChild(dd.parent, menu, dd.x, menuY, dd.w, menuH, 40)
  dd.menu = menu
  for index, option in ipairs(options) do
    local iy = (index - 1) * 27
    local bg = addBorder(dd.tree, menu, 0, iy, dd.w, 26, BUTTON_BG, 1)
    local text = addText(dd.tree, menu,
      'PBZArcs_MenuDrop_' .. dd.key .. '_Opt_' .. index .. '_' .. tag, '',
      8, iy + 4, dd.w - 16, 20, 14, GOLD, 2)
    if bg and text then
      dd.items[#dd.items + 1] = {
        value = option.value, id = option.id, label = option.label,
        x = dd.x, y = menuY + iy, w = dd.w, h = 26,
        bg = bg, text = text,
      }
    end
  end
  pcall(function() menu:SetVisibility(1) end)
end

function Menu:buildDropdown(parent, tree, def)
  local dd = {
    key = def.key, x = def.x, y = def.y, w = def.w, h = def.h, open = false,
    parent = parent, tree = tree, up = def.up, optionsFor = def.optionsFor,
  }
  local button = self:buildButton(parent, tree, def.x, def.y, def.w, def.h, def.key,
    def.options and def.options[1] and def.options[1].id or 'menu.title')
  if not button then return nil end
  dd.button = button
  button.tip = def.tip
  if button.textSlot then
    pcall(function() button.textSlot:SetSize({ X = def.w - 30, Y = def.h - 8 }) end)
  end
  button.textFor = def.text
  button.get = function() return dd.open end
  button.action = function() self:toggleDropdown(dd) end
  self:fillDropdownMenu(dd, def.options or {})

  dd.chevron = self:buildChevron(parent, tree, def.x + def.w - 24,
    def.y + math.floor((def.h - 12) / 2), 12, 12, 3)
  dd.value = def.value
  dd.set = def.set
  self.dropdowns[#self.dropdowns + 1] = dd
  return dd
end

function Menu:refreshDropdown(dd)
  if valid(dd.menu) then
    pcall(function() dd.menu:SetVisibility(dd.open and 0 or 1) end)
  end
  self:setChevron(dd.chevron, dd.open)
  if dd.open then
    local current = dd.value and dd.value() or nil
    for _, item in ipairs(dd.items or {}) do
      local active = current == item.value
      pcall(function() item.bg:SetBrushColor(toLinear(active and BUTTON_ON or BUTTON_BG)) end)
      if item.label then
        pcall(function() item.text:SetText(FText(item.label)) end)
      elseif item.id then
        pcall(function() item.text:SetText(FText(self:t(item.id))) end)
      end
    end
  end
  if dd.button then self:refreshButton(dd.button) end
end

function Menu:closeDropdowns(except)
  for _, dd in ipairs(self.dropdowns or {}) do
    if dd ~= except and dd.open then
      dd.open = false
      self:refreshDropdown(dd)
    end
  end
end

function Menu:toggleDropdown(dd)
  local opening = not dd.open
  self:closeDropdowns(dd)
  dd.open = opening
  -- 带有动态选项列表（预设、语言）的下拉框每次打开都会重新填充，
  -- 所以菜单打开期间新增或改名的文件会立刻出现。
  if opening and dd.optionsFor then
    self:forgetPresets()
    self:fillDropdownMenu(dd, dd.optionsFor())
  end
  self:refreshDropdown(dd)
end

function Menu:chooseDropdown(dd, value)
  if dd.set then dd.set(value) end
  dd.open = false
  self:refreshDropdown(dd)
  if dd.button then self:refreshButtonText(dd.button) end
  self:saveSoon(true)
end

function Menu:wireToggle(button, def)
  button.get = def.get
  button.tip = def.tip
  button.idOn, button.idOff = def.idOn, def.idOff
  button.action = function()
    local value = not def.get()
    def.set(value)
    self:refreshButtonText(button)
    self:refreshButton(button)
    self:changed(button.key)
    self:saveSoon(true)
  end
end

---------------------------------------------------------------------------------------------------
-- 预设

-- 从 Scripts/preset 里的文件读取，这样在游戏外改过的名字不用重启
-- 就能显示出来。按钮文本刷新频繁，所以列表会缓存，并在菜单重新
-- 打开或写入预设时丢弃。文件夹缺失时报告为一个未命名预设，
-- 这样 保存 至少还有地方可写。
function Menu:presetList()
  if self._presets then return self._presets end
  local list = Config.listPresets()
  if #list == 0 then
    list[1] = { index = 1, key = Config.presetKey(1), name = '预设 1', values = nil }
  end
  self._presets = list
  return list
end

function Menu:forgetPresets()
  self._presets = nil
end

-- 当前数值所属的预设。已不存在的文件名会拿到一个
-- 新的空位，而不是让这次保存丢掉。
function Menu:presetTarget()
  local list = self:presetList()
  return Config.presetByKey(list, self.S.Preset) or Config.nextPresetSlot(list)
end

-- 选中预设的显示名，取不到时回退到已保存的文件名。
function Menu:presetName()
  local preset = Config.presetByKey(self:presetList(), self.S.Preset)
  return preset and preset.name or tostring(self.S.Preset)
end

-- 加载预设会用已存的值替换当前设置，然后按它们重画面板
-- 并重建弧形。
function Menu:applyPreset(key)
  local preset = Config.presetByKey(self:presetList(), key)
  if preset == nil or preset.values == nil then
    if self.callbacks.alert then self.callbacks.alert('preset missing: ' .. tostring(key)) end
    return
  end
  -- 语言属于玩家而不属于预设，所以仍然带着 Lang 行的旧预设
  -- 文件永远不会切换菜单语言。
  for k, value in pairs(preset.values) do
    if k ~= 'Lang' then self.S[k] = value end
  end
  self.S.Preset = preset.key
  Config.sanitize(self.S)
  self:refreshAllRows()
  self:refreshLanguage()
  self:changed('Preset')
  self:saveSoon(true)
end

function Menu:saveCurrentPreset()
  local preset = self:presetTarget()
  if not Config.savePreset(preset, self.S) then return end
  self:forgetPresets()
  if self.callbacks.log then self.callbacks.log('preset saved: ' .. preset.name) end
end

-- 新预设取下一个空编号，数值保持原样，
-- 并成为当前选中的那个预设。
function Menu:createPreset()
  local preset = Config.nextPresetSlot(self:presetList())
  if not Config.savePreset(preset, self.S) then return end
  self.S.Preset = preset.key
  Config.save(self.S)
  self:forgetPresets()
  self:refreshAllButtons()
  if self.callbacks.log then self.callbacks.log('preset created: ' .. preset.name) end
end

function Menu:refreshButton(button)
  local on = button.get ~= nil and button.get() == true
  local colour = on and BUTTON_ON or BUTTON_BG
  if button.hovered then
    colour = { R = colour.R + 0.10, G = colour.G + 0.10, B = colour.B + 0.10, A = colour.A or 1 }
  end
  pcall(function() button.bg:SetBrushColor(toLinear(colour)) end)
end

function Menu:refreshButtonText(button)
  if button.textFor then
    if button.text then pcall(function() button.text:SetText(FText(button.textFor())) end) end
    return
  end
  local id = button.id
  if button.key == 'Reset' then
    id = 'btn.reset'
  elseif button.get ~= nil then
    id = button.get() and button.idOn or button.idOff
  end
  if id and button.text then
    button.id = id
    pcall(function() button.text:SetText(FText(self:t(id))) end)
  end
end

function Menu:build()
  self:forgetPresets()
  -- 每次打开都重新读取语言文件，这样改过的措辞和新加的语言
  -- 不用重启游戏就能显示出来。
  Lang.reload()
  self.text = nil
  self:destroy()
  cleanupOld('PBZArcs_Menu')
  local engine = FindFirstOf('GameEngine') or FindFirstOf('Engine')
  if not valid(engine) then return false end
  local gi = prop(engine, 'GameInstance')
  if not valid(gi) then return false end

  local suffix = tostring(os.time()) .. '_' .. tostring(math.random(1000, 9999))
  local root = StaticConstructObject(cls(CLASS.user), gi, FName('PBZArcs_Menu_' .. suffix))
  local tree = StaticConstructObject(cls(CLASS.tree), root, FName('PBZArcs_MenuTree_' .. suffix))
  if not (valid(root) and valid(tree)) then return false end
  root.WidgetTree = tree
  local canvas = StaticConstructObject(cls(CLASS.canvas), tree, FName('PBZArcs_MenuCanvas_' .. suffix))
  tree.RootWidget = canvas

  local vw, vh = viewportSize()
  local px = math.max(8, vw - PANEL_W - 24)
  local py = math.max(8, (vh - PANEL_H) / 2)
  self.panelX, self.panelY = px, py

  local panel = StaticConstructObject(cls(CLASS.canvas), tree, FName('PBZArcs_MenuPanel_' .. suffix))
  local panelSlot = addChild(canvas, panel, px, py, PANEL_W, PANEL_H, 10)
  if not valid(panelSlot) then return false end
  addBorder(tree, panel, 0, 0, PANEL_W, PANEL_H, PANEL_BG, 0)
  addBorder(tree, panel, 0, 0, PANEL_W, 2, GOLD, 1)

  -- 游戏一直隐藏硬件光标，所以菜单自己画一个。
  local hoverBand, hoverBandSlot = addBorder(tree, panel, 12, 0, PANEL_W - 24, ROW_H,
    { R = 0.72, G = 0.57, B = 0.24, A = 0.14 }, 0)
  if hoverBand then pcall(function() hoverBand:SetVisibility(1) end) end
  self.hover, self.hoverSlot = hoverBand, hoverBandSlot

  self.rows = {}
  self.buttons = {}
  self.labels = {}

  local title = addText(tree, panel, 'PBZArcs_Title', self:t('menu.title'),
    24, 14, 500, 30, 20, GOLD, 1)
  if title then self.labels[#self.labels + 1] = { widget = title, id = 'menu.title' } end
  local hint = addText(tree, panel, 'PBZArcs_Hint', self:t('menu.hint'),
    24, 50, 720, 22, 12, DIM, 1)
  if hint then self.labels[#self.labels + 1] = { widget = hint, id = 'menu.hint' } end

  local function buildRows(defs, labelX, sliderX, valueX, column)
    for index, def in ipairs(defs) do
      local y = ROW_TOP + (index - 1) * ROW_H
      local label = addText(tree, panel, 'PBZArcs_Label_' .. column .. '_' .. index,
        self:t(def.id), labelX, y + 4, sliderX - labelX - 10, 22, 14, WHITE, 1)
      addBorder(tree, panel, sliderX, y + 10, SLIDER_W, 6, TRACK, 1)
      local fill, fillSlot = addBorder(tree, panel, sliderX, y + 10, 1, 6, GOLD, 2)
      local handle, handleSlot = addBorder(tree, panel, sliderX - 4, y + 4, 8, 18, GOLD, 3)
      local value = addText(tree, panel, 'PBZArcs_Value_' .. column .. '_' .. index,
        '', valueX, y + 4, 64, 22, 14, GOLD, 1)
      if label and fill and handle and value then
        local row = {
          def = def,
          label = label,
          value = value,
          fill = fill,
          fillSlot = fillSlot,
          handle = handle,
          handleSlot = handleSlot,
          sliderX = sliderX,
          y = y,
          index = index,
          -- 整行都响应中键：标签、轨道和读数。
          -- 除非该行覆盖，否则 tip 由标签 id 推导出来。
          labelX = labelX,
          valueX = valueX,
          tip = def.tip or ('tip.' .. def.id:sub(5)),
        }
        self.rows[#self.rows + 1] = row
        self.labels[#self.labels + 1] = { widget = label, id = def.id }
      end
    end
  end
  buildRows(ROWS_A, COL_A_LABEL, COL_A_SLIDER, COL_A_VALUE, 'A')
  buildRows(ROWS_B, COL_B_LABEL, COL_B_SLIDER, COL_B_VALUE, 'B')
  -- 让标签持有对该行的引用，以便刷新语言。
  for i, row in ipairs(self.rows) do
    for _, item in ipairs(self.labels) do
      if item.widget == row.label then item.row = row end
    end
  end

  -- 悬停提示：一个跟随指针的小框，用来解释指针下的条目。
  -- 它靠渲染平移移动，而不是改 slot 位置，所以跟随鼠标
  -- 不会每帧都跑一遍 canvas 布局。边框把文本当作自己的子控件
  -- 并自适应大小，因此框总是和文本实际换行后的结果一致；
  -- 显式指定高度只会让背景绑在一个对换行的猜测上。
  local tipRoot = StaticConstructObject(cls(CLASS.canvas), tree, FName('PBZArcs_MenuTip_' .. suffix))
  if valid(tipRoot) then
    addChild(panel, tipRoot, 0, 0, PANEL_W, PANEL_H, 60)
    local tipBg, tipBgSlot = addBorder(tree, tipRoot, 0, 0, 0, 0, TOOLTIP_BG, 0)
    local tipText = StaticConstructObject(cls(CLASS.text), tree, FName('PBZArcs_MenuTipText_' .. suffix))
    if tipBg and valid(tipText) then
      pcall(function() tipText:SetText(FText('')) end)
      pcall(function() tipText.Font.Size = 12 end)
      local col = toLinear(WHITE)
      pcall(function()
        tipText:SetColorAndOpacity({
          SpecifiedColor = { R = col.R, G = col.G, B = col.B, A = col.A },
          ColorUseRule = 0,
        })
      end)
      -- 换行是手工做的，而不是交给文本块：UMG 会把这段文本按给定宽度的
      -- 大约三分之二处换行，而框必须和文本的实际表现一致。
      -- 用硬换行后，框只需量最长的那一行。
      pcall(function() tipText:SetAutoWrapText(false) end)
      pcall(function() tipBg:SetPadding({ Left = 9, Top = 6, Right = 9, Bottom = 7 }) end)
      local attached = pcall(function() tipBg:AddChild(tipText) end)
      if attached then pcall(function() tipBgSlot:SetAutoSize(true) end) end
      pcall(function() tipRoot:SetVisibility(1) end)
      self.tipRoot, self.tipBg, self.tipBgSlot = tipRoot, tipBg, tipBgSlot
      self.tipText = tipText
      self:probeLog('tip: border ' .. (attached and 'ok' or 'failed'))
    end
  end

  -- 两列的行数相同，所以按钮区落在较长的那一列下面
  -- 隔一个 16px 的空隙。
  local buttonY = ROW_TOP + math.max(#ROWS_A, #ROWS_B) * ROW_H + 16
  local buttonH, gap, rowGap = 32, 14, 18
  -- 两行都是六个等宽的格子。
  local colW = math.floor((PANEL_W - 48 - gap * 5) / 6)
  local function colX(index) return 24 + (colW + gap) * (index - 1) end
  local toggles = {
    { key = 'FollowCharacter', idOn = 'btn.followOn', idOff = 'btn.followOff', tip = 'tip.follow',
      get = function() return self.S.FollowCharacter end, set = function(v) self.S.FollowCharacter = v end },
    { key = 'ShowGhost', idOn = 'btn.ghostOn', idOff = 'btn.ghostOff', tip = 'tip.ghost',
      get = function() return self.S.ShowGhost end, set = function(v) self.S.ShowGhost = v end },
    { key = 'ShowTip', idOn = 'btn.tipOn', idOff = 'btn.tipOff', tip = 'tip.tip',
      get = function() return self.S.ShowTip end, set = function(v) self.S.ShowTip = v end },
    { key = 'MedicineHud', idOn = 'btn.medicineOn', idOff = 'btn.medicineOff', tip = 'tip.medicine',
      get = function() return self.S.MedicineHud end, set = function(v) self.S.MedicineHud = v end },
    { key = 'UltHud', idOn = 'btn.ultOn', idOff = 'btn.ultOff', tip = 'tip.ult',
      get = function() return self.S.UltHud end, set = function(v) self.S.UltHud = v end },
    { key = 'PinHudBars', idOn = 'btn.pinBarsOn', idOff = 'btn.pinBarsOff', tip = 'tip.pinBars',
      get = function() return self.S.PinHudBars end,
      -- 只固定而不显示读数从来不是这个开关的本意，所以它会顺手把
      -- 数字也打开；之后数字开关仍可单独设置。
      set = function(v)
        self.S.PinHudBars = v
        if v then self.S.HudNumbers = true end
        self:refreshAllButtons()
      end },
  }
  for index, def in ipairs(toggles) do
    local button = self:buildButton(panel, tree, colX(index), buttonY,
      colW, buttonH, def.key, def.idOn)
    if button then self:wireToggle(button, def) end
  end

  local row2 = buttonY + buttonH + rowGap

  self:buildDropdown(panel, tree, {
    key = 'Visibility',
    x = colX(1), y = row2, w = colW, h = buttonH,
    up = true,
    tip = 'tip.visibility',
    options = {
      { value = 'always', id = 'btn.visibilityAlways' },
      { value = 'hud', id = 'btn.visibilityHud' },
      { value = 'dynamic', id = 'btn.visibilityDynamic' },
    },
    value = function() return tostring(self.S.Visibility or 'dynamic'):lower() end,
    set = function(value)
      self.S.Visibility = value
      self:changed('Visibility')
    end,
    text = function()
      local mode = tostring(self.S.Visibility or 'dynamic'):lower()
      return self:t((mode == 'always' and 'btn.visibilityAlways')
        or (mode == 'hud' and 'btn.visibilityHud') or 'btn.visibilityDynamic')
    end,
  })

  self:buildDropdown(panel, tree, {
    key = 'DisplayMode',
    x = colX(2), y = row2, w = colW, h = buttonH,
    up = true,
    tip = 'tip.display',
    options = {
      { value = 'both', id = 'btn.displayBoth' },
      { value = 'hp', id = 'btn.displayHp' },
      { value = 'qi', id = 'btn.displayQi' },
      { value = 'off', id = 'btn.displayOff' },
    },
    value = function() return tostring(self.S.DisplayMode or 'both'):lower() end,
    set = function(value)
      self.S.DisplayMode = value
      self:changed('DisplayMode')
    end,
    text = function()
      local mode = tostring(self.S.DisplayMode or 'both'):lower()
      return self:t((mode == 'hp' and 'btn.displayHp')
        or (mode == 'qi' and 'btn.displayQi')
        or (mode == 'off' and 'btn.displayOff') or 'btn.displayBoth')
    end,
  })

  local hpButton = self:buildButton(panel, tree, colX(3), row2, colW, buttonH,
    'HpOnLeft', 'btn.hpLeftOn')
  if hpButton then
    self:wireToggle(hpButton, {
      key = 'HpOnLeft', idOn = 'btn.hpLeftOn', idOff = 'btn.hpLeftOff', tip = 'tip.hpLeft',
      get = function() return self.S.HpOnLeft end, set = function(v) self.S.HpOnLeft = v end,
    })
  end
  local numButton = self:buildButton(panel, tree, colX(4), row2, colW, buttonH,
    'HudNumbers', 'btn.numbersOn')
  if numButton then
    self:wireToggle(numButton, {
      key = 'HudNumbers', idOn = 'btn.numbersOn', idOff = 'btn.numbersOff', tip = 'tip.numbers',
      get = function() return self.S.HudNumbers end,
      set = function(v) self.S.HudNumbers = v end,
    })
  end
  -- 数字绘制的位置：在条的上方和下方，或在条内部。
  self:buildDropdown(panel, tree, {
    key = 'HudNumberStyle',
    x = colX(5), y = row2, w = colW, h = buttonH,
    up = true,
    tip = 'tip.numStyle',
    options = {
      { value = 'side', id = 'btn.numStyleSide' },
      { value = 'center', id = 'btn.numStyleCenter' },
    },
    value = function() return tostring(self.S.HudNumberStyle or 'side'):lower() end,
    set = function(value)
      self.S.HudNumberStyle = value
      self:changed('HudNumberStyle')
    end,
    text = function()
      local style = tostring(self.S.HudNumberStyle or 'side'):lower()
      return self:t(style == 'center' and 'btn.numStyleCenter' or 'btn.numStyleSide')
    end,
  })
  self:buildButton(panel, tree, colX(6), row2, colW, buttonH, 'Reset', 'btn.reset')

  -- 语言选择器在右上角，位于菜单网格上方。
  local langW, langH = 115, 26
  local langX, langY = PANEL_W - 24 - langW, 12
  local langLabel = addText(tree, panel, 'PBZArcs_MenuLangLabel', self:t('label.lang'),
    langX - 94, langY + 2, 86, 22, 14, WHITE, 1)
  if langLabel then
    pcall(function() langLabel.Justification = 1 end)
    self.labels[#self.labels + 1] = { widget = langLabel, id = 'label.lang' }
  end
  self:buildDropdown(panel, tree, {
    key = 'Lang',
    x = langX, y = langY, w = langW, h = langH,
    tip = 'tip.lang',
    -- 选项行来自 languages.ini 和每个文件自己的 lang.name，所以新增一种语言
    -- 只需要一个文件加上在那个列表里的一行。
    optionsFor = function() return Lang.options() end,
    value = function() return self.S.Lang end,
    set = function(value)
      self.S.Lang = value
      self:refreshLanguage()
    end,
    text = function() return Lang.nameFor(self.S.Lang) end,
  })

  -- 预设选择器及其两个按钮，位于语言区的左侧。选项行
  -- 完全按玩家写的样子显示 preset/*.ini 里的名字，而
  -- settings.ini 里保留的值是文件名，所以改名不会丢失对应关系。
  local presetW, smallW, smallGap = 150, 56, 8
  local saveX = langX - 94 - 40 - smallW * 2 - smallGap
  self:buildDropdown(panel, tree, {
    key = 'Preset',
    x = saveX - 10 - presetW, y = langY, w = presetW, h = langH,
    up = true,
    tip = 'tip.preset',
    optionsFor = function()
      local options = {}
      for _, preset in ipairs(self:presetList()) do
        options[#options + 1] = { value = preset.key, label = preset.name }
      end
      return options
    end,
    value = function() return self.S.Preset end,
    set = function(value) self:applyPreset(value) end,
    text = function() return self:presetName() end,
  })

  local presetButtons = {
    { key = 'PresetSave', id = 'btn.presetSave', tip = 'tip.presetSave', run = 'saveCurrentPreset' },
    { key = 'PresetNew', id = 'btn.presetNew', tip = 'tip.presetNew', run = 'createPreset' },
  }
  for index, def in ipairs(presetButtons) do
    local button = self:buildButton(panel, tree, saveX + (smallW + smallGap) * (index - 1),
      langY, smallW, langH, def.key, def.id)
    if button then
      button.tip = def.tip
      pcall(function() button.text.Justification = 1 end)
      button.action = function() self[def.run](self) end
    end
  end

  -- 连接非布尔按钮。
  for _, button in ipairs(self.buttons) do
    if button.key == 'Reset' then
      button.tip = 'tip.reset'
      -- 恢复默认回到当前预设存的值，不是出厂默认值。
      button.action = function() self:applyPreset(self.S.Preset) end
    end
  end

  -- 游戏在游玩过程中把 bShowMouseCursor 保持为 false。这个反射标志
  -- 仍然接受直接写入，之后引擎就会画出它正常的箭头
  -- 光标，所以菜单打开期间一直把它置为 true。只有写入失败时
  -- 才退回自己画的十字准星。
  local pc = playerController()
  self.cursorFallback = not (valid(pc) and pcall(function() pc.bShowMouseCursor = true end))
  if self.cursorFallback then
    local cursorH, cursorHSlot = addBorder(tree, canvas, 0, 0, 22, 2, CURSOR, 30)
    local cursorV, cursorVSlot = addBorder(tree, canvas, 0, 0, 2, 22, CURSOR, 31)
    if cursorH and cursorV then
      self.cursorH, self.cursorHSlot = cursorH, cursorHSlot
      self.cursorV, self.cursorVSlot = cursorV, cursorVSlot
      pcall(function()
        cursorH:SetVisibility(3)
        cursorV:SetVisibility(3)
      end)
    end
  end
  self.pointerX, self.pointerY = nil, nil
  if self.callbacks.log then
    self.callbacks.log('cursor: system=' .. tostring(not self.cursorFallback))
  end

  -- 一个铺满整个视口的空按钮，在面板之上、自绘光标
  -- 之下。UMG 会在按下与抬起之间保持鼠标捕获，所以轮询它
  -- 就能把一次点击边沿变成真正的按住；菜单在 Lua 里做命中测试，
  -- 因此它下面的东西不需要接收这个事件。
  self.capture = nil
  local capture = StaticConstructObject(cls(CLASS.button), tree, FName('PBZArcs_MenuCapture_' .. suffix))
  if valid(capture) then
    -- 用零渲染不透明度，而不是染色：SetColorAndOpacity 只会给
    -- 按钮的内容染色，而游戏的 UI 主题给按钮一个实心笔刷，所以
    -- 染色的按钮会把整个屏幕填成白色。跳过绘制过程仍然
    -- 会把该控件留在命中测试路径里，而这正是我们需要它做的。
    pcall(function() capture:SetRenderOpacity(0) end)
    pcall(function()
      capture.bHoverEffectActivated = false
      capture.bPressedEffectActivated = false
      capture.bDisabledEffectActivated = false
    end)
    local captureSlot = canvas:AddChildToCanvas(capture)
    if valid(captureSlot) then
      pcall(function()
        captureSlot:SetAnchors({ Minimum = { X = 0, Y = 0 }, Maximum = { X = 1, Y = 1 } })
        captureSlot:SetOffsets({ Left = 0, Top = 0, Right = 0, Bottom = 0 })
        captureSlot:SetZOrder(20)
      end)
      self.capture = capture
    end
  end

  self:refreshAllRows()
  self:refreshAllButtons()

  -- 遮罩有自己独立的视口控件。放在菜单 canvas 里的话它会处在
  -- 菜单的 z 序上，压住弧形和图标读数，把它们冲淡。
  -- 这里失败最多只是没有遮罩，所以一直留在 pcall 里。
  pcall(function()
    local dimRoot = StaticConstructObject(cls(CLASS.user), gi, FName('PBZArcs_MenuDim_' .. suffix))
    local dimTree = StaticConstructObject(cls(CLASS.tree), dimRoot, FName('PBZArcs_MenuDimTree_' .. suffix))
    if valid(dimRoot) and valid(dimTree) then
      dimRoot.WidgetTree = dimTree
      local dimCanvas = StaticConstructObject(cls(CLASS.canvas), dimTree, FName('PBZArcs_MenuDimCanvas_' .. suffix))
      dimTree.RootWidget = dimCanvas
      local dim = StaticConstructObject(cls(CLASS.border), dimTree, FName('PBZArcs_MenuDimBorder_' .. suffix))
      if valid(dimCanvas) and valid(dim) then
        pcall(function() dim:SetBrushColor({ R = 0, G = 0, B = 0, A = 0.42 }) end)
        pcall(function() dim:SetPadding({ Left = 0, Top = 0, Right = 0, Bottom = 0 }) end)
        local dimSlot = dimCanvas:AddChildToCanvas(dim)
        if valid(dimSlot) then
          pcall(function()
            dimSlot:SetAnchors({ Minimum = { X = 0, Y = 0 }, Maximum = { X = 1, Y = 1 } })
            dimSlot:SetOffsets({ Left = 0, Top = 0, Right = 0, Bottom = 0 })
          end)
          dimRoot:AddToViewport(DIM_Z)
          self.dimRoot = dimRoot
        end
      end
    end
  end)

  if self.S.Debug and self.callbacks.log then
    self.callbacks.log('menu: built ' .. tostring(#self.rows) .. ' rows, capture='
      .. tostring(self.capture ~= nil))
  end
  root:AddToViewport(MENU_Z)
  self.viewportZ = MENU_Z
  root:SetVisibility(0)
  self.root, self.tree, self.canvas = root, tree, canvas
  self.open = true
  self:setInput(true)
  if self.callbacks.log then self.callbacks.log('menu opened') end
  return true
end

function Menu:refreshButtonByKey(key)
  for _, button in ipairs(self.buttons) do
    if button.key == key then
      self:refreshButton(button)
      self:refreshButtonText(button)
      return
    end
  end
end

function Menu:refreshAllButtons()
  for _, button in ipairs(self.buttons) do
    self:refreshButton(button)
    self:refreshButtonText(button)
  end
end

function Menu:refreshRow(row)
  local value = rowGet(self.S, row.def)
  local frac = (value - row.def.min) / math.max(0.0001, row.def.max - row.def.min)
  frac = math.max(0, math.min(1, frac))
  pcall(function() row.fillSlot:SetSize({ X = math.max(1, SLIDER_W * frac), Y = 6 }) end)
  pcall(function() row.handleSlot:SetPosition({ X = row.sliderX + SLIDER_W * frac - 4, Y = row.y + 4 }) end)
  pcall(function() row.value:SetText(FText(formatValue(row.def, value))) end)
end

function Menu:refreshAllRows()
  for _, row in ipairs(self.rows) do self:refreshRow(row) end
end

---------------------------------------------------------------------------------------------------
-- 悬停提示与中键重置

-- 按提示文本在字号 12 下的实际绘制量测：一个拉丁字符约 7.4 slate 宽，
-- 一个中文字符约 14.5（三个字节，每个 4.85）。
local TIP_ASCII, TIP_CJK_BYTE = 7.4, 4.85

local function textWidth(text)
  local ascii = select(2, text:gsub('[\1-\127]', ''))
  local high = #text - ascii
  return ascii * TIP_ASCII + high * TIP_CJK_BYTE
end

-- 把提示硬拆成每行最多 `budget` slate 像素的多行。拉丁单词保持
-- 完整；中文可以在任意处断开。最宽的那一行就是框最终的宽度。
local function breakLines(text, budget)
  local tokens = {}
  local i, n = 1, #text
  while i <= n do
    local byte = text:byte(i)
    if byte == 32 then
      tokens[#tokens + 1] = { text = ' ', width = TIP_ASCII }
      i = i + 1
    elseif byte < 128 then
      local j = i
      while j <= n and text:byte(j) ~= 32 and text:byte(j) < 128 do j = j + 1 end
      local word = text:sub(i, j - 1)
      tokens[#tokens + 1] = { text = word, width = #word * TIP_ASCII }
      i = j
    else
      local length = byte >= 240 and 4 or (byte >= 224 and 3 or 2)
      tokens[#tokens + 1] = { text = text:sub(i, i + length - 1), width = length * TIP_CJK_BYTE }
      i = i + length
    end
  end
  local lines, line, width = {}, '', 0
  for _, token in ipairs(tokens) do
    if line ~= '' and width + token.width > budget then
      lines[#lines + 1] = line
      if token.text == ' ' then
        line, width = '', 0
      else
        line, width = token.text, token.width
      end
    else
      line = line .. token.text
      width = width + token.width
    end
  end
  if line ~= '' then lines[#lines + 1] = line end
  return table.concat(lines, '\n'), math.max(1, #lines)
end

function Menu:refreshTooltip(tipKey)
  if tipKey == self.tipKey then return end
  self.tipKey = tipKey
  if not valid(self.tipRoot) then return end
  local text = tipKey ~= nil and self:t(tipKey) or nil
  if text == nil or text == '' or text == tipKey then
    pcall(function() self.tipRoot:SetVisibility(1) end)
    return
  end
  local body, count = breakLines(text, TIP_WRAP)
  pcall(function() self.tipText:SetText(FText(body)) end)
  local widest = 0
  for line in body:gmatch('[^\n]+') do
    widest = math.max(widest, textWidth(line))
  end
  self.tipW = math.floor(widest) + 18
  self.tipH = count * 19 + 13
  pcall(function() self.tipRoot:SetVisibility(3) end)
end

function Menu:placeTooltip(lx, ly)
  if self.tipKey == nil or not valid(self.tipRoot) then return end
  local w, h = self.tipW or 240, self.tipH or 30
  local tx, ty = lx + 18, ly + 18
  if tx + w > PANEL_W - 8 then tx = math.max(8, lx - w - 12) end
  if ty + h > PANEL_H - 8 then ty = math.max(8, ly - h - 12) end
  pcall(function() self.tipRoot:SetRenderTranslation({ X = tx, Y = ty }) end)
end

-- 指针下的滑块行。标签算作该行的一部分，
-- 另一列和页边距不算。
function Menu:rowAtMouse()
  local x, y = self.mouseX, self.mouseY
  if x == nil or y == nil then return nil end
  local lx, ly = x - self.panelX, y - self.panelY
  for _, row in ipairs(self.rows) do
    if ly >= row.y and ly <= row.y + ROW_H
      and lx >= row.labelX and lx <= row.valueX + 54 then
      return row
    end
  end
  return nil
end

function Menu:resetRow(row)
  -- 单行回到当前预设保存的值，也就是 Reset 按钮
  -- 对所有行做的事；内置默认值只用来顶替
  -- 预设文件早于其存在的那个键。
  local preset = Config.presetByKey(self:presetList(), self.S.Preset)
  local default = preset and preset.values and preset.values[row.def.key]
  if default == nil then default = Config.DEFAULTS[row.def.key] end
  if default == nil then return end
  if row.def.colour then
    -- 三个通道滑块对应同一个颜色，所以任意一个都会重置全部三个。
    self.S[row.def.key] = Config.normalizeHex(default, self.S[row.def.key])
  else
    rowSet(self.S, row.def, tonumber(default) or row.def.min)
  end
  for _, other in ipairs(self.rows) do
    if other.def.key == row.def.key then self:refreshRow(other) end
  end
  self:changed(row.def.key)
end

function Menu:middleClick()
  if not self.open then return false end
  for _, dd in ipairs(self.dropdowns or {}) do
    if dd.open then return false end
  end
  local row = self:rowAtMouse()
  if row == nil then return false end
  self:resetRow(row)
  return true
end

function Menu:refreshLanguage()
  for _, item in ipairs(self.labels) do
    if item.id then
      pcall(function() item.widget:SetText(FText(self:t(item.id))) end)
    end
  end
  self:refreshAllButtons()
  for _, dd in ipairs(self.dropdowns or {}) do
    if dd.open then self:refreshDropdown(dd) end
  end
  self:refreshTooltip(nil)
end

function Menu:setInput(open)
  local pc = playerController()
  if not valid(pc) then return end
  local lib = StaticFindObject('/Script/UMG.Default__WidgetBlueprintLibrary')
  if valid(lib) then
    if open then
      local ok = pcall(function() lib:SetInputMode_UIOnlyEx(pc, self.root, 0, false) end)
      if not ok then
        pcall(function() lib:SetInputMode_GameAndUIEx(pc, self.root, 0, false, false) end)
      end
    else
      pcall(function() lib:SetInputMode_GameOnly(pc, false) end)
    end
  end
  pcall(function() pc.bShowMouseCursor = open end)
  if self.callbacks.log and self.S.Debug then
    local ok, shown = pcall(function() return pc.bShowMouseCursor end)
    self.callbacks.log('cursor: input=' .. tostring(open) .. ' pc.bShowMouseCursor=' .. tostring(ok and shown))
  end
end

function Menu:mouse()
  local pc = playerController()
  if not valid(pc) then return nil end
  local world = prop(pc, 'GetWorld') and pc:GetWorld() or nil
  local lib = layoutLibrary()
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

---------------------------------------------------------------------------------------------------
-- 按钮按住状态。UE4SS 的按键绑定只在按下沿触发一次，所以「按钮是否
-- 还按着」必须从引擎获取：捕获按钮负责报告鼠标左键，
-- 其余按键则尝试 IsInputKeyDown。两者在这个版本里都可能不可用，
-- 那样 held() 返回 nil，调用方保持自己的兜底方案。

local KEY_NAMES = { lmb = 'LeftMouseButton', rmb = 'RightMouseButton', mmb = 'MiddleMouseButton' }
local fkeyCache = {}

local function fkeyArg(name)
  if fkeyCache[name] ~= nil then return fkeyCache[name] end
  local arg = name
  pcall(function()
    local fname = FName(name)
    if fname ~= nil then arg = { KeyName = fname } end
  end)
  fkeyCache[name] = arg
  return arg
end

function Menu:probeLog(message)
  if not self.S.Debug then return end
  self.probeSeen = self.probeSeen or {}
  if self.probeSeen[message] then return end
  self.probeSeen[message] = true
  if self.callbacks.log then self.callbacks.log(message) end
end

function Menu:keyDown(name)
  if name == nil or self.keyUsable == false then return nil end
  local pc = playerController()
  if not valid(pc) then return nil end
  local arg = fkeyArg(name)
  local ok, down = pcall(function() return pc:IsInputKeyDown(arg) end)
  if not ok and type(arg) == 'table' then
    ok, down = pcall(function() return pc:IsInputKeyDown(arg.KeyName) end)
  end
  if not ok then
    self.keyUsable = false
    self:probeLog('hold detection: IsInputKeyDown unavailable (' .. tostring(down) .. ')')
    return nil
  end
  self.keyUsable = true
  return down == true
end

-- button 为 'lmb' / 'rmb' / 'mmb'。
function Menu:held(button)
  if button == 'lmb' and valid(self.capture) then
    local ok, down = pcall(function() return self.capture:IsPressed() end)
    if ok then return down == true end
  end
  return self:keyDown(KEY_NAMES[button])
end

local HOLD_GRACE = 0.25

-- 拖动进行期间每帧调用一次。按下沿已经证明按钮是按下的，
-- 所以第一个报告出真正「按下」的帧说明这个来源也可以被信任去
-- 报告抬起；如果始终没有，就说明这个版本判断不了，调用方
-- 保持用光标静止来判断的兜底方案。
function Menu:checkHold(state, dt)
  local down = self:held(state.button)
  if state.reliable == nil then
    if down == true then
      state.reliable = true
      self:probeLog('hold ' .. tostring(state.button) .. ': engine reports the button down')
    else
      state.grace = (state.grace or 0) + (tonumber(dt) or 0.016)
      if state.grace >= HOLD_GRACE then
        state.reliable = false
        self:probeLog('hold ' .. tostring(state.button) .. ': no button state, using still cursor')
      end
    end
  end
  if state.reliable == true then return down == true end
  return nil
end

-- 供可拖动的 HUD 读数使用，这样点在面板上的点击永远不会被抢走。
function Menu:hitPanel(x, y)
  if not self.open or x == nil or y == nil then return false end
  local lx, ly = x - self.panelX, y - self.panelY
  return lx >= 0 and lx <= PANEL_W and ly >= 0 and ly <= PANEL_H
end

-- 视口控件没法原地改 z 序，所以把面板摘下再放回去；
-- 行控件在这次往返中会保留下来。
function Menu:setViewportZ(z)
  if self.viewportZ == z or not valid(self.root) then return end
  local ok = pcall(function()
    self.root:RemoveFromParent()
    self.root:AddToViewport(z)
  end)
  -- 失败时置为 nil，让下一次轮询把面板重新放回视口。
  self.viewportZ = ok and z or nil
end

function Menu:applyAt(row, x)
  local frac = (x - (self.panelX + row.sliderX)) / SLIDER_W
  frac = math.max(0, math.min(1, frac))
  local value = row.def.min + frac * (row.def.max - row.def.min)
  rowSet(self.S, row.def, value)
  self:refreshRow(row)
  self:changed(row.def.key)
end

function Menu:click()
  if not self.open then return end
  if self.dragRow ~= nil then
    self.dragRow, self.dragHold = nil, nil
    return
  end
  local x, y = self:mouse()
  if x == nil then return end
  local lx, ly = x - self.panelX, y - self.panelY

  local openDD = nil
  for _, dd in ipairs(self.dropdowns or {}) do
    if dd.open then openDD = dd end
  end
  if openDD then
    for _, item in ipairs(openDD.items or {}) do
      if lx >= item.x and lx <= item.x + item.w and ly >= item.y and ly <= item.y + item.h then
        self:chooseDropdown(openDD, item.value)
        return
      end
    end
    local onButton = openDD.button ~= nil
      and lx >= openDD.button.x and lx <= openDD.button.x + openDD.button.w
      and ly >= openDD.button.y and ly <= openDD.button.y + openDD.button.h
    if not onButton then
      self:closeDropdowns(nil)
      return
    end
  end

  for _, button in ipairs(self.buttons) do
    if lx >= button.x and lx <= button.x + button.w and ly >= button.y and ly <= button.y + button.h then
      if button.action then
        local ok, err = pcall(button.action)
        if not ok and self.callbacks.alert then
          self.callbacks.alert('menu action ' .. tostring(button.key) .. ': ' .. tostring(err))
        end
      end
      return
    end
  end
  for _, row in ipairs(self.rows) do
    if ly >= row.y and ly <= row.y + ROW_H and lx >= row.sliderX - 8 and lx <= row.sliderX + SLIDER_W + 8 then
      self.dragRow = row
      self.dragHold = { button = 'lmb' }
      self.stillTime = 0
      self.lastMoveX, self.lastMoveY = x, y
      self:applyAt(row, x)
      return
    end
  end
end

function Menu:updatePointer(x, y)
  self.mouseX, self.mouseY = x, y
  local lx, ly = x - self.panelX, y - self.panelY
  local moved = self.pointerX == nil
    or math.abs(self.pointerX - x) > 0.01 or math.abs(self.pointerY - y) > 0.01
  if moved and self.cursorH ~= nil then
    self.pointerX, self.pointerY = x, y
    -- 渲染平移会跳过 slot 的 SetPosition 所触发的 canvas 布局。
    -- 光标挂在全屏 canvas 下，因此在整个窗口上都可见。
    local cx, cy = math.floor(x + 0.5), math.floor(y + 0.5)
    local ok = pcall(function()
      self.cursorH:SetRenderTranslation({ X = cx - 11, Y = cy - 1 })
      self.cursorV:SetRenderTranslation({ X = cx - 1, Y = cy - 11 })
    end)
    if not ok then
      pcall(function()
        self.cursorHSlot:SetPosition({ X = cx - 11, Y = cy - 1 })
        self.cursorVSlot:SetPosition({ X = cx - 1, Y = cy - 11 })
      end)
    end
  end
  local inside = lx > 0 and lx < PANEL_W and ly > 0 and ly < PANEL_H

  local hoverRow = nil
  if inside then
    for _, row in ipairs(self.rows) do
      if ly >= row.y and ly <= row.y + ROW_H then
        hoverRow = row
        break
      end
    end
  end
  if hoverRow ~= self.hoverRow then
    self.hoverRow = hoverRow
    if self.hover ~= nil then
      if hoverRow then
        pcall(function()
          self.hoverSlot:SetPosition({ X = 12, Y = hoverRow.y })
          self.hover:SetVisibility(3)
        end)
      else
        pcall(function() self.hover:SetVisibility(1) end)
      end
    end
  end

  local hoverButton = nil
  if inside then
    for _, button in ipairs(self.buttons) do
      if lx >= button.x and lx <= button.x + button.w
        and ly >= button.y and ly <= button.y + button.h then
        hoverButton = button
        break
      end
    end
  end
  if hoverButton ~= self.hoverButton then
    if self.hoverButton ~= nil then
      self.hoverButton.hovered = false
      self:refreshButton(self.hoverButton)
    end
    self.hoverButton = hoverButton
    if hoverButton ~= nil then
      hoverButton.hovered = true
      self:refreshButton(hoverButton)
    end
  end

  -- 同一时间只显示一条提示，位置在指针所在控件之上。打开的下拉框会盖住
  -- 它下面的控件，滑块拖动又占用了指针，所以这两种情况都会把提示藏起来。
  local tipKey = nil
  local dropdownOpen = false
  for _, dd in ipairs(self.dropdowns or {}) do
    if dd.open then dropdownOpen = true; break end
  end
  if inside and not dropdownOpen and self.dragRow == nil then
    if hoverButton ~= nil then
      tipKey = hoverButton.tip
    else
      local row = self:rowAtMouse()
      tipKey = row and row.tip or nil
    end
  end
  self:refreshTooltip(tipKey)
  if tipKey ~= nil then self:placeTooltip(lx, ly) end
end

-- 游戏在游玩过程中会清掉硬件光标。菜单占有输入期间每帧重新
-- 置位，好让正常的箭头跟随鼠标。
function Menu:assertCursor()
  local pc = playerController()
  if not valid(pc) then return end
  -- 在这个版本里 PlayerController:SetShowMouseCursor 没有暴露给 Lua，
  -- 但这个标志本身是反射属性。游戏会清掉它，所以菜单占有
  -- 输入期间一直重新设置。
  local okSet = pcall(function() pc.bShowMouseCursor = true end)
  if self.S.Debug and not self.cursorLogged and self.callbacks.log then
    self.cursorLogged = true
    local okShow, shown = pcall(function() return pc.bShowMouseCursor end)
    self.callbacks.log('cursor assert: set=' .. tostring(okSet)
      .. ' show=' .. tostring(okShow and shown))
  end
end

function Menu:poll(dt, keepLow)
  if not self.open or not valid(self.root) then return end
  self:assertCursor()
  local x, y = self:mouse()
  if x == nil then return end
  self:updatePointer(x, y)
  -- 面板压在读数之上会遮住它们，压在读数之下又收不到
  -- 鼠标，所以只有当指针在面板内时它才升高。图标拖动和
  -- 进行中的滑块拖动会让面板保持原位。
  if self.dragRow == nil and not keepLow then
    self:setViewportZ(self:hitPanel(x, y) and MENU_TOP_Z or MENU_Z)
  end
  if self.dragRow ~= nil then
    if self.dragHold == nil then self.dragHold = { button = 'lmb' } end
    local held = self:checkHold(self.dragHold, dt)
    local moved = self.lastMoveX == nil
      or math.abs(self.lastMoveX - x) > 0.5 or math.abs(self.lastMoveY - y) > 0.5
    if held == false then
      self.dragRow, self.dragHold = nil, nil
      self.lastMoveX, self.lastMoveY = nil, nil
    elseif moved then
      self.lastMoveX, self.lastMoveY = x, y
      self.stillTime = 0
      self:applyAt(self.dragRow, x)
    elseif held == nil and self.dragHold.reliable ~= nil then
      -- 这里没有任何东西报告抬起；光标静止即结束拖动。
      self.stillTime = self.stillTime + (tonumber(dt) or 0.016)
      if self.stillTime > 0.12 then
        self.dragRow, self.dragHold = nil, nil
        self.lastMoveX, self.lastMoveY = nil, nil
      end
    end
  end
end

function Menu:toggle()
  local now = os.clock()
  if now - self.lastToggle < 0.4 then return end
  self.lastToggle = now
  if self.open then
    self:saveSoon(true)
    self:setInput(false)
    self:destroy()
    if self.callbacks.log then self.callbacks.log('menu closed') end
  else
    local ok, err = pcall(function() return self:build() end)
    if not ok or err == false then
      if self.callbacks.alert then self.callbacks.alert('menu build failed: ' .. tostring(err)) end
    end
  end
end

function Menu:destroy()
  if self.root ~= nil and valid(self.root) then
    pcall(function() self.root:RemoveFromParent() end)
  end
  if self.dimRoot ~= nil and valid(self.dimRoot) then
    pcall(function() self.dimRoot:RemoveFromParent() end)
  end
  self.dimRoot = nil
  self.viewportZ = nil
  self.root, self.tree, self.canvas = nil, nil, nil
  self.open = false
  self.dragRow = nil
  self.dragHold = nil
  self.capture = nil
  self.rows, self.buttons, self.labels = {}, {}, {}
  self.hover, self.hoverSlot = nil, nil
  self.cursorH, self.cursorHSlot, self.cursorV, self.cursorVSlot = nil, nil, nil, nil
  self.hoverRow, self.hoverButton = nil, nil
  self.pointerX, self.pointerY = nil, nil
  self.mouseX, self.mouseY = nil, nil
  self.tipRoot, self.tipBg, self.tipBgSlot = nil, nil, nil
  self.tipText, self.tipKey = nil, nil
  self.tipW, self.tipH = nil, nil
  self.dropdowns = {}
  self.cursorLogged = nil
  self.stillTime = 0
  self.lastMoveX, self.lastMoveY = nil, nil
end

return Menu
