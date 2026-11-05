-- PBZPlayerArcs: defaults, settings.ini IO and colour helpers.
local Config = {}

local src = debug.getinfo(1, 'S').source:gsub('^@', ''):gsub('\\', '/')
Config.DIR = src:match('^(.*)/[^/]+$') or '.'
Config.INI = Config.DIR .. '/settings.ini'
Config.LOG = Config.DIR .. '/PBZArcs.log'
Config.VERSION = '0.2.0'

-- Presets live in the Scripts/preset/ folder, one full settings file per preset:
-- preset1.ini, preset2.ini ... Each keeps its own display name in its Preset line,
-- while settings.ini's Preset holds the preset file's name without its extension,
-- so renaming the display name never breaks which preset is currently in use.
Config.PRESET_DIR = Config.DIR .. '/preset'

function Config.presetKey(index)
  return 'preset' .. tostring(index)
end

function Config.presetPath(index)
  return Config.PRESET_DIR .. '/' .. Config.presetKey(index) .. '.ini'
end

local DEFAULTS = {
  Enabled = true,

  -- File name (no extension) of the preset in preset/ that the current values came from
  Preset = 'preset1',

  -- Follow
  FollowCharacter = true,
  FollowSmoothing = 0.10,   -- seconds; 0 = snap
  FixedAnchorX = 0.50,      -- used only when FollowCharacter = false
  FixedAnchorY = 0.55,
  AnchorHeight = 15,        -- cm above the player actor origin
  AnchorOffsetX = 0,        -- 1080p baseline pixels
  AnchorOffsetY = 0,

  -- Arc geometry (1080p baseline pixels / degrees)
  Radius = 180,
  Thickness = 16,
  ArcSpan = 90,
  Segments = 64,
  HpOnLeft = true,
  BrushJitter = 0,

  -- Appearance
  BarOpacity = 1.00,
  TrackOpacity = 0.45,
  GhostOpacity = 0.55,
  GhostSpeed = 0.35,        -- seconds
  ShowGhost = true,
  ShowTip = true,
  TipScale = 1.00,
  TipAngle = -15,
  HpColor = '#D6D2C6',      -- game health bar is pale silver
  QiColor = '#D9A62E',      -- game Sha-Chi bar is gold
  TrackColor = '#0A0908',
  WarnColor = '#E0301E',

  -- Low-value warning
  WarnThresholdHp = 0.30,
  WarnThresholdQi = 0.25,
  WarnFlashSpeed = 1.80,    -- Hz
  WarnFlashAmount = 0.65,

  -- Visibility
  Visibility = 'dynamic',   -- always / hud / dynamic (dynamic = hide a full bar after HideDelay, otherwise follow HUD)
  HideDelay = 3.0,          -- seconds a bar must stay full before dynamic hides it
  DisplayMode = 'both',     -- both / hp / qi

  -- Flat medicine / ultimate readouts (copied from the game HUD)
  MedicineHud = true,
  UltHud = true,
  MedicineHudX = -1,        -- screen pixels; -1 = auto bottom-centre
  MedicineHudY = -1,
  UltHudX = -1,
  UltHudY = -1,
  -- Per-icon shift inside its own group; 0 = the automatic layout.
  Med1OffX = 0, Med1OffY = 0,
  Med2OffX = 0, Med2OffY = 0,
  Ult1OffX = 0, Ult1OffY = 0,
  Ult2OffX = 0, Ult2OffY = 0,
  IconScale = 1.0,          -- sizes every icon, its number and the gaps between them
  UltChargeBar = true,      -- 精纯杀气图标本体的充能填充

  -- Keys / menu
  ToggleKey = 'F4',
  MenuKey = 'F2',
  Lang = 'zh_cn',        -- file name under Scripts/lang, listed in languages.ini

  -- Assets
  Texture = '/Game/PBZContent/VFX/SceneFX/UI/Common/Assets/T_UI_Common_InkBar_003.T_UI_Common_InkBar_003',
  InkMaterial = '/Game/PBZContent/VFX/SceneFX/UI/Common/M_UI_InkBar_A_002_Inst2.M_UI_InkBar_A_002_Inst2',
  TipTexture = '/Game/PBZContent/UI/Hud/Art/Hud_Blood_End.Hud_Blood_End',

  -- Ink stroke
  StrokeOverlap = 10,       -- how many segments long each brush copy is drawn

  Debug = false,
}
Config.DEFAULTS = DEFAULTS

local ORDER = {
  'Enabled', 'Preset',
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
  'ToggleKey', 'MenuKey', 'Lang',
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
-- Colour helpers. UMG SetColorAndOpacity takes linear colour, settings.ini stores sRGB hex.

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

-- Unused by the renderer but kept for future overlay work.
function Config.linearToHex(colour)
  local function hex(c)
    c = math.floor(clamp(linearToSrgb(clamp(c or 0, 0, 1)), 0, 1) * 255 + 0.5)
    return string.format('%02X', c)
  end
  return '#' .. hex(colour.R) .. hex(colour.G) .. hex(colour.B)
end

---------------------------------------------------------------------------------------------------
-- Load / save

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
  S.StrokeOverlap = clamp(tonumber(S.StrokeOverlap) or 10, 1, 24)
  S.BarOpacity = clamp(tonumber(S.BarOpacity) or 1, 0.05, 1)
  S.TrackOpacity = clamp(tonumber(S.TrackOpacity) or 0.45, 0, 1)
  S.GhostOpacity = clamp(tonumber(S.GhostOpacity) or 0.55, 0, 1)
  S.GhostSpeed = clamp(tonumber(S.GhostSpeed) or 0.35, 0.01, 1.0)
  S.TipScale = clamp(tonumber(S.TipScale) or 1, 0.3, 3)
  S.TipAngle = clamp(tonumber(S.TipAngle) or -15, -90, 90)
  S.WarnThresholdHp = clamp(tonumber(S.WarnThresholdHp) or 0.30, 0, 1)
  S.WarnThresholdQi = clamp(tonumber(S.WarnThresholdQi) or 0.25, 0, 1)
  S.WarnFlashSpeed = clamp(tonumber(S.WarnFlashSpeed) or 1.8, 0.2, 8)
  S.WarnFlashAmount = clamp(tonumber(S.WarnFlashAmount) or 0.65, 0, 1)
  S.DisplayMode = tostring(S.DisplayMode or 'both'):lower()
  if S.DisplayMode ~= 'hp' and S.DisplayMode ~= 'qi' then S.DisplayMode = 'both' end
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
  S.HpColor = Config.normalizeHex(S.HpColor, DEFAULTS.HpColor)
  S.QiColor = Config.normalizeHex(S.QiColor, DEFAULTS.QiColor)
  S.TrackColor = Config.normalizeHex(S.TrackColor, DEFAULTS.TrackColor)
  S.WarnColor = Config.normalizeHex(S.WarnColor, DEFAULTS.WarnColor)
  -- A language is one file under Scripts/lang, so keep only what a file name can hold.
  local lang = tostring(S.Lang or DEFAULTS.Lang):lower():gsub('[^%w_%.]', '')
  if #lang > 24 then lang = lang:sub(1, 24) end
  if lang == '' then lang = DEFAULTS.Lang end
  S.Lang = lang
  -- The preset's file name is kept as written: trimmed and length-capped only.
  local preset = tostring(S.Preset or DEFAULTS.Preset):gsub('^%s+', ''):gsub('%s+$', '')
  if preset == '' then preset = DEFAULTS.Preset end
  S.Preset = preset:sub(1, 48)
  S.ToggleKey = tostring(S.ToggleKey or 'F4'):upper()
  S.MenuKey = tostring(S.MenuKey or 'F2'):upper()
  S.Texture = tostring(S.Texture or DEFAULTS.Texture)
  S.InkMaterial = tostring(S.InkMaterial or DEFAULTS.InkMaterial)
  S.TipTexture = tostring(S.TipTexture or DEFAULTS.TipTexture)
  S.Enabled = parseBool(S.Enabled)
  S.FollowCharacter = parseBool(S.FollowCharacter)
  S.HpOnLeft = parseBool(S.HpOnLeft)
  S.ShowGhost = parseBool(S.ShowGhost)
  S.ShowTip = parseBool(S.ShowTip)
  S.MedicineHud = parseBool(S.MedicineHud)
  S.UltHud = parseBool(S.UltHud)
  S.Debug = parseBool(S.Debug)
  return S
end

-- Older files used two booleans. Translate them the first time the new key is written.
local LEGACY_VISIBILITY = { FollowHud = true, ShowInCombat = true }

-- Shared by settings.ini and the preset files: read the known keys and convert
-- every value to the type its default has. Returns nil when the file is missing.
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

function Config.load()
  local S = Config.copyDefaults()
  local values, legacy = readValues(Config.INI)
  if values then
    for key, value in pairs(values) do S[key] = value end
    if values.Visibility == nil then
      if legacy.ShowInCombat then S.Visibility = 'dynamic'
      elseif legacy.FollowHud then S.Visibility = 'hud'
      else S.Visibility = 'always' end
    end
  end
  return Config.sanitize(S)
end

local function formatValue(value)
  if type(value) == 'boolean' then return value and 'true' or 'false' end
  if type(value) == 'number' then return string.format('%.4g', value) end
  return tostring(value)
end

-- Rewrite values in place so the file keeps its comments, blank lines and key order.
local function writeValues(path, S)
  local lines, seen = {}, {}
  local f = io.open(path, 'r')
  if f then
    for line in f:lines() do
      local key = line:match('^%s*([%w_]+)%s*=')
      if key and LEGACY_VISIBILITY[key] then
        -- dropped in favour of Visibility
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
-- Presets

local PRESET_MAX = 64

-- The files are found by counting up from preset1.ini and stopping at the first
-- number without a file, so no directory listing is needed. key is the file's name
-- without extension and is what settings.ini stores; name is the display text kept
-- in that file's own Preset line. A file with no Preset line is listed as 预设 N.
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

-- A new preset takes the first free number, so its display name continues the
-- 预设 N run even when a file in the middle was deleted.
function Config.nextPresetSlot(list)
  local taken = {}
  for _, preset in ipairs(list) do taken[preset.index] = true end
  local index = 1
  while taken[index] do index = index + 1 end
  return { index = index, key = Config.presetKey(index), name = '预设 ' .. index }
end

-- Store the current values as a preset. The Preset line always holds the file's
-- own display name, never whichever preset happens to be selected.
function Config.savePreset(preset, S)
  local copy = {}
  for key, value in pairs(S) do copy[key] = value end
  copy.Preset = preset.name
  return writeValues(Config.presetPath(preset.index), copy)
end

return Config
