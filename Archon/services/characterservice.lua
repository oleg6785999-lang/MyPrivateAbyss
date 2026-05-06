local Players = game:GetService("Players")
local CharacterService = {}
CharacterService.__index = CharacterService

function CharacterService.new()
    return setmetatable({
        character = nil,
        humanoid = nil,
        rootPart = nil,
        connections = {},
        events = nil
    }, CharacterService)
end

function CharacterService:Init(_, events)
    self.events = events
    local lp = Players.LocalPlayer
    local function scan(char)
        self.character = char
        self.humanoid = char and char:FindFirstChildOfClass("Humanoid") or nil
        self.rootPart = char and char:FindFirstChild("HumanoidRootPart") or nil
        if self.events then self.events:publish("CharacterSpawned", char, self.humanoid, self.rootPart) end
    end
    if lp.Character then scan(lp.Character) end
    table.insert(self.connections, lp.CharacterAdded:Connect(scan))
    table.insert(self.connections, lp.CharacterRemoving:Connect(function()
        self.character = nil; self.humanoid = nil; self.rootPart = nil
        if self.events then self.events:publish("CharacterRemoved") end
    end))
end

function CharacterService:getCharacter() return self.character end
function CharacterService:getHumanoid() return self.humanoid end
function CharacterService:getRootPart() return self.rootPart end

function CharacterService:Start() end
function CharacterService:Update() end
function CharacterService:Stop() end
function CharacterService:Destroy()
    for _, c in ipairs(self.connections) do if c.Connected then c:Disconnect() end end
    table.clear(self.connections)
end

return CharacterService