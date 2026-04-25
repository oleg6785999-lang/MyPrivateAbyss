-- Movement.lua
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local flyAttachment, flyLinearVelocity, flyAlignOrientation = nil, nil, nil

local function MovementLoop()
    while task.wait() do
        if _G.Settings.Fly.Enabled then
            local root = cachedRoot
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
                local camLook = Camera.CFrame.LookVector
                local camRight = Camera.CFrame.RightVector
                if UserInputService:IsKeyDown(Enum.KeyCode.W) then move += camLook end
                if UserInputService:IsKeyDown(Enum.KeyCode.S) then move -= camLook end
                if UserInputService:IsKeyDown(Enum.KeyCode.A) then move -= camRight end
                if UserInputService:IsKeyDown(Enum.KeyCode.D) then move += camRight end
                if UserInputService:IsKeyDown(Enum.KeyCode.Space) then move += Vector3.new(0,1,0) end
                if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then move -= Vector3.new(0,1,0) end
                if flyLinearVelocity then flyLinearVelocity.VectorVelocity = move.Unit * _G.Settings.Fly.Speed end
                if flyAlignOrientation then flyAlignOrientation.CFrame = Camera.CFrame end
            end
        else
            if flyLinearVelocity then flyLinearVelocity:Destroy() flyLinearVelocity = nil end
            if flyAlignOrientation then flyAlignOrientation:Destroy() flyAlignOrientation = nil end
            if flyAttachment then flyAttachment:Destroy() flyAttachment = nil end
        end

        if _G.Settings.SpeedHack.Enabled and cachedCharacter then
            local hum = cachedCharacter:FindFirstChild("Humanoid")
            if hum then hum.WalkSpeed = _G.Settings.SpeedHack.Speed end
        end

        if _G.Settings.InfJump and cachedCharacter then
            local hum = cachedCharacter:FindFirstChild("Humanoid")
            if hum and UserInputService:IsKeyDown(Enum.KeyCode.Space) and tick() - lastJumpTime > 0.25 then
                hum:ChangeState(Enum.HumanoidStateType.Jumping)
                lastJumpTime = tick()
            end
        end

        if _G.Settings.NoClip and cachedCharacter then
            for _, part in ipairs(cachedCharacter:GetDescendants()) do
                if part:IsA("BasePart") then part.CanCollide = false end
            end
        end
    end
end

task.spawn(MovementLoop)
