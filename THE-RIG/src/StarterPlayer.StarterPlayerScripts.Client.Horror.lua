-- StarterPlayerScripts/Client/Horror
-- Client-side fear: everything here is local presentation, never gameplay.
--   * SCREAMER: when a creature strikes you (or one is suddenly right in your face), its head
--     fills the screen with a distorted scream, red flash and heavy shake (cool-down 35 s).
--   * HEARTBEAT that speeds up as creatures close in; a STINGER when one starts hunting you.
--   * Creatures twitch: jerky head snaps, a jaw that gapes while hunting, flickering eyes.
--   * Lamps flicker and die for a moment near a creature.
--   * Night ambience: low wind and distant cries somewhere out in the dark.
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SFX = require(ReplicatedStorage.Modules.SFX)

local Horror = { lastScare = -100, jolts = {}, flicker = {}, seen = {} }
local C
local camera = workspace.CurrentCamera
local SCARE_COOLDOWN = 25
local AUDIO_RANGE = 75

local function monsters()
	return CollectionService:GetTagged("Monster")
end

local function rootOf(m)
	return m.PrimaryPart or m:FindFirstChild("HumanoidRootPart")
end

local function small(m)
	local brain = m:GetAttribute("Brain")
	return brain == "Climber" or brain == "Mimic" or brain == "Lurker"
end

function Horror.init(ctx)
	C = ctx
	local gui = Instance.new("ScreenGui")
	gui.Name = "Scare"
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 90
	gui.ResetOnSpawn = false
	gui.Enabled = false
	gui.Parent = C.gui.Parent
	local vp = Instance.new("ViewportFrame")
	vp.Size = UDim2.fromScale(1, 1)
	vp.BackgroundColor3 = Color3.new(0, 0, 0)
	vp.BackgroundTransparency = 0
	vp.Ambient = Color3.fromRGB(150, 40, 40)
	vp.LightColor = Color3.fromRGB(255, 190, 170)
	vp.LightDirection = Vector3.new(0.3, -0.4, -1)
	vp.Parent = gui
	local red = Instance.new("Frame")
	red.Size = UDim2.fromScale(1, 1)
	red.BackgroundColor3 = Color3.fromRGB(160, 0, 0)
	red.BackgroundTransparency = 0.55
	red.BorderSizePixel = 0
	red.ZIndex = 3
	red.Parent = gui
	Horror.gui, Horror.vp, Horror.red = gui, vp, red
	Horror.vpCam = Instance.new("Camera")
	Horror.vpCam.FieldOfView = 70
	Horror.vpCam.Parent = vp
	vp.CurrentCamera = Horror.vpCam

	ReplicatedStorage:WaitForChild("Remotes").Effect.OnClientEvent:Connect(function(kind, a)
		if kind == "Scare" then
			Horror.scare(a, false)
		end
	end)
	RunService.RenderStepped:Connect(Horror.render)
	task.spawn(Horror.slowLoop)
	task.spawn(Horror.ambience)
end

-- The screamer --------------------------------------------------------------------
function Horror.scare(model, sudden)
	local now = os.clock()
	if now - Horror.lastScare < SCARE_COOLDOWN or C.panelOpen or typeof(model) ~= "Instance" or not model.Parent then
		return
	end
	Horror.lastScare = now
	local ok, copy = pcall(function()
		local was = model.Archivable
		model.Archivable = true
		local c = model:Clone()
		model.Archivable = was
		return c
	end)
	if not ok or not copy then
		return
	end
	for _, d in ipairs(copy:GetDescendants()) do
		if d:IsA("Script") or d:IsA("LocalScript") or d:IsA("Sound") or d:IsA("BillboardGui") or d:IsA("Highlight") then
			d:Destroy()
		end
	end
	local head = copy:FindFirstChild("Head") or copy.PrimaryPart
	if not head then
		copy:Destroy()
		return
	end
	copy.Parent = Horror.vp
	local face = head.CFrame
	local function shot(dist, fov, roll)
		local jitter = Vector3.new((math.random() - 0.5) * 0.35, (math.random() - 0.5) * 0.3, 0)
		local cam = face.Position + face.LookVector * dist + Vector3.new(0, 0.15, 0) + jitter
		Horror.vpCam.FieldOfView = fov
		Horror.vpCam.CFrame = CFrame.lookAt(cam, face.Position) * CFrame.Angles(0, 0, roll)
	end
	shot(6, 60, 0)
	Horror.gui.Enabled = true
	Horror.vp.ImageTransparency = 0
	Horror.vp.BackgroundTransparency = 0
	Horror.red.BackgroundTransparency = 0.4
	SFX.play("ScreamA", nil, { volume = sudden and 0.9 or 1.1 })
	SFX.play("ScreamB", nil, { volume = 1.1 })
	SFX.play("ScreamC")
	SFX.play("Stinger", nil, { volume = 1.2 })
	C.Env.effect("Shake", 1.6, 1.1)
	task.spawn(function()
		-- 1) it lunges at the lens, 2) hard cuts: black / face / red, 3) fade out.
		local t0 = os.clock()
		while os.clock() - t0 < 0.45 do
			local k = (os.clock() - t0) / 0.45
			shot(6 - k * 5.2, 60 - k * 22, (math.random() - 0.5) * 0.35)
			Horror.red.BackgroundTransparency = 0.25 + math.random() * 0.45
			RunService.RenderStepped:Wait()
		end
		for cut = 1, 6 do
			local black = cut % 2 == 0
			Horror.vp.ImageTransparency = black and 1 or 0
			Horror.red.BackgroundColor3 = black and Color3.new(0, 0, 0) or Color3.fromRGB(170, 0, 0)
			Horror.red.BackgroundTransparency = black and 0 or 0.35
			shot(0.75 + math.random() * 0.3, 36 + math.random() * 8, (math.random() - 0.5) * 0.6)
			task.wait(0.045 + math.random() * 0.04)
		end
		Horror.red.BackgroundColor3 = Color3.fromRGB(160, 0, 0)
		Horror.vp.ImageTransparency = 0
		shot(0.8, 38, 0.1)
		task.wait(0.22)
		local fade = os.clock()
		while os.clock() - fade < 0.4 do
			local k = (os.clock() - fade) / 0.4
			Horror.vp.ImageTransparency = k
			Horror.vp.BackgroundTransparency = k
			Horror.red.BackgroundTransparency = 0.4 + k * 0.6
			RunService.RenderStepped:Wait()
		end
		Horror.gui.Enabled = false
		Horror.vp.ImageTransparency = 0
		Horror.vp.BackgroundTransparency = 0
		copy:Destroy()
	end)
end

-- Creature audio, always on while one is near and silent when it is far ------------------
-- Each close creature carries local looped breathing and claw skitter (louder while it
-- hunts) plus growls every few seconds; a Lurker gets bubbling instead of claws.
Horror.voices = {}
function Horror.voiceStep()
	local character = C.player.Character
	local myRoot = character and character:FindFirstChild("HumanoidRootPart")
	local now = os.clock()
	for _, m in ipairs(monsters()) do
		local root = rootOf(m)
		local disguised = m:GetAttribute("Brain") == "Mimic" and m:GetAttribute("State") ~= "Hunt"
		local near = root and myRoot and not disguised and small(m) and m:GetAttribute("Kind") ~= "Pale" and (root.Position - myRoot.Position).Magnitude < AUDIO_RANGE
		local v = Horror.voices[m]
		if near and not v then
			v = { breath = SFX.make("Breath", root), skitter = SFX.make(m:GetAttribute("Brain") == "Lurker" and "Breath" or "Skitter", root), nextGrowl = now + math.random(1, 3) }
			if v.breath then
				v.breath:Play()
			end
			Horror.voices[m] = v
		elseif not near and v then
			for _, snd in ipairs({ v.breath, v.skitter }) do
				if snd then
					snd:Destroy()
				end
			end
			Horror.voices[m] = nil
			v = nil
		end
		if v then
			local state = m:GetAttribute("State")
			local hunting = state == "Chase" or state == "Attack" or state == "Hunt" or state == "Scale" or state == "Stalk" or state == "Lunge"
			local speed = root.AssemblyLinearVelocity.Magnitude
			if v.breath then
				v.breath.Volume = hunting and 2.2 or 1.4
				v.breath.PlaybackSpeed = hunting and 0.55 or 0.42
			end
			if v.skitter then
				local moving = speed > 5 or state == "Scale" or state == "Climb"
				if moving and not v.skitter.IsPlaying then
					v.skitter:Play()
				elseif not moving and v.skitter.IsPlaying then
					v.skitter:Stop()
				end
				v.skitter.Volume = hunting and 1.8 or 1.1
			end
			if now >= v.nextGrowl and state ~= "Lurk" then
				v.nextGrowl = now + (hunting and math.random(2, 4) or math.random(4, 8))
				SFX.play(hunting and "Snarl" or (math.random() < 0.5 and "Growl" or "GrowlLow"), root, { volume = 1.2, speed = 0.9 + math.random() * 0.2 })
			end
		end
	end
	for m, v in pairs(Horror.voices) do
		if not m.Parent then
			for _, snd in ipairs({ v.breath, v.skitter }) do
				if snd then
					snd:Destroy()
				end
			end
			Horror.voices[m] = nil
		end
	end
end

-- Every frame: twitching creatures -------------------------------------------------
local function joint(part)
	if not part then
		return nil
	end
	return part:FindFirstChild("CreatureJoint") or part:FindFirstChild("Neck")
end

function Horror.render()
	local now = os.clock()
	local camPos = camera.CFrame.Position
	for _, m in ipairs(monsters()) do
		local root = rootOf(m)
		local state = m:GetAttribute("State")
		-- A Mimic that has not revealed itself must look perfectly human.
		local disguised = m:GetAttribute("Brain") == "Mimic" and state ~= "Hunt"
		if root and small(m) and not disguised and (root.Position - camPos).Magnitude < 140 then
			local hunting = state == "Chase" or state == "Attack" or state == "Hunt" or state == "Scale" or state == "Stalk"
			local j = Horror.jolts[m]
			if not j then
				j = { next = 0, head = nil, jaw = nil }
				local headJoint = joint(m:FindFirstChild("Head"))
				if headJoint and headJoint:IsA("Motor6D") then
					j.head, j.headC0 = headJoint, headJoint.C0
				end
				local jawJoint = joint(m:FindFirstChild("Jaw"))
				if jawJoint and jawJoint:IsA("Motor6D") then
					j.jaw, j.jawC0 = jawJoint, jawJoint.C0
				end
				Horror.jolts[m] = j
			end
			if now >= j.next then
				-- Jerky, unnatural snaps: hold a pose, then jump to another one.
				j.next = now + (hunting and math.random(4, 14) / 100 or math.random(20, 90) / 100)
				local amount = hunting and 0.5 or 0.22
				j.pose = CFrame.Angles((math.random() - 0.5) * amount, (math.random() - 0.5) * amount * 1.6, (math.random() - 0.5) * amount * 1.4)
				j.open = hunting and math.rad(math.random(18, 42)) or (math.random() < 0.15 and math.rad(20) or 0)
			end
			if j.head and j.head.Parent then
				j.head.C0 = j.headC0 * (j.pose or CFrame.identity)
			end
			if j.jaw and j.jaw.Parent then
				j.jaw.C0 = j.jawC0 * CFrame.Angles(j.open or 0, 0, 0)
			end
		end
	end
	for m in pairs(Horror.jolts) do
		if not m.Parent then
			Horror.jolts[m] = nil
		end
	end
	for light, f in pairs(Horror.flicker) do
		if not light.Parent or now > f.untilT then
			if light.Parent then
				light.Brightness = f.base
			end
			Horror.flicker[light] = nil
		else
			light.Brightness = math.random() < 0.45 and 0 or f.base * (0.3 + math.random() * 0.7)
		end
	end
end

-- Several times a second: heartbeat, stingers, flicker, sudden-scares -----------------
function Horror.slowLoop()
	local nextBeat = 0
	local lastStinger = -100
	while true do
		task.wait(0.1)
		local ok, err = pcall(function()
			local character = C.player.Character
			local myRoot = character and character:FindFirstChild("HumanoidRootPart")
			if not myRoot then
				return
			end
			local now = os.clock()
			local nearest, nearestM = math.huge, nil
			for _, m in ipairs(monsters()) do
				local root = rootOf(m)
				local disguised = m:GetAttribute("Brain") == "Mimic" and m:GetAttribute("State") ~= "Hunt"
				if root and small(m) and not disguised then
					local d = (root.Position - myRoot.Position).Magnitude
					if d < nearest then
						nearest, nearestM = d, m
					end
					-- A creature that starts hunting close by: stinger.
					local state = m:GetAttribute("State")
					local was = Horror.seen[m]
					Horror.seen[m] = state
					if d < 70 and (state == "Chase" or state == "Hunt" or state == "Scale") and was ~= state and now - lastStinger > 14 then
						lastStinger = now
						SFX.play("Stinger")
					end
					-- Lights stutter around it.
					if d < 160 and math.random() < 0.08 then
						Horror.flickerNear(root.Position)
					end
				end
			end
			for m in pairs(Horror.seen) do
				if not m.Parent then
					Horror.seen[m] = nil
				end
			end
			C.Env.fear = math.clamp(1 - nearest / 40, 0, 1)
			Horror.voiceStep()
			-- Heartbeat: from 45 studs, faster the closer it gets.
			if nearest < 45 and now >= nextBeat then
				local k = 1 - nearest / 45
				nextBeat = now + (1.05 - k * 0.7)
				SFX.play("Heartbeat", nil, { volume = 0.5 + k * 0.9 })
				task.delay(0.22, function()
					SFX.play("Heartbeat", nil, { volume = 0.35 + k * 0.6, speed = 0.9 })
				end)
			end
			-- Sudden scare: one appears right in front of you.
			if nearestM and nearest < 8 and nearestM:GetAttribute("Brain") ~= "Lurker" then
				local root = rootOf(nearestM)
				local look = camera.CFrame.LookVector
				local dir = (root.Position - camera.CFrame.Position)
				if dir.Magnitude > 0.1 and look:Dot(dir.Unit) > 0.7 and math.random() < 0.55 then
					Horror.scare(nearestM, true)
				end
			end
		end)
		if not ok then
			warn("[Horror] " .. tostring(err))
			task.wait(2)
		end
	end
end

function Horror.flickerNear(pos)
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	local lightsFolder = workspace:FindFirstChild("Rig")
	if not lightsFolder then
		return
	end
	params.FilterDescendantsInstances = { lightsFolder }
	local ok, parts = pcall(function()
		return workspace:GetPartBoundsInRadius(pos, 30, params)
	end)
	if not ok then
		return
	end
	local now = os.clock()
	for _, p in ipairs(parts) do
		for _, l in ipairs(p:GetChildren()) do
			if l:IsA("Light") and l.Enabled and not Horror.flicker[l] then
				Horror.flicker[l] = { base = l.Brightness, untilT = now + 0.4 + math.random() * 0.9 }
			end
		end
	end
end

-- Night ambience: low wind + distant cries out in the dark.
function Horror.ambience()
	local wind = SFX.make("Wind")
	while true do
		task.wait(3)
		local night = C.state:GetAttribute("Phase") == "Night"
		if wind then
			if night and not wind.IsPlaying then
				wind:Play()
			elseif not night and wind.IsPlaying then
				wind:Stop()
			end
		end
		if night and math.random() < 0.12 then
			local character = C.player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			if root then
				local a = math.random() * math.pi * 2
				local p = Instance.new("Part")
				p.Anchored = true
				p.CanCollide = false
				p.CanQuery = false
				p.CanTouch = false
				p.Transparency = 1
				p.Size = Vector3.new(1, 1, 1)
				p.Position = root.Position + Vector3.new(math.cos(a) * 90, -6, math.sin(a) * 90)
				p.Parent = camera
				SFX.play("Distant", p, { speed = 0.8 + math.random() * 0.4 })
				game:GetService("Debris"):AddItem(p, 12)
			end
		end
	end
end

return Horror
