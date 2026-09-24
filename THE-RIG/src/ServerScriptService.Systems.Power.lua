-- ServerScriptService/Systems/Power
-- Generator E-01: fuel, health (via Repair), level upgrades, power grid with per-system
-- switches, overload warning + breaker trip, and all powered lights on the rig.
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Modules.Config)

local GEN = Config.Generator
local Power = {
	fuel = GEN.StartFuel,
	level = 1,
	grid = {},
	powered = {},
	online = false,
	tripUntil = 0,
	overload = 0,
	demand = 0,
	lamps = {},
	roomLights = {},
	machines = {},
	displayTimer = 0,
}
local G
local consumers = {}
for _, c in ipairs(Config.Consumers) do
	consumers[c.id] = c
end
Power.ConsumerById = consumers

function Power.init(g)
	G = g
	for _, c in ipairs(Config.Consumers) do
		Power.grid[c.id] = c.id == "Lights"
		Power.powered[c.id] = false
	end

	local inter = workspace:WaitForChild("Interactables")
	Power.generator = inter:WaitForChild("Generator")
	Power.core = Power.generator:FindFirstChild("Core") or Power.generator.PrimaryPart
	G.Repair.register(Power.generator, {
		name = "E-01 GENERATOR",
		max = GEN.MaxHealth,
		health = GEN.StartHealth,
		cost = GEN.RepairCost,
		promptPart = Power.core,
		onBroken = function()
			G.Net.banner("E-01 DESTROYED", "The generator is down. Repair it or the rig goes dark.", "danger")
		end,
	})
	local manage = G.Util.prompt(Power.core, "Power panel", "E-01 GENERATOR", 0, 12)
	manage.Triggered:Connect(function(p)
		if G.Net.near(p, Power.core, 16) then
			G.Net.open(p, "Power")
		end
	end)

	for _, console in ipairs(CollectionService:GetTagged("PowerConsole")) do
		local prompt = G.Util.prompt(console, "Power grid", "POWER CONSOLE", 0, 10)
		prompt.Triggered:Connect(function(p)
			if G.Net.near(p, console, 14) then
				G.Net.open(p, "Power")
			end
		end)
	end

	-- Machines that consumers depend on.
	local pump = inter:FindFirstChild("BilgePump")
	if pump then
		Power.machines.Pumps = pump
		G.Repair.register(pump, { name = "BILGE PUMP", max = 100, health = 30, cost = { ScrapMetal = 3, MechanicalParts = 2 }, heavy = true })
	end
	local sonar = inter:FindFirstChild("SonarArray")
	if sonar then
		Power.machines.Sonar = sonar
		G.Repair.register(sonar, { name = "SONAR ARRAY", max = 100, health = 20, cost = { Electronics = 3, Copper = 2 }, heavy = true })
	end

	-- Rig floodlights (Models named "Floodlight" with a "Lamp" part).
	for _, m in ipairs(workspace:GetDescendants()) do
		if m:IsA("Model") and m.Name == "Floodlight" and not m:IsDescendantOf(ReplicatedStorage) then
			Power.registerLamp(m, true)
		end
	end
	for _, p in ipairs(CollectionService:GetTagged("CeilingLight")) do
		table.insert(Power.roomLights, { part = p, light = p:FindFirstChildWhichIsA("Light"), on = nil })
	end

	Power.buildDisplay()

	G.Net.on("Grid", function(player, id, on)
		if type(id) ~= "string" or not consumers[id] or type(on) ~= "boolean" then
			return
		end
		if not Power.nearConsole(player) then
			G.Net.toast(player, "Use a POWER CONSOLE (generator room or control room) to switch systems.", "warn")
			return
		end
		Power.grid[id] = on
		local demand = Power.computeDemand()
		local cap = GEN.Levels[Power.level].capacity
		if on and demand > cap then
			G.Net.toast(player, string.format("OVERLOAD: %d / %d. Breaker trips in %d s unless you cut load.", demand, cap, GEN.OverloadGrace), "danger")
		end
		Power.publish()
	end, 0.15)

	G.Net.on("Refuel", function(player)
		Power.refuel(player)
	end, 0.4)

	G.Net.on("UpgradeGenerator", function(player)
		Power.upgrade(player)
	end, 1)
end

-- Lamps --------------------------------------------------------------------
function Power.registerLamp(model, builtin)
	local lamp = model:FindFirstChild("Lamp")
	if not lamp then
		return nil
	end
	local light = lamp:FindFirstChildWhichIsA("SpotLight") or lamp:FindFirstChildWhichIsA("Light")
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { model }
	local dir = lamp.CFrame.LookVector
	local hit = workspace:Raycast(lamp.Position, dir * 70, params)
	local target = hit and hit.Position or (lamp.Position + dir * 30)
	-- Fake volumetric cone for all clients.
	local a0 = Instance.new("Attachment")
	a0.Name = "BeamStart"
	a0.Parent = lamp
	local a1 = Instance.new("Attachment")
	a1.Name = "BeamEnd"
	a1.Parent = lamp
	a1.WorldPosition = target
	local beam = Instance.new("Beam")
	beam.Attachment0 = a0
	beam.Attachment1 = a1
	beam.Width0 = 1.5
	beam.Width1 = 10
	beam.FaceCamera = true
	beam.LightEmission = 0.25
	beam.Color = ColorSequence.new(Color3.fromRGB(255, 232, 190))
	beam.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.95), NumberSequenceKeypoint.new(1, 1) })
	beam.Segments = 1
	beam.Enabled = false
	beam.Parent = lamp
	local entry = {
		model = model,
		lamp = lamp,
		light = light,
		beam = beam,
		target = target,
		radius = 16,
		kind = "Floodlight",
		on = nil,
	}
	if builtin then
		G.Repair.register(model, {
			name = "FLOODLIGHT",
			max = 80,
			cost = { ScrapMetal = 1, Electronics = 1 },
			promptPart = model:FindFirstChild("Pole") or lamp,
		})
	end
	CollectionService:AddTag(model, "Floodlight")
	table.insert(Power.lamps, entry)
	model.Destroying:Connect(function()
		for i, e in ipairs(Power.lamps) do
			if e == entry then
				table.remove(Power.lamps, i)
				break
			end
		end
	end)
	return entry
end

function Power.lampIsLit(entry)
	return entry.on == true
end

function Power.applyLights()
	local lightsOn = Power.powered.Lights
	for _, e in ipairs(Power.lamps) do
		local on = lightsOn and (e.model:GetAttribute("Health") or 1) > 0
		if on ~= e.on then
			e.on = on
			if e.light then
				e.light.Enabled = on
			end
			e.beam.Enabled = on
			e.lamp.Material = on and Enum.Material.Neon or Enum.Material.Glass
		end
	end
	for _, r in ipairs(Power.roomLights) do
		if lightsOn ~= r.on then
			r.on = lightsOn
			if r.light then
				r.light.Enabled = lightsOn
			end
			r.part.Material = lightsOn and Enum.Material.Neon or Enum.Material.SmoothPlastic
		end
	end
end

-- Grid ---------------------------------------------------------------------
function Power.computeDemand()
	local d = 0
	for id, on in pairs(Power.grid) do
		if on then
			d += consumers[id].demand
		end
	end
	return d
end

function Power.machineOk(id)
	local m = Power.machines[id]
	return m == nil or (m:GetAttribute("Health") or 0) > 0
end

function Power.isPowered(id)
	return Power.powered[id] == true
end

function Power.nearConsole(player)
	if G.Net.near(player, Power.core, 16) then
		return true
	end
	for _, console in ipairs(CollectionService:GetTagged("PowerConsole")) do
		if G.Net.near(player, console, 14) then
			return true
		end
	end
	return false
end

function Power.trip(seconds, title, subtitle)
	Power.tripUntil = math.max(Power.tripUntil, os.clock() + seconds)
	if title then
		G.Net.banner(title, subtitle or "", "danger")
	end
	G.Net.effectAll("Blackout", seconds)
end

function Power.damage(amount)
	G.Repair.damage(Power.generator, amount)
end

function Power.refuel(player)
	if not G.Net.near(player, Power.core, 16) then
		G.Net.toast(player, "Stand next to E-01 to refuel it.", "warn")
		return
	end
	local tank = GEN.Levels[Power.level].tank
	if Power.fuel > tank - 5 then
		G.Net.toast(player, "The tank is full.", "info")
		return
	end
	if not G.Inventory.remove(player, "Fuel", 1) then
		G.Net.toast(player, "You need a Fuel Can. Search fuel drums (engine room, dock, storage).", "warn")
		return
	end
	Power.fuel = math.min(tank, Power.fuel + GEN.FuelPerCan)
	G.AI.noise(Power.core.Position, 40)
	G.Net.toast(player, string.format("E-01 refuelled  %d / %d", math.floor(Power.fuel), tank), "good")
	if G.Quests then
		G.Quests.event("Refuel", "Any", 1)
	end
	Power.publish()
end

function Power.upgrade(player)
	if not G.Net.near(player, Power.core, 16) then
		G.Net.toast(player, "Stand next to E-01 to install upgrades.", "warn")
		return
	end
	if Power.level >= #GEN.Levels then
		G.Net.toast(player, "E-01 is already at maximum level.", "info")
		return
	end
	local cost = { GeneratorUpgrade = 1 }
	if Power.level == 2 then
		if not G.PlayerData.hasTech(player, "Reactor") then
			G.Net.toast(player, "Level 3 needs the GENERATOR MK III technology (research terminal).", "warn")
			return
		end
		cost.RareMaterials = 2
	end
	local ok, missing = G.Inventory.takeAll(player, cost)
	if not ok then
		G.Net.toast(player, "Missing: " .. missing, "warn")
		return
	end
	Power.level += 1
	G.Repair.setHealth(Power.generator, GEN.MaxHealth)
	G.Net.banner("E-01 UPGRADED", string.format("Level %d: %d power, %d fuel tank.", Power.level, GEN.Levels[Power.level].capacity, GEN.Levels[Power.level].tank), "good")
	Power.publish()
end

-- Status screen on the generator, visible to everyone nearby.
function Power.buildDisplay()
	local screen = Power.generator:FindFirstChild("Display")
	if not screen then
		return
	end
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.CanvasSize = Vector2.new(400, 200)
	gui.LightInfluence = 0
	gui.Brightness = 1.5
	gui.Parent = screen
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundColor3 = Color3.fromRGB(8, 14, 12)
	label.TextColor3 = Color3.fromRGB(120, 255, 170)
	label.Font = Enum.Font.Code
	label.TextScaled = true
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Text = "E-01"
	label.Parent = gui
	Power.displayLabel = label
	Power.statusLamp = Power.generator:FindFirstChild("StatusLamp")
end

function Power.publish()
	local S = G.State
	local lv = GEN.Levels[Power.level]
	S.set("GenFuel", math.floor(Power.fuel * 10) / 10)
	S.set("GenTank", lv.tank)
	S.set("GenLevel", Power.level)
	S.set("GenHealth", Power.generator:GetAttribute("Health") or 0)
	S.set("GenOnline", Power.online)
	S.set("PowerCapacity", lv.capacity)
	S.set("PowerDemand", Power.demand)
	S.set("Overload", Power.overload > 0)
	S.set("OverloadTime", math.max(0, math.ceil(GEN.OverloadGrace - Power.overload)))
	S.set("Tripped", os.clock() < Power.tripUntil)
	for _, c in ipairs(Config.Consumers) do
		S.set("Grid_" .. c.id, Power.grid[c.id] == true)
		S.set("Pow_" .. c.id, Power.powered[c.id] == true)
		S.set("Ok_" .. c.id, Power.machineOk(c.id))
	end
end

-- 4 Hz from the main loop.
function Power.step(dt)
	local now = os.clock()
	local lv = GEN.Levels[Power.level]
	local health = Power.generator:GetAttribute("Health") or 0
	local demand = Power.computeDemand()
	local canRun = Power.fuel > 0 and health > 0 and now >= Power.tripUntil
	if canRun and demand > lv.capacity then
		Power.overload += dt
		if Power.overload >= GEN.OverloadGrace then
			Power.overload = 0
			for id in pairs(Power.grid) do
				Power.grid[id] = false
			end
			Power.trip(6, "BREAKER TRIPPED", "Grid overloaded. Every circuit was cut. Re-enable fewer systems.")
			Power.damage(8)
			canRun = false
		end
	else
		Power.overload = 0
	end
	local wasOnline = Power.online
	Power.online = canRun
	if canRun then
		local load = math.min(demand / lv.capacity, 1.5)
		Power.fuel = math.max(0, Power.fuel - (GEN.BaseBurn + GEN.LoadBurn * load) * G.Campaign.fuelMultiplier() * dt)
		if Power.fuel <= 0 then
			G.Net.banner("E-01 OUT OF FUEL", "The rig is dark. Bring Fuel Cans to the generator.", "danger")
		end
		if health < 25 and math.random() < dt * 0.03 then
			Power.trip(3, "E-01 SPUTTERING", "Generator health is critical. Repair it.")
		end
	end
	if wasOnline and not Power.online and Power.fuel > 0 and health <= 0 then
		G.Net.effectAll("Blackout", 2)
	end
	Power.demand = demand
	for id in pairs(Power.grid) do
		Power.powered[id] = canRun and Power.grid[id] and Power.machineOk(id)
	end
	Power.applyLights()
	Power.publish()

	Power.displayTimer -= dt
	if Power.displayTimer <= 0 and Power.displayLabel then
		Power.displayTimer = 1
		Power.displayLabel.Text = string.format(
			" E-01  L%d  %s\n FUEL  %3d / %d\n HP    %3d / %d\n LOAD  %3d / %d",
			Power.level,
			Power.online and "ONLINE" or "OFFLINE",
			math.floor(Power.fuel),
			lv.tank,
			math.floor(health),
			GEN.MaxHealth,
			demand,
			lv.capacity
		)
		Power.displayLabel.TextColor3 = Power.online and Color3.fromRGB(120, 255, 170) or Color3.fromRGB(255, 90, 70)
		if Power.statusLamp then
			Power.statusLamp.Color = Power.online and Color3.fromRGB(80, 255, 120) or Color3.fromRGB(255, 50, 40)
		end
	end
end

function Power.serialize()
	return {
		fuel = Power.fuel,
		level = Power.level,
		health = Power.generator:GetAttribute("Health") or GEN.StartHealth,
		grid = Power.grid,
		pump = Power.machines.Pumps and Power.machines.Pumps:GetAttribute("Health") or nil,
		sonar = Power.machines.Sonar and Power.machines.Sonar:GetAttribute("Health") or nil,
	}
end

function Power.deserialize(d)
	if type(d) ~= "table" then
		return
	end
	if type(d.level) == "number" then
		Power.level = math.clamp(math.floor(d.level), 1, #GEN.Levels)
	end
	if type(d.fuel) == "number" then
		Power.fuel = math.clamp(d.fuel, 0, GEN.Levels[Power.level].tank)
	end
	if type(d.health) == "number" then
		G.Repair.setHealth(Power.generator, d.health)
	end
	if type(d.grid) == "table" then
		for id in pairs(consumers) do
			if type(d.grid[id]) == "boolean" then
				Power.grid[id] = d.grid[id]
			end
		end
	end
	if type(d.pump) == "number" and Power.machines.Pumps then
		G.Repair.setHealth(Power.machines.Pumps, d.pump)
	end
	if type(d.sonar) == "number" and Power.machines.Sonar then
		G.Repair.setHealth(Power.machines.Sonar, d.sonar)
	end
end

function Power.reset()
	Power.fuel = GEN.StartFuel
	Power.level = 1
	Power.tripUntil = 0
	for _, c in ipairs(Config.Consumers) do
		Power.grid[c.id] = c.id == "Lights"
	end
	G.Repair.setHealth(Power.generator, GEN.StartHealth)
	if Power.machines.Pumps then
		G.Repair.setHealth(Power.machines.Pumps, 30)
	end
	if Power.machines.Sonar then
		G.Repair.setHealth(Power.machines.Sonar, 20)
	end
end

return Power
