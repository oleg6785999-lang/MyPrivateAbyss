local PitchEngine = {}
PitchEngine.__index = PitchEngine

function PitchEngine.new()
    return setmetatable({enabled = false, mode = "Down", angle = 89, events = nil}, PitchEngine)
end

function PitchEngine:setEnabled(v) self.enabled = v end
function PitchEngine:setMode(v) self.mode = v end
function PitchEngine:setAngle(v) self.angle = v end

function PitchEngine:Init(di, events)
    self.events = events
    local cfg = di:resolve("ConfigService")
    cfg:bind(self, "AntiAim.Pitch.Enabled", "enabled")
    cfg:bind(self, "AntiAim.Pitch.Mode", "mode")
    cfg:bind(self, "AntiAim.Pitch.Angle", "angle")
end

function PitchEngine:Start() end
function PitchEngine:Stop() end
function PitchEngine:Destroy() end

function PitchEngine:compute(dt)
    if not self.enabled then return 0 end
    local mode = self.mode
    local ang = math.rad(self.angle)
    if mode == "Down" then return -ang
    elseif mode == "Up" then return ang
    elseif mode == "FakeUp" then return ang * 0.8
    elseif mode == "Random" then return (math.random() * 2 - 1) * ang
    end
    return 0
end

return PitchEngine