-- ServerScriptService/Systems/Director
-- Runs the 100-day loop: night spawning, waves, creature rolls, dawn rewards, radio,
-- current objective, day-100 finale and victory. Also hosts the Studio-only test commands.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Modules.Config)
local Progression = require(ReplicatedStorage.Modules.Progression)
local Story = require(ReplicatedStorage.Modules.Story)
local Items = require(ReplicatedStorage.Modules.Items)

local Director = {
	profile = Progression.profile(1),
	nightCrew = {},
	nextSpawn = 0,
	waves = {},
	leviathanHour = nil,
	objectiveTimer = 0,
	hunterTimers = {},
	scoutTimer = 0,
}
local G

function Director.init(g)
	G = g
	G.DayCycle.on("Phase", Director.onPhase)
	G.DayCycle.on("Dawn", Director.onDawn)
	if RunService:IsStudio() and Config.StudioTools then
		G.State.set("StudioTools", true)
		G.Net.on("Test", Director.test, 0.3)
	end
end

function Director.refreshProfile()
	Director.profile = Progression.profile(G.DayCycle.day)
	local phase = Progression.phase(G.DayCycle.day)
	G.State.set("PhaseTitle", phase.title)
end

function Director.onPhase(phase, day)
	Director.refreshProfile()
	local p = Director.profile
	if phase == "Evening" or phase == "Night" then
		if math.random() < p.silhouetteChance * (phase == "Evening" and 0.5 or 1) then
			G.AI.Silhouette.summon()
		end
	end
	if phase == "Evening" then
		G.Net.banner("EVENING", "Three hours to nightfall. Refuel E-01, close the doors, power the lights.", "warn")
		if math.random() < p.watcherChance * 0.5 then
			G.AI.Watcher.appear()
		end
		for _ = 1, p.mimicMax do
			if math.random() < p.mimicChance * 0.5 and G.AI.Mimic.count() < p.mimicMax then
				task.spawn(G.AI.Mimic.spawn) -- builds a character model, may yield
			end
		end
	elseif phase == "Night" then
		Director.nightCrew = {}
		for _, info in ipairs(G.Util.alivePlayers()) do
			Director.nightCrew[info.player] = true
		end
		Director.nextSpawn = os.clock() + 4
		Director.waves = { [23] = p.climberWaves, [3] = p.climberWaves }
		Director.leviathanHour = (math.random() < p.leviathanChance) and (p.final and 2 or math.random(22, 27) % 24) or nil
		local title = p.final and "THE FINAL NIGHT" or ("NIGHT " .. day)
		local sub = p.final and "Everything is coming up. Survive until dawn." or "Movement in the water. Stay near powered floodlights — and never stay in one place for long."
		G.Net.banner(title, sub, "danger")
		if math.random() < p.watcherChance then
			G.AI.Watcher.appear()
		end
		for _ = 1, p.mimicMax do
			if math.random() < p.mimicChance and G.AI.Mimic.count() < p.mimicMax then
				task.spawn(G.AI.Mimic.spawn) -- builds a character model, may yield
			end
		end
	end
	Director.objectiveDirty()
end

function Director.onDeath(player)
	Director.nightCrew[player] = nil
	if G.Quests and G.DayCycle.phase == "Night" then
		G.Quests.event("Death", "Any", 1)
	end
end

function Director.reachedDeep(player)
	G.PlayerData.unlock(player, "deep_dive")
end

function Director.onDawn(day)
	G.AI.clearNight()
	-- Everyone who was there at nightfall and never died survived the night.
	local survivors = {}
	for player in pairs(Director.nightCrew) do
		if player.Parent then
			table.insert(survivors, player)
			G.PlayerData.stat(player, "Nights", 1)
			G.PlayerData.addCredits(player, 10 + math.floor(day / 5))
			G.PlayerData.award(player, "FIRST_NIGHT")
		end
	end
	Director.nightCrew = {}
	for _, player in ipairs(Players:GetPlayers()) do
		G.PlayerData.setBest(player, "BestDay", day)
		if day >= 10 then
			G.PlayerData.award(player, "DAY_10")
		end
		if day >= 25 then
			G.PlayerData.award(player, "DAY_25")
		end
		if day >= 50 then
			G.PlayerData.award(player, "DAY_50")
		end
		G.PlayerData.push(player)
	end

	if day > Config.MaxDays and not G.State.get("Completed") then
		Director.victory()
	else
		Director.refreshProfile()
		local phase = Progression.phase(day)
		local sub = phase.goal
		if #survivors > 0 then
			sub = #survivors .. " survived the night. " .. sub
		end
		G.Net.banner(string.format("DAY %d / %d", day, Config.MaxDays), phase.title .. " — " .. sub, "good")
		if Story.Radio[day] then
			task.delay(6, function()
				G.Net.banner("RADIO", Story.Radio[day], "info")
			end)
		end
	end
	task.spawn(G.WorldSave.save, "dawn")
end

function Director.victory()
	G.State.set("Completed", true)
	for _, player in ipairs(Players:GetPlayers()) do
		G.PlayerData.award(player, "DAY_100")
		G.Net.Notify:FireClient(player, "Victory", {
			day = G.DayCycle.day - 1,
			credits = player:GetAttribute("Credits") or 0,
			evidence = G.Campaign.completed >= 7,
		})
	end
	G.Net.banner("RESCUE HAS ARRIVED", "The Aldmere is at the rig. You survived 100 days on KESTREL-9.", "good")
end

function Director.spawnWave(n, flank, force)
	local p = Director.profile
	for i = 1, n do
		task.delay(i * 0.8, function()
			if G.AI.Climber.count() < p.climberMax + 6 then
				G.AI.Climber.spawn({ flank = flank or p.flankers, force = force, role = (p.saboteurs and math.random() < G.AI.saboteurChance(0.3)) and "Saboteur" or nil })
			end
		end)
	end
end

function Director.objectiveDirty()
	Director.objectiveTimer = 0
end

function Director.computeObjective()
	local S = G.State
	local hp = S.get("GenHealth") or 0
	local fuel = S.get("GenFuel") or 0
	local tank = S.get("GenTank") or 100
	local phase = G.DayCycle.phase
	if G.Campaign.transmitting then return G.Campaign.objective() end
	local doors = G.Doors.list
	if hp <= 0 then
		return "REPAIR E-01 — the generator is destroyed (Scrap Metal + Electronics)"
	end
	if fuel <= 0 then
		return "REFUEL E-01 — search fuel drums for Fuel Cans"
	end
	if phase == "Night" then
		if G.AI.Watcher.position() then
			return "SURVIVE until 06:00 — the Watcher reacts to the floodlights"
		end
		return "SURVIVE until 06:00 — stay near powered floodlights"
	end
	if phase == "Evening" then
		return "PREPARE — refuel E-01, close doors, power LIGHTS"
	end
	if hp < 60 then
		return "REPAIR E-01 — " .. Items.costText(G.Repair.costFor(G.Repair.entries[G.Power.generator]))
	end
	if fuel < tank * 0.35 then
		return "FUEL — collect Fuel Cans and refuel E-01"
	end
	local story = G.Campaign.objective()
	if story then return story end
	local function locked(name)
		return doors[name] and not doors[name].unlocked
	end
	if locked("Door_EngineRoom") then
		return "EXPLORE — switch DOORS power on and unlock the ENGINE ROOM"
	end
	if locked("Door_Storage") then
		return "EXPLORE — pry open STORAGE with a Crowbar"
	end
	if locked("Door_Control") then
		return "EXPLORE — bypass the CONTROL ROOM lock (Electronics + Copper)"
	end
	local pump = G.Power.machines.Pumps
	if pump and (pump:GetAttribute("Health") or 0) < 100 then
		return "REPAIR the BILGE PUMP (needs a Toolkit)"
	end
	if not G.Doors.drained then
		return "Power PUMPS to drain the flooded maintenance level"
	end
	if locked("Door_Medical") then
		return "EXPLORE — bypass the MEDICAL ROOM lock"
	end
	if (S.get("GenLevel") or 1) < 2 then
		return "UPGRADE E-01 — craft a Generator Upgrade at the bench"
	end
	return Progression.phase(G.DayCycle.day).goal
end

-- 4 Hz from the main loop.
function Director.step(dt)
	Director.objectiveTimer -= dt
	if Director.objectiveTimer <= 0 then
		Director.objectiveTimer = 1
		G.State.set("Objective", Director.computeObjective())
	end
	local p = Director.profile
	local now = os.clock()
	-- Evening scouts: a Climber may come up early to probe the rig.
	if G.DayCycle.phase == "Evening" and p.scouts then
		Director.scoutTimer -= dt
		if Director.scoutTimer <= 0 then
			Director.scoutTimer = math.random(45, 75)
			if math.random() < 0.55 and G.AI.Climber.count() < 1 + math.floor(G.DayCycle.day / 8) then
				G.AI.Climber.spawn({ flank = true })
			end
		end
	end
	if G.DayCycle.phase ~= "Night" then
		return
	end
	Director.huntStep(dt, p)
	if now >= Director.nextSpawn then
		Director.nextSpawn = now + p.climberInterval * G.Campaign.threatMultiplier()
		if G.AI.Climber.count() < p.climberMax then
			G.AI.Climber.spawn({ flank = p.flankers, role = (p.saboteurs and math.random() < G.AI.saboteurChance(0.3)) and "Saboteur" or nil })
		end
	end
	local hour = math.floor(G.DayCycle.hour())
	if Director.waves[hour] then
		Director.waves[hour] = false
		G.Net.banner("WAVE INCOMING", "Many shapes are climbing the legs.", "danger")
		Director.spawnWave(p.waveSize)
	end
	if Director.leviathanHour and hour == Director.leviathanHour then
		Director.leviathanHour = nil
		G.AI.Leviathan.trigger(true)
	end
end

-- Nowhere is safe at night. Players far from the rig (islands, wrecks, ships, jetties) get
-- Climbers rising out of the water or the sand next to them; players who sit still (SCENT)
-- get hunters sent straight to them.
function Director.huntStep(dt, p)
	if not p.hunters then
		return
	end
	local extra = 1 + math.floor(G.DayCycle.day / 12)
	for _, info in ipairs(G.Util.alivePlayers()) do
		local pos = info.root.Position
		local key = info.player
		Director.hunterTimers[key] = (Director.hunterTimers[key] or 8) - dt
		if Director.hunterTimers[key] <= 0 then
			local seat = info.humanoid.SeatPart
			local swimming = pos.Y < Config.WaterLevel + 1.5 or info.player:GetAttribute("InWater") == true
			local offRig = not G.Util.onRig(pos)
			local scented = G.AI.isScented(info.player)
			local near = G.AI.Climber.countNear(pos, scented and 90 or 130)
			Director.hunterTimers[key] = scented and 18 or p.climberInterval * 1.4
			if not seat and not swimming and (offRig or scented) and near < (scented and 2 or extra) and G.AI.Climber.count() < p.climberMax + 6 then
				local unit = G.AI.Climber.spawn({ near = pos, role = nil })
				if unit and scented then
					G.Net.toast(info.player, "Something is climbing towards you.", "danger")
				end
			end
		end
	end
	for player in pairs(Director.hunterTimers) do
		if not player.Parent then
			Director.hunterTimers[player] = nil
		end
	end
end

function Director.resetRun()
	G.AI.Climber.clear()
	G.AI.Mimic.clear()
	G.Scatter.clear()
	G.AI.Watcher.leave()
	G.State.set("Completed", false)
	G.Campaign.reset()
	G.Power.reset()
	G.Doors.reset()
	G.Building.clear()
	G.Inventory.clearAll()
	G.Boats.reset()
	G.DayCycle.setDay(1)
	G.DayCycle.start()
	Director.refreshProfile()
end

-- Studio-only test commands (DEV panel).
function Director.test(player, what)
	if not RunService:IsStudio() then
		return
	end
	if what == "Night" then
		G.DayCycle.setHour(21)
	elseif what == "Evening" then
		G.DayCycle.setHour(18)
	elseif what == "Dawn" then
		G.DayCycle.setHour(5.92)
	elseif what == "Climber" then
		G.AI.Climber.spawn({ flank = true, force = true })
	elseif what == "Wave" then
		Director.spawnWave(4, true, true)
	elseif what == "Watcher" then
		G.AI.Watcher.appear(true)
	elseif what == "Mimic" then
		task.spawn(G.AI.Mimic.spawn, true) -- builds a character model, may yield
	elseif what == "Lurker" then
		local _, _, root = G.Net.alive(player)
		if root then
			G.AI.Lurker.spawn({ kind = "swimmer", pos = root.Position, force = true })
			G.Net.toast(player, "DEV: a Lurker is hunting in the water near you. Jump in.", "info")
		end
	elseif what == "Silhouette" then
		G.AI.Silhouette.summon(true)
	elseif what == "Leviathan" then
		G.AI.Leviathan.trigger(false)
	elseif what == "Storm" then
		G.Environment.set("Storm")
	elseif what == "Clear" then
		G.Environment.set("Clear")
	elseif what == "Event" then
		G.Events.random(true)
	elseif what == "Supplies" then
		for _, id in ipairs({ "ScrapMetal", "Electronics", "Plastic", "Copper", "Fuel", "Chemicals", "MechanicalParts", "RareMaterials" }) do
			G.Inventory.add(player, id, 8)
		end
		G.Inventory.add(player, "Toolkit", 1)
	elseif what == "SkipDays" then
		G.DayCycle.setDay(G.DayCycle.day + 10)
		Director.refreshProfile()
		G.Net.toastAll("DEV: jumped to day " .. G.DayCycle.day, "info")
	elseif what == "DamageGen" then
		G.Power.damage(30)
	elseif what == "Tech" then
		for _, t in ipairs({ "Diving", "Armor", "Defense", "DeepSonar", "Reactor" }) do
			G.PlayerData.unlockTech(player, t)
		end
	end
end

return Director
