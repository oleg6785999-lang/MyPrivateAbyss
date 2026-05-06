local Indicators = {}
Indicators.__index = Indicators

function Indicators.new()
    return setmetatable({
        enabled = true, pool = {}, free = setmetatable({}, {__mode="k"}),
        realArrow = nil, fakeArrow = nil, desyncBar = nil, lagText = nil, events = nil
    }, Indicators)
end

function Indicators:Init(di, events)
    self.events = events
    self.cameraService = di:resolve("CameraService")
    self.characterService = di:resolve("CharacterService")
    local cfg = di:resolve("ConfigService")
    cfg:bind(self, "AntiAim.Indicators.Enabled", "enabled")
end

function Indicators:Start() end
function Indicators:Stop() end
function Indicators:Destroy()
    for _, pool in pairs(self.pool) do for i=1,#pool do pcall(function() pool[i]:Remove() end) end; table.clear(pool) end
end

function Indicators:acquire(class)
    if type(Drawing) ~= "table" then return nil end
    local pool = self.pool[class]
    if not pool then pool = {}; self.pool[class] = pool end
    for i = 1, #pool do
        if self.free[pool[i]] then self.free[pool[i]] = false; return pool[i] end
    end
    local ok, d = pcall(Drawing.new, class)
    if not ok or not d then return nil end
    table.insert(pool, d); self.free[d] = false
    return d
end

function Indicators:release(obj)
    if not obj then return end
    pcall(function() obj.Visible = false end)
    self.free[obj] = true
end

function Indicators:draw(realYaw, fakeYaw, pitch, lagging, dt)
    if not self.enabled then self:hide(); return end
    local cam = self.cameraService:getCamera()
    local root = self.characterService:getRootPart()
    if not cam or not root then self:hide(); return end

    local headPos = root.Position + Vector3.new(0, 3, 0)
    local sp, on = cam:WorldToViewportPoint(headPos)
    if not on or sp.Z < 0 then self:hide(); return end

    local center = Vector2.new(sp.X, sp.Y)
    local len = 40

    self.realArrow = self.realArrow or self:acquire("Line")
    if self.realArrow then
        local rDir = Vector2.new(math.sin(realYaw), math.cos(realYaw)) * len
        self.realArrow.From = center
        self.realArrow.To = center + rDir
        self.realArrow.Color = Color3.fromRGB(50, 255, 50)
        self.realArrow.Thickness = 2
        self.realArrow.Visible = true
    end

    self.fakeArrow = self.fakeArrow or self:acquire("Line")
    if self.fakeArrow then
        local fDir = Vector2.new(math.sin(fakeYaw), math.cos(fakeYaw)) * len
        self.fakeArrow.From = center
        self.fakeArrow.To = center + fDir
        self.fakeArrow.Color = Color3.fromRGB(255, 50, 50)
        self.fakeArrow.Thickness = 2
        self.fakeArrow.Visible = true
    end

    self.desyncBar = self.desyncBar or self:acquire("Square")
    if self.desyncBar then
        local diff = math.abs(fakeYaw - realYaw)
        local pct = math.clamp(diff / math.pi, 0, 1)
        self.desyncBar.Size = Vector2.new(60 * pct, 4)
        self.desyncBar.Position = Vector2.new(center.X - 30, center.Y + 25)
        self.desyncBar.Color = Color3.fromRGB(255, 200, 50)
        self.desyncBar.Filled = true
        self.desyncBar.Visible = true
    end

    self.lagText = self.lagText or self:acquire("Text")
    if self.lagText then
        self.lagText.Text = lagging and "LAG" or "SYNC"
        self.lagText.Position = Vector2.new(center.X, center.Y + 35)
        self.lagText.Color = lagging and Color3.fromRGB(255, 100, 100) or Color3.fromRGB(100, 255, 100)
        self.lagText.Size = 13
        self.lagText.Center = true
        self.lagText.Outline = true
        self.lagText.Visible = true
    end
end

function Indicators:hide()
    if self.realArrow then self:release(self.realArrow); self.realArrow = nil end
    if self.fakeArrow then self:release(self.fakeArrow); self.fakeArrow = nil end
    if self.desyncBar then self:release(self.desyncBar); self.desyncBar = nil end
    if self.lagText then self:release(self.lagText); self.lagText = nil end
end

return Indicators