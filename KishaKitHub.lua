--[[
	Kisha Hub — Kit PvP (from decompiled client)
	UI: Kisha library
	Features derived from:
	  - client_request_attack_3 (CombatController_3)
	  - Config.combat.reach / building.reach
	  - EntityRenderer entity ids / positions
	  - AimTargeting / AimAssist
	  - Network.Fire ability / dash / stomp / jetpack / lobby_fly / holy_ray
]]

if not game:IsLoaded() then
	game.Loaded:Wait()
end

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local LocalPlayer = Players.LocalPlayer
local Camera = workspace.CurrentCamera

-- ===================== Kisha UI =====================
local KISHA_URL = "https://raw.githubusercontent.com/mialmos/Kisha-ui/refs/heads/main/Kisha.lua"
local Kisha
do
	local ok, src = pcall(function()
		return game:HttpGet(KISHA_URL)
	end)
	if not ok or type(src) ~= "string" or #src < 100 then
		error("[Kisha Hub] Failed to download Kisha UI", 0)
	end
	local fn, err = loadstring(src)
	if not fn then
		error("[Kisha Hub] Failed to compile Kisha: " .. tostring(err), 0)
	end
	Kisha = fn()
	if type(Kisha) ~= "table" or type(Kisha.CreateWindow) ~= "function" then
		error("[Kisha Hub] Kisha library missing CreateWindow", 0)
	end
end

local Window = Kisha:CreateWindow({
	Title = "Kisha Hub",
	Subtitle = "Kit PvP",
	ToggleKey = Enum.KeyCode.RightControl,
	Size = UDim2.fromOffset(560, 420),
	Keybinds = true,
})

local function notify(title, content, dur)
	pcall(function()
		Kisha:Notify({ Title = title or "Kisha", Content = content or "", Duration = dur or 3 })
	end)
end

-- ===================== Game module bridges =====================
local Network, EntityRenderer, Config, AimTargeting
local modulesReady = false

local function tryRequireModules()
	local ok1, net = pcall(function()
		return require(ReplicatedStorage.Shared.Network)
	end)
	local ok2, er = pcall(function()
		return require(ReplicatedStorage.Client.Controller_3.EntityRenderer)
	end)
	-- EntityRenderer path may differ; try alternate
	if not ok2 then
		ok2, er = pcall(function()
			local client = ReplicatedStorage:FindFirstChild("Client")
			local c3 = client and client:FindFirstChild("Controller_3")
			local mod = c3 and c3:FindFirstChild("EntityRenderer")
			return mod and require(mod)
		end)
	end
	local ok3, cfg = pcall(function()
		return require(ReplicatedStorage.Shared.Config)
	end)
	local ok4, aim = pcall(function()
		return require(ReplicatedStorage.Client.Controller_3.AimTargeting)
	end)
	if not ok4 then
		ok4, aim = pcall(function()
			local client = ReplicatedStorage:FindFirstChild("Client")
			local c3 = client and client:FindFirstChild("Controller_3")
			local mod = c3 and c3:FindFirstChild("AimTargeting")
			return mod and require(mod)
		end)
	end

	if ok1 then Network = net end
	if ok2 then EntityRenderer = er end
	if ok3 then Config = cfg end
	if ok4 then AimTargeting = aim end

	modulesReady = Network ~= nil
	return modulesReady
end

task.spawn(function()
	for _ = 1, 30 do
		if tryRequireModules() then
			notify("Modules", "Network bridged", 2)
			break
		end
		task.wait(1)
	end
end)

local function netFire(name, ...)
	if not Network or type(Network.Fire) ~= "function" then
		return false
	end
	local ok = pcall(Network.Fire, Network, name, ...)
	return ok
end

-- ===================== State =====================
local S = {
	KillAura = false,
	KillAuraRange = 8,
	KillAuraDelay = 0.12,
	Reach = false,
	ReachValue = 8,
	OrigReach = nil,
	OrigBuildReach = nil,
	SilentAim = false,
	AimAssistBoost = false,
	CamLock = false,
	CamLockMode = "none", -- "nearest" | "crosshair" | "none"
	CamLockTarget = nil,
	CamSmooth = 0.25,
	ESP = false,
	ESPTeamCheck = false,
	Speed = false,
	SpeedValue = 22,
	Fly = false,
	FlySpeed = 50,
	Noclip = false,
	InfJump = false,
	FOV = false,
	FOVValue = 100,
	Fullbright = false,
	AutoAbility = false,
	AutoDash = false,
	AutoStomp = false,
	JetpackSpam = false,
	HitboxExpand = false,
	HitboxSize = 6,
	NoMissDelay = false,
	AutoSprint = false,
}

local highlights = {} -- [model] = Highlight
local lastAura = 0
local flyBV, flyBG
local noclipParts = {}

-- ===================== Helpers =====================
local function charOf(plr)
	return plr and plr.Character
end

local function hrpOf(char)
	return char and char:FindFirstChild("HumanoidRootPart")
end

local function humOf(char)
	return char and char:FindFirstChildOfClass("Humanoid")
end

local function isAlive(char)
	local h = humOf(char)
	return h and h.Health > 0
end

local function myHRP()
	return hrpOf(LocalPlayer.Character)
end

local function clearHL(model)
	if not model then return end
	local h = highlights[model]
	if h then
		pcall(function() h:Destroy() end)
		highlights[model] = nil
	end
	local existing = model:FindFirstChild("KishaHL")
	if existing then pcall(function() existing:Destroy() end) end
end

local function setHL(model, fill, outline, fillT)
	if not model then return end
	local h = model:FindFirstChild("KishaHL")
	if not h then
		h = Instance.new("Highlight")
		h.Name = "KishaHL"
		h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
		h.Parent = model
	end
	h.FillColor = fill
	h.OutlineColor = outline
	h.FillTransparency = fillT or 0.5
	h.OutlineTransparency = 0.1
	h.Enabled = true
	highlights[model] = h
	return h
end

local function getEntityId(plr)
	if EntityRenderer and type(EntityRenderer.getPlayerEntityId) == "function" then
		local ok, id = pcall(EntityRenderer.getPlayerEntityId, EntityRenderer, plr)
		if ok and type(id) == "number" then return id end
	end
	return nil
end

local function getEntityPos(id)
	if EntityRenderer and type(EntityRenderer.getEntityDrawPosition) == "function" then
		local ok, pos = pcall(EntityRenderer.getEntityDrawPosition, EntityRenderer, id)
		if ok and typeof(pos) == "Vector3" then return pos end
	end
	return nil
end

local function getLastTick()
	if EntityRenderer and type(EntityRenderer.getLastUpdateTick) == "function" then
		local ok, t = pcall(EntityRenderer.getLastUpdateTick, EntityRenderer)
		if ok and type(t) == "number" then return t end
	end
	return 0
end

-- Fire attack using decompiled packet shape:
-- client_request_attack_3(Id, relativeVec, tick, position, lookTurn, fromUpdateTick)
local function fireAttack(targetPlr)
	if not targetPlr or targetPlr == LocalPlayer then return false end
	local tChar = charOf(targetPlr)
	if not isAlive(tChar) then return false end
	local tHRP = hrpOf(tChar)
	local me = myHRP()
	if not tHRP or not me then return false end

	local id = getEntityId(targetPlr)
	local pos = getEntityPos(id) or tHRP.Position
	local rel = me.Position - pos -- relative from target to attacker as used in client
	-- decompiled: vec7 - arg3.position where vec7 is eye/attack origin; use HRP delta
	rel = me.Position - pos

	local tickVal = getLastTick()
	-- lookTurn: use ANY / 0 as fallback when LookSweep unavailable
	local lookTurn = 0

	if id then
		return netFire("client_request_attack_3", id, rel, tickVal, pos, lookTurn, tickVal)
	end

	-- fallback: still try with a synthetic approach if Network works but no entity id
	-- without entity id server will reject; return false
	return false
end

local function nearestPlayer(maxDist)
	local me = myHRP()
	if not me then return nil, math.huge end
	local best, bestD = nil, maxDist or 1e9
	for _, plr in ipairs(Players:GetPlayers()) do
		if plr ~= LocalPlayer then
			local c = charOf(plr)
			local h = hrpOf(c)
			if isAlive(c) and h then
				local d = (h.Position - me.Position).Magnitude
				if d < bestD then
					best, bestD = plr, d
				end
			end
		end
	end
	return best, bestD
end

local function closestToCrosshair(maxPx)
	maxPx = maxPx or 200
	local cam = workspace.CurrentCamera
	if not cam then return nil end
	local center = Vector2.new(cam.ViewportSize.X / 2, cam.ViewportSize.Y / 2)
	local best, bestScore = nil, maxPx
	for _, plr in ipairs(Players:GetPlayers()) do
		if plr ~= LocalPlayer then
			local c = charOf(plr)
			if isAlive(c) then
				local part = c:FindFirstChild("Head") or hrpOf(c)
				if part then
					local sp, on = cam:WorldToViewportPoint(part.Position)
					if on and sp.Z > 0 then
						local score = (Vector2.new(sp.X, sp.Y) - center).Magnitude
						if score < bestScore then
							best, bestScore = plr, score
						end
					end
				end
			end
		end
	end
	return best
end

-- ===================== Reach patch =====================
local function applyReach(on)
	if not Config then
		tryRequireModules()
	end
	if not Config then return end
	pcall(function()
		if on then
			if S.OrigReach == nil and Config.combat then
				S.OrigReach = Config.combat.reach
			end
			if S.OrigBuildReach == nil and Config.building then
				S.OrigBuildReach = Config.building.reach
			end
			if Config.combat then Config.combat.reach = S.ReachValue end
			if Config.building then Config.building.reach = S.ReachValue end
		else
			if Config.combat and S.OrigReach ~= nil then Config.combat.reach = S.OrigReach end
			if Config.building and S.OrigBuildReach ~= nil then Config.building.reach = S.OrigBuildReach end
		end
	end)
	-- also patch miss delay
	if Config and Config.combat and S.NoMissDelay then
		pcall(function() Config.combat.hasMissDelay = false end)
	end
end

-- ===================== Kill aura loop =====================
task.spawn(function()
	while true do
		task.wait(0.03)
		if S.KillAura then
			local now = tick()
			if now - lastAura >= S.KillAuraDelay then
				local plr, dist = nearestPlayer(S.KillAuraRange)
				if plr and dist <= S.KillAuraRange then
					if fireAttack(plr) then
						lastAura = now
					else
						-- fallback: click simulation won't work well; try fire again without id path
						lastAura = now
					end
				end
			end
		end
		if S.AutoAbility then
			netFire("client_request_ability", nil)
		end
		if S.AutoDash then
			netFire("client_request_dasher_dash", Vector3.new(0, 0, -1))
		end
		if S.AutoStomp then
			netFire("client_request_stomp_leap")
			netFire("client_request_stomp")
		end
		if S.JetpackSpam then
			netFire("client_request_jetpack_thrust", true)
		end
	end
end)

-- ===================== Cam lock + aim =====================
local previewPlr = nil

RunService.RenderStepped:Connect(function(dt)
	-- Silent aim / assist: ease camera toward nearest or crosshair target while attacking
	if S.SilentAim or S.AimAssistBoost then
		local target = closestToCrosshair(250) or select(1, nearestPlayer(12))
		if target and isAlive(charOf(target)) then
			local part = charOf(target):FindFirstChild("Head") or hrpOf(charOf(target))
			if part then
				local cam = workspace.CurrentCamera
				local strength = S.SilentAim and 0.55 or 0.2
				cam.CFrame = cam.CFrame:Lerp(CFrame.lookAt(cam.CFrame.Position, part.Position), strength)
			end
		end
	end

	-- Cam lock
	if S.CamLock and S.CamLockTarget then
		local c = charOf(S.CamLockTarget)
		if not isAlive(c) then
			clearHL(c)
			S.CamLockTarget = nil
			S.CamLock = false
		else
			local part = c:FindFirstChild("Head") or hrpOf(c)
			if part then
				setHL(c, Color3.fromRGB(255, 40, 40), Color3.fromRGB(255, 100, 100), 0.4)
				local cam = workspace.CurrentCamera
				cam.CFrame = cam.CFrame:Lerp(CFrame.lookAt(cam.CFrame.Position, part.Position), S.CamSmooth)
			end
		end
	else
		-- yellow preview for crosshair candidate
		local cand = closestToCrosshair(160)
		if cand ~= previewPlr then
			if previewPlr and charOf(previewPlr) and previewPlr ~= S.CamLockTarget then
				clearHL(charOf(previewPlr))
			end
			previewPlr = cand
			if previewPlr and charOf(previewPlr) then
				setHL(charOf(previewPlr), Color3.fromRGB(255, 220, 40), Color3.fromRGB(255, 255, 120), 0.55)
			end
		elseif previewPlr and charOf(previewPlr) and previewPlr ~= S.CamLockTarget then
			setHL(charOf(previewPlr), Color3.fromRGB(255, 220, 40), Color3.fromRGB(255, 255, 120), 0.55)
		end
	end

	-- Speed
	if S.Speed then
		local h = humOf(LocalPlayer.Character)
		if h then h.WalkSpeed = S.SpeedValue end
	end

	-- FOV
	if S.FOV and workspace.CurrentCamera then
		workspace.CurrentCamera.FieldOfView = S.FOVValue
	end

	-- Hitbox expand (local visual only + larger selection for aura via range)
	if S.HitboxExpand then
		for _, plr in ipairs(Players:GetPlayers()) do
			if plr ~= LocalPlayer and isAlive(charOf(plr)) then
				local hrp = hrpOf(charOf(plr))
				if hrp then
					local box = hrp:FindFirstChild("KishaHitbox")
					if not box then
						box = Instance.new("Part")
						box.Name = "KishaHitbox"
						box.Anchored = true
						box.CanCollide = false
						box.CanQuery = false
						box.Material = Enum.Material.ForceField
						box.Color = Color3.fromRGB(255, 80, 80)
						box.Transparency = 0.7
						box.Parent = hrp
					end
					box.Size = Vector3.new(S.HitboxSize, S.HitboxSize * 1.4, S.HitboxSize)
					box.CFrame = hrp.CFrame
				end
			end
		end
	end
end)

-- Fly
RunService.Heartbeat:Connect(function(dt)
	if not S.Fly then
		if flyBV then pcall(function() flyBV:Destroy() end) flyBV = nil end
		if flyBG then pcall(function() flyBG:Destroy() end) flyBG = nil end
		return
	end
	local hrp = myHRP()
	local hum = humOf(LocalPlayer.Character)
	if not hrp or not hum then return end
	hum.PlatformStand = true
	if not flyBV or flyBV.Parent ~= hrp then
		if flyBV then pcall(function() flyBV:Destroy() end) end
		flyBV = Instance.new("BodyVelocity")
		flyBV.MaxForce = Vector3.new(1e5, 1e5, 1e5)
		flyBV.Velocity = Vector3.zero
		flyBV.Parent = hrp
	end
	if not flyBG or flyBG.Parent ~= hrp then
		if flyBG then pcall(function() flyBG:Destroy() end) end
		flyBG = Instance.new("BodyGyro")
		flyBG.MaxTorque = Vector3.new(1e5, 1e5, 1e5)
		flyBG.P = 1e4
		flyBG.Parent = hrp
	end
	local cam = workspace.CurrentCamera
	flyBG.CFrame = cam.CFrame
	local dir = Vector3.zero
	if UserInputService:IsKeyDown(Enum.KeyCode.W) then dir += cam.CFrame.LookVector end
	if UserInputService:IsKeyDown(Enum.KeyCode.S) then dir -= cam.CFrame.LookVector end
	if UserInputService:IsKeyDown(Enum.KeyCode.A) then dir -= cam.CFrame.RightVector end
	if UserInputService:IsKeyDown(Enum.KeyCode.D) then dir += cam.CFrame.RightVector end
	if UserInputService:IsKeyDown(Enum.KeyCode.Space) then dir += Vector3.yAxis end
	if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then dir -= Vector3.yAxis end
	if dir.Magnitude > 0 then dir = dir.Unit * S.FlySpeed else dir = Vector3.zero end
	flyBV.Velocity = dir
end)

-- Noclip
RunService.Stepped:Connect(function()
	if not S.Noclip then return end
	local char = LocalPlayer.Character
	if not char then return end
	for _, part in ipairs(char:GetDescendants()) do
		if part:IsA("BasePart") then
			part.CanCollide = false
		end
	end
end)

-- Inf jump
UserInputService.JumpRequest:Connect(function()
	if not S.InfJump then return end
	local h = humOf(LocalPlayer.Character)
	if h then
		h:ChangeState(Enum.HumanoidStateType.Jumping)
	end
end)

-- Cam lock keys R / E / Q
UserInputService.InputBegan:Connect(function(input, gp)
	if gp then return end
	if input.KeyCode == Enum.KeyCode.R then
		local plr = select(1, nearestPlayer(500))
		if plr then
			if S.CamLockTarget and charOf(S.CamLockTarget) then clearHL(charOf(S.CamLockTarget)) end
			S.CamLockTarget = plr
			S.CamLock = true
			S.CamLockMode = "nearest"
			notify("Cam Lock", "R → " .. plr.Name, 2)
		end
	elseif input.KeyCode == Enum.KeyCode.E then
		local plr = closestToCrosshair(300)
		if plr then
			if S.CamLockTarget and charOf(S.CamLockTarget) then clearHL(charOf(S.CamLockTarget)) end
			S.CamLockTarget = plr
			S.CamLock = true
			S.CamLockMode = "crosshair"
			notify("Cam Lock", "E → " .. plr.Name, 2)
		end
	elseif input.KeyCode == Enum.KeyCode.Q then
		if S.CamLockTarget and charOf(S.CamLockTarget) then clearHL(charOf(S.CamLockTarget)) end
		S.CamLock = false
		S.CamLockTarget = nil
		S.CamLockMode = "none"
		notify("Cam Lock", "Unlocked", 2)
	end
end)

-- ESP
local espFolder = Instance.new("Folder")
espFolder.Name = "KishaESP"
espFolder.Parent = game:GetService("CoreGui")

local function clearESP()
	espFolder:ClearAllChildren()
end

local function updateESP()
	if not S.ESP then
		clearESP()
		return
	end
	clearESP()
	for _, plr in ipairs(Players:GetPlayers()) do
		if plr ~= LocalPlayer and isAlive(charOf(plr)) then
			local hrp = hrpOf(charOf(plr))
			if hrp then
				local bb = Instance.new("BillboardGui")
				bb.Name = plr.Name
				bb.Adornee = hrp
				bb.Size = UDim2.fromOffset(120, 30)
				bb.AlwaysOnTop = true
				bb.Parent = espFolder
				local tl = Instance.new("TextLabel")
				tl.Size = UDim2.fromScale(1, 1)
				tl.BackgroundTransparency = 1
				tl.TextColor3 = Color3.fromRGB(255, 80, 80)
				tl.TextStrokeTransparency = 0.4
				tl.Font = Enum.Font.GothamBold
				tl.TextSize = 13
				local dist = myHRP() and math.floor((hrp.Position - myHRP().Position).Magnitude) or 0
				tl.Text = string.format("%s [%dm]", plr.Name, dist)
				tl.Parent = bb
				local hl = setHL(charOf(plr), Color3.fromRGB(255, 60, 60), Color3.fromRGB(255, 120, 120), 0.75)
			end
		end
	end
end

task.spawn(function()
	while true do
		task.wait(0.5)
		if S.ESP then pcall(updateESP) end
	end
end)

-- Fullbright
local function applyFullbright(on)
	if on then
		Lighting.Brightness = 2.5
		Lighting.ClockTime = 14
		Lighting.FogEnd = 1e6
		Lighting.GlobalShadows = false
		Lighting.OutdoorAmbient = Color3.new(1, 1, 1)
	else
		Lighting.Brightness = 1
		Lighting.FogEnd = 1000
		Lighting.GlobalShadows = true
	end
end

LocalPlayer.CharacterAdded:Connect(function()
	task.wait(1)
	if S.Fly then
		local h = humOf(LocalPlayer.Character)
		if h then h.PlatformStand = false end
	end
	if not S.Fly then
		if flyBV then pcall(function() flyBV:Destroy() end) flyBV = nil end
	end
end)

-- ===================== UI =====================
local Combat = Window:CreateTab({ Name = "Combat" })
local Visual = Window:CreateTab({ Name = "Visual" })
local Move = Window:CreateTab({ Name = "Movement" })
local Misc = Window:CreateTab({ Name = "Misc" })

local cSec = Combat:CreateSection({ Name = "Attack" })
cSec:AddToggle({
	Name = "Kill Aura",
	Default = false,
	Flag = "KillAura",
	Callback = function(v)
		S.KillAura = v
		if v and not modulesReady then
			tryRequireModules()
			if not modulesReady then
				notify("Kill Aura", "Network module not ready — attacks may fail", 3)
			end
		end
	end,
})
cSec:AddSlider({
	Name = "Aura Range",
	Min = 3,
	Max = 25,
	Default = 8,
	Increment = 0.5,
	Flag = "AuraRange",
	Callback = function(v) S.KillAuraRange = v end,
})
cSec:AddSlider({
	Name = "Aura Delay",
	Min = 0.05,
	Max = 0.5,
	Default = 0.12,
	Increment = 0.01,
	Flag = "AuraDelay",
	Callback = function(v) S.KillAuraDelay = v end,
})
cSec:AddToggle({
	Name = "Reach",
	Default = false,
	Flag = "Reach",
	Callback = function(v)
		S.Reach = v
		applyReach(v)
	end,
})
cSec:AddSlider({
	Name = "Reach Value",
	Min = 3,
	Max = 20,
	Default = 8,
	Increment = 0.5,
	Flag = "ReachVal",
	Callback = function(v)
		S.ReachValue = v
		if S.Reach then applyReach(true) end
	end,
})
cSec:AddToggle({
	Name = "No Miss Delay",
	Default = false,
	Flag = "NoMiss",
	Callback = function(v)
		S.NoMissDelay = v
		if Config and Config.combat then
			pcall(function() Config.combat.hasMissDelay = not v and Config.combat.hasMissDelay or false end)
		end
	end,
})
cSec:AddToggle({
	Name = "Silent Aim (cam pull)",
	Default = false,
	Flag = "SilentAim",
	Callback = function(v) S.SilentAim = v end,
})
cSec:AddToggle({
	Name = "Aim Assist Boost",
	Default = false,
	Flag = "AimBoost",
	Callback = function(v) S.AimAssistBoost = v end,
})

local lockSec = Combat:CreateSection({ Name = "Cam Lock" })
lockSec:AddToggle({
	Name = "Cam Lock Enabled",
	Default = false,
	Flag = "CamLock",
	Callback = function(v)
		S.CamLock = v
		if not v and S.CamLockTarget and charOf(S.CamLockTarget) then
			clearHL(charOf(S.CamLockTarget))
			S.CamLockTarget = nil
		end
	end,
})
lockSec:AddSlider({
	Name = "Lock Smoothness",
	Min = 0.05,
	Max = 1,
	Default = 0.25,
	Increment = 0.05,
	Flag = "CamSmooth",
	Callback = function(v) S.CamSmooth = v end,
})
-- keybinds documented: R nearest, E crosshair, Q unlock

local kitSec = Combat:CreateSection({ Name = "Kit Spam" })
kitSec:AddToggle({
	Name = "Auto Ability",
	Default = false,
	Flag = "AutoAbility",
	Callback = function(v) S.AutoAbility = v end,
})
kitSec:AddToggle({
	Name = "Auto Dash (Dasher)",
	Default = false,
	Flag = "AutoDash",
	Callback = function(v) S.AutoDash = v end,
})
kitSec:AddToggle({
	Name = "Auto Stomp",
	Default = false,
	Flag = "AutoStomp",
	Callback = function(v) S.AutoStomp = v end,
})
kitSec:AddToggle({
	Name = "Jetpack Thrust Spam",
	Default = false,
	Flag = "Jetpack",
	Callback = function(v)
		S.JetpackSpam = v
		if not v then netFire("client_request_jetpack_thrust", false) end
	end,
})
kitSec:AddButton({
	Name = "Angel Air Jump Once",
	Callback = function()
		netFire("client_request_angel_air_jump")
	end,
})
kitSec:AddButton({
	Name = "Holy Ray Start",
	Callback = function()
		netFire("client_request_holy_ray_start")
	end,
})
kitSec:AddButton({
	Name = "Holy Ray Stop",
	Callback = function()
		netFire("client_request_holy_ray_stop")
	end,
})

local vSec = Visual:CreateSection({ Name = "ESP & World" })
vSec:AddToggle({
	Name = "Player ESP",
	Default = false,
	Flag = "ESP",
	Callback = function(v)
		S.ESP = v
		if not v then clearESP() end
	end,
})
vSec:AddToggle({
	Name = "Hitbox Visual",
	Default = false,
	Flag = "Hitbox",
	Callback = function(v)
		S.HitboxExpand = v
		if not v then
			for _, plr in ipairs(Players:GetPlayers()) do
				local hrp = hrpOf(charOf(plr))
				if hrp then
					local b = hrp:FindFirstChild("KishaHitbox")
					if b then b:Destroy() end
				end
			end
		end
	end,
})
vSec:AddSlider({
	Name = "Hitbox Size",
	Min = 2,
	Max = 12,
	Default = 6,
	Increment = 0.5,
	Flag = "HitboxSize",
	Callback = function(v) S.HitboxSize = v end,
})
vSec:AddToggle({
	Name = "Fullbright",
	Default = false,
	Flag = "Fullbright",
	Callback = function(v)
		S.Fullbright = v
		applyFullbright(v)
	end,
})
vSec:AddToggle({
	Name = "Custom FOV",
	Default = false,
	Flag = "FOV",
	Callback = function(v)
		S.FOV = v
		if not v and workspace.CurrentCamera then
			workspace.CurrentCamera.FieldOfView = 70
		end
	end,
})
vSec:AddSlider({
	Name = "FOV Value",
	Min = 40,
	Max = 120,
	Default = 100,
	Increment = 1,
	Flag = "FOVVal",
	Callback = function(v) S.FOVValue = v end,
})

local mSec = Move:CreateSection({ Name = "Movement" })
mSec:AddToggle({
	Name = "Speed",
	Default = false,
	Flag = "Speed",
	Callback = function(v)
		S.Speed = v
		if not v then
			local h = humOf(LocalPlayer.Character)
			if h then h.WalkSpeed = 16 end
		end
	end,
})
mSec:AddSlider({
	Name = "Speed Value",
	Min = 16,
	Max = 50,
	Default = 22,
	Increment = 1,
	Flag = "SpeedVal",
	Callback = function(v) S.SpeedValue = v end,
})
mSec:AddToggle({
	Name = "Fly (client)",
	Default = false,
	Flag = "Fly",
	Callback = function(v)
		S.Fly = v
		local h = humOf(LocalPlayer.Character)
		if not v and h then h.PlatformStand = false end
		if not v then
			if flyBV then pcall(function() flyBV:Destroy() end) flyBV = nil end
			if flyBG then pcall(function() flyBG:Destroy() end) flyBG = nil end
		end
	end,
})
mSec:AddSlider({
	Name = "Fly Speed",
	Min = 20,
	Max = 120,
	Default = 50,
	Increment = 5,
	Flag = "FlySpeed",
	Callback = function(v) S.FlySpeed = v end,
})
mSec:AddToggle({
	Name = "Noclip",
	Default = false,
	Flag = "Noclip",
	Callback = function(v) S.Noclip = v end,
})
mSec:AddToggle({
	Name = "Infinite Jump",
	Default = false,
	Flag = "InfJump",
	Callback = function(v) S.InfJump = v end,
})
mSec:AddButton({
	Name = "Request Lobby Fly ON",
	Callback = function()
		netFire("client_request_lobby_fly", "on")
		notify("Lobby Fly", "Requested ON", 2)
	end,
})
mSec:AddButton({
	Name = "Request Lobby Fly OFF",
	Callback = function()
		netFire("client_request_lobby_fly", "off")
	end,
})

local xSec = Misc:CreateSection({ Name = "System" })
xSec:AddButton({
	Name = "Retry Module Bridge",
	Callback = function()
		if tryRequireModules() then
			notify("Modules", "OK — Network ready", 2)
		else
			notify("Modules", "Still missing Network/EntityRenderer", 3)
		end
	end,
})
local extra = Misc:CreateSection({ Name = "Extra (2nd scan)" })
extra:AddButton({
	Name = "Crossbow Shoot",
	Callback = function()
		-- payload unknown; fire empty / look vector attempt
		local me = myHRP()
		local look = workspace.CurrentCamera and workspace.CurrentCamera.CFrame.LookVector or Vector3.zAxis
		netFire("client_request_crossbow_shoot", look)
	end,
})
extra:AddButton({
	Name = "Item Use Start",
	Callback = function() netFire("client_request_item_use_start") end,
})
extra:AddButton({
	Name = "Item Use Release",
	Callback = function() netFire("client_request_item_use_release") end,
})
extra:AddButton({
	Name = "Throw Item",
	Callback = function()
		local look = workspace.CurrentCamera and workspace.CurrentCamera.CFrame.LookVector or Vector3.zAxis
		netFire("client_request_item_throw", look)
	end,
})
extra:AddButton({
	Name = "Pop Decoy",
	Callback = function() netFire("client_request_pop_decoy") end,
})
extra:AddButton({
	Name = "Lucky Block Use",
	Callback = function() netFire("client_request_lucky_block_use") end,
})
extra:AddButton({
	Name = "Break Start (look)",
	Callback = function() netFire("client_request_break_start") end,
})

xSec:AddButton({
	Name = "Reset Character",
	Callback = function()
		netFire("client_request_reset")
		local h = humOf(LocalPlayer.Character)
		if h then h.Health = 0 end
	end,
})
xSec:AddButton({
	Name = "Unload Hub",
	Callback = function()
		S.KillAura = false
		S.Fly = false
		S.Noclip = false
		S.ESP = false
		S.CamLock = false
		clearESP()
		pcall(function() Window:Destroy() end)
	end,
})

notify("Kisha Hub", "Kit PvP loaded — R nearest lock | E crosshair lock | Q unlock", 4)
print("[Kisha Hub] Kit PvP — modulesReady=", modulesReady)
