local Players = _G.Players or game:GetService("Players")
local Camera = _G.Camera or workspace.CurrentCamera

local drawingAvailable = type(Drawing) == "table" and type(Drawing.new) == "function"

local DrawingPool = table.create(300)
local function GetDrawing(class)
    for _, obj in ipairs(DrawingPool) do
        if obj.ClassName == class and not obj.Visible then
            return obj
        end
    end
    local d = Drawing.new(class)
    table.insert(DrawingPool, d)
    return d
end

local Highlights = {}
local espBoxes = {}
local espHealthBars = {}
local espSnaplines = {}

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

local function CleanupESP()
    for _, box in pairs(espBoxes) do if box then box:Remove() end end
    for _, bars in pairs(espHealthBars) do 
        if bars then 
            if bars.bg then bars.bg:Remove() end 
            if bars.fill then bars.fill:Remove() end 
        end 
    end
    for _, line in pairs(espSnaplines) do if line then line:Remove() end end
    for _, hl in pairs(Highlights) do if hl then hl:Destroy() end end
    table.clear(espBoxes)
    table.clear(espHealthBars)
    table.clear(espSnaplines)
    table.clear(Highlights)
end

local function UpdateChams(plr, char)
    if _G.Settings.ESP.Chams then
        if not Highlights[plr] then
            local hl = Instance.new("Highlight")
            hl.Name = "ABYSS_Highlight"
            hl.FillColor = Color3.fromRGB(255,0,0)
            hl.OutlineColor = Color3.fromRGB(255,255,255)
            hl.FillTransparency = 0.5
            hl.Adornee = char
            hl.Parent = char
            Highlights[plr] = hl
        end
    elseif Highlights[plr] then
        Highlights[plr]:Destroy()
        Highlights[plr] = nil
    end
end

game:GetService("RunService").RenderStepped:Connect(function()
    if not _G.Settings.ESP.Enabled or not drawingAvailable then
        CleanupESP()
        return
    end

    for _, plr in ipairs(Players:GetPlayers()) do
        if plr == _G.LocalPlayer or not plr.Character then continue end
        if _G.Settings.ESP.OnlyEnemies and not IsEnemy(plr) then continue end

        local char = plr.Character
        local root = char:FindFirstChild("HumanoidRootPart")
        local hum = char:FindFirstChild("Humanoid")
        if not root or not hum or hum.Health <= 0 then continue end

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
            if not espBoxes[plr] then espBoxes[plr] = GetDrawing("Square") end
            local box = espBoxes[plr]
            box.Filled = false
            box.Color = Color3.fromRGB(255,255,255)
            box.Thickness = 1
            box.Size = Vector2.new(width, height)
            box.Position = Vector2.new(x, y)
            box.Visible = true
        end

        if _G.Settings.ESP.HealthBar then
            local healthPercent = hum.Health / hum.MaxHealth
            if not espHealthBars[plr] then
                local bg = GetDrawing("Square")
                local fill = GetDrawing("Square")
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
            if not espSnaplines[plr] then espSnaplines[plr] = GetDrawing("Line") end
            local line = espSnaplines[plr]
            line.Color = Color3.fromRGB(255,255,255)
            line.Thickness = 1
            line.From = Vector2.new(Camera.ViewportSize.X / 2, Camera.ViewportSize.Y)
            line.To = Vector2.new(headScreen.X, headScreen.Y)
            line.Visible = true
        end

        UpdateChams(plr, char)
    end
end)
