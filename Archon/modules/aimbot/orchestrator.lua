local TargetSelector    = require(script.Parent.target_selector)
local Predictor         = require(script.Parent.predictor)
local VisibilityChecker = require(script.Parent.visibility_checker)
local AimController     = require(script.Parent.aim_controller)

local HITBOX_PRIORITY = {"Head", "UpperTorso", "HumanoidRootPart", "Torso"}
local mathAbs = math.abs
local Vector2New = Vector2.new

local Aimbot = {}
Aimbot.__index = Aimbot

function Aimbot.new()
    return setmetatable({
        enabled    = false,
        silent     = false,
        selector   = TargetSelector.new(),
        predictor  = Predictor.new(),
        visibility = VisibilityChecker.new(),
        controller = AimController.new(),
        positions  = {},          -- reused between frames (zero alloc)
        fovCircle  = nil,
        events     = nil
    }, Aimbot)
end

function Aimbot:setEnabled(v) self.enabled = v end
function Aimbot:setSilent(v)  self.silent = v end

function Aimbot:Init(di, events)
    self.events = events
    self.camera    = di:resolve("CameraService")
    self.players   = di:resolve("PlayerService")
    self.character = di:resolve("CharacterService")
    self.target    = di:resolve("TargetService")
    self.visibility.raycastService = di:resolve("RaycastService")

    local cfg = di:resolve("ConfigService")
    self.config = cfg

    cfg:bind(self.selector,   "Aimbot.FOV",            "fov")
    cfg:bind(self.selector,   "Aimbot.Hysteresis",     "hysteresis")
    cfg:bind(self.selector,   "Aimbot.HysteresisMult", "hysteresisMult")
    cfg:bind(self.selector,   "Aimbot.TargetMode",     "mode")

    cfg:bind(self.predictor,  "Aimbot.Prediction",     "prediction")
    cfg:bind(self.predictor,  "Aimbot.HitboxOffset",   "hitboxOffset")
    cfg:bind(self.predictor,  "Aimbot.PredictGravity", "predictGravity")
    cfg:bind(self.predictor,  "Aimbot.Backtrack",      "backtrack")
    cfg:bind(self.predictor,  "Aimbot.BulletVel",      "bulletVel")
    cfg:bind(self.predictor,  "Aimbot.UseResolver",    "useResolver")
    cfg:bind(self.predictor,  "Aimbot.UsePing",        "usePing")
    cfg:bind(self.predictor,  "Aimbot.UseAccel",       "useAccel")

    cfg:bind(self.visibility, "Aimbot.WallCheck",      "wallCheck")
    cfg:bind(self.visibility, "Aimbot.MultiRay",       "multiRay")

    cfg:bind(self.controller, "Aimbot.Smoothing",      "smoothing")
    cfg:bind(self.controller, "Aimbot.Sensitivity",    "sensitivity")
    cfg:bind(self.controller, "Aimbot.MaxFovDelta",    "maxFovDelta")
    cfg:bind(self.controller, "Aimbot.RageMode",       "rageMode")

    cfg:bind(self, "Aimbot.Enabled", "enabled")
    cfg:bind(self, "Aimbot.Silent",  "silent")

    -- FOV circle drawing
    local ok, d = pcall(function() return Drawing.new("Circle") end)
    if ok and d then
        self.fovCircle = d
        self.fovCircle.Thickness    = 2
        self.fovCircle.NumSides     = 64
        self.fovCircle.Transparency = 0.85
        self.fovCircle.Filled       = false
        self.fovCircle.Visible      = false
    end
end

function Aimbot:Start() end

local function getBestHitbox(char)
    if not char then return nil end
    for i = 1, #HITBOX_PRIORITY do
        local p = char:FindFirstChild(HITBOX_PRIORITY[i])
        if p and p:IsA("BasePart") then return p end
    end
    return nil
end

function Aimbot:Update(dt)
    -- Disable when off
    if not self.enabled and not self.silent then
        self.target:setTarget(nil)
        return
    end

    local cam  = self.camera:getCamera()
    local char = self.character:getCharacter()
    if not cam or not char then return end

    self.predictor:updatePing()

    local plrs = self.players:getPlayers()
    local localPlr = self.players:getLocalPlayer()
    local camPos   = self.camera:getPosition()
    local camRight = cam.CFrame.RightVector

    -- Reuse positions map
    local positions = self.positions
    table.clear(positions)

    for i = 1, #plrs do
        local plr = plrs[i]
        if plr ~= localPlr and plr.Character then
            local hum = plr.Character:FindFirstChildOfClass("Humanoid")
            if hum and hum.Health > 0 then
                local part = getBestHitbox(plr.Character)
                if part then
                    self.predictor:store(part)
                    local predicted, speed = self.predictor:compute(part, camPos, camRight)
                    local visible = self.visibility:check(cam, char, predicted, part)

                    -- Backtrack fallback if predicted blocked
                    if (not visible) and self.predictor.backtrack then
                        local bt = self.predictor:getBacktrack(part, 0.24, function(p, h)
                            return self.visibility:check(cam, char, p, h)
                        end)
                        if bt ~= part.Position then
                            predicted = bt
                            visible = true
                        end
                    end

                    local d3D = (predicted - camPos).Magnitude
                    local resolverActive = self.predictor.useResolver
                        and self.predictor.resolverEMA[part]
                        and mathAbs(self.predictor.resolverEMA[part]) > 0.01
                        or false

                    positions[plr] = {
                        pos             = predicted,
                        part            = part,
                        visible         = visible,
                        speed           = speed,
                        resolverActive  = resolverActive,
                        dist3D          = d3D
                    }
                end
            end
        end
    end

    -- Always restrict to enemies (rage default; team-aware via Team checks in selector)
    local onlyEnemies = true

    -- WallCheck filtering: drop blocked targets unless backtracked
    if self.visibility.wallCheck then
        for plr, data in pairs(positions) do
            if not data.visible then positions[plr] = nil end
        end
    end

    local final = self.selector:select(cam, plrs, localPlr, positions, onlyEnemies)
    if final then final.timestamp = os.clock() end
    self.target:setTarget(final)

    if self.enabled and final then
        self.controller:apply(cam, final.position, dt)
    end
end

function Aimbot:Render(dt)
    if not self.fovCircle then return end
    if self.enabled or self.silent then
        local v = self.camera:getViewport()
        self.fovCircle.Position = v * 0.5
        self.fovCircle.Radius   = self.selector.fov
        self.fovCircle.Color    = self.silent and Color3.fromRGB(255,80,80) or Color3.fromRGB(0,255,100)
        self.fovCircle.Visible  = true
    else
        self.fovCircle.Visible = false
    end
end

function Aimbot:Stop() end

function Aimbot:Destroy()
    if self.fovCircle then pcall(function() self.fovCircle:Remove() end); self.fovCircle = nil end
    -- Caches are weak → auto-GC; explicit clear for determinism
    table.clear(self.predictor.velEMA)
    table.clear(self.predictor.velTS)
    table.clear(self.predictor.velPrev)
    table.clear(self.predictor.accelEMA)
    table.clear(self.predictor.btHistory)
    table.clear(self.predictor.btIndex)
    table.clear(self.predictor.resolverHist)
    table.clear(self.predictor.resolverEMA)
    self.visibility:invalidate()
    table.clear(self.positions)
end

return Aimbot