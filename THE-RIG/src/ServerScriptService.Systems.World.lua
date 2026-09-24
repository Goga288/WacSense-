-- ServerScriptService/Systems/World
-- Runtime world setup. Static geometry (rig, ships, islands props) is saved in the place file.
-- Here we: make sure the Workspace folders exist, build the ocean / seabed / islands with
-- Terrain (one optimized water volume instead of thousands of parts), tag objects for
-- CollectionService and add particle effects.
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Modules.Config)

local World = { climbPoints = {}, patrolPoints = {}, ready = false }

-- Terrain features. Positions match the props placed in the place file.
World.Islands = {
	{ pos = Vector3.new(-1240,0,-920), r = 100, station = true },
	{ pos = Vector3.new(1260,0,920), r = 120, station = true },
	{ pos = Vector3.new(-1080,0,1120), r = 90, station = true },
	{ pos = Vector3.new(180,0,-1540), r = 120, station = true },
	{ pos = Vector3.new(-380, 0, -320), r = 50 },
	{ pos = Vector3.new(420, 0, 300), r = 42 },
	{ pos = Vector3.new(-260, 0, 420), r = 36 },
	-- Far scenery islands: the fog opens onto more land the further you sail.
	{ pos = Vector3.new(2400, 0, -1800), r = 110 },
	{ pos = Vector3.new(-2200, 0, 600), r = 90 },
	{ pos = Vector3.new(1500, 0, 2800), r = 130 },
	{ pos = Vector3.new(3400, 0, -3000), r = 80 },
	{ pos = Vector3.new(-3600, 0, -600), r = 100 },
	{ pos = Vector3.new(600, 0, 3600), r = 90 },
	{ pos = Vector3.new(-600, 0, -3400), r = 110 },
	{ pos = Vector3.new(3500, 0, 2200), r = 70 },
}
-- Large walkable islands (hills, cliffs, stepped beaches). Camps sit on the flat south side.
World.BigIslands = {
	{ name = "GRAVE ISLAND", pos = Vector3.new(-4400, 0, -1800), r = 420, seed = 11 },
	{ name = "RADAR ISLAND", pos = Vector3.new(4600, 0, -3800), r = 300, seed = 23 },
	{ name = "NORTH ISLES", pos = Vector3.new(800, 0, 5200), r = 260, seed = 37 },
	{ name = "NORTH ISLES B", pos = Vector3.new(1330, 0, 5480), r = 120, seed = 41 },
	{ name = "NORTH ISLES C", pos = Vector3.new(300, 0, 5620), r = 150, seed = 43 },
}

function World.buildBigIslands()
	local T = workspace.Terrain
	for _, isl in ipairs(World.BigIslands) do
		local c, r = isl.pos, isl.r
		-- Stepped beach rings so players can walk out of the sea.
		for i, step in ipairs({ { 48, 1.5 }, { 32, 3.5 }, { 16, 5.5 }, { 0, 8 } }) do
			local radius, topY = r + step[1], step[2]
			local material = i < 3 and Enum.Material.Sand or Enum.Material.Ground
			T:FillCylinder(CFrame.new(c.X, (topY - 40) / 2, c.Z), topY + 40, radius, material)
		end
		T:FillCylinder(CFrame.new(c.X, -15, c.Z), 46, r - 40, Enum.Material.Grass)
		local rng = Random.new(isl.seed)
		local camp = Vector3.new(c.X, 8, c.Z - r * 0.55)
		local hills = math.floor(r / 45)
		for _ = 1, hills do
			local a = rng:NextNumber(0, math.pi * 2)
			local d = rng:NextNumber(0, r * 0.62)
			local p = Vector3.new(c.X + math.cos(a) * d, 0, c.Z + math.sin(a) * d)
			local rad = rng:NextNumber(30, math.min(95, r * 0.35))
			-- Hills stay well clear of the camp so it never ends up buried.
			if (p - Vector3.new(camp.X, 0, camp.Z)).Magnitude > rad + 100 then
				T:FillBall(Vector3.new(p.X, 8 - rad * 0.5, p.Z), rad, rng:NextNumber() < 0.45 and Enum.Material.Rock or Enum.Material.Grass)
			end
		end
		for _ = 1, math.floor(r / 60) do
			local a = rng:NextNumber(0, math.pi * 2)
			if math.abs(a - math.pi * 1.5) > 0.5 then -- keep the southern (camp) shore open
				local p = Vector3.new(c.X + math.cos(a) * r, 0, c.Z + math.sin(a) * r)
				T:FillBall(Vector3.new(p.X, 2, p.Z), rng:NextNumber(18, 34), Enum.Material.Rock)
			end
		end
		-- Guaranteed flat camp at exactly Y=8 (the place file puts the buildings there).
		T:FillCylinder(CFrame.new(camp.X, -15, camp.Z), 46, 85, Enum.Material.Grass)
		T:FillCylinder(CFrame.new(camp.X, 44, camp.Z), 72, 85, Enum.Material.Air)
		task.wait()
	end
end

-- The Throat: a nest trench dug into the seabed west of the rig (floor at -100).
World.Throat = { pos = Vector3.new(-450, 0, 700), size = 110 }
-- Shallow shoal under the ship graveyard.
World.Shoals = {
	{ pos = Vector3.new(-2600, -76, -2400), r = 72 },
	{ pos = Vector3.new(-2500, -80, -2520), r = 60 },
}
World.WreckMound = { pos = Vector3.new(-200, -100, 150), r = 58 }
World.Cave = { pos = Vector3.new(-160, -62, -240), r = 34, hollow = 20 }
World.FloodRegion = { center = Vector3.new(-38, 22, -34), size = Vector3.new(36, 12, 36) }
World.LabRegion = { center = Vector3.new(140, -64, 120), size = Vector3.new(24, 16, 32) }

local function folder(parent, name)
	local f = parent:FindFirstChild(name)
	if not f then
		f = Instance.new("Folder")
		f.Name = name
		f.Parent = parent
	end
	return f
end

function World.init()
	World.Map = folder(workspace, "Map")
	World.Rig = folder(workspace, "Rig")
	World.Interactables = folder(workspace, "Interactables")
	World.NPCs = folder(workspace, "NPCs")
	World.Boats = folder(workspace, "Boats")
	World.BuildObjects = folder(workspace, "BuildObjects")
	World.Effects = folder(workspace, "Effects")
	World.Dropped = folder(World.Interactables, "Dropped")
	World.collectNodes()
	World.decorate()
end

function World.collectNodes()
	local nodes = World.Map:FindFirstChild("AINodes")
	if nodes then
		for _, p in ipairs(nodes:GetDescendants()) do
			if p:IsA("BasePart") then
				if p.Name == "ClimbPoint" then
					table.insert(World.climbPoints, p.CFrame)
				elseif p.Name == "PatrolPoint" then
					table.insert(World.patrolPoints, p.Position)
				end
				p.Transparency = 1
				p.CanCollide = false
				p.CanQuery = false
				p.CanTouch = false
			end
		end
	end
	if #World.climbPoints == 0 then
		-- Fallback: middle of each deck edge, looking inward.
		for _, v in ipairs({ Vector3.new(0, 33, 63), Vector3.new(0, 33, -63), Vector3.new(83, 33, -16), Vector3.new(-83, 33, -18) }) do
			table.insert(World.climbPoints, CFrame.lookAt(v, Vector3.new(0, 33, 0)))
		end
	end
	if #World.patrolPoints == 0 then
		for x = -40, 40, 20 do
			for z = -30, 30, 20 do
				table.insert(World.patrolPoints, Vector3.new(x, 33, z))
			end
		end
	end
end

local function emitter(parent, props)
	local e = Instance.new("ParticleEmitter")
	for k, v in pairs(props) do
		e[k] = v
	end
	e.Parent = parent
	return e
end

local SMOKE = "rbxasset://textures/particles/smoke_main.dds"
local FIRE = "rbxasset://textures/particles/fire_main.dds"
local SPARK = "rbxasset://textures/particles/sparkles_main.dds"

function World.decorate()
	for _, root in ipairs({ World.Map, World.Rig, World.Interactables }) do
		for _, p in ipairs(root:GetDescendants()) do
			if p:IsA("BasePart") then
				local n = p.Name
				if n == "SteamVent" then
					emitter(p, {
						Texture = SMOKE,
						Color = ColorSequence.new(Color3.fromRGB(190, 196, 198)),
						Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 7) }),
						Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.55), NumberSequenceKeypoint.new(1, 1) }),
						Lifetime = NumberRange.new(3, 5),
						Speed = NumberRange.new(3, 6),
						Rate = 5,
						SpreadAngle = Vector2.new(12, 12),
						Acceleration = Vector3.new(1.5, 1, 0),
						EmissionDirection = Enum.NormalId.Top,
					})
				elseif n == "FlareTip" then
					emitter(p, {
						Texture = FIRE,
						Color = ColorSequence.new(Color3.fromRGB(255, 170, 70), Color3.fromRGB(255, 70, 30)),
						LightEmission = 1,
						Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 5), NumberSequenceKeypoint.new(1, 1) }),
						Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) }),
						Lifetime = NumberRange.new(0.6, 1.2),
						Speed = NumberRange.new(10, 16),
						Rate = 35,
						SpreadAngle = Vector2.new(10, 10),
						Acceleration = Vector3.new(4, 4, 0),
						EmissionDirection = Enum.NormalId.Top,
					})
					emitter(p, {
						Texture = SMOKE,
						Color = ColorSequence.new(Color3.fromRGB(30, 30, 32)),
						Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 4), NumberSequenceKeypoint.new(1, 14) }),
						Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 1) }),
						Lifetime = NumberRange.new(4, 7),
						Speed = NumberRange.new(14, 20),
						Rate = 6,
						Acceleration = Vector3.new(5, 2, 0),
						EmissionDirection = Enum.NormalId.Top,
					})
					local l = Instance.new("PointLight")
					l.Color = Color3.fromRGB(255, 140, 60)
					l.Range = 60
					l.Brightness = 3
					l.Parent = p
				elseif n == "SparkPoint" then
					emitter(p, {
						Texture = SPARK,
						Color = ColorSequence.new(Color3.fromRGB(255, 220, 120)),
						LightEmission = 1,
						Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 0) }),
						Lifetime = NumberRange.new(0.3, 0.6),
						Speed = NumberRange.new(8, 14),
						Rate = 3,
						SpreadAngle = Vector2.new(60, 60),
						Acceleration = Vector3.new(0, -40, 0),
					})
				elseif n == "Drip" then
					emitter(p, {
						Texture = SPARK,
						Color = ColorSequence.new(Color3.fromRGB(150, 190, 200)),
						Size = NumberSequence.new(0.12),
						Lifetime = NumberRange.new(0.6, 0.9),
						Speed = NumberRange.new(0, 0.5),
						Rate = 2,
						Acceleration = Vector3.new(0, -50, 0),
						EmissionDirection = Enum.NormalId.Bottom,
					})
				elseif n == "BuoyLight" or n == "Blinker" then
					CollectionService:AddTag(p, "Blinker")
				elseif n == "Crystal" then
					local l = Instance.new("PointLight")
					l.Color = Color3.fromRGB(80, 240, 230)
					l.Range = 14
					l.Brightness = 1.5
					l.Parent = p
				elseif n == "PowerConsole" then
					CollectionService:AddTag(p, "PowerConsole")
				elseif n == "CeilingLight" then
					CollectionService:AddTag(p, "CeilingLight")
				elseif string.sub(n, 1, 5) == "Sign:" then
					World.sign(p, string.sub(n, 6))
				end
			elseif p:IsA("Model") and p.Name == "CraftingBench" then
				CollectionService:AddTag(p, "CraftingBench")
			end
		end
	end
end

-- Stencilled zone sign on the front face of a thin plate.
function World.sign(part, text)
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.LightInfluence = 0.6
	gui.Parent = part
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextColor3 = Color3.fromRGB(236, 176, 54)
	label.Font = Enum.Font.GothamBlack
	label.TextScaled = true
	label.Parent = gui
end

-- Yields while building the ocean. Called once from Main before anything unanchors.
function World.buildTerrain()
	local T = workspace.Terrain
	-- 0.17: a deeper, more reflective North Sea.
	T.WaterColor = Color3.fromRGB(16, 54, 64)
	T.WaterTransparency = 0.55
	T.WaterReflectance = 0.8
	T.WaterWaveSize = 0.22
	T.WaterWaveSpeed = 12
	local half = Config.OceanHalfSize
	local top, bottom = Config.WaterLevel, Config.SeabedY
	-- Deep water (to the seabed) within +-1024 of the rig; a shallower shelf elsewhere keeps
	-- the 12 km ocean's voxel count bounded. Big tiles far away, small tiles near the rig.
	local function fill(cx, cz, size, depth)
		T:FillBlock(CFrame.new(cx, (top + depth) / 2, cz), Vector3.new(size, top - depth, size), Enum.Material.Water)
		T:FillBlock(CFrame.new(cx, depth - 6, cz), Vector3.new(size, 12, size), Enum.Material.Sand)
	end
	local big = 1024
	for x = -half, half - big, big do
		for z = -half, half - big, big do
			local cx, cz = x + big / 2, z + big / 2
			if math.abs(cx) < 1024 and math.abs(cz) < 1024 then
				for dx = -256, 256, 512 do
					for dz = -256, 256, 512 do
						fill(cx + dx, cz + dz, 512, bottom)
					end
				end
			else
				fill(cx, cz, big, -24)
			end
			task.wait()
		end
	end
	World.buildBigIslands()
	-- Rocky patches on the seabed.
	local rng = Random.new(1107)
	for _ = 1, 40 do
		local p = Vector3.new(rng:NextNumber(-900, 900), bottom - 4, rng:NextNumber(-900, 900))
		if p.Magnitude > 120 then
			T:FillBall(p, rng:NextNumber(8, 22), Enum.Material.Rock)
		end
	end
	-- Islands
	for _, isl in ipairs(World.Islands) do
		local c = isl.pos
		T:FillBall(Vector3.new(c.X, 10 - isl.r, c.Z), isl.r, Enum.Material.Sand)
		T:FillBall(Vector3.new(c.X + isl.r * 0.25, 12 - isl.r * 0.8, c.Z + isl.r * 0.1), isl.r * 0.7, Enum.Material.Rock)
		T:FillBall(Vector3.new(c.X - isl.r * 0.2, 4, c.Z - isl.r * 0.25), isl.r * 0.28, Enum.Material.Basalt)
		if isl.station then
			-- Clear the playable floor and boarding route after sculpting the island.
			T:FillBlock(CFrame.new(c.X, 27, c.Z), Vector3.new(68,40,68), Enum.Material.Air)
			T:FillBlock(CFrame.new(c.X, 25, c.Z-66), Vector3.new(18,36,66), Enum.Material.Air)
		end
	end
	-- Flat tops for the small prop islands (props sit at Y=10).
	for _, isl in ipairs(World.Islands) do
		if not isl.station and isl.r <= 50 then
			T:FillCylinder(CFrame.new(isl.pos.X, -10, isl.pos.Z), 40, 24, Enum.Material.Sand)
			T:FillCylinder(CFrame.new(isl.pos.X, 30, isl.pos.Z), 40, 24, Enum.Material.Air)
		end
	end
	-- Mound under the sunken ship
	T:FillBall(World.WreckMound.pos, World.WreckMound.r, Enum.Material.Rock)
	-- Underwater cave: rock outcrop, hollowed and flooded, with a tunnel entrance.
	local cave = World.Cave
	T:FillBall(cave.pos, cave.r, Enum.Material.Rock)
	T:FillBall(cave.pos - Vector3.new(0, 2, 0), cave.hollow, Enum.Material.Water)
	T:FillBlock(CFrame.new(cave.pos + Vector3.new(0, -2, 26)), Vector3.new(10, 10, 24), Enum.Material.Water)
	-- The Throat: rock shell below the seabed, then flood the pit; ragged rocks on the rim.
	local th = World.Throat
	T:FillBlock(CFrame.new(th.pos.X, -96, th.pos.Z), Vector3.new(th.size + 40, 24, th.size + 40), Enum.Material.Rock)
	T:FillBlock(CFrame.new(th.pos.X, -86, th.pos.Z), Vector3.new(th.size, 28, th.size), Enum.Material.Water)
	local trng = Random.new(77)
	for i = 1, 18 do
		local a = i / 18 * math.pi * 2
		local r = th.size * 0.55 + trng:NextNumber(-4, 8)
		T:FillBall(Vector3.new(th.pos.X + math.cos(a) * r, -74, th.pos.Z + math.sin(a) * r), trng:NextNumber(8, 16), Enum.Material.Basalt)
	end
	for _, shoal in ipairs(World.Shoals) do
		T:FillBall(shoal.pos, shoal.r, Enum.Material.Sand)
	end
	World.ready = true
end

function World.setFlooded(flooded)
	local r = World.FloodRegion
	workspace.Terrain:FillBlock(CFrame.new(r.center), r.size, flooded and Enum.Material.Water or Enum.Material.Air)
end

function World.setLabAir(hasAir)
	local r = World.LabRegion
	workspace.Terrain:FillBlock(CFrame.new(r.center), r.size, hasAir and Enum.Material.Air or Enum.Material.Water)
end

return World
