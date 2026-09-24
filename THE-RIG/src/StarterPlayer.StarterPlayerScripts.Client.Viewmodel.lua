-- StarterPlayerScripts/Client/Viewmodel
-- First-person arms.
--   * If your avatar's arm meshes loaded, the arms ARE your avatar's arms (cloned with shirt
--     and body colours into a camera model, so animations never move them out of view).
--   * If they could not load (e.g. Studio is not signed in), plain stand-in arms are used.
-- LEFT hand: the flashlight whenever you carry one (F switches it on).
-- RIGHT hand: the equipped crowbar / flare. Arms only show in first person; in third person
-- you see your real character holding the items.
local RunService = game:GetService("RunService")
local Input = game:GetService("UserInputService")
local ContentProvider = game:GetService("ContentProvider")

local View = { swing = 0, phase = 0, sway = Vector2.zero, amount = { Left = 0, Right = 0 }, dirty = true, avatarReady = {} }
local C

local ARM_NAMES = {
	R15 = { Left = { "LeftUpperArm", "LeftLowerArm", "LeftHand" }, Right = { "RightUpperArm", "RightLowerArm", "RightHand" } },
	R6 = { Left = { "Left Arm" }, Right = { "Right Arm" } },
}
local STRIP = { "JointInstance", "Constraint", "WrapLayer", "WrapTarget", "Script", "LocalScript", "Attachment", "Weld", "WeldConstraint", "Light" }

local function visual(p)
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Massless = true
end

local function newPart(parent, name, size, color, material, shape)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = color
	p.Material = material or Enum.Material.Metal
	if shape then
		p.Shape = shape
	end
	visual(p)
	p.Parent = parent
	return p
end

-- Item meshes attached to the hand. Offsets are in hand space (-Y = forward).
local function buildItems(model)
	local items = { Left = {}, Right = {} }
	local cyl = CFrame.Angles(0, 0, math.rad(90)) -- cylinder axis (X) -> hand Y
	local function add(side, id, p, offset)
		table.insert(items[side], { part = p, id = id, offset = offset })
	end
	local body = newPart(model, "TorchBody", Vector3.new(1.15, 0.32, 0.32), Color3.fromRGB(44, 50, 56), Enum.Material.Metal, Enum.PartType.Cylinder)
	add("Left", "Flashlight", body, CFrame.new(0, -0.35, -0.12) * cyl)
	local head = newPart(model, "TorchHead", Vector3.new(0.32, 0.46, 0.46), Color3.fromRGB(78, 86, 92), Enum.Material.Metal, Enum.PartType.Cylinder)
	add("Left", "Flashlight", head, CFrame.new(0, -0.98, -0.12) * cyl)
	local lens = newPart(model, "Lens", Vector3.new(0.04, 0.4, 0.4), Color3.fromRGB(255, 244, 210), Enum.Material.Neon, Enum.PartType.Cylinder)
	add("Left", "Flashlight", lens, CFrame.new(0, -1.16, -0.12) * cyl)
	local glow = Instance.new("PointLight")
	glow.Color = Color3.fromRGB(255, 238, 205)
	glow.Brightness = 1.4
	glow.Range = 6
	glow.Shadows = false
	glow.Parent = lens
	View.glow = glow
	local bar = newPart(model, "CrowbarShaft", Vector3.new(0.14, 2.6, 0.14), Color3.fromRGB(160, 40, 34))
	add("Right", "Crowbar", bar, CFrame.new(0, -0.9, -0.12))
	local hook = newPart(model, "CrowbarHook", Vector3.new(0.14, 0.14, 0.5), Color3.fromRGB(110, 116, 120))
	add("Right", "Crowbar", hook, CFrame.new(0, -2.15, -0.3))
	local flare = newPart(model, "FlareStick", Vector3.new(0.26, 0.95, 0.26), Color3.fromRGB(215, 60, 42), Enum.Material.SmoothPlastic)
	add("Right", "Flare", flare, CFrame.new(0, -0.45, -0.12))
	return items
end

local function rigOf(character)
	return character:FindFirstChild("UpperTorso") and "R15" or "R6"
end

-- Checks once per character whether the avatar's arm meshes actually downloaded.
function View.checkAvatar(character)
	if View.avatarReady[character] ~= nil then
		return
	end
	View.avatarReady[character] = false
	task.spawn(function()
		task.wait(1.5) -- let the appearance finish attaching
		local list = {}
		for _, names in pairs(ARM_NAMES[rigOf(character)]) do
			for _, n in ipairs(names) do
				local p = character:FindFirstChild(n)
				if not p then
					return
				end
				if p:IsA("MeshPart") and p.MeshId ~= "" then
					table.insert(list, p)
				end
			end
		end
		local ok = true
		if #list > 0 then
			local loaded = pcall(function()
				ContentProvider:PreloadAsync(list, function(_, status)
					if status ~= Enum.AssetFetchStatus.Success then
						ok = false
					end
				end)
			end)
			if not loaded then ok = false end
		end
		if character.Parent then
			View.avatarReady[character] = ok
			View.dirty = true
			local offline = C and C.player:GetAttribute("AvatarStatus") == "Offline"
			if (not ok or offline) and not View.avatarWarned and C and C.HUD then
				View.avatarWarned = true
				C.HUD.toast("Your avatar (skin) could not be downloaded: Roblox Studio is not signed in. Sign in (top-right corner of Studio) and press Play again.", "warn")
			end
		end
	end)
end

local function strip(inst)
	for _, d in ipairs(inst:GetDescendants()) do
		for _, class in ipairs(STRIP) do
			if d:IsA(class) then
				d:Destroy()
				break
			end
		end
	end
end

local function standIn(model, character, side)
	local bc = character:FindFirstChildOfClass("BodyColors")
	local torso = character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso")
	local sleeveColor = (bc and bc.TorsoColor3) or (torso and torso.Color) or Color3.fromRGB(70, 82, 92)
	local armSrc = character:FindFirstChild(side .. "Hand") or character:FindFirstChild(side .. " Arm")
	local skin = (bc and (side == "Left" and bc.LeftArmColor3 or bc.RightArmColor3)) or (armSrc and armSrc.Color) or Color3.fromRGB(204, 142, 105)
	local sleeve = newPart(model, side .. "Sleeve", Vector3.new(0.78, 1.7, 0.78), sleeveColor, Enum.Material.Fabric)
	local cuff = newPart(model, side .. "Cuff", Vector3.new(0.84, 0.2, 0.84), sleeveColor:Lerp(Color3.new(0, 0, 0), 0.35), Enum.Material.Fabric)
	local hand = newPart(model, side .. "Hand", Vector3.new(0.62, 0.62, 0.7), skin, Enum.Material.SmoothPlastic)
	return {
		parts = { sleeve, cuff, hand },
		handLen = 0.7,
		place = function(handPos, dir, rot)
			hand.CFrame = CFrame.new(handPos) * rot
			cuff.CFrame = CFrame.new(handPos - dir * 0.42) * rot
			sleeve.CFrame = CFrame.new(handPos - dir * 1.28) * rot
		end,
	}
end

local function avatarArm(model, character, side)
	local rig = rigOf(character)
	local chain = {}
	for _, n in ipairs(ARM_NAMES[rig][side]) do
		local src = character:FindFirstChild(n)
		if not src or not src:IsA("BasePart") then
			return nil
		end
		local copy = src:Clone()
		strip(copy)
		visual(copy)
		copy.Transparency = 0
		copy.LocalTransparencyModifier = 0
		copy.Parent = model
		table.insert(chain, { part = copy, length = src.Size.Y, hide = rig == "R15" and n:find("UpperArm") ~= nil })
	end
	local parts = {}
	for _, l in ipairs(chain) do
		if not l.hide then
			table.insert(parts, l.part)
		else
			l.part.Transparency = 1
		end
	end
	return {
		parts = parts,
		handLen = rig == "R15" and chain[#chain].length or 0.7,
		place = function(handPos, dir, rot)
			if rig == "R6" then
				chain[1].part.CFrame = CFrame.new(handPos - dir * (chain[1].length / 2 - 0.35)) * rot
				return
			end
			local centre = handPos
			for i = #chain, 1, -1 do
				if i < #chain then
					centre -= dir * (chain[i + 1].length / 2 + chain[i].length / 2)
				end
				chain[i].part.CFrame = CFrame.new(centre) * rot
			end
		end,
	}
end

function View.rebuild(character)
	if View.model then
		View.model:Destroy()
	end
	View.checkAvatar(character)
	local model = Instance.new("Model")
	model.Name = "FirstPersonArms"
	local useAvatar = View.avatarReady[character] == true
	if useAvatar then
		-- A Humanoid + the avatar's Shirt / BodyColors dress the cloned arms exactly like yours.
		local hum = Instance.new("Humanoid")
		hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		hum.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
		hum.RequiresNeck = false
		pcall(function()
			hum.EvaluateStateMachine = false
		end)
		hum.RigType = rigOf(character) == "R15" and Enum.HumanoidRigType.R15 or Enum.HumanoidRigType.R6
		hum.Parent = model
		for _, class in ipairs({ "Shirt", "BodyColors" }) do
			local src = character:FindFirstChildOfClass(class)
			if src then
				src:Clone().Parent = model
			end
		end
	end
	local arms = {}
	for _, side in ipairs({ "Left", "Right" }) do
		arms[side] = (useAvatar and avatarArm(model, character, side)) or standIn(model, character, side)
	end
	View.items = buildItems(model)
	model.Parent = workspace.CurrentCamera
	View.model, View.arms, View.character, View.usingAvatar = model, arms, character, useAvatar
	View.dirty = false
end

function View.init(ctx)
	C = ctx
	local fill = newPart(workspace.CurrentCamera, "ArmFill", Vector3.new(0.1, 0.1, 0.1), Color3.new(1, 1, 1), Enum.Material.SmoothPlastic)
	fill.Transparency = 1
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(235, 228, 214)
	light.Brightness = 1
	light.Range = 5
	light.Shadows = false
	light.Enabled = false
	light.Parent = fill
	View.fill, View.fillLight = fill, light
	local function watch(character)
		View.dirty = true
		character.ChildAdded:Connect(function(child)
			if child:IsA("BasePart") or child:IsA("Clothing") or child:IsA("BodyColors") then
				View.dirty = true
			end
		end)
	end
	if C.player.Character then
		watch(C.player.Character)
	end
	C.player.CharacterAdded:Connect(watch)
	C.player.CharacterAppearanceLoaded:Connect(function(character)
		View.avatarReady[character] = nil
		View.dirty = true
	end)
	task.delay(8, function()
		C.HUD.toast("Left hand holds your flashlight (F turns it on). Right hand appears with the crowbar or a flare (1-6). V switches first / third person.", "info")
	end)
	RunService:BindToRenderStep("RigHands", Enum.RenderPriority.Camera.Value + 5, function(dt)
		local ok, err = pcall(View.render, dt)
		if not ok and not View.warned then
			View.warned = true
			warn("[Viewmodel] " .. tostring(err))
		end
	end)
end

function View.kick()
	View.swing = 0.35
end

function View.toggled() end

local function hasFlashlight(player)
	if player:GetAttribute("HasFlashlight") == true then
		return true
	end
	for _, slot in ipairs(C.inventory and C.inventory.slots or {}) do
		if slot.id == "Flashlight" then
			return true
		end
	end
	return false
end

local function torchOn(_character)
	-- The server keeps TorchOn in sync; the local beam itself lives in the Flashlight module.
	return C.player:GetAttribute("TorchOn") == true
end

local function setShown(side, shown, equipped)
	local arm = View.arms[side]
	if arm then
		for _, p in ipairs(arm.parts) do
			p.Transparency = shown and 0 or 1
		end
	end
	for _, it in ipairs(View.items[side]) do
		local want = shown and (side == "Left" or it.id == equipped)
		it.part.Transparency = want and 0 or 1
	end
end

function View.render(dt)
	local camera = workspace.CurrentCamera
	local player = C.player
	local character = player.Character
	local hum = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not camera or not hum or not root then
		if View.model then View.model.Parent = nil end
		if View.glow then View.glow.Enabled = false end
		View.fillLight.Enabled = false
		return
	end
	if View.dirty or View.character ~= character or not View.model or not View.model.Parent then
		View.rebuild(character)
	end
	if View.model.Parent ~= camera then
		View.model.Parent = camera
	end

	local head = character:FindFirstChild("Head")
	local firstPerson = head ~= nil and (camera.CFrame.Position - head.Position).Magnitude < 2
	View.firstPerson = firstPerson
	if not firstPerson then
		View.amount.Left, View.amount.Right = 0, 0 -- no arm fade when zoomed out
	end
	local show = firstPerson and hum.Health > 0 and not C.panelOpen and not (C.Build and C.Build.active) and not hum.Sit
	local equipped = player:GetAttribute("Equipped") or ""
	local lit = torchOn(character)
	local want = {
		Left = show and hasFlashlight(player),
		Right = show and (equipped == "Crowbar" or equipped == "Flare"),
	}

	local delta = Input:GetMouseDelta()
	View.sway = View.sway:Lerp(Vector2.new(math.clamp(delta.X, -20, 20), math.clamp(delta.Y, -20, 20)), math.min(dt * 10, 1))
	local speed = Vector3.new(root.AssemblyLinearVelocity.X, 0, root.AssemblyLinearVelocity.Z).Magnitude
	View.phase += dt * (1.6 + speed * 0.42)
	View.swing = math.max(0, View.swing - dt)
	local bob = math.min(speed / 14, 1.4) * 0.035
	local breathe = math.sin(os.clock() * 1.6) * 0.012
	local running = speed > 18
	local cf = camera.CFrame
	local anyShown = false

	for side, sign in pairs({ Left = -1, Right = 1 }) do
		local a = View.amount[side]
		a += ((want[side] and 1 or 0) - a) * math.min(dt * 11, 1)
		View.amount[side] = a
		local shown = a > 0.04
		anyShown = anyShown or shown
		setShown(side, shown, equipped)
		if shown then
			local x = sign * 0.62 + math.sin(View.phase) * bob * sign - View.sway.X * 0.0022
			local y = -0.66 - (1 - a) * 1.8 + math.abs(math.cos(View.phase)) * bob + breathe - (running and 0.12 or 0) + View.sway.Y * 0.0016
			local z = -1.35
			local pitch, yaw = 0.3, -sign * 0.14
			if side == "Right" and View.swing > 0 then
				local t = 1 - View.swing / 0.35
				local arc = math.sin(t * math.pi)
				y += arc * 0.35
				x -= arc * 0.35
				z -= arc * 0.25
				pitch += arc * 0.9 - t * 0.6
			end
			-- Forearm direction (elbow -> hand) in camera space: forward, slightly up and inward.
			local dirLocal = Vector3.new(yaw, pitch, -1).Unit
			local dir = cf:VectorToWorldSpace(dirLocal)
			local handPos = cf:PointToWorldSpace(Vector3.new(x, y, z))
			local right = cf.RightVector - dir * dir:Dot(cf.RightVector)
			right = right.Magnitude > 0.05 and right.Unit or cf.RightVector
			local rot = CFrame.fromMatrix(Vector3.zero, right, -dir) -- part -Y points along dir
			local arm = View.arms[side]
			local handCF = CFrame.new(handPos) * rot
			if arm then
				arm.place(handPos, dir, rot)
			end
			local handLen = arm and arm.handLen or 0.7
			for _, it in ipairs(View.items[side]) do
				it.part.CFrame = handCF * CFrame.new(0, -handLen / 2, 0) * it.offset
			end
		end
	end

	View.glow.Enabled = want.Left and lit and View.amount.Left > 0.5
	View.fillLight.Enabled = anyShown
	View.fill.CFrame = cf * CFrame.new(0, -0.5, -1.2)
	-- Our own world props stay hidden (other players see them in our character's hands).
	for _, name in ipairs({ "HeldItem", "HeldLight" }) do
		local held = character:FindFirstChild(name)
		if held then
			local hide = firstPerson and 1 or 0
			held.LocalTransparencyModifier = hide
			for _, d in ipairs(held:GetDescendants()) do
				if d:IsA("BasePart") then
					d.LocalTransparencyModifier = hide
				end
			end
		end
	end
end

return View
