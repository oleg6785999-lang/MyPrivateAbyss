local UIAdapter = require(script.Parent.uiadapter)
local RayfieldAdapter = require(script.Parent.rayfieldadapter)

local UIManager = {}
UIManager.__index = UIManager

function UIManager.new()
    return setmetatable({
        adapter = nil,
        cfgService = nil,    -- canonical access (no stale ref)
        events = nil,
        loaded = false
    }, UIManager)
end

function UIManager:Init(di, events)
    self.events = events
    self.cfgService = di:resolve("ConfigService")
    self.adapter = RayfieldAdapter.new()
end

function UIManager:Start()
    if self.loaded then return end
    local lib = self:fetchLibrary()
    if not lib then return end
    self.adapter:init(lib)
    self:build()
    self.adapter:loadConfig()
    self.adapter:notify({Title = "ARCHON", Content = "UI ONLINE", Duration = 3})
    self.loaded = true
end

function UIManager:Update(dt) end
function UIManager:Stop() end

function UIManager:Destroy()
    if self.adapter then self.adapter:destroy() end
    self.adapter = nil
    self.cfgService = nil
    self.events = nil
    self.loaded = false
end

function UIManager:validateSource(src)
    if type(src) ~= "string" or #src < 100 or #src > 600000 then return false end
    if src:find("getgenv%(") or src:find("setfenv%(") then return false end
    local ok = pcall(function() loadstring(src) end)
    return ok
end

function UIManager:fetchLibrary()
    local urls = {
        "https://sirius.menu/rayfield",
        "https://raw.githubusercontent.com/SiriusSoftwareLtd/Rayfield/main/source.lua"
    }
    for _, url in ipairs(urls) do
        local ok, res = pcall(function()
            local src = game:HttpGet(url, true)
            if not self:validateSource(src) then return nil end
            local fn = loadstring(src)
            if not fn then return nil end
            return fn()
        end)
        if ok and typeof(res) == "table" and res.CreateWindow then return res end
    end
    return nil
end

----------------------------------------------------------------
-- Path helpers (read/write canonical config via ConfigService)
----------------------------------------------------------------
function UIManager:_split(path)
    local keys = {}
    for k in string.gmatch(path, "[^.]+") do keys[#keys+1] = k end
    return keys
end

function UIManager:_getCurrent(path)
    local cfg = self.cfgService:get()
    local node = cfg
    for k in string.gmatch(path, "[^.]+") do
        if type(node) ~= "table" then return nil end
        node = node[k]
    end
    return node
end

function UIManager:_setCurrent(path, val)
    local cfg = self.cfgService:get()
    local keys = self:_split(path)
    local node = cfg
    for i = 1, #keys - 1 do
        node = node[keys[i]]
        if type(node) ~= "table" then return false end
    end
    local prev = node[keys[#keys]]
    node[keys[#keys]] = val
    if self.events then self.events:publish("ConfigChanged", path, prev, val) end
    return true
end

function UIManager:bindToggle(tab, path, name)
    self.adapter:createToggle(tab, {
        Name = name, CurrentValue = self:_getCurrent(path),
        Callback = function(v) self:_setCurrent(path, v) end
    })
end

function UIManager:bindSlider(tab, path, name, range, inc)
    self.adapter:createSlider(tab, {
        Name = name, Range = range, Increment = inc,
        CurrentValue = self:_getCurrent(path),
        Callback = function(v) self:_setCurrent(path, v) end
    })
end

function UIManager:bindDropdown(tab, path, name, options)
    self.adapter:createDropdown(tab, {
        Name = name, Options = options,
        CurrentOption = {self:_getCurrent(path)},
        Callback = function(o) self:_setCurrent(path, o[1]) end
    })
end

function UIManager:build()
    local win = self.adapter:createWindow({
        Name = "ARCHON CORE",
        LoadingTitle = "INITIALIZING",
        Theme = "DarkBlue",
        ToggleUIKeybind = Enum.KeyCode.RightShift,
        ConfigurationSaving = {Enabled = true, FolderName = "ArchonCore", FileName = "Config"}
    })
    if not win then return end

    -- Combat
    local combat = self.adapter:createTab(win, "Combat", "crosshair")
    self:bindToggle(combat, "Aimbot.Enabled",     "Aimbot")
    self:bindToggle(combat, "Aimbot.Silent",      "Silent Aim")
    self:bindToggle(combat, "Aimbot.RageMode",    "Rage Mode (snap)")
    self:bindSlider(combat, "Aimbot.FOV",         "FOV",         {10, 600}, 5)
    self:bindSlider(combat, "Aimbot.Smoothing",   "Smoothing",   {1, 20}, 1)
    self:bindSlider(combat, "Aimbot.Prediction",  "Prediction",  {0, 0.5}, 0.01)
    self:bindSlider(combat, "Aimbot.BulletVel",   "Bullet Velocity (0 = hitscan)", {0, 5000}, 50)
    self:bindToggle(combat, "Aimbot.WallCheck",   "Wall Check")
    self:bindToggle(combat, "Aimbot.MultiRay",    "Multi-Ray")
    self:bindToggle(combat, "Aimbot.Backtrack",   "Backtrack")
    self:bindToggle(combat, "Aimbot.UseResolver", "Resolver")
    self:bindToggle(combat, "Aimbot.UsePing",     "Ping Compensation")
    self:bindToggle(combat, "Aimbot.UseAccel",    "Accel Prediction")
    self:bindDropdown(combat, "Aimbot.TargetMode", "Target Mode", {"Score", "Distance"})
    self:bindToggle(combat, "Aimbot.Hysteresis",  "Target Hysteresis")

    -- Silent Aim
    self:bindSlider(combat, "SilentAim.HitChance",      "HitChance %",       {0, 100}, 5)
    self:bindSlider(combat, "SilentAim.MissOffset",     "Miss Offset",       {0, 20}, 1)
    self:bindSlider(combat, "SilentAim.Humanizer",      "Humanizer",         {0, 1}, 0.05)
    self:bindSlider(combat, "SilentAim.MaxPerSec",      "Max Shots/sec",     {0, 30}, 1)
    self:bindSlider(combat, "SilentAim.MinDelay",       "Min Shot Delay",    {0, 1}, 0.05)
    self:bindToggle(combat, "SilentAim.Burst",          "Burst Mode")
    self:bindSlider(combat, "SilentAim.OriginRange",    "Origin Range",      {25, 200}, 5)
    self:bindToggle(combat, "SilentAim.AutoOriginRange","Auto Origin Range")
    self:bindToggle(combat, "SilentAim.RequireMouseDown","Require Mouse Down")

    -- Visuals
    local visuals = self.adapter:createTab(win, "Visuals", "eye")
    self:bindToggle(visuals, "ESP.Enabled",       "ESP")
    self:bindToggle(visuals, "ESP.Boxes",         "Boxes")
    self:bindToggle(visuals, "ESP.HealthBar",     "Health Bar")
    self:bindToggle(visuals, "ESP.Snaplines",     "Snaplines")
    self:bindToggle(visuals, "ESP.Chams",         "Chams")
    self:bindToggle(visuals, "ESP.ShowNames",     "Names")
    self:bindToggle(visuals, "ESP.ShowDistance",  "Distance")
    self:bindToggle(visuals, "ESP.ShowHealth",    "Health Text")
    self:bindToggle(visuals, "ESP.TeamColor",     "Team Color")
    self:bindSlider(visuals, "ESP.MaxDistance",   "Max Distance", {50, 2000}, 50)

    -- Anti-Aim
    local antiaim = self.adapter:createTab(win, "Anti-Aim", "shield")
    self:bindToggle(antiaim, "AntiAim.Enabled",                 "Enabled")
    self:bindToggle(antiaim, "AntiAim.Jitter.Enabled",          "Jitter")
    self:bindDropdown(antiaim,"AntiAim.Jitter.Mode",            "Jitter Mode", {"Sine","Static","Flick","RandomWalk","CustomPattern"})
    self:bindSlider(antiaim, "AntiAim.Jitter.Angle",            "Jitter Angle",      {10, 180}, 5)
    self:bindSlider(antiaim, "AntiAim.Jitter.Speed",            "Jitter Speed",      {1, 50}, 1)
    self:bindToggle(antiaim, "AntiAim.Spin.Enabled",            "Spin")
    self:bindSlider(antiaim, "AntiAim.Spin.Speed",              "Spin Speed",        {1, 200}, 5)
    self:bindToggle(antiaim, "AntiAim.Pitch.Enabled",           "Pitch")
    self:bindDropdown(antiaim,"AntiAim.Pitch.Mode",             "Pitch Mode", {"Down","Up","FakeUp","Random"})
    self:bindToggle(antiaim, "AntiAim.Desync.Enabled",          "Desync")
    self:bindDropdown(antiaim,"AntiAim.Desync.Mode",            "Desync Type", {"Spin","Backwards","Switch","Static","Random"})
    self:bindSlider(antiaim, "AntiAim.Desync.Strength",         "Desync Strength", {0, 1}, 0.05)
    self:bindToggle(antiaim, "AntiAim.Desync.BufferTeleport",   "Buffer Teleport")
    self:bindToggle(antiaim, "AntiAim.Desync.PredictorBias",    "Predictor Bias")
    self:bindToggle(antiaim, "AntiAim.FakeLag.Enabled",         "Fake Lag")
    self:bindDropdown(antiaim,"AntiAim.FakeLag.Mode",           "FakeLag Mode", {"Static","Random","Adaptive","Switch"})
    self:bindSlider(antiaim, "AntiAim.FakeLag.Intensity",       "Lag Intensity", {1, 15}, 0.5)
    self:bindToggle(antiaim, "AntiAim.FakeLag.BackForth",       "Back & Forth")
    self:bindToggle(antiaim, "AntiAim.FakeLag.Doubletap",       "Doubletap")
    self:bindToggle(antiaim, "AntiAim.YawFlip.Enabled",         "Yaw Flip ±90°")
    self:bindSlider(antiaim, "AntiAim.YawFlip.Interval",        "Yaw Flip Interval", {0.05, 1}, 0.05)
    self:bindToggle(antiaim, "AntiAim.Manual.Enabled",          "Manual AA (←↓→)")
    self:bindToggle(antiaim, "AntiAim.Freestanding.Enabled",    "Freestanding")
    self:bindToggle(antiaim, "AntiAim.Indicators.Enabled",      "Indicators")

    -- Movement
    local movement = self.adapter:createTab(win, "Movement", "zap")
    self:bindToggle(movement, "Exploits.Fly.Enabled",        "Fly")
    self:bindSlider(movement, "Exploits.Fly.Speed",          "Fly Speed", {30, 300}, 5)
    self:bindSlider(movement, "Exploits.Fly.Smoothness",     "Fly Smoothness", {1, 30}, 1)
    self:bindToggle(movement, "Exploits.Fly.AirControl",     "Air Control")
    self:bindToggle(movement, "Exploits.Fly.VelPreserve",    "Preserve Velocity")
    self:bindToggle(movement, "Exploits.Noclip.Enabled",     "NoClip")
    self:bindDropdown(movement,"Exploits.Noclip.Mode",       "NoClip Mode", {"Standard","Advanced"})
    self:bindToggle(movement, "Exploits.SpeedHack.Enabled",  "SpeedHack")
    self:bindSlider(movement, "Exploits.SpeedHack.Speed",    "Speed", {16, 500}, 2)
    self:bindToggle(movement, "Exploits.InfJump.Enabled",    "Infinite Jump")
    self:bindSlider(movement, "Exploits.InfJump.Cooldown",   "InfJump Cooldown", {0.1, 1}, 0.05)
    self:bindSlider(movement, "Exploits.InfJump.Boost",      "InfJump Boost", {0, 100}, 5)
    self:bindToggle(movement, "Exploits.Hitbox.Enabled",     "Hitbox Expander")
    self:bindSlider(movement, "Exploits.Hitbox.Size",        "Hitbox Size", {3, 50}, 1)
    self:bindToggle(movement, "Exploits.Hitbox.OnlyEnemies", "Hitbox: Only Enemies")
    self:bindToggle(movement, "Exploits.Velocity.Enabled",   "Velocity Boost")
    self:bindSlider(movement, "Exploits.Velocity.Multiplier","Velocity Mult", {1, 10}, 0.5)
    self:bindSlider(movement, "Exploits.Velocity.Cap",       "Velocity Cap", {50, 500}, 25)
    self:bindToggle(movement, "Exploits.Teleport.Enabled",   "Teleport (V)")
    self:bindSlider(movement, "Exploits.Teleport.Range",     "Teleport Range", {10, 300}, 10)
end

return UIManager