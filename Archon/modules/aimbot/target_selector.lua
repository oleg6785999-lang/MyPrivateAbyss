local TargetSelector = {}
TargetSelector.__index = TargetSelector

function TargetSelector.new()
    return setmetatable({ fov = 120, hysteresis = true, hysteresisMult = 1.3, prevPlayer = nil }, TargetSelector)
end

function TargetSelector:setFov(v) self.fov = v end
function TargetSelector:setHysteresis(v) self.hysteresis = v end
function TargetSelector:setHysteresisMult(v) self.hysteresisMult = v end

function TargetSelector:select(camera, players, localPlayer, positions)
    if not camera then return nil end
    local vp = camera.ViewportSize
    local center = Vector2.new(vp.X * 0.5, vp.Y * 0.5)
    local best, bestDist = nil, self.fov
    local prevEntry = nil
    local hystFov = self.fov * self.hysteresisMult

    for _, plr in ipairs(players) do
        if plr ~= localPlayer and positions[plr] then
            local pos = positions[plr]
            local sp, on = camera:WorldToViewportPoint(pos)
            if on and sp.Z > 0 then
                local scr = Vector2.new(sp.X, sp.Y)
                local d = (scr - center).Magnitude
                local entry = { player = plr, position = pos, screen = scr, distance = d }
                if plr == self.prevPlayer and d <= hystFov then prevEntry = entry end
                if d <= self.fov and d < bestDist then bestDist = d; best = entry end
            end
        end
    end

    local final
    if self.hysteresis and prevEntry and best and prevEntry.player ~= best.player then
        final = best.distance < prevEntry.distance * 0.85 and best or prevEntry
    else
        final = best or prevEntry
    end
    self.prevPlayer = final and final.player or nil
    return final
end

return TargetSelector
