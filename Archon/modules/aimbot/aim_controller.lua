local AimController = {}
AimController.__index = AimController

function AimController.new()
    return setmetatable({ smoothing = 3, sensitivity = 1, maxFovDelta = 30 }, AimController)
end

function AimController:setSmoothing(v) self.smoothing = v end
function AimController:setSensitivity(v) self.sensitivity = v end
function AimController:setMaxFovDelta(v) self.maxFovDelta = v end

function AimController:apply(camera, targetPos, dt)
    if not camera or not targetPos then return end
    local desired = CFrame.lookAt(camera.CFrame.Position, targetPos)
    local sm = math.max(self.smoothing, 0.001)
    local sens = math.max(self.sensitivity, 0.01)
    local alpha = math.clamp((1 - math.exp(-(dt or 1/60) * (60 / sm))) * sens, 0, 1)
    if self.maxFovDelta > 0 then
        local ang = math.acos(math.clamp(camera.CFrame.LookVector:Dot(desired.LookVector), -1, 1))
        local maxRad = math.rad(self.maxFovDelta)
        if ang > 0 and ang * alpha > maxRad then alpha = maxRad / ang end
    end
    camera.CFrame = camera.CFrame:Lerp(desired, alpha)
end

return AimController
