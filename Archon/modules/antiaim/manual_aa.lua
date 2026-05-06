local UserInputService = game:GetService("UserInputService")
local ManualAA = {}
ManualAA.__index = ManualAA

function ManualAA.new()
    return setmetatable({enabled = false, left = false, right = false, back = false, angle = 0, events = nil}, ManualAA)
end

function ManualAA:setEnabled(v) self.enabled = v end

function ManualAA:Init(di, events)
    self.events = events
    local cfg = di:resolve("ConfigService")
    cfg:bind(self, "AntiAim.Manual.Enabled", "enabled")
    self.conn = UserInputService.InputBegan:Connect(function(input, gpe)
        if gpe or not self.enabled then return end
        if input.KeyCode == Enum.KeyCode.Left then self.left = true; self.right = false; self.back = false
        elseif input.KeyCode == Enum.KeyCode.Right then self.right = true; self.left = false; self.back = false
        elseif input.KeyCode == Enum.KeyCode.Down then self.back = true; self.left = false; self.right = false
        end
    end)
    self.conn2 = UserInputService.InputEnded:Connect(function(input, gpe)
        if gpe then return end
        if input.KeyCode == Enum.KeyCode.Left then self.left = false
        elseif input.KeyCode == Enum.KeyCode.Right then self.right = false
        elseif input.KeyCode == Enum.KeyCode.Down then self.back = false
        end
    end)
end

function ManualAA:Start() end
function ManualAA:Stop() end
function ManualAA:Destroy()
    if self.conn then self.conn:Disconnect() end
    if self.conn2 then self.conn2:Disconnect() end
end

function ManualAA:getAngle()
    if not self.enabled then return 0 end
    if self.left then return math.rad(90)
    elseif self.right then return math.rad(-90)
    elseif self.back then return math.rad(180)
    end
    return 0
end

return ManualAA