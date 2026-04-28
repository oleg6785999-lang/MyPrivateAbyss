-- === ЗАМЕНИ ЭТОТ ФАЙЛ НА ПОЛНОСТЬЮ ===
-- FILENAME: Visuals.lua
-- ============================================================
-- Visuals.lua — ABYSS ARCHON / Modular  (v4 ELITE)
-- ESP (Drawing API: Box / HealthBar / Snapline / Text labels)
-- + Chams (Highlight, DepthMode AlwaysOnTop, конфиг прозрачности)
--
-- Settings: _G.Settings.ESP
--   Existing: Enabled, Boxes, HealthBar, Snaplines, OnlyEnemies,
--             MaxDistance, Chams
--   v4 ELITE: ShowNames, ShowDistance, ShowHealth, TextSize,
--             TextFont, BoxThickness, SnaplineFromBottom,
--             ChamsOutline, ChamsFillTransparency,
--             ChamsOutlineTransparency, TeamColor
-- ============================================================

local Players    = game:GetService("Players")
local RunService = game:GetService("RunService")

if _G.ABYSS_Visuals and type(_G.ABYSS_Visuals.Disconnect) == "function" then
    pcall(_G.ABYSS_Visuals.Disconnect)
end
_G.ABYSS_Visuals = nil

_G.Settings = _G.Settings or {}
local E = _G.Settings.ESP or {}
if E.Enabled            == nil then E.Enabled            = false end
if E.Boxes              == nil then E.Boxes              = false end
if E.HealthBar          == nil then E.HealthBar          = false end
if E.Snaplines          == nil then E.Snaplines          = false end
if E.OnlyEnemies        == nil then E.OnlyEnemies        = true  end
if E.Chams              == nil then E.Chams              = false end
if E.ShowNames          == nil then E.ShowNames          = false end
if E.ShowDistance       == nil then E.ShowDistance       = false end
if E.ShowHealth         == nil then E.ShowHealth         = false end
if E.SnaplineFromBottom == nil then E.SnaplineFromBottom = true  end
if E.ChamsOutline       == nil then E.ChamsOutline       = true  end
if E.TeamColor          == nil then E.TeamColor          = true  end
E.MaxDistance              = tonumber(E.MaxDistance)              or 500
E.TextSize                 = tonumber(E.TextSize)                 or 13
E.BoxThickness             = tonumber(E.BoxThickness)             or 1
E.ChamsFillTransparency    = tonumber(E.ChamsFillTransparency)    or 0.4
E.ChamsOutlineTransparency = tonumber(E.ChamsOutlineTransparency) or 0.2
E.TextFont                 = E.TextFont                           or "UI"
_G.Settings.ESP = E

-- Drawing.Font enum: 0=UI, 1=System, 2=Plex, 3=Monospace
local FONT_MAP = { UI = 0, System = 1, Plex = 2, Monospace = 3 }
local function GetFontIdx() return FONT_MAP[E.TextFont] or 0 end

local LocalPlayer      = Players.LocalPlayer
local Camera           = workspace.CurrentCamera
local drawingAvailable = type(Drawing) == "table" and type(Drawing.new) == "function"

local C_ENEMY   = Color3.fromRGB(255, 60, 60)
local C_TEAM    = Color3.fromRGB(60, 140, 255)
local C_NEUTRAL = Color3.fromRGB(220, 220, 100)
local C_HP_BG   = Color3.fromRGB(0, 0, 0)
local C_HP_OK   = Color3.fromRGB(60, 220, 60)
local C_HP_LO   = Color3.fromRGB(220, 60, 60)
local C_OUT     = Color3.fromRGB(255, 255, 255)
local C_TEXT    = Color3.fromRGB(255, 255, 255)
local C_TEXT_OL = Color3.fromRGB(0, 0, 0)

-- Per-type Drawing pool
local DrawingPool = { Square = {}, Line = {}, Text = {}, Circle = {}, Quad = {}, Triangle = {} }
local DrawingFree = setmetatable({}, { __mode = "k" })

local function Acquire(class)
    if not drawingAvailable then return nil end
    local pool = DrawingPool[class]
    if not pool then pool = {}; DrawingPool[class] = pool end
    for i = 1, #pool do
        local obj = pool[i]
        if DrawingFree[obj] then DrawingFree[obj] = false; return obj end
    end
    local ok, d = pcall(Drawing.new, class)
    if not ok or not d then return nil end
    table.insert(pool, d); DrawingFree[d] = false
    return d
end

local function Release(obj)
    if not obj then return end
    pcall(function() obj.Visible = false end)
    DrawingFree[obj] = true
end

local function NukePool()
    for _, pool in pairs(DrawingPool) do
        for i = 1, #pool do pcall(function() pool[i]:Remove() end) end
        table.clear(pool)
    end
end

-- Per-player ESP entries
local ESP = {}

local function ReleaseDrawings(e)
    if e.box      then Release(e.box);      e.box      = nil end
    if e.hpBg     then Release(e.hpBg);     e.hpBg     = nil end
    if e.hpFill   then Release(e.hpFill);   e.hpFill   = nil end
    if e.snapline then Release(e.snapline); e.snapline = nil end
    if e.nameText then Release(e.nameText); e.nameText = nil end
    if e.distText then Release(e.distText); e.distText = nil end
    if e.hpText   then Release(e.hpText);   e.hpText   = nil end
end

local function HideEntry(plr)
    local e = ESP[plr]
    if not e then return end
    ReleaseDrawings(e)
    if e.highlight then
        pcall(function() e.highlight:Destroy() end)
        e.highlight = nil
    end
end

local function DestroyEntry(plr)
    HideEntry(plr); ESP[plr] = nil
end

-- Helpers
local function IsAlive(char, hum)
    return char and char.Parent and hum and hum.Health > 0
end

local function IsEnemy(player)
    if not player or player == LocalPlayer then return false end
    local mine, theirs = LocalPlayer.Team, player.Team
    if not mine or not theirs then return true end
    if LocalPlayer.Neutral or player.Neutral then return true end
    return theirs ~= mine
end

local function GetColor(player, enemy)
    if not E.TeamColor then return C_ENEMY end
    if not LocalPlayer.Team or not player.Team then return enemy and C_ENEMY or C_NEUTRAL end
    if LocalPlayer.Neutral or player.Neutral then return C_NEUTRAL end
    return enemy and C_ENEMY or C_TEAM
end

local function SetupText(text, str, position, color, size)
    text.Text         = str
    text.Position     = position
    text.Color        = color
    text.Size         = size
    text.Outline      = true
    text.OutlineColor = C_TEXT_OL
    text.Center       = true
    text.Visible      = true
    pcall(function() text.Font = GetFontIdx() end)
end

-- Lifecycle (event-based)
local connections = {}

local function HookCharRemoving(plr)
    table.insert(connections, plr.CharacterRemoving:Connect(function() HideEntry(plr) end))
end

table.insert(connections, Players.PlayerAdded:Connect(function(plr)
    if plr ~= LocalPlayer then HookCharRemoving(plr) end
end))
table.insert(connections, Players.PlayerRemoving:Connect(DestroyEntry))
for _, plr in ipairs(Players:GetPlayers()) do
    if plr ~= LocalPlayer then HookCharRemoving(plr) end
end

-- Render step
local STEP_NAME        = "ABYSS_VisualsStep"
local cleanedOnDisable = false

local function step()
    Camera = workspace.CurrentCamera
    local cfg = _G.Settings.ESP
    if not cfg then return end

    if not cfg.Enabled or not drawingAvailable then
        if not cleanedOnDisable then
            for plr in pairs(ESP) do HideEntry(plr) end
            cleanedOnDisable = true
        end
        return
    end
    cleanedOnDisable = false
    if not Camera then return end

    -- per-frame cached scalars (минимум аллокаций внутри per-player loop)
    local viewport = Camera.ViewportSize
    local camPos   = Camera.CFrame.Position
    local snapBase
    if cfg.SnaplineFromBottom then
        snapBase = Vector2.new(viewport.X * 0.5, viewport.Y)
    else
        snapBase = Vector2.new(viewport.X * 0.5, viewport.Y * 0.5)
    end
    local maxDist  = cfg.MaxDistance or 500
    local textSize = cfg.TextSize or 13
    local boxThk   = cfg.BoxThickness or 1
    local fillT    = cfg.ChamsFillTransparency or 0.4
    local outlT    = cfg.ChamsOutline and (cfg.ChamsOutlineTransparency or 0.2) or 1

    for _, plr in ipairs(Players:GetPlayers()) do
        if plr == LocalPlayer then continue end

        local char = plr.Character
        local hum  = char and char:FindFirstChildOfClass("Humanoid")
        local root = char and char:FindFirstChild("HumanoidRootPart")

        if not IsAlive(char, hum) or not root then
            if ESP[plr] then HideEntry(plr) end
            continue
        end

        local enemy = IsEnemy(plr)
        if cfg.OnlyEnemies and not enemy then
            if ESP[plr] then HideEntry(plr) end
            continue
        end

        local dist = (root.Position - camPos).Magnitude
        if dist > maxDist then
            if ESP[plr] then HideEntry(plr) end
            continue
        end

        local head    = char:FindFirstChild("Head")
        local headPos = (head and head.Position) or (root.Position + Vector3.new(0, 2.5, 0))
        local legPos  = root.Position - Vector3.new(0, 2.5, 0)
        local headSp  = Camera:WorldToViewportPoint(headPos)
        local legSp   = Camera:WorldToViewportPoint(legPos)

        if headSp.Z < 0 and legSp.Z < 0 then
            if ESP[plr] then HideEntry(plr) end
            continue
        end

        local height = math.abs(legSp.Y - headSp.Y)
        local width  = height * 0.5
        local x      = headSp.X - width * 0.5
        local y      = headSp.Y
        local color  = GetColor(plr, enemy)

        local e = ESP[plr]
        if not e then e = {}; ESP[plr] = e end

        -- Box
        if cfg.Boxes then
            e.box = e.box or Acquire("Square")
            if e.box then
                local b = e.box
                b.Filled    = false
                b.Color     = color
                b.Thickness = boxThk
                b.Size      = Vector2.new(width, height)
                b.Position  = Vector2.new(x, y)
                b.Visible   = true
            end
        elseif e.box then Release(e.box); e.box = nil end

        -- HealthBar (vertical, слева от box)
        if cfg.HealthBar and hum.MaxHealth > 0 then
            e.hpBg   = e.hpBg   or Acquire("Square")
            e.hpFill = e.hpFill or Acquire("Square")
            local pct = math.clamp(hum.Health / hum.MaxHealth, 0, 1)
            if e.hpBg then
                e.hpBg.Filled    = true
                e.hpBg.Color     = C_HP_BG
                e.hpBg.Thickness = 1
                e.hpBg.Size      = Vector2.new(3, height)
                e.hpBg.Position  = Vector2.new(x - 5, y)
                e.hpBg.Visible   = true
            end
            if e.hpFill then
                local barH = height * pct
                e.hpFill.Filled    = true
                e.hpFill.Thickness = 1
                e.hpFill.Color     = C_HP_OK:Lerp(C_HP_LO, 1 - pct)
                e.hpFill.Size      = Vector2.new(3, barH)
                e.hpFill.Position  = Vector2.new(x - 5, y + (height - barH))
                e.hpFill.Visible   = true
            end
        else
            if e.hpBg   then Release(e.hpBg);   e.hpBg = nil end
            if e.hpFill then Release(e.hpFill); e.hpFill = nil end
        end

        -- Snapline
        if cfg.Snaplines then
            e.snapline = e.snapline or Acquire("Line")
            if e.snapline then
                local l = e.snapline
                l.Color     = color
                l.Thickness = 1
                l.From      = snapBase
                l.To        = Vector2.new(headSp.X, headSp.Y)
                l.Visible   = true
            end
        elseif e.snapline then Release(e.snapline); e.snapline = nil end

        -- Text labels (имя над боксом, дист/HP — под)
        local labelY = y - textSize - 2
        local botY   = y + height + 2

        if cfg.ShowNames then
            e.nameText = e.nameText or Acquire("Text")
            if e.nameText then
                local nm = (plr.DisplayName ~= "" and plr.DisplayName) or plr.Name
                SetupText(e.nameText, nm,
                          Vector2.new(headSp.X, labelY), color, textSize)
            end
        elseif e.nameText then Release(e.nameText); e.nameText = nil end

        if cfg.ShowDistance then
            e.distText = e.distText or Acquire("Text")
            if e.distText then
                SetupText(e.distText, string.format("%dm", math.floor(dist)),
                          Vector2.new(headSp.X, botY), C_TEXT, textSize)
            end
        elseif e.distText then Release(e.distText); e.distText = nil end

        if cfg.ShowHealth and hum.MaxHealth > 0 then
            e.hpText = e.hpText or Acquire("Text")
            if e.hpText then
                local hpY = cfg.ShowDistance and (botY + textSize + 1) or botY
                local pct = math.clamp(hum.Health / hum.MaxHealth, 0, 1)
                local hpColor = C_HP_OK:Lerp(C_HP_LO, 1 - pct)
                SetupText(e.hpText, string.format("%d HP", math.floor(hum.Health)),
                          Vector2.new(headSp.X, hpY), hpColor, textSize)
            end
        elseif e.hpText then Release(e.hpText); e.hpText = nil end

        -- Chams (Highlight)
        if cfg.Chams then
            local hl = e.highlight
            if hl and (not hl.Parent or hl.Adornee ~= char) then
                pcall(function() hl:Destroy() end)
                e.highlight = nil; hl = nil
            end
            if not hl then
                local h = Instance.new("Highlight")
                h.Name                = "ABYSS_HL"
                h.FillColor           = color
                h.OutlineColor        = cfg.ChamsOutline and C_OUT or color
                h.FillTransparency    = fillT
                h.OutlineTransparency = outlT
                pcall(function() h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop end)
                h.Adornee = char
                h.Parent  = char
                e.highlight = h
            else
                hl.FillColor           = color
                hl.OutlineColor        = cfg.ChamsOutline and C_OUT or color
                hl.FillTransparency    = fillT
                hl.OutlineTransparency = outlT
            end
        elseif e.highlight then
            pcall(function() e.highlight:Destroy() end)
            e.highlight = nil
        end
    end
end

pcall(function()
    RunService:BindToRenderStep(STEP_NAME, Enum.RenderPriority.Camera.Value + 2, step)
end)

-- Disconnect (мгновенная очистка)
local function Disconnect()
    pcall(function() RunService:UnbindFromRenderStep(STEP_NAME) end)
    for _, c in ipairs(connections) do
        if c and c.Connected then pcall(function() c:Disconnect() end) end
    end
    table.clear(connections)
    for plr in pairs(ESP) do DestroyEntry(plr) end
    NukePool()
end

_G.ABYSS_Visuals = { Disconnect = Disconnect }
print("[ABYSS] Visuals v4 ELITE loaded — Boxes+HP+Snap+Text+Chams")
