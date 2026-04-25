local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local flyAttachment = nil
local flyLinearVelocity = nil
local flyAlignOrientation = nil
local lastJumpTime = 0
local originalCanCollide = {}

local function ToggleNoClip(enable)
    local char = _G.LocalPlayer.Character
    if not char then return end
    for _, part in ipairs(char:GetDescendants()) do
        if part:IsA("BasePart") then
            if enable then
                originalCanCollide[part] = part.CanCollide
                part.CanCollide = false
            else
                if originalCanCollide[part] ~= nil then
                    part.CanCollide = originalCanCollide[part]
                end
            end
        end
    end
end

RunService.Heartbeat:Connect(function()
    local char = _G.LocalPlayer.Character
    if not char then return end
    local root = char:FindFirstChild("HumanoidRootPart")
    local hum = char:FindFirstChild("Humanoid")
    if not root or not hum then return end

    if _G.Settings.Fly.Enabled then
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
        end

        local move = Vector3.new()
        local camLook = _G.Camera.CFrame.LookVector
        local camRight = _G.Camera.CFrame.RightVector
        if UserInputService:IsKeyDown(Enum.KeyCode.W) then move += camLook end
        if UserInputService:IsKeyDown(Enum.KeyCode.S) then move -= camLook end
        if UserInputService:IsKeyDown(Enum.KeyCode.A) then move -= camRight end
        if UserInputService:IsKeyDown(Enum.KeyCode.D) then move += camRight end
        if UserInputService:IsKeyDown(Enum.KeyCode.Space) then move += Vector3.new(0,1,0) end
        if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then move -= Vector3.new(0,1,0) end

        local speed = _G.Settings.Fly.Speed or 70
        flyLinearVelocity.VectorVelocity = move.Magnitude > 0 and move.Unit * speed or Vector3.new()
        flyAlignOrientation.CFrame = _G.Camera.CFrame
    else
        if flyLinearVelocity then flyLinearVelocity:Destroy() flyLinearVelocity = nil end
        if flyAlignOrientation then flyAlignOrientation:Destroy() flyAlignOrientation = nil end
        if flyAttachment then flyAttachment:Destroy() flyAttachment = nil end
    end

    if _G.Settings.SpeedHack.Enabled then
        hum.WalkSpeed = _G.Settings.SpeedHack.Speed or 50
    else
        hum.WalkSpeed = 16
    end

    if _G.Settings.InfJump and UserInputService:IsKeyDown(Enum.KeyCode.Space) and tick() - lastJumpTime > (0.18 + math.random() * 0.1) then
        hum:ChangeState(Enum.HumanoidStateType.Jumping)
        lastJumpTime = tick()
    end

    if _G.Settings.NoClip then
        ToggleNoClip(true)
    else
        ToggleNoClip(false)
    end

    if _G.Settings.HitboxExpander.Enabled then
        for _, plr in ipairs(_G.Players:GetPlayers()) do
            if plr ~= _G.LocalPlayer and plr.Character then
                for _, part in ipairs(plr.Character:GetChildren()) do
                    if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" then
                        local desired = _G.Settings.HitboxExpander.Size or 12
                        if part.Size.X ~= desired then
                            part.Size = Vector3.new(desired, desired, desired)
                            part.Transparency = 0.7
                        end
                    end
                end
            end
        end
    end
end)
