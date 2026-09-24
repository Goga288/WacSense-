-- ServerScriptService/AI/AIService
-- Shared AI services: creature registry, noise events, light queries, damage routing,
-- camera highlights and sonar. Creature brains live in Climber / Mimic / Watcher / Leviathan.
-- 0.15: Roster turns the creature models placed in the map into tonight's creatures (they
-- use the Climber brain); Peeker is the one that watches from behind you.
--
-- 0.10: the HIVE. Every creature shares one memory:
--   * sightings (who was seen where, and how fast they were moving),
--   * SCENT: a player who stays in one spot at night is smelled from far away and hunted,
--   * HIDEOUTS: places where players spent a long time are searched when nobody is visible,
--   * PACK ROLES: creatures hunting the same player split into front / flank / behind / cut-off,
--   * LEARNING: deaths in light raise the number of lamp saboteurs; crowbar kills make them dodge.
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Modules.Config)
local SFX = require(ReplicatedStorage.Modules.SFX)

local AI = { noises = {}, SFX = SFX }
local G

AI.hive = { players = {}, hideouts = {}, lightDeaths = 0, meleeDeaths = 0, lastShriek = 0 }
local SCENT_TIME = 40 -- seconds standing still at night before the hive smells you

function AI.init(g)
	G = g
	AI.Climber = require(script.Parent.Climber)
	AI.Mimic = require(script.Parent.Mimic)
	AI.Watcher = require(script.Parent.Watcher)
	AI.Leviathan = require(script.Parent.Leviathan)
	AI.Lurker = require(script.Parent.Lurker)
	AI.Silhouette = require(script.Parent.Silhouette)
	AI.Roster = require(script.Parent.Roster)
	AI.Peeker = require(script.Parent.Peeker)
	-- The roster first: the Climber brain takes its kinds from it.
	local ok, err = pcall(AI.Roster.init, G, AI)
	if not ok then
		warn("[AI] Roster.init failed: " .. tostring(err))
	end
	for _, m in ipairs({ AI.Climber, AI.Mimic, AI.Watcher, AI.Leviathan, AI.Lurker, AI.Silhouette, AI.Peeker }) do
		m.init(G, AI)
	end
	Players.PlayerRemoving:Connect(function(p)
		AI.hive.players[p] = nil
		AI.sightings[p] = nil
	end)
end

-- Sound helpers ---------------------------------------------------------------
-- Plays a creature sound with a per-creature cooldown (u.sfx[name]).
function AI.cry(u, name, cooldown)
	if u.C and u.C.silent then
		return
	end
	local now = os.clock()
	u.sfx = u.sfx or {}
	if now < (u.sfx[name] or 0) or not u.root or not u.root.Parent then
		return
	end
	-- Shrieks are loud: never more than one every 1.2 s across the whole map.
	if name == "Shriek" then
		if now - AI.hive.lastShriek < 1.2 then
			return
		end
		AI.hive.lastShriek = now
	end
	u.sfx[name] = now + (cooldown or 4)
	SFX.play(name, u.root, { speed = 0.9 + math.random() * 0.2 })
end

-- Noise ---------------------------------------------------------------------
function AI.noise(position, radius)
	table.insert(AI.noises, { position = position, radius = radius, expires = os.clock() + 6 })
end

-- Loudest recent noise a creature at `pos` can hear.
function AI.hear(pos)
	local now = os.clock()
	local best, bestD
	for i = #AI.noises, 1, -1 do
		local n = AI.noises[i]
		if n.expires < now then
			table.remove(AI.noises, i)
		else
			local d = (n.position - pos).Magnitude
			if d < n.radius and (not bestD or d < bestD) then
				best, bestD = n.position, d
			end
		end
	end
	-- A running generator hums: creatures on the rig are drawn to it at night.
	if G.Power.online and G.DayCycle.isNight() then
		local gp = G.Power.core.Position
		if (gp - pos).Magnitude < 120 and not best then
			best = gp
		end
	end
	return best
end

local function rayParams(extra)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local filter = { workspace.NPCs, workspace.Effects }
	for _, e in ipairs(extra or {}) do
		table.insert(filter, e)
	end
	params.FilterDescendantsInstances = filter
	params.IgnoreWater = true
	return params
end

-- Shared visibility and short-term memory; walls block attacks and light.
function AI.visible(from, to, target, ignore)
	local direction = to - from
	if direction.Magnitude < 0.05 then
		return true
	end
	local hit = workspace:Raycast(from, direction, rayParams({ ignore }))
	return not hit or (target ~= nil and (hit.Instance == target or hit.Instance:IsDescendantOf(target)))
end

-- Is `player` looking at `pos` (camera aim), with a clear line of sight?
function AI.lookingAt(player, pos, maxDist)
	local character = player.Character
	local head = character and character:FindFirstChild("Head")
	if not head then
		return false
	end
	local delta = pos - head.Position
	if delta.Magnitude > (maxDist or 120) or delta.Magnitude < 0.1 then
		return false
	end
	local aim = G.Equipment.aimOf and G.Equipment.aimOf(player) or head.CFrame.LookVector
	return aim:Dot(delta.Unit) > 0.8 and AI.visible(head.Position, pos, nil, character)
end

-- Walkable floor near `target` (players' level), approached from `from`. Returns the root
-- position a creature should stand at, or nil.
function AI.findLanding(target, from, radii)
	local params = rayParams()
	local ignore = {}
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Character then
			table.insert(ignore, p.Character)
		end
	end
	params = rayParams(ignore)
	params.IgnoreWater = false
	local flat = Vector3.new((from or target).X - target.X, 0, (from or target).Z - target.Z)
	local dir = flat.Magnitude > 0.1 and flat.Unit or Vector3.new(1, 0, 0)
	for _, r in ipairs(radii or { 5, 3, 8, 11 }) do
		for _, turn in ipairs({ 0, 40, -40, 90, -90 }) do
			local a = math.rad(turn)
			local d = Vector3.new(dir.X * math.cos(a) - dir.Z * math.sin(a), 0, dir.X * math.sin(a) + dir.Z * math.cos(a))
			local probe = target + d * r
			local hit = workspace:Raycast(probe + Vector3.new(0, 4, 0), Vector3.new(0, -14, 0), params)
			if hit and hit.Normal.Y > 0.7 and hit.Material ~= Enum.Material.Water then
				local head = workspace:Raycast(hit.Position + Vector3.new(0, 0.3, 0), Vector3.new(0, 5.5, 0), params)
				if not head then
					return hit.Position + Vector3.new(0, 3.2, 0)
				end
			end
		end
	end
	return nil
end

-- Open water near `pos` a creature can rise out of. Returns the water-surface point or nil.
function AI.findWaterNear(pos, minR)
	local params = rayParams()
	params.IgnoreWater = false
	for _, r in ipairs({ minR or 22, 34, 50, 72, 100, 140 }) do
		local start = math.random() * math.pi * 2
		for k = 0, 11 do
			local a = start + k * math.pi / 6
			local x, z = pos.X + math.cos(a) * r, pos.Z + math.sin(a) * r
			local hit = workspace:Raycast(Vector3.new(x, pos.Y + 90, z), Vector3.new(0, -400, 0), params)
			if hit and hit.Instance == workspace.Terrain and hit.Material == Enum.Material.Water then
				return Vector3.new(x, Config.WaterLevel, z)
			end
		end
	end
	return nil
end

-- Pack knowledge: a creature that sees a player shares the sighting with the others nearby.
AI.sightings = {}

function AI.shareSighting(player, position, now, scent)
	AI.sightings[player] = { position = position, time = now, scent = scent == true }
end

function AI.recentSighting(pos, now, range)
	local best, bestD
	for player, s in pairs(AI.sightings) do
		if now - s.time > 6 or not player.Parent then
			AI.sightings[player] = nil
		else
			local d = (s.position - pos).Magnitude
			-- The scent of a player who sits still carries far.
			if d < (s.scent and math.max(range, 420) or range) and (not bestD or d < bestD) then
				best, bestD = s, d
			end
		end
	end
	return best
end

-- The hive tracks every player once per second: scent and hideouts.
local trackTimer = 0
function AI.track(dt, now)
	trackTimer -= dt
	if trackTimer > 0 then
		return
	end
	trackTimer = 1
	local night = G.DayCycle.isNight()
	for _, info in ipairs(G.Util.alivePlayers()) do
		local h = AI.hive.players[info.player]
		if not h then
			h = {}
			AI.hive.players[info.player] = h
		end
		local pos = info.root.Position
		if not h.anchor or (pos - h.anchor).Magnitude > 14 then
			h.anchor, h.since, h.scented = pos, now, false
			info.player:SetAttribute("Scented", false)
		end
		h.pos = pos
		local still = now - h.since
		if night and still > SCENT_TIME and pos.Y > Config.WaterLevel - 4 then
			if not h.scented then
				h.scented = true
				info.player:SetAttribute("Scented", true)
				G.Net.toast(info.player, "They can SMELL you. Staying in one place at night draws them in — keep moving.", "danger")
			end
			if now - (h.lastBroadcast or 0) > 4 then
				h.lastBroadcast = now
				AI.shareSighting(info.player, pos, now, true)
			end
		end
		-- Remember long stays as hideouts to search later.
		if still > 50 then
			local known = false
			for _, spot in ipairs(AI.hive.hideouts) do
				if (spot.pos - h.anchor).Magnitude < 16 then
					spot.time = now
					known = true
				end
			end
			if not known then
				table.insert(AI.hive.hideouts, { pos = h.anchor, time = now })
				if #AI.hive.hideouts > 14 then
					table.remove(AI.hive.hideouts, 1)
				end
			end
		end
	end
end

function AI.isScented(player)
	local h = AI.hive.players[player]
	return h ~= nil and h.scented == true
end

function AI.scentedSince(player)
	local h = AI.hive.players[player]
	return h and h.scented and h.since or nil
end

-- Nearest remembered hideout within `range` of pos (not the one we just searched).
function AI.nearestHideout(pos, range, exclude)
	local best, bestD
	for _, spot in ipairs(AI.hive.hideouts) do
		local d = (spot.pos - pos).Magnitude
		if d < range and (not exclude or (spot.pos - exclude).Magnitude > 10) and (not bestD or d < bestD) then
			best, bestD = spot.pos, d
		end
	end
	return best
end

-- Prefers wounded and isolated prey; remembers its current target; hunts as a pack.
function AI.acquire(u, now, sightRange, hearRange)
	local pos = u.root.Position
	local alive = G.Util.alivePlayers()
	local night = G.DayCycle.isNight()
	local best, score, seen
	for _, info in ipairs(alive) do
		local distance = (info.root.Position - pos).Magnitude
		-- A lit flashlight at night gives you away from much further.
		local torch = night and G.Equipment.beamOf(info.player) ~= nil
		local range = torch and sightRange * 1.5 or sightRange
		if distance > range then
			continue
		end
		local visible = AI.visible(pos, info.root.Position, info.character, u.model)
		local velocity = info.root.AssemblyLinearVelocity
		local speed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
		local audible = (distance < hearRange and speed > 7) or (distance < hearRange * 1.8 and speed > 17)
		-- Smell: a scented player, or its current prey within 26 studs, is sensed through walls.
		local smelled = (AI.isScented(info.player) and distance < 140) or (u.targetPlayer == info.player and distance < 26)
		if not visible and not audible and not smelled then
			continue
		end
		local allies = 0
		for _, other in ipairs(alive) do
			if other ~= info and (other.root.Position - info.root.Position).Magnitude < 22 then
				allies += 1
			end
		end
		local wounded = (1 - info.humanoid.Health / math.max(info.humanoid.MaxHealth, 1)) * 25
		local lit = info.player:GetAttribute("TorchFocus") and 10 or 0
		local rank = distance - wounded + allies * 12 + lit - (u.targetPlayer == info.player and 12 or 0) - (u.aggro == info.player and 15 or 0)
		if not score or rank < score then
			best, score, seen = info, rank, visible
		end
	end
	if best then
		u.targetPlayer = best.player
		u.lastKnown = best.root.Position
		local v = best.root.AssemblyLinearVelocity
		u.lastVelocity = Vector3.new(v.X, 0, v.Z)
		u.memoryUntil = now + (seen and 10 or 4)
		if seen then
			AI.shareSighting(best.player, best.root.Position, now)
		end
		return best, (best.root.Position - pos).Magnitude, seen
	end
	if u.memoryUntil and now >= u.memoryUntil then
		u.lastKnown = nil
		u.targetPlayer = nil
	end
	if not u.lastKnown then
		local shared = AI.recentSighting(pos, now, 130)
		if shared then
			u.lastKnown = shared.position
			u.memoryUntil = now + 5
		end
	end
	return nil
end

-- Pack roles: recomputed each AI tick for everything hunting the same player.
local ROLES = { "Front", "Flank", "Behind", "Cutoff", "Flank", "Behind" }
function AI.assignRoles(units)
	local byTarget = {}
	for _, u in ipairs(units) do
		if u.targetPlayer and u.model.Parent then
			byTarget[u.targetPlayer] = byTarget[u.targetPlayer] or {}
			table.insert(byTarget[u.targetPlayer], u)
		else
			u.packRole = nil
		end
	end
	for _, list in pairs(byTarget) do
		table.sort(list, function(a, b)
			return (a.id or 0) < (b.id or 0)
		end)
		for i, u in ipairs(list) do
			u.packRole = #list == 1 and "Front" or ROLES[(i - 1) % #ROLES + 1]
			u.packSize = #list
		end
	end
end

local function facingOf(info)
	local aim = G.Equipment.aimOf and G.Equipment.aimOf(info.player)
	local f = aim or info.root.CFrame.LookVector
	f = Vector3.new(f.X, 0, f.Z)
	return f.Magnitude > 0.1 and f.Unit or Vector3.new(0, 0, -1)
end

function AI.pursuitPoint(u, victim, visible)
	-- Hearing tells us where a sound occurred; it does not grant continuous wall vision.
	if not visible then return u.lastKnown or victim.root.Position end
	local now = os.clock()
	local vpos = victim.root.Position
	local v = victim.root.AssemblyLinearVelocity
	local flatV = Vector3.new(v.X, 0, v.Z)
	local toVictim = vpos - u.root.Position
	local flat = Vector3.new(toVictim.X, 0, toVictim.Z)
	local dist = flat.Magnitude
	local dest = vpos
	if visible then
		-- Intercept: aim where the victim will be when we arrive (cut-off units look further).
		local t = math.clamp(dist / math.max(u.hum.WalkSpeed, 1), 0, u.packRole == "Cutoff" and 2.4 or 1.2)
		local lead = flatV * t
		if lead.Magnitude > 24 then
			lead = lead.Unit * 24
		end
		dest = vpos + lead
	end
	if dist > 10 then
		local role = u.packRole or "Front"
		if role == "Behind" then
			dest = vpos - facingOf(victim) * 9
		elseif role == "Flank" or (role == "Front" and u.packSize == nil) then
			u.flank = u.flank or ((math.random() < 0.5 and -1 or 1) * math.random(6, 11))
			local side = Vector3.new(-flat.Z, 0, flat.X).Unit
			dest = dest + side * u.flank * math.clamp((dist - 10) / 18, 0, 1.4)
		end
	end
	-- Approach from the dark side when the direct approach is lit.
	if dist > 12 then
		if not u.darkUntil or now >= u.darkUntil then
			u.darkUntil = now + 1.5
			u.darkDest = nil
			if AI.lightAt(dest) > 0 then
				local bestP, bestD
				for k = 0, 7 do
					local a = k * math.pi / 4
					local p = vpos + Vector3.new(math.cos(a) * 11, 0, math.sin(a) * 11)
					local d = (p - u.root.Position).Magnitude
					if (not bestD or d < bestD) and AI.lightAt(p) <= 0 then
						bestP, bestD = p, d
					end
				end
				u.darkDest = bestP
			end
		end
		if u.darkDest then
			dest = u.darkDest
		end
	end
	-- Do not predict through a corner: aim at the last observed position instead.
	if not AI.visible(vpos, dest, nil, victim.character) then
		return vpos
	end
	return dest
end

-- Find cover beside an observed victim, on actual floor, with enough headroom.
-- Cache the expensive probes and keep a chosen route long enough to finish it.
function AI.coverPoint(u, victim, now)
	if now < (u.nextCoverProbe or 0) then return u.coverDest end
	u.nextCoverProbe = now + 2.5
	u.coverDest = nil
	local toward = victim.root.Position - u.root.Position
	local flat = Vector3.new(toward.X,0,toward.Z)
	if flat.Magnitude < 16 or flat.Magnitude > 85 then return nil end
	local side = Vector3.new(-flat.Z,0,flat.X).Unit
	local best,score
	for _,offset in ipairs({-18,18,-11,11}) do
		local candidate = u.root.Position + flat.Unit*8 + side*offset
		local ground = AI.findLanding(candidate,u.root.Position,{0})
		if ground and math.abs(ground.Y-u.root.Position.Y)<4
			and not AI.visible(victim.root.Position+Vector3.new(0,1,0),ground+Vector3.new(0,1,0),nil,victim.character) then
			local rank=(ground-victim.root.Position).Magnitude+AI.lightAt(ground)*24
			if not score or rank<score then best,score=ground,rank end
		end
	end
	u.coverDest=best
	return best
end

function AI.strike(u, victim, now, range, damage, cause, cooldown)
	if now < u.nextAttack then
		return
	end
	u.nextAttack = now + cooldown
	u.model:SetAttribute("AttackUntil", workspace:GetServerTimeNow() + 0.45)
	AI.cry(u, "Snarl", 1)
	task.delay(0.2, function()
		if not u.model.Parent or u.hum.Health <= 0 or not victim.root.Parent or victim.humanoid.Health <= 0 then
			return
		end
		local pos = u.root.Position
		if (victim.root.Position - pos).Magnitude > range + 0.5 then
			return
		end
		if not AI.visible(pos, victim.root.Position, victim.character, u.model) then
			return
		end
		if victim.character:FindFirstChildOfClass("ForceField") then
			return
		end
		G.Survival.damage(victim.humanoid, damage, cause)
		if victim.player.Parent then
			G.Net.Effect:FireClient(victim.player, "Hit", 0.6)
			G.Net.Effect:FireClient(victim.player, "Scare", u.model)
		end
	end)
end

-- Melee dodge: a creature may side-step a crowbar swing it can see coming.
function AI.tryDodge(model, player)
	local brain = model:GetAttribute("Brain")
	if brain == "Climber" then
		return AI.Climber.dodge(model, player)
	end
	return false
end

-- Light ---------------------------------------------------------------------
-- Returns intensity (damage per second) and the light's position if `pos` is lit.
function AI.lightAt(pos)
	for _, e in ipairs(G.Power.lamps) do
		if e.on then
			local flat = Vector3.new(pos.X - e.target.X, 0, pos.Z - e.target.Z).Magnitude
			if flat < e.radius and pos.Y < e.lamp.Position.Y + 2 and pos.Y > e.target.Y - 6 and AI.visible(e.lamp.Position, pos, nil, e.model) then
				return 6, e.lamp.Position, e
			end
		end
	end
	for _, f in ipairs(G.Equipment.activeFlares()) do
		if (f.position - pos).Magnitude < f.radius and AI.visible(f.position, pos) then
			return 3, f.position, nil
		end
	end
	local defense = G.Building.defenseAt(pos)
	if defense == "post" then
		return 8, pos, nil
	elseif defense == "fence" then
		return 10, pos, nil
	end
	return 0, nil, nil
end

-- Is any player shining a flashlight at `pos` from close range?
function AI.flashlightOn(pos, range)
	for _, p in ipairs(Players:GetPlayers()) do
		local origin, dir = G.Equipment.beamOf(p)
		if origin then
			local delta = pos - origin
			if delta.Magnitude > 0.05 and delta.Magnitude < range and dir:Dot(delta.Unit) > 0.85 and AI.visible(origin, pos, nil, p.Character) then
				return p
			end
		end
	end
	return nil
end

-- A focused flashlight beam (hold right mouse) burns like a small floodlight.
function AI.focusedBeam(pos, range)
	for _, p in ipairs(Players:GetPlayers()) do
		local origin, dir, focused = G.Equipment.beamOf(p)
		if origin and focused then
			local delta = pos - origin
			if delta.Magnitude > 0.05 and delta.Magnitude < range and dir:Dot(delta.Unit) > 0.94 and AI.visible(origin, pos, nil, p.Character) then
				return p, origin
			end
		end
	end
	return nil
end

-- Damage --------------------------------------------------------------------
function AI.hit(model, amount, byPlayer)
	local hum = model:FindFirstChildOfClass("Humanoid")
	if not hum or hum.Health <= 0 then
		return
	end
	hum:TakeDamage(amount)
	local brain = model:GetAttribute("Brain")
	if brain == "Mimic" then
		AI.Mimic.onHit(model, byPlayer)
	elseif brain == "Climber" then
		AI.Climber.onHit(model, byPlayer)
	elseif brain == "Lurker" then
		AI.Lurker.onHit(model, byPlayer)
	elseif brain == "Peeker" then
		AI.Peeker.onHit(model, byPlayer)
		return
	end
	if hum.Health <= 0 and byPlayer then
		AI.hive.meleeDeaths += 1
		G.PlayerData.stat(byPlayer, "Kills", 1)
		G.PlayerData.addCredits(byPlayer, 3)
		if G.Quests then
			G.Quests.event("Kill", brain or "Creature", 1)
		end
		if brain == "Mimic" then
			G.PlayerData.award(byPlayer, "UNMASKED")
		end
	end
end

-- Called by a creature brain when it dies (any cause).
function AI.died(model, lit)
	if lit then
		AI.hive.lightDeaths += 1
	end
	local root = model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
	if root then
		SFX.play("GrowlLow", root, { speed = 0.8 })
	end
end

-- More lamp saboteurs once the hive has lost creatures to the light.
function AI.saboteurChance(base)
	return math.clamp(base + AI.hive.lightDeaths * 0.02, 0, 0.6)
end

function AI.dodgeChance()
	local day = G.DayCycle.day or 1
	return math.clamp(0.15 + day * 0.004 + AI.hive.meleeDeaths * 0.01, 0.15, 0.5)
end

-- The one question every creature asks before it comes into the world.
function AI.allowed(force)
	return force == true or (G.Director.profile.brain or 0) > 0
end

function AI.register(model, brain)
	model:SetAttribute("Brain", brain)
	CollectionService:AddTag(model, "Monster")
	local hl = Instance.new("Highlight")
	hl.Name = "CameraTag"
	hl.FillTransparency = 1
	hl.OutlineColor = Color3.fromRGB(255, 60, 40)
	hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	hl.Enabled = false
	hl.Parent = model
end

-- Nearest living player; optional max distance and line-of-sight check.
function AI.nearestPlayer(pos, maxDist, needSight, ignoreModel)
	local best, bestD
	local params
	for _, info in ipairs(G.Util.alivePlayers()) do
		local d = (info.root.Position - pos).Magnitude
		if d < maxDist and (not bestD or d < bestD) then
			local visible = true
			if needSight then
				params = params or rayParams({ ignoreModel })
				local hit = workspace:Raycast(pos, info.root.Position - pos, params)
				visible = hit == nil or hit.Instance:IsDescendantOf(info.character)
			end
			if visible then
				best, bestD = info, d
			end
		end
	end
	return best, bestD
end

function AI.anyPlayerWithin(pos, dist)
	for _, info in ipairs(G.Util.alivePlayers()) do
		if (info.root.Position - pos).Magnitude < dist then
			return true
		end
	end
	return false
end

function AI.watcherPosition()
	return AI.Watcher.position()
end

function AI.count()
	return #CollectionService:GetTagged("Monster")
end

function AI.clearNight()
	AI.Climber.retreatAll()
	AI.Mimic.clear()
	AI.Watcher.leave()
	AI.Lurker.retreatAll()
	AI.Silhouette.leave()
	AI.Peeker.leave()
	AI.Roster.clear()
	for p, h in pairs(AI.hive.players) do
		h.scented = false
		h.anchor = nil
		if p.Parent then
			p:SetAttribute("Scented", false)
		end
	end
end

-- Sonar + cameras (every 2 s).
local sonarTimer = 0
local function compass(v)
	local a = math.deg(math.atan2(v.X, -v.Z)) % 360
	local names = { "N", "NE", "E", "SE", "S", "SW", "W", "NW" }
	return names[math.floor((a + 22.5) / 45) % 8 + 1]
end

function AI.updateSensors(dt)
	sonarTimer -= dt
	if sonarTimer > 0 then
		return
	end
	sonarTimer = 2
	local cams = G.Power.isPowered("Cameras")
	local center = Vector3.new(0, 30, 0)
	local count, nearest, nearestD = 0, nil, nil
	for _, m in ipairs(CollectionService:GetTagged("Monster")) do
		local root = m.PrimaryPart or m:FindFirstChild("HumanoidRootPart")
		if root then
			local onRig = G.Util.onRig(root.Position)
			local hl = m:FindFirstChild("CameraTag")
			if hl then
				hl.Enabled = cams and onRig
			end
			local d = (root.Position - center).Magnitude
			if d < 700 then
				count += 1
				if not nearestD or d < nearestD then
					nearest, nearestD = root.Position, d
				end
			end
		end
	end
	if G.Power.isPowered("Sonar") then
		local text
		if count == 0 then
			text = "NO CONTACTS"
		else
			text = count .. " CONTACT" .. (count > 1 and "S" or "")
			if nearest then
				text ..= string.format(" · NEAREST %dm %s", math.floor(nearestD), compass(nearest - center))
			end
		end
		local big = AI.Watcher.position()
		if big then
			local deep = false
			for _, p in ipairs(Players:GetPlayers()) do
				deep = deep or G.PlayerData.hasTech(p, "DeepSonar")
			end
			text ..= deep and string.format(" · LARGE %dm %s", math.floor((big - center).Magnitude), compass(big - center)) or " · LARGE CONTACT"
		end
		G.State.set("Sonar", text)
	else
		G.State.set("Sonar", "")
	end
	G.State.set("Threat", count)
end

-- Main AI tick (5 Hz).
function AI.step(dt)
	local now = os.clock()
	AI.track(dt, now)
	AI.assignRoles(AI.Climber.units)
	AI.Climber.step(now, dt)
	AI.Mimic.step(now, dt)
	AI.Watcher.step(now, dt)
	AI.Lurker.step(now, dt)
	AI.Silhouette.step(now, dt)
	AI.Peeker.step(now, dt)
	AI.updateSensors(dt)
end

return AI
