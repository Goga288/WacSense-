-- ServerScriptService/Systems/Util
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Modules.Config)

local Util = {}

function Util.init(G)
	Util.G = G
end

function Util.prompt(part, action, object, hold, distance)
	local p = Instance.new("ProximityPrompt")
	p.ActionText = action
	p.ObjectText = object or ""
	p.HoldDuration = hold or 0
	p.MaxActivationDistance = distance or 10
	p.RequiresLineOfSight = false
	p.KeyboardKeyCode = Enum.KeyCode.E
	p.Style = Enum.ProximityPromptStyle.Default
	p.Parent = part
	return p
end

function Util.sound(parent, id, volume, speed)
	if not id or id == "" then
		return nil
	end
	local s = Instance.new("Sound")
	s.SoundId = id
	s.Volume = volume or 0.6
	s.PlaybackSpeed = speed or 1
	s.RollOffMaxDistance = 180
	s.Parent = parent
	s:Play()
	game:GetService("Debris"):AddItem(s, 8)
	return s
end

function Util.splash(position)
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Transparency = 1
	p.Size = Vector3.new(1, 1, 1)
	p.Position = Vector3.new(position.X, Config.WaterLevel + 0.5, position.Z)
	p.Parent = workspace:FindFirstChild("Effects") or workspace
	local e = Instance.new("ParticleEmitter")
	e.Texture = "rbxasset://textures/particles/smoke_main.dds"
	e.Color = ColorSequence.new(Color3.fromRGB(200, 220, 225))
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 2), NumberSequenceKeypoint.new(1, 6) })
	e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1) })
	e.Lifetime = NumberRange.new(0.8, 1.4)
	e.Speed = NumberRange.new(10, 18)
	e.SpreadAngle = Vector2.new(35, 35)
	e.Acceleration = Vector3.new(0, -30, 0)
	e.EmissionDirection = Enum.NormalId.Top
	e.Rate = 0
	e.Parent = p
	e:Emit(24)
	Util.sound(p, Config.Sounds.Splash, 0.8)
	game:GetService("Debris"):AddItem(p, 3)
end

function Util.shuffle(t)
	for i = #t, 2, -1 do
		local j = math.random(1, i)
		t[i], t[j] = t[j], t[i]
	end
	return t
end

function Util.weighted(weights)
	local total = 0
	for _, w in pairs(weights) do
		total += w
	end
	if total <= 0 then
		return nil
	end
	local r = math.random() * total
	for k, w in pairs(weights) do
		r -= w
		if r <= 0 then
			return k
		end
	end
	return next(weights)
end

function Util.alivePlayers()
	local list = {}
	for _, p in ipairs(game:GetService("Players"):GetPlayers()) do
		local c = p.Character
		local h = c and c:FindFirstChildOfClass("Humanoid")
		local r = c and c:FindFirstChild("HumanoidRootPart")
		if h and r and h.Health > 0 then
			table.insert(list, { player = p, character = c, humanoid = h, root = r })
		end
	end
	return list
end

function Util.onRig(pos)
	local a, b = Config.RigMin, Config.RigMax
	return pos.X >= a.X and pos.X <= b.X and pos.Y >= a.Y and pos.Y <= b.Y and pos.Z >= a.Z and pos.Z <= b.Z
end

function Util.part(parent, name, size, cf, color, material, extra)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color or Color3.fromRGB(60, 64, 68)
	p.Material = material or Enum.Material.Metal
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if extra then
		for k, v in pairs(extra) do
			p[k] = v
		end
	end
	p.Parent = parent
	return p
end

return Util
