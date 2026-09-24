-- ServerScriptService/Systems/Equipment
-- Hand-held items: flashlight (never runs out, beam visible to everyone), crowbar (melee),
-- flares (thrown light sources that repel Climbers). All effects are resolved here.
-- 0.15: whether the flashlight is on is kept here (state.torchOn), not on the SpotLight.
-- Avatar loading can replace the Head and take the light with it; the light is rebuilt
-- whenever it is missing, so the switch can no longer silently stop working.
-- Also the X key: the player screams. Everyone hears it, and so does everything hunting.
local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Modules.Config)
local Items = require(ReplicatedStorage.Modules.Items)

local Equipment = { state = {}, flares = {} }
local G

local MELEE_RANGE = 8
local MELEE_DAMAGE = 20
local MELEE_COOLDOWN = 0.6
local FLARE_TIME = 30
local FLARE_RADIUS = 20
local SCREAM_COOLDOWN = 3.5
local SCREAM_NOISE = 95 -- studs: creatures this close hear it and come to look

local function stateOf(player)
	local s = Equipment.state[player]
	if not s then
		s = { propId = nil, prop = nil, lastSwing = 0, lastFlare = 0, lastScream = 0, torchOn = false }
		Equipment.state[player] = s
	end
	return s
end

function Equipment.init(g)
	G = g
	G.Net.on("UseEquipped", function(player)
		Equipment.useEquipped(player)
	end, 0.15)
	G.Net.on("Flashlight", function(player)
		Equipment.toggleFlashlight(player)
	end, 0.2)
	G.Net.on("Scream", function(player)
		Equipment.scream(player)
	end, 0.5)
	-- Hold right mouse / FOCUS: a narrow, hot beam that burns Climbers.
	G.Net.on("Focus", function(player, on)
		Equipment.setFocus(player, on == true)
	end, 0.1)
	G.Net.on("Aim", function(player, direction)
		if not G.Net.isFiniteVector(direction) or direction.Magnitude < .9 or direction.Magnitude > 1.1 then return end
		local character = G.Net.alive(player)
		local head = character and character:FindFirstChild("Head")
		local mount = head and head:FindFirstChild("TorchMount")
		if not mount then return end
		direction = direction.Unit
		stateOf(player).aim = direction
		player:SetAttribute("TorchAim", direction)
		-- The beam starts in front of the face, never inside the head (the head would shadow it).
		local held = character:FindFirstChild("HeldLight")
		local lens = held and held:FindFirstChild("Lens")
		-- A mount on the actual prop is visible on all clients. Local pose points the arm.
		local origin = lens and lens.Position or head.Position + direction * 1.1
		mount.CFrame = head.CFrame:ToObjectSpace(CFrame.lookAt(origin, origin + direction))
	end, .08)
	Players.PlayerRemoving:Connect(function(p)
		Equipment.state[p] = nil
	end)
	-- Watchdog: re-attach anything the avatar loader knocked off (light, held props).
	task.spawn(function()
		while true do
			task.wait(1)
			for _, p in ipairs(Players:GetPlayers()) do
				local ok, err = pcall(Equipment.heal, p)
				if not ok and not Equipment.healWarned then
					Equipment.healWarned = true
					warn("[Equipment] heal failed: " .. tostring(err))
				end
			end
		end
	end)
end

function Equipment.onCharacter(player, character)
	local s = stateOf(player)
	for _, name in ipairs({"HeldItem", "HeldLight"}) do
		local old = character:FindFirstChild(name); if old then old:Destroy() end
	end
	s.propId = nil
	s.prop = nil
	s.aim = nil
	s.torchProp = nil
	s.focus = false
	s.torchOn = false
	player:SetAttribute("TorchOn", false)
	player:SetAttribute("TorchAim", nil)
	player:SetAttribute("TorchFocus", false)
	local head = character:WaitForChild("Head", 10)
	if head then
		local old = head:FindFirstChild("TorchMount"); if old then old:Destroy() end
	end
	Equipment.refresh(player)
end

local NORMAL_BEAM = { Angle = 50, Range = 60, Brightness = 4.5 }
local FOCUS_BEAM = { Angle = 22, Range = 70, Brightness = 8 }

-- The server beam other players see. Built on demand and rebuilt if the head was replaced;
-- its Enabled always follows state.torchOn.
local function torchOf(player)
	local c = player.Character
	local head = c and c:FindFirstChild("Head")
	if not head then
		return nil
	end
	local s = stateOf(player)
	local mount = head:FindFirstChild("TorchMount")
	if not mount then
		mount = Instance.new("Attachment")
		mount.Name = "TorchMount"
		mount.Parent = head
	end
	local torch = mount:FindFirstChild("Torch")
	if not torch then
		torch = Instance.new("SpotLight")
		torch.Name = "Torch"
		torch.Face = Enum.NormalId.Front
		torch.Color = Color3.fromRGB(255, 244, 222)
		torch.Shadows = true
		for k, v in pairs(s.focus and FOCUS_BEAM or NORMAL_BEAM) do
			torch[k] = v
		end
		torch.Enabled = false
		torch.Parent = mount
	end
	local want = s.torchOn == true
	if torch.Enabled ~= want then
		torch.Enabled = want
	end
	return torch
end

-- A welded prop is still on the character (its hand was not swapped out from under it).
local function attached(prop, character)
	if not prop or prop.Parent ~= character then
		return false
	end
	local weld = prop:FindFirstChildOfClass("WeldConstraint")
	return weld ~= nil and weld.Part0 ~= nil and weld.Part0.Parent == character
end

function Equipment.hasFlashlight(player)
	return G.Inventory.count(player, "Flashlight") > 0
end

function Equipment.setFocus(player, on)
	local s = stateOf(player)
	on = on and s.torchOn == true
	s.focus = on
	local torch = torchOf(player)
	player:SetAttribute("TorchFocus", on)
	if torch then
		for k, v in pairs(on and FOCUS_BEAM or NORMAL_BEAM) do
			torch[k] = v
		end
	end
end

-- Flashlight lives in the right hand for other players to see (the owner sees the viewmodel).
local function refreshTorchHand(player, s)
	local character = player.Character
	local want = character ~= nil and Equipment.hasFlashlight(player)
	player:SetAttribute("HasFlashlight", Equipment.hasFlashlight(player))
	if want and attached(s.torchProp, character) then
		return
	end
	if s.torchProp then
		s.torchProp:Destroy()
		s.torchProp = nil
	end
	if not want then
		return
	end
	local hand = character:FindFirstChild("RightHand") or character:FindFirstChild("Right Arm")
	if not hand then
		return
	end
	local prop = Instance.new("Part")
	prop.Name = "HeldLight"
	prop.Size = Vector3.new(0.35, 0.35, 1.3)
	prop.Color = Color3.fromRGB(40, 44, 48)
	prop.Material = Enum.Material.Metal
	prop.CanCollide = false
	prop.CanQuery = false
	prop.CanTouch = false
	prop.Massless = true
	prop.CFrame = hand.CFrame * CFrame.new(0, -hand.Size.Y / 2 - 0.45, 0) * CFrame.Angles(math.rad(-90), 0, 0)
	local lens = Instance.new("Part")
	lens.Name = "Lens"
	lens.Size = Vector3.new(0.42, 0.42, 0.1)
	lens.Color = Color3.fromRGB(255, 240, 200)
	lens.Material = Enum.Material.Glass
	lens.CanCollide = false
	lens.CanQuery = false
	lens.CanTouch = false
	lens.Massless = true
	lens.CFrame = prop.CFrame * CFrame.new(0, 0, -0.68)
	lens.Parent = prop
	local w = Instance.new("WeldConstraint")
	w.Part0 = prop
	w.Part1 = lens
	w.Parent = lens
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = hand
	weld.Part1 = prop
	weld.Parent = prop
	prop.Parent = character
	s.torchProp = prop
	-- Machined grip, bezel and end cap remain welded to the visible tool.
	for index, z in ipairs({-.54,-.36,-.18,0,.18,.36,.54}) do
		local ring = Instance.new("Part")
		ring.Name = index == 1 and "Bezel" or "GripRing"
		ring.Shape = Enum.PartType.Cylinder
		ring.Size = Vector3.new(index == 1 and .18 or .045, index == 1 and .46 or .38, index == 1 and .46 or .38)
		ring.Color = index == 1 and Color3.fromRGB(132,145,154) or Color3.fromRGB(20,24,28)
		ring.Material = Enum.Material.Metal
		ring.CanCollide,ring.CanTouch,ring.CanQuery,ring.Massless = false,false,false,true
		ring.CFrame = prop.CFrame * CFrame.new(0,0,z) * CFrame.Angles(0,math.pi/2,0)
		ring.Parent = prop
		local rw=Instance.new("WeldConstraint");rw.Part0=prop;rw.Part1=ring;rw.Parent=ring
	end
end

function Equipment.equippedId(player)
	local bag = G.Inventory.bags[player]
	if not bag or bag.equipped == 0 then
		return nil
	end
	local s = bag.slots[bag.equipped]
	if not s then
		return nil
	end
	local def = Items.get(s.id)
	return def and def.equip and s.id or nil
end

function Equipment.select(player, slot)
	local bag = G.Inventory.bags[player]
	if not bag then
		return
	end
	if bag.equipped == slot then
		slot = 0 -- pressing the same key again unequips
	end
	bag.equipped = slot
	bag.dirty = true
	Equipment.refresh(player)
end

local function makeProp(id, hand)
	local prop = Instance.new("Part")
	prop.Name = "HeldItem"
	prop.CanCollide = false
	prop.CanQuery = false
	prop.CanTouch = false
	prop.Massless = true
	prop.Material = Enum.Material.Metal
	local offset
	-- Props point along the hand's -Y axis: forward when the first-person arm is raised,
	-- downward when other players see the arm hanging.
	local forward = CFrame.Angles(math.rad(-90), 0, 0)
	if id == "Flashlight" then
		prop.Size = Vector3.new(0.35, 0.35, 1.3)
		prop.Color = Color3.fromRGB(40, 42, 44)
		offset = CFrame.new(0, -hand.Size.Y / 2 - 0.35, 0) * forward
	elseif id == "Crowbar" then
		prop.Size = Vector3.new(0.25, 0.25, 3.2)
		prop.Color = Color3.fromRGB(170, 40, 34)
		offset = CFrame.new(0, -hand.Size.Y / 2 - 1.2, 0) * forward
	else -- Flare
		prop.Size = Vector3.new(0.3, 0.3, 1)
		prop.Color = Color3.fromRGB(230, 60, 50)
		prop.Material = Enum.Material.SmoothPlastic
		offset = CFrame.new(0, -hand.Size.Y / 2 - 0.3, 0) * forward
	end
	prop.CFrame = hand.CFrame * offset
	if id == "Flashlight" then
		local lens = Instance.new("Part")
		lens.Name = "Lens"
		lens.Size = Vector3.new(0.4, 0.4, 0.1)
		lens.CanCollide = false
		lens.CanQuery = false
		lens.CanTouch = false
		lens.Massless = true
		lens.Material = Enum.Material.Neon
		lens.Color = Color3.fromRGB(255, 240, 200)
		lens.CFrame = prop.CFrame * CFrame.new(0, 0, -0.68)
		lens.Parent = prop
		local w = Instance.new("WeldConstraint")
		w.Part0 = prop
		w.Part1 = lens
		w.Parent = lens
	end
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = hand
	weld.Part1 = prop
	weld.Parent = prop
	return prop
end

-- Re-evaluates the prop in the player's hand after any inventory change.
function Equipment.refresh(player)
	local s = stateOf(player)
	local id = Equipment.equippedId(player)
	local character = player.Character
	player:SetAttribute("Equipped", id or "")
	refreshTorchHand(player, s)
	if s.torchOn and not Equipment.hasFlashlight(player) then
		s.torchOn = false
		Equipment.setFocus(player, false)
	end
	torchOf(player)
	player:SetAttribute("TorchOn", s.torchOn == true)
	local lens = s.torchProp and s.torchProp:FindFirstChild("Lens")
	if lens then
		lens.Material = s.torchOn and Enum.Material.Neon or Enum.Material.Glass
	end
	-- The flashlight is carried in the right hand; tools use the left hand.
	if id == "Flashlight" then
		id = nil
	end
	if id == s.propId and (s.prop == nil or attached(s.prop, character)) then
		return
	end
	if s.prop then
		s.prop:Destroy()
		s.prop = nil
	end
	s.propId = id
	if not id or not character then
		return
	end
	local hand = character:FindFirstChild("LeftHand") or character:FindFirstChild("Left Arm")
	if not hand then
		return
	end
	local prop = makeProp(id, hand)
	prop.Parent = character
	s.prop = prop
end

-- Unlimited: there is no battery. On/off is all there is.
function Equipment.toggleFlashlight(player)
	if not Equipment.hasFlashlight(player) then
		G.Net.toast(player, "You have no flashlight. Craft one at a bench.", "warn")
		player:SetAttribute("TorchOn", false)
		return
	end
	local s = stateOf(player)
	s.torchOn = not s.torchOn
	if not s.torchOn then
		Equipment.setFocus(player, false)
	end
	Equipment.refresh(player)
end

-- Once a second: puts back whatever an avatar reload knocked off the character.
function Equipment.heal(player)
	local character = player.Character
	if not character or not character.Parent then
		return
	end
	local s = stateOf(player)
	torchOf(player)
	local brokenLeft = s.torchProp ~= nil and not attached(s.torchProp, character)
	local missingLeft = s.torchProp == nil and Equipment.hasFlashlight(player)
		and (character:FindFirstChild("RightHand") or character:FindFirstChild("Right Arm")) ~= nil
	local brokenRight = s.prop ~= nil and not attached(s.prop, character)
	if brokenLeft or missingLeft or brokenRight then
		if brokenRight then
			s.propId = nil
		end
		Equipment.refresh(player)
	end
	if player:GetAttribute("TorchOn") ~= (s.torchOn == true) then
		player:SetAttribute("TorchOn", s.torchOn == true)
	end
end

-- X: a scream everyone nearby hears. Creatures hear it too and come to look.
function Equipment.scream(player)
	local s = stateOf(player)
	local now = os.clock()
	if now - s.lastScream < SCREAM_COOLDOWN then
		return
	end
	local character, _, root = G.Net.alive(player)
	if not character then
		return
	end
	s.lastScream = now
	local head = character:FindFirstChild("Head") or root
	G.AI.SFX.play("PlayerScream", head, { speed = 0.96 + math.random() * 0.08 })
	G.AI.noise(root.Position, SCREAM_NOISE)
	player:SetAttribute("ScreamAt", workspace:GetServerTimeNow())
end

function Equipment.useEquipped(player)
	local id = Equipment.equippedId(player)
	if id == "Flashlight" then
		Equipment.toggleFlashlight(player)
	elseif id == "Crowbar" then
		Equipment.swing(player)
	elseif id == "Flare" then
		Equipment.throwFlare(player)
	end
end

function Equipment.swing(player)
	local s = stateOf(player)
	local now = os.clock()
	if now - s.lastSwing < MELEE_COOLDOWN then
		return
	end
	s.lastSwing = now
	local _, _, root = G.Net.alive(player)
	if not root then
		return
	end
	local best, bestDist = nil, MELEE_RANGE
	for _, model in ipairs(CollectionService:GetTagged("Monster")) do
		local hum = model:FindFirstChildOfClass("Humanoid")
		local mroot = model:FindFirstChild("HumanoidRootPart")
		if hum and mroot and hum.Health > 0 then
			local delta = mroot.Position - root.Position
			local d = delta.Magnitude
			if d < bestDist and (d < 3 or (s.aim or root.CFrame.LookVector):Dot(delta.Unit) > 0.2)
				and G.AI.visible(root.Position, mroot.Position, model, player.Character) then
				best, bestDist = model, d
			end
		end
	end
	if best and G.AI.tryDodge(best, player) then
		G.Net.Effect:FireClient(player, "Swing", false)
		return
	end
	G.Net.Effect:FireClient(player, "Swing", best ~= nil)
	if best then
		G.AI.hit(best, MELEE_DAMAGE, player)
	end
end

function Equipment.throwFlare(player)
	local s = stateOf(player)
	local now = os.clock()
	if now - s.lastFlare < 1 then
		return
	end
	local _, _, root = G.Net.alive(player)
	if not root or not G.Inventory.remove(player, "Flare", 1) then
		return
	end
	s.lastFlare = now
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { player.Character, workspace:FindFirstChild("NPCs") }
	local target = root.Position + root.CFrame.LookVector * 9
	local hit = workspace:Raycast(target + Vector3.new(0, 4, 0), Vector3.new(0, -60, 0), params)
	local pos = hit and hit.Position + Vector3.new(0, 0.3, 0) or target
	local flare = Instance.new("Part")
	flare.Name = "Flare"
	flare.Size = Vector3.new(0.4, 0.4, 1.2)
	flare.CFrame = CFrame.new(pos) * CFrame.Angles(0, math.random() * 6.28, math.rad(80))
	flare.Anchored = true
	flare.CanCollide = false
	flare.CanQuery = false
	flare.Material = Enum.Material.Neon
	flare.Color = Color3.fromRGB(255, 70, 50)
	flare.Parent = G.World.Effects
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 90, 70)
	light.Range = 28
	light.Brightness = 4
	light.Shadows = true
	light.Parent = flare
	local fire = Instance.new("ParticleEmitter")
	fire.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	fire.Color = ColorSequence.new(Color3.fromRGB(255, 120, 80))
	fire.LightEmission = 1
	fire.Size = NumberSequence.new(0.5, 0)
	fire.Lifetime = NumberRange.new(0.3, 0.7)
	fire.Speed = NumberRange.new(4, 9)
	fire.SpreadAngle = Vector2.new(40, 40)
	fire.Rate = 40
	fire.Acceleration = Vector3.new(0, -10, 0)
	fire.Parent = flare
	local entry = { position = pos, expires = now + FLARE_TIME, radius = FLARE_RADIUS, part = flare }
	table.insert(Equipment.flares, entry)
	G.AI.noise(pos, 50)
	task.delay(FLARE_TIME, function()
		if flare.Parent then
			flare:Destroy()
		end
	end)
end

function Equipment.activeFlares()
	local now = os.clock()
	for i = #Equipment.flares, 1, -1 do
		if Equipment.flares[i].expires <= now then
			table.remove(Equipment.flares, i)
		end
	end
	return Equipment.flares
end

-- Where the player is looking (camera direction sent by the client), or nil.
function Equipment.aimOf(player)
	return stateOf(player).aim
end

-- Returns a player's flashlight beam if it is on: origin, direction.
function Equipment.beamOf(player)
	local s = stateOf(player)
	if not s.torchOn then
		return nil
	end
	local torch = torchOf(player)
	if torch then
		local mount = torch.Parent
		return mount.WorldPosition, mount.WorldCFrame.LookVector, s.focus == true
	end
	-- No head (a headless avatar): shine from the chest along the aim.
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if root then
		local aim = s.aim or root.CFrame.LookVector
		return root.Position + Vector3.new(0, 1.5, 0) + aim, aim, s.focus == true
	end
	return nil
end

return Equipment
