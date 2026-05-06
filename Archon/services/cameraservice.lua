local Workspace = game:GetService("Workspace")
local CameraService = {}
CameraService.__index = CameraService

function CameraService.new()
    return setmetatable({
        camera = Workspace.CurrentCamera,
        connections = {},
        events = nil
    }, CameraService)
end

function CameraService:Init(_, events)
    self.events = events
    table.insert(self.connections, Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
        local old = self.camera
        self.camera = Workspace.CurrentCamera
        if self.events and old ~= self.camera then self.events:publish("CameraChanged", self.camera) end
    end))
end

function CameraService:getCamera() return self.camera end
function CameraService:getViewport() return self.camera and self.camera.ViewportSize or Vector2.new(0,0) end
function CameraService:getPosition() return self.camera and self.camera.CFrame.Position or Vector3.new(0,0,0) end
function CameraService:getCFrame() return self.camera and self.camera.CFrame or CFrame.new() end

function CameraService:Start() end
function CameraService:Update() end
function CameraService:Stop() end
function CameraService:Destroy()
    for _, c in ipairs(self.connections) do if c.Connected then c:Disconnect() end end
    table.clear(self.connections)
end

return CameraService