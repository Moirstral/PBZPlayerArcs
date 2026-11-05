-- UI text: one ini per language in Scripts/lang, listed by Scripts/lang/languages.ini.
-- UE4SS gives Lua no way to list a directory, so the languages the dropdown offers
-- come from that list rather than from whatever files happen to be on disk. Each
-- file spells its own name in a top lang.name line, so a new language needs no code.
local Lang = {}

local src = debug.getinfo(1, 'S').source:gsub('^@', ''):gsub('\\', '/')
local DIR = src:match('^(.*)/[^/]+$') or '.'
local LANG_DIR = DIR .. '/lang'
local DEFAULT_CODE = 'zh_cn'
local NAME_KEY = 'lang.name'

local cache = {}

local function readAll(path)
  local f = io.open(path, 'rb')
  if not f then return nil end
  local text = f:read('*a')
  f:close()
  -- Notepad can save a byte order mark, and it would hide the very first key.
  return (text:gsub('^\239\187\191', ''))
end

local function readTable(path)
  local text = readAll(path)
  if text == nil then return nil end
  local out = {}
  for line in (text .. '\n'):gmatch('([^\n]*)\n') do
    local key, value = line:match('^%s*([%w_%.]+)%s*=%s*(.-)%s*$')
    if key then out[key] = value end
  end
  return out
end

-- A language code becomes a file name, so anything that could leave the lang
-- folder is dropped before it is ever used.
function Lang.normalize(code)
  local clean = tostring(code or ''):lower():gsub('[^%w_%.]', '')
  if #clean > 24 then clean = clean:sub(1, 24) end
  if clean == '' then clean = DEFAULT_CODE end
  return clean
end

local function pathFor(code)
  return LANG_DIR .. '/' .. code .. '.ini'
end

-- Strings of one language, or nil when that file is missing or holds no keys.
-- A failed lookup is cached as false so it is not retried on every refresh.
local function loadRaw(code)
  local cached = cache[code]
  if cached ~= nil then return cached or nil end
  local strings = readTable(pathFor(code))
  if strings == nil or next(strings) == nil then
    cache[code] = false
    return nil
  end
  cache[code] = strings
  return strings
end

-- The codes languages.ini lists, in file order. Without that list only the default
-- language can be offered.
local function readCodes()
  local codes, seen = {}, {}
  local text = readAll(LANG_DIR .. '/languages.ini')
  if text then
    for line in (text .. '\n'):gmatch('([^\n]*)\n') do
      local raw = line:match('^%s*([%w_%.%-]+)%s*$')
      if raw then
        local code = Lang.normalize(raw)
        if not seen[code] then
          seen[code] = true
          codes[#codes + 1] = code
        end
      end
    end
  end
  if #codes == 0 then codes[1] = DEFAULT_CODE end
  return codes
end

function Lang.load(code)
  code = Lang.normalize(code)
  return loadRaw(code) or loadRaw(DEFAULT_CODE) or {}
end

-- Dropdown rows: every listed code whose file exists, labelled with the name that
-- file spells for itself.
function Lang.options()
  local out = {}
  for _, code in ipairs(readCodes()) do
    local strings = loadRaw(code)
    if strings then
      local name = strings[NAME_KEY]
      out[#out + 1] = { value = code, label = (name ~= nil and name ~= '') and name or code }
    end
  end
  if #out == 0 then out[1] = { value = DEFAULT_CODE, label = DEFAULT_CODE } end
  return out
end

function Lang.nameFor(code)
  code = Lang.normalize(code)
  local strings = loadRaw(code)
  local name = strings and strings[NAME_KEY]
  if name ~= nil and name ~= '' then return name end
  return code
end

-- Called when the menu opens, so an edited or newly added language file is picked
-- up without restarting the game.
function Lang.reload()
  cache = {}
end

return Lang
