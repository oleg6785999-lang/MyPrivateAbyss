-- ============================================================
-- 3.lua / Visuals.lua  — ABYSS ARCHON / Modular
-- ESP (Drawing API) + Chams (Highlight)
-- Settings: _G.Settings.ESP { Enabled, Boxes, HealthBar, Snaplines,
--                             Chams, OnlyEnemies, MaxDistance }
-- ============================================================

local Players    = game:GetService("Players")
local RunService = game:GetService("RunService")

-- 1. Защита от повторной загрузки
if _G.ABYSS_Visuals and type(_G.ABYSS_Visuals.Disconnect) == "function" then
    pcall(_G.ABYSS_Visuals.Disconnect)
end
_G.ABYSS_Visuals = nil

local LocalPlayer = Players.LocalPlayer
local Camera      = workspace.CurrentCamera
local drawingAvailable = type(Drawing) == "table" and type(Drawing.new) == "function"

-- Цвета
local C_ENEMY = Color3.fromRGB(255, 60, 60)
local C_TEAM  = Color3.fromRGB(60, 140, 255)
local C_HP_BG = Color3.fromRGB(0, 0, 0)
local C_HP_OK = Color3.fromRGB(60, 220, 60)
local C_HP_LO = Color3.fromRGB(220, 60, 60)
local C_OUT   = Color3.fromRGB(255, 255, 255)

-- ============================================================
-- 2. Per-type Drawing pool
-- ============================================================
local DrawingPool = { Square = {}, Line = {}, Circle = {}, Text = {}, Quad = {}, Triangle = {} }
local DrawingFree = setmetatable({}, { __mode = "k" })

local function Acquire(class)
    if not drawingAvailable then return nil end
    local pool = DrawingPool[class]
    if not pool then pool = {}; DrawingPool[class] = pool end
    for i = 1, #pool do
        local obj = pool[i]
        if DrawingFree[obj] then
            DrawingFree[obj] = false
            return obj
        end
    end
    local ok, d = pcall(Drawing.new, class)
    if not ok or not d then return nil end
    table.insert(pool, d)
    DrawingFree[d] = false
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

-- ============================================================
-- 3. Per-player ESP entries
-- ============================================================
-- entry: { box, hpBg, hpFill, snapline, highlight }
local ESP = {}

local function ReleaseDrawings(e)
    if e.box      then Release(e.box);      e.box = nil end
    if e.hpBg     then Release(e.hpBg);     e.hpBg = nil end
    if e.hpFill   then Release(e.hpFill);   e.hpFill = nil end
    if e.snapline then Release(e.snapline); e.snapline = nil end
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
    HideEntry(plr)
    ESP[plr] = nil
end

-- ============================================================
-- 4. Хелперы
-- ============================================================
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

-- ============================================================
-- 5. Lifecycle (event-based, не RenderStepped)
-- ============================================================
local connections = {}

local function HookCharRemoving(plr)
    table.insert(connections, plr.CharacterRemoving:Connect(function()
        HideEntry(plr)  -- освобождаем drawings, удаляем highlight
    end))
end

table.insert(connections, Players.PlayerAdded:Connect(function(plr)
    if plr ~= LocalPlayer then HookCharRemoving(plr) end
end))
table.insert(connections, Players.PlayerRemoving:Connect(DestroyEntry))

for _, plr in ipairs(Players:GetPlayers()) do
    if plr ~= LocalPlayer then HookCharRemoving(plr) end
end

-- ============================================================
-- 6. Render loop
-- ============================================================
local STEP_NAME        = "ABYSS_VisualsStep"
local cleanedOnDisable = false

local function step()
    Camera = workspace.CurrentCamera
    local S = _G.Settings
    if not S or not S.ESP then return end
    local cfg = S.ESP

    if not cfg.Enabled or not drawingAvailable then
        if not cleanedOnDisable then
            for plr in pairs(ESP) do HideEntry(plr) end
            cleanedOnDisable = true
        end
        return
    end
    cleanedOnDisable = false
    if not Camera then return end

    local viewport = Camera.ViewportSize
    local camPos   = Camera.CFrame.Position
    local snapBase = Vector2.new(viewport.X * 0.5, viewport.Y)
    local maxDist  = cfg.MaxDistance or 500

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
        local color  = enemy and C_ENEMY or C_TEAM

        local e = ESP[plr]
        if not e then e = {}; ESP[plr] = e end

        -- Box
        if cfg.Boxes then
            e.box = e.box or Acquire("Square")
            if e.box then
                local b = e.box
                b.Filled    = false
                b.Color     = color
                b.Thickness = 1
                b.Size      = Vector2.new(width, height)
                b.Position  = Vector2.new(x, y)
                b.Visible   = true
            end
        elseif e.box then
            Release(e.box); e.box = nil
        end

        -- HealthBar
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
        elseif e.snapline then
            Release(e.snapline); e.snapline = nil
        end

        -- Chams (Highlight)
        if cfg.Chams then
            local hl = e.highlight
            if hl and (not hl.Parent or hl.Adornee ~= char) then
                pcall(function() hl:Destroy() end)
                e.highlight = nil; hl = nil
            end
            if not hl then
                local h = Instance.new("Highlight")
                h.Name                 = "ABYSS_HL"
                h.FillColor            = color
                h.OutlineColor         = C_OUT
                h.FillTransparency     = 0.4
                h.OutlineTransparency  = 0.2
                pcall(function() h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop end)
                h.Adornee = char
                h.Parent  = char
                e.highlight = h
            else
                e.highlight.FillColor = color
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

-- ============================================================
-- 7. Disconnect
-- ============================================================
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
print("[ABYSS] Visuals loaded")
