local RunService = game:GetService("RunService")

local desyncGyro = nil
local originalNeckC0 = nil

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
            end
        end
        originalNeckC0 = nil
    end

    if _G.Settings.AntiAim.Desync then
        if not desyncGyro then
            desyncGyro = Instance.new("BodyGyro")
            desyncGyro.MaxTorque = Vector3.new(0, math.huge, 0)
            desyncGyro.P = 10000
            desyncGyro.Parent = root
        end
        if _G.Settings.AntiAim.DesyncType == "Spin" then
            desyncGyro.CFrame = CFrame.Angles(0, math.rad(tick() * _G.Settings.AntiAim.DesyncSpeed), 0)
        elseif _G.Settings.AntiAim.DesyncType == "Backwards" then
            desyncGyro.CFrame = root.CFrame * CFrame.Angles(0, math.pi, 0)
        end
    elseif desyncGyro then
        desyncGyro:Destroy()
        desyncGyro = nil
    end
end

RunService.Heartbeat:Connect(UpdateAntiAim)
