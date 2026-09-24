-- ReplicatedStorage/Modules/Recipes
-- Crafting recipes (Crafting Bench) and research technologies (Control Room terminal).
local Recipes = {}

Recipes.List = {
	{ id = "Flashlight", out = "Flashlight", count = 1, cost = { Plastic = 2, Electronics = 1, Copper = 1 } },
	{ id = "Medkit", out = "Medkit", count = 1, cost = { Chemicals = 2, Plastic = 1 } },
	{ id = "Crowbar", out = "Crowbar", count = 1, cost = { ScrapMetal = 3 } },
	{ id = "Flare", out = "Flare", count = 2, cost = { Chemicals = 1, Plastic = 1 } },
	{ id = "Toolkit", out = "Toolkit", count = 1, cost = { ScrapMetal = 3, MechanicalParts = 2 } },
	{ id = "RepairKit", out = "RepairKit", count = 1, cost = { ScrapMetal = 3, MechanicalParts = 1, Electronics = 1 } },
	{ id = "OxygenTank", out = "OxygenTank", count = 1, cost = { ScrapMetal = 2, Plastic = 2, MechanicalParts = 1 } },
	{ id = "DivingGear", out = "DivingGear", count = 1, cost = { Plastic = 4, Chemicals = 2, MechanicalParts = 2, OxygenTank = 1 }, tech = "Diving" },
	{ id = "ArmorVest", out = "ArmorVest", count = 1, cost = { ScrapMetal = 4, Plastic = 3, Chemicals = 1 }, tech = "Armor" },
	{ id = "FishingRod", out = "FishingRod", count = 1, cost = { Plastic = 2, Copper = 1, ScrapMetal = 1 } },
	{ id = "GeneratorUpgrade", out = "GeneratorUpgrade", count = 1, cost = { ScrapMetal = 6, Electronics = 3, Copper = 4, MechanicalParts = 2 } },
}

Recipes.Tech = {
	{ id = "Diving", name = "DIVING EQUIPMENT", cost = { Electronics = 3, Plastic = 2 }, desc = "Unlocks Diving Gear at the Crafting Bench." },
	{ id = "Armor", name = "PROTECTIVE GEAR", cost = { Electronics = 2, Chemicals = 3 }, desc = "Unlocks the Armor Vest." },
	{ id = "Defense", name = "PERIMETER DEFENSE", cost = { Electronics = 4, Copper = 4 }, desc = "Unlocks Defense Post and Electric Fence builds." },
	{ id = "DeepSonar", name = "DEEP SONAR", cost = { Electronics = 3, RareMaterials = 2 }, desc = "Sonar reports bearing and range of large contacts." },
	{ id = "Reactor", name = "GENERATOR MK III", cost = { Electronics = 4, RareMaterials = 3 }, desc = "Allows upgrading E-01 to level 3." },
}

Recipes.ById = {}
for _, r in ipairs(Recipes.List) do
	Recipes.ById[r.id] = r
end
Recipes.TechById = {}
for _, t in ipairs(Recipes.Tech) do
	Recipes.TechById[t.id] = t
end

return Recipes
