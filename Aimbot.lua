-- === ЗАМЕНИ ЭТОТ ФАЙЛ НА ПОЛНОСТЬЮ ===
-- FILENAME: Aimbot.lua
-- ============================================================
-- Aimbot.lua — ABYSS ARCHON / Modular  (v5 ELITE)
--   Visible (Camera.CFrame) + Silent (__namecall hook), независимо.
--   v5 улучшения:
--    + Backtrack (ring buffer recent positions, choose visible)
--    + Target Hysteresis (smooth target switching, no jitter)
--    + MinShotDelay (humanizer rate-limit)
--    + MaxFovDeltaPerFrame (clamp angular change, no visual snap)
--    + Cached locals (mathRandom, Vector3New, etc) — micro-perf
--    + Stale velocity reset (>2sec) + clamp 500 studs/sec
--    + Iterative 2-pass prediction + bullet velocity + gravity
--   Settings: _G.Settings.Aimbot (defensive merge с Main.lua)
-- ============================================================

local Players          = game:GetService("Players")
local RunService       = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

if _G.ABYSS_Aimbot and type(_G.ABYSS_Aimbot.Disconnect) == "function" then
    pcall(_G.ABYSS_Aimbot.Disconnect)
end
_G.ABYSS_Aimbot = nil

-- Settings (defensive merge)
_G.Settings     = _G.Settings or {}
_G.Settings.ESP = _G.Settings.ESP or {}
local S = _G.Settings.Aimbot or {}
if S.Enabled          == nil then S.Enabled          = false end
if S.Silent           == nil then S.Silent           = false end
if S.WallCheck        == nil then S.WallCheck        = true  end
if S.PredictGravity   == nil then S.PredictGravity   = false end
if S.RequireMouseDown == nil then S.RequireMouseDown = false end
if S.Backtrack        == nil then S.Backtrack        = false end
if S.TargetHysteresis == nil then S.TargetHysteresis = true  end
S.FOV                 = tonumber(S.FOV)                 or 120
S.Smoothing           = tonumber(S.Smoothing)           or 3
S.Prediction          = tonumber(S.Prediction)          or 0.12
S.HitboxOffset        = tonumber(S.HitboxOffset)        or 0
S.Sensitivity         = tonumber(S.Sensitivity)         or 1
S.HitChance           = tonumber(S.HitChance)           or 100
S.HumanizerStrength   = tonumber(S.HumanizerStrength)   or 0.4
S.BulletVelocity      = tonumber(S.BulletVelocity)      or 0
S.MissOffset          = tonumber(S.MissOffset)          or 4
S.MaxSilentPerSec     = tonumber(S.MaxSilentPerSec)     or 0
S.BacktrackTime       = tonumber(S.BacktrackTime)       or 0.2
S.HysteresisMult      = tonumber(S.HysteresisMult)      or 1.3
S.MinShotDelay        = tonumber(S.MinShotDelay)        or 0
S.MaxFovDeltaPerFrame = tonumber(S.MaxFovDeltaPerFrame) or 30
_G.Settings.Aimbot = S

-- Cached locals (perf)
local mathRandom    = math.random
local mathRad       = math.rad
local mathExp       = math.exp
local mathClamp     = math.clamp
local mathMin       = math.min
local mathMax       = math.max
local mathAcos      = math.acos
local Vector3New    = Vector3.new
local Vector2New    = Vector2.new
local CFrameLookAt  = CFrame.lookAt
local osClock       = os.clock
local tableInsert   = table.insert
local tableRemove   = table.remove
local tableUnpack   = table.unpack

local LocalPlayer = Players.LocalPlayer
local Camera      = workspace.CurrentCamera

local rayParams = RaycastParams.new()
rayParams.FilterType  = Enum.RaycastFilterType.Exclude
rayParams.IgnoreWater = true

local HITBOX_PRIORITY     = { "Head", "UpperTorso", "HumanoidRootPart", "Torso" }
local CACHE_LIFETIME      = 0.10
local SILENT_ORIGIN_RANGE = 60
local LEAD_CAP            = 35
local PRED_DIST_NORM      = 300
local VEL_EMA_TC          = 0.10
local VEL_CAP             = 500
local VEL_STALE_AFTER     = 2.0
local DIR_DOT_THRESH      = 0.0
local GRAVITY_Y           = -workspace.Gravity
local BACKTRACK_MAX_FRAMES = 16

-- Caches (weak)
local velEMA    = setmetatable({}, { __mode = "k" })
local velTS     = setmetatable({}, { __mode = "k" })
local btHistory = setmetatable({}, { __mode = "k" })

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
    for i = 1, #HITBOX_PRIORITY do
        local p = character:FindFirstChild(HITBOX_PRIORITY[i])
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
    if char then tableInsert(ignore, char) end
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

-- Predict (single pass)
local function ComputePredictedPos(part, smoothed, dist)
    local t = (S.Prediction or 0.12) * (1 + dist / PRED_DIST_NORM)
    if S.BulletVelocity and S.BulletVelocity > 0 then
        t = t + dist / S.BulletVelocity
    end
    local lead = smoothed * t
    if lead.Magnitude > LEAD_CAP then lead = lead.Unit * LEAD_CAP end
    local pos = part.Position + lead
    if S.PredictGravity and t > 0 then
        pos = pos + Vector3New(0, 0.5 * GRAVITY_Y * t * t, 0)
    end
    return pos
end

-- 2-pass iterative refinement
local function PredictPosition(part)
    local now    = osClock()
    local curVel = part.AssemblyLinearVelocity
    if typeof(curVel) ~= "Vector3" then curVel = Vector3New(0, 0, 0) end
    if curVel.Magnitude > VEL_CAP then curVel = curVel.Unit * VEL_CAP end

    local prev, prevT = velEMA[part], velTS[part]
    local smoothed
    if prev and prevT and (now - prevT) < VEL_STALE_AFTER then
        local dt = now - prevT
        local alpha = 1 - mathExp(-dt / VEL_EMA_TC)
        if alpha < 0 then alpha = 0 elseif alpha > 1 then alpha = 1 end
        smoothed = prev:Lerp(curVel, alpha)
    else
        smoothed = curVel
    end
    velEMA[part] = smoothed; velTS[part] = now

    local origin = Camera and Camera.CFrame.Position or Vector3New(0, 0, 0)
    local d1 = (part.Position - origin).Magnitude
    local pos1 = ComputePredictedPos(part, smoothed, d1)
    local d2 = (pos1 - origin).Magnitude
    local pos2 = ComputePredictedPos(part, smoothed, d2)

    if S.HitboxOffset and S.HitboxOffset ~= 0 then
        pos2 = pos2 + Vector3New(0, S.HitboxOffset, 0)
    end
    return pos2
end

-- Backtrack ring buffer
local function StoreBacktrack(part)
    if not S.Backtrack then return end
    local hist = btHistory[part]
    if not hist then hist = {}; btHistory[part] = hist end
    hist[#hist + 1] = { pos = part.Position, t = osClock() }
    while #hist > BACKTRACK_MAX_FRAMES do tableRemove(hist, 1) end
end

-- Find best historical visible position
local function GetBacktrackPos(part)
    if not S.Backtrack then return part.Position end
    local hist = btHistory[part]
    if not hist or #hist == 0 then return part.Position end
    local now    = osClock()
    local maxAge = S.BacktrackTime or 0.2
    for i = #hist, 1, -1 do
        local entry = hist[i]
        if now - entry.t > maxAge then break end
        if IsVisible(entry.pos, part) then return entry.pos end
    end
    return part.Position
end

-- Target selection с hysteresis (smooth target switch)
local prevTargetPlayer = nil

local function GetClosestTarget()
    if not LocalPlayer.Character or not Camera then return nil end
    local viewport = Camera.ViewportSize
    local center   = Vector2New(viewport.X * 0.5, viewport.Y * 0.5)
    local fov      = S.FOV or 120
    local hystFOV  = fov * (S.HysteresisMult or 1.3)

    local bestEntry, bestDist = nil, fov
    local prevEntry = nil  -- prev target данные если виден в этом кадре

    for _, plr in ipairs(Players:GetPlayers()) do
        if plr == LocalPlayer then continue end
        if not IsEnemy(plr) then continue end
        local char = plr.Character
        if not IsAlive(char) then continue end
        local part = GetBestHitbox(char)
        if not part then continue end

        StoreBacktrack(part)

        local pos = PredictPosition(part)
        local sp, onScreen = Camera:WorldToViewportPoint(pos)
        if not onScreen or sp.Z < 0 then continue end
        local screen2 = Vector2New(sp.X, sp.Y)
        local d = (screen2 - center).Magnitude

        -- WallCheck с backtrack fallback
        if S.WallCheck and not IsVisible(pos, part) then
            if S.Backtrack then
                local btPos = GetBacktrackPos(part)
                if btPos == part.Position then continue end
                pos = btPos
                local sp2 = Camera:WorldToViewportPoint(pos)
                screen2 = Vector2New(sp2.X, sp2.Y)
                d = (screen2 - center).Magnitude
            else
                continue
            end
        end

        local entry = { player=plr, character=char, part=part,
                        position=pos, screen=screen2, distance=d }

        if plr == prevTargetPlayer and d <= hystFOV then
            prevEntry = entry
        end
        if d <= fov and d < bestDist then
            bestDist  = d
            bestEntry = entry
        end
    end

    -- Hysteresis: keep prev target если он не сильно дальше нового
    local final
    if S.TargetHysteresis and prevEntry and bestEntry and prevEntry.player ~= bestEntry.player then
        if bestEntry.distance < prevEntry.distance * 0.85 then
            final = bestEntry
        else
            final = prevEntry
        end
    else
        final = bestEntry or prevEntry
    end

    prevTargetPlayer = final and final.player or nil
    return final
end

-- AimAt с per-frame angular cap
local function AimAt(position, dt)
    if not position or not Camera then return end
    local cam     = Camera.CFrame
    local desired = CFrameLookAt(cam.Position, position)
    local sm      = mathMax(tonumber(S.Smoothing) or 3, 0.001)
    local sens    = mathMax(tonumber(S.Sensitivity) or 1, 0.01)
    local alpha   = (1 - mathExp(-(dt or 1/60) * (60 / sm))) * sens
    if alpha < 0 then alpha = 0 elseif alpha > 1 then alpha = 1 end

    -- Clamp angular delta per frame (prevent visual snap)
    local maxDeg = S.MaxFovDeltaPerFrame or 30
    if maxDeg > 0 then
        local angBetween = mathAcos(mathClamp(cam.LookVector:Dot(desired.LookVector), -1, 1))
        local maxRad = mathRad(maxDeg)
        if angBetween > 0 and angBetween * alpha > maxRad then
            alpha = maxRad / angBetween
        end
    end

    Camera.CFrame = cam:Lerp(desired, alpha)
end

-- FOV Circle
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

-- Step loop (BindToRenderStep, Camera+1 priority)
local connections  = {}
local cachedTarget = nil
local cachedAt     = 0
local STEP_NAME    = "ABYSS_AimbotStep"

local function step(dt)
    Camera = workspace.CurrentCamera
    if not Camera then return end
    if fovCircle then
        if S.Enabled or S.Silent then
            local v = Camera.ViewportSize
            fovCircle.Position = Vector2New(v.X * 0.5, v.Y * 0.5)
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
        cachedTarget = t; cachedAt = osClock()
        if S.Enabled and t then AimAt(t.position, dt) end
    else
        cachedTarget = nil
    end
end

pcall(function()
    RunService:BindToRenderStep(STEP_NAME, Enum.RenderPriority.Camera.Value + 1, step)
end)

tableInsert(connections, LocalPlayer.CharacterAdded:Connect(function()
    Camera = workspace.CurrentCamera
    cachedTarget = nil
    prevTargetPlayer = nil
    table.clear(velEMA); table.clear(velTS); table.clear(btHistory)
end))

tableInsert(connections, workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
    Camera = workspace.CurrentCamera
end))

-- Silent helpers
local function humanize(part, pos)
    if not part or not part:IsA("BasePart") then return pos end
    local s = mathClamp(S.HumanizerStrength or 0.4, 0, 1)
    if s <= 0 then return pos end
    local sz = part.Size
    return pos + Vector3New(
        (mathRandom() - 0.5) * sz.X * 0.4 * s,
        (mathRandom() - 0.5) * sz.Y * 0.3 * s,
        (mathRandom() - 0.5) * sz.Z * 0.4 * s
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
    if osClock() - cachedAt > CACHE_LIFETIME then return nil end
    if not t.character or not t.character.Parent then return nil end
    if not IsAlive(t.character) then return nil end
    if not t.part or not t.part.Parent then return nil end
    if Camera then
        local sp, on = Camera:WorldToViewportPoint(t.position)
        if not on or sp.Z < 0 then return nil end
    end
    return t
end

-- Sliding 1-sec rate limiter
local silentTS = {}
local function rateLimitOk()
    local cap = tonumber(S.MaxSilentPerSec) or 0
    if cap <= 0 then return true end
    local now = osClock()
    while #silentTS > 0 and (now - silentTS[1]) > 1 do
        tableRemove(silentTS, 1)
    end
    if #silentTS >= cap then return false end
    tableInsert(silentTS, now)
    return true
end

-- Min interval between consecutive shots (humanizer)
local lastShotTime = 0
local function shotDelayOk()
    local d = tonumber(S.MinShotDelay) or 0
    if d <= 0 then return true end
    local now = osClock()
    if now - lastShotTime < d then return false end
    lastShotTime = now
    return true
end

local function isMouseDown()
    if not S.RequireMouseDown then return true end
    local ok, down = pcall(function()
        return UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1)
    end)
    return ok and down or false
end

local function applyMissOffset(pos)
    local r = tonumber(S.MissOffset) or 4
    if r <= 0 then return nil end
    local rnd = Vector3New(
        (mathRandom() - 0.5) * 2,
        (mathRandom() - 0.5) * 2,
        (mathRandom() - 0.5) * 2
    )
    if rnd.Magnitude < 0.001 then rnd = Vector3New(1, 0, 0) end
    return pos + rnd.Unit * r
end

-- Silent hook
local hookInstalled, origNamecall, mt = false, nil, nil

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
    if not shotDelayOk() then return origNamecall(self, ...) end

    local aimPos
    local hitOk = (S.HitChance or 100) >= 100 or (mathRandom(1, 100) <= S.HitChance)
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
        return origNamecall(self, tableUnpack(args))
    else
        local args = { ... }
        args[1] = Ray.new(origin, newDir)
        return origNamecall(self, tableUnpack(args))
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

-- Disconnect
local function Disconnect()
    pcall(function() RunService:UnbindFromRenderStep(STEP_NAME) end)
    UninstallHook()
    for _, c in ipairs(connections) do
        if c and c.Connected then pcall(function() c:Disconnect() end) end
    end
    table.clear(connections); table.clear(velEMA); table.clear(velTS)
    table.clear(silentTS); table.clear(btHistory)
    cachedTarget = nil; prevTargetPlayer = nil
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

print("[ABYSS] Aimbot v5 ELITE loaded — Backtrack+Hysteresis+SmartMiss+SilentRateLimit")
