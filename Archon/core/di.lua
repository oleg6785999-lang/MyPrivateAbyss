local DI = {}
DI.__index = DI

function DI.new()
    return setmetatable({
        factories = {},
        instances = {},
        deps = {},
        stack = {},
        state = {}
    }, DI)
end

function DI:register(name, factory, dependencies)
    self.factories[name] = factory
    self.deps[name] = dependencies or {}
    self.state[name] = nil
end

function DI:resolve(name)
    if self.instances[name] then return self.instances[name] end
    if self.state[name] == "resolving" then error("DI: Cycle at " .. name) end
    if not self.factories[name] then error("DI: Unknown " .. name) end

    self.state[name] = "resolving"
    local proxy = setmetatable({}, {
        __index = function(_, k)
            error(string.format("DI: Missing dep '%s' in '%s'", tostring(k), name))
        end
    })
    for _, dep in ipairs(self.deps[name]) do
        proxy[dep] = self:resolve(dep)
    end

    local ok, instance = pcall(self.factories[name], proxy)
    if not ok then
        self.state[name] = nil
        error(string.format("DI: Factory failed '%s'\n%s", name, tostring(instance)))
    end

    self.state[name] = "resolved"
    self.instances[name] = instance
    table.insert(self.stack, name)
    return instance
end

-- Soft reset: keeps factories/deps for re-resolve (used on reboot)
function DI:reset()
    for i = #self.stack, 1, -1 do
        local name = self.stack[i]
        local inst = self.instances[name]
        if inst and type(inst) == "table" and type(inst.Destroy) == "function" then
            pcall(inst.Destroy, inst)
        end
    end
    table.clear(self.instances)
    table.clear(self.stack)
    table.clear(self.state)
end

-- Hard destroy: full teardown
function DI:clear()
    self:reset()
    table.clear(self.factories)
    table.clear(self.deps)
end

return DI