local RunService = game:GetService("RunService")
local DI = require(script.Parent.di)
local EventBus = require(script.Parent.eventbus)
local Scheduler = require(script.Parent.scheduler)

local Engine = {}
Engine.__index = Engine

function Engine.new()
    local self = setmetatable({}, Engine)
    self.di = DI.new()
    self.events = EventBus.new()
    self.scheduler = Scheduler.new()
    self.running = false
    self.heartbeatConn = nil
    self.renderConn = nil
    self.moduleConfigs = {}
    self.moduleOrder = {}  -- deterministic Init/Start order

    self.di:register("Engine", function() return self end, {})
    self.di:register("EventBus", function() return self.events end, {})
    self.di:register("Scheduler", function() return self.scheduler end, {})

    return self
end

function Engine:registerModule(name, factory, dependencies, phaseConfig)
    self.di:register(name, factory, dependencies)
    self.moduleConfigs[name] = phaseConfig or {}
    self.moduleOrder[#self.moduleOrder + 1] = name
end

function Engine:start()
    if self.running then return end
    self.running = true

    -- Deterministic Init order (registration order)
    for _, name in ipairs(self.moduleOrder) do
        local ok, inst = pcall(self.di.resolve, self.di, name)
        if ok and type(inst) == "table" then
            if type(inst.Init) == "function" then
                local initOk, err = pcall(inst.Init, inst, self.di, self.events)
                if not initOk then warn("[Engine] Init failed " .. name .. ": " .. tostring(err)) end
            end
            self.scheduler:register(name, inst, self.moduleConfigs[name] or {})
        else
            warn("[Engine] Resolve failed " .. name .. ": " .. tostring(inst))
        end
    end

    for _, name in ipairs(self.moduleOrder) do
        local inst = self.di.instances[name]
        if inst and type(inst.Start) == "function" then
            local ok, err = pcall(inst.Start, inst)
            if not ok then warn("[Engine] Start failed " .. name .. ": " .. tostring(err)) end
        end
    end

    self.heartbeatConn = RunService.Heartbeat:Connect(function(dt) self:heartbeat(dt) end)
    self.renderConn = RunService.RenderStepped:Connect(function(dt) self.scheduler:render(dt) end)
end

function Engine:heartbeat(dt)
    if not self.running then return end
    self.scheduler:tick(dt)
end

function Engine:stop()
    if not self.running then return end
    self.running = false

    if self.heartbeatConn then self.heartbeatConn:Disconnect(); self.heartbeatConn = nil end
    if self.renderConn then self.renderConn:Disconnect(); self.renderConn = nil end

    -- reverse order Stop → Destroy
    for i = #self.di.stack, 1, -1 do
        local name = self.di.stack[i]
        local inst = self.di.instances[name]
        if inst and type(inst.Stop) == "function" then
            local ok, err = pcall(inst.Stop, inst)
            if not ok then warn("[Engine] Stop failed " .. name .. ": " .. tostring(err)) end
        end
    end

    self.scheduler:clear()
    self.events:clear()
    -- soft reset: instances+state cleared, factories/deps preserved → reboot works
    self.di:reset()
end

-- Full teardown (used on script shutdown). Cannot be re-started.
function Engine:destroy()
    self:stop()
    self.di:clear()
    table.clear(self.moduleConfigs)
    table.clear(self.moduleOrder)
end

return Engine