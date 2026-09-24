-- ServerScriptService/Systems/Grounder
-- Runs once after the terrain (islands, sand banks) has been generated. The map builder
-- already guarantees that nothing hovers above other parts; only the terrain height is
-- unknown until runtime. Every small object that touches nothing:
--   * signs, lamps and beacons get a post down to the ground,
--   * everything else is set down onto the ground (or lifted out of it when buried).
local Grounder = {}

local ROOTS = { "Map", "Interactables", "Rig" }
local SKIP = { AINodes = true, Ocean = true, Boundary = true, Loot = true, Doors = true }
local POST_WORDS = { "Sign", "Blinker", "Light", "Lamp", "Beacon" }

function Grounder.init(g)
	Grounder.G = g
end

local terrainParams = RaycastParams.new()
terrainParams.FilterType = Enum.RaycastFilterType.Include

local function boxOf(obj)
	if obj:IsA("Model") then
		return obj:GetBoundingBox()
	end
	return obj.CFrame, obj.Size
end

local function isolated(obj, cf, size)
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { obj }
	local ok, hits = pcall(function()
		return workspace:GetPartBoundsInBox(cf, size + Vector3.new(0.3, 0.3, 0.3), params)
	end)
	return ok and #hits == 0
end

local function wantsPost(name)
	for _, w in ipairs(POST_WORDS) do
		if string.find(name, w, 1, true) then
			return true
		end
	end
	return false
end

function Grounder.fix(obj)
	local cf, size = boxOf(obj)
	if size.Magnitude > 60 then
		return false
	end
	local bottom = cf.Position.Y - size.Y / 2
	if bottom < 0.5 then
		return false
	end
	local center = cf.Position
	-- Only loose objects: anything resting on / joined to other parts is left alone.
	if not isolated(obj, cf, size) then
		return false
	end
	local down = workspace:Raycast(Vector3.new(center.X, bottom + 0.05, center.Z), Vector3.new(0, -60, 0), terrainParams)
	local fromTop = workspace:Raycast(Vector3.new(center.X, center.Y + size.Y / 2 + 0.5, center.Z), Vector3.new(0, -(size.Y + 1), 0), terrainParams)
	if fromTop and fromTop.Position.Y > bottom + 0.4 and fromTop.Position.Y < center.Y + size.Y / 2 then
		-- Buried: lift it out.
		obj:PivotTo(obj:GetPivot() + Vector3.new(0, fromTop.Position.Y - bottom + 0.02, 0))
		return true
	end
	if not down or down.Material == Enum.Material.Water then
		return false
	end
	local gap = bottom - down.Position.Y
	if gap < 0.25 then
		return false
	end
	if wantsPost(obj.Name) then
		local post = Instance.new("Part")
		post.Name = "GroundPost"
		post.Anchored = true
		post.Size = Vector3.new(0.5, gap + 0.6, 0.5)
		post.CFrame = CFrame.new(center.X, down.Position.Y + (gap + 0.6) / 2 - 0.3, center.Z)
		post.Color = Color3.fromRGB(52, 56, 58)
		post.Material = Enum.Material.Metal
		post.Parent = obj:IsA("Model") and obj or obj.Parent
	else
		obj:PivotTo(obj:GetPivot() - Vector3.new(0, gap - 0.02, 0))
	end
	return true
end

-- Called from Main after World.buildTerrain.
function Grounder.run()
	terrainParams.FilterDescendantsInstances = { workspace.Terrain }
	local fixed = 0
	local function visit(container)
		for _, child in ipairs(container:GetChildren()) do
			if SKIP[child.Name] then
				continue
			end
			if child:IsA("Folder") then
				visit(child)
			elseif child:IsA("Model") or child:IsA("BasePart") then
				local ok, changed = pcall(Grounder.fix, child)
				if ok and changed then
					fixed += 1
				end
			end
		end
	end
	for _, name in ipairs(ROOTS) do
		local root = workspace:FindFirstChild(name)
		if root then
			visit(root)
		end
	end
	return fixed
end

return Grounder
