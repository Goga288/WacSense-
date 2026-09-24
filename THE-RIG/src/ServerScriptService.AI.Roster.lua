-- ServerScriptService/AI/Roster
-- THE NIGHT ROSTER (0.15). The creature models placed in the map become the creatures of
-- the night, in tiers (see Config.Tiers and Modules/MonsterRigs):
--   D1  every night, 2 different kinds
--   D2  often but not every night, 1-2 kinds (random)
--   D3  rare, 1 kind a night
--   Boss  recognised but not spawned yet
-- plus the Peeker, which has its own brain (AI/Peeker).
--
-- At server start every tier model is taken out of Workspace (the file keeps them where
-- they were placed) and given a body that can walk: an invisible HumanoidRootPart at its
-- feet with a Humanoid, and the skinned mesh welded on top, facing the way the creature
-- faces. The mesh itself never collides, so a giant still fits through a door; its bones
-- are animated on each client (Client/MonsterAnim).
--
-- The Climber brain drives them: Climber.spawn asks Roster.pick for tonight's kind, and
-- the kind's tier and the night decide how clever it is (Roster.brainFor).
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Modules.Config)
local MonsterRigs = require(ReplicatedStorage.Modules.MonsterRigs)

local Roster = { kinds = {}, byTier = { D1 = {}, D2 = {}, D3 = {}, Boss = {}, Peeker = {} }, night = nil }
local G, AI
local TIERS = { "D1", "D2", "D3" }

local function storage()
	local root = ServerStorage:FindFirstChild("MonsterTemplates")
	if not root then
		root = Instance.new("Folder")
		root.Name = "MonsterTemplates"
		root.Parent = ServerStorage
	end
	for _, name in ipairs({ "Placed", "Built" }) do
		if not root:FindFirstChild(name) then
			local f = Instance.new("Folder")
			f.Name = name
			f.Parent = root
		end
	end
	return root
end

-- Gives a placed model a body that can walk. Returns the new template and its measurements.
local function assemble(original, tier)
	local model = original:Clone()
	local mesh, boneCount = MonsterRigs.meshOf(model)
	if not mesh or boneCount == 0 then
		model:Destroy()
		return nil
	end
	local spec = MonsterRigs.spec(mesh.Name)
	local scale = Config.Tiers.Scale or 1
	if scale ~= 1 then
		pcall(function()
			model:ScaleTo(model:GetScale() * scale)
		end)
	end
	-- Import leftovers: the default animator must never touch the bones, and the saved
	-- poses are only for re-importing.
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("AnimationController") or d:IsA("Animator") or d:IsA("Humanoid")
			or (d:IsA("Folder") and d.Name == "InitialPoses") or (d:IsA("ObjectValue") and d.Name == "AnimSaves")
			or d:IsA("Script") or d:IsA("LocalScript") then
			d:Destroy()
		end
	end
	-- The body frame: where its back (up) and its face (forward) point in the world.
	local rot = mesh.CFrame.Rotation
	local up = rot:VectorToWorldSpace(spec.up).Unit
	local fwd = rot:VectorToWorldSpace(spec.forward)
	fwd = fwd - up * fwd:Dot(up)
	if fwd.Magnitude < 0.01 then
		fwd = rot:VectorToWorldSpace(Vector3.new(0, 0, -1))
		fwd = fwd - up * fwd:Dot(up)
	end
	fwd = fwd.Unit
	local right = fwd:Cross(up).Unit
	local body = CFrame.fromMatrix(Vector3.zero, right, up)
	-- Its box, in body axes, measured from the mesh centre.
	local half = mesh.Size / 2
	local lo = Vector3.new(math.huge, math.huge, math.huge)
	local hi = -lo
	for _, sx in ipairs({ -1, 1 }) do
		for _, sy in ipairs({ -1, 1 }) do
			for _, sz in ipairs({ -1, 1 }) do
				local world = rot:VectorToWorldSpace(Vector3.new(sx * half.X, sy * half.Y, sz * half.Z))
				local c = body:VectorToObjectSpace(world)
				lo = lo:Min(c)
				hi = hi:Max(c)
			end
		end
	end
	local size = hi - lo
	local height = size.Y
	local core = math.min(size.X, size.Z)
	local rw = math.clamp(core * 0.45, 1.6, 4)
	local rh = math.clamp(height * 0.3, 2, 5)
	local hip = math.clamp(height * 0.12, 0.6, 2.2)
	local feetWorld = mesh.Position + body:VectorToWorldSpace(Vector3.new((lo.X + hi.X) / 2, lo.Y, (lo.Z + hi.Z) / 2))

	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = Vector3.new(rw, rh, rw)
	root.CFrame = CFrame.new(feetWorld + up * (hip + rh / 2)) * body
	root.Transparency = 1
	root.CanCollide = true
	root.CanTouch = true
	root.CanQuery = true
	root.Anchored = false
	root.Parent = model
	model.PrimaryPart = root
	for _, p in ipairs(model:GetDescendants()) do
		if p:IsA("BasePart") and p ~= root then
			p.Anchored = false
			p.CanCollide = false
			p.CanTouch = false
			p.CanQuery = false
			p.Massless = true
			local w = Instance.new("Weld")
			w.Name = "BodyWeld"
			w.Part0 = root
			w.Part1 = p
			w.C0 = root.CFrame:ToObjectSpace(p.CFrame)
			w.Parent = p
		end
	end
	local hum = Instance.new("Humanoid")
	hum.RigType = Enum.HumanoidRigType.R15
	hum.HipHeight = hip
	hum.RequiresNeck = false
	hum.BreakJointsOnDeath = false
	hum.MaxSlopeAngle = 70
	hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	hum.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	hum.Parent = model
	pcall(function()
		model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	end)
	model.Name = spec.name
	model:SetAttribute("Tier", tier)
	model:SetAttribute("MeshName", mesh.Name)
	model:SetAttribute("Height", height)
	model:SetAttribute("Gait", spec.gait or "biped")
	model:SetAttribute("AnimScale", model:GetScale())
	return model, { height = height, width = size.X, depth = size.Z, rw = rw, rh = rh, hip = hip, mesh = mesh.Name, spec = spec }
end

function Roster.init(g, ai)
	G = g
	AI = ai
	local folder = storage()
	local found = {}
	for _, source in ipairs({ workspace, folder.Placed }) do
		for _, m in ipairs(source:GetChildren()) do
			if m:IsA("Model") and not m:GetAttribute("RosterIgnore") then
				local tier = MonsterRigs.tierOf(m)
				if tier then
					table.insert(found, { model = m, tier = tier })
				end
			end
		end
	end
	local used = {}
	for _, f in ipairs(found) do
		-- The placed model leaves the map (the saved place is untouched).
		f.model.Parent = folder.Placed
		local ok, template, info = pcall(assemble, f.model, f.tier)
		if not ok then
			warn("[Roster] could not build " .. f.model.Name .. ": " .. tostring(template))
		elseif template then
			local id = info.mesh
			local n = 1
			while used[id] do
				n += 1
				id = info.mesh .. "_" .. n
			end
			used[id] = true
			template:SetAttribute("Kind", id)
			template.Parent = folder.Built
			local kind = { id = id, tier = f.tier, template = template, info = info, name = info.spec.name }
			Roster.kinds[id] = kind
			table.insert(Roster.byTier[f.tier], kind)
		end
	end
	local counts = {}
	for tier, list in pairs(Roster.byTier) do
		if #list > 0 then
			table.insert(counts, tier .. "=" .. #list)
		end
	end
	print("[Roster] creature kinds: " .. (#counts > 0 and table.concat(counts, ", ") or "none"))
end

-- Is there anything of the tiers to spawn at all?
function Roster.hasKinds()
	return #Roster.byTier.D1 + #Roster.byTier.D2 + #Roster.byTier.D3 > 0
end

function Roster.kind(id)
	return Roster.kinds[id]
end

-- How clever a creature of `tier` is on `day` (1 stupid .. 4 relentless).
function Roster.brainFor(tier, day)
	local T = Config.Tiers[tier]
	local level = 1
	for _, m in ipairs(T and T.minds or { { 1, 2 } }) do
		if day >= m[1] then
			level = m[2]
		end
	end
	return math.clamp(level, 1, 4)
end

local function shuffled(list)
	local copy = table.clone(list)
	for i = #copy, 2, -1 do
		local j = math.random(1, i)
		copy[i], copy[j] = copy[j], copy[i]
	end
	return copy
end

-- Tonight's kinds. Rolled once per night (evening scouts already come from it).
function Roster.roll(day, force)
	if Roster.night and Roster.night.day == day and not force then
		return Roster.night
	end
	local night = { day = day, kinds = {}, tiers = {} }
	for _, tier in ipairs(TIERS) do
		local T = Config.Tiers[tier]
		local pool = Roster.byTier[tier]
		if T and T.spawn ~= false and #pool > 0 then
			local chance = math.min((T.chance or 1) + (T.grow or 0) * (day - 1), T.maxChance or 1)
			if day >= Config.MaxDays then
				chance = 1
			end
			if math.random() < chance then
				local want = math.random(T.kinds[1], T.kinds[2])
				for i, kind in ipairs(shuffled(pool)) do
					if i > want then
						break
					end
					table.insert(night.kinds, kind)
					night.tiers[tier] = (night.tiers[tier] or 0) + 1
				end
			end
		end
	end
	Roster.night = night
	local names = {}
	for _, k in ipairs(night.kinds) do
		table.insert(names, k.tier .. ":" .. k.name)
	end
	print(string.format("[Roster] night %d: %s", day, #names > 0 and table.concat(names, ", ") or "nothing"))
	return night
end

function Roster.clear()
	Roster.night = nil
end

-- Most of a tier allowed on the map at once, tonight.
local function aliveCap(tier, day)
	local T = Config.Tiers[tier]
	if not T or not T.alive then
		return math.huge
	end
	return T.alive + math.floor(day / (T.aliveGrowth or 1000))
end

-- The kind for the next spawn: one of tonight's, weighted by tier, never over a tier's cap.
-- `tier` forces a tier (DEV panel).
function Roster.pick(day, alive, tier)
	if tier then
		local pool = Roster.byTier[tier]
		return #pool > 0 and pool[math.random(1, #pool)] or nil
	end
	local night = Roster.roll(day)
	local total, options = 0, {}
	for _, kind in ipairs(night.kinds) do
		if (alive[kind.tier] or 0) < aliveCap(kind.tier, day) then
			local w = Config.Tiers[kind.tier].weight or 1
			total += w
			table.insert(options, { kind = kind, w = w })
		end
	end
	if total <= 0 then
		return nil
	end
	local roll = math.random() * total
	for _, o in ipairs(options) do
		roll -= o.w
		if roll <= 0 then
			return o.kind
		end
	end
	return options[#options].kind
end

-- The Peeker's body (the first Peeker model placed), or nil.
function Roster.peeker()
	return Roster.byTier.Peeker[1]
end

return Roster
