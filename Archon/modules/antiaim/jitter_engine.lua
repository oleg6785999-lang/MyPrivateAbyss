local JitterEngine = {}
JitterEngine.__index = JitterEngine

function JitterEngine.new()
    return setmetatable({
        enabled = false, mode = "Sine", angle = 40, speed = 12,
        pattern = {1, -1, 0.5, -0.5}, patternIdx = 1, patternT = 0,
        randWalk = 0, events = nil
    }, JitterEngine)
end

function JitterEngine:setEnabled(v) self.enabled = v end
function JitterEngine:setMode(v) self.mode = v end
function JitterEngine:setAngle(v) self.angle = v end
function JitterEngine:setSpeed(v) self.speed = v end
function JitterEngine:setPattern(v) self.pattern = v end

function JitterEngine:Init(di, events)
    self.events = events
    local cfg = di:resolve("ConfigService")
    cfg:bind(self, "AntiAim.Jitter.Enabled", "enabled")
    cfg:bind(self, "AntiAim.Jitter.Mode", "mode")
    cfg:bind(self, "AntiAim.Jitter.Angle", "angle")
    cfg:bind(self, "AntiAim.Jitter.Speed", "speed")
    cfg:bind(self, "AntiAim.Jitter.Pattern", "pattern")
end

function JitterEngine:Start() end
function JitterEngine:Stop() end
function JitterEngine:Destroy() end

function JitterEngine:compute(dt)
    if not self.enabled then return 0 end
    local max = math.rad(self.angle)
    local spd = self.speed
    local mode = self.mode
    if mode == "Sine" then return math.sin(tick() * spd) * max
    elseif mode == "Static" then return max
    elseif mode == "Flick" then return (math.floor(tick() * spd) % 2 == 0) and max or -max
    elseif mode == "RandomWalk" then
        self.randWalk = math.clamp(self.randWalk + (math.random() - 0.5) * 0.15, -1, 1)
        return self.randWalk * max
    elseif mode == "CustomPattern" then
        local pat = self.pattern
        if tick() - self.patternT > 0.15 then
            self.patternIdx = (self.patternIdx % #pat) + 1
            self.patternT = tick()
        end
        return (pat[self.patternIdx] or 0) * max
    end
    return (math.random() * 2 - 1) * max
end

return JitterEngine