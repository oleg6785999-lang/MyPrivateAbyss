local Scheduler = {}
Scheduler.__index = Scheduler

function Scheduler.new()
    return setmetatable({
        phases = {
            FixedUpdate = {},
            PreUpdate = {},
            Update = {},
            LateUpdate = {},
            Render = {}
        },
        fixedDt = 1 / 60,
        acc = 0,
        maxSteps = 5
    }, Scheduler)
end

function Scheduler:register(name, instance, phaseConfig)
    for phase, priority in pairs(phaseConfig) do
        if self.phases[phase] then
            table.insert(self.phases[phase], { name = name, instance = instance, priority = priority or 0 })
            table.sort(self.phases[phase], function(a, b)
                if a.priority == b.priority then return a.name < b.name end
                return a.priority > b.priority
            end)
        end
    end
end

function Scheduler:runPhase(phase, dt)
    local list = self.phases[phase]
    if not list then return end
    for _, entry in ipairs(list) do
        if entry.instance and type(entry.instance[phase]) == "function" then
            local ok, err = pcall(entry.instance[phase], entry.instance, dt)
            if not ok then warn("[Scheduler] " .. phase .. " " .. entry.name .. ": " .. tostring(err)) end
        end
    end
end

function Scheduler:tick(dt)
    self.acc = self.acc + dt
    local steps = 0
    while self.acc >= self.fixedDt and steps < self.maxSteps do
        self.acc = self.acc - self.fixedDt
        self:runPhase("FixedUpdate", self.fixedDt)
        steps = steps + 1
    end
    if self.acc > self.fixedDt * self.maxSteps then self.acc = 0 end
    self:runPhase("PreUpdate", dt)
    self:runPhase("Update", dt)
    self:runPhase("LateUpdate", dt)
end

function Scheduler:render(dt)
    self:runPhase("Render", dt)
end

function Scheduler:clear()
    for phase in pairs(self.phases) do table.clear(self.phases[phase]) end
    self.acc = 0
end

return Scheduler