-- StarterPlayerScripts/Client/Corridors
-- Corridor ambience (Config.Sounds.Corridors): a loop that fades in while you are inside a
-- corridor or a cramped room and fades out when you step back outside.
-- "Inside" means a ceiling over your head and walls close on two opposite sides (or all
-- round), or being in one of the named tunnel areas below. Checked a few times a second
-- with short rays, on this client only.
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SFX = require(ReplicatedStorage.Modules.SFX)

local Corridors = { inside = false, level = 0 }
local C

-- Areas that always count as corridors while there is a ceiling overhead.
local AREAS = {
	{ "Rig", "Structure", "ServiceTunnels" },
	{ "Rig", "Buildings", "UNDERDECK" },
	{ "Rig", "Buildings", "FLOODED MAINTENANCE LEVEL" },
	{ "Map", "Station Marrow" },
}
local CEILING = 20 -- studs above the head
local WALL = 13 -- studs to a wall on each side
local FADE = 1.6 -- seconds for a full fade

local params = RaycastParams.new()
params.FilterType = Enum.RaycastFilterType.Exclude
params.IgnoreWater = true

local function areaFolders()
	local list = {}
	for _, path in ipairs(AREAS) do
		local node = workspace
		for _, name in ipairs(path) do
			node = node and node:FindFirstChild(name)
		end
		if node then
			table.insert(list, node)
		end
	end
	return list
end

local function refreshFilter(character)
	local list = { character }
	for _, name in ipairs({ "NPCs", "Effects", "LocalFX", "Scatter" }) do
		local f = workspace:FindFirstChild(name)
		if f then
			table.insert(list, f)
		end
	end
	local cam = workspace.CurrentCamera
	if cam then
		table.insert(list, cam)
	end
	params.FilterDescendantsInstances = list
end

local DIRS = {}
for i = 0, 7 do
	local a = i * math.pi / 4
	DIRS[i] = Vector3.new(math.cos(a), 0, math.sin(a))
end

function Corridors.check()
	local character = C.player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then
		return false
	end
	refreshFilter(character)
	local chest = root.Position + Vector3.new(0, 1, 0)
	local ceiling = workspace:Raycast(chest, Vector3.new(0, CEILING, 0), params)
	if not ceiling then
		return false
	end
	-- Named tunnel areas.
	local folders = areaFolders()
	if #folders > 0 then
		local overlap = OverlapParams.new()
		overlap.FilterType = Enum.RaycastFilterType.Include
		overlap.FilterDescendantsInstances = folders
		local ok, parts = pcall(function()
			return workspace:GetPartBoundsInRadius(root.Position, 12, overlap)
		end)
		if ok and #parts > 0 then
			return true
		end
	end
	-- Walls: on both sides along some axis (a corridor), or on most sides (a small room).
	local hit = {}
	local count = 0
	for i = 0, 7 do
		hit[i] = workspace:Raycast(chest, DIRS[i] * WALL, params) ~= nil
		if hit[i] then
			count += 1
		end
	end
	for i = 0, 3 do
		if hit[i] and hit[i + 4] then
			return true
		end
	end
	return count >= 5
end

function Corridors.init(ctx)
	C = ctx
	local sound = SFX.make("Corridors")
	if not sound then
		return
	end
	local full = sound.Volume
	sound.Volume = 0
	Corridors.sound = sound
	task.spawn(function()
		while true do
			task.wait(0.35)
			local ok, inside = pcall(Corridors.check)
			Corridors.inside = ok and inside == true
		end
	end)
	RunService.Heartbeat:Connect(function(dt)
		local target = Corridors.inside and 1 or 0
		local step = dt / FADE
		if Corridors.level < target then
			Corridors.level = math.min(target, Corridors.level + step)
		elseif Corridors.level > target then
			Corridors.level = math.max(target, Corridors.level - step)
		end
		sound.Volume = full * Corridors.level
		if Corridors.level > 0 and not sound.IsPlaying then
			sound:Play()
		elseif Corridors.level <= 0 and sound.IsPlaying then
			sound:Stop()
		end
	end)
end

return Corridors
