local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local TeleportService = game:GetService("TeleportService")

local LocalPlayer = Players.LocalPlayer
local Camera = Workspace.CurrentCamera

local drawingAvailable = type(Drawing) == "table" and type(Drawing.new) == "function"

local Rayfield = nil
local urls = {"https://sirius.menu/rayfield", "https://raw.githubusercontent.com/SiriusSoftwareLtd/Rayfield/main/source.lua"}

local function LoadRayfield()
    for _, url in ipairs(urls) do
        local success, result = pcall(function() return loadstring(game:HttpGet(url))() end)
        if success and typeof(result) == "table" and result.CreateWindow then
            Rayfield = result
            return true
        end
    end
    return false
end

local loaded = LoadRayfield()
if not loaded then
    if getgenv and getgenv().Rayfield_InterfaceBuild then getgenv().Rayfield_InterfaceBuild = nil end
    loaded = LoadRayfield()
end

if Rayfield then
    local oldName = "Rayfield"
    local newName = "x" .. string.char(math.random(65,90)) .. string.char(math.random(65,90)) .. string.char(math.random(65,90)) .. tostring(math.random(1000,9999))
    pcall(function() Rayfield.Interface.Name = newName end)
end

local Settings = {
    Tracers = {Enabled = false, OnlyEnemies = true, FOV = 160, Thickness = 2, Transparency = 0.8, Color = Color3.fromRGB(255,255,255)},
    Aimbot = {Enabled = false, FOV = 120, Smoothing = 3, Prediction = 0.12, HitboxOffset = 2.5, Sensitivity = 1.2, WallCheck = true, Silent = false},
    Rage = {Spinbot = false, SpinSpeed = 25},
    SpeedHack = {Enabled = false, Speed = 50},
    Fly = {Enabled = false, Speed = 70},
    InfJump = false,
    NoClip = false,
    HitboxExpander = {Enabled = false, Size = 12},
    Triggerbot = false,
    Aura = {Enabled = false, Radius = 50, Damage = 100, Delay = 0.2},
    TeleportEnabled = false,
    RapidFire = false,
    ESP = {Enabled = false, Boxes = false, HealthBar = false, Snaplines = false, OnlyEnemies = true, MaxDistance = 500, Chams = false},
    AntiCheatMonitor = false,
    TriggerDelay = 0.08,
    AntiAim = {
        Jitter = false, JitterAngle = 40,
        Desync = false, DesyncType = "Spin", DesyncSpeed = 30,
        HideHead = false, HideHeadMode = "Back",
        FakeLag = false, FakeLagIntensity = 5, FakeLagFrequency = 1, FakeLagMode = "Random", FakeLagNoClip = true
    }
}

local FriendList = {}
local TracersTable = {}
local espBoxes = {}
local espHealthBars = {}
local espSnaplines = {}
local highlightPool = {}

local flyAttachment = nil
local flyLinearVelocity = nil
local flyAlignOrientation = nil

local noclipConnection = nil
local hitboxCache = {}
local connections = {}
local lastAuraTime = 0
local lastRapidTime = 0
local lastJumpTime = 0
local AntiDetected = false
local lastAntiCheck = 0
local lastTriggerTime = 0

local mouseMoverExists = type(mousemoverel) == "function"
local mouseClickExists = type(mouse1click) == "function"

local isAiming = false
local allPlayers = {}

local silentAimConnection = nil
local antiAimConnection = nil
local desyncGyro = nil
local desyncAngle = 0
local originalNeckC0 = nil
local fakeLagCounter = 0

local cachedCharacter = nil
local cachedRoot = nil

local function UpdateCache()
    cachedCharacter = LocalPlayer.Character
    cachedRoot = cachedCharacter and cachedCharacter:FindFirstChild("HumanoidRootPart")
end

LocalPlayer.CharacterAdded:Connect(function()
    task.wait(0.2)
    UpdateCache()
end)

LocalPlayer.CharacterRemoving:Connect(function()
    cachedCharacter = nil
    cachedRoot = nil
end)

local function IsFriend(plr)
    for _, id in ipairs(FriendList) do if plr.UserId == id then return true end end
    return false
end

local function IsEnemy(plr)
    return plr ~= LocalPlayer and not IsFriend(plr)
end

local function IsVisible(targetPosition)
    if not cachedRoot then return false end
    local origin = Camera.CFrame.Position
    local direction = targetPosition - origin
    local params = RaycastParams.new()
    params.FilterDescendantsInstances = {cachedCharacter}
    params.FilterType = Enum.RaycastFilterType.Exclude
    return not Workspace:Raycast(origin, direction, params)
end

local oldNamecall
oldNamecall = hookmetamethod(game, "__namecall", function(self, ...)
    local method = getnamecallmethod()
    local args = {...}
    if Settings.Aimbot.Silent and method == "FireServer" and self.Name:find("Bullet") or self.Name:find("Shoot") or self.Name:find("Gun") then
        local closest = nil
        local shortest = math.huge
        for _, plr in ipairs(allPlayers) do
            if not IsEnemy(plr) or not plr.Character then continue end
            local root = plr.Character:FindFirstChild("HumanoidRootPart")
            local hum = plr.Character:FindFirstChild("Humanoid")
            if not root or not hum or hum.Health <= 0 then continue end
            local targetPos = root.Position + Vector3.new(0, Settings.Aimbot.HitboxOffset, 0)
            if Settings.Aimbot.WallCheck and not IsVisible(targetPos) then continue end
            local predicted = targetPos + (root.AssemblyLinearVelocity or Vector3.new()) * Settings.Aimbot.Prediction
            local sp, onScreen = Camera:WorldToViewportPoint(predicted)
            if onScreen then
                local d = (Vector2.new(sp.X, sp.Y) - UserInputService:GetMouseLocation()).Magnitude
                if d < shortest and d < Settings.Aimbot.FOV then
                    shortest = d
                    closest = predicted
                end
            end
        end
        if closest then
            args[1] = closest
        end
    end
    return oldNamecall(self, unpack(args))
end)

local function EnableSilentAim()
    if silentAimConnection then return end
    silentAimConnection = RunService.RenderStepped:Connect(function()
        if not Settings.Aimbot.Silent or not cachedRoot then return end
    end)
end

local function DisableSilentAim()
    if silentAimConnection then silentAimConnection:Disconnect() silentAimConnection = nil end
end

local function CreateFly()
    local root = cachedRoot
    if not root then return end
    if flyAttachment then flyAttachment:Destroy() end
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

local function UpdateFly()
    if not Settings.Fly.Enabled then
        if flyLinearVelocity then flyLinearVelocity:Destroy() flyLinearVelocity = nil end
        if flyAlignOrientation then flyAlignOrientation:Destroy() flyAlignOrientation = nil end
        if flyAttachment then flyAttachment:Destroy() flyAttachment = nil end
        return
    end
    if not flyAttachment then CreateFly() end
    local root = cachedRoot
    if not root then return end
    local move = Vector3.new()
    local camLook = Camera.CFrame.LookVector
    local camRight = Camera.CFrame.RightVector
    if UserInputService:IsKeyDown(Enum.KeyCode.W) then move += camLook end
    if UserInputService:IsKeyDown(Enum.KeyCode.S) then move -= camLook end
    if UserInputService:IsKeyDown(Enum.KeyCode.A) then move -= camRight end
    if UserInputService:IsKeyDown(Enum.KeyCode.D) then move += camRight end
    if UserInputService:IsKeyDown(Enum.KeyCode.Space) then move += Vector3.new(0,1,0) end
    if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then move -= Vector3.new(0,1,0) end
    if flyLinearVelocity then flyLinearVelocity.VectorVelocity = move.Unit * Settings.Fly.Speed end
    if flyAlignOrientation then flyAlignOrientation.CFrame = Camera.CFrame end
end

local function ToggleNoClip(v)
    Settings.NoClip = v
    if v then
        if noclipConnection then noclipConnection:Disconnect() end
        noclipConnection = RunService.Stepped:Connect(function()
            if cachedCharacter then
                for _, part in ipairs(cachedCharacter:GetDescendants()) do
                    if part:IsA("BasePart") then part.CanCollide = false end
                end
            end
        end)
    else
        if noclipConnection then noclipConnection:Disconnect() noclipConnection = nil end
        if cachedCharacter then
            for _, part in ipairs(cachedCharacter:GetDescendants()) do
                if part:IsA("BasePart") then part.CanCollide = true end
            end
        end
    end
end

local function ToggleHitboxExpander(v)
    Settings.HitboxExpander.Enabled = v
    if not v then
        for part, cache in pairs(hitboxCache) do
            if part and part.Parent then
                part.Size = cache.Size
                part.Transparency = cache.Transparency
                part.CanCollide = cache.CanCollide
            end
        end
        hitboxCache = {}
    end
end

local function SoftAntiCheatWarn(reason)
    if not Settings.AntiCheatMonitor then return end
    warn("[ABYSS] Soft Detect: " .. reason)
    if Rayfield then
        Rayfield:Notify({Title = "ABYSS ARCHON", Content = "Возможный детект:\n" .. reason, Duration = 5})
    end
end

local function UpdateAntiAim()
    local char = cachedCharacter
    if not char then return end
    local root = cachedRoot
    if not root then return end

    if Settings.AntiAim.HideHead then
        local head = char:FindFirstChild("Head")
        if head then
            local neck = head:FindFirstChild("Neck")
            if neck and neck:IsA("Motor6D") then
                if not originalNeckC0 then
                    originalNeckC0 = neck.C0
                end
                if Settings.AntiAim.HideHeadMode == "Back" then
                    neck.C0 = CFrame.Angles(0, math.rad(180), 0)
                else
                    neck.C0 = CFrame.Angles(math.rad(-90), 0, 0)
                end
            end
        end
    elseif originalNeckC0 then
        local head = char:FindFirstChild("Head")
        if head then
            local neck = head:FindFirstChild("Neck")
            if neck and neck:IsA("Motor6D") then
                neck.C0 = originalNeckC0
                originalNeckC0 = nil
            end
        end
    end

    if Settings.AntiAim.Jitter then
        local angleY = math.rad(math.random(-Settings.AntiAim.JitterAngle, Settings.AntiAim.JitterAngle))
        local angleX = math.rad(math.random(-15, 15))
        root.CFrame = root.CFrame * CFrame.Angles(angleX, angleY, 0)
    end

    if Settings.Rage.Spinbot and not Settings.Fly.Enabled then
        root.CFrame = root.CFrame * CFrame.Angles(0, math.rad(Settings.Rage.SpinSpeed), 0)
    end

    if Settings.AntiAim.Desync and desyncGyro then
        if Settings.AntiAim.DesyncType == "Spin" then
            desyncAngle = (desyncAngle + Settings.AntiAim.DesyncSpeed) % 360
            desyncGyro.CFrame = CFrame.Angles(0, math.rad(desyncAngle), 0)
        elseif Settings.AntiAim.DesyncType == "Backwards" then
            desyncGyro.CFrame = (root.CFrame * CFrame.Angles(0, math.pi, 0)).Rotation
        end
    end

    if Settings.AntiAim.FakeLag and not Settings.Fly.Enabled then
        fakeLagCounter = fakeLagCounter + 1
        if fakeLagCounter % Settings.AntiAim.FakeLagFrequency == 0 then
            local intensity = Settings.AntiAim.FakeLagIntensity
            local origPos = root.Position
            local offset = Vector3.new(
                math.random(-intensity, intensity),
                math.random(-intensity/2, intensity/2),
                math.random(-intensity, intensity)
            )
            if Settings.AntiAim.FakeLagMode == "BackAndForth" then
                if fakeLagCounter % 2 == 0 then
                    root.CFrame = root.CFrame + offset
                else
                    root.CFrame = CFrame.new(origPos) * root.CFrame.Rotation
                end
            else
                root.CFrame = root.CFrame + offset
            end
            if Settings.AntiAim.FakeLagNoClip then
                for _, part in ipairs(char:GetDescendants()) do
                    if part:IsA("BasePart") then part.CanCollide = false end
                end
            end
        end
    end
end

local function ToggleJitter(v)
    Settings.AntiAim.Jitter = v
end

local function ToggleDesync(v)
    Settings.AntiAim.Desync = v
    if not v then
        if desyncGyro then desyncGyro:Destroy() desyncGyro = nil end
        return
    end
    local root = cachedRoot
    if not root then return end
    if desyncGyro then desyncGyro:Destroy() end
    desyncGyro = Instance.new("BodyGyro")
    desyncGyro.MaxTorque = Vector3.new(400000, 400000, 400000)
    desyncGyro.P = 100000
    desyncGyro.Parent = root
end

local function ToggleHideHead(v)
    Settings.AntiAim.HideHead = v
end

local function ToggleDesyncSpin()
    Settings.AntiAim.DesyncType = "Spin"
end

local function ToggleDesyncBackwards()
    Settings.AntiAim.DesyncType = "Backwards"
end

local function ToggleFakeLag(v)
    Settings.AntiAim.FakeLag = v
end

table.insert(connections, UserInputService.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton2 then isAiming = true end
    if input.KeyCode == Enum.KeyCode.X then 
        Settings.Fly.Enabled = not Settings.Fly.Enabled 
    end
    if input.KeyCode == Enum.KeyCode.T and Settings.TeleportEnabled then
        local rayOrigin = Camera.CFrame.Position
        local rayDirection = Camera.CFrame.LookVector * 1000
        local result = Workspace:Raycast(rayOrigin, rayDirection)
        local targetPos = result and result.Position or (rayOrigin + rayDirection)
        local root = cachedRoot
        if root then root.CFrame = CFrame.new(targetPos) end
    end
end))

table.insert(connections, UserInputService.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton2 then isAiming = false end
end))

RunService.RenderStepped:Connect(function()
    if AntiDetected then return end

    allPlayers = Players:GetPlayers()

    if drawingAvailable then
        if Settings.Tracers.Enabled then
            for _, plr in ipairs(allPlayers) do
                if plr == LocalPlayer or not plr.Character or not plr.Character:FindFirstChild("HumanoidRootPart") then continue end
                if Settings.Tracers.OnlyEnemies and not IsEnemy(plr) then continue end
                local root = plr.Character.HumanoidRootPart
                local dist = (root.Position - Camera.CFrame.Position).Magnitude
                if dist > 950 then continue end
                local dir = (root.Position - Camera.CFrame.Position).Unit
                local angle = math.acos(Camera.CFrame.LookVector:Dot(dir))
                if angle > math.rad(Settings.Tracers.FOV) then continue end
                if not TracersTable[plr] then
                    local line = Drawing.new("Line")
                    local text = Drawing.new("Text")
                    TracersTable[plr] = {Line = line, Text = text}
                    text.Center = true
                    text.Outline = true
                    text.Size = 16
                end
                local tracer = TracersTable[plr].Line
                local textObj = TracersTable[plr].Text
                local color = IsFriend(plr) and Color3.fromRGB(0,255,0) or Settings.Tracers.Color
                local toPos = root.Position + Vector3.new(0,3,0)
                local screenTo = Camera:WorldToViewportPoint(toPos)
                tracer.From = Vector2.new(Camera.ViewportSize.X/2, Camera.ViewportSize.Y-40)
                tracer.To = Vector2.new(screenTo.X, screenTo.Y)
                tracer.Color = color
                tracer.Thickness = Settings.Tracers.Thickness
                tracer.Transparency = Settings.Tracers.Transparency
                tracer.Visible = true
                textObj.Text = string.format("%s | %.0fm", plr.Name, dist)
                textObj.Position = Vector2.new(screenTo.X, screenTo.Y-25)
                textObj.Color = color
                textObj.Visible = true
            end
        else
            for _, data in pairs(TracersTable) do
                if data.Line then data.Line:Remove() end
                if data.Text then data.Text:Remove() end
            end
            TracersTable = {}
        end

        if Settings.ESP.Enabled then
            for _, plr in ipairs(allPlayers) do
                if plr == LocalPlayer or not plr.Character then continue end
                if Settings.ESP.OnlyEnemies and not IsEnemy(plr) then continue end
                local root = plr.Character:FindFirstChild("HumanoidRootPart")
                local hum = plr.Character:FindFirstChild("Humanoid")
                if not root or not hum then continue end
                local dist = (root.Position - Camera.CFrame.Position).Magnitude
                if dist > Settings.ESP.MaxDistance then continue end
                local headPos = root.Position + Vector3.new(0, 2.5, 0)
                local legPos = root.Position - Vector3.new(0, 2.5, 0)
                local headScreen, visHead = Camera:WorldToViewportPoint(headPos)
                local legScreen, visLeg = Camera:WorldToViewportPoint(legPos)
                if not (visHead and visLeg) then continue end
                local height = math.abs(legScreen.Y - headScreen.Y)
                local width = height * 0.5
                local x = headScreen.X - width / 2
                local y = headScreen.Y
                if Settings.ESP.Boxes then
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
                if Settings.ESP.HealthBar then
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
                if Settings.ESP.Snaplines then
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
            end
        else
            for _, box in pairs(espBoxes) do if box then box.Visible = false end end
            for _, bars in pairs(espHealthBars) do 
                if bars then 
                    if bars.bg then bars.bg.Visible = false end 
                    if bars.fill then bars.fill.Visible = false end 
                end 
            end
            for _, line in pairs(espSnaplines) do if line then line.Visible = false end end
        end
    end

    if isAiming and Settings.Aimbot.Enabled then
        local closest = nil
        local shortest = Settings.Aimbot.FOV
        local mousePos = UserInputService:GetMouseLocation()
        for _, plr in ipairs(allPlayers) do
            if not IsEnemy(plr) or not plr.Character then continue end
            local root = plr.Character:FindFirstChild("HumanoidRootPart")
            local hum = plr.Character:FindFirstChild("Humanoid")
            if not root or not hum or hum.Health <= 0 then continue end
            local targetPos = root.Position + Vector3.new(0, Settings.Aimbot.HitboxOffset, 0)
            if Settings.Aimbot.WallCheck and not IsVisible(targetPos) then continue end
            local predicted = targetPos + (root.AssemblyLinearVelocity or Vector3.new()) * Settings.Aimbot.Prediction
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
                local dx = (closest.X - mousePos.X) / Settings.Aimbot.Smoothing
                local dy = (closest.Y - mousePos.Y) / Settings.Aimbot.Smoothing
                mousemoverel(dx * Settings.Aimbot.Sensitivity, dy * Settings.Aimbot.Sensitivity)
            else
                local ray = Camera:ScreenPointToRay(closest.X, closest.Y)
                local targetWorld = ray.Origin + ray.Direction * 100
                Camera.CFrame = CFrame.lookAt(Camera.CFrame.Position, targetWorld)
            end
        end
    end
end)

RunService.Heartbeat:Connect(function()
    UpdateFly()
    UpdateAntiAim()
end)

LocalPlayer.CharacterAdded:Connect(function()
    task.wait(0.2)
    UpdateCache()
    if Settings.Fly.Enabled then CreateFly() end
    if Settings.NoClip then ToggleNoClip(true) end
    if Settings.HitboxExpander.Enabled then ToggleHitboxExpander(true) end
    if Settings.AntiAim.Jitter then ToggleJitter(true) end
    if Settings.AntiAim.Desync then ToggleDesync(true) end
    if Settings.AntiAim.HideHead then ToggleHideHead(true) end
end)

LocalPlayer.CharacterRemoving:Connect(function()
    if flyLinearVelocity then flyLinearVelocity:Destroy() flyLinearVelocity = nil end
    if flyAlignOrientation then flyAlignOrientation:Destroy() flyAlignOrientation = nil end
    if flyAttachment then flyAttachment:Destroy() flyAttachment = nil end
    if desyncGyro then desyncGyro:Destroy() desyncGyro = nil end
    if Settings.AutoRejoin and not AntiDetected then
        task.wait(1)
        TeleportService:Teleport(game.PlaceId, LocalPlayer)
    end
end)

if Rayfield then
    local Window = Rayfield:CreateWindow({Name = "ABYSS ARCHON • UNIVERSAL 2026", LoadingTitle = "ABYSS ARCHON v1003.420", LoadingSubtitle = "Xeno Edition", Theme = "DarkBlue", ToggleUIKeybind = Enum.KeyCode.RightShift, ConfigurationSaving = {Enabled = true, FolderName = "AbyssUniversal", FileName = "Config"}})

    local Tab_Combat = Window:CreateTab("Бой", "crosshair")
    Tab_Combat:CreateSection("Аимбот")
    Tab_Combat:CreateToggle({Name = "Аимбот (ПКМ)", CurrentValue = false, Callback = function(v) Settings.Aimbot.Enabled = v end})
    Tab_Combat:CreateToggle({Name = "Silent Aim", CurrentValue = false, Callback = function(v) Settings.Aimbot.Silent = v if v then EnableSilentAim() else DisableSilentAim() end end})
    Tab_Combat:CreateToggle({Name = "Triggerbot", CurrentValue = false, Callback = function(v) Settings.Triggerbot = v end})
    Tab_Combat:CreateToggle({Name = "Только враги", CurrentValue = true, Callback = function(v) Settings.Tracers.OnlyEnemies = v Settings.ESP.OnlyEnemies = v end})
    Tab_Combat:CreateSlider({Name = "FOV", Range = {10,500}, Increment = 10, CurrentValue = 120, Callback = function(v) Settings.Aimbot.FOV = v end})
    Tab_Combat:CreateSlider({Name = "Сглаживание", Range = {1,15}, Increment = 1, CurrentValue = 3, Callback = function(v) Settings.Aimbot.Smoothing = v end})
    Tab_Combat:CreateSlider({Name = "Prediction", Range = {0,0.3}, Increment = 0.01, CurrentValue = 0.12, Callback = function(v) Settings.Aimbot.Prediction = v end})
    Tab_Combat:CreateSlider({Name = "Hitbox Offset", Range = {0,5}, Increment = 0.1, CurrentValue = 2.5, Callback = function(v) Settings.Aimbot.HitboxOffset = v end})
    Tab_Combat:CreateSlider({Name = "Sensitivity", Range = {0.5,3}, Increment = 0.1, CurrentValue = 1.2, Callback = function(v) Settings.Aimbot.Sensitivity = v end})
    Tab_Combat:CreateToggle({Name = "WallCheck", CurrentValue = true, Callback = function(v) Settings.Aimbot.WallCheck = v end})

    local Tab_Visuals = Window:CreateTab("Визуал", "eye")
    Tab_Visuals:CreateSection("Трассеры")
    Tab_Visuals:CreateToggle({Name = "Трассеры", CurrentValue = false, Callback = function(v) Settings.Tracers.Enabled = v end})
    Tab_Visuals:CreateSlider({Name = "FOV Трассеров", Range = {30,360}, Increment = 10, CurrentValue = 160, Callback = function(v) Settings.Tracers.FOV = v end})
    Tab_Visuals:CreateSlider({Name = "Толщина", Range = {1,5}, Increment = 0.5, CurrentValue = 2, Callback = function(v) Settings.Tracers.Thickness = v end})
    Tab_Visuals:CreateSlider({Name = "Прозрачность", Range = {0.1,1}, Increment = 0.05, CurrentValue = 0.8, Callback = function(v) Settings.Tracers.Transparency = v end})
    Tab_Visuals:CreateSection("ESP")
    Tab_Visuals:CreateToggle({Name = "ESP Enabled", CurrentValue = false, Callback = function(v) Settings.ESP.Enabled = v end})
    Tab_Visuals:CreateToggle({Name = "Box ESP", CurrentValue = false, Callback = function(v) Settings.ESP.Boxes = v end})
    Tab_Visuals:CreateToggle({Name = "Health Bar", CurrentValue = false, Callback = function(v) Settings.ESP.HealthBar = v end})
    Tab_Visuals:CreateToggle({Name = "Snaplines", CurrentValue = false, Callback = function(v) Settings.ESP.Snaplines = v end})
    Tab_Visuals:CreateToggle({Name = "Chams", CurrentValue = false, Callback = function(v) Settings.ESP.Chams = v end})
    Tab_Visuals:CreateSlider({Name = "Max Distance", Range = {100,1000}, Increment = 10, CurrentValue = 500, Callback = function(v) Settings.ESP.MaxDistance = v end})

    local Tab_Rage = Window:CreateTab("Rage", "sword")
    Tab_Rage:CreateSection("Rage Mode")
    Tab_Rage:CreateToggle({Name = "Spinbot", CurrentValue = false, Callback = function(v) Settings.Rage.Spinbot = v end})
    Tab_Rage:CreateSlider({Name = "Spin Speed", Range = {5,100}, Increment = 1, CurrentValue = 25, Callback = function(v) Settings.Rage.SpinSpeed = v end})
    Tab_Rage:CreateSection("Kill Aura")
    Tab_Rage:CreateToggle({Name = "Kill Aura", CurrentValue = false, Callback = function(v) Settings.Aura.Enabled = v end})
    Tab_Rage:CreateSlider({Name = "Aura Radius", Range = {5,100}, Increment = 1, CurrentValue = 50, Callback = function(v) Settings.Aura.Radius = v end})
    Tab_Rage:CreateSlider({Name = "Aura Damage", Range = {10,500}, Increment = 10, CurrentValue = 100, Callback = function(v) Settings.Aura.Damage = v end})
    Tab_Rage:CreateSlider({Name = "Aura Delay", Range = {0.05,1}, Increment = 0.05, CurrentValue = 0.2, Callback = function(v) Settings.Aura.Delay = v end})
    Tab_Rage:CreateSection("Дополнительный Rage")
    Tab_Rage:CreateToggle({Name = "Rapid Fire", CurrentValue = false, Callback = function(v) Settings.RapidFire = v end})
    Tab_Rage:CreateToggle({Name = "Auto Equip Weapon", CurrentValue = false, Callback = function(v) Settings.AutoWeapon = v end})
    Tab_Rage:CreateToggle({Name = "Auto Rejoin on Kick", CurrentValue = false, Callback = function(v) Settings.AutoRejoin = v end})

    local Tab_AntiAim = Window:CreateTab("Anti-Aim", "shield")
    Tab_AntiAim:CreateSection("Вращение")
    Tab_AntiAim:CreateToggle({Name = "Jitter", CurrentValue = false, Callback = ToggleJitter})
    Tab_AntiAim:CreateSlider({Name = "Jitter Angle", Range = {10,180}, Increment = 5, CurrentValue = 40, Callback = function(v) Settings.AntiAim.JitterAngle = v end})
    Tab_AntiAim:CreateToggle({Name = "Spinbot", CurrentValue = false, Callback = function(v) Settings.Rage.Spinbot = v end})
    Tab_AntiAim:CreateSlider({Name = "Spin Speed", Range = {5,100}, Increment = 1, CurrentValue = 25, Callback = function(v) Settings.Rage.SpinSpeed = v end})

    Tab_AntiAim:CreateSection("Десинк")
    Tab_AntiAim:CreateToggle({Name = "Desync", CurrentValue = false, Callback = ToggleDesync})
    Tab_AntiAim:CreateToggle({Name = "Desync Spin", CurrentValue = true, Callback = ToggleDesyncSpin})
    Tab_AntiAim:CreateToggle({Name = "Desync Backwards", CurrentValue = false, Callback = ToggleDesyncBackwards})
    Tab_AntiAim:CreateSlider({Name = "Desync Speed", Range = {10,200}, Increment = 5, CurrentValue = 30, Callback = function(v) Settings.AntiAim.DesyncSpeed = v end})

    Tab_AntiAim:CreateSection("Голова")
    Tab_AntiAim:CreateToggle({Name = "Hide Head", CurrentValue = false, Callback = ToggleHideHead})
    Tab_AntiAim:CreateToggle({Name = "Hide Head Back", CurrentValue = true, Callback = function(v) if v then Settings.AntiAim.HideHeadMode = "Back" end end})
    Tab_AntiAim:CreateToggle({Name = "Hide Head Down", CurrentValue = false, Callback = function(v) if v then Settings.AntiAim.HideHeadMode = "Down" end end})

    Tab_AntiAim:CreateSection("Fake Lag (Пинг 999)")
    Tab_AntiAim:CreateToggle({Name = "Fake Lag", CurrentValue = false, Callback = ToggleFakeLag})
    Tab_AntiAim:CreateSlider({Name = "Lag Intensity", Range = {1,15}, Increment = 0.5, CurrentValue = 5, Callback = function(v) Settings.AntiAim.FakeLagIntensity = v end})
    Tab_AntiAim:CreateSlider({Name = "Lag Frequency", Range = {1,5}, Increment = 1, CurrentValue = 1, Callback = function(v) Settings.AntiAim.FakeLagFrequency = v end})
    Tab_AntiAim:CreateToggle({Name = "Lag Back&Forth", CurrentValue = false, Callback = function(v) if v then Settings.AntiAim.FakeLagMode = "BackAndForth" else Settings.AntiAim.FakeLagMode = "Random" end end})
    Tab_AntiAim:CreateToggle({Name = "Lag NoClip", CurrentValue = true, Callback = function(v) Settings.AntiAim.FakeLagNoClip = v end})

    local Tab_Movement = Window:CreateTab("Движение", "zap")
    Tab_Movement:CreateSection("Спидхак")
    Tab_Movement:CreateButton({Name = "x2 (32)", Callback = function() Settings.SpeedHack.Enabled = true Settings.SpeedHack.Speed = 32 end})
    Tab_Movement:CreateButton({Name = "x3 (48)", Callback = function() Settings.SpeedHack.Enabled = true Settings.SpeedHack.Speed = 48 end})
    Tab_Movement:CreateButton({Name = "x5 (80)", Callback = function() Settings.SpeedHack.Enabled = true Settings.SpeedHack.Speed = 80 end})
    Tab_Movement:CreateButton({Name = "ВЫКЛ СПИД", Callback = function() Settings.SpeedHack.Enabled = false end})
    Tab_Movement:CreateSection("Дополнительно")
    Tab_Movement:CreateToggle({Name = "NoClip", CurrentValue = false, Callback = function(v) ToggleNoClip(v) end})
    Tab_Movement:CreateToggle({Name = "Infinite Jump", CurrentValue = false, Callback = function(v) Settings.InfJump = v end})
    Tab_Movement:CreateToggle({Name = "Hitbox Expander", CurrentValue = false, Callback = function(v) ToggleHitboxExpander(v) end})
    Tab_Movement:CreateToggle({Name = "Fly (X)", CurrentValue = false, Callback = function(v) Settings.Fly.Enabled = v end})
    Tab_Movement:CreateSlider({Name = "Fly Speed", Range = {30,150}, Increment = 5, CurrentValue = 70, Callback = function(v) Settings.Fly.Speed = v end})
    Tab_Movement:CreateToggle({Name = "Blatant Teleport (T)", CurrentValue = false, Callback = function(v) Settings.TeleportEnabled = v end})

    Rayfield:LoadConfiguration()
    Rayfield:Notify({Title = "ABYSS ARCHON", Content = "v1003.420 ЗАГРУЖЕН | CLEAN + SILENT AIM + FAKE LAG + MOTOR6D | ПРОФЕССИОНАЛЬНЫЙ УРОВЕНЬ | ГОТОВ К АННИГИЛЯЦИИ", Duration = 8})
end

print("ABYSS ARCHON v1003.420 — ETERNAL VOID LOCKDOWN AWAKENED")