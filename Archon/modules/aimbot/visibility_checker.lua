local VisibilityChecker = {}
VisibilityChecker.__index = VisibilityChecker

function VisibilityChecker.new()
    return setmetatable({ wallCheck = true, raycastService = nil }, VisibilityChecker)
end

function VisibilityChecker:setWallCheck(v) self.wallCheck = v end

function VisibilityChecker:check(camera, character, pos, hitPart)
    if not self.wallCheck then return true end
    if not camera then return false end
    local ignore = {camera}
    if character then table.insert(ignore, character) end
    local origin = camera.CFrame.Position
    local dir = pos - origin
    if dir.Magnitude < 0.05 then return true end
    local hit = self.raycastService:raycast(origin, dir, ignore)
    if not hit then return true end
    if hitPart and hit.Instance then
        if hit.Instance == hitPart then return true end
        local model = hitPart.Parent
        if model and hit.Instance:IsDescendantOf(model) then return true end
    end
    return false
end

return VisibilityChecker
