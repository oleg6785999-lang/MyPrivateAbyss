-- Aimbot.lua
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local isAiming = false

UserInputService.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton2 then isAiming = true end
end)

UserInputService.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton2 then isAiming = false end
end)

local function AimbotLoop()
    while task.wait() do
        if not _G.Settings.Aimbot.Enabled or not isAiming then continue end
        local closest = nil
        local shortest = _G.Settings.Aimbot.FOV
        local mousePos = UserInputService:GetMouseLocation()
        for _, plr in ipairs(Players:GetPlayers()) do
            if not IsEnemy(plr) or not plr.Character then continue end
            local root = plr.Character:FindFirstChild("HumanoidRootPart")
            local hum = plr.Character:FindFirstChild("Humanoid")
            if not root or not hum or hum.Health <= 0 then continue end
            local targetPos = root.Position + Vector3.new(0, _G.Settings.Aimbot.HitboxOffset, 0)
            if _G.Settings.Aimbot.WallCheck and not IsVisible(targetPos) then continue end
            local predicted = targetPos + (root.AssemblyLinearVelocity or Vector3.new()) * _G.Settings.Aimbot.Prediction
            local sp, onScreen = Camera:WorldToViewportPoint(predicted)
            if onScreen then
                local d = (Vector2.new(sp.X, sp.Y) - mousePos).Magnitude
                if d < shortest then
                    shortest = d
                    closest = sp
                end
            end
        end
        if closest then
            if mouseMoverExists then
                local dx = (closest.X - mousePos.X) / _G.Settings.Aimbot.Smoothing
                local dy = (closest.Y - mousePos.Y) / _G.Settings.Aimbot.Smoothing
                mousemoverel(dx * _G.Settings.Aimbot.Sensitivity, dy * _G.Settings.Aimbot.Sensitivity)
            end
        end
    end
end

task.spawn(AimbotLoop)
