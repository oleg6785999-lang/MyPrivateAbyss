local EventBus = {}
EventBus.__index = EventBus

function EventBus.new()
    return setmetatable({
        registry = {},
        sorted = {},
        nextId = 1,
        dirty = {}
    }, EventBus)
end

function EventBus:subscribe(event, callback, priority, once)
    if not self.registry[event] then
        self.registry[event] = {}
        self.sorted[event] = {}
        self.dirty[event] = false
    end
    local id = self.nextId
    self.nextId = self.nextId + 1
    self.registry[event][id] = { id = id, cb = callback, priority = priority or 0, once = once or false }
    table.insert(self.sorted[event], id)
    self.dirty[event] = true
    return { event = event, id = id, bus = self }
end

function EventBus:publish(event, ...)
    local reg = self.registry[event]
    if not reg or next(reg) == nil then return end
    if self.dirty[event] then
        table.sort(self.sorted[event], function(a, b)
            local ea, eb = reg[a], reg[b]
            if ea.priority == eb.priority then return a < b end
            return ea.priority > eb.priority
        end)
        self.dirty[event] = false
    end
    local ids = self.sorted[event]
    local toRemove = {}
    for i = 1, #ids do
        local id = ids[i]
        local entry = reg[id]
        if entry then
            local ok, err = pcall(entry.cb, ...)
            if not ok then warn("[EventBus] " .. event .. ": " .. tostring(err)) end
            if entry.once then table.insert(toRemove, id) end
        end
    end
    for _, id in ipairs(toRemove) do
        reg[id] = nil
        self.dirty[event] = true
    end
end

function EventBus:unsubscribe(conn)
    if conn and conn.bus and conn.bus.registry[conn.event] then
        conn.bus.registry[conn.event][conn.id] = nil
        conn.bus.dirty[conn.event] = true
    end
end

function EventBus:clear()
    table.clear(self.registry)
    table.clear(self.sorted)
    table.clear(self.dirty)
end

return EventBus