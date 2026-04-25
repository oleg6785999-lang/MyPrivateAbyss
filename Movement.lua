-- Movement.lua
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local flyAttachment, flyLinearVelocity, flyAlignOrientation = nil, nil, nil

local function MovementLoop()
    while task.wait() do
        -- Fly
        if _G.Settings.Fly.Enabled then
            local root = _G.LocalPlayer.Character and _G.LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
            if root then
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
                if flyLinearVelocity then flyLinearVelocity.VectorVelocity = move.Unit * _G.Settings.Fly.Speed end
                if flyAlignOrientation then flyAlignOrientation.CFrame = _G.Camera.CFrame end
            end
        else
            if flyLinearVelocity then flyLinearVelocity:Destroy() flyLinearVelocity = nil end
            if flyAlignOrientation then flyAlignOrientation:Destroy() flyAlignOrientation = nil end
            if flyAttachment then flyAttachment:Destroy() flyAttachment = nil end
        end

        -- SpeedHack (CFrame метод)
        if _G.Settings.SpeedHack.Enabled and _G.LocalPlayer.Character then
            local root = _G.LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
            local hum = _G.LocalPlayer.Character:FindFirstChild("Humanoid")
            if root and hum and hum.MoveDirection.Magnitude > 0 then
                root.CFrame = root.CFrame + (hum.MoveDirection * (_G.Settings.SpeedHack.Speed / 100))
            end
        end

        -- Infinite Jump
        if _G.Settings.InfJump and _G.LocalPlayer.Character then
            local hum = _G.LocalPlayer.Character:FindFirstChild("Humanoid")
            if hum and UserInputService:IsKeyDown(Enum.KeyCode.Space) and tick() - lastJumpTime > 0.25 then
                hum:ChangeState(Enum.HumanoidStateType.Jumping)
                lastJumpTime = tick()
            end
        end

        -- NoClip
        if _G.Settings.NoClip and _G.LocalPlayer.Character then
            for _, part in ipairs(_G.LocalPlayer.Character:GetDescendants()) do
                if part:IsA("BasePart") then part.CanCollide = false end
            end
        end

        -- Hitbox Expander
        if _G.Settings.HitboxExpander.Enabled then
            for _, plr in ipairs(_G.Players:GetPlayers()) do
                if plr ~= _G.LocalPlayer and plr.Character and plr.Character:FindFirstChild("HumanoidRootPart") then
                    local part = plr.Character.HumanoidRootPart
                    part.Size = Vector3.new(_G.Settings.HitboxExpander.Size, _G.Settings.HitboxExpander.Size, _G.Settings.HitboxExpander.Size)
                    part.Transparency = 0.7
                end
            end
        end
    end
end

task.spawn(MovementLoop)
