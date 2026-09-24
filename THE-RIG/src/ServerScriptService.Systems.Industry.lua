-- ServerScriptService/Systems/Industry
-- Renewable resources that make long runs possible on the huge map:
--   * Crude Extractor (south-west deck): with PUMPS powered it refines 1 Fuel Can per minute.
--   * Fishing spots: with a Fishing Rod, hold to fish for food. At night something else bites.
--   * Rain Collectors (buildable): fill Water Bottles while it rains.
-- Everything is server-side; prompts only start requests.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Items = require(ReplicatedStorage.Modules.Items)

local Industry = { collectors = {}, fishers = {} }
local G

local EXTRACT_TIME = 60
local EXTRACT_MAX = 6
local COLLECT_TIME = 40
local COLLECT_MAX = 4
local FISH_COOLDOWN = 5
local RAINY = { Rain = true, HeavyRain = true, Thunderstorm = true, Storm = true }

function Industry.init(g)
	G = g
	local extractor = workspace.Interactables:FindFirstChild("CrudeExtractor", true)
	if extractor and extractor:IsA("Model") then
		Industry.extractor = extractor
		Industry.progress = 0
		extractor:SetAttribute("Stored", 0)
		G.Repair.register(extractor, {
			name = "CRUDE EXTRACTOR",
			max = 100,
			health = 40,
			cost = { MechanicalParts = 3, ScrapMetal = 4 },
			heavy = true,
		})
		local prompt = G.Util.prompt(extractor.PrimaryPart, "Collect fuel", "CRUDE EXTRACTOR", 0.8, 10)
		Industry.extractorPrompt = prompt
		prompt.Triggered:Connect(function(player)
			Industry.collectFuel(player)
		end)
	end
	for _, spot in ipairs(workspace:GetDescendants()) do
		if spot:IsA("BasePart") and spot.Name == "FishingSpot" then
			local prompt = G.Util.prompt(spot, "Fish", "FISHING SPOT", 3, 10)
			prompt.Triggered:Connect(function(player)
				Industry.fish(player, spot)
			end)
		end
	end
	Players.PlayerRemoving:Connect(function(p)
		Industry.fishers[p] = nil
	end)
end

-- Extractor ------------------------------------------------------------------
function Industry.collectFuel(player)
	local ex = Industry.extractor
	if not ex or not G.Net.near(player, ex.PrimaryPart, 14) then
		return
	end
	local stored = ex:GetAttribute("Stored") or 0
	if stored <= 0 then
		G.Net.toast(player, "Nothing refined yet. The extractor needs PUMPS power and repairs (Toolkit).", "warn")
		return
	end
	local added = G.Inventory.add(player, "Fuel", stored)
	if added <= 0 then
		G.Net.toast(player, "Inventory full.", "warn")
		return
	end
	ex:SetAttribute("Stored", stored - added)
	G.Net.toast(player, "+" .. added .. " Fuel Can", "good")
	G.AI.noise(ex.PrimaryPart.Position, 40)
end

-- Fishing --------------------------------------------------------------------
local CATCH = {
	{ id = "Food", n = 1, weight = 55, text = "A cod. Dinner." },
	{ id = "Food", n = 2, weight = 10, text = "A big halibut!" },
	{ id = "ScrapMetal", n = 2, weight = 10, text = "Old junk off the seabed." },
	{ id = "Chemicals", n = 1, weight = 5, text = "A sealed canister of reagent." },
	{ id = "RareMaterials", n = 1, weight = 3, text = "A glowing shard tangled in the line." },
	{ weight = 17, text = "Nothing bites." },
}

function Industry.fish(player, spot)
	if not G.Net.near(player, spot, 12) then
		return
	end
	if G.Inventory.count(player, "FishingRod") < 1 then
		G.Net.toast(player, "You need a Fishing Rod (Crafting Bench).", "warn")
		return
	end
	local now = os.clock()
	if (Industry.fishers[player] or 0) > now then
		return
	end
	Industry.fishers[player] = now + FISH_COOLDOWN
	G.AI.noise(spot.Position, 25)
	-- At night the water is not empty.
	if G.DayCycle.isNight() and math.random() < 0.18 then
		G.Net.banner("SOMETHING PULLS BACK", "The line snaps. Something is climbing up after it.", "danger")
		G.Net.Effect:FireClient(player, "Shake", 0.5, 1)
		local best, bestD
		for _, cf in ipairs(G.World.climbPoints) do
			local d = (cf.Position - spot.Position).Magnitude
			if not bestD or d < bestD then
				best, bestD = cf, d
			end
		end
		if best and bestD < 200 then
			G.AI.Climber.spawn({ point = best })
		end
		return
	end
	local total = 0
	for _, c in ipairs(CATCH) do
		total += c.weight
	end
	local r = math.random() * total
	for _, c in ipairs(CATCH) do
		r -= c.weight
		if r <= 0 then
			if c.id then
				local added = G.Inventory.add(player, c.id, c.n)
				G.Net.toast(player, c.text .. (added > 0 and ("  +" .. added .. " " .. Items.name(c.id)) or "  (inventory full)"), added > 0 and "good" or "warn")
			else
				G.Net.toast(player, c.text, "info")
			end
			return
		end
	end
end

-- Rain collectors ---------------------------------------------------------------
function Industry.registerCollector(model)
	local entry = { model = model, progress = 0 }
	model:SetAttribute("Stored", 0)
	local prompt = G.Util.prompt(model.PrimaryPart, "Take water", "RAIN COLLECTOR 0/" .. COLLECT_MAX, 0.5, 9)
	entry.prompt = prompt
	prompt.Triggered:Connect(function(player)
		if not model.Parent or not G.Net.near(player, model.PrimaryPart, 12) then
			return
		end
		local stored = model:GetAttribute("Stored") or 0
		if stored <= 0 then
			G.Net.toast(player, "Empty. It fills while it rains.", "info")
			return
		end
		local added = G.Inventory.add(player, "Water", stored)
		model:SetAttribute("Stored", stored - added)
		prompt.ObjectText = string.format("RAIN COLLECTOR %d/%d", stored - added, COLLECT_MAX)
		if added > 0 then
			G.Net.toast(player, "+" .. added .. " Water Bottle", "good")
		end
	end)
	table.insert(Industry.collectors, entry)
end

-- 4 Hz from the main loop.
function Industry.step(dt)
	local ex = Industry.extractor
	if ex and ex.Parent then
		local stored = ex:GetAttribute("Stored") or 0
		local working = (ex:GetAttribute("Health") or 0) > 0 and G.Power.isPowered("Pumps") and stored < EXTRACT_MAX
		if working then
			Industry.progress += dt
			if Industry.progress >= EXTRACT_TIME then
				Industry.progress = 0
				stored += 1
				ex:SetAttribute("Stored", stored)
			end
		end
		ex:SetAttribute("Working", working)
		Industry.extractorPrompt.ObjectText = string.format("CRUDE EXTRACTOR  %d/%d  %s", stored, EXTRACT_MAX,
			working and string.format("refining %d%%", math.floor(Industry.progress / EXTRACT_TIME * 100)) or "idle (PUMPS + repair)")
		G.State.set("ExtractorStored", stored)
	end
	local raining = RAINY[G.Environment.weather] == true
	for i = #Industry.collectors, 1, -1 do
		local c = Industry.collectors[i]
		if not c.model.Parent then
			table.remove(Industry.collectors, i)
		elseif raining then
			local stored = c.model:GetAttribute("Stored") or 0
			if stored < COLLECT_MAX then
				c.progress += dt
				if c.progress >= COLLECT_TIME then
					c.progress = 0
					c.model:SetAttribute("Stored", stored + 1)
					c.prompt.ObjectText = string.format("RAIN COLLECTOR %d/%d", stored + 1, COLLECT_MAX)
				end
			end
		end
	end
end

function Industry.serialize()
	return { stored = Industry.extractor and Industry.extractor:GetAttribute("Stored") or 0 }
end

function Industry.deserialize(d)
	if type(d) == "table" and type(d.stored) == "number" and Industry.extractor then
		Industry.extractor:SetAttribute("Stored", math.clamp(math.floor(d.stored), 0, EXTRACT_MAX))
	end
end

return Industry
