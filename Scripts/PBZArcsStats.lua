-- PBZPlayerArcs：只读读取玩家的生命 / 杀气数值。
-- 沿用本版本上 PBZNumericHUD 已经验证过的属性链。
local Stats = {}
Stats.__index = Stats

local Util = require('PBZArcsUtil')
local valid, prop, unwrap = Util.valid, Util.prop, Util.unwrap

local function call(object, name, ...)
  local fn = object and prop(object, name)
  if type(fn) ~= 'function' then return nil end
  -- pcall 会把后续参数原样转交 fn，不必再包一层匿名闭包、也不必建 args 表。
  local ok, result = pcall(fn, object, ...)
  if ok then return result end
  return nil
end

local ENGINE = nil
local ASC_CLASS = nil
local function abilitySystemClass()
  if valid(ASC_CLASS) then return ASC_CLASS end
  local class = StaticFindObject('/Script/GameplayAbilities.AbilitySystemComponent')
  if valid(class) then ASC_CLASS = class end
  return class
end

local function engine()
  if valid(ENGINE) then return ENGINE end
  local e = FindFirstOf('GameEngine')
  if not valid(e) then e = FindFirstOf('Engine') end
  if valid(e) then ENGINE = e; return e end
  return nil
end

local function playerController()
  local e = engine()
  if not e then return nil end
  local gi = prop(e, 'GameInstance')
  if not valid(gi) then return nil end
  local players = prop(gi, 'LocalPlayers')
  if not players or #players < 1 then return nil end
  local localPlayer = unwrap(players[1])
  if not valid(localPlayer) then return nil end
  local pc = prop(localPlayer, 'PlayerController')
  if not valid(pc) then return nil end
  return pc
end

local function propertyNames(object)
  local names = {}
  local class = call(object, 'GetClass')
  if not valid(class) then return names end
  pcall(function()
    class:ForEachProperty(function(first, second)
      local entry = first
      if type(first) == 'string' then entry = second end
      if entry == nil then return end
      local ok, name = pcall(function() return entry:GetFName():ToString() end)
      if ok and type(name) == 'string' and name ~= '' then
        names[#names + 1] = name
      end
    end)
  end)
  return names
end

local function findAttributeSet(pawn)
  local asc = prop(pawn, 'AbilitySystemComponent')
  if not valid(asc) then
    asc = call(pawn, 'GetComponentByClass', abilitySystemClass())
  end
  if not valid(asc) then return nil, nil, nil end
  local sets = prop(asc, 'SpawnedAttributes')
  if not sets then return nil, nil, nil end
  local fallback, fallbackNames
  for i = 1, #sets do
    local set = unwrap(sets[i])
    if valid(set) then
      local names = propertyNames(set)
      local lower = {}
      for _, n in ipairs(names) do lower[n:lower()] = n end
      if lower.health and lower.shachi then
        return set, names, asc
      end
      if lower.health and not fallback then
        fallback, fallbackNames = set, names
      end
    end
  end
  return fallback, fallbackNames, asc
end

local function pickName(names, wanted)
  local lower = {}
  for _, n in ipairs(names or {}) do lower[n:lower()] = n end
  return lower[wanted:lower()]
end

-- 每帧读 6 个属性，闭包提到模块级，避免 6 次新建匿名函数。
local function rawGetPropertyValue(attributes, name)
  return attributes:GetPropertyValue(name)
end

local function readAttribute(attributes, name)
  if not name then return nil end
  local ok, value = pcall(rawGetPropertyValue, attributes, name)
  if ok and value ~= nil then
    if type(value) == 'number' then return value end
    local data = unwrap(value)
    local current = prop(data, 'CurrentValue')
    if type(current) == 'number' then return current end
  end
  local direct = prop(attributes, name)
  if type(direct) == 'number' then return direct end
  if direct ~= nil then
    local data = unwrap(direct)
    local current = prop(data, 'CurrentValue')
    if type(current) == 'number' then return current end
  end
  return nil
end

function Stats.new()
  return setmetatable({}, Stats)
end

function Stats:read()
  local pc = self._pc
  if not valid(pc) then
    pc = playerController()
    self._pc = pc
    self._pawn = nil
    self._set = nil
    self._names = nil
  end
  if not valid(pc) then return nil, 'player controller is not ready' end

  local pawn = prop(pc, 'Pawn')
  if not valid(pawn) then
    self._pawn = nil
    self._set = nil
    return nil, 'player pawn is not ready'
  end
  if pawn ~= self._pawn or not valid(self._set) then
    self._pawn = pawn
    self._set, self._names = findAttributeSet(pawn)
    self._hp = pickName(self._names, 'Health')
    self._hpMax = pickName(self._names, 'Health_Max')
    self._qi = pickName(self._names, 'Shachi')
    self._qiMax = pickName(self._names, 'Shachi_Max')
    self._ult = pickName(self._names, 'UltimateCharge')
    self._ultMax = pickName(self._names, 'UltimateCharge_Max')
  end
  if not valid(self._set) then return nil, 'BasicAttributeSet is not ready' end

  local hp = readAttribute(self._set, self._hp)
  local hpMax = readAttribute(self._set, self._hpMax)
  if type(hp) ~= 'number' or type(hpMax) ~= 'number' or hpMax <= 0 then
    -- 复活期间这个属性集可能被重建；下一帧再重新解析一次。
    self._set = nil
    return nil, 'Health is unavailable'
  end

  local qi = readAttribute(self._set, self._qi)
  local qiMax = readAttribute(self._set, self._qiMax)
  if type(qi) ~= 'number' or type(qiMax) ~= 'number' or qiMax <= 0 then
    qi, qiMax = nil, nil
  end

  hp = math.max(0, hp)
  if qi then qi = math.max(0, qi) end

  -- 精纯杀气的充能进度：充满时游戏把 UltimateCharge 清零、UltimateChargeCount 加一，
  -- 所以这个比值就是界面上那条进度。取不到时按 nil 处理，界面自己决定怎么显示。
  local ult = readAttribute(self._set, self._ult)
  local ultMax = readAttribute(self._set, self._ultMax)
  if type(ult) ~= 'number' or type(ultMax) ~= 'number' or ultMax <= 0 then
    ult, ultMax = nil, nil
  else
    ult = math.max(0, math.min(ultMax, ult))
  end
  return {
    pc = pc,
    pawn = pawn,
    hp = hp,
    hpMax = hpMax,
    qi = qi,
    qiMax = qiMax,
    ult = ult,
    ultMax = ultMax,
  }
end

-- 换世界（读档、过图）时调用：缓存的 PlayerController / Pawn / 属性集全部属于
-- 旧世界，引擎会在换图之后把它们销毁。这里只丢 Lua 侧的引用，不碰任何 UObject，
-- 所以可以在 LoadMap 的钩子里安全调用。
function Stats:forget()
  self._pc, self._pawn, self._set, self._names = nil, nil, nil, nil
  self._hp, self._hpMax, self._qi, self._qiMax = nil, nil, nil, nil
  self._ult, self._ultMax = nil, nil
end

return Stats
