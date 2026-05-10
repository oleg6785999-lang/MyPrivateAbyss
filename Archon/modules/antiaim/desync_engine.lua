local DesyncEngine = {}
DesyncEngine.__index = DesyncEngine

function DesyncEngine.new()
    return setmetatable({
        enabled = false, mode = "Switch", strength = 1.0, speed = 30,
        bufferTeleport = false, side = 1, lastSwitch = 0,
        bufPhase = 0, bufOrig = nil, lastBufT = 0, events = nil
    }, DesyncEngine)
end

function DesyncEngine:setEnabled(v) self.enabled = v end
function DesyncEngine:setMode(v) self.mode = v end
function DesyncEngine:setStrength(v) self.strength = v end
function DesyncEngine:setSpeed(v) self.speed = v end
function DesyncEngine:setBufferTeleport(v) self.bufferTeleport = v end

function DesyncEngine:Init(di, events)
    self.events = events
    self.characterService = di:resolve("CharacterService")
    local cfg = di:resolve("ConfigService")
    cfg:bind(self, "AntiAim.Desync.Enabled", "enabled")
    cfg:bind(self, "AntiAim.Desync.Mode", "mode")
    cfg:bind(self, "AntiAim.Desync.Strength", "strength")
    cfg:bind(self, "AntiAim.Desync.Speed", "speed")
    cfg:bind(self, "AntiAim.Desync.BufferTeleport", "bufferTeleport")
end

function DesyncEngine:Start() end
function DesyncEngine:Stop() end
function DesyncEngine:Destroy() self.bufOrig = nil; self.bufPhase = 0 end

function DesyncEngine:compute(dt)
    if not self.enabled then return 0 end
    local str = math.clamp(self.strength, 0, 1)
    local mode = self.mode
    if mode == "Static" then return math.rad(60) * str
    elseif mode == "Spin" then return math.rad(tick() * self.speed) * str
    elseif mode == "Random" then return (math.random() * 2 - 1) * math.rad(120) * str
    elseif mode == "Switch" then
        local int = 1 / math.max(self.speed / 10, 0.5)
        if tick() - self.lastSwitch > int then self.side = -self.side; self.lastSwitch = tick() end
        return math.rad(60) * str * self.side
    elseif mode == "Backwards" then return math.rad(180) * str
    end
    return 0
end

function DesyncEngine:applyBufferTeleport(dt)
    if not self.bufferTeleport or not self.enabled then self.bufPhase = 0; self.bufOrig = nil; return end
    local root = self.characterService:getRootPart()
    if not root then return end
    local now = tick()
    if self.bufPhase == 0 then
        if now - self.lastBufT > 0.1 then
            self.bufOrig = root.CFrame
            pcall(function() root.CFrame = self.bufOrig * CFrame.new((math.random()-0.5)*4, 0, (math.random()-0.5)*4) end)
            self.bufPhase = 1; self.lastBufT = now
        end
    else
        if self.bufOrig then pcall(function() root.CFrame = self.bufOrig end) end
        self.bufOrig = nil; self.bufPhase = 0
    end
end

return DesyncEngine
