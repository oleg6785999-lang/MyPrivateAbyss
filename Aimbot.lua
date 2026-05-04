-- ============================================================
-- Aimbot.lua — ABYSS ARCHON / Modular  (v6 ELITE)
--   Score-based selection + iterative 2-pass prediction + ping EMA
--   Resolver (least-squares 8 frames + EMA 0.25) + RotVelocity flip
--   Multi-ray visibility (5 лучей ±0.45) + weak cache TTL=0.045
--   Adaptive smoothing + 1D noise + overaim + fatigue
--   Silent: burst (3 ≤150ms / pause 1.5-2.3s)
--   task.spawn heavy loop @ 52ms; RenderStep — light cache read
--   _G.ABYSS_Event + _G.ABYSS_Render (shared)
--   Conflict guards: Fly / NoClip / Desync
-- ============================================================

local Players          = game:GetService("Players")
local RunService       = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Stats            = game:FindService("Stats")

if _G.ABYSS_Aimbot and type(_G.ABYSS_Aimbot.Disconnect) == "function" then
    pcall(_G.ABYSS_Aimbot.Disconnect)
end
_G.ABYSS_Aimbot = nil

----------------------------------------------------------------
-- Settings (defensive merge + v6 additions)
----------------------------------------------------------------
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
S.Prediction          = tonumber(S.Prediction)          or 0.142
S.HitboxOffset        = tonumber(S.HitboxOffset)        or 0
S.Sensitivity         = tonumber(S.Sensitivity)         or 1
S.HitChance           = tonumber(S.HitChance)           or 100
S.HumanizerStrength   = tonumber(S.HumanizerStrength)   or 0.4
S.BulletVelocity      = tonumber(S.BulletVelocity)      or 0
S.MissOffset          = tonumber(S.MissOffset)          or 4
S.MaxSilentPerSec     = tonumber(S.MaxSilentPerSec)     or 0
S.BacktrackTime       = tonumber(S.BacktrackTime)       or 0.24
S.HysteresisMult      = tonumber(S.HysteresisMult)      or 1.3
S.MinShotDelay        = tonumber(S.MinShotDelay)        or 0
S.MaxFovDeltaPerFrame = tonumber(S.MaxFovDeltaPerFrame) or 38

-- v6 additions
if S.UseResolver  == nil then S.UseResolver  = true end
if S.UsePing      == nil then S.UsePing      = true end
if S.UseFatigue   == nil then S.UseFatigue   = true end
if S.UseOveraim   == nil then S.UseOveraim   = true end
if S.UseBurst     == nil then S.UseBurst     = true end
if S.SafeOnFly    == nil then S.SafeOnFly    = true end
if S.SafeOnNoClip == nil then S.SafeOnNoClip = true end
S.SmoothingBase   = tonumber(S.SmoothingBase)   or 0.085
S.TremorAmp       = tonumber(S.TremorAmp)       or 0.18
S.UpdateRate      = tonumber(S.UpdateRate)      or 0.052
S.VisibilityTTL   = tonumber(S.VisibilityTTL)   or 0.045
S.FatigueLockTime = tonumber(S.FatigueLockTime) or 7.0
S.OveraimDeg      = tonumber(S.OveraimDeg)      or 0.7
S.SkipChance      = tonumber(S.SkipChance)      or 0.075
_G.Settings.Aimbot = S

----------------------------------------------------------------
-- Math / Vector upvalues
----------------------------------------------------------------
local mathRandom = math.random
local mathRad    = math.rad
local mathExp    = math.exp
local mathClamp  = math.clamp
local mathMin    = math.min
local mathMax    = math.max
local mathAbs    = math.abs
local mathAcos   = math.acos
local mathSin    = math.sin
local mathSign   = math.sign
local mathHuge   = math.huge
local Vector3New = Vector3.new
local Vector2New = Vector2.new
local Vector3Z   = Vector3.zero
local CFrameNew    = CFrame.new
local CFrameLookAt = CFrame.lookAt or function(at, target) return CFrameNew(at, target) end
local osClock     = os.clock
local tableInsert = table.insert
local tableRemove = table.remove
local tableUnpack = table.unpack
local tableClear  = table.clear
local tableCreate = table.create
local taskSpawn = task.spawn
local taskWait  = task.wait

local LocalPlayer = Players.LocalPlayer
local Camera      = workspace.CurrentCamera

----------------------------------------------------------------
-- CONFIG — точные пороги ELITE
----------------------------------------------------------------
local CONFIG = {
    UPDATE_RATE       = S.UpdateRate,
    VIS_CACHE_TTL     = S.VisibilityTTL,
    PRED_DIST_NORM    = 300,
    VEL_EMA_TC        = 0.10,
    VEL_CAP           = 500,
    VEL_STALE_AFTER   = 2.0,
    LEAD_CAP          = 35,
    DIR_DOT_THRESH    = 0.0,
    GRAVITY_Y         = -workspace.Gravity,
    BT_FRAMES         = 24,
    BT_TTL            = 0.24,
    RESOLVER_FRAMES   = 8,
    RESOLVER_EMA      = 0.25,
    RESOLVER_ROTVEL   = 3.5,
    RESOLVER_OFFSET   = 1.3,
    PING_EMA_ALPHA    = 0.4,
    MULTIRAY_OFFSET   = 0.45,
    MULTIRAY_TRANS    = 0.85,
    SMOOTH_BASE       = S.SmoothingBase,
    SMOOTH_MIN        = 0.042,
    SMOOTH_MAX        = 0.29,
    SMOOTH_DIST_NORM  = 65,
    TREMOR_FREQ_A     = 8.2,
    TREMOR_FREQ_B     = 13.7,
    TREMOR_AMP        = S.TremorAmp,
    MAX_ANGLE_DEG     = S.MaxFovDeltaPerFrame,
    OVERAIM_DEG       = S.OveraimDeg,
    OVERAIM_VEL_THR   = 40,
    OVERAIM_DECAY     = 0.10,
    FATIGUE_LOCK_T    = S.FatigueLockTime,
    FATIGUE_HC_PEN    = 5,
    FATIGUE_RESET_PAUSE = 2.0,
    BURST_COUNT       = 3,
    BURST_WINDOW      = 0.150,
    BURST_PAUSE_MIN   = 1.5,
    BURST_PAUSE_MAX   = 2.3,
    BURST_RESET_GAP   = 0.300,
    ORIGIN_MIN        = 25,
    ORIGIN_MAX        = 80,
    HITBOX_PRIORITY   = { "Head", "UpperTorso", "HumanoidRootPart", "Torso" },
}

----------------------------------------------------------------
-- Event Bus  _G.ABYSS_Event
----------------------------------------------------------------
if type(_G.ABYSS_Event) ~= "table" or type(_G.ABYSS_Event.Fire) ~= "function" then
    local listeners = {}
    _G.ABYSS_Event = {
        _listeners = listeners,
        Connect = function(self, name, fn)
            if type(name) ~= "string" or type(fn) ~= "function" then return nil end
            listeners[name] = listeners[name] or {}
            local arr = listeners[name]
            arr[#arr + 1] = fn
            return { Disconnect = function()
                for i = #arr, 1, -1 do if arr[i] == fn then tableRemove(arr, i) end end
            end }
        end,
        Fire = function(self, name, ...)
            local arr = listeners[name]; if not arr then return end
            for i = 1, #arr do pcall(arr[i], ...) end
        end,
    }
end
local Bus = _G.ABYSS_Event

----------------------------------------------------------------
-- Shared Render Pool  _G.ABYSS_Render
----------------------------------------------------------------
local drawingAvailable = type(Drawing) == "table" and type(Drawing.new) == "function"

local function IsDrawingAlive(obj)
    if not obj then return false end
    local ok = pcall(function() return obj.Visible end)
    return ok
end

local function SafeSet(obj, key, value)
    if not obj then return false end
    local ok = pcall(function() obj[key] = value end)
    return ok
end

if type(_G.ABYSS_Render) ~= "table" then
    _G.ABYSS_Render = {
        FOVCircle       = nil,
        TargetHighlight = {},
        SnaplinesPool   = {},
        _owners         = {},
    }
end
local RP = _G.ABYSS_Render
RP._owners.aimbot = true

local function AcquireFOV()
    if not drawingAvailable then return nil end
    if IsDrawingAlive(RP.FOVCircle) then return RP.FOVCircle end
    local ok, d = pcall(Drawing.new, "Circle")
    if not ok or not d then return nil end
    SafeSet(d, "Thickness",    2)
    SafeSet(d, "NumSides",     64)
    SafeSet(d, "Color",        Color3.fromRGB(0, 255, 100))
    SafeSet(d, "Transparency", 0.85)
    SafeSet(d, "Filled",       false)
    SafeSet(d, "Visible",      false)
    RP.FOVCircle = d
    return d
end

local function ReleaseFOV()
    if RP.FOVCircle then
        pcall(function() RP.FOVCircle:Remove() end)
        RP.FOVCircle = nil
    end
end

----------------------------------------------------------------
-- Table pools (table.create + table.clear)
----------------------------------------------------------------
local EntryPool, EntryPoolN = tableCreate(32), 0
local function EntryGet()
    if EntryPoolN > 0 then
        local e = EntryPool[EntryPoolN]; EntryPool[EntryPoolN] = nil; EntryPoolN = EntryPoolN - 1
        return e
    end
    return {}
end
local function EntryPut(e)
    if not e or type(e) ~= "table" then return end
    tableClear(e)
    if EntryPoolN < 32 then EntryPoolN = EntryPoolN + 1; EntryPool[EntryPoolN] = e end
end

----------------------------------------------------------------
-- Raycast + weak caches
----------------------------------------------------------------
local rayParams = RaycastParams.new()
rayParams.FilterType  = Enum.RaycastFilterType.Exclude
rayParams.IgnoreWater = true

local velEMA       = setmetatable({}, { __mode = "k" })
local velTS        = setmetatable({}, { __mode = "k" })
local velPrev      = setmetatable({}, { __mode = "k" })
local accelEMA     = setmetatable({}, { __mode = "k" })
local btHistory    = setmetatable({}, { __mode = "k" })
local btIndex      = setmetatable({}, { __mode = "k" })
local visCache     = setmetatable({}, { __mode = "k" })
local resolverHist = setmetatable({}, { __mode = "k" })
local resolverEMA  = setmetatable({}, { __mode = "k" })

local internalRaycast = false

----------------------------------------------------------------
-- Conflict guards
----------------------------------------------------------------
local function IsFlyActive()
    return _G.Settings.Fly and _G.Settings.Fly.Enabled
end

local function IsNoClipActive()
    return _G.Settings.NoClip == true
end

local function IsDesyncActive()
    return _G.Settings.AntiAim and _G.Settings.AntiAim.Desync
end

----------------------------------------------------------------
-- Player / character helpers
----------------------------------------------------------------
local function IsAlive(character)
    if not character or not character.Parent then return false end
    local hum = character:FindFirstChildOfClass("Humanoid")
    if not hum or hum.Health <= 0 then return false end
    return true
end

local function GetHumanoid(character)
    if not character then return nil end
    return character:FindFirstChildOfClass("Humanoid")
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
    local prio = CONFIG.HITBOX_PRIORITY
    for i = 1, #prio do
        local p = character:FindFirstChild(prio[i])
        if p and p:IsA("BasePart") then return p end
    end
    return nil
end

----------------------------------------------------------------
-- Multi-ray visibility (5 rays) + cache TTL 0.045 s
----------------------------------------------------------------
local function rebuildIgnoreList()
    local ignore = { Camera }
    local char = LocalPlayer.Character
    if char then tableInsert(ignore, char) end
    rayParams.FilterDescendantsInstances = ignore
end

local function rayHitsTarget(hit, hitPart)
    if not hit then return true end
    local inst = hit.Instance
    if not inst then return true end
    local okT, transp = pcall(function() return inst.Transparency end)
    if okT and type(transp) == "number" and transp > CONFIG.MULTIRAY_TRANS then return true end
    if hitPart then
        if inst == hitPart then return true end
        local model = hitPart.Parent
        if model and inst:IsDescendantOf(model) then return true end
    end
    return false
end

local function castSingle(origin, dir)
    internalRaycast = true
    local ok, res = pcall(workspace.Raycast, workspace, origin, dir, rayParams)
    internalRaycast = false
    if not ok then return nil, false end
    return res, true
end

local function MultiRayVisible(pos, hitPart)
    if not Camera then return false end
    rebuildIgnoreList()
    local origin = Camera.CFrame.Position
    local dir    = pos - origin
    if dir.Magnitude < 0.05 then return true end
    local right  = Camera.CFrame.RightVector * CONFIG.MULTIRAY_OFFSET
    local up     = Camera.CFrame.UpVector    * CONFIG.MULTIRAY_OFFSET
    local offsets = { Vector3Z, right, -right, up, -up }
    for i = 1, 5 do
        local p = pos + offsets[i]
        local hit, ok = castSingle(origin, p - origin)
        if ok and rayHitsTarget(hit, hitPart) then return true end
    end
    return false
end

local function IsVisibleCached(pos, hitPart)
    if not hitPart then return MultiRayVisible(pos, nil) end
    local now = osClock()
    local c = visCache[hitPart]
    if c and (now - c.t) < CONFIG.VIS_CACHE_TTL then return c.v end
    local v = MultiRayVisible(pos, hitPart)
    visCache[hitPart] = { v = v, t = now }
    return v
end

-- Legacy single-ray alias (API compat)
local function IsVisible(target, hitPart)
    if not Camera then return false end
    local pos
    if typeof(target) == "Vector3" then
        pos = target
    elseif typeof(target) == "Instance" and target:IsA("BasePart") then
        pos = target.Position; hitPart = hitPart or target
    else return false end
    return IsVisibleCached(pos, hitPart)
end

----------------------------------------------------------------
-- Ping EMA (GetNetworkPing + Stats fallback)
----------------------------------------------------------------
local pingEMA = 0.0

local function readPingRaw()
    local ok, p = pcall(function() return LocalPlayer:GetNetworkPing() end)
    if ok and type(p) == "number" and p > 0 and p < 5 then return p end
    if Stats then
        local okS, v = pcall(function()
            return Stats.Network.ServerStatsItem["Data Ping"]:GetValue() / 1000
        end)
        if okS and type(v) == "number" and v > 0 then return v end
    end
    return 0
end

local function UpdatePing()
    if not S.UsePing then pingEMA = 0; return end
    local raw = readPingRaw()
    if raw <= 0 then return end
    pingEMA = pingEMA + (raw - pingEMA) * CONFIG.PING_EMA_ALPHA
end

----------------------------------------------------------------
-- Resolver: least-squares 8-frame + EMA 0.25
----------------------------------------------------------------
local function PushResolverSample(part, rotY, now)
    local hist = resolverHist[part]
    if not hist then hist = {}; resolverHist[part] = hist end
    hist[#hist + 1] = { r = rotY, t = now }
    while #hist > CONFIG.RESOLVER_FRAMES do tableRemove(hist, 1) end
end

local function ResolverOffset(part)
    if not S.UseResolver then return 0 end
    local hist = resolverHist[part]
    if not hist or #hist < 3 then return resolverEMA[part] or 0 end
    local n  = #hist
    local t0 = hist[1].t
    local sx, sy, sxx, sxy = 0, 0, 0, 0
    for i = 1, n do
        local x = hist[i].t - t0
        local y = hist[i].r
        sx = sx + x; sy = sy + y
        sxx = sxx + x * x; sxy = sxy + x * y
    end
    local denom = (n * sxx - sx * sx)
    local slope = 0
    if denom > 1e-6 then slope = (n * sxy - sx * sy) / denom end
    local target = 0
    if mathAbs(slope) > CONFIG.RESOLVER_ROTVEL then
        target = -mathSign(slope) * CONFIG.RESOLVER_OFFSET
    end
    local prev = resolverEMA[part] or 0
    local sm = prev + (target - prev) * CONFIG.RESOLVER_EMA
    resolverEMA[part] = sm
    return sm
end

----------------------------------------------------------------
-- Iterative 2-pass prediction  +  accel EMA  +  gravity + ping
-- returns (predictedPos, smoothedSpeed)
----------------------------------------------------------------
local function ComputePredictedPos(part, smoothed, accel, dist)
    local t = (pingEMA + (S.Prediction or 0.142) + CONFIG.UPDATE_RATE)
              * (1 + dist / CONFIG.PRED_DIST_NORM)
    if S.BulletVelocity and S.BulletVelocity > 0 then
        t = t + dist / S.BulletVelocity
    end
    local lead = smoothed * t
    if accel and accel.Magnitude > 0.5 then
        lead = lead + accel * (0.5 * t * t)
    end
    if lead.Magnitude > CONFIG.LEAD_CAP then lead = lead.Unit * CONFIG.LEAD_CAP end
    local pos = part.Position + lead
    if S.PredictGravity and t > 0 then
        pos = pos + Vector3New(0, 0.5 * CONFIG.GRAVITY_Y * t * t, 0)
    end
    return pos
end

local function PredictPosition(part)
    local now    = osClock()
    local curVel = part.AssemblyLinearVelocity
    if typeof(curVel) ~= "Vector3" then curVel = Vector3Z end
    if curVel.Magnitude > CONFIG.VEL_CAP then curVel = curVel.Unit * CONFIG.VEL_CAP end

    local prev, prevT = velEMA[part], velTS[part]
    local smoothed, accel
    if prev and prevT and (now - prevT) < CONFIG.VEL_STALE_AFTER then
        local dt = now - prevT
        if dt < 1e-4 then dt = 1e-4 end
        local alpha = 1 - mathExp(-dt / CONFIG.VEL_EMA_TC)
        if alpha < 0 then alpha = 0 elseif alpha > 1 then alpha = 1 end
        smoothed = prev:Lerp(curVel, alpha)
        local rawAccel = (curVel - (velPrev[part] or curVel)) / dt
        local pAcc = accelEMA[part] or Vector3Z
        accel = pAcc:Lerp(rawAccel, alpha)
    else
        smoothed = curVel; accel = Vector3Z
    end
    velEMA[part]   = smoothed
    velTS[part]    = now
    velPrev[part]  = curVel
    accelEMA[part] = accel

    local okR, rotV = pcall(function() return part.AssemblyAngularVelocity end)
    if okR and typeof(rotV) == "Vector3" then
        PushResolverSample(part, rotV.Y, now)
    end

    local origin = Camera and Camera.CFrame.Position or Vector3Z
    local d1 = (part.Position - origin).Magnitude
    local pos1 = ComputePredictedPos(part, smoothed, accel, d1)
    local d2 = (pos1 - origin).Magnitude
    local pos2 = ComputePredictedPos(part, smoothed, accel, d2)

    if S.HitboxOffset and S.HitboxOffset ~= 0 then
        pos2 = pos2 + Vector3New(0, S.HitboxOffset, 0)
    end
    if Camera then
        local off = ResolverOffset(part)
        if off ~= 0 then
            pos2 = pos2 + Camera.CFrame.RightVector * off
        end
    end
    return pos2, smoothed.Magnitude
end

----------------------------------------------------------------
-- Backtrack: ring buffer 24 frames, TTL 0.24 s
----------------------------------------------------------------
local function StoreBacktrack(part)
    if not S.Backtrack then return end
    local hist = btHistory[part]
    if not hist then
        hist = tableCreate(CONFIG.BT_FRAMES)
        btHistory[part] = hist
        btIndex[part]   = 0
    end
    local idx = (btIndex[part] % CONFIG.BT_FRAMES) + 1
    btIndex[part] = idx
    hist[idx] = { pos = part.Position, t = osClock() }
end

local function GetBacktrackPos(part)
    if not S.Backtrack then return part.Position end
    local hist = btHistory[part]
    if not hist then return part.Position end
    local now    = osClock()
    local maxAge = S.BacktrackTime or CONFIG.BT_TTL
    local startI = btIndex[part] or #hist
    local n = #hist
    if n == 0 then return part.Position end
    for k = 0, n - 1 do
        local i = ((startI - k - 1) % n) + 1
        local entry = hist[i]
        if entry then
            if (now - entry.t) > maxAge then break end
            if IsVisibleCached(entry.pos, part) then return entry.pos end
        end
    end
    return part.Position
end

----------------------------------------------------------------
-- Score-based target selection
--   score = (1/(dist+1)) * (FOVFactor/(angle+0.01))
--           * healthMult * velBonus * visScore * resolverConf
----------------------------------------------------------------
local prevTargetPlayer = nil

local function ComputeScore(char, part, screen2px, fov, dist3D, isVis, smoothedSpeed)
    local hum = GetHumanoid(char)
    local hp  = (hum and hum.Health or 100) / 100
    if hp < 0.05 then hp = 0.05 end
    local healthMult = 1 + (1 - hp) * 0.5
    local velBonus   = 1
    if smoothedSpeed and smoothedSpeed > 5 then
        velBonus = mathClamp(0.6 + smoothedSpeed / 90, 0.6, 1.4)
    end
    local visScore = isVis and 2 or 0.5
    local resConf  = 1
    if S.UseResolver and resolverEMA[part] and mathAbs(resolverEMA[part]) > 0.01 then
        resConf = 1.15
    end
    local distScore = 1 / (dist3D + 1)
    local angScore  = fov / (screen2px + 0.01)
    return distScore * angScore * healthMult * velBonus * visScore * resConf
end

local function GetClosestTarget()
    if not LocalPlayer.Character or not Camera then return nil end

    local viewport = Camera.ViewportSize
    local center   = Vector2New(viewport.X * 0.5, viewport.Y * 0.5)
    local camPos   = Camera.CFrame.Position
    local fov      = S.FOV or 120
    local hystFOV  = fov * (S.HysteresisMult or 1.3)

    local bestEntry, bestScore = nil, -mathHuge
    local prevEntry, prevScore = nil, -mathHuge

    local players = Players:GetPlayers()
    for i = 1, #players do
        local plr = players[i]
        if plr ~= LocalPlayer and IsEnemy(plr) then
            local pchar = plr.Character
            if IsAlive(pchar) then
                local part = GetBestHitbox(pchar)
                if part then
                    StoreBacktrack(part)

                    local pos, smoothedSpeed = PredictPosition(part)
                    local sp, onScreen = Camera:WorldToViewportPoint(pos)
                    if onScreen and sp.Z >= 0 then
                        local screen2 = Vector2New(sp.X, sp.Y)
                        local d2  = (screen2 - center).Magnitude
                        local d3D = (pos - camPos).Magnitude

                        local visible = true
                        if S.WallCheck then
                            visible = IsVisibleCached(pos, part)
                            if not visible and S.Backtrack then
                                local btPos = GetBacktrackPos(part)
                                if btPos ~= part.Position then
                                    pos = btPos
                                    local sp2 = Camera:WorldToViewportPoint(pos)
                                    screen2 = Vector2New(sp2.X, sp2.Y)
                                    d2 = (screen2 - center).Magnitude
                                    d3D = (pos - camPos).Magnitude
                                    visible = true
                                end
                            end
                        end

                        local inBase = (d2 <= fov)
                        local inHyst = (plr == prevTargetPlayer and d2 <= hystFOV)
                        local wallOK = (not S.WallCheck) or visible

                        if (inBase or inHyst) and wallOK then
                            local sc = ComputeScore(pchar, part, d2, fov, d3D, visible, smoothedSpeed)
                            local entry = EntryGet()
                            entry.player    = plr
                            entry.character = pchar
                            entry.part      = part
                            entry.position  = pos
                            entry.screen    = screen2
                            entry.distance  = d2
                            entry.dist3D    = d3D
                            entry.score     = sc
                            entry.visible   = visible
                            entry.speed     = smoothedSpeed

                            local assigned = false
                            if inHyst and plr == prevTargetPlayer and sc > prevScore then
                                if prevEntry then EntryPut(prevEntry) end
                                prevEntry, prevScore = entry, sc
                                assigned = true
                            end
                            if not assigned and inBase and sc > bestScore then
                                if bestEntry then EntryPut(bestEntry) end
                                bestEntry, bestScore = entry, sc
                                assigned = true
                            end
                            if not assigned then EntryPut(entry) end
                        end
                    end
                end
            end
        end
    end

    local final
    if S.TargetHysteresis and prevEntry and bestEntry and prevEntry.player ~= bestEntry.player then
        if bestScore > prevScore * 1.18 then
            final = bestEntry; EntryPut(prevEntry)
        else
            final = prevEntry; EntryPut(bestEntry)
        end
    else
        final = bestEntry or prevEntry
        if bestEntry and prevEntry and bestEntry ~= prevEntry then
            if final == bestEntry then EntryPut(prevEntry) else EntryPut(bestEntry) end
        end
    end

    local prevPlr = prevTargetPlayer
    prevTargetPlayer = final and final.player or nil

    if (final and final.player) ~= prevPlr then
        Bus:Fire("TargetChanged", final and final.player or nil, final)
    end
    return final
end

----------------------------------------------------------------
-- Noise / Overaim / Fatigue
----------------------------------------------------------------
local lastSpeed   = 0
local overaimT    = 0
local overaimSign = 1

local function Noise1D(t)
    return (mathSin(t * CONFIG.TREMOR_FREQ_A) + mathSin(t * CONFIG.TREMOR_FREQ_B * 0.7)) * 0.5
end

local function MaybeOveraim(speed, dist)
    if not S.UseOveraim then return 0 end
    if speed and speed > CONFIG.OVERAIM_VEL_THR and lastSpeed <= CONFIG.OVERAIM_VEL_THR then
        overaimT = osClock() + CONFIG.OVERAIM_DECAY
        overaimSign = (mathRandom() < 0.5) and -1 or 1
    end
    lastSpeed = speed or 0
    if osClock() < overaimT then
        local scale = 1 + (dist or 0) / 500
        return overaimSign * mathRad(CONFIG.OVERAIM_DEG) * scale
    end
    return 0
end

local lockedSince  = 0
local lastTargetPl = nil
local lastNoLockT  = osClock()
local fatigueAct   = false
local fatigueDeg   = 0

local function UpdateFatigue(curTarget)
    if not S.UseFatigue then fatigueAct = false; fatigueDeg = 0; return end
    local now = osClock()
    if curTarget and curTarget.player then
        if curTarget.player ~= lastTargetPl then
            lockedSince  = now
            lastTargetPl = curTarget.player
            fatigueAct   = false
            fatigueDeg   = 0
        end
        if (now - lockedSince) > CONFIG.FATIGUE_LOCK_T then
            fatigueAct = true
            fatigueDeg = mathMin(fatigueDeg + 0.0005, 0.15)
        end
        lastNoLockT = now
    else
        if (now - lastNoLockT) > CONFIG.FATIGUE_RESET_PAUSE then
            lockedSince  = now
            lastTargetPl = nil
            fatigueAct   = false
            fatigueDeg   = 0
        end
    end
end

local function HitChanceFloor(dist)
    if (S.BulletVelocity or 0) > 500 then
        return mathMax(75, 100 - (dist or 0) / 20)
    end
    return 0
end

----------------------------------------------------------------
-- Adaptive smoothing + AimAt (angular cap 38°)
----------------------------------------------------------------
local function AdaptiveAlpha(dt, dist)
    local base = CONFIG.SMOOTH_BASE * (1 + (dist or 0) / CONFIG.SMOOTH_DIST_NORM)
    base = mathClamp(base, CONFIG.SMOOTH_MIN, CONFIG.SMOOTH_MAX)
    local legacy = mathMax(tonumber(S.Smoothing) or 3, 0.001)
    local k = base * (3 / legacy)
    local alpha = 1 - mathExp(-(dt or 1/60) * (1 / mathMax(k, 1e-3)))
    alpha = alpha * mathMax(tonumber(S.Sensitivity) or 1, 0.01)
    if fatigueAct then alpha = alpha * (1 - fatigueDeg) end
    if alpha < 0 then alpha = 0 elseif alpha > 1 then alpha = 1 end
    return alpha
end

local function AimAt(position, dt, speed, dist3D)
    if not position or not Camera then return end
    local cam = Camera.CFrame

    local now = osClock()
    local n   = Noise1D(now)
    local tremorScale = CONFIG.TREMOR_AMP * (1 + (dist3D or 0) / 50)
    local jitter = cam.RightVector * (n * tremorScale * 0.02)
                 + cam.UpVector    * (n * tremorScale * 0.01)
    local target = position + jitter

    local oa = MaybeOveraim(speed, dist3D)
    if oa ~= 0 then
        target = target + cam.RightVector * (oa * (dist3D or 1) * 0.02)
    end

    local desired = CFrameLookAt(cam.Position, target)
    local alpha   = AdaptiveAlpha(dt, dist3D)

    local maxDeg = CONFIG.MAX_ANGLE_DEG
    if maxDeg > 0 then
        local lookDot = mathClamp(cam.LookVector:Dot(desired.LookVector), -1, 1)
        local ang = mathAcos(lookDot)
        local maxRad = mathRad(maxDeg)
        if ang > 0 and ang * alpha > maxRad then
            alpha = maxRad / ang
        end
    end
    Camera.CFrame = cam:Lerp(desired, alpha)
end

----------------------------------------------------------------
-- FOV circle via Render Pool (SafeSet)
----------------------------------------------------------------
local function UpdateFOVCircle()
    local active = (S.Enabled or S.Silent) and not (S.SafeOnFly and IsFlyActive())
    if not active then
        if IsDrawingAlive(RP.FOVCircle) then SafeSet(RP.FOVCircle, "Visible", false) end
        return
    end
    local circle = AcquireFOV()
    if not circle then return end
    if not IsDrawingAlive(circle) then RP.FOVCircle = nil; return end
    local v = Camera.ViewportSize
    if not SafeSet(circle, "Position", Vector2New(v.X * 0.5, v.Y * 0.5)) then
        RP.FOVCircle = nil; return
    end
    SafeSet(circle, "Radius",  S.FOV)
    SafeSet(circle, "Color",   S.Silent and Color3.fromRGB(255, 80, 80) or Color3.fromRGB(0, 255, 100))
    SafeSet(circle, "Visible", true)
end

----------------------------------------------------------------
-- Heavy loop (52 ms via task.spawn) + Light RenderStep
----------------------------------------------------------------
local connections  = {}
local cachedTarget = nil
local cachedAt     = 0
local STEP_NAME    = "ABYSS_AimbotStep"
local heavyAlive   = true

local function isAimActive()
    if S.SafeOnFly    and IsFlyActive()    then return false end
    if S.SafeOnNoClip and IsNoClipActive() then return false end
    return S.Enabled or S.Silent
end

local function heavyLoop()
    while heavyAlive do
        local ok, err = pcall(function()
            Camera = workspace.CurrentCamera
            UpdatePing()
            if isAimActive() and LocalPlayer.Character then
                -- random skip 6-9% для anti-pattern
                if mathRandom() < (S.SkipChance or 0.075) then
                    UpdateFatigue(cachedTarget)
                else
                    local t = GetClosestTarget()
                    cachedTarget = t
                    cachedAt = osClock()
                    UpdateFatigue(t)
                end
            else
                if cachedTarget then Bus:Fire("TargetChanged", nil, nil) end
                cachedTarget = nil
                UpdateFatigue(nil)
            end
        end)
        if not ok then warn("[ABYSS] heavyLoop: " .. tostring(err)) end
        local jitter = (mathRandom() - 0.5) * 0.012
        taskWait(CONFIG.UPDATE_RATE + jitter)
    end
end

taskSpawn(heavyLoop)

local function lightStep(dt)
    Camera = workspace.CurrentCamera
    if not Camera then return end
    UpdateFOVCircle()
    if not isAimActive() then return end
    local t = cachedTarget
    if not t then return end
    if (osClock() - cachedAt) > 0.20 then return end
    if not S.Enabled then return end
    if not t.position or not t.part or not t.part.Parent then return end
    AimAt(t.position, dt, t.speed or 0, t.dist3D or 0)
end

pcall(function()
    RunService:BindToRenderStep(STEP_NAME, Enum.RenderPriority.Camera.Value + 1, lightStep)
end)

tableInsert(connections, LocalPlayer.CharacterAdded:Connect(function()
    Camera = workspace.CurrentCamera
    cachedTarget = nil
    prevTargetPlayer = nil
    lockedSince  = osClock()
    lastTargetPl = nil
    fatigueAct = false; fatigueDeg = 0
    tableClear(velEMA); tableClear(velTS); tableClear(velPrev); tableClear(accelEMA)
    tableClear(btHistory); tableClear(btIndex)
    tableClear(visCache); tableClear(resolverHist); tableClear(resolverEMA)
end))

tableInsert(connections, workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
    Camera = workspace.CurrentCamera
end))

----------------------------------------------------------------
-- Silent helpers
----------------------------------------------------------------
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

-- Dynamic origin radius: 25..80 stud по velocity текущего оружия
local function DynamicOriginRange()
    local char = LocalPlayer.Character
    if not char then return CONFIG.ORIGIN_MAX end
    local tool = char:FindFirstChildOfClass("Tool")
    if not tool then return CONFIG.ORIGIN_MAX end
    local okV, vel = pcall(function()
        if type(gethiddenproperty) == "function" then
            local v = gethiddenproperty(tool, "Velocity")
            return v
        end
        return tool:GetAttribute("Velocity") or tool:GetAttribute("BulletVelocity")
    end)
    if not okV or type(vel) ~= "number" or vel <= 0 then return CONFIG.ORIGIN_MAX end
    -- velocity [200..2500] → radius [25..80]
    local r = CONFIG.ORIGIN_MIN + ((CONFIG.ORIGIN_MAX - CONFIG.ORIGIN_MIN) * mathClamp(vel / 2500, 0, 1))
    return r
end

local function isPlayerOriginRay(origin)
    if typeof(origin) ~= "Vector3" then return false end
    local char = LocalPlayer.Character
    if not char then return false end
    local hrp = char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso")
    if not hrp then return false end
    local range = DynamicOriginRange()
    return (origin - hrp.Position).Magnitude < range
end

local function getValidTarget()
    local t = cachedTarget
    if not t then return nil end
    if osClock() - cachedAt > 0.20 then return nil end
    if not t.character or not t.character.Parent then return nil end
    if not IsAlive(t.character) then return nil end
    if not t.part or not t.part.Parent then return nil end
    if Camera then
        local sp, on = Camera:WorldToViewportPoint(t.position)
        if not on or sp.Z < 0 then return nil end
    end
    return t
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

----------------------------------------------------------------
-- Sliding 1-sec rate limiter (trim always)
----------------------------------------------------------------
local silentTS = {}
local function rateLimitOk()
    local now = osClock()
    while #silentTS > 0 and (now - silentTS[1]) > 1 do
        tableRemove(silentTS, 1)
    end
    local cap = tonumber(S.MaxSilentPerSec) or 0
    if cap <= 0 then return true end
    if #silentTS >= cap then return false end
    tableInsert(silentTS, now)
    return true
end

-- Min interval between shots
local lastShotTime = 0
local function shotDelayOk()
    local d = tonumber(S.MinShotDelay) or 0
    if d <= 0 then return true end
    local now = osClock()
    if now - lastShotTime < d then return false end
    lastShotTime = now
    return true
end

----------------------------------------------------------------
-- Burst manager: 3 shots ≤150ms, pause 1.5-2.3s, reset >300ms gap
----------------------------------------------------------------
local burstTimes = tableCreate(CONFIG.BURST_COUNT)
local burstCount = 0
local burstPauseUntil = 0
local burstLastShot = 0

local function BurstOk()
    if not S.UseBurst then return true end
    local now = osClock()
    if now < burstPauseUntil then return false end
    -- reset if long gap
    if burstLastShot > 0 and (now - burstLastShot) > CONFIG.BURST_RESET_GAP then
        burstCount = 0
        tableClear(burstTimes)
    end
    -- trim old (>window)
    local i = 1
    while i <= #burstTimes do
        if (now - burstTimes[i]) > CONFIG.BURST_WINDOW then
            tableRemove(burstTimes, i)
        else
            i = i + 1
        end
    end
    burstCount = #burstTimes
    if burstCount >= CONFIG.BURST_COUNT then
        local pause = CONFIG.BURST_PAUSE_MIN
                    + (CONFIG.BURST_PAUSE_MAX - CONFIG.BURST_PAUSE_MIN) * mathRandom()
        burstPauseUntil = now + pause
        tableClear(burstTimes)
        burstCount = 0
        return false
    end
    burstTimes[#burstTimes + 1] = now
    burstCount = burstCount + 1
    burstLastShot = now
    return true
end

----------------------------------------------------------------
-- Silent hook
----------------------------------------------------------------
local hookInstalled, origNamecall, mt = false, nil, nil

local function HookBody(self, ...)
    if internalRaycast or not S.Silent then return origNamecall(self, ...) end
    if self ~= workspace then return origNamecall(self, ...) end
    -- Guard: disable Silent при активном Fly/NoClip/Desync
    if S.SafeOnFly and IsFlyActive() then return origNamecall(self, ...) end
    if S.SafeOnNoClip and IsNoClipActive() then return origNamecall(self, ...) end

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
    if direction.Unit:Dot(diff.Unit) < CONFIG.DIR_DOT_THRESH then
        return origNamecall(self, ...)
    end

    if not rateLimitOk() then return origNamecall(self, ...) end
    if not shotDelayOk() then return origNamecall(self, ...) end
    if not BurstOk() then return origNamecall(self, ...) end

    -- Dynamic HitChance floor
    local hcBase = S.HitChance or 100
    local floor  = HitChanceFloor(t.dist3D or 0)
    local hc = mathMax(hcBase, floor)
    if fatigueAct then hc = mathMax(hc - CONFIG.FATIGUE_HC_PEN, 0) end

    local aimPos
    if hc >= 100 or mathRandom(1, 100) <= hc then
        aimPos = humanize(t.part, t.position)
    else
        aimPos = applyMissOffset(t.position)
        if not aimPos then return origNamecall(self, ...) end
    end

    local diff2 = aimPos - origin
    if diff2.Magnitude < 0.5 then return origNamecall(self, ...) end

    local newDir = diff2.Unit * direction.Magnitude
    Bus:Fire("SilentShot", t.player, aimPos)

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
    if not ok or not gmt then
        warn("[ABYSS] Silent Aim: getrawmetatable failed: " .. tostring(gmt)); return
    end

    local origCandidate = gmt.__namecall
    if type(origCandidate) ~= "function" then
        warn("[ABYSS] Silent Aim: mt.__namecall is " .. typeof(origCandidate) .. "; abort hook")
        return
    end

    local cclosOk, cclosResult = pcall(newcclosure, HookBody)
    local hookFn
    if cclosOk and type(cclosResult) == "function" then
        hookFn = cclosResult
    else
        warn("[ABYSS] newcclosure failed (" .. tostring(cclosResult) .. "), using raw function")
        hookFn = HookBody
    end

    mt = gmt
    origNamecall = origCandidate
    pcall(setreadonly, mt, false)
    mt.__namecall = hookFn
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

----------------------------------------------------------------
-- Master Disconnect
----------------------------------------------------------------
local function Disconnect()
    heavyAlive = false
    pcall(function() RunService:UnbindFromRenderStep(STEP_NAME) end)
    UninstallHook()
    for _, c in ipairs(connections) do
        if c and c.Connected then pcall(function() c:Disconnect() end) end
    end
    tableClear(connections)
    tableClear(velEMA); tableClear(velTS); tableClear(velPrev); tableClear(accelEMA)
    tableClear(btHistory); tableClear(btIndex)
    tableClear(visCache); tableClear(resolverHist); tableClear(resolverEMA)
    tableClear(silentTS); tableClear(burstTimes)
    cachedTarget = nil; prevTargetPlayer = nil
    -- Render Pool cleanup (single cycle)
    ReleaseFOV()
    if RP._owners then RP._owners.aimbot = nil end
end

----------------------------------------------------------------
-- Extended API
----------------------------------------------------------------
local function Toggle(name)
    if type(name) ~= "string" then return end
    if S[name] == nil then return end
    S[name] = not S[name]
    return S[name]
end

_G.ABYSS_Aimbot = {
    Disconnect       = Disconnect,
    -- v5 compat
    GetClosestTarget = GetClosestTarget,
    GetCurrentTarget = function() return cachedTarget end,
    AimAt            = AimAt,
    IsAlive          = IsAlive,
    IsEnemy          = IsEnemy,
    GetBestHitbox    = GetBestHitbox,
    IsVisible        = IsVisible,
    Settings         = S,
    -- v6 extensions
    GetTarget        = function() return cachedTarget end,
    GetPredictedPos  = function() return cachedTarget and cachedTarget.position or nil end,
    IsAimbotActive   = function() return isAimActive() and S.Enabled end,
    IsSilentActive   = function() return isAimActive() and S.Silent and hookInstalled end,
    Toggle           = Toggle,
    GetPing          = function() return pingEMA end,
    GetResolverOff   = function(part) return resolverEMA[part] or 0 end,
    Bus              = Bus,
    RenderPool       = RP,
}

print("[ABYSS] Aimbot v6 ELITE loaded — ScoreSelect+Resolver+MultiRay+Burst+Fatigue")
