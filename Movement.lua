local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local flyAttachment = nil
local flyLinearVelocity = nil
local flyAlignOrientation = nil
local lastJumpTime = 0
local originalCanCollide = {}
local flyEnabledLast = false

local function ToggleFly(enable)
    local char = _G.LocalPlayer.Character
    if not char then return end
    local root = char:FindFirstChild("HumanoidRootPart")
    local hum = char:FindFirstChild("Humanoid")
    if not root or not hum then return end

    if enable then
        if not flyAttachment then
            flyAttachment = Instance.new("Attachment")
            flyAttachment.Name = "ABYSS_FlyAttachment"
            flyAttachment.Parent = root

            flyLinearVelocity = Instance.new("LinearVelocity")
            flyLinearVelocity.Name = "ABYSS_FlyVelocity"
            flyLinearVelocity.Attachment0 = flyAttachment
            flyLinearVelocity.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
            flyLinearVelocity.MaxForce = math.huge
            flyLinearVelocity.Parent = root

            flyAlignOrientation = Instance.new("AlignOrientation")
            flyAlignOrientation.Name = "ABYSS_FlyAlign"
            flyAlignOrientation.Attachment0 = flyAttachment
            flyAlignOrientation.Mode = Enum.OrientationAlignmentMode.OneAttachment
            flyAlignOrientation.MaxTorque = math.huge
            flyAlignOrientation.RigidityEnabled = true
            flyAlignOrientation.Parent = root

            root.CustomPhysicalProperties = PhysicalProperties.new(0, 0, 0, 0, 0)
            hum:ChangeState(Enum.HumanoidStateType.Physics)
        end
    else
        if flyLinearVelocity then flyLinearVelocity:Destroy() flyLinearVelocity = nil end
        if flyAlignOrientation then flyAlignOrientation:Destroy() flyAlignOrientation = nil end
        if flyAttachment then flyAttachment:Destroy() flyAttachment = nil end
    end
end

local function ToggleNoClip(enable)
    local char = _G.LocalPlayer.Character
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
                end
            end
        end
    end
end

local function ResetHitboxes()
    for _, plr in ipairs(_G.Players:GetPlayers()) do
        if plr ~= _G.LocalPlayer and plr.Character then
            for _, part in ipairs(plr.Character:GetChildren()) do
                if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" then
                    part.Size = Vector3.new(2, 2, 1)
                    part.Transparency = 0
                end
            end
        end
    end
end

local function UpdateHitbox()
    if not _G.Settings.HitboxExpander.Enabled then
        ResetHitboxes()
        return
    end
    local size = _G.Settings.HitboxExpander.Size or 12
    for _, plr in ipairs(_G.Players:GetPlayers()) do
        if plr ~= _G.LocalPlayer and plr.Character then
            for _, part in ipairs(plr.Character:GetChildren()) do
                if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" then
                    if part.Size.X ~= size then
                        part.Size = Vector3.new(size, size, size)
                        part.Transparency = 0.7
                    end
                end
            end
        end
    end
end

_G.LocalPlayer.CharacterAdded:Connect(function()
    task.wait(0.5)
    ToggleFly(_G.Settings.Fly.Enabled)
    ToggleNoClip(_G.Settings.NoClip)
    UpdateHitbox()
end)

_G.Players.PlayerAdded:Connect(function(plr)
    plr.CharacterAdded:Connect(function()
        task.wait(0.5)
        ToggleNoClip(_G.Settings.NoClip)
        UpdateHitbox()
    end)
end)

RunService.Heartbeat:Connect(function()
    local char = _G.LocalPlayer.Character
    if not char then return end
    local root = char:FindFirstChild("HumanoidRootPart")
    local hum = char:FindFirstChild("Humanoid")
    if not root or not hum then return end

    if _G.Settings.Fly.Enabled ~= flyEnabledLast then
        ToggleFly(_G.Settings.Fly.Enabled)
        flyEnabledLast = _G.Settings.Fly.Enabled
    end

    if _G.Settings.Fly.Enabled and flyLinearVelocity then
        local move = Vector3.new()
        local camLook = _G.Camera.CFrame.LookVector
        local camRight = _G.Camera.CFrame.RightVector
        if UserInputService:IsKeyDown(Enum.KeyCode.W) then move += camLook end
        if UserInputService:IsKeyDown(Enum.KeyCode.S) then move -= camLook end
        if UserInputService:IsKeyDown(Enum.KeyCode.A) then move -= camRight end
        if UserInputService:IsKeyDown(Enum.KeyCode.D) then move += camRight end
        if UserInputService:IsKeyDown(Enum.KeyCode.Space) then move += Vector3.new(0,1,0) end
        if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then move -= Vector3.new(0,1,0) end

        local speed = _G.Settings.Fly.Speed or 58
        flyLinearVelocity.VectorVelocity = move.Magnitude > 0 and move.Unit * speed or Vector3.new()
        flyAlignOrientation.CFrame = _G.Camera.CFrame
    end

    if _G.Settings.SpeedHack.Enabled then
        if hum.WalkSpeed ~= _G.Settings.SpeedHack.Speed then
            hum.WalkSpeed = _G.Settings.SpeedHack.Speed or 50
        end
        root.AssemblyLinearVelocity = root.AssemblyLinearVelocity * Vector3.new(1.02, 1, 1.02)
    else
        if hum.WalkSpeed ~= 16 then
            hum.WalkSpeed = 16
        end
    end

    if _G.Settings.InfJump and UserInputService:IsKeyDown(Enum.KeyCode.Space) and tick() - lastJumpTime > (0.18 + math.random() * 0.1) then
        hum:ChangeState(Enum.HumanoidStateType.Jumping)
        lastJumpTime = tick()
        if root.AssemblyLinearVelocity then
            root.AssemblyLinearVelocity = Vector3.new(root.AssemblyLinearVelocity.X, 0, root.AssemblyLinearVelocity.Z)
        end
    end

    if _G.Settings.Rage.Spinbot then
        root.CFrame = root.CFrame * CFrame.Angles(0, math.rad(_G.Settings.Rage.SpinSpeed or 25), 0)
    end

    ToggleNoClip(_G.Settings.NoClip)
    UpdateHitbox()
end)
