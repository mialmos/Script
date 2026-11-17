--[[
	Kisha Tixo — Violence District
	UI: Kisha library
	Feature logic: ported from Tixo (tx.lua + module.lua + esp patterns)
	Standalone — does not depend on testscript
]]

if not game:IsLoaded() then
	game.Loaded:Wait()
end

local KISHA_URL = "https://raw.githubusercontent.com/mialmos/Kisha-ui/refs/heads/main/Kisha.lua"
local Kisha
do
	local ok, src = pcall(function()
		return game:HttpGet(KISHA_URL)
	end)
	if not ok or type(src) ~= "string" or #src < 100 then
		error("[Kisha Tixo] Failed to download Kisha UI", 0)
	end
	local fn, err = loadstring(src)
	if not fn then
		error("[Kisha Tixo] Failed to compile Kisha: " .. tostring(err), 0)
	end
	Kisha = fn()
	if type(Kisha) ~= "table" or type(Kisha.CreateWindow) ~= "function" then
		error("[Kisha Tixo] Kisha missing CreateWindow", 0)
	end
end

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local VirtualInputManager = game:GetService("VirtualInputManager")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CoreGui = game:GetService("CoreGui")
local HttpService = game:GetService("HttpService")
local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local GuiService = game:GetService("GuiService")
local TweenService = game:GetService("TweenService")

local LP = Players.LocalPlayer
local Camera = workspace.CurrentCamera
local PlayerGui = LP:WaitForChild("PlayerGui")

local Config = {
	-- Survivor
	AutoParry = false,
	AutoParryV2 = false,
	ParrySafety = true,
	ParryAggressive = false,
	ParryRadius = 15,
	ParryFace = 0.7,
	AutoCrouch = false,
	AutoSkillCheck = false,
	SkillCheckMode = "Instant", -- Instant | Legit | Normal
	AutoPallet = false,
	AutoPalletRadius = 10,
	SelfHeal = false,
	NoFall = false,
	GodMode = false,
	AutoSprint = false,
	-- Aim
	TOF2 = false,
	TOF2_Predict = 1.5,
	TOF2_Laser = false,
	SilentVeil = false,
	VeilLead = 1.7,
	VeilFOV = 150,
	ButcherAim = false,
	ButcherLead = 1.2,
	FlashSilent = false,
	-- Killer
	InfLunge = false,
	NoSlowdown = false,
	AntiBlind = false,
	-- Visual
	ESP_Master = false,
	ESP_Player = false,
	ESP_Killer = false,
	ESP_Generator = false,
	ESP_Pallet = false,
	ESP_Hook = false,
	ESP_Gate = false,
	ESP_Window = false,
	ESP_Name = true,
	ESP_Distance = true,
	ESP_MaxDist = 1000,
	FullBright = false,
	NoFog = false,
	-- Misc
	Invis = false,
	MoonWalk = false,
	CustomFOV = false,
	FOVValue = 90,
}

local State = {
	ParryCooldown = false,
	LastParry = 0,
	SkillBusy = false,
	Pv2Conn = nil,
	Pv1Attached = {},
	TrackV2 = {},
	TOF2_Dir = nil,
	TOF2_Origin = nil,
	TOF2_Target = nil,
	Veil_HasCache = false,
	Veil_Dir = nil,
	Veil_Origin = nil,
	Butcher_HasCache = false,
	Butcher_Dir = nil,
	ESPObjects = {},
	MapCache = { Generators = {}, Pallets = {}, Hooks = {}, Gates = {}, Windows = {} },
	Alive = true,
}

local VALID_PARRY_IDS = {
	["78935059863801"] = "Veil Basic",
	["122812055447896"] = "Veil lunge",
	["133963973694098"] = "Stalker Basic",
	["117042998468241"] = "Stalker lunge",
	["121216847022485"] = "cure Basic",
	["135002183282873"] = "cure lunge",
	["113691709436161"] = "Jason Basic",
	["129626174716003"] = "Jason lunge",
	["75618342544502"] = "Jeff Basic",
	["93902163029544"] = "Jeff lunge",
	["104540716539347"] = "Jeff Frenzy lunge",
	["101636125032002"] = "Abyssal Basic",
	["125430111937587"] = "Abyssal lunge",
	["100014992013740"] = "Abyssal S1",
	["111920872708571"] = "Masked Basic",
	["105374834496520"] = "Masked lunge",
	["138720291317243"] = "Masked Tony",
	["130593238885843"] = "Masked Cobra",
	["115244153053858"] = "Masked Cobra lunge",
	["74968262036854"] = "Hidden Basic",
	["113255068724446"] = "Hidden lunge",
	["98163597193511"] = "Hidden S1",
	["127417297154354"] = "Buck lunge",
	["83333467665074"] = "Buck Basic",
	["81963230963908"] = "Veil Basic",
	["84926129581106"] = "Veil lunge",
}

local CROUCH_DODGE = {
	["80411309607666"] = true,
	["100014992013740"] = true,
	["98163597193511"] = true,
}

local ESP_COLORS = {
	Player = Color3.fromRGB(60, 255, 60),
	Killer = Color3.fromRGB(255, 60, 60),
	Generator = Color3.fromRGB(255, 255, 0),
	GeneratorDone = Color3.fromRGB(0, 255, 0),
	Pallet = Color3.fromRGB(255, 128, 0),
	Hook = Color3.fromRGB(255, 105, 180),
	Gate = Color3.fromRGB(255, 255, 255),
	Window = Color3.fromRGB(0, 150, 255),
}

-- ==================== helpers ====================
local function getRole()
	if not LP.Team then return "Unknown" end
	local n = LP.Team.Name
	if n == "Killer" then return "Killer" end
	if n == "Survivors" then return "Survivor" end
	return "Spectator"
end

local function isKiller(plr)
	return plr and plr.Team and plr.Team.Name == "Killer"
end

local function isDowned(char)
	if not char then return false end
	return char:GetAttribute("Knocked") == true or char:GetAttribute("IsHooked") == true
end

local function isSafeToParry(char)
	if not Config.ParrySafety then return true end
	if not char then return false end
	local busy = char:FindFirstChild("CheckInterractable")
	if busy then
		for _, a in ipairs({ "isVaulting", "isRepairing", "isUnhooking", "isHealing", "isSliding", "isDroppingPallet" }) do
			if busy:GetAttribute(a) then return false end
		end
	end
	return true
end

local function attackByName(name)
	name = string.lower(tostring(name or ""))
	if string.find(name, "vm", -2, true) then return nil end
	if string.find(name, "^attack") and not string.find(name, "done", 1, true) then return name end
	for _, w in ipairs({ "swing", "slash", "stab", "strike", "chop", "lunge" }) do
		if string.find(name, w, 1, true) and not string.find(name, "idle", 1, true) then
			return name
		end
	end
	if string.find(name, "lungehold", 1, true) then return name end
	return nil
end

local function remotePath(...)
	local cur = ReplicatedStorage:FindFirstChild("Remotes")
	for _, name in ipairs({ ... }) do
		cur = cur and cur:FindFirstChild(name)
	end
	return cur
end

local function parryRemote()
	return remotePath("Items", "Parrying Dagger", "parry")
end

-- ==================== PARRY ====================
local function triggerCrouch()
	pcall(function()
		local gui = LP:FindFirstChild("PlayerGui")
		local node = gui
		for seg in string.gmatch("Survivor-mob.Controls.crouch.icon", "[^%.]+") do
			node = node and node:FindFirstChild(seg)
		end
		if node and node:IsA("GuiObject") and node.Parent and node.Parent:IsA("GuiButton") then
			local btn = node.Parent
			if UserInputService.TouchEnabled and type(firesignal) == "function" then
				firesignal(btn.MouseButton1Click)
				task.wait(1.4)
				firesignal(btn.MouseButton1Click)
			else
				VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.LeftControl, false, game)
				task.wait(1.4)
				VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.LeftControl, false, game)
			end
		else
			VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.LeftControl, false, game)
			task.wait(1.4)
			VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.LeftControl, false, game)
		end
	end)
end

local function executeParry(killerRoot)
	if State.ParryCooldown then return end
	local now = os.clock()
	if now - State.LastParry < 0.15 then return end
	State.LastParry = now

	local char = LP.Character
	if not char then return end

	if killerRoot and killerRoot.Parent then
		local hrp = char:FindFirstChild("HumanoidRootPart")
		if hrp then
			local goal = Vector3.new(killerRoot.Position.X, hrp.Position.Y, killerRoot.Position.Z)
			if (goal - hrp.Position).Magnitude > 0.3 then
				hrp.CFrame = CFrame.lookAt(hrp.Position, goal)
			end
		end
	end

	local pr = parryRemote()
	if pr then
		pcall(function()
			pr:FireServer(char)
		end)
	else
		pcall(function()
			local mob = PlayerGui:FindFirstChild("Survivor-mob")
			local gui = mob and mob:FindFirstChild("Controls") and mob.Controls:FindFirstChild("Gui-mob")
			if gui and type(firesignal) == "function" then
				firesignal(gui.MouseButton1Down)
				task.wait(0.01)
				firesignal(gui.MouseButton1Up)
			else
				VirtualInputManager:SendMouseButtonEvent(0, 0, 1, true, game, 0)
				task.wait(0.01)
				VirtualInputManager:SendMouseButtonEvent(0, 0, 1, false, game, 0)
			end
		end)
	end
end

-- listen parry cooldown from game
task.spawn(function()
	local pr = remotePath("Items", "Parrying Dagger", "parryResult")
	if not pr then
		local remotes = ReplicatedStorage:WaitForChild("Remotes", 8)
		local items = remotes and remotes:WaitForChild("Items", 5)
		local dagger = items and items:WaitForChild("Parrying Dagger", 5)
		pr = dagger and dagger:WaitForChild("parryResult", 5)
	end
	if pr then
		pr.OnClientEvent:Connect(function(_, t)
			local n = tonumber(t) or 60
			State.ParryCooldown = true
			task.delay(n, function()
				State.ParryCooldown = false
			end)
		end)
	end
end)

-- Parry V1: AnimationPlayed on killers (Tixo / classic)
local function attachParrySensor(char)
	if not char or State.Pv1Attached[char] then return end
	State.Pv1Attached[char] = true
	local hum = char:WaitForChild("Humanoid", 5)
	if not hum then return end
	local animator = hum:FindFirstChildOfClass("Animator") or hum:WaitForChild("Animator", 5)
	if not animator then return end

	char.AncestryChanged:Connect(function(_, parent)
		if not parent then State.Pv1Attached[char] = nil end
	end)

	animator.AnimationPlayed:Connect(function(track)
		if not Config.AutoParry then return end
		local anim = track.Animation
		local id = anim and tostring(anim.AnimationId):match("%d+") or ""
		local name = VALID_PARRY_IDS[id] or attackByName(track.Name)
		if not name then return end

		if CROUCH_DODGE[id] and Config.AutoCrouch then
			local my = LP.Character
			local myHRP = my and my:FindFirstChild("HumanoidRootPart")
			local kHRP = char:FindFirstChild("HumanoidRootPart")
			if myHRP and kHRP and (myHRP.Position - kHRP.Position).Magnitude <= 40 and not isDowned(my) then
				triggerCrouch()
			end
			return
		end

		if State.ParryCooldown then return end
		local my = LP.Character
		if isDowned(my) or not isSafeToParry(my) then return end
		local myHRP = my and my:FindFirstChild("HumanoidRootPart")
		local kHRP = char:FindFirstChild("HumanoidRootPart")
		if not myHRP or not kHRP then return end
		local dist = (myHRP.Position - kHRP.Position).Magnitude
		if dist > Config.ParryRadius then
			if not Config.ParryAggressive then return end
			local t0 = os.clock()
			local conn
			conn = RunService.Heartbeat:Connect(function()
				if os.clock() - t0 > 0.85 or State.ParryCooldown or isDowned(my) then
					if conn then conn:Disconnect() end
					return
				end
				if myHRP.Parent and kHRP.Parent and (myHRP.Position - kHRP.Position).Magnitude <= Config.ParryRadius then
					executeParry(kHRP)
					if conn then conn:Disconnect() end
				end
			end)
			return
		end
		executeParry(kHRP)
	end)
end

local function setupKillerParry(plr)
	if plr == LP then return end
	plr.CharacterAdded:Connect(function()
		if isKiller(plr) and plr.Character then
			attachParrySensor(plr.Character)
		end
	end)
	plr:GetPropertyChangedSignal("Team"):Connect(function()
		if isKiller(plr) and plr.Character then
			attachParrySensor(plr.Character)
		end
	end)
	if isKiller(plr) and plr.Character then
		attachParrySensor(plr.Character)
	end
end

for _, p in ipairs(Players:GetPlayers()) do
	setupKillerParry(p)
end
Players.PlayerAdded:Connect(setupKillerParry)

-- Parry V2: Heartbeat track scan (Tixo ParryV2S)
local function setParryV2(on)
	Config.AutoParryV2 = on
	if State.Pv2Conn then
		State.Pv2Conn:Disconnect()
		State.Pv2Conn = nil
	end
	table.clear(State.TrackV2)
	if not on then return end
	State.Pv2Conn = RunService.Heartbeat:Connect(function()
		if not Config.AutoParryV2 then return end
		local my = LP.Character
		if not my or isDowned(my) or not isSafeToParry(my) then return end
		local myHRP = my:FindFirstChild("HumanoidRootPart")
		if not myHRP then return end
		local radius = Config.ParryRadius
		for _, plr in ipairs(Players:GetPlayers()) do
			if plr ~= LP and isKiller(plr) and plr.Character then
				local kChar = plr.Character
				local kHRP = kChar:FindFirstChild("HumanoidRootPart")
				if not kHRP then continue end
				local dist = (myHRP.Position - kHRP.Position).Magnitude
				if dist > radius + 5 then continue end
				local hum = kChar:FindFirstChildOfClass("Humanoid")
				local animator = hum and hum:FindFirstChildOfClass("Animator")
				if not animator then continue end
				local flatDelta = Vector3.new(myHRP.Position.X - kHRP.Position.X, 0, myHRP.Position.Z - kHRP.Position.Z)
				if flatDelta.Magnitude > 0.1 then
					local kLook = Vector3.new(kHRP.CFrame.LookVector.X, 0, kHRP.CFrame.LookVector.Z)
					if kLook.Magnitude > 0.05 and kLook.Unit:Dot(flatDelta.Unit) < Config.ParryFace then
						continue
					end
				end
				for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
					if not State.TrackV2[track] then
						State.TrackV2[track] = true
						local anim = track.Animation
						local id = anim and tostring(anim.AnimationId):match("%d+") or ""
						local name = VALID_PARRY_IDS[id] or attackByName(track.Name)
						if name and dist <= radius then
							executeParry(kHRP)
						end
					end
				end
			end
		end
		for track in pairs(State.TrackV2) do
			if not track.IsPlaying then State.TrackV2[track] = nil end
		end
	end)
end

-- ==================== SKILL CHECK (Tixo Instant) ====================
local function fireSkillCheck()
	pcall(function()
		local mob = PlayerGui:FindFirstChild("Survivor-mob")
		local controls = mob and mob:FindFirstChild("Controls")
		local action = controls and (controls:FindFirstChild("action") or controls:FindFirstChild("check"))
		if action and action.Visible and type(firesignal) == "function" then
			firesignal(action.MouseButton1Down)
			task.wait(0.005)
			firesignal(action.MouseButton1Up)
			return
		end
		local raw = LP:GetAttribute("kb_skillcheck") or "Space"
		local mouseIndex = tostring(raw):match("^MouseButton(%d)$")
		if mouseIndex then
			local button = tonumber(mouseIndex) - 1
			VirtualInputManager:SendMouseButtonEvent(0, 0, button, true, game, 0)
			task.wait(0.005)
			VirtualInputManager:SendMouseButtonEvent(0, 0, button, false, game, 0)
			return
		end
		local key = Enum.KeyCode[raw] or Enum.KeyCode.Space
		VirtualInputManager:SendKeyEvent(true, key, false, game)
		task.wait(0.005)
		VirtualInputManager:SendKeyEvent(false, key, false, game)
	end)
end

local skillConn
local function setSkillCheck(on)
	Config.AutoSkillCheck = on
	if skillConn then
		skillConn:Disconnect()
		skillConn = nil
	end
	if not on then return end
	skillConn = RunService.Heartbeat:Connect(function()
		if not Config.AutoSkillCheck or State.SkillBusy then return end
		local my = LP.Character
		if my and my:GetAttribute("Trapped") then return end
		local prompt = PlayerGui:FindFirstChild("SkillCheckPromptGui") or PlayerGui:FindFirstChild("SkillCheckPromptGui-con")
		if not prompt then return end
		local check = prompt:FindFirstChild("Check")
		if not check or not check.Visible then return end
		local line = check:FindFirstChild("Line")
		local goal = check:FindFirstChild("Goal")
		if not line or not goal then return end

		local trapGoal = check:FindFirstChild("TrapGoal")
		local trapPerfect = check:FindFirstChild("TrapPerfect")
		local isTrap = (trapPerfect and trapPerfect.Visible) or (trapGoal and trapGoal.Visible)

		if Config.SkillCheckMode == "Instant" then
			if isTrap then
				local tg = (trapPerfect and trapPerfect.Visible and trapPerfect) or trapGoal or goal
				line.Rotation = (tg.Rotation + 102) + 3
			else
				line.Rotation = (goal.Rotation % 360) + 85
			end
			State.SkillBusy = true
			task.spawn(function()
				fireSkillCheck()
				task.wait(0.05)
				State.SkillBusy = false
			end)
			return
		end

		-- Legit / Normal zone hit
		local lr = line.Rotation % 360
		local gr = goal.Rotation % 360
		local ss, se
		if Config.SkillCheckMode == "Normal" then
			ss, se = (gr + 116) % 360, (gr + 140) % 360
		else
			ss, se = (gr + 102) % 360, (gr + 116) % 360
		end
		local inZone = (ss > se and (lr >= ss or lr <= se)) or (lr >= ss and lr <= se)
		if inZone then
			State.SkillBusy = true
			task.spawn(function()
				fireSkillCheck()
				task.wait(0.05)
				State.SkillBusy = false
			end)
		end
	end)
end

-- ==================== AUTO PALLET ====================
local function scanMap()
	local cache = State.MapCache
	table.clear(cache.Generators)
	table.clear(cache.Pallets)
	table.clear(cache.Hooks)
	table.clear(cache.Gates)
	table.clear(cache.Windows)
	local root = workspace:FindFirstChild("Map") or workspace
	for i, d in ipairs(root:GetDescendants()) do
		if i % 250 == 0 then task.wait() end
		if d:IsA("Model") then
			local n = string.lower(d.Name)
			if n == "generator" then
				local p = d:FindFirstChild("GeneratorBody") or d:FindFirstChildWhichIsA("BasePart")
				if p then table.insert(cache.Generators, { model = d, part = p }) end
			elseif n == "hook" and d:FindFirstChild("HookPoint") then
				table.insert(cache.Hooks, d)
			elseif n == "gate" and d:FindFirstChild("ExitLever") then
				table.insert(cache.Gates, d)
			elseif n == "window" then
				table.insert(cache.Windows, d)
			elseif n == "pallet" or string.find(n, "pallet") then
				table.insert(cache.Pallets, d)
			end
		elseif d:IsA("BasePart") and (d.Name == "PrimaryPartPallet" or d.Name == "PalletPoint" or d.Name == "PalletPointSlide") then
			local m = d:FindFirstAncestorWhichIsA("Model")
			if m and not table.find(cache.Pallets, m) then
				table.insert(cache.Pallets, m)
			end
		end
	end
end

local function dropPallet(point)
	local ev = remotePath("Pallet", "PalletDropEvent")
	local char = LP.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not point or not hrp then return false end
	return pcall(function()
		if ev then
			ev:FireServer(point, hrp.Position, hum and hum.MoveDirection or Vector3.zero, HttpService:GenerateGUID(false), char)
		end
	end)
end

local palletThread
local function setAutoPallet(on)
	Config.AutoPallet = on
	if palletThread then
		task.cancel(palletThread)
		palletThread = nil
	end
	if not on then return end
	palletThread = task.spawn(function()
		while Config.AutoPallet and State.Alive do
			task.wait(0.35)
			if getRole() ~= "Survivor" then continue end
			local my = LP.Character
			local hrp = my and my:FindFirstChild("HumanoidRootPart")
			if not hrp or isDowned(my) then continue end
			local killerHRP
			for _, plr in ipairs(Players:GetPlayers()) do
				if isKiller(plr) and plr.Character then
					local k = plr.Character:FindFirstChild("HumanoidRootPart")
					if k then killerHRP = k break end
				end
			end
			if not killerHRP then continue end
			if (hrp.Position - killerHRP.Position).Magnitude > Config.AutoPalletRadius + 8 then continue end
			local best, bestD = nil, Config.AutoPalletRadius
			for _, pallet in ipairs(State.MapCache.Pallets) do
				if pallet and pallet.Parent then
					local pt = pallet:FindFirstChild("PrimaryPartPallet")
						or pallet:FindFirstChild("PalletPoint")
						or pallet:FindFirstChildWhichIsA("BasePart")
					if pt then
						local d = (hrp.Position - pt.Position).Magnitude
						if d < bestD then best, bestD = pt, d end
					end
				end
			end
			if best then dropPallet(best) end
		end
	end)
end

-- ==================== TOF 2 / VEIL / BUTCHER caches ====================
local function nearestKillerPart()
	local my = LP.Character
	local hrp = my and my:FindFirstChild("HumanoidRootPart")
	if not hrp then return nil end
	local best, bestD = nil, math.huge
	for _, plr in ipairs(Players:GetPlayers()) do
		if plr ~= LP and isKiller(plr) and plr.Character then
			local k = plr.Character:FindFirstChild("HumanoidRootPart")
			local hum = plr.Character:FindFirstChildOfClass("Humanoid")
			if k and hum and hum.Health > 0 then
				local d = (k.Position - hrp.Position).Magnitude
				if d < bestD then best, bestD = k, d end
			end
		end
	end
	return best, bestD
end

local function nearestSurvivorPart(maxDist)
	local my = LP.Character
	local hrp = my and my:FindFirstChild("HumanoidRootPart")
	if not hrp then return nil end
	local best, bestD = nil, maxDist or 300
	for _, plr in ipairs(Players:GetPlayers()) do
		if plr ~= LP and plr.Team and plr.Team.Name == "Survivors" and plr.Character then
			local k = plr.Character:FindFirstChild("HumanoidRootPart")
			local hum = plr.Character:FindFirstChildOfClass("Humanoid")
			if k and hum and hum.Health > 0 and not isDowned(plr.Character) then
				local d = (k.Position - hrp.Position).Magnitude
				if d < bestD then best, bestD = k, d end
			end
		end
	end
	return best, bestD
end

local aimCacheConn
aimCacheConn = RunService.Heartbeat:Connect(function()
	if not State.Alive then return end
	if Config.TOF2 then
		local part, dist = nearestKillerPart()
		local my = LP.Character
		local hrp = my and my:FindFirstChild("HumanoidRootPart")
		if part and hrp then
			local vel = Vector3.new(part.AssemblyLinearVelocity.X, 0, part.AssemblyLinearVelocity.Z)
			local t = dist / 200
			local pred = part.Position + vel * t * Config.TOF2_Predict
			local origin = hrp.Position + Vector3.new(0, 1.5, 0)
			State.TOF2_Dir = (pred - origin).Unit
			State.TOF2_Origin = origin
			State.TOF2_Target = pred
		else
			State.TOF2_Dir = nil
		end
	end
	if Config.SilentVeil or Config.ButcherAim then
		local my = LP.Character
		local hrp = my and my:FindFirstChild("HumanoidRootPart")
		local arm = my and (my:FindFirstChild("RightHand") or my:FindFirstChild("Right Arm"))
		local start = arm and arm.Position or (hrp and hrp.Position + Vector3.new(1.5, 0.5, 0))
		local part, dist = nearestSurvivorPart(Config.SilentVeil and 300 or 50)
		if start and part then
			local vel = Vector3.new(part.AssemblyLinearVelocity.X, 0, part.AssemblyLinearVelocity.Z)
			if Config.SilentVeil then
				local speed = 165
				local t = dist / speed
				local pred = part.Position + vel * (t * Config.VeilLead)
				local drop = 0.5 * 70 * (t * t)
				local aim = pred + Vector3.new(0, drop, 0)
				State.Veil_Dir = (aim - start).Unit
				State.Veil_Origin = start
				State.Veil_HasCache = true
			end
			if Config.ButcherAim and dist <= 50 then
				local speed = 140
				local t = dist / speed
				local lead = Config.ButcherLead + (dist / 40) * 0.6
				local pred = part.Position + vel * (t * lead)
				State.Butcher_Dir = (pred - start).Unit
				State.Butcher_HasCache = true
			else
				State.Butcher_HasCache = false
			end
		else
			State.Veil_HasCache = false
			State.Butcher_HasCache = false
		end
	end
end)

-- Namecall redirect for Veil / Butcher / TOF when available
pcall(function()
	local mt = getrawmetatable(game)
	if not mt then return end
	local old = mt.__namecall
	setreadonly(mt, false)
	mt.__namecall = newcclosure(function(self, ...)
		local method = getnamecallmethod()
		if method == "FireServer" then
			local name = self.Name
			if Config.SilentVeil and name == "Spearthrow" and State.Veil_HasCache and State.Veil_Dir then
				local args = { ... }
				if type(args[1]) == "table" and args[1].Direction then
					args[1].Direction = State.Veil_Dir
					args[1].Origin = State.Veil_Origin or args[1].Origin
					return old(self, table.unpack(args))
				end
			end
			if Config.ButcherAim and name == "ChainThrow" and State.Butcher_HasCache and State.Butcher_Dir then
				return old(self, State.Butcher_Dir, select(2, ...))
			end
			if Config.TOF2 and name == "Fire" and self.Parent and self.Parent.Name == "Twist of Fate" and State.TOF2_Dir then
				local a1, a2, a3 = ...
				return old(self, a1, State.TOF2_Dir, a3 or 3)
			end
		end
		return old(self, ...)
	end)
	setreadonly(mt, true)
end)

-- ==================== ESP ====================
local function clearESP()
	for _, obj in pairs(State.ESPObjects) do
		pcall(function()
			if obj and obj.Parent then obj:Destroy() end
		end)
	end
	table.clear(State.ESPObjects)
	for _, pallet in ipairs(State.MapCache.Pallets) do
		local h = pallet and pallet:FindFirstChild("KT_PalletEH")
		if h then h:Destroy() end
	end
	for _, g in ipairs(State.MapCache.Generators) do
		local m = g.model
		if m then
			local h = m:FindFirstChild("KT_GEH")
			if h then h:Destroy() end
		end
	end
end

local function ensureHighlight(parent, name, color)
	local h = parent:FindFirstChild(name)
	if not h then
		h = Instance.new("Highlight")
		h.Name = name
		h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
		h.Parent = parent
	end
	h.FillColor = color
	h.OutlineColor = color
	h.FillTransparency = 0.55
	h.OutlineTransparency = 0
	h.Adornee = parent
	return h
end

local function updateESP()
	if not Config.ESP_Master then
		clearESP()
		return
	end
	local camPos = Camera.CFrame.Position
	local maxD = Config.ESP_MaxDist

	if Config.ESP_Player or Config.ESP_Killer then
		for _, plr in ipairs(Players:GetPlayers()) do
			if plr ~= LP and plr.Character then
				local char = plr.Character
				local hrp = char:FindFirstChild("HumanoidRootPart")
				if not hrp then continue end
				local d = (hrp.Position - camPos).Magnitude
				local isK = isKiller(plr)
				local want = (isK and Config.ESP_Killer) or (not isK and Config.ESP_Player)
				local key = "plr_" .. plr.UserId
				if want and d <= maxD then
					local col = isK and ESP_COLORS.Killer or ESP_COLORS.Player
					local h = ensureHighlight(char, "KT_PlayerEH", col)
					State.ESPObjects[key] = h
				else
					local h = char:FindFirstChild("KT_PlayerEH")
					if h then h:Destroy() end
					State.ESPObjects[key] = nil
				end
			end
		end
	end

	if Config.ESP_Generator then
		for _, g in ipairs(State.MapCache.Generators) do
			local model, part = g.model, g.part
			if model and model.Parent and part then
				local d = (part.Position - camPos).Magnitude
				if d <= maxD then
					local prog = tonumber(model:GetAttribute("RepairProgress")) or 0
					local col = ESP_COLORS.Generator:Lerp(ESP_COLORS.GeneratorDone, math.clamp(prog / 100, 0, 1))
					ensureHighlight(model, "KT_GEH", col)
				else
					local h = model:FindFirstChild("KT_GEH")
					if h then h:Destroy() end
				end
			end
		end
	end

	if Config.ESP_Pallet then
		for _, pallet in ipairs(State.MapCache.Pallets) do
			if pallet and pallet.Parent then
				local part = pallet:FindFirstChild("PrimaryPartPallet")
					or pallet:FindFirstChild("PalletPoint")
					or pallet:FindFirstChildWhichIsA("BasePart")
				if part and (part.Position - camPos).Magnitude <= maxD then
					local dropped = pallet:GetAttribute("PalletState") == "Dropped"
					local col = dropped and Color3.fromRGB(255, 180, 40) or ESP_COLORS.Pallet
					ensureHighlight(pallet, "KT_PalletEH", col)
				else
					local h = pallet:FindFirstChild("KT_PalletEH")
					if h then h:Destroy() end
				end
			end
		end
	end

	if Config.ESP_Hook then
		for _, hook in ipairs(State.MapCache.Hooks) do
			if hook and hook.Parent then
				local part = hook:FindFirstChildWhichIsA("BasePart")
				if part and (part.Position - camPos).Magnitude <= maxD then
					ensureHighlight(hook, "KT_HookEH", ESP_COLORS.Hook)
				end
			end
		end
	end

	if Config.ESP_Gate then
		for _, gate in ipairs(State.MapCache.Gates) do
			if gate and gate.Parent then
				ensureHighlight(gate, "KT_GateEH", ESP_COLORS.Gate)
			end
		end
	end

	if Config.ESP_Window then
		for _, win in ipairs(State.MapCache.Windows) do
			if win and win.Parent then
				local part = win:FindFirstChild("Bottom") or win:FindFirstChildWhichIsA("BasePart")
				if part and (part.Position - camPos).Magnitude <= maxD then
					ensureHighlight(win, "KT_WindowEH", ESP_COLORS.Window)
				end
			end
		end
	end
end

task.spawn(function()
	while State.Alive do
		task.wait(0.5)
		if Config.ESP_Master then
			pcall(updateESP)
		end
	end
end)

task.spawn(function()
	task.wait(2)
	scanMap()
	while State.Alive do
		task.wait(20)
		scanMap()
	end
end)

workspace.ChildAdded:Connect(function(c)
	if c.Name == "Map" then
		task.wait(1.5)
		scanMap()
	end
end)

-- ==================== MISC ====================
local function setFullBright(on)
	Config.FullBright = on
	if on then
		Lighting.Brightness = 2.8
		Lighting.FogEnd = 1e5
		Lighting.Ambient = Color3.fromRGB(200, 200, 200)
		Lighting.OutdoorAmbient = Color3.fromRGB(200, 200, 200)
	else
		Lighting.Brightness = 1
		Lighting.FogEnd = 1000
		Lighting.Ambient = Color3.fromRGB(128, 128, 128)
		Lighting.OutdoorAmbient = Color3.fromRGB(128, 128, 128)
	end
end

local function setNoFog(on)
	Config.NoFog = on
	if on then
		Lighting.FogStart = 0
		Lighting.FogEnd = 1e5
		local at = Lighting:FindFirstChildOfClass("Atmosphere")
		if at then
			at.Density = 0
			at.Haze = 0
		end
	end
end

local invisConn
local function setInvis(on)
	Config.Invis = on
	if invisConn then
		invisConn:Disconnect()
		invisConn = nil
	end
	local function apply(char)
		if not char then return end
		for _, p in ipairs(char:GetDescendants()) do
			if p:IsA("BasePart") or p:IsA("Decal") or p:IsA("Texture") then
				pcall(function()
					if on then
						p:SetAttribute("_ktInvis", p.Transparency)
						p.Transparency = 1
					else
						local o = p:GetAttribute("_ktInvis")
						if o ~= nil then p.Transparency = o end
					end
				end)
			end
		end
	end
	if on then
		apply(LP.Character)
		invisConn = LP.CharacterAdded:Connect(function(c)
			task.wait(0.4)
			if Config.Invis then apply(c) end
		end)
	else
		apply(LP.Character)
	end
end

local moonConn
local function setMoonWalk(on)
	Config.MoonWalk = on
	if moonConn then
		moonConn:Disconnect()
		moonConn = nil
	end
	if not on then return end
	moonConn = RunService.RenderStepped:Connect(function()
		if not Config.MoonWalk then return end
		local char = LP.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if not (hrp and hum) or hum.MoveDirection.Magnitude < 0.05 then return end
		local flat = Vector3.new(hum.MoveDirection.X, 0, hum.MoveDirection.Z)
		if flat.Magnitude > 0.05 then
			hrp.CFrame = CFrame.lookAt(hrp.Position, hrp.Position - flat)
		end
	end)
end

local fovConn
local function setCustomFOV(on)
	Config.CustomFOV = on
	if fovConn then
		fovConn:Disconnect()
		fovConn = nil
	end
	if on then
		fovConn = RunService.RenderStepped:Connect(function()
			if Config.CustomFOV and Camera then
				Camera.FieldOfView = Config.FOVValue
			end
		end)
	end
end

-- Infinite lunge (killer)
local function setInfLunge(on)
	Config.InfLunge = on
	-- soft approach: spam readiness by clearing common cooldown attributes when possible
	task.spawn(function()
		while Config.InfLunge and State.Alive do
			task.wait(0.2)
			local char = LP.Character
			if char and getRole() == "Killer" then
				pcall(function()
					char:SetAttribute("LungeCooldown", false)
					char:SetAttribute("AttackCooldown", 0)
				end)
			end
		end
	end)
end

-- ==================== UI ====================
local Window = Kisha:CreateWindow({
	Title = "Kisha Tixo",
	Subtitle = "Violence District",
	ToggleKey = Enum.KeyCode.RightControl,
	Size = UDim2.fromOffset(560, 420),
	Keybinds = true,
})

local function tab(name)
	return Window:CreateTab({ Name = name })
end

local function section(t, name)
	return t:CreateSection({ Name = name })
end

-- Survivor
local SurvTab = tab("Survivor")
local parrySec = section(SurvTab, "Auto Parry")
parrySec:AddToggle({
	Name = "Auto Parry V1",
	Default = false,
	Callback = function(v)
		Config.AutoParry = v
		if v then Config.AutoParryV2 = false end
	end,
})
parrySec:AddToggle({
	Name = "Auto Parry V2",
	Default = false,
	Callback = function(v)
		setParryV2(v)
		if v then Config.AutoParry = false end
	end,
})
parrySec:AddToggle({
	Name = "Parry Safety",
	Default = true,
	Callback = function(v) Config.ParrySafety = v end,
})
parrySec:AddToggle({
	Name = "Aggressive Parry",
	Default = false,
	Callback = function(v) Config.ParryAggressive = v end,
})
parrySec:AddSlider({
	Name = "Parry Radius",
	Min = 5,
	Max = 25,
	Default = 15,
	Increment = 1,
	Callback = function(v) Config.ParryRadius = v end,
})
parrySec:AddSlider({
	Name = "Face Sensitivity",
	Min = 0,
	Max = 10,
	Default = 7,
	Increment = 1,
	Callback = function(v) Config.ParryFace = v / 10 end,
})
parrySec:AddToggle({
	Name = "Auto Crouch (S1 dodge)",
	Default = false,
	Callback = function(v) Config.AutoCrouch = v end,
})

local skillSec = section(SurvTab, "Skill Check & Pallet")
skillSec:AddToggle({
	Name = "Auto Skill Check",
	Default = false,
	Callback = function(v) setSkillCheck(v) end,
})
skillSec:AddDropdown({
	Name = "Skill Mode",
	Options = { "Instant", "Legit", "Normal" },
	Default = "Instant",
	Callback = function(v) Config.SkillCheckMode = v end,
})
skillSec:AddToggle({
	Name = "Auto Drop Pallet",
	Default = false,
	Callback = function(v) setAutoPallet(v) end,
})
skillSec:AddSlider({
	Name = "Pallet Radius",
	Min = 5,
	Max = 20,
	Default = 10,
	Increment = 1,
	Callback = function(v) Config.AutoPalletRadius = v end,
})

local utilSec = section(SurvTab, "Utility")
utilSec:AddToggle({
	Name = "God Mode (Anti Knock)",
	Default = false,
	Callback = function(v) Config.GodMode = v end,
})
utilSec:AddToggle({
	Name = "No Fall / Anti Slow",
	Default = false,
	Callback = function(v) Config.NoFall = v end,
})
utilSec:AddToggle({
	Name = "Moon Walk",
	Default = false,
	Callback = function(v) setMoonWalk(v) end,
})
utilSec:AddToggle({
	Name = "Invis",
	Default = false,
	Callback = function(v) setInvis(v) end,
})

-- Aim
local AimTab = tab("Aim")
local tofSec = section(AimTab, "Twist of Fate")
tofSec:AddToggle({
	Name = "TOF 2 (Silent)",
	Default = false,
	Callback = function(v) Config.TOF2 = v end,
})
tofSec:AddSlider({
	Name = "Predict Strength",
	Min = 5,
	Max = 30,
	Default = 15,
	Increment = 1,
	Callback = function(v) Config.TOF2_Predict = v / 10 end,
})
tofSec:AddToggle({
	Name = "Flash Silent",
	Default = false,
	Callback = function(v) Config.FlashSilent = v end,
})

local veilSec = section(AimTab, "Veil & Butcher")
veilSec:AddToggle({
	Name = "Silent Veil",
	Default = false,
	Callback = function(v) Config.SilentVeil = v end,
})
veilSec:AddSlider({
	Name = "Veil Lead",
	Min = 5,
	Max = 30,
	Default = 17,
	Increment = 1,
	Callback = function(v) Config.VeilLead = v / 10 end,
})
veilSec:AddToggle({
	Name = "Butcher Aim",
	Default = false,
	Callback = function(v) Config.ButcherAim = v end,
})
veilSec:AddSlider({
	Name = "Butcher Lead",
	Min = 5,
	Max = 30,
	Default = 12,
	Increment = 1,
	Callback = function(v) Config.ButcherLead = v / 10 end,
})

-- Killer
local KillTab = tab("Killer")
local kSec = section(KillTab, "Killer Ability")
kSec:AddToggle({
	Name = "Infinite Lunge",
	Default = false,
	Callback = function(v) setInfLunge(v) end,
})
kSec:AddToggle({
	Name = "No Slowdown",
	Default = false,
	Callback = function(v)
		Config.NoSlowdown = v
		local char = LP.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if v and hum then hum.WalkSpeed = 16 end
	end,
})
kSec:AddToggle({
	Name = "Anti Blind",
	Default = false,
	Callback = function(v) Config.AntiBlind = v end,
})

-- Visual
local VisTab = tab("Visual")
local espSec = section(VisTab, "ESP")
espSec:AddToggle({
	Name = "Enable ESP",
	Default = false,
	Callback = function(v)
		Config.ESP_Master = v
		if not v then clearESP() else scanMap() updateESP() end
	end,
})
espSec:AddToggle({
	Name = "Player ESP",
	Default = false,
	Callback = function(v) Config.ESP_Player = v end,
})
espSec:AddToggle({
	Name = "Killer ESP",
	Default = false,
	Callback = function(v) Config.ESP_Killer = v end,
})
espSec:AddToggle({
	Name = "Generator ESP",
	Default = false,
	Callback = function(v) Config.ESP_Generator = v end,
})
espSec:AddToggle({
	Name = "Pallet ESP",
	Default = false,
	Callback = function(v) Config.ESP_Pallet = v end,
})
espSec:AddToggle({
	Name = "Hook ESP",
	Default = false,
	Callback = function(v) Config.ESP_Hook = v end,
})
espSec:AddToggle({
	Name = "Gate ESP",
	Default = false,
	Callback = function(v) Config.ESP_Gate = v end,
})
espSec:AddToggle({
	Name = "Window ESP",
	Default = false,
	Callback = function(v) Config.ESP_Window = v end,
})
espSec:AddSlider({
	Name = "ESP Max Distance",
	Min = 100,
	Max = 3000,
	Default = 1000,
	Increment = 50,
	Callback = function(v) Config.ESP_MaxDist = v end,
})
espSec:AddButton({
	Name = "Refresh Map",
	Callback = function()
		scanMap()
		if Config.ESP_Master then updateESP() end
		Kisha:Notify({ Title = "Map", Content = "Rescanned", Duration = 2 })
	end,
})

local worldSec = section(VisTab, "World")
worldSec:AddToggle({
	Name = "Full Bright",
	Default = false,
	Callback = function(v) setFullBright(v) end,
})
worldSec:AddToggle({
	Name = "No Fog",
	Default = false,
	Callback = function(v) setNoFog(v) end,
})
worldSec:AddToggle({
	Name = "Custom FOV",
	Default = false,
	Callback = function(v) setCustomFOV(v) end,
})
worldSec:AddSlider({
	Name = "FOV Value",
	Min = 60,
	Max = 120,
	Default = 90,
	Increment = 1,
	Callback = function(v) Config.FOVValue = v end,
})

-- Settings
local SetTab = tab("Settings")
local setSec = section(SetTab, "UI")
setSec:AddButton({
	Name = "Save Config",
	Callback = function()
		pcall(function()
			Kisha:SaveConfig("kisha_tixo")
			Kisha:Notify({ Title = "Config", Content = "Saved", Duration = 2 })
		end)
	end,
})
setSec:AddButton({
	Name = "Load Config",
	Callback = function()
		pcall(function()
			Kisha:LoadConfig("kisha_tixo")
			Kisha:Notify({ Title = "Config", Content = "Loaded", Duration = 2 })
		end)
	end,
})

pcall(function()
	Kisha:LoadConfig("kisha_tixo")
end)

Kisha:Notify({
	Title = "Kisha Tixo",
	Content = "Loaded — RightControl to toggle",
	Duration = 4,
})
