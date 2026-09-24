-- ServerScriptService/Systems/Scatter
-- Loose loot everywhere, not only at fixed nodes. Small pickups (scrap, cans, bottles,
-- batteries, wire, boards, jerrycans...) keep appearing on any walkable surface around every
-- player: decks, roofs, walkways, wrecks, islands, rooms. Farther from KESTREL-9 the finds get
-- better. Items far from everyone or left too long disappear, so the world never fills up.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Modules.Config)
local Items = require(ReplicatedStorage.Modules.Items)
local SFX = require(ReplicatedStorage.Modules.SFX)

local Scatter = { items = {}, timer = 0 }
local G

local PER_PLAYER = 14 -- within RADIUS of each player
local RADIUS = 200
local MAX_TOTAL = 120
local LIFETIME = 600
local SPACING = 9

local function col(r, g, b)
	return Color3.fromRGB(r, g, b)
end

-- kind = {item, min, max, weight, rareWeight (weight far from the rig), label}
local KINDS = {
	Scrap = { "ScrapMetal", 1, 2, 26, 14, "Scrap" },
	Cans = { "Food", 1, 1, 12, 10, "Canned food" },
	Bottle = { "Water", 1, 1, 12, 10, "Water bottle" },
	Wires = { "Copper", 1, 2, 11, 11, "Copper wire" },
	Circuit = { "Electronics", 1, 1, 7, 12, "Circuit board" },
	Jerrycan = { "Fuel", 1, 1, 6, 11, "Jerrycan" },
	Plastic = { "Plastic", 1, 2, 10, 6, "Plastic" },
	Chem = { "Chemicals", 1, 1, 5, 8, "Chemicals" },
	Gears = { "MechanicalParts", 1, 1, 6, 9, "Gears" },
	MedPouch = { "Medkit", 1, 1, 2, 4, "Med pouch" },
	Flares = { "Flare", 1, 2, 3, 4, "Flares" },
}

local function piece(model, size, cf, color, material, shape)
	local p = Instance.new("Part")
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or Enum.Material.Metal
	p.Anchored = true
	p.CanCollide = false
	p.CastShadow = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if shape then
		p.Shape = shape
	end
	p.Parent = model
	return p
end

local CYL = Enum.PartType.Cylinder
local UP = CFrame.Angles(0, 0, math.rad(90)) -- cylinder axis X -> Y

-- Builders get the ground CFrame (Y up, random yaw) and return the main part.
local BUILD = {
	Scrap = function(m, cf)
		local base = piece(m, Vector3.new(1.6, 0.25, 1.1), cf * CFrame.new(0, 0.13, 0) * CFrame.Angles(0, 0, math.rad(8)), col(118, 122, 124), Enum.Material.CorrodedMetal)
		piece(m, Vector3.new(1.2, 0.18, 0.7), cf * CFrame.new(0.3, 0.3, 0.2) * CFrame.Angles(math.rad(20), math.rad(30), 0), col(96, 80, 64), Enum.Material.CorrodedMetal)
		piece(m, Vector3.new(1.4, 0.25, 0.25), cf * CFrame.new(-0.3, 0.3, -0.3) * CFrame.Angles(0, math.rad(60), 0), col(80, 84, 86), Enum.Material.Metal, CYL)
		return base
	end,
	Cans = function(m, cf)
		local a = piece(m, Vector3.new(0.7, 0.5, 0.5), cf * CFrame.new(0, 0.35, 0) * UP, col(170, 60, 50), Enum.Material.Metal, CYL)
		piece(m, Vector3.new(0.7, 0.5, 0.5), cf * CFrame.new(0.55, 0.35, 0.1) * UP, col(60, 110, 160), Enum.Material.Metal, CYL)
		piece(m, Vector3.new(0.52, 0.28, 0.02), cf * CFrame.new(0, 0.38, -0.26), col(230, 220, 190), Enum.Material.SmoothPlastic)
		return a
	end,
	Bottle = function(m, cf)
		local b = piece(m, Vector3.new(1.1, 0.45, 0.45), cf * CFrame.new(0, 0.55, 0) * UP, col(120, 180, 220), Enum.Material.Glass, CYL)
		b.Transparency = 0.3
		piece(m, Vector3.new(0.25, 0.22, 0.22), cf * CFrame.new(0, 1.2, 0) * UP, col(40, 90, 170), Enum.Material.SmoothPlastic, CYL)
		return b
	end,
	Wires = function(m, cf)
		local c = piece(m, Vector3.new(0.3, 1.3, 1.3), cf * CFrame.new(0, 0.15, 0) * UP, col(196, 120, 64), Enum.Material.Fabric, CYL)
		piece(m, Vector3.new(0.32, 0.5, 0.5), cf * CFrame.new(0, 0.16, 0) * UP, col(30, 30, 30), Enum.Material.SmoothPlastic, CYL)
		piece(m, Vector3.new(1.2, 0.08, 0.08), cf * CFrame.new(0.8, 0.05, 0.3) * CFrame.Angles(0, math.rad(25), 0), col(196, 120, 64), Enum.Material.Fabric)
		return c
	end,
	Circuit = function(m, cf)
		local b = piece(m, Vector3.new(1.3, 0.08, 0.9), cf * CFrame.new(0, 0.05, 0), col(40, 120, 70), Enum.Material.SmoothPlastic)
		for i = -1, 1 do
			piece(m, Vector3.new(0.25, 0.12, 0.25), cf * CFrame.new(i * 0.35, 0.14, 0.15), col(30, 30, 30), Enum.Material.SmoothPlastic)
		end
		local led = piece(m, Vector3.new(0.1, 0.1, 0.1), cf * CFrame.new(0.5, 0.14, -0.3), col(255, 80, 60), Enum.Material.Neon)
		led.CastShadow = false
		return b
	end,
	Jerrycan = function(m, cf)
		local b = piece(m, Vector3.new(1.3, 1.6, 0.6), cf * CFrame.new(0, 0.8, 0), col(170, 40, 30), Enum.Material.Metal)
		piece(m, Vector3.new(0.7, 0.18, 0.2), cf * CFrame.new(-0.1, 1.72, 0), col(40, 40, 40), Enum.Material.Metal)
		piece(m, Vector3.new(0.2, 0.3, 0.2), cf * CFrame.new(0.45, 1.7, 0), col(200, 170, 60), Enum.Material.Metal, CYL)
		return b
	end,
	Plastic = function(m, cf)
		local b = piece(m, Vector3.new(1.4, 0.7, 1), cf * CFrame.new(0, 0.35, 0), col(200, 196, 176), Enum.Material.Plastic)
		piece(m, Vector3.new(1.6, 0.3, 0.3), cf * CFrame.new(0.2, 0.15, 0.7) * CFrame.Angles(0, math.rad(15), 0), col(180, 180, 170), Enum.Material.Plastic, CYL)
		return b
	end,
	Chem = function(m, cf)
		local b = piece(m, Vector3.new(0.9, 0.55, 0.55), cf * CFrame.new(0, 0.45, 0) * UP, col(150, 110, 190), Enum.Material.Glass, CYL)
		b.Transparency = 0.25
		piece(m, Vector3.new(0.2, 0.35, 0.35), cf * CFrame.new(0, 0.98, 0) * UP, col(40, 40, 40), Enum.Material.SmoothPlastic, CYL)
		local glow = piece(m, Vector3.new(0.6, 0.4, 0.4), cf * CFrame.new(0, 0.4, 0) * UP, col(170, 255, 120), Enum.Material.Neon, CYL)
		glow.Transparency = 0.5
		return b
	end,
	Gears = function(m, cf)
		local g = piece(m, Vector3.new(0.25, 1.1, 1.1), cf * CFrame.new(0, 0.13, 0) * UP, col(150, 140, 110), Enum.Material.Metal, CYL)
		piece(m, Vector3.new(0.25, 0.7, 0.7), cf * CFrame.new(0.7, 0.13, 0.3) * UP, col(120, 110, 90), Enum.Material.CorrodedMetal, CYL)
		return g
	end,
	MedPouch = function(m, cf)
		local b = piece(m, Vector3.new(1.2, 0.5, 0.8), cf * CFrame.new(0, 0.25, 0), col(230, 230, 226), Enum.Material.Fabric)
		piece(m, Vector3.new(0.5, 0.52, 0.15), cf * CFrame.new(0, 0.26, 0), col(200, 40, 40), Enum.Material.SmoothPlastic)
		piece(m, Vector3.new(0.15, 0.52, 0.5), cf * CFrame.new(0, 0.26, 0), col(200, 40, 40), Enum.Material.SmoothPlastic)
		return b
	end,
	Flares = function(m, cf)
		local a = piece(m, Vector3.new(1, 0.25, 0.25), cf * CFrame.new(0, 0.13, 0), col(220, 60, 50), Enum.Material.SmoothPlastic, CYL)
		piece(m, Vector3.new(1, 0.25, 0.25), cf * CFrame.new(0.1, 0.13, 0.3) * CFrame.Angles(0, math.rad(12), 0), col(220, 60, 50), Enum.Material.SmoothPlastic, CYL)
		return a
	end,
}

function Scatter.init(g)
	G = g
end

local function pickKind(far)
	local total = 0
	for _, k in pairs(KINDS) do
		total += k[4] + (k[5] - k[4]) * far
	end
	local r = math.random() * total
	for name, k in pairs(KINDS) do
		r -= k[4] + (k[5] - k[4]) * far
		if r <= 0 then
			return name
		end
	end
	return "Scrap"
end

local params
local function filter()
	if not params then
		params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.IgnoreWater = false
	end
	local list = { workspace.NPCs, workspace.Effects }
	for _, name in ipairs({ "Interactables", "Boats", "BuildObjects", "Scatter" }) do
		local f = workspace:FindFirstChild(name)
		if f then
			table.insert(list, f)
		end
	end
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Character then
			table.insert(list, p.Character)
		end
	end
	params.FilterDescendantsInstances = list
	return params
end

local function folder()
	local f = workspace:FindFirstChild("Scatter")
	if not f then
		f = Instance.new("Folder")
		f.Name = "Scatter"
		f.Parent = workspace
	end
	return f
end

local function tooClose(pos)
	for _, it in ipairs(Scatter.items) do
		if (it.pos - pos).Magnitude < SPACING then
			return true
		end
	end
	return false
end

-- A walkable, dry, open spot on a surface. Returns the ground position or nil.
function Scatter.findSpot(center, p)
	local a = math.random() * math.pi * 2
	local r = math.random(22, RADIUS - 10)
	local x, z = center.X + math.cos(a) * r, center.Z + math.sin(a) * r
	-- Half the probes start at the player's level (finds floors inside rooms and under roofs).
	local fromY = math.random() < 0.5 and center.Y + 5 or center.Y + 80
	local hit = workspace:Raycast(Vector3.new(x, fromY, z), Vector3.new(0, -160, 0), p)
	if not hit or hit.Normal.Y < 0.78 or hit.Material == Enum.Material.Water then
		return nil
	end
	local pos = hit.Position
	if pos.Y < Config.WaterLevel + 0.6 then
		return nil
	end
	local inst = hit.Instance
	if inst ~= workspace.Terrain and (not inst:IsA("BasePart") or not inst.Anchored or inst.Transparency > 0.6) then
		return nil
	end
	if workspace:Raycast(pos + Vector3.new(0, 0.2, 0), Vector3.new(0, 4, 0), p) then
		return nil -- no headroom (under a pipe, inside a wall...)
	end
	-- Beside it must be floor too (not balanced on a railing or a thin beam).
	local side = workspace:Raycast(pos + Vector3.new(1.2, 1, 1.2), Vector3.new(0, -2.2, 0), p)
	if not side then
		return nil
	end
	if tooClose(pos) then
		return nil
	end
	return pos
end

function Scatter.spawn(kind, pos)
	local def = KINDS[kind]
	local m = Instance.new("Model")
	m.Name = "Scatter_" .. kind
	local cf = CFrame.new(pos) * CFrame.Angles(0, math.random() * math.pi * 2, 0)
	local main = BUILD[kind](m, cf)
	m.PrimaryPart = main
	m:SetAttribute("Scatter", kind)
	-- A faint glint so loose items can be spotted from a distance.
	local glint = Instance.new("ParticleEmitter")
	glint.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	glint.LightEmission = 1
	glint.Color = ColorSequence.new(Color3.fromRGB(255, 236, 180))
	glint.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 0) })
	glint.Lifetime = NumberRange.new(0.6, 1)
	glint.Rate = 0.9
	glint.Speed = NumberRange.new(0.5)
	glint.SpreadAngle = Vector2.new(180, 180)
	glint.Parent = main
	local prompt = G.Util.prompt(main, "Pick up", def[6], 0.25, 8)
	prompt.RequiresLineOfSight = false
	m.Parent = folder()
	local entry = { model = m, pos = pos, kind = kind, born = os.clock() }
	prompt.Triggered:Connect(function(player)
		Scatter.take(player, entry)
	end)
	table.insert(Scatter.items, entry)
	return entry
end

function Scatter.take(player, entry)
	if entry.taken or not entry.model.Parent or not G.Net.near(player, entry.model, 11) then
		return
	end
	local def = KINDS[entry.kind]
	local n = math.random(def[2], def[3])
	if G.Inventory.space(player, def[1]) <= 0 then
		G.Net.toast(player, "Inventory full.", "warn")
		return
	end
	entry.taken = true
	local added = G.Inventory.add(player, def[1], n)
	G.Net.toast(player, string.format("+%d %s", added, Items.name(def[1])), "good")
	local main = entry.model.PrimaryPart
	if main then
		SFX.play("Pickup", main)
	end
	G.AI.noise(entry.pos, 12)
	if G.Quests then
		G.Quests.event("Scavenge", "Any", 1)
		G.Quests.event("Gather", def[1], added)
	end
	entry.model:Destroy()
end

local function prune(alive)
	local now = os.clock()
	for i = #Scatter.items, 1, -1 do
		local it = Scatter.items[i]
		local keep = it.model.Parent ~= nil and not it.taken and now - it.born < LIFETIME
		if keep and now - it.born > 30 then
			local near = false
			for _, info in ipairs(alive) do
				if (info.root.Position - it.pos).Magnitude < RADIUS + 120 then
					near = true
					break
				end
			end
			keep = near
		end
		if not keep then
			if it.model.Parent then
				it.model:Destroy()
			end
			table.remove(Scatter.items, i)
		end
	end
end

-- 4 Hz from the main loop; does real work every 2.5 s.
function Scatter.step(dt)
	Scatter.timer -= dt
	if Scatter.timer > 0 then
		return
	end
	Scatter.timer = 2.5
	local alive = G.Util.alivePlayers()
	prune(alive)
	if #Scatter.items >= MAX_TOTAL then
		return
	end
	local p = filter()
	for _, info in ipairs(alive) do
		local center = info.root.Position
		local count = 0
		for _, it in ipairs(Scatter.items) do
			if (it.pos - center).Magnitude < RADIUS then
				count += 1
			end
		end
		local tries = 0
		while count < PER_PLAYER and tries < 8 and #Scatter.items < MAX_TOTAL do
			tries += 1
			local pos = Scatter.findSpot(center, p)
			-- Never pop into existence right in front of someone.
			if pos and ((pos - center).Magnitude > 45 or not G.AI.visible(info.root.Position + Vector3.new(0, 1.5, 0), pos + Vector3.new(0, 0.5, 0), nil, info.character)) then
				local far = math.clamp(Vector3.new(pos.X, 0, pos.Z).Magnitude / 2500, 0, 1)
				Scatter.spawn(pickKind(far), pos)
				count += 1
			end
		end
	end
end

function Scatter.clear()
	for _, it in ipairs(Scatter.items) do
		if it.model.Parent then
			it.model:Destroy()
		end
	end
	Scatter.items = {}
end

return Scatter
