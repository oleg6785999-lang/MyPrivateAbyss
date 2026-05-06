local Workspace = game:GetService("Workspace")
local RaycastService = {}
RaycastService.__index = RaycastService

local TRANS_THRESHOLD = 0.85

function RaycastService.new()
    local self = setmetatable({
        params = RaycastParams.new(),
        ignoreCache = {},
        internalRay = false  -- public flag: SilentAim hook checks this
    }, RaycastService)
    self.params.FilterType = Enum.RaycastFilterType.Exclude
    self.params.IgnoreWater = true
    return self
end

function RaycastService:Init() end

-- Ignore list reuse: avoids per-call alloc when ignoreList stays identical
function RaycastService:setIgnore(list)
    if not list then list = {} end
    self.params.FilterDescendantsInstances = list
end

function RaycastService:raycast(origin, direction, ignoreList)
    if not origin or not direction then return nil end
    if ignoreList then self:setIgnore(ignoreList) end
    self.internalRay = true
    local ok, result = pcall(Workspace.Raycast, Workspace, origin, direction, self.params)
    self.internalRay = false
    return ok and result or nil
end

-- Returns true if hit can be considered "no obstruction" (nil hit OR transparent OR target part)
function RaycastService:hitClear(hit, hitPart)
    if not hit then return true end
    local inst = hit.Instance
    if not inst then return true end
    local okT, t = pcall(function() return inst.Transparency end)
    if okT and type(t) == "number" and t > TRANS_THRESHOLD then return true end
    if hitPart then
        if inst == hitPart then return true end
        local model = hitPart.Parent
        if model and inst:IsDescendantOf(model) then return true end
    end
    return false
end

-- Multi-ray check: 5 rays (center + ±lateral on right/up vectors)
function RaycastService:multiRayClear(origin, targetPos, hitPart, rightVec, upVec, offset, ignoreList)
    offset = offset or 0.45
    if ignoreList then self:setIgnore(ignoreList) end
    local main = targetPos - origin
    if main.Magnitude < 0.05 then return true end

    local function cast(p)
        self.internalRay = true
        local ok, res = pcall(Workspace.Raycast, Workspace, origin, p - origin, self.params)
        self.internalRay = false
        return ok and res or nil
    end

    -- center
    if self:hitClear(cast(targetPos), hitPart) then return true end
    if rightVec then
        if self:hitClear(cast(targetPos + rightVec * offset),  hitPart) then return true end
        if self:hitClear(cast(targetPos - rightVec * offset),  hitPart) then return true end
    end
    if upVec then
        if self:hitClear(cast(targetPos + upVec * offset),     hitPart) then return true end
        if self:hitClear(cast(targetPos - upVec * offset),     hitPart) then return true end
    end
    return false
end

function RaycastService:Start() end
function RaycastService:Update() end
function RaycastService:Stop() end
function RaycastService:Destroy() table.clear(self.ignoreCache) end

return RaycastService