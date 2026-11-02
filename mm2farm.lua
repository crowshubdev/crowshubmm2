-- ═══════════════════════════════════════════════════════════════
-- CROWS LITE | MM2 Auto Farm (чистый, без стилера)
-- Farm only: Normal / Safe | Avoid Murderer | Anti-Fling
-- Auto Fling Murderer (если умер) | Auto Kill All (полный мешок)
-- UI: WindUI (Footagesus)
-- ═══════════════════════════════════════════════════════════════
print("[CWH Lite] START")

-- ═══ WIND UI ═══
local WindUI = loadstring(game:HttpGet("https://raw.githubusercontent.com/Footagesus/WindUI/main/dist/main.lua"))()

-- ═══ SERVICES ═══
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local LocalPlayer = Players.LocalPlayer

local function getChar(p) return p and p.Character end
local function getHum(c) return c and c:FindFirstChildOfClass("Humanoid") end
local function getHRP(c) return c and c:FindFirstChild("HumanoidRootPart") end
local realFireTouch = (typeof(firetouchinterest) == "function") and firetouchinterest or nil

-- ═══ CONFIG ═══
local Config = {
    Farm = false,
    Method = "Normal", -- Normal (по карте) / Safe (под полом)
    Speed = 23,
    YDepth = 6,        -- насколько ниже монеты лететь в Safe
    AvoidMurder = false,
    AntiFling = true,
    MaxVel = 500,
    FlingOnDeath = false,
    KillAllFullBag = false,
}

-- ═══ ROLES (gun первым делом, потом данные сервера, потом нож) ═══
local ServerRoles = {}
local roleCache, roleCacheT = {}, 0
local function getRole(plr)
    local now = os.clock()
    if now - roleCacheT > 0.4 then roleCache = {} roleCacheT = now end
    if not roleCache[plr] then
        local role = "Innocent"
        local c = plr and plr.Character
        local bp = plr and plr:FindFirstChild("Backpack")
        if c and c:FindFirstChild("Gun") or (bp and bp:FindFirstChild("Gun")) then
            role = "Sheriff"
        elseif type(ServerRoles[plr.Name]) == "table" and ServerRoles[plr.Name].Role then
            role = ServerRoles[plr.Name].Role
            if role == "Hero" then role = "Sheriff" end
            if role == "Sheriff" and ServerRoles[plr.Name].Dead then role = "Innocent" end
        elseif c and (c:FindFirstChild("Knife") or (bp and bp:FindFirstChild("Knife"))) then
            role = "Murderer"
        end
        roleCache[plr] = role
    end
    return roleCache[plr]
end
local function getMurderer()
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LocalPlayer and getRole(p) == "Murderer" then return p end
    end
end

task.spawn(function()
    local ok, remote = pcall(function()
        return ReplicatedStorage:WaitForChild("Remotes", 15)
            :WaitForChild("Gameplay", 15):WaitForChild("PlayerDataChanged", 15)
    end)
    if ok and remote then
        remote.OnClientEvent:Connect(function(data)
            ServerRoles = data or {}
            roleCache = {}
        end)
    end
end)

-- ═══ ANTI-FLING (из Crows Hub) ═══
local flinging = false -- пока сами флим — защиту не трогаем
task.spawn(function()
    while task.wait(0.05) do
        if Config.AntiFling and not flinging then
            pcall(function()
                local char = getChar(LocalPlayer)
                local hrp = getHRP(char)
                if not hrp then return end
                -- 1) снос чужих BodyMovers у себя (свой флинг — CWH_EpixVel — не трогаем)
                for _, obj in pairs(char:GetDescendants()) do
                    if obj:IsA("BodyVelocity") or obj:IsA("BodyAngularVelocity")
                        or obj:IsA("BodyThrust") or obj:IsA("BodyGyro")
                        or obj:IsA("LinearVelocity") or obj:IsA("AngularVelocity")
                        or obj:IsA("VectorForce") or obj:IsA("Torque") then
                        if obj.Name ~= "CWH_EpixVel" then obj:Destroy() end
                    end
                end
                -- 2) сброс аномальной своей скорости
                local vel = hrp.AssemblyLinearVelocity or hrp.Velocity
                local rot = hrp.AssemblyAngularVelocity or hrp.RotVelocity
                if vel and vel.Magnitude > Config.MaxVel then
                    hrp.AssemblyLinearVelocity = Vector3.zero
                    hrp.Velocity = Vector3.zero
                end
                if rot and rot.Magnitude > Config.MaxVel then
                    hrp.AssemblyAngularVelocity = Vector3.zero
                    hrp.RotVelocity = Vector3.zero
                end
            end)
        end
    end
end)

-- ═══ FLING (компактный SkidFling из Crows Hub) ═══
local function SkidFling(TargetPlayer)
    if not TargetPlayer or not TargetPlayer.Character or flinging then return end
    local Character = getChar(LocalPlayer)
    local Humanoid = getHum(Character)
    local RootPart = getHRP(Character)
    local TCharacter = TargetPlayer.Character
    local THumanoid = getHum(TCharacter)
    local TRootPart = getHRP(TCharacter)
    local THead = TCharacter and TCharacter:FindFirstChild("Head")
    if not (Character and Humanoid and RootPart and THumanoid) then return end
    if Humanoid.Health <= 0 then return end

    flinging = true
    pcall(function()
        local OldPos = RootPart.CFrame
        if RootPart.Velocity.Magnitude < 50 then OldPos = RootPart.CFrame end

        local FPDH = workspace.FallenPartsDestroyHeight
        workspace.FallenPartsDestroyHeight = 0/0

        local BV = Instance.new("BodyVelocity")
        BV.Name = "CWH_EpixVel"
        BV.Parent = RootPart
        BV.Velocity = Vector3.new(9e8, 9e8, 9e8)
        BV.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
        Humanoid:SetStateEnabled(Enum.HumanoidStateType.Seated, false)

        local FPos = function(BasePart, Pos, Ang)
            RootPart.CFrame = CFrame.new(BasePart.Position) * Pos * Ang
            RootPart.Velocity = Vector3.new(9e7, 9e7 * 10, 9e7)
            RootPart.RotVelocity = Vector3.new(9e8, 9e8, 9e8)
        end

        -- крутимся вокруг цели, пока она не улетит (макс 2.5 сек)
        local BasePart = TRootPart or THead
        local Time = tick()
        local Angle = 0
        if BasePart then
            repeat
                if BasePart.Velocity.Magnitude < 50 then
                    Angle = Angle + 100
                    FPos(BasePart, CFrame.new(0, 1.5, 0) + THumanoid.MoveDirection * BasePart.Velocity.Magnitude / 1.25, CFrame.Angles(math.rad(Angle), 0, 0))
                    task.wait()
                    FPos(BasePart, CFrame.new(0, -1.5, 0) + THumanoid.MoveDirection * BasePart.Velocity.Magnitude / 1.25, CFrame.Angles(math.rad(Angle), 0, 0))
                    task.wait()
                    FPos(BasePart, CFrame.new(2.25, 1.5, -2.25) + THumanoid.MoveDirection * BasePart.Velocity.Magnitude / 1.25, CFrame.Angles(math.rad(Angle), 0, 0))
                    task.wait()
                    FPos(BasePart, CFrame.new(-2.25, -1.5, 2.25) + THumanoid.MoveDirection * BasePart.Velocity.Magnitude / 1.25, CFrame.Angles(math.rad(Angle), 0, 0))
                    task.wait()
                else
                    FPos(BasePart, CFrame.new(0, 1.5, THumanoid.WalkSpeed), CFrame.Angles(math.rad(90), 0, 0))
                    task.wait()
                    FPos(BasePart, CFrame.new(0, -1.5, -THumanoid.WalkSpeed), CFrame.Angles(0, 0, 0))
                    task.wait()
                    FPos(BasePart, CFrame.new(0, 1.5, THumanoid.WalkSpeed), CFrame.Angles(math.rad(90), 0, 0))
                    task.wait()
                    FPos(BasePart, CFrame.new(0, -1.5, 0), CFrame.Angles(math.rad(-90), 0, 0))
                    task.wait()
                end
            until BasePart.Velocity.Magnitude > 500 or BasePart.Parent ~= TCharacter
                or TargetPlayer.Parent ~= Players
                or (THumanoid and THumanoid.Sit)
                or (Humanoid and Humanoid.Health <= 0)
                or tick() > Time + 2.5
        end

        if BV and BV.Parent then BV:Destroy() end
        Humanoid:SetStateEnabled(Enum.HumanoidStateType.Seated, true)
        if workspace.CurrentCamera then
            workspace.CurrentCamera.CameraSubject = Humanoid
        end

        -- возврат на место
        if Humanoid.Health > 0 then
            RootPart.CFrame = OldPos * CFrame.new(0, 0.5, 0)
            Humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
            for _, x in ipairs(Character:GetChildren()) do
                if x:IsA("BasePart") then
                    x.Velocity, x.RotVelocity = Vector3.new(), Vector3.new()
                end
            end
        end
        workspace.FallenPartsDestroyHeight = FPDH
    end)
    flinging = false
end

-- ═══ AUTO FLING MURDERER ЕСЛИ УМЕР ═══
local function hookDeath(char)
    local hum = char:WaitForChild("Humanoid", 5)
    if not hum then return end
    hum.Died:Connect(function()
        if not Config.FlingOnDeath then return end
        task.spawn(function()
            local m = getMurderer()
            if not m then return end
            -- ждём респавн, потом мстим
            LocalPlayer.CharacterAdded:Wait()
            task.wait(2)
            local c = getChar(LocalPlayer)
            local h = getHum(c)
            if c and h and h.Health > 0 and m.Parent and m ~= LocalPlayer then
                SkidFling(m)
            end
        end)
    end)
end
if LocalPlayer.Character then hookDeath(LocalPlayer.Character) end
LocalPlayer.CharacterAdded:Connect(hookDeath)

-- ═══ FARM CORE (из Crows Hub + детект Coin_Server) ═══
local touchedCoins = {}  -- [coin] = время touch
local touchCounts = {}   -- [coin] = сколько раз touch не сработал
local blockedCoins = {}  -- [coin] = время блокировки (10 сек)
local FarmTarget = nil
local CollectedCount = 0

local NoclipCache = {}
local function set_farm_noclip(on)
    local char = getChar(LocalPlayer)
    if on then
        if not char then return end
        for _, p in ipairs(char:GetDescendants()) do
            if p:IsA("BasePart") and p.CanCollide then
                if NoclipCache[p] == nil then NoclipCache[p] = p.CanCollide end
                p.CanCollide = false
            end
        end
    else
        for p, v in pairs(NoclipCache) do
            if p and p.Parent then pcall(function() p.CanCollide = v end) end
        end
        NoclipCache = {}
    end
end
RunService.Stepped:Connect(function()
    if Config.Farm and getChar(LocalPlayer) then
        set_farm_noclip(true)
    end
end)

local function coin_available(v)
    return v and v.Parent
        and not v:FindFirstChild("CollectedCoin")
        and v:FindFirstChild("TouchInterest") ~= nil
end
local function get_map()
    for _, child in ipairs(Workspace:GetChildren()) do
        if child:IsA("Model") and child:FindFirstChild("CoinContainer") then
            return child
        end
    end
end
local function available_coins()
    local list = {}
    local map = get_map()
    if map then
        for _, c in ipairs(map.CoinContainer:GetChildren()) do
            if c.Name == "Coin_Server" and coin_available(c) then
                list[#list + 1] = c
            end
        end
    end
    if #list == 0 then
        -- запасной способ из Crows Hub (CoinVisual)
        local ok, tagged = pcall(function()
            return game:GetService("CollectionService"):GetTagged("CoinVisual")
        end)
        if ok then
            for _, v in ipairs(tagged) do
                if v and v.Parent and v:IsA("BasePart")
                    and not v:GetAttribute("Collected")
                    and not v:GetAttribute("Delete") then
                    list[#list + 1] = v
                end
            end
        end
    end
    return list
end
local function nearest_coin(pos, list)
    local best, bd = nil, math.huge
    local now = os.clock()
    for _, v in ipairs(list) do
        local tT = touchedCoins[v]
        local tB = blockedCoins[v]
        if not (tT and now - tT < 1.5) and not (tB and now - tB < 10) then
            local d = (v.Position - pos).Magnitude
            if d < bd then bd = d best = v end
        end
    end
    return best
end

local function touch_targets(coin)
    local list, seen = {}, {}
    local function add(p)
        if p and not seen[p] and p:IsA("BasePart") then
            seen[p] = true
            list[#list + 1] = p
        end
    end
    add(coin)
    for _, v in ipairs(coin:GetChildren()) do add(v) end
    local par = coin.Parent
    if par then
        if par:IsA("BasePart") then add(par) end
        for _, v in ipairs(par:GetChildren()) do add(v) end
    end
    if #list == 0 then list[1] = coin end
    return list
end

local LastTouch = 0
local function fire_touch(coin)
    if not realFireTouch or not coin or not coin.Parent then return false end
    local now = os.clock()
    if now - LastTouch < 0.05 then return false end
    LastTouch = now
    local hrp = getHRP(getChar(LocalPlayer))
    if not hrp then return false end
    for _, p in ipairs(touch_targets(coin)) do
        pcall(realFireTouch, hrp, p, 0)
        pcall(realFireTouch, hrp, p, 1)
    end
    touchedCoins[coin] = now
    -- застряли: 3-й touch той же монеты — блокируем её на 10 сек
    touchCounts[coin] = (touchCounts[coin] or 0) + 1
    if touchCounts[coin] >= 3 then
        blockedCoins[coin] = now
        touchCounts[coin] = nil
    end
    CollectedCount = CollectedCount + 1
    return true
end

local function farm_move(hrp, dest, dt)
    local dir = dest - hrp.Position
    local dist = dir.Magnitude
    if dist > 0.1 then
        local np = hrp.Position + dir.Unit * math.min(Config.Speed * dt, dist)
        pcall(function()
            hrp.CFrame = CFrame.new(np)
            hrp.AssemblyLinearVelocity = Vector3.zero
            hrp.AssemblyAngularVelocity = Vector3.zero
        end)
    end
end

local function flat_dist(a, b)
    return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
end
local AVOID_DIST = 40
local function avoid_steer(cur, dest, mpos)
    if not (Config.AvoidMurder and mpos) then return dest end
    local dm = flat_dist(cur, mpos)
    if dm >= AVOID_DIST then return dest end
    local away = Vector3.new(cur.X - mpos.X, 0, cur.Z - mpos.Z)
    if away.Magnitude < 0.1 then away = Vector3.new(1, 0, 0) end
    away = away.Unit
    local want = Vector3.new(dest.X - cur.X, 0, dest.Z - cur.Z)
    local mag = want.Magnitude
    if mag < 0.1 then return dest end
    local weight = 1 + (1 - dm / AVOID_DIST) * 2
    local blend = (want.Unit + away * weight)
    if blend.Magnitude < 0.1 then blend = away else blend = blend.Unit end
    local np = cur + blend * mag
    return Vector3.new(np.X, dest.Y, np.Z)
end

local function murderer_pos()
    local m = getMurderer()
    local c = m and getChar(m)
    local h = c and getHRP(c)
    local hum = c and getHum(c)
    if h and (not hum or hum.Health > 0) then return h.Position end
end

local function coin_bags_full()
    local pg = LocalPlayer:FindFirstChild("PlayerGui")
    local main = pg and pg:FindFirstChild("MainGUI")
    local gg = main and main:FindFirstChild("Game")
    local bags = gg and gg:FindFirstChild("CoinBags")
    local container = bags and bags:FindFirstChild("Container")
    if not container then return false end
    local any = false
    for _, v in ipairs(container:GetChildren()) do
        if v:IsA("Frame") and v.Visible then
            any = true
            local full = v:FindFirstChild("Full")
            if not (full and full.Visible) then return false end
        end
    end
    return any
end

-- ═══ AUTO KILL ALL ПРИ ПОЛНОМ МЕШКЕ (из Crows Hub Auto KE) ═══
local KEDoneThisRound = false
local function getKnife()
    local c = getChar(LocalPlayer)
    if c and c:FindFirstChild("Knife") then return c:FindFirstChild("Knife") end
    local bp = LocalPlayer:FindFirstChild("Backpack")
    return bp and bp:FindFirstChild("Knife")
end
local function keKillAll()
    local knife = getKnife()
    if not knife then return 0 end
    local c = getChar(LocalPlayer)
    if knife.Parent ~= c then
        local hum = getHum(c)
        if hum then
            pcall(function() hum:EquipTool(knife) end)
            task.wait(0.2)
            knife = getKnife()
        end
    end
    if not knife then return 0 end
    local ev = knife:FindFirstChild("Events")
    local st = ev and ev:FindFirstChild("KnifeStabbed")
    local to = ev and ev:FindFirstChild("HandleTouched")
    local handle = knife:FindFirstChild("Handle")
    local n = 0
    if st then pcall(function() st:FireServer() end) end
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= LocalPlayer then
            local pc = getChar(plr)
            local ph = getHum(pc)
            local phrp = pc and getHRP(pc)
            if ph and ph.Health > 0 and phrp then
                if to then pcall(function() to:FireServer(phrp) end) end
                if handle and realFireTouch then
                    pcall(function()
                        realFireTouch(handle, phrp, 1)
                        realFireTouch(handle, phrp, 0)
                    end)
                end
                n = n + 1
            end
        end
    end
    return n
end

-- сбросы в новом раунде
task.spawn(function()
    local ok, remote = pcall(function()
        return ReplicatedStorage:WaitForChild("Remotes", 15)
            :WaitForChild("Gameplay", 15):WaitForChild("CoinsStarted", 15)
    end)
    if ok and remote then
        remote.OnClientEvent:Connect(function()
            FarmTarget = nil
            touchedCoins = {}
            touchCounts = {}
            blockedCoins = {}
            KEDoneThisRound = false
        end)
    end
end)
LocalPlayer.CharacterAdded:Connect(function()
    FarmTarget = nil
    touchedCoins = {}
    touchCounts = {}
    blockedCoins = {}
    KEDoneThisRound = false
end)

-- ═══ ГЛАВНЫЙ ЦИКЛ ФЕРМЫ ═══
local lastFrame = os.clock()
task.spawn(function()
    while true do
        local now = os.clock()
        local dt = math.min(now - lastFrame, 0.1)
        lastFrame = now

        -- чистим старые метки
        for coin, t in pairs(touchedCoins) do
            if not coin.Parent or now - t > 3 then touchedCoins[coin] = nil end
        end
        for coin, t in pairs(blockedCoins) do
            if not coin.Parent or now - t > 15 then blockedCoins[coin] = nil end
        end
        for coin in pairs(touchCounts) do
            if not coin.Parent then touchCounts[coin] = nil end
        end

        if Config.Farm then
            local hrp = getHRP(getChar(LocalPlayer))
            if hrp then
                -- полный мешок → авто-убийство
                if coin_bags_full() then
                    if Config.KillAllFullBag and not KEDoneThisRound and getKnife() then
                        KEDoneThisRound = true
                        task.spawn(function()
                            task.wait(0.3)
                            keKillAll()
                        end)
                    end
                    FarmTarget = nil
                    if Config.Method ~= "Safe" then
                        set_farm_noclip(false)
                    end
                    task.wait(1)
                else
                    local list = available_coins()
                    if #list > 0 then
                        -- таргет сбрасываем если монета собралась/помечена
                        if not FarmTarget or not coin_available(FarmTarget)
                            or touchedCoins[FarmTarget] then
                            FarmTarget = nearest_coin(hrp.Position, list)
                        end

                        if FarmTarget then
                            local cpos = FarmTarget.Position
                            local dest = cpos
                            local fireNow = false

                            if Config.Method == "Safe" then
                                -- летим НИЖЕ монеты, собираем через пол
                                dest = Vector3.new(cpos.X, cpos.Y - Config.YDepth, cpos.Z)
                                if flat_dist(hrp.Position, cpos) <= 5 then
                                    fire_touch(FarmTarget)
                                    FarmTarget = nil
                                end
                            else
                                -- Normal: летим прямо к монете
                                if (cpos - hrp.Position).Magnitude <= 6 then
                                    fire_touch(FarmTarget)
                                    FarmTarget = nil
                                end
                            end

                            if FarmTarget or Config.Method == "Safe" then
                                local mpos = Config.AvoidMurder and murderer_pos() or nil
                                dest = avoid_steer(hrp.Position, dest, mpos)
                                farm_move(hrp, dest, dt)
                            end
                        end
                    else
                        -- монет нет: в Safe висим на месте под полом (антигравитация), в Normal стоим
                        FarmTarget = nil
                        if Config.Method == "Safe" then
                            pcall(function()
                                hrp.CFrame = hrp.CFrame
                                hrp.AssemblyLinearVelocity = Vector3.zero
                                hrp.AssemblyAngularVelocity = Vector3.zero
                            end)
                        else
                            set_farm_noclip(false)
                            task.wait(0.2)
                        end
                    end
                end
            end
        else
            set_farm_noclip(false)
        end
        task.wait(0.03)
    end
end)

-- ═══ UI (WindUI) ═══
local Window = WindUI:CreateWindow({
    Title = "Crows Lite",
    SubTitle = "MM2 Auto Farm",
    Icon = "feather",
    Theme = "Dark",
    Size = UDim2.fromOffset(500, 360),
    OpenButton = {
        Title = "Crows Lite",
        CornerRadius = UDim.new(1, 0),
        StrokeThickness = 2,
        Enabled = true,
        Draggable = true,
        OnlyMobile = false,
        Scale = 0.5,
    },
})
pcall(function() Window:SetToggleKey(Enum.KeyCode.RightControl) end)

local TabFarm = Window:Tab({ Title = "Farm", Icon = "coins" })
local TabProt = Window:Tab({ Title = "Protect", Icon = "shield" })

TabFarm:Section({ Title = "Auto Farm" })
TabFarm:Toggle({
    Title = "Enable Auto Farm",
    Value = false,
    Callback = function(v)
        Config.Farm = v
        if v then CollectedCount = 0 end
        set_farm_noclip(false)
    end,
})
TabFarm:Dropdown({
    Title = "Method",
    Values = { "Normal", "Safe" },
    Value = "Normal",
    Callback = function(v)
        Config.Method = v
        set_farm_noclip(false)
    end,
})
TabFarm:Slider({
    Title = "Speed",
    Step = 1,
    Value = { Min = 10, Max = 30, Default = 23 },
    Callback = function(v) Config.Speed = v end,
})
TabFarm:Toggle({
    Title = "Avoid Murderer",
    Desc = "Держать дистанцию от убийцы",
    Value = false,
    Callback = function(v) Config.AvoidMurder = v end,
})

TabProt:Section({ Title = "Protection" })
TabProt:Toggle({
    Title = "Anti-Fling",
    Desc = "Защита от выброса другими игроками",
    Value = true,
    Callback = function(v) Config.AntiFling = v end,
})
TabProt:Slider({
    Title = "Max Velocity",
    Step = 10,
    Value = { Min = 100, Max = 2000, Default = 500 },
    Callback = function(v) Config.MaxVel = v end,
})
TabProt:Toggle({
    Title = "Auto Fling Murderer (if you die)",
    Desc = "Убийца тебя убил → после респавна его улетает",
    Value = false,
    Callback = function(v) Config.FlingOnDeath = v end,
})
TabProt:Toggle({
    Title = "Auto Kill All (full bag)",
    Desc = "Полный мешок монет → убиваешь всех (ты Murderer)",
    Value = false,
    Callback = function(v) Config.KillAllFullBag = v end,
})

WindUI:Notify({
    Title = "Crows Lite",
    Content = "Загружен! Farm only, без лишнего.",
    Icon = "feather",
    Duration = 4,
})
print("[CWH Lite] LOADED")
