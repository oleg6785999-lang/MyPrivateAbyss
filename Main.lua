-- === ЗАМЕНИ ЭТОТ ФАЙЛ НА ПОЛНОСТЬЮ ===
-- FILENAME: Main.lua
-- ============================================================
-- Main.lua — ABYSS ARCHON / Modular Loader  (v5 ELITE)
--
--   Технические улучшения:
--    1. Namespace isolation: реальные данные в скрытом
--       getgenv()["__ABYSS_DATA__<rand>"]; _G.Settings — alias.
--    2. Robust loader (FastSafeLoad): http проверка, custom headers,
--       раздельный pcall на загрузку и выполнение, возврат (ok, mod|err).
--    3. Schema + DeepMerge: рекурсивное слияние с типовой проверкой
--       и migration по Version.
--    4. Flow: Env -> UI -> Modules (task.spawn + wait) -> Config Apply.
--    5. Stealth: dynamic GetCamera(), randomized ConfigSaving filename
--       (детерминирован per-UserId, чтобы конфиг сохранялся).
-- ============================================================

local CONFIG_VERSION = 5000

----------------------------------------------------------------
-- 1. Cached services (один вызов GetService за всё время жизни)
----------------------------------------------------------------
local Players          = game:GetService("Players")
local RunService       = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

-- LocalPlayer guard: non-blocking poll с реальным hard-timeout.
-- ПРИЧИНА: sig:Wait() блокирует поток навсегда, если событие не приходит.
-- Поллинг через task.wait гарантирует выход максимум за DEADLINE.
local LocalPlayer = Players.LocalPlayer
if not LocalPlayer then
    local deadline = os.clock() + 10
    while not Players.LocalPlayer and os.clock() < deadline do
        task.wait(0.1)
    end
    LocalPlayer = Players.LocalPlayer
end

-- Dynamic camera getter (NO CACHE — пересчитывается при каждом вызове,
-- защита от nil-reference после респавна / смены камеры)
local function GetCamera()
    return workspace.CurrentCamera
end

----------------------------------------------------------------
-- 2. Hidden namespace + proxy alias
----------------------------------------------------------------
local genv = (type(getgenv) == "function") and getgenv() or _G

-- Случайный ключ с расширенной энтропией (~268M вариантов вместо 900)
local HIDDEN_PREFIX = "__ABYSS_DATA__"
local HIDDEN_KEY    = HIDDEN_PREFIX .. string.format("%X", math.random(0x100000, 0xFFFFFFF))

-- Reinject: ищем существующий ключ, удаляем дубликаты (избегаем утечки в getgenv)
local DataStore
do
    local found, foundKey
    local toDelete = {}
    for k, v in pairs(genv) do
        if type(k) == "string" and k:sub(1, #HIDDEN_PREFIX) == HIDDEN_PREFIX then
            if not found and type(v) == "table" then
                found, foundKey = v, k
            else
                toDelete[#toDelete + 1] = k  -- дубликат / не-таблица
            end
        end
    end
    for _, k in ipairs(toDelete) do genv[k] = nil end
    if found then
        DataStore  = found
        HIDDEN_KEY = foundKey
    else
        DataStore = {}
    end
end
genv[HIDDEN_KEY] = DataStore

----------------------------------------------------------------
-- 3. DEFAULTS schema (полный, по всем v4/v5 ELITE модулям)
----------------------------------------------------------------
local DEFAULTS = {
    Version = CONFIG_VERSION,

    Aimbot = {
        Enabled          = false,
        Silent           = false,
        WallCheck        = true,
        PredictGravity   = false,
        RequireMouseDown = false,
        Backtrack        = false,
        TargetHysteresis = true,

        FOV                 = 120,
        Smoothing           = 3,
        Prediction          = 0.12,
        HitboxOffset        = 0,
        Sensitivity         = 1.0,
        HitChance           = 100,
        HumanizerStrength   = 0.4,
        BulletVelocity      = 0,
        MissOffset          = 4,
        MaxSilentPerSec     = 0,
        BacktrackTime       = 0.2,
        HysteresisMult      = 1.3,
        MinShotDelay        = 0,
        MaxFovDeltaPerFrame = 30,
    },

    ESP = {
        Enabled            = false,
        Boxes              = false,
        HealthBar          = false,
        Snaplines          = false,
        OnlyEnemies        = true,
        Chams              = false,
        ShowNames          = false,
        ShowDistance       = false,
        ShowHealth         = false,
        SnaplineFromBottom = true,
        ChamsOutline       = true,
        TeamColor          = true,

        MaxDistance              = 500,
        TextSize                 = 13,
        BoxThickness             = 1,
        ChamsFillTransparency    = 0.4,
        ChamsOutlineTransparency = 0.2,

        TextFont = "UI",
    },

    AntiAim = {
        Jitter               = false,
        Desync               = false,
        HideHead             = false,
        FakeLag              = false,
        FakeLagBackForth     = false,
        Visualizer           = false,
        ResolverBypass       = false,
        Predictor            = false,
        DesyncBufferTeleport = false,

        JitterMode    = "Sine",
        DesyncMode    = "Spin",
        HideHeadMode  = "Back",
        FakeLagMode   = "Static",

        JitterAngle      = 40,
        JitterSpeed      = 12,
        DesyncStrength   = 1.0,
        DesyncSpeed      = 30,
        HideHeadOffset   = 1.5,
        FakeLagIntensity = 5,
        FakeLagFrequency = 1,
        MicroJitterAngle = 0.05,
        PredictorAngle   = 15,
    },

    Fly = {
        Enabled              = false,
        AirControl           = true,
        VelocityPreservation = true,
        Speed                = 58,
    },

    SpeedHack = {
        Enabled = false,
        Speed   = 50,
    },

    HitboxExpander = {
        Enabled            = false,
        Size               = 12,
        TransparencyMode   = "Translucent",
        TransparencyValue  = 0.7,
    },

    Rage = {
        Spinbot   = false,
        SpinSpeed = 25,
        SpinMode  = "Yaw",
    },

    Movement = {
        BhopEnabled          = false,
        FlySmoothness        = 6,
        VelocityMultiplier   = 1,
        NoClipMode           = "Standard",
        InfJumpVelocityBoost = 0,
        InfJumpCooldown      = 0.22,
        VelocityCap          = 200,
    },

    InfJump = false,
    NoClip  = false,
}

----------------------------------------------------------------
-- 4. DeepMerge: рекурсивное слияние с типовой проверкой
----------------------------------------------------------------
-- DeepCopy/DeepMerge с защитой от циклических ссылок (seen-set)
local function DeepCopy(t, seen)
    if type(t) ~= "table" then return t end
    seen = seen or {}
    if seen[t] then return seen[t] end
    local out = {}
    seen[t] = out
    for k, v in pairs(t) do out[k] = DeepCopy(v, seen) end
    return out
end

local function DeepMerge(target, default, seen)
    if type(target) ~= "table" then return DeepCopy(default) end
    seen = seen or {}
    if seen[default] then return target end
    seen[default] = true
    for k, v in pairs(default) do
        local cur = target[k]
        if cur == nil then
            target[k] = (type(v) == "table") and DeepCopy(v) or v
        elseif type(v) == "table" then
            if type(cur) ~= "table" then
                target[k] = DeepCopy(v)
            else
                target[k] = DeepMerge(cur, v, seen)
            end
        elseif type(cur) ~= type(v) then
            target[k] = v
        end
    end
    return target
end

-- Migration по Version
if type(DataStore.Version) ~= "number" or DataStore.Version < CONFIG_VERSION then
    DataStore.Version = CONFIG_VERSION
end

DeepMerge(DataStore, DEFAULTS)

-- _G.Settings — alias на тот же DataStore (модули используют _G.Settings.X.Y)
_G.Settings = DataStore

----------------------------------------------------------------
-- 5. FastSafeLoad: устойчивая загрузка скриптов с диагностикой
----------------------------------------------------------------
local HTTP_HEADERS = {
    ["User-Agent"]    = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko)",
    ["Accept"]        = "text/plain, application/octet-stream, */*",
    ["Cache-Control"] = "no-cache",
}

local function HttpFetch(url)
    -- Универсальный шлюз: поддержка нескольких exec-API
    if syn and type(syn.request) == "function" then
        local resp = syn.request({ Url = url, Method = "GET", Headers = HTTP_HEADERS })
        if type(resp) == "table" then return resp.Body, resp.StatusCode end
    elseif type(http_request) == "function" then
        local resp = http_request({ Url = url, Method = "GET", Headers = HTTP_HEADERS })
        if type(resp) == "table" then return resp.Body, resp.StatusCode end
    elseif type(request) == "function" then
        local resp = request({ Url = url, Method = "GET", Headers = HTTP_HEADERS })
        if type(resp) == "table" then return resp.Body, resp.StatusCode end
    end
    -- Fallback: stock HttpGet (без headers)
    local ok, body = pcall(game.HttpGet, game, url, true)
    if ok then return body, 200 end
    return nil, 0
end

-- Расширенная проверка тела ответа: 4xx/5xx, HTML, rate-limit, login pages
local function IsValidScriptBody(body)
    if type(body) ~= "string" or #body < 4 then return false, "empty/short body" end
    local head = body:sub(1, 512):lower()

    -- HTML-страницы (login / error / GitHub auth)
    if head:find("<!doctype") or head:find("<html") or head:find("<title>") then
        return false, "HTML response"
    end
    -- 4xx
    if head:find("404") and head:find("not found")  then return false, "404 not found"  end
    if head:find("403") and head:find("forbidden")  then return false, "403 forbidden"  end
    if head:find("401") and head:find("unauthorized") then return false, "401 unauthorized" end
    if head:find("rate limit") or head:find("too many requests") then
        return false, "rate limited (429)"
    end
    -- 5xx
    if head:find("500") and head:find("internal server") then return false, "500 server error" end
    if head:find("502") and head:find("bad gateway")     then return false, "502 bad gateway"   end
    if head:find("503") and head:find("unavailable")     then return false, "503 unavailable"   end
    if head:find("504") and head:find("gateway timeout") then return false, "504 timeout"       end

    return true
end

-- Возвращает (true, returnedValue) либо (false, errorMsg).
-- Делит pcall: отдельно на компиляцию и на выполнение, чтобы точно
-- понимать стадию падения.
local function FastSafeLoad(name, url, attempts)
    if type(url) ~= "string" or url == "" then
        return false, "empty url"
    end
    attempts = math.max(tonumber(attempts) or 3, 1)

    local lastErr = "unknown"
    for i = 1, attempts do
        local body, status
        local fetchOk, fetchErr = pcall(function()
            body, status = HttpFetch(url)
        end)

        if not fetchOk then
            lastErr = "http: " .. tostring(fetchErr)
        elseif type(body) ~= "string" then
            lastErr = "non-string response (status=" .. tostring(status) .. ")"
        elseif status and status >= 400 then
            lastErr = "http " .. tostring(status)
        else
            local valid, why = IsValidScriptBody(body)
            if not valid then
                lastErr = why
            else
                local fn, compileErr = loadstring(body, "=" .. tostring(name))
                if not fn then
                    lastErr = "compile: " .. tostring(compileErr)
                else
                    local execOk, modOrErr = pcall(fn)
                    if execOk then
                        return true, modOrErr
                    end
                    lastErr = "exec: " .. tostring(modOrErr)
                end
            end
        end

        if i < attempts then task.wait(0.15 * i) end
    end
    return false, lastErr
end

----------------------------------------------------------------
-- 6. Rayfield loader (использует FastSafeLoad)
----------------------------------------------------------------
local Rayfield
local RAYFIELD_URLS = {
    "https://sirius.menu/rayfield",
    "https://raw.githubusercontent.com/SiriusSoftwareLtd/Rayfield/main/source.lua",
}

for _, u in ipairs(RAYFIELD_URLS) do
    local ok, mod = FastSafeLoad("Rayfield", u, 2)
    if ok and type(mod) == "table" and type(mod.CreateWindow) == "function" then
        Rayfield = mod
        break
    end
end

if not Rayfield then
    -- Иногда getgenv().Rayfield_InterfaceBuild мешает повторной загрузке
    if type(getgenv) == "function" then
        local g = getgenv()
        if g.Rayfield_InterfaceBuild then g.Rayfield_InterfaceBuild = nil end
    end
    for _, u in ipairs(RAYFIELD_URLS) do
        local ok, mod = FastSafeLoad("Rayfield", u, 2)
        if ok and type(mod) == "table" and type(mod.CreateWindow) == "function" then
            Rayfield = mod; break
        end
    end
end

if not Rayfield then
    warn("[ABYSS] Rayfield не загрузился — abort"); return
end

-- Маскировка имени Rayfield-интерфейса (рандомизация)
do
    local n = "x" .. string.char(math.random(65, 90)) .. string.char(math.random(65, 90))
                  .. string.char(math.random(65, 90)) .. tostring(math.random(1000, 9999))
    pcall(function() Rayfield.Interface.Name = n end)
end

----------------------------------------------------------------
-- 7. Window + рандомизированное имя конфига (стабильно per-UserId)
----------------------------------------------------------------
local function GenConfigFileName()
    local uid = LocalPlayer and LocalPlayer.UserId or 0
    if uid <= 0 then
        -- Guest fallback: стабильный per-session salt в getgenv
        local saltKey = "__ABYSS_SALT__"
        if type(genv[saltKey]) ~= "number" then
            genv[saltKey] = math.random(0x100000, 0xFFFFFF)
        end
        uid = genv[saltKey]
    end
    return string.format("ABYSS_%X", math.abs(uid) % 0xFFFFFFFF)
end

local Window = Rayfield:CreateWindow({
    Name            = "ABYSS ARCHON • MODULAR",
    LoadingTitle    = "ABYSS ARCHON v" .. tostring(CONFIG_VERSION),
    LoadingSubtitle = "Professional Modular Edition",
    Theme           = "DarkBlue",
    ToggleUIKeybind = Enum.KeyCode.RightShift,
    ConfigurationSaving = {
        Enabled    = true,
        FolderName = "AbyssUniversal",
        FileName   = GenConfigFileName(),
    },
})

----------------------------------------------------------------
-- 8. UI: Combat (Aimbot v5)
----------------------------------------------------------------
local SA = DataStore.Aimbot
local SE = DataStore.ESP

local Tab_Combat = Window:CreateTab("Бой", "crosshair")

Tab_Combat:CreateSection("Аимбот")
Tab_Combat:CreateToggle({ Name = "Aimbot (Visible)", CurrentValue = SA.Enabled,
    Flag = "AB_Enabled", Callback = function(v) SA.Enabled = v end })
Tab_Combat:CreateToggle({ Name = "Silent Aim", CurrentValue = SA.Silent,
    Flag = "AB_Silent", Callback = function(v) SA.Silent = v end })
Tab_Combat:CreateToggle({ Name = "Require Mouse Down", CurrentValue = SA.RequireMouseDown,
    Flag = "AB_RMD", Callback = function(v) SA.RequireMouseDown = v end })

Tab_Combat:CreateSection("Настройка прицеливания")
Tab_Combat:CreateSlider({ Name = "FOV", Range = {10, 600}, Increment = 10,
    CurrentValue = SA.FOV, Flag = "AB_FOV",
    Callback = function(v) SA.FOV = v end })
Tab_Combat:CreateSlider({ Name = "Smoothing", Range = {1, 20}, Increment = 1,
    CurrentValue = SA.Smoothing, Flag = "AB_Smooth",
    Callback = function(v) SA.Smoothing = v end })
Tab_Combat:CreateSlider({ Name = "Sensitivity", Range = {0.1, 3}, Increment = 0.05, Suffix = "x",
    CurrentValue = SA.Sensitivity, Flag = "AB_Sens",
    Callback = function(v) SA.Sensitivity = v end })
Tab_Combat:CreateSlider({ Name = "Prediction", Range = {0, 0.5}, Increment = 0.01,
    CurrentValue = SA.Prediction, Flag = "AB_Pred",
    Callback = function(v) SA.Prediction = v end })
Tab_Combat:CreateSlider({ Name = "Hitbox Offset (Y)", Range = {-3, 3}, Increment = 0.1,
    CurrentValue = SA.HitboxOffset, Flag = "AB_Off",
    Callback = function(v) SA.HitboxOffset = v end })
Tab_Combat:CreateSlider({ Name = "Max FOV Δ / frame (deg)", Range = {0, 180}, Increment = 5,
    CurrentValue = SA.MaxFovDeltaPerFrame, Flag = "AB_MaxFovD",
    Callback = function(v) SA.MaxFovDeltaPerFrame = v end })

Tab_Combat:CreateSection("Фильтры / Wallcheck")
Tab_Combat:CreateToggle({ Name = "Wall Check", CurrentValue = SA.WallCheck,
    Flag = "AB_WC", Callback = function(v) SA.WallCheck = v end })
Tab_Combat:CreateToggle({ Name = "Only Enemies", CurrentValue = SE.OnlyEnemies,
    Flag = "AB_OE", Callback = function(v) SE.OnlyEnemies = v end })
Tab_Combat:CreateToggle({ Name = "Predict Gravity", CurrentValue = SA.PredictGravity,
    Flag = "AB_Grav", Callback = function(v) SA.PredictGravity = v end })
Tab_Combat:CreateSlider({ Name = "Bullet Velocity (0=instant)", Range = {0, 1500}, Increment = 25,
    CurrentValue = SA.BulletVelocity, Flag = "AB_BV",
    Callback = function(v) SA.BulletVelocity = v end })

Tab_Combat:CreateSection("Humanizer / Smart Miss")
Tab_Combat:CreateSlider({ Name = "Hit Chance %", Range = {1, 100}, Increment = 1,
    CurrentValue = SA.HitChance, Flag = "AB_HC",
    Callback = function(v) SA.HitChance = v end })
Tab_Combat:CreateSlider({ Name = "Humanizer Strength", Range = {0, 1}, Increment = 0.05,
    CurrentValue = SA.HumanizerStrength, Flag = "AB_HS",
    Callback = function(v) SA.HumanizerStrength = v end })
Tab_Combat:CreateSlider({ Name = "Miss Offset (studs)", Range = {0, 12}, Increment = 0.5,
    CurrentValue = SA.MissOffset, Flag = "AB_MO",
    Callback = function(v) SA.MissOffset = v end })
Tab_Combat:CreateSlider({ Name = "Max Silent /sec (0=off)", Range = {0, 30}, Increment = 1,
    CurrentValue = SA.MaxSilentPerSec, Flag = "AB_RL",
    Callback = function(v) SA.MaxSilentPerSec = v end })
Tab_Combat:CreateSlider({ Name = "Min Shot Delay (s)", Range = {0, 1}, Increment = 0.01,
    CurrentValue = SA.MinShotDelay, Flag = "AB_MSD",
    Callback = function(v) SA.MinShotDelay = v end })

Tab_Combat:CreateSection("Smart Targeting (v5)")
Tab_Combat:CreateToggle({ Name = "Backtrack", CurrentValue = SA.Backtrack,
    Flag = "AB_BT", Callback = function(v) SA.Backtrack = v end })
Tab_Combat:CreateSlider({ Name = "Backtrack Time (s)", Range = {0.05, 1}, Increment = 0.05,
    CurrentValue = SA.BacktrackTime, Flag = "AB_BTT",
    Callback = function(v) SA.BacktrackTime = v end })
Tab_Combat:CreateToggle({ Name = "Target Hysteresis", CurrentValue = SA.TargetHysteresis,
    Flag = "AB_TH", Callback = function(v) SA.TargetHysteresis = v end })
Tab_Combat:CreateSlider({ Name = "Hysteresis Multiplier", Range = {1, 2.5}, Increment = 0.1,
    CurrentValue = SA.HysteresisMult, Flag = "AB_HM",
    Callback = function(v) SA.HysteresisMult = v end })

----------------------------------------------------------------
-- 9. UI: Visuals (ESP v4)
----------------------------------------------------------------
local Tab_Visuals = Window:CreateTab("Визуал", "eye")

Tab_Visuals:CreateSection("ESP")
Tab_Visuals:CreateToggle({ Name = "Enable ESP", CurrentValue = SE.Enabled,
    Flag = "ESP_On", Callback = function(v) SE.Enabled = v end })
Tab_Visuals:CreateToggle({ Name = "Box ESP", CurrentValue = SE.Boxes,
    Flag = "ESP_Box", Callback = function(v) SE.Boxes = v end })
Tab_Visuals:CreateToggle({ Name = "Health Bar", CurrentValue = SE.HealthBar,
    Flag = "ESP_HP", Callback = function(v) SE.HealthBar = v end })
Tab_Visuals:CreateToggle({ Name = "Snaplines", CurrentValue = SE.Snaplines,
    Flag = "ESP_SL", Callback = function(v) SE.Snaplines = v end })
Tab_Visuals:CreateToggle({ Name = "Chams (Highlight)", CurrentValue = SE.Chams,
    Flag = "ESP_Cham", Callback = function(v) SE.Chams = v end })

Tab_Visuals:CreateSection("Текстовые метки")
Tab_Visuals:CreateToggle({ Name = "Show Names", CurrentValue = SE.ShowNames,
    Flag = "ESP_Name", Callback = function(v) SE.ShowNames = v end })
Tab_Visuals:CreateToggle({ Name = "Show Distance", CurrentValue = SE.ShowDistance,
    Flag = "ESP_Dist", Callback = function(v) SE.ShowDistance = v end })
Tab_Visuals:CreateToggle({ Name = "Show Health", CurrentValue = SE.ShowHealth,
    Flag = "ESP_HPT", Callback = function(v) SE.ShowHealth = v end })
Tab_Visuals:CreateSlider({ Name = "Text Size", Range = {10, 24}, Increment = 1,
    CurrentValue = SE.TextSize, Flag = "ESP_TS",
    Callback = function(v) SE.TextSize = v end })
Tab_Visuals:CreateDropdown({ Name = "Text Font",
    Options = { "UI", "System", "Plex", "Monospace" },
    CurrentOption = { SE.TextFont }, Flag = "ESP_TF",
    Callback = function(o) SE.TextFont = o[1] end })

Tab_Visuals:CreateSection("Параметры")
Tab_Visuals:CreateSlider({ Name = "Max Distance", Range = {50, 2000}, Increment = 50,
    CurrentValue = SE.MaxDistance, Flag = "ESP_MD",
    Callback = function(v) SE.MaxDistance = v end })
Tab_Visuals:CreateSlider({ Name = "Box Thickness", Range = {1, 4}, Increment = 1,
    CurrentValue = SE.BoxThickness, Flag = "ESP_BT",
    Callback = function(v) SE.BoxThickness = v end })
Tab_Visuals:CreateToggle({ Name = "Snapline From Bottom", CurrentValue = SE.SnaplineFromBottom,
    Flag = "ESP_SLB", Callback = function(v) SE.SnaplineFromBottom = v end })
Tab_Visuals:CreateToggle({ Name = "Team Color", CurrentValue = SE.TeamColor,
    Flag = "ESP_Team", Callback = function(v) SE.TeamColor = v end })

Tab_Visuals:CreateSection("Chams")
Tab_Visuals:CreateToggle({ Name = "Chams Outline", CurrentValue = SE.ChamsOutline,
    Flag = "Cham_OL", Callback = function(v) SE.ChamsOutline = v end })
Tab_Visuals:CreateSlider({ Name = "Fill Transparency", Range = {0, 1}, Increment = 0.05,
    CurrentValue = SE.ChamsFillTransparency, Flag = "Cham_FT",
    Callback = function(v) SE.ChamsFillTransparency = v end })
Tab_Visuals:CreateSlider({ Name = "Outline Transparency", Range = {0, 1}, Increment = 0.05,
    CurrentValue = SE.ChamsOutlineTransparency, Flag = "Cham_OT",
    Callback = function(v) SE.ChamsOutlineTransparency = v end })

----------------------------------------------------------------
-- 10. UI: AntiAim (v4 ELITE)
----------------------------------------------------------------
local SAA = DataStore.AntiAim
local Tab_AA = Window:CreateTab("Anti-Aim", "shield")

Tab_AA:CreateSection("Jitter")
Tab_AA:CreateToggle({ Name = "Jitter", CurrentValue = SAA.Jitter,
    Flag = "AA_Jit", Callback = function(v) SAA.Jitter = v end })
Tab_AA:CreateDropdown({ Name = "Jitter Mode",
    Options = { "Sine", "RandomWalk", "Flick", "Static", "CustomPattern" },
    CurrentOption = { SAA.JitterMode }, Flag = "AA_JitM",
    Callback = function(o) SAA.JitterMode = o[1] end })
Tab_AA:CreateSlider({ Name = "Jitter Angle (deg)", Range = {5, 180}, Increment = 5,
    CurrentValue = SAA.JitterAngle, Flag = "AA_JitA",
    Callback = function(v) SAA.JitterAngle = v end })
Tab_AA:CreateSlider({ Name = "Jitter Speed", Range = {1, 60}, Increment = 1,
    CurrentValue = SAA.JitterSpeed, Flag = "AA_JitS",
    Callback = function(v) SAA.JitterSpeed = v end })

Tab_AA:CreateSection("Desync")
Tab_AA:CreateToggle({ Name = "Desync (RootJoint+Waist)", CurrentValue = SAA.Desync,
    Flag = "AA_Des", Callback = function(v) SAA.Desync = v end })
Tab_AA:CreateDropdown({ Name = "Desync Mode",
    Options = { "Static", "Spin", "Random", "Switch", "Backwards" },
    CurrentOption = { SAA.DesyncMode }, Flag = "AA_DesM",
    Callback = function(o) SAA.DesyncMode = o[1] end })
Tab_AA:CreateSlider({ Name = "Desync Strength", Range = {0, 1}, Increment = 0.05,
    CurrentValue = SAA.DesyncStrength, Flag = "AA_DesStr",
    Callback = function(v) SAA.DesyncStrength = v end })
Tab_AA:CreateSlider({ Name = "Desync Speed", Range = {1, 200}, Increment = 5,
    CurrentValue = SAA.DesyncSpeed, Flag = "AA_DesSp",
    Callback = function(v) SAA.DesyncSpeed = v end })
Tab_AA:CreateToggle({ Name = "Buffered CFrame Teleport", CurrentValue = SAA.DesyncBufferTeleport,
    Flag = "AA_BufT", Callback = function(v) SAA.DesyncBufferTeleport = v end })

Tab_AA:CreateSection("Hide Head")
Tab_AA:CreateToggle({ Name = "Hide Head", CurrentValue = SAA.HideHead,
    Flag = "AA_HH", Callback = function(v) SAA.HideHead = v end })
Tab_AA:CreateDropdown({ Name = "Hide Head Mode",
    Options = { "Back", "Down", "Offset", "Spin" },
    CurrentOption = { SAA.HideHeadMode }, Flag = "AA_HHM",
    Callback = function(o) SAA.HideHeadMode = o[1] end })
Tab_AA:CreateSlider({ Name = "Hide Head Offset", Range = {0, 5}, Increment = 0.1,
    CurrentValue = SAA.HideHeadOffset, Flag = "AA_HHO",
    Callback = function(v) SAA.HideHeadOffset = v end })

Tab_AA:CreateSection("Fake Lag (no Anchor)")
Tab_AA:CreateToggle({ Name = "Fake Lag", CurrentValue = SAA.FakeLag,
    Flag = "AA_FL", Callback = function(v) SAA.FakeLag = v end })
Tab_AA:CreateDropdown({ Name = "Fake Lag Mode",
    Options = { "Static", "Random", "Adaptive", "Switch" },
    CurrentOption = { SAA.FakeLagMode }, Flag = "AA_FLM",
    Callback = function(o) SAA.FakeLagMode = o[1] end })
Tab_AA:CreateSlider({ Name = "Lag Intensity (frames)", Range = {1, 20}, Increment = 1,
    CurrentValue = SAA.FakeLagIntensity, Flag = "AA_FLI",
    Callback = function(v) SAA.FakeLagIntensity = v end })
Tab_AA:CreateSlider({ Name = "Lag Frequency (Hz)", Range = {0.2, 8}, Increment = 0.1,
    CurrentValue = SAA.FakeLagFrequency, Flag = "AA_FLF",
    Callback = function(v) SAA.FakeLagFrequency = v end })
Tab_AA:CreateToggle({ Name = "Lag BackForth (snap-back)", CurrentValue = SAA.FakeLagBackForth,
    Flag = "AA_FLB", Callback = function(v) SAA.FakeLagBackForth = v end })

Tab_AA:CreateSection("Misc / Visualizer")
Tab_AA:CreateToggle({ Name = "Visualizer (real vs fake)", CurrentValue = SAA.Visualizer,
    Flag = "AA_Vis", Callback = function(v) SAA.Visualizer = v end })
Tab_AA:CreateToggle({ Name = "Resolver Bypass (micro-jitter)", CurrentValue = SAA.ResolverBypass,
    Flag = "AA_RB", Callback = function(v) SAA.ResolverBypass = v end })
Tab_AA:CreateSlider({ Name = "Micro Jitter (rad)", Range = {0, 0.3}, Increment = 0.01,
    CurrentValue = SAA.MicroJitterAngle, Flag = "AA_MJ",
    Callback = function(v) SAA.MicroJitterAngle = v end })
Tab_AA:CreateToggle({ Name = "Predictor (move-bias)", CurrentValue = SAA.Predictor,
    Flag = "AA_Pred", Callback = function(v) SAA.Predictor = v end })
Tab_AA:CreateSlider({ Name = "Predictor Angle (deg)", Range = {0, 45}, Increment = 1,
    CurrentValue = SAA.PredictorAngle, Flag = "AA_PA",
    Callback = function(v) SAA.PredictorAngle = v end })

----------------------------------------------------------------
-- 11. UI: Movement (v4 ELITE)
----------------------------------------------------------------
local SF  = DataStore.Fly
local SSH = DataStore.SpeedHack
local SHX = DataStore.HitboxExpander
local SM  = DataStore.Movement

local Tab_Mov = Window:CreateTab("Движение", "zap")

Tab_Mov:CreateSection("SpeedHack")
Tab_Mov:CreateToggle({ Name = "SpeedHack", CurrentValue = SSH.Enabled,
    Flag = "SH_On", Callback = function(v) SSH.Enabled = v end })
Tab_Mov:CreateSlider({ Name = "Walk Speed", Range = {16, 200}, Increment = 2,
    CurrentValue = SSH.Speed, Flag = "SH_Spd",
    Callback = function(v) SSH.Speed = v end })
Tab_Mov:CreateButton({ Name = "Preset x2 (32)",
    Callback = function() SSH.Enabled = true; SSH.Speed = 32 end })
Tab_Mov:CreateButton({ Name = "Preset x3 (48)",
    Callback = function() SSH.Enabled = true; SSH.Speed = 48 end })
Tab_Mov:CreateButton({ Name = "Preset x5 (80)",
    Callback = function() SSH.Enabled = true; SSH.Speed = 80 end })
Tab_Mov:CreateSlider({ Name = "Velocity Multiplier", Range = {1, 4}, Increment = 0.1, Suffix = "x",
    CurrentValue = SM.VelocityMultiplier, Flag = "M_VM",
    Callback = function(v) SM.VelocityMultiplier = v end })
Tab_Mov:CreateSlider({ Name = "Velocity Cap", Range = {50, 500}, Increment = 10,
    CurrentValue = SM.VelocityCap, Flag = "M_VC",
    Callback = function(v) SM.VelocityCap = v end })

Tab_Mov:CreateSection("Fly")
Tab_Mov:CreateToggle({ Name = "Fly", CurrentValue = SF.Enabled,
    Flag = "Fly_On", Callback = function(v) SF.Enabled = v end })
Tab_Mov:CreateSlider({ Name = "Fly Speed", Range = {30, 250}, Increment = 5,
    CurrentValue = SF.Speed, Flag = "Fly_Spd",
    Callback = function(v) SF.Speed = v end })
Tab_Mov:CreateSlider({ Name = "Fly Smoothness", Range = {1, 20}, Increment = 1,
    CurrentValue = SM.FlySmoothness, Flag = "Fly_Sm",
    Callback = function(v) SM.FlySmoothness = v end })
Tab_Mov:CreateToggle({ Name = "Air Control (smooth accel)", CurrentValue = SF.AirControl,
    Flag = "Fly_AC", Callback = function(v) SF.AirControl = v end })
Tab_Mov:CreateToggle({ Name = "Velocity Preservation", CurrentValue = SF.VelocityPreservation,
    Flag = "Fly_VP", Callback = function(v) SF.VelocityPreservation = v end })

Tab_Mov:CreateSection("NoClip / InfJump / Bhop")
Tab_Mov:CreateToggle({ Name = "NoClip", CurrentValue = DataStore.NoClip,
    Flag = "NC_On", Callback = function(v) DataStore.NoClip = v end })
Tab_Mov:CreateDropdown({ Name = "NoClip Mode",
    Options = { "Standard", "Advanced" },
    CurrentOption = { SM.NoClipMode }, Flag = "NC_M",
    Callback = function(o) SM.NoClipMode = o[1] end })
Tab_Mov:CreateToggle({ Name = "Infinite Jump", CurrentValue = DataStore.InfJump,
    Flag = "IJ_On", Callback = function(v) DataStore.InfJump = v end })
Tab_Mov:CreateSlider({ Name = "InfJump Velocity Boost", Range = {0, 100}, Increment = 5,
    CurrentValue = SM.InfJumpVelocityBoost, Flag = "IJ_VB",
    Callback = function(v) SM.InfJumpVelocityBoost = v end })
Tab_Mov:CreateSlider({ Name = "InfJump Cooldown (s)", Range = {0.05, 1}, Increment = 0.05,
    CurrentValue = SM.InfJumpCooldown, Flag = "IJ_CD",
    Callback = function(v) SM.InfJumpCooldown = v end })
Tab_Mov:CreateToggle({ Name = "Bhop (auto-jump)", CurrentValue = SM.BhopEnabled,
    Flag = "BH_On", Callback = function(v) SM.BhopEnabled = v end })

Tab_Mov:CreateSection("Hitbox Expander")
Tab_Mov:CreateToggle({ Name = "Hitbox Expander", CurrentValue = SHX.Enabled,
    Flag = "HX_On", Callback = function(v) SHX.Enabled = v end })
Tab_Mov:CreateSlider({ Name = "Hitbox Size", Range = {3, 30}, Increment = 1,
    CurrentValue = SHX.Size, Flag = "HX_Sz",
    Callback = function(v) SHX.Size = v end })
Tab_Mov:CreateDropdown({ Name = "Transparency Mode",
    Options = { "Invisible", "Translucent", "Opaque" },
    CurrentOption = { SHX.TransparencyMode }, Flag = "HX_TM",
    Callback = function(o) SHX.TransparencyMode = o[1] end })
Tab_Mov:CreateSlider({ Name = "Translucent Value", Range = {0, 1}, Increment = 0.05,
    CurrentValue = SHX.TransparencyValue, Flag = "HX_TV",
    Callback = function(v) SHX.TransparencyValue = v end })

----------------------------------------------------------------
-- 12. UI: Rage (Spinbot)
----------------------------------------------------------------
local SR = DataStore.Rage
local Tab_Rage = Window:CreateTab("Rage", "sword")

Tab_Rage:CreateSection("Spinbot")
Tab_Rage:CreateToggle({ Name = "Spinbot", CurrentValue = SR.Spinbot,
    Flag = "RG_On", Callback = function(v) SR.Spinbot = v end })
Tab_Rage:CreateDropdown({ Name = "Spin Mode",
    Options = { "Yaw", "Pitch", "Roll", "Random" },
    CurrentOption = { SR.SpinMode }, Flag = "RG_M",
    Callback = function(o) SR.SpinMode = o[1] end })
Tab_Rage:CreateSlider({ Name = "Spin Speed", Range = {1, 360}, Increment = 5,
    CurrentValue = SR.SpinSpeed, Flag = "RG_Sp",
    Callback = function(v) SR.SpinSpeed = v end })

----------------------------------------------------------------
-- 13. UI: Misc (Reset / Unload)
----------------------------------------------------------------
local Tab_Misc = Window:CreateTab("Misc", "sliders")

Tab_Misc:CreateSection("Управление")
Tab_Misc:CreateButton({ Name = "Reset to defaults",
    Callback = function()
        for k in pairs(DataStore) do DataStore[k] = nil end
        DeepMerge(DataStore, DEFAULTS)
        Rayfield:Notify({ Title = "ABYSS", Content = "Defaults restored. Перезагрузите чит.", Duration = 6 })
    end })

Tab_Misc:CreateButton({ Name = "Unload (Disconnect All)",
    Callback = function()
        if _G.ABYSS_Main and type(_G.ABYSS_Main.Disconnect) == "function" then
            pcall(_G.ABYSS_Main.Disconnect)
        end
    end })

-- HIDDEN_KEY НЕ выводим в UI (детект-вектор)
Tab_Misc:CreateLabel("Config version: " .. tostring(CONFIG_VERSION))

----------------------------------------------------------------
-- 14. Module loading via task.spawn (parallel, with timeout) +
--     Config Application AFTER all modules ready.
----------------------------------------------------------------
-- BASE_URL split: фрагментация литерала снижает сигнатуру при byte-grep
-- античитом по исходнику. Не криптография, но защита от тривиального scan.
local BASE_URL = ("https://")
              .. ("raw.github") .. ("usercontent.com/")
              .. ("oleg") .. ("6785999-lang/")
              .. ("MyPrivate") .. ("Abyss/main/")

local MODULES = {
    { name = "Aimbot",   url = BASE_URL .. "Aimbot.lua"   },
    { name = "Visuals",  url = BASE_URL .. "Visuals.lua"  },
    { name = "Movement", url = BASE_URL .. "Movement.lua" },
    { name = "AntiAim",  url = BASE_URL .. "AntiAim.lua"  },
}

local results       = {}
local totalCount    = #MODULES
local LOAD_TIMEOUT  = 12  -- секунд

-- Атомарный счётчик: считаем по уникальным ключам в results,
-- т.к. инкремент локальной переменной из coroutine не атомарен
-- между точками yield (HTTP fetch).
local function countDone()
    local n = 0
    for _ in pairs(results) do n = n + 1 end
    return n
end

for _, m in ipairs(MODULES) do
    task.spawn(function()
        local ok, errOrMod = FastSafeLoad(m.name, m.url, 4)
        results[m.name] = { ok = ok, msg = errOrMod }
        if ok then
            print("[ABYSS] " .. m.name .. " loaded OK")
        else
            warn("[ABYSS] " .. m.name .. " FAILED: " .. tostring(errOrMod))
        end
    end)
end

local startT = os.clock()
while countDone() < totalCount and (os.clock() - startT) < LOAD_TIMEOUT do
    task.wait(0.05)
end

local successCount = 0
local failedNames  = {}
for _, m in ipairs(MODULES) do
    local r = results[m.name]
    if r and r.ok then
        successCount = successCount + 1
    else
        table.insert(failedNames, m.name)
    end
end

----------------------------------------------------------------
-- 15. Config Application — ТОЛЬКО после загрузки модулей.
--     Это критично: callbacks слайдеров мутируют DataStore,
--     модули читают актуальные значения на следующем frame.
----------------------------------------------------------------
local cfgOk, cfgErr = pcall(function() Window:LoadConfiguration() end)
if not cfgOk then
    warn("[ABYSS] LoadConfiguration error: " .. tostring(cfgErr))
end

-- Post-load sanity merge: если LoadConfiguration снёс новые ключи (миграция
-- старого конфига), восстанавливаем их из DEFAULTS. Это гарантирует, что
-- модули не упадут на nil-индексации (например, SA.Backtrack).
DeepMerge(DataStore, DEFAULTS)

----------------------------------------------------------------
-- 16. Notify
----------------------------------------------------------------
do
    local title, content
    if successCount == totalCount then
        title   = "ABYSS ARCHON"
        content = string.format("v%d ELITE LOADED — %d/%d modules", CONFIG_VERSION, successCount, totalCount)
    else
        title   = "ABYSS ARCHON (partial)"
        content = string.format("Loaded %d/%d. Failed: %s", successCount, totalCount, table.concat(failedNames, ", "))
    end
    Rayfield:Notify({ Title = title, Content = content, Duration = 6 })
end

----------------------------------------------------------------
-- 17. Master Disconnect API
----------------------------------------------------------------
-- Динамический список ключей: автоматически расширяется при добавлении модулей
local MODULE_KEYS = {}
for _, m in ipairs(MODULES) do
    MODULE_KEYS[#MODULE_KEYS + 1] = "ABYSS_" .. m.name
end

local function MasterDisconnect()
    for _, key in ipairs(MODULE_KEYS) do
        local mod = _G[key]
        if mod and type(mod.Disconnect) == "function" then
            pcall(mod.Disconnect)
        end
        _G[key] = nil
    end
    pcall(function() if Window and Window.Destroy then Window:Destroy() end end)
    -- Hidden namespace оставляем (для возможного reinject); _G.Settings очищаем
    _G.Settings = nil
    _G.ABYSS_Main = nil
end

_G.ABYSS_Main = {
    Disconnect = MasterDisconnect,
    Settings   = DataStore,
    Window     = Window,
    Rayfield   = Rayfield,
    GetCamera  = GetCamera,
    Version    = CONFIG_VERSION,
    HiddenKey  = HIDDEN_KEY,
}

print(string.format("[ABYSS] Main v%d loaded — %d/%d modules ready", CONFIG_VERSION, successCount, totalCount))
