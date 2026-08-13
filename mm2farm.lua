-- Services
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local CoreGui = game:GetService("CoreGui")

local LocalPlayer = Players.LocalPlayer

-- Global Settings
local Settings = {
    AutoFarm = false,
    CoinAura = false,
    Underground = true,
    SafeVoid = true,
    AutoKill = false,
    AntiFling = true,
    AntiAFK = true,
    
    ResetSheriff = false,
    ResetMurder = false,
    ResetInnocent = false,
    
    TweenSpeed = 25,
    MaxCoins = 40
}

-- Safe Parent for UI
local TargetParent = gethui and gethui() or CoreGui

-- Cleanup Existing UI
if TargetParent:FindFirstChild("CrowsHubMM2") then
    TargetParent.CrowsHubMM2:Destroy()
end

-- ScreenGui Setup (Adaptive for Mobile & PC)
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "CrowsHubMM2"
ScreenGui.ResetOnSpawn = false
ScreenGui.Parent = TargetParent

-- Main Frame (Center Screen, Relative Size)
local MainFrame = Instance.new("Frame")
MainFrame.Name = "MainFrame"
MainFrame.Size = UDim2.new(0.35, 0, 0.55, 0) -- 35% width, 55% height
MainFrame.Position = UDim2.new(0.325, 0, 0.225, 0)
MainFrame.BackgroundColor3 = Color3.fromRGB(25, 25, 30)
MainFrame.BorderSizePixel = 0
MainFrame.Active = true
MainFrame.Draggable = true
MainFrame.Parent = ScreenGui

local UICorner = Instance.new("UICorner")
UICorner.CornerRadius = UDim.new(0, 8)
UICorner.Parent = MainFrame

local AspectRatio = Instance.new("UIAspectRatioConstraint")
AspectRatio.AspectRatio = 1.2
AspectRatio.Parent = MainFrame

-- Title Bar
local Title = Instance.new("TextLabel")
Title.Size = UDim2.new(1, 0, 0.12, 0)
Title.BackgroundColor3 = Color3.fromRGB(35, 35, 45)
Title.Text = "  Crows Hub | MM2 Farm Lite"
Title.TextColor3 = Color3.fromRGB(200, 200, 255)
Title.TextScaled = true
Title.Font = Enum.Font.SourceSansBold
Title.TextXAlignment = Enum.TextXAlignment.Left
Title.Parent = MainFrame

local TitleCorner = Instance.new("UICorner")
TitleCorner.CornerRadius = UDim.new(0, 8)
TitleCorner.Parent = Title

-- Container for Toggles
local Container = Instance.new("ScrollingFrame")
Container.Size = UDim2.new(0.9, 0, 0.82, 0)
Container.Position = UDim2.new(0.05, 0, 0.15, 0)
Container.BackgroundTransparency = 1
Container.ScrollBarThickness = 4
Container.Parent = MainFrame

local UIList = Instance.new("UIListLayout")
UIList.SortOrder = Enum.SortOrder.LayoutOrder
UIList.Padding = UDim.new(0, 6)
UIList.Parent = Container

-- Helper Function to Create Buttons
local function CreateToggle(text, settingName)
    local Btn = Instance.new("TextButton")
    Btn.Size = UDim2.new(1, -10, 0, 32)
    Btn.BackgroundColor3 = Settings[settingName] and Color3.fromRGB(40, 140, 60) or Color3.fromRGB(45, 45, 55)
    Btn.Text = text .. ": " .. (Settings[settingName] and "[ON]" or "[OFF]")
    Btn.TextColor3 = Color3.fromRGB(255, 255, 255)
    Btn.Font = Enum.Font.SourceSans
    Btn.TextSize = 16
    Btn.Parent = Container

    local Corner = Instance.new("UICorner")
    Corner.CornerRadius = UDim.new(0, 6)
    Corner.Parent = Btn

    Btn.MouseButton1Click:Connect(function()
        Settings[settingName] = not Settings[settingName]
        Btn.BackgroundColor3 = Settings[settingName] and Color3.fromRGB(40, 140, 60) or Color3.fromRGB(45, 45, 55)
        Btn.Text = text .. ": " .. (Settings[settingName] and "[ON]" or "[OFF]")
    end)
    return Btn
end

-- UI Controls
CreateToggle("Auto Farm Coins", "AutoFarm")
CreateToggle("Safe Coin Aura (Distance)", "CoinAura")
CreateToggle("Farm Under Floor", "Underground")
CreateToggle("Teleport to Void when Full", "SafeVoid")
CreateToggle("Auto Kill (If Murderer & Full)", "AutoKill")
CreateToggle("Anti-Fling", "AntiFling")
CreateToggle("Anti-AFK", "AntiAFK")
CreateToggle("Auto Reset (Sheriff)", "ResetSheriff")
CreateToggle("Auto Reset (Murderer)", "ResetMurder")
CreateToggle("Auto Reset (Innocent)", "ResetInnocent")

Container.CanvasSize = UDim2.new(0, 0, 0, UIList.AbsoluteContentSize.Y + 20)

----------------------------------------------------------------
-- Anti-AFK Logic
----------------------------------------------------------------
local VirtualUser = game:GetService("VirtualUser")
LocalPlayer.Idled:Connect(function()
    if Settings.AntiAFK then
        VirtualUser:Button2Down(Vector2.new(0, 0), workspace.CurrentCamera.CFrame)
        task.wait(1)
        VirtualUser:Button2Up(Vector2.new(0, 0), workspace.CurrentCamera.CFrame)
    end
end)

----------------------------------------------------------------
-- Anti-Fling Logic
----------------------------------------------------------------
RunService.Stepped:Connect(function()
    if Settings.AntiFling and LocalPlayer.Character then
        for _, player in pairs(Players:GetPlayers()) do
            if player ~= LocalPlayer and player.Character then
                for _, part in pairs(player.Character:GetChildren()) do
                    if part:IsA("BasePart") then
                        part.CanCollide = false
                    end
                end
            end
        end
    end
end)

----------------------------------------------------------------
-- Auto Reset Check on Spawn
----------------------------------------------------------------
LocalPlayer.CharacterAdded:Connect(function(char)
    task.wait(1.5)
    local backpack = LocalPlayer:FindFirstChild("Backpack")
    
    local isSheriff = backpack:FindFirstChild("Gun") or char:FindFirstChild("Gun")
    local isMurder = backpack:FindFirstChild("Knife") or char:FindFirstChild("Knife")
    
    if isSheriff and Settings.ResetSheriff then
        char:BreakJoints()
    elseif isMurder and Settings.ResetMurder then
        char:BreakJoints()
    elseif not isSheriff and not isMurder and Settings.ResetInnocent then
        char:BreakJoints()
    end
end)

----------------------------------------------------------------
-- Auto Farm, Safe Void, Coin Aura & Auto Kill Core Logic
----------------------------------------------------------------
task.spawn(function()
    while task.wait(0.2) do
        if Settings.AutoFarm and LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart") then
            local hrp = LocalPlayer.Character.HumanoidRootPart
            local coinContainer = workspace:FindFirstChild("CoinContainer", true)
            
            -- Check Coins Amount
            local coinData = LocalPlayer:FindFirstChild("CoinData") or LocalPlayer:FindFirstChild("leaderstats")
            local currentCoins = coinData and coinData:FindFirstChild("Coins") and coinData.Coins.Value or 0
            
            -- If max coins reached
            if currentCoins >= Settings.MaxCoins then
                -- 1. Check AutoKill if Murderer
                local hasKnife = LocalPlayer.Backpack:FindFirstChild("Knife") or LocalPlayer.Character:FindFirstChild("Knife")
                if hasKnife and Settings.AutoKill then
                    for _, v in pairs(Players:GetPlayers()) do
                        if v ~= LocalPlayer and v.Character and v.Character:FindFirstChild("HumanoidRootPart") then
                            hrp.CFrame = v.Character.HumanoidRootPart.CFrame
                            task.wait(0.2)
                        end
                    end
                -- 2. Teleport to Safe Void
                elseif Settings.SafeVoid then
                    hrp.CFrame = CFrame.new(0, -300, 0)
                end
            elseif coinContainer then
                -- Collecting Coins Logic
                for _, coin in pairs(coinContainer:GetChildren()) do
                    if not Settings.AutoFarm then break end
                    if coin:IsA("BasePart") and coin.Name == "Coin" then
                        
                        local targetPos = coin.Position
                        
                        -- Offset under the floor
                        if Settings.Underground then
                            targetPos = targetPos - Vector3.new(0, 7, 0)
                        end
                        
                        -- Fly to coin
                        local dist = (hrp.Position - targetPos).Magnitude
                        local tween = TweenService:Create(hrp, TweenInfo.new(dist / Settings.TweenSpeed, Enum.EasingStyle.Linear), {CFrame = CFrame.new(targetPos)})
                        tween:Play()
                        tween.Completed:Wait()
                        
                        -- Safe Coin Aura
                        if Settings.CoinAura then
                            firetouchinterest(hrp, coin, 0)
                            task.wait()
                            firetouchinterest(hrp, coin, 1)
                        end
                        task.wait(0.1)
                    end
                end
            end
        end
    end
end)
