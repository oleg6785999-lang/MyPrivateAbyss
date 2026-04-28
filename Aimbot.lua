-- === ЗАМЕНИ ЭТОТ ФАЙЛ НА ПОЛНОСТЬЮ ===
-- FILENAME: Aimbot.lua
-- ============================================================
-- Aimbot.lua — ABYSS ARCHON / Modular  (v4 ELITE)
-- Visible (Camera.CFrame) + Silent (__namecall hook).
-- Settings: _G.Settings.Aimbot
--   Existing: Enabled, Silent, FOV, Smoothing, Sensitivity,
--             Prediction, HitboxOffset, WallCheck
--   v4 ELITE: HitChance, HumanizerStrength, BulletVelocity,
--             PredictGravity, RequireMouseDown, MissOffset,
--             MaxSilentPerSec
-- Team filter: _G.Settings.ESP.OnlyEnemies
-- ============================================================

local Players          = game:GetService("Players")
local RunService       = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

if _G.ABYSS_Aimbot and type(_G.ABYSS_Aimbot.Disconnect) == "function" then
    pcall(_G.ABYSS_Aimbot.Disconnect)
end
_G.ABYSS_Aimbot = nil

_G.Settings     = _G.Settings or {}
_G.Settings.ESP = _G.Settings.ESP or {}
local S = _G.Settings.Aimbot or {}
if S.Enabled          == nil then S.Enabled          = false end
if S.Silent           == nil then S.Silent           = false end
if S.WallCheck        == nil then S.WallCheck        = true  end
if S.PredictGravity   == nil then S.PredictGravity   = false end
if S.RequireMouseDown == nil then S.RequireMouseDown = false end
S.FOV               = tonumber(S.FOV)               or 120
S.Smoothing         = tonumber(S.Smoothing)         or 3
S.Prediction        = tonumber(S.Prediction)        or 0.12
S.HitboxOffset      = tonumber(S.HitboxOffset)      or 0
S.Sensitivity       = tonumber(S.Sensitivity)       or 1
S.HitChance         = tonumber(S.HitChance)         or 100
S.HumanizerStrength = tonumber(S.HumanizerStrength) or 0.4
S.BulletVelocity    = tonumber(S.BulletVelocity)    or 0
S.MissOffset        = tonumber(S.MissOffset)        or 4
S.MaxSilentPerSec   = tonumber(S.MaxSilentPerSec)   or 0
_G.Settings.Aimbot = S

local LocalPlayer = Players.LocalPlayer
local Camera      = workspace.CurrentCamera

local rayParams = RaycastParams.new()
rayParams.FilterType  = Enum.RaycastFilterType.Exclude
rayParams.IgnoreWater = true

local HITBOX_PRIORITY     = { "Head", "UpperTorso", "HumanoidRootPart" }
local CACHE_LIFETIME      = 0.10
local SILENT_ORIGIN_RANGE = 60
local LEAD_CAP            = 35
local PRED_DIST_NORM      = 300
local VEL_EMA_TC          = 0.10
local VEL_CAP             = 500
local VEL_STALE_AFTER     = 2.0
local DIR_DOT_THRESH      = 0.0
local GRAVITY_Y           = -workspace.Gravity

local velEMA = setmetatable({}, { __mode = "k" })
local velTS  = setmetatable({}, { __mode = "k" })
local internalRaycast = false

local function IsAlive(character)
    if not character or not character.Parent then return false end
    local hum = character:FindFirstChildOfClass("Humanoid")
    if not hum or hum.Health <= 0 then return false end
    return true
end

local function IsEnemy(player)
    if not player or player == LocalPlayer then return false end
    if not _G.Settings.ESP.OnlyEnemies then return true end
    local mine, theirs = LocalPlayer.Team, player.Team
    if not mine or not theirs then return true end
    if LocalPlayer.Neutral or player.Neutral then return true end
    return theirs ~= mine
end

local function GetBestHitbox(character)
    if not character then return nil end
    for _, name in ipairs(HITBOX_PRIORITY) do
        local p = character:FindFirstChild(name)
        if p and p:IsA("BasePart") then return p end
    end
    return nil
end

local function IsVisible(target, hitPart)
    if not Camera then return false end
    local pos
    if typeof(target) == "Vector3" then
        pos = target
    elseif typeof(target) == "Instance" and target:IsA("BasePart") then
        pos = target.Position; hitPart = hitPart or target
    else return false end
    local ignore = { Camera }
    local char = LocalPlayer.Character
    if char then table.insert(ignore, char) end
    rayParams.FilterDescendantsInstances = ignore
    local origin = Camera.CFrame.Position
    local dir = pos - origin
    if dir.Magnitude < 0.05 then return true end
    internalRaycast = true
    local ok, hit = pcall(workspace.Raycast, workspace, origin, dir, rayParams)
    internalRaycast = false
    if not ok then return false end
    if not hit then return true end
    if hitPart and hit.Instance then
        if hit.Instance == hitPart then return true end
        local model = hitPart.Parent
        if model and hit.Instance:IsDescendantOf(model) then return true end
    end
    return false
end

-- Predict с iterative refinement (2-pass — важно при gravity drop на длинной дистанции)
local function ComputePredictedPos(part, smoothed, dist)
    local t = (S.Prediction or 0.12) * (1 + dist / PRED_DIST_NORM)
    if S.BulletVelocity and S.BulletVelocity > 0 then
        t = t + dist / S.BulletVelocity
    end
    local lead = smoothed * t
    if lead.Magnitude > LEAD_CAP then lead = lead.Unit * LEAD_CAP end
    local pos = part.Position + lead
    if S.PredictGravity and t > 0 then
        pos = pos + Vector3.new(0, 0.5 * GRAVITY_Y * t * t, 0)
    end
    return pos
end

local function PredictPosition(part)
    local now    = os.clock()
    local curVel = part.AssemblyLinearVelocity
    if typeof(curVel) ~= "Vector3" then curVel = Vector3.zero end
    if curVel.Magnitude > VEL_CAP then curVel = curVel.Unit * VEL_CAP end

    local prev, prevT = velEMA[part], velTS[part]
    local smoothed
    if prev and prevT and (now - prevT) < VEL_STALE_AFTER then
        local dt = now - prevT
        local alpha = 1 - math.exp(-dt / VEL_EMA_TC)
        if alpha < 0 then alpha = 0 elseif alpha > 1 then alpha = 1 end
        smoothed = prev:Lerp(curVel, alpha)
    else
        smoothed = curVel
    end
    velEMA[part] = smoothed; velTS[part] = now

    local origin = Camera and Camera.CFrame.Position or Vector3.zero
    local d1 = (part.Position - origin).Magnitude
    local pos1 = ComputePredictedPos(part, smoothed, d1)
    local d2 = (pos1 - origin).Magnitude
    local pos2 = ComputePredictedPos(part, smoothed, d2)

    if S.HitboxOffset and S.HitboxOffset ~= 0 then
        pos2 = pos2 + Vector3.new(0, S.HitboxOffset, 0)
    end
    return pos2
end

local function GetClosestTarget()
    if not LocalPlayer.Character or not Camera then return nil end
    local viewport = Camera.ViewportSize
    local center   = Vector2.new(viewport.X * 0.5, viewport.Y * 0.5)
    local bestDist = S.FOV
    local best     = nil
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr == LocalPlayer then continue end
        if not IsEnemy(plr) then continue end
        local char = plr.Character
        if not IsAlive(char) then continue end
        local part = GetBestHitbox(char)
        if not part then continue end
        local pos = PredictPosition(part)
        local sp, onScreen = Camera:WorldToViewportPoint(pos)
        if not onScreen or sp.Z < 0 then continue end
        local screen2 = Vector2.new(sp.X, sp.Y)
        local d = (screen2 - center).Magnitude
        if d > bestDist then continue end
        if S.WallCheck and not IsVisible(pos, part) then continue end
        bestDist = d
        best = { player=plr, character=char, part=part,
                 position=pos, screen=screen2, distance=d }
    end
    return best
end

local function AimAt(position, dt)
    if not position or not Camera then return end
    local cam     = Camera.CFrame
    local desired = CFrame.lookAt(cam.Position, position)
    local sm      = math.max(tonumber(S.Smoothing) or 3, 0.001)
    local sens    = math.max(tonumber(S.Sensitivity) or 1, 0.01)
    local alpha   = (1 - math.exp(-(dt or 1/60) * (60 / sm))) * sens
    if alpha < 0 then alpha = 0 elseif alpha > 1 then alpha = 1 end
    Camera.CFrame = cam:Lerp(desired, alpha)
end

local fovCircle = nil
do
    local ok, drawing = pcall(function() return Drawing.new("Circle") end)
    if ok and drawing then
        fovCircle = drawing
        fovCircle.Thickness    = 2
        fovCircle.NumSides     = 64
        fovCircle.Color        = Color3.fromRGB(0, 255, 100)
        fovCircle.Transparency = 0.85
        fovCircle.Filled       = false
        fovCircle.Visible      = false
    end
end

local connections   = {}
local cachedTarget  = nil
local cachedAt      = 0
local STEP_NAME     = "ABYSS_AimbotStep"

local function step(dt)
    Camera = workspace.CurrentCamera
    if not Camera then return end
    if fovCircle then
        if S.Enabled or S.Silent then
            local v = Camera.ViewportSize
            fovCircle.Position = Vector2.new(v.X * 0.5, v.Y * 0.5)
            fovCircle.Radius   = S.FOV
            fovCircle.Color    = S.Silent and Color3.fromRGB(255, 80, 80) or Color3.fromRGB(0, 255, 100)
            fovCircle.Visible  = true
        else
            fovCircle.Visible = false
        end
    end
    if not LocalPlayer.Character then cachedTarget = nil; return end
    if S.Enabled or S.Silent then
        local t = GetClosestTarget()
        cachedTarget = t; cachedAt = os.clock()
        if S.Enabled and t then AimAt(t.position, dt) end
    else
        cachedTarget = nil
    end
end

pcall(function()
    RunService:BindToRenderStep(STEP_NAME, Enum.RenderPriority.Camera.Value + 1, step)
end)

table.insert(connections, LocalPlayer.CharacterAdded:Connect(function()
    Camera = workspace.CurrentCamera
    cachedTarget = nil
    table.clear(velEMA); table.clear(velTS)
end))

table.insert(connections, workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
    Camera = workspace.CurrentCamera
end))

-- Silent Aim — defensive cascade
local function humanize(part, pos)
    if not part or not part:IsA("BasePart") then return pos end
    local s = math.clamp(S.HumanizerStrength or 0.4, 0, 1)
    if s <= 0 then return pos end
    local sz = part.Size
    return pos + Vector3.new(
        (math.random() - 0.5) * sz.X * 0.4 * s,
        (math.random() - 0.5) * sz.Y * 0.3 * s,
        (math.random() - 0.5) * sz.Z * 0.4 * s
    )
end

local function isPlayerOriginRay(origin)
    if typeof(origin) ~= "Vector3" then return false end
    local char = LocalPlayer.Character
    if not char then return false end
    local hrp = char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso")
    if not hrp then return false end
    return (origin - hrp.Position).Magnitude < SILENT_ORIGIN_RANGE
end

local function getValidTarget()
    local t = cachedTarget
    if not t then return nil end
    if os.clock() - cachedAt > CACHE_LIFETIME then return nil end
    if not t.character or not t.character.Parent then return nil end
    if not IsAlive(t.character) then return nil end
    if not t.part or not t.part.Parent then return nil end
    if Camera then
        local sp, on = Camera:WorldToViewportPoint(t.position)
        if not on or sp.Z < 0 then return nil end
    end
    return t
end

-- Rate limiter (sliding 1-second window)
local silentTS = {}
local function rateLimitOk()
    local cap = tonumber(S.MaxSilentPerSec) or 0
    if cap <= 0 then return true end
    local now = os.clock()
    while #silentTS > 0 and (now - silentTS[1]) > 1 do
        table.remove(silentTS, 1)
    end
    if #silentTS >= cap then return false end
    table.insert(silentTS, now)
    return true
end

local function isMouseDown()
    if not S.RequireMouseDown then return true end
    local ok, down = pcall(function()
        return UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1)
    end)
    return ok and down or false
end

-- Smart-miss: deliberate offset вместо pass-through
local function applyMissOffset(pos)
    local r = tonumber(S.MissOffset) or 4
    if r <= 0 then return nil end
    local rnd = Vector3.new(
        (math.random() - 0.5) * 2,
        (math.random() - 0.5) * 2,
        (math.random() - 0.5) * 2
    )
    if rnd.Magnitude < 0.001 then rnd = Vector3.new(1, 0, 0) end
    return pos + rnd.Unit * r
end

local hookInstalled = false
local origNamecall, mt = nil, nil

local function HookBody(self, ...)
    if internalRaycast or not S.Silent then return origNamecall(self, ...) end
    if self ~= workspace then return origNamecall(self, ...) end

    local method = getnamecallmethod()
    local isRaycast = (method == "Raycast")
    local isLegacy  = (method == "FindPartOnRayWithIgnoreList" or method == "FindPartOnRay")
    if not isRaycast and not isLegacy then return origNamecall(self, ...) end

    if not isMouseDown() then return origNamecall(self, ...) end

    local origin, direction
    if isRaycast then
        origin    = select(1, ...)
        direction = select(2, ...)
        if typeof(origin) ~= "Vector3" or typeof(direction) ~= "Vector3" then
            return origNamecall(self, ...)
        end
    else
        local ray = select(1, ...)
        if typeof(ray) ~= "Ray" then return origNamecall(self, ...) end
        origin    = ray.Origin
        direction = ray.Direction
    end

    if direction.Magnitude < 0.5 then return origNamecall(self, ...) end
    if not isPlayerOriginRay(origin) then return origNamecall(self, ...) end

    local t = getValidTarget()
    if not t then return origNamecall(self, ...) end

    local diff = t.position - origin
    if diff.Magnitude < 0.5 then return origNamecall(self, ...) end

    if direction.Unit:Dot(diff.Unit) < DIR_DOT_THRESH then
        return origNamecall(self, ...)
    end

    if not rateLimitOk() then return origNamecall(self, ...) end

    -- HitChance: hit (humanized) vs smart-miss (offset)
    local aimPos
    local hitOk = (S.HitChance or 100) >= 100 or (math.random(1, 100) <= S.HitChance)
    if hitOk then
        aimPos = humanize(t.part, t.position)
    else
        aimPos = applyMissOffset(t.position)
        if not aimPos then return origNamecall(self, ...) end
    end

    local diff2 = aimPos - origin
    if diff2.Magnitude < 0.5 then return origNamecall(self, ...) end

    local newDir = diff2.Unit * direction.Magnitude
    if isRaycast then
        local args = { ... }
        args[2] = newDir
        return origNamecall(self, table.unpack(args))
    else
        local args = { ... }
        args[1] = Ray.new(origin, newDir)
        return origNamecall(self, table.unpack(args))
    end
end

local function InstallHook()
    if hookInstalled then return end
    if type(getrawmetatable) ~= "function" or type(setreadonly) ~= "function"
       or type(newcclosure) ~= "function" or type(getnamecallmethod) ~= "function" then
        warn("[ABYSS] Silent Aim: exec не поддерживает namecall hook"); return
    end
    local ok, gmt = pcall(getrawmetatable, game)
    if not ok or not gmt then return end
    mt = gmt; origNamecall = mt.__namecall
    pcall(setreadonly, mt, false)
    mt.__namecall = newcclosure(HookBody)
    pcall(setreadonly, mt, true)
    hookInstalled = true
end

local function UninstallHook()
    if not hookInstalled then return end
    if mt and origNamecall then
        pcall(setreadonly, mt, false)
        mt.__namecall = origNamecall
        pcall(setreadonly, mt, true)
    end
    hookInstalled = false; origNamecall = nil; mt = nil
end

InstallHook()

local function Disconnect()
    pcall(function() RunService:UnbindFromRenderStep(STEP_NAME) end)
    UninstallHook()
    for _, c in ipairs(connections) do
        if c and c.Connected then pcall(function() c:Disconnect() end) end
    end
    table.clear(connections); table.clear(velEMA); table.clear(velTS); table.clear(silentTS)
    cachedTarget = nil
    if fovCircle then
        pcall(function() fovCircle.Visible = false; fovCircle:Remove() end)
        fovCircle = nil
    end
end

_G.ABYSS_Aimbot = {
    Disconnect       = Disconnect,
    GetClosestTarget = GetClosestTarget,
    GetCurrentTarget = function() return cachedTarget end,
    AimAt            = AimAt,
    IsAlive          = IsAlive,
    IsEnemy          = IsEnemy,
    GetBestHitbox    = GetBestHitbox,
    IsVisible        = IsVisible,
    Settings         = S,
}

print("[ABYSS] Aimbot v4 ELITE loaded — Silent+Visible+RateLimit+SmartMiss")
