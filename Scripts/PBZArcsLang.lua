-- UI 文本：Scripts/lang 下每种语言一个 ini，由 Scripts/lang/languages.ini 列出。
-- UE4SS 无法让 Lua 列出目录，所以下拉框提供的语言
-- 来自那份清单，而不是磁盘上恰好存在的文件。每个
-- 文件都在顶部 lang.name 行里写明自己的名字，因此新增语言无需改代码。
local Lang = {}

local src = debug.getinfo(1, 'S').source:gsub('^@', ''):gsub('\\', '/')
local DIR = src:match('^(.*)/[^/]+$') or '.'
local LANG_DIR = DIR .. '/lang'
-- 文化名，与游戏自己使用的完全一致（Culture.ToString()）；文件
-- 直接就是 <culture>.ini，所以无需查找表就能用上游戏的语言。
local DEFAULT_CODE = 'zh-Hans'
local NAME_KEY = 'lang.name'

local cache = {}

local function readAll(path)
  local f = io.open(path, 'rb')
  if not f then return nil end
  local text = f:read('*a')
  f:close()
  -- 记事本可能保存了字节顺序标记，而它会藏住第一个键。
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

-- 语言代码会变成文件名，所以任何可能跑出 lang 目录的内容
-- 都会在被使用之前剔除。大小写和连字符保留：该代码就是游戏的
-- 文化名，写法与游戏拼写完全一致。
function Lang.normalize(code)
  local clean = tostring(code or ''):gsub('[^%w_%.%-]', '')
  if #clean > 24 then clean = clean:sub(1, 24) end
  if clean == '' then clean = DEFAULT_CODE end
  return clean
end

local function pathFor(code)
  return LANG_DIR .. '/' .. code .. '.ini'
end

-- 某种语言的字符串；该文件缺失或不含任何键时返回 nil。
-- 失败的查找会缓存为 false，以免每次刷新都重试。
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

-- languages.ini 列出的代码，按文件顺序。没有这份清单时
-- 只能提供默认语言。
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

-- 下拉框的每一行：每个已列出且文件存在的代码，用该文件
-- 为自己写明的名字作标签。
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

-- 菜单打开时调用，这样编辑过或新增的语言文件
-- 无需重启游戏就能生效。
function Lang.reload()
  cache = {}
end

return Lang
