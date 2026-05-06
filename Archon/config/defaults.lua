return {
    version = 2,
    Aimbot = {
        Enabled = false, Silent = false,
        FOV = 120, Smoothing = 3, Sensitivity = 1,
        Prediction = 0.14, HitboxOffset = 0,
        WallCheck = true, PredictGravity = false,
        Backtrack = false, Hysteresis = true, HysteresisMult = 1.3,
        MaxFovDelta = 38, BulletVel = 0,
        UseResolver = true, UsePing = true, UseAccel = true,
        MultiRay = true, RageMode = true,
        TargetMode = "Score"
    },
    SilentAim = {
        Enabled = false, HitChance = 100, Humanizer = 0.4, MissOffset = 4,
        MaxPerSec = 0, MinDelay = 0, RequireMouseDown = false,
        Burst = false, BurstCount = 3, BurstWindow = 0.15, BurstPauseMin = 1.5, BurstPauseMax = 2.3,
        OriginRange = 80, AutoOriginRange = true,
        SafeOnFly = false, SafeOnNoclip = false
    },
    ESP = {
        Enabled = false, Boxes = false, HealthBar = false, Snaplines = false, Chams = false,
        ShowNames = false, ShowDistance = false, ShowHealth = false, SnapFromBottom = true,
        ChamsOutline = true, TeamColor = true, MaxDistance = 500, TextSize = 13,
        BoxThickness = 1, ChamsFillTransparency = 0.4, ChamsOutlineTransparency = 0.2
    },
    AntiAim = {
        Enabled = false,
        Jitter = { Enabled = false, Mode = "Sine", Angle = 40, Speed = 12, Pattern = {1, -1, 0.5, -0.5} },
        Spin = { Enabled = false, Speed = 30, Mode = "Yaw" },
        Pitch = { Enabled = false, Mode = "Down", Angle = 89 },
        Desync = { Enabled = false, Mode = "Switch", Strength = 1.0, Speed = 30, BufferTeleport = false, PredictorBias = true },
        FakeLag = { Enabled = false, Mode = "Static", Intensity = 5, Frequency = 1, BackForth = false, Doubletap = false },
        Freestanding = { Enabled = false, EdgeDetect = true, Range = 15 },
        Manual = { Enabled = false },
        Indicators = { Enabled = true },
        YawFlip = { Enabled = false, Interval = 0.2 }
    },
    Exploits = {
        Teleport = { Enabled = false, Key = "V", Range = 50 },
        Hitbox = { Enabled = false, Size = 12, Whitelist = {"Head","UpperTorso","LowerTorso","Torso"}, TransparencyMode = "Translucent", TransparencyValue = 0.7, OnlyVisible = false, OnlyEnemies = true },
        SpeedHack = { Enabled = false, Speed = 50 },
        Fly = { Enabled = false, Speed = 58, Smoothness = 6, AirControl = true, VelPreserve = true },
        Noclip = { Enabled = false, Mode = "Standard" },
        InfJump = { Enabled = false, Cooldown = 0.22, Boost = 0 },
        Velocity = { Enabled = false, Multiplier = 1, Cap = 200 }
    }
}