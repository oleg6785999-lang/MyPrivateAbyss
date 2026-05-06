-- ============================================================
-- modules/silentaim.lua  —  ARCHON Rage Silent Aim
--   Namecall hook (Raycast / FindPartOnRay*)
--   Dynamic origin radius (auto by tool velocity)
--   Burst manager (3 shots ≤150ms → pause 1.5-2.3s)
--   Sliding rate limit + min shot delay
--   HitChance + smart-miss + humanizer
--   Conflict guards: Fly / Noclip
-- ============================================================

local Players          = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local SilentAim = {}
SilentAim.__index = SilentAim

local mathRandom = math.random
local mathClamp  = math.clamp
local mathMax    = math.max
local mathMin    = math.min
local Vector3New = Vector3.new
local osClock    = os.clock
local tableInsert = table.insert
local tableRemove = table.remove
local tableUnpack = table.unpack
local tableClear  = table.clear

function SilentAim.new()
    return setmetatable({
        enabled         = false,
        hitChance       = 100,
        humanizer       = 0.4,
        missOffset      = 4,
        maxPerSec       = 0,
        minDelay        = 0,
        requireMouseDown = false,
        burst           = false,
        burstCount      = 3,
        burstWindow     = 0.15,
        burstPauseMin   = 1.5,
        burstPauseMax   = 2.3,
        originRange     = 80,
        autoOriginRange = true,
        safeOnFly       = false,
        safeOnNoclip    = false,

        -- runtime state
        shotTS        = {},
        burstTimes    = {},
        burstPauseTil = 0,
        burstLastTS   = 0,
        lastShot      = 0,

        -- hook
        hookInstalled = false,
        origNamecall  = nil,
        rawmt         = nil,
        internalRay   = false,

        -- services
        target        = nil,
        character     = nil,
        camera        = nil,
        raycast       = nil,
        playerSvc     = nil,
        events        = nil,
        config        = nil,
    }, SilentAim)
end

-- setters (config bind compatible)
function SilentAim:setEnabled(v) self.enabled = v end
function SilentAim:setHitChance(v) self.hitChance = v end
function SilentAim:setHumanizer(v) self.humanizer = v end
function SilentAim:setMissOffset(v) self.missOffset = v end
function SilentAim:setMaxPerSec(v) self.maxPerSec = v end
function SilentAim:setMinDelay(v) self.minDelay = v end
function SilentAim:setRequireMouseDown(v) self.requireMouseDown = v end
function SilentAim:setBurst(v) self.burst = v end
function SilentAim:setBurstCount(v) self.burstCount = v end
function SilentAim:setBurstWindow(v) self.burstWindow = v end
function SilentAim:setBurstPauseMin(v) self.burstPauseMin = v end
function SilentAim:setBurstPauseMax(v) self.burstPauseMax = v end
function SilentAim:setOriginRange(v) self.originRange = v end
function SilentAim:setAutoOriginRange(v) self.autoOriginRange = v end
function SilentAim:setSafeOnFly(v) self.safeOnFly = v end
function SilentAim:setSafeOnNoclip(v) self.safeOnNoclip = v end

function SilentAim:Init(di, events)
    self.events    = events
    self.target    = di:resolve("TargetService")
    self.character = di:resolve("CharacterService")
    self.camera    = di:resolve("CameraService")
    self.raycast   = di:resolve("RaycastService")
    self.playerSvc = di:resolve("PlayerService")
    self.config    = di:resolve("ConfigService")

    self.config:bind(self, "SilentAim.Enabled",         "enabled")
    self.config:bind(self, "SilentAim.HitChance",       "hitChance")
    self.config:bind(self, "SilentAim.Humanizer",       "humanizer")
    self.config:bind(self, "SilentAim.MissOffset",      "missOffset")
    self.config:bind(self, "SilentAim.MaxPerSec",       "maxPerSec")
    self.config:bind(self, "SilentAim.MinDelay",        "minDelay")
    self.config:bind(self, "SilentAim.RequireMouseDown","requireMouseDown")
    self.config:bind(self, "SilentAim.Burst",           "burst")
    self.config:bind(self, "SilentAim.BurstCount",      "burstCount")
    self.config:bind(self, "SilentAim.BurstWindow",     "burstWindow")
    self.config:bind(self, "SilentAim.BurstPauseMin",   "burstPauseMin")
    self.config:bind(self, "SilentAim.BurstPauseMax",   "burstPauseMax")
    self.config:bind(self, "SilentAim.OriginRange",     "originRange")
    self.config:bind(self, "SilentAim.AutoOriginRange", "autoOriginRange")
    self.config:bind(self, "SilentAim.SafeOnFly",       "safeOnFly")
    self.config:bind(self, "SilentAim.SafeOnNoclip",    "safeOnNoclip")

    -- SilentAim также включается через Aimbot.Silent (legacy compat)
    self.config:bind(self, "Aimbot.Silent", "enabled")
end

function SilentAim:Start()
    self:installHook()
end

function SilentAim:Stop()
    self:uninstallHook()
end

function SilentAim:Update(dt) end
function SilentAim:Render(dt) end

function SilentAim:Destroy()
    self:uninstallHook()
    tableClear(self.shotTS)
    tableClear(self.burstTimes)
end

----------------------------------------------------------------
-- Helpers
----------------------------------------------------------------
function SilentAim:isFlyActive()
    if not self.safeOnFly then return false end
    local v = self.config and self.config:get("Exploits.Fly.Enabled")
    return v == true
end

function SilentAim:isNoclipActive()
    if not self.safeOnNoclip then return false end
    local v = self.config and self.config:get("Exploits.Noclip.Enabled")
    return v == true
end

function SilentAim:isMouseDown()
    if not self.requireMouseDown then return true end
    local ok, down = pcall(function()
        return UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1)
    end)
    return ok and down or false
end

function SilentAim:rateLimitOk()
    local now = osClock()
    while #self.shotTS > 0 and (now - self.shotTS[1]) > 1 do
        tableRemove(self.shotTS, 1)
    end
    if (self.maxPerSec or 0) <= 0 then return true end
    if #self.shotTS >= self.maxPerSec then return false end
    tableInsert(self.shotTS, now)
    return true
end

function SilentAim:shotDelayOk()
    if (self.minDelay or 0) <= 0 then return true end
    local now = osClock()
    if now - self.lastShot < self.minDelay then return false end
    self.lastShot = now
    return true
end

function SilentAim:burstOk()
    if not self.burst then return true end
    local now = osClock()
    if now < self.burstPauseTil then return false end
    -- reset gap >300ms
    if self.burstLastTS > 0 and (now - self.burstLastTS) > 0.3 then
        tableClear(self.burstTimes)
    end
    -- trim window
    local i = 1
    while i <= #self.burstTimes do
        if (now - self.burstTimes[i]) > self.burstWindow then
            tableRemove(self.burstTimes, i)
        else
            i = i + 1
        end
    end
    if #self.burstTimes >= self.burstCount then
        local pause = self.burstPauseMin + (self.burstPauseMax - self.burstPauseMin) * mathRandom()
        self.burstPauseTil = now + pause
        tableClear(self.burstTimes)
        return false
    end
    self.burstTimes[#self.burstTimes + 1] = now
    self.burstLastTS = now
    return true
end

function SilentAim:dynamicOriginRange()
    if not self.autoOriginRange then return self.originRange end
    local char = self.character:getCharacter()
    if not char then return self.originRange end
    local tool = char:FindFirstChildOfClass("Tool")
    if not tool then return self.originRange end
    local vel = nil
    if type(gethiddenproperty) == "function" then
        local ok, v = pcall(gethiddenproperty, tool, "Velocity")
        if ok and type(v) == "number" then vel = v end
    end
    if not vel then
        vel = tool:GetAttribute("Velocity") or tool:GetAttribute("BulletVelocity")
    end
    if type(vel) ~= "number" or vel <= 0 then return self.originRange end
    -- vel [200..2500] → range [25..self.originRange]
    return 25 + (self.originRange - 25) * mathClamp(vel / 2500, 0, 1)
end

function SilentAim:isPlayerOriginRay(origin)
    if typeof(origin) ~= "Vector3" then return false end
    local root = self.character:getRootPart()
    if not root then return false end
    return (origin - root.Position).Magnitude < self:dynamicOriginRange()
end

function SilentAim:humanize(part, pos)
    if not part or not part:IsA("BasePart") then return pos end
    local s = mathClamp(self.humanizer or 0.4, 0, 1)
    if s <= 0 then return pos end
    local sz = part.Size
    return pos + Vector3New(
        (mathRandom() - 0.5) * sz.X * 0.4 * s,
        (mathRandom() - 0.5) * sz.Y * 0.3 * s,
        (mathRandom() - 0.5) * sz.Z * 0.4 * s
    )
end

function SilentAim:applyMiss(pos)
    local r = self.missOffset or 4
    if r <= 0 then return nil end
    local rnd = Vector3New(
        (mathRandom() - 0.5) * 2,
        (mathRandom() - 0.5) * 2,
        (mathRandom() - 0.5) * 2
    )
    if rnd.Magnitude < 0.001 then rnd = Vector3New(1, 0, 0) end
    return pos + rnd.Unit * r
end

function SilentAim:isAlive(character)
    if not character or not character.Parent then return false end
    local hum = character:FindFirstChildOfClass("Humanoid")
    if not hum or hum.Health <= 0 then return false end
    return true
end

function SilentAim:getValidTarget()
    local t = self.target:getTarget()
    if not t then return nil end
    if not t.position or not t.part or not t.part.Parent then return nil end
    if not self:isAlive(t.character) then return nil end
    if t.timestamp and (osClock() - t.timestamp) > 0.30 then return nil end
    local cam = self.camera:getCamera()
    if cam then
        local sp, on = cam:WorldToViewportPoint(t.position)
        if not on or sp.Z < 0 then return nil end
    end
    return t
end

----------------------------------------------------------------
-- Hook
----------------------------------------------------------------
function SilentAim:redirectArgs(isRaycast, origin, oldDir, newDir, args)
    local newArgs = { tableUnpack(args) }
    if isRaycast then
        newArgs[2] = newDir
    else
        newArgs[1] = Ray.new(origin, newDir)
    end
    return newArgs
end

function SilentAim:hookBody(self2, ...)
    if self.internalRay or not self.enabled then return self.origNamecall(self2, ...) end
    if self2 ~= workspace then return self.origNamecall(self2, ...) end
    if self:isFlyActive() or self:isNoclipActive() then return self.origNamecall(self2, ...) end

    local method = getnamecallmethod()
    local isRaycast = (method == "Raycast")
    local isLegacy  = (method == "FindPartOnRayWithIgnoreList" or method == "FindPartOnRay" or method == "FindPartOnRayWithWhitelist")
    if not isRaycast and not isLegacy then return self.origNamecall(self2, ...) end

    if not self:isMouseDown() then return self.origNamecall(self2, ...) end

    local origin, direction
    if isRaycast then
        origin    = select(1, ...)
        direction = select(2, ...)
        if typeof(origin) ~= "Vector3" or typeof(direction) ~= "Vector3" then
            return self.origNamecall(self2, ...)
        end
    else
        local ray = select(1, ...)
        if typeof(ray) ~= "Ray" then return self.origNamecall(self2, ...) end
        origin    = ray.Origin
        direction = ray.Direction
    end

    if direction.Magnitude < 0.5 then return self.origNamecall(self2, ...) end
    if not self:isPlayerOriginRay(origin) then return self.origNamecall(self2, ...) end

    local t = self:getValidTarget()
    if not t then return self.origNamecall(self2, ...) end

    local diff = t.position - origin
    if diff.Magnitude < 0.5 then return self.origNamecall(self2, ...) end
    if direction.Unit:Dot(diff.Unit) < 0 then return self.origNamecall(self2, ...) end

    if not self:rateLimitOk() then return self.origNamecall(self2, ...) end
    if not self:shotDelayOk() then return self.origNamecall(self2, ...) end
    if not self:burstOk() then return self.origNamecall(self2, ...) end

    local hc = self.hitChance or 100
    local aimPos
    if hc >= 100 or mathRandom(1, 100) <= hc then
        aimPos = self:humanize(t.part, t.position)
    else
        aimPos = self:applyMiss(t.position)
        if not aimPos then return self.origNamecall(self2, ...) end
    end

    local diff2 = aimPos - origin
    if diff2.Magnitude < 0.5 then return self.origNamecall(self2, ...) end
    local newDir = diff2.Unit * direction.Magnitude

    if self.events then
        self.events:publish("SilentShot", t.player, aimPos)
    end

    local newArgs = self:redirectArgs(isRaycast, origin, direction, newDir, { ... })
    return self.origNamecall(self2, tableUnpack(newArgs))
end

function SilentAim:installHook()
    if self.hookInstalled then return end
    if type(getrawmetatable) ~= "function" or type(setreadonly) ~= "function"
       or type(getnamecallmethod) ~= "function" then
        warn("[SilentAim] executor missing namecall hook capabilities")
        return
    end

    local ok, gmt = pcall(getrawmetatable, game)
    if not ok or not gmt then
        warn("[SilentAim] getrawmetatable failed: " .. tostring(gmt))
        return
    end

    local origCandidate = gmt.__namecall
    if type(origCandidate) ~= "function" then
        warn("[SilentAim] __namecall not a function: " .. typeof(origCandidate))
        return
    end

    self.origNamecall = origCandidate
    self.rawmt = gmt

    local body = function(...) return self:hookBody(...) end
    local hookFn
    if type(newcclosure) == "function" then
        local cok, cres = pcall(newcclosure, body)
        hookFn = (cok and type(cres) == "function") and cres or body
    else
        hookFn = body
    end

    pcall(setreadonly, gmt, false)
    gmt.__namecall = hookFn
    pcall(setreadonly, gmt, true)
    self.hookInstalled = true
end

function SilentAim:uninstallHook()
    if not self.hookInstalled then return end
    if self.rawmt and self.origNamecall then
        pcall(setreadonly, self.rawmt, false)
        self.rawmt.__namecall = self.origNamecall
        pcall(setreadonly, self.rawmt, true)
    end
    self.hookInstalled = false
    self.origNamecall = nil
    self.rawmt = nil
end

return SilentAim
