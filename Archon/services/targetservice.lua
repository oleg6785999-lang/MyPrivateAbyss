local TargetService = {}
TargetService.__index = TargetService

function TargetService.new()
    return setmetatable({
        current = nil,
        currentPlayer = nil,
        events = nil
    }, TargetService)
end

function TargetService:Init(_, events) self.events = events end

function TargetService:setTarget(target)
    local newPlr = target and target.player or nil
    -- Always update payload (position changes every frame)
    self.current = target
    if newPlr ~= self.currentPlayer then
        self.currentPlayer = newPlr
        if self.events then self.events:publish("TargetChanged", target, newPlr) end
    end
end

function TargetService:getTarget() return self.current end
function TargetService:getTargetPlayer() return self.currentPlayer end

function TargetService:Start() end
function TargetService:Update() end
function TargetService:Stop() end
function TargetService:Destroy()
    self.current = nil
    self.currentPlayer = nil
end

return TargetService