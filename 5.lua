-- === ЗАМЕНИ ЭТОТ ФАЙЛ НА ПОЛНОСТЬЮ ===
-- FILENAME: AntiAim.lua
-- ============================================================
-- AntiAim.lua — ABYSS ARCHON / Modular  (v4 ELITE)
-- Современные методы 2026:
--   Desync   : RootJoint.C0 + LowerTorso.Root.C0 (R15 twist)
--              + buffered CFrame teleport-loop (real server-side)
--              БЕЗ AlignOrientation
--   FakeLag  : velocity freeze (no Anchor!) + Humanoid Physics state
--              modes: Static / Random / Adaptive / Switch
--   Jitter   : Sine / RandomWalk / Flick / Static / CustomPattern
--   HideHead : Neck.C0 rotation + Neck.C1 translate (extra effect)
--   Visualizer: реальный (HRP.LookVector) vs fake угол на экране
--   ResolverBypass: micro-jitter (anti-snap heuristic)
--   Predictor: bias desync против hum.MoveDirection
--
-- Конфликт-guard: skip CFrame/velocity ops при активном Fly;
-- Spinbot гасится в Movement.lua когда Desync включён.
-- ============================================================

local Players    = game:GetService("Players")
local RunService = game:GetService("RunService")

if _G.ABYSS_AntiAim and type(_G.ABYSS_AntiAim.Disconnect) == "function" then
    pcall(_G.ABYSS_AntiAim.Disconnect)
end
_G.ABYSS_AntiAim = nil

----------------------------------------------------------------
-- Settings (defensive merge)
----------------------------------------------------------------
_G.Settings = _G.Settings or {}
local A = _G.Settings.AntiAim or {}

if A.Jitter             == nil then A.Jitter             = false end
if A.Desync             == nil then A.Desync             = false end
if A.HideHead           == nil then A.HideHead           = false end
if A.FakeLag            == nil then A.FakeLag            = false end
if A.FakeLagBackForth   == nil then A.FakeLagBackForth   = false end
if A.Visualizer         == nil then A.Visualizer         = false end
if A.ResolverBypass     == nil then A.ResolverBypass     = false end
if A.Predictor          == nil then A.Predictor          = false end
if A.DesyncBufferTeleport == nil then A.DesyncBufferTeleport = false end

A.JitterMode       = A.JitterMode       or "Sine"      -- Sine/RandomWalk/Flick/Static/CustomPattern
A.JitterAngle      = tonumber(A.JitterAngle)      or 40
A.JitterSpeed      = tonumber(A.JitterSpeed)      or 12
A.JitterPattern    = A.JitterPattern    or { 1, -1, 0.5, -0.5 }

A.DesyncMode       = A.DesyncMode       or "Spin"      -- Static/Spin/Random/Switch/Backwards
A.DesyncStrength   = tonumber(A.DesyncStrength)   or 1.0
A.DesyncSpeed      = tonumber(A.DesyncSpeed)      or 30

A.HideHeadMode     = A.HideHeadMode     or "Back"      -- Back/Down/Offset/Spin
A.HideHeadOffset   = tonumber(A.HideHeadOffset)   or 1.5

A.FakeLagMode      = A.FakeLagMode      or "Static"    -- Static/Random/Adaptive/Switch
A.FakeLagIntensity = tonumber(A.FakeLagIntensity) or 5
A.FakeLagFrequency = tonumber(A.FakeLagFrequency) or 1

A.MicroJitterAngle = tonumber(A.MicroJitterAngle) or 0.05
A.PredictorAngle   = tonumber(A.PredictorAngle)   or 15

_G.Settings.AntiAim = A

local LocalPlayer = Players.LocalPlayer
local connections = {}

----------------------------------------------------------------
-- State
----------------------------------------------------------------
local STEP_NAME_VIS = "ABYSS_AntiAimVis"

local originalRootC0  = nil
local originalNeckC0  = nil
local originalNeckC1  = nil
local originalLowerC0 = nil

-- Jitter state
local jitterRandWalk    = 0
local jitterPatternIdx  = 1
local jitterPatternTime = 0

-- Desync state
local switchSide  = 1
local lastSwitchT = 0

-- Buffered CFrame teleport state
local lastBufferT  = 0
local bufferPhase  = 0  -- 0 = idle, 1 = teleport sent (rewinding)
local bufferOrigCF = nil

-- FakeLag state
local fl = {
    phase           = "release",  -- "release" or "lag"
    accumulator     = 0,
    bufferedCFrame  = nil,
    pulseCount      = 0,
}

-- Visualizer drawings
local viz = { realLine = nil, fakeLine = nil, circle = nil, text = nil }
local drawingAvailable = type(Drawing) == "table" and type(Drawing.new) == "function"

----------------------------------------------------------------
-- Utility
----------------------------------------------------------------
local function GetCharRig()
    local char = LocalPlayer.Character
    if not char or not char.Parent then return nil, nil, nil end
    local hum  = char:FindFirstChildOfClass("Humanoid")
    local root = char:FindFirstChild("HumanoidRootPart")
    if not hum or not root then return nil, nil, nil end
    return char, hum, root
end

local function GetRootJoint(root)
    if not root then return nil end
    local j = root:FindFirstChild("RootJoint")
    if j and j:IsA("Motor6D") then return j end
    return nil
end

local function GetLowerJoint(char)
    if not char then return nil end
    local lt = char:FindFirstChild("LowerTorso")
    if not lt then return nil end
    -- R15: внутри LowerTorso есть Motor6D "Root" что соединяет с UpperTorso? Нет.
    -- Реально LowerTorso имеет "Waist" Motor6D, соединяющий с UpperTorso.
    local waist = lt:FindFirstChild("Waist")
    if waist and waist:IsA("Motor6D") then return waist end
    return nil
end

local function GetNeck(char)
    if not char then return nil end
    local head = char:FindFirstChild("Head")
    if head then
        local n = head:FindFirstChild("Neck")
        if n and n:IsA("Motor6D") then return n end
    end
    for _, parentName in ipairs({ "UpperTorso", "Torso" }) do
        local p = char:FindFirstChild(parentName)
        if p then
            local n = p:FindFirstChild("Neck")
            if n and n:IsA("Motor6D") then return n end
        end
    end
    return nil
end

local function FlyActive()
    return _G.Settings.Fly and _G.Settings.Fly.Enabled
end

----------------------------------------------------------------
-- Jitter angle compute (per mode)
----------------------------------------------------------------
local function ComputeJitterAngle()
    if not A.Jitter then return 0 end
    local maxAng = math.rad(A.JitterAngle or 40)
    local mode   = A.JitterMode or "Sine"
    local speed  = A.JitterSpeed or 12

    if mode == "Sine" then
        return math.sin(tick() * speed) * maxAng
    elseif mode == "Static" then
        return maxAng
    elseif mode == "Flick" then
        local phase = math.floor(tick() * speed) % 2
        return (phase == 0) and maxAng or -maxAng
    elseif mode == "RandomWalk" then
        jitterRandWalk = jitterRandWalk + (math.random() - 0.5) * 0.15
        if jitterRandWalk >  1 then jitterRandWalk =  1 end
        if jitterRandWalk < -1 then jitterRandWalk = -1 end
        return jitterRandWalk * maxAng
    elseif mode == "CustomPattern" then
        local pat = A.JitterPattern
        if not pat or #pat == 0 then return 0 end
        local now = tick()
        if now - jitterPatternTime > 0.15 then
            jitterPatternIdx  = (jitterPatternIdx % #pat) + 1
            jitterPatternTime = now
        end
        return (pat[jitterPatternIdx] or 0) * maxAng
    end
    return (math.random() * 2 - 1) * maxAng
end

----------------------------------------------------------------
-- Desync angle compute (per mode)
----------------------------------------------------------------
local function ComputeDesyncAngle()
    if not A.Desync then return 0 end
    local strength = math.clamp(A.DesyncStrength or 1, 0, 1)
    local mode     = A.DesyncMode or "Spin"

    if mode == "Static" then
        return math.rad(60) * strength
    elseif mode == "Spin" then
        return math.rad(tick() * (A.DesyncSpeed or 30)) * strength
    elseif mode == "Random" then
        return (math.random() * 2 - 1) * math.rad(120) * strength
    elseif mode == "Switch" then
        local interval = 1 / math.max((A.DesyncSpeed or 30) / 10, 0.5)
        if tick() - lastSwitchT > interval then
            switchSide  = -switchSide
            lastSwitchT = tick()
        end
        return math.rad(60) * strength * switchSide
    elseif mode == "Backwards" then
        return math.rad(180) * strength
    end
    return 0
end

----------------------------------------------------------------
-- Resolver bypass micro-jitter
----------------------------------------------------------------
local function GetMicroJitter()
    if not A.ResolverBypass then return 0 end
    return (math.random() - 0.5) * 2 * (A.MicroJitterAngle or 0.05)
end

----------------------------------------------------------------
-- Predictor: bias desync против движения
----------------------------------------------------------------
local function GetPredictorBias()
    if not A.Predictor then return 0 end
    local _, hum = GetCharRig()
    if not hum then return 0 end
    local md = hum.MoveDirection
    if md.Magnitude < 0.1 then return 0 end
    local cam = workspace.CurrentCamera
    if not cam then return 0 end
    local dot = md:Dot(cam.CFrame.RightVector)
    if math.abs(dot) < 0.1 then return 0 end
    return -math.sign(dot) * math.rad(A.PredictorAngle or 15)
end

----------------------------------------------------------------
-- Apply combined angles to RootJoint.C0 + LowerTorso.Waist.C0
----------------------------------------------------------------
local function ApplyAngles()
    local char, _, root = GetCharRig()
    if not root then return end
    local joint = GetRootJoint(root)
    if not joint then return end
    if not originalRootC0 then originalRootC0 = joint.C0 end

    local jit   = ComputeJitterAngle()
    local des   = ComputeDesyncAngle()
    local bias  = GetPredictorBias()
    local micro = GetMicroJitter()
    local total = jit + des + bias + micro

    if not A.Jitter and not A.Desync and not A.ResolverBypass and not A.Predictor then
        if joint.C0 ~= originalRootC0 then joint.C0 = originalRootC0 end
        if originalLowerC0 then
            local waist = GetLowerJoint(char)
            if waist and waist.C0 ~= originalLowerC0 then waist.C0 = originalLowerC0 end
            originalLowerC0 = nil
        end
        return
    end

    joint.C0 = originalRootC0 * CFrame.Angles(0, total, 0)

    -- LowerTorso twist (R15 extra) — половинная амплитуда desync для torso splitting
    if A.Desync then
        local waist = GetLowerJoint(char)
        if waist then
            if not originalLowerC0 then originalLowerC0 = waist.C0 end
            waist.C0 = originalLowerC0 * CFrame.Angles(0, des * 0.5, 0)
        end
    elseif originalLowerC0 then
        local waist = GetLowerJoint(char)
        if waist and waist.C0 ~= originalLowerC0 then waist.C0 = originalLowerC0 end
        originalLowerC0 = nil
    end
end

----------------------------------------------------------------
-- Buffered CFrame teleport-loop (real server-side desync)
-- Каждые ~100мс: телепорт на смещение → следующий тик возврат.
-- Skip при FlyActive.
----------------------------------------------------------------
local function ApplyBufferTeleport()
    if not A.Desync or not A.DesyncBufferTeleport then
        bufferPhase  = 0
        bufferOrigCF = nil
        return
    end
    if FlyActive() then return end

    local _, _, root = GetCharRig()
    if not root then return end

    local now = tick()
    if bufferPhase == 0 then
        if now - lastBufferT > 0.1 then
            bufferOrigCF = root.CFrame
            local off = CFrame.new(
                (math.random() - 0.5) * 4,
                0,
                (math.random() - 0.5) * 4
            )
            pcall(function() root.CFrame = bufferOrigCF * off end)
            bufferPhase = 1
            lastBufferT = now
        end
    else
        -- следующий тик: вернули позицию назад (server увидел fake → real)
        if bufferOrigCF then
            pcall(function() root.CFrame = bufferOrigCF end)
        end
        bufferOrigCF = nil
        bufferPhase  = 0
    end
end

----------------------------------------------------------------
-- HideHead (Neck.C0 + Neck.C1 offset)
----------------------------------------------------------------
local function ApplyHideHead()
    local char = LocalPlayer.Character
    if not char then return end
    local neck = GetNeck(char)
    if not neck then return end

    if not A.HideHead then
        if originalNeckC0 then
            if neck.C0 ~= originalNeckC0 then neck.C0 = originalNeckC0 end
            originalNeckC0 = nil
        end
        if originalNeckC1 then
            if neck.C1 ~= originalNeckC1 then neck.C1 = originalNeckC1 end
            originalNeckC1 = nil
        end
        return
    end

    if not originalNeckC0 then originalNeckC0 = neck.C0 end
    if not originalNeckC1 then originalNeckC1 = neck.C1 end

    local mode = A.HideHeadMode or "Back"
    local off  = A.HideHeadOffset or 1.5

    if mode == "Down" then
        neck.C0 = originalNeckC0 * CFrame.Angles(math.rad(-90), 0, 0)
    elseif mode == "Offset" then
        neck.C0 = originalNeckC0 * CFrame.new(0, -off, 0) * CFrame.Angles(0, math.rad(180), 0)
    elseif mode == "Spin" then
        neck.C0 = originalNeckC0 * CFrame.Angles(0, tick() * 6, 0)
    else  -- Back
        neck.C0 = originalNeckC0 * CFrame.Angles(0, math.rad(180), 0)
    end

    -- Дополнительный translate головы через Neck.C1 (head local frame)
    neck.C1 = originalNeckC1 * CFrame.new(0, off * 0.5, 0)
end

----------------------------------------------------------------
-- FakeLag — velocity freeze (no Anchor!)
----------------------------------------------------------------
local function StartLag(root, hum)
    fl.bufferedCFrame = root.CFrame
    pcall(function()
        root.AssemblyLinearVelocity  = Vector3.zero
        root.AssemblyAngularVelocity = Vector3.zero
        hum:ChangeState(Enum.HumanoidStateType.Physics)
    end)
    fl.phase = "lag"
end

local function StopLag(root, hum)
    pcall(function()
        hum:ChangeState(Enum.HumanoidStateType.GettingUp)
    end)
    if A.FakeLagBackForth and fl.bufferedCFrame then
        pcall(function() root.CFrame = fl.bufferedCFrame end)
    end
    fl.bufferedCFrame = nil
    fl.phase = "release"
end

local function ApplyFakeLag(dt)
    if not A.FakeLag or FlyActive() then
        if fl.phase == "lag" then
            local _, hum, root = GetCharRig()
            if root and hum then StopLag(root, hum) end
        end
        fl.accumulator = 0
        return
    end

    local _, hum, root = GetCharRig()
    if not hum or not root then return end
    fl.accumulator = fl.accumulator + dt

    -- Cycle params per mode
    local intensity, frequency
    local mode = A.FakeLagMode or "Static"
    if mode == "Static" then
        intensity = (A.FakeLagIntensity or 5) / 60
        frequency = A.FakeLagFrequency or 1
    elseif mode == "Random" then
        intensity = math.random(2, math.max(A.FakeLagIntensity or 5, 3)) / 60
        frequency = math.random() * 2 + 0.5
    elseif mode == "Adaptive" then
        local v = root.AssemblyLinearVelocity.Magnitude
        local scale = math.clamp(v / 30, 0.3, 1)
        intensity = ((A.FakeLagIntensity or 5) / 60) * scale
        frequency = A.FakeLagFrequency or 1
    elseif mode == "Switch" then
        intensity = (fl.pulseCount % 2 == 0) and 0.05 or 0.15
        frequency = A.FakeLagFrequency or 1
    else
        intensity = (A.FakeLagIntensity or 5) / 60
        frequency = A.FakeLagFrequency or 1
    end

    local cycle      = 1 / math.max(frequency, 0.1)
    local lagPhase   = math.min(intensity, cycle * 0.7)
    local releasePhT = cycle - lagPhase

    if fl.phase == "release" then
        if fl.accumulator >= releasePhT then
            StartLag(root, hum)
            fl.accumulator = 0
            fl.pulseCount  = fl.pulseCount + 1
        end
    else  -- lag
        if fl.accumulator >= lagPhase then
            StopLag(root, hum)
            fl.accumulator = 0
        else
            -- maintain freeze each frame (game/physics могут вернуть velocity)
            pcall(function()
                root.AssemblyLinearVelocity  = Vector3.zero
                root.AssemblyAngularVelocity = Vector3.zero
            end)
        end
    end
end

----------------------------------------------------------------
-- Visualizer (Drawing line + circle + text)
----------------------------------------------------------------
local function EnsureViz()
    if not drawingAvailable then return end
    if not viz.realLine then
        local ok, l = pcall(Drawing.new, "Line")
        if ok and l then viz.realLine = l; l.Thickness = 2; l.Color = Color3.fromRGB(255, 50, 50); l.Visible = false end
    end
    if not viz.fakeLine then
        local ok, l = pcall(Drawing.new, "Line")
        if ok and l then viz.fakeLine = l; l.Thickness = 2; l.Color = Color3.fromRGB(50, 255, 50); l.Visible = false end
    end
    if not viz.circle then
        local ok, c = pcall(Drawing.new, "Circle")
        if ok and c then
            viz.circle = c; c.Thickness = 2; c.NumSides = 32; c.Filled = false
            c.Color = Color3.fromRGB(80, 80, 255); c.Visible = false
        end
    end
    if not viz.text then
        local ok, t = pcall(Drawing.new, "Text")
        if ok and t then
            viz.text = t; t.Size = 13; t.Color = Color3.fromRGB(255, 255, 255)
            t.Outline = true; t.Center = true; t.Visible = false
        end
    end
end

local function HideViz()
    if viz.realLine then viz.realLine.Visible = false end
    if viz.fakeLine then viz.fakeLine.Visible = false end
    if viz.circle   then viz.circle.Visible   = false end
    if viz.text     then viz.text.Visible     = false end
end

local function DestroyViz()
    if viz.realLine then pcall(function() viz.realLine:Remove() end); viz.realLine = nil end
    if viz.fakeLine then pcall(function() viz.fakeLine:Remove() end); viz.fakeLine = nil end
    if viz.circle   then pcall(function() viz.circle:Remove()   end); viz.circle   = nil end
    if viz.text     then pcall(function() viz.text:Remove()     end); viz.text     = nil end
end

local function UpdateVisualizer()
    if not drawingAvailable then return end
    if not A.Visualizer then HideViz(); return end
    EnsureViz()

    local _, _, root = GetCharRig()
    if not root then HideViz(); return end
    local cam = workspace.CurrentCamera
    if not cam then HideViz(); return end

    -- "real" — server видит HRP.LookVector (оригинал), потому что C0 — visual-only.
    -- "fake" — то, куда визуально смотрит client (HRP * total Y rotation).
    local realLook = root.CFrame.LookVector
    local fakeAng  = ComputeJitterAngle() + ComputeDesyncAngle()
                   + GetPredictorBias() + GetMicroJitter()
    local fakeLook = (root.CFrame * CFrame.Angles(0, fakeAng, 0)).LookVector

    local headWorld = root.Position + Vector3.new(0, 3, 0)
    local realPt    = root.Position + realLook * 5
    local fakePt    = root.Position + fakeLook * 5

    local hSp = cam:WorldToViewportPoint(headWorld)
    local rSp = cam:WorldToViewportPoint(realPt)
    local fSp = cam:WorldToViewportPoint(fakePt)

    if hSp.Z > 0 then
        local headV2 = Vector2.new(hSp.X, hSp.Y)

        if rSp.Z > 0 and viz.realLine then
            viz.realLine.From = headV2
            viz.realLine.To   = Vector2.new(rSp.X, rSp.Y)
            viz.realLine.Visible = true
        elseif viz.realLine then viz.realLine.Visible = false end

        if fSp.Z > 0 and viz.fakeLine then
            viz.fakeLine.From = headV2
            viz.fakeLine.To   = Vector2.new(fSp.X, fSp.Y)
            viz.fakeLine.Visible = true
        elseif viz.fakeLine then viz.fakeLine.Visible = false end

        if viz.circle then
            viz.circle.Position = headV2
            viz.circle.Radius   = 8
            viz.circle.Color    = (fl.phase == "lag")
                                  and Color3.fromRGB(255, 200, 50)
                                  or  Color3.fromRGB(80, 80, 255)
            viz.circle.Visible  = true
        end

        if viz.text then
            viz.text.Position = Vector2.new(headV2.X, headV2.Y - 28)
            viz.text.Text = string.format("J:%s D:%s%s%s%s",
                A.Jitter and (A.JitterMode or "?") or "off",
                A.Desync and (A.DesyncMode or "?") or "off",
                A.FakeLag and (" | LAG-" .. fl.phase) or "",
                A.ResolverBypass and " | RB" or "",
                A.Predictor and " | P" or "")
            viz.text.Visible = true
        end
    else
        HideViz()
    end
end

----------------------------------------------------------------
-- Main loops
----------------------------------------------------------------
local function HeartbeatStep(dt)
    if not _G.Settings or not _G.Settings.AntiAim then return end
    ApplyAngles()
    ApplyBufferTeleport()
    ApplyHideHead()
    ApplyFakeLag(dt)
end

table.insert(connections, RunService.Heartbeat:Connect(HeartbeatStep))

pcall(function()
    RunService:BindToRenderStep(STEP_NAME_VIS, Enum.RenderPriority.Camera.Value + 3, UpdateVisualizer)
end)

----------------------------------------------------------------
-- CharacterAdded — полный сброс state
----------------------------------------------------------------
table.insert(connections, LocalPlayer.CharacterAdded:Connect(function(char)
    originalRootC0  = nil
    originalNeckC0  = nil
    originalNeckC1  = nil
    originalLowerC0 = nil

    jitterRandWalk    = 0
    jitterPatternIdx  = 1
    jitterPatternTime = 0

    switchSide  = 1
    lastSwitchT = 0

    bufferPhase  = 0
    bufferOrigCF = nil
    lastBufferT  = 0

    fl.phase           = "release"
    fl.accumulator     = 0
    fl.bufferedCFrame  = nil
    fl.pulseCount      = 0

    char:WaitForChild("HumanoidRootPart", 5)
end))

----------------------------------------------------------------
-- Disconnect — restore everything
----------------------------------------------------------------
local function Disconnect()
    pcall(function() RunService:UnbindFromRenderStep(STEP_NAME_VIS) end)
    for _, c in ipairs(connections) do
        if c and c.Connected then pcall(function() c:Disconnect() end) end
    end
    table.clear(connections)

    local char, hum, root = GetCharRig()

    -- Restore RootJoint.C0
    if root and originalRootC0 then
        local j = GetRootJoint(root)
        if j then pcall(function() j.C0 = originalRootC0 end) end
    end
    -- Restore Neck.C0/C1
    if char and originalNeckC0 then
        local n = GetNeck(char)
        if n then pcall(function() n.C0 = originalNeckC0 end) end
    end
    if char and originalNeckC1 then
        local n = GetNeck(char)
        if n then pcall(function() n.C1 = originalNeckC1 end) end
    end
    -- Restore LowerTorso.Waist.C0
    if char and originalLowerC0 then
        local w = GetLowerJoint(char)
        if w then pcall(function() w.C0 = originalLowerC0 end) end
    end

    -- Stop active fake lag (без Anchor — просто выйти из Physics state)
    if fl.phase == "lag" and root and hum then
        pcall(function() hum:ChangeState(Enum.HumanoidStateType.GettingUp) end)
    end

    DestroyViz()

    originalRootC0  = nil
    originalNeckC0  = nil
    originalNeckC1  = nil
    originalLowerC0 = nil
end

_G.ABYSS_AntiAim = { Disconnect = Disconnect }
print("[ABYSS] AntiAim v4 ELITE loaded — Jitter+Desync(C0+Buffered)+HideHead+FakeLag(NoAnchor)+Visualizer")
