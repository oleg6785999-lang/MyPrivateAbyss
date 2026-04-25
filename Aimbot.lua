local Players = _G.Players or game:GetService("Players")
local Camera = _G.Camera or workspace.CurrentCamera
local UserInputService = game:GetService("UserInputService")

local isAiming = false

UserInputService.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton2 then
        isAiming = true
    end
end)

UserInputService.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton2 then
        isAiming = false
    end
end)

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

local function IsEnemy(player)
    if not _G.Settings.ESP.OnlyEnemies then return true end
    if not player.Team or not _G.LocalPlayer.Team then return true end
    return player.Team ~= _G.LocalPlayer.Team
end

local function IsVisible(targetPosition)
    if not _G.LocalPlayer.Character then return false end
    rayParams.FilterDescendantsInstances = {_G.LocalPlayer.Character}
    local origin = Camera.CFrame.Position
    local direction = targetPosition - origin
    return not workspace:Raycast(origin, direction, rayParams)
end

local function GetClosest()
    local closest = nil
    local shortest = _G.Settings.Aimbot.FOV or 120
    local mousePos = UserInputService:GetMouseLocation()
    local myRoot = _G.LocalPlayer.Character and _G.LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
    if not myRoot then return nil end

    for _, plr in ipairs(Players:GetPlayers()) do
        if not IsEnemy(plr) or not plr.Character then continue end
        local char = plr.Character
        local root = char:FindFirstChild("HumanoidRootPart")
        local hum = char:FindFirstChild("Humanoid")
        if not root or not hum or hum.Health <= 0 then continue end

        local targetPos = root.Position + Vector3.new(0, _G.Settings.Aimbot.HitboxOffset or 2.5, 0)
        if _G.Settings.Aimbot.WallCheck and not IsVisible(targetPos) then continue end

        local predicted = targetPos + (root.AssemblyLinearVelocity or Vector3.new()) * (_G.Settings.Aimbot.Prediction or 0.12)
        local sp, onScreen = Camera:WorldToViewportPoint(predicted)
        if onScreen then
            local d = (Vector2.new(sp.X, sp.Y) - mousePos).Magnitude
            if d < shortest then
                shortest = d
                closest = {Position = predicted, ScreenPos = Vector2.new(sp.X, sp.Y)}
            end
        end
    end
    return closest
end

local mt = getrawmetatable(game)
local oldNamecall = mt.__namecall
setreadonly(mt, false)
mt.__namecall = newcclosure(function(self, ...)
    local args = {...}
    local method = getnamecallmethod()
    if _G.Settings.Aimbot.Silent and method == "FireServer" then
        if self.Name:lower():find("shoot") or self.Name:lower():find("attack") or self.Name:lower():find("bullet") or self.Name:lower():find("remote") then
            local target = GetClosest()
            if target then
                args[1] = target.Position + Vector3.new(math.random(-0.3,0.3), math.random(-0.1,0.1), math.random(-0.3,0.3))
            end
        end
    end
    return oldNamecall(self, unpack(args))
end)
setreadonly(mt, true)

game:GetService("RunService").RenderStepped:Connect(function()
    if not _G.Settings.Aimbot.Enabled or not isAiming then return end
    local target = GetClosest()
    if target and target.ScreenPos then
        local mousePos = UserInputService:GetMouseLocation()
        local dx = (target.ScreenPos.X - mousePos.X) / (_G.Settings.Aimbot.Smoothing or 3)
        local dy = (target.ScreenPos.Y - mousePos.Y) / (_G.Settings.Aimbot.Smoothing or 3)
        mousemoverel(dx * (_G.Settings.Aimbot.Sensitivity or 1), dy * (_G.Settings.Aimbot.Sensitivity or 1))
    end
end)
