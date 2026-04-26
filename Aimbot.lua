if _G.AimbotHooked then return end
_G.AimbotHooked = true

print("[ABYSS] Aimbot module starting...")

local Players = _G.Players or game:GetService("Players")
local Camera = _G.Camera or workspace.CurrentCamera
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local fovCircle = Drawing.new("Circle")
fovCircle.Thickness = 2
fovCircle.NumSides = 100
fovCircle.Color = Color3.fromRGB(0, 255, 100)
fovCircle.Transparency = 0.8
fovCircle.Filled = false
fovCircle.Visible = false

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

local lastTarget = nil
local lastUpdate = 0

local function GetClosest()
    if tick() - lastUpdate < 0.02 then return lastTarget end
    lastUpdate = tick()

    local closest = nil
    local shortest = math.huge
    local mousePos = UserInputService:GetMouseLocation()
    local fov = _G.Settings.Aimbot.FOV or 120
    local fovRad = math.rad(fov / 2)

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
        if not onScreen then continue end

        local d = (Vector2.new(sp.X, sp.Y) - mousePos).Magnitude
        local angle = math.acos(Camera.CFrame.LookVector:Dot((predicted - Camera.CFrame.Position).Unit))

        if angle <= fovRad or d <= fov then
            if d < shortest then
                shortest = d
                closest = {Position = predicted, ScreenPos = Vector2.new(sp.X, sp.Y)}
            end
        end
    end
    lastTarget = closest
    return closest
end

local mt = getrawmetatable(game)
local oldNamecall = mt.__namecall
setreadonly(mt, false)
mt.__namecall = newcclosure(function(self, ...)
    local args = {...}
    if _G.Settings.Aimbot.Silent and getnamecallmethod() == "FireServer" then
        local name = self.Name:lower()
        if name:find("shoot") or name:find("bullet") or name:find("damage") or name:find("attack") or name:find("fire") then
            local target = GetClosest()
            if target then
                local direction = (target.Position - Camera.CFrame.Position).Unit
                for i, arg in ipairs(args) do
                    if typeof(arg) == "Vector3" and arg.Magnitude > 0.1 then
                        args[i] = direction
                        break
                    end
                end
            end
        end
    end
    return oldNamecall(self, unpack(args))
end)
setreadonly(mt, true)

RunService.RenderStepped:Connect(function()
    if not _G.Settings or not _G.Settings.Aimbot or not _G.Settings.Aimbot.Enabled then 
        fovCircle.Visible = false
        return 
    end

    local mousePos = UserInputService:GetMouseLocation()
    fovCircle.Position = mousePos
    fovCircle.Radius = _G.Settings.Aimbot.FOV or 120
    fovCircle.Visible = true

    local activateButton = Enum.UserInputType.MouseButton1
    if not UserInputService:IsMouseButtonPressed(activateButton) then
        return
    end

    local target = GetClosest()
    if target and target.ScreenPos then
        local camPos = Camera.CFrame.Position
        local targetPos = target.Position

        local currentLook = Camera.CFrame.LookVector
        local desiredLook = (targetPos - camPos).Unit

        local sensitivity = _G.Settings.Aimbot.Sensitivity or 1.2
        local smoothing = _G.Settings.Aimbot.Smoothing or 4
        local lerpFactor = (1 / smoothing) * sensitivity

        local newLook = currentLook:Lerp(desiredLook, lerpFactor)
        Camera.CFrame = CFrame.new(camPos, camPos + newLook)
    end
end)

print("[ABYSS] Aimbot Always-On + Camera Aim + Real FOV + Smart Silent LOADED")
