if _G.AimbotHooked then return end
_G.AimbotHooked = true

print("[ABYSS] Simple Aimbot starting...")

local Players = _G.Players or game:GetService("Players")
local RunService = game:GetService("RunService")
local LocalPlayer = _G.LocalPlayer

-- Самый примитивный поиск ближайшего врага
local function GetNearestTarget()
    if not LocalPlayer.Character then return nil end
    local myRoot = LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
    if not myRoot then return nil end

    local nearest = nil
    local minDist = 500 -- радиус поиска в студиях

    for _, plr in ipairs(Players:GetPlayers()) do
        if plr == LocalPlayer then continue end
        local char = plr.Character
        if not char then continue end
        local root = char:FindFirstChild("HumanoidRootPart")
        local hum = char:FindFirstChild("Humanoid")
        if not root or not hum or hum.Health <= 0 then continue end

        local dist = (myRoot.Position - root.Position).Magnitude
        if dist < minDist then
            minDist = dist
            nearest = root
        end
    end
    return nearest
end

RunService.RenderStepped:Connect(function()
    if not _G.Settings or not _G.Settings.Aimbot or not _G.Settings.Aimbot.Enabled then return end

    local char = LocalPlayer.Character
    if not char then return end
    local myRoot = char:FindFirstChild("HumanoidRootPart")
    if not myRoot then return end

    local targetRoot = GetNearestTarget()
    if targetRoot then
        -- Поворачиваем туловище в сторону цели
        myRoot.CFrame = CFrame.new(myRoot.Position, targetRoot.Position)
    end
end)

print("[ABYSS] Simple Aimbot LOADED!")
