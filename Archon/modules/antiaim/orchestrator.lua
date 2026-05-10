local JitterEngine = require(script.Parent.jitter_engine)
local SpinEngine = require(script.Parent.spin_engine)
local PitchEngine = require(script.Parent.pitch_engine)
local DesyncEngine = require(script.Parent.desync_engine)
local FakeLagController = require(script.Parent.fakelag_controller)
local Freestanding = require(script.Parent.freestanding)
local ManualAA = require(script.Parent.manual_aa)
local Indicators = require(script.Parent.indicators)

local AntiAimOrchestrator = {}
AntiAimOrchestrator.__index = AntiAimOrchestrator

function AntiAimOrchestrator.new()
    return setmetatable({
        enabled = false,
        jitter = JitterEngine.new(),
        spin = SpinEngine.new(),
        pitch = PitchEngine.new(),
        desync = DesyncEngine.new(),
        fakelag = FakeLagController.new(),
        freestanding = Freestanding.new(),
        manual = ManualAA.new(),
        indicators = Indicators.new(),
        events = nil,
        character = nil,
        rootJoint = nil,
        neck = nil,
        waist = nil,
        origRootC0 = nil,
        origNeckC0 = nil,
        origNeckC1 = nil,
        origWaistC0 = nil
    }, AntiAimOrchestrator)
end

function AntiAimOrchestrator:setEnabled(v) self.enabled = v end

function AntiAimOrchestrator:Init(di, events)
    self.events = events
    self.characterService = di:resolve("CharacterService")
    self.cameraService = di:resolve("CameraService")
    self.raycastService = di:resolve("RaycastService")
    local cfg = di:resolve("ConfigService")
    cfg:bind(self, "AntiAim.Enabled", "enabled")
    self.jitter:Init(di, events)
    self.spin:Init(di, events)
    self.pitch:Init(di, events)
    self.desync:Init(di, events)
    self.fakelag:Init(di, events)
    self.freestanding:Init(di, events)
    self.manual:Init(di, events)
    self.indicators:Init(di, events)
end

function AntiAimOrchestrator:Start()
    self.jitter:Start()
    self.spin:Start()
    self.pitch:Start()
    self.desync:Start()
    self.fakelag:Start()
    self.freestanding:Start()
    self.manual:Start()
    self.indicators:Start()
end

function AntiAimOrchestrator:cacheJoints()
    local char = self.characterService:getCharacter()
    if not char then return end
    if char ~= self.character then
        self.character = char
        local root = self.characterService:getRootPart()
        if root then
            self.rootJoint = root:FindFirstChild("RootJoint")
            if self.rootJoint and self.rootJoint:IsA("Motor6D") and not self.origRootC0 then
                self.origRootC0 = self.rootJoint.C0
            end
        end
        local head = char:FindFirstChild("Head")
        if head then
            self.neck = head:FindFirstChild("Neck")
            if self.neck and self.neck:IsA("Motor6D") then
                if not self.origNeckC0 then self.origNeckC0 = self.neck.C0 end
                if not self.origNeckC1 then self.origNeckC1 = self.neck.C1 end
            end
        end
        local lt = char:FindFirstChild("LowerTorso")
        if lt then
            self.waist = lt:FindFirstChild("Waist")
            if self.waist and self.waist:IsA("Motor6D") and not self.origWaistC0 then
                self.origWaistC0 = self.waist.C0
            end
        end
    end
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
    local manualAngle = self.manual:getAngle()
    local spinAngle = self.spin:compute(dt)
    local jitterAngle = self.jitter:compute(dt)
    local desyncAngle = self.desync:compute(dt)

    local baseYaw = 0
    if manualAngle ~= 0 then baseYaw = manualAngle
    elseif freestandAngle ~= 0 then baseYaw = freestandAngle
    else baseYaw = spinAngle + jitterAngle end

    local totalYaw = baseYaw + desyncAngle
    local pitchAngle = self.pitch:compute(dt)

    if self.origRootC0 and self.rootJoint then
        self.rootJoint.C0 = self.origRootC0 * CFrame.Angles(pitchAngle, totalYaw, 0)
    end
    if self.origWaistC0 and self.waist and desyncAngle ~= 0 then
        self.waist.C0 = self.origWaistC0 * CFrame.Angles(0, desyncAngle * 0.5, 0)
    end

    self.fakelag:apply(dt)
    self.desync:applyBufferTeleport(dt)
end

function AntiAimOrchestrator:Render(dt)
    if not self.enabled then
        self.indicators:hide()
        return
    end
    local realYaw = 0
    local fakeYaw = self.spin:compute(0) + self.jitter:compute(0) + self.desync:compute(0)
    local pitch = self.pitch:compute(0)
    local lagging = self.fakelag:isLagging()
    self.indicators:draw(realYaw, fakeYaw, pitch, lagging, dt)
end

function AntiAimOrchestrator:restoreJoints()
    if self.rootJoint and self.origRootC0 then self.rootJoint.C0 = self.origRootC0 end
    if self.neck and self.origNeckC0 then self.neck.C0 = self.origNeckC0 end
    if self.neck and self.origNeckC1 then self.neck.C1 = self.origNeckC1 end
    if self.waist and self.origWaistC0 then self.waist.C0 = self.origWaistC0 end
end

function AntiAimOrchestrator:Stop()
    self.jitter:Stop()
    self.spin:Stop()
    self.pitch:Stop()
    self.desync:Stop()
    self.fakelag:Stop()
    self.freestanding:Stop()
    self.manual:Stop()
    self.indicators:Stop()
end

function AntiAimOrchestrator:Destroy()
    self:restoreJoints()
    self.fakelag:Destroy()
    self.desync:Destroy()
    self.indicators:Destroy()
    self.jitter:Destroy()
    self.spin:Destroy()
    self.pitch:Destroy()
    self.freestanding:Destroy()
    self.manual:Destroy()
    self.character = nil
    self.rootJoint = nil
    self.neck = nil
    self.waist = nil
    self.origRootC0 = nil
    self.origNeckC0 = nil
    self.origNeckC1 = nil
    self.origWaistC0 = nil
end

return AntiAimOrchestrator
