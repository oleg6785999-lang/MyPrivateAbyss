local FakeLagController = {}
FakeLagController.__index = FakeLagController

function FakeLagController.new()
    return setmetatable({
        enabled = false, mode = "Static", intensity = 5, frequency = 1,
        backForth = false, phase = "release", acc = 0, buf = nil, pulse = 0, events = nil
    }, FakeLagController)
end

function FakeLagController:setEnabled(v) self.enabled = v end
function FakeLagController:setMode(v) self.mode = v end
function FakeLagController:setIntensity(v) self.intensity = v end
function FakeLagController:setFrequency(v) self.frequency = v end
function FakeLagController:setBackForth(v) self.backForth = v end

function FakeLagController:Init(di, events)
    self.events = events
    self.characterService = di:resolve("CharacterService")
    local cfg = di:resolve("ConfigService")
    cfg:bind(self, "AntiAim.FakeLag.Enabled", "enabled")
    cfg:bind(self, "AntiAim.FakeLag.Mode", "mode")
    cfg:bind(self, "AntiAim.FakeLag.Intensity", "intensity")
    cfg:bind(self, "AntiAim.FakeLag.Frequency", "frequency")
    cfg:bind(self, "AntiAim.FakeLag.BackForth", "backForth")
end

function FakeLagController:Start() end
function FakeLagController:Stop() end
function FakeLagController:Destroy() self:release() end

function FakeLagController:isLagging() return self.phase == "lag" end

function FakeLagController:release()
    local hum = self.characterService:getHumanoid()
    if hum and self.phase == "lag" then
        pcall(function() hum:ChangeState(Enum.HumanoidStateType.GettingUp) end)
    end
    self.phase = "release"; self.acc = 0; self.buf = nil
end

function FakeLagController:apply(dt)
    if not self.enabled then self:release(); return end
    local root = self.characterService:getRootPart()
    local hum = self.characterService:getHumanoid()
    if not root or not hum then self:release(); return end

    self.acc = self.acc + dt
    local mode = self.mode
    local intensity, frequency
    if mode == "Static" then intensity = self.intensity / 60; frequency = self.frequency
    elseif mode == "Random" then intensity = math.random(2, math.max(self.intensity, 3)) / 60; frequency = math.random() * 2 + 0.5
    elseif mode == "Adaptive" then
        local v = root.AssemblyLinearVelocity.Magnitude
        intensity = (self.intensity / 60) * math.clamp(v / 30, 0.3, 1); frequency = self.frequency
    elseif mode == "Switch" then intensity = (self.pulse % 2 == 0) and 0.05 or 0.15; frequency = self.frequency
    else intensity = self.intensity / 60; frequency = self.frequency end

    local cycle = 1 / math.max(frequency, 0.1)
    local lagP = math.min(intensity, cycle * 0.7)
    local relP = cycle - lagP

    if self.phase == "release" then
        if self.acc >= relP then
            self.buf = root.CFrame
            pcall(function()
                root.AssemblyLinearVelocity = Vector3.zero
                root.AssemblyAngularVelocity = Vector3.zero
                hum:ChangeState(Enum.HumanoidStateType.Physics)
            end)
            self.phase = "lag"; self.acc = 0; self.pulse = self.pulse + 1
        end
    else
        if self.acc >= lagP then
            pcall(function() hum:ChangeState(Enum.HumanoidStateType.GettingUp) end)
            if self.backForth and self.buf then pcall(function() root.CFrame = self.buf end) end
            self.buf = nil; self.phase = "release"; self.acc = 0
        else
            pcall(function()
                root.AssemblyLinearVelocity = Vector3.zero
                root.AssemblyAngularVelocity = Vector3.zero
            end)
        end
    end
end

return FakeLagController
