local DesyncEngine = {}
DesyncEngine.__index = DesyncEngine

local mathRandom = math.random
local mathClamp  = math.clamp
local mathRad    = math.rad
local mathSign   = math.sign
local mathMax    = math.max

function DesyncEngine.new()
    return setmetatable({
        enabled        = false,
        mode           = "Switch",
        strength       = 1.0,
        speed          = 30,
        bufferTeleport = false,
        predictorBias  = true,
        side           = 1,
        lastSwitch     = 0,
        bufPhase       = 0,
        bufOrig        = nil,
        lastBufT       = 0,
        events         = nil,
        targetService  = nil,
        playerService  = nil
    }, DesyncEngine)
end

function DesyncEngine:setEnabled(v) self.enabled = v end
function DesyncEngine:setMode(v) self.mode = v end
function DesyncEngine:setStrength(v) self.strength = v end
function DesyncEngine:setSpeed(v) self.speed = v end
function DesyncEngine:setBufferTeleport(v) self.bufferTeleport = v end
function DesyncEngine:setPredictorBias(v) self.predictorBias = v end

function DesyncEngine:Init(di, events)
    self.events           = events
    self.characterService = di:resolve("CharacterService")
    -- Optional services (graceful)
    local ok1, ts = pcall(function() return di:resolve("TargetService") end)
    if ok1 then self.targetService = ts end
    local ok2, ps = pcall(function() return di:resolve("PlayerService") end)
    if ok2 then self.playerService = ps end

    local cfg = di:resolve("ConfigService")
    cfg:bind(self, "AntiAim.Desync.Enabled",        "enabled")
    cfg:bind(self, "AntiAim.Desync.Mode",           "mode")
    cfg:bind(self, "AntiAim.Desync.Strength",       "strength")
    cfg:bind(self, "AntiAim.Desync.Speed",          "speed")
    cfg:bind(self, "AntiAim.Desync.BufferTeleport", "bufferTeleport")
    cfg:bind(self, "AntiAim.Desync.PredictorBias",  "predictorBias")
end

function DesyncEngine:Start() end
function DesyncEngine:Stop() end
function DesyncEngine:Destroy() self.bufOrig = nil; self.bufPhase = 0 end

-- Predictor-driven bias: if a target is locked, flip side to anti-resolve
function DesyncEngine:_predictorSide()
    if not self.predictorBias or not self.targetService then return nil end
    local t = self.targetService:getTarget()
    if not t or not t.position then return nil end
    local root = self.characterService:getRootPart()
    if not root then return nil end
    -- Direction from us to target on horizontal plane
    local dir = t.position - root.Position
    local right = root.CFrame.RightVector
    local dot = dir.X * right.X + dir.Z * right.Z
    if math.abs(dot) < 0.1 then return nil end
    -- Bias opposite to relative direction (server reads "real" hidden side)
    return -mathSign(dot)
end

function DesyncEngine:compute(dt)
    if not self.enabled then return 0 end
    local str = mathClamp(self.strength, 0, 1)
    local mode = self.mode

    if mode == "Static" then return mathRad(60) * str
    elseif mode == "Spin" then return mathRad(tick() * self.speed) * str
    elseif mode == "Random" then return (mathRandom() * 2 - 1) * mathRad(120) * str
    elseif mode == "Switch" then
        local int = 1 / mathMax(self.speed / 10, 0.5)
        if tick() - self.lastSwitch > int then
            local biased = self:_predictorSide()
            self.side = biased or -self.side
            self.lastSwitch = tick()
        end
        return mathRad(60) * str * self.side
    elseif mode == "Backwards" then return mathRad(180) * str
    end
    return 0
end

function DesyncEngine:applyBufferTeleport(dt)
    if not self.bufferTeleport or not self.enabled then
        self.bufPhase = 0; self.bufOrig = nil; return
    end
    local root = self.characterService:getRootPart()
    if not root then return end
    local now = tick()
    if self.bufPhase == 0 then
        -- Randomize interval 80-120ms to avoid pattern detection
        local interval = 0.08 + mathRandom() * 0.04
        if now - self.lastBufT > interval then
            self.bufOrig = root.CFrame
            local off = mathRad(60) * 0.5  -- magnitude
            pcall(function()
                root.CFrame = self.bufOrig * CFrame.new(
                    (mathRandom() - 0.5) * 4,
                    0,
                    (mathRandom() - 0.5) * 4
                )
            end)
            self.bufPhase = 1; self.lastBufT = now
        end
    else
        if self.bufOrig then
            pcall(function() root.CFrame = self.bufOrig end)
        end
        self.bufOrig = nil; self.bufPhase = 0
    end
end

return DesyncEngine