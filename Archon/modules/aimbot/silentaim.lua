local SilentAim = {}
SilentAim.__index = SilentAim

function SilentAim.new()
    return setmetatable({
        enabled = false,
        hitChance = 100,
    }, SilentAim)
end

function SilentAim:Init(di, events)
    self.events = events
    local cfg = di:resolve("ConfigService")
    cfg:bind(self, "SilentAim.Enabled", "enabled")
    cfg:bind(self, "SilentAim.HitChance", "hitChance")
end

function SilentAim:Start() end
function SilentAim:Update() end
function SilentAim:Render() end
function SilentAim:Stop() end
function SilentAim:Destroy() end

return SilentAim
