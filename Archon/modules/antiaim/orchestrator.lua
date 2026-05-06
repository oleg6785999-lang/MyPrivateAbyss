local JitterEngine       = require(script.Parent.jitter_engine)
local SpinEngine         = require(script.Parent.spin_engine)
local PitchEngine        = require(script.Parent.pitch_engine)
local DesyncEngine       = require(script.Parent.desync_engine)
local FakeLagController  = require(script.Parent.fakelag_controller)
local Freestanding       = require(script.Parent.freestanding)
local ManualAA           = require(script.Parent.manual_aa)
local Indicators         = require(script.Parent.indicators)

local mathAtan2 = math.atan2
local mathPi    = math.pi

local AntiAimOrchestrator = {}
AntiAimOrchestrator.__index = AntiAimOrchestrator

function AntiAimOrchestrator.new()
    return setmetatable({
        enabled = false,
        yawFlipEnabled = false,
        yawFlipInterval = 0.2,
        yawFlipState   = 1,
        yawFlipLast    = 0,

        jitter        = JitterEngine.new(),
        spin          = SpinEngine.new(),
        pitch         = PitchEngine.new(),
        desync        = DesyncEngine.new(),
        fakelag       = FakeLagController.new(),
        freestanding  = Freestanding.new(),
        manual        = ManualAA.new(),
        indicators    = Indicators.new(),

        events       = nil,
        character    = nil,
        rootJoint    = nil,
        neck         = nil,
        waist        = nil,
        origRootC0   = nil,
        origNeckC0   = nil,
        origNeckC1   = nil,
        origWaistC0  = nil,

        -- frame snapshot (Update writes, Render reads)
        snap = {
            realYaw  = 0,
            fakeYaw  = 0,
            pitch    = 0,
            lagging  = false,
            desync   = 0
        },

        spawnConn = nil
    }, AntiAimOrchestrator)
end

function AntiAimOrchestrator:setEnabled(v) self.enabled = v end
function AntiAimOrchestrator:setYawFlipEnabled(v) self.yawFlipEnabled = v end
function AntiAimOrchestrator:setYawFlipInterval(v) self.yawFlipInterval = v end

function AntiAimOrchestrator:Init(di, events)
    self.events = events
    self.characterService = di:resolve("CharacterService")
    self.cameraService    = di:resolve("CameraService")
    self.raycastService   = di:resolve("RaycastService")
    local cfg = di:resolve("ConfigService")
    cfg:bind(self, "AntiAim.Enabled",          "enabled")
    cfg:bind(self, "AntiAim.YawFlip.Enabled",  "yawFlipEnabled")
    cfg:bind(self, "AntiAim.YawFlip.Interval", "yawFlipInterval")

    self.jitter:Init(di, events)
    self.spin:Init(di, events)
    self.pitch:Init(di, events)
    self.desync:Init(di, events)
    self.fakelag:Init(di, events)
    self.freestanding:Init(di, events)
    self.manual:Init(di, events)
    self.indicators:Init(di, events)

    -- Reset orig C0/C1 on respawn so they don't apply to a stale rig
    if events then
        self.spawnConn = events:subscribe("CharacterSpawned", function(_)
            self.character     = nil
            self.rootJoint     = nil
            self.neck          = nil
            self.waist         = nil
            self.origRootC0    = nil
            self.origNeckC0    = nil
            self.origNeckC1    = nil
            self.origWaistC0   = nil
        end, 100)
    end
end

function AntiAimOrchestrator:Start()
    self.jitter:Start(); self.spin:Start(); self.pitch:Start()
    self.desync:Start(); self.fakelag:Start(); self.freestanding:Start()
    self.manual:Start(); self.indicators:Start()
end

function AntiAimOrchestrator:cacheJoints()
    local char = self.characterService:getCharacter()
    if not char then return end
    if char ~= self.character then
        self.character    = char
        self.rootJoint    = nil
        self.neck         = nil
        self.waist        = nil
        self.origRootC0   = nil
        self.origNeckC0   = nil
        self.origNeckC1   = nil
        self.origWaistC0  = nil

        local root = self.characterService:getRootPart()
        if root then
            local rj = root:FindFirstChild("RootJoint")
            if rj and rj:IsA("Motor6D") then
                self.rootJoint = rj
                self.origRootC0 = rj.C0
            end
        end
        local head = char:FindFirstChild("Head")
        if head then
            local n = head:FindFirstChild("Neck")
            if n and n:IsA("Motor6D") then
                self.neck = n
                self.origNeckC0 = n.C0
                self.origNeckC1 = n.C1
            end
        end
        local lt = char:FindFirstChild("LowerTorso")
        if lt then
            local w = lt:FindFirstChild("Waist")
            if w and w:IsA("Motor6D") then
                self.waist = w
                self.origWaistC0 = w.C0
            end
        end
    end
end

function AntiAimOrchestrator:_yawFlipBoost(dt)
    if not self.yawFlipEnabled then return 0 end
    local now = os.clock()
    if (now - self.yawFlipLast) > (self.yawFlipInterval or 0.2) then
        self.yawFlipState = -self.yawFlipState
        self.yawFlipLast = now
    end
    return self.yawFlipState * (mathPi * 0.5) -- ±90°
end

function AntiAimOrchestrator:Update(dt)
    if not self.enabled then
        self:restoreJoints()
        self.fakelag:release()
        return
    end
    self:cacheJoints()
    if not self.rootJoint then return end

    local freestandAngle = self.freestanding:compute(dt)
    local manualAngle    = self.manual:getAngle()
    local spinAngle      = self.spin:compute(dt)
    local jitterAngle    = self.jitter:compute(dt)
    local desyncAngle    = self.desync:compute(dt)
    local pitchAngle     = self.pitch:compute(dt)

    local baseYaw
    if manualAngle ~= 0 then baseYaw = manualAngle
    elseif freestandAngle ~= 0 then baseYaw = freestandAngle
    else baseYaw = spinAngle + jitterAngle end

    -- Yaw flip overlays additional ±90° toggle on top of base
    baseYaw = baseYaw + self:_yawFlipBoost(dt)

    local totalYaw = baseYaw + desyncAngle

    if self.origRootC0 then
        pcall(function()
            self.rootJoint.C0 = self.origRootC0 * CFrame.Angles(pitchAngle, totalYaw, 0)
        end)
    end
    if self.origWaistC0 and self.waist and desyncAngle ~= 0 then
        pcall(function()
            self.waist.C0 = self.origWaistC0 * CFrame.Angles(0, desyncAngle * 0.5, 0)
        end)
    end

    self.fakelag:apply(dt)
    self.desync:applyBufferTeleport(dt)

    -- Compute real yaw from current camera (for indicators)
    local cam = self.cameraService:getCamera()
    local realYaw = 0
    if cam then
        local lv = cam.CFrame.LookVector
        realYaw = mathAtan2(lv.X, lv.Z)
    end

    -- Snapshot for Render (no recomputation, no state mutation in Render)
    self.snap.realYaw = realYaw
    self.snap.fakeYaw = realYaw + baseYaw + desyncAngle
    self.snap.pitch   = pitchAngle
    self.snap.lagging = self.fakelag:isLagging()
    self.snap.desync  = desyncAngle
end

function AntiAimOrchestrator:Render(dt)
    if not self.enabled then
        self.indicators:hide()
        return
    end
    local s = self.snap
    self.indicators:draw(s.realYaw, s.fakeYaw, s.pitch, s.lagging, dt)
end

function AntiAimOrchestrator:restoreJoints()
    if self.rootJoint and self.origRootC0 then pcall(function() self.rootJoint.C0 = self.origRootC0 end) end
    if self.neck and self.origNeckC0 then pcall(function() self.neck.C0 = self.origNeckC0 end) end
    if self.neck and self.origNeckC1 then pcall(function() self.neck.C1 = self.origNeckC1 end) end
    if self.waist and self.origWaistC0 then pcall(function() self.waist.C0 = self.origWaistC0 end) end
end

function AntiAimOrchestrator:Stop()
    self.jitter:Stop(); self.spin:Stop(); self.pitch:Stop()
    self.desync:Stop(); self.fakelag:Stop(); self.freestanding:Stop()
    self.manual:Stop(); self.indicators:Stop()
end

function AntiAimOrchestrator:Destroy()
    self:restoreJoints()
    if self.spawnConn and self.events then
        pcall(function() self.events:unsubscribe(self.spawnConn) end)
        self.spawnConn = nil
    end
    self.fakelag:Destroy(); self.desync:Destroy(); self.indicators:Destroy()
    self.jitter:Destroy(); self.spin:Destroy(); self.pitch:Destroy()
    self.freestanding:Destroy(); self.manual:Destroy()
    self.character    = nil
    self.rootJoint    = nil
    self.neck         = nil
    self.waist        = nil
    self.origRootC0   = nil
    self.origNeckC0   = nil
    self.origNeckC1   = nil
    self.origWaistC0  = nil
end

return AntiAimOrchestrator