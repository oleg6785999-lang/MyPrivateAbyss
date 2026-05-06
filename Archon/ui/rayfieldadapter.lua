local UIAdapter = require(script.Parent.uiadapter)
local RayfieldAdapter = setmetatable({}, {__index = UIAdapter})
RayfieldAdapter.__index = RayfieldAdapter

function RayfieldAdapter.new()
    return setmetatable({lib = nil, window = nil, elements = {}}, RayfieldAdapter)
end

function RayfieldAdapter:init(lib)
    self.lib = lib
end

function RayfieldAdapter:createWindow(cfg)
    local ok, win = pcall(self.lib.CreateWindow, self.lib, cfg)
    if ok then self.window = win end
    return ok and win or nil
end

function RayfieldAdapter:createTab(win, name, icon)
    if not win then return nil end
    local ok, tab = pcall(win.CreateTab, win, name, icon)
    return ok and tab or nil
end

function RayfieldAdapter:createToggle(tab, cfg)
    if not tab then return nil end
    local ok, el = pcall(tab.CreateToggle, tab, cfg)
    if ok and el then table.insert(self.elements, el) end
    return ok and el or nil
end

function RayfieldAdapter:createSlider(tab, cfg)
    if not tab then return nil end
    local ok, el = pcall(tab.CreateSlider, tab, cfg)
    if ok and el then table.insert(self.elements, el) end
    return ok and el or nil
end

function RayfieldAdapter:createDropdown(tab, cfg)
    if not tab then return nil end
    local ok, el = pcall(tab.CreateDropdown, tab, cfg)
    if ok and el then table.insert(self.elements, el) end
    return ok and el or nil
end

function RayfieldAdapter:loadConfig()
    if self.lib then pcall(self.lib.LoadConfiguration, self.lib) end
end

function RayfieldAdapter:notify(cfg)
    if self.lib then pcall(self.lib.Notify, self.lib, cfg) end
end

function RayfieldAdapter:destroy()
    self.lib = nil
    self.window = nil
    table.clear(self.elements)
end

return RayfieldAdapter