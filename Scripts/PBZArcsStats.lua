-- PBZPlayerArcs: read-only player Health / Sha-Chi values.
-- Mirrors the attribute chain proven by PBZNumericHUD on this build.
local Stats = {}
Stats.__index = Stats

local function valid(object)
  if object == nil then return false end
  local ok, answer = pcall(function() return object:IsValid() end)
  return ok and answer == true
end

local function unwrap(value)
  local ok, inner = pcall(function() return value:get() end)
  if ok and inner ~= nil then return inner end
  return value
end

local function prop(object, name)
  local ok, value = pcall(function() return object[name] end)
  if ok then return value end
  return nil
end

local function call(object, name, ...)
  local fn = object and prop(object, name)
  if type(fn) ~= 'function' then return nil end
  local args = { ... }
  local ok, result = pcall(function() return fn(object, table.unpack(args)) end)
  if ok then return result end
  return nil
end

local ENGINE = nil
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
    asc = call(pawn, 'GetComponentByClass', StaticFindObject('/Script/GameplayAbilities.AbilitySystemComponent'))
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

local function readAttribute(attributes, name)
  if not name then return nil end
  local ok, value = pcall(function() return attributes:GetPropertyValue(name) end)
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

---------------------------------------------------------------------------------------------------
-- Discovery dump (one-shot, Debug only). Read-only: it lists every attribute set,
-- inventory-ish component and item-related widget so unknown fields (medicine
-- charges, pure Sha-Chi, ...) can be identified without guessing.

local DUMP_KEYWORDS = {
  'medicine', 'potion', 'pill', 'drug', 'elixir', 'heal', 'bottle', 'flask',
  'item', 'inventory', 'consum', 'equip', 'accessory', 'ultimate', 'pure',
  -- The game itself uses pinyin in BP data (DisplayYaoShiData, CurrentHupo),
  -- so the Chinese names must be probed as pinyin too.
  'yao', 'hupo', 'heishi', 'dan',
  'count', 'num', 'charges',
}

local function keywordHit(text)
  if type(text) ~= 'string' then return false end
  local lower = text:lower()
  for _, keyword in ipairs(DUMP_KEYWORDS) do
    if lower:find(keyword, 1, true) then return true end
  end
  return false
end

local function classNameOf(object)
  local class = call(object, 'GetClass')
  if not valid(class) then return '?' end
  local ok, name = pcall(function() return class:GetFName():ToString() end)
  if ok and type(name) == 'string' then return name end
  return '?'
end

local function fullNameOf(object)
  local ok, name = pcall(function() return object:GetFullName() end)
  if ok and type(name) == 'string' then return name end
  return '?'
end

local function elementText(element)
  if type(element) == 'number' then return string.format('%.6g', element) end
  if type(element) == 'string' or type(element) == 'boolean' then return tostring(element) end
  local inner = unwrap(element)
  if inner ~= nil and inner ~= element then
    if type(inner) == 'number' then return string.format('%.6g', inner) end
    if valid(inner) then return classNameOf(inner) .. ' ' .. fullNameOf(inner) end
  end
  if valid(element) then return classNameOf(element) .. ' ' .. fullNameOf(element) end
  return '<' .. type(element) .. '>'
end

local function fieldText(owner, name)
  local number = readAttribute(owner, name)
  if number ~= nil then return string.format('%.6g', number) end
  local raw = prop(owner, name)
  if raw == nil then return nil end
  local kind = type(raw)
  if kind == 'number' or kind == 'boolean' or kind == 'string' then return tostring(raw) end
  local ok, length = pcall(function() return #raw end)
  if ok and type(length) == 'number' and length > 0 then return 'array[' .. length .. ']' end
  return '<' .. kind .. '>'
end

local function dumpFields(out, object, indent, limit)
  local count = 0
  for _, name in ipairs(propertyNames(object)) do
    local text = fieldText(object, name)
    if text ~= nil then
      count = count + 1
      if count <= limit then out[#out + 1] = indent .. name .. ' = ' .. text end
    end
    if text ~= nil and text:sub(1, 6) == 'array[' then
      local raw = prop(object, name)
      local ok, length = pcall(function() return #raw end)
      if ok and type(length) == 'number' and length > 0 then
        for index = 1, math.min(length, 8) do
          out[#out + 1] = indent .. '  [' .. index .. '] ' .. elementText(raw[index])
        end
      end
    end
  end
  if count > limit then out[#out + 1] = indent .. '... ' .. (count - limit) .. ' more fields' end
end

local function textValue(value)
  if value == nil then return nil end
  if type(value) == 'string' then return value end
  for _, method in ipairs({ 'ToString', 'GetDisplayString', 'AsString' }) do
    local text = call(value, method)
    if type(text) == 'string' then return text end
  end
  local inner = unwrap(value)
  if inner ~= nil and inner ~= value then
    if type(inner) == 'string' then return inner end
    for _, method in ipairs({ 'ToString', 'GetDisplayString' }) do
      local text = call(inner, method)
      if type(text) == 'string' then return text end
    end
  end
  return nil
end

local function textOf(block)
  local text = textValue(prop(block, 'Text'))
  if text == nil then text = textValue(call(block, 'GetText')) end
  if text == nil then text = '<unreadable ' .. type(prop(block, 'Text')) .. '>' end
  return (text:gsub('[\r\n]+', ' '))
end

local function gameInstance()
  local e = engine()
  if not e then return nil end
  local gi = prop(e, 'GameInstance')
  if valid(gi) then return gi end
  return nil
end

local function componentsOf(actor)
  if not valid(actor) then return nil end
  local class = StaticFindObject('/Script/Engine.ActorComponent')
  local result = call(actor, 'K2_GetComponentsByClass', class)
  if type(result) ~= 'table' then result = call(actor, 'GetComponentsByClass', class) end
  if type(result) ~= 'table' then result = call(actor, 'GetComponents') end
  if type(result) == 'table' then return result end
  return nil
end

local function anyKeywordField(object)
  if keywordHit(classNameOf(object)) then return true end
  for _, name in ipairs(propertyNames(object)) do
    if keywordHit(name) then return true end
  end
  return false
end

function Stats:describeAttributes()
  local out = {}
  local pc = playerController()
  if not valid(pc) then return out end
  local pawn = prop(pc, 'Pawn')
  local playerState = prop(pc, 'PlayerState')
  local gi = gameInstance()

  local ascs, seenAsc = {}, {}
  local function addAsc(label, asc)
    if not valid(asc) then return end
    local full = fullNameOf(asc)
    if seenAsc[full] or full:find('Default__', 1, true) then return end
    seenAsc[full] = true
    ascs[#ascs + 1] = { label = label, asc = asc }
  end
  if valid(pawn) then addAsc('pawn', prop(pawn, 'AbilitySystemComponent')) end
  if valid(playerState) then addAsc('playerstate', prop(playerState, 'AbilitySystemComponent')) end
  addAsc('controller', prop(pc, 'AbilitySystemComponent'))
  local okAsc, allAsc = pcall(function() return FindAllOf('AbilitySystemComponent') end)
  if okAsc and type(allAsc) == 'table' then
    for i = 1, #allAsc do addAsc('found', allAsc[i]) end
  end

  local seenSet = {}
  local function dumpSet(label, set, limit)
    local full = fullNameOf(set)
    if seenSet[full] then return end
    seenSet[full] = true
    out[#out + 1] = label .. ' ' .. classNameOf(set) .. '  ' .. full
    dumpFields(out, set, '  ', limit or 400)
  end
  for _, entry in ipairs(ascs) do
    out[#out + 1] = 'asc[' .. entry.label .. '] ' .. classNameOf(entry.asc) .. '  ' .. fullNameOf(entry.asc)
    local sets = prop(entry.asc, 'SpawnedAttributes')
    for i = 1, (sets and #sets or 0) do
      local set = unwrap(sets[i])
      if valid(set) then dumpSet('  set[' .. i .. ']', set) end
    end
  end
  local okSet, allSets = pcall(function() return FindAllOf('AttributeSet') end)
  if okSet and type(allSets) == 'table' then
    local ownerNames = {}
    for _, object in ipairs({ pawn, playerState, pc }) do
      if valid(object) then ownerNames[#ownerNames + 1] = fullNameOf(object) end
    end
    local ownedSets, otherSets = {}, 0
    for i = 1, #allSets do
      local set = allSets[i]
      if valid(set) and not fullNameOf(set):find('Default__', 1, true) then
        local full = fullNameOf(set)
        local owned = false
        for _, owner in ipairs(ownerNames) do
          if full:find(owner, 1, true) then owned = true; break end
        end
        if owned then
          if #ownedSets < 8 then ownedSets[#ownedSets + 1] = set end
        elseif otherSets < 4 then
          otherSets = otherSets + 1
          dumpSet('other', set, 80)
        end
      end
    end
    for _, set in ipairs(ownedSets) do dumpSet('found', set) end
  end

  local function scanObject(label, object)
    if not valid(object) then return end
    for _, name in ipairs(propertyNames(object)) do
      if keywordHit(name) then
        local text = fieldText(object, name)
        out[#out + 1] = label .. '.' .. name .. ' = ' .. tostring(text)
        local raw = prop(object, name)
        local inner = raw ~= nil and unwrap(raw) or nil
        if valid(inner) and inner ~= object then
          out[#out + 1] = label .. '.' .. name .. ' :: ' .. classNameOf(inner) .. '  ' .. fullNameOf(inner)
          dumpFields(out, inner, '    ', 40)
        end
      end
    end
  end
  scanObject('pawn', pawn)
  scanObject('playerstate', playerState)
  scanObject('controller', pc)

  -- GameInstance / GameState: inventory and save data usually hang off them.
  if valid(gi) then
    out[#out + 1] = 'gi ' .. classNameOf(gi) .. '  ' .. fullNameOf(gi)
    dumpFields(out, gi, '  ', 120)
    scanObject('gi', gi)
  end
  local okGs, gameStates = pcall(function() return FindAllOf('GameStateBase') end)
  if okGs and type(gameStates) == 'table' then
    for i = 1, math.min(#gameStates, 2) do
      local gs = gameStates[i]
      if valid(gs) and not fullNameOf(gs):find('Default__', 1, true) then
        out[#out + 1] = 'gamesate ' .. classNameOf(gs) .. '  ' .. fullNameOf(gs)
        scanObject('gamestate', gs)
      end
    end
  end

  -- Components on the player objects: a medicine pouch component would live here.
  local seenComp, compClasses, compCount = {}, {}, 0
  for _, entry in ipairs({ { 'pawn', pawn }, { 'playerstate', playerState }, { 'controller', pc } }) do
    local comps = componentsOf(entry[2])
    for i = 1, (comps and #comps or 0) do
      local comp = unwrap(comps[i])
      if valid(comp) then
        local full = fullNameOf(comp)
        if not seenComp[full] and not full:find('Default__', 1, true) then
          seenComp[full] = true
          compCount = compCount + 1
          local cls = classNameOf(comp)
          compClasses[cls] = (compClasses[cls] or 0) + 1
          if anyKeywordField(comp) then
            out[#out + 1] = 'comp[' .. entry[1] .. '] ' .. cls .. '  ' .. full
            dumpFields(out, comp, '  ', 60)
          end
        end
      end
    end
  end
  local compList = {}
  for cls, n in pairs(compClasses) do compList[#compList + 1] = cls .. ' x' .. n end
  table.sort(compList)
  out[#out + 1] = 'sec comps: ' .. compCount .. ' -> ' .. table.concat(compList, ', ')

  -- Subsystems (inventory / item / save managers are usually subsystems).
  local seenSub, subNames = {}, {}
  for _, base in ipairs({ 'GameInstanceSubsystem', 'WorldSubsystem', 'LocalPlayerSubsystem', 'Subsystem' }) do
    local okSub, subs = pcall(function() return FindAllOf(base) end)
    if okSub and type(subs) == 'table' then
      for i = 1, #subs do
        local sub = subs[i]
        if valid(sub) then
          local full = fullNameOf(sub)
          if not seenSub[full] and not full:find('Default__', 1, true) then
            seenSub[full] = true
            local cls = classNameOf(sub)
            subNames[cls] = (subNames[cls] or 0) + 1
            if anyKeywordField(sub) then
              out[#out + 1] = 'sub ' .. cls .. '  ' .. full
              dumpFields(out, sub, '  ', 60)
            end
          end
        end
      end
    end
  end
  local subList = {}
  for cls, n in pairs(subNames) do subList[#subList + 1] = cls .. ' x' .. n end
  table.sort(subList)
  out[#out + 1] = 'sec subs: ' .. table.concat(subList, ', ')

  -- Save-game objects often keep the consumable counts in plain fields.
  local seenSave, saveShown = {}, 0
  for _, base in ipairs({ 'SaveGame', 'SaveGameArchive' }) do
    local okSave, saves = pcall(function() return FindAllOf(base) end)
    if okSave and type(saves) == 'table' then
      for i = 1, #saves do
        local save = saves[i]
        if valid(save) and saveShown < 4 then
          local full = fullNameOf(save)
          if not seenSave[full] and not full:find('Default__', 1, true) then
            seenSave[full] = true
            saveShown = saveShown + 1
            out[#out + 1] = 'save ' .. classNameOf(save) .. '  ' .. full
            dumpFields(out, save, '  ', 120)
          end
        end
      end
    end
  end
  out[#out + 1] = 'sec saves: ' .. saveShown

  -- On-screen text: the medicine counter is a number drawn by the HUD.
  local okT, texts = pcall(function() return FindAllOf('TextBlock') end)
  if okT and type(texts) == 'table' then
    local shown, unreadable = 0, 0
    for i = 1, #texts do
      local block = texts[i]
      if valid(block) then
        local full = fullNameOf(block)
        local lower = full:lower()
        if not lower:find('default__', 1, true) and shown < 250 then
          local text = textOf(block)
          local isHud = lower:find('/uinnew/hud/', 1, true) ~= nil
          if text:sub(1, 11) == '<unreadable' then
            unreadable = unreadable + 1
            if isHud then
              shown = shown + 1
              out[#out + 1] = 'text ' .. full .. ' = ' .. text
            end
          else
            shown = shown + 1
            out[#out + 1] = 'text ' .. full .. ' = ' .. text
          end
        end
      end
    end
    out[#out + 1] = 'sec texts: shown ' .. shown .. ', unreadable ' .. unreadable
  end

  local okW, widgets = pcall(function() return FindAllOf('UserWidget') end)
  if okW and type(widgets) == 'table' then
    local seenClass, hudClasses, hudCount = {}, {}, 0
    local allClasses, classList = {}, {}
    for i = 1, #widgets do
      local widget = widgets[i]
      if valid(widget) then
        local full = fullNameOf(widget)
        local lower = full:lower()
        if not lower:find('default__', 1, true) then
          local class = classNameOf(widget)
          if not allClasses[class] then
            allClasses[class] = 0
            classList[#classList + 1] = class
          end
          allClasses[class] = allClasses[class] + 1
          if lower:find('/uinnew/hud/', 1, true) or lower:find('/ui/hud/', 1, true) then
            hudCount = hudCount + 1
            if not seenClass[class] then
              seenClass[class] = true
              hudClasses[#hudClasses + 1] = 'hudwidget ' .. class .. '  ' .. full
            end
          end
        end
      end
    end
    table.sort(classList)
    local names = {}
    for i = 1, math.min(#classList, 250) do
      local class = classList[i]
      names[#names + 1] = class .. ' x' .. allClasses[class]
    end
    out[#out + 1] = 'sec widgetclasses: ' .. table.concat(names, ', ')
    for i = 1, math.min(#hudClasses, 250) do out[#out + 1] = hudClasses[i] end
    out[#out + 1] = 'sec hudwidgets: ' .. #hudClasses .. ' classes, ' .. hudCount .. ' instances'

    -- Field dump for medicine-ish widgets and anything that looks like a HUD gauge.
    local seenFull, shown = {}, 0
    for i = 1, #widgets do
      local widget = widgets[i]
      if valid(widget) then
        local full = fullNameOf(widget)
        local class = classNameOf(widget)
        local hit = keywordHit(class) or keywordHit(full)
        if not seenFull[full] and not full:find('Default__', 1, true) and hit and shown < 30 then
          seenFull[full] = true
          shown = shown + 1
          out[#out + 1] = 'widget ' .. class .. '  ' .. full
          dumpFields(out, widget, '  ', 150)
        end
      end
    end
  end
  return out
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
    -- The set can be rebuilt during respawn; retry resolution on the next tick.
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

return Stats
