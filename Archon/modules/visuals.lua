local Visuals = {}
Visuals.__index = Visuals

function Visuals.new()
    return setmetatable({
        enabled = false, boxes = false, healthBar = false, snaplines = false,
        chams = false, showNames = false, showDist = false, showHealth = false,
        snapFromBottom = true, chamsOutline = true, teamColor = true,
        maxDist = 500, txtSize = 13, boxThk = 1, fillT = 0.4, outlT = 0.2,
        pool = {}, free = setmetatable({}, {__mode="k"}), entries = {}, events = nil
    }, Visuals)
end

function Visuals:setEnabled(v) self.enabled = v end
function Visuals:setBoxes(v) self.boxes = v end
function Visuals:setHealthBar(v) self.healthBar = v end
function Visuals:setSnaplines(v) self.snaplines = v end
function Visuals:setChams(v) self.chams = v end
function Visuals:setShowNames(v) self.showNames = v end
function Visuals:setShowDist(v) self.showDist = v end
function Visuals:setShowHealth(v) self.showHealth = v end
function Visuals:setSnapFromBottom(v) self.snapFromBottom = v end
function Visuals:setChamsOutline(v) self.chamsOutline = v end
function Visuals:setTeamColor(v) self.teamColor = v end
function Visuals:setMaxDist(v) self.maxDist = v end
function Visuals:setTxtSize(v) self.txtSize = v end
function Visuals:setBoxThk(v) self.boxThk = v end
function Visuals:setFillT(v) self.fillT = v end
function Visuals:setOutlT(v) self.outlT = v end

function Visuals:Init(di, events)
    self.events = events
    self.camera = di:resolve("CameraService")
    self.players = di:resolve("PlayerService")
    self.target = di:resolve("TargetService")
    local cfg = di:resolve("ConfigService")
    cfg:bind(self, "ESP.Enabled", "enabled")
    cfg:bind(self, "ESP.Boxes", "boxes")
    cfg:bind(self, "ESP.HealthBar", "healthBar")
    cfg:bind(self, "ESP.Snaplines", "snaplines")
    cfg:bind(self, "ESP.Chams", "chams")
    cfg:bind(self, "ESP.ShowNames", "showNames")
    cfg:bind(self, "ESP.ShowDistance", "showDist")
    cfg:bind(self, "ESP.ShowHealth", "showHealth")
    cfg:bind(self, "ESP.SnapFromBottom", "snapFromBottom")
    cfg:bind(self, "ESP.ChamsOutline", "chamsOutline")
    cfg:bind(self, "ESP.TeamColor", "teamColor")
    cfg:bind(self, "ESP.MaxDistance", "maxDist")
    cfg:bind(self, "ESP.TextSize", "txtSize")
    cfg:bind(self, "ESP.BoxThickness", "boxThk")
    cfg:bind(self, "ESP.ChamsFillTransparency", "fillT")
    cfg:bind(self, "ESP.ChamsOutlineTransparency", "outlT")
end

function Visuals:Start() end
function Visuals:Update(dt) end

function Visuals:Render(dt)
    if not self.enabled then
        for plr in pairs(self.entries) do self:hideEntry(plr) end
        return
    end
    local cam = self.camera:getCamera()
    if not cam then return end
    local vp = cam.ViewportSize
    local camPos = self.camera:getPosition()
    local snapBase = self.snapFromBottom and Vector2.new(vp.X*0.5, vp.Y) or Vector2.new(vp.X*0.5, vp.Y*0.5)
    local localPlr = self.players:getLocalPlayer()
    for _, plr in ipairs(self.players:getPlayers()) do
        if plr ~= localPlr and plr.Character then
            local hum = plr.Character:FindFirstChildOfClass("Humanoid")
            local root = plr.Character:FindFirstChild("HumanoidRootPart")
            if hum and hum.Health > 0 and root then
                local dist = (root.Position - camPos).Magnitude
                if dist <= self.maxDist then
                    local head = plr.Character:FindFirstChild("Head")
                    local headPos = head and head.Position or root.Position + Vector3.new(0,2.5,0)
                    local legPos = root.Position - Vector3.new(0,2.5,0)
                    local hSp, hOn = cam:WorldToViewportPoint(headPos)
                    local lSp, lOn = cam:WorldToViewportPoint(legPos)
                    if hSp.Z > 0 and lSp.Z > 0 and (hOn or lOn) then
                        local h = math.abs(lSp.Y - hSp.Y)
                        local w = h * 0.5
                        local x, y = hSp.X - w*0.5, hSp.Y
                        local enemy = true
                        if self.teamColor and localPlr.Team and plr.Team and not localPlr.Neutral and not plr.Neutral then
                            enemy = plr.Team ~= localPlr.Team
                        end
                        local col = enemy and Color3.fromRGB(255,60,60) or Color3.fromRGB(60,140,255)
                        local e = self.entries[plr] or {}; self.entries[plr] = e
                        if self.boxes then
                            e.box = e.box or self:acquire("Square")
                            if e.box then e.box.Filled=false; e.box.Color=col; e.box.Thickness=self.boxThk; e.box.Size=Vector2.new(w,h); e.box.Position=Vector2.new(x,y); e.box.Visible=true end
                        elseif e.box then self:release(e.box); e.box=nil end
                        if self.healthBar and hum.MaxHealth > 0 then
                            e.hpBg = e.hpBg or self:acquire("Square")
                            e.hpFill = e.hpFill or self:acquire("Square")
                            local pct = math.clamp(hum.Health/hum.MaxHealth,0,1)
                            if e.hpBg then e.hpBg.Filled=true; e.hpBg.Color=Color3.new(0,0,0); e.hpBg.Size=Vector2.new(3,h); e.hpBg.Position=Vector2.new(x-5,y); e.hpBg.Visible=true end
                            if e.hpFill then local bH=h*pct; e.hpFill.Filled=true; e.hpFill.Color=Color3.fromRGB(60,220,60):Lerp(Color3.fromRGB(220,60,60),1-pct); e.hpFill.Size=Vector2.new(3,bH); e.hpFill.Position=Vector2.new(x-5,y+(h-bH)); e.hpFill.Visible=true end
                        else
                            if e.hpBg then self:release(e.hpBg); e.hpBg=nil end
                            if e.hpFill then self:release(e.hpFill); e.hpFill=nil end
                        end
                        if self.snaplines then
                            e.snapline = e.snapline or self:acquire("Line")
                            if e.snapline then e.snapline.Color=col; e.snapline.Thickness=1; e.snapline.From=snapBase; e.snapline.To=Vector2.new(hSp.X,hSp.Y); e.snapline.Visible=true end
                        elseif e.snapline then self:release(e.snapline); e.snapline=nil end
                        local labelY, botY = y - self.txtSize - 2, y + h + 2
                        if self.showNames then
                            e.nameText = e.nameText or self:acquire("Text")
                            if e.nameText then local nm=plr.DisplayName~="" and plr.DisplayName or plr.Name; e.nameText.Text=nm; e.nameText.Position=Vector2.new(hSp.X,labelY); e.nameText.Color=col; e.nameText.Size=self.txtSize; e.nameText.Outline=true; e.nameText.OutlineColor=Color3.new(0,0,0); e.nameText.Center=true; e.nameText.Visible=true; pcall(function() e.nameText.Font=0 end) end
                        elseif e.nameText then self:release(e.nameText); e.nameText=nil end
                        if self.showDist then
                            e.distText = e.distText or self:acquire("Text")
                            if e.distText then e.distText.Text=string.format("%dm",math.floor(dist)); e.distText.Position=Vector2.new(hSp.X,botY); e.distText.Color=Color3.new(1,1,1); e.distText.Size=self.txtSize; e.distText.Outline=true; e.distText.OutlineColor=Color3.new(0,0,0); e.distText.Center=true; e.distText.Visible=true; pcall(function() e.distText.Font=0 end) end
                        elseif e.distText then self:release(e.distText); e.distText=nil end
                        if self.showHealth and hum.MaxHealth > 0 then
                            e.hpText = e.hpText or self:acquire("Text")
                            if e.hpText then local hpY=self.showDist and botY+self.txtSize+1 or botY; local pct=math.clamp(hum.Health/hum.MaxHealth,0,1); e.hpText.Text=string.format("%d HP",math.floor(hum.Health)); e.hpText.Position=Vector2.new(hSp.X,hpY); e.hpText.Color=Color3.fromRGB(60,220,60):Lerp(Color3.fromRGB(220,60,60),1-pct); e.hpText.Size=self.txtSize; e.hpText.Outline=true; e.hpText.OutlineColor=Color3.new(0,0,0); e.hpText.Center=true; e.hpText.Visible=true; pcall(function() e.hpText.Font=0 end) end
                        elseif e.hpText then self:release(e.hpText); e.hpText=nil end
                        if self.chams then
                            local hl = e.highlight
                            if hl and (not hl.Parent or hl.Adornee ~= plr.Character) then pcall(function() hl:Destroy() end); e.highlight=nil; hl=nil end
                            if not hl then
                                local h = Instance.new("Highlight")
                                h.Name="ARCHON_HL"; h.FillColor=col; h.OutlineColor=self.chamsOutline and Color3.new(1,1,1) or col
                                h.FillTransparency=self.fillT; h.OutlineTransparency=self.outlT
                                pcall(function() h.DepthMode=Enum.HighlightDepthMode.AlwaysOnTop end)
                                h.Adornee=plr.Character; h.Parent=plr.Character; e.highlight=h
                            else
                                hl.FillColor=col; hl.OutlineColor=self.chamsOutline and Color3.new(1,1,1) or col
                                hl.FillTransparency=self.fillT; hl.OutlineTransparency=self.outlT
                            end
                        elseif e.highlight then pcall(function() e.highlight:Destroy() end); e.highlight=nil end
                    else self:hideEntry(plr) end
                else self:hideEntry(plr) end
            else self:hideEntry(plr) end
        end
    end
end

function Visuals:Stop() end
function Visuals:Destroy()
    for plr in pairs(self.entries) do self:hideEntry(plr) end
    for _, pool in pairs(self.pool) do for i=1,#pool do pcall(function() pool[i]:Remove() end) end; table.clear(pool) end
    table.clear(self.entries)
end

function Visuals:acquire(class)
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

function Visuals:release(obj)
    if not obj then return end
    pcall(function() obj.Visible = false end)
    self.free[obj] = true
end

function Visuals:hideEntry(plr)
    local e = self.entries[plr]
    if not e then return end
    for _, k in ipairs({"box","hpBg","hpFill","snapline","nameText","distText","hpText"}) do
        if e[k] then self:release(e[k]); e[k] = nil end
    end
    if e.highlight then pcall(function() e.highlight:Destroy() end); e.highlight = nil end
end

return Visuals