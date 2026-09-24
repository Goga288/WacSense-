-- ServerScriptService/Main (Script)
-- Bootstraps every server system in dependency order, then runs the fixed-rate loops.
-- Systems talk to each other through the shared registry table G.
local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Modules.Config)

local Systems = ServerScriptService:WaitForChild("Systems")
local AIFolder = ServerScriptService:WaitForChild("AI")
local Data = ServerScriptService:WaitForChild("Data")

Players.RespawnTime = Config.Player.RespawnTime

local G = {}
local ORDER = {
	{ "Net", Systems.Net },
	{ "State", Systems.State },
	{ "Util", Systems.Util },
	{ "PlayerData", Data.PlayerData },
	{ "WorldSave", Data.WorldSave },
	{ "World", Systems.World },
	{ "Inventory", Systems.Inventory },
	{ "Equipment", Systems.Equipment },
	{ "Survival", Systems.Survival },
	{ "Repair", Systems.Repair },
	{ "DayCycle", Systems.DayCycle },
	{ "Environment", Systems.Environment },
	{ "Power", Systems.Power },
	{ "Doors", Systems.Doors },
	{ "Loot", Systems.Loot },
	{ "Carry", Systems.Carry },
	{ "Crafting", Systems.Crafting },
	{ "Stations", Systems.Stations },
	{ "Building", Systems.Building },
	{ "Boats", Systems.Boats },
	{ "Industry", Systems.Industry },
	{ "AI", AIFolder.AIService },
	{ "Director", Systems.Director },
	{ "Events", Systems.Events },
	{ "Campaign", Systems.Campaign },
	{ "Scatter", Systems.Scatter },
	{ "Quests", Systems.Quests },
	{ "Appearance", Systems.Appearance },
	{ "Grounder", Systems.Grounder },
	{ "Donate", Systems.Donate },
}

for _, entry in ipairs(ORDER) do
	G[entry[1]] = require(entry[2])
end
for _, entry in ipairs(ORDER) do
	local ok, err = pcall(G[entry[1]].init, G)
	if not ok then
		warn(string.format("[Main] %s.init failed: %s", entry[1], tostring(err)))
	end
end
G.State.set("Ready", false)
G.State.set("Version", Config.Version)

-- Players -------------------------------------------------------------------
local worldReady = false

local function onCharacter(player, character)
	task.spawn(G.Survival.onCharacter, player, character)
	task.spawn(G.Equipment.onCharacter, player, character)
	task.spawn(function()
		character:WaitForChild("HumanoidRootPart", 10)
		G.PlayerData.applySuit(player)
	end)
end

local function onPlayer(player)
	player.CharacterAdded:Connect(function(character)
		onCharacter(player, character)
	end)
	if player.Character then
		onCharacter(player, player.Character)
	end
	task.spawn(function()
		G.PlayerData.load(player)
		G.PlayerData.applySuit(player)
	end)
	task.spawn(function()
		while not worldReady do
			task.wait(0.2)
		end
		if player.Parent then
			G.Inventory.setup(player)
			G.Equipment.refresh(player)
		end
	end)
end

Players.PlayerAdded:Connect(onPlayer)
for _, p in ipairs(Players:GetPlayers()) do
	task.spawn(onPlayer, p)
end

-- World startup ---------------------------------------------------------------
local ok, err = pcall(G.World.buildTerrain)
if not ok then
	warn("[Main] Terrain build failed: " .. tostring(err))
end
ok, err = pcall(G.Grounder.run)
if not ok then
	warn("[Main] Grounder failed: " .. tostring(err))
end
ok, err = pcall(G.Loot.settle)
if not ok then
	warn("[Main] Loot settle failed: " .. tostring(err))
end
ok, err = pcall(G.Boats.setup)
if not ok then
	warn("[Main] Boat setup failed: " .. tostring(err))
end

local host = Players:GetPlayers()[1] or Players.PlayerAdded:Wait()
local saved = G.WorldSave.load(host)
G.WorldSave.apply(saved)
G.Boats.applyPending()
G.Doors.applyTerrain()
G.WorldSave.bindToClose()
G.Director.refreshProfile()
G.Net.on("ClientReady", function(player)
	G.Inventory.markDirty(player)
	G.PlayerData.push(player)
	-- First visit: the story intro.
	task.spawn(function()
		for _ = 1, 40 do
			if G.PlayerData.profiles[player] then
				break
			end
			task.wait(0.25)
		end
		if player.Parent and G.PlayerData.unlock(player, "intro") then
			G.Net.Notify:FireClient(player, "Intro")
		end
	end)
end, 2)
worldReady = true
G.State.set("Ready", true)
G.DayCycle.start()

task.delay(3, function()
	if saved then
		G.Net.banner("WORLD RESTORED", string.format("DAY %d / %d — host: %s", G.DayCycle.day, Config.MaxDays, host.DisplayName), "info")
	else
		G.Net.banner("DAY 1 / 100", "KESTREL-9 is dark. Restore generator E-01 before nightfall.", "info")
	end
end)

-- Loops ---------------------------------------------------------------------
local STEPS = {
	{ "DayCycle", G.DayCycle.step },
	{ "Environment", G.Environment.step },
	{ "Power", G.Power.step },
	{ "Survival", G.Survival.step },
	{ "Doors", G.Doors.step },
	{ "Building", G.Building.step },
	{ "Director", G.Director.step },
	{ "Events", G.Events.step },
	{ "Campaign", G.Campaign.step },
	{ "Industry", G.Industry.step },
	{ "Scatter", G.Scatter.step },
	{ "Quests", G.Quests.step },
}
local failures = {}

task.spawn(function()
	local last = os.clock()
	while true do
		task.wait(0.25)
		local now = os.clock()
		local dt = math.min(now - last, 1)
		last = now
		for _, s in ipairs(STEPS) do
			local okStep, errStep = pcall(s[2], dt)
			if not okStep then
				failures[s[1]] = (failures[s[1]] or 0) + 1
				if failures[s[1]] <= 3 then
					warn(string.format("[Main] %s.step failed: %s", s[1], tostring(errStep)))
				end
			end
		end
	end
end)

task.spawn(function()
	local last = os.clock()
	while true do
		task.wait(0.2)
		local now = os.clock()
		local dt = math.min(now - last, 1)
		last = now
		local okAI, errAI = pcall(G.AI.step, dt)
		if not okAI then
			failures.AI = (failures.AI or 0) + 1
			if failures.AI <= 3 then
				warn("[Main] AI.step failed: " .. tostring(errAI))
			end
		end
	end
end)
