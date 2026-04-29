-- ============================================================
-- Visuals.lua — ABYSS ARCHON (v4 ELITE + Audit-Fixed)
--   Полный файл с интегрированными исправлениями:
--     - Acquire проверяет живучесть объектов из пула
--     - Все сеттеры Drawing обёрнуты в pcall/SafeSet
--     - SetupText полностью защищён
--     - Release чистит умершие объекты из пула
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

-- Пулы и безопасность
local DrawingPool = { Square = {}, Line = {}, Text = {}, Circle = {}, Quad = {}, Triangle = {} }
local DrawingFree = setmetatable({}, { __mode = "k" })

-- Проверка: жив ли Drawing-объект? (пробуем прочитать Visible)
local function IsDrawingAlive(obj)
    if not obj then return false end
    local ok = pcall(function() return obj.Visible end)
    return ok
end

-- Удалить объект из пула по ссылке
local function RemoveFromPool(obj)
    if not obj then return end
    -- Чтение ClassName на мёртвом объекте может бросить ошибку
    -- (executor C++ объект уничтожен) — оборачиваем в pcall.
    local ok, class = pcall(function() return obj.ClassName end)
    if ok and class and DrawingPool[class] then
        local pool = DrawingPool[class]
        for i = #pool, 1, -1 do
            if pool[i] == obj then
                table.remove(pool, i)
                break
            end
        end
    else
        -- ClassName недоступен — fallback: ищем во всех пулах
        for _, pool in pairs(DrawingPool) do
            for i = #pool, 1, -1 do
                if pool[i] == obj then
                    table.remove(pool, i)
                    break
                end
            end
        end
    end
    DrawingFree[obj] = nil
    pcall(function() obj:Remove() end)
end

local function Acquire(class)
    if not drawingAvailable then return nil end
    local pool = DrawingPool[class]
    if not pool then pool = {}; DrawingPool[class] = pool end

    -- ищем живой свободный объект
    for i = #pool, 1, -1 do
        local obj = pool[i]
        if DrawingFree[obj] then
            if IsDrawingAlive(obj) then
                DrawingFree[obj] = false
                return obj
            else
                -- мёртвый — удаляем из пула
                pcall(function() obj:Remove() end)
                table.remove(pool, i)
                DrawingFree[obj] = nil
            end
        end
    end

    -- создаём новый
    local ok, d = pcall(Drawing.new, class)
    if not ok or not d then return nil end
    table.insert(pool, d)
    DrawingFree[d] = false
    return d
end

local function Release(obj)
    if not obj then return end
    if not IsDrawingAlive(obj) then
        RemoveFromPool(obj)
        return
    end
    pcall(function() obj.Visible = false end)
    DrawingFree[obj] = true
end

local function SafeSet(obj, key, value)
    if not obj then return false end
    local ok = pcall(function() obj[key] = value end)
    if not ok then
        -- объект умер, удаляем из пула
        RemoveFromPool(obj)
        return false
    end
    return true
end

-- Массовое задание свойств через SafeSet
local function SafeConfigure(obj, props)
    if not obj then return end
    for k, v in pairs(props) do
        if not SafeSet(obj, k, v) then
            -- объект сдох при установке, не пытаемся дальше
            break
        end
    end
end

local function NukePool()
    for _, pool in pairs(DrawingPool) do
        for i = 1, #pool do
            pcall(function() pool[i]:Remove() end)
        end
        table.clear(pool)
    end
    DrawingFree = setmetatable({}, { __mode = "k" })
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

-- SetupText с полной защитой
local function SetupText(text, str, position, color, size)
    if not text then return end
    local success = true
    success = success and SafeSet(text, "Text", str)
    success = success and SafeSet(text, "Position", position)
    success = success and SafeSet(text, "Color", color)
    success = success and SafeSet(text, "Size", size)
    success = success and SafeSet(text, "Outline", true)
    success = success and SafeSet(text, "OutlineColor", C_TEXT_OL)
    success = success and SafeSet(text, "Center", true)
    success = success and SafeSet(text, "Visible", true)
    pcall(function() text.Font = GetFontIdx() end)  -- это может упасть, pcall оставлен
    if not success then
        -- если одно из свойств не применилось, объект мёртв, убираем из пула
        RemoveFromPool(text)
    end
end

-- Lifecycle
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
            if not e.box or not IsDrawingAlive(e.box) then
                if e.box then Release(e.box) end
                e.box = Acquire("Square")
            end
            if e.box then
                SafeConfigure(e.box, {
                    Filled    = false,
                    Color     = color,
                    Thickness = boxThk,
                    Size      = Vector2.new(width, height),
                    Position  = Vector2.new(x, y),
                    Visible   = true
                })
            end
        elseif e.box then
            Release(e.box); e.box = nil
        end

        -- HealthBar
        if cfg.HealthBar and hum.MaxHealth > 0 then
            if not e.hpBg or not IsDrawingAlive(e.hpBg) then
                if e.hpBg then Release(e.hpBg) end
                e.hpBg = Acquire("Square")
            end
            if not e.hpFill or not IsDrawingAlive(e.hpFill) then
                if e.hpFill then Release(e.hpFill) end
                e.hpFill = Acquire("Square")
            end
            local pct = math.clamp(hum.Health / hum.MaxHealth, 0, 1)
            if e.hpBg then
                SafeConfigure(e.hpBg, {
                    Filled    = true,
                    Color     = C_HP_BG,
                    Thickness = 1,
                    Size      = Vector2.new(3, height),
                    Position  = Vector2.new(x - 5, y),
                    Visible   = true
                })
            end
            if e.hpFill then
                local barH = height * pct
                SafeConfigure(e.hpFill, {
                    Filled    = true,
                    Thickness = 1,
                    Color     = C_HP_OK:Lerp(C_HP_LO, 1 - pct),
                    Size      = Vector2.new(3, barH),
                    Position  = Vector2.new(x - 5, y + (height - barH)),
                    Visible   = true
                })
            end
        else
            if e.hpBg   then Release(e.hpBg);   e.hpBg = nil end
            if e.hpFill then Release(e.hpFill); e.hpFill = nil end
        end

        -- Snapline
        if cfg.Snaplines then
            if not e.snapline or not IsDrawingAlive(e.snapline) then
                if e.snapline then Release(e.snapline) end
                e.snapline = Acquire("Line")
            end
            if e.snapline then
                SafeConfigure(e.snapline, {
                    Color     = color,
                    Thickness = 1,
                    From      = snapBase,
                    To        = Vector2.new(headSp.X, headSp.Y),
                    Visible   = true
                })
            end
        elseif e.snapline then
            Release(e.snapline); e.snapline = nil
        end

        -- Text labels
        local labelY = y - textSize - 2
        local botY   = y + height + 2

        if cfg.ShowNames then
            if not e.nameText or not IsDrawingAlive(e.nameText) then
                if e.nameText then Release(e.nameText) end
                e.nameText = Acquire("Text")
            end
            if e.nameText then
                local nm = (plr.DisplayName ~= "" and plr.DisplayName) or plr.Name
                SetupText(e.nameText, nm, Vector2.new(headSp.X, labelY), color, textSize)
            end
        elseif e.nameText then
            Release(e.nameText); e.nameText = nil
        end

        if cfg.ShowDistance then
            if not e.distText or not IsDrawingAlive(e.distText) then
                if e.distText then Release(e.distText) end
                e.distText = Acquire("Text")
            end
            if e.distText then
                SetupText(e.distText, string.format("%dm", math.floor(dist)),
                          Vector2.new(headSp.X, botY), C_TEXT, textSize)
            end
        elseif e.distText then
            Release(e.distText); e.distText = nil
        end

        if cfg.ShowHealth and hum.MaxHealth > 0 then
            if not e.hpText or not IsDrawingAlive(e.hpText) then
                if e.hpText then Release(e.hpText) end
                e.hpText = Acquire("Text")
            end
            if e.hpText then
                local hpY = cfg.ShowDistance and (botY + textSize + 1) or botY
                local pct = math.clamp(hum.Health / hum.MaxHealth, 0, 1)
                local hpColor = C_HP_OK:Lerp(C_HP_LO, 1 - pct)
                SetupText(e.hpText, string.format("%d HP", math.floor(hum.Health)),
                          Vector2.new(headSp.X, hpY), hpColor, textSize)
            end
        elseif e.hpText then
            Release(e.hpText); e.hpText = nil
        end

        -- Chams (Highlight)
        if cfg.Chams then
            local hl = e.highlight
            if hl and (not hl.Parent or hl.Adornee ~= char) then
                pcall(function() hl:Destroy() end)
                e.highlight = nil; hl = nil
            end
            if not hl then
                local ok, h = pcall(function()
                    local hh = Instance.new("Highlight")
                    hh.Name = "ABYSS_HL"
                    hh.FillColor = color
                    hh.OutlineColor = cfg.ChamsOutline and C_OUT or color
                    hh.FillTransparency = fillT
                    hh.OutlineTransparency = outlT
                    pcall(function() hh.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop end)
                    hh.Adornee = char
                    hh.Parent = char
                    return hh
                end)
                if ok and h then
                    e.highlight = h
                end
            else
                pcall(function()
                    hl.FillColor = color
                    hl.OutlineColor = cfg.ChamsOutline and C_OUT or color
                    hl.FillTransparency = fillT
                    hl.OutlineTransparency = outlT
                end)
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

-- Disconnect
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
print("[ABYSS] Visuals v4 ELITE loaded — Boxes+HP+Snap+Text+Chams (audit-fixed)")
