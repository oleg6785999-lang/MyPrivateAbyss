-- AntiAim.lua
local RunService = game:GetService("RunService")

local desyncGyro = nil
local desyncAngle = 0
local originalNeckC0 = nil
local fakeLagCounter = 0

local function UpdateAntiAim()
    local char = _G.LocalPlayer.Character
    if not char then return end
    local root = char:FindFirstChild("HumanoidRootPart")
    if not root then return end

    if _G.Settings.AntiAim.HideHead then
        local head = char:FindFirstChild("Head")
        if head then
            local neck = head:FindFirstChild("Neck")
            if neck and neck:IsA("Motor6D") then
                if not originalNeckC0 then originalNeckC0 = neck.C0 end
                if _G.Settings.AntiAim.HideHeadMode == "Back" then
                    neck.C0 = CFrame.Angles(0, math.rad(180), 0)
                else
                    neck.C0 = CFrame.Angles(math.rad(-90), 0, 0)
                end
            end
        end
    elseif originalNeckC0 then
        local head = char:FindFirstChild("Head")
        if head then
            local neck = head:FindFirstChild("Neck")
            if neck and neck:IsA("Motor6D") then
                neck.C0 = originalNeckC0
                originalNeckC0 = nil
            end
        end
    end

    if _G.Settings.AntiAim.Jitter then
        local angleY = math.rad(math.random(-_G.Settings.AntiAim.JitterAngle, _G.Settings.AntiAim.JitterAngle))
        local angleX = math.rad(math.random(-15, 15))
        root.CFrame = root.CFrame * CFrame.Angles(angleX, angleY, 0)
    end

    if _G.Settings.Rage.Spinbot and not _G.Settings.Fly.Enabled then
        root.CFrame = root.CFrame * CFrame.Angles(0, math.rad(_G.Settings.Rage.SpinSpeed), 0)
    end

    if _G.Settings.AntiAim.Desync and desyncGyro then
        if _G.Settings.AntiAim.DesyncType == "Spin" then
            desyncAngle = (desyncAngle + _G.Settings.AntiAim.DesyncSpeed) % 360
            desyncGyro.CFrame = CFrame.Angles(0, math.rad(desyncAngle), 0)
        elseif _G.Settings.AntiAim.DesyncType == "Backwards" then
            desyncGyro.CFrame = (root.CFrame * CFrame.Angles(0, math.pi, 0)).Rotation
        end
    end

    if _G.Settings.AntiAim.FakeLag and not _G.Settings.Fly.Enabled then
        fakeLagCounter = fakeLagCounter + 1
        if fakeLagCounter % _G.Settings.AntiAim.FakeLagFrequency == 0 then
            local intensity = _G.Settings.AntiAim.FakeLagIntensity
            local origPos = root.Position
            local offset = Vector3.new(math.random(-intensity, intensity), math.random(-intensity/2, intensity/2), math.random(-intensity, intensity))
            if _G.Settings.AntiAim.FakeLagMode == "BackAndForth" then
                if fakeLagCounter % 2 == 0 then
                    root.CFrame = root.CFrame + offset
                else
                    root.CFrame = CFrame.new(origPos) * root.CFrame.Rotation
                end
            else
                root.CFrame = root.CFrame + offset
            end
            if _G.Settings.AntiAim.FakeLagNoClip then
                for _, part in ipairs(char:GetDescendants()) do
                    if part:IsA("BasePart") then part.CanCollide = false end
                end
            end
        end
    end
end

local function AntiAimLoop()
    while task.wait() do
        UpdateAntiAim()
    end
end

task.spawn(AntiAimLoop)
