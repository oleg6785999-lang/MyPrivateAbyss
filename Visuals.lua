-- Visuals.lua
local Players = _G.Players or game:GetService("Players")
local Camera = _G.Camera or workspace.CurrentCamera

local drawingAvailable = type(Drawing) == "table" and type(Drawing.new) == "function"

local TracersTable = {}
local espBoxes = {}
local espHealthBars = {}
local espSnaplines = {}

local function IsEnemy(player)
    if not _G.Settings.ESP.OnlyEnemies then return true end
    if not player.Team or not _G.LocalPlayer.Team then return true end
    return player.Team ~= _G.LocalPlayer.Team
end

local function IsVisible(targetPosition)
    if not _G.LocalPlayer.Character then return false end
    local origin = Camera.CFrame.Position
    local direction = targetPosition - origin
    local params = RaycastParams.new()
    params.FilterDescendantsInstances = {_G.LocalPlayer.Character}
    params.FilterType = Enum.RaycastFilterType.Exclude
    return not Workspace:Raycast(origin, direction, params)
end

local function VisualsLoop()
    while task.wait(0.016) do
        if not _G.Settings.ESP.Enabled or not drawingAvailable then
            for _, box in pairs(espBoxes) do if box then box.Visible = false end end
            for _, bars in pairs(espHealthBars) do 
                if bars then 
                    if bars.bg then bars.bg.Visible = false end 
                    if bars.fill then bars.fill.Visible = false end 
                end 
            end
            for _, line in pairs(espSnaplines) do if line then line.Visible = false end end
            continue
        end

        for _, plr in ipairs(Players:GetPlayers()) do
            if plr == _G.LocalPlayer or not plr.Character then continue end
            if _G.Settings.ESP.OnlyEnemies and not IsEnemy(plr) then continue end
            local root = plr.Character:FindFirstChild("HumanoidRootPart")
            local hum = plr.Character:FindFirstChild("Humanoid")
            if not root or not hum then continue end
            if hum.Health <= 0 then
                if espBoxes[plr] then espBoxes[plr].Visible = false end
                if espHealthBars[plr] then 
                    if espHealthBars[plr].bg then espHealthBars[plr].bg.Visible = false end
                    if espHealthBars[plr].fill then espHealthBars[plr].fill.Visible = false end
                end
                continue
            end
            local dist = (root.Position - Camera.CFrame.Position).Magnitude
            if dist > _G.Settings.ESP.MaxDistance then continue end
            local headPos = root.Position + Vector3.new(0, 2.5, 0)
            local legPos = root.Position - Vector3.new(0, 2.5, 0)
            local headScreen, visHead = Camera:WorldToViewportPoint(headPos)
            local legScreen, visLeg = Camera:WorldToViewportPoint(legPos)
            if not (visHead and visLeg) then continue end
            local height = math.abs(legScreen.Y - headScreen.Y)
            local width = height * 0.5
            local x = headScreen.X - width / 2
            local y = headScreen.Y

            if _G.Settings.ESP.Boxes then
                if not espBoxes[plr] then
                    local box = Drawing.new("Square")
                    box.Filled = false
                    box.Color = Color3.fromRGB(255,255,255)
                    box.Thickness = 1
                    espBoxes[plr] = box
                end
                local box = espBoxes[plr]
                box.Size = Vector2.new(width, height)
                box.Position = Vector2.new(x, y)
                box.Visible = true
            end

            if _G.Settings.ESP.HealthBar then
                local healthPercent = hum.Health / hum.MaxHealth
                if not espHealthBars[plr] then
                    local bg = Drawing.new("Square")
                    local fill = Drawing.new("Square")
                    bg.Filled = true
                    bg.Color = Color3.fromRGB(0,0,0)
                    fill.Filled = true
                    fill.Color = Color3.fromRGB(0,255,0)
                    espHealthBars[plr] = {bg = bg, fill = fill}
                end
                local bars = espHealthBars[plr]
                bars.bg.Size = Vector2.new(3, height)
                bars.bg.Position = Vector2.new(x - 5, y)
                bars.bg.Visible = true
                local barHeight = height * healthPercent
                bars.fill.Size = Vector2.new(3, barHeight)
                bars.fill.Position = Vector2.new(x - 5, y + (height - barHeight))
                bars.fill.Visible = true
            end

            if _G.Settings.ESP.Snaplines then
                if not espSnaplines[plr] then
                    local line = Drawing.new("Line")
                    line.Color = Color3.fromRGB(255,255,255)
                    line.Thickness = 1
                    espSnaplines[plr] = line
                end
                local line = espSnaplines[plr]
                line.From = Vector2.new(Camera.ViewportSize.X / 2, Camera.ViewportSize.Y)
                line.To = Vector2.new(headScreen.X, headScreen.Y)
                line.Visible = true
            end

            if _G.Settings.ESP.Chams then
                local highlight = plr.Character:FindFirstChild("AbyssHighlight") or Instance.new("Highlight", plr.Character)
                highlight.Name = "AbyssHighlight"
                highlight.FillColor = Color3.fromRGB(255, 0, 0)
                highlight.OutlineColor = Color3.fromRGB(255, 255, 255)
                highlight.FillTransparency = 0.5
            else
                if plr.Character:FindFirstChild("AbyssHighlight") then
                    plr.Character.AbyssHighlight:Destroy()
                end
            end
        end
    end
end

task.spawn(VisualsLoop)
