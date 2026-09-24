-- ServerScriptService/AI/Mimic
-- THE MIMIC (day 12+). Copies the appearance and name of a crew member on the server.
-- At first it behaves almost normally: walks the deck, stops near people, follows them.
-- Tells: it never carries a light, and powered CAMERAS outline it in red. After a while,
-- when someone is alone with it, or when it is hit, it reveals itself and hunts.
local PathfindingService = game:GetService("PathfindingService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Modules.Config)
local SFX = require(ReplicatedStorage.Modules.SFX)

local Mimic = { units = {} }
local M = Config.Mimic
local G, AI

function Mimic.init(g, ai)
	G = g
	AI = ai
end

function Mimic.count()
	return #Mimic.units
end

-- What it says to lure people away. It never repeats real chat: only these fixed lines.
local LURES = {
	"hey... over here",
	"I found fuel. come look",
	"can you help me with this?",
	"is anyone there?",
	"don't go back inside. follow me",
	"%s... it's me",
	"I think the others are gone",
	"the generator... something's wrong. come",
}

local function say(u, text)
	local head = u.model:FindFirstChild("Head")
	if not head then
		return
	end
	local old = head:FindFirstChild("MimicBubble")
	if old then
		old:Destroy()
	end
	local bb = Instance.new("BillboardGui")
	bb.Name = "MimicBubble"
	bb.Size = UDim2.fromOffset(220, 40)
	bb.StudsOffset = Vector3.new(0, 2.6, 0)
	bb.MaxDistance = 60
	bb.LightInfluence = 0
	bb.Parent = head
	local t = Instance.new("TextLabel")
	t.Size = UDim2.fromScale(1, 1)
	t.BackgroundColor3 = Color3.fromRGB(245, 245, 240)
	t.BackgroundTransparency = 0.1
	t.TextColor3 = Color3.fromRGB(20, 20, 20)
	t.Font = Enum.Font.Gotham
	t.TextSize = 14
	t.TextWrapped = true
	t.Text = text
	t.Parent = bb
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = t
	game:GetService("Debris"):AddItem(bb, 4)
end

-- Reads the victim's own animation pack from its Animate script and plays it on the server.
local ANIM_PATHS = { idle = { "idle", "Animation1" }, walk = { "walk", "WalkAnim" }, run = { "run", "RunAnim" } }

local function loadAnims(model, hum)
	local tracks = {}
	local animate = model:FindFirstChild("Animate")
	local animator = hum:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = hum
	end
	if animate then
		for key, path in pairs(ANIM_PATHS) do
			local folder = animate:FindFirstChild(path[1])
			local anim = folder and folder:FindFirstChild(path[2])
			if anim and anim:IsA("Animation") and anim.AnimationId ~= "" then
				local ok, track = pcall(function()
					return animator:LoadAnimation(anim)
				end)
				if ok and track then
					track.Looped = true
					tracks[key] = track
				end
			end
		end
		animate:Destroy()
	end
	return tracks
end

local function play(u, name)
	if u.anim == name then
		return
	end
	u.anim = name
	u.model:SetAttribute("Locomotion", name)
	for key, track in pairs(u.tracks or {}) do
		if key == name then
			pcall(function()
				track:Play(0.2)
			end)
		elseif track.IsPlaying then
			track:Stop(0.2)
		end
	end
end

function Mimic.spawn(force)
	if not AI.allowed(force) then
		return nil
	end
	local alive = G.Util.alivePlayers()
	if #alive == 0 then
		return nil
	end
	local victim = alive[math.random(1, #alive)]
	-- Copy the victim's actual avatar (clothing, accessories, animation pack).
	local character = victim.character
	local wasArchivable = character.Archivable
	character.Archivable = true
	local ok, model = pcall(function()
		return character:Clone()
	end)
	character.Archivable = wasArchivable
	if not ok or not model then
		return nil
	end
	for _, d in ipairs(model:GetDescendants()) do
		if (d:IsA("Script") or d:IsA("LocalScript")) and d.Name ~= "Animate" then
			d:Destroy()
		elseif d:IsA("Light") or d:IsA("ForceField") or d.Name == "HeldItem" or d.Name == "HeldLight" or d.Name == "TorchMount" then
			d:Destroy()
		end
	end
	-- Spawn at a deck point out of everyone's immediate sight.
	local spot
	local pts = G.Util.shuffle(table.clone(G.World.patrolPoints))
	for _, p in ipairs(pts) do
		if not AI.anyPlayerWithin(p, 30) then
			spot = p
			break
		end
	end
	spot = spot or pts[1]
	if not spot then model:Destroy(); return nil end
	model.Name = victim.player.DisplayName
	local hum = model:FindFirstChildOfClass("Humanoid")
	local root = model:FindFirstChild("HumanoidRootPart")
	local tracks = loadAnims(model, hum)
	hum.DisplayName = victim.player.DisplayName
	hum.MaxHealth = M.Health
	hum.Health = M.Health
	hum.WalkSpeed = M.WalkSpeed
	hum.BreakJointsOnDeath = false
	model:PivotTo(CFrame.new(spot + Vector3.new(0, 3, 0)))
	model.Parent = G.World.NPCs
	pcall(function()
		root:SetNetworkOwner(nil)
	end)
	AI.register(model, "Mimic")
	local unit = {
		model = model,
		hum = hum,
		root = root,
		name = victim.player.DisplayName,
		revealAt = os.clock() + math.random(M.RevealMin, M.RevealMax),
		revealed = false,
		nextAttack = 0,
		nextPath = 0,
		pauseUntil = 0,
		tracks = tracks,
		path = PathfindingService:CreatePath({ AgentRadius = 1.5, AgentHeight = 5, AgentCanJump = true, WaypointSpacing = 6 }),

	}
	table.insert(Mimic.units, unit)
	play(unit, "idle")
	return unit
end

local function moveTo(u, dest, now)
	local pos = u.root.Position
	if now >= u.nextPath and not u.computing then
		u.computing = true
		u.nextPath = now + 1.5
		task.spawn(function()
			local ok = pcall(function()
				u.path:ComputeAsync(pos, dest)
			end)
			if not u.model.Parent then u.computing = false; return end
			if ok and u.path.Status == Enum.PathStatus.Success then
				u.waypoints = u.path:GetWaypoints()
				u.wpIndex = 2
			else
				u.waypoints = nil
			end
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
				u.hum.Jump = true
			end
			u.hum:MoveTo(wp.Position)
			return
		end
	end
	u.hum:MoveTo(dest)
end

function Mimic.reveal(u)
	if u.revealed then
		return
	end
	u.revealed = true
	u.model:SetAttribute("State", "Hunt")
	u.hum.WalkSpeed = M.HuntSpeed
	u.hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	for _, d in ipairs(u.model:GetDescendants()) do
		if d:IsA("BasePart") and d.Name ~= "HumanoidRootPart" then
			TweenService:Create(d, TweenInfo.new(1.2), { Color = Color3.fromRGB(14, 14, 18) }):Play()
		elseif d:IsA("Decal") or d:IsA("Clothing") or d:IsA("ShirtGraphic") then
			d:Destroy()
		end
	end
	local head = u.model:FindFirstChild("Head")
	if head then
		for _, s in ipairs({ -1, 1 }) do
			local eye = Instance.new("Part")
			eye.Name = "Eye"
			eye.Size = Vector3.new(0.2, 0.12, 0.1)
			eye.Material = Enum.Material.Neon
			eye.Color = Color3.fromRGB(255, 40, 30)
			eye.CanCollide = false
			eye.CanQuery = false
			eye.Massless = true
			eye.CFrame = head.CFrame * CFrame.new(s * 0.22, 0.15, -head.Size.Z / 2 - 0.02)
			eye.Parent = u.model
			local w = Instance.new("WeldConstraint")
			w.Part0 = head
			w.Part1 = eye
			w.Parent = eye
		end
	end
	local hl = u.model:FindFirstChild("CameraTag")
	if hl then
		hl.FillTransparency = 0.7
		hl.FillColor = Color3.fromRGB(120, 0, 0)
	end
	G.Net.banner("THAT IS NOT " .. string.upper(u.name), "A Mimic is hunting on the rig.", "danger")
	local bubble = u.model:FindFirstChild("MimicBubble", true)
	if bubble then
		bubble:Destroy()
	end
	SFX.play("Shriek", u.root, { speed = 0.8 })
	SFX.play("GrowlLow", u.root)

	G.Net.effectAll("Shake", 0.3, 1)
	play(u, "run")
end

function Mimic.onHit(model)
	for _, u in ipairs(Mimic.units) do
		if u.model == model then
			Mimic.reveal(u)
		end
	end
end

local function flee(u)
	if u.fleeing then
		return
	end
	u.fleeing = true
	local pos = u.root.Position
	local best, bestD
	for _, cf in ipairs(G.World.climbPoints) do
		local d = (cf.Position - pos).Magnitude
		if not bestD or d < bestD then
			best, bestD = cf, d
		end
	end
	u.exit = best and best.Position or pos
end

local function vanish(u)
	u.root.Anchored = true
	G.Util.splash(u.root.Position)
	u.model:Destroy()
end

local function think(u, now)
	local pos = u.root.Position
	if pos.Y < Config.WaterLevel + 3 then
		vanish(u)
		return
	end
	if u.fleeing then
		if (u.exit - pos).Magnitude < 6 then
			vanish(u)
		else
			play(u, "run")
			u.hum.WalkSpeed = M.HuntSpeed
			moveTo(u, u.exit, now)
		end
		return
	end

	if not u.revealed then
		-- Reveal conditions.
		local nearest, d = AI.nearestPlayer(pos, 14, true, u.model)
		local alone = false
		if nearest then
			alone = true
			for _, other in ipairs(G.Util.alivePlayers()) do
				if other.player ~= nearest.player and (other.root.Position - nearest.root.Position).Magnitude < 35 then
					alone = false
				end
			end
		end
		local dark = AI.lightAt(pos) <= 0
		if now >= u.revealAt or (alone and d and d < 9 and G.DayCycle.isNight() and (dark or not G.Power.isPowered("Lights"))) then
			Mimic.reveal(u)
			return
		end
		-- Lure: pick out a lone player and call them somewhere quiet.
		local lone = AI.nearestPlayer(pos, 70, true, u.model)
		if lone then
			local company = false
			for _, other in ipairs(G.Util.alivePlayers()) do
				if other.player ~= lone.player and (other.root.Position - lone.root.Position).Magnitude < 35 then
					company = true
				end
			end
			if not company then
				if now >= (u.nextLine or 0) then
					u.nextLine = now + math.random(9, 15)
					say(u, string.format(LURES[math.random(1, #LURES)], lone.player.DisplayName))
				end
				local offset = pos - lone.root.Position
				if offset.Magnitude > 11 then
					moveTo(u, lone.root.Position + offset.Unit * 9, now)
					play(u, "walk")
				else
					u.hum:MoveTo(pos)
					play(u, "idle")
				end
				return
			end
		end
		-- Crew-like behaviour.
		if now < u.pauseUntil then
			u.hum:MoveTo(pos)
			play(u, "idle")
			return
		end
		local follow = AI.nearestPlayer(pos, 40, true, u.model)
		if follow and math.random() < 0.5 then
			local offset = pos - follow.root.Position
			local dist = offset.Magnitude
			if dist > 13 then
				moveTo(u, follow.root.Position + offset.Unit * 11, now)
				play(u, "walk")
			else
				u.hum:MoveTo(pos)
				play(u, "idle")
				u.pauseUntil = now + math.random(2, 5)
			end
			return
		end
		if not u.dest or (u.dest - pos).Magnitude < 4 then
			local pts = G.World.patrolPoints
			if #pts == 0 then return end
			u.dest = pts[math.random(1, #pts)]
			u.pauseUntil = now + math.random(1, 4)
		end
		moveTo(u, u.dest, now)
		play(u, "walk")
		return
	end

	-- Revealed: hunt.
	if u.hum.Health < M.Health * 0.25 then
		flee(u)
		return
	end
	if now >= (u.nextGrowl or 0) then
		u.nextGrowl = now + math.random(5, 10)
		AI.cry(u, "Growl", 3)
	end
	local victim, dist, visible = AI.acquire(u, now, 130, 30)
	if not victim then
		if u.lastKnown and (u.lastKnown - pos).Magnitude > 4 then play(u, "walk"); moveTo(u, u.lastKnown, now); return end
		play(u, "idle")
		u.hum:MoveTo(pos)
		return
	end
	play(u, "run")
	if dist <= 5 and visible then
		u.hum:MoveTo(victim.root.Position)
		AI.strike(u, victim, now, 5, M.Damage, "The Mimic", 1.2)
	else
		moveTo(u, AI.pursuitPoint(u, victim, visible), now)
	end
end

function Mimic.step(now)
	for i = #Mimic.units, 1, -1 do
		local u = Mimic.units[i]
		if not u.model.Parent then
			table.remove(Mimic.units, i)
		elseif u.hum.Health <= 0 then
			table.remove(Mimic.units, i)
			AI.died(u.model, false)
			if u.breath then
				u.breath:Stop()
			end
			u.root.Anchored = true
			for _, p in ipairs(u.model:GetDescendants()) do
				if p:IsA("BasePart") then
					TweenService:Create(p, TweenInfo.new(1.5), { Transparency = 1 }):Play()
				end
			end
			task.delay(1.6, function()
				if u.model.Parent then
					u.model:Destroy()
				end
			end)
		else
			local ok, err = pcall(think, u, now)
			if not ok then
				warn("[Mimic] " .. tostring(err))
			end
		end
	end
end

function Mimic.clear()
	for _, u in ipairs(Mimic.units) do
		flee(u)
	end
end

return Mimic
