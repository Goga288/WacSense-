-- ServerScriptService/Systems/Events
-- Random events rolled once per in-game hour. Some help, some hurt. The pool and the
-- chance grow with the day number (see Progression.profile).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Modules.Config)

local Events = { lastHour = -1, cooldown = {} }
local G

-- Offshore spots that a signal / drifting boat can point to (reachable by boat).
local SIGNAL_SPOTS = {
	Vector3.new(230, 1.5, 150),
	Vector3.new(-260, 1.5, -80),
	Vector3.new(90, 1.5, -330),
	Vector3.new(-120, 1.5, 300),
	Vector3.new(360, 1.5, -40),
}

local DEFS = {
	{ id = "POWER_FAILURE", tone = "danger", weight = 10, minDay = 2 },
	{ id = "STORM_APPROACHING", tone = "warn", weight = 8, minDay = 4, dayOnly = true },
	{ id = "UNKNOWN_SIGNAL", tone = "info", weight = 7, minDay = 3, dayOnly = true },
	{ id = "CREATURE_DETECTED", tone = "danger", weight = 9, minDay = 2, nightOnly = true },
	{ id = "GENERATOR_MALFUNCTION", tone = "danger", weight = 8, minDay = 3, malfunction = true },
	{ id = "SUPPLY_CRATE", tone = "good", weight = 9, minDay = 1, dayOnly = true },
	{ id = "BOAT_SIGNAL", tone = "good", weight = 6, minDay = 5, dayOnly = true },
	{ id = "STRUCTURAL_DAMAGE", tone = "danger", weight = 7, minDay = 4, malfunction = true },
}

function Events.init(g)
	G = g
end

local function run(id)
	local Net = G.Net
	if id == "POWER_FAILURE" then
		G.Power.trip(20, "POWER FAILURE", "A relay blew. The grid is down for 20 seconds.")
	elseif id == "STORM_APPROACHING" then
		G.Environment.forceNext("Storm")
		Net.banner("STORM APPROACHING", "Barometer is dropping. Expect lightning and blackouts tonight.", "warn")
	elseif id == "UNKNOWN_SIGNAL" then
		local spot = SIGNAL_SPOTS[math.random(1, #SIGNAL_SPOTS)]
		local cache = G.Loot.spawnContainer("Cache", CFrame.new(spot), G.World.Interactables)
		cache.Size = Vector3.new(4, 4, 4)
		Net.banner("UNKNOWN SIGNAL DETECTED", "A beacon is transmitting offshore. Take the boat.", "info")
		Net.effectAll("Ping", spot, "SIGNAL")
		task.delay(Config.DaySeconds * 1.5, function()
			if cache.Parent then
				cache:Destroy()
			end
		end)
	elseif id == "CREATURE_DETECTED" then
		Net.banner("CREATURE DETECTED", "Multiple contacts climbing the legs.", "danger")
		G.Director.spawnWave(2 + math.floor(G.DayCycle.day / 15), true)
	elseif id == "GENERATOR_MALFUNCTION" then
		G.Power.damage(25)
		Net.banner("GENERATOR MALFUNCTION", "E-01 lost 25 health. Repair it before night.", "danger")
	elseif id == "SUPPLY_CRATE" then
		local pad = workspace:FindFirstChild("HelipadDrop", true)
		local pos = pad and pad.Position or Vector3.new(58, 48, -40)
		local offset = Vector3.new(math.random(-8, 8), 2, math.random(-8, 8))
		G.Loot.spawnContainer("AirDrop", CFrame.new(pos + offset), G.World.Interactables)
		Net.banner("SUPPLY CRATE FOUND", "A drop landed on the helipad.", "good")
	elseif id == "BOAT_SIGNAL" then
		local spot = SIGNAL_SPOTS[math.random(1, #SIGNAL_SPOTS)]
		local raft = Instance.new("Part")
		raft.Name = "DriftingRaft"
		raft.Size = Vector3.new(10, 1.4, 14)
		raft.CFrame = CFrame.new(spot + Vector3.new(0, -1, 0))
		raft.Anchored = true
		raft.Color = Color3.fromRGB(230, 110, 30)
		raft.Material = Enum.Material.Fabric
		raft.Parent = G.World.Interactables
		local crate = G.Loot.spawnContainer("AirDrop", CFrame.new(spot + Vector3.new(0, 1.2, 0)), raft)
		crate.Size = Vector3.new(3, 2, 3)
		Net.banner("BOAT SIGNAL DETECTED", "A drifting lifeboat with supplies. Marked on your screen.", "good")
		Net.effectAll("Ping", spot, "LIFEBOAT")
		task.delay(Config.DaySeconds, function()
			if raft.Parent then
				raft:Destroy()
			end
		end)
	elseif id == "STRUCTURAL_DAMAGE" then
		local candidates = {}
		for _, e in ipairs(G.Power.lamps) do
			table.insert(candidates, e.model)
		end
		for _, m in pairs(G.Power.machines) do
			table.insert(candidates, m)
		end
		for _, d in pairs(G.Doors.list) do
			table.insert(candidates, d.model)
		end
		G.Util.shuffle(candidates)
		local names = {}
		for i = 1, math.min(2, #candidates) do
			G.Repair.damage(candidates[i], 45)
			table.insert(names, candidates[i]:GetAttribute("DisplayName") or candidates[i].Name)
		end
		G.Net.effectAll("Shake", 0.5, 1.5)
		Net.banner("STRUCTURAL DAMAGE", "Damaged: " .. table.concat(names, ", "), "danger")
	end
end

function Events.random(force)
	local day = G.DayCycle.day
	local phase = G.DayCycle.phase
	local profile = G.Director.profile
	local weights = {}
	local now = os.clock()
	for _, d in ipairs(DEFS) do
		local ok = day >= d.minDay or force
		if d.dayOnly and phase == "Night" then
			ok = false
		end
		if d.nightOnly and phase ~= "Night" then
			ok = false
		end
		if (Events.cooldown[d.id] or 0) > now and not force then
			ok = false
		end
		if ok then
			weights[d.id] = d.weight * (d.malfunction and profile.malfunctionBias or 1)
		end
	end
	local id = G.Util.weighted(weights)
	if not id then
		return
	end
	Events.cooldown[id] = now + Config.DaySeconds * 0.6
	local ok, err = pcall(run, id)
	if not ok then
		warn("[Events] " .. id .. " failed: " .. tostring(err))
	end
end

function Events.step()
	if not G.DayCycle.running then
		return
	end
	local hour = math.floor(G.DayCycle.hour())
	if hour == Events.lastHour then
		return
	end
	Events.lastHour = hour
	-- Guaranteed early help so new crews are not stranded.
	if G.DayCycle.day == 2 and hour == 10 then
		pcall(run, "SUPPLY_CRATE")
		return
	end
	if math.random() < G.Director.profile.eventChance then
		Events.random(false)
	end
end

return Events
