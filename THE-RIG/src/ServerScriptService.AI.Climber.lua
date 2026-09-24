--!nocheck
-- ServerScriptService/AI/Climber
-- THE CLIMBER. Rises from the sea at night, climbs a rig leg and hunts on the deck.
-- States: Climb, Idle, Patrol, Investigate, Search, Lurk, Stalk, Chase, Attack, Scale,
--         Retreat, Regroup, Dive.
--
-- What makes it dangerous (0.10):
--   * SCALE: nowhere is out of reach. If its prey is up on a roof, a crane, a container or
--     any ledge it cannot path to, it climbs straight up the wall and drops next to them.
--   * It rises out of the water (or out of the sand) next to players who are far from the
--     rig: islands, wrecks and ships are not safe at night.
--   * STALK: at range it moves while you look away and freezes when you look at it, then
--     rushes once it is close.
--   * Pack roles (front / flank / behind / cut-off), interception of running prey, and it
--     approaches through the dark side of a lit area.
--   * SEARCH: when it loses you it sweeps your last position, the direction you were running
--     and remembered hideouts; then it LURKS silently in ambush.
--   * It regenerates in the dark, fakes a retreat when hurt, dodges crowbar swings and
--     learns: lamps that kill Climbers attract more saboteurs.
--   Still fears bright light (floodlights, flares, defense posts): it burns and flees.
local PathfindingService = game:GetService("PathfindingService")
local TweenService = game:GetService("TweenService")
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Modules.Config)
local SFX = require(ReplicatedStorage.Modules.SFX)

local Climber = { units = {}, nextId = 0 }
local C = Config.Climber
local G, AI
local templates = {}

-- Four kinds come up out of the sea, and they share one brain. Each is a body and a
-- few numbers; what that brain is allowed to do is decided by the day (Progression).
--   Climber  the drowned thing: the one that has always come up the legs
--   Skitter  small and low, on all fours: quick, fragile, comes in numbers
--   Brute    a bloated giant: too big for doors so it smashes them, too heavy to
--            climb, and the light barely hurts it
--   Pale     white, eyeless and silent; the light does not drive it off
-- Every limb is a part on a Motor6D named CreatureJoint. CrewMotion swings any limb
-- called UpperArm, Forearm or Claw as an arm and Thigh or Shin as a leg.
local KINDS = {
	Climber = { name = "The Climber" },
	Skitter = { name = "The Skitter", Health = 55, WalkSpeed = 18, ChaseSpeed = 27, Damage = 9, StructureDamage = 6,
		AttackRange = 4.2, AttackCooldown = 0.55, HipHeight = 1.1, root = Vector3.new(1.6, 1.2, 2.2),
		agent = { AgentRadius = 1.4, AgentHeight = 3 }, noDoors = true },
	Brute = { name = "The Brute", Health = 420, WalkSpeed = 11, ChaseSpeed = 15, Damage = 38, StructureDamage = 80,
		GeneratorDamage = 24, LampDamage = 70, AttackRange = 7.5, StructureRange = 10, AttackCooldown = 1.8,
		LightDamage = 2, HipHeight = 3.8, root = Vector3.new(3.6, 3, 2.4), agent = { AgentRadius = 3.2, AgentHeight = 9 },
		noScale = true, heavy = true },
	Pale = { name = "The Pale", Health = 170, WalkSpeed = 17, ChaseSpeed = 26, Damage = 24, AttackCooldown = 0.8,
		LightDamage = 1.5, HipHeight = 2.8, silent = true, fearless = true },
}

local function limb(model, root, name, size, offset, color, material)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = root.CFrame * offset
	p.Color = color
	p.Material = material or Enum.Material.Slate
	p.Reflectance = 0.06
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = model
	local w = Instance.new("Motor6D")
	w.Name = "CreatureJoint"
	w.C0 = offset
	w.Part0 = root
	w.Part1 = p
	w.Parent = p
	return p
end

local rad = math.rad
local function A(x, y, z) return CFrame.Angles(rad(x or 0), rad(y or 0), rad(z or 0)) end
local function at(x, y, z) return CFrame.new(x, y, z) end
local NEON, SMOOTH = Enum.Material.Neon, Enum.Material.SmoothPlastic

-- A pin-point eye in a black socket: the thing you see first in the dark.
local function eye(model, root, cf, socket, pupil)
	limb(model, root, "EyeSocket", Vector3.new(socket, socket * 0.8, 0.18), cf, Color3.fromRGB(4, 4, 6), SMOOTH).Reflectance = 0
	limb(model, root, "Eye", Vector3.new(pupil, pupil, pupil), cf * at(0, 0, -0.1), Color3.fromRGB(255, 240, 214), NEON).Reflectance = 0
end

local function teeth(model, root, base, count, width, length, color)
	for k = 1, count do
		local x = (k - (count + 1) / 2) * width
		limb(model, root, "Tooth", Vector3.new(0.09, length, 0.09), base * at(x, 0, 0) * A(0, 0, (k % 2 == 0) and 6 or -6), color)
	end
end

local BODIES = {}

-- The drowned thing. Too tall when it straightens, hunched when it does not; the head
-- hangs off a long neck, tipped over to one side, and the jaw has come loose.
function BODIES.Climber(model, root)
	local SKIN, DARK, BONE, GUM = Color3.fromRGB(138, 146, 140), Color3.fromRGB(46, 52, 54), Color3.fromRGB(214, 206, 184), Color3.fromRGB(80, 6, 12)
	limb(model, root, "Pelvis", Vector3.new(1.6, 0.8, 1), at(0, -0.3, 0.25), DARK)
	limb(model, root, "Torso", Vector3.new(1.8, 3, 1), at(0, 1.2, -0.35) * A(-38), SKIN)
	for i = 0, 4 do
		limb(model, root, "Rib", Vector3.new(1.95, 0.12, 1.08), at(0, 1.95 - i * 0.38, -0.95 + i * 0.28) * A(-38), BONE)
	end
	for i = 0, 6 do
		limb(model, root, "Spine", Vector3.new(0.3, 0.42, 0.42), at(0, 2.35 - i * 0.48, 0.2 + i * 0.26) * A(-38), BONE)
	end
	limb(model, root, "Neck", Vector3.new(0.42, 1.7, 0.42), at(0.1, 2.75, -1.55) * A(-55, 0, 8), DARK)
	local head = at(0.35, 3.05, -2.45) * A(-18, 0, 22)
	limb(model, root, "Head", Vector3.new(1, 1.2, 1.35), head, SKIN)
	limb(model, root, "Jaw", Vector3.new(0.9, 0.22, 1.15), head * at(0, -0.9, -0.2) * A(38), DARK)
	limb(model, root, "Mouth", Vector3.new(0.8, 0.5, 1), head * at(0, -0.62, -0.15) * A(18), GUM, SMOOTH)
	teeth(model, root, head * at(0, -0.62, -0.66), 6, 0.14, 0.32, BONE)
	teeth(model, root, head * at(0, -1.02, -0.72) * A(38), 5, 0.15, 0.28, BONE)
	-- Four eyes: two where eyes go and two smaller ones above them that should not be there.
	for _, s in ipairs({ -1, 1 }) do
		eye(model, root, head * at(s * 0.26, 0.12, -0.68), 0.3, 0.08)
		eye(model, root, head * at(s * 0.17, 0.42, -0.66), 0.18, 0.05)
	end
	for k = -3, 3 do
		local len = 1.4 + (k % 3) * 0.6
		limb(model, root, "Hair", Vector3.new(0.1, len, 0.1), head * at(k * 0.14, 0.55 - len / 2, -0.62) * A(-6, 0, k * 3), Color3.fromRGB(12, 12, 14), SMOOTH)
	end
	for _, s in ipairs({ -1, 1 }) do
		-- Arms long enough to touch the deck while it stands.
		limb(model, root, "UpperArm", Vector3.new(0.42, 3.3, 0.42), at(s * 1.25, 1.1, -0.9) * A(-30, 0, s * 16), SKIN)
		limb(model, root, "Forearm", Vector3.new(0.34, 3.5, 0.34), at(s * 1.75, -1.1, -2.2) * A(-58, 0, s * 6), DARK)
		for k = -1.5, 1.5 do
			limb(model, root, "Claw", Vector3.new(0.1, 1.6, 0.1), at(s * 1.85 + k * 0.15, -2.35, -3.45) * A(-84, 0, k * 7), Color3.fromRGB(20, 18, 16))
		end
		-- Legs bent the wrong way.
		limb(model, root, "Thigh", Vector3.new(0.55, 1.9, 0.55), at(s * 0.7, -1.25, -0.15) * A(28), SKIN)
		limb(model, root, "Shin", Vector3.new(0.42, 1.8, 0.42), at(s * 0.7, -2.55, 0.35) * A(-24), DARK)
		limb(model, root, "Foot", Vector3.new(0.5, 0.2, 0.9), at(s * 0.7, -3.3, 0.05), DARK)
	end
end

-- Small, wet and black, running on its arms. Its head is almost all mouth.
function BODIES.Skitter(model, root)
	local SKIN, DARK, BONE, GUM = Color3.fromRGB(38, 44, 50), Color3.fromRGB(18, 22, 26), Color3.fromRGB(196, 190, 170), Color3.fromRGB(96, 8, 14)
	limb(model, root, "Torso", Vector3.new(1.3, 0.8, 2.3), at(0, 0.05, 0) * A(-6), SKIN, SMOOTH)
	for i = 0, 5 do
		limb(model, root, "Spine", Vector3.new(0.22, 0.34, 0.3), at(0, 0.5, 0.9 - i * 0.38), BONE)
	end
	local head = at(0, 0.2, -1.55) * A(-8, 0, -10)
	limb(model, root, "Head", Vector3.new(0.95, 0.8, 1), head, SKIN, SMOOTH)
	limb(model, root, "Jaw", Vector3.new(0.9, 0.18, 0.95), head * at(0, -0.55, -0.15) * A(30), DARK)
	limb(model, root, "Mouth", Vector3.new(0.8, 0.45, 0.8), head * at(0, -0.3, -0.12) * A(14), GUM, SMOOTH)
	teeth(model, root, head * at(0, -0.3, -0.5), 7, 0.11, 0.26, BONE)
	for _, s in ipairs({ -1, 1 }) do
		eye(model, root, head * at(s * 0.3, 0.2, -0.5), 0.16, 0.05)
		eye(model, root, head * at(s * 0.16, 0.3, -0.52), 0.12, 0.04)
		limb(model, root, "UpperArm", Vector3.new(0.26, 1.6, 0.26), at(s * 0.85, -0.25, -0.9) * A(-40, 0, s * 30), SKIN)
		limb(model, root, "Forearm", Vector3.new(0.22, 1.5, 0.22), at(s * 1.2, -0.7, -1.7) * A(35, 0, s * 12), DARK)
		limb(model, root, "Claw", Vector3.new(0.08, 0.7, 0.08), at(s * 1.3, -1.35, -2), DARK)
		limb(model, root, "Thigh", Vector3.new(0.3, 1.2, 0.3), at(s * 0.6, -0.4, 0.85) * A(40, 0, s * 18), SKIN)
		limb(model, root, "Shin", Vector3.new(0.24, 1.1, 0.24), at(s * 0.85, -1, 1.25) * A(-30, 0, s * 8), DARK)
	end
end

-- A bloated giant grown over with the sea: a head sunk between its shoulders, one arm
-- heavier than the other, and barnacles where the skin has split.
function BODIES.Brute(model, root)
	local SKIN, DARK, BONE, CRUST = Color3.fromRGB(104, 106, 98), Color3.fromRGB(48, 50, 46), Color3.fromRGB(206, 198, 176), Color3.fromRGB(70, 74, 66)
	limb(model, root, "Pelvis", Vector3.new(3.2, 1.4, 2.2), at(0, -0.9, 0.3), DARK)
	limb(model, root, "Torso", Vector3.new(4.6, 4.2, 3), at(0, 1.9, -0.3) * A(-18), SKIN)
	limb(model, root, "Belly", Vector3.new(3.6, 2.4, 2.4), at(0, 0.5, -0.9), SKIN)
	for i = 0, 7 do
		local x, y = math.sin(i * 1.7) * 1.8, 1 + (i % 4) * 0.8
		limb(model, root, "Barnacle", Vector3.new(0.6, 0.6, 0.6), at(x, y, 0.9 + (i % 2) * 0.3), CRUST).Shape = Enum.PartType.Ball
	end
	local head = at(0, 3.9, -1.7) * A(-12)
	limb(model, root, "Head", Vector3.new(1.6, 1.5, 1.6), head, DARK)
	limb(model, root, "Jaw", Vector3.new(1.5, 0.4, 1.3), head * at(0, -1, -0.25) * A(24), DARK)
	teeth(model, root, head * at(0, -0.72, -0.78), 6, 0.2, 0.4, BONE)
	for _, s in ipairs({ -1, 1 }) do
		eye(model, root, head * at(s * 0.4, 0.2, -0.8), 0.26, 0.07)
		local big = s == 1 and 1.25 or 1
		limb(model, root, "UpperArm", Vector3.new(1.3 * big, 3.6, 1.3 * big), at(s * 3, 2.2, -0.6) * A(-14, 0, s * 14), SKIN)
		limb(model, root, "Forearm", Vector3.new(1.5 * big, 3.8, 1.5 * big), at(s * 3.6, -0.9, -1.5) * A(-30, 0, s * 4), CRUST)
		for k = -1, 1 do
			limb(model, root, "Claw", Vector3.new(0.3, 1.4, 0.3), at(s * 3.7 + k * 0.4, -3, -2.3) * A(-50), BONE)
		end
		limb(model, root, "Thigh", Vector3.new(1.4, 2.2, 1.4), at(s * 1.2, -2.3, 0.3) * A(12), SKIN)
		limb(model, root, "Shin", Vector3.new(1.2, 2.2, 1.2), at(s * 1.2, -4.1, 0.25) * A(-10), DARK)
		limb(model, root, "Foot", Vector3.new(1.4, 0.4, 1.8), at(s * 1.2, -4.8, -0.2), DARK)
	end
end

-- White as something that has never seen the sun. No eyes at all, a mouth that runs
-- almost ear to ear, and it makes no sound.
function BODIES.Pale(model, root)
	local SKIN, SHADE, BONE, MOUTH = Color3.fromRGB(232, 232, 226), Color3.fromRGB(190, 190, 184), Color3.fromRGB(250, 248, 240), Color3.fromRGB(10, 6, 8)
	limb(model, root, "Pelvis", Vector3.new(1.4, 0.7, 0.9), at(0, -0.3, 0.2), SHADE, SMOOTH)
	limb(model, root, "Torso", Vector3.new(1.5, 3.2, 0.85), at(0, 1.3, -0.3) * A(-24), SKIN, SMOOTH)
	for i = 0, 4 do
		limb(model, root, "Rib", Vector3.new(1.6, 0.1, 0.92), at(0, 2.05 - i * 0.4, -0.7 + i * 0.18) * A(-24), SHADE, SMOOTH)
	end
	limb(model, root, "Neck", Vector3.new(0.34, 1.4, 0.34), at(0, 3, -1.1) * A(-30), SKIN, SMOOTH)
	local head = at(0, 3.55, -1.6) * A(-8, 0, -12)
	limb(model, root, "Head", Vector3.new(0.95, 1.35, 1.05), head, SKIN, SMOOTH)
	limb(model, root, "Mouth", Vector3.new(0.92, 0.22, 0.2), head * at(0, -0.3, -0.5), MOUTH, SMOOTH)
	teeth(model, root, head * at(0, -0.27, -0.58), 9, 0.1, 0.16, BONE)
	for _, s in ipairs({ -1, 1 }) do
		-- Where the eyes should be: smooth shallow dents.
		limb(model, root, "EyeSocket", Vector3.new(0.26, 0.18, 0.06), head * at(s * 0.22, 0.2, -0.52), SHADE, SMOOTH)
		limb(model, root, "UpperArm", Vector3.new(0.3, 3.4, 0.3), at(s * 1, 1.2, -0.6) * A(-22, 0, s * 10), SKIN, SMOOTH)
		limb(model, root, "Forearm", Vector3.new(0.26, 3.4, 0.26), at(s * 1.25, -1.2, -1.6) * A(-40, 0, s * 4), SKIN, SMOOTH)
		for k = -1.5, 1.5 do
			limb(model, root, "Claw", Vector3.new(0.07, 1.4, 0.07), at(s * 1.3 + k * 0.12, -2.8, -2.5) * A(-66, 0, k * 6), BONE, SMOOTH)
		end
		limb(model, root, "Thigh", Vector3.new(0.4, 2, 0.4), at(s * 0.55, -1.35, 0) * A(18), SKIN, SMOOTH)
		limb(model, root, "Shin", Vector3.new(0.32, 2, 0.32), at(s * 0.55, -2.8, 0.3) * A(-14), SHADE, SMOOTH)
	end
end

local function buildTemplate(kind)
	local spec = KINDS[kind]
	local model = Instance.new("Model")
	model.Name = spec.name
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = spec.root or Vector3.new(2, 2, 1)
	root.CFrame = CFrame.new(0, 10, 0)
	root.Transparency = 1
	root.CanCollide = true
	root.Parent = model
	model.PrimaryPart = root
	BODIES[kind](model, root)
	local head = model:FindFirstChild("Head")
	if not spec.silent then
		local glow = Instance.new("PointLight")
		glow.Color = Color3.fromRGB(255, 200, 170)
		glow.Range = kind == "Brute" and 8 or 5
		glow.Brightness = 0.6
		glow.Parent = head
	end
	-- Dark mist clinging to the body, and sea water dripping off it.
	local torso = model:FindFirstChild("Torso")
	local mist = Instance.new("ParticleEmitter")
	mist.Name = "Mist"
	mist.Texture = "rbxasset://textures/particles/smoke_main.dds"
	mist.Color = ColorSequence.new(kind == "Pale" and Color3.fromRGB(200, 200, 196) or Color3.fromRGB(8, 10, 12))
	mist.LightInfluence = 1
	mist.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 2), NumberSequenceKeypoint.new(1, 5) })
	mist.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.3, 0.72), NumberSequenceKeypoint.new(1, 1) })
	mist.Lifetime = NumberRange.new(1.5, 2.5)
	mist.Speed = NumberRange.new(0.3, 1)
	mist.SpreadAngle = Vector2.new(180, 180)
	mist.Rate = 6
	mist.Parent = torso
	local drip = Instance.new("ParticleEmitter")
	drip.Name = "Drip"
	drip.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	drip.Color = ColorSequence.new(Color3.fromRGB(170, 200, 210))
	drip.Size = NumberSequence.new(0.12)
	drip.Transparency = NumberSequence.new(0.35)
	drip.Lifetime = NumberRange.new(0.5, 0.8)
	drip.Speed = NumberRange.new(0)
	drip.Acceleration = Vector3.new(0, -40, 0)
	drip.Rate = 10
	drip.Parent = torso
	local hum = Instance.new("Humanoid")
	hum.RigType = Enum.HumanoidRigType.R15
	hum.HipHeight = spec.HipHeight or 2.4
	hum.RequiresNeck = false
	hum.BreakJointsOnDeath = false
	hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	hum.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	hum.Parent = model
	model:SetAttribute("Kind", kind)
	model.Parent = ServerStorage
	return model
end

-- What the brain may do, by band of days (Progression.brain). Band 0 never spawns.
--   sense      multiplies how far it sees and hears
--   speed      added to its walking and running speed
--   instinct   seconds between night-time hunches about where the crew is
--   lurk       seconds it lies in wait after a search turns up nothing
--   scaleHeight  the tallest wall it will climb to reach you
local BRAINS = {
	{ sense = 0.6, speed = -3, instinct = math.huge, lurk = 0, scaleHeight = 0 }, -- days 6-10
	{ sense = 1, speed = 0, instinct = 10, lurk = 11, scaleHeight = 14 }, -- days 11-30
	{ sense = 1.15, speed = 1, instinct = 7, lurk = 9, scaleHeight = math.huge }, -- days 31-50
	{ sense = 1.35, speed = 3, instinct = 4, lurk = 5, scaleHeight = math.huge }, -- days 51-100
}

-- The numbers one creature fights with: the Climber's, overridden by its kind, then
-- sharpened by the band it came up in.
local function statsFor(kind, brain)
	local stats = {}
	for k, v in pairs(C) do stats[k] = v end
	for k, v in pairs(KINDS[kind]) do stats[k] = v end
	local mind = BRAINS[brain]
	stats.WalkSpeed += mind.speed
	stats.ChaseSpeed += mind.speed
	stats.SightRange *= mind.sense
	stats.HearRange *= mind.sense
	return stats, mind
end

-- Which kind comes up next, weighted by what the day allows.
local function pickKind()
	local kinds = G.Director.profile.kinds or { Climber = 1 }
	local total = 0
	for _, w in pairs(kinds) do total += w end
	local roll = math.random() * total
	for kind, w in pairs(kinds) do
		roll -= w
		if roll <= 0 then return kind end
	end
	return "Climber"
end

function Climber.init(g, ai)
	G = g
	AI = ai
	for kind in pairs(KINDS) do
		templates[kind] = buildTemplate(kind)
	end
end

local function unitOf(model)
	for _, u in ipairs(Climber.units) do
		if u.model == model then
			return u
		end
	end
	return nil
end

function Climber.count()
	return #Climber.units
end

-- Climbers within `range` of pos.
function Climber.countNear(pos, range)
	local n = 0
	for _, u in ipairs(Climber.units) do
		if u.model.Parent and (u.root.Position - pos).Magnitude < range then
			n += 1
		end
	end
	return n
end

local function setState(u, state)
	local C = u.C
	if u.state ~= state then
		local was = u.state
		u.state = state
		u.stateSince = os.clock()
		u.model:SetAttribute("State", state)
		local speed = C.WalkSpeed
		if state == "Chase" or state == "Retreat" or state == "Regroup" then
			speed = C.ChaseSpeed
		elseif state == "Stalk" then
			speed = C.ChaseSpeed + 2
		elseif state == "Lurk" then
			speed = 0
		end
		u.hum.WalkSpeed = speed
		if state == "Chase" and was ~= "Attack" then
			AI.cry(u, "Shriek", 7)
		end
	end
end

local function finishArrival(u, root)
	if not u.model.Parent then
		return
	end
	root.Anchored = false
	pcall(function()
		root:SetNetworkOwner(nil)
	end)
	if u.skitter then
		u.skitter.Playing = false
	end
	setState(u, "Idle")
	u.lastPos = root.Position
	u.lastMoveCheck = os.clock() + 2
end

-- Navigation helpers ---------------------------------------------------------------------
local navParams = RaycastParams.new()
navParams.FilterType = Enum.RaycastFilterType.Exclude
navParams.IgnoreWater = false

local function refreshNavFilter()
	local list = { workspace.NPCs }
	local fx = workspace:FindFirstChild("Effects")
	if fx then
		table.insert(list, fx)
	end
	local sc = workspace:FindFirstChild("Scatter")
	if sc then
		table.insert(list, sc)
	end
	for _, p in ipairs(game:GetService("Players"):GetPlayers()) do
		if p.Character then
			table.insert(list, p.Character)
		end
	end
	navParams.FilterDescendantsInstances = list
end

-- Solid, dry ground under a point (never the sea).
local function groundAt(p)
	local hit = workspace:Raycast(p + Vector3.new(0, 2.5, 0), Vector3.new(0, -18, 0), navParams)
	if hit and hit.Material ~= Enum.Material.Water then
		return hit
	end
	return nil
end

-- Solid footing under a point, measured from the creature's own feet.
local function footing(u, p)
	local feet = u.root.Position.Y - u.hum.HipHeight - u.root.Size.Y / 2
	local hit = workspace:Raycast(Vector3.new(p.X, feet + 2, p.Z), Vector3.new(0, -9.5, 0), navParams)
	return hit ~= nil and hit.Material ~= Enum.Material.Water
end

local function rotateFlat(v, deg)
	local a = math.rad(deg)
	local c, s = math.cos(a), math.sin(a)
	return Vector3.new(v.X * c - v.Z * s, 0, v.X * s + v.Z * c)
end

-- Whisker steering: find a safe heading towards `target`, hopping over low obstacles and
-- never stepping off an edge. Returns a point to walk to, or nil when boxed in.
local function steer(u, pos, target)
	local flat = Vector3.new(target.X - pos.X, 0, target.Z - pos.Z)
	if flat.Magnitude < 0.5 then
		return target
	end
	local dir = flat.Unit
	local reach = math.min(flat.Magnitude, 8)
	for _, ang in ipairs({ 0, 30, -30, 60, -60, 95, -95, 135, -135 }) do
		local d = rotateFlat(dir, ang)
		local low = workspace:Raycast(pos - Vector3.new(0, 1.6, 0), d * 4, navParams)
		local high = workspace:Raycast(pos + Vector3.new(0, 1.2, 0), d * 4, navParams)
		local safe = footing(u, pos + d * 3.5)
		if safe and not high then
			if low then
				if ang == 0 then
					u.hum.Jump = true -- low obstacle straight ahead: hop over it
					return pos + d * reach
				end
			else
				return pos + d * (ang == 0 and reach or 6)
			end
		end
	end
	return nil
end

-- Walks towards `target` only along safe ground.
local function safeMove(u, target)
	local pos = u.root.Position
	local step = steer(u, pos, target)
	if step then
		u.hum:MoveTo(step)
		return true
	end
	u.hum:MoveTo(pos)
	return false
end

-- Is every step of the straight line from here to there on solid footing?
local function clearLine(u, to)
	local from = u.root.Position
	local flat = Vector3.new(to.X - from.X, 0, to.Z - from.Z)
	local n = math.ceil(flat.Magnitude / 2)
	for i = 1, n do
		if not footing(u, from + flat * (i / n)) then
			return false
		end
	end
	return true
end

-- Walks straight at a point only when nothing on the way is a drop; otherwise steers
-- round it the way safeMove does.
local function guardedMove(u, point)
	if clearLine(u, point) then
		u.hum:MoveTo(point)
		return true
	end
	return safeMove(u, point)
end

-- The last line: whatever the brain decided, it does not walk off an edge. The
-- humanoid keeps walking between AI ticks, so it looks as far ahead as it will
-- travel before the next one -- but never past the point it is walking to, or it
-- would stop short of every corner on a catwalk.
local function edgeBrake(u)
	if u.root.Anchored or u.leaving or u.fleeing or os.clock() < (u.jumpUntil or 0) then
		return
	end
	local dir = u.hum.MoveDirection
	if dir.Magnitude < 0.1 then
		return
	end
	local pos = u.root.Position
	local goal = u.hum.WalkToPoint
	local left = Vector3.new(goal.X - pos.X, 0, goal.Z - pos.Z).Magnitude
	if left < 1 then
		return
	end
	local ahead = math.min(math.clamp(u.hum.WalkSpeed * 0.3, 3, 8), left)
	if not footing(u, pos + dir * math.min(2, ahead)) or not footing(u, pos + dir * ahead) then
		u.hum:MoveTo(pos)
	end
end

-- Moves an anchored creature along a list of {cframe, seconds} legs, then releases it.
local function travel(u, legs, onDone)
	local root = u.root
	root.Anchored = true
	local i = 0
	local function nextLeg()
		i += 1
		local leg = legs[i]
		if not leg or not u.model.Parent or u.hum.Health <= 0 then
			if onDone then
				onDone()
			end
			return
		end
		local t = TweenService:Create(root, TweenInfo.new(math.max(leg[2], 0.1), leg[3] or Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), { CFrame = leg[1] })
		t.Completed:Connect(nextLeg)
		t:Play()
	end
	nextLeg()
end

local function newUnit(model, opts)
	Climber.nextId += 1
	local root = model.HumanoidRootPart
	-- A spawn forced from the DEV panel on a quiet day still gets the stupidest mind.
	local brain = math.max(G.Director.profile.brain or 1, 1)
	local stats, mind = statsFor(opts.kind, brain)
	local agent = stats.agent or { AgentRadius = 2, AgentHeight = 5 }
	local unit = {
		id = Climber.nextId,
		kind = opts.kind,
		brain = brain,
		mind = mind,
		C = stats,
		model = model,
		root = root,
		hum = model:FindFirstChildOfClass("Humanoid"),
		role = opts.role,
		stalker = math.random() < 0.55,
		state = "Climb",
		stateSince = os.clock(),
		nextAttack = 0,
		nextPath = 0,
		computing = false,
		exposure = 0,
		flinchUntil = 0,
		lastFlinch = 0,
		lastLit = 0,
		lastPos = root.Position,
		lastMoveCheck = os.clock() + 4,
		watched = 0,
		nextGrowl = os.clock() + math.random(3, 8),
		path = PathfindingService:CreatePath({ AgentRadius = agent.AgentRadius, AgentHeight = agent.AgentHeight, AgentCanJump = true, AgentCanClimb = brain >= 2, WaypointSpacing = 6, Costs = { Water = math.huge } }),
	}
	unit.blocked = unit.path.Blocked:Connect(function(index)
		if index >= (unit.wpIndex or 2) then
			unit.nextPath = 0
			unit.waypoints = nil
		end
	end)
	-- Looped breathing / claws are played by each client while the creature is near
	-- (Client/Horror), so they never pile up on the server.
	unit.hum.MaxHealth = stats.Health
	unit.hum.Health = stats.Health
	unit.hum.WalkSpeed = stats.WalkSpeed
	model:SetAttribute("State", "Climb")
	model:SetAttribute("Mind", brain)
	table.insert(Climber.units, unit)
	return unit
end

-- opts = {flank = bool, role = "Saboteur" | nil, point = CFrame, near = Vector3 (player position)}
function Climber.spawn(opts)
	opts = opts or {}
	if not AI.allowed(opts.force) then
		return nil
	end
	if opts.near then
		return Climber.spawnNear(opts.near, opts)
	end
	local points = G.World.climbPoints
	if #points == 0 then
		return nil
	end
	local cf = opts.point
	if not cf then
		local pool = opts.flank and #points or math.min(4, #points)
		local near = {}
		for i, point in ipairs(points) do
			if AI.anyPlayerWithin(point.Position, 150) and (opts.flank or i <= pool) then
				table.insert(near, point)
			end
		end
		if #near == 0 then
			for _, point in ipairs(points) do
				if AI.anyPlayerWithin(point.Position, 190) then
					table.insert(near, point)
				end
			end
		end
		cf = #near > 0 and near[math.random(1, #near)] or points[math.random(1, pool)]
	end
	local look = Vector3.new(cf.LookVector.X, 0, cf.LookVector.Z)
	look = look.Magnitude > 0.01 and look.Unit or Vector3.new(0, 0, -1)
	local top = cf.Position
	local outside = top - look * 2.5
	local start = Vector3.new(outside.X, Config.WaterLevel - 5, outside.Z)
	local landing = top + look * 5

	opts.kind = opts.kind or pickKind()
	local model = templates[opts.kind]:Clone()
	local root = model.HumanoidRootPart
	root.Anchored = true
	model:PivotTo(CFrame.lookAt(start, start + look))
	model.Parent = G.World.NPCs
	AI.register(model, "Climber")
	local unit = newUnit(model, opts)
	G.Util.splash(start)
	SFX.play("Emerge", root)
	if unit.skitter then
		unit.skitter.Playing = true
	end
	local up = outside + Vector3.new(0, top.Y - outside.Y, 0)
	travel(unit, {
		{ CFrame.lookAt(up, up + look), unit.C.ClimbTime },
		{ CFrame.lookAt(landing, landing + look), 0.7, Enum.EasingStyle.Quad },
	}, function()
		finishArrival(unit, root)
	end)
	return unit
end

-- Rises out of the water next to a player far from the rig (island, wreck, ship, jetty),
-- or digs out of the ground when there is no water close enough.
function Climber.spawnNear(target, opts)
	opts = opts or {}
	local water = AI.findWaterNear(target, 24)
	local start, climbTop
	if water then
		start = water - Vector3.new(0, 5, 0)
	else
		local a = math.random() * math.pi * 2
		local ground = AI.findLanding(target + Vector3.new(math.cos(a) * 32, 0, math.sin(a) * 32), target, { 0, 4, 8 })
		if not ground then
			return nil
		end
		start = ground - Vector3.new(0, 7, 0)
	end
	local landing = AI.findLanding(target, start, { 9, 6, 13, 4 })
	if not landing then
		return nil
	end
	climbTop = Vector3.new(start.X, landing.Y + 1, start.Z)
	local flat = Vector3.new(landing.X - start.X, 0, landing.Z - start.Z)
	local look = flat.Magnitude > 0.1 and flat.Unit or Vector3.new(0, 0, -1)
	opts.kind = opts.kind or pickKind()
	local model = templates[opts.kind]:Clone()
	local root = model.HumanoidRootPart
	root.Anchored = true
	model:PivotTo(CFrame.lookAt(start, start + look))
	model.Parent = G.World.NPCs
	AI.register(model, "Climber")
	local unit = newUnit(model, opts)
	if water then
		G.Util.splash(start)
	end
	SFX.play("Emerge", root)
	if unit.skitter then
		unit.skitter.Playing = true
	end
	local rise = math.clamp((climbTop - start).Magnitude / 9, 1.2, 6)
	local cross = math.clamp((landing - climbTop).Magnitude / 16, 0.4, 5)
	travel(unit, {
		{ CFrame.lookAt(climbTop, climbTop + look), rise },
		{ CFrame.lookAt(landing, landing + look), cross, Enum.EasingStyle.Quad },
	}, function()
		finishArrival(unit, root)
	end)
	return unit
end

-- Crawls straight up walls / over edges to reach a spot it cannot walk to.
function Climber.scale(u, targetPos, now)
	if u.brain < 2 or u.C.noScale or u.root.Anchored or now < (u.nextScale or 0) then
		return false
	end
	local pos = u.root.Position
	if (targetPos - pos).Magnitude > 90 then
		return false
	end
	local landing = AI.findLanding(targetPos, pos, { 6, 4, 9, 12 })
	if not landing or (landing - pos).Magnitude < 5 or landing.Y - pos.Y > u.mind.scaleHeight then
		u.nextScale = now + 3
		return false
	end
	u.nextScale = now + 9
	setState(u, "Scale")
	AI.cry(u, "Shriek", 6)
	if u.skitter then
		u.skitter.Playing = true
	end
	local flat = Vector3.new(landing.X - pos.X, 0, landing.Z - pos.Z)
	local look = flat.Magnitude > 0.1 and flat.Unit or u.root.CFrame.LookVector
	local high = math.max(landing.Y, pos.Y) + 2
	local a = Vector3.new(pos.X, high, pos.Z)
	local b = Vector3.new(landing.X, high, landing.Z)
	travel(u, {
		{ CFrame.lookAt(a, a + look), math.clamp(math.abs(high - pos.Y) / 13, 0.25, 4) },
		{ CFrame.lookAt(b, b + look), math.clamp(flat.Magnitude / 18, 0.25, 4), Enum.EasingStyle.Quad },
		{ CFrame.lookAt(landing, landing + look), 0.3, Enum.EasingStyle.Quad },
	}, function()
		finishArrival(u, u.root)
		setState(u, "Chase")
	end)
	return true
end

-- Climbs out of the water onto the nearest safe spot near `goal`.
function Climber.climbOut(u, goal)
	local pos = u.root.Position
	local landing = AI.findLanding(goal, pos, { 7, 10, 14, 4, 20 })
	if not landing or (landing - pos).Magnitude > 220 then
		local edge = nil
		local best
		for _, cf in ipairs(G.World.climbPoints) do
			local d = (cf.Position - pos).Magnitude
			if not best or d < best then
				edge, best = cf, d
			end
		end
		if not edge or best > 220 then
			return false
		end
		landing = edge.Position + edge.LookVector * 5
	end
	local flat = Vector3.new(landing.X - pos.X, 0, landing.Z - pos.Z)
	local look = flat.Magnitude > 0.1 and flat.Unit or Vector3.new(0, 0, -1)
	local top = Vector3.new(pos.X, landing.Y + 1, pos.Z)
	setState(u, "Scale")
	G.Util.splash(pos)
	travel(u, {
		{ CFrame.lookAt(top, top + look), math.clamp((top - pos).Magnitude / 11, 0.6, 5) },
		{ CFrame.lookAt(landing, landing + look), math.clamp(flat.Magnitude / 16, 0.3, 8), Enum.EasingStyle.Quad },
	}, function()
		finishArrival(u, u.root)
		setState(u, "Chase")
	end)
	return true
end

-- Side-steps a crowbar swing it sees coming.
function Climber.dodge(model, player)
	local u = unitOf(model)
	if not u or u.brain < 3 or u.root.Anchored or u.state == "Climb" or u.state == "Dive" then
		return false
	end
	local now = os.clock()
	if now < (u.nextDodge or 0) or math.random() > AI.dodgeChance() then
		return false
	end
	u.nextDodge = now + 3.5
	local r = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if r then
		local away = u.root.Position - r.Position
		local side = Vector3.new(-away.Z, 0, away.X)
		if side.Magnitude > 0.1 then
			local dir = side.Unit * (math.random() < 0.5 and -1 or 1)
			if not groundAt(u.root.Position + dir * 6) then
				dir = -dir
			end
			if groundAt(u.root.Position + dir * 6) then
				u.root.AssemblyLinearVelocity = dir * 34 + Vector3.new(0, 10, 0)
			end
		end
	end
	AI.cry(u, "Snarl", 1)
	u.flinchUntil = now + 0.35
	return true
end

local function dive(u)
	if u.state == "Dive" then
		return
	end
	setState(u, "Dive")
	local root = u.root
	root.Anchored = true
	local pos = root.Position
	local down = Vector3.new(pos.X, Config.WaterLevel - 8, pos.Z)
	G.Util.splash(down)
	local t = TweenService:Create(root, TweenInfo.new(1.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { CFrame = CFrame.new(down) })
	t.Completed:Connect(function()
		if u.model.Parent then
			u.model:Destroy()
		end
	end)
	t:Play()
end

local function nearestEdge(pos)
	local best, bestD
	for _, cf in ipairs(G.World.climbPoints) do
		local d = (cf.Position - pos).Magnitude
		if not bestD or d < bestD then
			best, bestD = cf, d
		end
	end
	return best, bestD
end

local function moveTo(u, dest, now)
	local pos = u.root.Position
	if (dest - pos).Magnitude < 5 then
		guardedMove(u, dest)
		return
	end
	local stale = not u.pathDest or (u.pathDest - dest).Magnitude > 6
	if (stale or now >= u.nextPath) and not u.computing and now >= u.nextPath then
		u.computing = true
		u.nextPath = now + ((stale or u.state == "Chase") and 0.6 or 1.4)
		local from = pos
		task.spawn(function()
			local ok = pcall(function()
				u.path:ComputeAsync(from, dest)
			end)
			if not u.model.Parent then
				u.computing = false
				return
			end
			if ok and u.path.Status == Enum.PathStatus.Success then
				u.waypoints = u.path:GetWaypoints()
				u.wpIndex = 2
				u.pathFailed = false
			else
				u.waypoints = nil
				u.pathFailed = true
			end
			u.pathDest = dest
			u.computing = false
		end)
	end
	local wps = u.waypoints
	if wps then
		local wp = wps[u.wpIndex]
		while wp and Vector3.new(wp.Position.X - pos.X, 0, wp.Position.Z - pos.Z).Magnitude < 3 do
			u.wpIndex += 1
			wp = wps[u.wpIndex]
		end
		if wp then
			if wp.Action == Enum.PathWaypointAction.Jump then
				-- The path finder measured this jump; trust it over the edge check.
				u.hum.Jump = true
				u.jumpUntil = os.clock() + 0.8
				u.hum:MoveTo(wp.Position)
			else
				guardedMove(u, wp.Position)
			end
			return
		end
	end
	-- No path (yet): steer around obstacles, never off an edge.
	if not safeMove(u, dest) then
		u.pathFailed = true
	end
end

-- Something breakable between the creature and where it wants to go (doors, walls...).
local function findObstacle(u, dest)
	local pos = u.root.Position
	local dir = dest - pos
	if dir.Magnitude < 0.1 then
		return nil
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { workspace.NPCs, workspace.Effects }
	local hit = workspace:Raycast(pos, dir.Unit * 10, params)
	if hit then
		local e = G.Repair.entryOf(hit.Instance)
		if e and (e.inst:GetAttribute("Health") or 0) > 0 then
			return e
		end
	end
	-- No direct hit: nearest intact door / structure roughly in the travel direction.
	local best, bestD
	for _, d in pairs(G.Doors.list) do
		if not d.open and (d.model:GetAttribute("Health") or 0) > 0 then
			local delta = d.panel.Position - pos
			local dist = delta.Magnitude
			if dist > 0.1 and dist < 45 and delta.Unit:Dot(dir.Unit) > 0.2 and (not bestD or dist < bestD) then
				best, bestD = G.Repair.entries[d.model], dist
			end
		end
	end
	for _, s in ipairs(G.Building.structures) do
		local p = s.model:GetPivot().Position
		local delta = p - pos
		local dist = delta.Magnitude
		if dist < 25 and dist > 0.1 and delta.Unit:Dot(dir.Unit) > 0.4 and (not bestD or dist < bestD) then
			best, bestD = G.Repair.entries[s.model], dist
		end
	end
	return best
end

local function attackEntry(u, e, now, damage)
	local C = u.C
	local pos = u.root.Position
	local target = e.part and e.part.Position or e.inst:GetPivot().Position
	local flat = Vector3.new(target.X - pos.X, 0, target.Z - pos.Z)
	if flat.Magnitude > C.StructureRange or math.abs(target.Y - pos.Y) > 8 or not AI.visible(pos, target, e.inst, u.model) then
		moveTo(u, Vector3.new(target.X, pos.Y, target.Z), now)
		return false
	end
	u.hum:MoveTo(pos)
	setState(u, "Attack")
	if now >= u.nextAttack then
		u.nextAttack = now + C.AttackCooldown
		G.Repair.damage(e.inst, damage)
		AI.noise(target, 40)
		SFX.play("Slam", u.root)
	end
	return true
end

-- Is the prey somewhere we cannot walk to (above us, path failed or stuck)?
local function unreachable(u, targetPos)
	local pos = u.root.Position
	local rise = targetPos.Y - pos.Y
	local flat = Vector3.new(targetPos.X - pos.X, 0, targetPos.Z - pos.Z).Magnitude
	if flat > 70 then
		return false
	end
	return (u.pathFailed and (rise > 4 or flat < 30)) or (u.stuck and rise > 3) or (rise > 9 and flat < 16)
end

-- Search pattern: last position, then along the escape direction, then a remembered hideout.
local function planSearch(u, from)
	local pts = { from }
	local v = u.lastVelocity
	if v and v.Magnitude > 2 then
		table.insert(pts, from + v.Unit * 18)
		table.insert(pts, from + v.Unit * 34)
	else
		local a = math.random() * math.pi * 2
		table.insert(pts, from + Vector3.new(math.cos(a) * 16, 0, math.sin(a) * 16))
	end
	local hide = AI.nearestHideout(from, 120, from)
	if hide then
		table.insert(pts, hide)
	end
	u.search = pts
	-- Discard search points hanging over the ocean or above an obstructed deck.
	local walkable = {}
	for _,point in ipairs(pts) do
		local landing = AI.findLanding(point,u.root.Position,{0,3,6})
		if landing then table.insert(walkable,landing) end
	end
	u.search = walkable
	u.searchIndex = 1
end

local function think(u, now, dt, profile)
	local C = u.C
	local brain, mind = u.brain, u.mind
	local pos = u.root.Position
	if pos.Y < Config.WaterLevel + 3 then
		-- Fell or was knocked into the sea: climb straight back out towards its prey.
		if AI.anyPlayerWithin(pos, 220) then
			if now >= (u.nextRescue or 0) then
				u.nextRescue = now + 3
				local goal = u.lastKnown
				if not goal then
					local info = AI.nearestPlayer(pos, 220, false)
					goal = info and info.root.Position
				end
				if goal and Climber.climbOut(u, goal) then
					return
				end
			end
		else
			dive(u)
			return
		end
	end
	if not AI.anyPlayerWithin(pos, C.ActivationRange) then
		u.hum:MoveTo(pos) -- dormant far from every player
		return
	end
	local speedNow = u.root.AssemblyLinearVelocity.Magnitude
	if u.skitter then
		u.skitter.Playing = speedNow > 6
	end
	if now >= u.nextGrowl then
		u.nextGrowl = now + math.random(5, 12)
		if u.state ~= "Lurk" then
			AI.cry(u, math.random() < 0.5 and "Growl" or "GrowlLow", 3)
		end
	end

	-- Light: burns and repels (saboteurs push through while healthy).
	local dps, lightPos, lamp = AI.lightAt(pos)
	if dps <= 0 then
		local beamer, origin = AI.focusedBeam(pos, 34)
		if beamer then
			if brain >= 2 and u.hum.Health > C.Health * 0.5 and now >= (u.dodgeUntil or 0) + 1.5 then
				-- Side-step out of the cone and keep coming.
				local away = pos - origin
				local side = Vector3.new(-away.Z, 0, away.X)
				if side.Magnitude > 0.1 then
					u.dodgeUntil = now + 0.8
					u.dodgeDir = side.Unit * (math.random() < 0.5 and -1 or 1)
				end
				u.hum:TakeDamage((C.LightDamage + 1) * dt)
			else
				dps, lightPos = C.LightDamage + 1, origin
				u.aggro = nil
			end
		end
	end
	if u.dodgeUntil and now < u.dodgeUntil and u.dodgeDir then
		u.hum.WalkSpeed = C.ChaseSpeed + 4
		safeMove(u, pos + u.dodgeDir * 12)
		return
	end
	if dps > 0 then
		u.lastLit = now
		u.exposure += dt
		u.hum:TakeDamage(dps * dt * C.LightDamage / Config.Climber.LightDamage)
		local charging = u.role == "Saboteur" and lamp ~= nil and u.hum.Health > C.Health * 0.4
		if charging then
			u.lampTarget = lamp
		elseif C.fearless then
			-- The Pale burns and keeps coming.
		elseif u.state ~= "Retreat" then
			setState(u, "Retreat")
			AI.cry(u, "Shriek", 3)
			u.fleeFrom = lightPos
		end
	else
		u.exposure = math.max(0, u.exposure - dt * 0.5)
		-- Heals in the dark while it is not fighting.
		if brain >= 3 and now - u.lastLit > 6 and u.state ~= "Chase" and u.state ~= "Attack" and u.hum.Health < u.hum.MaxHealth then
			u.hum.Health = math.min(u.hum.MaxHealth, u.hum.Health + 2.5 * dt)
		end
	end

	if u.state == "Retreat" then
		if u.hum.Health < C.Health * 0.3 or u.exposure > 5 or u.fleeing then
			local edge, d = nearestEdge(pos)
			if edge and d < 160 then
				u.fleeing = true
				if d < 6 then
					dive(u)
				else
					moveTo(u, edge.Position, now)
				end
				return
			end
		end
		if now - u.lastLit > 2.5 then
			setState(u, "Investigate")
		else
			local away = pos - (u.fleeFrom or pos)
			away = Vector3.new(away.X, 0, away.Z)
			away = away.Magnitude > 0.1 and away.Unit or Vector3.new(math.random() - 0.5, 0, math.random() - 0.5).Unit
			safeMove(u, pos + away * 16)
		end
		return
	end

	-- Feint: wounded, it backs off into the dark... then comes straight back.
	if u.state == "Regroup" then
		if now >= (u.regroupUntil or 0) then
			setState(u, "Chase")
			u.hum.WalkSpeed = C.ChaseSpeed + 5
			AI.cry(u, "Shriek", 2)
		else
			local away = pos - (u.regroupFrom or pos)
			away = Vector3.new(away.X, 0, away.Z)
			away = away.Magnitude > 0.1 and away.Unit or Vector3.new(1, 0, 0)
			safeMove(u, pos + away * 14)
			return
		end
	end

	-- Flashlight flinch.
	if now < u.flinchUntil then
		u.hum:MoveTo(pos)
		return
	end
	if now - u.lastFlinch > 3 and AI.flashlightOn(pos, C.FlashlightRange) then
		u.lastFlinch = now
		u.flinchUntil = now + 0.7
		u.model:SetAttribute("State", "Flinch")
		return
	end

	if u.state == "Idle" and now - u.stateSince < 1.2 then
		u.hum:MoveTo(pos)
		return
	end

	-- Stuck detection every 2 s.
	if now >= u.lastMoveCheck then
		local moving = u.state == "Chase" or u.state == "Investigate" or u.state == "Patrol" or u.state == "Search" or u.state == "Stalk"
		u.stuck = moving and (pos - u.lastPos).Magnitude < 1.5
		u.lastPos = pos
		u.lastMoveCheck = now + 2
		if u.stuck and not u.obstacle then
			u.nextPath = 0
			u.waypoints = nil
			u.hum.Jump = true
		end
	end

	-- Current obstacle: keep hitting it until it breaks.
	if u.obstacle then
		if not u.obstacle.inst.Parent or (u.obstacle.inst:GetAttribute("Health") or 0) <= 0 or now - (u.obstacleSince or now) > 25 then
			u.obstacle = nil
		else
			attackEntry(u, u.obstacle, now, C.StructureDamage)
			return
		end
	end

	-- Saboteur: smash the lamp it is charging.
	if u.lampTarget then
		if not u.lampTarget.on or not u.lampTarget.model.Parent then
			u.lampTarget = nil
		else
			local e = G.Repair.entries[u.lampTarget.model]
			if e then
				attackEntry(u, e, now, C.LampDamage)
				return
			end
			u.lampTarget = nil
		end
	end

	-- Keep a target while it is sensed, then search only its last known position.
	local victim, dist, visible = AI.acquire(u, now, C.SightRange, C.HearRange)
	if victim then
		u.search = nil
		local vpos = victim.root.Position
		-- Flankers break line of sight, then reappear from cover; no teleporting.
		if brain >= 3 and visible and dist>18 and dist<80 and (u.packRole=="Flank" or u.packRole=="Behind")
			and AI.lookingAt(victim.player,pos+Vector3.new(0,2,0),90) then
			local cover = AI.coverPoint(u,victim,now)
			if cover and (cover-pos).Magnitude>4 then
				setState(u,"Stalk")
				moveTo(u,cover,now)
				return
			end
		end
		if dist <= C.AttackRange and visible then
			setState(u, "Attack")
			guardedMove(u, vpos)
			AI.strike(u, victim, now, C.AttackRange, C.Damage, C.name, C.AttackCooldown)
			return
		end
		-- Hurt: fake a retreat (once), then come back from the dark.
		if brain >= 3 and not u.feinted and u.hum.Health < C.Health * 0.4 and math.random() < 0.6 then
			u.feinted = true
			u.regroupUntil = now + math.random(2, 4)
			u.regroupFrom = vpos
			setState(u, "Regroup")
			return
		end
		-- Nowhere is out of reach.
		if unreachable(u, vpos) and Climber.scale(u, vpos, now) then
			return
		end
		-- Stalking: moves while you look away, freezes while you watch, rushes when close.
		if brain >= 2 and u.stalker and visible and dist > 20 and dist < 80 and G.DayCycle.isNight() then
			if AI.lookingAt(victim.player, pos + Vector3.new(0, 2, 0), 90) then
				u.watched += dt
				if u.watched < 2.6 then
					setState(u, "Stalk")
					u.model:SetAttribute("State", "Still")
					u.hum:MoveTo(pos)
					return
				end
				-- Watched too long: slip out of sight sideways.
				u.watched = 0
				local side = Vector3.new(-(vpos - pos).Z, 0, (vpos - pos).X)
				if side.Magnitude > 0.1 then
					u.dodgeUntil = now + 0.9
					u.dodgeDir = side.Unit * (math.random() < 0.5 and -1 or 1)
				end
				return
			end
			u.watched = math.max(0, u.watched - dt)
			setState(u, "Stalk")
			u.model:SetAttribute("State", "Stalk")
			moveTo(u, AI.pursuitPoint(u, victim, visible), now)
			return
		end
		setState(u, "Chase")
		local destination = brain >= 2 and AI.pursuitPoint(u, victim, visible) or vpos
		moveTo(u, destination, now)
		if (u.stuck or u.pathFailed) and profile.doorBreakers and not C.noDoors then
			local e = findObstacle(u, destination)
			if e then
				u.obstacle = e
				u.obstacleSince = now
			end
		end
		return
	elseif u.lastKnown then
		if brain < 2 then
			-- It has no idea where you went, and does not try to find out.
			u.lastKnown = nil
		elseif not u.search then
			planSearch(u, u.lastKnown)
		end
	end

	-- Sweep the search points, then lie in wait.
	if u.search then
		local point = u.search[u.searchIndex]
		if point then
			setState(u, "Search")
			if (point - pos).Magnitude < 6 then
				u.searchIndex += 1
			else
				moveTo(u, point, now)
				if unreachable(u, point) then
					Climber.scale(u, point, now)
				elseif (u.stuck or u.pathFailed) and profile.doorBreakers and not C.noDoors then
					local e = findObstacle(u, point)
					if e then
						u.obstacle = e
						u.obstacleSince = now
					end
				end
			end
			return
		end
		u.search = nil
		u.lurkUntil = now + mind.lurk * (0.7 + math.random() * 0.6)
	end
	if u.lurkUntil and now < u.lurkUntil then
		setState(u, "Lurk")
		u.hum:MoveTo(pos)
		return
	end
	u.lurkUntil = nil

	-- Saboteurs look for a lit floodlight.
	if u.role == "Saboteur" and not u.lampTarget then
		local best, bestD
		for _, e in ipairs(G.Power.lamps) do
			if e.on then
				local d = (e.lamp.Position - pos).Magnitude
				if d < 90 and (not bestD or d < bestD) then
					best, bestD = e, d
				end
			end
		end
		if best then
			u.lampTarget = best
			return
		end
	end

	-- Noise / the humming generator.
	local heard = AI.hear(pos)
	if heard then
		setState(u, "Investigate")
		local gen = G.Power.core.Position
		if (heard - gen).Magnitude < 3 then
			local e = G.Repair.entries[G.Power.generator]
			if e and (G.Power.generator:GetAttribute("Health") or 0) > 0 then
				local flat = Vector3.new(gen.X - pos.X, 0, gen.Z - pos.Z).Magnitude
				if flat <= C.StructureRange + 3 then
					attackEntry(u, { inst = G.Power.generator, part = G.Power.core }, now, C.GeneratorDamage)
					return
				end
			end
		end
		moveTo(u, heard, now)
		if (u.stuck or u.pathFailed) and profile.doorBreakers and not C.noDoors then
			local e = findObstacle(u, heard)
			if e then
				u.obstacle = e
				u.obstacleSince = now
			end
		end
		return
	end

	-- No leads: check a remembered hideout, otherwise patrol between deck points.
	if brain >= 2 and (not u.checkedHideout or now - u.checkedHideout > 30) then
		local hide = AI.nearestHideout(pos, 160)
		if hide then
			u.checkedHideout = now
			planSearch(u, hide)
			return
		end
	end
	-- Hunting instinct: at night it always ends up heading for someone.
	if brain >= 2 and G.DayCycle.isNight() and now >= (u.nextInstinct or 0) then
		u.nextInstinct = now + mind.instinct
		local info = AI.nearestPlayer(pos, 450, false)
		if info then
			local jitter = Vector3.new(math.random(-14, 14), 0, math.random(-14, 14))
			planSearch(u, info.root.Position + jitter)
			return
		end
	end
	setState(u, "Patrol")
	if not u.patrolDest or (u.patrolDest - pos).Magnitude < 5 or now - u.stateSince > 20 then
		local pts = G.World.patrolPoints
		if #pts == 0 then
			u.hum:MoveTo(pos)
			return
		end
		u.patrolDest = pts[math.random(1, #pts)]
		u.stateSince = now
	end
	moveTo(u, u.patrolDest, now)
end

function Climber.onHit(model, player)
	local u = unitOf(model)
	if not u or u.state == "Climb" or u.state == "Dive" or u.root.Anchored then
		return
	end
	u.aggro = player
	u.lurkUntil = nil
	local c = player and player.Character
	local r = c and c:FindFirstChild("HumanoidRootPart")
	if r then
		local dir = u.root.Position - r.Position
		local flat = Vector3.new(dir.X, 0, dir.Z)
		if flat.Magnitude > 0.1 and not u.C.heavy then
			local safe = groundAt(u.root.Position + flat.Unit * 7) ~= nil
			u.root.AssemblyLinearVelocity = (safe and flat.Unit * 26 or Vector3.zero) + Vector3.new(0, 10, 0)
		end
	end
	AI.cry(u, "Snarl", 0.6)
	u.flinchUntil = os.clock() + 0.4
end

local function die(u)
	u.model:SetAttribute("State", "Dead")
	u.root.Anchored = true
	AI.died(u.model, os.clock() - u.lastLit < 1.5)
	for _, s in ipairs({ u.breath, u.skitter }) do
		if s then
			s:Stop()
		end
	end
	for _, p in ipairs(u.model:GetDescendants()) do
		if p:IsA("BasePart") and p.Name ~= "HumanoidRootPart" then
			TweenService:Create(p, TweenInfo.new(1.5), { Transparency = 1, Color = Color3.new(0, 0, 0) }):Play()
		elseif p:IsA("Light") then
			p.Enabled = false
		end
	end
	task.delay(1.6, function()
		if u.model.Parent then
			u.model:Destroy()
		end
	end)
end

function Climber.step(now, dt)
	local profile = G.Director.profile
	refreshNavFilter()
	for i = #Climber.units, 1, -1 do
		local u = Climber.units[i]
		if not u.model.Parent then
			if u.blocked then
				u.blocked:Disconnect()
			end
			table.remove(Climber.units, i)
		elseif u.hum.Health <= 0 then
			if u.blocked then
				u.blocked:Disconnect()
			end
			table.remove(Climber.units, i)
			die(u)
		elseif u.state ~= "Climb" and u.state ~= "Dive" and not u.root.Anchored then
			if u.leaving then
				local edge, d = nearestEdge(u.root.Position)
				if not edge or d < 6 or d > 200 or now - u.leaving > 25 then
					dive(u)
				else
					u.hum.WalkSpeed = u.C.ChaseSpeed
					moveTo(u, edge.Position, now)
				end
			else
				local ok, err = pcall(think, u, now, dt, profile)
				if not ok then
					warn("[Climber] " .. tostring(err))
				end
				edgeBrake(u)
			end
		end
	end
end

-- Dawn: every Climber runs back to the sea.
function Climber.retreatAll()
	local now = os.clock()
	for _, u in ipairs(Climber.units) do
		u.leaving = now
		u.model:SetAttribute("State", "Retreat")
	end
end

function Climber.clear()
	for _, u in ipairs(Climber.units) do
		if u.blocked then
			u.blocked:Disconnect()
		end
		if u.model.Parent then
			u.model:Destroy()
		end
	end
	Climber.units = {}
end

return Climber
