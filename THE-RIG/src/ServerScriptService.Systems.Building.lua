-- ServerScriptService/Systems/Building
-- Server-confirmed building. The client only proposes (id, position, yaw); the server checks
-- tech, distance, build zone, support underneath, overlap with objects / players, limits and
-- materials, then places the structure from the shared template.
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Modules.Config)
local Buildables = require(ReplicatedStorage.Modules.Buildables)

local Building = { structures = {}, perPlayer = {} }
local G
local templates

local STEP = math.rad(15)

function Building.init(g)
	G = g
	local assets = ReplicatedStorage:WaitForChild("Assets")
	templates = assets:FindFirstChild("BuildTemplates")
	if not templates then
		templates = Instance.new("Folder")
		templates.Name = "BuildTemplates"
		templates.Parent = assets
	end
	for _, def in ipairs(Buildables.List) do
		if not templates:FindFirstChild(def.id) then
			Buildables.makeTemplate(def).Parent = templates
		end
	end

	G.Net.on("Build", function(player, id, position, yaw)
		Building.request(player, id, position, yaw)
	end, 0.35)
	G.Net.on("Demolish", function(player, target)
		Building.demolish(player, target)
	end, 0.5)
end

local function inZone(pos)
	for _, z in ipairs(Config.Build.Zones) do
		local a, b = z[1], z[2]
		if pos.X >= a.X and pos.X <= b.X and pos.Y >= a.Y and pos.Y <= b.Y and pos.Z >= a.Z and pos.Z <= b.Z then
			return true
		end
	end
	return false
end

local function isStructureSurface(inst)
	return inst:IsDescendantOf(workspace.Rig) or inst:IsDescendantOf(workspace.Map) or inst:IsDescendantOf(workspace.BuildObjects)
end

-- Shared validation. Returns ok, cframe or reason.
function Building.validate(player, def, position, yaw, root)
	if (root.Position - position).Magnitude > Config.Build.Range then
		return false, "Too far away."
	end
	if not inZone(position) then
		return false, "Outside the allowed build area (rig deck, dock, helipad)."
	end
	local size = def.size
	-- Support: something solid right under the bottom face.
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ignore = { workspace.NPCs, workspace.Interactables.Dropped, workspace.Effects }
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Character then
			table.insert(ignore, p.Character)
		end
	end
	params.FilterDescendantsInstances = ignore
	local bottom = position.Y - size.Y / 2
	local hit = workspace:Raycast(position, Vector3.new(0, -(size.Y / 2 + 1.5), 0), params)
	if not hit or not isStructureSurface(hit.Instance) or hit.Instance:IsA("Terrain") then
		return false, "Needs solid support underneath."
	end
	if math.abs(bottom - hit.Position.Y) > 1.2 then
		return false, "Needs solid support underneath."
	end
	local snapped = Vector3.new(position.X, hit.Position.Y + size.Y / 2 + 0.02, position.Z)
	local cf = CFrame.new(snapped) * CFrame.Angles(0, yaw, 0)
	-- Overlap: shrink slightly so touching neighbours / the floor is fine.
	local overlap = OverlapParams.new()
	overlap.FilterType = Enum.RaycastFilterType.Exclude
	overlap.FilterDescendantsInstances = { workspace.Interactables.Dropped, workspace.Effects }
	local parts = workspace:GetPartBoundsInBox(cf * CFrame.new(0, 0.15, 0), size - Vector3.new(0.3, 0.4, 0.3), overlap)
	for _, p in ipairs(parts) do
		local model = p:FindFirstAncestorOfClass("Model")
		if model and model:FindFirstChildOfClass("Humanoid") then
			return false, "Something is standing there."
		end
		if p.CanCollide and not p:IsA("Terrain") then
			return false, "Blocked by " .. p.Name .. "."
		end
	end
	return true, cf
end

function Building.request(player, id, position, yaw)
	local def = type(id) == "string" and Buildables.ById[id]
	if not def or not G.Net.isFiniteVector(position) or type(yaw) ~= "number" or yaw ~= yaw then
		return
	end
	local _, _, root = G.Net.alive(player)
	if not root then
		return
	end
	if def.tech and not G.PlayerData.hasTech(player, def.tech) then
		G.Net.toast(player, "Locked: research " .. def.tech .. " first.", "warn")
		return
	end
	if #Building.structures >= Config.Build.MaxTotal then
		G.Net.toast(player, "The rig can't hold more structures.", "warn")
		return
	end
	if (Building.perPlayer[player.UserId] or 0) >= Config.Build.MaxPerPlayer then
		G.Net.toast(player, "You reached your personal build limit.", "warn")
		return
	end
	yaw = math.floor(yaw / STEP + 0.5) * STEP
	local ok, result = Building.validate(player, def, position, yaw, root)
	if not ok then
		G.Net.toast(player, result, "warn")
		return
	end
	local paid, missing = G.Inventory.takeAll(player, def.cost)
	if not paid then
		G.Net.toast(player, "Missing: " .. missing, "warn")
		return
	end
	Building.place(def, result, player.UserId, def.health)
	G.PlayerData.stat(player, "Builds", 1)
	G.AI.noise(result.Position, 40)
	G.Net.toast(player, def.name .. " built.", "good")
end

function Building.place(def, cf, ownerId, health)
	local model = templates[def.id]:Clone()
	model:PivotTo(cf)
	model:SetAttribute("BuildId", def.id)
	model:SetAttribute("Owner", ownerId)
	model.Parent = workspace.BuildObjects
	CollectionService:AddTag(model, "BuildObject")
	local entry = { model = model, def = def, owner = ownerId }
	table.insert(Building.structures, entry)
	Building.perPlayer[ownerId] = (Building.perPlayer[ownerId] or 0) + 1

	G.Repair.register(model, {
		name = string.upper(def.name),
		max = def.health,
		health = math.min(health or def.health, def.health),
		cost = def.repair,
		onBroken = function()
			Building.destroy(entry, true)
		end,
	})

	if def.id == "Door" then
		local panel = model:FindFirstChild("Panel")
		local prompt = G.Util.prompt(panel, "Open", "DOOR", 0, 9)
		local open = false
		prompt.Triggered:Connect(function(p)
			if not G.Net.near(p, panel, 12) then
				return
			end
			open = not open
			panel.CanCollide = not open
			panel.Transparency = open and 0.75 or 0
			prompt.ActionText = open and "Close" or "Open"
		end)
	elseif def.id == "Floodlight" then
		entry.lamp = G.Power.registerLamp(model, false)
	elseif def.id == "RainCollector" then
		G.Industry.registerCollector(model)
	elseif def.id == "DefensePost" or def.id == "ElectricFence" then
		CollectionService:AddTag(model, def.id)
		Building.defenseOn = nil -- refresh lamps on the next step
	end
	local demolish = G.Util.prompt(model.PrimaryPart, "Demolish", string.upper(def.name), 1.5, 8)
	demolish.KeyboardKeyCode = Enum.KeyCode.X
	demolish.UIOffset = Vector2.new(0, -70)
	demolish.Triggered:Connect(function(p)
		Building.demolish(p, model)
	end)
	return entry
end

function Building.destroy(entry, byDamage)
	for i, e in ipairs(Building.structures) do
		if e == entry then
			table.remove(Building.structures, i)
			break
		end
	end
	Building.perPlayer[entry.owner] = math.max(0, (Building.perPlayer[entry.owner] or 1) - 1)
	if entry.model.Parent then
		if byDamage then
			G.Net.toastAll(entry.def.name .. " was destroyed!", "danger")
		end
		entry.model:Destroy()
	end
end

function Building.demolish(player, target)
	if typeof(target) ~= "Instance" then
		return
	end
	for _, e in ipairs(Building.structures) do
		if e.model == target then
			if not G.Net.near(player, target, 14) then
				return
			end
			if e.owner ~= player.UserId and player.UserId ~= G.State.get("HostId") then
				G.Net.toast(player, "Only the builder or the host can demolish this.", "warn")
				return
			end
			for id, n in pairs(e.def.cost) do
				local refund = math.floor(n / 2)
				if refund > 0 then
					G.Inventory.add(player, id, refund)
				end
			end
			Building.destroy(e, false)
			G.Net.toast(player, "Demolished (50 % refund).", "info")
			return
		end
	end
end

-- Defense posts and electric fences burn / shock creatures while DEFENSE is powered.
function Building.defenseAt(pos)
	if not G.Power.isPowered("Defense") then
		return nil
	end
	for _, m in ipairs(CollectionService:GetTagged("DefensePost")) do
		if m.Parent and (m:GetPivot().Position - pos).Magnitude < 18 then
			return "post"
		end
	end
	for _, m in ipairs(CollectionService:GetTagged("ElectricFence")) do
		if m.Parent and (m:GetPivot().Position - pos).Magnitude < 6 then
			return "fence"
		end
	end
	return nil
end

-- Shows / hides the lamp on defense structures.
function Building.step()
	local on = G.Power.isPowered("Defense")
	if on == Building.defenseOn then
		return
	end
	Building.defenseOn = on
	for _, tag in ipairs({ "DefensePost", "ElectricFence" }) do
		for _, m in ipairs(CollectionService:GetTagged(tag)) do
			for _, d in ipairs(m:GetDescendants()) do
				if d:IsA("Light") then
					d.Enabled = on
				elseif d:IsA("BasePart") and (d.Name == "Lamp" or d.Name == "Wire") then
					d.Material = on and Enum.Material.Neon or Enum.Material.Metal
				end
			end
		end
	end
end

function Building.serialize()
	local list = {}
	for _, e in ipairs(Building.structures) do
		local cf = e.model:GetPivot()
		local _, yaw = cf:ToEulerAnglesYXZ()
		table.insert(list, {
			id = e.def.id,
			p = { math.floor(cf.X * 100) / 100, math.floor(cf.Y * 100) / 100, math.floor(cf.Z * 100) / 100 },
			y = math.floor(yaw * 1000) / 1000,
			h = e.model:GetAttribute("Health") or e.def.health,
			o = e.owner,
		})
	end
	return list
end

function Building.deserialize(list)
	if type(list) ~= "table" then
		return
	end
	for _, s in ipairs(list) do
		local def = type(s) == "table" and Buildables.ById[s.id]
		if def and type(s.p) == "table" and #s.p == 3 then
			local cf = CFrame.new(s.p[1], s.p[2], s.p[3]) * CFrame.Angles(0, tonumber(s.y) or 0, 0)
			Building.place(def, cf, tonumber(s.o) or 0, tonumber(s.h))
		end
	end
	Building.defenseOn = nil
end

function Building.clear()
	for i = #Building.structures, 1, -1 do
		Building.destroy(Building.structures[i], false)
	end
	Building.perPlayer = {}
end

return Building
