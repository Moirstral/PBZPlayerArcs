-- PBZPlayerArcs：把玩家 Pawn 投影到 Slate 坐标，并对锚点做平滑。
local Follow = {}
Follow.__index = Follow

local METHODS = {
  { name = 'widget', object = '/Script/UMG.Default__WidgetLayoutLibrary',
    fn = 'ProjectWorldLocationToWidgetPosition', static = true, slate = true },
  { name = 'statics', object = '/Script/Engine.Default__GameplayStatics',
    fn = 'ProjectWorldToScreen', static = true, slate = false },
  { name = 'controller', fn = 'ProjectWorldLocationToScreen', static = false, slate = false },
}

local function valid(object)
  if object == nil then return false end
  local ok, answer = pcall(function() return object:IsValid() end)
  return ok and answer == true
end

local function prop(object, name)
  local ok, value = pcall(function() return object[name] end)
  if ok then return value end
  return nil
end

-- 相机从角色右肩上方看过去，所以 actor 原点会落在弧线视觉中心稍偏右的位置。
-- 这个基准修正值以 1080p 像素为单位，并像 AnchorOffsetX 一样缩放；
-- 滑块本身仍然只作微调。
local BASE_OFFSET_X = -10

local function finite(value)
  return type(value) == 'number' and value == value and math.abs(value) < 1e9
end

local function xy(value)
  if value == nil then return nil, nil end
  local x = value.X or value.x
  local y = value.Y or value.y
  if finite(x) and finite(y) then return x, y end
  return nil, nil
end

function Follow.new(settings, log)
  return setmetatable({
    S = settings,
    log = log or function() end,
    x = nil,
    y = nil,
    pawn = nil,
    viewport = nil,
    viewportAt = -100,
    methodIndex = nil,
    projectionWarning = false,
  }, Follow)
end

function Follow:getViewport(pc)
  local now = os.clock()
  if self.viewport and now - self.viewportAt < 0.5 then return self.viewport end
  self.viewportAt = now

  local okWorld, world = pcall(function() return pc:GetWorld() end)
  if not okWorld then world = nil end
  local lib = StaticFindObject('/Script/UMG.Default__WidgetLayoutLibrary')
  local vp, dpi
  if valid(lib) and valid(world) then
    local ok, result = pcall(function() return lib:GetViewportSize(world) end)
    if ok then vp = result end
    local ok2, scale = pcall(function() return lib:GetViewportScale(world) end)
    if ok2 and finite(scale) and scale > 0.1 then dpi = scale end
  end
  local w, h = xy(vp)
  if not (finite(w) and finite(h) and w > 0 and h > 0) then
    w, h = 1920, 1080
  end
  dpi = dpi or 1
  self.viewport = {
    w = w / dpi,
    h = h / dpi,
    dpi = dpi,
    pixelsW = w,
    pixelsH = h,
  }
  return self.viewport
end

function Follow:project(pc, pawn, viewport)
  local locationOk, location = pcall(function() return pawn:K2_GetActorLocation() end)
  if not locationOk then location = nil end
  if location == nil then
    local getLoc = prop(pawn, 'K2_GetActorLocation')
    if type(getLoc) == 'function' then
      local ok, result = pcall(function() return getLoc(pawn) end)
      if ok then location = result end
    end
  end
  local x, y, z = nil, nil, nil
  if type(location) == 'table' then
    x, y, z = location.X, location.Y, location.Z
    if not finite(x) then x, y, z = location.x, location.y, location.z end
  end
  if not (finite(x) and finite(y) and finite(z)) then
    if not self.projectionWarning then
      self.projectionWarning = true
      self.log('player location is unavailable; follow is paused')
    end
    return nil, nil
  end
  local point = { X = x, Y = y, Z = z + (tonumber(self.S.AnchorHeight) or 0) }

  local order = {}
  if self.methodIndex then order[#order + 1] = self.methodIndex end
  for i = 1, #METHODS do
    if i ~= self.methodIndex then order[#order + 1] = i end
  end
  for _, index in ipairs(order) do
    local method = METHODS[index]
    local object = method.object and StaticFindObject(method.object) or pc
    if valid(object) then
      local out = {}
      local ok, result, extra, extra2 = pcall(function()
        if method.static then
          return object[method.fn](object, pc, point, out, false)
        end
        return object[method.fn](object, point, out, false)
      end)
      if ok then
        local sx, sy = xy(out)
        if not sx and type(result) == 'table' then sx, sy = xy(result) end
        if not sx and type(extra) == 'table' then sx, sy = xy(extra) end
        if not sx and type(extra) == 'table' and type(extra.X) == 'number' then
          sx, sy = extra.X, extra.Y
        end
        if not sx and finite(extra) and finite(extra2) then sx, sy = extra, extra2 end
        if sx and sy then
          if result == false then return nil, nil end
          if not method.slate then
            sx, sy = sx / viewport.dpi, sy / viewport.dpi
          end
          if finite(sx) and finite(sy) then
            if self.methodIndex ~= index then
              self.methodIndex = index
              self.log('follow projection: ' .. method.name)
            end
            return sx, sy
          end
        end
      end
    end
  end
  if not self.projectionWarning then
    self.projectionWarning = true
    self.log('no world-to-screen projection is available; using the fixed anchor')
  end
  return nil, nil
end

function Follow:update(snapshot, dt)
  local S = self.S
  if not snapshot or not valid(snapshot.pc) or not valid(snapshot.pawn) then
    return self.x, self.y, false
  end
  local viewport = self:getViewport(snapshot.pc)
  local scale = math.max(0.35, viewport.h / 1080)
  local targetX, targetY
  local projected = true

  if S.FollowCharacter then
    targetX, targetY = self:project(snapshot.pc, snapshot.pawn, viewport)
    if targetX == nil then
      projected = false
    end
  else
    projected = false
  end
  if not projected then
    targetX = viewport.w * (tonumber(S.FixedAnchorX) or 0.5)
    targetY = viewport.h * (tonumber(S.FixedAnchorY) or 0.55)
  else
    -- 只有投影得到的锚点需要这项相机修正；固定锚点就是一个明确的屏幕比例，
    -- 说在哪就停在哪。
    targetX = targetX + BASE_OFFSET_X * scale
  end
  targetX = targetX + (tonumber(S.AnchorOffsetX) or 0) * scale
  targetY = targetY + (tonumber(S.AnchorOffsetY) or 0) * scale

  local snap = self.x == nil or self.pawn ~= snapshot.pawn
  if not snap then
    local dx, dy = targetX - self.x, targetY - self.y
    if dx * dx + dy * dy > 600 * 600 then snap = true end
  end
  self.pawn = snapshot.pawn
  if snap then
    self.x, self.y = targetX, targetY
  else
    local tau = tonumber(S.FollowSmoothing) or 0
    local k = (tau <= 0.001) and 1 or (1 - math.exp(-math.max(0, dt) / tau))
    self.x = self.x + (targetX - self.x) * k
    self.y = self.y + (targetY - self.y) * k
  end

  local margin = 80
  local onscreen = self.x > -margin and self.x < viewport.w + margin
    and self.y > -margin and self.y < viewport.h + margin
  return self.x, self.y, onscreen, viewport, scale
end

return Follow
