local TargetSelector = require(script.Parent.target_selector)
local Predictor = require(script.Parent.predictor)
local VisibilityChecker = require(script.Parent.visibility_checker)
local AimController = require(script.Parent.aim_controller)

local Aimbot = {}
Aimbot.__index = Aimbot

function Aimbot.new()
    return setmetatable({
        enabled = false, silent = false,
        selector = TargetSelector.new(),
        predictor = Predictor.new(),
        visibility = VisibilityChecker.new(),
        controller = AimController.new(),
        fovCircle = nil, events = nil
    }, Aimbot)
end

function Aimbot:setEnabled(v) self.enabled = v end
function Aimbot:setSilent(v) self.silent = v end

function Aimbot:Init(di, events)
    self.events = events
    self.camera = di:resolve("CameraService")
    self.players = di:resolve("PlayerService")
    self.character = di:resolve("CharacterService")
    self.target = di:resolve("TargetService")
    self.visibility.raycastService = di:resolve("RaycastService")
    local cfg = di:resolve("ConfigService")
    cfg:bind(self.selector, "Aimbot.FOV", "fov")
    cfg:bind(self.selector, "Aimbot.Hysteresis", "hysteresis")
    cfg:bind(self.selector, "Aimbot.HysteresisMult", "hysteresisMult")
    cfg:bind(self.predictor, "Aimbot.Prediction", "prediction")
    cfg:bind(self.predictor, "Aimbot.HitboxOffset", "hitboxOffset")
    cfg:bind(self.predictor, "Aimbot.PredictGravity", "predictGravity")
    cfg:bind(self.predictor, "Aimbot.Backtrack", "backtrack")
    cfg:bind(self.predictor, "Aimbot.BulletVel", "bulletVel")
    cfg:bind(self.visibility, "Aimbot.WallCheck", "wallCheck")
    cfg:bind(self.controller, "Aimbot.Smoothing", "smoothing")
    cfg:bind(self.controller, "Aimbot.Sensitivity", "sensitivity")
    cfg:bind(self.controller, "Aimbot.MaxFovDelta", "maxFovDelta")
    cfg:bind(self, "Aimbot.Enabled", "enabled")
    cfg:bind(self, "Aimbot.Silent", "silent")
    local ok, d = pcall(function() return Drawing.new("Circle") end)
    if ok and d then
        self.fovCircle = d
        self.fovCircle.Thickness = 2; self.fovCircle.NumSides = 64
        self.fovCircle.Transparency = 0.85; self.fovCircle.Filled = false
        self.fovCircle.Visible = false
    end
end

function Aimbot:Start() end

function Aimbot:Update(dt)
    if not self.enabled and not self.silent then
        self.target:setTarget(nil)
        return
    end
    local cam = self.camera:getCamera()
    local char = self.character:getCharacter()
    if not cam or not char then return end

    local positions = {}
    local plrs = self.players:getPlayers()
    local localPlr = self.players:getLocalPlayer()
    local camPos = self.camera:getPosition()

    for _, plr in ipairs(plrs) do
        if plr ~= localPlr and plr.Character then
            local hum = plr.Character:FindFirstChildOfClass("Humanoid")
            if hum and hum.Health > 0 then
                local part = plr.Character:FindFirstChild("Head") or plr.Character:FindFirstChild("HumanoidRootPart")
                if part then
                    self.predictor:store(part)
                    local predicted = self.predictor:compute(part, camPos)
                    if self.visibility:check(cam, char, predicted, part) then
                        positions[plr] = predicted
                    else
                        local bt = self.predictor:getBacktrack(part, 0.2, function(p, h) return self.visibility:check(cam, char, p, h) end)
                        if bt ~= part.Position and self.visibility:check(cam, char, bt, part) then
                            positions[plr] = bt
                        end
                    end
                end
            end
        end
    end

    local final = self.selector:select(cam, plrs, localPlr, positions)
    if final then final.timestamp = os.clock() end
    self.target:setTarget(final)
    if self.enabled and final then self.controller:apply(cam, final.position, dt) end
end

function Aimbot:Render(dt)
    if self.fovCircle then
        if self.enabled or self.silent then
            local v = self.camera:getViewport()
            self.fovCircle.Position = v * 0.5
            self.fovCircle.Radius = self.selector.fov
            self.fovCircle.Color = self.silent and Color3.fromRGB(255,80,80) or Color3.fromRGB(0,255,100)
            self.fovCircle.Visible = true
        else
            self.fovCircle.Visible = false
        end
    end
end

function Aimbot:Stop() end
function Aimbot:Destroy()
    if self.fovCircle then pcall(function() self.fovCircle:Remove() end) end
    table.clear(self.predictor.velEMA)
    table.clear(self.predictor.velTS)
    table.clear(self.predictor.btHistory)
end

return Aimbot
