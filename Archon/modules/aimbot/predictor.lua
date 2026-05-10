local Predictor = {}
Predictor.__index = Predictor

function Predictor.new()
    return setmetatable({
        prediction = 0.12, hitboxOffset = 0, predictGravity = false,
        backtrack = false, bulletVel = 0,
        velEMA = setmetatable({}, {__mode="k"}),
        velTS = setmetatable({}, {__mode="k"}),
        btHistory = setmetatable({}, {__mode="k"})
    }, Predictor)
end

function Predictor:setPrediction(v) self.prediction = v end
function Predictor:setHitboxOffset(v) self.hitboxOffset = v end
function Predictor:setPredictGravity(v) self.predictGravity = v end
function Predictor:setBacktrack(v) self.backtrack = v end
function Predictor:setBulletVel(v) self.bulletVel = v end

function Predictor:store(part)
    if not self.backtrack then return end
    local hist = self.btHistory[part]
    if not hist then hist = {}; self.btHistory[part] = hist end
    hist[#hist+1] = {pos=part.Position, t=os.clock()}
    while #hist > 16 do table.remove(hist, 1) end
end

function Predictor:getBacktrack(part, maxAge, visibilityCheck)
    if not self.backtrack then return part.Position end
    local hist = self.btHistory[part]
    if not hist or #hist == 0 then return part.Position end
    local now = os.clock()
    for i = #hist, 1, -1 do
        if now - hist[i].t > maxAge then break end
        if visibilityCheck(hist[i].pos, part) then return hist[i].pos end
    end
    return part.Position
end

function Predictor:compute(part, cameraPos)
    local vel = part.AssemblyLinearVelocity
    if typeof(vel) ~= "Vector3" then vel = Vector3.zero end
    if vel.Magnitude > 500 then vel = vel.Unit * 500 end
    local dist = (part.Position - cameraPos).Magnitude
    local t = math.clamp(self.prediction * (1 + dist / 300), 0, 0.5)
    if self.bulletVel > 0 then t = math.clamp(t + dist / self.bulletVel, 0, 0.5) end
    local lead = vel * t
    if lead.Magnitude > 35 then lead = lead.Unit * 35 end
    local pos = part.Position + lead
    if self.predictGravity and t > 0 then pos = pos + Vector3.new(0, 0.5 * -workspace.Gravity * t * t, 0) end
    if self.hitboxOffset ~= 0 then pos = pos + Vector3.new(0, self.hitboxOffset, 0) end
    return pos
end

return Predictor
