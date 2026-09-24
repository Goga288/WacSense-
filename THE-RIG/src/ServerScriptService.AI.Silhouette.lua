-- ServerScriptService/AI/Silhouette
-- THE TALL ONE. A black figure three times a man's height, with red eyes and white
-- pupils.
--
-- From day 20 it is only seen. It stands at the far end of a catwalk, on a roof, at
-- the edge of the light, and it watches. Look at it for too long, or walk towards it,
-- and it is gone -- and then it is somewhere else.
--
-- From night 40 it hunts. It moves only while nobody is looking at it, and every time
-- it moves it is closer. If it reaches you with your back turned it strikes and is
-- gone again. It will not stand in a floodlight, a focused flashlight beam drives it
-- off, and nothing that tall fits through a door: indoors is the one place it cannot
-- follow. It cannot be hurt.
--
-- Server-anchored and moved by placing it, never by walking: it is simply somewhere
-- else each time you look.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local SFX = require(ReplicatedStorage.Modules.SFX)

local Silhouette = { model = nil }
local G, AI

local TALL = 18 -- studs of clearance it needs; its crown is at 17.6
local WATCH_NEAR = 22 -- walk this close while it only watches and it leaves
local STARE = 1.2 -- seconds of being looked at that it will stand
local STRIKE = 7 -- reach, in studs
local DAMAGE = 45
local BLACK = Color3.fromRGB(5, 5, 7)
local RED = Color3.fromRGB(255, 20, 16)
local WHITE = Color3.fromRGB(255, 255, 255)

local function part(model, name, size, cf, color, material, shape)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color or BLACK
	p.Material = material or Enum.Material.SmoothPlastic
	p.Reflectance = 0
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	if shape then
		p.Shape = shape
	end
	p.Parent = model
	return p
end

-- Built standing at the origin with its feet on y = 0, so placing it is one PivotTo.
local function build()
	local model = Instance.new("Model")
	model.Name = "The Tall One"
	local rad = math.rad
	local feet = part(model, "Root", Vector3.new(1, 1, 1), CFrame.new(0, 0.5, 0))
	feet.Transparency = 1
	model.PrimaryPart = feet
	for _, s in ipairs({ -1, 1 }) do
		part(model, "Leg", Vector3.new(0.8, 8.4, 0.8), CFrame.new(s * 0.75, 4.2, 0) * CFrame.Angles(0, 0, s * rad(1.5)))
		-- Arms that hang past its knees, fingers longer than a hand should be.
		part(model, "Arm", Vector3.new(0.6, 9, 0.6), CFrame.new(s * 1.75, 9.4, -0.1) * CFrame.Angles(0, 0, s * rad(4)))
		for k = -1, 1 do
			part(model, "Finger", Vector3.new(0.14, 2.2, 0.14), CFrame.new(s * 2.05 + k * 0.18, 3.9, -0.15) * CFrame.Angles(0, 0, s * rad(6 + k * 4)))
		end
	end
	part(model, "Pelvis", Vector3.new(2.1, 1, 1), CFrame.new(0, 8.7, 0))
	part(model, "Torso", Vector3.new(2.4, 5.6, 1.1), CFrame.new(0, 11.8, 0) * CFrame.Angles(rad(-4), 0, 0))
	part(model, "Shoulders", Vector3.new(3.8, 0.8, 1), CFrame.new(0, 14.4, -0.1))
	part(model, "Neck", Vector3.new(0.5, 1.2, 0.5), CFrame.new(0, 15.2, -0.25) * CFrame.Angles(rad(-10), 0, 0))
	-- The head tilts, a little, as if it is listening.
	local head = part(model, "Head", Vector3.new(1.5, 2.1, 1.4), CFrame.new(0, 16.35, -0.45) * CFrame.Angles(rad(-6), 0, rad(9)))
	for _, s in ipairs({ -1, 1 }) do
		local cf = head.CFrame * CFrame.new(s * 0.36, 0.2, -0.68)
		part(model, "Eye", Vector3.new(0.46, 0.46, 0.46), cf, RED, Enum.Material.Neon, Enum.PartType.Ball)
		part(model, "Pupil", Vector3.new(0.17, 0.17, 0.17), cf * CFrame.new(0, 0, -0.2), WHITE, Enum.Material.Neon, Enum.PartType.Ball)
	end
	local glow = Instance.new("PointLight")
	glow.Name = "EyeGlow"
	glow.Color = RED
	glow.Range = 9
	glow.Brightness = 0.9
	glow.Shadows = false
	glow.Parent = head
	-- A thin black haze around it, so its edges never quite resolve.
	local haze = Instance.new("ParticleEmitter")
	haze.Texture = "rbxasset://textures/particles/smoke_main.dds"
	haze.Color = ColorSequence.new(Color3.fromRGB(0, 0, 0))
	haze.LightInfluence = 0
	haze.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 3), NumberSequenceKeypoint.new(1, 6) })
	haze.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.4, 0.8), NumberSequenceKeypoint.new(1, 1) })
	haze.Lifetime = NumberRange.new(2, 3)
	haze.Speed = NumberRange.new(0.2, 0.6)
	haze.SpreadAngle = Vector2.new(180, 180)
	haze.Rate = 4
	haze.Parent = model:FindFirstChild("Torso")
	pcall(function()
		model.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	end)
	return model, head
end

function Silhouette.init(g, ai)
	G = g
	AI = ai
end

function Silhouette.position()
	return Silhouette.model and Silhouette.base or nil
end

-- Where something seventeen studs tall can stand: level footing, not water, not in
-- a floodlight, and nothing solid anywhere in the column above it.
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
local overlap = OverlapParams.new()
overlap.FilterType = Enum.RaycastFilterType.Exclude
local function refreshFilters()
	local list = { workspace:FindFirstChild("NPCs"), workspace:FindFirstChild("Effects") }
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Character then
			table.insert(list, p.Character)
		end
	end
	rayParams.FilterDescendantsInstances = list
	overlap.FilterDescendantsInstances = list
end

local function standAt(x, z, fromY, depth)
	local hit = workspace:Raycast(Vector3.new(x, fromY, z), Vector3.new(0, -depth, 0), rayParams)
	if not hit or hit.Material == Enum.Material.Water or hit.Normal.Y < 0.8 then
		return nil
	end
	local base = hit.Position
	if workspace:Raycast(base + Vector3.new(0, 0.4, 0), Vector3.new(0, TALL, 0), rayParams) then
		return nil
	end
	for _, p in ipairs(workspace:GetPartBoundsInBox(CFrame.new(base + Vector3.new(0, TALL / 2 + 0.6, 0)), Vector3.new(3, TALL - 0.6, 3), overlap)) do
		if p.CanCollide then
			return nil
		end
	end
	if AI.lightAt(base + Vector3.new(0, 2, 0)) > 0 then
		return nil
	end
	return base
end

local function headAt(base)
	return base + Vector3.new(0, 16.5, 0)
end

-- Is anyone looking at a spot? Everyone, not only its prey: it will not move where
-- any of the crew would see it happen.
local function seen(pos)
	for _, p in ipairs(Players:GetPlayers()) do
		if AI.lookingAt(p, pos, 180) then
			return true
		end
	end
	return false
end

-- Out of the world entirely rather than transparent: a hidden figure must not show on
-- the cameras, count on the sonar, or be found by anything that looks for monsters.
local function hide()
	Silhouette.model:PivotTo(CFrame.new(0, -2000, 0))
	Silhouette.base = nil
end

local function place(base, facing)
	local flat = Vector3.new(facing.X - base.X, 0, facing.Z - base.Z)
	local look = flat.Magnitude > 0.1 and flat.Unit or Vector3.new(0, 0, -1)
	Silhouette.base = base
	Silhouette.model:PivotTo(CFrame.lookAt(base + Vector3.new(0, 0.5, 0), base + Vector3.new(0, 0.5, 0) + look))
end

-- A spot `distance` from `around`, preferring the directions `around` is not facing,
-- that satisfies `ok`. Its own height is searched from `around`'s height, so it lands
-- on the level its prey is on and not on the roof above.
local function spotNear(around, distance, facing, ok)
	local best
	for i = 0, 11 do
		local a = (i * 0.5236) + math.random() * 0.4
		local dir = Vector3.new(math.cos(a), 0, math.sin(a))
		-- Behind first: skip the forward half on the first pass.
		if not facing or dir:Dot(facing) < 0.2 or i >= 8 then
			local p = around + dir * distance
			local base = standAt(p.X, p.Z, around.Y + 6, 18) or standAt(p.X, p.Z, around.Y + 30, 60)
			if base and (not ok or ok(base)) then
				best = base
				break
			end
		end
	end
	return best
end

local function flatDistance(a, b)
	return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
end

-- Pick someone. It keeps its prey while that player lives and stays on the rig.
local function prey()
	local current = Silhouette.target
	for _, info in ipairs(G.Util.alivePlayers()) do
		if info.player == current then
			return info
		end
	end
	local alive = G.Util.alivePlayers()
	if #alive == 0 then
		return nil
	end
	local info = alive[math.random(1, #alive)]
	Silhouette.target = info.player
	return info
end

function Silhouette.appear(force)
	if not AI.allowed(force) or Silhouette.model then
		return
	end
	refreshFilters()
	local info = prey()
	if not info then
		return
	end
	local model, head = build()
	Silhouette.model = model
	Silhouette.head = head
	-- Far enough to be a shape, near enough to be seen: somewhere the player could see.
	local pos = info.root.Position
	local spot = spotNear(pos, math.random(45, 85), nil, function(base)
		return AI.visible(pos + Vector3.new(0, 2, 0), headAt(base), nil, info.character)
	end)
	if not spot then
		model:Destroy()
		Silhouette.model = nil
		return
	end
	place(spot, pos)
	model.Parent = G.World.NPCs
	AI.register(model, "Silhouette")
	Silhouette.stared = 0
	Silhouette.visits = 0
	Silhouette.nextAt = nil
	Silhouette.nextStep = os.clock() + 3
	Silhouette.nextStrike = 0
	Silhouette.want = false
end

-- The Director decides it comes tonight; it comes as soon as there is somewhere for it
-- to stand where it can be seen. Deciding and arriving are separate so that a crew
-- indoors at nightfall does not simply cancel it.
function Silhouette.summon(force)
	Silhouette.want = true
	Silhouette.force = force == true
	Silhouette.nextTry = 0
end

-- Gone from here; back somewhere else later, a few times a night.
local function vanish(now, backIn)
	SFX.play("Distant", Silhouette.head, { speed = 0.6 })
	hide()
	Silhouette.stared = 0
	Silhouette.visits += 1
	Silhouette.nextAt = now + backIn
end

local function reappear(now, hunting)
	refreshFilters()
	local info = prey()
	if not info then
		return
	end
	local pos = info.root.Position
	local spot
	if hunting then
		-- Back out in the dark, out of sight, and then it starts coming again.
		spot = spotNear(pos, math.random(55, 80), info.root.CFrame.LookVector, function(base)
			return not seen(headAt(base))
		end)
	else
		spot = spotNear(pos, math.random(45, 85), nil, function(base)
			return AI.visible(pos + Vector3.new(0, 2, 0), headAt(base), nil, info.character)
		end)
	end
	if not spot then
		Silhouette.nextAt = now + 4
		return
	end
	place(spot, pos)
	Silhouette.nextAt = nil
	Silhouette.nextStep = now + 2
end

local function strike(info, now)
	Silhouette.nextStrike = now + 3
	G.Survival.damage(info.humanoid, DAMAGE, "The Tall One")
	if info.player.Parent then
		G.Net.Effect:FireClient(info.player, "Hit", 0.9)
		G.Net.Effect:FireClient(info.player, "Scare", Silhouette.model)
	end
	SFX.play("Stinger", Silhouette.head)
	vanish(now, math.random(9, 16))
end

-- 5 Hz from AIService.
function Silhouette.step(now, dt)
	local model = Silhouette.model
	if not model then
		if Silhouette.want and now >= (Silhouette.nextTry or 0) then
			Silhouette.nextTry = now + 8
			Silhouette.appear(Silhouette.force)
		end
		return
	end
	if not model.Parent then
		Silhouette.model = nil
		return
	end
	local hunting = G.Director.profile.silhouetteHunts and G.DayCycle.isNight()
	if Silhouette.nextAt then
		if now >= Silhouette.nextAt and Silhouette.visits < (hunting and 12 or 4) then
			reappear(now, hunting)
		end
		return
	end
	local info = prey()
	if not info then
		return
	end
	local head = headAt(Silhouette.base)
	local watched = seen(head)
	-- It always faces its prey.
	place(Silhouette.base, info.root.Position)

	if not hunting then
		-- Only watching: it will not be stared at, and it will not be approached.
		if watched then
			Silhouette.stared += dt
		end
		if Silhouette.stared > STARE or flatDistance(info.root.Position, Silhouette.base) < WATCH_NEAR then
			vanish(now, math.random(18, 40))
		end
		return
	end

	-- Hunting. A focused beam in its face and it is gone.
	if AI.focusedBeam(head, 70) or AI.focusedBeam(head - Vector3.new(0, 8, 0), 70) then
		vanish(now, math.random(10, 18))
		return
	end
	-- Looked at, it does not move at all.
	if watched then
		return
	end
	local dist = flatDistance(info.root.Position, Silhouette.base)
	if dist <= STRIKE and math.abs(info.root.Position.Y - Silhouette.base.Y) < 8 then
		if now >= Silhouette.nextStrike then
			strike(info, now)
		end
		return
	end
	if now < Silhouette.nextStep then
		return
	end
	-- Faster the later it gets.
	Silhouette.nextStep = now + ((G.Director.profile.brain or 3) >= 4 and 1.1 or 1.7)
	refreshFilters()
	local pos = info.root.Position
	local closer = math.max(dist * 0.55, STRIKE - 2)
	local spot = spotNear(pos, closer, info.root.CFrame.LookVector, function(base)
		return not seen(headAt(base))
	end)
	if spot then
		place(spot, pos)
		if math.random() < 0.3 then
			SFX.play("Heartbeat", Silhouette.head, { speed = 0.8 })
		end
	end
end

function Silhouette.leave()
	if Silhouette.model then
		Silhouette.model:Destroy()
	end
	Silhouette.model = nil
	Silhouette.target = nil
	Silhouette.nextAt = nil
	Silhouette.want = false
end

return Silhouette
