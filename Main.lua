-- Main.lua
_G.Settings = _G.Settings or {
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
    AntiAim = {
        Jitter = false, JitterAngle = 40,
        Desync = false, DesyncType = "Spin", DesyncSpeed = 30,
        HideHead = false, HideHeadMode = "Back",
        FakeLag = false, FakeLagIntensity = 5, FakeLagFrequency = 1, FakeLagMode = "Random", FakeLagNoClip = true
    }
}

_G.Players = game:GetService("Players")
_G.Camera = workspace.CurrentCamera
_G.LocalPlayer = _G.Players.LocalPlayer

local baseUrl = "https://raw.githubusercontent.com/oleg6785999-lang/MyPrivateAbyss/main/"

local function LoadModule(name)
    local success, result = pcall(function()
        return loadstring(game:HttpGet(baseUrl .. name .. ".lua"))()
    end)
    if not success then
        warn("[ABYSS] Failed to load module: " .. name)
    end
    return result
end

LoadModule("Aimbot")
LoadModule("Visuals")
LoadModule("Movement")
LoadModule("AntiAim")

local Rayfield = nil
local urls = {
    "https://sirius.menu/rayfield",
    "https://raw.githubusercontent.com/SiriusSoftwareLtd/Rayfield/main/source.lua",
    "https://raw.githubusercontent.com/Janixx/Rayfield/main/source.lua"
}

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

    local Window = Rayfield:CreateWindow({
        Name = "ABYSS ARCHON • MODULAR",
        LoadingTitle = "ABYSS ARCHON v1005.420",
        LoadingSubtitle = "Professional Modular Edition",
        Theme = "DarkBlue",
        ToggleUIKeybind = Enum.KeyCode.RightShift,
        ConfigurationSaving = {Enabled = true, FolderName = "AbyssUniversal", FileName = "Config"}
    })

    local Tab_Combat = Window:CreateTab("Бой", "crosshair")
    Tab_Combat:CreateSection("Аимбот")
    Tab_Combat:CreateToggle({Name = "Аимбот (ПКМ)", CurrentValue = false, Callback = function(v) _G.Settings.Aimbot.Enabled = v end})
    Tab_Combat:CreateToggle({Name = "Silent Aim", CurrentValue = false, Callback = function(v) _G.Settings.Aimbot.Silent = v end})
    Tab_Combat:CreateToggle({Name = "Triggerbot", CurrentValue = false, Callback = function(v) _G.Settings.Triggerbot = v end})

    local Tab_Visuals = Window:CreateTab("Визуал", "eye")
    Tab_Visuals:CreateSection("Трассеры")
    Tab_Visuals:CreateToggle({Name = "Трассеры", CurrentValue = false, Callback = function(v) _G.Settings.Tracers.Enabled = v end})
    Tab_Visuals:CreateSection("ESP")
    Tab_Visuals:CreateToggle({Name = "ESP Enabled", CurrentValue = false, Callback = function(v) _G.Settings.ESP.Enabled = v end})
    Tab_Visuals:CreateToggle({Name = "Box ESP", CurrentValue = false, Callback = function(v) _G.Settings.ESP.Boxes = v end})
    Tab_Visuals:CreateToggle({Name = "Health Bar", CurrentValue = false, Callback = function(v) _G.Settings.ESP.HealthBar = v end})
    Tab_Visuals:CreateToggle({Name = "Snaplines", CurrentValue = false, Callback = function(v) _G.Settings.ESP.Snaplines = v end})
    Tab_Visuals:CreateToggle({Name = "Chams", CurrentValue = false, Callback = function(v) _G.Settings.ESP.Chams = v end})

    local Tab_Rage = Window:CreateTab("Rage", "sword")
    Tab_Rage:CreateSection("Rage Mode")
    Tab_Rage:CreateToggle({Name = "Spinbot", CurrentValue = false, Callback = function(v) _G.Settings.Rage.Spinbot = v end})
    Tab_Rage:CreateSection("Kill Aura")
    Tab_Rage:CreateToggle({Name = "Kill Aura", CurrentValue = false, Callback = function(v) _G.Settings.Aura.Enabled = v end})
    Tab_Rage:CreateSection("Дополнительный Rage")
    Tab_Rage:CreateToggle({Name = "Rapid Fire", CurrentValue = false, Callback = function(v) _G.Settings.RapidFire = v end})

    local Tab_AntiAim = Window:CreateTab("Anti-Aim", "shield")
    Tab_AntiAim:CreateSection("Anti-Aim")
    Tab_AntiAim:CreateToggle({Name = "Jitter", CurrentValue = false, Callback = function(v) _G.Settings.AntiAim.Jitter = v end})
    Tab_AntiAim:CreateSlider({Name = "Jitter Angle", Range = {10,180}, Increment = 5, CurrentValue = 40, Callback = function(v) _G.Settings.AntiAim.JitterAngle = v end})
    Tab_AntiAim:CreateToggle({Name = "Desync", CurrentValue = false, Callback = function(v) _G.Settings.AntiAim.Desync = v end})
    Tab_AntiAim:CreateToggle({Name = "Desync Spin", CurrentValue = true, Callback = function(v) _G.Settings.AntiAim.DesyncType = "Spin" end})
    Tab_AntiAim:CreateToggle({Name = "Desync Backwards", CurrentValue = false, Callback = function(v) _G.Settings.AntiAim.DesyncType = "Backwards" end})
    Tab_AntiAim:CreateSlider({Name = "Desync Speed", Range = {10,200}, Increment = 5, CurrentValue = 30, Callback = function(v) _G.Settings.AntiAim.DesyncSpeed = v end})
    Tab_AntiAim:CreateToggle({Name = "Hide Head", CurrentValue = false, Callback = function(v) _G.Settings.AntiAim.HideHead = v end})
    Tab_AntiAim:CreateToggle({Name = "Hide Head Back", CurrentValue = true, Callback = function(v) if v then _G.Settings.AntiAim.HideHeadMode = "Back" end end})
    Tab_AntiAim:CreateToggle({Name = "Hide Head Down", CurrentValue = false, Callback = function(v) if v then _G.Settings.AntiAim.HideHeadMode = "Down" end end})
    Tab_AntiAim:CreateToggle({Name = "Fake Lag", CurrentValue = false, Callback = function(v) _G.Settings.AntiAim.FakeLag = v end})
    Tab_AntiAim:CreateSlider({Name = "Lag Intensity", Range = {1,15}, Increment = 0.5, CurrentValue = 5, Callback = function(v) _G.Settings.AntiAim.FakeLagIntensity = v end})
    Tab_AntiAim:CreateSlider({Name = "Lag Frequency", Range = {1,5}, Increment = 1, CurrentValue = 1, Callback = function(v) _G.Settings.AntiAim.FakeLagFrequency = v end})
    Tab_AntiAim:CreateToggle({Name = "Lag Back&Forth", CurrentValue = false, Callback = function(v) if v then _G.Settings.AntiAim.FakeLagMode = "BackAndForth" else _G.Settings.AntiAim.FakeLagMode = "Random" end end})
    Tab_AntiAim:CreateToggle({Name = "Lag NoClip", CurrentValue = true, Callback = function(v) _G.Settings.AntiAim.FakeLagNoClip = v end})

    local Tab_Movement = Window:CreateTab("Движение", "zap")
    Tab_Movement:CreateSection("Спидхак")
    Tab_Movement:CreateButton({Name = "x2 (32)", Callback = function() _G.Settings.SpeedHack.Enabled = true _G.Settings.SpeedHack.Speed = 32 end})
    Tab_Movement:CreateButton({Name = "x3 (48)", Callback = function() _G.Settings.SpeedHack.Enabled = true _G.Settings.SpeedHack.Speed = 48 end})
    Tab_Movement:CreateButton({Name = "x5 (80)", Callback = function() _G.Settings.SpeedHack.Enabled = true _G.Settings.SpeedHack.Speed = 80 end})
    Tab_Movement:CreateButton({Name = "ВЫКЛ СПИД", Callback = function() _G.Settings.SpeedHack.Enabled = false end})
    Tab_Movement:CreateSection("Дополнительно")
    Tab_Movement:CreateToggle({Name = "NoClip", CurrentValue = false, Callback = function(v) _G.Settings.NoClip = v end})
    Tab_Movement:CreateToggle({Name = "Infinite Jump", CurrentValue = false, Callback = function(v) _G.Settings.InfJump = v end})
    Tab_Movement:CreateToggle({Name = "Hitbox Expander", CurrentValue = false, Callback = function(v) _G.Settings.HitboxExpander.Enabled = v end})
    Tab_Movement:CreateToggle({Name = "Fly (X)", CurrentValue = false, Callback = function(v) _G.Settings.Fly.Enabled = v end})
    Tab_Movement:CreateSlider({Name = "Fly Speed", Range = {30,150}, Increment = 5, CurrentValue = 70, Callback = function(v) _G.Settings.Fly.Speed = v end})
    Tab_Movement:CreateToggle({Name = "Blatant Teleport (T)", CurrentValue = false, Callback = function(v) _G.Settings.TeleportEnabled = v end})

    Rayfield:LoadConfiguration()
    Rayfield:Notify({Title = "ABYSS ARCHON", Content = "MODULAR v1005.420 LOADED | READY FOR ANNIHILATION", Duration = 8})
end

print("ABYSS ARCHON MODULAR LOADER v1005.420 — AWAKENED")
