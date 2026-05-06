local AimController = {}
AimController.__index = AimController

local mathExp   = math.exp
local mathRad   = math.rad
local mathAcos  = math.acos
local mathClamp = math.clamp
local mathMax   = math.max
local mathRandom = math.random
local CFrameLookAt = CFrame.lookAt or function(a, b) return CFrame.new(a, b) end

function AimController.new()
    return setmetatable({
        smoothing   = 3,
        sensitivity = 1,
        maxFovDelta = 38,
        rageMode    = true   -- snap mode: instant aim
    }, AimController)
end

function AimController:setSmoothing(v)   self.smoothing = v end
function AimController:setSensitivity(v) self.sensitivity = v end
function AimController:setMaxFovDelta(v) self.maxFovDelta = v end
function AimController:setRageMode(v)    self.rageMode = v end

function AimController:apply(camera, targetPos, dt)
    if not camera or not targetPos then return end
    local cam = camera.CFrame
    local desired = CFrameLookAt(cam.Position, targetPos)

    local alpha
    if self.rageMode then
        -- Rage: hard snap (alpha=1)
        alpha = 1
    else
        local sm = mathMax(self.smoothing or 3, 0.001)
        local sens = mathMax(self.sensitivity or 1, 0.01)
        alpha = mathClamp((1 - mathExp(-(dt or 1/60) * (60 / sm))) * sens, 0, 1)
        -- Per-frame angular cap (legit only)
        if (self.maxFovDelta or 0) > 0 then
            local ang = mathAcos(mathClamp(cam.LookVector:Dot(desired.LookVector), -1, 1))
            local maxRad = mathRad(self.maxFovDelta)
            if ang > 0 and ang * alpha > maxRad then alpha = maxRad / ang end
        end
    end

    -- Micro-jitter +/- 0.05° anti-snap (legit only)
    if not self.rageMode then
        local jitter = mathRad((mathRandom() - 0.5) * 0.1)
        desired = desired * CFrame.Angles(0, jitter, 0)
    end

    camera.CFrame = cam:Lerp(desired, alpha)
end

return AimController