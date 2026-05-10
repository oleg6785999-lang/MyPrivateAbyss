local SilentAim = {}
SilentAim.__index = SilentAim

function SilentAim.new()
    return setmetatable({
        enabled = false,
        hitChance = 100,
        fov = 180,
        target = nil
    }, SilentAim)
end

function SilentAim:Init(di, events)
    self.events = events
    self.targetService = di:resolve("TargetService")
    self.characterService = di:resolve("CharacterService")
    self.raycastService = di:resolve("RaycastService")
    
    local cfg = di:resolve("ConfigService")
    cfg:bind(self, "SilentAim.Enabled", "enabled")
    cfg:bind(self, "SilentAim.HitChance", "hitChance")
    cfg:bind(self, "SilentAim.FOV", "fov")
end

function SilentAim:Start() end

function SilentAim:Update(dt)
    if not self.enabled then return end
    -- Пока заглушка, позже сделаем полноценный silent
end

function SilentAim:Render(dt) end
function SilentAim:Stop() end
function SilentAim:Destroy() end

return SilentAim
