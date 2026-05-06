local VisibilityChecker = {}
VisibilityChecker.__index = VisibilityChecker

local CACHE_TTL = 0.045

function VisibilityChecker.new()
    return setmetatable({
        wallCheck = true,
        multiRay = true,
        raycastService = nil,
        cache = setmetatable({}, {__mode = "k"}),
        ignoreList = {}
    }, VisibilityChecker)
end

function VisibilityChecker:setWallCheck(v) self.wallCheck = v end
function VisibilityChecker:setMultiRay(v) self.multiRay = v end

function VisibilityChecker:_buildIgnore(camera, character)
    local list = self.ignoreList
    table.clear(list)
    list[1] = camera
    if character then list[2] = character end
    return list
end

function VisibilityChecker:check(camera, character, pos, hitPart)
    if not self.wallCheck then return true end
    if not camera or not self.raycastService then return false end

    -- Cache lookup (only when hitPart provided)
    if hitPart then
        local c = self.cache[hitPart]
        local now = os.clock()
        if c and (now - c.t) < CACHE_TTL then return c.v end
    end

    local ignore = self:_buildIgnore(camera, character)
    local origin = camera.CFrame.Position
    local dir = pos - origin
    if dir.Magnitude < 0.05 then
        if hitPart then self.cache[hitPart] = {v = true, t = os.clock()} end
        return true
    end

    local visible
    if self.multiRay and self.raycastService.multiRayClear then
        local cf = camera.CFrame
        visible = self.raycastService:multiRayClear(origin, pos, hitPart, cf.RightVector, cf.UpVector, 0.45, ignore)
    else
        local hit = self.raycastService:raycast(origin, dir, ignore)
        visible = self.raycastService:hitClear(hit, hitPart)
    end

    if hitPart then self.cache[hitPart] = {v = visible, t = os.clock()} end
    return visible
end

function VisibilityChecker:invalidate()
    table.clear(self.cache)
end

return VisibilityChecker