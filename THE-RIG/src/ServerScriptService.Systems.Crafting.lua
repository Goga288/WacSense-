-- ServerScriptService/Systems/Crafting
-- Crafting at Crafting Benches and research at the Control Room terminal.
-- The server checks: recipe exists, tech unlocked, player next to a bench, materials, space.
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Recipes = require(ReplicatedStorage.Modules.Recipes)
local Items = require(ReplicatedStorage.Modules.Items)

local Crafting = {}
local G

local function benchPart(bench)
	if bench:IsA("BasePart") then
		return bench
	end
	return bench.PrimaryPart or bench:FindFirstChildWhichIsA("BasePart", true)
end

function Crafting.init(g)
	G = g
	for _, bench in ipairs(CollectionService:GetTagged("CraftingBench")) do
		local part = benchPart(bench)
		if part then
			local prompt = G.Util.prompt(part, "Craft", "CRAFTING BENCH", 0, 10)
			prompt.Triggered:Connect(function(player)
				if G.Net.near(player, part, 14) then
					G.Net.open(player, "Craft")
				end
			end)
		end
	end
	local terminal = workspace.Interactables:FindFirstChild("ResearchTerminal", true)
	Crafting.terminal = terminal
	if terminal then
		local prompt = G.Util.prompt(terminal, "Research", "RESEARCH TERMINAL", 0, 10)
		prompt.Triggered:Connect(function(player)
			if G.Net.near(player, terminal, 14) then
				G.Net.open(player, "Research")
			end
		end)
	end

	G.Net.on("Craft", function(player, recipeId)
		Crafting.craft(player, recipeId)
	end, 0.3)
	G.Net.on("Research", function(player, techId)
		Crafting.research(player, techId)
	end, 0.5)
end

function Crafting.nearBench(player)
	for _, bench in ipairs(CollectionService:GetTagged("CraftingBench")) do
		local part = benchPart(bench)
		if part and G.Net.near(player, part, 14) then
			return true
		end
	end
	return false
end

function Crafting.craft(player, recipeId)
	local recipe = type(recipeId) == "string" and Recipes.ById[recipeId]
	if not recipe then
		return
	end
	if not Crafting.nearBench(player) then
		G.Net.toast(player, "You need to stand at a Crafting Bench (Workshop / Living Quarters).", "warn")
		return
	end
	if recipe.tech and not G.PlayerData.hasTech(player, recipe.tech) then
		G.Net.toast(player, "Locked: research " .. recipe.tech .. " at the Control Room terminal.", "warn")
		return
	end
	if G.Inventory.space(player, recipe.out) < recipe.count then
		G.Net.toast(player, "Not enough inventory space.", "warn")
		return
	end
	local ok, missing = G.Inventory.takeAll(player, recipe.cost)
	if not ok then
		G.Net.toast(player, "Missing: " .. missing, "warn")
		return
	end
	G.Inventory.add(player, recipe.out, recipe.count)
	if G.Quests then
		G.Quests.event("Craft", "Any", 1)
	end
	G.AI.noise(G.Net.posOf(player.Character) or Vector3.zero, 30)
	G.Net.toast(player, "Crafted " .. Items.name(recipe.out) .. (recipe.count > 1 and (" x" .. recipe.count) or ""), "good")
end

function Crafting.research(player, techId)
	local tech = type(techId) == "string" and Recipes.TechById[techId]
	if not tech then
		return
	end
	if not Crafting.terminal or not G.Net.near(player, Crafting.terminal, 14) then
		G.Net.toast(player, "Use the research terminal in the Control Room.", "warn")
		return
	end
	if G.PlayerData.hasTech(player, techId) then
		G.Net.toast(player, "Already researched.", "info")
		return
	end
	local ok, missing = G.Inventory.takeAll(player, tech.cost)
	if not ok then
		G.Net.toast(player, "Missing: " .. missing, "warn")
		return
	end
	-- Co-op: research is shared with everyone on the server and saved to each profile.
	for _, p in ipairs(Players:GetPlayers()) do
		G.PlayerData.unlockTech(p, techId)
	end
	G.Net.banner("RESEARCH COMPLETE", tech.name .. " — " .. tech.desc, "good")
end

return Crafting
