-- ServerScriptService/Systems/Inventory
-- Server-authoritative slot inventory (24 slots, slots 1-6 are the hotbar).
-- The client only sends intents (move / use / drop / give); the server checks everything.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Modules.Config)
local Items = require(ReplicatedStorage.Modules.Items)

local Inventory = { bags = {}, offline = {} }
local SLOTS = Config.Inventory.Slots
local HOTBAR = Config.Inventory.Hotbar
local MAX_DROPPED = 60
local G

local function newBag()
	return { slots = {}, equipped = 0, dirty = true }
end

function Inventory.init(g)
	G = g
	local Net = G.Net

	Net.on("InvMove", function(player, from, to)
		if not Net.isInt(from, 1, SLOTS) or not Net.isInt(to, 1, SLOTS) or from == to then
			return
		end
		Inventory.move(player, from, to)
	end, 0.05)

	Net.on("InvUse", function(player, slot)
		if not Net.isInt(slot, 1, SLOTS) then
			return
		end
		Inventory.use(player, slot)
	end, 0.25)

	Net.on("InvDrop", function(player, slot, amount)
		if not Net.isInt(slot, 1, SLOTS) or not Net.isInt(amount, 1, 999) then
			return
		end
		Inventory.drop(player, slot, amount)
	end, 0.3)

	Net.on("InvGive", function(player, slot, targetUserId)
		if not Net.isInt(slot, 1, SLOTS) or type(targetUserId) ~= "number" then
			return
		end
		Inventory.give(player, slot, targetUserId)
	end, 0.4)

	Net.on("Hotbar", function(player, slot)
		if not Net.isInt(slot, 0, HOTBAR) then
			return
		end
		G.Equipment.select(player, slot)
	end, 0.08)

	Players.PlayerRemoving:Connect(function(player)
		local bag = Inventory.bags[player]
		if bag then
			Inventory.offline[tostring(player.UserId)] = Inventory.serialize(bag)
		end
		Inventory.bags[player] = nil
	end)

	-- Flush dirty inventories at most 10 times per second.
	task.spawn(function()
		while true do
			task.wait(0.1)
			for player, bag in pairs(Inventory.bags) do
				if bag.dirty and player.Parent then
					bag.dirty = false
					G.Net.Sync:FireClient(player, "Inventory", Inventory.payload(bag))
				end
			end
		end
	end)
end

-- Called once the world save is loaded.
function Inventory.setup(player)
	if Inventory.bags[player] then
		return
	end
	local key = tostring(player.UserId)
	local saved = Inventory.offline[key]
	Inventory.offline[key] = nil
	local bag = newBag()
	if type(saved) == "table" and type(saved.slots) == "table" then
		for _, s in ipairs(saved.slots) do
			local def = type(s) == "table" and Items.get(s.id)
			if def and type(s.i) == "number" and s.i >= 1 and s.i <= SLOTS and type(s.n) == "number" and s.n >= 1 then
				bag.slots[math.floor(s.i)] = { id = s.id, n = math.min(math.floor(s.n), def.stack) }
			end
		end

	else
		for _, entry in ipairs(Config.StarterKit) do
			Inventory.add(player, entry[1], entry[2], bag)
		end
	end
	-- Equip the starting flashlight so the first-person model is visible immediately.
	if bag.slots[1] and bag.slots[1].id == "Flashlight" then bag.equipped = 1 end
	Inventory.bags[player] = bag
	Inventory.markDirty(player)
end

function Inventory.markDirty(player)
	local bag = Inventory.bags[player]
	if bag then
		bag.dirty = true
	end
end

function Inventory.payload(bag)
	local list = {}
	for i = 1, SLOTS do
		local s = bag.slots[i]
		if s then
			table.insert(list, { i = i, id = s.id, n = s.n })
		end
	end
	return { slots = list, equipped = bag.equipped }
end

function Inventory.serialize(bag)
	local list = {}
	for i = 1, SLOTS do
		local s = bag.slots[i]
		if s then
			table.insert(list, { i = i, id = s.id, n = s.n })
		end
	end
	return { slots = list }
end

function Inventory.serializeAll()
	local all = {}
	for k, v in pairs(Inventory.offline) do
		all[k] = v
	end
	for player, bag in pairs(Inventory.bags) do
		local data = Inventory.serialize(bag)
		all[tostring(player.UserId)] = data
	end
	return all
end

function Inventory.deserializeAll(data)
	if type(data) ~= "table" then
		return
	end
	for k, v in pairs(data) do
		if type(k) == "string" and type(v) == "table" then
			Inventory.offline[k] = v
		end
	end
end

function Inventory.clearAll()
	Inventory.offline = {}
	local players = {}
	for player in pairs(Inventory.bags) do
		table.insert(players, player)
	end
	Inventory.bags = {}
	for _, player in ipairs(players) do
		Inventory.setup(player)
		G.Equipment.refresh(player)
	end
end

-- Queries --------------------------------------------------------------------
function Inventory.get(player, slot)
	local bag = Inventory.bags[player]
	return bag and bag.slots[slot]
end

function Inventory.count(player, id)
	local bag = Inventory.bags[player]
	if not bag then
		return 0
	end
	local n = 0
	for i = 1, SLOTS do
		local s = bag.slots[i]
		if s and s.id == id then
			n += s.n
		end
	end
	return n
end

function Inventory.space(player, id, bag)
	bag = bag or Inventory.bags[player]
	local def = Items.get(id)
	if not bag or not def then
		return 0
	end
	local free = 0
	for i = 1, SLOTS do
		local s = bag.slots[i]
		if not s then
			free += def.stack
		elseif s.id == id then
			free += def.stack - s.n
		end
	end
	return free
end

-- Mutations ------------------------------------------------------------------
-- Adds up to n items. Returns how many were added.
function Inventory.add(player, id, n, bagOverride)
	local bag = bagOverride or Inventory.bags[player]
	local def = Items.get(id)
	if not bag or not def or n <= 0 then
		return 0
	end
	local left = n
	for i = 1, SLOTS do
		local s = bag.slots[i]
		if s and s.id == id and s.n < def.stack then
			local mv = math.min(def.stack - s.n, left)
			s.n += mv
			left -= mv
			if left <= 0 then
				break
			end
		end
	end
	if left > 0 then
		-- Tools prefer the hotbar, resources prefer the backpack.
		local startAt = def.kind == "Tool" and 1 or HOTBAR + 1
		for pass = 1, 2 do
			local a, b = startAt, SLOTS
			if pass == 2 then
				a, b = 1, SLOTS
			end
			for i = a, b do
				if left <= 0 then
					break
				end
				if not bag.slots[i] then
					local mv = math.min(def.stack, left)
					bag.slots[i] = { id = id, n = mv }
					left -= mv
				end
			end
		end
	end
	bag.dirty = true
	if not bagOverride then
		G.Equipment.refresh(player)
	end
	return n - left
end

-- Removes exactly n items or nothing.
function Inventory.remove(player, id, n)
	local bag = Inventory.bags[player]
	if not bag or n <= 0 or Inventory.count(player, id) < n then
		return false
	end
	local left = n
	for i = SLOTS, 1, -1 do
		local s = bag.slots[i]
		if s and s.id == id then
			local mv = math.min(s.n, left)
			s.n -= mv
			left -= mv
			if s.n <= 0 then
				bag.slots[i] = nil
			end
			if left <= 0 then
				break
			end
		end
	end
	bag.dirty = true
	G.Equipment.refresh(player)
	return true
end

function Inventory.hasAll(player, cost)
	local missing = {}
	for id, n in pairs(cost) do
		local have = Inventory.count(player, id)
		if have < n then
			table.insert(missing, Items.name(id) .. " x" .. (n - have))
		end
	end
	if #missing > 0 then
		return false, table.concat(missing, ", ")
	end
	return true, ""
end

-- Atomic: checks everything first, then removes.
function Inventory.takeAll(player, cost)
	local ok, missing = Inventory.hasAll(player, cost)
	if not ok then
		return false, missing
	end
	for id, n in pairs(cost) do
		Inventory.remove(player, id, n)
	end
	return true, ""
end

function Inventory.move(player, from, to)
	local bag = Inventory.bags[player]
	if not bag then
		return
	end
	local a, b = bag.slots[from], bag.slots[to]
	if not a then
		return
	end
	if b and b.id == a.id then
		local def = Items.get(a.id)
		local mv = math.min(def.stack - b.n, a.n)
		b.n += mv
		a.n -= mv
		if a.n <= 0 then
			bag.slots[from] = nil
		end
	else
		bag.slots[from], bag.slots[to] = b, a
	end
	bag.dirty = true
	G.Equipment.refresh(player)
end

function Inventory.use(player, slot)
	local s = Inventory.get(player, slot)
	if not s then
		return
	end
	local def = Items.get(s.id)
	local _, humanoid = G.Net.alive(player)
	if not humanoid then
		return
	end
	if def.equip then
		G.Equipment.select(player, slot)
		return
	end
	local use = def.use
	if use == "Eat" then
		if G.Survival.add(player, "Hunger", 35) then
			Inventory.remove(player, s.id, 1)
		end
	elseif use == "Drink" then
		if G.Survival.add(player, "Thirst", 40) then
			Inventory.remove(player, s.id, 1)
		end
	elseif use == "Heal" then
		if humanoid.Health >= humanoid.MaxHealth then
			G.Net.toast(player, "Already at full health.", "info")
			return
		end
		Inventory.remove(player, s.id, 1)
		humanoid.Health = math.min(humanoid.MaxHealth, humanoid.Health + 45)
		G.Net.toast(player, "Medkit used  +45 HP", "good")
	elseif use == "Wear" then
		if (player:GetAttribute("Armor") or 0) >= 150 then
			G.Net.toast(player, "You are already wearing a full vest.", "info")
			return
		end
		Inventory.remove(player, s.id, 1)
		player:SetAttribute("Armor", 150)
		G.Net.toast(player, "Armor vest on (absorbs 150 damage).", "good")
	elseif s.id == "GeneratorUpgrade" then
		G.Net.toast(player, "Install it at generator E-01 (POWER panel → UPGRADE).", "info")
	elseif s.id == "RepairKit" then
		G.Net.toast(player, "Open a REPAIR prompt on damaged equipment to use the kit.", "info")
	else
		G.Net.toast(player, def.name .. ": " .. def.desc, "info")
	end
end

function Inventory.drop(player, slot, amount)
	local bag = Inventory.bags[player]
	local _, _, root = G.Net.alive(player)
	local s = bag and bag.slots[slot]
	if not s or not root then
		return
	end
	local n = math.min(amount, s.n)
	local id = s.id
	s.n -= n
	if s.n <= 0 then
		bag.slots[slot] = nil
	end
	bag.dirty = true
	G.Equipment.refresh(player)
	Inventory.spawnDrop(id, n, root.Position + root.CFrame.LookVector * 3)
end

function Inventory.spawnDrop(id, n, position)
	local def = Items.get(id)
	local folder = G.World.Dropped
	local list = folder:GetChildren()
	if #list >= MAX_DROPPED then
		list[1]:Destroy()
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { folder, workspace:FindFirstChild("NPCs") }
	local hit = workspace:Raycast(position + Vector3.new(0, 3, 0), Vector3.new(0, -40, 0), params)
	local y = hit and hit.Position.Y + 0.6 or position.Y
	local box = Instance.new("Part")
	box.Name = "Dropped_" .. id
	box.Size = Vector3.new(1.2, 1.2, 1.2)
	box.Position = Vector3.new(position.X, y, position.Z)
	box.Anchored = true
	box.CanCollide = false
	box.Color = def.color or Color3.fromRGB(200, 200, 200)
	box.Material = Enum.Material.SmoothPlastic
	box:SetAttribute("ItemId", id)
	box:SetAttribute("Count", n)
	box.Parent = folder
	local prompt = G.Util.prompt(box, "Pick up", def.name .. " x" .. n, 0, 9)
	prompt.Triggered:Connect(function(p)
		if not box.Parent or not G.Net.near(p, box, 11) then
			return
		end
		local count = box:GetAttribute("Count") or 0
		local added = Inventory.add(p, id, count)
		if added <= 0 then
			G.Net.toast(p, "Inventory full.", "warn")
			return
		end
		G.Net.toast(p, "+" .. added .. " " .. def.name, "good")
		if added >= count then
			box:Destroy()
		else
			box:SetAttribute("Count", count - added)
			prompt.ObjectText = def.name .. " x" .. (count - added)
		end
	end)
	task.delay(300, function()
		if box.Parent then
			box:Destroy()
		end
	end)
	return box
end

function Inventory.give(player, slot, targetUserId)
	local target = Players:GetPlayerByUserId(targetUserId)
	if not target or target == player then
		return
	end
	local _, _, rootA = G.Net.alive(player)
	local _, _, rootB = G.Net.alive(target)
	if not rootA or not rootB or (rootA.Position - rootB.Position).Magnitude > 14 then
		G.Net.toast(player, "Stand next to " .. target.DisplayName .. " to hand items over.", "warn")
		return
	end
	local bag = Inventory.bags[player]
	local s = bag and bag.slots[slot]
	if not s or not Inventory.bags[target] then
		return
	end
	local id, n = s.id, s.n
	local added = Inventory.add(target, id, n)
	if added <= 0 then
		G.Net.toast(player, target.DisplayName .. "'s inventory is full.", "warn")
		return
	end
	s.n -= added
	if s.n <= 0 then
		bag.slots[slot] = nil
	end
	bag.dirty = true
	G.Equipment.refresh(player)
	G.Net.toast(player, "Gave " .. added .. " " .. Items.name(id) .. " to " .. target.DisplayName, "good")
	G.Net.toast(target, player.DisplayName .. " gave you " .. added .. " " .. Items.name(id), "good")
end

return Inventory
