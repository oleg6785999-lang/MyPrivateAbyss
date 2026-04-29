-- 1.lua / Main.lua — ABYSS ARCHON / Modular Loader
-- UI (Rayfield) -> Modules -> LoadConfiguration -> Notify

local DEFAULTS = {
    Aimbot = {
        Enabled = false, Silent = false, FOV = 120, Smoothing = 3,
        Sensitivity = 1.0, Prediction = 0.12, HitboxOffset = 0, WallCheck = true,
    },
    Rage = { Spinbot = false, SpinSpeed = 25 },
    SpeedHack = { Enabled = false, Speed = 50 },
    Fly = { Enabled = false, Speed = 58 },
    InfJump = false,
    NoClip = false,
    HitboxExpander = { Enabled = false, Size = 12 },
    ESP = {
        Enabled = false, Boxes = false, HealthBar = false, Snaplines = false,
        OnlyEnemies = true, MaxDistance = 500, Chams = false,
    },
    AntiAim = {
        Jitter = false, JitterAngle = 40,
        Desync = false, DesyncType = "Spin", DesyncSpeed = 30,
        HideHead = false, HideHeadMode = "Back",
        FakeLag = false, FakeLagIntensity = 5, FakeLagFrequency = 1,
        FakeLagMode = "Random", FakeLagNoClip = true,
    },
}

_G.Settings = _G.Settings or {}
for k, v in pairs(DEFAULTS) do
    if type(v) == "table" then
        _G.Settings[k] = _G.Settings[k] or {}
        for k2, v2 in pairs(v) do
            if _G.Settings[k][k2] == nil then _G.Settings[k][k2] = v2 end
        end
    elseif _G.Settings[k] == nil then
        _G.Settings[k] = v
    end
end

_G.Players     = game:GetService("Players")
_G.Camera      = workspace.CurrentCamera
_G.LocalPlayer = _G.Players.LocalPlayer

local baseUrl = "https://raw.githubusercontent.com/oleg6785999-lang/MyPrivateAbyss/main/"

-- ============================================================
-- 2. Загрузка Rayfield
-- ============================================================
local Rayfield
local urls = {
    "https://sirius.menu/rayfield",
    "https://raw.githubusercontent.com/SiriusSoftwareLtd/Rayfield/main/source.lua",
}

local function LoadRayfield()
    for _, url in ipairs(urls) do
        local ok, result = pcall(function() return loadstring(game:HttpGet(url))() end)
        if ok and typeof(result) == "table" and result.CreateWindow then
            Rayfield = result
            return true
        end
    end
    return false
end

if not LoadRayfield() then
    if getgenv and getgenv().Rayfield_InterfaceBuild then
        getgenv().Rayfield_InterfaceBuild = nil
    end
    LoadRayfield()
end

if not Rayfield then
    warn("[ABYSS] Rayfield не загрузился")
    return
end

local newName = "x" .. string.char(math.random(65,90)) .. string.char(math.random(65,90))
                    .. string.char(math.random(65,90)) .. tostring(math.random(1000,9999))
pcall(function() Rayfield.Interface.Name = newName end)

local Window = Rayfield:CreateWindow({
    Name            = "ABYSS ARCHON • MODULAR",
    LoadingTitle    = "ABYSS ARCHON v1005.420",
    LoadingSubtitle = "Professional Modular Edition",
    Theme           = "DarkBlue",
    ToggleUIKeybind = Enum.KeyCode.RightShift,
    ConfigurationSaving = { Enabled = true, FolderName = "AbyssUniversal", FileName = "Config" },
})

-- ============================================================
-- 3. COMBAT (Aimbot) — все параметры нового модуля
-- ============================================================
local Tab_Combat = Window:CreateTab("Бой", "crosshair")

Tab_Combat:CreateSection("Аимбот")
Tab_Combat:CreateToggle({Name = "Aimbot (Visible)", CurrentValue = _G.Settings.Aimbot.Enabled,
    Callback = function(v) _G.Settings.Aimbot.Enabled = v end})
Tab_Combat:CreateToggle({Name = "Silent Aim", CurrentValue = _G.Settings.Aimbot.Silent,
    Callback = function(v) _G.Settings.Aimbot.Silent = v end})

Tab_Combat:CreateSection("Настройка")
Tab_Combat:CreateSlider({Name = "FOV", Range = {10, 600}, Increment = 10,
    CurrentValue = _G.Settings.Aimbot.FOV,
    Callback = function(v) _G.Settings.Aimbot.FOV = v end})
Tab_Combat:CreateSlider({Name = "Smoothing", Range = {1, 20}, Increment = 1,
    CurrentValue = _G.Settings.Aimbot.Smoothing,
    Callback = function(v) _G.Settings.Aimbot.Smoothing = v end})
Tab_Combat:CreateSlider({Name = "Sensitivity", Range = {0.1, 3}, Increment = 0.05, Suffix = "x",
    CurrentValue = _G.Settings.Aimbot.Sensitivity,
    Callback = function(v) _G.Settings.Aimbot.Sensitivity = v end})
Tab_Combat:CreateSlider({Name = "Prediction", Range = {0, 0.5}, Increment = 0.01,
    CurrentValue = _G.Settings.Aimbot.Prediction,
    Callback = function(v) _G.Settings.Aimbot.Prediction = v end})
Tab_Combat:CreateSlider({Name = "Hitbox Offset (Y)", Range = {-3, 3}, Increment = 0.1,
    CurrentValue = _G.Settings.Aimbot.HitboxOffset,
    Callback = function(v) _G.Settings.Aimbot.HitboxOffset = v end})

Tab_Combat:CreateSection("Фильтры")
Tab_Combat:CreateToggle({Name = "Wall Check", CurrentValue = _G.Settings.Aimbot.WallCheck,
    Callback = function(v) _G.Settings.Aimbot.WallCheck = v end})
Tab_Combat:CreateToggle({Name = "Only Enemies", CurrentValue = _G.Settings.ESP.OnlyEnemies,
    Callback = function(v) _G.Settings.ESP.OnlyEnemies = v end})

-- ============================================================
-- 4. VISUALS (ESP)
-- ============================================================
local Tab_Visuals = Window:CreateTab("Визуал", "eye")

Tab_Visuals:CreateSection("ESP")
Tab_Visuals:CreateToggle({Name = "Enable ESP", CurrentValue = _G.Settings.ESP.Enabled,
    Callback = function(v) _G.Settings.ESP.Enabled = v end})
Tab_Visuals:CreateToggle({Name = "Box ESP", CurrentValue = _G.Settings.ESP.Boxes,
    Callback = function(v) _G.Settings.ESP.Boxes = v end})
Tab_Visuals:CreateToggle({Name = "Health Bar", CurrentValue = _G.Settings.ESP.HealthBar,
    Callback = function(v) _G.Settings.ESP.HealthBar = v end})
Tab_Visuals:CreateToggle({Name = "Snaplines", CurrentValue = _G.Settings.ESP.Snaplines,
    Callback = function(v) _G.Settings.ESP.Snaplines = v end})
Tab_Visuals:CreateToggle({Name = "Chams", CurrentValue = _G.Settings.ESP.Chams,
    Callback = function(v) _G.Settings.ESP.Chams = v end})

Tab_Visuals:CreateSection("Параметры")
Tab_Visuals:CreateSlider({Name = "Max Distance", Range = {50, 2000}, Increment = 50,
    CurrentValue = _G.Settings.ESP.MaxDistance,
    Callback = function(v) _G.Settings.ESP.MaxDistance = v end})

-- ============================================================
-- 5. ANTI-AIM
-- ============================================================
local Tab_AntiAim = Window:CreateTab("Anti-Aim", "shield")

Tab_AntiAim:CreateSection("Jitter")
Tab_AntiAim:CreateToggle({Name = "Jitter", CurrentValue = _G.Settings.AntiAim.Jitter,
    Callback = function(v) _G.Settings.AntiAim.Jitter = v end})
Tab_AntiAim:CreateSlider({Name = "Jitter Angle", Range = {10, 180}, Increment = 5,
    CurrentValue = _G.Settings.AntiAim.JitterAngle,
    Callback = function(v) _G.Settings.AntiAim.JitterAngle = v end})

Tab_AntiAim:CreateSection("Desync")
Tab_AntiAim:CreateToggle({Name = "Desync", CurrentValue = _G.Settings.AntiAim.Desync,
    Callback = function(v) _G.Settings.AntiAim.Desync = v end})
Tab_AntiAim:CreateDropdown({Name = "Desync Type", Options = {"Spin", "Backwards"},
    CurrentOption = { _G.Settings.AntiAim.DesyncType or "Spin" },
    Callback = function(o) _G.Settings.AntiAim.DesyncType = o[1] end})
Tab_AntiAim:CreateSlider({Name = "Desync Speed", Range = {10, 200}, Increment = 5,
    CurrentValue = _G.Settings.AntiAim.DesyncSpeed,
    Callback = function(v) _G.Settings.AntiAim.DesyncSpeed = v end})

Tab_AntiAim:CreateSection("Hide Head")
Tab_AntiAim:CreateToggle({Name = "Hide Head", CurrentValue = _G.Settings.AntiAim.HideHead,
    Callback = function(v) _G.Settings.AntiAim.HideHead = v end})
Tab_AntiAim:CreateDropdown({Name = "Hide Head Mode", Options = {"Back", "Down"},
    CurrentOption = { _G.Settings.AntiAim.HideHeadMode or "Back" },
    Callback = function(o) _G.Settings.AntiAim.HideHeadMode = o[1] end})

Tab_AntiAim:CreateSection("Fake Lag")
Tab_AntiAim:CreateToggle({Name = "Fake Lag", CurrentValue = _G.Settings.AntiAim.FakeLag,
    Callback = function(v) _G.Settings.AntiAim.FakeLag = v end})
Tab_AntiAim:CreateSlider({Name = "Lag Intensity", Range = {1, 15}, Increment = 0.5,
    CurrentValue = _G.Settings.AntiAim.FakeLagIntensity,
    Callback = function(v) _G.Settings.AntiAim.FakeLagIntensity = v end})
Tab_AntiAim:CreateSlider({Name = "Lag Frequency", Range = {1, 5}, Increment = 1,
    CurrentValue = _G.Settings.AntiAim.FakeLagFrequency,
    Callback = function(v) _G.Settings.AntiAim.FakeLagFrequency = v end})
Tab_AntiAim:CreateDropdown({Name = "Lag Mode", Options = {"Random", "BackAndForth"},
    CurrentOption = { _G.Settings.AntiAim.FakeLagMode or "Random" },
    Callback = function(o) _G.Settings.AntiAim.FakeLagMode = o[1] end})
Tab_AntiAim:CreateToggle({Name = "Lag NoClip", CurrentValue = _G.Settings.AntiAim.FakeLagNoClip,
    Callback = function(v) _G.Settings.AntiAim.FakeLagNoClip = v end})

-- ============================================================
-- 6. MOVEMENT
-- ============================================================
local Tab_Movement = Window:CreateTab("Движение", "zap")

Tab_Movement:CreateSection("SpeedHack")
Tab_Movement:CreateButton({Name = "x2 (32)", Callback = function()
    _G.Settings.SpeedHack.Enabled = true; _G.Settings.SpeedHack.Speed = 32 end})
Tab_Movement:CreateButton({Name = "x3 (48)", Callback = function()
    _G.Settings.SpeedHack.Enabled = true; _G.Settings.SpeedHack.Speed = 48 end})
Tab_Movement:CreateButton({Name = "x5 (80)", Callback = function()
    _G.Settings.SpeedHack.Enabled = true; _G.Settings.SpeedHack.Speed = 80 end})
Tab_Movement:CreateButton({Name = "ВЫКЛ Speed", Callback = function()
    _G.Settings.SpeedHack.Enabled = false end})

Tab_Movement:CreateSection("Fly / NoClip")
Tab_Movement:CreateToggle({Name = "Fly (X)", CurrentValue = _G.Settings.Fly.Enabled,
    Callback = function(v) _G.Settings.Fly.Enabled = v end})
Tab_Movement:CreateSlider({Name = "Fly Speed", Range = {30, 150}, Increment = 5,
    CurrentValue = _G.Settings.Fly.Speed,
    Callback = function(v) _G.Settings.Fly.Speed = v end})
Tab_Movement:CreateToggle({Name = "NoClip", CurrentValue = _G.Settings.NoClip,
    Callback = function(v) _G.Settings.NoClip = v end})

Tab_Movement:CreateSection("Прочее")
Tab_Movement:CreateToggle({Name = "Infinite Jump", CurrentValue = _G.Settings.InfJump,
    Callback = function(v) _G.Settings.InfJump = v end})
Tab_Movement:CreateToggle({Name = "Hitbox Expander", CurrentValue = _G.Settings.HitboxExpander.Enabled,
    Callback = function(v) _G.Settings.HitboxExpander.Enabled = v end})
Tab_Movement:CreateSlider({Name = "Hitbox Size", Range = {3, 25}, Increment = 1,
    CurrentValue = _G.Settings.HitboxExpander.Size,
    Callback = function(v) _G.Settings.HitboxExpander.Size = v end})

-- ============================================================
-- 7. RAGE
-- ============================================================
local Tab_Rage = Window:CreateTab("Rage", "sword")
Tab_Rage:CreateSection("Spinbot")
Tab_Rage:CreateToggle({Name = "Spinbot", CurrentValue = _G.Settings.Rage.Spinbot,
    Callback = function(v) _G.Settings.Rage.Spinbot = v end})
Tab_Rage:CreateSlider({Name = "Spin Speed", Range = {5, 100}, Increment = 5,
    CurrentValue = _G.Settings.Rage.SpinSpeed,
    Callback = function(v) _G.Settings.Rage.SpinSpeed = v end})

-- ============================================================
-- 8. ЗАГРУЗКА МОДУЛЕЙ -> LoadConfiguration -> Notify
-- ============================================================
local function FastSafeLoad(name)
    for i = 1, 4 do
        local ok = pcall(function() loadstring(game:HttpGet(baseUrl .. name .. ".lua", true))() end)
        if ok then
            print("[ABYSS] " .. name .. " loaded")
            return true
        end
        task.wait(0.15 * i)
    end
    warn("[ABYSS] FAILED " .. name)
    return false
end

FastSafeLoad("Aimbot")
FastSafeLoad("Visuals")
FastSafeLoad("Movement")
FastSafeLoad("AntiAim")

-- LoadConfiguration ПОСЛЕ модулей: их Settings уже инициализированы,
-- сохранённые значения корректно применятся через Callbacks UI.
pcall(function() Rayfield:LoadConfiguration() end)

Rayfield:Notify({
    Title    = "ABYSS ARCHON",
    Content  = "MODULAR v1005.420 LOADED",
    Duration = 6,
})

print("ABYSS ARCHON MODULAR LOADER v1005.420 — READY")
