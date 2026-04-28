-- ============================================================
-- 5.lua / AntiAim.lua  — ABYSS ARCHON / Modular
-- Modern AntiAim:
--   - Jitter (RootJoint.C0, modes: Random / Sine / Static)
--   - Desync (AlignOrientation, modes: Static / Spin / Random / Switch / Backwards)
--   - HideHead (Neck.C0, modes: Back / Down / Offset)
--   - FakeLag (Anchor + Humanoid:ChangeState(Physics) + buffered CFrame teleport)
--   - Visualizer (Drawing line/circle/text — реальный угол тела на сервере)
-- Конфликт со Spinbot решён в Movement.lua (Spinbot уступает Desync).
-- ============================================================

local Players    = game:GetService("Players")
local RunService = game:GetService("RunService")

----------------------------------------------------------------
-- 1. Защита от повторной загрузки
----------------------------------------------------------------
if _G.ABYSS_AntiAim and type(_G.ABYSS_AntiAim.Disconnect) == "function" then
    pcall(_G.ABYSS_AntiAim.Disconnect)
end
_G.ABYSS_AntiAim = nil

----------------------------------------------------------------
-- 2. Settings + дефолты (мерж с существующими)
----------------------------------------------------------------
_G.Settings = _G.Settings or {}
local A = _G.Settings.AntiAim or {}

if A.Jitter         == nil then A.Jitter         = false end
if A.Desync         == nil then A.Desync         = false end
if A.HideHead       == nil then A.HideHead       = false end
if A.FakeLag        == nil then A.FakeLag        = false end
if A.FakeLagNoClip  == nil then A.FakeLagNoClip  = true  end
if A.Visualizer     == nil then A.Visualizer     = false end

A.JitterAngle      = tonumber(A.JitterAngle)      or 40
A.JitterMode       = A.JitterMode                 or "Random"   -- Random / Sine / Static
A.DesyncType       = A.DesyncType                 or "Spin"     -- Static / Spin / Random / Switch / Backwards
A.DesyncSpeed      = tonumber(A.DesyncSpeed)      or 30
A.DesyncStrength   = tonumber(A.DesyncStrength)   or 1.0        -- 0..1
A.HideHeadMode     = A.HideHeadMode               or "Back"     -- Back / Down / Offset
A.FakeLagIntensity = tonumber(A.FakeLagIntensity) or 5
A.FakeLagFrequency = tonumber(A.FakeLagFrequency) or 1
A.FakeLagMode      = A.FakeLagMode                or "Random"   -- Random / BackAndForth

_G.Settings.AntiAim = A

local LocalPlayer = Players.LocalPlayer

----------------------------------------------------------------
-- 3. State
----------------------------------------------------------------
local connections   = {}
local STEP_NAME_VIS = "ABYSS_AntiAimVis"

local originalRootC0 = nil
local originalNeckC0 = nil

local desyncAtt   = nil
local desyncAlign = nil

-- FakeLag
local fl = {
    accumulator              = 0,
    isLagging                = false,
    bufferedCFrame           = nil,
    originalAnchored         = nil,
    noclipApplied            = false,
    noclipCanCollideOriginal = setmetatable({}, { __mode = "k" }),
}

-- Desync Switch state
local switchSide  = 1
local lastSwitchT = 0

-- Visualizer
local viz = { line = nil, circle = nil, text = nil }
local drawingAvailable = type(Drawing) == "table" and type(Drawing.new) == "function"

----------------------------------------------------------------
-- 4. Utility
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

----------------------------------------------------------------
-- 5. Jitter (RootJoint.C0, всегда от originalRootC0)
----------------------------------------------------------------
local function ApplyJitter()
    local _, _, root = GetCharRig()
    if not root then return end
    local joint = GetRootJoint(root)
    if not joint then return end

    if not originalRootC0 then originalRootC0 = joint.C0 end

    if not A.Jitter then
        if joint.C0 ~= originalRootC0 then joint.C0 = originalRootC0 end
        return
    end

    local maxAng = math.rad(A.JitterAngle or 40)
    local angle  = 0
    local mode   = A.JitterMode

    if mode == "Sine" then
        angle = math.sin(tick() * 12) * maxAng
    elseif mode == "Static" then
        angle = maxAng
    else  -- Random
        angle = (math.random() * 2 - 1) * maxAng
    end

    joint.C0 = originalRootC0 * CFrame.Angles(0, angle, 0)
end

----------------------------------------------------------------
-- 6. Desync (AlignOrientation на Y-оси)
----------------------------------------------------------------
local function EnsureDesyncRig()
    local _, _, root = GetCharRig()
    if not root then return end
    if desyncAtt and desyncAtt.Parent == root
       and desyncAlign and desyncAlign.Parent then return end

    if desyncAlign then pcall(function() desyncAlign:Destroy() end); desyncAlign = nil end
    if desyncAtt   then pcall(function() desyncAtt:Destroy()   end); desyncAtt   = nil end

    desyncAtt = Instance.new("Attachment")
    desyncAtt.Name   = "ABYSS_DesyncAtt"
    desyncAtt.Parent = root

    desyncAlign = Instance.new("AlignOrientation")
    desyncAlign.Name             = "ABYSS_DesyncAlign"
    desyncAlign.Mode             = Enum.OrientationAlignmentMode.OneAttachment
    desyncAlign.Attachment0      = desyncAtt
    desyncAlign.MaxTorque        = math.huge
    desyncAlign.Responsiveness   = 200
    desyncAlign.RigidityEnabled  = false
    desyncAlign.Parent           = root
end

local function DestroyDesyncRig()
    if desyncAlign then pcall(function() desyncAlign:Destroy() end); desyncAlign = nil end
    if desyncAtt   then pcall(function() desyncAtt:Destroy()   end); desyncAtt   = nil end
end

local function ApplyDesync()
    if not A.Desync then
        DestroyDesyncRig()
        return
    end

    local _, _, root = GetCharRig()
    if not root then return end

    EnsureDesyncRig()
    if not desyncAlign then return end

    local strength = math.clamp(A.DesyncStrength or 1, 0, 1)
    local mode     = A.DesyncType
    local rot      = 0

    if mode == "Static" then
        rot = math.rad(60) * strength
    elseif mode == "Spin" then
        rot = math.rad(tick() * (A.DesyncSpeed or 30)) * strength
    elseif mode == "Random" then
        rot = (math.random() * 2 - 1) * math.rad(120) * strength
    elseif mode == "Switch" then
        local interval = 1 / math.max((A.DesyncSpeed or 30) / 10, 0.5)
        if tick() - lastSwitchT > interval then
            switchSide = -switchSide
            lastSwitchT = tick()
        end
        rot = math.rad(60) * strength * switchSide
    elseif mode == "Backwards" then
        rot = math.rad(180) * strength
    end

    desyncAlign.CFrame = CFrame.Angles(0, rot, 0)
end

----------------------------------------------------------------
-- 7. HideHead (Neck.C0 + offset translation в режиме Offset)
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
        return
    end

    if not originalNeckC0 then originalNeckC0 = neck.C0 end

    local mode = A.HideHeadMode
    if mode == "Down" then
        neck.C0 = originalNeckC0 * CFrame.Angles(math.rad(-90), 0, 0)
    elseif mode == "Offset" then
        -- Combined: rotate 180° + translate down (visual head внутри тела)
        neck.C0 = originalNeckC0 * CFrame.new(0, -1.5, 0) * CFrame.Angles(0, math.rad(180), 0)
    else  -- Back (default)
        neck.C0 = originalNeckC0 * CFrame.Angles(0, math.rad(180), 0)
    end
end

----------------------------------------------------------------
-- 8. FakeLag — controlled latency simulation
--    Trick: периодически Anchor + Humanoid:ChangeState(Physics)
--    замораживает реплицируемую позицию HRP, потом резкое release.
--    Optional NoClip на время лаг-фазы (FakeLagNoClip).
--    BackAndForth — телепорт обратно в буферизованный CFrame на release.
----------------------------------------------------------------
local function ApplyFakeLagNoClip(enable)
    local char = LocalPlayer.Character
    if not char then return end
    if enable then
        for _, p in ipairs(char:GetDescendants()) do
            if p:IsA("BasePart") and p.CanCollide then
                fl.noclipCanCollideOriginal[p] = p.CanCollide
                p.CanCollide = false
            end
        end
        fl.noclipApplied = true
    else
        for p, cc in pairs(fl.noclipCanCollideOriginal) do
            pcall(function() p.CanCollide = cc end)
        end
        table.clear(fl.noclipCanCollideOriginal)
        fl.noclipApplied = false
    end
end

local function StartFakeLag()
    local _, hum, root = GetCharRig()
    if not root or not hum then return end
    if fl.isLagging then return end

    fl.bufferedCFrame   = root.CFrame
    fl.originalAnchored = root.Anchored

    pcall(function()
        if A.FakeLagNoClip then ApplyFakeLagNoClip(true) end
        hum:ChangeState(Enum.HumanoidStateType.Physics)
        root.Anchored = true
    end)
    fl.isLagging = true
end

local function StopFakeLag()
    local _, hum, root = GetCharRig()
    if not root or not hum then return end
    if not fl.isLagging then return end

    pcall(function()
        root.Anchored = fl.originalAnchored or false
        hum:ChangeState(Enum.HumanoidStateType.GettingUp)
        if fl.noclipApplied then ApplyFakeLagNoClip(false) end
    end)

    if A.FakeLagMode == "BackAndForth" and fl.bufferedCFrame then
        pcall(function() root.CFrame = fl.bufferedCFrame end)
    end

    fl.bufferedCFrame   = nil
    fl.originalAnchored = nil
    fl.isLagging        = false
end

local function ApplyFakeLag(dt)
    if not A.FakeLag then
        if fl.isLagging then StopFakeLag() end
        fl.accumulator = 0
        return
    end

    local _, hum, root = GetCharRig()
    if not hum or not root then return end

    fl.accumulator = fl.accumulator + dt
    local frequency  = math.clamp(A.FakeLagFrequency or 1, 0.1, 10)
    local intensity  = math.clamp(A.FakeLagIntensity or 5, 1, 30) / 60  -- сек активного lag
    local cycle      = 1 / frequency
    local lagPhase   = math.min(intensity, cycle * 0.7)
    local releaseT   = cycle - lagPhase

    if not fl.isLagging then
        if fl.accumulator >= releaseT then
            StartFakeLag()
            fl.accumulator = 0
        end
    else
        if fl.accumulator >= lagPhase then
            StopFakeLag()
            fl.accumulator = 0
        end
    end
end

----------------------------------------------------------------
-- 9. Visualizer (Drawing line/circle/text)
----------------------------------------------------------------
local function EnsureVisualizer()
    if not drawingAvailable then return end
    if not viz.line then
        local ok, l = pcall(Drawing.new, "Line")
        if ok and l then
            viz.line = l
            l.Thickness = 2
            l.Color     = Color3.fromRGB(255, 80, 80)
            l.Visible   = false
        end
    end
    if not viz.circle then
        local ok, c = pcall(Drawing.new, "Circle")
        if ok and c then
            viz.circle = c
            c.Thickness = 2
            c.NumSides  = 32
            c.Filled    = false
            c.Color     = Color3.fromRGB(80, 255, 80)
            c.Visible   = false
        end
    end
    if not viz.text then
        local ok, t = pcall(Drawing.new, "Text")
        if ok and t then
            viz.text = t
            t.Size    = 14
            t.Color   = Color3.fromRGB(255, 255, 255)
            t.Outline = true
            t.Center  = true
            t.Visible = false
        end
    end
end

local function HideVisualizer()
    if viz.line   then viz.line.Visible   = false end
    if viz.circle then viz.circle.Visible = false end
    if viz.text   then viz.text.Visible   = false end
end

local function DestroyVisualizer()
    if viz.line   then pcall(function() viz.line:Remove()   end); viz.line   = nil end
    if viz.circle then pcall(function() viz.circle:Remove() end); viz.circle = nil end
    if viz.text   then pcall(function() viz.text:Remove()   end); viz.text   = nil end
end

local function UpdateVisualizer()
    if not drawingAvailable then return end
    if not A.Visualizer then HideVisualizer(); return end

    EnsureVisualizer()

    local _, _, root = GetCharRig()
    if not root then HideVisualizer(); return end
    local cam = workspace.CurrentCamera
    if not cam then HideVisualizer(); return end

    -- Реальный (server-side) угол: HRP.CFrame * desyncAlign rotation
    local realCFrame = root.CFrame
    if A.Desync and desyncAlign then
        realCFrame = CFrame.new(root.Position) * desyncAlign.CFrame
    end

    local headPos = root.Position + Vector3.new(0, 3, 0)
    local lookPos = root.Position + realCFrame.LookVector * 4

    local hSp = cam:WorldToViewportPoint(headPos)
    local lSp = cam:WorldToViewportPoint(lookPos)

    if hSp.Z > 0 and lSp.Z > 0 then
        if viz.line then
            viz.line.From    = Vector2.new(hSp.X, hSp.Y)
            viz.line.To      = Vector2.new(lSp.X, lSp.Y)
            viz.line.Visible = true
        end
        if viz.circle then
            viz.circle.Position = Vector2.new(hSp.X, hSp.Y)
            viz.circle.Radius   = 8
            viz.circle.Visible  = true
        end
        if viz.text then
            viz.text.Position = Vector2.new(hSp.X, hSp.Y - 26)
            viz.text.Text     = string.format("%s | str %.1f%s",
                A.DesyncType or "off",
                A.DesyncStrength or 0,
                fl.isLagging and " | LAG" or "")
            viz.text.Visible = true
        end
    else
        HideVisualizer()
    end
end

----------------------------------------------------------------
-- 10. Main loops
----------------------------------------------------------------
local function HeartbeatStep(dt)
    if not _G.Settings or not _G.Settings.AntiAim then return end
    ApplyJitter()
    ApplyDesync()
    ApplyHideHead()
    ApplyFakeLag(dt)
end

table.insert(connections, RunService.Heartbeat:Connect(HeartbeatStep))

pcall(function()
    RunService:BindToRenderStep(STEP_NAME_VIS, Enum.RenderPriority.Camera.Value + 3, UpdateVisualizer)
end)

----------------------------------------------------------------
-- 11. CharacterAdded — сброс всех cached references
----------------------------------------------------------------
table.insert(connections, LocalPlayer.CharacterAdded:Connect(function(char)
    originalRootC0 = nil
    originalNeckC0 = nil

    desyncAtt   = nil
    desyncAlign = nil

    fl.isLagging        = false
    fl.accumulator      = 0
    fl.bufferedCFrame   = nil
    fl.originalAnchored = nil
    fl.noclipApplied    = false
    table.clear(fl.noclipCanCollideOriginal)

    switchSide  = 1
    lastSwitchT = 0

    char:WaitForChild("HumanoidRootPart", 5)
end))

----------------------------------------------------------------
-- 12. Disconnect — restore everything
----------------------------------------------------------------
local function Disconnect()
    pcall(function() RunService:UnbindFromRenderStep(STEP_NAME_VIS) end)
    for _, c in ipairs(connections) do
        if c and c.Connected then pcall(function() c:Disconnect() end) end
    end
    table.clear(connections)

    -- Restore Motor6D originals
    local char, _, root = GetCharRig()
    if root and originalRootC0 then
        local j = GetRootJoint(root)
        if j then pcall(function() j.C0 = originalRootC0 end) end
    end
    if char and originalNeckC0 then
        local neck = GetNeck(char)
        if neck then pcall(function() neck.C0 = originalNeckC0 end) end
    end

    -- Stop active fake lag
    if fl.isLagging then StopFakeLag() end
    if fl.noclipApplied then ApplyFakeLagNoClip(false) end

    -- Destroy desync rig
    DestroyDesyncRig()

    -- Visualizer
    DestroyVisualizer()

    originalRootC0 = nil
    originalNeckC0 = nil
end

_G.ABYSS_AntiAim = { Disconnect = Disconnect }
print("[ABYSS] AntiAim loaded — Jitter+Desync+HideHead+FakeLag+Visualizer")
