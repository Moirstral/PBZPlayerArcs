-- PBZPlayerArcs：默认值、settings.ini 读写与颜色辅助函数。
local Config = {}

local src = debug.getinfo(1, 'S').source:gsub('^@', ''):gsub('\\', '/')
Config.DIR = src:match('^(.*)/[^/]+$') or '.'
Config.INI = Config.DIR .. '/settings.ini'
Config.LOG = Config.DIR .. '/PBZArcs.log'
Config.VERSION = '0.3.0'

-- 预设存放在 Scripts/preset/ 文件夹里，每个预设一个完整的设置文件：
-- preset1.ini、preset2.ini……每个文件在各自的 Preset 行里保存自己的显示名，
-- 而 settings.ini 的 Preset 保存的是预设文件名（不含扩展名），
-- 因此重命名显示名永远不会破坏「当前正在用哪个预设」的对应关系。
Config.PRESET_DIR = Config.DIR .. '/preset'

function Config.presetKey(index)
  return 'preset' .. tostring(index)
end

function Config.presetPath(index)
  return Config.PRESET_DIR .. '/' .. Config.presetKey(index) .. '.ini'
end

local DEFAULTS = {
  -- 当前数值来源的那个 preset/ 里的预设的文件名（不含扩展名）
  Preset = 'preset1',

  -- 跟随
  FollowCharacter = true,
  FollowSmoothing = 0.10,   -- 秒；0 = 瞬间吸附
  FixedAnchorX = 0.50,      -- 仅在 FollowCharacter = false 时使用
  FixedAnchorY = 0.55,
  AnchorHeight = 15,        -- 厘米，位于玩家 actor 原点之上
  AnchorOffsetX = 0,        -- 1080p 基准像素
  AnchorOffsetY = 0,

  -- 弧形几何（1080p 基准像素 / 角度）
  Radius = 195,
  Thickness = 12,
  ArcSpan = 60,
  Segments = 45,
  HpOnLeft = true,
  BrushJitter = 0,

  -- 外观
  BarOpacity = 0.75,
  TrackOpacity = 0.45,
  GhostOpacity = 0.55,
  GhostSpeed = 0.35,        -- 秒
  ShowGhost = true,
  ShowTip = true,
  TipScale = 1.80,
  TipAngle = -15,
  HpColor = '#D6D2C6',      -- 游戏血条为淡银色
  QiColor = '#D9A62E',      -- 游戏杀气条为金色
  TrackColor = '#0A0908',
  WarnColor = '#E0301E',

  -- 低值警告
  WarnThresholdHp = 0.30,
  WarnThresholdQi = 0.25,
  WarnFlashSpeed = 1.80,    -- 赫兹
  WarnFlashAmount = 0.65,

  -- 可见性
  Visibility = 'dynamic',   -- always / hud / dynamic（dynamic = 满条持续 HideDelay 后隐藏，否则跟随 HUD）
  HideDelay = 3.0,          -- 条必须保持满值的秒数，之后 dynamic 才会把它隐藏
  DisplayMode = 'both',     -- both / hp / qi / off

  -- 平面式的药品 / 绝招读数（复制自游戏 HUD）
  MedicineHud = true,
  UltHud = true,
  MedicineHudX = -1,        -- 屏幕像素；-1 = 自动放在底部居中
  MedicineHudY = -1,
  UltHudX = -1,
  UltHudY = -1,
  -- 每个图标在自己组内的位移；0 = 自动布局。
  Med1OffX = 0, Med1OffY = 0,
  Med2OffX = 0, Med2OffY = 0,
  Ult1OffX = 0, Ult1OffY = 0,
  Ult2OffX = 0, Ult2OffY = 0,
  IconScale = 1.0,          -- 决定每个图标、其数字以及它们之间间距的大小
  UltChargeBar = true,      -- 精纯杀气图标本体的充能填充

  -- 原生血条 / 杀气条（游戏自带的左下角条）
  PinHudBars = true,        -- 把两条固定为游戏最初设定的长度
  HudBarWidth = -1,         -- 固定宽度，单位为 slate 像素；-1 = 游戏给这条设定的长度
  HudNumbers = true,        -- 在游戏的条上显示当前 / 最大值；是否固定都能用
  HudNumberStyle = 'center', -- side = 在条的上方 / 下方，center = 在条内部

  -- 按键 / 菜单
  MenuKey = 'F2',
  -- 空表示「尚未选择」：首次运行会用游戏自身的 culture 填入。
  Lang = '',            -- Scripts/lang 下的语言文件名，即一个 culture 名称

  -- 资源
  Texture = '/Game/PBZContent/VFX/SceneFX/UI/Common/Assets/T_UI_Common_InkBar_003.T_UI_Common_InkBar_003',
  InkMaterial = '/Game/PBZContent/VFX/SceneFX/UI/Common/M_UI_InkBar_A_002_Inst2.M_UI_InkBar_A_002_Inst2',
  TipTexture = '/Game/PBZContent/UI/Hud/Art/Hud_Blood_End.Hud_Blood_End',

  -- 墨迹笔画
  StrokeOverlap = 9.5,      -- 每一份笔刷副本绘制多少个段长

  Debug = false,
}
Config.DEFAULTS = DEFAULTS

local ORDER = {
  'Preset',
  'FollowCharacter', 'FollowSmoothing', 'FixedAnchorX', 'FixedAnchorY',
  'AnchorHeight', 'AnchorOffsetX', 'AnchorOffsetY',
  'Radius', 'Thickness', 'ArcSpan', 'Segments', 'HpOnLeft', 'BrushJitter', 'StrokeOverlap',
  'BarOpacity', 'TrackOpacity', 'GhostOpacity', 'GhostSpeed', 'ShowGhost',
  'ShowTip', 'TipScale', 'TipAngle',
  'HpColor', 'QiColor', 'TrackColor', 'WarnColor',
  'WarnThresholdHp', 'WarnThresholdQi', 'WarnFlashSpeed', 'WarnFlashAmount',
  'Visibility', 'HideDelay', 'DisplayMode',
  'MedicineHud', 'UltHud', 'MedicineHudX', 'MedicineHudY', 'UltHudX', 'UltHudY',
  'Med1OffX', 'Med1OffY', 'Med2OffX', 'Med2OffY',
  'Ult1OffX', 'Ult1OffY', 'Ult2OffX', 'Ult2OffY',
  'IconScale', 'UltChargeBar',
  'PinHudBars', 'HudBarWidth', 'HudNumbers', 'HudNumberStyle',
  'MenuKey', 'Lang',
  'Texture', 'InkMaterial', 'TipTexture',
  'Debug',
}
Config.ORDER = ORDER

local function parseBool(v)
  if type(v) == 'boolean' then return v end
  local s = tostring(v or ''):lower()
  return s == 'true' or s == '1' or s == 'yes' or s == 'on'
end
Config.parseBool = parseBool

local function clamp(v, lo, hi)
  if type(v) ~= 'number' or v ~= v then return lo end
  if v < lo then return lo end
  if v > hi then return hi end
  return v
end
Config.clamp = clamp

function Config.copyDefaults()
  local s = {}
  for k, v in pairs(DEFAULTS) do s[k] = v end
  return s
end

function Config.log(message)
  local f = io.open(Config.LOG, 'a')
  if f then
    f:write(os.date('%H:%M:%S ') .. tostring(message) .. '\n')
    f:close()
  end
end

function Config.initLog()
  local f = io.open(Config.LOG, 'r')
  local big = false
  if f then
    local size = f:seek('end') or 0
    big = size > 2 * 1024 * 1024
    f:close()
  end
  if big then
    pcall(os.remove, Config.LOG)
  end
  Config.log('--- PBZPlayerArcs ' .. Config.VERSION .. ' ---')
end

---------------------------------------------------------------------------------------------------
-- 颜色辅助函数。UMG 的 SetColorAndOpacity 接受线性颜色，而 settings.ini 存的是 sRGB 十六进制。

local function srgbToLinear(c)
  c = c / 255
  if c <= 0.04045 then return c / 12.92 end
  return ((c + 0.055) / 1.055) ^ 2.4
end
local function linearToSrgb(c)
  if c <= 0.0031308 then return c * 12.92 end
  return 1.055 * (c ^ (1 / 2.4)) - 0.055
end

function Config.parseHex(value)
  local hex = tostring(value or ''):gsub('^%s*#?', ''):gsub('%s*$', '')
  if #hex == 3 then
    hex = hex:sub(1, 1):rep(2) .. hex:sub(2, 2):rep(2) .. hex:sub(3, 3):rep(2)
  end
  if #hex ~= 6 or hex:find('[^%x]') then return nil end
  return tonumber(hex:sub(1, 2), 16), tonumber(hex:sub(3, 4), 16), tonumber(hex:sub(5, 6), 16)
end

function Config.normalizeHex(value, fallback)
  if Config.parseHex(value) then
    local hex = tostring(value):gsub('^%s*#?', ''):gsub('%s*$', ''):upper()
    if #hex == 3 then
      hex = hex:sub(1, 1):rep(2) .. hex:sub(2, 2):rep(2) .. hex:sub(3, 3):rep(2)
    end
    return '#' .. hex
  end
  return fallback or '#FFFFFF'
end

function Config.hexToLinear(value)
  local r, g, b = Config.parseHex(value)
  if not r then return { R = 1, G = 1, B = 1, A = 1 } end
  return { R = srgbToLinear(r), G = srgbToLinear(g), B = srgbToLinear(b), A = 1 }
end

function Config.lighten(colour, factor)
  local r = clamp((colour.R or 1) * factor, 0, 1)
  local g = clamp((colour.G or 1) * factor, 0, 1)
  local b = clamp((colour.B or 1) * factor, 0, 1)
  return { R = r, G = g, B = b, A = colour.A or 1 }
end

function Config.hexToHsl(value)
  local r, g, b = Config.parseHex(value)
  if not r then return 0, 0, 100 end
  r, g, b = r / 255, g / 255, b / 255
  local mx, mn = math.max(r, g, b), math.min(r, g, b)
  local l = (mx + mn) / 2
  local h, s = 0, 0
  if mx ~= mn then
    local d = mx - mn
    s = (l > 0.5) and (d / (2 - mx - mn)) or (d / (mx + mn))
    if mx == r then h = (g - b) / d + ((g < b) and 6 or 0)
    elseif mx == g then h = (b - r) / d + 2
    else h = (r - g) / d + 4 end
    h = h / 6
  end
  return h * 360, s * 100, l * 100
end

function Config.hslToHex(h, s, l)
  h = ((tonumber(h) or 0) % 360) / 360
  s = clamp(tonumber(s) or 0, 0, 100) / 100
  l = clamp(tonumber(l) or 0, 0, 100) / 100
  local function hue(p, q, t)
    if t < 0 then t = t + 1 end
    if t > 1 then t = t - 1 end
    if t < 1 / 6 then return p + (q - p) * 6 * t end
    if t < 1 / 2 then return q end
    if t < 2 / 3 then return p + (q - p) * (2 / 3 - t) * 6 end
    return p
  end
  local r, g, b
  if s == 0 then
    r, g, b = l, l, l
  else
    local q = (l < 0.5) and (l * (1 + s)) or (l + s - l * s)
    local p = 2 * l - q
    r, g, b = hue(p, q, h + 1 / 3), hue(p, q, h), hue(p, q, h - 1 / 3)
  end
  local function hex(c)
    c = math.floor(clamp(c, 0, 1) * 255 + 0.5)
    return string.format('%02X', c)
  end
  return '#' .. hex(r) .. hex(g) .. hex(b)
end

-- 渲染器没用到，但为以后做叠加层保留。
function Config.linearToHex(colour)
  local function hex(c)
    c = math.floor(clamp(linearToSrgb(clamp(c or 0, 0, 1)), 0, 1) * 255 + 0.5)
    return string.format('%02X', c)
  end
  return '#' .. hex(colour.R) .. hex(colour.G) .. hex(colour.B)
end

---------------------------------------------------------------------------------------------------
-- 读取 / 保存

function Config.sanitize(S)
  S.FollowSmoothing = clamp(tonumber(S.FollowSmoothing) or 0.10, 0, 1.0)
  S.FixedAnchorX = clamp(tonumber(S.FixedAnchorX) or 0.5, 0, 1)
  S.FixedAnchorY = clamp(tonumber(S.FixedAnchorY) or 0.55, 0, 1)
  S.AnchorHeight = clamp(tonumber(S.AnchorHeight) or DEFAULTS.AnchorHeight, -100, 300)
  S.AnchorOffsetX = clamp(tonumber(S.AnchorOffsetX) or 0, -600, 600)
  S.AnchorOffsetY = clamp(tonumber(S.AnchorOffsetY) or 0, -600, 600)
  S.Radius = clamp(math.floor((tonumber(S.Radius) or DEFAULTS.Radius) + 0.5), 60, 600)
  S.Thickness = clamp(math.floor((tonumber(S.Thickness) or DEFAULTS.Thickness) + 0.5), 2, 30)
  S.ArcSpan = clamp(tonumber(S.ArcSpan) or DEFAULTS.ArcSpan, 30, 180)
  S.Segments = clamp(math.floor((tonumber(S.Segments) or DEFAULTS.Segments) + 0.5), 8, 96)
  S.BrushJitter = clamp(tonumber(S.BrushJitter) or DEFAULTS.BrushJitter, 0, 1)
  S.StrokeOverlap = clamp(tonumber(S.StrokeOverlap) or DEFAULTS.StrokeOverlap, 1, 24)
  S.BarOpacity = clamp(tonumber(S.BarOpacity) or DEFAULTS.BarOpacity, 0.05, 1)
  S.TrackOpacity = clamp(tonumber(S.TrackOpacity) or 0.45, 0, 1)
  S.GhostOpacity = clamp(tonumber(S.GhostOpacity) or 0.55, 0, 1)
  S.GhostSpeed = clamp(tonumber(S.GhostSpeed) or 0.35, 0.01, 3.0)
  S.TipScale = clamp(tonumber(S.TipScale) or DEFAULTS.TipScale, 0.3, 3)
  S.TipAngle = clamp(tonumber(S.TipAngle) or -15, -90, 90)
  S.WarnThresholdHp = clamp(tonumber(S.WarnThresholdHp) or 0.30, 0, 1)
  S.WarnThresholdQi = clamp(tonumber(S.WarnThresholdQi) or 0.25, 0, 1)
  S.WarnFlashSpeed = clamp(tonumber(S.WarnFlashSpeed) or 1.8, 0.2, 8)
  S.WarnFlashAmount = clamp(tonumber(S.WarnFlashAmount) or 0.65, 0, 1)
  S.DisplayMode = tostring(S.DisplayMode or 'both'):lower()
  if S.DisplayMode ~= 'hp' and S.DisplayMode ~= 'qi' and S.DisplayMode ~= 'off' then
    S.DisplayMode = 'both'
  end
  S.Visibility = tostring(S.Visibility or 'dynamic'):lower()
  if S.Visibility ~= 'always' and S.Visibility ~= 'hud' then S.Visibility = 'dynamic' end
  S.HideDelay = clamp(tonumber(S.HideDelay) or DEFAULTS.HideDelay, 0, 30)
  S.MedicineHudX = clamp(tonumber(S.MedicineHudX) or -1, -10000, 20000)
  S.MedicineHudY = clamp(tonumber(S.MedicineHudY) or -1, -10000, 20000)
  S.UltHudX = clamp(tonumber(S.UltHudX) or -1, -10000, 20000)
  S.UltHudY = clamp(tonumber(S.UltHudY) or -1, -10000, 20000)
  local ENTRIES = { 'Med1', 'Med2', 'Ult1', 'Ult2' }
  for _, id in ipairs(ENTRIES) do
    S[id .. 'OffX'] = clamp(math.floor((tonumber(S[id .. 'OffX']) or 0) + 0.5), -800, 800)
    S[id .. 'OffY'] = clamp(math.floor((tonumber(S[id .. 'OffY']) or 0) + 0.5), -800, 800)
  end
  S.IconScale = clamp(tonumber(S.IconScale) or DEFAULTS.IconScale, 0.5, 3)
  -- -1 表示「读一次条的宽度并沿用」；其他值就是宽度。
  S.HudBarWidth = math.floor(clamp(tonumber(S.HudBarWidth) or -1, -1, 4000) + 0.5)
  S.HpColor = Config.normalizeHex(S.HpColor, DEFAULTS.HpColor)
  S.QiColor = Config.normalizeHex(S.QiColor, DEFAULTS.QiColor)
  S.TrackColor = Config.normalizeHex(S.TrackColor, DEFAULTS.TrackColor)
  S.WarnColor = Config.normalizeHex(S.WarnColor, DEFAULTS.WarnColor)
  -- 语言是 Scripts/lang 下的一个文件，以 culture 命名，所以只保留
  -- 文件名能容纳的字符。空值保持为空：它表示「尚未选择」。
  local lang = tostring(S.Lang or ''):gsub('[^%w_%.%-]', '')
  if #lang > 24 then lang = lang:sub(1, 24) end
  S.Lang = lang
  -- 预设文件名按原样保留：只做去空白和长度截断。
  local preset = tostring(S.Preset or DEFAULTS.Preset):gsub('^%s+', ''):gsub('%s+$', '')
  if preset == '' then preset = DEFAULTS.Preset end
  S.Preset = preset:sub(1, 48)
  S.MenuKey = tostring(S.MenuKey or 'F2'):upper()
  S.Texture = tostring(S.Texture or DEFAULTS.Texture)
  S.InkMaterial = tostring(S.InkMaterial or DEFAULTS.InkMaterial)
  S.TipTexture = tostring(S.TipTexture or DEFAULTS.TipTexture)
  S.FollowCharacter = parseBool(S.FollowCharacter)
  S.HpOnLeft = parseBool(S.HpOnLeft)
  S.ShowGhost = parseBool(S.ShowGhost)
  S.ShowTip = parseBool(S.ShowTip)
  S.MedicineHud = parseBool(S.MedicineHud)
  S.UltHud = parseBool(S.UltHud)
  S.PinHudBars = parseBool(S.PinHudBars)
  S.HudNumbers = parseBool(S.HudNumbers)
  S.HudNumberStyle = tostring(S.HudNumberStyle or DEFAULTS.HudNumberStyle):lower()
  if S.HudNumberStyle ~= 'center' then S.HudNumberStyle = 'side' end
  S.Debug = parseBool(S.Debug)
  return S
end

-- 旧文件用了两个布尔值。首次写入新键时把它们转换过来。
local LEGACY_VISIBILITY = { FollowHud = true, ShowInCombat = true }

-- 已不存在的功能。下次写入文件时这些行会被丢弃，
-- 这样旧的 settings.ini 或预设不会一直保留它们的痕迹。
local RETIRED_KEYS = { Enabled = true, ToggleKey = true }

-- settings.ini 与预设文件共用：读取已知的键，并把每个值
-- 转换成其默认值所属的类型。文件不存在时返回 nil。
local function readValues(path)
  local values, legacy = {}, {}
  local f = io.open(path, 'r')
  if not f then return nil, legacy end
  for line in f:lines() do
    local key, value = line:match('^%s*([%w_]+)%s*=%s*(.-)%s*$')
    if key and value ~= '' then
      if LEGACY_VISIBILITY[key] then
        legacy[key] = parseBool(value)
      elseif DEFAULTS[key] ~= nil then
        local default = DEFAULTS[key]
        if type(default) == 'boolean' then
          values[key] = parseBool(value)
        elseif type(default) == 'number' then
          values[key] = tonumber(value) or default
        else
          values[key] = value
        end
      end
    end
  end
  f:close()
  return values, legacy
end

local function hasLanguageFile(code)
  local file = io.open(Config.DIR .. '/lang/' .. code .. '.ini', 'r')
  if file == nil then return false end
  file:close()
  return true
end

-- 游戏自身运行所用的 culture。它同时也是语言文件的名字，
-- 因此直接照用。游戏按 BCP 47 的方式命名 culture，所以英语可能
-- 返回 "en" 或 "en-US"；当没有文件带完整标签时，只再试语言部分，
-- 这样就不需要一张查找表。
function Config.systemLanguage()
  local okLib, lib = pcall(function()
    return StaticFindObject('/Script/Engine.Default__KismetInternationalizationLibrary')
  end)
  if not okLib or lib == nil then return '' end
  local okCulture, culture = pcall(function() return lib:GetCurrentCulture() end)
  if not okCulture or culture == nil then return '' end
  local okText, text = pcall(function() return culture:ToString() end)
  if not okText or type(text) ~= 'string' then return '' end
  text = text:gsub('[^%w_%.%-]', '')
  if text == '' then return '' end
  if hasLanguageFile(text) then return text end
  local base = text:match('^([^%-_]+)')
  if base ~= nil and base ~= '' and base ~= text and hasLanguageFile(base) then
    return base
  end
  return ''
end

function Config.load()
  local S = Config.copyDefaults()
  local values, legacy = readValues(Config.INI)
  if values then
    for key, value in pairs(values) do S[key] = value end
    -- 在数字有独立开关之前，它们是随固定一起开启的，因此
    -- 只打开固定、没提到数字的文件仍然会显示数字。
    if values.HudNumbers == nil and S.PinHudBars then S.HudNumbers = true end
    if values.Visibility == nil then
      if legacy.ShowInCombat then S.Visibility = 'dynamic'
      elseif legacy.FollowHud then S.Visibility = 'hud'
      else S.Visibility = 'always' end
    end
  end
  Config.sanitize(S)
  -- 还没选语言：这是首次使用。取游戏正在用的那个，
  -- 并让调用方把它存下来，这样本次之后选择就不再跟随游戏。
  local firstUse = false
  if S.Lang == '' then
    S.Lang = Config.systemLanguage()
    firstUse = S.Lang ~= ''
  end
  return S, firstUse
end

local function formatValue(value)
  if type(value) == 'boolean' then return value and 'true' or 'false' end
  if type(value) == 'number' then return string.format('%.4g', value) end
  return tostring(value)
end

-- 原地重写数值，让文件保留自己的注释、空行和键的顺序。
-- `omit` 给出那些即使文件里已有也不能留下的键。
local function writeValues(path, S, omit)
  local lines, seen = {}, {}
  local f = io.open(path, 'r')
  if f then
    for line in f:lines() do
      local key = line:match('^%s*([%w_]+)%s*=')
      if key and (LEGACY_VISIBILITY[key] or RETIRED_KEYS[key] or (omit ~= nil and omit[key])) then
        -- 丢弃：已被取代、功能已移除，或这个键不该出现在这个文件里
      elseif key and S[key] ~= nil then
        lines[#lines + 1] = key .. ' = ' .. formatValue(S[key])
        seen[key] = true
      else
        lines[#lines + 1] = line
      end
    end
    f:close()
  end
  if #lines == 0 then
    lines[1] = '; PBZPlayerArcs settings'
  end
  for _, key in ipairs(ORDER) do
    if not seen[key] and S[key] ~= nil then
      lines[#lines + 1] = key .. ' = ' .. formatValue(S[key])
    end
  end
  local out = io.open(path, 'w')
  if not out then
    Config.log('cannot write ' .. path)
    return false
  end
  out:write(table.concat(lines, '\n') .. '\n')
  out:close()
  return true
end

function Config.save(S)
  return writeValues(Config.INI, S)
end

---------------------------------------------------------------------------------------------------
-- 预设

local PRESET_MAX = 64

-- 文件靠从 preset1.ini 往上数来找，遇到第一个没有文件的编号就停，
-- 因此不需要列目录。key 是文件名（不含扩展名），也是 settings.ini
-- 里存的值；name 是该文件自己 Preset 行里保存的显示文本。
-- 没有 Preset 行的文件显示为 预设 N。
function Config.listPresets()
  local list = {}
  for index = 1, PRESET_MAX do
    local values = readValues(Config.presetPath(index))
    if values == nil then break end
    local name = tostring(values.Preset or '')
    if name == '' then name = '预设 ' .. index end
    list[#list + 1] = { index = index, key = Config.presetKey(index), name = name, values = values }
  end
  return list
end

function Config.presetByKey(list, key)
  for _, preset in ipairs(list) do
    if preset.key == key then return preset end
  end
  return nil
end

-- 新预设取第一个空出的编号，因此即使中间有文件被删掉，
-- 它的显示名也会接着 预设 N 的顺序往下排。
function Config.nextPresetSlot(list)
  local taken = {}
  for _, preset in ipairs(list) do taken[preset.index] = true end
  local index = 1
  while taken[index] do index = index + 1 end
  return { index = index, key = Config.presetKey(index), name = '预设 ' .. index }
end

-- 把当前数值存成一个预设。Preset 行始终保存这个文件
-- 自己的显示名，而不是当前恰好选中的那个预设。语言属于
-- 玩家而不属于预设，所以既不写入也不保留。
function Config.savePreset(preset, S)
  local copy = {}
  for key, value in pairs(S) do copy[key] = value end
  copy.Preset = preset.name
  copy.Lang = nil
  return writeValues(Config.presetPath(preset.index), copy, { Lang = true })
end

return Config
