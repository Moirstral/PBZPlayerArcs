-- PBZPlayerArcs：默认值、settings.ini 读写与颜色辅助函数。
local Config = {}

local src = debug.getinfo(1, 'S').source:gsub('^@', ''):gsub('\\', '/')
Config.DIR = src:match('^(.*)/[^/]+$') or '.'
Config.INI = Config.DIR .. '/settings.ini'
Config.LOG = Config.DIR .. '/PBZArcs.log'
Config.VERSION = '0.4.0'

-- 预设存放在 Scripts/preset/ 文件夹里，每个预设一个差异文件：
-- preset1.ini、preset2.ini……只写与默认值不同的键，没写的键一律取
-- DEFAULTS。每个文件在各自的 Preset 行里保存自己的显示名，
-- 而 settings.ini 的 Preset 保存的是预设文件名（不含扩展名），
-- 因此重命名显示名永远不会破坏「当前正在用哪个预设」的对应关系。
Config.PRESET_DIR = Config.DIR .. '/preset'

function Config.presetKey(index)
  return 'preset' .. tostring(index)
end

function Config.presetPath(index)
  return Config.PRESET_DIR .. '/' .. Config.presetKey(index) .. '.ini'
end

-- 唯一的默认值清单：键顺序就是 settings.ini / 预设文件的写入顺序。
-- 新增设置只在这里加一行：DEFAULTS 与 ORDER 都由 FIELDS 生成，
-- sanitize 的兜底值也统一从 DEFAULTS 取，不再各自维护一份字面量。
local FIELDS = {
  -- 当前数值来源的那个 preset/ 里的预设的文件名（不含扩展名）
  { 'Preset', 'preset1' },
  -- 跟随
  { 'FollowCharacter', true },
  { 'FollowSmoothing', 0.10 },    -- 秒；0 = 瞬间吸附
  { 'FixedAnchorX', 0.50 },    -- 仅在 FollowCharacter = false 时使用
  { 'FixedAnchorY', 0.55 },
  { 'AnchorHeight', 15 },    -- 厘米，位于玩家 actor 原点之上
  { 'AnchorOffsetX', 0 },    -- 1080p 基准像素
  { 'AnchorOffsetY', 0 },
  -- 弧形几何（1080p 基准像素 / 角度）
  { 'Radius', 195 },
  { 'Thickness', 12 },
  { 'ArcSpan', 60 },
  { 'Segments', 45 },
  { 'HpOnLeft', true },
  { 'BrushJitter', 0 },
  -- 墨迹笔画
  { 'StrokeOverlap', 9.5 },    -- 每一份笔刷副本绘制多少个段长
  -- 外观
  { 'BarOpacity', 0.75 },
  { 'TrackOpacity', 0.45 },
  { 'GhostOpacity', 0.55 },
  { 'GhostSpeed', 0.35 },    -- 秒
  { 'ShowGhost', true },
  { 'ShowTip', true },
  { 'TipScale', 1.80 },
  { 'TipAngle', -15 },
  { 'HpColor', '#D6D2C6' },    -- 游戏血条为淡银色
  { 'QiColor', '#D9A62E' },    -- 游戏杀气条为金色
  { 'TrackColor', '#0A0908' },
  { 'WarnColor', '#E0301E' },
  -- 低值警告
  { 'WarnThresholdHp', 0.30 },
  { 'WarnThresholdQi', 0.25 },
  { 'WarnFlashSpeed', 1.80 },    -- 赫兹
  { 'WarnFlashAmount', 0.65 },
  -- 可见性
  { 'Visibility', 'dynamic' },    -- hud / dynamic（dynamic = 满条持续 HideDelay 后隐藏，否则跟随 HUD）
  { 'HideDelay', 3.0 },    -- 条必须保持满值的秒数，之后 dynamic 才会把它隐藏
  { 'DisplayMode', 'both' },    -- both / hp / qi / off
  -- 平面式的药品 / 绝招读数（复制自游戏 HUD）
  { 'MedicineHud', true },
  { 'UltHud', true },
  { 'MedicineHudX', -1 },    -- 屏幕像素；-1 = 自动放在底部居中
  { 'MedicineHudY', -1 },
  { 'UltHudX', -1 },
  { 'UltHudY', -1 },
  { 'Med1OffX', 0 },
  { 'Med1OffY', 0 },
  { 'Med2OffX', 0 },
  { 'Med2OffY', 0 },
  { 'Ult1OffX', 0 },
  { 'Ult1OffY', 0 },
  { 'Ult2OffX', 0 },
  { 'Ult2OffY', 0 },
  { 'IconScale', 1.0 },    -- 决定每个图标、其数字以及它们之间间距的大小
  { 'UltChargeBar', true },    -- 精纯杀气图标本体的充能填充
  -- 原生血条 / 杀气条（游戏自带的左下角条）
  -- pin = 固定为游戏最初设定的长度 / dynamic = 随上限变长（游戏原本的样子）
  -- hide = 整条隐藏，连底图一起；只影响游戏画的条，本模块的读数照旧
  { 'NativeBars', 'pin' },
  { 'HudBarWidth', -1 },    -- 固定宽度，单位为 slate 像素；-1 = 游戏给这条设定的长度
  { 'HudNumbers', true },    -- 在游戏的条上显示当前 / 最大值；是否固定都能用
  { 'HudNumberStyle', 'center' },    -- side = 在条的上方 / 下方，center = 在条内部
  -- 按键 / 菜单
  { 'MenuKey', 'F2' },
  { 'Lang', '' },    -- Scripts/lang 下的语言文件名，即一个 culture 名称
  -- 资源
  { 'Texture', '/Game/PBZContent/VFX/SceneFX/UI/Common/Assets/T_UI_Common_InkBar_003.T_UI_Common_InkBar_003' },
  { 'InkMaterial', '/Game/PBZContent/VFX/SceneFX/UI/Common/M_UI_InkBar_A_002_Inst2.M_UI_InkBar_A_002_Inst2' },
  { 'TipTexture', '/Game/PBZContent/UI/Hud/Art/Hud_Blood_End.Hud_Blood_End' },
  -- 调试
  { 'Debug', false },
}
Config.FIELDS = FIELDS

local DEFAULTS, ORDER = {}, {}
for _, field in ipairs(FIELDS) do
  DEFAULTS[field[1]] = field[2]
  ORDER[#ORDER + 1] = field[1]
end
Config.DEFAULTS = DEFAULTS
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

-- 数值兜底统一走 DEFAULTS，不再给每个键各写一份默认字面量。
-- round = true 时先四舍五入再夹到区间，顺序与原实现一致。
local function ranged(S, key, lo, hi, round)
  local n = tonumber(S[key]) or DEFAULTS[key]
  if round then n = math.floor(n + 0.5) end
  return clamp(n, lo, hi)
end

function Config.copyDefaults()
  local s = {}
  for k, v in pairs(DEFAULTS) do s[k] = v end
  return s
end

-- 日志句柄常驻复用：原来每条日志都 io.open('a') / write / close，
-- Debug 打开时一帧能写多条，全是重复的系统调用。写完立即 flush，
-- 外部查看日志仍能看到最新内容，语义与逐条 close 一致。
local logHandle = nil

function Config.closeLog()
  if logHandle then
    pcall(function() logHandle:close() end)
    logHandle = nil
  end
end

function Config.log(message)
  if logHandle == nil then
    logHandle = io.open(Config.LOG, 'a')
  end
  local f = logHandle
  if f then
    local ok = pcall(function()
      f:write(os.date('%H:%M:%S ') .. tostring(message) .. '\n')
      f:flush()
    end)
    if not ok then Config.closeLog() end
  end
end

function Config.initLog()
  -- 可能要删掉超大日志，先放开句柄，否则 Windows 上文件删不掉。
  Config.closeLog()
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
  S.FollowSmoothing = ranged(S, 'FollowSmoothing', 0, 1.0)
  S.FixedAnchorX = ranged(S, 'FixedAnchorX', 0, 1)
  S.FixedAnchorY = ranged(S, 'FixedAnchorY', 0, 1)
  S.AnchorHeight = ranged(S, 'AnchorHeight', -100, 300)
  S.AnchorOffsetX = ranged(S, 'AnchorOffsetX', -600, 600)
  S.AnchorOffsetY = ranged(S, 'AnchorOffsetY', -600, 600)
  S.Radius = ranged(S, 'Radius', 60, 600, true)
  S.Thickness = ranged(S, 'Thickness', 2, 30, true)
  S.ArcSpan = ranged(S, 'ArcSpan', 30, 180)
  S.Segments = ranged(S, 'Segments', 8, 96, true)
  S.BrushJitter = ranged(S, 'BrushJitter', 0, 1)
  S.StrokeOverlap = ranged(S, 'StrokeOverlap', 1, 24)
  S.BarOpacity = ranged(S, 'BarOpacity', 0.05, 1)
  S.TrackOpacity = ranged(S, 'TrackOpacity', 0, 1)
  S.GhostOpacity = ranged(S, 'GhostOpacity', 0, 1)
  S.GhostSpeed = ranged(S, 'GhostSpeed', 0.01, 3.0)
  S.TipScale = ranged(S, 'TipScale', 0.3, 3)
  S.TipAngle = ranged(S, 'TipAngle', -90, 90)
  S.WarnThresholdHp = ranged(S, 'WarnThresholdHp', 0, 1)
  S.WarnThresholdQi = ranged(S, 'WarnThresholdQi', 0, 1)
  S.WarnFlashSpeed = ranged(S, 'WarnFlashSpeed', 0.2, 8)
  S.WarnFlashAmount = ranged(S, 'WarnFlashAmount', 0, 1)
  S.DisplayMode = tostring(S.DisplayMode or DEFAULTS.DisplayMode):lower()
  if S.DisplayMode ~= 'hp' and S.DisplayMode ~= 'qi' and S.DisplayMode ~= 'off' then
    S.DisplayMode = DEFAULTS.DisplayMode
  end
  S.Visibility = tostring(S.Visibility or DEFAULTS.Visibility):lower()
  if S.Visibility ~= 'hud' then S.Visibility = DEFAULTS.Visibility end
  S.HideDelay = ranged(S, 'HideDelay', 0, 30)
  S.MedicineHudX = ranged(S, 'MedicineHudX', -10000, 20000)
  S.MedicineHudY = ranged(S, 'MedicineHudY', -10000, 20000)
  S.UltHudX = ranged(S, 'UltHudX', -10000, 20000)
  S.UltHudY = ranged(S, 'UltHudY', -10000, 20000)
  local ENTRIES = { 'Med1', 'Med2', 'Ult1', 'Ult2' }
  for _, id in ipairs(ENTRIES) do
    S[id .. 'OffX'] = ranged(S, id .. 'OffX', -800, 800, true)
    S[id .. 'OffY'] = ranged(S, id .. 'OffY', -800, 800, true)
  end
  S.IconScale = ranged(S, 'IconScale', 0.5, 3)
  -- -1 表示「读一次条的宽度并沿用」；其他值就是宽度。
  S.HudBarWidth = math.floor(ranged(S, 'HudBarWidth', -1, 4000) + 0.5)
  S.HpColor = Config.normalizeHex(S.HpColor, DEFAULTS.HpColor)
  S.QiColor = Config.normalizeHex(S.QiColor, DEFAULTS.QiColor)
  S.TrackColor = Config.normalizeHex(S.TrackColor, DEFAULTS.TrackColor)
  S.WarnColor = Config.normalizeHex(S.WarnColor, DEFAULTS.WarnColor)
  -- 语言是 Scripts/lang 下的一个文件，以 culture 命名，所以只保留
  -- 文件名能容纳的字符。空值保持为空：它表示「尚未选择」。
  local lang = tostring(S.Lang or DEFAULTS.Lang):gsub('[^%w_%.%-]', '')
  if #lang > 24 then lang = lang:sub(1, 24) end
  S.Lang = lang
  -- 预设文件名按原样保留：只做去空白和长度截断。
  local preset = tostring(S.Preset or DEFAULTS.Preset):gsub('^%s+', ''):gsub('%s+$', '')
  if preset == '' then preset = DEFAULTS.Preset end
  S.Preset = preset:sub(1, 48)
  S.MenuKey = tostring(S.MenuKey or DEFAULTS.MenuKey):upper()
  S.Texture = tostring(S.Texture or DEFAULTS.Texture)
  S.InkMaterial = tostring(S.InkMaterial or DEFAULTS.InkMaterial)
  S.TipTexture = tostring(S.TipTexture or DEFAULTS.TipTexture)
  S.FollowCharacter = parseBool(S.FollowCharacter)
  S.HpOnLeft = parseBool(S.HpOnLeft)
  S.ShowGhost = parseBool(S.ShowGhost)
  S.ShowTip = parseBool(S.ShowTip)
  S.MedicineHud = parseBool(S.MedicineHud)
  S.UltHud = parseBool(S.UltHud)
  S.NativeBars = tostring(S.NativeBars or DEFAULTS.NativeBars):lower()
  -- 'dynamic' 与 'hide' 之外的一律当成默认的 pin。
  if S.NativeBars ~= 'dynamic' and S.NativeBars ~= 'hide' then
    S.NativeBars = DEFAULTS.NativeBars
  end
  S.HudNumbers = parseBool(S.HudNumbers)
  S.HudNumberStyle = tostring(S.HudNumberStyle or DEFAULTS.HudNumberStyle):lower()
  -- 'side' 是 center 之外的另一个合法枚举值，不是默认值。
  if S.HudNumberStyle ~= 'center' then S.HudNumberStyle = 'side' end
  S.Debug = parseBool(S.Debug)
  return S
end

-- 旧文件用了两个布尔值。首次写入新键时把它们转换过来。
local LEGACY_VISIBILITY = { FollowHud = true, ShowInCombat = true }

-- 原生条以前是布尔开关：PinHudBars = true 就是固定长度。读的时候换成
-- 新的三态 NativeBars，老 settings.ini 和老预设都不用手改。
local LEGACY_NATIVE_BARS_KEY = 'PinHudBars'

-- 已不存在的功能。下次写入文件时这些行会被丢弃，
-- 这样旧的 settings.ini 或预设不会一直保留它们的痕迹。
local RETIRED_KEYS = { Enabled = true, ToggleKey = true, PinHudBars = true }

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
      elseif key == LEGACY_NATIVE_BARS_KEY then
        legacy.NativeBars = parseBool(value) and 'pin' or 'dynamic'
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
  -- 文件里同时写了新键时以新键为准，旧布尔值只是迁移用的。
  if legacy.NativeBars ~= nil and values.NativeBars == nil then
    values.NativeBars = legacy.NativeBars
  end
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
    if values.HudNumbers == nil and S.NativeBars ~= 'dynamic' then S.HudNumbers = true end
    if values.Visibility == nil then
      if legacy.ShowInCombat then S.Visibility = 'dynamic'
      elseif legacy.FollowHud then S.Visibility = 'hud'
      else S.Visibility = 'dynamic' end
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
  -- 临时文件 + 原子替换：直接以 'w' 打开原文件，写一半被打断会丢配置。
  -- Windows 的 os.rename 不允许覆盖已存在文件，所以先把原文件挪成 .bak，
  -- 再把临时文件挪到目标；任何一步失败都把 .bak 还回去，最坏留下一份备份。
  local tmp, backup = path .. '.tmp', path .. '.bak'
  local out = io.open(tmp, 'w')
  if not out then
    Config.log('cannot write ' .. tmp)
    return false
  end
  local wrote = pcall(function() out:write(table.concat(lines, '\n') .. '\n') end)
  pcall(function() out:close() end)
  if not wrote then
    pcall(os.remove, tmp)
    Config.log('cannot finish writing ' .. tmp)
    return false
  end
  local old = io.open(path, 'r')
  if old then old:close() end
  pcall(os.remove, backup)
  -- os.rename 失败时返回 nil 而不是抛异常，pcall 的第一个返回值永远是 true，
  -- 必须取它的第二个返回值才能判断成败，否则失败时会误删 .bak 并假装成功。
  local _, backed = pcall(os.rename, path, backup)
  if old and not backed then
    pcall(os.remove, tmp)
    Config.log('cannot back up ' .. path)
    return false
  end
  local _, moved = pcall(os.rename, tmp, path)
  if not moved then
    if old then pcall(os.rename, backup, path) end
    pcall(os.remove, tmp)
    Config.log('cannot replace ' .. path)
    return false
  end
  if old then pcall(os.remove, backup) end
  return true
end

-- 只有预设文件是差异文件：保存时只写「与默认值不同」的键。
-- 用 formatValue 比较而不是直接比值：差异应以写进文件的那串文本为准，
-- 例如 0.4500001 写盘是 0.45，和默认值 0.45 就没有区别。
--   keep 里的键无条件保留（Preset 显示名）；
--   omit 里的键连老文件里的旧行也一并删掉（玩家级配置）。
-- drop 会传给 writeValues 的 omit 参数，于是旧的全量预设保存一次就
-- 自然瘦成差异文件，不需要玩家手工删行。
local function diffValues(S, keep, omit)
  local diff, drop = {}, {}
  for key, value in pairs(S) do
    if keep[key] or DEFAULTS[key] == nil or
       formatValue(value) ~= formatValue(DEFAULTS[key]) then
      diff[key] = value
    else
      drop[key] = true
    end
  end
  for key in pairs(omit) do
    diff[key] = nil
    drop[key] = true
  end
  return diff, drop
end

function Config.save(S)
  -- settings.ini 必须写全键：这是玩家不打开配置界面时唯一的配置入口
  -- （界面打不开、按键失效、无 UI 环境下都要能直接编辑这个文件）。
  -- 它同时也是一份自带注释的完整快照，不要为了省行数改成差异文件。
  return writeValues(Config.INI, S)
end

---------------------------------------------------------------------------------------------------
-- 预设

local PRESET_MAX = 64

-- 玩家级配置：属于玩家本人，不属于任何一套预设。它们只在 settings.ini
-- 里读写，切换 / 保存预设都不会带上它们。
--   Lang      菜单语言（首次使用时按游戏语言自动选）
--   MenuKey   打开菜单的按键（启动时绑定一次，运行中改值不会重新绑定）
--   Preset    当前选中的预设文件名；预设文件里同名的一行是「显示名」，语义不同
-- 读取与写入预设、以及 Menu:applyPreset 都从这里取名单，避免各写一份漏掉某个键。
local PLAYER_KEYS = { Lang = true, MenuKey = true, Preset = true }
Config.PLAYER_KEYS = PLAYER_KEYS

-- 每个预设都「基于默认值」：文件里只写与默认不同的键，读取时先用
-- DEFAULTS 打底、再用文件里的值覆盖。于是出厂 preset1.ini 可以只写显示名，
-- 玩家保存过的全量预设也不会被改动（每个键文件里都有值）。
local function withDefaults(values)
  -- 老预设文件里可能残留 Lang / MenuKey（早期版本保存的是全量快照）。
  -- 直接丢掉：它们不该出现在预设里，更不能覆盖玩家当前设置。
  -- Preset 留着，它在预设文件里是显示名，listPresets 要用。
  values.Lang = nil
  values.MenuKey = nil
  for key, value in pairs(DEFAULTS) do
    if not PLAYER_KEYS[key] and values[key] == nil then
      values[key] = value
    end
  end
  return values
end

-- 文件靠从 preset1.ini 往上数来找，遇到第一个没有文件的编号就停，
-- 因此不需要列目录。key 是文件名（不含扩展名），也是 settings.ini
-- 里存的值；name 是该文件自己 Preset 行里保存的显示文本。
-- 没有 Preset 行的文件显示为 预设 N。
function Config.listPresets()
  local list = {}
  for index = 1, PRESET_MAX do
    local values = readValues(Config.presetPath(index))
    if values == nil then break end
    values = withDefaults(values)
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

-- 把当前数值存成一个差异预设：只写与 DEFAULTS 不同的键。
-- Preset 行始终保存这个文件自己的显示名，而不是当前恰好选中的那个预设。
-- 玩家级配置（Lang / MenuKey）既不写入也不保留：omit 会把老文件里
-- 残留的行一并丢掉，免得它们跟着预设到处跑、日后又覆盖玩家的设置。
function Config.savePreset(preset, S)
  local diff, drop = diffValues(S, { Preset = true },
                                { Lang = true, MenuKey = true })
  diff.Preset = preset.name
  return writeValues(Config.presetPath(preset.index), diff, drop)
end

return Config
