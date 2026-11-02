-- ═══════════════════════════════════════════════════════════════
--  CROWS LITE | Murder Mystery 2 — Auto Farm
--  Лайт-версия Crows Hub: только авто-фарм
--  GUI: Wind UI | Executor: Delta
--  Меню: Right Shift (на телефоне — кнопка-перо после закрытия)
-- ═══════════════════════════════════════════════════════════════
print("[CL] START — Crows Lite загружается")

-- глушим старый инстанс, если перезапускаешь скрипт
getgenv().CL_RUN = false
pcall(function()
    if getgenv().CL_Window and getgenv().CL_Window.Destroy then
        getgenv().CL_Window:Destroy()
    end
end)
getgenv().CL_Window = nil
task.wait(0.2)

-- ═══ WIND UI LOADER ═══
local WindUI = nil
for attempt = 1, 3 do
    local ok, src = pcall(function()
        return game:HttpGet("https://raw.githubusercontent.com/KevinScripts2024/Gkfkfkdlwsk/refs/heads/main/wind%20(1).txt")
    end)
    if ok and type(src) == "string" and #src > 1000 then
        local chunk = loadstring(src)
        if chunk then
            local ok2, res = pcall(chunk)
            if ok2 and type(res) == "table" and type(res.CreateWindow) == "function" then
                WindUI = res
                print("[CL] Wind UI OK, попытка " .. attempt)
                break
            end
        end
    end
    warn("[CL] GUI попытка " .. attempt .. " не удалась, повтор...")
    task.wait(2)
end
if not WindUI then
    warn("[CL] Wind UI не загрузился за 3 попытки")
    pcall(function()
        game:GetService("StarterGui"):SetCore("SendNotification", {
            Title = "Crows Lite",
            Text = "GUI не загрузился — проверь интернет и запусти ещё раз",
            Duration = 8,
        })
    end)
    return
end
getgenv().CL_RUN = true

-- ═══ SERVICES ═══
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local LocalPlayer = Players.LocalPlayer
local realFireTouch = (type(firetouchinterest) == "function") and firetouchinterest or nil

-- ═══ UTILS ═══
local function Notify(t, c, d)
    pcall(function()
        WindUI:Notify({ Title = t or "Crows Lite", Content = c or "", Duration = d or 3 })
    end)
end

local function getChar(p) return p and p.Character end
local function getHum(c) return c and c:FindFirstChildOfClass("Humanoid") end
local function getHRP(c) return c and (c:FindFirstChild("HumanoidRootPart") or c.PrimaryPart) end

-- ═══ ROLES (PlayerDataChanged — мгновенно) ═══
local ServerRoles = {}
task.spawn(function()
    if not getgenv().CL_RUN then return end
    local ok, remotes = pcall(function() return ReplicatedStorage:WaitForChild("Remotes", 8) end)
    if ok and remotes then
        local gp = remotes:FindFirstChild("Gameplay") or remotes:FindFirstChild("Gameplay", true)
        local pd = gp and gp:FindFirstChild("PlayerDataChanged")
        if pd and pd:IsA("RemoteEvent") then
            pd.OnClientEvent:Connect(function(d)
                if type(d) == "table" then ServerRoles = d end
            end)
        end
    end
end)

local roleCache, roleCacheT = {}, 0
local function getRole(plr)
    local now = os.clock()
    if now - roleCacheT > 0.4 then roleCache = {} roleCacheT = now end
    if not roleCache[plr] then
        local role = "Unknown"
        -- реальный Gun в руках/рюкзаке = Sheriff (покрывает Hero)
        local c0 = plr and plr.Character
        if c0 then
            local bp0 = plr:FindFirstChild("Backpack")
            if (c0:FindFirstChild("Gun")) or (bp0 and bp0:FindFirstChild("Gun")) then
                roleCache[plr] = "Sheriff"
                return roleCache[plr]
            end
        end
        local sd = ServerRoles[plr.Name]
        if type(sd) == "table" and sd.Role then
            role = (sd.Role == "Hero") and "Sheriff" or sd.Role
            if role == "Sheriff" and sd.Dead then role = "Innocent" end
        else
            local c = plr and plr.Character
            if c then
                local bp = plr:FindFirstChild("Backpack")
                if (bp and bp:FindFirstChild("Knife")) or c:FindFirstChild("Knife") then role = "Murderer"
                elseif (bp and bp:FindFirstChild("Gun")) or c:FindFirstChild("Gun") then role = "Sheriff"
                else role = "Innocent" end
            end
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
local function getSheriff()
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LocalPlayer and getRole(p) == "Sheriff" then return p end
    end
end
local function getMap()
    for _, o in ipairs(workspace:GetChildren()) do
        if o:FindFirstChild("CoinContainer") and o:FindFirstChild("Spawns") then return o end
    end
end

-- ═══════════════════════════════════════════════════════════════
--  AUTO FARM (порт из Crows Hub full)
--  Режимы: Normal — по карте; Safe Standing — под полом стоя;
--          Safe Lying — под полом лёжа (лицом вниз)
-- ═══════════════════════════════════════════════════════════════
local AutoFarmSystem = {
    Enabled = false, Mode = "Normal", AvoidMurder = false,
    AutoReset = false, CollectedCount = 0, CoinTarget = 0,
    Target = nil, LastTouch = 0, NoclipCache = {},
    TweenMode = false, TweenSpeed = 35, YDepth = 6,
}
getgenv().CL_FarmRef = AutoFarmSystem

local FARM_SPEED = 23
local DOWN_RISE_XZ = 4
local AVOID_DIST = 40
local RISE_SAFE_DIST = 20
local touchedCoins = {} -- [coin] = время touch
local blockedCoins = {} -- [coin] = время блока (застряла 3 раза)
local touchCounts = {}  -- [coin] = сколько раз touch не сработал
local farmToggleRef = nil -- тоггл из GUI (синхронизация при достижении цели)

local function farm_is_down()
    return AutoFarmSystem.Mode ~= "Normal"
end
local function farm_is_lying()
    return AutoFarmSystem.Mode == "Safe Lying"
end

local function farm_hrp()
    local c = getChar(LocalPlayer)
    return c and getHRP(c)
end
local function flat_dist(a, b)
    return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
end
local function coin_available(v)
    return v and v.Parent and v:IsA("BasePart")
        and not v:GetAttribute("Collected")
        and not v:GetAttribute("Delete")
end
local function coin_part(c)
    if not c or not c.Parent then return nil end
    if c:IsA("BasePart") then return c end
    if c:IsA("Model") then return c:FindFirstChildWhichIsA("BasePart", true) end
    return nil
end

local function available_coins()
    local list = {}
    -- 1) самый точный способ (из сурса): CoinContainer → Coin_Server
    local map = getMap()
    local cont = map and map:FindFirstChild("CoinContainer")
    if cont then
        for _, c in ipairs(cont:GetChildren()) do
            if c.Name == "Coin_Server" and not c:FindFirstChild("CollectedCoin") then
                local p = coin_part(c)
                if p then list[#list + 1] = p end
            end
        end
    end
    -- 2) запасной способ: тег CoinVisual
    if #list == 0 then
        local cs = game:GetService("CollectionService")
        for _, v in ipairs(cs:GetTagged("CoinVisual")) do
            if coin_available(v) then list[#list + 1] = v end
        end
    end
    -- 3) последний фолбэк: скан по имени
    if #list == 0 then
        for _, obj in ipairs(workspace:GetDescendants()) do
            if obj:IsA("BasePart")
                and (obj.Name:lower():find("coin") or obj.Name:lower():find("collectible"))
                and coin_available(obj) then
                list[#list + 1] = obj
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

local function set_farm_noclip(on, lying)
    local char = getChar(LocalPlayer)
    local hum = getHum(char)
    if on then
        if not char then return end
        -- PlatformStand ТОЛЬКО в режиме лёжа — стоя он даёт джиттер
        if hum and lying then
            pcall(function() hum.PlatformStand = true end)
        end
        for _, p in ipairs(char:GetDescendants()) do
            if p:IsA("BasePart") and p.CanCollide then
                if AutoFarmSystem.NoclipCache[p] == nil then
                    AutoFarmSystem.NoclipCache[p] = p.CanCollide
                end
                p.CanCollide = false
            end
        end
    else
        if hum then pcall(function() hum.PlatformStand = false end) end
        for p, v in pairs(AutoFarmSystem.NoclipCache) do
            if p and p.Parent then pcall(function() p.CanCollide = v end) end
        end
        AutoFarmSystem.NoclipCache = {}
    end
end

-- страховка: движок любит вернуть CanCollide — применяем каждый физ-шаг, пока фарм включён
RunService.Stepped:Connect(function()
    if AutoFarmSystem.Enabled and getChar(LocalPlayer) then
        set_farm_noclip(true, farm_is_lying())
    end
end)

local function murderer_hrp()
    local m = getMurderer()
    if not m then return nil end
    local c = getChar(m)
    local h = c and getHRP(c)
    local hum = c and getHum(c)
    if h and (not hum or hum.Health > 0) then return h end
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

local function fire_touch(coin)
    if not realFireTouch or not coin or not coin.Parent then return false end
    local now = os.clock()
    if now - AutoFarmSystem.LastTouch < 0.05 then return false end
    AutoFarmSystem.LastTouch = now
    local hrp = farm_hrp()
    if not hrp then return false end
    for _, p in ipairs(touch_targets(coin)) do
        pcall(realFireTouch, hrp, p, 0)
        pcall(realFireTouch, hrp, p, 1)
    end
    -- помечаем монету — не летим в неё повторно
    touchedCoins[coin] = now
    -- застряли: 3-й touch той же монеты — блокируем её на 10 сек
    touchCounts[coin] = (touchCounts[coin] or 0) + 1
    if touchCounts[coin] >= 3 then
        blockedCoins[coin] = now
        touchCounts[coin] = nil
    end
    AutoFarmSystem.CollectedCount = AutoFarmSystem.CollectedCount + 1
    return true
end

local function farm_move(hrp, dest, dt)
    local dir = dest - hrp.Position
    local dist = dir.Magnitude
    local speed = AutoFarmSystem.TweenMode and (AutoFarmSystem.TweenSpeed or 35) or FARM_SPEED
    local np = dest
    if dist > 0.1 then
        np = hrp.Position + dir.Unit * math.min(speed * dt, dist)
    end
    local cf = CFrame.new(np)
    -- лёжа: разворот персонажа лицом к полу
    if farm_is_lying() then
        cf = cf * CFrame.Angles(-math.pi * 0.5, 0, 0)
    end
    pcall(function()
        hrp.CFrame = cf
        hrp.AssemblyLinearVelocity = Vector3.zero
        hrp.AssemblyAngularVelocity = Vector3.zero
    end)
end

local function avoid_steer(cur, dest, mpos)
    if not (AutoFarmSystem.AvoidMurder and mpos) then return dest end
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

local function farm_reset()
    AutoFarmSystem.Target = nil
    touchedCoins = {}
    touchCounts = {}
    blockedCoins = {}
    AutoFarmSystem.NoclipCache = {}
end

-- ═══ ГЛАВНЫЙ ЦИКЛ ФАРМА ═══
local lastFrame = os.clock()
task.spawn(function()
    while true do
        if not getgenv().CL_RUN then break end
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

        if AutoFarmSystem.Enabled then
            -- цель по монетам (0 = без лимита)
            if AutoFarmSystem.CoinTarget > 0 and AutoFarmSystem.CollectedCount >= AutoFarmSystem.CoinTarget then
                AutoFarmSystem.Enabled = false
                set_farm_noclip(false)
                if farmToggleRef then pcall(function() farmToggleRef:Set(false) end) end
                Notify("Auto Farm", "Цель собрана: " .. AutoFarmSystem.CollectedCount .. " монет!", nil, 4)
                if AutoFarmSystem.AutoReset then
                    local hum = getHum(getChar(LocalPlayer))
                    if hum then pcall(function() hum.Health = 0 end) end
                end
                task.wait(1)
                continue
            end

            local hrp = farm_hrp()
            if hrp then
                local isDown = farm_is_down()
                local isLying = farm_is_lying()
                local list = available_coins()

                if coin_bags_full() then
                    if AutoFarmSystem.AutoReset then
                        local hum = getHum(getChar(LocalPlayer))
                        if hum then pcall(function() hum.Health = 0 end) end
                    elseif isDown then
                        -- Safe: висим на месте под полом (антигравитация)
                        pcall(function()
                            hrp.CFrame = hrp.CFrame
                            hrp.AssemblyLinearVelocity = Vector3.zero
                            hrp.AssemblyAngularVelocity = Vector3.zero
                        end)
                    else
                        set_farm_noclip(false)
                    end
                    task.wait(1)
                    continue
                end

                if #list > 0 then
                    local mhrp = AutoFarmSystem.AvoidMurder and murderer_hrp() or nil
                    local mpos = mhrp and mhrp.Position or nil

                    -- таргет сбрасываем если монета собралась/помечена
                    if not AutoFarmSystem.Target or not coin_available(AutoFarmSystem.Target)
                        or touchedCoins[AutoFarmSystem.Target] then
                        AutoFarmSystem.Target = nearest_coin(hrp.Position, list)
                    end

                    if AutoFarmSystem.Target then
                        set_farm_noclip(true, isLying)
                        local cpos = AutoFarmSystem.Target.Position
                        local dest = cpos

                        if isDown then
                            -- Safe: летим под полом, поднимаемся только к монете
                            local xz = flat_dist(hrp.Position, cpos)
                            local safe_to_rise = (not mpos) or flat_dist(hrp.Position, mpos) > RISE_SAFE_DIST
                            if xz <= DOWN_RISE_XZ and safe_to_rise then
                                dest = cpos
                                fire_touch(AutoFarmSystem.Target)
                                AutoFarmSystem.Target = nil
                            else
                                dest = Vector3.new(cpos.X, cpos.Y - AutoFarmSystem.YDepth, cpos.Z)
                            end
                        elseif (cpos - hrp.Position).Magnitude <= 6 then
                            fire_touch(AutoFarmSystem.Target)
                            AutoFarmSystem.Target = nil
                        end

                        if AutoFarmSystem.Target or isDown then
                            dest = avoid_steer(hrp.Position, dest, mpos)
                            farm_move(hrp, dest, dt)
                        end
                    elseif mpos then
                        set_farm_noclip(true, isLying)
                        local away = Vector3.new(hrp.Position.X - mpos.X, 0, hrp.Position.Z - mpos.Z)
                        if away.Magnitude < 0.1 then away = Vector3.new(1, 0, 0) end
                        away = away.Unit
                        farm_move(hrp, hrp.Position + away * 40, dt)
                    else
                        -- таргета нет (все монеты затроганы/заблокированы):
                        -- в Safe висим под полом, в Normal стоим на карте
                        if isDown then
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
                else
                    -- монет нет: в Safe висим под полом, в Normal стоим на карте
                    AutoFarmSystem.Target = nil
                    if isDown then
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
        task.wait(0.03)
    end
end)

-- ═══ COIN AURA (порт из full) ═══
local CA4 = { On = false, Radius = 15, Delay = 0.05, Last = 0 }

task.spawn(function()
    while task.wait(0.05) do
        if not getgenv().CL_RUN then break end
        if CA4.On then
            pcall(function()
                local now = os.clock()
                if now - CA4.Last < CA4.Delay then return end
                local char = getChar(LocalPlayer)
                local root = getHRP(char)
                if not root then return end
                local map = getMap()
                local cont = map and map:FindFirstChild("CoinContainer")
                if not cont then return end
                local touched = false
                for _, c in ipairs(cont:GetDescendants()) do
                    if c:IsA("BasePart")
                        and not c:GetAttribute("Collected")
                        and not c:GetAttribute("Delete")
                        and (c.Position - root.Position).Magnitude <= CA4.Radius then
                        pcall(function()
                            realFireTouch(root, c, 0)
                            realFireTouch(root, c, 1)
                        end)
                        touched = true
                    end
                end
                if touched then CA4.Last = now end
            end)
        end
    end
end)

-- ═══ ANTI-FLING (порт из full) ═══
local flinging = false -- пока сами флим — анти-флинг не мешает
local AntiFling = {
    On = true, MaxVel = 500, ClearMovers = true, DisableEnemyCollide = true,
}

task.spawn(function()
    while task.wait(0.05) do
        if not getgenv().CL_RUN then break end
        if AntiFling.On and not flinging then
            pcall(function()
                local char = getChar(LocalPlayer)
                local hrp = getHRP(char)
                if not hrp then return end

                -- 1) снос BodyMovers у себя
                if AntiFling.ClearMovers then
                    for _, obj in pairs(char:GetDescendants()) do
                        if obj:IsA("BodyVelocity") or obj:IsA("BodyAngularVelocity")
                            or obj:IsA("BodyThrust") or obj:IsA("BodyGyro")
                            or obj:IsA("LinearVelocity") or obj:IsA("AngularVelocity")
                            or obj:IsA("VectorForce") or obj:IsA("Torque") then
                            -- не трогаем свой флинг-инструмент
                            if obj.Name ~= "CL_EpixVel" then
                                obj:Destroy()
                            end
                        end
                    end
                end

                -- 2) чужие CanCollide off + обнуление скорости HRP
                if AntiFling.DisableEnemyCollide then
                    for _, other in ipairs(Players:GetPlayers()) do
                        if other ~= LocalPlayer and other.Character then
                            for _, part in ipairs(other.Character:GetChildren()) do
                                if part:IsA("BasePart") and part.CanCollide then
                                    part.CanCollide = false
                                    if part.Name == "HumanoidRootPart" then
                                        part.Velocity = Vector3.zero
                                        part.RotVelocity = Vector3.zero
                                    end
                                end
                            end
                        end
                    end
                end

                -- 3) сброс аномальной своей скорости
                local vel = hrp.AssemblyLinearVelocity or hrp.Velocity
                local rot = hrp.AssemblyAngularVelocity or hrp.RotVelocity
                if vel and vel.Magnitude > AntiFling.MaxVel then
                    hrp.AssemblyLinearVelocity = Vector3.zero
                    hrp.Velocity = Vector3.zero
                end
                if rot and rot.Magnitude > AntiFling.MaxVel then
                    hrp.AssemblyAngularVelocity = Vector3.zero
                    hrp.RotVelocity = Vector3.zero
                end
            end)
        end
    end
end)

-- ═══ FLING (SkidFling из Vision Hub, порт из full) ═══
local function SkidFling(TargetPlayer)
    if not TargetPlayer or not TargetPlayer.Character then return end

    local Character = LocalPlayer and LocalPlayer.Character
    local Humanoid = Character and (Character:FindFirstChildOfClass("Humanoid") or Character:FindFirstChild("Humanoid"))
    local RootPart = Character and (Character:FindFirstChild("HumanoidRootPart") or Character.PrimaryPart)

    local TCharacter = TargetPlayer and TargetPlayer.Character
    local THumanoid, TRootPart, THead, Accessory, Handle

    if TCharacter and TCharacter:FindFirstChildOfClass("Humanoid") then
        THumanoid = TCharacter:FindFirstChildOfClass("Humanoid")
    end
    if THumanoid then
        TRootPart = TCharacter:FindFirstChild("HumanoidRootPart") or TCharacter.PrimaryPart or THumanoid.RootPart
    end
    if TCharacter and TCharacter:FindFirstChild("Head") then
        THead = TCharacter.Head
    end
    if TCharacter and TCharacter:FindFirstChildOfClass("Accessory") then
        Accessory = TCharacter:FindFirstChildOfClass("Accessory")
    end
    if Accessory and Accessory:FindFirstChild("Handle") then
        Handle = Accessory.Handle
    end

    if Character and Humanoid and RootPart then
        -- флаг остановки: Стоп-кнопка прерывает на любом шаге
        getgenv().CL_FlingStop = false

        if RootPart.Velocity.Magnitude < 50 then
            getgenv().CL_OldPos = RootPart.CFrame
        end

        local CurrentCam = workspace.CurrentCamera
        if THead then
            CurrentCam.CameraSubject = THead
        elseif not THead and Handle then
            CurrentCam.CameraSubject = Handle
        elseif THumanoid and TRootPart then
            CurrentCam.CameraSubject = THumanoid
        end
        if not (TCharacter and TCharacter:FindFirstChildWhichIsA("BasePart")) then
            return
        end

        local FPos = function(BasePart, Pos, Ang)
            if getgenv().CL_FlingStop then return end
            RootPart.CFrame = CFrame.new(BasePart.Position) * Pos * Ang
            pcall(function()
                if Character and Character.PrimaryPart then
                    Character:SetPrimaryPartCFrame(CFrame.new(BasePart.Position) * Pos * Ang)
                end
            end)
            RootPart.Velocity = Vector3.new(9e7, 9e7 * 10, 9e7)
            RootPart.RotVelocity = Vector3.new(9e8, 9e8, 9e8)
        end

        local SFBasePart = function(BasePart)
            local TimeToWait = 2
            local Time = tick()
            local Angle = 0
            repeat
                if getgenv().CL_FlingStop then break end
                if RootPart and THumanoid then
                    if BasePart.Velocity.Magnitude < 50 then
                        Angle = Angle + 100
                        FPos(BasePart, CFrame.new(0, 1.5, 0) + THumanoid.MoveDirection * BasePart.Velocity.Magnitude / 1.25, CFrame.Angles(math.rad(Angle), 0, 0))
                        task.wait()
                        if getgenv().CL_FlingStop then break end
                        FPos(BasePart, CFrame.new(0, -1.5, 0) + THumanoid.MoveDirection * BasePart.Velocity.Magnitude / 1.25, CFrame.Angles(math.rad(Angle), 0, 0))
                        task.wait()
                        if getgenv().CL_FlingStop then break end
                        FPos(BasePart, CFrame.new(2.25, 1.5, -2.25) + THumanoid.MoveDirection * BasePart.Velocity.Magnitude / 1.25, CFrame.Angles(math.rad(Angle), 0, 0))
                        task.wait()
                        if getgenv().CL_FlingStop then break end
                        FPos(BasePart, CFrame.new(-2.25, -1.5, 2.25) + THumanoid.MoveDirection * BasePart.Velocity.Magnitude / 1.25, CFrame.Angles(math.rad(Angle), 0, 0))
                        task.wait()
                        if getgenv().CL_FlingStop then break end
                        FPos(BasePart, CFrame.new(0, 1.5, 0) + THumanoid.MoveDirection, CFrame.Angles(math.rad(Angle), 0, 0))
                        task.wait()
                        if getgenv().CL_FlingStop then break end
                        FPos(BasePart, CFrame.new(0, -1.5, 0) + THumanoid.MoveDirection, CFrame.Angles(math.rad(Angle), 0, 0))
                        task.wait()
                    else
                        FPos(BasePart, CFrame.new(0, 1.5, THumanoid.WalkSpeed), CFrame.Angles(math.rad(90), 0, 0))
                        task.wait()
                        if getgenv().CL_FlingStop then break end
                        FPos(BasePart, CFrame.new(0, -1.5, -THumanoid.WalkSpeed), CFrame.Angles(0, 0, 0))
                        task.wait()
                        if getgenv().CL_FlingStop then break end
                        FPos(BasePart, CFrame.new(0, 1.5, THumanoid.WalkSpeed), CFrame.Angles(math.rad(90), 0, 0))
                        task.wait()
                        if getgenv().CL_FlingStop then break end
                        FPos(BasePart, CFrame.new(0, 1.5, TRootPart and TRootPart.Velocity.Magnitude / 1.25 or 0), CFrame.Angles(math.rad(90), 0, 0))
                        task.wait()
                        if getgenv().CL_FlingStop then break end
                        FPos(BasePart, CFrame.new(0, -1.5, -(TRootPart and TRootPart.Velocity.Magnitude / 1.25 or 0)), CFrame.Angles(0, 0, 0))
                        task.wait()
                        if getgenv().CL_FlingStop then break end
                        FPos(BasePart, CFrame.new(0, 1.5, TRootPart and TRootPart.Velocity.Magnitude / 1.25 or 0), CFrame.Angles(math.rad(90), 0, 0))
                        task.wait()
                        if getgenv().CL_FlingStop then break end
                        FPos(BasePart, CFrame.new(0, -1.5, 0), CFrame.Angles(math.rad(90), 0, 0))
                        task.wait()
                        if getgenv().CL_FlingStop then break end
                        FPos(BasePart, CFrame.new(0, -1.5, 0), CFrame.Angles(0, 0, 0))
                        task.wait()
                        if getgenv().CL_FlingStop then break end
                        FPos(BasePart, CFrame.new(0, -1.5, 0), CFrame.Angles(math.rad(-90), 0, 0))
                        task.wait()
                        if getgenv().CL_FlingStop then break end
                        FPos(BasePart, CFrame.new(0, -1.5, 0), CFrame.Angles(0, 0, 0))
                        task.wait()
                    end
                else
                    break
                end
            until BasePart.Velocity.Magnitude > 500 or BasePart.Parent ~= TargetPlayer.Character
                or TargetPlayer.Parent ~= Players or TargetPlayer.Character ~= TCharacter
                or (THumanoid and THumanoid.Sit) or (Humanoid and Humanoid.Health <= 0)
                or tick() > Time + TimeToWait
        end

        if not getgenv().CL_FPDH then
            getgenv().CL_FPDH = workspace.FallenPartsDestroyHeight
        end
        workspace.FallenPartsDestroyHeight = 0/0

        local BV = Instance.new("BodyVelocity")
        BV.Name = "CL_EpixVel"
        BV.Parent = RootPart
        BV.Velocity = Vector3.new(9e8, 9e8, 9e8)
        BV.MaxForce = Vector3.new(1/0, 1/0, 1/0)

        Humanoid:SetStateEnabled(Enum.HumanoidStateType.Seated, false)

        if TRootPart and THead then
            if (TRootPart.CFrame.p - THead.CFrame.p).Magnitude > 5 then
                SFBasePart(THead)
            else
                SFBasePart(TRootPart)
            end
        elseif TRootPart and not THead then
            SFBasePart(TRootPart)
        elseif not TRootPart and THead then
            SFBasePart(THead)
        elseif not TRootPart and not THead and Accessory and Handle then
            SFBasePart(Handle)
        end

        if BV and BV.Parent then BV:Destroy() end
        Humanoid:SetStateEnabled(Enum.HumanoidStateType.Seated, true)
        if workspace.CurrentCamera and Humanoid then
            workspace.CurrentCamera.CameraSubject = Humanoid
        end

        -- возврат на исходную позицию (прерывается Стопом)
        repeat
            if getgenv().CL_FlingStop then break end
            if getgenv().CL_OldPos then
                RootPart.CFrame = getgenv().CL_OldPos * CFrame.new(0, .5, 0)
                pcall(function()
                    if Character and Character.PrimaryPart then
                        Character:SetPrimaryPartCFrame(getgenv().CL_OldPos * CFrame.new(0, .5, 0))
                    end
                end)
            end
            Humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
            for _, x in ipairs(Character:GetChildren()) do
                if x:IsA("BasePart") then
                    x.Velocity, x.RotVelocity = Vector3.new(), Vector3.new()
                end
            end
            task.wait()
        until not getgenv().CL_OldPos or (RootPart.Position - getgenv().CL_OldPos.p).Magnitude < 25

        if getgenv().CL_FPDH then
            workspace.FallenPartsDestroyHeight = getgenv().CL_FPDH
        end

        getgenv().CL_OldPos = nil
    end
end

local function doFling(plr)
    if flinging then Notify("Fling", "Уже идёт флинг — жми Стоп", nil, 2) return end
    if not plr then return end
    flinging = true
    getgenv().CL_FlingStop = false
    Notify("Fling", "Флинг: " .. plr.Name, nil, 3)
    task.spawn(function()
        pcall(SkidFling, plr)
        flinging = false
    end)
end
getgenv().CL_DoFling = doFling

local function stopFling()
    getgenv().CL_FlingStop = true
    flinging = false
    Notify("Fling", "Stopped", nil, 2)
end

-- ─── AUTO FLING MURDERER ПОСЛЕ СМЕРТИ (порт из full) ───
local AutoFlingDeath = { On = false }
local deathFlingPending = false

local function hookHumanoid(char)
    task.spawn(function()
        local hum = char:WaitForChild("Humanoid", 5)
        if hum then
            hum.Died:Connect(function()
                if AutoFlingDeath.On then
                    deathFlingPending = true
                    Notify("Auto Fling", "Умер — после респавна флингую убийцу", nil, 3)
                end
            end)
        end
    end)
end

if LocalPlayer.Character then hookHumanoid(LocalPlayer.Character) end

-- ═══ AUTO KILL EVERYONE (порт из full) ═══
local AutoKE = { On = false, DoneThisRound = false }

local function keGetKnife()
    local c = getChar(LocalPlayer)
    if c and c:FindFirstChild("Knife") then return c:FindFirstChild("Knife") end
    local bp = LocalPlayer:FindFirstChild("Backpack")
    return bp and bp:FindFirstChild("Knife")
end

local function keKillAll()
    local knife = keGetKnife()
    if not knife then return 0 end
    local c = getChar(LocalPlayer)
    if knife.Parent ~= c then
        local hum = getHum(c)
        if hum then
            pcall(function() hum:EquipTool(knife) end)
            task.wait(0.2)
            knife = keGetKnife()
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
                if handle then
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

-- ═══ INSTANT GRAB GUN (порт из full) ═══
local grabGunOn = false

task.spawn(function()
    while task.wait(0.15) do
        if not getgenv().CL_RUN then break end
        if grabGunOn then
            pcall(function()
                local map = getMap()
                local root = getHRP(getChar(LocalPlayer))
                local drop = map and map:FindFirstChild("GunDrop", true)
                if drop and root and realFireTouch then
                    realFireTouch(drop, root, 1)
                    realFireTouch(drop, root, 0)
                end
            end)
        end
    end
end)

-- уведомление когда пистолет реально взят
task.spawn(function()
    local seen = false
    while task.wait(0.3) do
        if not getgenv().CL_RUN then break end
        pcall(function()
            local c = getChar(LocalPlayer)
            local bp = LocalPlayer:FindFirstChild("Backpack")
            local has = (c and c:FindFirstChild("Gun")) or (bp and bp:FindFirstChild("Gun"))
            if has and not seen and grabGunOn then
                seen = true
                Notify("Grab Gun", "Gun взят!", nil, 3)
            elseif not has then
                seen = false
            end
        end)
    end
end)

-- цикл Auto Kill (собрал цель / полную сумку → убить всех)
task.spawn(function()
    while task.wait(0.5) do
        if not getgenv().CL_RUN then break end
        if AutoKE.On and not AutoKE.DoneThisRound then
            local collected = AutoFarmSystem.CollectedCount
            local amMurd = keGetKnife() ~= nil
            local reached = (AutoFarmSystem.CoinTarget > 0 and collected >= AutoFarmSystem.CoinTarget)
                or coin_bags_full()
            if amMurd and reached then
                AutoKE.DoneThisRound = true
                Notify("Auto Kill", "Монеты собраны — убиваю всех!", nil, 4)
                task.wait(0.3)
                local n = keKillAll()
                Notify("Auto Kill", "Атаковано: " .. n, nil, 3)
            end
        end
    end
end)

-- ═══ SILENT AIM (Simple/Pro, порт из full) ═══
local SA2 = { On = false, Mode = "Simple", Target = "Murderer", Predict = true, Range = 300 }
local WS2, origM, origT, hooked = nil, nil, nil, false

local function getWS()
    if WS2 then return WS2 end
    local ok, m = pcall(function()
        return require(ReplicatedStorage:WaitForChild("ClientServices", 10):WaitForChild("WeaponService", 10))
    end)
    if ok and type(m) == "table" then WS2 = m end
    return WS2
end

local function pickSA()
    if SA2.Target == "Murderer" then return getMurderer() end
    if SA2.Target == "Sheriff" then return getSheriff() end
    local my = getHRP(getChar(LocalPlayer))
    if not my then return end
    local best, bd = nil, math.huge
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LocalPlayer then
            local h = getHum(getChar(p))
            local hrp = getChar(p) and getHRP(getChar(p))
            if h and h.Health > 0 and hrp then
                local d = (hrp.Position - my.Position).Magnitude
                if d < bd then bd = d best = p end
            end
        end
    end
    return best
end

local function aimCF()
    local t = pickSA()
    if not (t and t.Character) then return end
    local c = t.Character
    local part = c:FindFirstChild("Head") or c:FindFirstChild("UpperTorso")
        or c:FindFirstChild("Torso") or c:FindFirstChild("HumanoidRootPart")
    local my = getHRP(getChar(LocalPlayer))
    if not (part and my) then return end
    local pos = part.Position
    local dist = (pos - my.Position).Magnitude
    if SA2.Mode == "Simple" then
        if dist > SA2.Range then return end
        local params = RaycastParams.new()
        params.FilterType = Enum.RaycastFilterType.Exclude
        params.FilterDescendantsInstances = { LocalPlayer.Character }
        local hit = workspace:Raycast(my.Position, pos - my.Position, params)
        if hit and not (hit.Instance and hit.Instance:IsDescendantOf(c)) then return end
    elseif SA2.Mode == "Pro" then
        if dist > SA2.Range then return end
    end
    if SA2.Predict then
        local root = getHRP(c)
        if root then
            local vel = root.AssemblyLinearVelocity or Vector3.zero
            local ping = 0
            pcall(function() ping = LocalPlayer:GetNetworkPing() or 0 end)
            if ping > 1 then ping = ping / 1000 end
            pos = pos + vel * (ping + 0.05)
        end
    end
    return CFrame.new(pos)
end

local function installHooks()
    local m = getWS()
    if not m then
        Notify("Silent Aim", "WeaponService не найден", nil, 3)
        return false
    end
    if hooked then return true end
    pcall(function() setreadonly(m, false) end)
    if type(m.GetMouseTargetCFrame) == "function" then
        origM = m.GetMouseTargetCFrame
        m.GetMouseTargetCFrame = function(s, ...)
            if SA2.On then
                local cf = aimCF()
                if cf then return cf end
            end
            return origM(s, ...)
        end
    end
    if type(m.GetTargetPosition) == "function" then
        origT = m.GetTargetPosition
        m.GetTargetPosition = function(s, ...)
            if SA2.On then
                local cf = aimCF()
                if cf then return cf.Position end
            end
            return origT(s, ...)
        end
    end
    hooked = true
    return true
end

local function removeHooks()
    if WS2 and hooked then
        pcall(function() setreadonly(WS2, false) end)
        if origM then pcall(function() WS2.GetMouseTargetCFrame = origM end) end
        if origT then pcall(function() WS2.GetTargetPosition = origT end) end
    end
    hooked = false
end

-- ═══ ОБЩИЕ РЕСЕТЫ (смерть + новый раунд) ═══
LocalPlayer.CharacterAdded:Connect(function(char)
    farm_reset()
    AutoKE.DoneThisRound = false
    -- авто-флинг убийцы после смерти
    if deathFlingPending and AutoFlingDeath.On then
        deathFlingPending = false
        -- даём нормально заспавниться
        task.delay(2.5, function()
            if not AutoFlingDeath.On then return end
            local mur = getMurderer()
            if mur and getgenv().CL_DoFling then
                Notify("Auto Fling", "Флинг убийцы: " .. mur.Name, nil, 3)
                getgenv().CL_DoFling(mur)
            else
                Notify("Auto Fling", "Murderer не найден", nil, 3)
            end
        end)
    end
    hookHumanoid(char)
end)

task.spawn(function()
    if not getgenv().CL_RUN then return end
    local ok, remote = pcall(function()
        return ReplicatedStorage:WaitForChild("Remotes", 15):WaitForChild("Gameplay", 15):WaitForChild("CoinsStarted", 15)
    end)
    if ok and remote and remote:IsA("RemoteEvent") then
        remote.OnClientEvent:Connect(function()
            farm_reset()
            AutoKE.DoneThisRound = false
        end)
    end
end)

-- ═══════════════════════════════════════════════════════════════
--  WIND UI
-- ═══════════════════════════════════════════════════════════════
local Window = nil
local okWin = pcall(function()
    Window = WindUI:CreateWindow({
        Title = "Crows Lite",
        Author = "MM2 Auto Farm • by Crows Hub",
        Icon = "feather",
        Folder = "CrowsLite",
        Size = UDim2.fromOffset(560, 380),
        ToggleKey = Enum.KeyCode.RightShift,
        SideBarWidth = 155,
    })
end)
if not okWin or not Window then
    -- фолбэк: окно без иконки (если feather не отдался)
    warn("[CL] CreateWindow с иконкой упал — пробую без иконки")
    Window = WindUI:CreateWindow({
        Title = "Crows Lite",
        Author = "MM2 Auto Farm • by Crows Hub",
        Folder = "CrowsLite",
        Size = UDim2.fromOffset(560, 380),
        ToggleKey = Enum.KeyCode.RightShift,
        SideBarWidth = 155,
    })
end
getgenv().CL_Window = Window

-- перо-кнопка после закрытия меню (и на ПК тоже, не только на телефоне)
pcall(function()
    Window:EditOpenButton({
        Title = "Crows Lite",
        Enabled = true,
        Draggable = true,
        OnlyMobile = false,
        CornerRadius = UDim.new(1, 0),
        StrokeThickness = 2,
    })
end)
pcall(function() Window:SetToggleKey(Enum.KeyCode.RightShift) end)

local FarmTab = Window:Tab({ Title = "Фарм", Icon = "coins", Desc = "Авто-фарм монет" })
local CombatTab = Window:Tab({ Title = "Бой", Icon = "crosshair", Desc = "Пистолет, килл, аим" })
local ProtectTab = Window:Tab({ Title = "Защита", Icon = "shield", Desc = "Анти-флинг" })

-- слайдер + ручной ввод одним блоком
local function addNum(tab, title, desc, min, max, def, setter)
    tab:Slider({
        Title = title,
        Desc = desc,
        Step = 1,
        Value = { Min = min, Max = max, Default = def },
        Callback = function(v) setter(v) end,
    })
    tab:Input({
        Title = title .. " (вписать)",
        Placeholder = "число " .. min .. "-" .. max,
        Callback = function(txt)
            local digits = tostring(txt or ""):gsub("[^%d]", "")
            local n = tonumber(digits)
            if n then
                n = math.clamp(n, min, max)
                setter(n)
                Notify("Crows Lite", title .. ": " .. n, nil, 2)
            else
                Notify("Crows Lite", "Впиши число " .. min .. "-" .. max, nil, 2)
            end
        end,
    })
end

-- ─── ВКЛАДКА ФАРМ ───
FarmTab:Section({ Title = "Авто Фарм" })
FarmTab:Paragraph({
    Title = "Crows Lite",
    Desc = "Normal — сбор по карте\nSafe Standing — под полом в полный рост\nSafe Lying — под полом лёжа\nRight Shift — меню (на телефоне кнопка-перо)",
})

farmToggleRef = FarmTab:Toggle({
    Title = "Авто-фарм",
    Desc = "Летает по монетам и собирает их",
    Value = false,
    Callback = function(v)
        AutoFarmSystem.Enabled = v
        if v then
            AutoFarmSystem.CollectedCount = 0
            touchedCoins = {}
            Notify("Auto Farm", "Старт! Метод: " .. AutoFarmSystem.Mode, nil, 3)
        else
            set_farm_noclip(false)
        end
    end,
})

FarmTab:Dropdown({
    Title = "Метод фарма",
    Desc = "Normal / Safe Standing (стоя) / Safe Lying (лёжа)",
    Values = { "Normal", "Safe Standing", "Safe Lying" },
    Value = "Normal",
    Callback = function(v)
        AutoFarmSystem.Mode = v
        AutoFarmSystem.Target = nil
        set_farm_noclip(false)
    end,
})

addNum(FarmTab, "Сколько монет собрать", "0 = без лимита (до полной сумки)", 0, 50, 0,
    function(n) AutoFarmSystem.CoinTarget = n end)

addNum(FarmTab, "Скорость фарма", "Скорость полёта к монете", 15, 100, 23,
    function(n) FARM_SPEED = n end)

FarmTab:Toggle({
    Title = "Плавный режим (твин)",
    Desc = "Плавное движение вместо рывков",
    Value = false,
    Callback = function(v) AutoFarmSystem.TweenMode = v end,
})

addNum(FarmTab, "Скорость твина", "Работает в плавном режиме", 10, 80, 35,
    function(n) AutoFarmSystem.TweenSpeed = n end)

addNum(FarmTab, "Глубина под полом", "Насколько ниже монеты лететь (Safe)", 1, 8, 6,
    function(n) AutoFarmSystem.YDepth = n end)

FarmTab:Toggle({
    Title = "Избегать убийцы",
    Desc = "Облетает монеты рядом с Murderer",
    Value = false,
    Callback = function(v)
        AutoFarmSystem.AvoidMurder = v
        AutoFarmSystem.Target = nil
    end,
})

FarmTab:Toggle({
    Title = "Респавн при полной сумке",
    Desc = "Умирает, чтобы начать сбор заново",
    Value = false,
    Callback = function(v) AutoFarmSystem.AutoReset = v end,
})

FarmTab:Section({ Title = "Coin Aura" })
FarmTab:Toggle({
    Title = "Coin Aura",
    Desc = "Собирает монеты вокруг без полёта",
    Value = false,
    Callback = function(v) CA4.On = v end,
})
addNum(FarmTab, "Радиус ауры", "Студы вокруг персонажа", 3, 35, 15,
    function(n) CA4.Radius = n end)

-- ─── ВКЛАДКА БОЙ ───
CombatTab:Section({ Title = "Пистолет" })
CombatTab:Toggle({
    Title = "Авто-взять пистолет",
    Desc = "Подбирает Gun сразу после отчёта — работает во время фарма и после",
    Value = false,
    Callback = function(v) grabGunOn = v end,
})

CombatTab:Section({ Title = "Убийство" })
CombatTab:Toggle({
    Title = "Убить всех при цели",
    Desc = "Собрал цель / полную сумку → убиваешь всех ножом (нужна роль Murderer)",
    Value = false,
    Callback = function(v) AutoKE.On = v end,
})

CombatTab:Section({ Title = "Silent Aim" })
CombatTab:Toggle({
    Title = "Silent Aim",
    Desc = "Пули сами летят в цель",
    Value = false,
    Callback = function(v)
        SA2.On = v
        if v then installHooks() else removeHooks() end
    end,
})
CombatTab:Dropdown({
    Title = "Режим",
    Desc = "Simple — прямая видимость, Pro — сквозь стены",
    Values = { "Simple", "Pro" },
    Value = "Simple",
    Callback = function(v) SA2.Mode = v end,
})
CombatTab:Dropdown({
    Title = "Цель",
    Values = { "Murderer", "Sheriff", "Closest" },
    Value = "Murderer",
    Callback = function(v) SA2.Target = v end,
})
CombatTab:Toggle({
    Title = "Предсказание (Predict)",
    Desc = "Упреждение по скорости цели",
    Value = true,
    Callback = function(v) SA2.Predict = v end,
})

CombatTab:Section({ Title = "Флинг" })
CombatTab:Button({
    Title = "Флинг убийцы",
    Desc = "Выбросить Murderer с карты",
    Callback = function()
        local m = getMurderer()
        if m then doFling(m) else Notify("Fling", "Murderer не найден", nil, 3) end
    end,
})
CombatTab:Button({
    Title = "Стоп флинг",
    Desc = "Остановить активный флинг и вернуться",
    Callback = stopFling,
})

-- ─── ВКЛАДКА ЗАЩИТА ───
ProtectTab:Section({ Title = "Anti-Fling" })
ProtectTab:Toggle({
    Title = "Анти-флинг",
    Desc = "Защита от выброса другими игроками",
    Value = true,
    Callback = function(v) AntiFling.On = v end,
})
addNum(ProtectTab, "Порог скорости", "Свыше этого = аномально, сбрасываем", 100, 2000, 500,
    function(n) AntiFling.MaxVel = n end)

ProtectTab:Section({ Title = "После смерти" })
ProtectTab:Toggle({
    Title = "Авто-флинг убийцы",
    Desc = "Тебя убили → респавн → флинг Murderer",
    Value = false,
    Callback = function(v)
        AutoFlingDeath.On = v
        if not v then deathFlingPending = false end
    end,
})

-- ═══ СТАРТ ═══
Window:SelectTab(1)
print("[CL] Crows Lite готов — все системы запущены")
Notify("Crows Lite", "Загружен! Right Shift / кнопка-перо — открыть меню", nil, 4)

  
