local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local flyAttachment = nil
local flyLinearVelocity = nil
local flyAlignOrientation = nil
local lastJumpTime = 0

RunService.Heartbeat:Connect(function()
    local char = _G.LocalPlayer.Character
    if not char then return end
    local root = char:FindFirstChild("HumanoidRootPart")
    local hum = char:FindFirstChild("Humanoid")
    if not root or not hum then return end

    if _G.Settings.Fly.Enabled then
        if not flyAttachment then
            flyAttachment = Instance.new("Attachment")
            flyAttachment.Parent = root
            flyLinearVelocity = Instance.new("LinearVelocity")
            flyLinearVelocity.Attachment0 = flyAttachment
            flyLinearVelocity.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
            flyLinearVelocity.MaxForce = math.huge
            flyLinearVelocity.Parent = root
            flyAlignOrientation = Instance.new("AlignOrientation")
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

        if move.Magnitude > 0 then
            flyLinearVelocity.VectorVelocity = move.Unit * (_G.Settings.Fly.Speed or 70)
        else
            flyLinearVelocity.VectorVelocity = Vector3.new()
        end
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

    if _G.Settings.InfJump and UserInputService:IsKeyDown(Enum.KeyCode.Space) and tick() - lastJumpTime > 0.25 then
        hum:ChangeState(Enum.HumanoidStateType.Jumping)
        lastJumpTime = tick()
    end

    if _G.Settings.NoClip then
        for _, part in ipairs(char:GetDescendants()) do
            if part:IsA("BasePart") then
                part.CanCollide = false
            end
        end
    end

    if _G.Settings.HitboxExpander.Enabled then
        for _, plr in ipairs(_G.Players:GetPlayers()) do
            if plr ~= _G.LocalPlayer and plr.Character then
                local parts = plr.Character:GetChildren()
                for _, part in ipairs(parts) do
                    if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" then
                        part.Size = Vector3.new(_G.Settings.HitboxExpander.Size, _G.Settings.HitboxExpander.Size, _G.Settings.HitboxExpander.Size)
                        part.Transparency = 0.7
                    end
                end
            end
        end
    end
end)
