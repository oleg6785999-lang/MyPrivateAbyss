local Engine          = require(script.core.engine)
local PlayerService   = require(script.services.playerservice)
local CameraService   = require(script.services.cameraservice)
local CharacterService = require(script.services.characterservice)
local TargetService   = require(script.services.targetservice)
local RaycastService  = require(script.services.raycastservice)
local ConfigService   = require(script.services.configservice)
local Aimbot          = require(script.modules.aimbot.orchestrator)
local SilentAim       = require(script.modules.silentaim)
local Visuals         = require(script.modules.visuals)
local AntiAim         = require(script.modules.antiaim.orchestrator)
local Exploits        = require(script.modules.exploits.orchestrator)
local UIManager       = require(script.ui.uimanager)

local engine = Engine.new()

-- Order matters: register services first, then modules that depend on them
engine:registerModule("PlayerService",    PlayerService.new,    {}, {})
engine:registerModule("CameraService",    CameraService.new,    {}, {})
engine:registerModule("CharacterService", CharacterService.new, {}, {})
engine:registerModule("TargetService",    TargetService.new,    {}, {})
engine:registerModule("RaycastService",   RaycastService.new,   {}, {})
engine:registerModule("ConfigService",    ConfigService.new,    {"Engine"}, {})

engine:registerModule("Aimbot", Aimbot.new,
    {"CameraService","PlayerService","CharacterService","TargetService","RaycastService","ConfigService"},
    { Update = 30, Render = 50 })

engine:registerModule("SilentAim", SilentAim.new,
    {"TargetService","CharacterService","CameraService","PlayerService","RaycastService","ConfigService"},
    {})

engine:registerModule("Visuals", Visuals.new,
    {"CameraService","PlayerService","TargetService","ConfigService"},
    { Render = 60 })

engine:registerModule("AntiAim", AntiAim.new,
    {"CharacterService","CameraService","RaycastService","PlayerService","TargetService","ConfigService"},
    { Update = 20, Render = 55 })

engine:registerModule("Exploits", Exploits.new,
    {"CharacterService","PlayerService","CameraService","RaycastService","ConfigService"},
    { Update = 10 })

engine:registerModule("UIManager", UIManager.new, {"ConfigService"}, {})

engine.di:resolve("ConfigService"):load(require(script.config.defaults))

engine:start()

-- UIManager:Start blocks on HttpGet → spawn so engine isn't held
task.spawn(function()
    local ui = engine.di:resolve("UIManager")
    if ui then ui:Start() end
end)

script.Destroying:Connect(function()
    engine:destroy()
end)