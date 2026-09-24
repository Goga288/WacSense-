-- ServerScriptService/Systems/Survival
-- Health side-systems: hunger, thirst, stamina / sprint, oxygen, pressure, death causes.
-- Stats are server-owned and replicated as player attributes.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Modules.Config)

local Survival = { stats = {} }
local P = Config.Player
local G

local function stats(player)
	local s = Survival.stats[player]
	if not s then
		s = { Hunger = 100, Thirst = 100, Stamina = 100, Oxygen = 100, sprint = false, under = false, underCheck = 0, pressureWarned = false }
		Survival.stats[player] = s
	end
	return s
end

function Survival.init(g)
	G = g
	G.Net.on("Sprint", function(player, on)
		stats(player).sprint = on == true
	end, 0.05)
	Players.PlayerRemoving:Connect(function(p)
		Survival.stats[p] = nil
	end)
end

function Survival.onCharacter(player, character)
	local s = stats(player)
	s.Stamina = 100
	s.Oxygen = 100
	s.Hunger = math.max(s.Hunger, 60)
	s.Thirst = math.max(s.Thirst, 60)
	s.sprint = false
	s.under = false
	local humanoid = character:WaitForChild("Humanoid", 10)
	if not humanoid then
		return
	end
	humanoid.WalkSpeed = P.WalkSpeed
	humanoid.Died:Connect(function()
		local cause = character:GetAttribute("LastHit") or "Unknown causes"
		G.Net.Notify:FireClient(player, "Death", cause, P.RespawnTime)
		G.PlayerData.stat(player, "Deaths", 1)
		G.Director.onDeath(player)
	end)
	Survival.publish(player, s)
end

function Survival.add(player, key, amount)
	local s = stats(player)
	if s[key] >= 99.5 then
		G.Net.toast(player, (key == "Hunger" and "Not hungry." or "Not thirsty."), "info")
		return false
	end
	s[key] = math.min(100, s[key] + amount)
	Survival.publish(player, s)
	return true
end

-- Damage entry point for creatures / hazards. Armor absorbs 30 % until depleted.
function Survival.damage(humanoid, amount, source)
	if not humanoid or humanoid.Health <= 0 then
		return
	end
	local character = humanoid.Parent
	local player = Players:GetPlayerFromCharacter(character)
	if player then
		local armor = player:GetAttribute("Armor") or 0
		if armor > 0 then
			local absorbed = math.min(armor, amount * 0.3)
			amount -= absorbed
			player:SetAttribute("Armor", math.floor((armor - absorbed) * 10) / 10)
		end
	end
	character:SetAttribute("LastHit", source)
	humanoid:TakeDamage(amount)
end

local function headUnderwater(head)
	local pos = head.Position
	if pos.Y > Config.WaterLevel + 2 and pos.Y < 12 then
		return false
	end
	local region = Region3.new(pos - Vector3.new(1, 1, 1), pos + Vector3.new(1, 1, 1)):ExpandToGrid(4)
	local ok, materials, occupancy = pcall(function()
		return workspace.Terrain:ReadVoxels(region, 4)
	end)
	if not ok then
		return pos.Y < Config.WaterLevel
	end
	local m = materials[1] and materials[1][1] and materials[1][1][1]
	local o = occupancy[1] and occupancy[1][1] and occupancy[1][1][1]
	return m == Enum.Material.Water and (o or 0) > 0.4
end

function Survival.publish(player, s)
	player:SetAttribute("Hunger", math.floor(s.Hunger + 0.5))
	player:SetAttribute("Thirst", math.floor(s.Thirst + 0.5))
	player:SetAttribute("Stamina", math.floor(s.Stamina + 0.5))
	player:SetAttribute("Oxygen", math.floor(s.Oxygen + 0.5))
	player:SetAttribute("Underwater", s.under)
end

-- 4 Hz from the main loop.
function Survival.step(dt)
	local now = os.clock()
	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local head = character and character:FindFirstChild("Head")
		if humanoid and head and humanoid.Health > 0 then
			local s = stats(player)
			s.Hunger = math.max(0, s.Hunger - P.HungerDecay * dt)
			s.Thirst = math.max(0, s.Thirst - P.ThirstDecay * dt)
			if s.Hunger <= 0 or s.Thirst <= 0 then
				Survival.damage(humanoid, P.StarveDamage * dt, s.Thirst <= 0 and "Dehydration" or "Starvation")
			end

			-- Oxygen / pressure (terrain voxel check twice per second).
			if now >= s.underCheck then
				s.underCheck = now + 0.5
				s.under = headUnderwater(head)
				local root = character:FindFirstChild("HumanoidRootPart")
				s.inWater = s.under or (root ~= nil and headUnderwater(root))
				player:SetAttribute("InWater", s.inWater)
			end
			local hasGear = G.Inventory.count(player, "DivingGear") > 0
			local hasTank = G.Inventory.count(player, "OxygenTank") > 0
			if s.under then
				local mult = hasGear and 0.33 or (hasTank and 0.5 or 1)
				s.Oxygen = math.max(0, s.Oxygen - P.OxygenDrain * mult * dt)
				if s.Oxygen <= 0 then
					Survival.damage(humanoid, P.DrownDamage * dt, "Drowned")
				end
				local limit = hasGear and P.PressureDepth.DivingGear or (hasTank and P.PressureDepth.OxygenTank or P.PressureDepth.None)
				if head.Position.Y < limit then
					Survival.damage(humanoid, P.PressureDamage * dt, "Crushed by water pressure")
					if not s.pressureWarned then
						s.pressureWarned = true
						G.Net.toast(player, "TOO DEEP — pressure damage. Better diving equipment needed.", "danger")
					end
				end
				if head.Position.Y < -60 then
					G.Director.reachedDeep(player)
				end
			else
				s.pressureWarned = false
				s.Oxygen = math.min(100, s.Oxygen + P.OxygenRegen * dt)
			end

			-- Stamina / sprint
			local moving = humanoid.MoveDirection.Magnitude > 0.1
			local swimming = s.inWater == true
			local speed = swimming and P.SwimSpeed or P.WalkSpeed
			if s.sprint and moving and s.Stamina > 1 then
				-- Sprinting also works as a hard swim stroke (a bit more tiring).
				s.Stamina = math.max(0, s.Stamina - P.StaminaDrain * (swimming and 1.3 or 1) * dt)
				speed = swimming and P.SwimSprintSpeed or P.SprintSpeed
			else
				s.Stamina = math.min(100, s.Stamina + P.StaminaRegen * dt * (moving and 0.6 or 1))
			end
			if swimming and hasGear then
				speed *= 1.35
			end
			if s.Hunger < 15 or s.Thirst < 15 then
				speed *= 0.85
			end
			if math.abs(humanoid.WalkSpeed - speed) > 0.05 then
				humanoid.WalkSpeed = speed
			end
			Survival.publish(player, s)
		end
	end
end

return Survival
