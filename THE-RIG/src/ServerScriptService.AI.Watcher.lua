-- ServerScriptService/AI/Watcher
-- THE WATCHER. A colossal figure standing in the fog far from the rig. It rarely attacks:
-- it watches. Powered floodlights draw its attention. If attention fills up it "calls" a
-- wave of Climbers and sinks. Turn the lights off and it loses interest and leaves.
-- Server-anchored model moved a few times per second (no physics, no pathfinding).
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Modules.Config)
local SFX = require(ReplicatedStorage.Modules.SFX)

local Watcher = { model = nil }
local W = Config.Watcher
local G, AI

local BODY = Color3.fromRGB(16, 20, 22)

local function part(model, name, size, cf, color, material)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color or BODY
	p.Material = material or Enum.Material.Slate
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Parent = model
	return p
end

local function build(base)
	local model = Instance.new("Model")
	model.Name = "The Watcher"
	local rad = math.rad
	local BONE = Color3.fromRGB(58, 56, 50)
	-- A starved, hunched giant: thin ribbed torso, spine ridge, arms long enough to trail in
	-- the sea, a long skull with a hanging jaw and hollow sockets with pin-point eyes.
	local function limb(name, a, b, thick, color)
		local la, lb = base * a, base * b
		local mid = (la + lb) / 2
		return part(model, name, Vector3.new(thick, thick, (lb - la).Magnitude + thick * 0.5), CFrame.lookAt(mid, lb), color)
	end
	local body = part(model, "Body", Vector3.new(14, 64, 11), base * CFrame.new(0, 55, 0) * CFrame.Angles(rad(-8), 0, 0))
	model.PrimaryPart = body
	part(model, "Pelvis", Vector3.new(18, 8, 12), base * CFrame.new(0, 21, 1))
	for i = 0, 5 do
		part(model, "Rib", Vector3.new(16.5 - i * 0.4, 1.6, 12.6), base * CFrame.new(0, 62 + i * 5, -0.6 - i * 0.7) * CFrame.Angles(rad(-8), 0, 0), BONE)
	end
	for i = 0, 7 do
		part(model, "Spine", Vector3.new(3.4, 4, 3.4), base * CFrame.new(0, 28 + i * 9, 6 + i * 0.4), BONE)
	end
	for _, s in ipairs({ -1, 1 }) do
		part(model, "Shoulder", Vector3.new(10, 10, 10), base * CFrame.new(s * 12, 88, -1), nil, nil).Shape = Enum.PartType.Ball
		limb("UpperArm", Vector3.new(s * 13, 88, -1), Vector3.new(s * 20, 42, -8), 5)
		limb("Forearm", Vector3.new(s * 20, 42, -8), Vector3.new(s * 17, -6, -14), 4)
		for k = -1.5, 1.5 do
			limb("Finger", Vector3.new(s * 17 + k * 1.3, -6, -14), Vector3.new(s * 17 + k * 2.2, -22, -17), 1.1, BONE)
		end
		limb("Leg", Vector3.new(s * 6, 18, 1), Vector3.new(s * 8, -40, 3), 6)
	end
	limb("Neck", Vector3.new(0, 88, -2), Vector3.new(0, 100, -10), 6)
	local head = part(model, "Head", Vector3.new(12, 20, 15), base * CFrame.new(0, 106, -14) * CFrame.Angles(rad(-22), 0, 0))
	part(model, "Jaw", Vector3.new(10, 3.5, 12), head.CFrame * CFrame.new(0, -11, -3) * CFrame.Angles(rad(28), 0, 0), BONE)
	for _, s in ipairs({ -1, 1 }) do
		part(model, "EyeSocket", Vector3.new(4.2, 3.2, 1), head.CFrame * CFrame.new(s * 3, 3, -7.4), Color3.fromRGB(2, 2, 3))
		local eye = part(model, "Eye", Vector3.new(1.3, 1, 0.6), head.CFrame * CFrame.new(s * 3, 3, -8), Color3.fromRGB(255, 240, 200), Enum.Material.Neon)
		eye.Name = "Eye"
	end
	local glow = Instance.new("PointLight")
	glow.Name = "EyeGlow"
	glow.Color = Color3.fromRGB(255, 230, 180)
	glow.Range = 60
	glow.Brightness = 1
	glow.Parent = head
	pcall(function()
		model.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	end)
	return model
end

function Watcher.init(g, ai)
	G = g
	AI = ai
end

function Watcher.position()
	if Watcher.model and Watcher.model.Parent then
		return Watcher.model.PrimaryPart.Position
	end
	return nil
end

function Watcher.appear(force)
	if not AI.allowed(force) or Watcher.model then
		return
	end
	local angle = math.random() * math.pi * 2
	local dist = math.random(W.MinDistance, W.MaxDistance)
	local ground = Vector3.new(math.cos(angle) * dist, Config.WaterLevel - 50, math.sin(angle) * dist)
	local facing = CFrame.lookAt(ground, Vector3.new(0, ground.Y, 0))
	local model = build(facing * CFrame.new(0, -140, 0))
	model.Parent = G.World.NPCs
	Watcher.model = model
	Watcher.base = facing
	Watcher.attention = 0
	Watcher.dark = 0
	Watcher.leaveAt = os.clock() + math.random(W.StayMin, W.StayMax)
	Watcher.angle = angle
	Watcher.dist = dist
	Watcher.rising = true
	AI.register(model, "Watcher")
	local cf0 = model:GetPivot()
	local value = Instance.new("CFrameValue")
	value.Value = cf0
	value.Changed:Connect(function(v)
		if model.Parent then
			model:PivotTo(v)
		end
	end)
	local t = TweenService:Create(value, TweenInfo.new(14, Enum.EasingStyle.Sine), { Value = cf0 * CFrame.new(0, 140, 0) })
	t.Completed:Connect(function()
		value:Destroy()
		Watcher.rising = false
	end)
	t:Play()
	G.Net.toastAll("Something enormous is standing in the fog.", "warn")
	SFX.play("Horn", model:FindFirstChild("Head"))
end

function Watcher.leave(called)
	local model = Watcher.model
	if not model then
		return
	end
	Watcher.model = nil
	local cf0 = model:GetPivot()
	local value = Instance.new("CFrameValue")
	value.Value = cf0
	value.Changed:Connect(function(v)
		if model.Parent then
			model:PivotTo(v)
		end
	end)
	local t = TweenService:Create(value, TweenInfo.new(called and 6 or 12, Enum.EasingStyle.Sine, Enum.EasingDirection.In), { Value = cf0 * CFrame.new(0, -170, 0) })
	t.Completed:Connect(function()
		value:Destroy()
		model:Destroy()
	end)
	t:Play()
end

local function setEyes(model, brightness, color)
	for _, p in ipairs(model:GetDescendants()) do
		if p.Name == "Eye" and p:IsA("BasePart") then
			p.Color = color
		elseif p.Name == "EyeGlow" then
			p.Brightness = brightness
			p.Color = color
		end
	end
end

function Watcher.step(now, dt)
	local model = Watcher.model
	if not model or not model.Parent then
		Watcher.model = nil
		return
	end
	-- Slow drift around the rig.
	if not Watcher.rising then
		Watcher.angle += dt * 0.004
		-- Pivot is the body centre: 55 studs above its feet, which stand 50 studs below the surface.
		local pos = Vector3.new(math.cos(Watcher.angle) * Watcher.dist, Config.WaterLevel + 5, math.sin(Watcher.angle) * Watcher.dist)
		-- It turns to stare at the nearest player.
		local look = Vector3.new(0, pos.Y, 0)
		local info = AI.nearestPlayer(pos, 2000, false)
		if info then
			look = Vector3.new(info.root.Position.X, pos.Y, info.root.Position.Z)
		end
		Watcher.facing = (Watcher.facing or look):Lerp(look, math.clamp(dt * 0.6, 0, 1))
		model:PivotTo(CFrame.lookAt(pos, Watcher.facing))
	end
	local lit = 0
	for _, e in ipairs(G.Power.lamps) do
		if e.on then
			lit += 1
		end
	end
	if lit > 0 then
		Watcher.attention += dt * (0.6 + lit * 0.12)
		Watcher.dark = 0
	else
		Watcher.attention = math.max(0, Watcher.attention - dt * 0.5)
		Watcher.dark += dt
	end
	local a = math.clamp(Watcher.attention / W.AttentionLimit, 0, 1)
	setEyes(model, 1 + a * 6, Color3.fromRGB(255, math.floor(240 - a * 190), math.floor(200 - a * 170)))
	G.State.set("WatcherAttention", math.floor(a * 100))
	if Watcher.attention >= W.AttentionLimit then
		G.Net.banner("THE WATCHER HAS NOTICED THE LIGHTS", "It calls to the deep. Climbers incoming.", "danger")
		G.Net.effectAll("Shake", 0.4, 2)
		SFX.play("Horn", model:FindFirstChild("Head"), { speed = 1.2 })
		G.Director.spawnWave(3 + math.floor(G.DayCycle.day / 10), true)
		G.State.set("WatcherAttention", 0)
		Watcher.leave(true)
	elseif Watcher.dark > 25 then
		G.Net.toastAll("The Watcher lost interest and sank into the fog.", "good")
		G.State.set("WatcherAttention", 0)
		Watcher.leave(false)
	elseif now > Watcher.leaveAt then
		G.State.set("WatcherAttention", 0)
		Watcher.leave(false)
	end
end

return Watcher
