-- === ЗАМЕНИ ЭТОТ ФАЙЛ НА ПОЛНОСТЬЮ ===
-- FILENAME: Movement.lua
-- ============================================================
-- Movement.lua — ABYSS ARCHON / Modular  (v4 ELITE)
--   Fly       : LinearVelocity + AlignOrientation, smooth fade,
--               air control, velocity preservation
--   SpeedHack : сохраняет оригинал WalkSpeed + VelocityMultiplier boost
--   HitboxExp : whitelist частей + TransparencyMode (Inv/Trans/Opaque)
--   NoClip    : Standard / Advanced (GetPropertyChangedSignal hook)
--   InfJump   : VelocityBoost + AntiSpam cooldown
--   Spinbot   : Yaw / Pitch / Roll / Random; off если AntiAim.Desync
--   Bhop      : continuous-jump while Space held
--   Все включения через change-detection (без операций каждый Heartbeat).  
-- ============================================================

local Players          = game:GetService("Players")
local RunService       = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

if _G.ABYSS_Movement and type(_G.ABYSS_Movement.Disconnect) == "function" then
    pcall(_G.ABYSS_Movement.Disconnect)
end
_G.ABYSS_Movement = nil

-- Settings: defensive merge
_G.Settings                = _G.Settings or {}
_G.Settings.Fly            = _G.Settings.Fly or {}
_G.Settings.SpeedHack      = _G.Settings.SpeedHack or {}
_G.Settings.HitboxExpander = _G.Settings.HitboxExpander or {}
_G.Settings.Rage           = _G.Settings.Rage or {}
_G.Settings.Movement       = _G.Settings.Movement or {}

local F  = _G.Settings.Fly
local SH = _G.Settings.SpeedHack
local HX = _G.Settings.HitboxExpander
local R  = _G.Settings.Rage
local M  = _G.Settings.Movement

if F.Enabled              == nil then F.Enabled              = false end
if F.AirControl           == nil then F.AirControl           = true  end
if F.VelocityPreservation == nil then F.VelocityPreservation = true  end
F.Speed = tonumber(F.Speed) or 58

if SH.Enabled == nil then SH.Enabled = false end
SH.Speed = tonumber(SH.Speed) or 50

if HX.Enabled == nil then HX.Enabled = false end
HX.Size              = tonumber(HX.Size) or 12
HX.PartsWhitelist    = HX.PartsWhitelist or { "Head", "UpperTorso", "LowerTorso", "Torso" }
HX.TransparencyMode  = HX.TransparencyMode or "Translucent"  -- Invisible / Translucent / Opaque
HX.TransparencyValue = tonumber(HX.TransparencyValue) or 0.7

if R.Spinbot == nil then R.Spinbot = false end
R.SpinSpeed = tonumber(R.SpinSpeed) or 25
R.SpinMode  = R.SpinMode or "Yaw"

M.FlySmoothness        = tonumber(M.FlySmoothness)        or 6
if M.BhopEnabled == nil then M.BhopEnabled = false end
M.VelocityMultiplier   = tonumber(M.VelocityMultiplier)   or 1
M.NoClipMode           = M.NoClipMode                     or "Standard"  -- Standard / Advanced
M.InfJumpVelocityBoost = tonumber(M.InfJumpVelocityBoost) or 0
M.InfJumpCooldown      = tonumber(M.InfJumpCooldown)      or 0.22
M.VelocityCap          = tonumber(M.VelocityCap)          or 200

if _G.Settings.InfJump == nil then _G.Settings.InfJump = false end
if _G.Settings.NoClip  == nil then _G.Settings.NoClip  = false end

local LocalPlayer = Players.LocalPlayer
local connections = {}

-- Кэш os.clock (FIX #2: tick() устарел и нестабилен в некоторых условиях)
local osClock = os.clock

-- Кэши
local lastNoClip          = nil
local lastNoClipMode      = nil
local lastHitboxEnabled   = nil
local lastHitboxSize      = nil
local lastHitboxTrMode    = nil
local originalWalkSpeed   = nil
local originalCanCollide  = setmetatable({}, { __mode = "k" })
local originalHitbox      = setmetatable({}, { __mode = "k" })
local advancedNoClipConn  = {}
local lastJumpTime        = 0

-- Fly state
local fly = {
    attachment   = nil,
    linearVel    = nil,
    align        = nil,
    enabled      = false,
    fadeAlpha    = 0,
    targetAlpha  = 0,
    inputVel     = Vector3.zero,
    lastVelocity = Vector3.zero,
    captured     = false,  -- FIX #5: флаг "lastVelocity захвачен в этой сессии"
}

local function GetCharRig()
    local char = LocalPlayer.Character
    if not char then return nil, nil, nil end
    local hum  = char:FindFirstChildOfClass("Humanoid")
    local root = char:FindFirstChild("HumanoidRootPart")
    if not hum or not root then return nil, nil, nil end
    return char, hum, root
end

-- ============================================================
-- Fly
-- ============================================================
local function DestroyFly()
    if fly.linearVel  then pcall(function() fly.linearVel:Destroy()  end) end
    if fly.align      then pcall(function() fly.align:Destroy()      end) end
    if fly.attachment then pcall(function() fly.attachment:Destroy() end) end
    fly.linearVel, fly.align, fly.attachment = nil, nil, nil
    fly.enabled = false
end

local function CreateFly()
    local _, hum, root = GetCharRig()
    if not root or not hum then return false end
    if fly.attachment and fly.attachment.Parent == root
       and fly.linearVel and fly.linearVel.Parent
       and fly.align     and fly.align.Parent then
        fly.enabled = true; return true
    end
    DestroyFly()

    fly.attachment = Instance.new("Attachment")
    fly.attachment.Name   = "ABYSS_FlyAtt"
    fly.attachment.Parent = root

    fly.linearVel = Instance.new("LinearVelocity")
    fly.linearVel.Name                   = "ABYSS_FlyVel"
    fly.linearVel.Attachment0            = fly.attachment
    fly.linearVel.MaxForce               = math.huge
    fly.linearVel.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
    fly.linearVel.VectorVelocity         = Vector3.zero
    fly.linearVel.Parent                 = root

    fly.align = Instance.new("AlignOrientation")
    fly.align.Name             = "ABYSS_FlyAlign"
    fly.align.Mode             = Enum.OrientationAlignmentMode.OneAttachment
    fly.align.Attachment0      = fly.attachment
    fly.align.MaxTorque        = math.huge
    fly.align.Responsiveness   = 200
    fly.align.RigidityEnabled  = false
    fly.align.Parent           = root

    fly.enabled = true
    return true
end

-- ============================================================
-- NoClip (Standard + Advanced)
-- ============================================================
local function ClearAdvancedNoClip()
    for _, c in ipairs(advancedNoClipConn) do
        if c.Connected then pcall(function() c:Disconnect() end) end
    end
    table.clear(advancedNoClipConn)
end

local function ApplyNoClip(enable, mode)
    ClearAdvancedNoClip()
    local char = LocalPlayer.Character
    if not char then return end
    for _, part in ipairs(char:GetDescendants()) do
        if part:IsA("BasePart") then
            if enable then
                if originalCanCollide[part] == nil then
                    originalCanCollide[part] = part.CanCollide
                end
                part.CanCollide = false
                if mode == "Advanced" then
                    -- держим CanCollide=false даже если игра пытается восстановить
                    local conn = part:GetPropertyChangedSignal("CanCollide"):Connect(function()
                        if part.CanCollide then part.CanCollide = false end
                    end)
                    table.insert(advancedNoClipConn, conn)
                end
            else
                if originalCanCollide[part] ~= nil then
                    part.CanCollide = originalCanCollide[part]
                    originalCanCollide[part] = nil
                end
            end
        end
    end
end

-- ============================================================
-- HitboxExpander (whitelist + TransparencyMode)
-- ============================================================
local function IsWhitelisted(partName)
    local list = HX.PartsWhitelist
    if not list or #list == 0 then return true end
    for _, name in ipairs(list) do
        if partName == name then return true end
    end
    return false
end

local function ApplyHitbox()
    local enabled = HX.Enabled
    local size    = HX.Size or 12
    local trMode  = HX.TransparencyMode or "Translucent"
    local trVal   = HX.TransparencyValue or 0.7

    for _, plr in ipairs(Players:GetPlayers()) do
        if plr == LocalPlayer or not plr.Character then continue end
        for _, part in ipairs(plr.Character:GetChildren()) do
            if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" then
                local listOk = IsWhitelisted(part.Name)
                if enabled and listOk then
                    if not originalHitbox[part] then
                        originalHitbox[part] = {
                            Size         = part.Size,
                            Transparency = part.Transparency,
                        }
                    end
                    if part.Size.X ~= size then
                        part.Size = Vector3.new(size, size, size)
                    end
                    if trMode == "Invisible" then
                        part.Transparency = 1
                    elseif trMode == "Opaque" then
                        part.Transparency = 0
                    else
                        part.Transparency = trVal
                    end
                elseif originalHitbox[part] then
                    part.Size         = originalHitbox[part].Size
                    part.Transparency = originalHitbox[part].Transparency
                    originalHitbox[part] = nil
                end
            end
        end
    end
end

-- ============================================================
-- Spinbot
-- ============================================================
-- FIX #1: Spinbot теперь использует dt — SpinSpeed интерпретируется как
-- градусы/сек (раньше был "за кадр", FPS-зависимая аномалия).
local function ApplySpinbot(root, dt)
    if not root or not dt then return end
    local A = _G.Settings.AntiAim
    if A and A.Desync then return end  -- conflict guard
    if not (R and R.Spinbot) then return end

    local angle = math.rad(R.SpinSpeed or 25) * dt
    local mode = R.SpinMode or "Yaw"
    local rot
    if mode == "Yaw" then
        rot = CFrame.Angles(0, angle, 0)
    elseif mode == "Pitch" then
        rot = CFrame.Angles(angle, 0, 0)
    elseif mode == "Roll" then
        rot = CFrame.Angles(0, 0, angle)
    elseif mode == "Random" then
        local axis = math.random(1, 3)
        rot = (axis == 1) and CFrame.Angles(0, angle, 0)
              or (axis == 2) and CFrame.Angles(angle, 0, 0)
              or CFrame.Angles(0, 0, angle)
    else
        rot = CFrame.Angles(0, angle, 0)
    end
    root.CFrame = root.CFrame * rot
end

-- ============================================================
-- Heartbeat
-- ============================================================
local function Heartbeat(dt)
    if not _G.Settings then return end
    local char, hum, root = GetCharRig()
    if not char then
        if fly.targetAlpha ~= 0 then fly.targetAlpha = 0 end
        return
    end

    -- NoClip (apply on change: enabled OR mode change)
    local nc = _G.Settings.NoClip and true or false
    if nc ~= lastNoClip or (nc and M.NoClipMode ~= lastNoClipMode) then
        ApplyNoClip(nc, M.NoClipMode)
        lastNoClip     = nc
        lastNoClipMode = M.NoClipMode
    end

    -- Hitbox (apply on change: enabled OR size OR transparency mode change)
    if HX.Enabled ~= lastHitboxEnabled
       or HX.Size ~= lastHitboxSize
       or HX.TransparencyMode ~= lastHitboxTrMode then
        ApplyHitbox()
        lastHitboxEnabled = HX.Enabled
        lastHitboxSize    = HX.Size
        lastHitboxTrMode  = HX.TransparencyMode
    end

    -- SpeedHack (cached original)
    if SH.Enabled then
        if originalWalkSpeed == nil then originalWalkSpeed = hum.WalkSpeed end
        local target = SH.Speed or 50
        if hum.WalkSpeed ~= target then hum.WalkSpeed = target end
    elseif originalWalkSpeed and hum.WalkSpeed ~= originalWalkSpeed then
        hum.WalkSpeed = originalWalkSpeed
    end

    -- FIX #4: VelocityMultiplier — плавный Lerp вместо мгновенной замены.
    -- Раньше горизонтальная скорость прыгала к target за 1 кадр → рывки + детект.
    -- Теперь интерполируем с smoothness (берём M.FlySmoothness или дефолт 8).
    if M.VelocityMultiplier and M.VelocityMultiplier > 1 then
        local moveDir = hum.MoveDirection
        if moveDir.Magnitude > 0.1 then
            local v = root.AssemblyLinearVelocity
            local target = moveDir * (hum.WalkSpeed * M.VelocityMultiplier)

            -- Интерполяция горизонтальной составляющей (Y оставляем как есть)
            local smoothness = M.FlySmoothness or 8
            local k = math.min(dt * smoothness, 1)
            local curH    = Vector3.new(v.X, 0, v.Z)
            local tgtH    = Vector3.new(target.X, 0, target.Z)
            local smoothH = curH:Lerp(tgtH, k)

            -- Cap применяем уже к сглаженной скорости
            local cap = M.VelocityCap or 200
            if smoothH.Magnitude > cap then smoothH = smoothH.Unit * cap end

            root.AssemblyLinearVelocity = Vector3.new(smoothH.X, v.Y, smoothH.Z)
        end
    end

    -- InfJump (FIX #2: tick() → os.clock())
    if _G.Settings.InfJump and UserInputService:IsKeyDown(Enum.KeyCode.Space)
       and osClock() - lastJumpTime > (M.InfJumpCooldown or 0.22) then
        hum:ChangeState(Enum.HumanoidStateType.Jumping)
        if (M.InfJumpVelocityBoost or 0) > 0 then
            local v = root.AssemblyLinearVelocity
            root.AssemblyLinearVelocity = Vector3.new(v.X, v.Y + M.InfJumpVelocityBoost, v.Z)
        end
        lastJumpTime = osClock()
    end

    -- Bhop (FIX #3: убран RunningNoPhysics — нестабильный enum;
    -- + проверка что не сфокусировано текстовое поле, чтобы не прыгать в чате)
    if M.BhopEnabled
       and UserInputService:IsKeyDown(Enum.KeyCode.Space)
       and not UserInputService:GetFocusedTextBox() then
        local s = hum:GetState()
        if s == Enum.HumanoidStateType.Landed
           or s == Enum.HumanoidStateType.Running then
            hum:ChangeState(Enum.HumanoidStateType.Jumping)
        end
    end

    -- Spinbot (FIX #1: передаём dt)
    ApplySpinbot(root, dt)

    -- Fly lifecycle
    local flyOn = F.Enabled
    if flyOn then
        if not fly.enabled or not (fly.linearVel and fly.linearVel.Parent == root) then
            CreateFly()
        end
        fly.targetAlpha = 1
        -- сбрасываем флаг захвата при включении полёта
        fly.captured = false
    else
        -- FIX #5: захват lastVelocity ОДИН РАЗ в момент перехода targetAlpha→0,
        -- ДО того как затухание сделает VectorVelocity ≈ 0.
        if fly.targetAlpha ~= 0 and fly.enabled and F.VelocityPreservation
           and fly.linearVel and fly.linearVel.Parent then
            local snap = fly.linearVel.VectorVelocity
            if snap.Magnitude > 0.5 then
                fly.lastVelocity = snap
                fly.captured = true
            end
        end
        fly.targetAlpha = 0

        if fly.fadeAlpha < 0.01 and fly.enabled then
            DestroyFly()
            if F.VelocityPreservation and fly.captured
               and fly.lastVelocity.Magnitude > 0.5 then
                local cap = M.VelocityCap or 200
                local v = fly.lastVelocity
                if v.Magnitude > cap then v = v.Unit * cap end
                pcall(function() root.AssemblyLinearVelocity = v end)
            end
            fly.lastVelocity = Vector3.zero
            fly.captured = false
        end
    end

    -- Smooth fade (rate = M.FlySmoothness)
    local rate = math.max(M.FlySmoothness or 6, 0.1)
    local k = math.min(dt * rate, 1)
    fly.fadeAlpha = fly.fadeAlpha + (fly.targetAlpha - fly.fadeAlpha) * k
    if fly.fadeAlpha < 0 then fly.fadeAlpha = 0 elseif fly.fadeAlpha > 1 then fly.fadeAlpha = 1 end

    -- Fly drive
    if fly.enabled and fly.linearVel and fly.linearVel.Parent then
        local cam  = workspace.CurrentCamera
        local move = Vector3.zero
        if cam then
            local look, right = cam.CFrame.LookVector, cam.CFrame.RightVector
            if UserInputService:IsKeyDown(Enum.KeyCode.W) then move += look end
            if UserInputService:IsKeyDown(Enum.KeyCode.S) then move -= look end
            if UserInputService:IsKeyDown(Enum.KeyCode.A) then move -= right end
            if UserInputService:IsKeyDown(Enum.KeyCode.D) then move += right end
        end
        if UserInputService:IsKeyDown(Enum.KeyCode.Space)       then move += Vector3.new(0, 1, 0) end
        if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then move -= Vector3.new(0, 1, 0) end

        local rawSpeed   = F.Speed or 58
        local desiredVel = (move.Magnitude > 0) and (move.Unit * rawSpeed) or Vector3.zero

        -- Air control: smooth approach (lerp) instead of instant
        if F.AirControl then
            local accel = math.min(dt * 8, 1)
            fly.inputVel = fly.inputVel:Lerp(desiredVel, accel)
        else
            fly.inputVel = desiredVel
        end

        fly.linearVel.VectorVelocity = fly.inputVel * fly.fadeAlpha
        if fly.align and cam then fly.align.CFrame = cam.CFrame end
    end
end

table.insert(connections, RunService.Heartbeat:Connect(Heartbeat))

-- ============================================================
-- CharacterAdded — корректный сброс
-- ============================================================
table.insert(connections, LocalPlayer.CharacterAdded:Connect(function(char)
    fly.attachment, fly.linearVel, fly.align = nil, nil, nil
    fly.enabled, fly.fadeAlpha, fly.targetAlpha = false, 0, 0
    fly.inputVel, fly.lastVelocity = Vector3.zero, Vector3.zero
    fly.captured = false

    table.clear(originalCanCollide)
    ClearAdvancedNoClip()
    originalWalkSpeed = nil

    lastNoClip        = nil
    lastNoClipMode    = nil
    lastHitboxEnabled = nil
    lastHitboxSize    = nil
    lastHitboxTrMode  = nil

    char:WaitForChild("HumanoidRootPart", 5)
end))

-- Чужие игроки → respawn → пересобрать hitbox expander
-- FIX #6: задержка увеличена 0.2 → 0.5 секунды.
-- Раньше при 0.2с части персонажа ещё не успевали полностью загрузиться
-- (Head/Torso могли отсутствовать), и ApplyHitbox в следующем Heartbeat
-- молча пропускал нового игрока.
local HITBOX_RESPAWN_DELAY = 0.5

table.insert(connections, Players.PlayerAdded:Connect(function(plr)
    plr.CharacterAdded:Connect(function()
        task.wait(HITBOX_RESPAWN_DELAY)
        lastHitboxEnabled = nil
        lastHitboxSize    = nil
        lastHitboxTrMode  = nil
    end)
end))
for _, plr in ipairs(Players:GetPlayers()) do
    if plr ~= LocalPlayer then
        plr.CharacterAdded:Connect(function()
            task.wait(HITBOX_RESPAWN_DELAY)
            lastHitboxEnabled = nil
            lastHitboxSize    = nil
            lastHitboxTrMode  = nil
        end)
    end
end

-- ============================================================
-- Disconnect
-- ============================================================
local function Disconnect()
    for _, c in ipairs(connections) do
        if c and c.Connected then pcall(function() c:Disconnect() end) end
    end
    table.clear(connections)
    DestroyFly()
    ClearAdvancedNoClip()

    for part, can in pairs(originalCanCollide) do
        pcall(function() part.CanCollide = can end)
    end
    table.clear(originalCanCollide)

    for part, orig in pairs(originalHitbox) do
        pcall(function()
            part.Size         = orig.Size
            part.Transparency = orig.Transparency
        end)
    end
    table.clear(originalHitbox)

    if originalWalkSpeed then
        local _, hum = GetCharRig()
        if hum then pcall(function() hum.WalkSpeed = originalWalkSpeed end) end
        originalWalkSpeed = nil
    end
end

_G.ABYSS_Movement = { Disconnect = Disconnect }
print("[ABYSS] Movement v4 ELITE loaded — Fly+Speed+NoClip+Hitbox+Spinbot+Bhop")
