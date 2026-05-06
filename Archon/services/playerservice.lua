local Players = game:GetService("Players")
local PlayerService = {}
PlayerService.__index = PlayerService

function PlayerService.new()
    return setmetatable({
        cache = {},
        list = {},
        localPlayer = Players.LocalPlayer,
        connections = {},
        events = nil
    }, PlayerService)
end

function PlayerService:Init(_, events)
    self.events = events
    for _, p in ipairs(Players:GetPlayers()) do self.cache[p] = true end
    table.insert(self.connections, Players.PlayerAdded:Connect(function(p)
        self.cache[p] = true
        if self.events then self.events:publish("PlayerAdded", p) end
    end))
    table.insert(self.connections, Players.PlayerRemoving:Connect(function(p)
        self.cache[p] = nil
        if self.events then self.events:publish("PlayerRemoved", p) end
    end))
end

function PlayerService:getPlayers()
    table.clear(self.list)
    for p in pairs(self.cache) do table.insert(self.list, p) end
    return self.list
end

function PlayerService:getLocalPlayer() return self.localPlayer end

function PlayerService:Start() end
function PlayerService:Update() end
function PlayerService:Stop() end
function PlayerService:Destroy()
    for _, c in ipairs(self.connections) do if c.Connected then c:Disconnect() end end
    table.clear(self.connections)
    table.clear(self.cache)
    table.clear(self.list)
end

return PlayerService