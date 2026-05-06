local Predictor = {}
Predictor.__index = Predictor

local mathExp   = math.exp
local mathSign  = math.sign
local mathAbs   = math.abs
local mathClamp = math.clamp
local osClock   = os.clock
local Vector3New= Vector3.new
local Vector3Z  = Vector3.zero

local BT_FRAMES        = 24
local VEL_EMA_TC       = 0.10
local VEL_CAP          = 500
local VEL_STALE        = 2.0
local LEAD_CAP         = 35
local PING_EMA_ALPHA   = 0.4
local RESOLVER_FRAMES  = 8
local RESOLVER_EMA     = 0.25
local RESOLVER_ROTVEL  = 3.5
local RESOLVER_OFFSET  = 1.3
local PRED_DIST_NORM   = 300

function Predictor.new()
    return setmetatable({
        prediction       = 0.14,
        hitboxOffset     = 0,
        predictGravity   = false,
        backtrack        = false,
        bulletVel        = 0,
        useResolver      = true,
        usePing          = true,
        useAccel         = true,
        gravity          = -workspace.Gravity,

        velEMA           = setmetatable({}, {__mode="k"}),
        velTS            = setmetatable({}, {__mode="k"}),
        velPrev          = setmetatable({}, {__mode="k"}),
        accelEMA         = setmetatable({}, {__mode="k"}),
        btHistory        = setmetatable({}, {__mode="k"}),
        btIndex          = setmetatable({}, {__mode="k"}),
        resolverHist     = setmetatable({}, {__mode="k"}),
        resolverEMA      = setmetatable({}, {__mode="k"}),

        pingEMA          = 0,
        lastPingUpdate   = 0
    }, Predictor)
end

function Predictor:setPrediction(v)     self.prediction = v end
function Predictor:setHitboxOffset(v)   self.hitboxOffset = v end
function Predictor:setPredictGravity(v) self.predictGravity = v end
function Predictor:setBacktrack(v)      self.backtrack = v end
function Predictor:setBulletVel(v)      self.bulletVel = v end
function Predictor:setUseResolver(v)    self.useResolver = v end
function Predictor:setUsePing(v)        self.usePing = v end
function Predictor:setUseAccel(v)       self.useAccel = v end

----------------------------------------------------------------
-- Ping EMA (called periodically by orchestrator)
----------------------------------------------------------------
function Predictor:updatePing()
    if not self.usePing then self.pingEMA = 0; return end
    local now = osClock()
    if now - self.lastPingUpdate < 0.5 then return end
    self.lastPingUpdate = now
    local raw = 0
    local lp = game:GetService("Players").LocalPlayer
    if lp then
        local ok, p = pcall(function() return lp:GetNetworkPing() end)
        if ok and type(p) == "number" and p > 0 and p < 5 then raw = p end
    end
    if raw == 0 and game:FindService("Stats") then
        local ok, v = pcall(function()
            return game:FindService("Stats").Network.ServerStatsItem["Data Ping"]:GetValue() / 1000
        end)
        if ok and type(v) == "number" and v > 0 then raw = v end
    end
    if raw > 0 then
        self.pingEMA = self.pingEMA + (raw - self.pingEMA) * PING_EMA_ALPHA
    end
end

----------------------------------------------------------------
-- Backtrack: ring buffer 24 frames
----------------------------------------------------------------
function Predictor:store(part)
    if not self.backtrack then return end
    local hist = self.btHistory[part]
    if not hist then
        hist = table.create(BT_FRAMES)
        self.btHistory[part] = hist
        self.btIndex[part] = 0
    end
    local idx = (self.btIndex[part] % BT_FRAMES) + 1
    self.btIndex[part] = idx
    hist[idx] = {pos = part.Position, t = osClock()}
end

function Predictor:getBacktrack(part, maxAge, visibilityCheck)
    if not self.backtrack then return part.Position end
    local hist = self.btHistory[part]
    if not hist then return part.Position end
    local n = #hist
    if n == 0 then return part.Position end
    local startI = self.btIndex[part] or n
    local now = osClock()
    for k = 0, n - 1 do
        local i = ((startI - k - 1) % n) + 1
        local entry = hist[i]
        if entry then
            if (now - entry.t) > maxAge then break end
            if visibilityCheck(entry.pos, part) then return entry.pos end
        end
    end
    return part.Position
end

----------------------------------------------------------------
-- Resolver
----------------------------------------------------------------
function Predictor:_pushResolverSample(part, rotY, now)
    local hist = self.resolverHist[part]
    if not hist then hist = {}; self.resolverHist[part] = hist end
    hist[#hist + 1] = {r = rotY, t = now}
    while #hist > RESOLVER_FRAMES do table.remove(hist, 1) end
end

function Predictor:_resolverOffset(part)
    if not self.useResolver then return 0 end
    local hist = self.resolverHist[part]
    if not hist or #hist < 3 then return self.resolverEMA[part] or 0 end
    local n = #hist
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
    if mathAbs(slope) > RESOLVER_ROTVEL then
        target = -mathSign(slope) * RESOLVER_OFFSET
    end
    local prev = self.resolverEMA[part] or 0
    local sm = prev + (target - prev) * RESOLVER_EMA
    self.resolverEMA[part] = sm
    return sm
end

----------------------------------------------------------------
-- Iterative 2-pass prediction
----------------------------------------------------------------
function Predictor:_computePos(part, smoothed, accel, dist)
    local t = (self.pingEMA + self.prediction) * (1 + dist / PRED_DIST_NORM)
    if self.bulletVel and self.bulletVel > 0 then
        t = t + dist / self.bulletVel
    end
    local lead = smoothed * t
    if accel and self.useAccel and accel.Magnitude > 0.5 then
        lead = lead + accel * (0.5 * t * t)
    end
    if lead.Magnitude > LEAD_CAP then lead = lead.Unit * LEAD_CAP end
    local pos = part.Position + lead
    if self.predictGravity and t > 0 then
        pos = pos + Vector3New(0, 0.5 * self.gravity * t * t, 0)
    end
    return pos
end

function Predictor:compute(part, cameraPos, cameraRight)
    local now = osClock()
    local curVel = part.AssemblyLinearVelocity
    if typeof(curVel) ~= "Vector3" then curVel = Vector3Z end
    if curVel.Magnitude > VEL_CAP then curVel = curVel.Unit * VEL_CAP end

    -- Velocity EMA
    local prev, prevT = self.velEMA[part], self.velTS[part]
    local smoothed, accel
    if prev and prevT and (now - prevT) < VEL_STALE then
        local dt = now - prevT
        if dt < 1e-4 then dt = 1e-4 end
        local alpha = 1 - mathExp(-dt / VEL_EMA_TC)
        if alpha < 0 then alpha = 0 elseif alpha > 1 then alpha = 1 end
        smoothed = prev:Lerp(curVel, alpha)
        if self.useAccel then
            local rawAccel = (curVel - (self.velPrev[part] or curVel)) / dt
            local pAcc = self.accelEMA[part] or Vector3Z
            accel = pAcc:Lerp(rawAccel, alpha)
        else
            accel = Vector3Z
        end
    else
        smoothed = curVel
        accel    = Vector3Z
    end
    self.velEMA[part]   = smoothed
    self.velTS[part]    = now
    self.velPrev[part]  = curVel
    self.accelEMA[part] = accel

    -- Resolver sample (angular velocity)
    if self.useResolver then
        local okR, rotV = pcall(function() return part.AssemblyAngularVelocity end)
        if okR and typeof(rotV) == "Vector3" then
            self:_pushResolverSample(part, rotV.Y, now)
        end
    end

    -- 2-pass prediction
    local d1 = (part.Position - cameraPos).Magnitude
    local pos1 = self:_computePos(part, smoothed, accel, d1)
    local d2 = (pos1 - cameraPos).Magnitude
    local pos2 = self:_computePos(part, smoothed, accel, d2)

    if self.hitboxOffset and self.hitboxOffset ~= 0 then
        pos2 = pos2 + Vector3New(0, self.hitboxOffset, 0)
    end

    -- Resolver lateral nudge
    if self.useResolver and cameraRight then
        local off = self:_resolverOffset(part)
        if off ~= 0 then
            pos2 = pos2 + cameraRight * off
        end
    end
    return pos2, smoothed.Magnitude
end

return Predictor