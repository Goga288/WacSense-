-- StarterPlayerScripts/Client/Env
-- Client-side atmosphere. Lighting is driven locally from the replicated clock and weather
-- (the server never touches Lighting), so the sky moves smoothly for every player.
-- Also: rain, lightning bolts + flashes, camera shake, underwater look and sound,
-- huge silhouettes passing in the deep, blinking buoy lights, map pings.
local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local CollectionService = game:GetService("CollectionService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SFX = require(ReplicatedStorage.Modules.SFX)

local Env = { flash = 0, shakeUntil = 0, shakePower = 0, underwater = false, fear = 0, hurt = 0 }
local C
local camera = workspace.CurrentCamera

local WEATHER = {
	Clear = { dark = 1, fog = 0, rain = 0 },
	Fog = { dark = 0.85, fog = 0.2, rain = 0 },
	Rain = { dark = 0.72, fog = 0.08, rain = 180 },
	HeavyRain = { dark = 0.58, fog = 0.14, rain = 380 },
	Thunderstorm = { dark = 0.5, fog = 0.14, rain = 380 },
	Storm = { dark = 0.4, fog = 0.24, rain = 620 },
}

local function effect(class, name)
	local e = Lighting:FindFirstChild(name) or Lighting:FindFirstChildOfClass(class)
	if not e then
		e = Instance.new(class)
		e.Name = name
		e.Parent = Lighting
	end
	return e
end

local function lerp(a, b, t)
	return a + (b - a) * t
end

local function lerpColor(a, b, t)
	return a:Lerp(b, math.clamp(t, 0, 1))
end

local function daylight(h)
	if h < 5 or h >= 21.5 then
		return 0
	elseif h < 7 then
		return (h - 5) / 2
	elseif h < 17 then
		return 1
	end
	return 1 - (h - 17) / 4.5
end

function Env.init(ctx)
	C = ctx
	Env.atmo = effect("Atmosphere", "Atmosphere")
	Env.cc = effect("ColorCorrectionEffect", "ColorCorrection")
	Env.bloom = effect("BloomEffect", "Bloom")
	Env.dof = effect("DepthOfFieldEffect", "DepthOfField")
	Env.blur = effect("BlurEffect", "UnderwaterBlur")
	Env.sunrays = effect("SunRaysEffect", "SunRays")
	Env.blur.Size = 0
	Env.bloom.Intensity = 0.09
	Env.bloom.Size = 28
	Env.bloom.Threshold = 2.1
	Env.dof.FarIntensity = 0.04
	Env.dof.FocusDistance = 60
	Env.dof.InFocusRadius = 90
	Env.dof.NearIntensity = 0
	Env.sunrays.Intensity = 0.04
	Env.sunrays.Spread = 0.6
	Lighting.EnvironmentDiffuseScale = 0.65
	Lighting.EnvironmentSpecularScale = 0.7
	Lighting.ExposureCompensation = 0.1
	Env.cur = nil
	Env.clouds = workspace.Terrain:FindFirstChildOfClass("Clouds") or Instance.new("Clouds")
	Env.clouds.Name = "AtlanticClouds"
	Env.clouds.Cover = .52
	Env.clouds.Density = .55
	Env.clouds.Parent = workspace.Terrain

	-- Rain emitter that follows the camera.
	local rainPart = Instance.new("Part")
	rainPart.Name = "RainEmitter"
	rainPart.Anchored = true
	rainPart.CanCollide = false
	rainPart.CanQuery = false
	rainPart.CanTouch = false
	rainPart.Transparency = 1
	rainPart.Size = Vector3.new(90, 1, 90)
	rainPart.Parent = camera
	local rain = Instance.new("ParticleEmitter")
	rain.Texture = "rbxasset://textures/particles/smoke_main.dds"
	rain.Squash = NumberSequence.new(-.85)
	rain.Color = ColorSequence.new(Color3.fromRGB(190, 205, 215))
	rain.LightInfluence = 1
	rain.Transparency = NumberSequence.new(0.68)
	rain.Size = NumberSequence.new(0.045)
	pcall(function()
		rain.Squash = NumberSequence.new(3)
	end)
	rain.Orientation = Enum.ParticleOrientation.VelocityParallel
	rain.Lifetime = NumberRange.new(0.7, 0.9)
	rain.Speed = NumberRange.new(90, 110)
	rain.EmissionDirection = Enum.NormalId.Bottom
	rain.SpreadAngle = Vector2.new(6, 6)
	rain.Rate = 0
	rain.Parent = rainPart
	Env.rainPart = rainPart
	Env.rain = rain
	Env.mobile = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled

	Env.buildVignette()
	Env.buildGroundFog()
	RunService.RenderStepped:Connect(Env.render)
	RunService:BindToRenderStep("RigShake", Enum.RenderPriority.Camera.Value + 1, Env.shake)
	task.spawn(Env.slowLoop)
end

-- Permanent dark vignette (horror framing); it tightens at night, when hurt and when afraid.
function Env.buildVignette()
	local gui = Instance.new("ScreenGui")
	gui.Name = "Vignette"
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = -5
	gui.ResetOnSpawn = false
	gui.Parent = C.gui.Parent
	local frames = {}
	for _, spec in ipairs({
		{ UDim2.new(0, 0, 0, 0), UDim2.new(1, 0, 0.28, 0), 90 },
		{ UDim2.new(0, 0, 0.72, 0), UDim2.new(1, 0, 0.28, 0), -90 },
		{ UDim2.new(0, 0, 0, 0), UDim2.new(0.22, 0, 1, 0), 0 },
		{ UDim2.new(0.78, 0, 0, 0), UDim2.new(0.22, 0, 1, 0), 180 },
	}) do
		local f = Instance.new("Frame")
		f.Position, f.Size = spec[1], spec[2]
		f.BackgroundColor3 = Color3.new(0, 0, 0)
		f.BorderSizePixel = 0
		f.Parent = gui
		local g = Instance.new("UIGradient")
		g.Rotation = spec[3]
		g.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.25), NumberSequenceKeypoint.new(1, 1) })
		g.Parent = f
		table.insert(frames, f)
	end
	Env.vignette = frames
end

-- Low rolling fog that follows you (big, faint smoke puffs at knee height).
function Env.buildGroundFog()
	local p = Instance.new("Part")
	p.Name = "GroundFog"
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Transparency = 1
	p.Size = Vector3.new(110, 1, 110)
	p.Parent = camera
	local e = Instance.new("ParticleEmitter")
	e.Texture = "rbxasset://textures/particles/smoke_main.dds"
	e.Color = ColorSequence.new(Color3.fromRGB(150, 160, 164))
	e.LightInfluence = 1
	e.LightEmission = 0
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 10), NumberSequenceKeypoint.new(1, 22) })
	e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.4, 0.86), NumberSequenceKeypoint.new(1, 1) })
	e.Lifetime = NumberRange.new(9, 14)
	e.Speed = NumberRange.new(0.5, 2)
	e.SpreadAngle = Vector2.new(180, 20)
	e.EmissionDirection = Enum.NormalId.Top
	e.Acceleration = Vector3.new(0.6, 0, 0.3)
	e.RotSpeed = NumberRange.new(-8, 8)
	e.Rate = 14
	e.Parent = p
	Env.fogPart, Env.fogEmitter = p, e
end

-- Every frame: interpolate lighting towards the target.
function Env.render(dt)
	local S = C.state
	local hour = C.hour()
	local weather = WEATHER[S:GetAttribute("Weather") or "Clear"] or WEATHER.Clear
	local d = daylight(hour)
	local lit = d * weather.dark
	local under = Env.underwater
	local k = math.clamp(dt * 1.5, 0, 1)
	local dusk = math.max(0, 1 - math.abs(hour - 18) / 1.8) * weather.dark
	local dawn = math.max(0, 1 - math.abs(hour - 6.4) / 1.2) * weather.dark
	local golden = math.max(dawn, dusk)
	Env.clouds.Cover = lerp(Env.clouds.Cover, .42 + (1 - weather.dark) * .8, k)
	Env.clouds.Density = lerp(Env.clouds.Density, .5 + weather.fog, k)
	Env.clouds.Color = Color3.fromRGB(192, 204, 210):Lerp(Color3.fromRGB(224, 185, 147), golden * .5)
	Env.sunrays.Intensity = .015 + golden * .045

	-- Horror grade: nights are near-black (the flashlight matters), days are overcast and cold,
	-- fog is always there and thickens at night.
	local target = {
		brightness = 0.35 + 1.55 * lit,
		ambient = lerpColor(Color3.fromRGB(10, 12, 16), Color3.fromRGB(64, 70, 76), lit),
		outdoor = lerpColor(Color3.fromRGB(16, 20, 26), Color3.fromRGB(98, 106, 112), lit),
		density = math.min(0.72, lerp(0.6, 0.38, d) + weather.fog * 0.5),
		haze = lerp(3.2, 1.8, d) + weather.fog * 3,
		atmoColor = lerpColor(Color3.fromRGB(40, 50, 58), Color3.fromRGB(150, 160, 164), lit),
		decay = lerpColor(Color3.fromRGB(16, 22, 28), Color3.fromRGB(96, 104, 106), lit),
		sat = lerp(-0.42, -0.3, d),
		contrast = 0.16 + (1 - d) * 0.06,
		tint = lerpColor(Color3.fromRGB(176, 200, 206), Color3.fromRGB(226, 234, 230), d),
	}
	target.atmoColor = target.atmoColor:Lerp(Color3.fromRGB(170, 130, 100), golden * .18)
	target.decay = target.decay:Lerp(Color3.fromRGB(120, 90, 76), golden * .2)
	-- Fear: close to a creature the world drains of colour and closes in.
	local fear = Env.fear or 0
	target.sat -= fear * 0.35
	target.contrast += fear * 0.12
	target.density = math.min(0.85, target.density + fear * 0.12)
	if under then
		target.density = 0.9
		target.haze = 0
		target.atmoColor = Color3.fromRGB(10, 48, 58)
		target.decay = Color3.fromRGB(6, 30, 38)
		target.tint = Color3.fromRGB(110, 180, 200)
		target.sat = -0.25
	end
	local cur = Env.cur
	if not cur then
		cur = target
		Env.cur = target
	else
		for key, v in pairs(target) do
			local c = cur[key]
			if typeof(v) == "Color3" then
				cur[key] = c:Lerp(v, k)
			else
				cur[key] = c + (v - c) * k
			end
		end
	end

	Lighting.ClockTime = hour
	Env.flash = math.max(0, Env.flash - dt * 3)
	Lighting.Brightness = cur.brightness + Env.flash * 3
	Lighting.Ambient = cur.ambient
	Lighting.OutdoorAmbient = cur.outdoor:Lerp(Color3.fromRGB(200, 210, 255), Env.flash * 0.6)
	Env.atmo.Density = math.clamp(cur.density, 0, 1)
	Env.atmo.Haze = cur.haze
	Env.atmo.Color = cur.atmoColor
	Env.atmo.Decay = cur.decay
	Env.atmo.Offset = 0.1
	Env.atmo.Glare = d * 0.3
	Env.cc.Saturation = cur.sat
	Env.cc.Contrast = cur.contrast
	Env.cc.TintColor = cur.tint
	Env.cc.Brightness = Env.flash * 0.35 - (Env.blackout or 0)
	Env.blur.Size = under and 5 or ((Env.hurt or 0) > 0.5 and 3 or 0)
	if Env.vignette then
		local hum = C.player.Character and C.player.Character:FindFirstChildOfClass("Humanoid")
		Env.hurt = hum and (1 - hum.Health / math.max(hum.MaxHealth, 1)) or 0
		local dark = math.clamp((1 - d) * 0.35 + Env.hurt * 0.5 + (Env.fear or 0) * 0.4, 0, 0.95)
		for _, f in ipairs(Env.vignette) do
			f.BackgroundTransparency = 1 - (0.45 + dark * 0.55)
			f.BackgroundColor3 = Color3.new(0, 0, 0):Lerp(Color3.fromRGB(70, 0, 0), Env.hurt * 0.6)
		end
	end
	if Env.fogPart then
		local cp = camera.CFrame.Position
		Env.fogPart.CFrame = CFrame.new(cp.X, cp.Y - 3, cp.Z)
		Env.fogEmitter.Rate = under and 0 or (8 + (1 - d) * 16 + weather.fog * 20)
		Env.fogEmitter.Color = ColorSequence.new(cur.atmoColor)
	end
	Env.sunrays.Enabled = d > 0.3 and not under

	-- Rain follows the camera; stops under a roof.
	local cf = camera.CFrame
	Env.rainPart.CFrame = CFrame.new(cf.Position + Vector3.new(0, 40, 0))
	local wind = S:GetAttribute("Wind") or 0
	Env.rain.Acceleration = Vector3.new(wind * 45, 0, wind * 15)
	local rate = (C.settings.Rain and not under and not Env.covered) and weather.rain or 0
	Env.rain.Rate = Env.mobile and rate * 0.4 or rate
end

function Env.slowLoop()
	local blink = false
	local nextSilhouette = os.clock() + 10
	while true do
		task.wait(0.3)
		local ok, err = pcall(function()
			local pos = camera.CFrame.Position
			-- Underwater: camera inside terrain water.
			local region = Region3.new(pos - Vector3.new(1, 1, 1), pos + Vector3.new(1, 1, 1)):ExpandToGrid(4)
			local okRead, materials, occupancy = pcall(function()
				return workspace.Terrain:ReadVoxels(region, 4)
			end)
			local under = false
			if okRead then
				local m = materials[1] and materials[1][1] and materials[1][1][1]
				local o = occupancy[1] and occupancy[1][1] and occupancy[1][1][1]
				under = m == Enum.Material.Water and (o or 0) > 0.5
			end
			if under ~= Env.underwater then
				Env.underwater = under
				SoundService.AmbientReverb = under and Enum.ReverbType.UnderWater or Enum.ReverbType.NoReverb
			end
			-- Roof check for rain.
			local params = RaycastParams.new()
			params.FilterType = Enum.RaycastFilterType.Exclude
			params.FilterDescendantsInstances = { camera, C.player.Character }
			Env.covered = workspace:Raycast(pos, Vector3.new(0, 45, 0), params) ~= nil
			-- Blinking buoys and beacons.
			blink = not blink
			for _, p in ipairs(CollectionService:GetTagged("Blinker")) do
				if p:IsA("BasePart") then
					p.Material = blink and Enum.Material.Neon or Enum.Material.SmoothPlastic
					local l = p:FindFirstChildWhichIsA("Light")
					if l then
						l.Enabled = blink
					end
				end
			end
			-- Something huge passes by in the deep.
			if under and os.clock() > nextSilhouette then
				nextSilhouette = os.clock() + math.random(18, 40)
				if math.random() < 0.55 then
					Env.silhouette(pos)
				end
			end
		end)
		if not ok then
			warn("[Env] " .. tostring(err))
		end
	end
end

function Env.silhouette(camPos)
	local angle = math.random() * math.pi * 2
	local dist = math.random(90, 150)
	local start = camPos + Vector3.new(math.cos(angle) * dist, -math.random(15, 35), math.sin(angle) * dist)
	local dir = Vector3.new(-math.sin(angle), 0, math.cos(angle))
	local model = Instance.new("Model")
	model.Name = "DeepShape"
	local body = Instance.new("Part")
	body.Shape = Enum.PartType.Ball
	body.Size = Vector3.new(40, 40, 40)
	local parts = {}
	for i = 0, 5 do
		local p = Instance.new("Part")
		p.Shape = Enum.PartType.Ball
		local s = 44 - i * 6
		p.Size = Vector3.new(s, s * 0.7, s)
		p.CFrame = CFrame.new(start - dir * i * 26)
		p.Color = Color3.new(0, 0, 0)
		p.Material = Enum.Material.SmoothPlastic
		p.Transparency = 1
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.Parent = model
		table.insert(parts, p)
	end
	body:Destroy()
	model.Parent = camera
	for _, p in ipairs(parts) do
		TweenService:Create(p, TweenInfo.new(3), { Transparency = 0.3 }):Play()
		TweenService:Create(p, TweenInfo.new(16, Enum.EasingStyle.Linear), { CFrame = p.CFrame + dir * 220 }):Play()
	end
	task.delay(13, function()
		for _, p in ipairs(parts) do
			TweenService:Create(p, TweenInfo.new(3), { Transparency = 1 }):Play()
		end
		task.wait(3.2)
		model:Destroy()
	end)
end

function Env.shake()
	local now = os.clock()
	-- Head bob / breathing in first person.
	local character = C.player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local head = character and character:FindFirstChild("Head")
	if root and head and (camera.CFrame.Position - head.Position).Magnitude < 2 then
		local v = root.AssemblyLinearVelocity
		local speed = Vector3.new(v.X, 0, v.Z).Magnitude
		Env.bobT = (Env.bobT or 0) + math.min(speed, 24) * 0.011
		local amp = math.clamp(speed / 22, 0, 1)
		local breathe = math.sin(now * 1.6) * 0.012 * (1 + (Env.fear or 0) * 2)
		camera.CFrame = camera.CFrame * CFrame.new(math.cos(Env.bobT) * 0.05 * amp, math.abs(math.sin(Env.bobT)) * 0.09 * amp + breathe, 0)
			* CFrame.Angles(0, 0, math.cos(Env.bobT) * 0.004 * amp)
	end
	if now < Env.shakeUntil then
		local p = Env.shakePower * math.clamp((Env.shakeUntil - now) / 1, 0.2, 1)
		camera.CFrame = camera.CFrame * CFrame.new((math.random() - 0.5) * p, (math.random() - 0.5) * p, 0) * CFrame.Angles(0, 0, (math.random() - 0.5) * p * 0.02)
	end
end

function Env.sound(id, volume, parent)
	if not id or id == "" then
		return
	end
	local s = Instance.new("Sound")
	s.SoundId = id
	s.Volume = volume or 0.5
	s.Parent = parent or SoundService
	s:Play()
	game:GetService("Debris"):AddItem(s, 10)
end

function Env.ping()
	SFX.play("Ping")
end

function Env.lightning(pos)
	local top = Vector3.new(pos.X + math.random(-30, 30), 420, pos.Z + math.random(-30, 30))
	local folder = Instance.new("Folder")
	folder.Name = "Bolt"
	folder.Parent = camera
	local prev = top
	local steps = 9
	for i = 1, steps do
		local t = i / steps
		local nextPoint = top:Lerp(pos, t) + (i < steps and Vector3.new(math.random(-18, 18), 0, math.random(-18, 18)) or Vector3.zero)
		local len = (nextPoint - prev).Magnitude
		local seg = Instance.new("Part")
		seg.Anchored = true
		seg.CanCollide = false
		seg.CanQuery = false
		seg.CanTouch = false
		seg.Material = Enum.Material.Neon
		seg.Color = Color3.fromRGB(210, 225, 255)
		seg.Size = Vector3.new(0.8, 0.8, len)
		seg.CFrame = CFrame.lookAt((prev + nextPoint) / 2, nextPoint)
		seg.Parent = folder
		prev = nextPoint
	end
	Env.flash = 1
	task.delay(0.12, function()
		Env.flash = 0.6
	end)
	task.delay(0.3, function()
		folder:Destroy()
	end)
	local dist = (camera.CFrame.Position - pos).Magnitude
	task.delay(math.clamp(dist / 340, 0.1, 4), function()
		SFX.play("Thunder", nil, { volume = math.clamp(1.4 - dist / 900, 0.3, 1) })
		if dist < 200 then
			Env.shakeUntil = os.clock() + 0.6
			Env.shakePower = 0.4
		end
	end)
end

function Env.markPing(pos, label)
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.Transparency = 1
	p.Size = Vector3.new(1, 1, 1)
	p.Position = pos
	p.Parent = camera
	local bb = Instance.new("BillboardGui")
	bb.AlwaysOnTop = true
	bb.Size = UDim2.new(0, 160, 0, 40)
	bb.LightInfluence = 0
	bb.Parent = p
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Size = UDim2.new(1, 0, 1, 0)
	t.Font = Enum.Font.GothamBold
	t.TextSize = 14
	t.TextColor3 = Color3.fromRGB(242, 178, 58)
	t.TextStrokeTransparency = 0.4
	t.Parent = bb
	task.spawn(function()
		local stop = os.clock() + 25
		while os.clock() < stop do
			local d = (camera.CFrame.Position - pos).Magnitude
			t.Text = string.format("▼ %s  %dm", label or "SIGNAL", math.floor(d))
			task.wait(0.25)
		end
		p:Destroy()
	end)
end

function Env.effect(kind, a, b)
	if kind == "Lightning" then
		Env.lightning(a)
	elseif kind == "Shake" then
		Env.shakePower = (a or 0.5) * 1.5
		Env.shakeUntil = os.clock() + (b or 1)
	elseif kind == "Blackout" then
		Env.blackout = 0.15
		task.delay(0.25, function()
			Env.blackout = 0
		end)
	elseif kind == "Hit" then
		C.HUD.flashDamage(a or 0.6)
		Env.shakePower = 0.5
		Env.shakeUntil = os.clock() + 0.25
	elseif kind == "Swing" then
		Env.shakePower = a and 0.35 or 0.15
		Env.shakeUntil = os.clock() + 0.12
	elseif kind == "Ping" then
		Env.markPing(a, b)
	elseif kind == "Impact" then
		Env.flash = 0.4
	end
end

return Env
