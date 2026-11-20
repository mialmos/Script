--[[
	Kisha Hub — Kit PvP (fixed combat bridge)
	Kill aura / reach use the game's own modules:
	  Network.Fire("client_request_attack_3", id, rel, tick, pos, lookTurn, fromTick)
	  CombatController.setReach(n)
	  EntityRenderer.getEntityViewList_3()
]]

if not game:IsLoaded() then game.Loaded:Wait() end

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local LocalPlayer = Players.LocalPlayer

-- ===================== Kisha UI =====================
local KISHA_URL = "https://raw.githubusercontent.com/mialmos/Kisha-ui/refs/heads/main/Kisha.lua"
local Kisha do
	local ok, src = pcall(game.HttpGet, game, KISHA_URL)
	assert(ok and type(src) == "string" and #src > 100, "Kisha UI download failed")
	local fn, err = loadstring(src)
	assert(fn, "Kisha compile failed: " .. tostring(err))
	Kisha = fn()
end

local Window = Kisha:CreateWindow({
	Title = "Kisha Hub",
	Subtitle = "Kit PvP",
	ToggleKey = Enum.KeyCode.RightControl,
	Size = UDim2.fromOffset(580, 440),
	Keybinds = true,
})

local function notify(title, body, dur)
	pcall(function()
		Kisha:Notify({ Title = title or "Kisha", Content = body or "", Duration = dur or 3 })
	end)
end

-- ===================== Module bridge =====================
local Mods = {
	Network = nil,
	Combat = nil,
	Entity = nil,
	Camera = nil,
	LookSweep = nil,
	status = "not loaded",
}

local function findModule(...)
	local path = { ... }
	local node = path[1] == "RS" and ReplicatedStorage or path[1] == "Client" and ReplicatedStorage:FindFirstChild("Client") or path[1]
	if path[1] == "RS" then
		node = ReplicatedStorage
		for i = 2, #path do
			if not node then return nil end
			node = node:FindFirstChild(path[i])
		end
		return node
	end
	return nil
end

local function requirePath(...)
	local inst = findModule(...)
	if not inst then return nil end
	local ok, mod = pcall(require, inst)
	if ok then return mod end
	return nil
end

local function deepRequire(names)
	-- search under ReplicatedStorage for ModuleScript named in list
	for _, inst in ipairs(ReplicatedStorage:GetDescendants()) do
		if inst:IsA("ModuleScript") then
			for _, n in ipairs(names) do
				if inst.Name == n then
					local ok, mod = pcall(require, inst)
					if ok and type(mod) == "table" then
						return mod, inst:GetFullName()
					end
				end
			end
		end
	end
	return nil
end

function Mods.refresh()
	-- Network
	Mods.Network = requirePath("RS", "Shared", "Network")
		or select(1, deepRequire({ "Network" }))

	-- CombatController_3
	Mods.Combat = requirePath("RS", "Client", "Controller_3", "CombatController_3")
		or select(1, deepRequire({ "CombatController_3", "CombatController" }))

	-- EntityRenderer
	Mods.Entity = requirePath("RS", "Client", "Controller_3", "EntityRenderer")
		or select(1, deepRequire({ "EntityRenderer" }))

	-- CameraController (look turn)
	Mods.Camera = requirePath("RS", "Client", "Controller_3", "CameraController")
		or select(1, deepRequire({ "CameraController" }))

	Mods.LookSweep = requirePath("RS", "Shared", "LookSweep")
		or select(1, deepRequire({ "LookSweep" }))

	Mods.Movement = requirePath("RS", "Client", "Controller_3", "MovementController_3")
		or select(1, deepRequire({ "MovementController_3", "MovementController" }))

	local bits = {}
	bits[#bits + 1] = Mods.Network and "Net" or "no-Net"
	bits[#bits + 1] = Mods.Combat and "Combat" or "no-Combat"
	bits[#bits + 1] = Mods.Entity and "Entity" or "no-Entity"
	bits[#bits + 1] = Mods.Movement and "Move" or "no-Move"
	Mods.status = table.concat(bits, " | ")
	return Mods.Network ~= nil
end

-- keep trying for a while after join
task.spawn(function()
	for i = 1, 40 do
		if Mods.refresh() and Mods.Entity and Mods.Combat then
			notify("Bridge", "Modules OK: " .. Mods.status, 3)
			break
		end
		task.wait(0.75)
	end
	if not Mods.Network then
		notify("Bridge", "Still missing modules — open Misc → Retry Bridge in-match", 5)
	end
end)

local function netFire(name, ...)
	local n = Mods.Network
	if not n or type(n.Fire) ~= "function" then return false, "no network" end
	-- Network.Fire is a plain function: Fire(name, ...), NOT Fire(self, name, ...)
	local ok, err = pcall(n.Fire, name, ...)
	return ok, err
end

local function anyTurn()
	if Mods.LookSweep and type(Mods.LookSweep.ANY_TURN) == "number" then
		return Mods.LookSweep.ANY_TURN
	end
	return 180
end

local function lookTurn()
	if Mods.Camera and type(Mods.Camera.getLookTurn) == "function" then
		local ok, v = pcall(Mods.Camera.getLookTurn) -- no self
		if ok and v ~= nil then return v end
	end
	return anyTurn()
end

local function lastTick()
	if Mods.Entity and type(Mods.Entity.getLastUpdateTick) == "function" then
		local ok, t = pcall(Mods.Entity.getLastUpdateTick) -- no self
		if ok and type(t) == "number" then return t end
	end
	return 0
end

local function entityList()
	if not Mods.Entity then return {} end
	if type(Mods.Entity.getEntityViewList_3) == "function" then
		local ok, list = pcall(Mods.Entity.getEntityViewList_3) -- no self
		if ok and type(list) == "table" then return list end
	end
	return {}
end

-- ===================== State =====================
local S = {
	KillAura = false,
	AuraRange = 18,
	AuraDelay = 0.1,
	Reach = false,
	ReachValue = 10,
	SilentAim = false,
	AimFov = 180,
	AimSmooth = 0.35,
	CamLock = false,
	CamTarget = nil, -- Player
	CamSmooth = 0.28,
	ESP = false,
	Speed = false,
	SpeedVal = 22,
	Fly = false,
	FlySpeed = 55,
	Noclip = false,
	InfJump = false,
	FOV = false,
	FOVVal = 100,
	Fullbright = false,
	AutoAbility = false,
	AutoDash = false,
	AutoStomp = false,
	Jetpack = false,
}

local lastAura = 0
local flyBV, flyBG
local previewModel = nil

-- ===================== Helpers =====================
local function myChar() return LocalPlayer.Character end
local function myHRP() local c = myChar() return c and c:FindFirstChild("HumanoidRootPart") end
local function myHum() local c = myChar() return c and c:FindFirstChildOfClass("Humanoid") end

local function setHL(model, fill, outline, ft)
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
	h.FillTransparency = ft or 0.5
	h.OutlineTransparency = 0.15
	h.Enabled = true
	return h
end

local function clearHL(model)
	if not model then return end
	local h = model:FindFirstChild("KishaHL")
	if h then h:Destroy() end
end

-- True attack using decompiled packet
local function attackEntity(ent, eyePos)
	if not ent or not ent.id then return false end
	if type(ent.health) == "number" and ent.health <= 0 then return false end
	if ent.player == LocalPlayer then return false end
	if ent.isVanished then return false end

	local pos = ent.position
	if typeof(pos) ~= "Vector3" then return false end

	eyePos = eyePos or (myHRP() and myHRP().Position) or pos
	local rel = eyePos - pos
	local tickNow = lastTick()
	local fromTick = ent.fromUpdateTick or tickNow

	-- client_request_attack_3(Id, relativeVec, tick, position, lookTurn, fromUpdateTick)
	local ok = netFire(
		"client_request_attack_3",
		ent.id,
		rel,
		tickNow,
		pos,
		anyTurn(), -- allow any aim angle like miss-swing path
		fromTick
	)
	return ok
end

local function getMyBlockPos()
	-- 0) MovementController positions are already block-space
	if Mods.Movement then
		if type(Mods.Movement.getEyePosition_3) == "function" then
			local ok, p = pcall(Mods.Movement.getEyePosition_3)
			if ok and typeof(p) == "Vector3" then return p, "eye" end
		end
		if type(Mods.Movement.getPosition) == "function" then
			local ok, p = pcall(Mods.Movement.getPosition)
			if ok and typeof(p) == "Vector3" then return p, "move" end
		end
	end
	-- 1) local entity id → draw position (block space)
	if Mods.Entity and type(Mods.Entity.getLocalEntityId) == "function" then
		local okId, lid = pcall(Mods.Entity.getLocalEntityId)
		if okId and lid ~= nil then
			if type(Mods.Entity.getEntityDrawPosition) == "function" then
				local okp, p = pcall(Mods.Entity.getEntityDrawPosition, lid)
				if okp and typeof(p) == "Vector3" then return p, "draw:" .. tostring(lid) end
			end
			if type(Mods.Entity.getEntityView) == "function" then
				local okv, view = pcall(Mods.Entity.getEntityView, lid)
				if okv and view and typeof(view.position) == "Vector3" then
					return view.position, "view:" .. tostring(lid)
				end
			end
		end
	end
	-- 2) find ourselves inside entityList
	for _, ent in ipairs(entityList()) do
		if ent and ent.player == LocalPlayer and typeof(ent.position) == "Vector3" then
			return ent.position, "list-self"
		end
	end
	-- 3) classic character
	local hrp = myHRP()
	if hrp then return hrp.Position / 3, "hrp/3" end
	-- 4) Camera as last resort (block space)
	local cam = workspace.CurrentCamera
	if cam then return cam.CFrame.Position / 3, "cam/3" end
	return nil, "none"
end

local function entitiesInRange(range)
	range = range or 1e9
	local origin, originSrc = getMyBlockPos()
	local out = {}
	for _, ent in ipairs(entityList()) do
		if not ent or not ent.id then continue end
		if ent.player == LocalPlayer then continue end
		if type(ent.health) == "number" and ent.health <= 0 then continue end
		if ent.isVanished then continue end
		local pos = ent.position
		if typeof(pos) ~= "Vector3" then continue end
		local d = origin and (pos - origin).Magnitude or 0
		-- if no origin, still include everyone (sorted as 0) so aura/test can fire
		if (not origin) or d <= range then
			out[#out + 1] = { ent = ent, dist = d }
		end
	end
	table.sort(out, function(a, b) return a.dist < b.dist end)
	return out, originSrc
end

local function nearestEntity(range)
	local list = entitiesInRange(range or 1e9)
	return list[1] and list[1].ent, list[1] and list[1].dist
end

local function dumpEntities(limit)
	limit = limit or 12
	local origin, osrc = getMyBlockPos()
	print("[Kisha Dump] myBlockPos=", origin, "src=", osrc)
	local n = 0
	for _, ent in ipairs(entityList()) do
		n += 1
		if n > limit then break end
		local pos = ent and ent.position
		local d = (origin and typeof(pos) == "Vector3") and (pos - origin).Magnitude or -1
		local pname = ent.player and ent.player.Name or (ent.mobModel and "mob" or "?")
		print(string.format(
			"[Kisha Dump] id=%s player=%s health=%s dist=%.2f pos=%s vanished=%s",
			tostring(ent.id),
			tostring(pname),
			tostring(ent.health),
			d,
			tostring(pos),
			tostring(ent.isVanished)
		))
	end
	print("[Kisha Dump] total listed", n, "of", #entityList())
end

local function playerFromEnt(ent)
	return ent and ent.player
end

local function closestPlayerToCrosshair(maxPx)
	maxPx = maxPx or 220
	local cam = workspace.CurrentCamera
	if not cam then return nil end
	local center = Vector2.new(cam.ViewportSize.X * 0.5, cam.ViewportSize.Y * 0.5)
	local best, bestScore = nil, maxPx
	for _, plr in ipairs(Players:GetPlayers()) do
		if plr ~= LocalPlayer and plr.Character then
			local part = plr.Character:FindFirstChild("Head") or plr.Character:FindFirstChild("HumanoidRootPart")
			local hum = plr.Character:FindFirstChildOfClass("Humanoid")
			if part and hum and hum.Health > 0 then
				local sp, on = cam:WorldToViewportPoint(part.Position)
				if on and sp.Z > 0 then
					local sc = (Vector2.new(sp.X, sp.Y) - center).Magnitude
					if sc < bestScore then
						best, bestScore = plr, sc
					end
				end
			end
		end
	end
	return best
end

local function nearestPlayerStuds(maxd)
	local hrp = myHRP()
	if not hrp then return nil end
	local best, bd = nil, maxd or 1e9
	for _, plr in ipairs(Players:GetPlayers()) do
		if plr ~= LocalPlayer and plr.Character then
			local t = plr.Character:FindFirstChild("HumanoidRootPart")
			local h = plr.Character:FindFirstChildOfClass("Humanoid")
			if t and h and h.Health > 0 then
				local d = (t.Position - hrp.Position).Magnitude
				if d < bd then best, bd = plr, d end
			end
		end
	end
	return best, bd
end

-- ===================== Reach (real) =====================
local function applyReach(on)
	if not Mods.Combat then Mods.refresh() end
	if not Mods.Combat or type(Mods.Combat.setReach) ~= "function" then
		notify("Reach", "CombatController not found — join a match and Retry Bridge", 3)
		return false
	end
	if on then
		Mods.Combat.setReach(S.ReachValue) -- plain function, no self
	else
		Mods.Combat.setReach(nil) -- back to default (3)
	end
	return true
end

-- ===================== Kill aura loop =====================
task.spawn(function()
	while true do
		local waitTime = S.KillAura and math.max(S.AuraDelay, 0.03) or 0.15
		task.wait(waitTime)
		if S.KillAura then
			if not Mods.Network or not Mods.Entity then
				Mods.refresh()
			end
			local eye = myHRP() and (myHRP().Position / 3) -- block space
			local list = entitiesInRange(S.AuraRange)
			-- also compare against character distances in studs
			if #list == 0 then
				-- fallback: map nearest player → entity id
				local plr, dist = nearestPlayerStuds(S.AuraRange)
				if plr and Mods.Entity and type(Mods.Entity.getPlayerEntityId) == "function" then
					local ok, id = pcall(Mods.Entity.getPlayerEntityId, plr) -- no self
					if ok and type(id) == "number" then
						local view = Mods.Entity.getEntityView and Mods.Entity.getEntityView(id) -- no self
						if view then
							list = { { ent = view, dist = dist } }
						else
							-- synthesize minimal entity table
							local hrp = plr.Character and plr.Character:FindFirstChild("HumanoidRootPart")
							if hrp then
								list = { {
									ent = {
										id = id,
										position = hrp.Position,
										player = plr,
										health = 20,
										fromUpdateTick = lastTick(),
									},
									dist = dist,
								} }
							end
						end
					end
				end
			end
			for _, item in ipairs(list) do
				if item.dist <= S.AuraRange * 1.5 then -- tolerance for block-vs-stud units
					if attackEntity(item.ent, eye) then
						break -- one per tick like a real swing
					end
				end
			end
		end

		if S.AutoAbility then netFire("client_request_ability", nil) end
		if S.AutoDash then
			local look = workspace.CurrentCamera and workspace.CurrentCamera.CFrame.LookVector or Vector3.zAxis
			netFire("client_request_dasher_dash", look)
		end
		if S.AutoStomp then
			netFire("client_request_stomp_leap")
			netFire("client_request_stomp")
		end
		if S.Jetpack then netFire("client_request_jetpack_thrust", true) end
	end
end)

-- keep reach applied (game may reset it)
task.spawn(function()
	while true do
		task.wait(1)
		if S.Reach and Mods.Combat and type(Mods.Combat.setReach) == "function" then
			pcall(Mods.Combat.setReach, S.ReachValue) -- no self
		end
	end
end)

-- ===================== Aim + cam lock =====================
RunService.RenderStepped:Connect(function()
	local cam = workspace.CurrentCamera
	if not cam then return end

	-- Silent aim: pull camera toward closest-to-crosshair player
	if S.SilentAim then
		local aimed = false
		local plr = closestPlayerToCrosshair(S.AimFov)
		if plr and plr.Character then
			local part = plr.Character:FindFirstChild("Head") or plr.Character:FindFirstChild("HumanoidRootPart")
			if part then
				cam.CFrame = cam.CFrame:Lerp(CFrame.lookAt(cam.CFrame.Position, part.Position), S.AimSmooth)
				aimed = true
			end
		end
		if not aimed then
			-- aim at nearest entity in block space → world (*3)
			local ent = nearestEntity(S.AuraRange + 5)
			if ent and typeof(ent.position) == "Vector3" then
				local worldPos = ent.position * 3 + Vector3.new(0, 2, 0)
				cam.CFrame = cam.CFrame:Lerp(CFrame.lookAt(cam.CFrame.Position, worldPos), S.AimSmooth)
			end
		end
	end

	-- Cam lock hard track
	if S.CamLock and S.CamTarget then
		local c = S.CamTarget.Character
		local hum = c and c:FindFirstChildOfClass("Humanoid")
		local part = c and (c:FindFirstChild("Head") or c:FindFirstChild("HumanoidRootPart"))
		if not (hum and hum.Health > 0 and part) then
			clearHL(c)
			S.CamTarget = nil
			S.CamLock = false
		else
			setHL(c, Color3.fromRGB(255, 40, 40), Color3.fromRGB(255, 110, 110), 0.4)
			cam.CFrame = cam.CFrame:Lerp(CFrame.lookAt(cam.CFrame.Position, part.Position), S.CamSmooth)
		end
	else
		-- yellow preview under crosshair
		local cand = closestPlayerToCrosshair(150)
		local model = cand and cand.Character
		if model ~= previewModel then
			if previewModel then clearHL(previewModel) end
			previewModel = model
			if previewModel then
				setHL(previewModel, Color3.fromRGB(255, 220, 40), Color3.fromRGB(255, 255, 140), 0.55)
			end
		elseif previewModel then
			setHL(previewModel, Color3.fromRGB(255, 220, 40), Color3.fromRGB(255, 255, 140), 0.55)
		end
	end

	if S.Speed then
		local h = myHum()
		if h then h.WalkSpeed = S.SpeedVal end
	end
	if S.FOV then cam.FieldOfView = S.FOVVal end
end)

-- Fly
RunService.Heartbeat:Connect(function()
	if not S.Fly then
		if flyBV then pcall(function() flyBV:Destroy() end) flyBV = nil end
		if flyBG then pcall(function() flyBG:Destroy() end) flyBG = nil end
		return
	end
	local hrp, hum = myHRP(), myHum()
	if not hrp or not hum then return end
	hum.PlatformStand = true
	if not flyBV or flyBV.Parent ~= hrp then
		if flyBV then pcall(function() flyBV:Destroy() end) end
		flyBV = Instance.new("BodyVelocity")
		flyBV.MaxForce = Vector3.new(1e5, 1e5, 1e5)
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
	flyBV.Velocity = dir.Magnitude > 0 and dir.Unit * S.FlySpeed or Vector3.zero
end)

RunService.Stepped:Connect(function()
	if not S.Noclip then return end
	local c = myChar()
	if not c then return end
	for _, p in ipairs(c:GetDescendants()) do
		if p:IsA("BasePart") then p.CanCollide = false end
	end
end)

UserInputService.JumpRequest:Connect(function()
	if S.InfJump then
		local h = myHum()
		if h then h:ChangeState(Enum.HumanoidStateType.Jumping) end
	end
end)

UserInputService.InputBegan:Connect(function(input, gp)
	if gp then return end
	if input.KeyCode == Enum.KeyCode.R then
		local plr = nearestPlayerStuds(600)
		if plr then
			if S.CamTarget and S.CamTarget.Character then clearHL(S.CamTarget.Character) end
			S.CamTarget = plr
			S.CamLock = true
			notify("Lock", "R → " .. plr.Name, 2)
		end
	elseif input.KeyCode == Enum.KeyCode.E then
		local plr = closestPlayerToCrosshair(320)
		if plr then
			if S.CamTarget and S.CamTarget.Character then clearHL(S.CamTarget.Character) end
			S.CamTarget = plr
			S.CamLock = true
			notify("Lock", "E → " .. plr.Name, 2)
		end
	elseif input.KeyCode == Enum.KeyCode.Q then
		if S.CamTarget and S.CamTarget.Character then clearHL(S.CamTarget.Character) end
		S.CamLock, S.CamTarget = false, nil
		notify("Lock", "Off", 2)
	end
end)

-- ESP
local espFolder = Instance.new("Folder")
espFolder.Name = "KishaESP"
pcall(function() espFolder.Parent = game:GetService("CoreGui") end)
if not espFolder.Parent then espFolder.Parent = LocalPlayer:WaitForChild("PlayerGui") end

task.spawn(function()
	while true do
		task.wait(0.4)
		espFolder:ClearAllChildren()
		if not S.ESP then continue end
		local me = myHRP()
		for _, plr in ipairs(Players:GetPlayers()) do
			if plr ~= LocalPlayer and plr.Character then
				local hrp = plr.Character:FindFirstChild("HumanoidRootPart")
				local hum = plr.Character:FindFirstChildOfClass("Humanoid")
				if hrp and hum and hum.Health > 0 then
					local bb = Instance.new("BillboardGui")
					bb.Adornee = hrp
					bb.Size = UDim2.fromOffset(140, 28)
					bb.AlwaysOnTop = true
					bb.Parent = espFolder
					local tl = Instance.new("TextLabel")
					tl.BackgroundTransparency = 1
					tl.Size = UDim2.fromScale(1, 1)
					tl.Font = Enum.Font.GothamBold
					tl.TextSize = 13
					tl.TextColor3 = Color3.fromRGB(255, 90, 90)
					tl.TextStrokeTransparency = 0.5
					local d = me and math.floor((hrp.Position - me.Position).Magnitude) or 0
					tl.Text = string.format("%s  %dm", plr.Name, d)
					tl.Parent = bb
					setHL(plr.Character, Color3.fromRGB(255, 70, 70), Color3.fromRGB(255, 140, 140), 0.8)
				end
			end
		end
	end
end)

LocalPlayer.CharacterAdded:Connect(function()
	task.wait(0.5)
	if not S.Fly then
		local h = myHum()
		if h then h.PlatformStand = false end
	end
end)

-- ===================== UI =====================
local Combat = Window:CreateTab({ Name = "Combat" })
local Visual = Window:CreateTab({ Name = "Visual" })
local Move = Window:CreateTab({ Name = "Movement" })
local Misc = Window:CreateTab({ Name = "Misc" })

local a = Combat:CreateSection({ Name = "Kill Aura / Reach" })
a:AddToggle({
	Name = "Kill Aura",
	Default = false,
	Flag = "KA",
	Callback = function(v)
		S.KillAura = v
		if v then
			Mods.refresh()
			notify("Aura", "Bridge: " .. Mods.status, 3)
		end
	end,
})
a:AddSlider({
	Name = "Aura Range",
	Min = 3, Max = 50, Default = 18, Increment = 0.5, Flag = "AR",
	Callback = function(v) S.AuraRange = v end,
})
a:AddSlider({
	Name = "Aura Delay",
	Min = 0.05, Max = 0.4, Default = 0.1, Increment = 0.01, Flag = "AD",
	Callback = function(v) S.AuraDelay = v end,
})
a:AddToggle({
	Name = "Reach",
	Default = false,
	Flag = "Reach",
	Callback = function(v)
		S.Reach = v
		if not applyReach(v) and v then
			S.Reach = false
		else
			notify("Reach", v and ("set to " .. S.ReachValue) or "default", 2)
		end
	end,
})
a:AddSlider({
	Name = "Reach Value",
	Min = 3, Max = 25, Default = 10, Increment = 0.5, Flag = "RV",
	Callback = function(v)
		S.ReachValue = v
		if S.Reach then applyReach(true) end
	end,
})

local aim = Combat:CreateSection({ Name = "Aim" })
aim:AddToggle({
	Name = "Silent Aim (camera pull)",
	Default = false,
	Flag = "SA",
	Callback = function(v) S.SilentAim = v end,
})
aim:AddSlider({
	Name = "Aim FOV (px)",
	Min = 40, Max = 400, Default = 180, Increment = 10, Flag = "AFOV",
	Callback = function(v) S.AimFov = v end,
})
aim:AddSlider({
	Name = "Aim Smooth",
	Min = 0.05, Max = 1, Default = 0.35, Increment = 0.05, Flag = "ASM",
	Callback = function(v) S.AimSmooth = v end,
})
aim:AddToggle({
	Name = "Cam Lock master",
	Default = false,
	Flag = "CL",
	Callback = function(v)
		S.CamLock = v
		if not v then
			if S.CamTarget and S.CamTarget.Character then clearHL(S.CamTarget.Character) end
			S.CamTarget = nil
		end
	end,
})
aim:AddSlider({
	Name = "Lock Smooth",
	Min = 0.05, Max = 1, Default = 0.28, Increment = 0.05, Flag = "CS",
	Callback = function(v) S.CamSmooth = v end,
})

local kit = Combat:CreateSection({ Name = "Kit" })
kit:AddToggle({ Name = "Auto Ability", Default = false, Flag = "AA",
	Callback = function(v) S.AutoAbility = v end })
kit:AddToggle({ Name = "Auto Dash", Default = false, Flag = "ADash",
	Callback = function(v) S.AutoDash = v end })
kit:AddToggle({ Name = "Auto Stomp", Default = false, Flag = "AStomp",
	Callback = function(v) S.AutoStomp = v end })
kit:AddToggle({ Name = "Jetpack Spam", Default = false, Flag = "JP",
	Callback = function(v)
		S.Jetpack = v
		if not v then netFire("client_request_jetpack_thrust", false) end
	end })
kit:AddButton({ Name = "Angel Air Jump", Callback = function() netFire("client_request_angel_air_jump") end })
kit:AddButton({ Name = "Holy Ray Start", Callback = function() netFire("client_request_holy_ray_start") end })

local vis = Visual:CreateSection({ Name = "Visuals" })
vis:AddToggle({ Name = "ESP", Default = false, Flag = "ESP",
	Callback = function(v) S.ESP = v if not v then espFolder:ClearAllChildren() end end })
vis:AddToggle({ Name = "Fullbright", Default = false, Flag = "FB",
	Callback = function(v)
		if v then
			Lighting.Brightness = 2.5
			Lighting.ClockTime = 14
			Lighting.FogEnd = 1e6
			Lighting.GlobalShadows = false
			Lighting.OutdoorAmbient = Color3.new(1, 1, 1)
		else
			Lighting.Brightness = 1
			Lighting.GlobalShadows = true
			Lighting.FogEnd = 1000
		end
	end })
vis:AddToggle({ Name = "Custom FOV", Default = false, Flag = "FOV",
	Callback = function(v)
		S.FOV = v
		if not v and workspace.CurrentCamera then workspace.CurrentCamera.FieldOfView = 70 end
	end })
vis:AddSlider({ Name = "FOV", Min = 50, Max = 120, Default = 100, Increment = 1, Flag = "FOVV",
	Callback = function(v) S.FOVVal = v end })

local mov = Move:CreateSection({ Name = "Movement" })
mov:AddToggle({ Name = "Speed", Default = false, Flag = "Spd",
	Callback = function(v)
		S.Speed = v
		if not v and myHum() then myHum().WalkSpeed = 16 end
	end })
mov:AddSlider({ Name = "Speed Value", Min = 16, Max = 50, Default = 22, Increment = 1, Flag = "SpdV",
	Callback = function(v) S.SpeedVal = v end })
mov:AddToggle({ Name = "Fly", Default = false, Flag = "Fly",
	Callback = function(v)
		S.Fly = v
		if not v and myHum() then myHum().PlatformStand = false end
	end })
mov:AddSlider({ Name = "Fly Speed", Min = 20, Max = 150, Default = 55, Increment = 5, Flag = "FlyS",
	Callback = function(v) S.FlySpeed = v end })
mov:AddToggle({ Name = "Noclip", Default = false, Flag = "NC",
	Callback = function(v) S.Noclip = v end })
mov:AddToggle({ Name = "Infinite Jump", Default = false, Flag = "IJ",
	Callback = function(v) S.InfJump = v end })
mov:AddButton({ Name = "Lobby Fly ON", Callback = function() netFire("client_request_lobby_fly", "on") end })
mov:AddButton({ Name = "Lobby Fly OFF", Callback = function() netFire("client_request_lobby_fly", "off") end })

local misc = Misc:CreateSection({ Name = "Bridge / Debug" })
misc:AddButton({
	Name = "Retry Module Bridge",
	Callback = function()
		local ok = Mods.refresh()
		notify("Bridge", Mods.status .. (ok and " (Net OK)" or " (Net MISSING)"), 4)
		print("[Kisha] Bridge:", Mods.status)
		print("[Kisha] setReach?", Mods.Combat and type(Mods.Combat.setReach))
		print("[Kisha] entityList count", #entityList())
		local plr = nearestPlayerStuds(50)
		if plr and Mods.Entity and Mods.Entity.getPlayerEntityId then
			local o, id = pcall(Mods.Entity.getPlayerEntityId, plr) -- no self
			print("[Kisha] nearest", plr.Name, "entityId", o and id)
		end
	end,
})
misc:AddButton({
	Name = "Dump Entities (F9)",
	Callback = function()
		Mods.refresh()
		dumpEntities(20)
		notify("Dump", "entityList=" .. #entityList() .. " — see F9", 3)
	end,
})
misc:AddButton({
	Name = "Test Attack Nearest",
	Callback = function()
		Mods.refresh()
		local listCount = #entityList()
		print("[Kisha Test] modules:", Mods.status, "entityList:", listCount)
		dumpEntities(10)

		-- Prefer ANY living non-self entity, ignore Players:GetPlayers (characters often nil in this game)
		local list = entitiesInRange(50) -- wide range for test
		local ent = list[1] and list[1].ent
		local dist = list[1] and list[1].dist
		if not ent then
			-- last resort: first entity in list that isn't self, no range check
			for _, e in ipairs(entityList()) do
				if e and e.id and e.player ~= LocalPlayer and not (type(e.health) == "number" and e.health <= 0) then
					ent = e
					dist = -1
					break
				end
			end
		end
		if not ent then
			notify("Test", "entityList has " .. listCount .. " but none attackable — F9 dump", 5)
			return
		end
		local eye = select(1, getMyBlockPos())
		local ok, err = attackEntity(ent, eye)
		local pname = ent.player and ent.player.Name or "?"
		notify("Test Attack", ok and string.format("Fired id=%s %s d=%.1f", tostring(ent.id), pname, dist or -1) or ("FAIL " .. tostring(err)), 5)
		print("[Kisha Test] fire ok=", ok, "err=", err, "id=", ent.id, "player=", pname, "dist=", dist)
	end,
})
misc:AddButton({
	Name = "Print Status (F9)",
	Callback = function()
		Mods.refresh()
		print("==== Kisha Status ====")
		print("Modules:", Mods.status)
		print("Entities:", #entityList())
		print("Reach get:", Mods.Combat and Mods.Combat.getReach and Mods.Combat.getReach()) -- no self
		print("KillAura", S.KillAura, "Reach", S.Reach, "SilentAim", S.SilentAim)
	end,
})
misc:AddButton({
	Name = "Unload",
	Callback = function()
		S.KillAura, S.Fly, S.Noclip, S.ESP, S.CamLock = false, false, false, false, false
		espFolder:ClearAllChildren()
		pcall(function() Window:Destroy() end)
	end,
})

notify("Kisha Hub", "R nearest lock | E crosshair lock | Q unlock | use Retry Bridge in-match", 5)
print("[Kisha Hub] loaded — call Retry Module Bridge after you are in a round")
