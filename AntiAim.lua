local RunService = game:GetService("RunService")

local desyncGyro = nil
local originalNeckC0 = nil
local wasDesyncEnabled = false
local wasHideHeadEnabled = false

local function SetupDesync(enable)
    local char = _G.LocalPlayer.Character
    if not char then return end
    local root = char:FindFirstChild("HumanoidRootPart")
    if not root then return end

    if enable then
        if not desyncGyro then
            desyncGyro = Instance.new("BodyGyro")
            desyncGyro.Name = "ABYSS_DesyncGyro"
            desyncGyro.MaxTorque = Vector3.new(0, math.huge, 0)
            desyncGyro.P = 10000
            desyncGyro.Parent = root
        end
    else
        if desyncGyro then
            desyncGyro:Destroy()
            desyncGyro = nil
        end
    end
end

local function UpdateAntiAim()
    local char = _G.LocalPlayer.Character
    if not char then return end
    local root = char:FindFirstChild("HumanoidRootPart")
    if not root then return end

    if _G.Settings.AntiAim.HideHead ~= wasHideHeadEnabled then
        wasHideHeadEnabled = _G.Settings.AntiAim.HideHead
        if not _G.Settings.AntiAim.HideHead and originalNeckC0 then
            local head = char:FindFirstChild("Head")
            if head then
                local neck = head:FindFirstChild("Neck")
                if neck and neck:IsA("Motor6D") then
                    neck.C0 = originalNeckC0
                end
            end
            originalNeckC0 = nil
        end
    end

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
    end

    if _G.Settings.Rage.Spinbot then
        root.CFrame = root.CFrame * CFrame.Angles(0, math.rad(_G.Settings.Rage.SpinSpeed or 25), 0)
    elseif _G.Settings.AntiAim.Jitter then
        local angle = math.rad(math.sin(tick() * 20) * _G.Settings.AntiAim.JitterAngle)
        local rootJoint = root:FindFirstChild("RootJoint")
        if rootJoint and rootJoint:IsA("Motor6D") then
            rootJoint.C0 = rootJoint.C0 * CFrame.Angles(0, angle, 0)
        end
    end

    if _G.Settings.AntiAim.Desync ~= wasDesyncEnabled then
        wasDesyncEnabled = _G.Settings.AntiAim.Desync
        SetupDesync(_G.Settings.AntiAim.Desync)
    end

    if _G.Settings.AntiAim.Desync and desyncGyro then
        if _G.Settings.AntiAim.DesyncType == "Spin" then
            desyncGyro.CFrame = CFrame.Angles(0, math.rad(tick() * _G.Settings.AntiAim.DesyncSpeed), 0)
        elseif _G.Settings.AntiAim.DesyncType == "Backwards" then
            desyncGyro.CFrame = root.CFrame * CFrame.Angles(0, math.pi, 0)
        end
    end
end

RunService.Heartbeat:Connect(UpdateAntiAim)

_G.LocalPlayer.CharacterAdded:Connect(function()
    task.wait(0.5)
    wasDesyncEnabled = false
    wasHideHeadEnabled = false
    if desyncGyro then desyncGyro:Destroy() desyncGyro = nil end
    originalNeckC0 = nil
end)
