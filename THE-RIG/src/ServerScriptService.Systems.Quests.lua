-- ServerScriptService/Systems/Quests
-- Crew TASKS: three shared jobs are always active next to the story chapter. They give the
-- day a purpose (go out, scavenge, fight, fix, explore) and pay credits plus supplies to
-- everyone. A finished task is replaced a few seconds later. Night tasks are judged at dawn.
-- Progress arrives through Quests.event(kind, key, amount) from the other systems.
local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Items = require(ReplicatedStorage.Modules.Items)
local Expeditions = require(ReplicatedStorage.Modules.Expeditions)

local Quests = { active = {}, done = 0, nightLights = true, nightDeaths = 0, dirty = true, refill = 0 }
local G

local SLOTS = 3
local TEMPLATES = {
	{ id = "Scavenge", text = "Pick up %d loose items", event = "Scavenge", key = "Any", min = 6, max = 10, credits = 8, item = "Flare", n = 1 },
	{ id = "Scrap", text = "Collect %d Scrap Metal", event = "Gather", key = "ScrapMetal", min = 8, max = 14, credits = 6, item = "Medkit", n = 1 },
	{ id = "Copper", text = "Collect %d Copper Wire", event = "Gather", key = "Copper", min = 4, max = 8, credits = 6, item = "Fuel", n = 1 },
	{ id = "Electronics", text = "Collect %d Electronics", event = "Gather", key = "Electronics", min = 3, max = 5, credits = 8, item = "Flare", n = 2 },
	{ id = "Food", text = "Stock up %d Canned Food", event = "Gather", key = "Food", min = 3, max = 5, credits = 5, item = "Water", n = 2 },
	{ id = "FuelRun", text = "Find %d Fuel Cans", event = "Gather", key = "Fuel", min = 2, max = 4, credits = 8, item = "Flare", n = 2 },
	{ id = "Refuel", text = "Pour %d Fuel Cans into E-01", event = "Refuel", key = "Any", min = 2, max = 3, credits = 8, item = "Flare", n = 2 },
	{ id = "Hunt", text = "Kill %d Climbers", event = "Kill", key = "Climber", min = 2, max = 5, credits = 14, item = "ArmorVest", n = 1 },
	{ id = "Repair", text = "Make %d repairs", event = "Repair", key = "Any", min = 2, max = 4, credits = 6, item = "RepairKit", n = 1 },
	{ id = "Craft", text = "Craft %d items at a bench", event = "Craft", key = "Any", min = 2, max = 3, credits = 6, item = "Electronics", n = 2 },
	{ id = "Logs", text = "Find and read %d new logs", event = "Log", key = "Any", min = 1, max = 2, credits = 10, item = "Medkit", n = 1 },
	{ id = "Visit", text = "Reach %s", event = "Visit", key = "Any", min = 1, max = 1, credits = 16, item = "Fuel", n = 2 },
	{ id = "Lights", text = "Keep LIGHTS powered through the whole night", event = "NightLights", key = "Any", min = 1, max = 1, credits = 10, item = "Flare", n = 2 },
	{ id = "Clean", text = "Survive a night with no crew deaths", event = "CleanNight", key = "Any", min = 1, max = 1, credits = 12, item = "Medkit", n = 1 },
}

function Quests.init(g)
	G = g
	G.DayCycle.on("Phase", function(phase)
		if phase == "Night" then
			Quests.nightLights = true
			Quests.nightDeaths = 0
		end
	end)
	G.DayCycle.on("Dawn", function()
		if Quests.nightLights then
			Quests.event("NightLights", "Any", 1)
		end
		if Quests.nightDeaths == 0 and #G.Util.alivePlayers() > 0 then
			Quests.event("CleanNight", "Any", 1)
		end
	end)
	for _ = 1, SLOTS do
		Quests.add()
	end
end

local function has(id)
	for _, q in ipairs(Quests.active) do
		if q.id == id then
			return true
		end
	end
	return false
end

local function pickDestination()
	local day = G.DayCycle.day or 1
	local list = {}
	for i, d in ipairs(Expeditions.Destinations) do
		local dist = Vector3.new(d.position.X, 0, d.position.Z).Magnitude
		if i > 1 and (day >= 8 or dist < 1700) then
			table.insert(list, d)
		end
	end
	return #list > 0 and list[math.random(1, #list)] or nil
end

function Quests.add()
	local pool = {}
	for _, t in ipairs(TEMPLATES) do
		if not has(t.id) then
			table.insert(pool, t)
		end
	end
	if #pool == 0 then
		return
	end
	local t = pool[math.random(1, #pool)]
	local q = { id = t.id, event = t.event, key = t.key, progress = 0, goal = math.random(t.min, t.max), credits = t.credits, item = t.item, n = t.n }
	if t.event == "Visit" then
		local dest = pickDestination()
		if not dest then
			Quests.add()
			return
		end
		q.text = string.format(t.text, dest.name)
		q.position = dest.position
	else
		q.text = string.format(t.text, q.goal)
	end
	table.insert(Quests.active, q)
	Quests.dirty = true
end

local function complete(q)
	Quests.done += 1
	for _, p in ipairs(Players:GetPlayers()) do
		G.PlayerData.addCredits(p, q.credits)
		if q.item then
			G.Inventory.add(p, q.item, q.n or 1)
		end
		G.PlayerData.push(p)
	end
	G.Net.banner("TASK COMPLETE", string.format("%s — +%d credits%s", q.text, q.credits, q.item and (", +" .. (q.n or 1) .. " " .. Items.name(q.item)) or ""), "good")
	Quests.refill += 1
end

function Quests.event(kind, key, amount)
	if kind == "Death" then
		Quests.nightDeaths += 1
		return
	end
	for i = #Quests.active, 1, -1 do
		local q = Quests.active[i]
		if q.event == kind and (q.key == "Any" or q.key == key) then
			q.progress = math.min(q.goal, q.progress + (amount or 1))
			Quests.dirty = true
			if q.progress >= q.goal then
				table.remove(Quests.active, i)
				complete(q)
			end
		end
	end
end

function Quests.publish()
	local list = {}
	for _, q in ipairs(Quests.active) do
		table.insert(list, { t = q.text, p = q.progress, g = q.goal })
	end
	G.State.set("Quests", HttpService:JSONEncode(list))
	G.State.set("TasksDone", Quests.done)
end

local refillTimer = 0
-- 4 Hz from the main loop.
function Quests.step(dt)
	if G.DayCycle.phase == "Night" and not G.Power.isPowered("Lights") then
		Quests.nightLights = false
	end
	local reached = false
	for _, q in ipairs(Quests.active) do
		if q.position then
			for _, info in ipairs(G.Util.alivePlayers()) do
				local d = info.root.Position - q.position
				if Vector3.new(d.X, 0, d.Z).Magnitude < 60 then
					reached = true
				end
			end
		end
	end
	if reached then
		Quests.event("Visit", "Any", 1)
	end
	if Quests.refill > 0 then
		refillTimer += dt
		if refillTimer > 5 then
			refillTimer = 0
			Quests.refill -= 1
			Quests.add()
		end
	end
	if Quests.dirty then
		Quests.dirty = false
		Quests.publish()
	end
end

return Quests
