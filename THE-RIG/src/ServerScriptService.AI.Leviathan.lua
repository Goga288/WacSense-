-- ServerScriptService/AI/Leviathan
-- THE LEVIATHAN (day 61+). Not a roaming NPC: a scripted event. Sonar gives warning,
-- then it rises next to the rig and strikes: damages the generator, lights, structures and
-- boats, knocks players, trips power and knocks one system off the grid, raises huge waves.
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Modules.Config)

local Leviathan = { active = false }
local L = Config.Leviathan
local G, AI

local SKIN = Color3.fromRGB(20, 26, 30)

function Leviathan.init(g, ai)
	G = g
	AI = ai
end

local function build(base)
	local model = Instance.new("Model")
	model.Name = "The Leviathan"
	local segments = 9
	for i = 1, segments do
		local t = (i - 1) / (segments - 1)
		local p = Instance.new("Part")
		p.Name = i == segments and "Head" or "Segment"
		p.Shape = Enum.PartType.Ball
		local r = 34 - t * 12
		p.Size = Vector3.new(r, r, r)
		p.CFrame = base * CFrame.new(0, t * 150, -t * t * 70)
		p.Color = SKIN
		p.Material = Enum.Material.Slate
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.Parent = model
		if i == segments then
			model.PrimaryPart = p
			for _, s in ipairs({ -1, 1 }) do
				local eye = Instance.new("Part")
				eye.Name = "Eye"
				eye.Size = Vector3.new(4, 2, 1)
				eye.Material = Enum.Material.Neon
				eye.Color = Color3.fromRGB(255, 120, 40)
				eye.Anchored = true
				eye.CanCollide = false
				eye.CanQuery = false
				eye.CFrame = p.CFrame * CFrame.new(s * 7, 4, -r / 2 + 0.5)
				eye.Parent = model
			end
			local jaw = Instance.new("Part")
			jaw.Name = "Jaw"
			jaw.Size = Vector3.new(16, 5, 22)
			jaw.Color = SKIN
			jaw.Material = Enum.Material.Slate
			jaw.Anchored = true
			jaw.CanCollide = false
			jaw.CanQuery = false
			jaw.CFrame = p.CFrame * CFrame.new(0, -9, -10)
			jaw.Parent = model
		end
	end
	pcall(function()
		model.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	end)
	return model
end

local function tweenPivot(model, goal, seconds, style, dir)
	local value = Instance.new("CFrameValue")
	value.Value = model:GetPivot()
	value.Changed:Connect(function(v)
		if model.Parent then
			model:PivotTo(v)
		end
	end)
	local t = TweenService:Create(value, TweenInfo.new(seconds, style or Enum.EasingStyle.Sine, dir or Enum.EasingDirection.InOut), { Value = goal })
	t.Completed:Connect(function()
		value:Destroy()
	end)
	t:Play()
	return t
end

local function strike(impact)
	G.Net.effectAll("Shake", 1.4, 3)
	G.Net.effectAll("Impact", impact)
	G.Environment.surge(2.5, 20)
	-- Equipment damage
	G.Power.damage(20)
	local lamps = G.Util.shuffle(table.clone(G.Power.lamps))
	for i = 1, math.min(2, #lamps) do
		G.Repair.damage(lamps[i].model, 50)
	end
	local structures = G.Util.shuffle(table.clone(G.Building.structures))
	for i = 1, math.min(3, #structures) do
		G.Repair.damage(structures[i].model, 120)
	end
	-- Knock one system off the grid.
	local systems = { "Sonar", "Cameras", "Defense", "Pumps", "Lab" }
	local hitSystem = systems[math.random(1, #systems)]
	if G.Power.grid[hitSystem] then
		G.Power.grid[hitSystem] = false
	end
	G.Power.trip(15, "LEVIATHAN STRIKE", string.upper(hitSystem) .. " knocked off the grid. Power out for 15 s.")
	-- Players near the impact
	for _, info in ipairs(G.Util.alivePlayers()) do
		local d = (info.root.Position - impact).Magnitude
		if d < 40 then
			G.Survival.damage(info.humanoid, L.StrikeDamage * (1 - d / 60), "The Leviathan")
			local away = info.root.Position - impact
			away = Vector3.new(away.X, 0, away.Z)
			if away.Magnitude > 0.1 then
				info.root.AssemblyLinearVelocity = away.Unit * 60 + Vector3.new(0, 35, 0)
			end
		end
	end
	G.Boats.damageNear(impact, 220, L.BoatDamage)
end

function Leviathan.trigger(fromDirector)
	if not AI.allowed(not fromDirector) or Leviathan.active then
		return
	end
	Leviathan.active = true
	task.spawn(function()
		local sonar = G.Power.isPowered("Sonar")
		if sonar then
			G.Net.banner("SONAR: MASSIVE CONTACT", "Something huge is rising. Brace for impact in " .. L.WarningTime .. " s.", "danger")
			task.wait(L.WarningTime)
		else
			G.Net.effectAll("Shake", 0.3, 3)
			G.Net.toastAll("The deck trembles...", "danger")
			task.wait(3)
		end
		local angle = math.random() * math.pi * 2
		local side = Vector3.new(math.cos(angle), 0, math.sin(angle))
		local surface = side * 150
		local base = CFrame.lookAt(Vector3.new(surface.X, -190, surface.Z), Vector3.new(0, -190, 0))
		local model = build(base)
		model.Parent = G.World.NPCs
		AI.register(model, "Leviathan")
		local head0 = model:GetPivot()
		G.Util.splash(surface)
		tweenPivot(model, head0 * CFrame.new(0, 200, 0), 5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out).Completed:Wait()
		task.wait(1.5)
		-- Rear back, then slam down onto the edge of the rig.
		local impact = side * 70 + Vector3.new(0, 30, 0)
		local reared = model:GetPivot()
		local slamCF = CFrame.lookAt(impact + Vector3.new(0, 12, 0), impact + Vector3.new(0, 12, 0) + (reared.Position - impact).Unit * -1)
		tweenPivot(model, slamCF, 1.1, Enum.EasingStyle.Quad, Enum.EasingDirection.In).Completed:Wait()
		strike(impact)
		task.wait(2)
		tweenPivot(model, reared, 2)
		task.wait(3)
		tweenPivot(model, head0, 6, Enum.EasingStyle.Quad, Enum.EasingDirection.In).Completed:Wait()
		model:Destroy()
		Leviathan.active = false
		if not fromDirector then
			return
		end
	end)
end

return Leviathan
