local Freestanding = {}
Freestanding.__index = Freestanding

function Freestanding.new()
    return setmetatable({enabled = false, edgeDetect = true, range = 15, events = nil}, Freestanding)
end

function Freestanding:setEnabled(v) self.enabled = v end
function Freestanding:setEdgeDetect(v) self.edgeDetect = v end
function Freestanding:setRange(v) self.range = v end

function Freestanding:Init(di, events)
    self.events = events
    self.characterService = di:resolve("CharacterService")
    self.cameraService = di:resolve("CameraService")
    self.raycastService = di:resolve("RaycastService")
    local cfg = di:resolve("ConfigService")
    cfg:bind(self, "AntiAim.Freestanding.Enabled", "enabled")
    cfg:bind(self, "AntiAim.Freestanding.EdgeDetect", "edgeDetect")
    cfg:bind(self, "AntiAim.Freestanding.Range", "range")
end

function Freestanding:Start() end
function Freestanding:Stop() end
function Freestanding:Destroy() end

function Freestanding:compute(dt)
    if not self.enabled then return 0 end
    local root = self.characterService:getRootPart()
    local cam = self.cameraService:getCamera()
    if not root or not cam then return 0 end

    local pos = root.Position
    local dirs = {
        cam.CFrame.LookVector,
        -cam.CFrame.LookVector,
        cam.CFrame.RightVector,
        -cam.CFrame.RightVector
    }
    local bestDir, minDist = nil, math.huge

    for _, dir in ipairs(dirs) do
        local hit = self.raycastService:raycast(pos, dir * self.range, {root.Parent})
        local dist = hit and hit.Distance or self.range
        if dist < minDist then minDist = dist; bestDir = dir end
    end

    if bestDir and minDist < self.range * 0.8 then
        local angle = math.atan2(bestDir.X, bestDir.Z)
        return angle + math.pi
    end
    return 0
end

return Freestanding