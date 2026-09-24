-- ServerScriptService/Systems/Loot
-- Resource nodes placed at logical spots in the place file (workspace/Interactables/Loot).
-- The node's name decides what it holds: fuel drums hold fuel, electric panels hold
-- electronics and copper, fridges hold food... Every search guarantees the base items;
-- only small bonuses are random. Searching makes noise that creatures can hear.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Items = require(ReplicatedStorage.Modules.Items)

local Loot = { nodes = {} }
local G

local TABLES = {
	FuelDrum = { label = "Fuel Drum", respawn = 150, hold = 1, give = { { "Fuel", 1 } }, bonus = { { "Fuel", 1, 0.35 } } },
	ScrapPile = { label = "Scrap Pile", respawn = 90, hold = 0.8, give = { { "ScrapMetal", 2 } }, bonus = { { "ScrapMetal", 1, 0.5 }, { "MechanicalParts", 1, 0.12 } } },
	Toolbox = { label = "Toolbox", respawn = 200, hold = 1, give = { { "MechanicalParts", 1 } }, bonus = { { "ScrapMetal", 1, 0.5 } } },
	ElectricPanel = { label = "Electrical Panel", respawn = 180, hold = 1.4, give = { { "Electronics", 1 }, { "Copper", 1 } }, bonus = { { "Electronics", 1, 0.25 } } },
	CableSpool = { label = "Cable Spool", respawn = 160, hold = 1, give = { { "Copper", 2 } } },
	SupplyCrate = { label = "Supply Crate", respawn = 200, hold = 1, give = { { "Plastic", 2 } }, bonus = { { "Food", 1, 0.4 } } },
	Fridge = { label = "Fridge", respawn = 240, hold = 0.8, give = { { "Food", 1 } }, bonus = { { "Water", 1, 0.6 } } },
	WaterTank = { label = "Water Tank", respawn = 150, hold = 1, give = { { "Water", 1 } }, bonus = { { "Water", 1, 0.4 } } },
	MedCabinet = { label = "Medical Cabinet", respawn = 260, hold = 1, give = { { "Chemicals", 1 } }, bonus = { { "Medkit", 1, 0.25 } } },
	ChemDrum = { label = "Chemical Drum", respawn = 220, hold = 1, give = { { "Chemicals", 2 } } },
	Locker = { label = "Locker", respawn = 240, hold = 0.8, give = { { "Plastic", 1 } }, bonus = { { "Flare", 1, 0.25 } } },
	Wreckage = { label = "Wreckage", respawn = 300, hold = 1.5, give = { { "ScrapMetal", 3 }, { "Electronics", 1 } }, bonus = { { "MechanicalParts", 1, 0.5 } } },
	RareDeposit = { label = "Crystal Growth", respawn = 420, hold = 1.5, give = { { "RareMaterials", 1 } }, bonus = { { "Copper", 1, 0.5 } } },
	AirDrop = { label = "Supply Drop", once = true, hold = 1.2, give = { { "Fuel", 2 }, { "Electronics", 2 }, { "Food", 2 }, { "Water", 2 }, { "Medkit", 1 } } },
	Cache = { label = "Signal Cache", once = true, hold = 1.2, give = { { "RareMaterials", 1 }, { "Electronics", 2 }, { "MechanicalParts", 2 }, { "Fuel", 2 } } },
}
Loot.Tables = TABLES

-- Materials that are physically taken: they vanish when searched and reappear later.
local PICKUP = { FuelDrum = true, ScrapPile = true, Toolbox = true, CableSpool = true, SupplyCrate = true, ChemDrum = true, Wreckage = true, RareDeposit = true }
-- Loose objects with physics: they can be pushed, dragged (G) and they fall onto surfaces.
local PHYSICAL = { FuelDrum = 0.55, ScrapPile = 0.9, Toolbox = 0.6, CableSpool = 0.5, SupplyCrate = 0.35, ChemDrum = 0.55 }
-- Wall-mounted containers keep their exact placement.
local WALL = { ElectricPanel = true, MedCabinet = true }
Loot.byInstance = {}

function Loot.init(g)
	G = g
	local folder = workspace.Interactables:FindFirstChild("Loot")
	if folder then
		for _, node in ipairs(folder:GetDescendants()) do
			if (node:IsA("Model") or node:IsA("BasePart")) and TABLES[Loot.typeOf(node)] and node.Parent:IsA("Folder") then
				Loot.register(node)
			end
		end
	end
	local logs = workspace:GetDescendants()
	for _, p in ipairs(logs) do
		if p:IsA("BasePart") and string.sub(p.Name, 1, 4) == "Log_" then
			Loot.registerLog(p)
		end
	end
end

function Loot.typeOf(node)
	return string.match(node.Name, "^(%a+)")
end

local function partOf(node)
	if node:IsA("BasePart") then
		return node
	end
	return node.PrimaryPart or node:FindFirstChildWhichIsA("BasePart", true)
end

local function setEmpty(node, empty)
	node:SetAttribute("Empty", empty)
	for _, p in ipairs(node:IsA("BasePart") and { node } or node:GetDescendants()) do
		if p:IsA("BasePart") then
			if p:GetAttribute("BaseColor") == nil then
				p:SetAttribute("BaseColor", p.Color)
			end
			local base = p:GetAttribute("BaseColor")
			p.Color = empty and base:Lerp(Color3.new(0, 0, 0), 0.55) or base
		end
	end
end

function Loot.register(node)
	local kind = Loot.typeOf(node)
	local t = TABLES[kind]
	local part = partOf(node)
	if not t or not part then
		return
	end
	local prompt = G.Util.prompt(part, PICKUP[kind] and "Take" or "Search", t.label, t.hold, 9)
	local entry = { node = node, part = part, t = t, prompt = prompt, ready = true, kind = kind, pickup = PICKUP[kind] == true, density = PHYSICAL[kind] }
	Loot.byInstance[node] = entry
	prompt.Triggered:Connect(function(player)
		Loot.search(player, entry)
	end)
	table.insert(Loot.nodes, entry)
	return entry
end

function Loot.search(player, entry)
	if not entry.ready or not G.Net.near(player, entry.part, 12) then
		return
	end
	local got = {}
	local rewards = {}
	for _, g in ipairs(entry.t.give) do
		table.insert(rewards, { g[1], g[2] })
	end
	for _, b in ipairs(entry.t.bonus or {}) do
		if math.random() < b[3] then
			table.insert(rewards, { b[1], b[2] })
		end
	end
	local anyFit = false
	for _, r in ipairs(rewards) do
		if G.Inventory.space(player, r[1]) > 0 then
			anyFit = true
		end
	end
	if not anyFit then
		G.Net.toast(player, "Inventory full.", "warn")
		return
	end
	entry.ready = false
	entry.prompt.Enabled = false
	local lost = false
	for _, r in ipairs(rewards) do
		local added = G.Inventory.add(player, r[1], r[2])
		if added > 0 then
			table.insert(got, "+" .. added .. " " .. Items.name(r[1]))
			if G.Quests then
				G.Quests.event("Gather", r[1], added)
			end
		end
		if added < r[2] then
			lost = true
		end
	end
	G.Net.toast(player, table.concat(got, "   ") .. (lost and "  (no room for the rest)" or ""), "good")
	G.AI.noise(entry.part.Position, 35)
	if entry.t.once then
		task.delay(2, function()
			if entry.node.Parent then
				entry.node:Destroy()
			end
		end)
		return
	end
	if entry.pickup then
		G.Carry.releaseNode(entry.node)
		Loot.hide(entry)
	else
		setEmpty(entry.node, true)
	end
	task.delay(entry.t.respawn, function()
		if entry.node.Parent then
			entry.ready = true
			entry.prompt.Enabled = true
			if entry.pickup then
				Loot.show(entry)
			else
				setEmpty(entry.node, false)
			end
		end
	end)
end

local function partsOf(node)
	if node:IsA("BasePart") then
		return { node }
	end
	local list = {}
	for _, d in ipairs(node:GetDescendants()) do
		if d:IsA("BasePart") then
			table.insert(list, d)
		end
	end
	return list
end

function Loot.hide(entry)
	for _, p in ipairs(partsOf(entry.node)) do
		if p:GetAttribute("BaseTransparency") == nil then
			p:SetAttribute("BaseTransparency", p.Transparency)
			p:SetAttribute("BaseCollide", p.CanCollide)
		end
		p.Anchored = true
		p.Transparency = 1
		p.CanCollide = false
		p.CanQuery = false
	end
	for _, d in ipairs(entry.node:GetDescendants()) do
		if d:IsA("Light") or d:IsA("ParticleEmitter") then
			d.Enabled = false
		end
	end
	entry.node:SetAttribute("Taken", true)
end

function Loot.show(entry)
	entry.node:PivotTo(entry.home or entry.node:GetPivot())
	for _, p in ipairs(partsOf(entry.node)) do
		p.Transparency = p:GetAttribute("BaseTransparency") or 0
		p.CanCollide = p:GetAttribute("BaseCollide") ~= false
		p.CanQuery = true
		p.AssemblyLinearVelocity = Vector3.zero
		p.AssemblyAngularVelocity = Vector3.zero
	end
	for _, d in ipairs(entry.node:GetDescendants()) do
		if d:IsA("Light") or d:IsA("ParticleEmitter") then
			d.Enabled = true
		end
	end
	entry.node:SetAttribute("Taken", false)
	if entry.physical then
		for _, p in ipairs(partsOf(entry.node)) do
			p.Anchored = false
		end
	end
end

-- Drops a node onto whatever is below it (or lifts it out of the ground). Runs once the
-- terrain exists, so nothing hovers above or sinks into islands, decks and wrecks.
function Loot.snap(entry)
	if WALL[entry.kind] then
		return
	end
	local node = entry.node
	local cf, size
	if node:IsA("Model") then
		cf, size = node:GetBoundingBox()
	else
		cf, size = node.CFrame, node.Size
		-- Rotated cylinders: use the world-space extent.
		local ext = node.CFrame:VectorToWorldSpace(node.Size)
		size = Vector3.new(math.abs(ext.X), math.abs(ext.Y), math.abs(ext.Z))
		local up = math.abs(node.CFrame.RightVector.Y) * node.Size.X + math.abs(node.CFrame.UpVector.Y) * node.Size.Y + math.abs(node.CFrame.LookVector.Y) * node.Size.Z
		size = Vector3.new(size.X, up, size.Z)
	end
	local bottom = cf.Position.Y - size.Y / 2
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { node, workspace.NPCs, workspace.Interactables:FindFirstChild("Loot"), workspace.Effects }
	params.IgnoreWater = true
	local origin = Vector3.new(cf.Position.X, cf.Position.Y + math.min(size.Y / 2 + 1, 4), cf.Position.Z)
	local hit = workspace:Raycast(origin, Vector3.new(0, -60, 0), params)
	if not hit then
		return
	end
	local delta = hit.Position.Y - bottom
	if math.abs(delta) > 0.25 and math.abs(delta) < 40 then
		node:PivotTo(node:GetPivot() + Vector3.new(0, delta + 0.02, 0))
	end
end

-- Called from Main after the ocean and islands are built.
function Loot.settle()
	for _, entry in ipairs(Loot.nodes) do
		pcall(Loot.snap, entry)
		entry.home = entry.node:GetPivot()
		if entry.density and not entry.t.once then
			local parts = partsOf(entry.node)
			local main = entry.part
			for _, p in ipairs(parts) do
				p.CustomPhysicalProperties = PhysicalProperties.new(entry.density, 0.6, 0.1)
				if p ~= main then
					local w = Instance.new("WeldConstraint")
					w.Part0 = main
					w.Part1 = p
					w.Parent = p
				end
			end
			for _, p in ipairs(parts) do
				p.Anchored = false
			end
			entry.physical = true
			entry.node:SetAttribute("Draggable", true)
		end
	end
	-- Anything knocked into the sea or dragged far away drifts back home after a while.
	task.spawn(function()
		while true do
			task.wait(5)
			for _, entry in ipairs(Loot.nodes) do
				if entry.physical and entry.ready and entry.node.Parent and not entry.node:GetAttribute("Carried") then
					local pos = entry.part.Position
					if pos.Y < -40 or (entry.home and (pos - entry.home.Position).Magnitude > 900) then
						Loot.show(entry)
					end
				end
			end
		end
	end)
end

function Loot.entryOf(inst)
	local cur = inst
	while cur and cur ~= workspace do
		local e = Loot.byInstance[cur]
		if e then
			return e
		end
		cur = cur.Parent
	end
	return nil
end

-- Spawns a one-off loot container (events).
function Loot.spawnContainer(kind, cf, parent)
	local box = Instance.new("Part")
	box.Name = kind
	box.Size = Vector3.new(4, 3, 4)
	box.CFrame = cf
	box.Anchored = true
	box.Color = kind == "AirDrop" and Color3.fromRGB(200, 70, 40) or Color3.fromRGB(60, 150, 170)
	box.Material = Enum.Material.DiamondPlate
	box.Parent = parent or workspace.Interactables
	local light = Instance.new("PointLight")
	light.Color = box.Color
	light.Range = 18
	light.Brightness = 2
	light.Parent = box
	local smoke = Instance.new("ParticleEmitter")
	smoke.Texture = "rbxasset://textures/particles/smoke_main.dds"
	smoke.Color = ColorSequence.new(Color3.fromRGB(255, 90, 60))
	smoke.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 6) })
	smoke.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.4), NumberSequenceKeypoint.new(1, 1) })
	smoke.Lifetime = NumberRange.new(3, 5)
	smoke.Speed = NumberRange.new(6, 10)
	smoke.Rate = 8
	smoke.EmissionDirection = Enum.NormalId.Top
	smoke.Parent = box
	Loot.register(box)
	return box
end

function Loot.registerLog(part)
	local prompt = G.Util.prompt(part, "Read", "LOG", 0.3, 8)
	prompt.Triggered:Connect(function(player)
		if not G.Net.near(player, part, 10) then
			return
		end
		G.Net.open(player, "Log", { id = part.Name })
		if G.PlayerData.unlock(player, "log_" .. part.Name) and G.Quests then
			G.Quests.event("Log", "Any", 1)
		end
	end)
end

return Loot
