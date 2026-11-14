--[[
	Kisha Hub — Violence District
	UI: Kisha library (GitHub)
	Feature logic: ported from MeowX VD client (game remotes / systems unchanged)
]]

if not game:IsLoaded() then
	game.Loaded:Wait()
end

-- Load Kisha UI
local KISHA_URL = "https://raw.githubusercontent.com/mialmos/Kisha-ui/refs/heads/main/Kisha.lua"
local Kisha
do
	local ok, src = pcall(function()
		return game:HttpGet(KISHA_URL)
	end)
	if not ok or type(src) ~= "string" or #src < 100 then
		error("[Kisha Hub] Failed to download Kisha UI library", 0)
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

-- ============================================================
-- Adapter: MeowX-style Section API on top of Kisha
-- So the original feature wiring (AddToggle(title, default, cb)) still works.
-- ============================================================
local function MEOW_BUILD()
	local NOOP = function() end
	local API = { State = {}, Unloaded = false }
	local cleanup = {}
	function API.Track(dispose)
		table.insert(cleanup, dispose)
		return dispose
	end
	function API.Unload()
		if API.Unloaded then return end
		API.Unloaded = true
		for i = #cleanup, 1, -1 do
			pcall(cleanup[i])
		end
	end

	local Window = Kisha:CreateWindow({
		Title = "Kisha Hub",
		Subtitle = "Violence District",
		-- Accent left to Kisha default (pastel pink liquid glass)
		ToggleKey = Enum.KeyCode.RightControl,
		Size = UDim2.fromOffset(580, 440),
		Keybinds = true, -- every toggle/button gets keybind pill
	})

	API.Track(function()
		pcall(function() Window:Destroy() end)
	end)

	local Handle = {}
	Handle.__index = function(self, key)
		local v = rawget(Handle, key)
		if v ~= nil then return v end
		if type(key) == "string" and key:match("^%u") then return NOOP end
		return nil
	end
	function Handle.SetValue(self, a, b)
		local v = (a == self) and b or a
		self.Value = v
		if self._set then pcall(self._set, v) end
	end
	Handle.Set = Handle.SetValue
	function Handle.GetValue(self) return self.Value end
	Handle.Get = Handle.GetValue
	function Handle.Destroy(self)
		if self._destroy then pcall(self._destroy) end
	end
	function Handle.SetVisible() end
	function Handle.Refresh(self, list)
		if self._refresh and type(list) == "table" then pcall(self._refresh, list) end
	end
	Handle.SetValues = Handle.Refresh
	Handle.SetOptions = Handle.Refresh
	function Handle.AddKeyPicker() return setmetatable({}, Handle) end

	local Section = {}
	Section.__index = function(self, key)
		local v = rawget(Section, key)
		if v ~= nil then return v end
		if type(key) == "string" and key:match("^%u") then return NOOP end
		return nil
	end

	local function safe(cb, ...)
		if type(cb) ~= "function" then return end
		local ok, err = pcall(cb, ...)
		if not ok then warn("[Kisha] " .. tostring(err)) end
	end

	function Section:AddToggle(title, default, cb, o)
		o = o or {}
		local h = setmetatable({ Value = default == true, Title = title }, Handle)
		local keybinds = o.Keybinds
		if keybinds == nil then keybinds = true end
		local el = self.ksec:AddToggle({
			Name = title,
			Default = default == true,
			Flag = o.Flag,
			Keybinds = keybinds,
			KeybindNotify = o.KeybindNotify,
			Callback = function(v)
				h.Value = v
				safe(cb, v)
			end,
		})
		h._set = function(v) if el and el.Set then el:Set(v) end end
		h._destroy = function() if el and el.Destroy then el:Destroy() end end
		h.Element = el
		return h
	end
	Section.AddCheckbox = Section.AddToggle

	function Section:AddSlider(title, min, max, default, cb, o)
		o = o or {}
		local h = setmetatable({ Value = default }, Handle)
		local el = self.ksec:AddSlider({
			Name = title,
			Min = min, Max = max, Default = default,
			Increment = o.Increment or 1,
			Flag = o.Flag,
			Callback = function(v)
				h.Value = v
				safe(cb, v)
			end,
		})
		h._set = function(v) if el and el.Set then el:Set(v) end end
		h.Element = el
		return h
	end

	function Section:AddButton(title, cb)
		local h = setmetatable({}, Handle)
		local el = self.ksec:AddButton({
			Name = title,
			Keybinds = true,
			Callback = function() safe(cb) end,
		})
		h.Element = el
		return h
	end

	function Section:AddDropdown(title, options, multi, cb, o)
		o = o or {}
		options = options or {}
		local start = o.Default
		if start == nil then start = (not multi) and options[1] or nil end
		local h = setmetatable({ Value = start }, Handle)
		local el = self.ksec:AddDropdown({
			Name = title,
			Options = options,
			Default = start,
			Flag = o.Flag,
			Callback = function(v)
				h.Value = v
				safe(cb, v)
			end,
		})
		h._refresh = function(list)
			if el and el.Refresh then el:Refresh(list, true) end
		end
		h._set = function(v) if el and el.Set then el:Set(v) end end
		h.Element = el
		return h
	end

	function Section:AddTextbox(title, placeholder, cb, o)
		o = o or {}
		local h = setmetatable({ Value = "" }, Handle)
		local el = self.ksec:AddTextbox({
			Name = title,
			Placeholder = placeholder or "",
			Default = "",
			Flag = o.Flag,
			Callback = function(text)
				h.Value = text
				safe(cb, text)
			end,
		})
		h.Element = el
		return h
	end

	function Section:AddKeybind()
		return setmetatable({}, Handle)
	end

	function Section:AddColorPicker(color, o)
		o = o or {}
		-- Kisha may not have color picker; store value only
		local h = setmetatable({ Value = color }, Handle)
		return h
	end

	function Section:AddConfigManager()
		pcall(function()
			self.ksec:AddButton({
				Name = "Save Config",
				Callback = function()
					Kisha:SaveConfig("default")
					Kisha:Notify({ Title = "Config", Content = "Saved", Duration = 2 })
				end,
			})
			self.ksec:AddButton({
				Name = "Load Config",
				Callback = function()
					Kisha:LoadConfig("default")
					Kisha:Notify({ Title = "Config", Content = "Loaded", Duration = 2 })
				end,
			})
		end)
	end

	local Page = {}
	Page.__index = Page
	function Page:CreateSection(name, icon)
		local ksec = self.tab.kTab:CreateSection({ Name = name })
		return setmetatable({ name = name, icon = icon, tab = self.tab, ksec = ksec }, Section)
	end

	local Tab = {}
	Tab.__index = Tab
	function Tab:CreatePage()
		return setmetatable({ tab = self }, Page)
	end

	local Lib = { Scheme = {} }
	function Lib:Notify(opts)
		if type(opts) == "table" then
			Kisha:Notify({
				Title = opts.Title or "Kisha",
				Content = opts.Description or opts.Content or "",
				Duration = opts.Duration or opts.Time or 3,
			})
		end
	end
	Lib.SetWatermark = NOOP
	function Lib:CreateWindow()
		local win = {}
		function win:CreateTab(name)
			-- Skip pure settings chrome that MeowX hid
			local kTab = Window:CreateTab({ Name = name })
			return setmetatable({ kTab = kTab, nextSide = "Left" }, Tab)
		end
		function win:SetMenuKey(key)
			pcall(function() Window:SetToggleKey(key) end)
		end
		function win:SetTransparency() end
		function win:SetLocked() end
		return setmetatable(win, {
			__index = function(_, key)
				if type(key) == "string" and key:match("^%u") then return NOOP end
				return nil
			end,
		})
	end
	function Lib.Autoload()
		pcall(function() Kisha:LoadConfig("default") end)
	end
	Lib.Window = Window
	Lib.API = API
	Lib.Ui = Kisha
	return Lib
end

local lib = MEOW_BUILD()

local v, Players, localPlayer, RunService, UserInputService, VirtualInputManager, ReplicatedStorage, CoreGui, playerGui, currentCamera, CollectionService, HttpService, tbl, tbl2, tbl3, flag, tbl4, fn, fn2, fn3
local fn4, fn5, fn6, fn7, fn8

do
    -- Scheme table kept for legacy calls; Kisha owns real theme colors
    lib.Scheme.AccentColor = nil
    lib.Scheme.BackgroundColor = nil
    lib.Scheme.MainColor = nil
    lib.Scheme.OutlineColor = nil
    lib.Scheme.FontColor = nil
    lib.Scheme.SubTextColor = nil
    lib.Scheme.HoverColor = nil

    v = lib:CreateWindow({
        Title = "Kisha Hub",
        Subtitle = "Violence District",
        SubtitleColor = Color3.fromRGB(190, 140, 255),
        Logo = "rbxassetid://73763240772265",
        LogoSize = 32,
        SphereText = false,
        SphereWords = "ZX",
        SphereImage = "rbxassetid://73763240772265",
        SphereIconSize = 38,
        Watermark = true,
        WatermarkText = "Kisha",
        WatermarkIcon = "rbxassetid://73763240772265",
    })

    Players = game:GetService("Players")
    localPlayer = Players.LocalPlayer
    RunService = game:GetService("RunService")
    UserInputService = game:GetService("UserInputService")
    VirtualInputManager = game:GetService("VirtualInputManager")
    local GuiService = game:GetService("GuiService")
    ReplicatedStorage = game:GetService("ReplicatedStorage")
    CoreGui = game:GetService("CoreGui")
    playerGui = localPlayer:WaitForChild("PlayerGui")
    currentCamera = workspace.CurrentCamera
    CollectionService = game:GetService("CollectionService")
    HttpService = game:GetService("HttpService")
    game:GetService("TeleportService")
    local TweenService = game:GetService("TweenService")
    _G.Ox = {}
    _G.Ox.AntiBlindEnabled = false
    _G.Ox.GotBlindedRemote = nil
    _G.Ox.NoSlowdownEnabled = false
    _G.Ox.InfiniteLungeEnabled = false

    _G.Ox.Net = (function()
        local N = {ids = {}, active = {}}
        local function remote(...)
            local r = ReplicatedStorage:FindFirstChild("Remotes")
            for _, name in ipairs({...}) do
                r = r and r:FindFirstChild(name)
            end
            return r
        end
        local function guid()
            return HttpService:GenerateGUID(false)
        end
        local function character()
            return localPlayer.Character
        end
        local function store(kind, point)
            N.ids[kind] = N.ids[kind] or setmetatable({}, {__mode = "k"})
            return N.ids[kind]
        end
        local function fire(r, ...)
            if not r then
                return false
            end
            local args = table.pack(...)
            return pcall(function()
                r:FireServer(table.unpack(args, 1, args.n))
            end)
        end

        function N.repair(point, on)
            if not point then
                return false
            end
            local ids = store("repair", point)
            if on then
                if not ids[point] or not N.active[point] then
                    ids[point] = guid()
                end
                N.active[point] = true
            else
                ids[point] = ids[point] or guid()
                N.active[point] = nil
            end
            return fire(remote("Generator", "RepairEvent"), point, on == true, nil, ids[point], character())
        end

        function N.heal(target, on)
            if not target then
                return false
            end
            local ids = store("heal", target)
            if on then
                if not ids[target] or not N.active[target] then
                    ids[target] = guid()
                end
                N.active[target] = true
            else
                ids[target] = ids[target] or guid()
                N.active[target] = nil
            end
            return fire(remote("Healing", "HealEvent"), target, on == true, ids[target], character())
        end

        function N.drop(point)
            local char = character()
            local hrp = char and char:FindFirstChild("HumanoidRootPart")
            local hum = char and char:FindFirstChildOfClass("Humanoid")
            if not point or not hrp then
                return false
            end
            return fire(remote("Pallet", "PalletDropEvent"), point, hrp.Position, hum and hum.MoveDirection or Vector3.zero, guid(), char)
        end

        function N.vault(point, sprint, tier)
            if not point then
                return false
            end
            local id = guid()
            store("vault", point)[point] = id
            return fire(remote("Window", "VaultEvent"), point, sprint == true, id, character(), tier or "fast")
        end
        function N.vaultDone(point)
            if not point then
                return false
            end
            local ids = store("vault", point)
            return fire(remote("Window", "VaultCompleteEvent"), point, false, ids[point] or guid(), character())
        end

        function N.slide(point, sprint)
            if not point then
                return false
            end
            local id = guid()
            store("slide", point)[point] = id
            return fire(remote("Pallet", "PalletSlideEvent"), point, sprint == true, id, character())
        end
        function N.slideDone(point)
            if not point then
                return false
            end
            local ids = store("slide", point)
            return fire(remote("Pallet", "PalletSlideCompleteEvent"), point, ids[point] or guid(), character())
        end

        function N.unhook(point)
            if not point then
                return false
            end
            return fire(remote("Carry", "UnHookEvent"), point, character())
        end

        return N
    end)()

    local tbl5 = {
        ["122812055447896"] = "Veil lunge",
        ["133963973694098"] = "Mayers Basic",
        ["117042998468241"] = "Mayers lunge",
        ["135002183282873"] = "cure lunge",
        ["121216847022485"] = "cure Basic",
        ["132817836308238"] = "Jeff Basic",
        ["129784271201071"] = "Jeff lunge",
        ["82666958311998"] = "Jeff Frenzy",
        ["78432063483146"] = "Abyssal Basic",
        ["118907603246885"] = "Abyssal lunge",
        ["139369275981139"] = "Jason Basic",
        ["110355011987939"] = "Jason lunge",
        ["111920872708571"] = "Masked Basic",
        ["105374834496520"] = "Masked lunge",
        ["138720291317243"] = "Masked Tony",
        ["106871536134254"] = "Masked Alex",
        ["130593238885843"] = "Masked Cobra",
        ["115244153053858"] = "Masked Cobra lunge",
        ["74968262036854"] = "Hidden Basic",
        ["113255068724446"] = "Hidden lunge",
        ["98163597193511"] = "Hidden S1",
        ["80411309607666"] = "Abyssal S1",
        -- ids from the newest dump (all killers)
        ["101636125032002"] = "Abyssal Basic",
        ["77081789642514"] = "Abyssal Basic 2",
        ["125430111937587"] = "Abyssal lunge",
        ["83333467665074"] = "Butcher Basic",
        ["127417297154354"] = "Butcher lunge",
        ["75618342544502"] = "Jason Basic",
        ["79310600168078"] = "Jason Frenzy",
        ["93902163029544"] = "Jason lunge",
        ["104540716539347"] = "Jason Frenzy lunge",
        ["117070354890871"] = "Masked Alex lunge",
        ["113691709436161"] = "Slasher Basic",
        ["129626174716003"] = "Slasher lunge",
        ["81963230963908"] = "Veil Basic",
        ["84926129581106"] = "Veil lunge",
        ["100014992013740"] = "Abyssal S1",
    }
    -- animations that are dodged by crouching instead of parried (Abysswalker's slash dash)
    local CROUCH_DODGE = {["80411309607666"] = true, ["100014992013740"] = true}

    _G.Ox.ParryConfig = {
        AutoParry = false,
        ParrySafety = false,
        ParryAggressive = false,
        ParryCircle = true,
        ParryRadius = 15,
        ParryFace = 0.35,
        AutoCrouch = false,
        Ignored_Skills = {},
    }

    _G.Ox.AttachedParry = {}

    if not _G.Ox.State then
        _G.Ox.State = {}
    end

    _G.Ox.State.ParryCooldown = false
    _G.Ox.State.ParryCooldownTime = 60
    _G.Ox.State.AutoParryAdornment = nil
    _G.Ox.State.ParryCooldownThread = nil
    _G.Ox.AutoParryCustom = {Gui = nil, IsActive = false, GuiVisible = false}
    local ox = _G.Ox
    local parryHUD = _G.Ox.ParryHUD
    local v3 = parryHUD

    if not parryHUD then
        local tbl6 = {}
        v3 = tbl6
        tbl6.gradients = {}
        tbl6.icon = nil
        tbl6.rescanConn = nil
        tbl6.cachedIconColor = nil
    end

    ox.ParryHUD = v3
    ParryHUD = _G.Ox.ParryHUD

    IsDowned = function(arg)
        if not arg then
            return false
        end
        local flag2 = arg:GetAttribute("Knocked") == true or arg:GetAttribute("IsHooked") == true
        return flag2
    end

    IsKiller = function(arg)
        local flag2 = arg and arg.Team and arg.Team.Name == "Killer"
        return flag2
    end

    TriggerCrouch = function()
        pcall(function()
            local playerGui2 = localPlayer:FindFirstChild("PlayerGui")

            for match in string.gmatch("Survivor-mob.Controls.crouch.icon", "[^%.]+") do
                if playerGui2 then
                    playerGui2 = playerGui2:FindFirstChild(match)
                end
            end

            if playerGui2 and playerGui2:IsA("GuiObject") and playerGui2.Visible and playerGui2.Parent and playerGui2.Parent:IsA("GuiButton") then
                local parent = playerGui2.Parent

                if UserInputService.TouchEnabled and type(firesignal) == "function" then
                    firesignal(parent.MouseButton1Click)
                    task.wait(1.4)
                    firesignal(parent.MouseButton1Click)
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

    IsSafeToParry = function(arg)
        if not _G.Ox.ParryConfig.ParrySafety then
            return true
        end

        if not arg then
            return false
        end
        local checkInterractable = arg:FindFirstChild("CheckInterractable")

        if checkInterractable then
            if checkInterractable:GetAttribute("isVaulting") == true then
                return false
            end

            if checkInterractable:GetAttribute("isRepairing") == true then
                return false
            end

            if checkInterractable:GetAttribute("isUnhooking") == true then
                return false
            end

            if checkInterractable:GetAttribute("isHealing") == true then
                return false
            end

            if checkInterractable:GetAttribute("isSliding") == true then
                return false
            end
        end

        return true
    end

    tapMobileParryButton = function()
        local playerGui2 = localPlayer:FindFirstChild("PlayerGui")
        if not playerGui2 then
            return
        end
        local survivorMob = playerGui2:FindFirstChild("Survivor-mob")
        local guiMob = survivorMob and survivorMob:FindFirstChild("Controls") and survivorMob.Controls:FindFirstChild("Gui-mob")

        if guiMob and guiMob.Visible then
            if firesignal then
                pcall(function()
                    firesignal(guiMob.MouseButton1Down)
                    task.wait(0.01)
                    firesignal(guiMob.MouseButton1Up)
                end)
            end
        else
            pcall(function()
                if not mouse2click then
                    if mouse2press and mouse2release then
                        mouse2press()
                        task.wait(0.01)
                        mouse2release()
                        return
                    end

                    VirtualInputManager:SendMouseButtonEvent(0, 0, 1, true, game, 0)
                    task.wait(0.01)
                    VirtualInputManager:SendMouseButtonEvent(0, 0, 1, false, game, 0)
                    return
                end

                mouse2click()
            end)
        end
    end

    -- The game's own ParryClient object (found once, reused). Calling its :Parry() does exactly what a real button press does:
    -- remote with the character, animation, facing lock, cooldown bookkeeping.
    local parryClient, parryClientScan = nil, 0
    local function findParryClient()
        local character = localPlayer.Character
        if parryClient and parryClient.character == character and parryClient.parryEvent and parryClient.parryEvent.Parent then
            return parryClient
        end
        parryClient = nil
        if type(getgc) ~= "function" or os.clock() - parryClientScan < 2.5 then
            return nil
        end
        parryClientScan = os.clock()
        for _, obj in ipairs(getgc(true)) do
            if type(obj) == "table" and rawget(obj, "parryEvent") ~= nil and rawget(obj, "isParryOnCooldown") ~= nil
                and rawget(obj, "player") == localPlayer and rawget(obj, "character") == character then
                parryClient = obj
                return obj
            end
        end
        return nil
    end

    -- same gates as ParryClient.CanUse, for the case where the client object cannot be found
    local function parryAllowed(character)
        if not character or localPlayer:GetAttribute("IsDead") then
            return false
        end
        local humanoid = character:FindFirstChildOfClass("Humanoid")
        if not humanoid or humanoid.Health < humanoid.MaxHealth * 0.5 then
            return false
        end
        if character:GetAttribute("Trapped") or character:GetAttribute("IsCarried") or character:GetAttribute("IsHooked") then
            return false
        end
        if CollectionService:HasTag(character, "Silenced") then
            return false
        end
        local root = character:FindFirstChild("HumanoidRootPart")
        if root and CollectionService:HasTag(root, "doing action") then
            return false
        end
        local busy = character:FindFirstChild("CheckInterractable")
        if busy then
            for _, name in ipairs({"isVaulting", "isSliding", "isDroppingPallet", "isRepairing", "isHealing", "isUnhooking", "isExiting"}) do
                if busy:GetAttribute(name) then
                    return false
                end
            end
        end
        local tool = character:FindFirstChild("Parrying Dagger")
        return tool ~= nil
    end

    -- killers name their animations after the move ("attack", "lungehold", "attackfr", ...), so a new skin/id still counts
    local function attackByName(name)
        name = string.lower(tostring(name or ""))
        if string.find(name, "vm", -2, true) then
            return nil
        end
        if string.find(name, "^attack") and not string.find(name, "done", 1, true) then
            return name
        end
        for _, word in ipairs({"swing", "slash", "stab", "strike", "chop", "lunge"}) do
            if string.find(name, word, 1, true) and not string.find(name, "idle", 1, true) and not string.find(name, "wall", 1, true)
                and not string.find(name, "stun", 1, true) then
                return name
            end
        end
        if string.find(name, "lungehold", 1, true) then
            return name
        end
        return nil
    end

    -- parry straight at the killer: turn the body only (rotation, never position).
    -- The game's own ParryClient turns the body to the CAMERA direction right after it fires (0.2s tween + a short lock),
    -- which overwrote a one-off turn. So that method is wrapped: while a parry target is set it faces the killer instead.
    local faceToken = 0
    local function faceKiller(root)
        if not root then
            return
        end
        _G.Ox.State.ParryFaceTarget = root
        _G.Ox.State.ParryFaceAt = os.clock()
        faceToken += 1
        local token = faceToken
        local function apply()
            local char = localPlayer.Character
            local hrp = char and char:FindFirstChild("HumanoidRootPart")
            if hrp and root.Parent then
                local goal = Vector3.new(root.Position.X, hrp.Position.Y, root.Position.Z)
                if (goal - hrp.Position).Magnitude > 0.3 then
                    hrp.CFrame = CFrame.lookAt(hrp.Position, goal)
                end
            end
        end
        apply()
        task.spawn(function()
            local t0 = os.clock()
            while token == faceToken and os.clock() - t0 < 0.8 do
                RunService.Heartbeat:Wait()
                apply()
            end
        end)
    end

    local function patchParryClient(client)
        if client._meowxFace then
            return
        end
        client._meowxFace = true
        local original = client._faceLookDirection
        client._faceLookDirection = function(self, ...)
            local root = _G.Ox.State.ParryFaceTarget
            if root and root.Parent and os.clock() - (_G.Ox.State.ParryFaceAt or 0) < 1 and self.rootPart and self.rootPart.Parent then
                self.faceToken = (self.faceToken or 0) + 1
                local token, started, lock = self.faceToken, tick(), self.lockDuration or 0.6
                local conn
                conn = RunService.Heartbeat:Connect(function()
                    if self.faceToken ~= token or tick() - started > lock or not (self.rootPart and self.rootPart.Parent and root.Parent) then
                        conn:Disconnect()
                        return
                    end
                    local p = self.rootPart.Position
                    local g = Vector3.new(root.Position.X, p.Y, root.Position.Z)
                    if (g - p).Magnitude > 0.3 then
                        self.rootPart.CFrame = CFrame.lookAt(p, g)
                    end
                end)
                return
            end
            return original(self, ...)
        end
    end

    ExecuteParry = function(killerRoot)
        if _G.Ox.State.ParryCooldown then
            return
        end
        -- rate limit: one parry per 0.15s so the server never sees a burst
        local now = os.clock()
        if _G.Ox.State.LastParryFire and now - _G.Ox.State.LastParryFire < 0.15 then
            return
        end

        pcall(faceKiller, killerRoot)
        local client = findParryClient()
        if client then
            pcall(patchParryClient, client)
            if not client:CanUse() then
                return
            end
            _G.Ox.State.LastParryFire = now
            task.spawn(client.Parry, client)
            return
        end

        local character = localPlayer.Character
        local remotes = ReplicatedStorage:FindFirstChild("Remotes")
        local items = remotes and remotes:FindFirstChild("Items")
        local parryingDagger = items and items:FindFirstChild("Parrying Dagger")
        local parry = parryingDagger and parryingDagger:FindFirstChild("parry")
        if parry and parryAllowed(character) then
            _G.Ox.State.LastParryFire = now
            -- the real client sends the character as the only argument
            pcall(function()
                parry:FireServer(character)
            end)
        elseif not parry then
            _G.Ox.State.LastParryFire = now
            task.spawn(tapMobileParryButton)
        end
    end

    ParryHUD.Scan = function()
        local playerGui2 = localPlayer:FindFirstChild("PlayerGui")
        if not playerGui2 then
            return false
        end
        table.clear(ParryHUD.gradients)
        ParryHUD.icon = nil

        for i, v4 in ipairs({"Survivor", "Survivor-con"}) do
            local v5 = playerGui2:FindFirstChild(v4)

            if v5 then
                local gen = v5:FindFirstChild("Gen")
                local itemFrame = gen and gen:FindFirstChild("ItemFrame")

                if itemFrame then
                    local gui = itemFrame:FindFirstChild("Gui")
                    local bar = gui and gui:FindFirstChild("Bar")
                    local uiGradient = bar and bar:FindFirstChild("UIGradient")

                    if uiGradient then
                        table.insert(ParryHUD.gradients, uiGradient)
                    end

                    local icon = itemFrame:FindFirstChild("icon")

                    if icon then
                        ParryHUD.icon = icon
                    end
                end
            end
        end

        local survivorMob = playerGui2:FindFirstChild("Survivor-mob")
        local controls = survivorMob and survivorMob:FindFirstChild("Controls")

        if controls then
            for i, child in ipairs(controls:GetChildren()) do
                if child:IsA("ImageButton") and child.Name == "Gui-mob" then
                    local bar = child:FindFirstChild("Bar")
                    local uiGradient = bar and bar:FindFirstChild("UIGradient")

                    if uiGradient then
                        table.insert(ParryHUD.gradients, uiGradient)
                    end
                end
            end
        end

        local flag2 = #ParryHUD.gradients > 0 or ParryHUD.icon ~= nil
        return flag2
    end

    ParryHUD.SetColor = function(cachedIconColor)
        if #ParryHUD.gradients == 0 and not ParryHUD.icon then
            ParryHUD.Scan()
        end

        ParryHUD.cachedIconColor = cachedIconColor

        for i, gradient in ipairs(ParryHUD.gradients) do
            if gradient and gradient.Parent and gradient.Parent.Parent then
                local icon = gradient.Parent.Parent:FindFirstChild("icon")

                if icon then
                    icon.ImageColor3 = cachedIconColor
                end

                local gui = gradient.Parent.Parent:FindFirstChild("Gui")

                if gui then
                    gui.ImageColor3 = cachedIconColor
                end
            end
        end

        if ParryHUD.icon then
            ParryHUD.icon.ImageColor3 = cachedIconColor
        end
    end

    ParryHUD.Tween = function(arg)
        if #ParryHUD.gradients == 0 then
            ParryHUD.Scan()
        end

        for i, gradient in ipairs(ParryHUD.gradients) do
            if gradient and gradient.Parent then
                gradient.Offset = Vector2.new(0, 0.75)
                local tween = TweenService:Create(gradient, TweenInfo.new(arg, Enum.EasingStyle.Linear), {Offset = Vector2.new(0, 0.25)})
                tween:Play()

                tween.Completed:Connect(function()
                    if not _G.Ox.State.ParryCooldown then
                        ParryHUD.SetColor(Color3.fromRGB(255, 255, 255))
                    end
                end)
            end
        end
    end

    ParryHUD.Reset = function()
        ParryHUD.SetColor(Color3.fromRGB(255, 255, 255))

        for i, gradient in ipairs(ParryHUD.gradients) do
            if gradient and gradient.Parent then
                gradient.Offset = Vector2.new(0, 0.25)
            end
        end
    end

    ParryHUD.SetupWatcher = function()
        if ParryHUD.rescanConn then
            ParryHUD.rescanConn:Disconnect()
        end

        local playerGui2 = localPlayer:FindFirstChild("PlayerGui")
        if not playerGui2 then
            return
        end

        ParryHUD.rescanConn = playerGui2.ChildAdded:Connect(function(child)
            local name = child.Name

            if name == "Survivor" or name == "Survivor-con" or name == "Survivor-mob" then
                task.wait(0.3)
                ParryHUD.Scan()

                if _G.Ox.State.ParryCooldown and ParryHUD.cachedIconColor then
                    ParryHUD.SetColor(ParryHUD.cachedIconColor)
                end
            end
        end)

        task.spawn(function()
            local n = 0

            while n < 10 and not ParryHUD.Scan() do
                task.wait(0.5)
                n = n + 0.5
            end
        end)
    end

    ParryHUD.SetupWatcher()

    localPlayer.CharacterAdded:Connect(function()
        task.wait(1.5)
        ParryHUD.Scan()

        if _G.Ox.State.ParryCooldown and ParryHUD.cachedIconColor then
            ParryHUD.SetColor(ParryHUD.cachedIconColor)
        end
    end)

    ListenToParryResult = function()
        task.spawn(function()
            local remotes = ReplicatedStorage:WaitForChild("Remotes", 5)
            local parryingDagger = remotes and remotes:WaitForChild("Items", 5):WaitForChild("Parrying Dagger", 5)
            local parryResult = parryingDagger and parryingDagger:WaitForChild("parryResult", 5)

            if parryResult then
                parryResult.OnClientEvent:Connect(function(arg, arg2)
                    local num = tonumber(arg2)
                    local n = num or (arg == true and 90 or 60)
                    _G.Ox.State.ParryCooldown = true

                    if _G.Ox.State.ParryCooldownThread then
                        task.cancel(_G.Ox.State.ParryCooldownThread)
                    end

                    ParryHUD.SetColor(Color3.fromRGB(77, 77, 77))
                    ParryHUD.Tween(n)

                    _G.Ox.State.ParryCooldownThread = task.delay(n, function()
                        _G.Ox.State.ParryCooldown = false
                        ParryHUD.SetColor(Color3.fromRGB(255, 255, 255))
                    end)
                end)
            end
        end)
    end

    ListenToParryResult()

    IsInKillerPOV = function(arg, arg2, arg3)
        if not arg or not arg2 then
            return false
        end
        local n = arg2.Position - arg.Position
        local vector = Vector3.new(n.X, 0, n.Z)
        if vector.Magnitude < 0.15 then
            return true
        end
        local vector2 = Vector3.new(arg.CFrame.LookVector.X, 0, arg.CFrame.LookVector.Z)
        if vector2.Magnitude < 0.05 then
            return false
        end
        local v4 = vector2.Unit:Dot(vector.Unit)
        local n2 = arg3 or 0.35
        local flag2 = n2 <= v4
        return flag2
    end

    AttachParrySensor = function(arg)
        if not arg or _G.Ox.AttachedParry[arg] then
            return
        end
        _G.Ox.AttachedParry[arg] = true
        local humanoid = arg:WaitForChild("Humanoid", 5)
        if not humanoid then
            return
        end
        local animator = humanoid:FindFirstChildOfClass("Animator")
        local animator2 = animator or humanoid:WaitForChild("Animator", 5)
        if not animator2 then
            return
        end

        humanoid.ChildAdded:Connect(function(child)
            if child:IsA("Animator") then
                _G.Ox.AttachedParry[arg] = nil
                AttachParrySensor(arg)
            end
        end)

        arg.AncestryChanged:Connect(function(child, parent)
            if not parent then
                _G.Ox.AttachedParry[arg] = nil
            end
        end)

        animator2.AnimationPlayed:Connect(function(arg2)
            local animation = arg2.Animation
            local animationId = animation and arg2.Animation.AnimationId or ""
            local match = animationId:match("%d+")
            local v4 = tbl5[match] or attackByName(arg2.Name)
            if not v4 then
                return
            end

            if CROUCH_DODGE[match] and _G.Ox.ParryConfig.AutoCrouch then
                local character = localPlayer.Character
                if IsDowned(character) then
                    return
                end
                local humanoidRootPart = character and character:FindFirstChild("HumanoidRootPart")
                local humanoidRootPart2 = arg:FindFirstChild("HumanoidRootPart")

                if humanoidRootPart and humanoidRootPart2 and (humanoidRootPart.Position - humanoidRootPart2.Position).Magnitude <= 40 then
                    TriggerCrouch()
                end

                return
            end

            if not _G.Ox.ParryConfig.AutoParry then
                return
            end

            if _G.Ox.State.ParryCooldown then
                return
            end

            if _G.Ox.ParryConfig.Ignored_Skills and _G.Ox.ParryConfig.Ignored_Skills[v4] then
                return
            end
            local character = localPlayer.Character
            if IsDowned(character) or not IsSafeToParry(character) then
                return
            end
            local humanoidRootPart = character and character:FindFirstChild("HumanoidRootPart")
            local humanoidRootPart2 = arg:FindFirstChild("HumanoidRootPart")
            if not humanoidRootPart or not humanoidRootPart2 then
                return
            end
            local magnitude = (humanoidRootPart.Position - humanoidRootPart2.Position).Magnitude
            local parryFace = _G.Ox.ParryConfig.ParryFace

            if parryFace < 0.2 then
                parryFace = 0.35
            end

            if _G.Ox.ParryConfig.ParryAggressive then
                if _G.Ox.ParryConfig.ParryRadius < magnitude then
                    return
                end

                local function fn12()
                    if _G.Ox.State.ParryCooldown or IsDowned(character) then
                        return true
                    end

                    if not humanoidRootPart or not humanoidRootPart2 or not humanoidRootPart.Parent or not humanoidRootPart2.Parent then
                        return true
                    end

                    if (humanoidRootPart.Position - humanoidRootPart2.Position).Magnitude > _G.Ox.ParryConfig.ParryRadius then
                        return false
                    end
                    ExecuteParry(humanoidRootPart2)
                    return true
                end

                if fn12() then
                    return
                end
                local connection = nil
                local now = os.clock()

                connection = RunService.Heartbeat:Connect(function()
                    if (os.clock() - now >= 0.85 or fn12()) and connection then
                        connection:Disconnect()
                    end
                end)
            else
                local n = _G.Ox.ParryConfig.ParryRadius

                if magnitude <= n and true then
                    ExecuteParry(humanoidRootPart2)
                    return
                end
                local now = os.clock()
                local connection = nil

                connection = RunService.Heartbeat:Connect(function()
                    if os.clock() - now < 0.6 and not _G.Ox.State.ParryCooldown and humanoidRootPart and humanoidRootPart2 and humanoidRootPart.Parent and humanoidRootPart2.Parent and not IsDowned(character) then
                        if (humanoidRootPart.Position - humanoidRootPart2.Position).Magnitude <= n and true then
                            ExecuteParry(humanoidRootPart2)

                            if connection then
                                connection:Disconnect()
                            end
                        end

                        return
                    end

                    if connection then
                        connection:Disconnect()
                    end
                end)
            end
        end)
    end

    TryAttachParry = function(arg)
        if arg ~= localPlayer and IsKiller(arg) and arg.Character then
            AttachParrySensor(arg.Character)
        end
    end

    SetupPlayerParry = function(arg)
        if arg == localPlayer then
            return
        end

        arg.CharacterAdded:Connect(function()
            TryAttachParry(arg)
        end)

        arg:GetPropertyChangedSignal("Team"):Connect(function()
            TryAttachParry(arg)
        end)

        if arg.Character then
            TryAttachParry(arg)
        end
    end

    for i, player in ipairs(Players:GetPlayers()) do
        SetupPlayerParry(player)
    end

    Players.PlayerAdded:Connect(SetupPlayerParry)

    UpdateCustomParryGUI = function(arg)
        if not _G.Ox.AutoParryCustom.Gui then
            return
        end
        local frame = _G.Ox.AutoParryCustom.Gui:FindFirstChild("Frame")
        if not frame then
            return
        end
        local actionButton = frame:FindFirstChild("ActionButton")
        local uiStroke = frame:FindFirstChild("UIStroke")

        if arg then
            if actionButton then
                actionButton.Text = "PARRY [ON]"
                actionButton.TextColor3 = Color3.fromRGB(180, 255, 180)
                actionButton.BackgroundColor3 = Color3.fromRGB(40, 40, 45)
            end

            if uiStroke then
                uiStroke.Color = Color3.fromRGB(100, 200, 100)
            end
        else
            if actionButton then
                actionButton.Text = "PARRY [OFF]"
                actionButton.TextColor3 = Color3.fromRGB(200, 200, 200)
                actionButton.BackgroundColor3 = Color3.fromRGB(30, 30, 35)
            end

            if uiStroke then
                uiStroke.Color = Color3.fromRGB(90, 90, 95)
            end
        end
    end

    ToggleParryStatus = function()
        local parryConfig = _G.Ox.ParryConfig
        local autoParry

        if _G.Ox.ParryConfig.AutoParry then
            autoParry = false
        else
            autoParry = true
        end

        parryConfig.AutoParry = autoParry
        _G.Ox.AutoParryCustom.IsActive = _G.Ox.ParryConfig.AutoParry
        UpdateCustomParryGUI(_G.Ox.ParryConfig.AutoParry)
    end

    CreateCustomParryGUI = function()
        if _G.Ox.AutoParryCustom.Gui then
            _G.Ox.AutoParryCustom.Gui:Destroy()
        end

        local screenGui = Instance.new("ScreenGui")
        screenGui.Name = "AutoParryCustomGui"
        screenGui.ResetOnSpawn = false
        screenGui.IgnoreGuiInset = true
        screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
        screenGui.Parent = CoreGui
        screenGui.Enabled = false
        _G.Ox.AutoParryCustom.Gui = screenGui
        _G.Ox.AutoParryCustom.GuiVisible = false
        local frame = Instance.new("Frame", screenGui)
        frame.Name = "Frame"
        frame.Size = UDim2.fromOffset(110, 36)
        frame.Position = UDim2.fromScale(0.85, 0.35)
        frame.BackgroundColor3 = Color3.fromRGB(25, 25, 30)
        frame.BackgroundTransparency = 0.1
        frame.Active = true
        frame.BorderSizePixel = 0
        Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 8)
        local uiStroke = Instance.new("UIStroke", frame)
        uiStroke.Name = "UIStroke"
        uiStroke.Color = Color3.fromRGB(90, 90, 95)
        uiStroke.Thickness = 1.5
        uiStroke.Transparency = 0.2
        local textButton = Instance.new("TextButton", frame)
        textButton.Name = "ActionButton"
        textButton.Size = UDim2.new(1, 0, 1, 0)
        textButton.Text = "PARRY [OFF]"
        textButton.BackgroundColor3 = Color3.fromRGB(30, 30, 35)
        textButton.Font = Enum.Font.GothamBold
        textButton.TextSize = 12
        textButton.TextColor3 = Color3.fromRGB(200, 200, 200)
        textButton.BorderSizePixel = 0
        textButton.AutoButtonColor = false
        Instance.new("UICorner", textButton).CornerRadius = UDim.new(0, 8)
        local flag2 = false
        local flag3 = false
        local flag4 = false
        local position = nil
        local position2 = nil
        local thread = nil

        update = function(arg)
            if not flag2 or not flag4 or not position or not position2 then
                return
            end
            local n2 = arg.Position - position

            if not flag3 and (math.abs(n2.X) > 18 or math.abs(n2.Y) > 18) then
                flag3 = true
            end

            if flag3 then
                frame.Position = UDim2.new(position2.X.Scale, position2.X.Offset + n2.X, position2.Y.Scale, position2.Y.Offset + n2.Y)
            end
        end

        textButton.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                flag2 = true
                flag3 = false
                flag4 = false
                position = input.Position
                position2 = frame.Position

                if thread then
                    task.cancel(thread)
                end

                thread = task.delay(0.18, function()
                    if flag2 then
                        flag4 = true
                    end
                end)
            end
        end)

        textButton.InputEnded:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                if thread then
                    task.cancel(thread)
                end

                if flag2 and not flag3 then
                    ToggleParryStatus()
                end

                flag2 = false
                flag3 = false
                flag4 = false
                position = nil
                position2 = nil
            end
        end)

        UserInputService.InputChanged:Connect(function(input)
            if flag2 and flag4 and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
                update(input)
            end
        end)

        if _G.Ox.AutoParryCustom._statusConn then
            _G.Ox.AutoParryCustom._statusConn:Disconnect()
        end

        _G.Ox.AutoParryCustom._statusConn = RunService.Heartbeat:Connect(function()
            if _G.Ox.AutoParryCustom.Gui and _G.Ox.AutoParryCustom.Gui.Parent then
                if _G.Ox.AutoParryCustom.IsActive ~= _G.Ox.ParryConfig.AutoParry then
                    _G.Ox.AutoParryCustom.IsActive = _G.Ox.ParryConfig.AutoParry
                    UpdateCustomParryGUI(_G.Ox.ParryConfig.AutoParry)
                end

                return
            end

            if _G.Ox.AutoParryCustom._statusConn then
                _G.Ox.AutoParryCustom._statusConn:Disconnect()
            end
        end)
    end

    localPlayer.CharacterAdded:Connect(function()
        task.wait(1)

        if _G.Ox.AutoParryCustom.GuiVisible and _G.Ox.AutoParryCustom.Gui then
            _G.Ox.AutoParryCustom.Gui.Enabled = true
            UpdateCustomParryGUI(_G.Ox.ParryConfig.AutoParry)
        end
    end)

    _G.Ox.KorlessMorph = {Enabled = false, Connection = nil}
    _G.Ox.SelfHeal = {Enabled = false}
    _G.Ox.FlowstateNoCD = {Enabled = false, Connection = nil, CharAddedConn = nil}
    _G.Ox.NoFall = {Enabled = false}
    _G.Ox.NextKiller = {Enabled = false, IndicatorGui = nil}

    _G.Ox.CounterParry = {
        Enabled = false,
        Distance = 15,
        Interval = 0.3,
        AnimId = "rbxassetid://117042998468241",
        Thread = nil,
        Track = nil,
    }

    _G.Ox.Crosshair = {
        Enabled = false,
        Size = 8,
        Thickness = 2,
        Color = Color3.fromRGB(255, 255, 255),
        Style = "Dot",
        OffsetX = 0,
        OffsetY = 0,
    }

    _G.Ox.Spectator = {Enabled = false, Gui = nil, Label = nil}

    _G.Ox.Moonwalk = {
        Enabled = false,
        GuiVisible = false,
        Gui = nil,
        IsActive = false,
    }

    _G.Ox.CrosshairGui = nil
    _G.Ox.CrosshairElements = {}
    _G.Ox.CrosshairCreated = false
    _G.Ox.LastCrosshairStyle = nil
    local ox2 = _G.Ox
    local config = _G.Ox.Config
    local config2 = config or {}
    ox2.Config = config2
    _G.Ox.Config.Surv_PerfectVault = false
    _G.Ox.autoVaultEnabled = false
    _G.Ox.autoPalletSlideEnabled = false
    _G.Ox.lastActionTime = 0
    _G.Ox.COOLDOWN = 1.5
    _G.Ox.StreamerMode = {Enabled = false, SpooferConns = {}}
    _G.Ox.InfinityZoom = {Enabled = false}
    _G.Ox.StretchRes = {Enabled = false, Amount = 0.67, Conn = nil}
    _G.Ox.CameraFOV = {Enabled = false, Value = 90, Connection = nil}
    _G.Ox.Auto = {SkillCheck = false, AntiTrap = false, SkillCheckMode = "Legit", TrapMode = "Perfect"}
    _G.Ox.MapPredict = {Enabled = false}
    _G.Ox.KillerPerks = {Enabled = false, Gui = nil, Minimized = false}

    _G.Ox.Stun = {
        Enabled = false,
        Data = {},
    }

    _G.Ox.GodMode = false
    _G.Ox.ScriptAlive = true
    _G.Ox.UnlimitedVaultEnabled = false
    local ox3 = _G.Ox
    local state = _G.Ox.State
    local state2 = state or {}
    ox3.State = state2
    _G.Ox.State.busy = false
    _G.Ox.State.RandomMode_IsNormal = false
    _G.Ox.Connections = {SkillHeartbeat = nil}
    _G.Ox.Speed = {Enabled = false, Value = 0.1, Connection = nil, Loop = nil}
    _G.Ox.AutoRun = {PC = false, Mobile = false, MobileThread = nil}

    tbl = {
        Generators = {},
        Hooks = {},
        Gates = {},
        Pallets = {},
        Windows = {},
    }

    tbl2 = {Enabled = false, Conn = nil}

    if not _G.Ox.State then
        _G.Ox.State = {}
    end

    _G.Ox.State.ThirdPersonConn = nil

    tbl3 = {
        ["Left Arm"] = true,
        ["Right Arm"] = true,
        LeftHand = true,
        RightHand = true,
        LeftLowerArm = true,
        RightLowerArm = true,
        LeftUpperArm = true,
        RightUpperArm = true,
    }

    _G.Ox.FakePerks = {
        QuickRecoveryEnabled = false,
        PerfectLandingEnabled = false,
        FlowstateEnabled = false,
        FakeAdrenalineRush = false,
        PerkCooldown = 0,
        boostActive = false,
        perfectLandingBoostActive = false,
        fsOnCooldown = false,
        lastQRTime = 0,
        lastPLTime = 0,
        lastFSTime = 0,
        qrConnection = nil,
        plConnection = nil,
        fsConnection = nil,
        fsAnimConnection = nil,
        adrenalineOn = false,
        adrenalineConns = {},
        lastARTime = 0,
    }

    _G.Ox.AutoPallet = {
        Enabled = false,
        Safety = true,
        Distance = 7,
        Cooldown = 2.5,
        LastDrop = 0,
        UsedPallets = {},
        Connection = nil,
    }

    _G.Ox.FullBright = false
    _G.Ox.NoFog = false
    _G.Ox.NoShadow = false
    _G.Ox.TimeOfDayValue = 14

    _G.Ox.LowGFX = {
        Enabled = false,
        Textures = true,
        VisualEffects = true,
        Particles = true,
        Parts = true,
        Sky = false,
        Saved = {},
    }

    _G.Ox.AimConfig = {
        Aim_SilentVeilV2 = false,
        Veil_ShowFOV = true,
        SpearSmart_enable = true,
        Veil_FOV = 150,
        SPEAR_Speed = 180,
        SPEAR_Gravity = 98.1,
        SPEAR_AuraSpeed = 180,
        SPEAR_AuraGravity = 98.1,
        SPEAR_MaxDist = 1e9,
        Veil_LeadMultiplier = 1,
        AIM_TargetPart = "Torso",
        Pistol_BlockKnocked = false,
        LockAim = false,
        Veil_PermaLock = false,
        Veil_Laser = false,
        Veil_Trajectory = false,
        Veil_PermaTarget = nil, -- Model locked while PermaLock on
        Flash_Silent = false,
        Flash_YOffset = 1.5,
    }

    _G.Ox.isKillerAimbotHolding = false
    _G.Ox.lockedKillerAimbotTarget = nil
    _G.Ox.killerAimbotHighlight = nil

    _G.Ox.Config = {
        SpearSmart_enable = true,
        Killer_Aimbot_Enabled = false,
        Killer_Aimbot_MaxDist = 12,
        Killer_Aimbot_BestSmooth = true,
    }

    local flag2 = false
    local flag3 = false
    flag = false

    _G.Ox.ESPConfig = {
        Master = false,
        Player = false,
        Killer = false,
        Outline = false,
        Name = false,
        Distance = false,
        KillerWarn = false,
        ItemIcon = false,
        Generator = false,
        GeneratorName = true,
        Pallet = false,
        Hook = false,
        Gate = false,
        Window = false,
        SCP = false,
        HookCount = false,
        Status = false,
        MaxDistance = 1000,
    }

    _G.Ox.ESPColors = {
        Player = Color3.fromRGB(60, 255, 60),
        Killer = Color3.fromRGB(255, 60, 60),
        Generator = Color3.fromRGB(255, 255, 0),
        GeneratorDone = Color3.fromRGB(0, 255, 0),
        Pallet = Color3.fromRGB(60, 255, 255),
        Hook = Color3.fromRGB(255, 105, 180),
        Gate = Color3.fromRGB(255, 255, 255),
        Window = Color3.fromRGB(60, 255, 255),
        SCP = Color3.fromRGB(255, 0, 255),
        Injured = Color3.fromRGB(255, 140, 0),
        Downed = Color3.fromRGB(255, 40, 40),
        Hooked = Color3.fromRGB(240, 240, 255),
    }

    tbl4 = {
        Generators = {},
        Windows = {},
        Pallets = {},
        Hooks = {},
        Gates = {},
        SCPs = {},
    }

    GetRole = function()
        if not localPlayer.Team then
            return "Unknown"
        end
        local name = localPlayer.Team.Name
        if name == "Killer" then
            return "Killer"
        end

        if name == "Survivors" then
            return "Survivor"
        end
        return "Spectator"
    end

    GetDistance = function(arg)
        local character = localPlayer.Character
        local humanoidRootPart = character and localPlayer.Character:FindFirstChild("HumanoidRootPart")
        if not humanoidRootPart then
            return math.huge
        end
        return (arg - humanoidRootPart.Position).Magnitude
    end

    fn = function(arg, arg2)
        if arg and type(arg.SetValue) == "function" then
            pcall(function()
                arg:SetValue(arg2)
            end)
        end
    end

    ClearCrosshair = function()
        if _G.Ox.CrosshairGui then
            _G.Ox.CrosshairGui:Destroy()
            _G.Ox.CrosshairGui = nil
        end

        _G.Ox.CrosshairElements = {}
        _G.Ox.CrosshairCreated = false
        _G.Ox.LastCrosshairStyle = nil
    end

    DrawCrosshair = function()
        if not _G.Ox.Crosshair.Enabled then
            if _G.Ox.CrosshairGui then
                _G.Ox.CrosshairGui.Enabled = false
            end

            return
        end

        if _G.Ox.CrosshairGui then
            _G.Ox.CrosshairGui.Enabled = true
        end

        if _G.Ox.LastCrosshairStyle ~= _G.Ox.Crosshair.Style or not _G.Ox.CrosshairGui then
            ClearCrosshair()
            _G.Ox.LastCrosshairStyle = _G.Ox.Crosshair.Style
        end

        if not _G.Ox.CrosshairCreated then
            _G.Ox.CrosshairCreated = true
            _G.Ox.CrosshairGui = Instance.new("ScreenGui")
            _G.Ox.CrosshairGui.Name = "CrosshairUI"
            _G.Ox.CrosshairGui.IgnoreGuiInset = true
            _G.Ox.CrosshairGui.ResetOnSpawn = false
            _G.Ox.CrosshairGui.DisplayOrder = 999
            _G.Ox.CrosshairGui.Parent = CoreGui

            local function createFrame(size, position)
                local frame = Instance.new("Frame")
                frame.BackgroundColor3 = _G.Ox.Crosshair.Color
                frame.BorderSizePixel = 0
                frame.AnchorPoint = Vector2.new(0.5, 0.5)
                frame.Size = size
                frame.Position = position
                frame.Parent = _G.Ox.CrosshairGui
                return frame
            end

            local udim2 = UDim2.new(0.5, _G.Ox.Crosshair.OffsetX, 0.5, _G.Ox.Crosshair.OffsetY)

            if _G.Ox.Crosshair.Style == "Plus" then
                _G.Ox.CrosshairElements[1] = createFrame(UDim2.new(0, _G.Ox.Crosshair.Size * 2, 0, _G.Ox.Crosshair.Thickness), udim2)
                _G.Ox.CrosshairElements[2] = createFrame(UDim2.new(0, _G.Ox.Crosshair.Thickness, 0, _G.Ox.Crosshair.Size * 2), udim2)
            elseif _G.Ox.Crosshair.Style == "Dot" then
                local frame = Instance.new("Frame")
                frame.BackgroundColor3 = _G.Ox.Crosshair.Color
                frame.BorderSizePixel = 0
                frame.AnchorPoint = Vector2.new(0.5, 0.5)
                frame.Size = UDim2.new(0, _G.Ox.Crosshair.Size, 0, _G.Ox.Crosshair.Size)
                frame.Position = udim2
                Instance.new("UICorner", frame).CornerRadius = UDim.new(1, 0)
                frame.Parent = _G.Ox.CrosshairGui
                _G.Ox.CrosshairElements[1] = frame
            elseif _G.Ox.Crosshair.Style == "Circle" then
                local frame = Instance.new("Frame")
                frame.BackgroundTransparency = 1
                frame.BorderSizePixel = 0
                frame.AnchorPoint = Vector2.new(0.5, 0.5)
                frame.Size = UDim2.new(0, _G.Ox.Crosshair.Size * 2, 0, _G.Ox.Crosshair.Size * 2)
                frame.Position = udim2
                frame.Parent = _G.Ox.CrosshairGui
                local uiStroke = Instance.new("UIStroke")
                uiStroke.Color = _G.Ox.Crosshair.Color
                uiStroke.Thickness = _G.Ox.Crosshair.Thickness
                uiStroke.Parent = frame
                Instance.new("UICorner", frame).CornerRadius = UDim.new(1, 0)
                _G.Ox.CrosshairElements[1] = frame
            end
        end

        local udim2 = UDim2.new(0.5, _G.Ox.Crosshair.OffsetX, 0.5, _G.Ox.Crosshair.OffsetY)

        if _G.Ox.Crosshair.Style == "Plus" then
            if _G.Ox.CrosshairElements[1] then
                _G.Ox.CrosshairElements[1].Size = UDim2.new(0, _G.Ox.Crosshair.Size * 2, 0, _G.Ox.Crosshair.Thickness)
                _G.Ox.CrosshairElements[1].Position = udim2
                _G.Ox.CrosshairElements[1].BackgroundColor3 = _G.Ox.Crosshair.Color
            end

            if _G.Ox.CrosshairElements[2] then
                _G.Ox.CrosshairElements[2].Size = UDim2.new(0, _G.Ox.Crosshair.Thickness, 0, _G.Ox.Crosshair.Size * 2)
                _G.Ox.CrosshairElements[2].Position = udim2
                _G.Ox.CrosshairElements[2].BackgroundColor3 = _G.Ox.Crosshair.Color
            end
        elseif _G.Ox.Crosshair.Style == "Dot" then
            if _G.Ox.CrosshairElements[1] then
                _G.Ox.CrosshairElements[1].Size = UDim2.new(0, _G.Ox.Crosshair.Size, 0, _G.Ox.Crosshair.Size)
                _G.Ox.CrosshairElements[1].Position = udim2
                _G.Ox.CrosshairElements[1].BackgroundColor3 = _G.Ox.Crosshair.Color
            end
        elseif _G.Ox.Crosshair.Style == "Circle" and _G.Ox.CrosshairElements[1] then
            _G.Ox.CrosshairElements[1].Size = UDim2.new(0, _G.Ox.Crosshair.Size * 2, 0, _G.Ox.Crosshair.Size * 2)
            _G.Ox.CrosshairElements[1].Position = udim2
            local uiStroke = _G.Ox.CrosshairElements[1]:FindFirstChildOfClass("UIStroke")

            if uiStroke then
                uiStroke.Color = _G.Ox.Crosshair.Color
                uiStroke.Thickness = _G.Ox.Crosshair.Thickness
            end
        end
    end

    local function fn12()
        for i, player in ipairs(Players:GetPlayers()) do
            if player ~= localPlayer and (not player.Team or player.Team.Name ~= "Survivors") then
                local character = player.Character
                if not character then
                    continue
                end
                local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
                if humanoidRootPart then
                    return humanoidRootPart
                end
            end
        end

        return nil
    end

    local function fn13(arg)
        if not _G.Ox.AutoPallet.Safety then
            return true
        end

        if not arg then
            return false
        end

        if arg:GetAttribute("Knocked") == true then
            return false
        end

        if arg:GetAttribute("IsCarried") == true then
            return false
        end

        if arg:GetAttribute("IsHooked") == true then
            return false
        end
        local checkInterractable = arg:FindFirstChild("CheckInterractable")

        if checkInterractable then
            if checkInterractable:GetAttribute("isVaulting") == true then
                return false
            end

            if checkInterractable:GetAttribute("isRepairing") == true then
                return false
            end

            if checkInterractable:GetAttribute("isUnhooking") == true then
                return false
            end

            if checkInterractable:GetAttribute("isHealing") == true then
                return false
            end

            if checkInterractable:GetAttribute("isSliding") == true then
                return false
            end

            if checkInterractable:GetAttribute("isCarrying") == true then
                return false
            end
        end

        local humanoid = arg:FindFirstChildOfClass("Humanoid")
        if humanoid and humanoid.Health <= 0 then
            return false
        end
        return true
    end

    local function fn14(arg)
        local v4 = nil
        local distance = _G.Ox.AutoPallet.Distance
        local v5 = ipairs
        local pallets = tbl4.Pallets
        local tbl6 = pallets or {}

        for k, v6 in v5(tbl6) do
            if v6 and v6.Parent and not _G.Ox.AutoPallet.UsedPallets[v6] then
                local primaryPartPallet = v6:FindFirstChild("PrimaryPartPallet")
                local palletPoint = primaryPartPallet or v6:FindFirstChild("PalletPoint") or v6:FindFirstChild("PalletPointSlide") or v6:FindFirstChildWhichIsA("BasePart")

                if palletPoint then
                    local ok, result = pcall(function()
                        return palletPoint.Position
                    end)

                    if ok and result then
                        local magnitude = (arg.Position - result).Magnitude

                        if magnitude < distance then
                            distance = magnitude
                            v4 = v6
                        end
                    end
                end
            end
        end

        return v4
    end

    local function fn15(arg)
        if not arg then
            return false
        end
        local palletPointSlide = arg:FindFirstChild("PalletPointSlide")
        local palletPoint = palletPointSlide or arg:FindFirstChild("PalletPoint") or arg:FindFirstChildWhichIsA("BasePart")
        if not palletPoint then
            return false
        end
        local remotes = ReplicatedStorage:FindFirstChild("Remotes")
        local palletDropEvent = remotes and remotes:FindFirstChild("Pallet") and remotes.Pallet:FindFirstChild("PalletDropEvent")
        if not palletDropEvent then
            return false
        end

        pcall(function()
            _G.Ox.Net.drop(palletPoint)
        end)

        _G.Ox.AutoPallet.UsedPallets[arg] = true
        _G.Ox.AutoPallet.LastDrop = tick()
        return true
    end

    StartAutoPallet = function()
        if _G.Ox.AutoPallet.Connection then
            return
        end

        _G.Ox.AutoPallet.Connection = task.spawn(function()
            while _G.Ox.AutoPallet.Enabled do
                task.wait(0.3)

                if GetRole() == "Survivor" and tick() - _G.Ox.AutoPallet.LastDrop >= _G.Ox.AutoPallet.Cooldown then
                    pcall(function()
                        local character = localPlayer.Character
                        local humanoidRootPart = character and character:FindFirstChild("HumanoidRootPart")
                        local humanoid = character and character:FindFirstChildOfClass("Humanoid")
                        if not humanoidRootPart or not humanoid or humanoid.Health <= 0 then
                            return
                        end

                        if not fn13(character) then
                            return
                        end
                        local v4 = fn12()
                        if not v4 then
                            return
                        end

                        if _G.Ox.AutoPallet.Distance < (humanoidRootPart.Position - v4.Position).Magnitude then
                            return
                        end
                        local v5 = fn14(humanoidRootPart)

                        if v5 then
                            fn15(v5)
                        end
                    end)
                end
            end
        end)
    end

    StopAutoPallet = function()
        if _G.Ox.AutoPallet.Connection then
            task.cancel(_G.Ox.AutoPallet.Connection)
            _G.Ox.AutoPallet.Connection = nil
        end

        _G.Ox.AutoPallet.UsedPallets = {}
    end

    ToggleAutoPallet = function(enabled)
        _G.Ox.AutoPallet.Enabled = enabled

        if enabled then
            if GetRole() ~= "Survivor" then

                _G.Ox.AutoPallet.Enabled = false

                if AutoPalletToggle then
                    fn(AutoPalletToggle, false)
                end

                return
            end

            _G.Ox.AutoPallet.UsedPallets = {}
            StartAutoPallet()

        else
            StopAutoPallet()

        end
    end

    localPlayer.CharacterAdded:Connect(function()
        _G.Ox.AutoPallet.UsedPallets = {}
        _G.Ox.AutoPallet.LastDrop = 0
    end)

    DropAllPallets = function()
        local remotes = ReplicatedStorage:FindFirstChild("Remotes")
        local palletDropEvent = remotes and remotes:FindFirstChild("Pallet") and remotes.Pallet:FindFirstChild("PalletDropEvent")

        if not palletDropEvent then

            return
        end

        local tbl6 = {}
        local map = workspace:FindFirstChild("Map")

        if not map then

            return
        end

        for i, descendant in ipairs(map:GetDescendants()) do
            if descendant.Name == "PalletPoint" and descendant:IsA("BasePart") then
                local model = descendant:FindFirstAncestorWhichIsA("Model")

                if model then
                    if not tbl6[model] then
                        tbl6[model] = {}
                    end

                    table.insert(tbl6[model], descendant)
                end
            end
        end

        local n2 = 0
        local v4, v5, v6 = pairs(tbl6)
        local v7 = v6
        local v8 = v4
        local v9 = v5

        while true do
            local v10, v11 = v8(v9, v7)
            if v10 == nil then
                break
            end

            for i, v12 in ipairs(v11) do
                pcall(function()
                    _G.Ox.Net.drop(v12)
                    n2 = n2 + 1
                end)
            end

            v7 = v10
        end

    end

    local n2 = 0

    fn2 = function(arg)
        if not arg and tick() - n2 < 2 then
            return
        end
        n2 = tick()
        table.clear(tbl.Generators)
        table.clear(tbl.Windows)
        table.clear(tbl.Pallets)
        table.clear(tbl.Hooks)
        table.clear(tbl.Gates)
        table.clear(tbl4.Generators)
        table.clear(tbl4.Windows)
        table.clear(tbl4.Pallets)
        table.clear(tbl4.Hooks)
        table.clear(tbl4.Gates)
        table.clear(tbl4.SCPs)
        local map = workspace:FindFirstChild("Map")
        local v4 = map or workspace
        local descendants = v4:GetDescendants()

        for i, descendant in ipairs(descendants) do
            if i % 200 == 0 then
                task.wait()
            end

            if descendant:IsA("Model") then
                local v5 = string.lower(descendant.Name)

                if v5 == "generator" then
                    local generatorBody = descendant:FindFirstChild("GeneratorBody")
                    local basePart = generatorBody or descendant:FindFirstChildWhichIsA("BasePart")

                    if basePart then
                        local tbl6 = {model = descendant, part = basePart}
                        table.insert(tbl.Generators, tbl6)
                        table.insert(tbl4.Generators, tbl6)
                    end
                elseif v5 == "hook" and descendant:FindFirstChild("HookPoint") then
                    table.insert(tbl.Hooks, descendant)
                    table.insert(tbl4.Hooks, descendant)
                elseif v5 == "gate" and descendant:FindFirstChild("ExitLever") then
                    table.insert(tbl.Gates, descendant)
                    table.insert(tbl4.Gates, descendant)
                elseif v5 == "window" then
                    table.insert(tbl.Windows, descendant)
                    table.insert(tbl4.Windows, descendant)
                end
            elseif descendant:IsA("BasePart") and descendant.Name == "PrimaryPartPallet" then
                local parent = descendant.Parent

                if parent and not table.find(tbl.Pallets, parent) then
                    table.insert(tbl.Pallets, parent)
                    table.insert(tbl4.Pallets, parent)
                end
            end
        end

        local descendants2 = workspace:GetDescendants()

        for i, v5 in ipairs(descendants2) do
            if i % 200 == 0 then
                task.wait()
            end

            if v5:IsA("Model") and string.match(string.lower(v5.Name), "^scp") and not table.find(tbl4.SCPs, v5) then
                table.insert(tbl4.SCPs, v5)
            end
        end

        for _, tagged in ipairs(CollectionService:GetTagged("scp")) do
            local model = tagged:IsA("Model") and tagged or tagged:FindFirstAncestorOfClass("Model")
            if model and not table.find(tbl4.SCPs, model) then
                table.insert(tbl4.SCPs, model)
            end
        end
        for _, point in ipairs(CollectionService:GetTagged("VaultPoint")) do
            local model = point.Parent
            if model and string.lower(model.Name) == "window" and not table.find(tbl4.Windows, model) then
                table.insert(tbl.Windows, model)
                table.insert(tbl4.Windows, model)
            end
        end
    end

    fn3 = function(arg)
        if not arg then
            return
        end
        local character = localPlayer.Character
        local humanoidRootPart = character and character:FindFirstChild("HumanoidRootPart")

        if humanoidRootPart then
            local vector = Vector3.new(0, 3, 0)

            if arg:IsA("BasePart") then
                humanoidRootPart.CFrame = arg.CFrame + vector
            elseif arg:IsA("Model") then
                local basePart = arg:FindFirstChildWhichIsA("BasePart")

                if basePart then
                    humanoidRootPart.CFrame = basePart.CFrame + vector
                end
            end

        end
    end

    ApplyFullBright = function()
        local Lighting = game:GetService("Lighting")
        if not Lighting then
            return
        end

        if _G.Ox.FullBright then
            Lighting.Brightness = 2.8
            Lighting.ClockTime = _G.Ox.TimeOfDayValue
            Lighting.FogEnd = 100000
            Lighting.Ambient = Color3.fromRGB(200, 200, 200)
            Lighting.OutdoorAmbient = Color3.fromRGB(200, 200, 200)
        end
    end

    ApplyNoFog = function()
        local Lighting = game:GetService("Lighting")
        if not Lighting then
            return
        end

        if _G.Ox.NoFog then
            Lighting.FogStart = 0
            Lighting.FogEnd = 100000
            Lighting.FogColor = Color3.fromRGB(255, 255, 255)
            local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")

            if atmosphere then
                atmosphere.Density = 0
                atmosphere.Offset = 0
                atmosphere.Glare = 0
                atmosphere.Haze = 0
            end
        end
    end

    ApplyNoShadow = function()
        local Lighting = game:GetService("Lighting")
        if not Lighting then
            return
        end
        local globalShadows

        if _G.Ox.NoShadow then
            globalShadows = false
        else
            globalShadows = true
        end

        Lighting.GlobalShadows = globalShadows
    end

    ReapplyPerformance = function()
        ApplyFullBright()
        ApplyNoFog()
        ApplyNoShadow()
    end

    ReapplyPerformanceDelayed = function()
        task.spawn(function()
            ReapplyPerformance()
            task.wait(1.2)
            ReapplyPerformance()
            task.wait(2)
            ReapplyPerformance()
            task.wait(3)
            ReapplyPerformance()
        end)
    end

    StartLightingGuard = function()
        if _G.Ox.LightingGuardConn then
            return
        end
        local n3 = 0

        _G.Ox.LightingGuardConn = RunService.Heartbeat:Connect(function()
            if not _G.Ox.FullBright and not _G.Ox.NoFog and not _G.Ox.NoShadow then
                return
            end
            local now = tick()
            if now - n3 < 0.4 then
                return
            end
            n3 = now
            ReapplyPerformance()
        end)
    end

    StopLightingGuard = function()
        if _G.Ox.FullBright or _G.Ox.NoFog or _G.Ox.NoShadow then
            return
        end

        if _G.Ox.LightingGuardConn then
            _G.Ox.LightingGuardConn:Disconnect()
            _G.Ox.LightingGuardConn = nil
        end
    end

    if not _G.Ox.LightingChildConn then
        _G.Ox.LightingChildConn = game:GetService("Lighting").ChildAdded:Connect(function(child)
            if not _G.Ox.FullBright and not _G.Ox.NoFog then
                return
            end

            task.defer(function()
                if child:IsA("Atmosphere") and _G.Ox.NoFog then
                    child.Density = 0
                    child.Offset = 0
                    child.Glare = 0
                    child.Haze = 0
                end

                ReapplyPerformance()
            end)
        end)
    end

    local function fn16(arg, arg2, arg3)
        table.insert(_G.Ox.LowGFX.Saved, {obj = arg, kind = arg2, extra = arg3})
    end

    LowGFX_ProcessOne = function(arg)
        if not _G.Ox.LowGFX.Enabled or not arg then
            return
        end
        local lowGFX = _G.Ox.LowGFX

        if lowGFX.Parts and (arg:IsA("BasePart") or arg:IsA("UnionOperation") or arg:IsA("MeshPart")) and arg.Material ~= Enum.Material.SmoothPlastic then
            fn16(arg, "Part", arg.Material)
            arg.Material = Enum.Material.SmoothPlastic
        end

        if lowGFX.Particles and (arg:IsA("ParticleEmitter") or arg:IsA("Smoke") or arg:IsA("Explosion") or arg:IsA("Sparkles") or arg:IsA("Fire")) and arg.Enabled ~= false then
            fn16(arg, "Particle", true)
            arg.Enabled = false
        end

        if lowGFX.VisualEffects and (arg:IsA("BloomEffect") or arg:IsA("BlurEffect") or arg:IsA("DepthOfFieldEffect") or arg:IsA("SunRaysEffect") or arg:IsA("ColorCorrectionEffect")) and arg.Enabled ~= false then
            fn16(arg, "VFX", true)
            arg.Enabled = false
        end

        if lowGFX.Textures and (arg:IsA("Decal") or arg:IsA("Texture")) and arg.Texture ~= "" then
            fn16(arg, "Texture", arg.Texture)
            arg.Texture = ""
        end

        if lowGFX.Sky and arg:IsA("Sky") then
            fn16(arg, "Sky", arg.Parent)
            arg.Parent = nil
        end
    end

    ApplyLowGFX = function()
        if not _G.Ox.LowGFX.Enabled then
            return
        end
        local tbl6 = {workspace, game:GetService("Lighting")}
        local v4, v5, v6 = ipairs(tbl6)
        local v7 = v6
        local v8 = v4
        local v9 = v5

        while true do
            local v10, v11 = v8(v9, v7)
            if v10 == nil then
                break
            end
            local descendants = v11:GetDescendants()

            for i, descendant in ipairs(descendants) do
                if i % 250 == 0 then
                    task.wait()
                end

                LowGFX_ProcessOne(descendant)
            end

            v7 = v10
        end
    end

    RestoreLowGFX = function()
        for i, v4 in ipairs(_G.Ox.LowGFX.Saved) do
            local obj = v4.obj

            if obj and obj.Parent then
                pcall(function()
                    if v4.kind == "Part" then
                        obj.Material = v4.extra
                    elseif v4.kind ~= "Particle" and v4.kind ~= "VFX" then
                        if v4.kind == "Texture" then
                            obj.Texture = v4.extra
                        elseif v4.kind == "Sky" and v4.extra then
                            obj.Parent = v4.extra
                        end
                    else
                        obj.Enabled = v4.extra
                    end
                end)
            end
        end

        table.clear(_G.Ox.LowGFX.Saved)
    end

    ToggleLowGFX = function(enabled)
        _G.Ox.LowGFX.Enabled = enabled

        if enabled then
            task.spawn(ApplyLowGFX)

        else
            RestoreLowGFX()

        end
    end

    if not _G.Ox.LowGFX.StreamConn then
        _G.Ox.LowGFX.StreamConn = workspace.DescendantAdded:Connect(function(descendant)
            if not _G.Ox.LowGFX.Enabled then
                return
            end

            task.defer(function()
                LowGFX_ProcessOne(descendant)
            end)
        end)
    end

    CreateSpectatorUI = function()
        if _G.Ox.Spectator.Gui then
            _G.Ox.Spectator.Gui:Destroy()
            _G.Ox.Spectator.Gui = nil
        end

        _G.Ox.Spectator.Gui = Instance.new("ScreenGui")
        _G.Ox.Spectator.Gui.Name = "SpectatorCounter"
        _G.Ox.Spectator.Gui.ResetOnSpawn = false
        _G.Ox.Spectator.Gui.Parent = localPlayer:WaitForChild("PlayerGui")
        local frame = Instance.new("Frame")
        frame.Name = "MainBox"
        frame.AnchorPoint = Vector2.new(0.5, 1)
        frame.Position = UDim2.new(0.5, 0, 0, -10)
        frame.Size = UDim2.new(0, 68, 0, 22)
        frame.BackgroundColor3 = Color3.fromRGB(16, 16, 18)
        frame.BackgroundTransparency = 0.25
        frame.BorderSizePixel = 0
        frame.Parent = _G.Ox.Spectator.Gui
        Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 8)
        local uiGradient = Instance.new("UIGradient")

        uiGradient.Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 1),
            NumberSequenceKeypoint.new(0.3, 0.4),
            NumberSequenceKeypoint.new(1, 1),
        })

        uiGradient.Parent = frame
        local uiListLayout = Instance.new("UIListLayout", frame)
        uiListLayout.FillDirection = Enum.FillDirection.Horizontal
        uiListLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
        uiListLayout.VerticalAlignment = Enum.VerticalAlignment.Center
        uiListLayout.Padding = UDim.new(0, 6)
        local imageLabel = Instance.new("ImageLabel", frame)
        imageLabel.Size = UDim2.new(0, 15, 0, 15)
        imageLabel.BackgroundTransparency = 1
        imageLabel.Image = "rbxassetid://13321848320"
        imageLabel.ImageColor3 = Color3.fromRGB(225, 225, 225)
        _G.Ox.Spectator.Label = Instance.new("TextLabel", frame)
        _G.Ox.Spectator.Label.BackgroundTransparency = 1
        _G.Ox.Spectator.Label.Font = Enum.Font.GothamMedium
        _G.Ox.Spectator.Label.Text = "0"
        _G.Ox.Spectator.Label.TextColor3 = Color3.fromRGB(240, 240, 240)
        _G.Ox.Spectator.Label.TextSize = 13
        _G.Ox.Spectator.Label.AutomaticSize = Enum.AutomaticSize.X
    end

    UpdateSpectatorCount = function()
        if not _G.Ox.Spectator.Enabled or not _G.Ox.Spectator.Label then
            return
        end
        local n3 = 0

        for i, player in ipairs(Players:GetPlayers()) do
            if player.Team and player.Team.Name == "Spectator" then
                n3 = n3 + 1
            end
        end

        _G.Ox.Spectator.Label.Text = tostring(n3)
        local gui = _G.Ox.Spectator.Gui
        local mainBox = gui and _G.Ox.Spectator.Gui:FindFirstChild("MainBox")

        if mainBox then
            local udim2 = UDim2.new
            local n4 = n3 >= 10 and 8 or 0
            local n5 = 55 + n4
            local n6 = n3 >= 100 and 8 or 0
            mainBox.Size = udim2(0, n5 + n6, 0, 22)
        end
    end

    StartSpectatorInfo = function()
        if _G.Ox.Spectator.Enabled then
            return
        end
        _G.Ox.Spectator.Enabled = true
        CreateSpectatorUI()
        UpdateSpectatorCount()

        task.spawn(function()
            while _G.Ox.Spectator.Enabled do
                UpdateSpectatorCount()
                task.wait(1.2)
            end
        end)

    end

    StopSpectatorInfo = function()
        _G.Ox.Spectator.Enabled = false

        if _G.Ox.Spectator.Gui then
            _G.Ox.Spectator.Gui:Destroy()
            _G.Ox.Spectator.Gui = nil
            _G.Ox.Spectator.Label = nil
        end

    end

    fn4 = function(arg)
        if arg then
            StartSpectatorInfo()
        else
            StopSpectatorInfo()
        end
    end

    ScanMapESP = function(arg)
        fn2(arg)
    end

    ForceRefreshMap = function()
        fn2(true)

        if _G.Ox.ESPConfig.Master then
            ClearAllESP()
            task.wait(0.1)
            UpdatePlayerESP()
            UpdateSCPESP()
            UpdateStaticESP()
        end
    end

    task.spawn(function()
        task.wait(2)
        ScanMapESP()
    end)

    localPlayer.CharacterAdded:Connect(function()
        task.wait(1.5)
        ScanMapESP()

        if _G.Ox.ESPConfig.Master then
            task.spawn(function()
                task.wait(0.5)
                ClearAllESP()
                task.wait(0.2)
                UpdatePlayerESP()
                UpdateSCPESP()
                UpdateStaticESP()
            end)
        end
    end)

    workspace.ChildAdded:Connect(function(child)
        if child.Name == "Map" then
            task.wait(1)
            ScanMapESP(true)

            if _G.Ox.ESPConfig.Master then
                pcall(UpdatePlayerESP)
                pcall(UpdateSCPESP)
                pcall(UpdateStaticESP)
            end

            ReapplyPerformanceDelayed()

            if _G.Ox.LowGFX.Enabled then
                table.clear(_G.Ox.LowGFX.Saved)
                task.wait(1.5)
                ApplyLowGFX()
                task.wait(2.5)

                if _G.Ox.LowGFX.Enabled then
                    ApplyLowGFX()
                end
            end
        end
    end)

    task.spawn(function()
        while _G.Ox.ScriptAlive do
            task.wait(40)

            if _G.Ox.ESPConfig.Master then
                ScanMapESP()

                if _G.Ox.ESPConfig.Master then
                    pcall(UpdateStaticESP)
                    pcall(UpdatePlayerESP)
                    pcall(UpdateSCPESP)
                end
            end
        end
    end)

    local function fn17()
        local playerGui2 = localPlayer:FindFirstChild("PlayerGui")
        if not playerGui2 then
            return nil
        end
        local survivorMob = playerGui2:FindFirstChild("Survivor-mob")
        if not survivorMob then
            return nil
        end
        local controls = survivorMob:FindFirstChild("Controls")
        if not controls then
            return nil
        end
        local sprint = controls:FindFirstChild("sprint")
        if not sprint then
            return nil
        end

        if sprint:IsA("GuiButton") then
            return sprint
        end
        local icon = sprint:FindFirstChild("icon")
        if icon and icon:IsA("GuiButton") then
            return icon
        end

        if icon and icon.Parent and icon.Parent:IsA("GuiButton") then
            return icon.Parent
        end

        if sprint.Parent and sprint.Parent:IsA("GuiButton") then
            return sprint.Parent
        end
        return sprint
    end

    local function fn18()
        local v4 = fn17()
        if not v4 then
            return false
        end

        pcall(function()
            if type(firesignal) == "function" then
                firesignal(v4.MouseButton1Click)
                firesignal(v4.MouseButton1Down)
                task.wait(0.04)
                firesignal(v4.MouseButton1Up)
            else
                local absolutePosition = v4.AbsolutePosition
                local absoluteSize = v4.AbsoluteSize
                local guiInset = GuiService:GetGuiInset()
                local n3 = absolutePosition.X + absoluteSize.X / 2 + guiInset.X
                local n4 = absolutePosition.Y + absoluteSize.Y / 2 + guiInset.Y
                VirtualInputManager:SendTouchEvent(9901, 0, n3, n4)
                task.wait(0.04)
                VirtualInputManager:SendTouchEvent(9901, 2, n3, n4)
            end
        end)

        return true
    end

    local function fn19()
        local character = localPlayer.Character
        if not character then
            return false
        end
        local humanoid = character:FindFirstChildOfClass("Humanoid")
        if not humanoid then
            return false
        end

        if humanoid.MoveDirection.Magnitude > 0.12 then
            return true
        end
        local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")

        if humanoidRootPart then
            local assemblyLinearVelocity = humanoidRootPart.AssemblyLinearVelocity
            if Vector3.new(assemblyLinearVelocity.X, 0, assemblyLinearVelocity.Z).Magnitude > 1.5 then
                return true
            end
        end

        return false
    end

    local function fn20()
        local character = localPlayer.Character
        if not character then
            return false
        end
        local flag4 = character:GetAttribute("Crouching") == true or character:GetAttribute("Crouchingserver") == true
        return flag4
    end

    local function fn21()
        local character = localPlayer.Character
        if not character then
            return false
        end
        local flag4 = character:GetAttribute("Sprinting") == true or character:GetAttribute("IsRunning") == true
        return flag4
    end

    fn5 = function()
        if _G.Ox.AutoRun.MobileThread then
            return
        end

        _G.Ox.AutoRun.MobileThread = task.spawn(function()
            while _G.Ox.AutoRun.Mobile do
                local v4 = fn19()
                local v5 = fn20()
                local v6 = fn21()

                if v5 then
                    if v6 then
                        fn18()
                    end
                elseif v4 and not v6 then
                    fn18()
                elseif not v4 and v6 then
                    fn18()
                end

                task.wait(0.12)
            end

            _G.Ox.AutoRun.MobileThread = nil
        end)
    end

    fn6 = function()
        _G.Ox.AutoRun.Mobile = false

        if _G.Ox.AutoRun.MobileThread then
            task.cancel(_G.Ox.AutoRun.MobileThread)
            _G.Ox.AutoRun.MobileThread = nil
        end

        if fn21() then
            fn18()
        end
    end

    task.spawn(function()
        while _G.Ox.ScriptAlive do
            task.wait(0.1)
            if not _G.Ox.ScriptAlive then
                break
            end

            if not UserInputService.TouchEnabled and tick() - _G.Ox.lastActionTime >= _G.Ox.COOLDOWN then
                local autoVaultEnabled = _G.Ox.autoVaultEnabled
                local autoPalletSlideEnabled = _G.Ox.autoPalletSlideEnabled

                if autoVaultEnabled or autoPalletSlideEnabled then
                    local pcprompts = playerGui:FindFirstChild("pcprompts")
                    local frame = pcprompts and pcprompts:FindFirstChild("Frame")

                    if frame then
                        local vaultPromptGui = frame:FindFirstChild("VaultPromptGui")
                        local palletSlidePromptGui = frame:FindFirstChild("PalletSlidePromptGui")
                        local visible = vaultPromptGui and vaultPromptGui.Visible
                        local visible2 = palletSlidePromptGui and palletSlidePromptGui.Visible

                        if autoVaultEnabled and visible or autoPalletSlideEnabled and visible2 then
                            VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.Space, false, game)
                            task.wait(0.01)
                            VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.Space, false, game)
                            _G.Ox.lastActionTime = tick()
                        end
                    end
                end
            end
        end
    end)

    local function fn22()
        if not UserInputService.TouchEnabled then
            return
        end
        local survivorMob = playerGui:FindFirstChild("Survivor-mob")
        local survivorMob2 = survivorMob or playerGui:WaitForChild("Survivor-mob", 8)
        if not survivorMob2 then
            return
        end
        local controls = survivorMob2:FindFirstChild("Controls")
        local controls2 = controls or survivorMob2:WaitForChild("Controls", 5)
        local action = controls2

        if controls2 then
            local action2 = controls2:FindFirstChild("action")
            action = action2 or controls2:WaitForChild("action", 5)
        end

        if not action then
            return
        end

        local tbl6 = {
            vault = true,
            palletvault = true,
            palletslide = true,
            slide = true,
        }

        local function fn23(arg)
            if not arg:IsA("ImageLabel") and not arg:IsA("ImageButton") then
                return
            end
            local str = arg.Name:lower()
            if not tbl6[str] then
                return
            end

            arg:GetPropertyChangedSignal("Visible"):Connect(function()
                if not arg.Visible then
                    return
                end

                if tick() - _G.Ox.lastActionTime < _G.Ox.COOLDOWN then
                    return
                end
                local pos = str:find("vault")
                local flag4 = pos

                if pos then
                    if str:find("pallet") then
                        flag4 = false
                    else
                        flag4 = true
                    end
                end

                local pos2 = str:find("pallet")
                local pos3 = pos2 or str:find("slide")

                if flag4 and _G.Ox.autoVaultEnabled or pos3 and _G.Ox.autoPalletSlideEnabled then
                    pcall(function()
                        firesignal(action.MouseButton1Down)
                        task.wait(0.01)
                        firesignal(action.MouseButton1Up)
                    end)

                    _G.Ox.lastActionTime = tick()
                end
            end)
        end

        for k, child in pairs(action:GetChildren()) do
            fn23(child)
        end

        action.ChildAdded:Connect(function(child)
            task.wait()
            fn23(child)
        end)
    end

    task.spawn(fn22)

    localPlayer.CharacterAdded:Connect(function()
        task.wait(2)
        fn22()
    end)

    playerGui.ChildAdded:Connect(function(child)
        if child.Name == "Survivor-mob" then
            task.wait(1)
            fn22()
        end
    end);

    (function()
        task.spawn(function()
            local remotes = ReplicatedStorage:WaitForChild("Remotes", 10)
            local killerPerks = remotes and remotes:WaitForChild("KillerPerks", 5)
            local kingscourge = killerPerks and killerPerks:WaitForChild("kingscourge", 5)
            local kingScourgeStart = kingscourge and kingscourge:WaitForChild("KingScourgeStart", 5)

            if kingScourgeStart then
                kingScourgeStart.OnClientEvent:Connect(function()
                    if _G.Ox.Auto.SkillCheckMode == "Random" then
                        _G.Ox.State.RandomMode_IsNormal = true
                    end
                end)
            end
        end)
    end)()

    local function fn23()
        if not playerGui then
            return nil
        end
        local survivorMob = playerGui:FindFirstChild("Survivor-mob")
        if not survivorMob then
            return nil
        end
        local controls = survivorMob:FindFirstChild("Controls")
        if not controls then
            return nil
        end
        local action = controls:FindFirstChild("action")
        local check = action or controls:FindFirstChild("check")
        return check
    end

    local function fn24()
        local v4 = fn23()

        if v4 and v4:IsA("GuiObject") and v4.Visible and type(firesignal) == "function" then
            pcall(function()
                firesignal(v4.MouseButton1Down)
                task.wait(0.005)
                firesignal(v4.MouseButton1Up)
            end)

            return true
        end

        if v4 and v4:IsA("GuiObject") and v4.Visible then
            pcall(function()
                local absolutePosition = v4.AbsolutePosition
                local absoluteSize = v4.AbsoluteSize
                local guiInset = GuiService:GetGuiInset()
                local n3 = 8822 + math.random(1, 9999)
                VirtualInputManager:SendTouchEvent(n3, 0, absolutePosition.X + absoluteSize.X / 2 + guiInset.X, absolutePosition.Y + absoluteSize.Y / 2 + guiInset.Y)
                task.wait(0.005)
                VirtualInputManager:SendTouchEvent(n3, 2, absolutePosition.X + absoluteSize.X / 2 + guiInset.X, absolutePosition.Y + absoluteSize.Y / 2 + guiInset.Y)
            end)

            return true
        end

        pcall(function()

            local raw = localPlayer:GetAttribute("kb_skillcheck")
            if typeof(raw) ~= "string" or raw == "" then
                raw = "Space"
            end
            local mouseIndex = raw:match("^MouseButton(%d)$")
            if mouseIndex then
                local button = tonumber(mouseIndex) - 1
                VirtualInputManager:SendMouseButtonEvent(0, 0, button, true, game, 0)
                task.wait(0.005)
                VirtualInputManager:SendMouseButtonEvent(0, 0, button, false, game, 0)
                return
            end
            local okKey, keyCode = pcall(function()
                return Enum.KeyCode[raw]
            end)
            if not okKey or not keyCode then
                keyCode = Enum.KeyCode.Space
            end
            VirtualInputManager:SendKeyEvent(true, keyCode, false, game)
            task.wait(0.005)
            VirtualInputManager:SendKeyEvent(false, keyCode, false, game)
        end)

        return true
    end

    fn7 = function()
        if _G.Ox.Connections.SkillHeartbeat then
            _G.Ox.Connections.SkillHeartbeat:Disconnect()
            _G.Ox.Connections.SkillHeartbeat = nil
        end

        _G.Ox.Connections.SkillHeartbeat = RunService.Heartbeat:Connect(function()
            if not _G.Ox.Auto.SkillCheck or _G.Ox.State.busy then
                return
            end

            local ownChar = localPlayer.Character
            if ownChar and ownChar:GetAttribute("Trapped") == true then
                return
            end
            local skillCheckPromptGui = playerGui:FindFirstChild("SkillCheckPromptGui")
            if not skillCheckPromptGui then
                return
            end
            local check = skillCheckPromptGui:FindFirstChild("Check")
            if check then
                local trapGoal = check:FindFirstChild("TrapGoal")
                local trapPerfect = check:FindFirstChild("TrapPerfect")
                if (trapGoal and trapGoal.Visible) or (trapPerfect and trapPerfect.Visible) then
                    return
                end
            end

            if check and check.Visible then
                local line = check:FindFirstChild("Line")
                local goal = check:FindFirstChild("Goal")
                if not line or not goal then
                    return
                end
                local flag4 = _G.Ox.Auto.SkillCheckMode == "Instant"

                if not flag4 then
                    flag4 = _G.Ox.Auto.SkillCheckMode == "Random"

                    if flag4 then
                        if _G.Ox.State.RandomMode_IsNormal then
                            flag4 = false
                        else
                            flag4 = true
                        end
                    end
                end

                if flag4 then
                    line.Rotation = goal.Rotation + 109
                    _G.Ox.State.busy = true

                    task.spawn(function()
                        fn24()
                        task.wait(0.05)
                        _G.Ox.State.busy = false
                    end)
                else
                    local randomModeIsNormal = _G.Ox.Auto.SkillCheckMode == "Normal" or _G.Ox.Auto.SkillCheckMode == "Random" and _G.Ox.State.RandomMode_IsNormal
                    local n3 = line.Rotation % 360
                    local n4 = goal.Rotation % 360
                    local n5, n6

                    if randomModeIsNormal then
                        n5 = (n4 + 116) % 360
                        n6 = (n4 + 140) % 360
                    else
                        n5 = (n4 + 102) % 360
                        n6 = (n4 + 116) % 360
                    end

                    local v4

                    if n6 < n5 then
                        local flag5 = n5 <= n3 or n3 <= n6
                        v4 = flag5
                    else
                        local flag5 = n5 <= n3 and n3 <= n6
                        v4 = flag5
                    end

                    if v4 then
                        _G.Ox.State.busy = true

                        task.spawn(function()
                            fn24()
                            task.wait(0.05)
                            _G.Ox.State.busy = false
                        end)
                    end
                end

                return
            end

            _G.Ox.State.RandomMode_IsNormal = false
        end)
    end

    getTargetPartObject = function(arg)
        if _G.Ox.AimConfig.AIM_TargetPart == "Head" then
            return arg:FindFirstChild("Head")
        end

        if _G.Ox.AimConfig.AIM_TargetPart == "Root" or _G.Ox.AimConfig.AIM_TargetPart == "HumanoidRootPart" then
            return arg:FindFirstChild("HumanoidRootPart")
        end
        local torso = arg:FindFirstChild("Torso")
        local upperTorso = torso or arg:FindFirstChild("UpperTorso") or arg:FindFirstChild("HumanoidRootPart")
        return upperTorso
    end

    getClosestSurvivor = function()
        local character = localPlayer.Character
        local humanoidRootPart = character and character:FindFirstChild("HumanoidRootPart")
        if not humanoidRootPart then
            return nil
        end
        local cfg = _G.Ox.AimConfig

        -- PERMA LOCK: hard-lock one survivor model until toggled off
        if cfg.Veil_PermaLock and cfg.Veil_PermaTarget then
            local locked = cfg.Veil_PermaTarget
            if locked and locked.Parent then
                local humanoid = locked:FindFirstChildOfClass("Humanoid")
                local part = getTargetPartObject(locked)
                if humanoid and humanoid.Health > 0 and part then
                    return part
                end
            end
            -- locked model gone / dead → clear, fall through to normal acquire
            cfg.Veil_PermaTarget = nil
        end

        local fovLimit = cfg.Veil_FOV
        local maxDist = math.huge
        local currentCamera2 = workspace.CurrentCamera
        local center = Vector2.new(currentCamera2.ViewportSize.X / 2, currentCamera2.ViewportSize.Y / 2)

        local rayParams = RaycastParams.new()
        rayParams.FilterType = Enum.RaycastFilterType.Exclude

        local bestVisible, bestVisibleMag = nil, math.huge
        local bestAny, bestAnyMag = nil, math.huge

        local sticky = _G.Ox.VeilSticky
        local stickyPart

        for _, player in ipairs(Players:GetPlayers()) do
            if player ~= localPlayer and player.Team and player.Team.Name == "Survivors" and player.Character then
                local character2 = player.Character
                local humanoid = character2:FindFirstChildOfClass("Humanoid")
                local part = getTargetPartObject(character2)

                if part then
                    rayParams.FilterDescendantsInstances = {character, character2}
                    local from0 = humanoidRootPart.Position
                    local candidates = {part}
                    for _, partName in ipairs({"Head", "Torso", "HumanoidRootPart", "Left Leg", "Right Leg"}) do
                        local extra = character2:FindFirstChild(partName)
                        if extra then
                            candidates[#candidates + 1] = extra
                        end
                    end
                    for _, candidate in ipairs(candidates) do
                        local h0 = workspace:Raycast(from0, candidate.Position - from0, rayParams)
                        if not (h0 and h0.Instance.CanCollide and h0.Instance.Transparency < 0.05) then
                            part = candidate
                            break
                        end
                    end
                end

                if humanoid and humanoid.Health > 0 and part and (part.Position - humanoidRootPart.Position).Magnitude <= maxDist then
                    local screen, onScreen = currentCamera2:WorldToViewportPoint(part.Position)

                    if onScreen then
                        local mag = (Vector2.new(screen.X, screen.Y) - center).Magnitude

                        if mag <= fovLimit then
                            if sticky and sticky.char == character2 and os.clock() - sticky.t < 2 then
                                stickyPart = part
                            end

                            rayParams.FilterDescendantsInstances = {character, character2}
                            local from = humanoidRootPart.Position
                            local hit = workspace:Raycast(from, part.Position - from, rayParams)
                            local blocked = hit ~= nil and hit.Instance.CanCollide and hit.Instance.Transparency < 0.05

                            if not blocked and mag < bestVisibleMag then
                                bestVisible, bestVisibleMag = part, mag
                            end
                            if mag < bestAnyMag then
                                bestAny, bestAnyMag = part, mag
                            end
                        end
                    end
                end
            end
        end

        local picked = stickyPart or bestVisible or bestAny
        if picked then
            local m = picked:FindFirstAncestorOfClass("Model")
            _G.Ox.VeilSticky = {char = m, t = (stickyPart and sticky) and sticky.t or os.clock()}
            if stickyPart and sticky then
                _G.Ox.VeilSticky.t = os.clock()
            end
            -- when PermaLock is on, register this as the permanent target
            if cfg.Veil_PermaLock and m then
                cfg.Veil_PermaTarget = m
            end
        end
        return picked
    end


    getBestKillerAimbotTarget = function()
        local v7 = nil
        local huge = math.huge
        local character = localPlayer.Character
        local humanoidRootPart = character and character:FindFirstChild("HumanoidRootPart")
        if not humanoidRootPart then
            return nil
        end

        for i, player in ipairs(Players:GetPlayers()) do
            if player ~= localPlayer and player.Team and player.Team.Name == "Survivors" and player.Character then
                local humanoid = player.Character:FindFirstChildOfClass("Humanoid")
                local humanoidRootPart2 = player.Character:FindFirstChild("HumanoidRootPart")

                if humanoid and humanoid.Health > 0 and humanoidRootPart2 and not IsDowned(player.Character) then
                    local magnitude = (humanoidRootPart2.Position - humanoidRootPart.Position).Magnitude

                    if magnitude < huge and magnitude <= _G.Ox.Config.Killer_Aimbot_MaxDist then
                        huge = magnitude
                        v7 = humanoidRootPart2
                    end
                end
            end
        end

        return v7
    end

    getKillerTargetForFlash = function()
        local v7 = nil
        local huge = math.huge
        local character = localPlayer.Character
        local humanoidRootPart = character and character:FindFirstChild("HumanoidRootPart")
        if not humanoidRootPart then
            return nil
        end

        for i, player in ipairs(Players:GetPlayers()) do
            if player ~= localPlayer and player.Team and player.Team.Name == "Killer" and player.Character then
                local humanoid = player.Character:FindFirstChildOfClass("Humanoid")
                local humanoidRootPart2 = player.Character:FindFirstChild("HumanoidRootPart")

                if humanoid and humanoid.Health > 0 and humanoidRootPart2 and not IsDowned(player.Character) then
                    local magnitude = (humanoidRootPart2.Position - humanoidRootPart.Position).Magnitude

                    if magnitude < huge then
                        huge = magnitude
                        v7 = humanoidRootPart2
                    end
                end
            end
        end
    -- Veil laser (straight) + ballistic trajectory curve (same math as silent aim)
    local veilLaser = { part = nil, att0 = nil, att1 = nil, beam = nil }
    local veilTraj = { folder = nil, points = {}, beams = {} }
    local TRAJ_SEGMENTS = 24
    local SPEAR_PREVIEW_SPEED = 165
    local SPEAR_PREVIEW_GRAV = 98.1

    local function ballisticAnglePreview(speed, grav, dist, height)
        local d = math.max(dist, 0.1)
        local v2 = speed * speed
        local disc = v2 * v2 - grav * (grav * d * d + 2 * height * v2)
        local angle
        if disc < 0 then
            angle = math.pi / 4
        else
            angle = math.atan((v2 - math.sqrt(disc)) / (grav * d))
        end
        local cosA = math.cos(angle)
        if math.abs(cosA) < 1e-4 then
            cosA = 1e-4
        end
        return angle, d / (speed * cosA)
    end

    local function getVeilThrowOrigin()
        local char = localPlayer.Character
        if not char then return nil end
        local hand = char:FindFirstChild("RightHand") or char:FindFirstChild("Right Arm")
        local hrp = char:FindFirstChild("HumanoidRootPart")
        if hand and hand:IsA("BasePart") then
            return hand.Position
        end
        if hrp then
            return hrp.Position + Vector3.new(0, 1.5, 0)
        end
        return nil
    end

    local function predictTargetPos(targetPart)
        if not targetPart then return nil end
        local model = targetPart:FindFirstAncestorOfClass("Model") or targetPart.Parent
        local root = (model and model:FindFirstChild("HumanoidRootPart")) or targetPart
        local humanoid = model and model:FindFirstChildOfClass("Humanoid")
        local vel = (root and root:IsA("BasePart") and root.AssemblyLinearVelocity) or Vector3.zero
        if Vector3.new(vel.X, 0, vel.Z).Magnitude < 0.5 and humanoid and humanoid.MoveDirection.Magnitude > 0 then
            vel = humanoid.MoveDirection * (humanoid.WalkSpeed or 16)
        end
        local flatVel = Vector3.new(vel.X, 0, vel.Z)
        local lead = (_G.Ox.AimConfig and _G.Ox.AimConfig.Veil_LeadMultiplier) or 1
        local origin = getVeilThrowOrigin()
        if not origin then return targetPart.Position end
        local aimPos = targetPart.Position
        local speed = SPEAR_PREVIEW_SPEED
        local grav = SPEAR_PREVIEW_GRAV
        for _ = 1, 5 do
            local d = aimPos - origin
            local flat = Vector3.new(d.X, 0, d.Z)
            local angle, flight = ballisticAnglePreview(speed, grav, flat.Magnitude, d.Y)
            flight = math.clamp(flight, 0.05, 4)
            aimPos = targetPart.Position + flatVel * (flight * lead)
        end
        return aimPos
    end

    local function getVeilAimDirection(origin, aimPos, speed, grav)
        local d = aimPos - origin
        local flat = Vector3.new(d.X, 0, d.Z)
        if flat.Magnitude < 0.05 then
            return d.Magnitude > 0.05 and d.Unit or nil, 0
        end
        local angle, flight = ballisticAnglePreview(speed, grav, flat.Magnitude, d.Y)
        local dir = (flat.Unit * math.cos(angle) + Vector3.new(0, math.sin(angle), 0)).Unit
        return dir, math.clamp(flight, 0.05, 5)
    end

    local function ensureVeilLaser()
        if veilLaser.beam and veilLaser.beam.Parent then
            return
        end
        local p = Instance.new("Part")
        p.Name = "KishaVeilLaser"
        p.Anchored = true
        p.CanCollide = false
        p.CanQuery = false
        p.CanTouch = false
        p.Transparency = 1
        p.Size = Vector3.new(0.1, 0.1, 0.1)
        p.Parent = workspace
        local a0 = Instance.new("Attachment")
        a0.Parent = p
        local a1 = Instance.new("Attachment")
        a1.Parent = p
        local b = Instance.new("Beam")
        b.Attachment0 = a0
        b.Attachment1 = a1
        b.Color = ColorSequence.new(Color3.fromRGB(255, 145, 186))
        b.Width0 = 0.12
        b.Width1 = 0.04
        b.FaceCamera = true
        b.LightEmission = 1
        b.Transparency = NumberSequence.new(0.15)
        b.Parent = p
        veilLaser.part, veilLaser.att0, veilLaser.att1, veilLaser.beam = p, a0, a1, b
    end

    local function hideVeilLaser()
        if veilLaser.beam then
            veilLaser.beam.Enabled = false
        end
        if veilLaser.part then
            veilLaser.part.CFrame = CFrame.new(0, -5000, 0)
        end
    end

    local function ensureVeilTrajectory()
        if veilTraj.folder and veilTraj.folder.Parent then
            return
        end
        local folder = Instance.new("Folder")
        folder.Name = "KishaVeilTrajectory"
        folder.Parent = workspace
        veilTraj.folder = folder
        veilTraj.points = {}
        veilTraj.beams = {}
        for i = 1, TRAJ_SEGMENTS + 1 do
            local p = Instance.new("Part")
            p.Name = "T" .. i
            p.Anchored = true
            p.CanCollide = false
            p.CanQuery = false
            p.CanTouch = false
            p.Transparency = 1
            p.Size = Vector3.new(0.15, 0.15, 0.15)
            p.Material = Enum.Material.Neon
            p.Color = Color3.fromRGB(255, 145, 186)
            p.Parent = folder
            local att = Instance.new("Attachment")
            att.Parent = p
            veilTraj.points[i] = { part = p, att = att }
        end
        for i = 1, TRAJ_SEGMENTS do
            local b = Instance.new("Beam")
            b.Attachment0 = veilTraj.points[i].att
            b.Attachment1 = veilTraj.points[i + 1].att
            b.Color = ColorSequence.new(Color3.fromRGB(255, 145, 186))
            b.Width0 = 0.1
            b.Width1 = 0.08
            b.FaceCamera = true
            b.LightEmission = 0.9
            b.Transparency = NumberSequence.new({
                NumberSequenceKeypoint.new(0, 0.2),
                NumberSequenceKeypoint.new(1, 0.45),
            })
            b.Parent = folder
            veilTraj.beams[i] = b
        end
    end

    local function hideVeilTrajectory()
        if not veilTraj.folder then return end
        for _, b in ipairs(veilTraj.beams) do
            b.Enabled = false
        end
        for _, pt in ipairs(veilTraj.points) do
            pt.part.CFrame = CFrame.new(0, -5000, 0)
            pt.part.Transparency = 1
        end
    end

    local function sampleTrajectory(origin, dir, speed, grav, flight)
        local g = Vector3.new(0, -grav, 0)
        local pts = {}
        local steps = TRAJ_SEGMENTS
        for i = 0, steps do
            local t = flight * (i / steps)
            local pos = origin + dir * (speed * t) + g * (0.5 * t * t)
            pts[#pts + 1] = pos
        end
        return pts
    end

    local function updateVeilLaser()
        local cfg = _G.Ox.AimConfig
        if not cfg.Aim_SilentVeilV2 or not cfg.Veil_Laser then
            hideVeilLaser()
            return
        end
        local targetPart = getClosestSurvivor()
        if not targetPart then
            hideVeilLaser()
            return
        end
        local from = getVeilThrowOrigin()
        if not from then
            hideVeilLaser()
            return
        end
        local to = targetPart.Position
        ensureVeilLaser()
        local mid = from:Lerp(to, 0.5)
        veilLaser.part.CFrame = CFrame.new(mid)
        veilLaser.att0.WorldPosition = from
        veilLaser.att1.WorldPosition = to
        veilLaser.beam.Enabled = true
    end

    local function updateVeilTrajectory()
        local cfg = _G.Ox.AimConfig
        if not cfg.Aim_SilentVeilV2 or not cfg.Veil_Trajectory then
            hideVeilTrajectory()
            return
        end
        local targetPart = getClosestSurvivor()
        local origin = getVeilThrowOrigin()
        if not targetPart or not origin then
            hideVeilTrajectory()
            return
        end
        local aimPos = predictTargetPos(targetPart)
        local speed = SPEAR_PREVIEW_SPEED
        local grav = SPEAR_PREVIEW_GRAV
        local dir, flight = getVeilAimDirection(origin, aimPos, speed, grav)
        if not dir then
            hideVeilTrajectory()
            return
        end
        local pts = sampleTrajectory(origin, dir, speed, grav, flight)
        ensureVeilTrajectory()
        for i, pos in ipairs(pts) do
            local pt = veilTraj.points[i]
            if pt then
                pt.part.CFrame = CFrame.new(pos)
                if i == #pts then
                    pt.part.Transparency = 0.2
                    pt.part.Size = Vector3.new(0.35, 0.35, 0.35)
                else
                    pt.part.Transparency = 1
                    pt.part.Size = Vector3.new(0.12, 0.12, 0.12)
                end
            end
        end
        for _, b in ipairs(veilTraj.beams) do
            b.Enabled = true
        end
    end

    task.spawn(function()
        while _G.Ox.ScriptAlive ~= false do
            pcall(updateVeilLaser)
            pcall(updateVeilTrajectory)
            task.wait(0.03)
        end
        hideVeilLaser()
        hideVeilTrajectory()
    end)

setupSpearInterceptor = function()
        if flag3 then
            return
        end

        if not getrawmetatable or not setreadonly then
            return
        end
        local spearthrow = nil

        pcall(function()
            spearthrow = ReplicatedStorage.Remotes.Killers.Veil.Spearthrow
        end)

        local remotes = ReplicatedStorage:FindFirstChild("Remotes")
        local fall = remotes and ReplicatedStorage.Remotes:FindFirstChild("Mechanics") and ReplicatedStorage.Remotes.Mechanics:FindFirstChild("Fall")

        local function fn29(speed, grav, dist, height)
            local d = math.max(dist, 0.1)
            local v2 = speed * speed
            local disc = v2 * v2 - grav * (grav * d * d + 2 * height * v2)
            local angle
            if disc < 0 then
                angle = math.pi / 4
            else
                angle = math.atan((v2 - math.sqrt(disc)) / (grav * d))
            end
            return angle, d / (speed * math.cos(angle))
        end

        local SPEAR_MAX_SPEED, SPEAR_GRAV = 165, 98.1
        local chargeStart = {}
        local chargeOrder = {}

        local function noteCharge(seq, t)
            if seq ~= nil and typeof(t) == "number" then
                chargeStart[seq] = t
                table.insert(chargeOrder, seq)
                if #chargeOrder > 12 then
                    chargeStart[table.remove(chargeOrder, 1)] = nil
                end
            end
        end

        local function veilAimPayload(payload)
            if typeof(payload) ~= "table" or typeof(payload.Direction) ~= "Vector3" or typeof(payload.Origin) ~= "Vector3" then
                return nil
            end
            local targetPart = getClosestSurvivor()
            if not targetPart then
                return nil
            end
            local model = targetPart:FindFirstAncestorOfClass("Model")
            if not model then
                return nil
            end
            local origin = payload.Origin
            local grav = SPEAR_GRAV

            local speed = SPEAR_MAX_SPEED
            local started = chargeStart[payload.Sequence]
            if started and typeof(payload.ReleasedAt) == "number" then
                speed = math.clamp((payload.ReleasedAt - started) * SPEAR_MAX_SPEED, 1, SPEAR_MAX_SPEED)
            end

            local humanoid = model:FindFirstChildOfClass("Humanoid")
            local root = model:FindFirstChild("HumanoidRootPart") or targetPart
            local vel = root:IsA("BasePart") and root.AssemblyLinearVelocity or Vector3.new(0, 0, 0)
            if Vector3.new(vel.X, 0, vel.Z).Magnitude < 0.5 and humanoid and humanoid.MoveDirection.Magnitude > 0 then
                vel = humanoid.MoveDirection * humanoid.WalkSpeed
            end
            local airborne = humanoid ~= nil and humanoid.FloorMaterial == Enum.Material.Air
            local flatVel = Vector3.new(vel.X, 0, vel.Z)
            local vy = airborne and vel.Y or 0
            local worldG = workspace.Gravity

            local everyone = {}
            for _, pl in ipairs(Players:GetPlayers()) do
                if pl.Character then
                    table.insert(everyone, pl.Character)
                end
            end
            -- the game's own spear world rule: parts with Transparency >= 0.05 are ignored (unless TrueInvis), CanCollide does not matter
            local function solid(hit)
                local inst = hit.Instance
                if inst.Name == "Plant" then
                    return false
                end
                return inst.Transparency < 0.05 or CollectionService:HasTag(inst, "TrueInvis")
            end

            local bodyParts = {}
            for _, name in ipairs({"Head", "Torso", "UpperTorso", "LowerTorso", "Left Arm", "Right Arm", "Left Leg", "Right Leg"}) do
                local bp = model:FindFirstChild(name)
                if bp and bp:IsA("BasePart") then
                    table.insert(bodyParts, bp)
                end
            end

            -- ray (origin, delta) against an oriented box, same math as the game's bodyIntersection; returns the 0..1 fraction
            local function boxFraction(rayOrigin, delta, cf, size)
                local o = cf:PointToObjectSpace(rayOrigin)
                local d = cf:VectorToObjectSpace(delta)
                local t0, t1 = 0, 1
                for _, axis in ipairs({"X", "Y", "Z"}) do
                    local oa, da, h = o[axis], d[axis], size[axis] * 0.5
                    if math.abs(da) < 1e-8 then
                        if oa < -h or oa > h then
                            return nil
                        end
                    else
                        local a, b = (-h - oa) / da, (h - oa) / da
                        if a > b then
                            a, b = b, a
                        end
                        t0 = math.max(t0, a)
                        t1 = math.min(t1, b)
                        if t1 < t0 then
                            return nil
                        end
                    end
                end
                return t0
            end

            local function arcClear(startPos, dirUnit, flightT)
                local rp = RaycastParams.new()
                rp.FilterType = Enum.RaycastFilterType.Exclude
                rp.FilterDescendantsInstances = everyone
                local prev = startPos
                local limit = math.min(flightT + 0.35, 4)
                local steps = math.max(10, math.ceil(limit / 0.04))
                local pad = Vector3.new(0.3, 0.3, 0.3)
                for i = 1, steps do
                    local t = limit * i / steps
                    local pt = startPos + dirUnit * speed * t + Vector3.new(0, -0.5 * grav * t * t, 0)
                    local seg = pt - prev
                    local shift = flatVel * t
                    if airborne then
                        shift = shift + Vector3.new(0, vy * t - 0.5 * worldG * t * t, 0)
                    end
                    local bestF
                    for _, bp in ipairs(bodyParts) do
                        local f = boxFraction(prev, seg, bp.CFrame + shift, bp.Size + pad)
                        if f and (not bestF or f < bestF) then
                            bestF = f
                        end
                    end
                    local hit = workspace:Raycast(prev, seg, rp)
                    local guard = 0
                    while hit and not solid(hit) and guard < 8 do
                        local l2 = rp.FilterDescendantsInstances
                        table.insert(l2, hit.Instance)
                        rp.FilterDescendantsInstances = l2
                        hit = workspace:Raycast(prev, seg, rp)
                        guard += 1
                    end
                    if hit and solid(hit) then
                        local wallF = hit.Distance / math.max(seg.Magnitude, 1e-6)
                        return bestF ~= nil and bestF <= wallF
                    end
                    if bestF then
                        return true
                    end
                    prev = pt
                end
                return false
            end

            local function plan(partPos)
                local dir = payload.Direction
                local lowDir, lowFlight, highDir, highFlight, startPos
                for _ = 1, 3 do
                    startPos = origin + dir * 3
                    local d = partPos - startPos
                    local angle, flight = fn29(speed, grav, Vector3.new(d.X, 0, d.Z).Magnitude, d.Y)
                    if flatVel.Magnitude > 0.5 or airborne then
                        for _ = 1, 6 do
                            local t = math.min(flight, 4)
                            local aim = partPos + flatVel * t
                            if airborne then
                                aim = aim + Vector3.new(0, vy * t - 0.5 * worldG * t * t, 0)
                            end
                            d = aim - startPos
                            angle, flight = fn29(speed, grav, Vector3.new(d.X, 0, d.Z).Magnitude, d.Y)
                        end
                    end
                    local flat = Vector3.new(d.X, 0, d.Z)
                    if flat.Magnitude > 0.001 then
                        dir = flat.Unit * math.cos(angle) + Vector3.new(0, math.sin(angle), 0)
                        lowDir, lowFlight = dir, flight
                        local v2 = speed * speed
                        local dist = flat.Magnitude
                        local disc = v2 * v2 - grav * (grav * dist * dist + 2 * d.Y * v2)
                        if disc >= 0 then
                            local ha = math.atan((v2 + math.sqrt(disc)) / (grav * dist))
                            highDir = flat.Unit * math.cos(ha) + Vector3.new(0, math.sin(ha), 0)
                            highFlight = dist / (speed * math.cos(ha))
                        else
                            highDir, highFlight = nil, nil
                        end
                    else
                        dir = d.Unit
                        lowDir, lowFlight = dir, flight
                    end
                end
                return lowDir, lowFlight, highDir, highFlight, startPos
            end

            local points = {targetPart.Position}
            for _, name in ipairs({"Head", "HumanoidRootPart", "Torso", "UpperTorso", "Right Leg", "Left Leg", "Right Arm", "Left Arm"}) do
                local part = model:FindFirstChild(name)
                if part and part:IsA("BasePart") and part ~= targetPart then
                    table.insert(points, part.Position)
                end
            end

            local chosen, fallbackLow
            for index, point in ipairs(points) do
                local lowDir, lowFlight, highDir, highFlight, startPos = plan(point)
                if lowDir then
                    if index == 1 then
                        fallbackLow = lowDir
                    end
                    if lowFlight <= 4.0 and arcClear(startPos, lowDir.Unit, lowFlight) then
                        chosen = lowDir
                        break
                    end
                    if highDir and highFlight <= 4.0 and arcClear(startPos, highDir.Unit, highFlight) then
                        chosen = highDir
                        break
                    end
                end
            end

            if not chosen then
                local flatTo = Vector3.new(root.Position.X - origin.X, 0, root.Position.Z - origin.Z)
                if flatTo.Magnitude > 0.5 then
                    local yaw = flatTo.Unit
                    local hdist = flatTo.Magnitude
                    for _, deg in ipairs({0, 2, 4, 6, 8, 10, 12, 15, 18, 22, 26, 30, 35, 40, 45, 50, 55, 60, 65, 70, 75}) do
                        local rad = math.rad(deg)
                        local cand = yaw * math.cos(rad) + Vector3.new(0, math.sin(rad), 0)
                        local flight = hdist / math.max(speed * math.cos(rad), 1)
                        if flight <= 4 and arcClear(origin + cand * 3, cand, flight) then
                            chosen = cand
                            break
                        end
                    end
                end
            end

            local dir = chosen or fallbackLow or payload.Direction
            local outOrigin = origin

            -- Direct mode: the spear is released right next to the target's body and flies straight at it
            if not chosen and _G.Ox.AimConfig.Veil_Direct then
                local bodyPos = (model:FindFirstChild("HumanoidRootPart") or targetPart).Position
                local ownRoot = localPlayer.Character and localPlayer.Character:FindFirstChild("HumanoidRootPart")
                local toMe = ownRoot and Vector3.new(ownRoot.Position.X - bodyPos.X, 0, ownRoot.Position.Z - bodyPos.Z) or Vector3.new(0, 0, 1)
                toMe = toMe.Magnitude > 0.01 and toMe.Unit or Vector3.new(0, 0, 1)
                local side = Vector3.new(-toMe.Z, 0, toMe.X)
                local approaches = {
                    toMe * 4, side * 4, -side * 4, -toMe * 4,
                    toMe * 4 + Vector3.new(0, 3, 0), Vector3.new(0, 5, 0),
                }
                local rp = RaycastParams.new()
                rp.FilterType = Enum.RaycastFilterType.Exclude
                rp.FilterDescendantsInstances = {localPlayer.Character, model}
                for _, off in ipairs(approaches) do
                    local startPos = bodyPos + off
                    local hit = workspace:Raycast(startPos, bodyPos - startPos, rp)
                    local free = (not hit) or (not hit.Instance.CanCollide)
                    if free and not workspace:Raycast(bodyPos, off, rp) then
                        local aimDir = (bodyPos - startPos).Unit
                        local out = {}
                        for k, v in pairs(payload) do
                            out[k] = v
                        end
                        out.Direction = aimDir
                        out.Origin = startPos
                        return out
                    end
                end
            end

            if not chosen then
                local position = targetPart.Position
                local function blocked(a, b)
                    local rp = RaycastParams.new()
                    rp.FilterType = Enum.RaycastFilterType.Exclude
                    local list = {localPlayer.Character, model}
                    for _ = 1, 8 do
                        rp.FilterDescendantsInstances = list
                        local hit = workspace:Raycast(a, b - a, rp)
                        if not hit then
                            return false
                        end
                        if solid(hit) then
                            return true
                        end
                        table.insert(list, hit.Instance)
                    end
                    return false
                end
                if blocked(origin, position) then
                    local ownRoot = localPlayer.Character and localPlayer.Character:FindFirstChild("HumanoidRootPart")
                    local toMe = ownRoot and Vector3.new(ownRoot.Position.X - position.X, 0, ownRoot.Position.Z - position.Z) or Vector3.new(0, 0, 1)
                    toMe = toMe.Magnitude > 0.01 and toMe.Unit or Vector3.new(0, 0, 1)
                    local side = Vector3.new(-toMe.Z, 0, toMe.X)
                    local candidates = {
                        Vector3.new(0, 1, 0),
                        toMe * 0.9 + Vector3.new(0, 0.45, 0),
                        side * 0.9 + Vector3.new(0, 0.45, 0),
                        -side * 0.9 + Vector3.new(0, 0.45, 0),
                        -toMe * 0.9 + Vector3.new(0, 0.45, 0),
                    }
                    for _, c in ipairs(candidates) do
                        local point = position + c.Unit * 7
                        if not blocked(point, position) then
                            dir = (position - point).Unit
                            outOrigin = point - dir * 3
                            break
                        end
                    end
                end
            end

            local out = {}
            for k, v in pairs(payload) do
                out[k] = v
            end
            out.Direction = dir.Unit
            out.Origin = outOrigin
            return out
        end

        local v7 = getrawmetatable(game)
        setreadonly(v7, false)
        local namecall = v7.__namecall

        v7.__namecall = newcclosure(function(arg, ...)
            local v8 = getnamecallmethod()
            local flag9 = v8 == "FireServer" or v8 == "fireServer" or v8 == "InvokeServer"

            if flag9 and not checkcaller() and typeof(arg) == "Instance" then
                local ka = _G.Ox.KAim
                if ka and ka.flaskOn and ka.flaskRemote and arg == ka.flaskRemote and v8 == "FireServer" then
                    local ok, d1, d2, d3, d4 = pcall(ka.flask, ...)
                    if ok and d1 then
                        setnamecallmethod(v8)
                        return namecall(arg, d1, d2, d3, d4)
                    end
                end

                if _G.Ox.NoFall.Enabled and fall and arg == fall then
                    local tbl7 = {...}
                    tbl7[1] = 0
                    return namecall(arg, unpack(tbl7))
                end

                if _G.Ox.AntiBlindEnabled and _G.Ox.GotBlindedRemote and arg == _G.Ox.GotBlindedRemote and localPlayer.Team and localPlayer.Team.Name == "Killer" then
                    return nil
                end

                local tof = _G.Ox.ToF
                if tof and v8 == "FireServer" and arg == tof.remote then
                    local ok, a1, a2 = pcall(tof.onFire, ...)
                    if ok then
                        if a1 == false then
                            return nil
                        elseif a1 then
                            setnamecallmethod(v8)
                            return namecall(arg, a1, a2)
                        end
                    end
                end

                if arg.Name == "SpearState" and v8 == "FireServer" then
                    local st, seq, tm = ...
                    if st == "charge" then
                        pcall(noteCharge, seq, tm)
                    end
                end

                if arg.ClassName == "RemoteEvent" and arg.Name == "Spearthrow" and _G.Ox.AimConfig.Aim_SilentVeilV2 and typeof((...)) == "table" then
                    local okAim, newPayload = pcall(veilAimPayload, (...))
                    if okAim and newPayload then
                        setnamecallmethod(v8)
                        return namecall(arg, newPayload)
                    end
                end

                if arg.ClassName == "RemoteEvent" and arg.Name == "Spearthrow" and _G.Ox.AimConfig.Aim_SilentVeilV2 and not flag2 and typeof((...)) ~= "table" then
                    local character = localPlayer.Character
                    local humanoidRootPart = character and character:FindFirstChild("HumanoidRootPart")
                    local v9 = character

                    if character then
                        local head = character:FindFirstChild("Head")
                        v9 = head or humanoidRootPart
                    end

                    local flag10 = character and character:GetAttribute("special") == true
                    local v10, v11

                    if flag10 then
                        local spearAuraSpeed = _G.Ox.AimConfig.SPEAR_AuraSpeed
                        local n4 = spearAuraSpeed or 165
                        v10 = n4
                        local spearAuraGravity = _G.Ox.AimConfig.SPEAR_AuraGravity
                        local n5 = spearAuraGravity or 96.5
                        v11 = n5
                    else
                        local spearSpeed = _G.Ox.AimConfig.SPEAR_Speed
                        local n4 = spearSpeed or 165
                        v10 = n4
                        local spearGravity = _G.Ox.AimConfig.SPEAR_Gravity
                        local n5 = spearGravity or 103
                        v11 = n5
                    end

                    local v12 = v10
                    local value = (select(3, ...))

                    if not (select(3, ...)) then
                        local spearSmartEnable = _G.Ox.Config.SpearSmart_enable
                        value = spearSmartEnable and humanoidRootPart and humanoidRootPart.Position
                    end

                    if not value then
                        value = v9 and v9.Position
                    end

                    local v13 = value
                    local n4 = (...)
                    local v14 = getClosestSurvivor()

                    if v14 and v13 then
                        local isModel = v14:IsA("Model")
                        local humanoidRootPart2 = isModel and v14:FindFirstChild("HumanoidRootPart") or v14
                        local position = humanoidRootPart2.Position
                        local vector = Vector3.new(0, 0, 0)
                        local parent = v14.Parent
                        local humanoid = parent and v14.Parent:FindFirstChildOfClass("Humanoid")

                        if humanoid and humanoid.MoveDirection.Magnitude > 0 then
                            vector = humanoid.MoveDirection * humanoid.WalkSpeed
                        elseif humanoidRootPart2:IsA("BasePart") then
                            vector = humanoidRootPart2.AssemblyLinearVelocity
                        end

                        local vector2 = Vector3.new(vector.X, 0, vector.Z)
                        local n5 = position - v13
                        local magnitude = n5.Magnitude
                        local magnitude2 = Vector3.new(n5.X, 0, n5.Z).Magnitude
                        local y = n5.Y

                        if magnitude > 0.1 then
                            local spearMaxDist = _G.Ox.AimConfig.SPEAR_MaxDist
                            local n6 = spearMaxDist or 1000

                            if magnitude <= n6 then
                                local lead = _G.Ox.AimConfig.Veil_LeadMultiplier or 1
                                local aim = position
                                local angle, flight = fn29(v10, v11, magnitude2, y)

                                if _G.Ox.Config.SpearSmart_enable and vector2.Magnitude > 0.5 then
                                    for _ = 1, 4 do
                                        aim = position + vector2 * (math.min(flight, 4) * lead)
                                        local d = aim - v13
                                        angle, flight = fn29(v10, v11, Vector3.new(d.X, 0, d.Z).Magnitude, d.Y)
                                    end
                                end

                                local d = aim - v13
                                local flat = Vector3.new(d.X, 0, d.Z)

                                if flat.Magnitude > 0.001 then
                                    n4 = flat.Unit * math.cos(angle) + Vector3.new(0, math.sin(angle), 0)
                                else
                                    n4 = d.Unit
                                end
                            end
                        end
                    end

                    flag2 = true

                    pcall(function()
                        if spearthrow then
                            spearthrow:FireServer(n4, v12, v13)
                        else
                            arg:FireServer(n4, v12, v13)
                        end
                    end)

                    flag2 = false
                    return
                end
            end

            return namecall(arg, ...)
        end)

        setreadonly(v7, true)
        flag3 = true
    end

    local function fn29()
        local remotes = ReplicatedStorage:FindFirstChild("Remotes")
        local items = remotes and ReplicatedStorage.Remotes:FindFirstChild("Items")
        local flashlight = items and items:FindFirstChild("Flashlight")

        if flashlight then
            _G.Ox.GotBlindedRemote = flashlight:FindFirstChild("GotBlinded")
        end
    end

    task.spawn(function()
        task.wait(1)
        fn29()
        setupSpearInterceptor()
    end)

    localPlayer.CharacterAdded:Connect(function()
        task.wait(1)
        fn29()
    end)
end

local tbl5, fn13, fn14, fn15, fn16, fn17, fn18, fn19, fn20, fn21, fn22

do
    local v3 = Connections
    tbl5 = v3 or {}

    EnableInfiniteLunge = function()
        _G.Ox.InfiniteLungeEnabled = true
        local character = localPlayer.Character

        if character then
            character:SetAttribute("lungeboost", 999)

            if _G.Ox.InfLungeAttrConn then
                _G.Ox.InfLungeAttrConn:Disconnect()
            end

            _G.Ox.InfLungeAttrConn = character:GetAttributeChangedSignal("lungeboost"):Connect(function()
                if _G.Ox.InfiniteLungeEnabled and character:GetAttribute("lungeboost") ~= 999 then
                    character:SetAttribute("lungeboost", 999)
                end
            end)
        end

    end

    DisableInfiniteLunge = function()
        _G.Ox.InfiniteLungeEnabled = false

        if _G.Ox.InfLungeAttrConn then
            _G.Ox.InfLungeAttrConn:Disconnect()
            _G.Ox.InfLungeAttrConn = nil
        end

        local character = localPlayer.Character

        if character then
            character:SetAttribute("lungeboost", 1)
        end

    end

    localPlayer.CharacterAdded:Connect(function(character)
        task.wait(0.8)

        if _G.Ox.InfiniteLungeEnabled and character then
            character:SetAttribute("lungeboost", 999)
        end
    end)

    StopCounterParry = function()
        _G.Ox.CounterParry.Enabled = false

        if _G.Ox.CounterParry.Thread then
            task.cancel(_G.Ox.CounterParry.Thread)
            _G.Ox.CounterParry.Thread = nil
        end

        if _G.Ox.CounterParry.Track then
            pcall(function()
                _G.Ox.CounterParry.Track:Stop()
            end)

            _G.Ox.CounterParry.Track = nil
        end
    end

    StartCounterParry = function()
        if _G.Ox.CounterParry.Thread then
            return
        end

        _G.Ox.CounterParry.Thread = task.spawn(function()
            local character, humanoid, animator, humanoidRootPart, animation, ok, track, flag3, distance, v4, v5, v6, v7, v8, v9, character2, humanoidRootPart2, n
            n = 1

            while true do
                if n == 1 then
                    if _G.Ox.CounterParry.Enabled and _G.Ox.ScriptAlive then
                        n = 3
                    else
                        n = 2
                    end
                elseif n == 2 then
                    _G.Ox.CounterParry.Thread = nil
                    return
                elseif n == 3 then
                    character = localPlayer.Character

                    if character and character.Parent and GetRole() == "Killer" then
                        n = 5
                    else
                        n = 4
                    end
                elseif n == 4 then
                    task.wait(0.4)
                    n = 1
                elseif n == 5 then
                    humanoid = character:FindFirstChildOfClass("Humanoid")
                    animator = humanoid

                    if humanoid then
                        n = 6
                    else
                        n = 7
                    end
                elseif n == 6 then
                    animator = humanoid:FindFirstChildOfClass("Animator")
                    n = 7
                elseif n == 7 then
                    humanoidRootPart = character:FindFirstChild("HumanoidRootPart")

                    if animator and humanoidRootPart then
                        n = 9
                    else
                        n = 8
                    end
                elseif n == 8 then
                    task.wait(0.3)
                    n = 1
                elseif n == 9 then
                    if _G.Ox.CounterParry.Track and _G.Ox.CounterParry.Track.Parent ~= nil then
                        n = 13
                    else
                        n = 10
                    end
                elseif n == 10 then
                    animation = Instance.new("Animation")
                    animation.AnimationId = _G.Ox.CounterParry.AnimId

                    ok, track = pcall(function()
                        return animator:LoadAnimation(animation)
                    end)

                    if ok and track then
                        n = 12
                    else
                        n = 11
                    end
                elseif n == 11 then
                    task.wait(0.5)
                    n = 1
                elseif n == 12 then
                    _G.Ox.CounterParry.Track = track
                    n = 13
                elseif n == 13 then
                    flag3 = false
                    distance = _G.Ox.CounterParry.Distance
                    v4, v5, v6 = ipairs(Players:GetPlayers())
                    v7 = v6
                    n = 14
                elseif n == 14 then
                    v8, v9 = v4(v5, v7)

                    if v8 == nil then
                        n = 20
                    else
                        n = 15
                    end
                elseif n == 15 then
                    v7 = v8

                    if v9 ~= localPlayer and v9.Team and v9.Team.Name == "Survivors" then
                        n = 16
                    else
                        n = 14
                    end
                elseif n == 16 then
                    character2 = v9.Character
                    humanoidRootPart2 = character2

                    if character2 then
                        n = 17
                    else
                        n = 18
                    end
                elseif n == 17 then
                    humanoidRootPart2 = v9.Character:FindFirstChild("HumanoidRootPart")
                    n = 18
                elseif n == 18 then
                    if humanoidRootPart2 and (humanoidRootPart.Position - humanoidRootPart2.Position).Magnitude <= distance then
                        n = 19
                    else
                        n = 14
                    end
                elseif n == 19 then
                    flag3 = true
                    n = 20
                elseif n == 20 then
                    if flag3 and _G.Ox.CounterParry.Track then
                        n = 21
                    else
                        n = 22
                    end
                elseif n == 21 then
                    pcall(function()
                        _G.Ox.CounterParry.Track:Play()
                        _G.Ox.CounterParry.Track:AdjustWeight(0)
                    end)

                    task.wait(0.05)

                    pcall(function()
                        _G.Ox.CounterParry.Track:Stop()
                    end)

                    n = 22
                elseif n == 22 then
                    task.wait(_G.Ox.CounterParry.Interval)
                    n = 1
                end
            end
        end)
    end

    ToggleCounterParry = function(arg)
        if arg then
            if GetRole() ~= "Killer" then

                _G.Ox.CounterParry.Enabled = false

                if CounterParryToggle then
                    fn(CounterParryToggle, false)
                end

                return
            end

            _G.Ox.CounterParry.Enabled = true
            StartCounterParry()

        else
            StopCounterParry()

        end
    end

    localPlayer.CharacterAdded:Connect(function()
        _G.Ox.CounterParry.Track = nil
        task.wait(1)

        if _G.Ox.CounterParry.Enabled then
            StartCounterParry()
        end
    end)

    _G.Ox.killerAimbotHighlight = Instance.new("Highlight")
    _G.Ox.killerAimbotHighlight.Name = "KillerAimbotTarget"
    _G.Ox.killerAimbotHighlight.FillColor = Color3.fromRGB(255, 0, 0)
    _G.Ox.killerAimbotHighlight.OutlineColor = Color3.fromRGB(255, 255, 0)
    _G.Ox.killerAimbotHighlight.FillTransparency = 0.4
    _G.Ox.killerAimbotHighlight.OutlineTransparency = 0.2

    StopMoonwalk = function()
        _G.Ox.Moonwalk.Enabled = false
        local character = localPlayer.Character
        local humanoid = character and character:FindFirstChildOfClass("Humanoid")

        if humanoid then
            humanoid.AutoRotate = true
        end
    end

    StartMoonwalk = function()
        local character = localPlayer.Character
        local humanoidRootPart = character and character:FindFirstChild("HumanoidRootPart")
        local humanoid = character and character:FindFirstChildOfClass("Humanoid")
        if not humanoidRootPart or not humanoid then
            return
        end
        humanoid.AutoRotate = false
        _G.Ox.Moonwalk.Enabled = true
    end

    UpdateMoonwalkGUI = function(arg)
        if not _G.Ox.Moonwalk.Gui then
            return
        end
        local frame2 = _G.Ox.Moonwalk.Gui:FindFirstChild("Frame")
        if not frame2 then
            return
        end
        local actionButton = frame2:FindFirstChild("ActionButton")
        local uiStroke3 = frame2:FindFirstChild("UIStroke")

        if arg then
            if actionButton then
                actionButton.Text = "MOON [ON]"
                actionButton.TextColor3 = Color3.fromRGB(180, 255, 180)
                actionButton.BackgroundColor3 = Color3.fromRGB(40, 40, 45)
            end

            if uiStroke3 then
                uiStroke3.Color = Color3.fromRGB(100, 200, 100)
            end
        else
            if actionButton then
                actionButton.Text = "MOON [OFF]"
                actionButton.TextColor3 = Color3.fromRGB(200, 200, 200)
                actionButton.BackgroundColor3 = Color3.fromRGB(30, 30, 35)
            end

            if uiStroke3 then
                uiStroke3.Color = Color3.fromRGB(90, 90, 95)
            end
        end
    end

    ToggleMoonwalkStatus = function()
        if _G.Ox.Moonwalk.Enabled then
            StopMoonwalk()
        else
            StartMoonwalk()
        end

        _G.Ox.Moonwalk.IsActive = _G.Ox.Moonwalk.Enabled
        UpdateMoonwalkGUI(_G.Ox.Moonwalk.Enabled)

        if MoonwalkPCToggle then
            fn(MoonwalkPCToggle, _G.Ox.Moonwalk.Enabled)
        end

    end

    CreateMoonwalkGUI = function()
        if _G.Ox.Moonwalk.Gui then
            _G.Ox.Moonwalk.Gui:Destroy()
        end

        local screenGui2 = Instance.new("ScreenGui")
        screenGui2.Name = "MoonwalkCustomGui"
        screenGui2.ResetOnSpawn = false
        screenGui2.IgnoreGuiInset = true
        screenGui2.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
        screenGui2.Parent = CoreGui
        screenGui2.Enabled = false
        _G.Ox.Moonwalk.Gui = screenGui2
        _G.Ox.Moonwalk.GuiVisible = false
        local frame2 = Instance.new("Frame", screenGui2)
        frame2.Name = "Frame"
        frame2.Size = UDim2.fromOffset(110, 36)
        frame2.Position = UDim2.fromScale(0.85, 0.45)
        frame2.BackgroundColor3 = Color3.fromRGB(25, 25, 30)
        frame2.BackgroundTransparency = 0.1
        frame2.Active = true
        frame2.BorderSizePixel = 0
        Instance.new("UICorner", frame2).CornerRadius = UDim.new(0, 8)
        local uiStroke3 = Instance.new("UIStroke", frame2)
        uiStroke3.Name = "UIStroke"
        uiStroke3.Color = Color3.fromRGB(90, 90, 95)
        uiStroke3.Thickness = 1.5
        uiStroke3.Transparency = 0.2
        local textButton = Instance.new("TextButton", frame2)
        textButton.Name = "ActionButton"
        textButton.Size = UDim2.new(1, 0, 1, 0)
        textButton.Text = "MOON [OFF]"
        textButton.BackgroundColor3 = Color3.fromRGB(30, 30, 35)
        textButton.Font = Enum.Font.GothamBold
        textButton.TextSize = 12
        textButton.TextColor3 = Color3.fromRGB(200, 200, 200)
        textButton.BorderSizePixel = 0
        textButton.AutoButtonColor = false
        Instance.new("UICorner", textButton).CornerRadius = UDim.new(0, 8)
        local flag3 = false
        local flag4 = false
        local flag5 = false
        local position = nil
        local position2 = nil
        local thread = nil

        local function fn29(arg)
            if not flag3 or not flag5 or not position or not position2 then
                return
            end
            local n = arg.Position - position

            if not flag4 and (math.abs(n.X) > 18 or math.abs(n.Y) > 18) then
                flag4 = true
            end

            if flag4 then
                frame2.Position = UDim2.new(position2.X.Scale, position2.X.Offset + n.X, position2.Y.Scale, position2.Y.Offset + n.Y)
            end
        end

        textButton.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                flag3 = true
                flag4 = false
                flag5 = false
                position = input.Position
                position2 = frame2.Position

                if thread then
                    task.cancel(thread)
                end

                thread = task.delay(0.18, function()
                    if flag3 then
                        flag5 = true
                    end
                end)
            end
        end)

        textButton.InputEnded:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                if thread then
                    task.cancel(thread)
                end

                if flag3 and not flag4 then
                    ToggleMoonwalkStatus()
                end

                flag3 = false
                flag4 = false
                flag5 = false
                position = nil
                position2 = nil
            end
        end)

        UserInputService.InputChanged:Connect(function(input)
            if flag3 and flag5 and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
                fn29(input)
            end
        end)

        if _G.Ox.Moonwalk._statusConn then
            _G.Ox.Moonwalk._statusConn:Disconnect()
        end

        _G.Ox.Moonwalk._statusConn = RunService.Heartbeat:Connect(function()
            if _G.Ox.Moonwalk.Gui and _G.Ox.Moonwalk.Gui.Parent then
                if _G.Ox.Moonwalk.IsActive ~= _G.Ox.Moonwalk.Enabled then
                    _G.Ox.Moonwalk.IsActive = _G.Ox.Moonwalk.Enabled
                    UpdateMoonwalkGUI(_G.Ox.Moonwalk.Enabled)
                end

                return
            end

            if _G.Ox.Moonwalk._statusConn then
                _G.Ox.Moonwalk._statusConn:Disconnect()
            end
        end)
    end

    localPlayer.CharacterAdded:Connect(function()
        task.wait(1)

        if _G.Ox.Moonwalk.Enabled then
            StartMoonwalk()
        end

        if _G.Ox.Moonwalk.GuiVisible and _G.Ox.Moonwalk.Gui then
            _G.Ox.Moonwalk.Gui.Enabled = true
            UpdateMoonwalkGUI(_G.Ox.Moonwalk.Enabled)
        end
    end)

    task.spawn(function()
        task.wait(1.5)
        CreateMoonwalkGUI()
    end)

    RunService.RenderStepped:Connect(function(deltaTime)
        if not _G.Ox.Speed.Enabled and not _G.Ox.Moonwalk.Enabled and not _G.Ox.Crosshair.Enabled and not _G.Ox.StretchRes.Enabled and (not _G.Ox.Config.Killer_Aimbot_Enabled or not _G.Ox.isKillerAimbotHolding) and not _G.Ox.AimConfig.Aim_SilentVeilV2 and (not flag or not _G.Ox.AimConfig.Flash_Silent) then
            return
        end

        if _G.Ox.Crosshair.Enabled then
            DrawCrosshair()
        end

        if _G.Ox.Speed.Enabled then
            local character = localPlayer.Character

            if character then
                local humanoid = character:FindFirstChildOfClass("Humanoid")

                if humanoid then
                    local moveDirection = humanoid.MoveDirection

                    if moveDirection.Magnitude > 0 then
                        local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")

                        if humanoidRootPart then
                            local n = (_G.Ox.Speed.Value - 0.1) * 10

                            if n > 0 then
                                humanoidRootPart.CFrame = humanoidRootPart.CFrame + moveDirection * n * deltaTime
                            end
                        end
                    end
                end
            end
        end

        if _G.Ox.Moonwalk.Enabled then
            local character = localPlayer.Character
            local humanoidRootPart = character and character:FindFirstChild("HumanoidRootPart")
            local humanoid = character and character:FindFirstChildOfClass("Humanoid")
            local currentCamera2 = workspace.CurrentCamera

            if humanoidRootPart and humanoid and currentCamera2 then
                if humanoid.AutoRotate ~= false then
                    humanoid.AutoRotate = false
                end

                local vector = Vector3.new(currentCamera2.CFrame.LookVector.X, 0, currentCamera2.CFrame.LookVector.Z)
                local unit = vector
                local vector2 = Vector3.new(currentCamera2.CFrame.RightVector.X, 0, currentCamera2.CFrame.RightVector.Z)
                local unit2 = vector2

                if vector.Magnitude > 0.001 then
                    unit = vector.Unit
                end

                if vector2.Magnitude > 0.001 then
                    unit2 = vector2.Unit
                end

                local v5 = math.sin(tick() * 35)
                local n = CFrame.Angles(0, math.rad(30 * v5), 0) * unit
                humanoidRootPart.CFrame = CFrame.lookAt(humanoidRootPart.Position, humanoidRootPart.Position + n)
                humanoid:Move(-unit * 1.2 + unit2 * (v5 * 1.05), false)
            end
        end

        if _G.Ox.StretchRes.Enabled and currentCamera then
            currentCamera.CFrame = currentCamera.CFrame * CFrame.new(0, 0, 0, 1, 0, 0, 0, _G.Ox.StretchRes.Amount, 0, 0, 0, 1)
        end

        if flag and _G.Ox.AimConfig.Flash_Silent then
            local v5 = getKillerTargetForFlash()

            if v5 then
                local character = localPlayer.Character
                local humanoidRootPart = character and character:FindFirstChild("HumanoidRootPart")
                local n = v5.Position + Vector3.new(0, _G.Ox.AimConfig.Flash_YOffset, 0)
                local currentCamera2 = workspace.CurrentCamera
                currentCamera2.CFrame = currentCamera2.CFrame:Lerp(CFrame.lookAt(currentCamera2.CFrame.Position, n), 0.5)

                if humanoidRootPart then
                    local cframe = CFrame.lookAt(humanoidRootPart.Position, Vector3.new(n.X, humanoidRootPart.Position.Y, n.Z))
                    humanoidRootPart.CFrame = humanoidRootPart.CFrame:Lerp(cframe, 0.5)
                end
            end
        end

        if _G.Ox.Config.Killer_Aimbot_Enabled and _G.Ox.isKillerAimbotHolding then
            if GetRole() == "Killer" then
                if _G.Ox.lockedKillerAimbotTarget then
                    local parent = _G.Ox.lockedKillerAimbotTarget.Parent
                    local humanoid = parent and parent:FindFirstChild("Humanoid")

                    if not humanoid or humanoid.Health <= 0 or IsDowned(parent) then
                        _G.Ox.lockedKillerAimbotTarget = getBestKillerAimbotTarget()
                    end

                    if _G.Ox.lockedKillerAimbotTarget then
                        local position = _G.Ox.lockedKillerAimbotTarget.Position
                        local v5 = GetDistance(position)

                        if _G.Ox.Config.Killer_Aimbot_MaxDist < v5 then
                            _G.Ox.lockedKillerAimbotTarget = getBestKillerAimbotTarget()
                        else
                            _G.Ox.killerAimbotHighlight.Parent = parent
                            -- Best Smooth: frame-rate independent easing; off = hard lock
                            local alpha = _G.Ox.Config.Killer_Aimbot_BestSmooth and (1 - math.exp(-deltaTime * 14)) or 1
                            local cframe = CFrame.new(currentCamera.CFrame.Position, position)
                            currentCamera.CFrame = currentCamera.CFrame:Lerp(cframe, alpha)
                            local character = localPlayer.Character
                            local humanoidRootPart = character and character:FindFirstChild("HumanoidRootPart")

                            if humanoidRootPart then
                                local cframe2 = CFrame.new(humanoidRootPart.Position, Vector3.new(position.X, humanoidRootPart.Position.Y, position.Z))
                                -- rotate only: the position is never touched
                                local current = humanoidRootPart.CFrame
                                local turned = current:Lerp(cframe2, alpha)
                                humanoidRootPart.CFrame = CFrame.new(current.Position) * (turned - turned.Position)
                            end
                        end
                    end
                else
                    _G.Ox.lockedKillerAimbotTarget = getBestKillerAimbotTarget()
                end
            end
        elseif _G.Ox.killerAimbotHighlight then
            _G.Ox.killerAimbotHighlight.Parent = nil
        end

    end)

    local n = 0

    RunService.Heartbeat:Connect(function()
        if _G.Ox.ParryConfig.ParryCircle and _G.Ox.ParryConfig.AutoParry then
            local character = localPlayer.Character
            local humanoidRootPart = character and character:FindFirstChild("HumanoidRootPart")

            if humanoidRootPart then
                if not _G.Ox.State.AutoParryAdornment or _G.Ox.State.AutoParryAdornment.Parent ~= humanoidRootPart then
                    if _G.Ox.State.AutoParryAdornment then
                        _G.Ox.State.AutoParryAdornment:Destroy()
                    end

                    _G.Ox.State.AutoParryAdornment = Instance.new("CylinderHandleAdornment")
                    _G.Ox.State.AutoParryAdornment.Name = "AutoParryCircleESP"
                    _G.Ox.State.AutoParryAdornment.Height = 0.05
                    _G.Ox.State.AutoParryAdornment.Transparency = 0.3
                    _G.Ox.State.AutoParryAdornment.Adornee = humanoidRootPart
                    _G.Ox.State.AutoParryAdornment.Parent = humanoidRootPart
                    _G.Ox.State.AutoParryAdornment.ZIndex = 0
                    _G.Ox.State.AutoParryAdornment.AlwaysOnTop = false
                end

                local parryRadius = _G.Ox.ParryConfig.ParryRadius
                _G.Ox.State.AutoParryAdornment.Radius = parryRadius
                _G.Ox.State.AutoParryAdornment.InnerRadius = math.max(0.1, parryRadius - 0.15)
                _G.Ox.State.AutoParryAdornment.CFrame = CFrame.new(0, -3, 0) * CFrame.Angles(math.rad(90), 0, 0)

                if _G.Ox.State.ParryCooldown then
                    _G.Ox.State.AutoParryAdornment.Color3 = Color3.fromRGB(255, 128, 0)
                elseif _G.Ox.ParryConfig.ParryAggressive then
                    _G.Ox.State.AutoParryAdornment.Color3 = Color3.fromRGB(255, 0, 0)
                else
                    _G.Ox.State.AutoParryAdornment.Color3 = Color3.fromRGB(255, 255, 255)
                end
            elseif _G.Ox.State.AutoParryAdornment then
                _G.Ox.State.AutoParryAdornment:Destroy()
                _G.Ox.State.AutoParryAdornment = nil
            end
        elseif _G.Ox.State.AutoParryAdornment then
            _G.Ox.State.AutoParryAdornment:Destroy()
            _G.Ox.State.AutoParryAdornment = nil
        end

        if _G.Ox.GodMode then
            local character = localPlayer.Character

            if character then
                local humanoid = character:FindFirstChildOfClass("Humanoid")

                if humanoid and humanoid.Health < humanoid.MaxHealth then
                    humanoid.Health = humanoid.MaxHealth
                end
            end
        end

        if _G.Ox.AutoPallet.Enabled then
            for k in pairs(_G.Ox.AutoPallet.UsedPallets) do
                if not k or not k.Parent then
                    _G.Ox.AutoPallet.UsedPallets[k] = nil
                end
            end
        end

        if _G.Ox.CameraFOV.Enabled then
            currentCamera.FieldOfView = _G.Ox.CameraFOV.Value
        end

        if _G.Ox.NoSlowdownEnabled then
            local character = localPlayer.Character

            if character then
                local humanoid = character:FindFirstChildOfClass("Humanoid")

                if humanoid and GetRole() == "Killer" and humanoid.WalkSpeed < 16 then
                    humanoid.WalkSpeed = 16
                end
            end
        end

        if _G.Ox.ESPConfig.Master and tick() - n >= 2 then
            n = tick()
            UpdatePlayerESP()
            UpdateSCPESP()
            UpdateStaticESP()
        end
    end)

    local items = ReplicatedStorage:WaitForChild("Items", 5)

    extractAssetId = function(arg)
        return tostring(arg):match("%d+")
    end

    getItemIcon = function(arg)
        if not items then
            return nil
        end
        local v5 = items:FindFirstChild(arg)
        if not v5 then
            return nil
        end
        local v6 = nil

        pcall(function()
            local texture = v5.Texture
            local image = texture or v5.Image
            v6 = image
        end)

        if v6 and v6 ~= "" then
            local v7 = extractAssetId(v6)
            if v7 then
                return string.format("rbxthumb://type=Asset&id=%s&w=420&h=420", v7)
            end
        end

        return nil
    end

    CreateModernESP = function(parent, name, arg)
        if not parent then
            return
        end
        local name2 = arg.name
        local str = name2 or ""
        local flag3 = str ~= ""
        local flag4 = name ~= "PE_Text"

        if not flag4 then
            if flag3 then
                flag4 = false
            else
                flag4 = true
            end
        end

        local str2 = flag4 and "single" or "multi"
        local infoRich = arg.infoRich
        local text = infoRich or ""

        if text == "" then
            local tbl6 = {}

            if arg.subtext and arg.subtext ~= "" then
                table.insert(tbl6, tostring(arg.subtext))
            end

            if arg.distance then
                table.insert(tbl6, tostring(arg.distance) .. "m")
            end

            text = table.concat(tbl6, " <font color=\"#888888\">·</font> ")
        end

        local v5 = parent:FindFirstChild(name)
        local v6 = v5

        if v5 and v5:GetAttribute("Layout") ~= str2 then
            v5:Destroy()
            v6 = nil
        end

        if not v6 then
            local billboardGui = Instance.new("BillboardGui")
            v6 = billboardGui
            billboardGui.Name = name
            billboardGui.AlwaysOnTop = true
            billboardGui:SetAttribute("Layout", str2)
            local udim2 = flag4 and UDim2.new(0, 220, 0, 22) or UDim2.new(0, 220, 0, 34)
            billboardGui.Size = udim2
            local vector = Vector3.new
            local offsetY = arg.offsetY
            local n2 = offsetY or 4
            billboardGui.StudsOffset = vector(0, n2, 0)
            billboardGui.Parent = parent
            local frame2 = Instance.new("Frame")
            frame2.Name = "Box"
            frame2.BackgroundTransparency = 1
            frame2.Size = UDim2.new(1, 0, 1, 0)
            frame2.AnchorPoint = Vector2.new(0.5, 0.5)
            frame2.Position = UDim2.new(0.5, 0, 0.5, 0)
            frame2.Parent = billboardGui

            if arg.noDistScale then
                billboardGui:SetAttribute("NoDistScale", true)
            else
                local uiScale = Instance.new("UIScale")
                uiScale.Name = "DistScale"
                uiScale.Scale = 1
                uiScale.Parent = frame2
            end

            if flag4 then
                local uiListLayout = Instance.new("UIListLayout", frame2)
                uiListLayout.FillDirection = Enum.FillDirection.Horizontal
                uiListLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
                uiListLayout.VerticalAlignment = Enum.VerticalAlignment.Center
                uiListLayout.Padding = UDim.new(0, 4)
                local imageLabel = Instance.new("ImageLabel")
                imageLabel.Name = "Icon"
                imageLabel.BackgroundTransparency = 1
                imageLabel.Size = UDim2.new(0, 14, 0, 14)
                imageLabel.Visible = false
                imageLabel.Parent = frame2
                local textLabel = Instance.new("TextLabel")
                textLabel.Name = "Text"
                textLabel.BackgroundTransparency = 1
                textLabel.AutomaticSize = Enum.AutomaticSize.XY
                textLabel.Font = Enum.Font.GothamBold
                textLabel.TextSize = 12
                textLabel.TextWrapped = false
                textLabel.TextYAlignment = Enum.TextYAlignment.Center
                textLabel.RichText = true
                textLabel.TextStrokeTransparency = 0
                textLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
                textLabel.Parent = frame2
            else
                local uiListLayout = Instance.new("UIListLayout", frame2)
                uiListLayout.FillDirection = Enum.FillDirection.Vertical
                uiListLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
                uiListLayout.VerticalAlignment = Enum.VerticalAlignment.Center
                uiListLayout.Padding = UDim.new(0, 0)
                local frame3 = Instance.new("Frame")
                frame3.Name = "Row1"
                frame3.BackgroundTransparency = 1
                frame3.AutomaticSize = Enum.AutomaticSize.XY
                frame3.Size = UDim2.new(0, 0, 0, 16)
                frame3.Parent = frame2
                local uiListLayout2 = Instance.new("UIListLayout", frame3)
                uiListLayout2.FillDirection = Enum.FillDirection.Horizontal
                uiListLayout2.HorizontalAlignment = Enum.HorizontalAlignment.Center
                uiListLayout2.VerticalAlignment = Enum.VerticalAlignment.Center
                uiListLayout2.Padding = UDim.new(0, 4)
                local imageLabel = Instance.new("ImageLabel")
                imageLabel.Name = "Icon"
                imageLabel.BackgroundTransparency = 1
                imageLabel.Size = UDim2.new(0, 14, 0, 14)
                imageLabel.Visible = false
                imageLabel.Parent = frame3
                local textLabel = Instance.new("TextLabel")
                textLabel.Name = "Name"
                textLabel.BackgroundTransparency = 1
                textLabel.AutomaticSize = Enum.AutomaticSize.XY
                textLabel.Font = Enum.Font.GothamBold
                textLabel.TextSize = 12
                textLabel.TextWrapped = false
                textLabel.TextYAlignment = Enum.TextYAlignment.Center
                textLabel.TextStrokeTransparency = 0
                textLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
                textLabel.Parent = frame3
                local textLabel2 = Instance.new("TextLabel")
                textLabel2.Name = "Info"
                textLabel2.BackgroundTransparency = 1
                textLabel2.AutomaticSize = Enum.AutomaticSize.XY
                textLabel2.Font = Enum.Font.GothamBold
                textLabel2.TextSize = 11
                textLabel2.TextWrapped = false
                textLabel2.TextYAlignment = Enum.TextYAlignment.Center
                textLabel2.RichText = true
                textLabel2.TextStrokeTransparency = 0
                textLabel2.TextStrokeColor3 = Color3.new(0, 0, 0)
                textLabel2.Parent = frame2
            end
        end

        local box = v6:FindFirstChild("Box")

        if flag4 then
            local text2 = box and box:FindFirstChild("Text")
            local icon = box and box:FindFirstChild("Icon")

            if text2 then
                local str3 = "#FFFFFF"

                if arg.color then
                    str3 = string.format("#%02X%02X%02X", math.floor(arg.color.R * 255), math.floor(arg.color.G * 255), math.floor(arg.color.B * 255))
                end

                local v7 = tostring
                local str4 = str or ""
                local str5 = v7(str4):gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;")
                local text3 = ""

                if flag3 then
                    text3 = string.format("<font color=\"%s\">%s</font>", str3, str5)
                end

                if text ~= "" then
                    if text3 == "" then
                        text3 = text
                    elseif arg.noSeparator then
                        text3 = text3 .. " " .. text
                    else
                        text3 = text3 .. " <font color=\"#888888\">·</font> " .. text
                    end
                end

                text2.Text = text3
            end

            if icon then
                if arg.icon and arg.icon ~= "" then
                    icon.Image = arg.icon
                    icon.Visible = true
                else
                    icon.Visible = false
                end
            end
        else
            local row1 = box and box:FindFirstChild("Row1")
            local name3 = row1 and row1:FindFirstChild("Name")
            local icon = row1 and row1:FindFirstChild("Icon")
            local info = box and box:FindFirstChild("Info")

            if name3 then
                name3.Text = tostring(str):gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;")
                local color = arg.color
                local color2 = color or Color3.new(1, 1, 1)
                name3.TextColor3 = color2
            end

            if icon then
                if arg.icon and arg.icon ~= "" then
                    icon.Image = arg.icon
                    icon.Visible = true
                else
                    icon.Visible = false
                end
            end

            if info then
                if text == "" then
                    info.Visible = false
                else
                    info.Visible = true
                    info.Text = text
                end
            end
        end
    end

    local function fn29()
        local team = localPlayer.Team
        local flag3 = team and localPlayer.Team.Name == "Survivors"
        return flag3
    end

    local function perkBoost(char, key, mult, secs, alive)
        local ok, SS = pcall(function() return require(game:GetService("ReplicatedStorage").Modules.SpeedService) end)
        if ok and type(SS) == "table" and SS.set then
            pcall(SS.set, char, key, mult)
            local t0 = tick()
            while alive() and tick() - t0 < secs and char and char.Parent do task.wait(0.1) end
            pcall(SS.clear, char, key)
        else
            local t0 = tick()
            while alive() and tick() - t0 < secs and char and char.Parent do
                char:SetAttribute("speedboost", mult)
                task.wait()
            end
            if char and char.Parent then char:SetAttribute("speedboost", 1) end
        end
    end

    local function fn30(arg)
        local humanoid = arg:FindFirstChildOfClass("Humanoid")
        if not humanoid then
            return false
        end
        local animator = humanoid:FindFirstChildOfClass("Animator")
        if not animator then
            return false
        end

        for i, v5 in ipairs(animator:GetPlayingAnimationTracks()) do
            if v5.Animation and string.find(tostring(v5.Animation.AnimationId), "126081405469607") then
                return true
            end
        end

        return false
    end

    local function fn31(arg)
        if not _G.Ox.FakePerks.QuickRecoveryEnabled then
            return
        end

        if not fn29() then
            return
        end

        if _G.Ox.FakePerks.boostActive then
            return
        end

        if tick() - _G.Ox.FakePerks.lastQRTime < _G.Ox.FakePerks.PerkCooldown then
            return
        end
        _G.Ox.FakePerks.boostActive = true
        _G.Ox.FakePerks.lastQRTime = tick()
        local now = tick()

        task.spawn(function()
            perkBoost(arg, "MeowX_Perk1", 1.4, 3, function() return _G.Ox.FakePerks.QuickRecoveryEnabled end)

            _G.Ox.FakePerks.boostActive = false
        end)
    end

    local function fn32(arg)
        if _G.Ox.FakePerks.qrConnection then
            _G.Ox.FakePerks.qrConnection:Disconnect()
            _G.Ox.FakePerks.qrConnection = nil
        end

        if not arg then
            return
        end

        _G.Ox.FakePerks.qrConnection = arg:GetAttributeChangedSignal("isvaulting"):Connect(function()
            if arg:GetAttribute("isvaulting") == true then
                task.spawn(function()
                    task.wait(0.05)
                    local v5 = fn30(arg)
                    local v6 = v5

                    if not v5 then
                        task.wait(0.05)
                        v6 = fn30(arg)
                    end

                    if not v6 and arg:GetAttribute("isvaulting") == true then
                        fn31(arg)
                    end
                end)
            end
        end)
    end

    ToggleQuickRecovery = function(quickRecoveryEnabled)
        _G.Ox.FakePerks.QuickRecoveryEnabled = quickRecoveryEnabled

        if quickRecoveryEnabled and localPlayer.Character then
            fn32(localPlayer.Character)
        elseif not quickRecoveryEnabled and _G.Ox.FakePerks.qrConnection then
            _G.Ox.FakePerks.qrConnection:Disconnect()
            _G.Ox.FakePerks.qrConnection = nil
        end

    end

    local function fn33(arg)
        if not _G.Ox.FakePerks.PerfectLandingEnabled then
            return
        end

        if not fn29() then
            return
        end

        if _G.Ox.FakePerks.perfectLandingBoostActive then
            return
        end

        if tick() - _G.Ox.FakePerks.lastPLTime < _G.Ox.FakePerks.PerkCooldown then
            return
        end
        _G.Ox.FakePerks.perfectLandingBoostActive = true
        _G.Ox.FakePerks.lastPLTime = tick()
        local now = tick()

        task.spawn(function()
            perkBoost(arg, "MeowX_Perk2", 1.4, 3, function() return _G.Ox.FakePerks.perfectLandingBoostActive end)

            _G.Ox.FakePerks.perfectLandingBoostActive = false
        end)
    end

    local function fn34(arg)
        if _G.Ox.FakePerks.plConnection then
            _G.Ox.FakePerks.plConnection:Disconnect()
            _G.Ox.FakePerks.plConnection = nil
        end

        if not arg then
            return
        end

        _G.Ox.FakePerks.plConnection = arg:GetAttributeChangedSignal("speedboost"):Connect(function()
            if not fn29() then
                return
            end

            if arg:GetAttribute("speedboost") == 0.625 then
                fn33(arg)
            end
        end)
    end

    TogglePerfectLanding = function(perfectLandingEnabled)
        _G.Ox.FakePerks.PerfectLandingEnabled = perfectLandingEnabled

        if perfectLandingEnabled then
            if localPlayer.Character then
                fn34(localPlayer.Character)
            end
        else
            if _G.Ox.FakePerks.plConnection then
                _G.Ox.FakePerks.plConnection:Disconnect()
                _G.Ox.FakePerks.plConnection = nil
            end

            if _G.Ox.FakePerks.perfectLandingBoostActive and localPlayer.Character then
                localPlayer.Character:SetAttribute("speedboost", 1)
                _G.Ox.FakePerks.perfectLandingBoostActive = false
            end
        end

    end

    local function fn35(arg)
        if _G.Ox.FakePerks.fsConnection then
            _G.Ox.FakePerks.fsConnection:Disconnect()
            _G.Ox.FakePerks.fsConnection = nil
        end

        if _G.Ox.FakePerks.fsAnimConnection then
            _G.Ox.FakePerks.fsAnimConnection:Disconnect()
            _G.Ox.FakePerks.fsAnimConnection = nil
        end

        if not arg then
            return
        end
        local humanoid = arg:WaitForChild("Humanoid", 3)
        if not humanoid then
            return
        end
        local animator = humanoid:WaitForChild("Animator", 3)
        if not animator then
            return
        end

        _G.Ox.FakePerks.fsAnimConnection = animator.AnimationPlayed:Connect(function(arg2)
            if not arg2.Animation then
                return
            end

            if arg2.Animation.AnimationId ~= "rbxassetid://136962284480779" then
                return
            end
            local connection = nil

            connection = arg2.Stopped:Connect(function()
                if connection then
                    connection:Disconnect()
                end

                _G.Ox.FakePerks.lastFSTime = tick()
                _G.Ox.FakePerks.fsOnCooldown = true

                if arg and arg.Parent then
                    arg:SetAttribute("Flowstate", false)
                end

                task.delay(_G.Ox.FakePerks.PerkCooldown, function()
                    _G.Ox.FakePerks.fsOnCooldown = false

                    if _G.Ox.FakePerks.FlowstateEnabled and arg and arg.Parent then
                        arg:SetAttribute("Flowstate", true)
                    end
                end)
            end)
        end)

        _G.Ox.FakePerks.fsConnection = arg:GetAttributeChangedSignal("Flowstate"):Connect(function()
            if not _G.Ox.FakePerks.FlowstateEnabled then
                return
            end

            if not fn29() then
                return
            end
            local attribute = arg:GetAttribute("Flowstate")

            if attribute == true then
                if _G.Ox.FakePerks.fsOnCooldown or tick() - _G.Ox.FakePerks.lastFSTime < _G.Ox.FakePerks.PerkCooldown then
                    arg:SetAttribute("Flowstate", false)
                end
            elseif attribute == false and not _G.Ox.FakePerks.fsOnCooldown then
                local n2 = tick() - _G.Ox.FakePerks.lastFSTime

                if _G.Ox.FakePerks.PerkCooldown <= n2 then
                    arg:SetAttribute("Flowstate", true)
                end
            end
        end)

        task.wait(0.5)

        if _G.Ox.FakePerks.FlowstateEnabled and arg and arg.Parent then
            arg:SetAttribute("Flowstate", true)
        end
    end

    ToggleFlowstate = function(flowstateEnabled)
        _G.Ox.FakePerks.FlowstateEnabled = flowstateEnabled

        if flowstateEnabled then
            if localPlayer.Character then
                fn35(localPlayer.Character)
            end
        else
            if _G.Ox.FakePerks.fsConnection then
                _G.Ox.FakePerks.fsConnection:Disconnect()
                _G.Ox.FakePerks.fsConnection = nil
            end

            if _G.Ox.FakePerks.fsAnimConnection then
                _G.Ox.FakePerks.fsAnimConnection:Disconnect()
                _G.Ox.FakePerks.fsAnimConnection = nil
            end

            if localPlayer.Character then
                localPlayer.Character:SetAttribute("Flowstate", false)
            end
        end

    end

    local function fn36()
        local adrenalineConns = _G.Ox.FakePerks.adrenalineConns
        if not adrenalineConns then
            return
        end

        for i, adrenalineConn in ipairs(adrenalineConns) do
            pcall(function()
                adrenalineConn:Disconnect()
            end)
        end

        _G.Ox.FakePerks.adrenalineConns = {}
    end

    local function fn37(arg)
        if not _G.Ox.FakePerks.FakeAdrenalineRush then
            return
        end

        if not fn29() then
            return
        end

        if not arg or not arg.Parent then
            return
        end

        if _G.Ox.FakePerks.boostActive then
            return
        end
        local now = tick()
        local lastARTime = _G.Ox.FakePerks.lastARTime
        local n2 = lastARTime or 0
        if now - n2 < _G.Ox.FakePerks.PerkCooldown then
            return
        end
        _G.Ox.FakePerks.boostActive = true
        _G.Ox.FakePerks.lastARTime = tick()
        local now2 = tick()

        task.spawn(function()
            perkBoost(arg, "MeowX_Perk3", 1.4, 5, function() return _G.Ox.FakePerks.FakeAdrenalineRush end)

            _G.Ox.FakePerks.boostActive = false
        end)
    end

    local function fn38(arg)
        if not arg then
            return
        end
        local humanoid = arg:FindFirstChildOfClass("Humanoid")
        local humanoid2 = humanoid or arg:WaitForChild("Humanoid", 5)
        if not humanoid2 then
            return
        end
        local health = humanoid2.Health

        table.insert(_G.Ox.FakePerks.adrenalineConns, humanoid2.HealthChanged:Connect(function(health2)
            if not _G.Ox.FakePerks.FakeAdrenalineRush then
                return
            end

            if health2 < health and health2 <= 50 and health2 > 0 then
                fn37(arg)
            end

            health = health2
        end))
    end

    SetupFakeAdrenalineRush = function(arg)
        local fakePerks = _G.Ox.FakePerks
        local fakeAdrenalineRush = arg == true
        fakePerks.FakeAdrenalineRush = fakeAdrenalineRush
        local fakePerks2 = _G.Ox.FakePerks
        local adrenalineOn = arg == true
        fakePerks2.adrenalineOn = adrenalineOn
        fn36()

        if not arg then

            return
        end

        fn38(localPlayer.Character)

        table.insert(_G.Ox.FakePerks.adrenalineConns, localPlayer.CharacterAdded:Connect(function(character)
            task.wait(0.3)

            if _G.Ox.FakePerks.FakeAdrenalineRush then
                fn38(character)
            end
        end))

    end

    local function fn39(character)
        task.wait(0.5)

        if _G.Ox.FakePerks.QuickRecoveryEnabled then
            fn32(character)
        end

        if _G.Ox.FakePerks.PerfectLandingEnabled then
            fn34(character)
        end

        if _G.Ox.FakePerks.FlowstateEnabled then
            fn35(character)
        end

        if _G.Ox.FakePerks.FakeAdrenalineRush then
            fn38(character)
        end
    end

    if localPlayer.Character then
        fn39(localPlayer.Character)
    end

    localPlayer.CharacterAdded:Connect(fn39)

    -- ===== Streamer Mode: hides every real player name / avatar on screen =====
    local streamer = {
        tracked = {},               -- inst -> {conn, apply}
        origText = setmetatable({}, {__mode = "k"}),
        modText = setmetatable({}, {__mode = "k"}),
        origImage = setmetatable({}, {__mode = "k"}),
        origHum = setmetatable({}, {__mode = "k"}),
        roots = {},                 -- DescendantAdded connections
        alias = {},
        count = 0,
        gen = 0,
    }
    local STREAM_LOGO = "rbxassetid://73763240772265"

    local function escapePattern(s)
        return (s:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0"))
    end

    local function aliasFor(plr)
        local a = streamer.alias[plr.UserId]
        if not a then
            if plr == localPlayer then
                a = "MeowX"
            else
                streamer.count += 1
                a = "Player" .. streamer.count
            end
            streamer.alias[plr.UserId] = a
        end
        return a
    end

    local function scrub(text)
        if #text < 2 then
            return text
        end
        local out = text
        for _, plr in ipairs(Players:GetPlayers()) do
            local a = aliasFor(plr)
            local safeAlias = a:gsub("%%", "%%%%")
            for _, nm in ipairs({plr.DisplayName, plr.Name}) do
                if #nm >= 2 and out:find(nm, 1, true) then
                    out = (out:gsub(escapePattern(nm), safeAlias))
                end
            end
        end
        return out
    end

    local function hasAvatar(image)
        if image == "" or image == STREAM_LOGO then
            return false
        end
        for _, plr in ipairs(Players:GetPlayers()) do
            if image:find(tostring(plr.UserId), 1, true) then
                return true
            end
        end
        return false
    end

    local function trackInstance(inst)
        if streamer.tracked[inst] or not _G.Ox.StreamerMode.Enabled then
            return
        end
        if inst:FindFirstAncestor("MeowXUI") then
            return
        end
        local apply
        local prop
        if inst:IsA("TextLabel") or inst:IsA("TextButton") or inst:IsA("TextBox") then
            prop = "Text"
            apply = function()
                if not _G.Ox.StreamerMode.Enabled then
                    return
                end
                local text = inst.Text
                if streamer.modText[inst] == text then
                    return
                end
                local clean = scrub(text)
                if clean ~= text then
                    streamer.origText[inst] = text
                    streamer.modText[inst] = clean
                    inst.Text = clean
                else
                    streamer.origText[inst] = nil
                    streamer.modText[inst] = nil
                end
            end
        elseif inst:IsA("ImageLabel") or inst:IsA("ImageButton") then
            prop = "Image"
            apply = function()
                if not _G.Ox.StreamerMode.Enabled then
                    return
                end
                local image = inst.Image
                if hasAvatar(image) then
                    streamer.origImage[inst] = image
                    inst.Image = STREAM_LOGO
                end
            end
        else
            return
        end
        streamer.tracked[inst] = {conn = inst:GetPropertyChangedSignal(prop):Connect(apply), apply = apply}
        apply()
    end

    local function hideHumanoidName(character)
        local hum = character and character:FindFirstChildOfClass("Humanoid")
        local plr = character and Players:GetPlayerFromCharacter(character)
        if hum and plr and _G.Ox.StreamerMode.Enabled then
            if streamer.origHum[hum] == nil then
                streamer.origHum[hum] = hum.DisplayName
            end
            hum.DisplayName = aliasFor(plr)
        end
    end

    local function scanRoot(root, billboardsOnly)
        local myGen = streamer.gen
        task.spawn(function()
            local n = 0
            for _, d in ipairs(root:GetDescendants()) do
                if streamer.gen ~= myGen or not _G.Ox.StreamerMode.Enabled then
                    return
                end
                if not billboardsOnly or d:FindFirstAncestorWhichIsA("BillboardGui") or d:FindFirstAncestorWhichIsA("SurfaceGui") then
                    trackInstance(d)
                end
                n += 1
                if n % 120 == 0 then
                    RunService.Heartbeat:Wait()
                end
            end
        end)
        table.insert(streamer.roots, root.DescendantAdded:Connect(function(d)
            task.defer(function()
                if not billboardsOnly or d:FindFirstAncestorWhichIsA("BillboardGui") or d:FindFirstAncestorWhichIsA("SurfaceGui") then
                    trackInstance(d)
                end
            end)
        end))
    end

    local function watchCharacter(plr)
        local function onChar(character)
            if not _G.Ox.StreamerMode.Enabled then
                return
            end
            hideHumanoidName(character)
            scanRoot(character, true)
        end
        if plr.Character then
            onChar(plr.Character)
        end
        table.insert(streamer.roots, plr.CharacterAdded:Connect(function(character)
            task.wait(0.3)
            onChar(character)
        end))
    end

    local function fn40()
        streamer.gen += 1
        scanRoot(playerGui, false)
        pcall(function()
            local coreGui = game:GetService("CoreGui")
            for _, child in ipairs(coreGui:GetChildren()) do
                if child.Name ~= "MeowXUI" then
                    scanRoot(child, false)
                end
            end
            table.insert(streamer.roots, coreGui.ChildAdded:Connect(function(child)
                if child.Name ~= "MeowXUI" then
                    task.defer(scanRoot, child, false)
                end
            end))
        end)
        for _, plr in ipairs(Players:GetPlayers()) do
            watchCharacter(plr)
        end
        table.insert(streamer.roots, Players.PlayerAdded:Connect(function(plr)
            task.defer(function()
                if not _G.Ox.StreamerMode.Enabled then
                    return
                end
                watchCharacter(plr)
                for _, info in pairs(streamer.tracked) do
                    pcall(info.apply)
                end
            end)
        end))
    end

    local function fn41()
        streamer.gen += 1
        for _, conn in ipairs(streamer.roots) do
            conn:Disconnect()
        end
        table.clear(streamer.roots)
        for inst, info in pairs(streamer.tracked) do
            info.conn:Disconnect()
            streamer.tracked[inst] = nil
        end
        for inst, original in pairs(streamer.origText) do
            if inst.Parent and inst.Text == streamer.modText[inst] then
                inst.Text = original
            end
        end
        for inst, original in pairs(streamer.origImage) do
            if inst.Parent and inst.Image == STREAM_LOGO then
                inst.Image = original
            end
        end
        for hum, original in pairs(streamer.origHum) do
            if hum.Parent then
                hum.DisplayName = original
            end
        end
        table.clear(streamer.origText)
        table.clear(streamer.modText)
        table.clear(streamer.origImage)
        table.clear(streamer.origHum)
    end

    local function fn42(enabled)
        _G.Ox.StreamerMode.Enabled = enabled
        fn41()
        if enabled then
            fn40()
        end
    end

    local function fn43(enabled)
        _G.Ox.StretchRes.Enabled = enabled
    end

    local tbl6 = {}

    UpdateHookData = function()
        for k, player in pairs(Players:GetPlayers()) do
            if player ~= localPlayer and player.Team and player.Team.Name == "Survivors" then
                local attribute = player:GetAttribute("HookCount")
                local n2 = attribute or 0
                tbl6[player.Name] = n2
            end
        end
    end

    local tbl7 = {
        "rbxassetid://120434965879067",
        "rbxassetid://81511619438196",
        "rbxassetid://130571419892864",
    }

    CreateHookUICounter = function(parent, arg)
        if not parent then
            return
        end
        local num = tonumber(arg)
        local n2 = num or 0
        local v5 = n2
        local noxHookCounter = parent:FindFirstChild("MeowX_HookCounter")
        local v6 = noxHookCounter

        if v5 <= 0 then
            if noxHookCounter then
                noxHookCounter:Destroy()
            end

            return
        end

        local v7 = tbl7[math.clamp(v5, 1, 3)]
        if not v7 then
            return
        end

        if not noxHookCounter then
            local imageLabel = Instance.new("ImageLabel")
            v6 = imageLabel
            imageLabel.Name = "MeowX_HookCounter"
            imageLabel.BackgroundTransparency = 1
            local zIndex = parent.ZIndex
            local n3 = zIndex or 1
            imageLabel.ZIndex = n3 + 1
            imageLabel.Parent = parent
        end

        v6.Size = UDim2.new(0.509, 0, 0.51, 0)
        v6.Position = UDim2.new(0.91, 0, 0.18, 0)
        v6.AnchorPoint = Vector2.new(0.5, 0.5)
        v6.Image = v7
        v6.ScaleType = Enum.ScaleType.Fit
    end

    UpdateHookUICounter = function()
        if GetRole() == "Killer" then
            local playerGui2 = localPlayer:FindFirstChild("PlayerGui")
            if not playerGui2 then
                return
            end

            local function fn44(arg)
                if arg and type(arg) == "string" then
                    return tonumber(arg:match("id=(%d+)"))
                end
                return nil
            end

            local v5, v6, v7 = ipairs(playerGui2:GetChildren())
            local v8 = v7
            local v9 = v5
            local v10 = v6

            while true do
                local v11, v12 = v9(v10, v8)
                if v11 == nil then
                    break
                end
                v8 = v11

                if typeof(v12) == "Instance" then
                    local frame2 = v12:FindFirstChild("Frame")

                    if frame2 and frame2:IsA("Frame") then
                        for i, child in ipairs(frame2:GetChildren()) do
                            local imageLabel = child:FindFirstChild("ImageLabel")

                            if imageLabel then
                                local attribute = child:GetAttribute("UserId")
                                local v13 = attribute or fn44(imageLabel.Image)
                                local playerByUserId = v13 and Players:GetPlayerByUserId(tonumber(v13)) or nil

                                if playerByUserId and playerByUserId ~= localPlayer and playerByUserId.Team and playerByUserId.Team.Name == "Survivors" then
                                    local v14 = tbl6[playerByUserId.Name]
                                    local attribute2 = v14 or playerByUserId:GetAttribute("HookCount") or 0
                                    CreateHookUICounter(imageLabel, attribute2)
                                else
                                    local noxHookCounter = imageLabel:FindFirstChild("MeowX_HookCounter")

                                    if noxHookCounter then
                                        noxHookCounter:Destroy()
                                    end
                                end
                            end
                        end

                        v8 = v11
                    end
                end
            end

            return
        end

        ClearHookUICounter()
    end

    ClearHookUICounter = function()
        local playerGui2 = localPlayer:FindFirstChild("PlayerGui")
        if not playerGui2 then
            return
        end
        local v5, v6, v7 = ipairs(playerGui2:GetChildren())
        local v8 = v7
        local v9 = v5
        local v10 = v6

        while true do
            local v11, v12 = v9(v10, v8)
            if v11 == nil then
                break
            end
            v8 = v11

            if typeof(v12) == "Instance" then
                local frame2 = v12:FindFirstChild("Frame")

                if frame2 and frame2:IsA("Frame") then
                    for i, child in ipairs(frame2:GetChildren()) do
                        local imageLabel = child:FindFirstChild("ImageLabel")
                        local noxHookCounter = imageLabel and imageLabel:FindFirstChild("MeowX_HookCounter")

                        if noxHookCounter then
                            noxHookCounter:Destroy()
                        end
                    end

                    v8 = v11
                end
            end
        end
    end

    UpdateHookESP = function()
        if not _G.Ox.ESPConfig.HookCount then
            ClearHookESP()
        end
    end

    ClearHookESP = function()
        local v5, v6, v7 = pairs(Players:GetPlayers())
        local v8 = v7
        local v9 = v5
        local v10 = v6

        while true do
            local v11, v12 = v9(v10, v8)
            if v11 == nil then
                break
            end
            v8 = v11

            if v12.Character then
                for k, child in pairs(v12.Character:GetChildren()) do
                    if string.match(child.Name, "^HookESP_") then
                        child:Destroy()
                    end
                end

                v8 = v11
            end
        end
    end

    ClearESP = function(arg)
        if arg == "Player" then
            for k, player in pairs(Players:GetPlayers()) do
                if player.Character then
                    if player.Character:FindFirstChild("PEH") then
                        player.Character.PEH:Destroy()
                    end

                    if player.Character:FindFirstChild("PE_Text") then
                        player.Character.PE_Text:Destroy()
                    end
                end
            end
        elseif arg == "Killer" then
            for k, player in pairs(Players:GetPlayers()) do
                if player.Character then
                    if player.Character:FindFirstChild("KEH") then
                        player.Character.KEH:Destroy()
                    end

                    if player.Character:FindFirstChild("KE_Text") then
                        player.Character.KE_Text:Destroy()
                    end
                end
            end
        elseif arg == "Generator" then
            for k, generator in pairs(tbl4.Generators) do
                if generator.model and generator.model.Parent and generator.model:FindFirstChild("GEH") then
                    generator.model.GEH:Destroy()
                end

                if generator.part and generator.part.Parent and generator.part:FindFirstChild("GE_Text") then
                    generator.part.GE_Text:Destroy()
                end
            end
        elseif arg == "Pallet" then
            for k, pallet in pairs(tbl4.Pallets) do
                if pallet and pallet.Parent and pallet:FindFirstChild("PalletEH") then
                    pallet.PalletEH:Destroy()
                end
            end
        elseif arg == "Hook" then
            for k, hook in pairs(tbl4.Hooks) do
                if hook and hook.Parent and hook:FindFirstChild("HookEH") then
                    hook.HookEH:Destroy()
                end
            end
        elseif arg == "Window" then
            for k, window in pairs(tbl4.Windows) do
                if window and window.Parent and window:FindFirstChild("WindowEH") then
                    window.WindowEH:Destroy()
                end
            end
        elseif arg == "Gate" then
            for k, gate in pairs(tbl4.Gates) do
                if gate and gate.Parent and gate:FindFirstChild("GateEH") then
                    gate.GateEH:Destroy()
                end
            end
        elseif arg == "SCP" then
            for k, scP in pairs(tbl4.SCPs) do
                if scP and scP.Parent and scP:FindFirstChild("SCPEH") then
                    scP.SCPEH:Destroy()
                end
            end
        end
    end

    ClearAllESP = function()
        ClearESP("Player")
        ClearESP("Killer")
        ClearESP("Generator")
        ClearESP("Pallet")
        ClearESP("Hook")
        ClearESP("Gate")
        ClearESP("SCP")
        ClearESP("Window")
        ClearHookESP()
    end

    GetSurvivorStatus = function(arg)
        if not arg then
            return nil, nil
        end

        if arg:GetAttribute("IsHooked") == true then
            return "HOOKED", _G.Ox.ESPColors.Hooked
        end

        if arg:GetAttribute("Knocked") == true then
            return "DOWN", _G.Ox.ESPColors.Downed
        end
        local humanoid = arg:FindFirstChildOfClass("Humanoid")
        if humanoid and humanoid.Health > 0 and humanoid.Health < humanoid.MaxHealth then
            return "INJURED", _G.Ox.ESPColors.Injured
        end
        return nil, nil
    end

    buildInfoRich = function(arg, arg2, arg3, arg4, arg5)
        local tbl8 = {}

        if arg and arg ~= "" then
            local str = "#FFFFFF"

            if arg == "INJURED" then
                str = "#FF8C00"
            elseif arg == "DOWN" then
                str = "#FF2828"
            elseif arg == "HOOKED" then
                str = "#F0F0FF"
            end

            table.insert(tbl8, string.format("<font color=\"%s\">%s</font>", str, arg))
        end

        if arg3 then
            table.insert(tbl8, string.format("<font color=\"#FFFFFF\">%dm</font>", arg3))
        end

        if not arg5 and arg4 and arg ~= "HOOKED" then
            local str = "#C8C8C8"

            if arg4 >= 3 then
                str = "#FF3232"
            elseif arg4 >= 2 then
                str = "#FFC832"
            end

            table.insert(tbl8, string.format("<font color=\"%s\">Hooked %d</font>", str, arg4))
        end

        return table.concat(tbl8, " <font color=\"#888888\">·</font> ")
    end

    UpdatePlayerESP = function()
        if not _G.Ox.ESPConfig.Master then
            return
        end
        local character = localPlayer.Character
        local humanoidRootPart = character and character:FindFirstChild("HumanoidRootPart")

        if _G.Ox.ESPConfig.KillerWarn and humanoidRootPart and GetRole() == "Survivor" then
            local killerWarn = humanoidRootPart:FindFirstChild("KillerWarn")
            local v5 = killerWarn
            local huge = math.huge

            for k, player in pairs(Players:GetPlayers()) do
                if player ~= localPlayer and player.Team and player.Team.Name == "Killer" and player.Character then
                    local humanoidRootPart2 = player.Character:FindFirstChild("HumanoidRootPart")

                    if humanoidRootPart2 then
                        local magnitude = (humanoidRootPart2.Position - humanoidRootPart.Position).Magnitude

                        if magnitude < huge then
                            huge = magnitude
                        end
                    end
                end
            end

            if huge <= 80 then
                if not killerWarn then
                    local billboardGui = Instance.new("BillboardGui")
                    v5 = billboardGui
                    billboardGui.Name = "KillerWarn"
                    billboardGui.Size = UDim2.new(0, 30, 0, 30)
                    billboardGui.AlwaysOnTop = true
                    billboardGui.StudsOffset = Vector3.new(0, 4, 0)
                    billboardGui.Parent = humanoidRootPart
                    local textLabel = Instance.new("TextLabel")
                    textLabel.Name = "WarnText"
                    textLabel.Size = UDim2.new(1, 0, 1, 0)
                    textLabel.BackgroundTransparency = 1
                    textLabel.TextScaled = true
                    textLabel.TextStrokeTransparency = 0
                    textLabel.Font = Enum.Font.GothamBlack
                    textLabel.Parent = billboardGui
                end

                local warnText = v5:FindFirstChild("WarnText")

                if warnText then
                    if huge <= 40 then
                        warnText.Text = "!!"
                        warnText.TextColor3 = Color3.fromRGB(255, 0, 0)
                    else
                        warnText.Text = "!"
                        warnText.TextColor3 = Color3.fromRGB(255, 255, 0)
                    end
                end
            elseif killerWarn then
                killerWarn:Destroy()
            end
        else
            local killerWarn = humanoidRootPart and humanoidRootPart:FindFirstChild("KillerWarn")

            if killerWarn then
                killerWarn:Destroy()
            end
        end

        local v5, v6, v7 = pairs(Players:GetPlayers())
        local v8 = v7
        local v9 = v5
        local v10 = v6

        while true do
            local v11, v12 = v9(v10, v8)
            if v11 == nil then
                break
            end
            v8 = v11

            if v12 ~= localPlayer and v12.Character then
                local humanoidRootPart2 = v12.Character:FindFirstChild("HumanoidRootPart")

                if humanoidRootPart2 and _G.Ox.ESPConfig.MaxDistance < (currentCamera.CFrame.Position - humanoidRootPart2.Position).Magnitude then
                    for i, v13 in ipairs({"PE_Text", "KE_Text", "PEH", "KEH"}) do
                        local v14 = v12.Character:FindFirstChild(v13)

                        if v14 then
                            v14:Destroy()
                        end
                    end

                    v8 = v11
                else
                    local team = v12.Team
                    local flag3 = team and v12.Team.Name == "Killer"
                    local killer

                    if flag3 then
                        killer = _G.Ox.ESPConfig.Killer
                    else
                        local player = _G.Ox.ESPConfig.Player
                        local hookCount = player or _G.Ox.ESPConfig.HookCount
                        killer = hookCount
                    end

                    local str = flag3 and "KE_Text" or "PE_Text"
                    local name = flag3 and "KEH" or "PEH"
                    local killer2 = flag3 and _G.Ox.ESPColors.Killer or _G.Ox.ESPColors.Player
                    local v13 = nil
                    local v14 = nil

                    if not flag3 and _G.Ox.ESPConfig.Status then
                        local v15, v16 = GetSurvivorStatus(v12.Character)

                        if v15 then
                            v13 = v15
                            v14 = v16
                        end
                    end

                    if killer then
                        local v15, v16, v17 = ipairs({"PE_Text", "KE_Text"})
                        local v18 = v9
                        local v19 = v10

                        for k, v20 in v15, v16, v17 do
                            if v20 ~= str then
                                local v21 = v12.Character:FindFirstChild(v20)

                                if v21 then
                                    v21:Destroy()
                                end
                            end
                        end

                        for i, v20 in ipairs({"PEH", "KEH"}) do
                            if v20 ~= name then
                                local v21 = v12.Character:FindFirstChild(v20)

                                if v21 then
                                    v21:Destroy()
                                end
                            end
                        end

                        v8 = v11
                        v9 = v18
                        v10 = v19

                        if flag3 then
                            for i, child in ipairs(v12.Character:GetChildren()) do
                                if string.match(child.Name, "^HookESP_") then
                                    child:Destroy()
                                end
                            end

                            v8 = v11
                            v9 = v18
                            v10 = v19
                        end

                        local humanoidRootPart3 = v12.Character:FindFirstChild("HumanoidRootPart")
                        local n2 = humanoidRootPart3 and math.floor(GetDistance(humanoidRootPart3.Position)) or nil
                        local v20 = v12.Character:FindFirstChild(name)
                        local v21 = v20

                        if not v20 then
                            local highlight2 = Instance.new("Highlight")
                            v21 = highlight2
                            highlight2.Name = name
                            highlight2.Parent = v12.Character
                        end

                        v21.FillColor = killer2
                        v21.OutlineColor = killer2
                        local outline = _G.Ox.ESPConfig.Outline
                        local fillTransparency = outline and 1 or 0.5
                        v21.FillTransparency = fillTransparency
                        v21.OutlineTransparency = 0
                        local name2 = nil
                        local v22 = nil

                        if _G.Ox.ESPConfig.Name then
                            name2 = v12.Name

                            if flag3 then
                                local attribute = v12:GetAttribute("SelectedKiller")

                                if not attribute then
                                    local selectedKiller = v12:FindFirstChild("SelectedKiller")

                                    if selectedKiller then
                                        pcall(function()
                                            attribute = selectedKiller.Value
                                        end)
                                    end
                                end

                                if attribute and tostring(attribute) ~= "" then
                                    name2 = tostring(attribute)
                                end
                            end

                            if _G.Ox.ESPConfig.ItemIcon and not flag3 then
                                local attribute = v12:GetAttribute("EquippedItem")

                                if attribute and attribute ~= "" then
                                    v22 = getItemIcon(attribute)
                                end
                            end
                        end

                        local v23 = nil

                        if not flag3 and _G.Ox.ESPConfig.HookCount then
                            local v24 = tbl6[v12.Name]
                            local attribute = v24 or v12:GetAttribute("HookCount") or 0
                            v23 = attribute
                        end

                        local v24 = buildInfoRich
                        local distance = _G.Ox.ESPConfig.Distance
                        local v25 = distance and n2 or nil
                        local v26 = v24(v13, v14, v25, v23, flag3)

                        if not name2 and v26 == "" then
                            local v27 = v12.Character:FindFirstChild(str)

                            if v27 then
                                v27:Destroy()
                            end
                        else
                            local v27 = CreateModernESP
                            local character2 = v12.Character
                            local tbl8 = {}
                            local name3 = name2 or ""
                            tbl8.name = name3
                            tbl8.infoRich = v26
                            tbl8.color = killer2
                            tbl8.icon = v22
                            tbl8.offsetY = 4
                            v27(character2, str, tbl8)
                        end
                    else
                        local v15 = v12.Character:FindFirstChild(name)

                        if v15 then
                            v15:Destroy()
                        end

                        local v16 = v12.Character:FindFirstChild(str)

                        if v16 then
                            v16:Destroy()
                        end
                    end
                end
            end
        end
    end

    UpdateSCPESP = function()
        if not _G.Ox.ESPConfig.Master then
            return
        end

        if _G.Ox.ESPConfig.SCP then
            for i, scP in ipairs(tbl4.SCPs) do
                if scP and scP.Parent then
                    local humanoid = scP:FindFirstChildOfClass("Humanoid")
                    local humanoidRootPart = scP:FindFirstChild("HumanoidRootPart")
                    local torso = humanoidRootPart or scP:FindFirstChild("Torso") or scP.PrimaryPart

                    if torso and _G.Ox.ESPConfig.MaxDistance < (currentCamera.CFrame.Position - torso.Position).Magnitude then
                        local scpeh = scP:FindFirstChild("SCPEH")

                        if scpeh then
                            scpeh:Destroy()
                        end
                    elseif torso and (not humanoid or humanoid.Health > 0) then
                        local scp = _G.Ox.ESPColors.SCP
                        local scpeh = scP:FindFirstChild("SCPEH")
                        local v5 = scpeh

                        if not scpeh then
                            local highlight2 = Instance.new("Highlight")
                            v5 = highlight2
                            highlight2.Name = "SCPEH"
                            highlight2.Parent = scP
                        end

                        v5.FillColor = scp
                        v5.OutlineColor = scp
                        local outline = _G.Ox.ESPConfig.Outline
                        local fillTransparency = outline and 1 or 0.5
                        v5.FillTransparency = fillTransparency
                        v5.OutlineTransparency = 0
                    else
                        local scpeh = scP:FindFirstChild("SCPEH")

                        if scpeh then
                            scpeh:Destroy()
                        end
                    end
                end
            end
        else
            ClearESP("SCP")
        end
    end

    UpdateStaticESP = function()
        if not _G.Ox.ESPConfig.Master then
            return
        end

        if _G.Ox.ESPConfig.Generator then
            for k, generator in pairs(tbl4.Generators) do
                local model = generator.model

                if model and model.Parent then
                    local part = generator.part
                    local basePart = part or model:FindFirstChildWhichIsA("BasePart")

                    if basePart and _G.Ox.ESPConfig.MaxDistance < (currentCamera.CFrame.Position - basePart.Position).Magnitude then
                        local geh = model:FindFirstChild("GEH")

                        if geh then
                            geh:Destroy()
                        end

                        local geText = model:FindFirstChild("GE_Text")

                        if geText then
                            geText:Destroy()
                        end
                    else
                        local floor = math.floor
                        local attribute = model:GetAttribute("RepairProgress")
                        local n2 = attribute or 0
                        local v5 = floor(n2)
                        local n3 = math.clamp(v5 / 100, 0, 1)
                        local v6 = _G.Ox.ESPColors.Generator:Lerp(_G.Ox.ESPColors.GeneratorDone, n3)
                        local geh = model:FindFirstChild("GEH")
                        local v7 = geh

                        if not geh then
                            local highlight2 = Instance.new("Highlight")
                            v7 = highlight2
                            highlight2.Name = "GEH"
                            highlight2.Parent = model
                        end

                        v7.FillColor = v6
                        v7.OutlineColor = v6
                        local outline = _G.Ox.ESPConfig.Outline
                        local fillTransparency = outline and 1 or 0.5
                        v7.FillTransparency = fillTransparency
                        v7.OutlineTransparency = 0

                        if _G.Ox.ESPConfig.GeneratorName then
                            local str

                            if v5 >= 100 then
                                str = "DONE"
                            else
                                str = string.format("%d%%", v5)
                            end

                            local generator2 = _G.Ox.ESPColors.Generator
                            local part2 = generator.part
                            local v8 = part2 or model
                            local n4

                            if v8:IsA("BasePart") then
                                n4 = v8.Size.Y / 2 + 1
                            else
                                n4 = model:GetExtentsSize().Y / 2 + 1
                            end

                            CreateModernESP(v8, "GE_Text", {
                                name = "GEN",
                                infoRich = string.format("<font color=\"%s\">%s</font>", "#FF8000", str),
                                color = generator2,
                                icon = nil,
                                offsetY = n4,
                                noSeparator = true,
                                noDistScale = true,
                            })
                        else
                            local geText = model:FindFirstChild("GE_Text")

                            if geText then
                                geText:Destroy()
                            end
                        end
                    end
                end
            end
        end

        if _G.Ox.ESPConfig.Pallet then
            for k, pallet in pairs(tbl4.Pallets) do
                if pallet and pallet.Parent then
                    local basePart = pallet:FindFirstChildWhichIsA("BasePart")

                    if basePart and _G.Ox.ESPConfig.MaxDistance < (currentCamera.CFrame.Position - basePart.Position).Magnitude then
                        local palletEH = pallet:FindFirstChild("PalletEH")

                        if palletEH then
                            palletEH:Destroy()
                        end
                    else
                        local palletEH = pallet:FindFirstChild("PalletEH")
                        local v5 = palletEH

                        if not palletEH then
                            local highlight2 = Instance.new("Highlight")
                            v5 = highlight2
                            highlight2.Name = "PalletEH"
                            highlight2.Parent = pallet
                        end

                        v5.Adornee = pallet
                        v5.FillColor = _G.Ox.ESPColors.Pallet
                        v5.OutlineColor = _G.Ox.ESPColors.Pallet
                        local outline = _G.Ox.ESPConfig.Outline
                        local fillTransparency = outline and 1 or 0.5
                        v5.FillTransparency = fillTransparency
                        v5.OutlineTransparency = 0
                    end
                end
            end
        end

        if _G.Ox.ESPConfig.Window then
            for i, window in ipairs(tbl4.Windows) do
                if window and window.Parent then
                    local bottom = window:FindFirstChild("Bottom")
                    local basePart = bottom or window:FindFirstChildWhichIsA("BasePart")

                    if basePart and _G.Ox.ESPConfig.MaxDistance < (currentCamera.CFrame.Position - basePart.Position).Magnitude then
                        local windowEH = window:FindFirstChild("WindowEH")

                        if windowEH then
                            windowEH:Destroy()
                        end
                    elseif basePart then
                        local windowEH = window:FindFirstChild("WindowEH")
                        local v5 = windowEH

                        if not windowEH then
                            local boxHandleAdornment = Instance.new("BoxHandleAdornment")
                            v5 = boxHandleAdornment
                            boxHandleAdornment.Name = "WindowEH"
                            boxHandleAdornment.Parent = window
                            boxHandleAdornment.AlwaysOnTop = true
                            boxHandleAdornment.ZIndex = 5
                        end

                        v5.Adornee = basePart
                        v5.Size = basePart.Size
                        v5.Color3 = _G.Ox.ESPColors.Window
                        local outline = _G.Ox.ESPConfig.Outline
                        local transparency = outline and 0.8 or 0.4
                        v5.Transparency = transparency
                    end
                end
            end
        end

        if _G.Ox.ESPConfig.Hook then
            for i, hook in ipairs(tbl4.Hooks) do
                if hook and hook.Parent then
                    local hookPoint = hook:FindFirstChild("HookPoint")
                    local basePart = hookPoint or hook:FindFirstChildWhichIsA("BasePart")

                    if basePart and _G.Ox.ESPConfig.MaxDistance < (currentCamera.CFrame.Position - basePart.Position).Magnitude then
                        local hookEH = hook:FindFirstChild("HookEH")

                        if hookEH then
                            hookEH:Destroy()
                        end
                    else
                        local hookEH = hook:FindFirstChild("HookEH")
                        local v5 = hookEH

                        if not hookEH then
                            local highlight2 = Instance.new("Highlight")
                            v5 = highlight2
                            highlight2.Name = "HookEH"
                            highlight2.Parent = hook
                        end

                        v5.FillColor = _G.Ox.ESPColors.Hook
                        v5.OutlineColor = _G.Ox.ESPColors.Hook
                        local outline = _G.Ox.ESPConfig.Outline
                        local fillTransparency = outline and 1 or 0.5
                        v5.FillTransparency = fillTransparency
                        v5.OutlineTransparency = 0
                    end
                end
            end
        end

        if _G.Ox.ESPConfig.Gate then
            for i, gate in ipairs(tbl4.Gates) do
                if gate and gate.Parent then
                    local basePart = gate:FindFirstChildWhichIsA("BasePart")

                    if basePart and _G.Ox.ESPConfig.MaxDistance < (currentCamera.CFrame.Position - basePart.Position).Magnitude then
                        local gateEH = gate:FindFirstChild("GateEH")

                        if gateEH then
                            gateEH:Destroy()
                        end
                    else
                        local gateEH = gate:FindFirstChild("GateEH")
                        local v5 = gateEH

                        if not gateEH then
                            local highlight2 = Instance.new("Highlight")
                            v5 = highlight2
                            highlight2.Name = "GateEH"
                            highlight2.Parent = gate
                        end

                        v5.Adornee = gate
                        v5.FillColor = _G.Ox.ESPColors.Gate
                        v5.OutlineColor = _G.Ox.ESPColors.Gate
                        local outline = _G.Ox.ESPConfig.Outline
                        local fillTransparency = outline and 1 or 0.5
                        v5.FillTransparency = fillTransparency
                        v5.OutlineTransparency = 0
                    end
                end
            end
        end
    end

    task.spawn(function()
        local currentCamera2, v5, v6, v7, v8, v9, v10, v11, v12, humanoidRootPart, magnitude, scale, n2, v13, v14, v15, v16, v17, v18, v19
        local v20, v21, box, distScale, v22, v23, v24, v25, v26, v27, model, basePart, magnitude2, scale2, n3, geText, box2, distScale2, n4
        n4 = 1

        while true do
            if n4 == 1 then
                if _G.Ox.ScriptAlive then
                    n4 = 2
                else
                    n4 = 26
                end
            elseif n4 == 2 then
                task.wait(0.1)
                currentCamera2 = workspace.CurrentCamera

                if currentCamera2 then
                    n4 = 3
                else
                    n4 = 1
                end
            elseif n4 == 3 then
                v5, v6, v7 = ipairs(Players:GetPlayers())
                v8 = v7
                v9 = v5
                v10 = v6
                n4 = 4
            elseif n4 == 4 then
                v11, v12 = v9(v10, v8)

                if v11 == nil then
                    n4 = 16
                else
                    n4 = 5
                end
            elseif n4 == 5 then
                v8 = v11

                if v12 ~= localPlayer and v12.Character then
                    n4 = 6
                else
                    n4 = 4
                end
            elseif n4 == 6 then
                humanoidRootPart = v12.Character:FindFirstChild("HumanoidRootPart")

                if humanoidRootPart then
                    n4 = 7
                else
                    n4 = 4
                end
            elseif n4 == 7 then
                magnitude = (currentCamera2.CFrame.Position - humanoidRootPart.Position).Magnitude
                scale = math.clamp(40 / math.max(magnitude, 5), 0.8, 1)
                n2 = 4 + math.clamp((magnitude - 40) * 0.05, 0, 6)
                v13, v14, v15 = ipairs({"PE_Text", "KE_Text"})
                v16 = v9
                v17 = v10
                v18 = v15
                n4 = 8
            elseif n4 == 8 then
                v19, v20 = v13(v14, v18)

                if v19 == nil then
                    n4 = 15
                else
                    n4 = 9
                end
            elseif n4 == 9 then
                v18 = v19
                v21 = v12.Character:FindFirstChild(v20)

                if v21 and not v21:GetAttribute("NoDistScale") then
                    n4 = 10
                else
                    n4 = 8
                end
            elseif n4 == 10 then
                box = v21:FindFirstChild("Box")
                distScale = box

                if box then
                    n4 = 11
                else
                    n4 = 12
                end
            elseif n4 == 11 then
                distScale = box:FindFirstChild("DistScale")
                n4 = 12
            elseif n4 == 12 then
                if distScale then
                    n4 = 13
                else
                    n4 = 14
                end
            elseif n4 == 13 then
                distScale.Scale = scale
                n4 = 14
            elseif n4 == 14 then
                v21.StudsOffset = Vector3.new(0, n2, 0)
                n4 = 8
            elseif n4 == 15 then
                v8 = v11
                v9 = v16
                v10 = v17
                n4 = 4
            elseif n4 == 16 then
                v22, v23, v24 = pairs(tbl4.Generators)
                v25 = v24
                n4 = 17
            elseif n4 == 17 then
                v26, v27 = v22(v23, v25)

                if v26 == nil then
                    n4 = 1
                else
                    n4 = 18
                end
            elseif n4 == 18 then
                v25 = v26
                model = v27.model

                if model and model.Parent then
                    n4 = 19
                else
                    n4 = 17
                end
            elseif n4 == 19 then
                basePart = model:FindFirstChildWhichIsA("BasePart")

                if basePart then
                    n4 = 20
                else
                    n4 = 17
                end
            elseif n4 == 20 then
                magnitude2 = (currentCamera2.CFrame.Position - basePart.Position).Magnitude
                scale2 = math.clamp(40 / math.max(magnitude2, 5), 0.8, 1)
                n3 = 4 + math.clamp((magnitude2 - 40) * 0.05, 0, 6)
                geText = model:FindFirstChild("GE_Text")

                if geText and not geText:GetAttribute("NoDistScale") then
                    n4 = 21
                else
                    n4 = 17
                end
            elseif n4 == 21 then
                box2 = geText:FindFirstChild("Box")
                distScale2 = box2

                if box2 then
                    n4 = 22
                else
                    n4 = 23
                end
            elseif n4 == 22 then
                distScale2 = box2:FindFirstChild("DistScale")
                n4 = 23
            elseif n4 == 23 then
                if distScale2 then
                    n4 = 24
                else
                    n4 = 25
                end
            elseif n4 == 24 then
                distScale2.Scale = scale2
                n4 = 25
            elseif n4 == 25 then
                geText.StudsOffset = Vector3.new(0, n3, 0)
                n4 = 17
            elseif n4 == 26 then
                return
            end
        end
    end)

    SetupHookDetection = function()
        for k, player in pairs(Players:GetPlayers()) do
            if player ~= localPlayer then
                player:GetAttributeChangedSignal("HookCount"):Connect(function()
                    local name = player.Name
                    local attribute = player:GetAttribute("HookCount")
                    local n2 = attribute or 0
                    tbl6[name] = n2

                    if _G.Ox.ESPConfig.HookCount then
                        UpdateHookESP()
                        UpdateHookUICounter()
                    end
                end)
            end
        end
    end

    Players.PlayerAdded:Connect(function(player)
        player:GetAttributeChangedSignal("HookCount"):Connect(function()
            local name = player.Name
            local attribute = player:GetAttribute("HookCount")
            local n2 = attribute or 0
            tbl6[name] = n2

            if _G.Ox.ESPConfig.HookCount then
                UpdateHookESP()
                UpdateHookUICounter()
            end
        end)
    end)

    task.spawn(function()
        task.wait(2)
        SetupHookDetection()
    end)

    local flag3 = false

    task.spawn(function()
        while _G.Ox.ScriptAlive do
            task.wait(1)

            if _G.Ox.ESPConfig.HookCount then
                flag3 = true
                UpdateHookData()
                UpdatePlayerESP()
                UpdateHookUICounter()
            elseif flag3 then
                ClearHookESP()
                ClearHookUICounter()
                UpdatePlayerESP()
                flag3 = false
            end
        end
    end)

    local function fn44(enabled)
        _G.Ox.InfinityZoom.Enabled = enabled

        if enabled then
            localPlayer.CameraMaxZoomDistance = math.huge
            localPlayer.CameraMinZoomDistance = 0

        else
            localPlayer.CameraMaxZoomDistance = 12
            localPlayer.CameraMinZoomDistance = 0.5

        end
    end

    local function fn45(enabled)
        _G.Ox.CameraFOV.Enabled = enabled

        if not enabled then
            currentCamera.FieldOfView = 70
        end

    end

    local function fn46(value)
        _G.Ox.CameraFOV.Value = value

        if _G.Ox.CameraFOV.Enabled then
            currentCamera.FieldOfView = value
        end
    end

    localPlayer.CharacterAdded:Connect(function()
        task.wait(0.5)

        if _G.Ox.CameraFOV.Enabled then
            currentCamera.FieldOfView = _G.Ox.CameraFOV.Value
        end
    end)

    workspace.ChildAdded:Connect(function(child)
        if child.Name == "Map" then
            task.wait(0.5)

            if _G.Ox.CameraFOV.Enabled then
                currentCamera.FieldOfView = _G.Ox.CameraFOV.Value
            end
        end
    end)

    ResetAllTransparency = function()
        local v5, v6, v7 = pairs(currentCamera:GetChildren())
        local v8 = v7
        local v9 = v5
        local v10 = v6

        while true do
            local v11, v12 = v9(v10, v8)
            if v11 == nil then
                break
            end
            v8 = v11

            if v12 ~= localPlayer.Character then
                for k, descendant in pairs(v12:GetDescendants()) do
                    if descendant:IsA("BasePart") or descendant:IsA("Decal") then
                        pcall(function()
                            descendant.LocalTransparencyModifier = 0
                            descendant.Transparency = 0
                        end)
                    end
                end

                v8 = v11
            end
        end
    end

    SetWorldTransparency = function(localTransparencyModifier)
        local v5, v6, v7 = pairs(currentCamera:GetChildren())
        local v8 = v7
        local v9 = v5
        local v10 = v6

        while true do
            local v11, v12 = v9(v10, v8)
            if v11 == nil then
                break
            end
            v8 = v11

            if v12 ~= localPlayer.Character then
                for k, descendant in pairs(v12:GetDescendants()) do
                    if descendant:IsA("BasePart") or descendant:IsA("Decal") then
                        pcall(function()
                            descendant.LocalTransparencyModifier = localTransparencyModifier
                            descendant.Transparency = localTransparencyModifier
                        end)
                    end
                end

                v8 = v11
            end
        end
    end

    SetCharacterTransparency = function(arg, localTransparencyModifier)
        if not arg then
            return
        end
        local v5, v6, v7 = pairs(arg:GetChildren())
        local v8 = v7
        local v9 = v5
        local v10 = v6

        while true do
            local v11, v12 = v9(v10, v8)
            if v11 == nil then
                break
            end
            v8 = v11

            if v12.Name == "Hat" then
                for k, descendant in pairs(v12:GetDescendants()) do
                    if descendant:IsA("BasePart") or descendant:IsA("Decal") then
                        pcall(function()
                            descendant.LocalTransparencyModifier = localTransparencyModifier
                            descendant.Transparency = localTransparencyModifier
                        end)
                    end
                end

                v8 = v11
            end

            if v12:IsA("BasePart") and tbl3[v12.Name] then
                pcall(function()
                    v12.LocalTransparencyModifier = localTransparencyModifier
                    v12.Transparency = localTransparencyModifier
                end)
            end

            if v12:IsA("Tool") or v12:IsA("Model") then
                local isBasePart = v12:IsA("BasePart")
                local descendants = isBasePart

                if isBasePart then
                    local tbl8 = {}
                    descendants = tbl8
                    tbl8[1] = v12
                end

                if not descendants then
                    descendants = v12:GetDescendants()
                end

                for k, descendant in pairs(descendants) do
                    if descendant:IsA("BasePart") or descendant:IsA("Decal") then
                        pcall(function()
                            descendant.LocalTransparencyModifier = localTransparencyModifier
                            descendant.Transparency = localTransparencyModifier
                        end)
                    end
                end
            end
        end
    end

    ResetCharacterTransparency = function(arg)
        if not localPlayer.Character then
            return
        end

        if arg then
            local v5, v6, v7 = pairs(localPlayer.Character:GetChildren())
            local v8 = v7
            local v9 = v5
            local v10 = v6

            while true do
                local v11, v12 = v9(v10, v8)
                if v11 == nil then
                    break
                end
                v8 = v11

                if v12.Name == "Hat" then
                    for k, descendant in pairs(v12:GetDescendants()) do
                        if descendant:IsA("BasePart") or descendant:IsA("Decal") then
                            pcall(function()
                                descendant.LocalTransparencyModifier = 1
                                descendant.Transparency = 1
                            end)
                        end
                    end

                    v8 = v11
                end

                if v12:IsA("BasePart") and tbl3[v12.Name] then
                    pcall(function()
                        v12.LocalTransparencyModifier = 1
                        v12.Transparency = 1
                    end)
                end

                if v12:IsA("Tool") or v12:IsA("Model") then
                    local isBasePart = v12:IsA("BasePart")
                    local descendants = isBasePart

                    if isBasePart then
                        local tbl8 = {}
                        descendants = tbl8
                        tbl8[1] = v12
                    end

                    if not descendants then
                        descendants = v12:GetDescendants()
                    end

                    for k, descendant in pairs(descendants) do
                        if descendant:IsA("BasePart") or descendant:IsA("Decal") then
                            pcall(function()
                                descendant.LocalTransparencyModifier = 1
                                descendant.Transparency = 1
                            end)
                        end
                    end
                end
            end
        else
            SetCharacterTransparency(localPlayer.Character, 0)
        end
    end

    local function fn51()
        pcall(function()
            localPlayer.CameraMode = Enum.CameraMode.Classic

            if _G.Ox.InfinityZoom and _G.Ox.InfinityZoom.Enabled then
                localPlayer.CameraMinZoomDistance = 0
                localPlayer.CameraMaxZoomDistance = math.huge
            else
                localPlayer.CameraMinZoomDistance = 0.5
                localPlayer.CameraMaxZoomDistance = 128
            end
        end)

        ResetAllTransparency()

        if localPlayer.Character then
            ResetCharacterTransparency(false)
        end
    end

    local function fn52(enabled)
        local team = localPlayer.Team
        local flag4 = team and localPlayer.Team.Name == "Killer"

        if enabled and not flag4 then
            tbl2.Enabled = false
            fn(ThirdPersonToggle, false)
            return
        end

        tbl2.Enabled = enabled

        if _G.Ox.State.ThirdPersonConn then
            _G.Ox.State.ThirdPersonConn:Disconnect()
            _G.Ox.State.ThirdPersonConn = nil
        end

        if not enabled then
            fn51()
            return
        end

        -- set the camera up once, then only re-check 4x per second (the old version rewrote everything every frame)
        local function apply()
            pcall(function()
                if localPlayer.CameraMode ~= Enum.CameraMode.Classic then
                    localPlayer.CameraMode = Enum.CameraMode.Classic
                end
                if localPlayer.CameraMinZoomDistance < 7 then
                    localPlayer.CameraMinZoomDistance = 7
                end
                if localPlayer.CameraMaxZoomDistance < 128 then
                    localPlayer.CameraMaxZoomDistance = 128
                end
                local char = localPlayer.Character
                local head = char and char:FindFirstChild("Head")
                if head and head.LocalTransparencyModifier ~= 0 then
                    SetCharacterTransparency(char, 0)
                end
            end)
        end

        apply()
        SetWorldTransparency(1)

        local acc = 0
        _G.Ox.State.ThirdPersonConn = RunService.Heartbeat:Connect(function(dt)
            if not tbl2.Enabled then
                return
            end
            acc += dt
            if acc < 0.25 then
                return
            end
            acc = 0
            if localPlayer.Team and localPlayer.Team.Name == "Killer" then
                apply()
                return
            end
            tbl2.Enabled = false
            if _G.Ox.State.ThirdPersonConn then
                _G.Ox.State.ThirdPersonConn:Disconnect()
                _G.Ox.State.ThirdPersonConn = nil
            end
            fn51()
            fn(ThirdPersonToggle, false)
        end)
    end

    localPlayer:GetPropertyChangedSignal("Team"):Connect(function()
        local team = localPlayer.Team
        local name = team and localPlayer.Team.Name

        if name ~= "Killer" then
            if tbl2.Enabled then
                fn52(false)
                fn(ThirdPersonToggle, false)
            else
                fn51()
            end
        end
    end)

    localPlayer.CharacterAdded:Connect(function()
        task.wait(0.8)

        if tbl2.Enabled and localPlayer.Team and localPlayer.Team.Name == "Killer" then
            localPlayer.CameraMode = Enum.CameraMode.Classic
            localPlayer.CameraMinZoomDistance = 7
            localPlayer.CameraMaxZoomDistance = 128
        else
            fn51()
        end
    end)

    EnableUnlimitedVault = function()
        if _G.Ox.UnlimitedVaultEnabled then
            return
        end
        _G.Ox.UnlimitedVaultEnabled = true

        if _G.Ox.UnlimitedVaultConn then
            _G.Ox.UnlimitedVaultConn:Disconnect()
            _G.Ox.UnlimitedVaultConn = nil
        end

        for i, v5 in ipairs(CollectionService:GetTagged("Blocked")) do
            CollectionService:RemoveTag(v5, "Blocked")
        end

        _G.Ox.UnlimitedVaultConn = CollectionService:GetInstanceAddedSignal("Blocked"):Connect(function(arg)
            CollectionService:RemoveTag(arg, "Blocked")
        end)

    end

    DisableUnlimitedVault = function()
        _G.Ox.UnlimitedVaultEnabled = false

        if _G.Ox.UnlimitedVaultConn then
            _G.Ox.UnlimitedVaultConn:Disconnect()
            _G.Ox.UnlimitedVaultConn = nil
        end

    end

    local function fn53(arg)
        if arg then
            EnableUnlimitedVault()
        else
            DisableUnlimitedVault()
        end
    end

    localPlayer.CharacterAdded:Connect(function()
        task.wait(1)

        if _G.Ox.UnlimitedVaultEnabled then
            for i, v5 in ipairs(CollectionService:GetTagged("Blocked")) do
                CollectionService:RemoveTag(v5, "Blocked")
            end
        end
    end)

    task.spawn(function()
        if not game:IsLoaded() then
            game.Loaded:Wait()
        end

        local v5 = nil
        local n2 = 0

        while not v5 and n2 < 10 do
            n2 = n2 + 1

            local ok, result = pcall(function()
                local modules = ReplicatedStorage:WaitForChild("Modules", 5)
                if not modules then
                    return nil
                end
                local survivors = modules:WaitForChild("Survivors", 5)
                if not survivors then
                    return nil
                end
                local survivorAnimationsController = survivors:WaitForChild("SurvivorAnimationsController", 5)
                if not survivorAnimationsController then
                    return nil
                end
                return require(survivorAnimationsController)
            end)

            if ok and result then
                v5 = result
            else
                task.wait(1)
            end
        end

        if not v5 then
            return
        end
        local isFacingStraightEnough = v5._isFacingStraightEnough

        v5._isFacingStraightEnough = function(arg, arg2, arg3, arg4)
            if not _G.Ox.Config.Surv_PerfectVault then
                return isFacingStraightEnough(arg, arg2, arg3, arg4)
            end
            return true, 0
        end

        local validateFast = v5._validateFastVault
        if validateFast then
            v5._validateFastVault = function(a, b, c)
                if _G.Ox.Config.Surv_PerfectVault then
                    return true, "ok"
                end
                return validateFast(a, b, c)
            end
        end

        local onVaultAnimation = v5._onVaultAnimation

        v5._onVaultAnimation = function(arg, arg2, arg3, arg4)
            if not _G.Ox.Config.Surv_PerfectVault then
                return onVaultAnimation(arg, arg2, arg3, arg4)
            end
            return onVaultAnimation(arg, arg2, true, arg4)
        end
    end)

    local function fn54(arg)
        if not arg then
            return
        end
        arg:SetAttribute("Flowstate", true)

        if _G.Ox.FlowstateNoCD.Connection then
            _G.Ox.FlowstateNoCD.Connection:Disconnect()
            _G.Ox.FlowstateNoCD.Connection = nil
        end

        _G.Ox.FlowstateNoCD.Connection = arg:GetAttributeChangedSignal("Flowstate"):Connect(function()
            if not _G.Ox.FlowstateNoCD.Enabled then
                return
            end

            if arg:GetAttribute("Flowstate") == false then
                task.wait(0.05)
                arg:SetAttribute("Flowstate", true)
            end
        end)
    end

    local function fn55(enabled)
        _G.Ox.FlowstateNoCD.Enabled = enabled

        if _G.Ox.FlowstateNoCD.Connection then
            _G.Ox.FlowstateNoCD.Connection:Disconnect()
            _G.Ox.FlowstateNoCD.Connection = nil
        end

        if _G.Ox.FlowstateNoCD.CharAddedConn then
            _G.Ox.FlowstateNoCD.CharAddedConn:Disconnect()
            _G.Ox.FlowstateNoCD.CharAddedConn = nil
        end

        if not enabled then
            local character = localPlayer.Character

            if character then
                character:SetAttribute("Flowstate", false)
            end

            return
        end

        fn54(localPlayer.Character)

        _G.Ox.FlowstateNoCD.CharAddedConn = localPlayer.CharacterAdded:Connect(function(character)
            if not _G.Ox.FlowstateNoCD.Enabled then
                return
            end
            task.wait(1)
            fn54(character)
        end)

    end

    fn14 = function(enabled)
        _G.Ox.NoFall.Enabled = enabled
    end

    local connection = nil

    local function fn57()
        if connection then
            return
        end
        local character = localPlayer.Character
        if not character then
            return
        end
        local humanoid = character:FindFirstChildOfClass("Humanoid")
        if not humanoid then
            return
        end
        local animator = humanoid:FindFirstChildOfClass("Animator")
        if not animator then
            return
        end

        connection = animator.AnimationPlayed:Connect(function(arg)
            if arg.Animation and arg.Animation.AnimationId:find("95836365038528") then
                arg:Stop(0)
            end
        end)
    end

    local function fn58()
        if connection then
            pcall(function()
                connection:Disconnect()
            end)

            connection = nil
        end
    end

    task.spawn(function()
        while _G.Ox.ScriptAlive do
            task.wait(1.5)
            if not _G.Ox.ScriptAlive then
                break
            end

            if _G.Ox.SelfHeal.Enabled and localPlayer.Team and localPlayer.Team.Name ~= "Killer" then
                local character = localPlayer.Character

                if character then
                    local checkInterractable = character:FindFirstChild("CheckInterractable")
                    local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
                    local humanoid = character:FindFirstChildOfClass("Humanoid")
                    local flag4 = false

                    if checkInterractable and (checkInterractable:GetAttribute("isVaulting") or checkInterractable:GetAttribute("isRepairing") or checkInterractable:GetAttribute("isUnhooking") or checkInterractable:GetAttribute("isHealing") or checkInterractable:GetAttribute("isSliding")) then
                        flag4 = true
                    end

                    if not flag4 and humanoidRootPart and humanoid and humanoid.Health < humanoid.MaxHealth and humanoidRootPart:GetAttribute("CanGetHealed") ~= false then
                        pcall(function()
                            local remotes = ReplicatedStorage:FindFirstChild("Remotes")

                            if remotes and remotes:FindFirstChild("Healing") then
                                _G.Ox.Net.heal(humanoidRootPart, true)
                            end
                        end)
                    end
                end
            end
        end
    end)

    localPlayer.CharacterRemoving:Connect(function()
        fn58()
    end)

    localPlayer.CharacterAdded:Connect(function()
        task.wait(5)

        if _G.Ox.SelfHeal.Enabled then
            fn57()
        end
    end)

    fn16 = function(enabled)
        _G.Ox.SelfHeal.Enabled = enabled

        if enabled then
            if localPlayer.Team and localPlayer.Team.Name == "Killer" then

                _G.Ox.SelfHeal.Enabled = false

                if SelfHealToggle then
                    fn(SelfHealToggle, false)
                end

                return
            end

            fn57()

        else
            fn58()
            pcall(function()
                local c = localPlayer.Character
                local h = c and c:FindFirstChild("HumanoidRootPart")
                if h then
                    _G.Ox.Net.heal(h, false)
                end
            end)

        end
    end

    fn17 = function()
        local function fn59()
            repeat
                task.wait()
            until localPlayer.Character and localPlayer.Character:FindFirstChild("HumanoidRootPart") and localPlayer.Character:FindFirstChild("Right Leg")

            task.wait(0.1)
            local character = localPlayer.Character

            pcall(function()
                character.Head.Transparency = 1
                local face = character.Head:FindFirstChild("face")

                if face then
                    face:Destroy()
                end

                character["Right Leg"].Transparency = 1
                local meshPart = Instance.new("MeshPart")
                meshPart.Name = "KorlessHead"
                meshPart.Size = Vector3.new(0.85, 0.85, 0.85)
                meshPart.CanCollide = false
                meshPart.MeshId = "rbxassetid://902942096"
                meshPart.TextureID = "rbxassetid://902843398"
                meshPart.CFrame = character["Right Leg"].CFrame * CFrame.new(0, 0.7, 0)
                meshPart.Parent = character
                local weldConstraint = Instance.new("WeldConstraint")
                weldConstraint.Part0 = character["Right Leg"]
                weldConstraint.Part1 = meshPart
                weldConstraint.Parent = meshPart
            end)
        end

        fn59()

        if _G.Ox.KorlessMorph.Connection then
            _G.Ox.KorlessMorph.Connection:Disconnect()
        end

        _G.Ox.KorlessMorph.Connection = localPlayer.CharacterAdded:Connect(function()
            task.wait(1)
            fn59()
        end)
    end

    fn18 = function()
        local character = localPlayer.Character
        local humanoidRootPart = character and localPlayer.Character:FindFirstChild("HumanoidRootPart")
        if not humanoidRootPart then
            return
        end
        local v5 = nil

        for i, descendant in ipairs(workspace:GetDescendants()) do
            if string.lower(descendant.Name) == "fininshline" and descendant:IsA("BasePart") then
                v5 = descendant
                break
            end
        end

        if not v5 then

            return
        end

        humanoidRootPart.CFrame = v5.CFrame + Vector3.new(0, 5, 0)

    end

    SetupNextKillerIndicator = function()
        if _G.Ox.NextKiller.IndicatorGui then
            _G.Ox.NextKiller.IndicatorGui:Destroy()
        end

        _G.Ox.NextKiller.IndicatorGui = Instance.new("ScreenGui")
        _G.Ox.NextKiller.IndicatorGui.Name = "NextKillerIndicator"
        _G.Ox.NextKiller.IndicatorGui.ResetOnSpawn = false
        _G.Ox.NextKiller.IndicatorGui.Parent = localPlayer:WaitForChild("PlayerGui")
    end

    StartNextKiller = function()
        if _G.Ox.NextKiller.IndicatorGui then
            return
        end
        SetupNextKillerIndicator()

        task.spawn(function()
            while _G.Ox.NextKiller.Enabled and _G.Ox.NextKiller.IndicatorGui do
                local nextKillerDisplay = _G.Ox.NextKiller.IndicatorGui:FindFirstChild("NextKillerDisplay")
                local v5 = nextKillerDisplay

                if not nextKillerDisplay then
                    local textLabel = Instance.new("TextLabel")
                    v5 = textLabel
                    textLabel.Name = "NextKillerDisplay"
                    textLabel.Size = UDim2.new(0, 150, 0, 22)
                    textLabel.Position = UDim2.new(0.5, 0, 0, 10)
                    textLabel.AnchorPoint = Vector2.new(0.5, 0)
                    textLabel.BackgroundTransparency = 0.15
                    textLabel.BackgroundColor3 = Color3.fromRGB(10, 10, 12)
                    textLabel.TextColor3 = Color3.fromRGB(220, 220, 230)
                    textLabel.Font = Enum.Font.GothamMedium
                    textLabel.TextSize = 11
                    textLabel.RichText = true
                    textLabel.Parent = _G.Ox.NextKiller.IndicatorGui
                    local uiCorner = Instance.new("UICorner")
                    uiCorner.CornerRadius = UDim.new(0, 6)
                    uiCorner.Parent = textLabel
                    local uiStroke3 = Instance.new("UIStroke")
                    uiStroke3.Thickness = 1
                    uiStroke3.Color = Color3.fromRGB(60, 60, 70)
                    uiStroke3.Transparency = 0.3
                    uiStroke3.Parent = textLabel
                end

                local players = Players:GetPlayers()

                table.sort(players, function(arg, arg2)
                    local attribute = arg:GetAttribute("AllowKiller")
                    local flag4 = attribute or false
                    local attribute2 = arg2:GetAttribute("AllowKiller")
                    local flag5 = attribute2 or false
                    if flag4 ~= flag5 then
                        return flag4
                    end
                    local attribute3 = arg:GetAttribute("KillerChance")
                    local n2 = attribute3 or 0
                    local attribute4 = arg2:GetAttribute("KillerChance")
                    local n3 = attribute4 or 0
                    local flag6 = n3 < n2
                    return flag6
                end)

                local v6 = players[1]

                if v6 then
                    local name = v6 == localPlayer and "<font color='#ff5555'>KAMU</font>" or v6.Name
                    v5.Text = "Next Killer: " .. name
                else
                    v5.Text = "Next Killer: <font color='#888888'>Waiting...</font>"
                end

                task.wait(1.5)
            end
        end)
    end

    StopNextKiller = function()
        if _G.Ox.NextKiller.IndicatorGui then
            _G.Ox.NextKiller.IndicatorGui:Destroy()
            _G.Ox.NextKiller.IndicatorGui = nil
        end
    end

    fn19 = function(enabled)
        _G.Ox.NextKiller.Enabled = enabled

        if enabled then
            StartNextKiller()

        else
            StopNextKiller()

        end
    end

    local function fn59()
        local mapPredictUI = CoreGui:FindFirstChild("MapPredictUI")

        if mapPredictUI then
            mapPredictUI:Destroy()
        end
    end

    local function createScreenGui()
        local mapPredictUI = CoreGui:FindFirstChild("MapPredictUI")
        if mapPredictUI then
            return mapPredictUI
        end
        local screenGui2 = Instance.new("ScreenGui")
        screenGui2.Name = "MapPredictUI"
        screenGui2.ResetOnSpawn = false
        screenGui2.IgnoreGuiInset = true
        screenGui2.Parent = CoreGui
        local textLabel = Instance.new("TextLabel")
        textLabel.Name = "NextMapDisplay"
        textLabel.Size = UDim2.new(0, 220, 0, 22)
        textLabel.Position = UDim2.new(0.5, 0, 0, 36)
        textLabel.AnchorPoint = Vector2.new(0.5, 0)
        textLabel.BackgroundTransparency = 0.15
        textLabel.BackgroundColor3 = Color3.fromRGB(10, 10, 12)
        textLabel.TextColor3 = Color3.fromRGB(220, 220, 230)
        textLabel.Font = Enum.Font.GothamMedium
        textLabel.TextSize = 11
        textLabel.RichText = true
        textLabel.Text = "Next Map: <font color='#888888'>Waiting...</font>"
        textLabel.Parent = screenGui2
        local uiCorner = Instance.new("UICorner")
        uiCorner.CornerRadius = UDim.new(0, 6)
        uiCorner.Parent = textLabel
        local uiStroke3 = Instance.new("UIStroke")
        uiStroke3.Thickness = 1
        uiStroke3.Color = Color3.fromRGB(60, 60, 70)
        uiStroke3.Transparency = 0.3
        uiStroke3.Parent = textLabel
        return screenGui2
    end

    local function fn60()
        local map = workspace:FindFirstChild("Map")
        if not map then
            return nil
        end

        if map:FindFirstChild("random shakes") or map:FindFirstChild("SCP-173 Room") or map:FindFirstChild("SCP-205 Room") then
            return "Site 68"
        end

        if map:FindFirstChild("HooksMeat") then
            return "BLOODBATH! Club"
        end

        if map:FindFirstChild("Gate") and map.Gate:FindFirstChild("vfx") then
            return "Firelink Shrine"
        end

        if map:FindFirstChild("Bldg_Addon_RooftopUnit_A") or map:FindFirstChild("Rooftop") then
            return "Mercy Hospital Rooftop"
        end

        if map:FindFirstChild("White Armored Car") then
            return "Mount Massive Asylum"
        end

        if map:FindFirstChild("Dumbster") then
            return "The Bay Harbor"
        end

        if map:FindFirstChild("water pump") then
            return "Valdelobos Village"
        end

        if not map:FindFirstChild("LargeBoulder01") then
            return nil
        end
        return "Woodview Cabin"
    end

    fn20 = function(enabled)
        _G.Ox.MapPredict.Enabled = enabled

        if enabled then
            task.spawn(function()
                local v5 = nil
                local flag4 = false

                while _G.Ox.MapPredict.Enabled do
                    local v6 = createScreenGui()
                    local nextMapDisplay = v6:FindFirstChild("NextMapDisplay")
                    local enabled2 = false

                    pcall(function()
                        local team = localPlayer.Team
                        local flag5 = team and localPlayer.Team.Name == "Spectator"
                        enabled2 = flag5
                    end)

                    v6.Enabled = enabled2

                    if enabled2 and nextMapDisplay then
                        local flag5 = workspace:FindFirstChild("Map") ~= nil
                        local nextMap = fn60()

                        if flag4 and not flag5 then
                            local nextMap2 = v5 or "Unknown"
                            nextMapDisplay.Text = "Next Map: " .. nextMap2
                        elseif flag5 and nextMap then
                            v5 = nextMap
                            nextMapDisplay.Text = "Next Map: " .. nextMap
                        elseif flag5 and not nextMap then
                            nextMapDisplay.Text = "Next Map: Unknown"
                        else
                            nextMapDisplay.Text = "Next Map: <font color='#888888'>Waiting...</font>"
                        end

                        flag4 = flag5
                    end

                    task.wait(0.5)
                end

                fn59()
            end)

        else
            fn59()

        end
    end

    local function fn61(arg)
        local v5 = tostring
        local str = arg or ""
        return v5(str):gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;")
    end

    local function fn62(arg)
        local v5 = tostring
        local str = arg or ""
        local match, v6 = v5(str):match("^(.+)%s+(%d+)$")
        if not match then
            return nil
        end
        local str2 = match:gsub("^%s+", ""):gsub("%s+$", "")
        if str2 == "" then
            return nil
        end

        if not ({
            head = true,
            torso = true,
            humanoid = true,
            humanoidrootpart = true,
            ["left arm"] = true,
            ["right arm"] = true,
            ["left leg"] = true,
            ["right leg"] = true,
        })[str2:lower()] then
            return str2, v6
        end

        return nil
    end

    local function fn63()
        for i, player in ipairs(Players:GetPlayers()) do
            local team = player.Team
            local name = team and player.Team.Name
            if name and name:lower():find("killer") then
                return player
            end
        end

        return nil
    end

    local function fn64(arg)
        if not arg then
            return {}
        end
        local character = arg.Character
        local v5 = character or workspace:FindFirstChild(arg.Name) or workspace:FindFirstChild(arg.DisplayName)
        if not v5 then
            return {}
        end
        local tbl8 = {}
        local tbl9 = {}

        for i, child in ipairs(v5:GetChildren()) do
            local v6, v7 = fn62(child.Name)

            if v6 and not tbl9[v6] then
                tbl9[v6] = true
                table.insert(tbl8, {Name = v6, Level = v7})
            end
        end

        table.sort(tbl8, function(arg2, arg3)
            local flag4 = tostring(arg2.Name) < tostring(arg3.Name)
            return flag4
        end)

        return tbl8
    end

    local function fn65()
        local v5 = fn63()
        local name = v5

        if v5 then
            local displayName = v5.DisplayName
            name = displayName or v5.Name
        end

        if not name then
            name = "Unknown"
        end

        local v6 = fn64(v5)
        local v7 = v6

        if #v6 == 0 then
            for i, player in ipairs(Players:GetPlayers()) do
                local v8 = fn64(player)

                if #v8 > 0 then
                    local displayName = player.DisplayName
                    local name2 = displayName or player.Name
                    name = name2
                    v7 = v8
                    break
                end
            end
        end

        local tbl8 = {
            "Killer Perks [<font color=\"rgb(255,80,80)\">" .. fn61(name) .. "</font>]",
        }

        if #v7 == 0 then
            table.insert(tbl8, "<font color=\"rgb(200,200,200)\">- Waiting for perk data...</font>")
        else
            for i = 1, math.min(#v7, 4) do
                local v8 = v7[i]
                local level = v8.Level
                local str = level and " lvl " .. tostring(v8.Level) or ""
                table.insert(tbl8, "<font color=\"rgb(200,200,200)\">- " .. fn61(v8.Name .. str) .. "</font>")
            end
        end

        return table.concat(tbl8, "\n"), #v7
    end

    local function fn66()
        if _G.Ox.KillerPerks.Gui then
            pcall(function()
                _G.Ox.KillerPerks.Gui:Destroy()
            end)

            _G.Ox.KillerPerks.Gui = nil
        end

        if not _G.Ox.KillerPerks.Enabled then
            return
        end
        local screenGui2 = Instance.new("ScreenGui")
        screenGui2.Name = "NEX_KillerPerksGui"
        screenGui2.ResetOnSpawn = false
        screenGui2.IgnoreGuiInset = true
        screenGui2.Parent = CoreGui
        local frame2 = Instance.new("Frame")
        frame2.Name = "Holder"
        frame2.Size = UDim2.new(0, 180, 0, 85)
        frame2.Position = UDim2.new(0.08, 0, 0.22, 0)
        frame2.BackgroundTransparency = 1
        frame2.Active = true
        frame2.Parent = screenGui2
        local frame3 = Instance.new("Frame")
        frame3.Name = "Panel"
        frame3.Size = UDim2.new(1, 0, 1, 0)
        frame3.BackgroundColor3 = Color3.fromRGB(10, 10, 12)
        frame3.BackgroundTransparency = 0.15
        frame3.BorderSizePixel = 0
        frame3.Parent = frame2
        Instance.new("UICorner", frame3).CornerRadius = UDim.new(0, 6)
        local uiStroke3 = Instance.new("UIStroke")
        uiStroke3.Color = Color3.fromRGB(60, 60, 70)
        uiStroke3.Thickness = 1
        uiStroke3.Transparency = 0.3
        uiStroke3.Parent = frame3
        local frame4 = Instance.new("Frame")
        frame4.Size = UDim2.new(1, 0, 0, 24)
        frame4.BackgroundColor3 = Color3.fromRGB(15, 15, 20)
        frame4.BorderSizePixel = 0
        frame4.Parent = frame3
        Instance.new("UICorner", frame4).CornerRadius = UDim.new(0, 6)
        local textLabel = Instance.new("TextLabel")
        textLabel.Size = UDim2.new(1, -60, 1, 0)
        textLabel.Position = UDim2.new(0, 8, 0, 0)
        textLabel.BackgroundTransparency = 1
        textLabel.Font = Enum.Font.GothamSemibold
        textLabel.Text = "Killer Perks Info"
        textLabel.TextColor3 = Color3.fromRGB(220, 220, 230)
        textLabel.TextSize = 11
        textLabel.TextXAlignment = Enum.TextXAlignment.Left
        textLabel.Parent = frame4

        local function createTextButton(text, arg, arg2)
            local textButton = Instance.new("TextButton")
            textButton.Size = UDim2.new(0, 26, 0, 16)
            textButton.Position = UDim2.new(1, arg, 0, 4)
            local color = arg2 or Color3.fromRGB(25, 25, 30)
            textButton.BackgroundColor3 = color
            textButton.BorderSizePixel = 0
            textButton.Font = Enum.Font.GothamMedium
            textButton.Text = text
            textButton.TextColor3 = Color3.fromRGB(200, 200, 210)
            textButton.TextSize = 9
            textButton.Parent = frame4
            Instance.new("UICorner", textButton).CornerRadius = UDim.new(0, 4)
            return textButton
        end

        local Minimize = createTextButton("Minimize", -54, Color3.fromRGB(30, 30, 40))
        local Close = createTextButton("Close", -28, Color3.fromRGB(40, 25, 25))
        local textLabel2 = Instance.new("TextLabel")
        textLabel2.Name = "KillerPerksText"
        textLabel2.Size = UDim2.new(1, -14, 1, -32)
        textLabel2.Position = UDim2.new(0, 8, 0, 28)
        textLabel2.BackgroundTransparency = 1
        textLabel2.Font = Enum.Font.GothamMedium
        textLabel2.RichText = true
        textLabel2.TextXAlignment = Enum.TextXAlignment.Left
        textLabel2.TextYAlignment = Enum.TextYAlignment.Top
        textLabel2.TextColor3 = Color3.fromRGB(220, 220, 230)
        textLabel2.TextSize = 11
        textLabel2.TextWrapped = false
        textLabel2.Parent = frame3

        Minimize.MouseButton1Click:Connect(function()
            local killerPerks = _G.Ox.KillerPerks
            local minimized

            if _G.Ox.KillerPerks.Minimized then
                minimized = false
            else
                minimized = true
            end

            killerPerks.Minimized = minimized
            local visible

            if _G.Ox.KillerPerks.Minimized then
                visible = false
            else
                visible = true
            end

            textLabel2.Visible = visible
            local minimized2 = _G.Ox.KillerPerks.Minimized
            local text = minimized2 and "Show" or "Minimize"
            Minimize.Text = text
            local minimized3 = _G.Ox.KillerPerks.Minimized
            local udim2 = minimized3 and UDim2.new(0, 180, 0, 24) or UDim2.new(0, 180, 0, 85)
            frame2.Size = udim2
        end)

        Close.MouseButton1Click:Connect(function()
            _G.Ox.KillerPerks.Enabled = false

            if _G.Ox.KillerPerks.Gui then
                pcall(function()
                    _G.Ox.KillerPerks.Gui:Destroy()
                end)

                _G.Ox.KillerPerks.Gui = nil
            end

            if KillerPerksToggle then
                fn(KillerPerksToggle, false)
            end
        end)

        local flag4 = false
        local position = nil
        local position2 = nil

        frame2.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                flag4 = true
                position = input.Position
                position2 = frame2.Position

                input.Changed:Connect(function()
                    if input.UserInputState == Enum.UserInputState.End then
                        flag4 = false
                    end
                end)
            end
        end)

        UserInputService.InputChanged:Connect(function(input)
            if not flag4 or not position or not position2 then
                return
            end

            if input.UserInputType ~= Enum.UserInputType.MouseMovement and input.UserInputType ~= Enum.UserInputType.Touch then
                return
            end
            local n2 = input.Position - position
            frame2.Position = UDim2.new(position2.X.Scale, position2.X.Offset + n2.X, position2.Y.Scale, position2.Y.Offset + n2.Y)
        end)

        screenGui2.Parent = CoreGui
        _G.Ox.KillerPerks.Gui = screenGui2

        task.spawn(function()
            while _G.Ox.KillerPerks.Enabled and _G.Ox.KillerPerks.Gui do
                if not _G.Ox.KillerPerks.Minimized then
                    local v5, v6 = fn65()
                    textLabel2.Text = v5
                    local n2 = math.max(2, math.min(v6 + 1, 5))
                    frame2.Size = UDim2.new(0, 180, 0, math.max(65, 28 + n2 * 15))
                end

                task.wait(1)
            end
        end)
    end

    fn21 = function(enabled)
        _G.Ox.KillerPerks.Enabled = enabled

        if enabled then
            fn66()

        else
            if _G.Ox.KillerPerks.Gui then
                pcall(function()
                    _G.Ox.KillerPerks.Gui:Destroy()
                end)

                _G.Ox.KillerPerks.Gui = nil
            end

        end
    end

    local function fn67(arg)
        local humanoidRootPart = arg:FindFirstChild("HumanoidRootPart")
        if not humanoidRootPart then
            return nil
        end
        local stunRingUI = humanoidRootPart:FindFirstChild("StunRingUI")

        if stunRingUI then
            stunRingUI:Destroy()
        end

        local billboardGui = Instance.new("BillboardGui")
        billboardGui.Name = "StunRingUI"
        billboardGui.Adornee = humanoidRootPart
        billboardGui.AlwaysOnTop = true
        billboardGui.Size = UDim2.new(0, 40, 0, 40)
        billboardGui.StudsOffsetWorldSpace = Vector3.new(0, 4.5, 0)
        billboardGui.ResetOnSpawn = false
        billboardGui.LightInfluence = 0
        billboardGui.Parent = humanoidRootPart
        local imageLabel = Instance.new("ImageLabel", billboardGui)
        imageLabel.Size = UDim2.new(1, 0, 1, 0)
        imageLabel.Position = UDim2.new(0, 0, 0, 0)
        imageLabel.BackgroundTransparency = 1
        imageLabel.Image = "rbxassetid://129594563448607"
        imageLabel.ScaleType = Enum.ScaleType.Fit
        billboardGui.Enabled = false

        return billboardGui, task.spawn(function()
            local n2 = 0
            local currentCamera2 = workspace.CurrentCamera

            while billboardGui and billboardGui.Parent do
                if billboardGui.Enabled then
                    local rotation = (n2 + 6) % 360
                    n2 = rotation
                    imageLabel.Rotation = rotation
                    local n3 = math.clamp(math.floor(600 / (currentCamera2.CFrame.Position - humanoidRootPart.Position).Magnitude), 22, 44)
                    billboardGui.Size = UDim2.new(0, n3, 0, n3)
                end

                task.wait(0.1)
            end
        end)
    end

    local function fn68(arg)
        if not arg or _G.Ox.Stun.Data[arg] then
            return
        end
        local v5, v6 = fn67(arg)
        if not v5 then
            return
        end

        local tbl8 = {
            stunRing = v5,
            stunSpinThread = v6,
            _stunTimer = nil,
            extraConns = {},
        }

        _G.Ox.Stun.Data[arg] = tbl8

        local function fn69(arg2)
            if not tbl8.stunRing then
                return
            end
            tbl8.stunRing.Enabled = true

            if tbl8._stunTimer then
                task.cancel(tbl8._stunTimer)
            end

            tbl8._stunTimer = task.delay(arg2, function()
                if tbl8.stunRing then
                    tbl8.stunRing.Enabled = false
                end
            end)
        end

        local connection2 = arg:GetAttributeChangedSignal("IsStunned"):Connect(function()
            if arg:GetAttribute("IsStunned") == true then
                fn69(2.2)
            end
        end)

        local connection3 = arg:GetAttributeChangedSignal("Immobile"):Connect(function()
            if arg:GetAttribute("Immobile") == true then
                fn69(2.2)
            end
        end)

        table.insert(tbl8.extraConns, connection2)
        table.insert(tbl8.extraConns, connection3)
    end

    local function fn69(arg)
        local v5 = _G.Ox.Stun.Data[arg]

        if v5 then
            if v5._stunTimer then
                task.cancel(v5._stunTimer)
            end

            if v5.stunSpinThread then
                task.cancel(v5.stunSpinThread)
            end

            if v5.stunRing then
                v5.stunRing:Destroy()
            end

            if v5.extraConns then
                for i, extraConn in ipairs(v5.extraConns) do
                    pcall(function()
                        extraConn:Disconnect()
                    end)
                end
            end

            _G.Ox.Stun.Data[arg] = nil
        end
    end

    local function fn70()
        if not _G.Ox.Stun.Enabled then
            return
        end

        for i, player in ipairs(Players:GetPlayers()) do
            if IsKiller(player) and player.Character then
                fn68(player.Character)
            end
        end
    end

    Players.PlayerAdded:Connect(function(player)
        if not _G.Ox.Stun.Enabled then
            return
        end

        player.CharacterAdded:Connect(function(character)
            task.wait(0.5)

            if _G.Ox.Stun.Enabled and IsKiller(player) then
                fn68(character)
            end
        end)

        task.wait(0.5)

        if _G.Ox.Stun.Enabled and IsKiller(player) and player.Character then
            fn68(player.Character)
        end
    end)

    Players.PlayerAdded:Connect(function(player)
        player:GetPropertyChangedSignal("Team"):Connect(function()
            if not _G.Ox.Stun.Enabled then
                return
            end
            task.wait(0.5)

            if IsKiller(player) and player.Character then
                fn69(player.Character)
                task.wait(0.1)
                fn68(player.Character)
            end
        end)
    end)

    Players.PlayerAdded:Connect(function(player)
        task.wait(0.5)

        if _G.Ox.Stun.Enabled then
            fn70()
        end
    end)

    localPlayer.CharacterAdded:Connect(function()
        task.wait(1.5)

        if _G.Ox.Stun.Enabled then
            fn70()
        end
    end)

    task.spawn(function()
        local v5, v6, v7, v8, v9, v10, humanoidRootPart, n2
        n2 = 1

        while true do
            if n2 == 1 then
                if _G.Ox.ScriptAlive then
                    n2 = 2
                else
                    n2 = 9
                end
            elseif n2 == 2 then
                task.wait(5)

                if _G.Ox.ScriptAlive then
                    n2 = 3
                else
                    n2 = 9
                end
            elseif n2 == 3 then
                if _G.Ox.Stun.Enabled then
                    n2 = 4
                else
                    n2 = 1
                end
            elseif n2 == 4 then
                v5, v6, v7 = ipairs(Players:GetPlayers())
                v8 = v7
                n2 = 5
            elseif n2 == 5 then
                v9, v10 = v5(v6, v8)

                if v9 == nil then
                    n2 = 1
                else
                    n2 = 6
                end
            elseif n2 == 6 then
                v8 = v9

                if IsKiller(v10) and v10.Character then
                    n2 = 7
                else
                    n2 = 5
                end
            elseif n2 == 7 then
                humanoidRootPart = v10.Character:FindFirstChild("HumanoidRootPart")

                if humanoidRootPart and not humanoidRootPart:FindFirstChild("StunRingUI") then
                    n2 = 8
                else
                    n2 = 5
                end
            elseif n2 == 8 then
                fn68(v10.Character)
                n2 = 5
            elseif n2 == 9 then
                return
            end
        end
    end)

    fn22 = function(enabled)
        _G.Ox.Stun.Enabled = enabled

        if enabled then
            for k in pairs(_G.Ox.Stun.Data) do
                fn69(k)
            end

            _G.Ox.Stun.Data = {}
            task.wait(0.5)
            fn70()

        else
            for k in pairs(_G.Ox.Stun.Data) do
                fn69(k)
            end

            _G.Ox.Stun.Data = {}

        end
    end

    local function buildSection(page, name, icon)
        local section = page:CreateSection(name, icon)

        pcall(function()
            section:_gb()
        end)
        return section
    end

    MainTab = v:CreateTab("Main", false, false)
    M_Page = MainTab:CreatePage("Main")
    SurvivorTab = v:CreateTab("Survivor", false, false)
    S_Page = SurvivorTab:CreatePage("Survivor")
    KillerTab = v:CreateTab("Killer", false, false)
    K_Page = KillerTab:CreatePage("Killer")
    local TrapPage = S_Page -- Trap now lives in the Survivor tab

    MovementCard = buildSection(M_Page, "Movement", "move")
    CameraCard = buildSection(M_Page, "Camera Settings", "camera")
    StreamerCard = buildSection(M_Page, "Streamer Mode", "eye-off")
    UtilityCard = buildSection(M_Page, "Players Utility", "user-cog")
    PumpkinCard = buildSection(S_Page, "Pumpkin (Halloween)", "ghost")
    CrosshairBox = buildSection(M_Page, "Crosshair", "crosshair")

    GenCard = buildSection(S_Page, "Generator Settings", "plug-zap")
    VaultCard = buildSection(S_Page, "Vault & Pallet Slide", "move")
    AbilityCard = buildSection(S_Page, "Survivor Ability", "zap")
    FakePerksCard = buildSection(S_Page, "Fake Perks", "sparkles")
    SurvivorHealCard = buildSection(S_Page, "Heal & Bandage", "heart-pulse")
    PistolSection = buildSection(S_Page, "Twist of Fate & Flashlight", "crosshair")

    KillerAimbotCard = buildSection(K_Page, "Killer Aimbot", "swords")
    VeilCard = buildSection(K_Page, "Silent Veil", "arrow-up-right")
    AutoAttackCard = buildSection(K_Page, "Auto Attack", "swords")
    ObjectivesCard = buildSection(K_Page, "Hook & Generators", "bot")
    KillerAbilityCard = buildSection(K_Page, "Killer Ability", "zap")

    local v7 = MovementCard:AddToggle("Auto Run PC", false, function(pc)
        _G.Ox.AutoRun.PC = pc

        if pc then
            task.spawn(function()
                while _G.Ox.AutoRun.PC do
                    VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.LeftShift, false, localPlayer:GetMouse())
                    task.wait(0.1)
                end
            end)
        else
            VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.LeftShift, false, localPlayer:GetMouse())
        end
    end, {Flag = "AutoRunPc"})

    AutoRunPCToggle = v7

    local v8 = MovementCard:AddToggle("Auto Run Mobile", false, function(mobile)
        _G.Ox.AutoRun.Mobile = mobile

        if mobile then
            fn5()
        else
            fn6()
        end
    end, {Flag = "AutoRunMobile"})

    AutoRunMobileToggle = v8

    local v9 = MovementCard:AddToggle("Enable Speed Boost", false, function(enabled)
        _G.Ox.Speed.Enabled = enabled
    end, {Flag = "SpeedBoost"})

    SpeedToggle = v9

    MovementCard:AddSlider("SpeedAmount", 0.1, 3, 0.1, function(value)
        _G.Ox.Speed.Value = value
    end, {Increment = 0.1, Flag = "SpeedAmount"})

    _G.Ox.SetThirdPerson = fn52

    local v19 = CameraCard:AddToggle("Infinity Zoom Out", false, function(arg)
        fn44(arg)
    end, {Flag = "InfinityZoom"})

    InfinityToggle = v19

    local v20 = CameraCard:AddToggle("Camera FOV", false, function(arg)
        fn45(arg)
    end, {Flag = "CameraFov"})

    FOVToggle = v20

    local v23 = StreamerCard:AddToggle("Streamer Mode", false, function(arg)
        fn42(arg)
    end, {Flag = "StreamerMode"})

    StreamerToggle = v23

    local v27 = UtilityCard:AddToggle("Moonwalk GUI", false, function(arg)
        if arg then
            if not _G.Ox.Moonwalk.Gui then
                CreateMoonwalkGUI()
            end

            _G.Ox.Moonwalk.Gui.Enabled = true
            _G.Ox.Moonwalk.GuiVisible = true
            UpdateMoonwalkGUI(_G.Ox.Moonwalk.Enabled)

        else
            if _G.Ox.Moonwalk.Enabled then
                StopMoonwalk()

                if MoonwalkPCToggle then
                    fn(MoonwalkPCToggle, false)
                end
            end

            if _G.Ox.Moonwalk.Gui then
                _G.Ox.Moonwalk.Gui.Enabled = false
                _G.Ox.Moonwalk.GuiVisible = false
            end

        end
    end, {Flag = "MoonwalkGui"})

    MoonwalkGUIToggle = v27

    local v28 = UtilityCard:AddToggle("Moonwalk PC", false, function(arg)
        if arg then
            StartMoonwalk()
        else
            StopMoonwalk()
        end

        UpdateMoonwalkGUI(_G.Ox.Moonwalk.Enabled)
    end, {Flag = "MoonwalkPC"})

    MoonwalkPCToggle = v28

    _G.Ox.Act = {owner = nil, untilT = 0}
    function _G.Ox.Act.try(name, secs)
        local A = _G.Ox.Act
        if A.owner and A.owner ~= name and os.clock() < A.untilT then
            return false
        end
        A.owner, A.untilT = name, os.clock() + (secs or 30)
        return true
    end
    function _G.Ox.Act.done(name)
        if _G.Ox.Act.owner == name then
            _G.Ox.Act.owner = nil
        end
    end

    _G.Ox.Walker = (function()
        local PathfindingService = game:GetService("PathfindingService")
        local W = {}

        local function me()
            local char = localPlayer.Character
            return char, char and char:FindFirstChildOfClass("Humanoid"), char and char:FindFirstChild("HumanoidRootPart")
        end

        local function groundPoint(pos)
            local params = RaycastParams.new()
            params.FilterType = Enum.RaycastFilterType.Exclude
            params.FilterDescendantsInstances = {localPlayer.Character}
            local hit = workspace:Raycast(pos + Vector3.new(0, 4, 0), Vector3.new(0, -40, 0), params)
            return hit and hit.Position or pos
        end

        function W.walkTo(goal, opts)
            opts = opts or {}
            local stop = opts.stop or 3
            local timeout = opts.timeout or 45
            local active = opts.active or function()
                return true
            end
            local started = os.clock()
            local replans = 0
            local agent = {AgentRadius = 3, AgentHeight = 5.5, AgentCanJump = true, WaypointSpacing = 4}

            while os.clock() - started < timeout do
                local _, hum, root = me()
                if not (hum and root) or hum.Health <= 0 then
                    return false, "dead"
                end
                if not active() then
                    return false, "inactive"
                end
                if (root.Position - goal).Magnitude <= stop then
                    return true
                end

                local path = PathfindingService:CreatePath(agent)
                local okCompute = pcall(function()
                    path:ComputeAsync(root.Position, groundPoint(goal))
                end)
                if not okCompute or path.Status ~= Enum.PathStatus.Success then
                    replans += 1
                    if replans > 3 then
                        return false, "nopath"
                    end
                    task.wait(0.4)
                    continue
                end

                local blocked = false
                local currentWaypoint = 2
                local blockedConn = path.Blocked:Connect(function(blockedIndex)
                    if blockedIndex >= currentWaypoint then
                        blocked = true
                    end
                end)
                local waypoints = path:GetWaypoints()
                local arrived, stuck = false, false

                for i = 2, #waypoints do
                    currentWaypoint = i
                    local wp = waypoints[i]
                    if wp.Action == Enum.PathWaypointAction.Jump then
                        hum.Jump = true
                    end
                    hum:MoveTo(wp.Position)

                    local segStart = os.clock()
                    local lastPos, lastCheck = root.Position, os.clock()
                    while true do
                        task.wait(0.05)
                        local _, h2, r2 = me()
                        if not (h2 and r2) or h2.Health <= 0 or not active() or os.clock() - started > timeout then
                            blockedConn:Disconnect()
                            return false, "inactive"
                        end
                        if (r2.Position - goal).Magnitude <= stop then
                            arrived = true
                            break
                        end
                        local dx, dz = r2.Position.X - wp.Position.X, r2.Position.Z - wp.Position.Z
                        if math.sqrt(dx * dx + dz * dz) < 2.5 and math.abs(r2.Position.Y - wp.Position.Y) < 6 then
                            break
                        end
                        if blocked then
                            break
                        end
                        local now = os.clock()
                        if now - lastCheck >= 0.7 then
                            if (r2.Position - lastPos).Magnitude < 0.8 then
                                stuck = true
                                break
                            end
                            lastPos, lastCheck = r2.Position, now
                        end
                        if now - segStart > 4 then
                            stuck = true
                            break
                        end
                    end
                    if arrived or stuck or blocked then
                        break
                    end
                end
                blockedConn:Disconnect()

                local _, hum2, root2 = me()
                if arrived or (root2 and (root2.Position - goal).Magnitude <= stop) then
                    if hum2 and root2 then
                        hum2:MoveTo(root2.Position)
                    end
                    return true
                end
                if stuck or blocked then
                    replans += 1
                    if stuck and hum2 then
                        hum2.Jump = true
                    end
                    if replans > 6 then
                        return false, "stuck"
                    end
                    task.wait(0.2)
                end
            end
            return false, "timeout"
        end

        function W.face(point)
            local _, hum, root = me()
            if not (hum and root) then
                return
            end
            local look = CFrame.lookAt(root.Position, Vector3.new(point.X, root.Position.Y, point.Z))
            hum.AutoRotate = false
            game:GetService("TweenService"):Create(root, TweenInfo.new(0.12, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {CFrame = look}):Play()
            task.delay(1.2, function()
                if hum.Parent then
                    hum.AutoRotate = true
                end
            end)
        end

        return W
    end)()

    do
        local PumpCard = PumpkinCard
        local P = {farm = false, esp = false, cooldown = {}, fails = {}}
        local esp = {}
        local clearPathMarkers
        local candidates = {}   -- hitbox part -> true, kept live from tag/folder events

        local function pumpkinFolder()
            local map = workspace:FindFirstChild("Map")
            return map and map:FindFirstChild("Pumpkins")
        end
        local function hitbox(pumpkin)
            local hb = pumpkin:FindFirstChild("HB", true)
            if hb and hb:IsA("BasePart") and hb:IsDescendantOf(workspace) then
                return hb
            end
            return nil
        end
        local function crushRemote()
            local r = ReplicatedStorage:FindFirstChild("Remotes")
            local e = r and r:FindFirstChild("Events")
            local h = e and e:FindFirstChild("Halloween")
            return h and h:FindFirstChild("Crush")
        end

        local function addCandidate(part)
            if part and part:IsA("BasePart") then
                candidates[part] = true
            end
        end
        local function rescan()
            for part in pairs(candidates) do
                if not part.Parent or not part:IsDescendantOf(workspace) then
                    candidates[part] = nil
                end
            end
            for _, part in ipairs(CollectionService:GetTagged("pumpkin")) do
                addCandidate(part)
            end
            local folder = pumpkinFolder()
            if folder then
                for _, pumpkin in ipairs(folder:GetChildren()) do
                    addCandidate(hitbox(pumpkin))
                end
            end
        end
        CollectionService:GetInstanceAddedSignal("pumpkin"):Connect(addCandidate)
        CollectionService:GetInstanceRemovedSignal("pumpkin"):Connect(function(part)
            candidates[part] = nil
        end)
        rescan()

        PumpCard:AddToggle("Auto Stomp Pumpkins", false, function(v)
            P.farm = v
            if v then
                rescan()
            else
                clearPathMarkers()
            end
        end, {Flag = "PumpkinFarm"})

        -- the toggle itself lives in the Visual tab (Map ESP)
        _G.Ox.SetPumpkinESP = function(v)
            P.esp = v
        end
        if _G.Ox.WantPumpkinESP then
            P.esp = true
        end

        local function busyChar(char, hrp)
            return char:GetAttribute("Trapped") or char:GetAttribute("Knocked") or char:GetAttribute("IsHooked")
                or char:GetAttribute("IsCarried") or hrp:HasTag("doing action")
        end

        local function usable(part, now)
            return part.Parent ~= nil and part:IsDescendantOf(workspace)
                and not (part.Parent and CollectionService:HasTag(part.Parent, "Blocked"))
                and not CollectionService:HasTag(part, "doing action")
                and (P.cooldown[part] or 0) < now
        end

        -- the nearest few pumpkins, closest first
        local function nearestList(origin, limit)
            local now = tick()
            local list = {}
            for part in pairs(candidates) do
                if usable(part, now) then
                    list[#list + 1] = {part = part, dist = (part.Position - origin).Magnitude}
                end
            end
            table.sort(list, function(a, b)
                return a.dist < b.dist
            end)
            for i = #list, limit + 1, -1 do
                list[i] = nil
            end
            return list
        end

        -- walking distance of the real navmesh path (nil = unreachable), so a pumpkin behind a wall is not chosen over a reachable one
        local PathfindingService = game:GetService("PathfindingService")
        local function pathLength(from, goal)
            local path = PathfindingService:CreatePath({AgentRadius = 3, AgentHeight = 5.5, AgentCanJump = true, WaypointSpacing = 4})
            local ok = pcall(function()
                path:ComputeAsync(from, goal)
            end)
            if not ok or path.Status ~= Enum.PathStatus.Success then
                return nil
            end
            local total, prev = 0, from
            for _, wp in ipairs(path:GetWaypoints()) do
                total += (wp.Position - prev).Magnitude
                prev = wp.Position
            end
            return total, path:GetWaypoints()
        end

        -- Local-only white route markers with cumulative walking distance labels.
        local pathMarkers = {}
        clearPathMarkers = function()
            for i = #pathMarkers, 1, -1 do
                pcall(function() pathMarkers[i]:Destroy() end)
                pathMarkers[i] = nil
            end
        end
        local function showPathMarkers(waypoints)
            clearPathMarkers()
            if type(waypoints) ~= "table" then return end
            local cumulative, previous = 0, nil
            for index, waypoint in ipairs(waypoints) do
                local position = waypoint.Position
                if previous then cumulative += (position - previous).Magnitude end
                previous = position
                if index > 1 then
                    local marker = Instance.new("Part")
                    marker.Name = "MeowXPumpkinPathNode"
                    marker.Shape = Enum.PartType.Ball
                    marker.Size = Vector3.new(0.42, 0.42, 0.42)
                    marker.Anchored = true
                    marker.CanCollide = false
                    marker.CanTouch = false
                    marker.CanQuery = false
                    marker.CastShadow = false
                    marker.Material = Enum.Material.Neon
                    marker.Color = Color3.fromRGB(255, 255, 255)
                    marker.Position = position + Vector3.new(0, 0.35, 0)
                    marker.Parent = workspace
                    local tag = Instance.new("BillboardGui")
                    tag.Name = "Distance"
                    tag.Size = UDim2.fromOffset(90, 22)
                    tag.StudsOffset = Vector3.new(0, 0.8, 0)
                    tag.AlwaysOnTop = true
                    tag.Adornee = marker
                    tag.Parent = marker
                    local label = Instance.new("TextLabel")
                    label.BackgroundTransparency = 1
                    label.Size = UDim2.fromScale(1, 1)
                    label.Font = Enum.Font.GothamBold
                    label.TextSize = 11
                    label.TextColor3 = Color3.fromRGB(255, 255, 255)
                    label.TextStrokeTransparency = 0.25
                    label.Text = string.format("%.0f studs", cumulative)
                    label.Parent = tag
                    pathMarkers[#pathMarkers + 1] = marker
                end
            end
        end

        task.spawn(function()
            local lastScan = 0
            while _G.Ox.ScriptAlive do
                if not P.farm then
                    task.wait(0.3)
                    continue
                end
                if os.clock() - lastScan > 3 then
                    lastScan = os.clock()
                    rescan()
                end
                local worked = false
                pcall(function()
                    local char = localPlayer.Character
                    local hrp = char and char:FindFirstChild("HumanoidRootPart")
                    local hum = char and char:FindFirstChildOfClass("Humanoid")
                    local crush = crushRemote()
                    if not (hrp and hum and hum.Health > 0 and crush) or busyChar(char, hrp) then
                        return
                    end
                    local near = nearestList(hrp.Position, 15)
                    if #near == 0 then
                        return
                    end
                    if not _G.Ox.Act.try("pumpkin", 90) then
                        return
                    end

                    -- Check up to 15 nearest candidates (5x the previous shortlist).
                    -- Candidates are distance-sorted, so the first reachable pumpkin is the
                    -- nearest usable target. This avoids choosing a farther pumpkin merely
                    -- because its navmesh route happens to be shorter.
                    local target, bestPath, bestWaypoints
                    for _, entry in ipairs(near) do
                        if not entry.part or not entry.part.Parent or not usable(entry.part, tick()) then
                            continue
                        end
                        if entry.dist <= 4 then
                            target, bestPath = entry.part, entry.dist
                            bestWaypoints = nil
                            break
                        end

                        local len, waypoints = pathLength(hrp.Position, entry.part.Position)
                        if len and waypoints and #waypoints > 0 then
                            -- Reject pathological detours; try the next closest pumpkin instead.
                            local detourLimit = math.max(entry.dist * 3.5, entry.dist + 28)
                            if len <= detourLimit then
                                target, bestPath, bestWaypoints = entry.part, len, waypoints
                                break
                            end
                            P.fails[entry.part] = (P.fails[entry.part] or 0) + 1
                            P.cooldown[entry.part] = tick() + math.min(3 * P.fails[entry.part], 18)
                        else
                            -- Temporarily cool down unreachable targets to avoid repeating
                            -- expensive path computations every farm loop.
                            P.fails[entry.part] = (P.fails[entry.part] or 0) + 1
                            P.cooldown[entry.part] = tick() + math.min(3 * P.fails[entry.part], 18)
                        end
                    end
                    if not target or not usable(target, tick()) then
                        return
                    end
                    worked = true

                    local function active()
                        local c = localPlayer.Character
                        local r = c and c:FindFirstChild("HumanoidRootPart")
                        return P.farm and _G.Ox.ScriptAlive and target.Parent ~= nil and r ~= nil and not busyChar(c, r)
                            and not CollectionService:HasTag(target, "doing action")
                    end

                    if (hrp.Position - target.Position).Magnitude > 3.4 then
                        local limit = math.clamp(bestPath / math.max(hum.WalkSpeed, 8) * 2.2 + 6, 8, 60)
                        showPathMarkers(bestWaypoints)
                        local ok = _G.Ox.Walker.walkTo(target.Position, {stop = 3.2, timeout = limit, active = active})
                        clearPathMarkers()
                        if not ok then
                            P.fails[target] = (P.fails[target] or 0) + 1
                            P.cooldown[target] = tick() + math.min(5 * P.fails[target], 30)
                            return
                        end
                    end
                    if target.Parent and active() and (hrp.Position - target.Position).Magnitude <= 4 then
                        _G.Ox.Walker.face(target.Position)
                        task.wait(0.1)
                        crush:FireServer(target)
                        P.cooldown[target] = tick() + 3
                        P.fails[target] = nil
                        -- carry on as soon as this pumpkin is gone (or after a short safety wait)
                        local t0 = tick()
                        while target.Parent and tick() - t0 < 0.9 and P.farm do
                            task.wait(0.05)
                        end
                    end
                end)
                clearPathMarkers()
                _G.Ox.Act.done("pumpkin")
                -- no pause after a pumpkin; short idle only when there was nothing to do
                task.wait(worked and 0.02 or 0.4)
            end
        end)

        local function clearEsp(pumpkin)
            local e = esp[pumpkin]
            if e then
                pcall(function()
                    e.hl:Destroy()
                end)
                pcall(function()
                    e.gui:Destroy()
                end)
                esp[pumpkin] = nil
            end
        end

        task.spawn(function()
            while _G.Ox.ScriptAlive do
                task.wait(0.5)
                pcall(function()
                    local folder = pumpkinFolder()
                    if not P.esp or not folder then
                        for pumpkin in pairs(esp) do
                            clearEsp(pumpkin)
                        end
                        return
                    end
                    local hrp = localPlayer.Character and localPlayer.Character:FindFirstChild("HumanoidRootPart")
                    for pumpkin in pairs(esp) do
                        if not pumpkin.Parent or not hitbox(pumpkin) then
                            clearEsp(pumpkin)
                        end
                    end
                    for _, pumpkin in ipairs(folder:GetChildren()) do
                        local hb = hitbox(pumpkin)
                        if hb then
                            local e = esp[pumpkin]
                            if not e then
                                local hl = Instance.new("Highlight")
                                hl.FillColor = Color3.fromRGB(255, 140, 0)
                                hl.OutlineColor = Color3.fromRGB(255, 255, 255)
                                hl.FillTransparency = 0.45
                                hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
                                hl.Adornee = pumpkin
                                hl.Parent = pumpkin
                                local gui = Instance.new("BillboardGui")
                                gui.Size = UDim2.fromOffset(110, 22)
                                gui.StudsOffset = Vector3.new(0, 3, 0)
                                gui.AlwaysOnTop = true
                                gui.Adornee = hb
                                gui.Parent = hb
                                local label = Instance.new("TextLabel")
                                label.Size = UDim2.fromScale(1, 1)
                                label.BackgroundTransparency = 1
                                label.TextColor3 = Color3.fromRGB(255, 170, 40)
                                label.TextStrokeTransparency = 0.4
                                label.Font = Enum.Font.GothamBold
                                label.TextSize = 13
                                label.Parent = gui
                                e = {hl = hl, gui = gui, label = label}
                                esp[pumpkin] = e
                            end
                            if hrp then
                                e.label.Text = string.format("Pumpkin [%d]", (hb.Position - hrp.Position).Magnitude)
                            end
                        end
                    end
                end)
            end
        end)
    end

    local v29 = CrosshairBox:AddToggle("Enable Crosshair", false, function(enabled)
        _G.Ox.Crosshair.Enabled = enabled

        if not enabled then
            ClearCrosshair()
        end

    end, {Flag = "Crosshair"})

    CrosshairToggle = v29

    CrosshairBox:AddDropdown("Style", {"Plus", "Dot", "Circle"}, false, function(style)
        _G.Ox.Crosshair.Style = style
        ClearCrosshair()
        _G.Ox.CrosshairCreated = false
    end, {Flag = "CrosshairStyle"})

    CrosshairBox:AddSlider("Size", 2, 30, 8, function(size)
        _G.Ox.Crosshair.Size = size
    end, {Increment = 1, Flag = "CrosshairSize"})

    CrosshairBox:AddSlider("Thickness", 1, 5, 2, function(thickness)
        _G.Ox.Crosshair.Thickness = thickness
    end, {Increment = 1, Flag = "CrosshairThickness"})

    CrosshairBox:AddSlider("Position X", -100, 100, 0, function(offsetX)
        _G.Ox.Crosshair.OffsetX = offsetX
    end, {Increment = 1, Flag = "CrosshairX"})

    CrosshairBox:AddSlider("Position Y", -100, 100, 0, function(offsetY)
        _G.Ox.Crosshair.OffsetY = offsetY
    end, {Increment = 1, Flag = "CrosshairY"})

    local v32 = GenCard:AddToggle("Auto Skill Check", false, function(skillCheck)
        _G.Ox.Auto.SkillCheck = skillCheck

        if skillCheck then
            fn7()
        elseif _G.Ox.Connections.SkillHeartbeat then
            _G.Ox.Connections.SkillHeartbeat:Disconnect()
            _G.Ox.Connections.SkillHeartbeat = nil
        end
    end, {Flag = "AutoSkillCheck"})

    SkillCheckToggle = v32

    local v5 = VaultCard:AddToggle("Auto Vault", false, function(autoVaultEnabled)
        _G.Ox.autoVaultEnabled = autoVaultEnabled
    end, {Flag = "AutoVault"})

    AutoVaultToggle = v5

    local v6 = VaultCard:AddToggle("Auto Pallet Slide", false, function(autoPalletSlideEnabled)
        _G.Ox.autoPalletSlideEnabled = autoPalletSlideEnabled
    end, {Flag = "AutoPalletSlide"})

    AutoSlideToggle = v6

    local v13 = FakePerksCard:AddToggle("Quick Recovery", false, function(arg)
        ToggleQuickRecovery(arg)
    end, {Flag = "FakeQR"})

    QR_Toggle = v13

    local v14 = FakePerksCard:AddToggle("Perfect Landing", false, function(arg)
        TogglePerfectLanding(arg)
    end, {Flag = "FakePL"})

    PL_Toggle = v14

    local Flowstate = FakePerksCard:AddToggle("Flowstate", false, function(arg)
        ToggleFlowstate(arg)
    end, {Flag = "FakeFS"})

    FS_Toggle = Flowstate

    local v15 = FakePerksCard:AddToggle("Adrenaline Rush", false, function(arg)
        SetupFakeAdrenalineRush(arg)
    end, {Flag = "FakeAR"})

    AR_Toggle = v15

    local TrapBot = {token = 0, running = false, holding = false}

    TrapCard = TrapPage:CreateSection("Anti Trap", "triangle-alert")

    _G.Ox.TrapGroup = TrapCard

    pcall(function() TrapCard:_gb() end)

    task.spawn(function()
        local r = ReplicatedStorage:WaitForChild("Remotes", 15)
        local k = r and r:WaitForChild("Killers", 5)
        local b = k and k:WaitForChild("Butcher", 5)
        local ft = b and b:WaitForChild("FreeTrap", 5)
        if ft then
            ft.OnClientEvent:Connect(function(...)
                warn("[Kisha] FreeTrap server ->", ...)
            end)
        end
    end)

    local function sendBind(attr, default, down)
        local raw = localPlayer:GetAttribute(attr)
        if typeof(raw) ~= "string" or raw == "" then
            raw = default
        end
        local mouse = raw:match("^MouseButton(%d)$")
        if mouse then
            local cam = workspace.CurrentCamera
            VirtualInputManager:SendMouseButtonEvent(cam.ViewportSize.X / 2, cam.ViewportSize.Y / 2, tonumber(mouse) - 1, down, game, 0)
            return
        end
        local okKey, keyCode = pcall(function()
            return Enum.KeyCode[raw]
        end)
        if okKey and keyCode then
            VirtualInputManager:SendKeyEvent(down, keyCode, false, game)
        end
    end

    local function isTrapped()
        local character = localPlayer.Character
        return character ~= nil and character:GetAttribute("Trapped") == true
    end

    local function freeingNow()
        local gui = playerGui:FindFirstChild("ProgressPromptGui")
        local frame = gui and gui:FindFirstChild("Frame")
        local label = frame and frame:FindFirstChild("TextLabel")
        return frame ~= nil and frame.Visible and label ~= nil and label.Text == "FREEING"
    end

    local function readCheck()
        local gui = playerGui:FindFirstChild("SkillCheckPromptGui")
        local check = gui and gui:FindFirstChild("Check")
        if not (check and check.Visible) then
            return nil
        end
        local line = check:FindFirstChild("Line")
        local perfectObj = check:FindFirstChild("TrapPerfect")
        local goalObj = check:FindFirstChild("TrapGoal")
        local obj
        local perfectOnly = false
        if perfectObj and perfectObj.Visible then
            obj, perfectOnly = perfectObj, true
        elseif goalObj and goalObj.Visible then
            obj = goalObj
        end
        if not (line and obj) then
            return nil
        end
        return line, obj, perfectOnly
    end

    local function tapSkillKey()
        task.spawn(function()
            sendBind("kb_skillcheck", "Space", true)
            RunService.Heartbeat:Wait()
            sendBind("kb_skillcheck", "Space", false)
        end)
    end

    local function runTrapBot()
        if TrapBot.running then
            return
        end
        TrapBot.running = true
        TrapBot.token += 1
        local token = TrapBot.token

        local function alive()
            return _G.Ox.Auto.AntiTrap and TrapBot.token == token and isTrapped()
        end

        task.spawn(function()
            pcall(function()
                local clickhold = localPlayer:GetAttribute("clickhold") == true
                local lastTry = -10
                local lastFreeingSeen = -10
                local seenThisTry = false
                local prevRel, prevTime
                local cycleGoal, pressed, cycleMode
                local perfects, earlySent = 0, false
                local remotes = ReplicatedStorage:FindFirstChild("Remotes")
                local butcher = remotes and remotes:FindFirstChild("Killers") and remotes.Killers:FindFirstChild("Butcher")
                local freeTrap = butcher and butcher:FindFirstChild("FreeTrap")

                while alive() do
                    local now = os.clock()

                    local freeing = freeingNow()
                    if freeing then
                        lastFreeingSeen = now
                        seenThisTry = true
                    elseif seenThisTry and TrapBot.holding and now - lastFreeingSeen > 0.4 then

                        sendBind("kb_interact", "MouseButton1", false)
                        TrapBot.holding = false
                        seenThisTry = false
                    end

                    local instantMode = _G.Ox.Auto.TrapMode == "Instant"
                    if not freeing and now - lastTry > (instantMode and 0.8 or 1.6) and now - lastFreeingSeen > (instantMode and 1.5 or 3.0) then
                        lastTry = now
                        seenThisTry = false

                        task.wait(instantMode and 0 or 0.35)
                        if not alive() then
                            break
                        end
                        if TrapBot.holding then
                            sendBind("kb_interact", "MouseButton1", false)
                            TrapBot.holding = false
                        end
                        sendBind("kb_interact", "MouseButton1", true)
                        if clickhold then
                            task.wait(0.05)
                            sendBind("kb_interact", "MouseButton1", false)
                        else
                            TrapBot.holding = true
                        end
                    end

                    local line, obj, perfectOnly = readCheck()
                    if line then
                        local goalRot = obj.Rotation
                        if cycleGoal == nil or math.abs(goalRot - cycleGoal) > 0.5 then
                            cycleGoal, pressed, prevRel, prevTime = goalRot, false, nil, nil
                            local mode = _G.Ox.Auto.TrapMode
                            if mode == "Random" then
                                mode = math.random() < 0.5 and "Perfect" or "Normal"
                            end
                            cycleMode = mode
                        end

                        local rel = (line.Rotation - goalRot) % 360
                        local perfectWanted = perfectOnly or cycleMode ~= "Normal"

                        if not pressed then

                            local from, to, centre = 96, 140, 109
                            if not perfectWanted then
                                from, to, centre = 120, 150, 128
                            end

                            if cycleMode == "Instant" or (rel >= from and rel <= to) then
                                line.Rotation = goalRot + centre
                                pressed = true
                                tapSkillKey()
                            end
                            if pressed and perfectWanted then
                                perfects += 1
                            end
                        end
                        prevRel, prevTime = rel, now
                    else
                        cycleGoal = nil
                    end

                    RunService.Heartbeat:Wait()
                end
            end)
            if TrapBot.holding then
                sendBind("kb_interact", "MouseButton1", false)
                TrapBot.holding = false
            end
            task.wait(0.6)
            TrapBot.running = false
        end)
    end

    task.spawn(function()
        while _G.Ox.ScriptAlive do
            task.wait(_G.Ox.Auto.TrapMode == "Instant" and 0.03 or 0.2)
            if _G.Ox.Auto.AntiTrap and not TrapBot.running and isTrapped() then
                runTrapBot()
            end
        end
    end)

    TrapCard:AddToggle("Anti Trap (Auto Free)", false, function(antiTrap)
        _G.Ox.Auto.AntiTrap = antiTrap
        if not antiTrap then
            TrapBot.token += 1
        end
    end, {Flag = "AntiTrapSkillCheck"})

    TrapCard:AddDropdown("Trap Check Mode", {"Perfect", "Normal", "Random", "Instant"}, false, function(mode)
        _G.Ox.Auto.TrapMode = mode
    end, {Flag = "TrapCheckMode"})

    GenCard:AddDropdown("Skill Check Mode", {"Legit", "Instant", "Normal", "Random"}, false, function(skillCheckMode)
        _G.Ox.Auto.SkillCheckMode = skillCheckMode
        _G.Ox.State.RandomMode_IsNormal = false
    end, {Flag = "SkillCheckMode"})

    do
        local Help = {on = false, range = 15, busy = false, rejectedAt = 0, beganAt = 0, skip = {}}

        local function assistRemote()
            local r = ReplicatedStorage:FindFirstChild("Remotes")
            local k = r and r:FindFirstChild("Killers")
            local b = k and k:FindFirstChild("Butcher")
            return b and b:FindFirstChild("AssistFree")
        end

        task.spawn(function()
            local rem
            while _G.Ox.ScriptAlive and not rem do
                rem = assistRemote()
                task.wait(0.5)
            end
            if rem then
                rem.OnClientEvent:Connect(function(msg, ...)
                    if msg == "rejected" then
                        Help.rejectedAt = os.clock()
                    elseif msg == "began" then
                        Help.beganAt = os.clock()
                    elseif msg ~= nil then

                        warn("[Kisha] AssistFree server ->", msg, ...)
                    end
                end)
            end
        end)

        local function helperEligible()
            local char = localPlayer.Character
            if not char then
                return false
            end
            if char:GetAttribute("Trapped") or char:GetAttribute("Knocked") or char:GetAttribute("IsHooked") or char:GetAttribute("IsCarried") then
                return false
            end
            local hum = char:FindFirstChildOfClass("Humanoid")
            if not hum or hum.Health <= 0 then
                return false
            end
            local root = char:FindFirstChild("HumanoidRootPart")
            return root ~= nil and not root:HasTag("doing action")
        end

        local function helperAlive()
            local char = localPlayer.Character
            if not char then
                return false
            end
            if char:GetAttribute("Trapped") or char:GetAttribute("Knocked") or char:GetAttribute("IsHooked") or char:GetAttribute("IsCarried") then
                return false
            end
            local hum = char:FindFirstChildOfClass("Humanoid")
            return hum ~= nil and hum.Health > 0
        end

        local function pickTarget()
            local char = localPlayer.Character
            local root = char and char:FindFirstChild("HumanoidRootPart")
            if not root then
                return nil
            end
            local best, bestDist = nil, Help.range
            local candidates, seen = {}, {}
            local function addCandidate(model)
                if model and model ~= char and not seen[model] then
                    seen[model] = true
                    table.insert(candidates, model)
                end
            end
            for _, model in ipairs(CollectionService:GetTagged("Survivor")) do
                addCandidate(model)
            end

            for _, player in ipairs(Players:GetPlayers()) do
                if player ~= localPlayer and player.Team and player.Team.Name == "Survivor" then
                    addCandidate(player.Character)
                end
            end
            for _, m in ipairs(candidates) do
                if m:GetAttribute("Trapped") == true and not m:GetAttribute("BeingRescued")
                    and (Help.skip[m] or 0) < os.clock() then
                    local r = m:FindFirstChild("HumanoidRootPart")
                    if r then
                        local d = (r.Position - root.Position).Magnitude
                        if d <= bestDist then
                            best, bestDist = m, d
                        end
                    end
                end
            end
            return best
        end

        local function helpOne(target)
            local rem = assistRemote()
            if not rem then
                return
            end

            local function stillValid()
                return Help.on and _G.Ox.ScriptAlive and target.Parent ~= nil and target:GetAttribute("Trapped") == true
                    and helperAlive()
            end

            local function abort()
                rem:FireServer("cancel")
                Help.skip[target] = os.clock() + 3
            end

            local t0 = os.clock()
            rem:FireServer("begin", target)

            while os.clock() - t0 < 1.5 and Help.beganAt <= t0 and Help.rejectedAt <= t0 do
                task.wait(0.05)
            end
            if Help.rejectedAt > t0 or not stillValid() then
                abort()
                return
            end

            local startedAt = (Help.beganAt > t0) and Help.beganAt or t0
            local ok = true
            while os.clock() - startedAt < 7.1 do
                task.wait(0.1)
                if Help.rejectedAt > t0 or not stillValid() then
                    ok = false
                    break
                end
            end

            if ok then
                rem:FireServer("commit")
            else
                abort()
            end
        end

        task.spawn(function()
            while _G.Ox.ScriptAlive do
                task.wait(0.3)
                if Help.on and not Help.busy and helperEligible()
                    and localPlayer.Team and localPlayer.Team.Name ~= "Killer" then
                    local target = pickTarget()
                    if target and _G.Ox.Act.try("help", 90) then
                        Help.busy = true
                        pcall(helpOne, target)
                        Help.busy = false
                        _G.Ox.Act.done("help")
                        task.wait(0.5)
                    end
                end
            end
        end)

        TrapCard:AddToggle("Auto Help Trap Team", false, function(v)
            Help.on = v
        end, {Flag = "AutoHelpTrapTeam"})

    end

    do

        xpcall(function()
            local T = {on = false, items = {}}

            local function clear(model)
                local e = T.items[model]
                if e then
                    pcall(function() e.hl:Destroy() end)
                    pcall(function() e.gui:Destroy() end)
                    T.items[model] = nil
                end
            end

            -- the toggle itself lives in the Visual tab (Map ESP)
            _G.Ox.SetTrapESP = function(state)
                T.on = state
                if not state then
                    for model in pairs(T.items) do
                        clear(model)
                    end
                end
            end
            if _G.Ox.WantTrapESP then
                _G.Ox.SetTrapESP(true)
            end

            local scanCache, scanAt = {}, 0
            local function trapModels()
                local list, seenModels = {}, {}
                local function add(m)
                    if m and not seenModels[m] and m:IsDescendantOf(workspace) then

                        if m:IsA("BasePart") then
                            local owner = m:FindFirstAncestor("BearTrap")
                            if owner and seenModels[owner] then
                                return
                            end
                        end
                        seenModels[m] = true
                        table.insert(list, m)
                    end
                end
                for _, m in ipairs(CollectionService:GetTagged("BearTrap")) do
                    add(m)
                end
                local map = workspace:FindFirstChild("Map")
                if map then
                    if os.clock() >= scanAt then
                        scanAt = os.clock() + 3
                        scanCache = {}
                        for _, d in ipairs(map:GetDescendants()) do
                            if d.Name == "BearTrap" and d:FindFirstChild("Cube", true) then

                                for _, inner in ipairs(d:GetDescendants()) do
                                    if inner.Name == "Cube" and inner:IsA("BasePart") then
                                        table.insert(scanCache, inner)
                                    end
                                end
                            elseif d.Name == "BearTrap" then
                                if d:IsA("Folder") then
                                    local found = false
                                    for _, inner in ipairs(d:GetDescendants()) do
                                        if inner:IsA("Model") then
                                            found = true
                                            table.insert(scanCache, inner)
                                        end
                                    end
                                    if not found then
                                        for _, inner in ipairs(d:GetChildren()) do
                                            if inner:IsA("BasePart") then
                                                table.insert(scanCache, inner)
                                            end
                                        end
                                    end
                                elseif d:IsA("Model") or d:IsA("BasePart") then
                                    table.insert(scanCache, d)
                                end
                            end
                        end
                    end
                    for _, m in ipairs(scanCache) do
                        add(m)
                    end
                end
                return list
            end

            task.spawn(function()
                while _G.Ox.ScriptAlive do
                    task.wait(0.4)
                    pcall(function()
                        if not T.on then
                            return
                        end
                        local root = localPlayer.Character and localPlayer.Character:FindFirstChild("HumanoidRootPart")
                        local seen = {}
                        for _, model in ipairs(trapModels()) do
                            local part = model:IsA("BasePart") and model
                                or model:FindFirstChild("hitbox") or model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
                            if part then
                                seen[model] = true
                                local holder = model
                                if model:GetAttribute("Armed") == nil then
                                    holder = model:FindFirstAncestor("BearTrap") or model
                                end
                                local armed = holder:GetAttribute("Armed") ~= false and holder:GetAttribute("Triggered") ~= true
                                local color = armed and Color3.fromRGB(255, 70, 70) or Color3.fromRGB(255, 190, 60)
                                local e = T.items[model]
                                if not e or not e.hl.Parent or not e.gui.Parent then
                                    clear(model)
                                    local hl = Instance.new("Highlight")
                                    hl.FillTransparency = 0.5
                                    hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
                                    hl.Adornee = model
                                    hl.Parent = model
                                    local gui = Instance.new("BillboardGui")
                                    gui.Size = UDim2.fromOffset(120, 26)
                                    gui.StudsOffset = Vector3.new(0, 3, 0)
                                    gui.AlwaysOnTop = true
                                    gui.Adornee = part
                                    gui.Parent = part
                                    local label = Instance.new("TextLabel")
                                    label.Size = UDim2.fromScale(1, 1)
                                    label.BackgroundTransparency = 1
                                    label.Font = Enum.Font.GothamBold
                                    label.TextSize = 13
                                    label.TextStrokeTransparency = 0.4
                                    label.Parent = gui
                                    e = {hl = hl, gui = gui, label = label}
                                    T.items[model] = e
                                end
                                e.hl.FillColor = color
                                e.hl.OutlineColor = color
                                e.label.TextColor3 = color
                                local dist = root and math.floor((part.Position - root.Position).Magnitude) or 0
                                e.label.Text = string.format("⚠ %s [%d]", armed and "Trap" or "Trap (off)", dist)
                            end
                        end
                        for model in pairs(T.items) do
                            if not seen[model] then
                                clear(model)
                            end
                        end
                    end)
                end
                for model in pairs(T.items) do
                    clear(model)
                end
            end)
        end, function(err)
            warn("[Kisha] ESP Trap failed to build: " .. tostring(err))
        end)

    end

    local fire
    do
        local okFire, fireRemote = pcall(function()
            return ReplicatedStorage:WaitForChild("Remotes", 10):WaitForChild("Items", 10)["Twist of Fate"].Fire
        end)
        if okFire and fireRemote then
            fire = fireRemote
        else
            warn("[Kisha] Twist of Fate remote not found; related features are disabled")
            fire = {FireServer = function() end}
        end
    end
    _G.Ox.ToFFireRemote = fire
    _G.Ox.SilentShot = false
    local flag4 = false
    local flag5 = false
    local flag6 = false -- ToF draw-line visualization disabled
    local flag7 = false
    local flag8 = false
    local connection2 = nil
    local part = nil
    local str = "Killer"
    UDim2.new(0.5, -120, 0, 110)
    local tbl8 = {}

    local tbl9 = {
        PredictionEfficiency = 0.9,
        LerpSmoothness = 0.45,
        EnableJitter = false,
        MaxJitterStuds = 0,
        ProjectileSpeed = 500,
        MaxLead = 0.3,
        PingComp = true,
        AccelPredict = true,
        FOVDot = 0.5,
        SkipDowned = true,
        TargetBody = "Torso",
    }

    getGunObject = function()
        local character = localPlayer.Character
        if not character then
            return nil
        end
        local cg = tbl9.GunCache
        if cg and cg.Parent and cg:IsDescendantOf(character) then
            return cg
        end
        tbl9.GunCache = nil
        local twistOfFate = character:FindFirstChild("Twist of Fate", true)
        if not twistOfFate then
            return nil
        end
        local rightArm = twistOfFate:FindFirstChild("Right Arm")

        if rightArm then
            local gun = rightArm:FindFirstChild("gun")
            if gun then
                tbl9.GunCache = gun
                return gun
            end
            local emperorGun = rightArm:FindFirstChild("EmperorGun")
            if emperorGun then
                tbl9.GunCache = emperorGun
                return emperorGun
            end
        end

        return twistOfFate
    end

    isTargetVisible = function(arg, arg2, arg3)
        local n2 = arg2 - arg
        local magnitude = n2.Magnitude
        if magnitude < 0.1 then
            return true
        end
        local raycastParams = RaycastParams.new()
        raycastParams.FilterType = Enum.RaycastFilterType.Exclude
        local filterDescendantsInstances = {}
        local character = localPlayer.Character

        if character then
            table.insert(filterDescendantsInstances, character)
        end

        if arg3 and arg3 ~= character then
            table.insert(filterDescendantsInstances, arg3)
        end

        if part then
            table.insert(filterDescendantsInstances, part)
        end

        raycastParams.FilterDescendantsInstances = filterDescendantsInstances
        local flag9 = workspace:Raycast(arg, n2.Unit * magnitude, raycastParams) == nil
        return flag9
    end

    local tbl10 = {}
    local n2 = 0

    GetSCPs = function()
        if tick() - n2 < 1.5 then
            return tbl10
        end
        local tbl11 = {}
        local map = workspace:FindFirstChild("Map")

        if map then
            for k, descendant in pairs(map:GetDescendants()) do
                if descendant:IsA("Model") then
                    local attributes = descendant:GetAttributes()

                    if descendant:GetAttribute("CorpseCreated0492") or next(attributes) ~= nil then
                        local humanoidRootPart = descendant:FindFirstChild("HumanoidRootPart")

                        if humanoidRootPart then
                            table.insert(tbl11, humanoidRootPart)
                        end
                    end
                end
            end
        end

        tbl10 = tbl11
        n2 = tick()
        return tbl10
    end

    local StatsService = game:GetService("Stats")
    local function getPingSeconds()
        local ok, v = pcall(function()
            return StatsService.Network.ServerStatsItem["Data Ping"]:GetValue()
        end)
        if ok and type(v) == "number" then
            return math.clamp(v / 1000, 0, 0.4)
        end
        return 0
    end

    local function fn71(arg)
        local humanoidRootPart = arg:FindFirstChild("HumanoidRootPart")
        if not humanoidRootPart then
            return Vector3.zero, Vector3.zero
        end
        local position = humanoidRootPart.Position
        local now = tick()
        local st = tbl8[arg]
        if st and now - st.time > 0.3 then
            st = nil
        end
        local vel, acc
        if st then
            local dt = now - st.time
            if dt < 0.004 then
                return st.vel, st.acc
            end
            local raw = (position - st.pos) / dt
            if raw.Magnitude > 150 then
                vel = humanoidRootPart.AssemblyLinearVelocity
                acc = Vector3.zero
            else
                vel = st.vel:Lerp(raw, tbl9.LerpSmoothness)
                acc = st.acc:Lerp((vel - st.vel) / dt, 0.15)
                if acc.Magnitude > 60 then
                    acc = acc.Unit * 60
                end
            end
        else
            vel = humanoidRootPart.AssemblyLinearVelocity
            acc = Vector3.zero
        end

        pcall(function()
            local hum = arg:FindFirstChildOfClass("Humanoid")
            if hum and hum.FloorMaterial ~= Enum.Material.Air then
                vel = Vector3.new(vel.X, 0, vel.Z)
                acc = Vector3.new(acc.X, 0, acc.Z)
            end
        end)
        tbl8[arg] = {pos = position, vel = vel, acc = acc, time = now}
        return vel, acc
    end

    local function fn72(arg, arg2, arg3, arg4)
        local speed = math.max(arg4 or tbl9.ProjectileSpeed or 500, 1)
        local position = arg2.Position
        if (position - arg).Magnitude < 8 then
            return position
        end
        local vel, acc = fn71(arg3)
        local eff = tbl9.PredictionEfficiency
        local extra = tbl9.PingComp and getPingSeconds() * 0.5 or 0
        local useAcc = tbl9.AccelPredict
        local t = (position - arg).Magnitude / speed
        local predicted = position
        for _ = 1, 4 do
            local lead = math.min(t + extra, tbl9.MaxLead)
            local offset = vel * lead
            if useAcc then
                offset = offset + acc * (0.5 * lead * lead)
            end
            predicted = position + offset * eff
            t = (predicted - arg).Magnitude / speed
        end
        if tbl9.EnableJitter then
            predicted = predicted + Vector3.new((math.random() - 0.5) * tbl9.MaxJitterStuds, (math.random() - 0.5) * (tbl9.MaxJitterStuds / 2), (math.random() - 0.5) * tbl9.MaxJitterStuds)
        end
        return predicted
    end

    getTargetPosition = function()
        local currentCamera2 = workspace.CurrentCamera
        local v34 = getGunObject()
        local character = localPlayer.Character
        if not v34 or not character then
            return nil, nil, nil, nil
        end
        local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
        if not humanoidRootPart then
            return nil, nil, nil, nil
        end
        local position = humanoidRootPart.Position
        local n3 = nil

        if character:GetAttribute("IsCarried") then
            n3 = character.HumanoidRootPart.Position + character.HumanoidRootPart.CFrame.LookVector * 2
        else
            pcall(function()
                local isBasePart = v34:IsA("BasePart")
                local position2 = isBasePart and v34.Position

                if not position2 then
                    local basePart = v34:FindFirstChildOfClass("BasePart")
                    position2 = basePart and v34:FindFirstChildOfClass("BasePart").Position
                end

                n3 = position2
            end)

            local vector = n3 or Vector3.new(position.X, position.Y + 1.5, position.Z)
            n3 = vector
        end

        local function fn73(arg, arg2)
            local position2 = arg.Position
            if flag7 and not isTargetVisible(n3, position2, arg2) then
                return nil, nil, nil, nil
            end
            local v35 = getGunObject()
            local position3 = n3

            pcall(function()
                if v35 and v35:IsA("BasePart") then
                    position3 = v35.Position
                elseif v35 then
                    local basePart = v35:FindFirstChildOfClass("BasePart")

                    if basePart then
                        position3 = basePart.Position
                    end
                end
            end)

            if (position2 - position3).Magnitude < 8 then
                return (position2 - position3).Unit, v35, position3, position2
            end

            if not flag5 then
                return (position2 - position3).Unit, v35, position3, position2
            end
            local v36 = fn72(position3, arg, arg2, tbl9.ProjectileSpeed)
            return (v36 - position3).Unit, v35, position3, v36
        end

        local cam = workspace.CurrentCamera
        local camPos, camLook = cam.CFrame.Position, cam.CFrame.LookVector
        local cands = {}
        local function skipDowned(model)
            if not (tbl9.SkipDowned and model) then
                return false
            end
            return IsDowned(model) or model:GetAttribute("IsCarried") == true
        end
        local function bodyPart(model)
            return model:FindFirstChild(tbl9.TargetBody or "Torso") or model:FindFirstChild("Torso") or model:FindFirstChild("HumanoidRootPart")
        end

        if str == "Killer" or str == "Survivors" then
            for _, player in ipairs(Players:GetPlayers()) do
                if player ~= localPlayer and player.Team and player.Team.Name == str and player.Character then
                    local ch = player.Character
                    local body = bodyPart(ch)
                    local hum = ch:FindFirstChildOfClass("Humanoid")
                    if body and not (hum and hum.Health <= 0) and not (str == "Survivors" and skipDowned(ch)) then
                        local dir = body.Position - camPos
                        local dist = dir.Magnitude
                        local dot = dist > 0.01 and camLook:Dot(dir.Unit) or 1
                        if str == "Killer" then
                            table.insert(cands, {body, ch, (position - body.Position).Magnitude})
                        elseif dot > tbl9.FOVDot then

                            table.insert(cands, {body, ch, (1 - dot) * 200 + dist * 0.05})
                        end
                    end
                end
            end
        elseif str == "Zombie" then
            for _, p in ipairs(GetSCPs()) do
                if p and p.Parent then
                    local dir = p.Position - camPos
                    local dist = dir.Magnitude
                    local dot = dist > 0.01 and camLook:Dot(dir.Unit) or 1
                    if dot > tbl9.FOVDot then
                        table.insert(cands, {p, p.Parent, (1 - dot) * 200 + dist * 0.05})
                    end
                end
            end
        else
            return nil, nil, nil, nil
        end

        table.sort(cands, function(x, y)
            return x[3] < y[3]
        end)
        for _, c in ipairs(cands) do
            local r1, r2, r3, r4 = fn73(c[1], c[2])
            if r1 then
                return r1, r2, r3, r4
            end
        end
        return nil, nil, nil, nil
    end

    updateLaser = function(arg, arg2)
        if not part then
            part = Instance.new("Part")
            part.Name = "ToFLaser"
            part.Anchored = true
            part.CanCollide = false
            part.CanTouch = false
            part.CastShadow = false
            part.Material = Enum.Material.Neon
            local color = Color3.fromRGB(255, 50, 50)
            part.Color = color
            part.Parent = workspace
        end

        local vector = Vector3.new(0.05, 0.05, (arg2 - arg).Magnitude)
        part.Size = vector
        local cframe = CFrame.new((arg + arg2) / 2, arg2)
        part.CFrame = cframe
        part.Transparency = 0
    end

    clearLaser = function()
        if part then
            part:Destroy()
            part = nil
        end
    end

    local tbl11 = {}

    local function fn73()
        local attribute = localPlayer:GetAttribute("EquippedSkin_Twist_of_Fate")
        local str2 = attribute or ""
        if str2:find("AWP") or str2:find("Awp") or str2:find("awp") then
            return "rbxassetid://119691839016468"
        end

        if not str2:find("SCP") and not str2:find("3108") then
            return "rbxassetid://124735239320776"
        end
        return "rbxassetid://116394362601423"
    end

    local function fn74()
        for i, v34 in ipairs(tbl11) do
            v34:Disconnect()
        end

        tbl11 = {}
        local character = localPlayer.Character
        if not character then
            return
        end
        local humanoid = character:FindFirstChildOfClass("Humanoid")
        local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
        if not animator then
            return
        end

        local function fn75()
            local attribute = character:GetAttribute("IsCarried")
            local attribute2 = attribute or character:GetAttribute("Knocked")
            return attribute2
        end

        local function fn76()
            local tbl12 = {}
            tbl12[fn73()] = true
            tbl12["rbxassetid://111824163160605"] = true
            tbl12["rbxassetid://72749744367268"] = true
            return tbl12
        end

        table.insert(tbl11, animator.AnimationPlayed:Connect(function(arg)
            if not fn75() then
                return
            end

            if not arg.Animation then
                return
            end

            local trackName = string.lower(tostring(arg.Name or arg.Animation.Name or ""))
            if fn76()[arg.Animation.AnimationId] or string.find(trackName, "aim", 1, true) or string.find(trackName, "tof", 1, true) or string.find(trackName, "twist", 1, true) then
                arg:Stop(0)
            end
        end))

        table.insert(tbl11, character:GetAttributeChangedSignal("IsCarried"):Connect(function()
            if not fn75() then
                return
            end
            local v34 = fn76()

            for i, v35 in ipairs(animator:GetPlayingAnimationTracks()) do
                if v35.Animation and v34[v35.Animation.AnimationId] then
                    v35:Stop(0)
                end
            end
        end))

        table.insert(tbl11, character:GetAttributeChangedSignal("Knocked"):Connect(function()
            if not fn75() then
                return
            end
            local v34 = fn76()

            for i, v35 in ipairs(animator:GetPlayingAnimationTracks()) do
                if v35.Animation and v34[v35.Animation.AnimationId] then
                    v35:Stop(0)
                end
            end
        end))
    end

    task.defer(fn74)

    localPlayer.CharacterAdded:Connect(function()
        task.defer(function()
            task.wait(0.25)
            fn74()
        end)
    end)

    doShoot = function()
        if not flag4 or not flag8 then
            return
        end
        local character = localPlayer.Character
        if character and _G.Ox.AimConfig.Pistol_BlockKnocked and (IsDowned(character) or character:GetAttribute("IsCarried")) then
            return
        end
        if character then
            local hum = character:FindFirstChildOfClass("Humanoid")
            if CollectionService:HasTag(character, "Silenced") or localPlayer:GetAttribute("IsDead") or (hum and (hum.Health <= 0 or hum.Health < hum.MaxHealth * 0.5)) then
                return
            end
        end
        local v34, v35, v36, v37 = getTargetPosition()
        if not v34 or not v35 or not v37 or not v36 then
            return
        end
        local unit = (v37 - v36).Unit

        if typeof(v35) == "Instance" then
            if v35:GetAttribute("tofState") == "cooldown" then
                return
            end
            local shots = v35:GetAttribute("shots")
            if (shots == nil and 3 or shots) <= 0 then
                return
            end
        end
        if tick() - (_G.Ox.LastToFShot or 0) < 0.65 then
            return
        end
        _G.Ox.LastToFShot = tick()

        _G.Ox.SilentShot = true
        pcall(function()
            fire:FireServer(v35, unit)
        end)
        _G.Ox.SilentShot = false
    end

    startConnection = function()
        if connection2 then
            return
        end

        connection2 = RunService.Heartbeat:Connect(function()
            if flag8 and flag4 then
                local v34, v35, v36, v37 = getTargetPosition()

                if v34 and v35 and v37 then
                    pcall(function()
                        local character = localPlayer.Character
                        local humanoidRootPart = character and character:FindFirstChild("HumanoidRootPart")

                        if humanoidRootPart and not character:GetAttribute("IsCarried") then
                            humanoidRootPart.CFrame = CFrame.new(humanoidRootPart.Position, Vector3.new(v37.X, humanoidRootPart.Position.Y, v37.Z))
                        end
                    end)

                    if _G.Ox.AimConfig.LockAim then
                        local cframe = CFrame.lookAt(currentCamera.CFrame.Position, v37)
                        currentCamera.CFrame = currentCamera.CFrame:Lerp(cframe, 0.15)
                    end

                    if flag6 and v36 and v37 then
                        updateLaser(v36, v37)
                    end
                elseif part then
                    part.Transparency = 1
                end
            elseif part then
                part.Transparency = 1
            end
        end)
    end

    stopConnection = function()
        if connection2 then
            connection2:Disconnect()
            connection2 = nil
        end

        clearLaser()
    end

    local udim2 = UDim2.new(0.5, -82, 0, 30)
    local v34 = nil
    local connection3 = nil

    local tbl12 = {
        {
            internal = "Killer",
            display = "Killer (K)",
            activeColor = Color3.fromRGB(180, 45, 45),
            activeTxt = Color3.fromRGB(255, 180, 180),
        },
        {
            internal = "Survivors",
            display = "Survivors (J)",
            activeColor = Color3.fromRGB(25, 80, 150),
            activeTxt = Color3.fromRGB(160, 210, 255),
        },
        {
            internal = "Zombie",
            display = "Zombie (L)",
            activeColor = Color3.fromRGB(120, 80, 10),
            activeTxt = Color3.fromRGB(255, 210, 100),
        },
    }

    createTargetSelectorUI = function()
        if not CoreGui then
            return
        end

        if v34 and v34.Parent then
            return
        end
        local toFTargetSelector = CoreGui:FindFirstChild("ToFTargetSelector")

        if toFTargetSelector then
            toFTargetSelector:Destroy()
        end

        local screenGui2 = Instance.new("ScreenGui")
        screenGui2.Name = "ToFTargetSelector"
        screenGui2.ResetOnSpawn = false
        screenGui2.IgnoreGuiInset = true
        screenGui2.Parent = CoreGui
        local frame2 = Instance.new("Frame")
        frame2.Name = "Main"
        frame2.Size = UDim2.new(0, 165, 0, 32)
        frame2.Position = udim2
        frame2.BackgroundTransparency = 1
        frame2.Active = true
        frame2.Parent = screenGui2
        local visible = false
        local textButton = Instance.new("TextButton")
        textButton.Size = UDim2.new(1, 0, 1, 0)
        textButton.BackgroundColor3 = Color3.fromRGB(15, 15, 20)
        textButton.BackgroundTransparency = 0.25
        textButton.BorderSizePixel = 0
        textButton.Font = Enum.Font.GothamBold
        textButton.TextSize = 11
        textButton.TextColor3 = Color3.fromRGB(240, 240, 240)
        textButton.Parent = frame2
        Instance.new("UICorner", textButton).CornerRadius = UDim.new(0, 8)
        local uiStroke3 = Instance.new("UIStroke", textButton)
        uiStroke3.Color = Color3.fromRGB(100, 100, 110)
        uiStroke3.Thickness = 1.2
        uiStroke3.Transparency = 0.3
        local frame3 = Instance.new("Frame")
        frame3.Size = UDim2.new(1, 0, 0, 0)
        frame3.Position = UDim2.new(0, 0, 1, 5)
        frame3.BackgroundColor3 = Color3.fromRGB(15, 15, 20)
        frame3.BackgroundTransparency = 0.25
        frame3.BorderSizePixel = 0
        frame3.ClipsDescendants = true
        frame3.Visible = false
        frame3.AutomaticSize = Enum.AutomaticSize.Y
        frame3.Parent = frame2
        Instance.new("UICorner", frame3).CornerRadius = UDim.new(0, 8)
        local uiStroke4 = Instance.new("UIStroke", frame3)
        uiStroke4.Color = Color3.fromRGB(80, 80, 90)
        uiStroke4.Thickness = 1.2
        uiStroke4.Transparency = 0.4
        local uiListLayout = Instance.new("UIListLayout", frame3)
        uiListLayout.FillDirection = Enum.FillDirection.Vertical
        uiListLayout.SortOrder = Enum.SortOrder.LayoutOrder
        uiListLayout.Padding = UDim.new(0, 4)
        local uiPadding = Instance.new("UIPadding", frame3)
        uiPadding.PaddingTop = UDim.new(0, 4)
        uiPadding.PaddingBottom = UDim.new(0, 4)
        uiPadding.PaddingLeft = UDim.new(0, 4)
        uiPadding.PaddingRight = UDim.new(0, 4)
        local tbl13 = {}

        local function fn75()
            local str2 = "Unknown"

            for i, v35 in ipairs(tbl12) do
                if v35.internal == str then
                    str2 = v35.internal
                    break
                end
            end

            local v35 = visible
            local str3 = v35 and "v" or ">"
            textButton.Text = string.format("Target: %s   %s", str2, str3)
            frame3.Visible = visible

            for i, v36 in ipairs(tbl12) do
                local v37 = tbl13[v36.internal]

                if v37 then
                    if v36.internal == str then
                        v37.BackgroundColor3 = v36.activeColor
                        v37.TextColor3 = v36.activeTxt
                    else
                        v37.BackgroundColor3 = Color3.fromRGB(25, 25, 30)
                        v37.TextColor3 = Color3.fromRGB(150, 150, 150)
                    end
                end
            end
        end

        for i, v35 in ipairs(tbl12) do
            local textButton2 = Instance.new("TextButton")
            textButton2.Size = UDim2.new(1, 0, 0, 26)
            textButton2.BorderSizePixel = 0
            textButton2.Font = Enum.Font.GothamBold
            textButton2.TextSize = 10
            textButton2.Text = v35.display
            textButton2.LayoutOrder = i
            textButton2.Parent = frame3
            Instance.new("UICorner", textButton2).CornerRadius = UDim.new(0, 6)

            local function fn76()
                str = v35.internal
                visible = false
                fn75()
            end

            textButton2.MouseButton1Click:Connect(fn76)

            textButton2.InputEnded:Connect(function(input)
                if input.UserInputType == Enum.UserInputType.Touch then
                    fn76()
                end
            end)

            tbl13[v35.internal] = textButton2
        end

        fn75()
        local flag9 = false
        local flag10 = false
        local v35 = nil
        local position = nil
        local position2 = nil

        textButton.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                flag9 = true
                flag10 = false
                v35 = input
                position = input.Position
                position2 = frame2.Position
            end
        end)

        textButton.InputEnded:Connect(function(input)
            if input == v35 then
                flag9 = false

                if not flag10 then
                    local flag11

                    if visible then
                        flag11 = false
                    else
                        flag11 = true
                    end

                    visible = flag11
                    fn75()
                end

                v35 = nil
            end
        end)

        UserInputService.InputChanged:Connect(function(input)
            if not flag9 then
                return
            end
            local flag11 = false

            if input.UserInputType == Enum.UserInputType.Touch and input == v35 then
                flag11 = true
            elseif input.UserInputType == Enum.UserInputType.MouseMovement and v35.UserInputType == Enum.UserInputType.MouseButton1 then
                flag11 = true
            end

            if flag11 then
                local n3 = input.Position - position

                if math.abs(n3.X) > 4 or math.abs(n3.Y) > 4 then
                    flag10 = true
                end

                if flag10 then
                    local udim22 = UDim2.new(position2.X.Scale, position2.X.Offset + n3.X, position2.Y.Scale, position2.Y.Offset + n3.Y)
                    frame2.Position = udim22
                    udim2 = udim22
                end
            end
        end)

        if connection3 then
            connection3:Disconnect()
            connection3 = nil
        end

        connection3 = UserInputService.InputBegan:Connect(function(input, gameProcessed)
            if not flag4 then
                return
            end

            if gameProcessed or input.UserInputType ~= Enum.UserInputType.Keyboard then
                return
            end
            local str2 = nil

            if input.KeyCode == Enum.KeyCode.K then
                str2 = "Killer"
            elseif input.KeyCode == Enum.KeyCode.J then
                str2 = "Survivors"
            elseif input.KeyCode == Enum.KeyCode.L then
                str2 = "Zombie"
            end

            if str2 and str2 ~= str then
                str = str2
                fn75()
            end
        end)

        v34 = screenGui2
    end

    destroyTargetSelectorUI = function()
        if connection3 then
            connection3:Disconnect()
            connection3 = nil
        end

        if v34 then
            v34:Destroy()
            v34 = nil
        end
    end

    -- ===== Twist of Fate: wall-check =====
    -- Game facts (from its own client scripts): the shot is Fire(item, direction, step). The direction starts at the MUZZLE
    -- (not the camera) and goes through the crosshair point. Accuracy step is picked by how long the aim was held
    -- (full accuracy at the last STEPS[].at = 3s), so "2.6s - 86% ACC" = held time / 3s.
    local ToF = {remote = fire, wallCheck = false, status = "idle", last = 0, blockedAt = 0, blockedMsg = ""}
    _G.Ox.ToF = ToF

    local TOF_FULL = 3
    pcall(function()
        local tuning = require(ReplicatedStorage.Modules.Items.TwistOfFate.TwistoffateTuning)
        local last = tuning.STEPS[#tuning.STEPS]
        if last and type(last.at) == "number" and last.at > 0 then
            TOF_FULL = last.at
        end
    end)

    local function tofItem(char, obj)
        if typeof(obj) ~= "Instance" or not char or not obj:IsDescendantOf(char) then
            return nil
        end
        local item = obj
        while item.Parent and item.Parent ~= char do
            item = item.Parent
        end
        return item
    end

    -- same muzzle point the game uses for the bullet
    local function tofMuzzle(char)
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        if not hrp then
            return nil
        end
        local from = hrp.Position + Vector3.new(0, 1.373, 0)
        local to = (hrp.CFrame * CFrame.new(0.7, 1.373, -2.5)).Position
        local delta = to - from
        if delta.Magnitude <= 0 then
            return to
        end
        local params = RaycastParams.new()
        params.FilterType = Enum.RaycastFilterType.Exclude
        params.FilterDescendantsInstances = {char}
        params.IgnoreWater = true
        local hit = workspace:Raycast(from, delta, params)
        if hit then
            return hit.Position - delta.Unit * 0.5
        end
        return to
    end

    local function killerOf(inst)
        local model = inst and inst:FindFirstAncestorOfClass("Model")
        local plr = model and Players:GetPlayerFromCharacter(model)
        if plr and plr ~= localPlayer and plr.Team and plr.Team.Name == "Killer" then
            return model
        end
        return nil
    end

    -- does a shot from origin along dir reach a killer's body with nothing solid in front of it?
    local function tofClearHit(origin, dir)
        if typeof(dir) ~= "Vector3" or dir.Magnitude < 0.01 then
            return false
        end
        local mine = localPlayer.Character
        local params = RaycastParams.new()
        params.FilterType = Enum.RaycastFilterType.Exclude
        params.IgnoreWater = true
        local list = {mine}
        for _ = 1, 12 do
            params.FilterDescendantsInstances = list
            local hit = workspace:Raycast(origin, dir.Unit * 1000, params)
            if not hit then
                return false
            end
            if killerOf(hit.Instance) then
                return true
            end
            if hit.Instance.Transparency <= 0.01 and hit.Instance.CanQuery then
                return false
            end
            table.insert(list, hit.Instance)
        end
        return false
    end

    local function tofLineClear(origin, targetPos, killerModel)
        local params = RaycastParams.new()
        params.FilterType = Enum.RaycastFilterType.Exclude
        params.IgnoreWater = true
        local list = {localPlayer.Character, killerModel}
        for _ = 1, 12 do
            params.FilterDescendantsInstances = list
            local hit = workspace:Raycast(origin, targetPos - origin, params)
            if not hit then
                return true
            end
            if hit.Instance.Transparency > 0.01 then
                table.insert(list, hit.Instance)
            else
                return false
            end
        end
        return false
    end

    local function invalidReason(char, obj)
        local item = tofItem(char, obj)
        if not item then
            return "not equipped"
        end
        if item:GetAttribute("tofState") == "cooldown" then
            return "cooldown"
        end
        local shots = item:GetAttribute("shots")
        if (shots == nil and 1 or shots) <= 0 then
            return "no shots"
        end
        local hum = char:FindFirstChildOfClass("Humanoid")
        if not hum or hum.Health <= 0 then
            return "dead"
        end
        if CollectionService:HasTag(char, "Silenced") or localPlayer:GetAttribute("IsDead") then
            return "silenced"
        end
        if char:GetAttribute("Trapped") or char:GetAttribute("IsHooked") or char:GetAttribute("IsCarried") then
            return "busy"
        end
        return nil
    end

    -- called from the namecall hook for every shot the game sends. false = cancel, nil = let it through unchanged
    function ToF.onFire(obj, look)
        local char = localPlayer.Character
        if not ToF.wallCheck then
            return nil
        end
        local reason = invalidReason(char, obj)
        if not reason then
            local cam = workspace.CurrentCamera
            local origin = tofMuzzle(char) or (cam and cam.CFrame.Position)
            if not (origin and tofClearHit(origin, look)) then
                reason = "no target"
            end
        end
        if reason then
            ToF.status = "blocked: " .. reason
            ToF.blockedAt = os.clock()
            ToF.blockedMsg = reason
            return false
        end
        ToF.last = os.clock()
        ToF.status = "shot allowed"
        return nil
    end

    PistolSection:AddToggle("Silent Aim ToF", false, function(on)
        flag4 = on
        if on then
            createTargetSelectorUI()
            startConnection()
        else
            stopConnection()
            destroyTargetSelectorUI()
        end
    end, {Flag = "ToFSilentAim"})

    PistolSection:AddToggle("TOF Wall Check", false, function(on)
        ToF.wallCheck = on
        flag7 = on
        ToF.status = on and "wallcheck ready" or "idle"
    end, {Flag = "ToFWallCheck"})

    UserInputService.InputBegan:Connect(function(input, gameProcessed)
        local flag9 = input.UserInputType == Enum.UserInputType.Touch
        if gameProcessed and not flag9 then
            return
        end

        if input.UserInputType == Enum.UserInputType.MouseButton2 then
            flag8 = true

            if _G.Ox.AimConfig.Flash_Silent then
                flag = true
            end
        end
    end)

    UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton2 then
            if flag8 and flag4 then
                doShoot()
            end
            flag8 = false
            flag = false

            if part then
                part.Transparency = 1
            end
        end
    end)

    local connection4 = nil

    hookMobileButtons = function(arg)
        task.wait(0.5)
        local controls = arg:WaitForChild("Controls", 10)
        if not controls then
            return
        end
        local guiMob = controls:WaitForChild("Gui-mob", 5)
        if not guiMob then
            return
        end

        guiMob.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
                flag8 = true

                if _G.Ox.AimConfig.Flash_Silent then
                    flag = true
                end
            end
        end)

        guiMob.InputEnded:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
                doShoot()
                flag8 = false
                flag = false

                if part then
                    part.Transparency = 1
                end
            end
        end)
    end

    setupMobileButton = function()
        local playerGui2 = localPlayer:WaitForChild("PlayerGui", 10)
        if not playerGui2 then
            return
        end
        local survivorMob = playerGui2:FindFirstChild("Survivor-mob")

        if survivorMob then
            task.spawn(hookMobileButtons, survivorMob)
        end

        if connection4 then
            connection4:Disconnect()
            connection4 = nil
        end

        connection4 = playerGui2.ChildAdded:Connect(function(child)
            if child.Name == "Survivor-mob" then
                task.spawn(hookMobileButtons, child)
            end
        end)
    end

    setupMobileButton()

    localPlayer.CharacterAdded:Connect(function(character)
        clearLaser()
        tbl8 = {}
        tbl10 = {}
        n2 = 0
        flag8 = false
        character:WaitForChild("HumanoidRootPart", 5)
        setupMobileButton()

        if flag4 then
            stopConnection()
            task.wait(0.2)
            startConnection()
        end
    end)

    playerGui.ChildRemoved:Connect(function(child)
        if not flag4 then
            return
        end
        task.wait(0.5)
        if not flag4 then
            return
        end

        if child.Name == "ToFTargetSelector" then
        end
    end)

    AbilityCard:AddToggle("Auto Crouch (Dodge Abyssal S1)", false, function(autoCrouch)
        _G.Ox.ParryConfig.AutoCrouch = autoCrouch
    end, {Flag = "AutoCrouch"})

    local v46 = VaultCard:AddToggle("Unlimited Vault", false, function(arg)
        fn53(arg)
    end, {Flag = "UnlimitedVault"})

    UnlimitedVaultToggle = v46

    local v47 = VaultCard:AddToggle("Anti Slow Vault", false, function(survPerfectVault)
        _G.Ox.Config.Surv_PerfectVault = survPerfectVault
    end, {Flag = "AntiSlowVault"})

    AntiSlowVaultToggle = v47

    local v48 = AbilityCard:AddToggle("Flowstate No CD", false, function(arg)
        fn55(arg)
    end, {Flag = "FlowstateNoCD"})

    FlowstateToggle = v48
end

local v3 = AbilityCard:AddToggle("No Fall Damage", false, function(arg)
    fn14(arg)
end, {Flag = "NoFallDamage"})

NoFallToggle = v3

local v5 = AbilityCard:AddToggle("Self Heal", false, function(arg)
    fn16(arg)
end, {Flag = "SelfHeal"})

SelfHealToggle = v5

do
    local HealCard = SurvivorHealCard
    local H = {team = false, range = 15, bandage = false}

    local function healCandidate(myRoot)
        local best, bestDist = nil, H.range
        for _, plr in ipairs(Players:GetPlayers()) do
            local char = plr ~= localPlayer and plr.Character
            local root = char and char:FindFirstChild("HumanoidRootPart")
            local hum = char and char:FindFirstChildOfClass("Humanoid")
            if root and hum and hum.Health > 0 and root:GetAttribute("CanGetHealed") == true
                and not char:GetAttribute("IsHooked") and not char:GetAttribute("IsCarried") then
                local d = (root.Position - myRoot.Position).Magnitude
                if d <= bestDist then
                    best, bestDist = root, d
                end
            end
        end
        return best
    end

    HealCard:AddToggle("Heal Team", false, function(v)
        H.team = v
    end, {Flag = "HealTeam"})

    task.spawn(function()
        while _G.Ox.ScriptAlive do
            task.wait(0.25)
            if H.team and localPlayer.Team and localPlayer.Team.Name ~= "Killer" then
                pcall(function()
                    local char = localPlayer.Character
                    local myRoot = char and char:FindFirstChild("HumanoidRootPart")
                    local myHum = char and char:FindFirstChildOfClass("Humanoid")
                    if not (myRoot and myHum and myHum.Health > 0) or char:GetAttribute("Trapped") or char:GetAttribute("IsHooked")
                        or char:GetAttribute("IsCarried") then
                        return
                    end
                    local target = healCandidate(myRoot)
                    if not target or not _G.Ox.Act.try("heal", 30) then
                        return
                    end
                    _G.Ox.Net.heal(target, true)
                    local t0 = os.clock()
                    while H.team and _G.Ox.ScriptAlive and os.clock() - t0 < 25 do
                        task.wait(0.2)
                        local r = localPlayer.Character and localPlayer.Character:FindFirstChild("HumanoidRootPart")
                        if not (r and target.Parent) or target:GetAttribute("CanGetHealed") ~= true
                            or (target.Position - r.Position).Magnitude > H.range + 5 then
                            break
                        end
                    end
                    _G.Ox.Net.heal(target, false)
                    task.wait(0.3)
                end)
                _G.Ox.Act.done("heal")
            end
        end
    end)

    -- Infinite Bandage: talks to the server like the game's BandageClient does: Bandage.Fire(isHealing, tool, requestId).
    -- The Bandage tool does not have to be the one you are holding (parry / ToF stay equipped), the server is told
    -- "healing started" / "healing stopped" for the tool in your backpack or hand.
    local function bandageTool()
        local char = localPlayer.Character
        local backpack = localPlayer:FindFirstChildOfClass("Backpack")
        return (char and char:FindFirstChild("Bandage")) or (backpack and backpack:FindFirstChild("Bandage"))
    end

    HealCard:AddToggle("Infinite Bandage", false, function(v)
        H.bandage = v
    end, {Flag = "InfiniteBandage"})

    local bandageId = 1000
    task.spawn(function()
        local fire
        while _G.Ox.ScriptAlive do
            task.wait(0.3)
            if H.bandage and localPlayer.Team and localPlayer.Team.Name ~= "Killer" then
                pcall(function()
                    local char = localPlayer.Character
                    local hum = char and char:FindFirstChildOfClass("Humanoid")
                    local tool = bandageTool()
                    if not fire or not fire.Parent then
                        local r = ReplicatedStorage:FindFirstChild("Remotes")
                        local items = r and r:FindFirstChild("Items")
                        local bandage = items and items:FindFirstChild("Bandage")
                        fire = bandage and bandage:FindFirstChild("Fire")
                    end
                    if not (hum and tool and fire) or hum.Health <= 0 or hum.Health >= hum.MaxHealth
                        or char:GetAttribute("IsCarried") or char:GetAttribute("IsHooked") or char:GetAttribute("Trapped")
                        or CollectionService:HasTag(char, "Antiheal") or CollectionService:HasTag(char, "Silenced") then
                        return
                    end
                    bandageId += 1
                    local id = bandageId
                    fire:FireServer(true, tool, id)
                    local t0 = os.clock()
                    while H.bandage and os.clock() - t0 < 6 and hum.Health > 0 and hum.Health < hum.MaxHealth
                        and not char:GetAttribute("IsCarried") do
                        task.wait(0.15)
                    end
                    fire:FireServer(false, tool, id)
                    task.wait(0.2)
                end)
            end
        end
    end)
end

local v6 = AbilityCard:AddToggle("God Mode (Anti Knockdown)", false, function(godMode)
    _G.Ox.GodMode = godMode
end, {Flag = "GodMode"})

GodModeToggle = v6

local v17 = KillerAimbotCard:AddToggle("Enable Aimbot (Melee)", false, function(killerAimbotEnabled)
    _G.Ox.Config.Killer_Aimbot_Enabled = killerAimbotEnabled

    if not killerAimbotEnabled and _G.Ox.killerAimbotHighlight then
        _G.Ox.killerAimbotHighlight.Parent = nil
    end
end, {Flag = "AimbotKiller"})

KillerAimbotToggle = v17

KillerAimbotCard:AddSlider("Max Distance", 5, 30, 12, function(killerAimbotMaxDist)
    _G.Ox.Config.Killer_Aimbot_MaxDist = killerAimbotMaxDist
end, {Increment = 1, Flag = "AimbotKillerMaxDist"})

KillerAimbotCard:AddToggle("Best Smooth", true, function(bestSmooth)
    _G.Ox.Config.Killer_Aimbot_BestSmooth = bestSmooth
end, {Flag = "AimbotKillerBestSmooth"})

local v19 = VeilCard:AddToggle("Silent Veil", false, function(aimSilentVeilV2)
    _G.Ox.AimConfig.Aim_SilentVeilV2 = aimSilentVeilV2
end, {Flag = "SilentVeil"})

VeilTog = v19

VeilCard:AddToggle("Veil Laser", false, function(on)
    _G.Ox.AimConfig.Veil_Laser = on
end, {Flag = "VeilLaser"})

VeilCard:AddToggle("Veil Trajectory", false, function(on)
    _G.Ox.AimConfig.Veil_Trajectory = on
end, {Flag = "VeilTrajectory"})

VeilCard:AddToggle("Perma Lock", false, function(on)
    _G.Ox.AimConfig.Veil_PermaLock = on
    if not on then
        _G.Ox.AimConfig.Veil_PermaTarget = nil
    end
end, {Flag = "VeilPermaLock", KeybindNotify = true})

_G.Ox.AimConfig.Veil_Direct = true
_G.Ox.AimConfig.Veil_ShowFOV = false
VeilCard:AddSlider("FOV Radius", 50, 500, 150, function(veilFov)
    _G.Ox.AimConfig.Veil_FOV = veilFov
end, {Increment = 1, Flag = "VeilFOV"})

local v21 = KillerAbilityCard:AddToggle("Anti Blind (Flashlight)", false, function(antiBlindEnabled)
    _G.Ox.AntiBlindEnabled = antiBlindEnabled
end, {Flag = "AntiBlind"})

AntiBlindToggle = v21

local v22 = KillerAbilityCard:AddToggle("Anti Parry", false, function(arg)
    ToggleCounterParry(arg)
end)

CounterParryToggle = v22

local v23 = KillerAbilityCard:AddToggle("Infinite Lunge", false, function(arg)
    if arg then
        EnableInfiniteLunge()
    else
        DisableInfiniteLunge()
    end
end, {Flag = "InfiniteLunge"})

InfLungeToggle = v23

local v25 = KillerAbilityCard:AddToggle("No Slowdown Killer", false, function(noSlowdownEnabled)
    _G.Ox.NoSlowdownEnabled = noSlowdownEnabled

    if noSlowdownEnabled then
        local character = localPlayer.Character

        if character then
            local humanoid = character:FindFirstChildOfClass("Humanoid")

            if humanoid then
                humanoid.WalkSpeed = 16
            end
        end

    else
    end
end, {Flag = "NoSlowdown"})

AntiSlowdownToggle = v25

do

    local LUNGE_DELAY = 0.21
    local AURA_COOLDOWN = 1.1
    local ATTACK_RANGE = 9
    local REACH_RANGE = 13
    local LEGIT_ANGLE = 0.5
    local KICK_REGRESS = 25

    local K = {
        attack = false,
        carry = false,
        hook = false,
        kickGen = false,
        breakPallet = false,
        antiStun = false,
        freeTurn = false,
        reachAssist = false,

        atkUntil = 0,
        rejected = {},
        badPoint = setmetatable({}, {__mode = "k"}),
        kicked = setmetatable({}, {__mode = "k"}),
    }

    local function remote(...)
        local cur = ReplicatedStorage:FindFirstChild("Remotes")
        for _, name in ipairs({...}) do
            cur = cur and cur:FindFirstChild(name)
        end
        return cur
    end

    local R = {
        carry = remote("Carry", "CarrySurvivorEvent"),
        carryAnimDone = remote("Carry", "CarryAnimDone"),
        hook = remote("Carry", "HookEvent"),
        hookCommit = remote("Carry", "HookCommit"),
        hookReject = remote("Carry", "HookReject"),
        gen = remote("Generator", "BreakGenEvent"),
        genCommit = remote("Generator", "BreakGenCommit"),
        genReject = remote("Generator", "BreakGenReject"),
        attack = remote("Attacks", "BasicAttack"),
        lunge = remote("Attacks", "Lunge"),
        stun = remote("Pallet", "Jason", "Stun"),
        stunOver = remote("Pallet", "Jason", "Stunover") or remote("Pallet", "Jason", "StunOver"),
    }

    for _, name in ipairs({"hookReject", "genReject"}) do
        local rejectRemote = R[name]
        if rejectRemote then
            rejectRemote.OnClientEvent:Connect(function(id)
                if typeof(id) == "string" then
                    K.rejected[id] = true
                end
            end)
        end
    end

    local function isKiller()
        return localPlayer.Team ~= nil and localPlayer.Team.Name == "Killer"
    end

    local function me()
        local char = localPlayer.Character
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        if char and hrp and hum and hum.Health > 0 then
            return char, hrp, hum
        end
        return nil
    end

    local function ready(char)
        return not (char:GetAttribute("Immobile") or char:GetAttribute("IsStunned"))
    end

    local function survivors()
        local list = {}
        for _, plr in ipairs(Players:GetPlayers()) do
            if plr ~= localPlayer and plr.Team and plr.Team.Name == "Survivors" and plr.Character then
                table.insert(list, plr.Character)
            end
        end
        for _, bot in ipairs(CollectionService:GetTagged("SurvivorBot")) do
            table.insert(list, bot)
        end
        return list
    end

    local function aliveRoot(char)
        local root = char:FindFirstChild("HumanoidRootPart")
        local hum = char:FindFirstChildOfClass("Humanoid")
        if root and hum and hum.Health > 0 then
            return root, hum
        end
        return nil
    end

    local function canHit(char)
        return aliveRoot(char) ~= nil
            and char:GetAttribute("Knocked") ~= true
            and not char:GetAttribute("IsCarried")
            and not char:GetAttribute("IsHooked")
    end

    local function validPoint(point)
        return point:IsA("BasePart") and point.Parent and not CollectionService:HasTag(point, "doing action")
            and not point.Parent:GetAttribute("Regressing")
    end

    -- nearest point of a tag, nothing is range limited; points that could not be reached are skipped for a while
    local function nearest(tag, filter)
        local char, hrp = me()
        if not char then
            return nil
        end
        local best, bestDist = nil, math.huge
        local now = tick()
        for _, point in ipairs(CollectionService:GetTagged(tag)) do
            if validPoint(point) and (K.badPoint[point] or 0) < now and (not filter or filter(point)) then
                local dist = (point.Position - hrp.Position).Magnitude
                if dist < bestDist then
                    best, bestDist = point, dist
                end
            end
        end
        return best
    end

    local function walkTo(pos, stop, active)
        local _, hrp = me()
        if not hrp then
            return false
        end
        if (hrp.Position - pos).Magnitude <= stop then
            return true
        end
        return _G.Ox.Walker.walkTo(pos, {stop = stop, timeout = 60, active = function()
            return _G.Ox.ScriptAlive and isKiller() and me() ~= nil and active()
        end})
    end

    -- walk next to the point, then do the real start/commit calls (no teleporting)
    local function interact(point, startRemote, commitRemote, hold, stop, active)
        if not (startRemote and commitRemote) then
            return false
        end
        if not walkTo(point.Position, stop, active) then
            K.badPoint[point] = tick() + 8
            return false
        end
        local char = me()
        if not char or not active() then
            return false
        end
        _G.Ox.Walker.face(point.Position)
        task.wait(0.1)
        local id = HttpService:GenerateGUID(false)
        K.rejected[id] = nil
        pcall(function()
            startRemote:FireServer(point, id, char)
        end)
        task.wait(0.1)
        pcall(function()
            commitRemote:FireServer(point, id, char)
        end)
        local t0 = tick()
        while tick() - t0 < hold and not K.rejected[id] and _G.Ox.ScriptAlive and me() do
            task.wait(0.05)
        end
        return not K.rejected[id]
    end

    local function hookOccupied(hookPoint)
        for _, char in ipairs(survivors()) do
            local root = char:FindFirstChild("HumanoidRootPart")
            if root and char:GetAttribute("IsHooked") and (root.Position - hookPoint.Position).Magnitude < 10 then
                return true
            end
        end
        return false
    end

    -- Auto Hook: only hooks the survivor you are carrying
    local function doHook()
        local char = me()
        local hookPoint = nearest("HookPoint", function(point)
            return not hookOccupied(point)
        end)
        if not (char and hookPoint) then
            return false
        end
        local function active()
            return K.hook and char:GetAttribute("IsCarrying") == true
        end
        interact(hookPoint, R.hook, R.hookCommit, 0.6, 3.5, active)
        local t0 = tick()
        while char and char:GetAttribute("IsCarrying") and tick() - t0 < 2.5 do
            task.wait(0.1)
        end
        return true
    end

    -- Auto Carry: walks to the nearest downed survivor and picks them up
    local function doCarry()
        local char, hrp = me()
        if not char or not R.carry then
            return false
        end
        local target, bestDist = nil, math.huge
        local now = tick()
        for _, other in ipairs(survivors()) do
            local root, hum = aliveRoot(other)
            if root and (K.badPoint[other] or 0) < now then
                local downed = other:GetAttribute("Knocked") == true or hum.Health <= 20
                local progress = other:GetAttribute("HookedProgress")
                local onEarlyHook = progress ~= nil and progress < 2
                if downed and not onEarlyHook and not other:GetAttribute("IsCarried") and not other:GetAttribute("IsHooked") then
                    local dist = (root.Position - hrp.Position).Magnitude
                    if dist < bestDist then
                        target, bestDist = other, dist
                    end
                end
            end
        end
        if not target then
            return false
        end
        local function active()
            return K.carry and target.Parent ~= nil
                and not target:GetAttribute("IsCarried") and not target:GetAttribute("IsHooked")
        end
        local root = target:FindFirstChild("HumanoidRootPart")
        if not walkTo(root.Position, 3.2, active) then
            K.badPoint[target] = tick() + 8
            return true
        end
        if not active() or not me() then
            return true
        end
        _G.Ox.Walker.face(target.HumanoidRootPart.Position)
        task.wait(0.1)
        pcall(function()
            R.carry:FireServer(target)
        end)
        task.wait(0.5)
        if R.carryAnimDone then
            pcall(function()
                R.carryAnimDone:FireServer(1)
            end)
        end
        return true
    end

    local function doGen()
        local point = nearest("GeneratorPoint", function(pt)
            local gen = pt.Parent
            local progress = gen:GetAttribute("RepairProgress") or 0
            local kicks = gen:GetAttribute("kickcount") or 0
            local fresh = tick() - (K.kicked[gen] or 0) > KICK_REGRESS
            return progress > 0 and progress < 100 and kicks <= 7 and fresh
        end)
        if not point then
            return false
        end
        if interact(point, R.gen, R.genCommit, 1.95, 3.5, function()
            return K.kickGen
        end) then
            K.kicked[point.Parent] = tick()
        end
        return true
    end

    -- Break Pallet: same sequence as the game's KillerActions: Jason."Destroy-Global"(point, id, char) then PalletBreakCommit
    local palletRemote = {start = remote("Pallet", "Jason", "Destroy-Global"), commit = remote("Pallet", "Jason", "PalletBreakCommit")}
    local palletCache, palletScanAt = {}, 0
    local function droppedPalletPoint()
        local char, hrp = me()
        if not hrp then
            return nil
        end
        if tick() - palletScanAt > 3 then
            palletScanAt = tick()
            palletCache = {}
            local root = workspace:FindFirstChild("Map") or workspace
            for _, d in ipairs(root:GetDescendants()) do
                if d.Name == "PalletPoint" and d:IsA("BasePart") then
                    palletCache[#palletCache + 1] = d
                end
            end
        end
        local best, bestDist, now = nil, math.huge, tick()
        for _, point in ipairs(palletCache) do
            local model = point.Parent
            if point.Parent and model and model:GetAttribute("PalletState") == "Dropped" and (K.badPoint[point] or 0) < now then
                local dist = (point.Position - hrp.Position).Magnitude
                if dist < bestDist then
                    best, bestDist = point, dist
                end
            end
        end
        return best
    end

    local function doPalletBreak()
        local point = droppedPalletPoint()
        if not point then
            return false
        end
        if not palletRemote.start or not palletRemote.commit then
            palletRemote.start = remote("Pallet", "Jason", "Destroy-Global")
            palletRemote.commit = remote("Pallet", "Jason", "PalletBreakCommit")
        end
        interact(point, palletRemote.start, palletRemote.commit, 1.8, 3.5, function()
            return K.breakPallet and point.Parent ~= nil and point.Parent:GetAttribute("PalletState") == "Dropped"
        end)
        return true
    end

    local function fireLunge()
        if R.lunge then
            pcall(function()
                R.lunge:FireServer()
            end)
        end
    end

    -- turn on the spot (rotation only, position never changes)
    local function faceTarget(hrp, root)
        hrp.CFrame = CFrame.lookAt(hrp.Position, Vector3.new(root.Position.X, hrp.Position.Y, root.Position.Z))
    end

    -- Auto Attack: closest survivor inside the swing hitbox. Reach Assist = bigger invisible hitbox + auto turning towards it.
    local function legitTarget(hrp)
        local look = hrp.CFrame.LookVector
        local range = K.reachAssist and REACH_RANGE or ATTACK_RANGE
        local angle = K.reachAssist and -0.1 or LEGIT_ANGLE
        local best, bestDist = nil, math.huge
        for _, char in ipairs(survivors()) do
            if canHit(char) then
                local offset = char.HumanoidRootPart.Position - hrp.Position
                local dist = offset.Magnitude
                if dist > 0 and dist <= range and dist < bestDist and look:Dot(offset.Unit) >= angle then
                    best, bestDist = char, dist
                end
            end
        end
        return best
    end

    local function swing(target)
        local root = target:FindFirstChild("HumanoidRootPart")
        if not root then
            return
        end
        local _, hrp = me()
        if not hrp then
            return
        end
        if K.reachAssist then
            faceTarget(hrp, root)
        end
        fireLunge()
        task.wait(LUNGE_DELAY)
        local _, hrp2 = me()
        if hrp2 and root.Parent and K.reachAssist then
            faceTarget(hrp2, root)
        end
        pcall(function()
            R.attack:FireServer()
        end)
    end

    local function doAttack(hrp)
        if not R.attack or tick() < K.atkUntil then
            return false
        end
        local target = legitTarget(hrp)
        if not target then
            return false
        end
        K.atkUntil = tick() + AURA_COOLDOWN
        swing(target)
        return true
    end

    local function step()
        if not (K.attack or K.carry or K.hook or K.kickGen or K.breakPallet) or not isKiller() then
            return
        end
        local char, hrp = me()
        if not char or not ready(char) then
            return
        end
        if not _G.Ox.Act.try("killer", 70) then
            return
        end

        if char:GetAttribute("IsCarrying") then
            if K.hook then
                doHook()
            end
        elseif not (K.carry and doCarry()) and not (K.attack and doAttack(hrp)) and not (K.breakPallet and doPalletBreak()) and K.kickGen then
            doGen()
        end
        _G.Ox.Act.done("killer")
    end

    task.spawn(function()
        while _G.Ox.ScriptAlive do
            task.wait(0.15)
            local ok, err = pcall(step)
            if not ok then
                _G.Ox.Act.done("killer")
                warn("[Kisha] killer automation: " .. tostring(err))
                task.wait(1)
            end
        end
    end)

    local mutedStun = {}
    local function releaseStun()
        if K.antiStun and isKiller() and R.stunOver then
            pcall(function()
                R.stunOver:FireServer()
            end)
        end
    end

    local function setStunMuted(muted)
        if muted then
            if type(getconnections) ~= "function" or not R.stun then
                return
            end
            pcall(function()
                for _, conn in ipairs(getconnections(R.stun.OnClientEvent)) do
                    if conn.Enabled and conn.Function ~= releaseStun then
                        conn:Disable()
                        table.insert(mutedStun, conn)
                    end
                end
            end)
        else
            for _, conn in ipairs(mutedStun) do
                pcall(function()
                    conn:Enable()
                end)
            end
            table.clear(mutedStun)
        end
    end

    if R.stun and R.stunOver then
        R.stun.OnClientEvent:Connect(releaseStun)
    end

    local turnConn
    turnConn = RunService.Heartbeat:Connect(function()
        if not _G.Ox.ScriptAlive then
            turnConn:Disconnect()
            return
        end
        if not K.freeTurn or not isKiller() then
            return
        end
        local char, hrp, hum = me()
        if not char or hum.AutoRotate or char:GetAttribute("overridelookscript") or char:GetAttribute("Immobile") then
            return
        end
        local look = workspace.CurrentCamera.CFrame.LookVector
        local flat = Vector3.new(look.X, 0, look.Z)
        if flat.Magnitude > 0 then
            hrp.CFrame = CFrame.lookAt(hrp.Position, hrp.Position + flat)
        end
    end)

    AutoAttackCard:AddToggle("Auto Attack (Aura)", false, function(on)
        K.attack = on
    end, {Flag = "MeowX_AutoAttack"})

    AutoAttackCard:AddToggle("Reach Assist", false, function(on)
        K.reachAssist = on
    end, {Flag = "MeowX_ReachAssist"})

    ObjectivesCard:AddToggle("Auto Carry", false, function(on)
        K.carry = on
    end, {Flag = "MeowX_AutoCarry"})

    ObjectivesCard:AddToggle("Auto Hook", false, function(on)
        K.hook = on
    end, {Flag = "MeowX_AutoHook"})

    ObjectivesCard:AddToggle("Auto Break Pallet", false, function(on)
        K.breakPallet = on
    end, {Flag = "MeowX_AutoBreakPallet"})


    KillerAbilityCard:AddToggle("Anti Stun (Pallet)", false, function(on)
        K.antiStun = on
        setStunMuted(on)
    end, {Flag = "MeowX_AntiStun"})

    KillerAbilityCard:AddToggle("No Turn Limit", false, function(on)
        K.freeTurn = on
    end, {Flag = "MeowX_FreeTurn"})

end

-- ===== Perks: auto buy / auto level / equip presets (Survivor tab + Killer tab) =====
do
    local SLOTS = 3
    local SURVIVOR_PRESETS = {
        ["Gen Boost"] = {"Perfectionist Planning", "Group Project", "Enhanced Touch"},
        ["Looping"] = {"Quick Recovery", "Great Collapse", "Visual Learner"},
        ["Medic"] = {"Enhanced Touch", "Grab My Hand", "Against All Odds"},
    }
    local KILLER_PRESETS = {
        ["Anti Gen"] = {"Crackdown", "King's Scourge", "Buddha Shrine"},
        ["Fast Gameplay"] = {"Murderous Acrobatics", "Stage Fright", "Sloppy Mess"},
    }

    local function norm(text)
        return (tostring(text):lower():gsub("[^%w]", ""))
    end

    local function remote(folder, name)
        local remotes = ReplicatedStorage:FindFirstChild("Remotes")
        local group = remotes and remotes:FindFirstChild(folder)
        return group and group:FindFirstChild(name)
    end

    local function invoke(rem, ...)
        if not rem then
            return nil
        end
        local ok, result = pcall(rem.InvokeServer, rem, ...)
        return ok and result or nil
    end

    local function wallet()
        return tonumber(localPlayer:GetAttribute("Screws")) or 0, tonumber(localPlayer:GetAttribute("Gears")) or 0
    end

    -- {name = level} from either {name = level} or {name = {level = n}}
    local function levels(data)
        local out = {}
        if type(data) == "table" then
            for name, value in pairs(data) do
                if type(name) == "string" then
                    local level = type(value) == "table" and (tonumber(value.level) or 1) or tonumber(value) or (value and 1 or 0)
                    out[name] = level
                end
            end
        end
        return out
    end

    -- the real (game) name of a perk: matches ignoring case, spaces and punctuation
    local function realName(wanted, ...)
        local key = norm(wanted)
        for _, source in ipairs({...}) do
            if typeof(source) == "Instance" then
                for _, child in ipairs(source:GetChildren()) do
                    if norm(child.Name) == key then
                        return child.Name
                    end
                end
            elseif type(source) == "table" then
                for name in pairs(source) do
                    if type(name) == "string" and norm(name) == key then
                        return name
                    end
                end
            end
        end
        return nil
    end

    local function spend(ownedMap)
        -- picks the highest level perks first (used for alternatives)
        local list = {}
        for name, level in pairs(ownedMap) do
            if level >= 1 then
                list[#list + 1] = name
            end
        end
        table.sort(list, function(a, b)
            if ownedMap[a] ~= ownedMap[b] then
                return ownedMap[a] > ownedMap[b]
            end
            return a < b
        end)
        return list
    end

    -- fills the three slots: preset perk when owned, else keep what is already there, else best owned perk
    local function fillSlots(want, current, ownedMap, isAllowed)
        local used = {}
        for i = 1, SLOTS do
            if want[i] then
                used[want[i]] = true
            end
        end
        local alternatives = spend(ownedMap)
        for i = 1, SLOTS do
            if not want[i] then
                local keep = current[i]
                if keep and not used[keep] and (not isAllowed or isAllowed(keep)) then
                    want[i] = keep
                    used[keep] = true
                else
                    for _, name in ipairs(alternatives) do
                        if not used[name] and (not isAllowed or isAllowed(name)) then
                            want[i] = name
                            used[name] = true
                            break
                        end
                    end
                end
            end
        end
        return want
    end

    -- ---------------------------------------------------------------- Survivor perks
    local Surv = {preset = "Gen Boost", buy = false, level = false, busy = false, noLevel = {}}

    local function survivorOwned()
        return levels(invoke(remote("Shop", "GetOwnedPerks")))
    end

    -- owned (buying it first when affordable) -> real perk name, otherwise nil
    local function ensureSurvivorPerk(name, owned)
        local folder = ReplicatedStorage:FindFirstChild("Perks")
        local real = realName(name, owned, folder)
        if not real then
            return nil
        end
        if (owned[real] or 0) >= 1 then
            return real
        end
        local info = invoke(remote("Shop", "GetPerkInfo"), real)
        if type(info) == "table" and info.owned then
            owned[real] = tonumber(info.level) or 1
            return real
        end
        local buy = remote("Shop", "PurchasePerk")
        local _, gears = wallet()
        if buy and type(info) == "table" and tonumber(info.price) and gears >= tonumber(info.price) then
            buy:FireServer(real)
            task.wait(0.5)
            local after = invoke(remote("Shop", "GetPerkInfo"), real)
            if type(after) == "table" and after.owned then
                owned[real] = tonumber(after.level) or 1
                return real
            end
        end
        return nil
    end

    function Surv.buyPreset()
        local bought = 0
        local owned = survivorOwned()
        for _, name in ipairs(SURVIVOR_PRESETS[Surv.preset] or {}) do
            local real = realName(name, owned, ReplicatedStorage:FindFirstChild("Perks"))
            local had = real and (owned[real] or 0) >= 1
            if ensureSurvivorPerk(name, owned) and not had then
                bought += 1
            end
        end
        return bought
    end

    function Surv.equip()
        local owned = survivorOwned()
        local want = {}
        for i, name in ipairs(SURVIVOR_PRESETS[Surv.preset] or {}) do
            want[i] = ensureSurvivorPerk(name, owned)
        end
        local equipped = invoke(remote("Shop", "GetEquippedPerks"))
        local current = {}
        for i = 1, SLOTS do
            local entry = type(equipped) == "table" and equipped[i]
            current[i] = type(entry) == "table" and entry.name or nil
        end
        fillSlots(want, current, owned)
        local equip = remote("Shop", "EquipPerk")
        if not equip then
            return 0
        end
        local changed = 0
        for i = 1, SLOTS do
            if want[i] and current[i] ~= want[i] then
                equip:FireServer(want[i], i)
                changed += 1
                task.wait(0.35)
            end
        end
        return changed
    end

    -- level up: preset perks first, then every other owned perk; one try per perk, failed ones rest for 2 minutes
    function Surv.levelUp()
        local level = remote("Shop", "LevelUpPerk")
        if not level then
            return 0
        end
        local owned = survivorOwned()
        local order, seen = {}, {}
        for _, name in ipairs(SURVIVOR_PRESETS[Surv.preset] or {}) do
            local real = realName(name, owned)
            if real and not seen[real] then
                seen[real] = true
                order[#order + 1] = real
            end
        end
        for _, name in ipairs(spend(owned)) do
            if not seen[name] then
                seen[name] = true
                order[#order + 1] = name
            end
        end
        local count = 0
        for _, name in ipairs(order) do
            if not Surv.level then
                break
            end
            if (Surv.noLevel[name] or 0) < tick() then
                local screwsBefore = wallet()
                local before = owned[name]
                level:FireServer(name)
                task.wait(0.4)
                local info = invoke(remote("Shop", "GetPerkInfo"), name)
                local screwsAfter = wallet()
                if (type(info) == "table" and (tonumber(info.level) or 0) > (before or 0)) or screwsAfter < screwsBefore then
                    count += 1
                else
                    Surv.noLevel[name] = tick() + 120
                end
            end
        end
        return count
    end

    -- ---------------------------------------------------------------- Killer perks
    local Kill = {preset = "Anti Gen", buy = false, level = false, busy = false, noLevel = {}}

    local function selectedKiller()
        local result = invoke(remote("Shop", "GetSelectedKiller"))
        if type(result) == "table" then
            result = result.name or result.Name or result[1]
        end
        return type(result) == "string" and result ~= "" and result or nil
    end

    local function killerPool(killer)
        local killers = ReplicatedStorage:FindFirstChild("Killers")
        local folder = killers and killers:FindFirstChild(killer)
        return folder and folder:FindFirstChild("Perks")
    end

    local function killerUnlocked()
        return levels(invoke(remote("ShopKillers", "GetUnlockedPerks")))
    end

    -- usable by the selected killer: owned (or bought when affordable) and part of that killer's perk list
    local function ensureKillerPerk(name, killer, unlocked)
        local pool = killerPool(killer)
        local real = realName(name, pool or unlocked)
        if not real or (pool and not pool:FindFirstChild(real)) then
            return nil
        end
        if (unlocked[real] or 0) >= 1 then
            return real
        end
        local buy = remote("Shop", "PurchasePerk")
        local info = invoke(remote("Shop", "GetPerkInfo"), real)
        local _, gears = wallet()
        if buy and type(info) == "table" and not info.owned and tonumber(info.price) and gears >= tonumber(info.price) then
            buy:FireServer(real)
            task.wait(0.5)
            local fresh = killerUnlocked()
            if (fresh[real] or 0) >= 1 then
                unlocked[real] = fresh[real]
                return real
            end
        end
        return nil
    end

    function Kill.buyPreset()
        local killer = selectedKiller()
        if not killer then
            return 0
        end
        local bought = 0
        local unlocked = killerUnlocked()
        for _, name in ipairs(KILLER_PRESETS[Kill.preset] or {}) do
            local pool = killerPool(killer)
            local real = realName(name, pool or unlocked)
            local had = real and (unlocked[real] or 0) >= 1
            if ensureKillerPerk(name, killer, unlocked) and not had then
                bought += 1
            end
        end
        return bought
    end

    function Kill.equip()
        local killer = selectedKiller()
        local equip = remote("ShopKillers", "EquipPerk")
        if not (killer and equip) then
            return 0
        end
        local unlocked = killerUnlocked()
        local want = {}
        for i, name in ipairs(KILLER_PRESETS[Kill.preset] or {}) do
            want[i] = ensureKillerPerk(name, killer, unlocked)
        end
        local equipped = invoke(remote("ShopKillers", "GetEquippedKillerPerks"), killer)
        local current = {}
        for i = 1, SLOTS do
            local entry = type(equipped) == "table" and equipped["perk" .. i]
            current[i] = type(entry) == "table" and entry.name or nil
        end
        local pool = killerPool(killer)
        local usableOwned = {}
        for name, level in pairs(unlocked) do
            if not pool or pool:FindFirstChild(name) then
                usableOwned[name] = level
            end
        end
        fillSlots(want, current, usableOwned, function(name)
            return not pool or pool:FindFirstChild(name) ~= nil
        end)
        local changed = 0
        for i = 1, SLOTS do
            if want[i] and current[i] ~= want[i] then
                equip:FireServer(killer, want[i], "perk" .. i)
                changed += 1
                task.wait(0.35)
            end
        end
        return changed
    end

    function Kill.levelUp()
        local level = remote("Shop", "LevelUpPerk")
        local killer = selectedKiller()
        if not (level and killer) then
            return 0
        end
        local unlocked = killerUnlocked()
        local pool = killerPool(killer)
        local order, seen = {}, {}
        for _, name in ipairs(KILLER_PRESETS[Kill.preset] or {}) do
            local real = realName(name, unlocked)
            if real and not seen[real] then
                seen[real] = true
                order[#order + 1] = real
            end
        end
        for _, name in ipairs(spend(unlocked)) do
            if not seen[name] and (not pool or pool:FindFirstChild(name)) then
                seen[name] = true
                order[#order + 1] = name
            end
        end
        local count = 0
        for _, name in ipairs(order) do
            if not Kill.level then
                break
            end
            if (Kill.noLevel[name] or 0) < tick() then
                local screwsBefore = wallet()
                local before = unlocked[name] or 0
                level:FireServer(name)
                task.wait(0.4)
                local after = killerUnlocked()
                if (after[name] or 0) > before or wallet() < screwsBefore then
                    count += 1
                else
                    Kill.noLevel[name] = tick() + 120
                end
            end
        end
        return count
    end

    -- ---------------------------------------------------------------- loops (only act when the wallet or preset changed)
    local function runLoop(side, tag, isMyRole)
        local lastKey
        while _G.Ox.ScriptAlive do
            task.wait(3)
            if (side.buy or side.level) and not side.busy and isMyRole() then
                local screws, gears = wallet()
                local key = screws .. "/" .. gears .. "/" .. side.preset
                if key ~= lastKey then
                    lastKey = key
                    side.busy = true
                    local ok, err = pcall(function()
                        if side.buy and side.buyPreset() > 0 then
                            side.equip()
                        end
                        if side.level then
                            side.levelUp()
                        end
                    end)
                    if not ok then
                        warn("[Kisha] " .. tag .. " perks: " .. tostring(err))
                    end
                    side.busy = false
                end
            end
        end
    end

    -- the shop data is available in the lobby and in the round, so the role is only used to pick the loop
    task.spawn(runLoop, Surv, "survivor", function()
        return true
    end)
    task.spawn(runLoop, Kill, "killer", function()
        return true
    end)

    local function option(value)
        if type(value) == "table" then
            return value[1]
        end
        return value
    end

    local function manual(side, label)
        return function()
            if side.busy then
                return
            end
            side.busy = true
            task.spawn(function()
                local ok, err = pcall(function()
                    side.buyPreset()
                    side.equip()
                end)
                if not ok then
                    warn("[Kisha] " .. label .. " perks: " .. tostring(err))
                end
                side.busy = false
            end)
        end
    end

    local SP = S_Page:CreateSection("Perks (Survivor)", "star")
    SP:AddDropdown("Survivor Perk Preset", {"Gen Boost", "Looping", "Medic"}, false, function(value)
        Surv.preset = option(value) or Surv.preset
    end, {Default = "Gen Boost", Flag = "SurvPerkPreset"})
    SP:AddToggle("Auto Buy Perks", false, function(on)
        Surv.buy = on
    end, {Flag = "SurvAutoBuyPerks"})
    SP:AddToggle("Auto Level Perks", false, function(on)
        Surv.level = on
    end, {Flag = "SurvAutoLevelPerks"})
    SP:AddButton("Equip Perk", manual(Surv, "survivor"))

    local KP = K_Page:CreateSection("Perks (Killer)", "star")
    KP:AddDropdown("Killer Perk Preset", {"Anti Gen", "Fast Gameplay"}, false, function(value)
        Kill.preset = option(value) or Kill.preset
    end, {Default = "Anti Gen", Flag = "KillPerkPreset"})
    KP:AddToggle("Auto Buy Killer Perks", false, function(on)
        Kill.buy = on
    end, {Flag = "KillAutoBuyPerks"})
    KP:AddToggle("Auto Level Killer Perks", false, function(on)
        Kill.level = on
    end, {Flag = "KillAutoLevelPerks"})
    KP:AddButton("Equip Killer Perk", manual(Kill, "killer"))
end

-- ===== Survivor: Auto Parry (Parrying Dagger) =====
do
    local PS = S_Page:CreateSection("Auto Parry (Dagger)", "sword")
    PS:AddToggle("Auto Parry", false, function(on)
        local cfg = _G.Ox.ParryConfig
        cfg.AutoParry = on
        _G.Ox.AutoParryCustom.IsActive = on
    end, {Flag = "AutoParry"})
    PS:AddToggle("Aggressive Mode", false, function(on)
        _G.Ox.ParryConfig.ParryAggressive = on
    end, {Flag = "AutoParryAggressive"})
    PS:AddSlider("Parry Radius", 5, 25, 15, function(value)
        _G.Ox.ParryConfig.ParryRadius = value
    end, {Increment = 1, Flag = "AutoParryRadius"})
end

-- ===== Killer extras (v7): every feature is tied to its killer, rules copied from the game's own client scripts =====
do
    local RS = game:GetService("RunService")

    local function killerRemote(group, name)
        local remotes = ReplicatedStorage:FindFirstChild("Remotes")
        local killers = remotes and remotes:FindFirstChild("Killers")
        local folder = killers and killers:FindFirstChild(group)
        return folder and folder:FindFirstChild(name)
    end

    local function isKiller()
        return localPlayer.Team ~= nil and localPlayer.Team.Name == "Killer"
    end

    -- which killer the local player picked ("The Hidden", "Butcher", ...). nil = unknown (then features stay available)
    local function selectedKiller()
        local value = localPlayer:GetAttribute("SelectedKiller")
        if not value then
            local obj = localPlayer:FindFirstChild("SelectedKiller")
            if obj then
                pcall(function()
                    value = obj.Value
                end)
            end
        end
        local char = localPlayer.Character
        value = value or (char and char:GetAttribute("SelectedKiller")) or (char and char:GetAttribute("Killer"))
        return type(value) == "string" and string.lower(value) or nil
    end

    local function isKillerType(word)
        local name = selectedKiller()
        return isKiller() and (name == nil or string.find(name, word, 1, true) ~= nil)
    end

    local function busy(char)
        if not char then
            return true
        end
        local interact = char:FindFirstChild("CheckInterractable")
        return (interact and interact:GetAttribute("action")) == true
            or char:GetAttribute("IsStunned") == true
            or char:GetAttribute("IsCarrying") == true
    end

    local function survivorList()
        local out = {}
        for _, plr in ipairs(Players:GetPlayers()) do
            local c = plr.Character
            if plr ~= localPlayer and c and plr.Team and plr.Team.Name == "Survivors" then
                out[#out + 1] = c
            end
        end
        for _, bot in ipairs(CollectionService:GetTagged("SurvivorBot")) do
            if bot:IsDescendantOf(workspace) then
                out[#out + 1] = bot
            end
        end
        return out
    end

    local function alive(c)
        local hum = c:FindFirstChildOfClass("Humanoid")
        local root = c:FindFirstChild("HumanoidRootPart")
        if not (hum and root) or hum.Health <= 0 then
            return nil
        end
        if c:GetAttribute("IsHooked") or c:GetAttribute("IsDead") or c:GetAttribute("Dead") then
            return nil
        end
        local okDown, down = pcall(IsDowned, c)
        if okDown and down then
            return nil
        end
        return root
    end

    local function lineClear(from, to, ignoreA, ignoreB)
        local params = RaycastParams.new()
        params.FilterType = Enum.RaycastFilterType.Exclude
        params.FilterDescendantsInstances = {ignoreA, ignoreB}
        params.IgnoreWater = true
        local hit = workspace:Raycast(from, to - from, params)
        return hit == nil or hit.Instance.Transparency >= 0.5 or not hit.Instance.CanCollide
    end

    -- the survivor closest to the crosshair (inside `minDot`), so the silent aim never jumps to somebody behind you
    local function pickTarget(origin, maxDist, minDot, rootCharacter)
        local cam = workspace.CurrentCamera
        if not cam then
            return nil
        end
        local look = cam.CFrame.LookVector
        local best, bestRoot, bestScore = nil, nil, minDot
        for _, c in ipairs(survivorList()) do
            local root = alive(c)
            if root then
                local delta = root.Position - origin
                local dist = delta.Magnitude
                if dist <= maxDist and dist > 0.5 then
                    local dot = look:Dot(delta.Unit)
                    if dot >= bestScore and lineClear(origin, root.Position, rootCharacter, c) then
                        best, bestRoot, bestScore = c, root, dot
                    end
                end
            end
        end
        return best, bestRoot
    end

    local function velocityOf(root)
        local v = root.AssemblyLinearVelocity
        return Vector3.new(v.X, 0, v.Z)
    end

    -- ======================= Butcher =======================
    local KA = {flaskOn = false, hiddenOn = false}
    _G.Ox.KAim = KA

    -- ======================= Cure flask =======================
    local FLASK_SPEED, FLASK_GRAVITY, FLASK_UP, FLASK_TRAVEL = 95, 196.2, 0.35, 70
    pcall(function()
        local m = require(ReplicatedStorage.Modules.Killers.Cure.FlaskTrajectory)
        FLASK_SPEED = m.ThrowSpeed or FLASK_SPEED
        FLASK_GRAVITY = -(m.Gravity and m.Gravity.Y or -196.2)
        FLASK_UP = m.UpBias or FLASK_UP
        FLASK_TRAVEL = m.TravelSpeed or FLASK_TRAVEL
    end)

    -- ThrowFlask:FireServer(lookVector, position, id, serverTime): the game launches along (look + up*UpBias).Unit * speed
    -- with gravity, so the look vector is solved backwards from the launch angle that lands on the target.
    function KA.flask(look, pos, id, stamp)
        local char = localPlayer.Character
        if not (char and typeof(look) == "Vector3" and typeof(pos) == "Vector3") then
            return nil
        end
        local reach = FLASK_SPEED * FLASK_SPEED / FLASK_GRAVITY
        local target, root = pickTarget(pos, reach - 2, 0.5, char)
        if not target then
            return nil
        end
        local aimPos = root.Position + Vector3.new(0, 0.5, 0)
        local flightTime = (aimPos - pos).Magnitude * 1.1 / FLASK_TRAVEL
        aimPos = aimPos + velocityOf(root) * flightTime
        local delta = aimPos - pos
        local flat = Vector3.new(delta.X, 0, delta.Z)
        local d, h = flat.Magnitude, delta.Y
        if d < 1 then
            return nil
        end
        local v2, g = FLASK_SPEED * FLASK_SPEED, FLASK_GRAVITY
        local disc = v2 * v2 - g * (g * d * d + 2 * h * v2)
        if disc < 0 then
            return nil
        end
        local tanTheta = (v2 - math.sqrt(disc)) / (g * d)
        local theta = math.atan(tanTheta)
        local launch = flat.Unit * math.cos(theta) + Vector3.new(0, math.sin(theta), 0)
        local lu = launch.Y * FLASK_UP
        local k = lu + math.sqrt(lu * lu + 1 - FLASK_UP * FLASK_UP)
        local newLook = launch * k - Vector3.new(0, FLASK_UP, 0)
        if newLook.Magnitude < 0.01 then
            return nil
        end
        return newLook.Unit, pos, id, stamp
    end

    task.spawn(function()
        KA.flaskRemote = killerRemote("Cure", "ThrowFlask")
        if not KA.flaskRemote then
            local remotes = ReplicatedStorage:WaitForChild("Remotes", 20)
            local killers = remotes and remotes:WaitForChild("Killers", 10)
            local cure = killers and killers:WaitForChild("Cure", 10)
            KA.flaskRemote = cure and cure:WaitForChild("ThrowFlask", 10)
        end
    end)

    KillerAbilityCard:AddToggle("Silent Aim Flask (Cure)", false, function(on)
        KA.flaskOn = on
    end, {Flag = "SilentAimFlask"})

    -- ======================= Hidden: Aim Lock (hold) =======================
    -- Skills only (Leap / M2 stab), never the basic melee attack (melee assist = Killer Aimbot, works for every killer).
    -- Hold the Hidden's skill key: camera and body lock on the closest survivor and keep following him wherever he goes,
    -- until the skill key is released (plus a short tail so the stab/leap that is already running still lands).
    local HL = {held = {}, releaseAt = 0, target = nil}
    local keybinds
    pcall(function()
        keybinds = require(ReplicatedStorage.Modules.Survivors.KeybindsConfig)
    end)
    local function isSkillInput(input)
        if not keybinds then
            return false
        end
        local ok, a1 = pcall(keybinds.matches, "ability1", input)
        local ok2, a2 = pcall(keybinds.matches, "ability2", input)
        return (ok and a1) or (ok2 and a2)
    end
    UserInputService.InputBegan:Connect(function(input)
        if isSkillInput(input) then
            HL.held[input] = true
        end
    end)
    UserInputService.InputEnded:Connect(function(input)
        if HL.held[input] then
            HL.held[input] = nil
            HL.releaseAt = os.clock()
        end
    end)

    KillerAbilityCard:AddToggle("Aim Lock (The Hidden) - hold skill key", false, function(on)
        KA.hiddenOn = on
        HL.target = nil
    end, {Flag = "AimLockHidden"})

    RS.Heartbeat:Connect(function(dt)
        if not KA.hiddenOn then
            return
        end
        local char = localPlayer.Character
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        if not (hrp and isKillerType("hidden")) then
            HL.target = nil
            return
        end
        local leaping = char:GetAttribute("ForensicsLaunch") == true or char:GetAttribute("LeapRecovering") == true
        local active = next(HL.held) ~= nil or leaping or os.clock() - HL.releaseAt < 0.9
        if not active then
            HL.target = nil
            return
        end
        -- keep the same survivor while he is alive and within reach; otherwise take the closest one
        local root = HL.target
        if not (root and root.Parent and alive(root.Parent) and (root.Position - hrp.Position).Magnitude < 90) then
            root = nil
            local bestDist = 70
            for _, c in ipairs(survivorList()) do
                local r = alive(c)
                if r then
                    local d = (r.Position - hrp.Position).Magnitude
                    if d < bestDist then
                        root, bestDist = r, d
                    end
                end
            end
            HL.target = root
        end
        if not root then
            return
        end
        local lead = (root.Position - hrp.Position).Magnitude / 65
        local aimPos = root.Position + velocityOf(root) * math.min(lead, 0.5)
        local alpha = 1 - math.exp(-dt * 22)
        local cam = workspace.CurrentCamera
        if cam then
            cam.CFrame = cam.CFrame:Lerp(CFrame.lookAt(cam.CFrame.Position, aimPos), alpha)
        end
        local goal = CFrame.lookAt(hrp.Position, Vector3.new(aimPos.X, hrp.Position.Y, aimPos.Z))
        local turned = hrp.CFrame:Lerp(goal, alpha)
        hrp.CFrame = CFrame.new(hrp.Position) * (turned - turned.Position)
    end)

    -- Auto Stalk (Stalker). Same calls as the Stalker's own M2 handler:
    -- StalkHold(true) every 0.5s while stalking, StartStalking(target) once a survivor is in view,
    -- StopStalking() when the target is lost. Target rules copied from the game: <= 100 studs, health > 50%,
    -- not hooked/dead, clear line of sight, and the camera must face the target (dot > 0.8).
    local S = {on = false, holding = false, started = nil, lastHold = 0}

    local function stalkerRemotes()
        local remotes = ReplicatedStorage:FindFirstChild("Remotes")
        local killers = remotes and remotes:FindFirstChild("Killers")
        local folder = killers and killers:FindFirstChild("Stalker")
        if not folder then
            return nil
        end
        return folder:FindFirstChild("StartStalking"), folder:FindFirstChild("StopStalking"), folder:FindFirstChild("StalkHold")
    end

    local function clearLine(fromChar, toChar)
        local a = fromChar:FindFirstChild("HumanoidRootPart")
        local b = toChar:FindFirstChild("HumanoidRootPart")
        if not (a and b) then
            return false
        end
        local params = RaycastParams.new()
        params.FilterType = Enum.RaycastFilterType.Exclude
        params.FilterDescendantsInstances = {fromChar, toChar}
        local origin, delta = a.Position, b.Position - a.Position
        for _ = 1, 10 do
            local hit = workspace:Raycast(origin, delta, params)
            if not hit then
                return true
            end
            if hit.Instance.Transparency < 0.99 or hit.Instance:HasTag("TrueInvis") then
                return false
            end
            local list = params.FilterDescendantsInstances
            list[#list + 1] = hit.Instance
            params.FilterDescendantsInstances = list
        end
        return false
    end

    local function bestTarget(char, hrp)
        local best, bestChar, bestDist = nil, nil, 100
        local function consider(handle, model)
            local root = model:FindFirstChild("HumanoidRootPart")
            local hum = model:FindFirstChildOfClass("Humanoid")
            if root and hum and hum.Health > 0 and hum.Health / hum.MaxHealth > 0.5
                and not model:GetAttribute("IsHooked") and not model:GetAttribute("IsDead") then
                local d = (root.Position - hrp.Position).Magnitude
                if d <= bestDist and clearLine(char, model) then
                    best, bestChar, bestDist = handle, model, d
                end
            end
        end
        for _, plr in ipairs(Players:GetPlayers()) do
            if plr ~= localPlayer and plr.Character and plr.Team and plr.Team.Name == "Survivors" then
                consider(plr, plr.Character)
            end
        end
        for _, bot in ipairs(CollectionService:GetTagged("SurvivorBot")) do
            if bot:IsDescendantOf(workspace) then
                consider(bot, bot)
            end
        end
        return best, bestChar
    end

    local function stopStalk(stop, hold)
        if S.started and stop then
            pcall(function()
                stop:FireServer()
            end)
        end
        if S.holding and hold then
            pcall(function()
                hold:FireServer(false)
            end)
        end
        S.started, S.holding = nil, false
    end

    task.spawn(function()
        while _G.Ox.ScriptAlive do
            task.wait(0.15)
            local start, stop = stalkerRemotes()
            local char = localPlayer.Character
            local hrp = char and char:FindFirstChild("HumanoidRootPart")
            local blocked = char and (char:GetAttribute("IsCarrying") or char:GetAttribute("IsStunned") or char:GetAttribute("Stage") == 2)
            local interact = char and char:FindFirstChild("CheckInterractable")
            if interact and interact:GetAttribute("action") then
                blocked = true
            end
            -- only the Stalker killer has a Stage attribute
            local isStalker = char ~= nil and char:GetAttribute("Stage") ~= nil and localPlayer.Team ~= nil and localPlayer.Team.Name == "Killer"
            if S.on and start and stop and hrp and isStalker and not blocked then
                pcall(function()
                    local handle = bestTarget(char, hrp)
                    if not handle then
                        if S.started then
                            stop:FireServer()
                            S.started = nil
                        end
                        return
                    end
                    -- no hold needed: stalking starts straight away on whoever is inside the range (re-sent every 1.5s)
                    if S.started ~= handle or os.clock() - S.lastHold >= 1.5 then
                        if S.started and S.started ~= handle then
                            stop:FireServer()
                        end
                        start:FireServer(handle)
                        S.started, S.lastHold = handle, os.clock()
                    end
                end)
            elseif S.started then
                pcall(function()
                    if stop then
                        stop:FireServer()
                    end
                end)
                S.started = nil
            end
        end
    end)

    KillerAbilityCard:AddToggle("Auto Stalk (Stalker)", false, function(on)
        S.on = on
        if not on then
            local _, stop = stalkerRemotes()
            stopStalk(stop, nil)
        end
    end, {Flag = "AutoStalk"})
end

local Visual = v:CreateTab("Visual", false, false)
EspTab = Visual
local esp = EspTab:CreatePage("ESP")
EspPage = esp
local v35 = EspPage:CreateSection("ESP Settings", "eye")
EspMasterCard = v35

local v36 = EspMasterCard:AddToggle("Enable ESP", false, function(master)
    _G.Ox.ESPConfig.Master = master

    if master then
        ForceRefreshMap()
    else
        ClearAllESP()
    end
end, {Flag = "EnableEspMaster"})

EspMasterToggle = v36

EspMasterCard:AddSlider("ESP Max Distance", 100, 5000, 1000, function(maxDistance)
    _G.Ox.ESPConfig.MaxDistance = maxDistance
end, {Increment = 100, Flag = "EspMaxDistance"})

local v37 = EspMasterCard:AddCheckbox("Player ESP", false, function(player)
    _G.Ox.ESPConfig.Player = player

    if _G.Ox.ESPConfig.Master then
        if player then
            ScanMapESP()
        else
            ClearESP("Player")
        end
    end
end, {Flag = "PlayerEsp"})

PlayerToggle = v37

local v38 = EspMasterCard:AddCheckbox("Killer ESP", false, function(killer)
    _G.Ox.ESPConfig.Killer = killer

    if _G.Ox.ESPConfig.Master then
        if killer then
            ScanMapESP()
        else
            ClearESP("Killer")
        end
    end
end, {Flag = "KillerEsp"})

KillerToggle = v38

local v39 = EspMasterCard:AddCheckbox("ESP Name", false, function(name)
    _G.Ox.ESPConfig.Name = name

    if _G.Ox.ESPConfig.Master then
        ScanMapESP()
    else
        ClearAllESP()
    end
end, {Flag = "EspName"})

NameToggle = v39

local v40 = EspMasterCard:AddCheckbox("ESP Distance", false, function(distance)
    _G.Ox.ESPConfig.Distance = distance

    if _G.Ox.ESPConfig.Master then
        UpdatePlayerESP()
    end
end, {Flag = "EspDistancw"})

DistToggle = v40

local v41 = EspMasterCard:AddCheckbox("ESP Status survivors", false, function(status)
    _G.Ox.ESPConfig.Status = status

    if _G.Ox.ESPConfig.Master then
        UpdatePlayerESP()
    end
end, {Flag = "EspStatus"})

StatusToggle = v41

local v42 = EspMasterCard:AddCheckbox("ESP Item Icon", false, function(itemIcon)
    _G.Ox.ESPConfig.ItemIcon = itemIcon

    if _G.Ox.ESPConfig.Master then
        UpdatePlayerESP()
    end
end, {Flag = "EspItemIcon"})

IconToggle = v42

local v43 = EspMasterCard:AddCheckbox("ESP Killer Warn", false, function(killerWarn)
    _G.Ox.ESPConfig.KillerWarn = killerWarn

    if not killerWarn then
        local character = localPlayer.Character
        local humanoidRootPart = character and localPlayer.Character:FindFirstChild("HumanoidRootPart")

        if humanoidRootPart and humanoidRootPart:FindFirstChild("KillerWarn") then
            humanoidRootPart.KillerWarn:Destroy()
        end
    end
end, {Flag = "KillerWarn"})

WarnToggle = v43

local v44 = EspMasterCard:AddCheckbox("ESP Outline Mode", false, function(outline)
    _G.Ox.ESPConfig.Outline = outline
end, {Flag = "EspOutlineMode"})

OutlineToggle = v44

local v45 = EspMasterCard:AddCheckbox("ESP Hook Count", false, function(hookCount)
    _G.Ox.ESPConfig.HookCount = hookCount

    if hookCount then
        UpdateHookData()
        UpdatePlayerESP()
        UpdateHookUICounter()
    else
        ClearHookESP()
        ClearHookUICounter()
        UpdatePlayerESP()
    end
end, {Flag = "EspHookCount"})

HookCountToggle = v45
local v46 = EspPage:CreateSection("World Effects", "flashlight")
PerfCard = v46

local v47 = PerfCard:AddToggle("Full Bright", false, function(fullBright)
    _G.Ox.FullBright = fullBright
    local Lighting = game:GetService("Lighting")
    if not Lighting then
        return
    end

    if fullBright then
        StartLightingGuard()
        ReapplyPerformanceDelayed()
    else
        Lighting.Brightness = 1
        Lighting.ClockTime = 14
        Lighting.FogEnd = 1000
        Lighting.Ambient = Color3.fromRGB(128, 128, 128)
        Lighting.OutdoorAmbient = Color3.fromRGB(128, 128, 128)
        StopLightingGuard()

    end
end, {Flag = "FullBright"})

FullBrightToggle = v47

PerfCard:AddSlider("Time Of Day", 0, 24, 14, function(timeOfDayValue)
    _G.Ox.TimeOfDayValue = timeOfDayValue

    if _G.Ox.FullBright then
        local Lighting = game:GetService("Lighting")

        if Lighting then
            Lighting.ClockTime = timeOfDayValue
        end
    end
end, {Increment = 1, Flag = "TimeOfDay"})

local v48 = PerfCard:AddToggle("No Fog", false, function(noFog)
    _G.Ox.NoFog = noFog

    if noFog then
        StartLightingGuard()
        ApplyNoFog()

    else
        local Lighting = game:GetService("Lighting")

        if Lighting then
            Lighting.FogStart = 0
            Lighting.FogEnd = 1000
            local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")

            if atmosphere then
                atmosphere.Density = 0.35
            end
        end

        StopLightingGuard()
    end
end, {Flag = "NoFog"})

NoFogToggle = v48

local v49 = PerfCard:AddToggle("No Shadow", false, function(noShadow)
    _G.Ox.NoShadow = noShadow

    if noShadow then
        StartLightingGuard()
        ApplyNoShadow()

    else
        ApplyNoShadow()
        StopLightingGuard()

    end
end, {Flag = "NoShadow"})

NoShadowToggle = v49

local v50 = PerfCard:AddToggle("Remove Texture (Low GFX)", false, function(arg)
    ToggleLowGFX(arg)
end, {Flag = "RemoveTexture"})

LowGFXToggle = v50
local v51 = EspPage:CreateSection("Map ESP", "map")
MapCard = v51

local v52 = MapCard:AddCheckbox("Generator ESP", false, function(generator)
    _G.Ox.ESPConfig.Generator = generator

    if _G.Ox.ESPConfig.Master then
        if generator then
            ScanMapESP()
        else
            ClearESP("Generator")
        end
    end
end, {Flag = "GeneratorEsp"})

GenToggle = v52

local v53 = MapCard:AddCheckbox("Generator Name & Progress", true, function(generatorName)
    _G.Ox.ESPConfig.GeneratorName = generatorName

    if _G.Ox.ESPConfig.Master then
        ScanMapESP()
    end
end, {Flag = "GeneratorName"})

GenNameToggle = v53

local v54 = MapCard:AddCheckbox("Pallet ESP", false, function(pallet)
    _G.Ox.ESPConfig.Pallet = pallet

    if _G.Ox.ESPConfig.Master then
        if pallet then
            ScanMapESP()
        else
            ClearESP("Pallet")
        end
    end
end, {Flag = "EspPallet"})

PalletToggle = v54

local v55 = MapCard:AddCheckbox("Window ESP", false, function(window)
    _G.Ox.ESPConfig.Window = window

    if _G.Ox.ESPConfig.Master then
        if window then
            ScanMapESP()
        else
            ClearESP("Window")
        end
    end
end, {Flag = "EspWindow"})

WindowToggle = v55

local v56 = MapCard:AddCheckbox("Hook ESP", false, function(hook)
    _G.Ox.ESPConfig.Hook = hook

    if _G.Ox.ESPConfig.Master then
        if hook then
            ScanMapESP()
        else
            ClearESP("Hook")
        end
    end
end, {Flag = "HookEsp"})

HookToggle = v56

local v57 = MapCard:AddCheckbox("Gate ESP", false, function(gate)
    _G.Ox.ESPConfig.Gate = gate

    if _G.Ox.ESPConfig.Master then
        if gate then
            ScanMapESP()
        else
            ClearESP("Gate")
        end
    end
end, {Flag = "GateEsp"})

GateToggle = v57

local v58 = MapCard:AddCheckbox("SCP ESP", false, function(scp)
    _G.Ox.ESPConfig.SCP = scp

    if _G.Ox.ESPConfig.Master then
        if scp then
            ScanMapESP()
        else
            ClearESP("SCP")
        end
    end
end, {Flag = "EspScp"})

SCPToggle = v58

MapCard:AddCheckbox("Pumpkin ESP", false, function(on)
    _G.Ox.WantPumpkinESP = on
    if _G.Ox.SetPumpkinESP then
        _G.Ox.SetPumpkinESP(on)
    end
end, {Flag = "PumpkinESP"})

MapCard:AddCheckbox("Trap ESP", false, function(on)
    _G.Ox.WantTrapESP = on
    if _G.Ox.SetTrapESP then
        _G.Ox.SetTrapESP(on)
    end
end, {Flag = "TrapEsp"})

MapCard:AddButton("Refresh Map", function()
    ForceRefreshMap()
end)

local Information = EspPage:CreateSection("Information", "info")
NextKillerCard = Information

local v59 = NextKillerCard:AddToggle("Next Killer Display", false, function(arg)
    fn19(arg)
end, {Flag = "NextKillerDisplay"})

NextKillerToggle = v59

local v60 = NextKillerCard:AddToggle("Next Map Prediction", false, function(arg)
    fn20(arg)
end, {Flag = "NextMapPredict"})

MapPredictToggle = v60

local v61 = NextKillerCard:AddToggle("Killer Perks Display", false, function(arg)
    fn21(arg)
end, {Flag = "KillerPerkDisplay"})

KillerPerksToggle = v61

local v62 = NextKillerCard:AddToggle("Killer Stun Indicator", false, function(arg)
    fn22(arg)
end, {Flag = "KillerStunIndicator"})

StunToggle = v62

local v63 = NextKillerCard:AddToggle("Spectator info", false, function(arg)
    fn4(arg)
end, {Flag = "SpectatorInfo"})

SpectatorToggle = v63

local Settings = v:CreateTab("Settings", false, false)
SettingsTab = Settings
local Settings2 = SettingsTab:CreatePage("Settings")
S_Page1 = Settings2
local v68 = S_Page1:CreateSection("UI Config", "sliders-vertical")
AppearanceCard = v68

AppearanceCard:AddKeybind("Menu Keybind", "RightShift", function(arg)
    v:SetMenuKey(arg)
end, {Flag = "MenuKeybing"})

AppearanceCard:AddToggle("Transparency Toggle", false, function(arg)
    local setTransparency = v.SetTransparency
    local n = arg and 0.2 or 0
    setTransparency(v, n)
end, {Flag = "ToggleTransparancy"})

AppearanceCard:AddToggle("Lock GUI", false, function(arg)
    v:SetLocked(arg)
end, {Flag = "LockGui"})

AppearanceCard:AddToggle("Watermark", true, function(arg)
    lib:SetWatermark({Enabled = arg})
end, {Flag = "Watermark"})

local Config = S_Page1:CreateSection("Config", "sliders-vertical")
SavesCard = Config
SavesCard:AddConfigManager("MeowXHub/Configs")

task.spawn(function()
    task.wait(2)
    fn2()
end)

localPlayer.CharacterAdded:Connect(function()
    _G.Ox.State.busy = false
    _G.Ox.State.RandomMode_IsNormal = false

    if _G.Ox.Auto.SkillCheck then
        task.wait(1)
        fn7()
    end
end)

localPlayer.CharacterAdded:Connect(function()
    task.wait(1.5)

    if _G.Ox.NoSlowdownEnabled then
        local character = localPlayer.Character

        if character then
            local humanoid = character:FindFirstChildOfClass("Humanoid")

            if humanoid then
                humanoid.WalkSpeed = 16
            end
        end
    end
end)

local v69 = nil

UserInputService.InputBegan:Connect(function(input, gameProcessed)
    local flag2 = input.UserInputType == Enum.UserInputType.Touch
    local v70 = GetRole()

    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        if gameProcessed then
            return
        end

        if v70 == "Killer" and _G.Ox.Config.Killer_Aimbot_Enabled then
            _G.Ox.lockedKillerAimbotTarget = getBestKillerAimbotTarget()

            if _G.Ox.lockedKillerAimbotTarget then
                _G.Ox.isKillerAimbotHolding = true
            end
        end
    end

    if flag2 and v70 == "Killer" and _G.Ox.Config.Killer_Aimbot_Enabled then
        local playerGui2 = localPlayer:FindFirstChild("PlayerGui")
        local v71 = nil

        if playerGui2 then
            for k, child in pairs(playerGui2:GetChildren()) do
                if string.sub(child.Name, -4) == "-mob" and child.Name ~= "Survivor-mob" then
                    v71 = child
                    break
                end
            end
        end

        local attack = v71 and v71:FindFirstChild("Controls") and v71.Controls:FindFirstChild("attack")

        if attack and attack.Visible then
            local position = input.Position
            local absolutePosition = attack.AbsolutePosition
            local absoluteSize = attack.AbsoluteSize

            if absolutePosition.X <= position.X and position.X <= absolutePosition.X + absoluteSize.X and absolutePosition.Y <= position.Y and position.Y <= absolutePosition.Y + absoluteSize.Y then
                _G.Ox.lockedKillerAimbotTarget = getBestKillerAimbotTarget()

                if _G.Ox.lockedKillerAimbotTarget then
                    _G.Ox.isKillerAimbotHolding = true
                    v69 = input
                end
            end
        end
    end
end)

UserInputService.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        _G.Ox.isKillerAimbotHolding = false
        _G.Ox.lockedKillerAimbotTarget = nil

        if _G.Ox.killerAimbotHighlight then
            _G.Ox.killerAimbotHighlight.Parent = nil
        end
    end

    if input.UserInputType == Enum.UserInputType.Touch and input == v69 then
        _G.Ox.isKillerAimbotHolding = false
        _G.Ox.lockedKillerAimbotTarget = nil
        v69 = nil

        if _G.Ox.killerAimbotHighlight then
            _G.Ox.killerAimbotHighlight.Parent = nil
        end
    end
end)

localPlayer.CharacterAdded:Connect(function()
    task.wait(1.5)
    ReapplyPerformanceDelayed()
end)

workspace.ChildAdded:Connect(function(child)
    if child.Name == "Map" then
        task.wait(1)
        ReapplyPerformanceDelayed()
    end
end)

task.spawn(function()
    task.wait(2)
    ReapplyPerformanceDelayed()
end)

pcall(lib.Autoload)
