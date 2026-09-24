-- ReplicatedStorage/Modules/Items
-- Item definitions shared by server (authority) and client (display only).
local Items = {}
Items.Defs = {}
Items.Order = {}

local function def(id, t)
	t.id = id
	t.kind = t.kind or "Resource"
	t.stack = t.stack or 20
	t.name = t.name or id
	t.short = t.short or string.upper(string.sub(id, 1, 4))
	t.desc = t.desc or ""
	Items.Defs[id] = t
	table.insert(Items.Order, id)
end

-- Resources
def("ScrapMetal", { name = "Scrap Metal", short = "SCRAP", stack = 40, color = Color3.fromRGB(128, 140, 148), desc = "Bent plating and bolts. Used for repairs and building." })
def("Electronics", { name = "Electronics", short = "ELEC", stack = 20, color = Color3.fromRGB(86, 170, 120), desc = "Circuit boards pulled from panels." })
def("Plastic", { name = "Plastic", short = "PLAS", stack = 30, color = Color3.fromRGB(200, 196, 176), desc = "Casings, crates and pipes." })
def("Copper", { name = "Copper Wire", short = "CU", stack = 30, color = Color3.fromRGB(196, 120, 64), desc = "Stripped cable. Needed for power equipment." })
def("Fuel", { name = "Fuel Can", short = "FUEL", stack = 10, color = Color3.fromRGB(222, 164, 48), desc = "Diesel. Feeds E-01 (+25) or a boat (+30)." })
def("Chemicals", { name = "Chemicals", short = "CHEM", stack = 20, color = Color3.fromRGB(150, 110, 190), desc = "Solvents and reagents." })
def("MechanicalParts", { name = "Mechanical Parts", short = "MECH", stack = 20, color = Color3.fromRGB(160, 150, 112), desc = "Gears, bearings, valves." })
def("Food", { name = "Canned Food", short = "FOOD", kind = "Consumable", stack = 10, use = "Eat", color = Color3.fromRGB(190, 90, 70), desc = "Restores 35 hunger." })
def("Water", { name = "Water Bottle", short = "H2O", kind = "Consumable", stack = 10, use = "Drink", color = Color3.fromRGB(80, 150, 210), desc = "Restores 40 thirst." })
def("RareMaterials", { name = "Rare Materials", short = "RARE", stack = 10, color = Color3.fromRGB(90, 230, 220), desc = "Strange crystalline growth from the deep." })

-- Tools / gear
def("Flashlight", { name = "Flashlight", short = "TORCH", kind = "Tool", stack = 1, equip = "Flashlight", color = Color3.fromRGB(240, 220, 150), desc = "Carried in your LEFT hand. F toggles it, hold right mouse (FOCUS) for a hot narrow beam that burns Climbers. Never runs out." })
def("Crowbar", { name = "Crowbar", short = "BAR", kind = "Tool", stack = 1, equip = "Crowbar", color = Color3.fromRGB(200, 60, 50), desc = "Melee weapon. Also pries jammed doors." })
def("Flare", { name = "Flare", short = "FLARE", kind = "Tool", stack = 10, equip = "Flare", color = Color3.fromRGB(255, 80, 60), desc = "Equip and click to throw. Bright light repels Climbers for 30 s." })
def("Medkit", { name = "Medkit", short = "MED", kind = "Consumable", stack = 5, use = "Heal", color = Color3.fromRGB(230, 230, 230), desc = "Restores 45 health." })
def("Toolkit", { name = "Toolkit", short = "TOOLS", kind = "Gear", stack = 1, color = Color3.fromRGB(210, 150, 60), desc = "Required to repair heavy machinery (pump, sonar)." })
def("RepairKit", { name = "Repair Kit", short = "RKIT", kind = "Consumable", stack = 5, color = Color3.fromRGB(230, 180, 70), desc = "Restores 50 health to any equipment without materials." })
def("OxygenTank", { name = "Oxygen Tank", short = "O2", kind = "Gear", stack = 3, color = Color3.fromRGB(120, 190, 230), desc = "Carried: oxygen lasts 2x longer, safe to depth -50." })
def("DivingGear", { name = "Diving Gear", short = "DIVE", kind = "Gear", stack = 1, color = Color3.fromRGB(60, 200, 190), desc = "Carried: oxygen lasts 3x longer, faster swimming, safe to -100." })
def("ArmorVest", { name = "Armor Vest", short = "VEST", kind = "Consumable", stack = 2, use = "Wear", color = Color3.fromRGB(90, 100, 80), desc = "Wear: absorbs 30 % of damage (150 points)." })
def("FishingRod", { name = "Fishing Rod", short = "ROD", kind = "Gear", stack = 1, color = Color3.fromRGB(150, 120, 70), desc = "Carried: fish at FISHING SPOTS (dock, south-west deck, relay buoys). At night something else may bite." })
def("GeneratorUpgrade", { name = "Generator Upgrade", short = "UPGR", kind = "Part", stack = 2, color = Color3.fromRGB(255, 170, 40), desc = "Install at E-01 via the POWER panel: more capacity and a bigger tank." })

function Items.get(id)
	if type(id) ~= "string" then
		return nil
	end
	return Items.Defs[id]
end

function Items.name(id)
	local d = Items.get(id)
	return d and d.name or tostring(id)
end

-- "Scrap Metal x4, Electronics x2"
function Items.costText(cost)
	local parts = {}
	for _, id in ipairs(Items.Order) do
		local n = cost[id]
		if n and n > 0 then
			table.insert(parts, Items.name(id) .. " x" .. n)
		end
	end
	return table.concat(parts, ", ")
end

return Items
