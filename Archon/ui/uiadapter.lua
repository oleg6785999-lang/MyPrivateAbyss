local UIAdapter = {}
UIAdapter.__index = UIAdapter

function UIAdapter.new()
    return setmetatable({}, UIAdapter)
end

function UIAdapter:init(lib) error("Not implemented") end
function UIAdapter:createWindow(cfg) error("Not implemented") end
function UIAdapter:createTab(win, name, icon) error("Not implemented") end
function UIAdapter:createToggle(tab, cfg) error("Not implemented") end
function UIAdapter:createSlider(tab, cfg) error("Not implemented") end
function UIAdapter:createDropdown(tab, cfg) error("Not implemented") end
function UIAdapter:loadConfig() error("Not implemented") end
function UIAdapter:notify(cfg) error("Not implemented") end
function UIAdapter:destroy() error("Not implemented") end

return UIAdapter