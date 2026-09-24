-- ServerScriptService/AI/Lurker
-- THE LURKER: an eel-like hunter of the open water. At night (and in the deep by day) it
-- finds players who are swimming or at sea in a boat. It circles below the surface, closes
-- in, then lunges: bites swimmers, rams boats. Light (flares, focused beams, floodlights)
-- and crowbar hits drive it off. It can never leave the water: climb out to be safe.
-- Server-anchored model moved at 5 Hz with short tweens (no physics, no pathfinding).
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Modules.Config)
local SFX = require(ReplicatedStorage.Modules.SFX)

local Lurker = { units = {} }
local L = Config.Lurker
local G, AI

local SKIN = Color3.fromRGB(22, 34, 38)
local BELLY = Color3.fromRGB(70, 84, 80)
local EYE = Color3.fromRGB(120, 255, 210)

function Lurker.init(g, ai)
	G = g
	AI = ai
end

function Lurker.count()
	return #Lurker.units
end

local function build(cf)
	local model = Instance.new("Model")
	model.Name = "The Lurker"
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = Vector3.new(3, 3, 3)
	root.Transparency = 1
	root.Anchored = true
	root.CanCollide = false
	root.CanTouch = false
	root.CFrame = cf
	root.Parent = model
	model.PrimaryPart = root
	local function seg(name, size, offset, color, material, shape)
		local p = Instance.new("Part")
		p.Name = name
		p.Size = size
		p.CFrame = cf * offset
		p.Color = color or SKIN
		p.Material = material or Enum.Material.SmoothPlastic
		p.Reflectance = 0.08
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		if shape then
			p.Shape = shape
		end
		p.Parent = model
		return p
	end
	for i = 0, 6 do
		local s = 4.2 - i * 0.45
		seg("Body", Vector3.new(s, s * 0.8, s * 1.4), CFrame.new(0, 0, i * 3.2), SKIN, nil, Enum.PartType.Ball)
	end
	seg("Head", Vector3.new(4.4, 3, 5.5), CFrame.new(0, 0.2, -3), SKIN, nil, Enum.PartType.Ball)
	seg("Jaw", Vector3.new(3.6, 0.8, 4.2), CFrame.new(0, -1.2, -3.8) * CFrame.Angles(math.rad(12), 0, 0), BELLY)
	for _, side in ipairs({ -1, 1 }) do
		seg("Eye", Vector3.new(0.5, 0.5, 0.5), CFrame.new(side * 1.3, 0.9, -5.2), EYE, Enum.Material.Neon, Enum.PartType.Ball)
		seg("Fin", Vector3.new(4, 0.3, 2), CFrame.new(side * 2.6, 0, 1.5) * CFrame.Angles(0, 0, side * math.rad(20)), SKIN)
		for k = 0, 2 do
			seg("Tooth", Vector3.new(0.18, 0.7, 0.18), CFrame.new(side * (0.5 + k * 0.45), -0.9, -5.6 + k * 0.4), Color3.fromRGB(220, 214, 196))
		end
	end
	seg("Dorsal", Vector3.new(0.3, 2.4, 5), CFrame.new(0, 2, 4), SKIN)
	seg("Tail", Vector3.new(0.3, 3.2, 3.5), CFrame.new(0, 0, 23), SKIN)
	local glow = Instance.new("PointLight")
	glow.Color = EYE
	glow.Range = 10
	glow.Brightness = 1.2
	glow.Parent = model:FindFirstChild("Head")
	local hum = Instance.new("Humanoid")
	hum.MaxHealth = L.Health
	hum.Health = L.Health
	hum.RequiresNeck = false
	hum.BreakJointsOnDeath = false
	hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	hum.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	pcall(function()
		hum.EvaluateStateMachine = false
	end)
	hum.Parent = model
	pcall(function()
		model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	end)
	return model, root, hum
end

-- Players in the water, and boats with a driver, are prey.
local function preyList()
	local list = {}
	for _, info in ipairs(G.Util.alivePlayers()) do
		if info.player:GetAttribute("InWater") then
			table.insert(list, { kind = "swimmer", pos = info.root.Position, info = info })
		end
	end
	for _, b in ipairs(G.Boats.list) do
		if b.seat and b.seat.Occupant and b.model.Parent then
			table.insert(list, { kind = "boat", pos = b.hull.Position, boat = b })
		end
	end
	return list
end

local function floorY(pos)
	local deep = math.abs(pos.X) < 1024 and math.abs(pos.Z) < 1024
	return deep and (Config.SeabedY + 6) or -20
end

local function clampDepth(p)
	return Vector3.new(p.X, math.clamp(p.Y, floorY(p), Config.WaterLevel - 2.5), p.Z)
end

function Lurker.spawn(target)
	if not AI.allowed(target.force) then
		return nil
	end
	local a = math.random() * math.pi * 2
	local d = math.random(90, 140)
	local p = clampDepth(Vector3.new(target.pos.X + math.cos(a) * d, target.pos.Y - 10, target.pos.Z + math.sin(a) * d))
	local model, root, hum = build(CFrame.lookAt(p, target.pos))
	model.Parent = G.World.NPCs
	AI.register(model, "Lurker")
	local u = {
		model = model,
		root = root,
		hum = hum,
		pos = p,
		heading = (target.pos - p).Unit,
		state = "Circle",
		orbit = math.random() * math.pi * 2,
		orbitDir = math.random() < 0.5 and -1 or 1,
		nextLunge = os.clock() + math.random(4, 7),
		fleeUntil = 0,
		lostSince = nil,
	}
	u.rel = {}
	local base = root.CFrame:Inverse()
	for _, segment in ipairs(model:GetChildren()) do
		if segment:IsA("BasePart") and segment ~= root then
			u.rel[segment] = base * segment.CFrame
		end
	end
	model:SetAttribute("State", "Circle")
	SFX.play("Distant", root)
	table.insert(Lurker.units, u)
	return u
end

local function move(u, dest, speed, dt)
	local delta = dest - u.pos
	local dist = delta.Magnitude
	if dist > 0.1 then
		local step = math.min(dist, speed * dt)
		local dir = delta.Unit
		-- Smooth turning so it swims instead of snapping.
		local h = u.heading * 3 + dir
		u.heading = h.Magnitude > 0.01 and h.Unit or dir
		u.pos = clampDepth(u.pos + u.heading * step)
	end
	local cf = CFrame.lookAt(u.pos, u.pos + u.heading)
	TweenService:Create(u.root, TweenInfo.new(0.2, Enum.EasingStyle.Linear), { CFrame = cf }):Play()
	-- Body segments follow the root rigidly using offsets captured at spawn.
	for p, rel in pairs(u.rel) do
		if p.Parent then
			TweenService:Create(p, TweenInfo.new(0.2, Enum.EasingStyle.Linear), { CFrame = cf * rel }):Play()
		end
	end
end

local function nearestPrey(u, list)
	local best, bestD
	for _, prey in ipairs(list) do
		local d = (prey.pos - u.pos).Magnitude
		if d < L.SenseRange and (not bestD or d < bestD) then
			best, bestD = prey, d
		end
	end
	return best, bestD
end

local function leave(u)
	if u.leaving then
		return
	end
	u.leaving = true
	u.model:SetAttribute("State", "Leave")
end

local function think(u, now, dt, list)
	if u.leaving then
		move(u, u.pos + u.heading * 30 - Vector3.new(0, 20, 0), L.CircleSpeed, dt)
		if (u.leftAt or now) and now - (u.leftAt or now) > 6 then
			u.model:Destroy()
		end
		u.leftAt = u.leftAt or now
		return
	end
	-- Light: flares / focused beams / floodlights at the surface drive it away.
	local dps, lightPos = AI.lightAt(Vector3.new(u.pos.X, Config.WaterLevel, u.pos.Z))
	if dps <= 0 then
		local beamer, origin = AI.focusedBeam(u.pos, 45)
		if beamer then
			dps, lightPos = 6, origin
		end
	end
	if dps > 0 then
		u.hum:TakeDamage(dps * dt)
		u.fleeUntil = now + 6
		u.fleeFrom = lightPos
	end
	if now < u.fleeUntil then
		u.model:SetAttribute("State", "Retreat")
		local away = u.pos - (u.fleeFrom or u.pos)
		away = Vector3.new(away.X, 0, away.Z)
		away = away.Magnitude > 0.1 and away.Unit or u.heading
		move(u, u.pos + away * 40 - Vector3.new(0, 8, 0), L.LungeSpeed * 0.8, dt)
		return
	end

	local prey, dist = nearestPrey(u, list)
	if not prey then
		u.lostSince = u.lostSince or now
		if now - u.lostSince > 12 then
			leave(u)
		end
		move(u, u.pos + u.heading * 20, L.CircleSpeed * 0.6, dt)
		return
	end
	u.lostSince = nil
	local target = prey.pos
	if u.state == "Lunge" then
		move(u, Vector3.new(target.X, math.min(target.Y, Config.WaterLevel - 1.5), target.Z), L.LungeSpeed, dt)
		if (u.pos - target).Magnitude < 6 then
			if prey.kind == "swimmer" then
				local info = prey.info
				if not info.character:FindFirstChildOfClass("ForceField") then
					G.Survival.damage(info.humanoid, L.Damage, "The Lurker")
					G.Net.Effect:FireClient(info.player, "Hit", 0.9)
					-- Drag the victim down.
					info.root.AssemblyLinearVelocity = Vector3.new(0, -26, 0) + u.heading * 10
				end
			else
				G.Repair.damage(prey.boat.model, L.BoatDamage)
				prey.boat.hull.AssemblyLinearVelocity += u.heading * 25 + Vector3.new(0, 18, 0)
				local occupant = prey.boat.seat.Occupant
				local player = occupant and game:GetService("Players"):GetPlayerFromCharacter(occupant.Parent)
				if player then
					G.Net.Effect:FireClient(player, "Shake", 0.8, 0.6)
				end
			end
			u.state = "Circle"
			u.nextLunge = now + math.random(5, 8) - math.min(G.DayCycle.day / 30, 2.5)
			u.model:SetAttribute("State", "Circle")
		elseif now > u.lungeUntil then
			u.state = "Circle"
			u.nextLunge = now + 3
		end
		return
	end
	-- Circle below the prey, tightening over time, then lunge.
	u.model:SetAttribute("State", dist > 60 and "Stalk" or "Circle")
	u.orbit += dt * 0.9 * u.orbitDir
	local radius = math.clamp(dist * 0.5, 14, 30)
	local circlePoint = Vector3.new(target.X + math.cos(u.orbit) * radius, target.Y - 7, target.Z + math.sin(u.orbit) * radius)
	move(u, dist > 60 and target - Vector3.new(0, 8, 0) or circlePoint, L.CircleSpeed, dt)
	if now >= u.nextLunge and dist < 45 then
		u.state = "Lunge"
		AI.cry(u, "Shriek", 5)
		u.lungeUntil = now + 2
		u.model:SetAttribute("State", "Lunge")
	end
end

function Lurker.onHit(model)
	for _, u in ipairs(Lurker.units) do
		if u.model == model then
			u.fleeUntil = os.clock() + 4
			u.fleeFrom = u.pos + u.heading * 5
			u.state = "Circle"
		end
	end
end

-- 5 Hz from AIService. Spawns hunters for prey when it is dark (or deep by day).
local spawnTimer = 0
function Lurker.step(now, dt)
	local list = preyList()
	spawnTimer -= dt
	if spawnTimer <= 0 then
		spawnTimer = 4
		local night = G.DayCycle.isNight() or G.DayCycle.phase == "Evening"
		local maxUnits = L.MaxBase + math.floor(G.DayCycle.day / 15)
		for _, prey in ipairs(list) do
			local deep = prey.kind == "swimmer" and prey.pos.Y < -30
			local hunted = false
			for _, u in ipairs(Lurker.units) do
				if (u.pos - prey.pos).Magnitude < L.SenseRange then
					hunted = true
				end
			end
			if (night or deep) and G.Director.profile.lurkers and not hunted and #Lurker.units < maxUnits and math.random() < (night and 0.6 or 0.25) then
				Lurker.spawn(prey)
				G.Net.toastAll("Something large is moving under the water.", "danger")
			end
		end
	end
	for i = #Lurker.units, 1, -1 do
		local u = Lurker.units[i]
		if not u.model.Parent then
			table.remove(Lurker.units, i)
		elseif u.hum.Health <= 0 then
			table.remove(Lurker.units, i)
			u.model:SetAttribute("State", "Dead")
			for _, p in ipairs(u.model:GetDescendants()) do
				if p:IsA("BasePart") then
					TweenService:Create(p, TweenInfo.new(2), { Transparency = 1, CFrame = p.CFrame - Vector3.new(0, 15, 0) }):Play()
				end
			end
			task.delay(2.1, function()
				if u.model.Parent then
					u.model:Destroy()
				end
			end)
		else
			local ok, err = pcall(think, u, now, dt, list)
			if not ok then
				warn("[Lurker] " .. tostring(err))
			end
		end
	end
end

-- Dawn: the hunters sink back into the deep.
function Lurker.retreatAll()
	for _, u in ipairs(Lurker.units) do
		leave(u)
	end
end

return Lurker
