-- ============================================================
-- 4.lua / Movement.lua  — ABYSS ARCHON / Modular
-- Fly (LinearVelocity + AlignOrientation, smooth fade), SpeedHack
-- (с сохранением оригинала), NoClip и HitboxExpander через
-- change-detection (без повторного применения каждый кадр),
-- InfJump, Spinbot (auto-off при AntiAim.Desync).
-- ============================================================

local Players          = game:GetService("Players")
local RunService       = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

----------------------------------------------------------------
-- 1. Защита от повторной загрузки
----------------------------------------------------------------
if _G.ABYSS_Movement and type(_G.ABYSS_Movement.Disconnect) == "function" then
    pcall(_G.ABYSS_Movement.Disconnect)
end
_G.ABYSS_Movement = nil

local LocalPlayer = Players.LocalPlayer
local connections = {}

----------------------------------------------------------------
-- 2. Кэши состояний
----------------------------------------------------------------
local lastNoClip          = nil  -- bool
local lastHitboxEnabled   = nil
local lastHitboxSize      = nil
local originalWalkSpeed   = nil
local originalCanCollide  = setmetatable({}, { __mode = "k" })  -- part -> bool
local originalHitbox      = setmetatable({}, { __mode = "k" })  -- part -> {Size, Transparency}
local lastJumpTime        = 0

-- Fly state
local fly = {
    attachment  = nil,
    linearVel   = nil,
    align       = nil,
    enabled     = false,  -- инстансы созданы и активны
    fadeAlpha   = 0,      -- текущая «громкость» fly (0..1) для плавного включения/выкл
    targetAlpha = 0,      -- куда тянем fadeAlpha
}

----------------------------------------------------------------
-- 3. Утилиты
----------------------------------------------------------------
local function GetCharRig()
    local char = LocalPlayer.Character
    if not char then return nil, nil, nil end
    local hum  = char:FindFirstChildOfClass("Humanoid")
    local root = char:FindFirstChild("HumanoidRootPart")
    if not hum or not root then return nil, nil, nil end
    return char, hum, root
end

----------------------------------------------------------------
-- 4. Fly — LinearVelocity + AlignOrientation
----------------------------------------------------------------
local function DestroyFly()
    if fly.linearVel  then pcall(function() fly.linearVel:Destroy()  end) end
    if fly.align      then pcall(function() fly.align:Destroy()      end) end
    if fly.attachment then pcall(function() fly.attachment:Destroy() end) end
    fly.linearVel  = nil
    fly.align      = nil
    fly.attachment = nil
    fly.enabled    = false
end

local function CreateFly()
    local _, hum, root = GetCharRig()
    if not root or not hum then return false end

    -- если предыдущие инстансы ещё живы и привязаны к текущему root — переиспользуем
    if fly.attachment and fly.attachment.Parent == root
       and fly.linearVel and fly.linearVel.Parent
       and fly.align     and fly.align.Parent then
        fly.enabled = true
        return true
    end

    DestroyFly()  -- чистим, если что-то от старого character осталось

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
    fly.align.Name              = "ABYSS_FlyAlign"
    fly.align.Mode              = Enum.OrientationAlignmentMode.OneAttachment
    fly.align.Attachment0       = fly.attachment
    fly.align.MaxTorque         = math.huge
    fly.align.Responsiveness    = 200
    fly.align.RigidityEnabled   = false
    fly.align.Parent            = root

    fly.enabled = true
    return true
end

----------------------------------------------------------------
-- 5. NoClip (apply on change)
----------------------------------------------------------------
local function ApplyNoClip(enable)
    local char = LocalPlayer.Character
    if not char then return end
    for _, part in ipairs(char:GetDescendants()) do
        if part:IsA("BasePart") then
            if enable then
                if originalCanCollide[part] == nil then
                    originalCanCollide[part] = part.CanCollide
                end
                part.CanCollide = false
            else
                if originalCanCollide[part] ~= nil then
                    part.CanCollide = originalCanCollide[part]
                    originalCanCollide[part] = nil
                end
            end
        end
    end
end

----------------------------------------------------------------
-- 6. HitboxExpander (apply on change)
----------------------------------------------------------------
local function ApplyHitbox()
    local cfg     = _G.Settings.HitboxExpander
    local enabled = cfg.Enabled
    local size    = cfg.Size or 12

    for _, plr in ipairs(Players:GetPlayers()) do
        if plr == LocalPlayer or not plr.Character then continue end
        for _, part in ipairs(plr.Character:GetChildren()) do
            if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" then
                if enabled then
                    if not originalHitbox[part] then
                        originalHitbox[part] = {
                            Size         = part.Size,
                            Transparency = part.Transparency,
                        }
                    end
                    if part.Size.X ~= size then
                        part.Size         = Vector3.new(size, size, size)
                        part.Transparency = 0.7
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

----------------------------------------------------------------
-- 7. Главный Heartbeat
----------------------------------------------------------------
local function Heartbeat(dt)
    if not _G.Settings then return end

    local char, hum, root = GetCharRig()
    if not char then
        -- Без character — только fade fly к нулю и destroy если можно
        if fly.targetAlpha ~= 0 then fly.targetAlpha = 0 end
        return
    end

    -- ---- NoClip: apply on change ----
    local nc = _G.Settings.NoClip and true or false
    if nc ~= lastNoClip then
        ApplyNoClip(nc)
        lastNoClip = nc
    end

    -- ---- HitboxExpander: apply on change ----
    local he = _G.Settings.HitboxExpander
    if he.Enabled ~= lastHitboxEnabled or he.Size ~= lastHitboxSize then
        ApplyHitbox()
        lastHitboxEnabled = he.Enabled
        lastHitboxSize    = he.Size
    end

    -- ---- SpeedHack с кэшем оригинала ----
    local sh = _G.Settings.SpeedHack
    if sh.Enabled then
        if originalWalkSpeed == nil then originalWalkSpeed = hum.WalkSpeed end
        local target = sh.Speed or 50
        if hum.WalkSpeed ~= target then hum.WalkSpeed = target end
    else
        if originalWalkSpeed and hum.WalkSpeed ~= originalWalkSpeed then
            hum.WalkSpeed = originalWalkSpeed
        end
    end

    -- ---- InfJump (cooldown 0.22с) ----
    if _G.Settings.InfJump and UserInputService:IsKeyDown(Enum.KeyCode.Space)
       and tick() - lastJumpTime > 0.22 then
        hum:ChangeState(Enum.HumanoidStateType.Jumping)
        lastJumpTime = tick()
    end

    -- ---- Spinbot: ВЫКЛ если AntiAim.Desync включён (anti-conflict) ----
    local desyncOn = _G.Settings.AntiAim and _G.Settings.AntiAim.Desync
    if _G.Settings.Rage and _G.Settings.Rage.Spinbot and not desyncOn then
        root.CFrame = root.CFrame * CFrame.Angles(0, math.rad(_G.Settings.Rage.SpinSpeed or 25), 0)
    end

    -- ---- Fly lifecycle: smooth fade in/out ----
    local flyOn = _G.Settings.Fly and _G.Settings.Fly.Enabled
    if flyOn then
        if not fly.enabled or not (fly.linearVel and fly.linearVel.Parent == root) then
            CreateFly()
        end
        fly.targetAlpha = 1
    else
        fly.targetAlpha = 0
        if fly.fadeAlpha < 0.01 and fly.enabled then
            DestroyFly()
        end
    end

    -- exponential fade ~ 6/sec
    local k = math.min(dt * 6, 1)
    fly.fadeAlpha = fly.fadeAlpha + (fly.targetAlpha - fly.fadeAlpha) * k
    if fly.fadeAlpha < 0 then fly.fadeAlpha = 0 elseif fly.fadeAlpha > 1 then fly.fadeAlpha = 1 end

    -- ---- Fly drive ----
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

        local speed  = (_G.Settings.Fly.Speed or 58) * fly.fadeAlpha
        local target = (move.Magnitude > 0) and (move.Unit * speed) or Vector3.zero
        fly.linearVel.VectorVelocity = target
        if fly.align and cam then fly.align.CFrame = cam.CFrame end
    end
end

table.insert(connections, RunService.Heartbeat:Connect(Heartbeat))

----------------------------------------------------------------
-- 8. CharacterAdded — корректный сброс
----------------------------------------------------------------
table.insert(connections, LocalPlayer.CharacterAdded:Connect(function(char)
    -- старый Fly умер вместе с HRP — сбрасываем ссылки в lua
    fly.attachment  = nil
    fly.linearVel   = nil
    fly.align       = nil
    fly.enabled     = false
    fly.fadeAlpha   = 0
    fly.targetAlpha = 0

    -- кэши, привязанные к старому character
    table.clear(originalCanCollide)
    originalWalkSpeed = nil

    -- триггеры повторного применения
    lastNoClip        = nil
    lastHitboxEnabled = nil
    lastHitboxSize    = nil

    char:WaitForChild("HumanoidRootPart", 5)
    -- Heartbeat сам всё переаплайнет на следующем кадре
end))

-- Новый игрок зашёл / респавнулся — пересобрать hitbox expander
table.insert(connections, Players.PlayerAdded:Connect(function(plr)
    plr.CharacterAdded:Connect(function()
        task.wait(0.2)
        lastHitboxEnabled = nil
        lastHitboxSize    = nil
    end)
end))
for _, plr in ipairs(Players:GetPlayers()) do
    if plr ~= LocalPlayer then
        plr.CharacterAdded:Connect(function()
            task.wait(0.2)
            lastHitboxEnabled = nil
            lastHitboxSize    = nil
        end)
    end
end

----------------------------------------------------------------
-- 9. Disconnect — восстанавливаем оригиналы
----------------------------------------------------------------
local function Disconnect()
    for _, c in ipairs(connections) do
        if c and c.Connected then pcall(function() c:Disconnect() end) end
    end
    table.clear(connections)
    DestroyFly()

    -- restore CanCollide
    for part, can in pairs(originalCanCollide) do
        pcall(function() part.CanCollide = can end)
    end
    table.clear(originalCanCollide)

    -- restore hitboxes
    for part, orig in pairs(originalHitbox) do
        pcall(function()
            part.Size         = orig.Size
            part.Transparency = orig.Transparency
        end)
    end
    table.clear(originalHitbox)

    -- restore WalkSpeed
    if originalWalkSpeed then
        local _, hum = GetCharRig()
        if hum then pcall(function() hum.WalkSpeed = originalWalkSpeed end) end
        originalWalkSpeed = nil
    end
end

_G.ABYSS_Movement = { Disconnect = Disconnect }
print("[ABYSS] Movement loaded")
