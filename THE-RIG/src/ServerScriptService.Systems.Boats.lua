-- ServerScriptService/Systems/Boats
-- Motorboat: floats on terrain water (low density hull), driven by the seated player's client
-- through LinearVelocity (plane) + AlignOrientation. The server owns fuel, health, cargo,
-- recall to dock and boundary checks.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Modules.Config)
local Items = require(ReplicatedStorage.Modules.Items)

local Boats = { list = {} }
local G
local B = Config.Boat

function Boats.init(g)
	G = g
	G.Net.on("CargoDeposit", function(player, boatModel, slot)
		if not G.Net.isInt(slot, 1, Config.Inventory.Slots) then
			return
		end
		Boats.deposit(player, boatModel, slot)
	end, 0.2)
	G.Net.on("CargoTake", function(player, boatModel, index)
		if not G.Net.isInt(index, 1, B.CargoSlots) then
			return
		end
		Boats.take(player, boatModel, index)
	end, 0.2)
	G.Net.on("BoatRefuel", function(player, boatModel)
		Boats.refuel(player, boatModel)
	end, 0.4)
end

local function boatOf(model)
	for _, b in ipairs(Boats.list) do
		if b.model == model then
			return b
		end
	end
	return nil
end

local function yawOnly(cf)
	local look = cf.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	if flat.Magnitude < 0.01 then
		flat = Vector3.new(0, 0, -1)
	end
	return CFrame.lookAt(Vector3.zero, flat.Unit)
end

-- Called after the ocean exists (boats are anchored in the place file until then).
function Boats.setup()
	for _, model in ipairs(workspace.Boats:GetChildren()) do
		if model:IsA("Model") and model:FindFirstChild("Hull") then
			Boats.setupBoat(model)
		end
	end
	local console = workspace.Interactables:FindFirstChild("BoatConsole", true)
	if console then
		local prompt = G.Util.prompt(console, "Recall boat", "BOAT DOCK", 1, 9)
		prompt.Triggered:Connect(function(player)
			if not G.Net.near(player, console, 12) then
				return
			end
			for _, b in ipairs(Boats.list) do
				if b.seat.Occupant then
					G.Net.toast(player, "Someone is driving the boat.", "warn")
				else
					Boats.recall(b)
					G.Net.toast(player, "Boat returned to the dock.", "good")
				end
			end
		end)
	end
	if console then
		-- Upgrades for the long expeditions (the ocean is 8 km across).
		local engine = G.Util.prompt(console, "Upgrade engine", "BOAT WORKSHOP", 1.2, 9)
		engine.KeyboardKeyCode = Enum.KeyCode.R
		engine.UIOffset = Vector2.new(0, 70)
		engine.Triggered:Connect(function(player)
			Boats.upgrade(player, console, "engine")
		end)
		local tank = G.Util.prompt(console, "Upgrade tank", "BOAT WORKSHOP", 1.2, 9)
		tank.KeyboardKeyCode = Enum.KeyCode.T
		tank.UIOffset = Vector2.new(0, 140)
		tank.Triggered:Connect(function(player)
			Boats.upgrade(player, console, "tank")
		end)
		Boats.upgradePrompts = { engine = engine, tank = tank }
		Boats.refreshUpgradePrompts()
	end
	task.spawn(function()
		while true do
			task.wait(1)
			for _, b in ipairs(Boats.list) do
				local ok, err = pcall(Boats.tick, b)
				if not ok then
					warn("[Boats] " .. tostring(err))
				end
			end
		end
	end)
end

local ENGINE = {
	{ speed = 46 },
	{ speed = 60, cost = { MechanicalParts = 4, Copper = 3, Electronics = 2 } },
	{ speed = 74, cost = { MechanicalParts = 6, Electronics = 4, RareMaterials = 2 } },
}
local TANK = {
	{ fuel = 100 },
	{ fuel = 170, cost = { ScrapMetal = 6, Plastic = 4 } },
	{ fuel = 250, cost = { ScrapMetal = 10, Plastic = 6, Chemicals = 3 } },
}

function Boats.refreshUpgradePrompts()
	local b = Boats.list[1]
	local prompts = Boats.upgradePrompts
	if not b or not prompts then
		return
	end
	local nextEngine, nextTank = ENGINE[(b.engine or 1) + 1], TANK[(b.tank or 1) + 1]
	prompts.engine.Enabled = nextEngine ~= nil
	prompts.tank.Enabled = nextTank ~= nil
	if nextEngine then
		prompts.engine.ObjectText = string.format("ENGINE L%d (%d kn): %s", (b.engine or 1) + 1, nextEngine.speed, Items.costText(nextEngine.cost))
	end
	if nextTank then
		prompts.tank.ObjectText = string.format("TANK L%d (%d fuel): %s", (b.tank or 1) + 1, nextTank.fuel, Items.costText(nextTank.cost))
	end
end

function Boats.applyLevels(b, engine, tank)
	b.engine, b.tank = engine, tank
	b.model:SetAttribute("EngineLevel", engine)
	b.model:SetAttribute("TankLevel", tank)
	b.model:SetAttribute("MaxSpeed", ENGINE[engine].speed)
	b.model:SetAttribute("FuelMax", TANK[tank].fuel)
	Boats.refreshUpgradePrompts()
end

function Boats.upgrade(player, console, kind)
	local b = Boats.list[1]
	if not b or not G.Net.near(player, console, 12) then
		return
	end
	local levels = kind == "engine" and ENGINE or TANK
	local current = (kind == "engine" and b.engine or b.tank) or 1
	local nextLevel = levels[current + 1]
	if not nextLevel then
		G.Net.toast(player, "Already at maximum level.", "info")
		return
	end
	local ok, missing = G.Inventory.takeAll(player, nextLevel.cost)
	if not ok then
		G.Net.toast(player, "Missing: " .. missing, "warn")
		return
	end
	if kind == "engine" then
		Boats.applyLevels(b, current + 1, b.tank or 1)
	else
		Boats.applyLevels(b, b.engine or 1, current + 1)
	end
	G.Net.banner("BOAT UPGRADED", string.format("Engine L%d (%d kn) / Tank L%d (%d fuel)", b.engine, ENGINE[b.engine].speed, b.tank, TANK[b.tank].fuel), "good")
end

function Boats.setupBoat(model)
	local hull = model.Hull
	model.PrimaryPart = hull
	local seat = model:FindFirstChildWhichIsA("VehicleSeat", true)
	local light = PhysicalProperties.new(0.3, 0.3, 0.1)
	for _, p in ipairs(model:GetDescendants()) do
		if p:IsA("BasePart") then
			p.CustomPhysicalProperties = light
			if p ~= hull then
				local w = Instance.new("WeldConstraint")
				w.Part0 = hull
				w.Part1 = p
				w.Parent = p
			end
		end
	end
	local att = Instance.new("Attachment")
	att.Name = "DriveAttachment"
	att.Parent = hull
	local drive = Instance.new("LinearVelocity")
	drive.Name = "Drive"
	drive.Attachment0 = att
	drive.RelativeTo = Enum.ActuatorRelativeTo.World
	drive.VelocityConstraintMode = Enum.VelocityConstraintMode.Plane
	drive.PrimaryTangentAxis = Vector3.new(1, 0, 0)
	drive.SecondaryTangentAxis = Vector3.new(0, 0, 1)
	drive.PlaneVelocity = Vector2.zero
	drive.MaxForce = 40000
	drive.Parent = hull
	local keel = Instance.new("AlignOrientation")
	keel.Name = "Keel"
	keel.Mode = Enum.OrientationAlignmentMode.OneAttachment
	keel.Attachment0 = att
	keel.MaxTorque = 5e6
	keel.Responsiveness = 14
	keel.CFrame = yawOnly(hull.CFrame)
	keel.Parent = hull

	local b = { model = model, hull = hull, seat = seat, drive = drive, keel = keel, home = model:GetPivot(), cargo = {} }
	model:SetAttribute("Fuel", B.StartFuel)
	model:SetAttribute("FuelMax", B.FuelMax)
	model:SetAttribute("MaxSpeed", B.MaxSpeed)
	model:SetAttribute("ReverseSpeed", B.ReverseSpeed)
	model:SetAttribute("TurnRate", B.TurnRate)
	G.Repair.register(model, {
		name = "MOTORBOAT",
		max = B.Health,
		cost = { ScrapMetal = 5, Plastic = 2 },
		promptPart = hull,
		onBroken = function()
			G.Net.toastAll("The motorboat is disabled! Repair it to drive again.", "danger")
		end,
	})
	local cargoPart = model:FindFirstChild("CargoBox") or hull
	local cargoPrompt = G.Util.prompt(cargoPart, "Cargo", "BOAT CARGO", 0, 9)
	cargoPrompt.Triggered:Connect(function(player)
		if G.Net.near(player, cargoPart, 14) then
			Boats.openCargo(player, b)
		end
	end)
	local fuelPart = model:FindFirstChild("FuelCap") or hull
	local fuelPrompt = G.Util.prompt(fuelPart, "Refuel boat", "MOTORBOAT", 0.5, 9)
	fuelPrompt.UIOffset = Vector2.new(0, -70)
	fuelPrompt.Triggered:Connect(function(player)
		Boats.refuel(player, model)
	end)

	for _, p in ipairs(model:GetDescendants()) do
		if p:IsA("BasePart") then
			p.Anchored = false
		end
	end
	hull:SetNetworkOwnershipAuto()
	table.insert(Boats.list, b)
	Boats.applyLevels(b, 1, 1)
	return b
end

function Boats.recall(b)
	for _, p in ipairs(b.model:GetDescendants()) do
		if p:IsA("BasePart") then
			p.AssemblyLinearVelocity = Vector3.zero
			p.AssemblyAngularVelocity = Vector3.zero
		end
	end
	b.model:PivotTo(b.home)
	b.keel.CFrame = yawOnly(b.home)
	b.drive.PlaneVelocity = Vector2.zero
end

function Boats.tick(b)
	local model = b.model
	if not model.Parent then
		return
	end
	local occupant = b.seat and b.seat.Occupant
	local pos = b.hull.Position
	if occupant then
		local v = b.hull.AssemblyLinearVelocity
		local speed = Vector3.new(v.X, 0, v.Z).Magnitude
		local fuel = model:GetAttribute("Fuel") or 0
		if fuel > 0 and speed > 1 then
			fuel = math.max(0, fuel - (0.04 + speed * 0.012))
			model:SetAttribute("Fuel", math.floor(fuel * 10) / 10)
			if fuel <= 0 then
				local player = Players:GetPlayerFromCharacter(occupant.Parent)
				if player then
					G.Net.toast(player, "The boat is out of fuel. Refuel it with a Fuel Can.", "warn")
				end
			end
		end
		-- Server-side sanity check on speed (driver's client simulates the boat).
		local maxSpeed = model:GetAttribute("MaxSpeed") or B.MaxSpeed
		if speed > maxSpeed * 1.6 then
			b.hull.AssemblyLinearVelocity = v.Unit * maxSpeed
		end
	else
		b.keel.CFrame = yawOnly(b.hull.CFrame)
		b.drive.PlaneVelocity = Vector2.zero
	end
	if Vector3.new(pos.X, 0, pos.Z).Magnitude > Config.BoundaryRadius + 60 or pos.Y < Config.WaterLevel - 25 then
		if occupant then
			occupant.Sit = false
		end
		Boats.recall(b)
	end
end

function Boats.refuel(player, model)
	local b = typeof(model) == "Instance" and boatOf(model)
	if not b or not G.Net.near(player, b.hull, 16) then
		return
	end
	local fuel = model:GetAttribute("Fuel") or 0
	local fuelMax = model:GetAttribute("FuelMax") or B.FuelMax
	if fuel > fuelMax - 5 then
		G.Net.toast(player, "Boat tank is full.", "info")
		return
	end
	if not G.Inventory.remove(player, "Fuel", 1) then
		G.Net.toast(player, "You need a Fuel Can.", "warn")
		return
	end
	model:SetAttribute("Fuel", math.min(fuelMax, fuel + B.FuelPerCan))
	G.Net.toast(player, string.format("Boat fuel %d / %d", math.floor(model:GetAttribute("Fuel")), fuelMax), "good")
end

function Boats.cargoPayload(b)
	local list = {}
	for i = 1, B.CargoSlots do
		local s = b.cargo[i]
		if s then
			table.insert(list, { i = i, id = s.id, n = s.n })
		end
	end
	return {
		boat = b.model,
		cargo = list,
		slots = B.CargoSlots,
		fuel = b.model:GetAttribute("Fuel") or 0,
		fuelMax = b.model:GetAttribute("FuelMax") or B.FuelMax,
		health = b.model:GetAttribute("Health") or 0,
		maxHealth = B.Health,
	}
end

function Boats.openCargo(player, b)
	G.Net.open(player, "Cargo", Boats.cargoPayload(b))
end

function Boats.deposit(player, model, slot)
	local b = typeof(model) == "Instance" and boatOf(model)
	if not b or not G.Net.near(player, b.hull, 18) then
		return
	end
	local s = G.Inventory.get(player, slot)
	if not s then
		return
	end
	local def = Items.get(s.id)
	local id, n = s.id, s.n
	-- Merge into an existing stack first, then a free slot.
	local moved = 0
	for i = 1, B.CargoSlots do
		local c = b.cargo[i]
		if c and c.id == id and c.n < def.stack then
			local mv = math.min(def.stack - c.n, n - moved)
			c.n += mv
			moved += mv
		end
	end
	for i = 1, B.CargoSlots do
		if moved >= n then
			break
		end
		if not b.cargo[i] then
			local mv = math.min(def.stack, n - moved)
			b.cargo[i] = { id = id, n = mv }
			moved += mv
		end
	end
	if moved <= 0 then
		G.Net.toast(player, "Boat cargo is full.", "warn")
		return
	end
	G.Inventory.remove(player, id, moved)
	Boats.openCargo(player, b)
end

function Boats.take(player, model, index)
	local b = typeof(model) == "Instance" and boatOf(model)
	if not b or not G.Net.near(player, b.hull, 18) then
		return
	end
	local c = b.cargo[index]
	if not c then
		return
	end
	local added = G.Inventory.add(player, c.id, c.n)
	if added <= 0 then
		G.Net.toast(player, "Inventory full.", "warn")
		return
	end
	c.n -= added
	if c.n <= 0 then
		b.cargo[index] = nil
	end
	Boats.openCargo(player, b)
end

-- Damage every boat within range (Leviathan waves).
function Boats.damageNear(pos, radius, amount)
	for _, b in ipairs(Boats.list) do
		if (b.hull.Position - pos).Magnitude < radius then
			G.Repair.damage(b.model, amount)
			b.hull.AssemblyLinearVelocity += Vector3.new(0, 30, 0)
		end
	end
end

function Boats.serialize()
	local out = {}
	for i, b in ipairs(Boats.list) do
		local cargo = {}
		for idx = 1, B.CargoSlots do
			local c = b.cargo[idx]
			if c then
				table.insert(cargo, { i = idx, id = c.id, n = c.n })
			end
		end
		out[i] = { fuel = b.model:GetAttribute("Fuel"), health = b.model:GetAttribute("Health"), cargo = cargo, engine = b.engine or 1, tank = b.tank or 1 }
	end
	return out
end

Boats.pending = nil
function Boats.deserialize(data)
	Boats.pending = data
end

-- Applied after setup() because boats are only initialised once terrain exists.
function Boats.applyPending()
	local data = Boats.pending
	Boats.pending = nil
	if type(data) ~= "table" then
		return
	end
	for i, d in ipairs(data) do
		local b = Boats.list[i]
		if b and type(d) == "table" then
			local engine = type(d.engine) == "number" and math.clamp(math.floor(d.engine), 1, #ENGINE) or 1
			local tank = type(d.tank) == "number" and math.clamp(math.floor(d.tank), 1, #TANK) or 1
			Boats.applyLevels(b, engine, tank)
			if type(d.fuel) == "number" then
				b.model:SetAttribute("Fuel", math.clamp(d.fuel, 0, b.model:GetAttribute("FuelMax") or B.FuelMax))
			end
			if type(d.health) == "number" then
				G.Repair.setHealth(b.model, d.health)
			end
			if type(d.cargo) == "table" then
				for _, c in ipairs(d.cargo) do
					local def = type(c) == "table" and Items.get(c.id)
					if def and type(c.i) == "number" and c.i >= 1 and c.i <= B.CargoSlots and type(c.n) == "number" then
						b.cargo[math.floor(c.i)] = { id = c.id, n = math.clamp(math.floor(c.n), 1, def.stack) }
					end
				end
			end
		end
	end
end

function Boats.reset()
	for _, b in ipairs(Boats.list) do
		b.cargo = {}
		Boats.applyLevels(b, 1, 1)
		b.model:SetAttribute("Fuel", B.StartFuel)
		G.Repair.setHealth(b.model, B.Health)
		Boats.recall(b)
	end
end

return Boats
