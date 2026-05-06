local SpinEngine = {}
SpinEngine.__index = SpinEngine

function SpinEngine.new()
    return setmetatable({enabled = false, speed = 30, mode = "Yaw", events = nil}, SpinEngine)
end

function SpinEngine:setEnabled(v) self.enabled = v end
function SpinEngine:setSpeed(v) self.speed = v end
function SpinEngine:setMode(v) self.mode = v end

function SpinEngine:Init(di, events)
    self.events = events
    local cfg = di:resolve("ConfigService")
    cfg:bind(self, "AntiAim.Spin.Enabled", "enabled")
    cfg:bind(self, "AntiAim.Spin.Speed", "speed")
    cfg:bind(self, "AntiAim.Spin.Mode", "mode")
end

function SpinEngine:Start() end
function SpinEngine:Stop() end
function SpinEngine:Destroy() end

function SpinEngine:compute(dt)
    if not self.enabled then return 0 end
    local rad = math.rad(self.speed)
    local mode = self.mode
    if mode == "Yaw" then return tick() * rad
    elseif mode == "Pitch" then return 0
    elseif mode == "Random" then return (math.random() * 2 - 1) * rad * 10
    end
    return tick() * rad
end

return SpinEngine