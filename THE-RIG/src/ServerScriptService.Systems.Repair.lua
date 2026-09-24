-- ServerScriptService/Systems/Repair
-- Generic breakable / repairable equipment. Any Model or BasePart registered here gets
-- Health / MaxHealth attributes (replicated) and a "Repair" prompt while damaged.
-- Cost scales with missing health: full cost when at 0, at least 1 of each material.
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Items = require(ReplicatedStorage.Modules.Items)

local Repair = { entries = {} }
local G

function Repair.init(g)
	G = g
	G.Net.on("Repair", function(player, inst, useKit)
		if typeof(inst) ~= "Instance" then
			return
		end
		Repair.request(player, inst, useKit == true)
	end, 0.4)
	G.Net.on("InspectRepair", function(player, inst)
		if typeof(inst) == "Instance" then
			Repair.inspect(player, inst)
		end
	end, 0.3)
end

local function promptPartOf(inst, explicit)
	if explicit then
		return explicit
	end
	if inst:IsA("BasePart") then
		return inst
	end
	return inst.PrimaryPart or inst:FindFirstChildWhichIsA("BasePart", true)
end

-- opt = {name, max, health, cost = {id = n}, heavy, promptPart, onBroken, onRepaired, onChanged, prompt = false}
function Repair.register(inst, opt)
	local e = {
		inst = inst,
		name = opt.name,
		max = opt.max,
		cost = opt.cost,
		heavy = opt.heavy == true,
		onBroken = opt.onBroken,
		onRepaired = opt.onRepaired,
		onChanged = opt.onChanged,
		part = promptPartOf(inst, opt.promptPart),
	}
	inst:SetAttribute("MaxHealth", opt.max)
	inst:SetAttribute("Health", opt.health or opt.max)
	inst:SetAttribute("DisplayName", opt.name)
	CollectionService:AddTag(inst, "Repairable")
	if e.part and opt.prompt ~= false then
		local prompt = G.Util.prompt(e.part, "Repair", opt.name, 0.3, 11)
		prompt.Name = "RepairPrompt"
		prompt.KeyboardKeyCode = Enum.KeyCode.R
		prompt.GamepadKeyCode = Enum.KeyCode.ButtonY
		prompt.UIOffset = Vector2.new(0, 70)
		prompt.Triggered:Connect(function(p)
			Repair.inspect(p, inst)
		end)
		e.prompt = prompt
	end
	Repair.entries[inst] = e
	inst.Destroying:Connect(function()
		Repair.entries[inst] = nil
	end)
	Repair.refresh(e)
	return e
end

function Repair.entryOf(inst)
	-- Walks up the hierarchy so a hit on any part finds its repairable owner.
	local cur = inst
	while cur and cur ~= workspace do
		local e = Repair.entries[cur]
		if e then
			return e
		end
		cur = cur.Parent
	end
	return nil
end

function Repair.refresh(e)
	local h = e.inst:GetAttribute("Health") or 0
	if e.prompt then
		e.prompt.Enabled = h < e.max
		e.prompt.ObjectText = string.format("%s  %d/%d", e.name, math.floor(h), e.max)
	end
	if e.onChanged then
		e.onChanged(h, e.max)
	end
end

function Repair.costFor(e)
	local h = e.inst:GetAttribute("Health") or 0
	local missing = math.clamp((e.max - h) / e.max, 0, 1)
	local cost = {}
	for id, n in pairs(e.cost) do
		cost[id] = math.max(1, math.ceil(n * missing))
	end
	return cost
end

function Repair.health(inst)
	return inst:GetAttribute("Health") or 0
end

function Repair.setHealth(inst, value)
	local e = Repair.entries[inst]
	if not e then
		return
	end
	local old = inst:GetAttribute("Health") or 0
	local h = math.clamp(value, 0, e.max)
	inst:SetAttribute("Health", math.floor(h * 10 + 0.5) / 10)
	if h <= 0 and old > 0 and e.onBroken then
		task.spawn(e.onBroken)
	elseif h > 0 and old <= 0 and e.onRepaired then
		task.spawn(e.onRepaired)
	end
	Repair.refresh(e)
end

function Repair.damage(inst, amount)
	local e = Repair.entries[inst]
	if not e then
		return
	end
	Repair.setHealth(inst, (inst:GetAttribute("Health") or 0) - amount)
end

function Repair.inspect(player, inst)
	local e = Repair.entries[inst]
	if not e or not G.Net.near(player, e.part, 16) then
		return
	end
	local cost = Repair.costFor(e)
	local have = {}
	for id in pairs(cost) do
		have[id] = G.Inventory.count(player, id)
	end
	G.Net.open(player, "Repair", {
		target = inst,
		name = e.name,
		health = inst:GetAttribute("Health") or 0,
		max = e.max,
		cost = cost,
		have = have,
		kits = G.Inventory.count(player, "RepairKit"),
		heavy = e.heavy,
		hasToolkit = G.Inventory.count(player, "Toolkit") > 0,
	})
end

function Repair.request(player, inst, useKit)
	local e = Repair.entries[inst]
	if not e then
		return
	end
	if not G.Net.near(player, e.part, 16) then
		G.Net.toast(player, "Move closer to " .. e.name .. ".", "warn")
		return
	end
	local h = inst:GetAttribute("Health") or 0
	if h >= e.max then
		G.Net.toast(player, e.name .. " is already at full health.", "info")
		return
	end
	if e.heavy and G.Inventory.count(player, "Toolkit") < 1 then
		G.Net.toast(player, "Heavy machinery: you need a Toolkit (craft at the bench).", "warn")
		return
	end
	if useKit then
		if not G.Inventory.remove(player, "RepairKit", 1) then
			G.Net.toast(player, "You have no Repair Kit.", "warn")
			return
		end
		Repair.setHealth(inst, h + 50)
	else
		local ok, missing = G.Inventory.takeAll(player, Repair.costFor(e))
		if not ok then
			G.Net.toast(player, "Missing: " .. missing, "warn")
			return
		end
		Repair.setHealth(inst, e.max)
	end
	if e.part then
		G.AI.noise(e.part.Position, 45)
	end
	G.PlayerData.stat(player, "Repairs", 1)
	if G.Quests then
		G.Quests.event("Repair", "Any", 1)
	end
	G.PlayerData.addCredits(player, 2)
	local nh = inst:GetAttribute("Health") or 0
	G.Net.toast(player, string.format("%s repaired  %d / %d", e.name, math.floor(nh), e.max), "good")
	for _, other in ipairs(game:GetService("Players"):GetPlayers()) do
		if other ~= player then
			G.Net.toast(other, player.DisplayName .. " repaired " .. e.name, "info")
		end
	end
	Repair.inspect(player, inst)
end

Repair.costText = Items.costText

return Repair
