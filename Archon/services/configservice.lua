local ConfigService = {}
ConfigService.__index = ConfigService

function ConfigService.new()
    return setmetatable({ current = {}, events = nil, engine = nil, bindings = {} }, ConfigService)
end

function ConfigService:Init(di, events)
    self.events = events
    self.engine = di:resolve("Engine")
    self.events:subscribe("ConfigChanged", function(path, _, newVal)
        local binds = self.bindings[path]
        if binds then
            for _, b in ipairs(binds) do
                local setterName = "set" .. b.field:sub(1,1):upper() .. b.field:sub(2)
                if type(b.module[setterName]) == "function" then
                    b.module[setterName](b.module, newVal)
                else
                    b.module[b.field] = newVal
                end
            end
        end
    end, 100)
end

function ConfigService:load(cfg) self.current = self:deepCopy(cfg) end

function ConfigService:get(path)
    if not path then return self.current end
    local keys = {}
    for k in string.gmatch(path, "[^.]+") do table.insert(keys, k) end
    local node = self.current
    for _, k in ipairs(keys) do
        if type(node) ~= "table" then return nil end
        node = node[k]
    end
    return node
end

function ConfigService:bind(module, path, field)
    if not self.bindings[path] then self.bindings[path] = {} end
    table.insert(self.bindings[path], { module = module, field = field })
    local val = self:get(path)
    local setterName = "set" .. field:sub(1,1):upper() .. field:sub(2)
    if type(module[setterName]) == "function" then
        module[setterName](module, val)
    else
        module[field] = val
    end
end

function ConfigService:deepCopy(t)
    if type(t) ~= "table" then return t end
    local copy = {}
    for k, v in pairs(t) do copy[k] = self:deepCopy(v) end
    return copy
end

function ConfigService:computeDiff(old, new, path, changes)
    changes = changes or { safe = {}, breaking = {} }
    path = path or ""
    local visited = {}
    for k in pairs(old) do visited[k] = true end
    for k in pairs(new) do visited[k] = true end
    for k in pairs(visited) do
        local full = path == "" and k or path .. "." .. k
        local o, n = old[k], new[k]
        local ot, nt = type(o), type(n)
        if o == nil then table.insert(changes.breaking, { path = full, reason = "added" })
        elseif n == nil then table.insert(changes.breaking, { path = full, reason = "removed" })
        elseif ot ~= nt then table.insert(changes.breaking, { path = full, reason = "type_mismatch" })
        elseif ot == "table" then self:computeDiff(o, n, full, changes)
        elseif o ~= n then table.insert(changes.safe, { path = full, old = o, new = n }) end
    end
    return changes
end

function ConfigService:setByPath(t, path, val)
    local keys = {}
    for k in string.gmatch(path, "[^.]+") do table.insert(keys, k) end
    local node = t
    for i = 1, #keys - 1 do
        node = node[keys[i]]
        if type(node) ~= "table" then return false end
    end
    node[keys[#keys]] = val
    return true
end

function ConfigService:apply(newCfg)
    if newCfg.version and newCfg.version ~= (self.current.version or 1) then
        self:triggerReboot(newCfg); return
    end
    local diff = self:computeDiff(self.current, newCfg)
    if #diff.breaking > 0 then self:triggerReboot(newCfg); return end
    for _, change in ipairs(diff.safe) do
        self:setByPath(self.current, change.path, change.new)
        self.events:publish("ConfigChanged", change.path, change.old, change.new)
    end
end

function ConfigService:triggerReboot(newCfg)
    local eng, ev, nextCfg = self.engine, self.events, self:deepCopy(newCfg)
    task.defer(function()
        eng:stop()
        self.current = nextCfg
        eng:start()
        ev:publish("ConfigRebooted", self.current)
    end)
end

function ConfigService:Start() end
function ConfigService:Update() end
function ConfigService:Stop() end
function ConfigService:Destroy() self.current = nil; table.clear(self.bindings) end

return ConfigService