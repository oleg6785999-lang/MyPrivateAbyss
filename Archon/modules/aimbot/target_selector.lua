local TargetSelector = {}
TargetSelector.__index = TargetSelector

local mathHuge  = math.huge
local mathClamp = math.clamp
local mathAbs   = math.abs
local Vector2New = Vector2.new

function TargetSelector.new()
    return setmetatable({
        fov            = 120,
        hysteresis     = true,
        hysteresisMult = 1.3,
        mode           = "Score",  -- "Score" or "Distance"
        prevPlayer     = nil,
        prevScore      = -mathHuge
    }, TargetSelector)
end

function TargetSelector:setFov(v) self.fov = v end
function TargetSelector:setHysteresis(v) self.hysteresis = v end
function TargetSelector:setHysteresisMult(v) self.hysteresisMult = v end
function TargetSelector:setMode(v) self.mode = v end

local function isEnemy(localPlr, plr, onlyEnemies)
    if not onlyEnemies then return true end
    local mine, theirs = localPlr.Team, plr.Team
    if not mine or not theirs then return true end
    if localPlr.Neutral or plr.Neutral then return true end
    return theirs ~= mine
end

local function computeScore(plr, char, part, screenDist, fov, dist3D, visible, speed, resolverActive)
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    local hpPct = (hum and hum.MaxHealth > 0) and (hum.Health / hum.MaxHealth) or 1
    if hpPct < 0.05 then hpPct = 0.05 end
    local healthMult = 1 + (1 - hpPct) * 0.5

    local velBonus = 1
    if speed and speed > 5 then
        velBonus = mathClamp(0.6 + speed / 90, 0.6, 1.4)
    end
    local visScore = visible and 2 or 0.5
    local resConf = resolverActive and 1.15 or 1
    local distScore = 1 / (dist3D + 1)
    local angScore  = fov / (screenDist + 0.01)
    return distScore * angScore * healthMult * velBonus * visScore * resConf
end

-- positions[plr] = { pos = Vector3, part = BasePart, visible = bool, speed = number, resolverActive = bool, dist3D = number }
function TargetSelector:select(camera, players, localPlayer, positions, onlyEnemies)
    if not camera then return nil end
    local vp = camera.ViewportSize
    local center = Vector2New(vp.X * 0.5, vp.Y * 0.5)
    local hystFov = self.fov * self.hysteresisMult

    local best, bestKey       = nil, -mathHuge
    local prevEntry, prevKey  = nil, -mathHuge

    local useScore = self.mode ~= "Distance"

    for _, plr in ipairs(players) do
        if plr ~= localPlayer then
            local data = positions[plr]
            if data and isEnemy(localPlayer, plr, onlyEnemies) then
                local sp, on = camera:WorldToViewportPoint(data.pos)
                if on and sp.Z > 0 then
                    local scr = Vector2New(sp.X, sp.Y)
                    local d = (scr - center).Magnitude
                    local inBase = (d <= self.fov)
                    local inHyst = (plr == self.prevPlayer and d <= hystFov)
                    if inBase or inHyst then
                        local key
                        if useScore then
                            key = computeScore(plr, plr.Character, data.part, d, self.fov, data.dist3D or d, data.visible, data.speed, data.resolverActive)
                        else
                            key = -d  -- distance: smaller is better → invert sign for "higher is better"
                        end
                        local entry = {
                            player = plr, position = data.pos, part = data.part,
                            screen = scr, distance = d, dist3D = data.dist3D or d,
                            visible = data.visible, speed = data.speed,
                            score = useScore and key or nil
                        }
                        if inHyst and plr == self.prevPlayer and key > prevKey then
                            prevEntry, prevKey = entry, key
                        elseif inBase and key > bestKey then
                            best, bestKey = entry, key
                        end
                    end
                end
            end
        end
    end

    local final
    if self.hysteresis and prevEntry and best and prevEntry.player ~= best.player then
        -- new must be 18% better to switch
        if bestKey > prevKey * 1.18 then final = best
        else final = prevEntry end
    else
        final = best or prevEntry
    end

    self.prevPlayer = final and final.player or nil
    self.prevScore  = final and (final.score or -final.distance) or -mathHuge
    return final
end

return TargetSelector