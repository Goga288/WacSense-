-- StarterPlayerScripts/Client/MonsterAnim
-- Animates the skinned creature models (AI/Roster tiers and the Peeker) on this client, bone
-- by bone: nothing is uploaded and nothing is sent over the network (Bone.Transform is
-- local). Every bone takes part, not only arms and legs:
--   * legs and arms walk / run / crawl in step with how fast the body is really moving
--   * the spine sways, leans into a chase, breathes when still; the body bobs
--   * neck and head turn to look at you, and jerk when it hunts
--   * the jaw hangs, chatters while hunting and gapes when it strikes
--   * every finger curls and twitches on its own; hands flex; toes follow the feet
--   * tails, tentacles, frills and any bone the rig has that we cannot name sway
-- A rig with clips of its own (Modules/MonsterClips, e.g. the Grinner) plays them for walk,
-- run, idle and attacks, and gets the looking, twitching and swaying on top.
--
-- How a bone is moved: its rest pose is read once, relative to the creature's root (which
-- faces the way the creature faces). Motions are rotations about the body's axes (right,
-- up, forward) at the bone's pivot, turned into the bone's own axes, so the same code
-- works for any skeleton, however it was imported.
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local MonsterRigs = require(ReplicatedStorage.Modules.MonsterRigs)

local Anim = { rigs = {} }
local C
local ClipData -- Modules/MonsterClips, loaded on first use

local UP, FWD, RIGHT, DOWN = Vector3.new(0, 1, 0), Vector3.new(0, 0, -1), Vector3.new(1, 0, 0), Vector3.new(0, -1, 0)
local IDENTITY = CFrame.identity
local TAU = math.pi * 2
local HUNT = { Chase = true, Attack = true, Stalk = true, Scale = true, Regroup = true, Hunt = true, Lunge = true }

-- Names ---------------------------------------------------------------------------------
local PATTERNS = {
	{ "finger", { "digit", "finger", "thumb", "index", "middle", "ring", "pinky", "claw", "nail" } },
	{ "hand", { "palm", "hand", "wrist" } },
	{ "clavicle", { "clavicle", "collar", "shoulder" } },
	{ "leg", { "thigh", "upleg", "calf", "shin", "knee", "leg", "foot", "toe", "ankle" } },
	{ "arm", { "upperarm", "forearm", "elbow", "arm" } },
	{ "jaw", { "jaw", "mouth", "mause", "mandible", "chin", "lip" } },
	{ "tail", { "tail", "tentacle", "tongue", "hair", "ear", "cloth", "cape", "tendril", "wing" } },
	{ "head", { "head", "skull" } },
	{ "neck", { "neck", "neg" } },
	{ "pelvis", { "pelvis", "hips", "hip", "root" } },
	{ "spine", { "spine", "chest", "ribcage", "rib", "torso", "body", "abdomen", "belly" } },
}

local function category(name)
	local n = string.lower(name)
	n = string.gsub(n, "armature", "")
	n = string.gsub(n, "forehead", "brow")
	for _, entry in ipairs(PATTERNS) do
		for _, word in ipairs(entry[2]) do
			if string.find(n, word, 1, true) then
				return entry[1]
			end
		end
	end
	return nil
end

-- Small helpers ---------------------------------------------------------------------------
local function unit(v, fallback)
	local m = v.Magnitude
	if m < 1e-5 then
		return fallback
	end
	return v / m
end

-- Axis that turns direction `d` towards `toward` (positive angle), or the fallback.
local function turnAxis(d, toward, fallback, minSin)
	local c = d:Cross(toward)
	if c.Magnitude < (minSin or 0.25) then
		return fallback
	end
	return c.Unit
end

local function noise(t, seed)
	return math.noise(t, seed, 0.37)
end

-- Rig building ----------------------------------------------------------------------------
local function buildRig(model)
	local root = model:FindFirstChild("HumanoidRootPart")
	local mesh = MonsterRigs.meshOf(model)
	if not root or not mesh then
		return nil
	end
	local list = {}
	for _, d in ipairs(mesh:GetDescendants()) do
		if d:IsA("Bone") then
			table.insert(list, d)
		end
	end
	if #list == 0 then
		return nil
	end
	local spec = MonsterRigs.spec(model:GetAttribute("MeshName") or mesh.Name)
	local hum = model:FindFirstChildOfClass("Humanoid")
	local rig = {
		model = model, root = root, mesh = mesh, hum = hum, spec = spec,
		gait = model:GetAttribute("Gait") or spec.gait or "biped",
		height = model:GetAttribute("Height") or mesh.Size.Y,
		bones = {}, byInst = {}, limbs = {}, fingers = {}, spine = {}, neck = {}, heads = {}, jaws = {},
		chains = {}, extras = {}, hands = {}, tops = {},
		phase = math.random() * TAU, walk = 0, lookYaw = 0, lookPitch = 0,
		seed = math.random() * 100, frame = 0, clip = nil,
		groundY = -(root.Size.Y / 2 + (hum and hum.HipHeight or 0)),
	}
	local rootCF = root.CFrame
	for _, b in ipairs(list) do
		b.Transform = IDENTITY
		local rest = rootCF:ToObjectSpace(b.WorldCFrame)
		local info = { bone = b, name = b.Name, rest = rest, R = rest.Rotation, p = rest.Position, cat = category(b.Name), children = {} }
		rig.byInst[b] = info
		table.insert(rig.bones, info)
	end
	for _, info in ipairs(rig.bones) do
		local parent = info.bone.Parent
		info.parent = parent and rig.byInst[parent] or nil
		if info.parent then
			table.insert(info.parent.children, info)
		else
			table.insert(rig.tops, info)
		end
	end
	-- Depth (parents before children).
	local ordered = {}
	local function visit(info, depth)
		info.depth = depth
		table.insert(ordered, info)
		for _, c in ipairs(info.children) do
			visit(c, depth + 1)
		end
	end
	for _, top in ipairs(rig.tops) do
		visit(top, 0)
	end
	rig.bones = ordered
	-- Skeleton extent.
	local lo, hi = math.huge, -math.huge
	local wide = 0
	for _, info in ipairs(rig.bones) do
		lo = math.min(lo, info.p.Y)
		hi = math.max(hi, info.p.Y)
		wide = math.max(wide, math.abs(info.p.X))
	end
	rig.skelLo, rig.skelHi, rig.skelWide = lo, hi, math.max(wide, 0.5)
	return rig
end

-- Direction of a bone at rest: towards its (first) child, else away from its parent.
local function restDir(info)
	local child = info.children[1]
	if child then
		local best = child
		-- Prefer the child that continues the chain (same category), then the farthest.
		for _, c in ipairs(info.children) do
			if c.cat == info.cat and best.cat ~= info.cat then
				best = c
			end
		end
		return unit(best.p - info.p, UP)
	end
	if info.parent then
		return unit(info.p - info.parent.p, UP)
	end
	return UP
end

-- Follows single children of the same kind: a limb, a finger, a tail.
local function chainFrom(info, same)
	local chain = { info }
	local cur = info
	while true do
		local nextOne = nil
		local count = 0
		for _, c in ipairs(cur.children) do
			if same(c) then
				nextOne = c
				count += 1
			end
		end
		if count ~= 1 then
			break
		end
		table.insert(chain, nextOne)
		cur = nextOne
	end
	return chain
end

-- Named rigs: limbs by name. Unnamed rigs (Bone.001...): limbs by shape.
local function classify(rig)
	local named = false
	for _, info in ipairs(rig.bones) do
		if info.cat == "arm" or info.cat == "leg" then
			named = true
			break
		end
	end
	if not named then
		-- Chains that start at a branch. The lowest-reaching descending ones are legs,
		-- the others that hang or reach sideways are arms, one that rises is a neck.
		local span = math.max(rig.skelHi - rig.skelLo, 0.5)
		for _, info in ipairs(rig.bones) do
			if #info.children >= 2 or not info.parent then
				for _, c in ipairs(info.children) do
					if c.cat == nil then
						local chain = chainFrom(c, function(x)
							return x.cat == nil
						end)
						if #chain >= 2 then
							local tip = chain[#chain]
							local drop = c.p.Y - tip.p.Y
							local kind
							if tip.p.Y < rig.skelLo + span * 0.3 and drop > span * 0.2 then
								kind = "leg"
							elseif tip.p.Y > c.p.Y + span * 0.15 and math.abs(tip.p.X) < rig.skelWide * 0.35 then
								kind = "neck"
							elseif math.abs(tip.p.X - c.p.X) > span * 0.08 or drop > span * 0.1 then
								kind = "arm"
							end
							if kind then
								for i, b in ipairs(chain) do
									b.cat = kind
									if kind == "neck" and i == #chain then
										b.cat = "head"
									end
								end
							end
						end
					end
				end
			end
		end
		-- What holds the limbs together is the spine.
		for _, info in ipairs(rig.bones) do
			if info.cat == nil and #info.children >= 1 then
				local limbKids = false
				for _, c in ipairs(info.children) do
					if c.cat == "arm" or c.cat == "leg" or c.cat == "neck" then
						limbKids = true
					end
				end
				if limbKids then
					info.cat = "spine"
				end
			end
		end
	end
	-- Fingers: every chain hanging off a hand counts, whatever it is called.
	for _, info in ipairs(rig.bones) do
		if info.cat == "hand" then
			for _, c in ipairs(info.children) do
				if c.cat == nil or c.cat == "finger" then
					local chain = chainFrom(c, function(x)
						return x.cat == nil or x.cat == "finger"
					end)
					for _, b in ipairs(chain) do
						b.cat = "finger"
					end
				end
			end
		end
	end
end

-- Rest corrections: a T-posed biped lowers its arms, a crawler puts its hands down.
local function corrections(rig)
	local clipRig = rig.spec.clips ~= nil
	for _, info in ipairs(rig.bones) do
		info.C = nil
		if not clipRig and info.cat == "arm" and (not info.parent or info.parent.cat ~= "arm") then
			local d = restDir(info)
			local target
			if rig.gait == "crawl" then
				target = unit(Vector3.new(d.X * 0.5, -0.86, -0.2), DOWN)
			elseif d.Y > -0.3 then
				target = unit(Vector3.new(d.X * 0.2, -1, 0.06), DOWN)
			end
			if target then
				local axis = d:Cross(target)
				if axis.Magnitude > 1e-3 then
					local angle = math.acos(math.clamp(d:Dot(target), -1, 1))
					info.C = CFrame.fromAxisAngle(axis.Unit, angle)
				end
			end
		end
	end
	-- Forward kinematics of the corrections: corrected orientation K and position q.
	for _, info in ipairs(rig.bones) do
		local parent = info.parent
		local Yp = parent and parent.Y or IDENTITY
		info.Y = info.C and (Yp * info.C) or Yp
		info.K = info.Y * info.R
		if parent then
			info.q = parent.q + parent.Y:VectorToWorldSpace(info.p - parent.p)
		else
			info.q = info.p
		end
		-- Local correction, applied first in the bone's own frame.
		info.Cl = info.C and (info.R:Inverse() * info.C * info.R) or nil
	end
	-- Corrected directions.
	for _, info in ipairs(rig.bones) do
		local child = info.children[1]
		for _, c in ipairs(info.children) do
			if c.cat == info.cat then
				child = c
				break
			end
		end
		if child then
			info.d = unit(child.q - info.q, UP)
		elseif info.parent then
			info.d = unit(info.q - info.parent.q, UP)
		else
			info.d = UP
		end
	end
end

-- A body-space axis in this bone's own frame.
local function localAxis(info, v)
	return info.K:VectorToObjectSpace(v)
end

local function setupParts(rig)
	local crawl = rig.gait == "crawl"
	-- Limbs.
	for _, info in ipairs(rig.bones) do
		local isStart = (info.cat == "arm" or info.cat == "leg" or info.cat == "clavicle")
			and (not info.parent or (info.parent.cat ~= info.cat and not (info.parent.cat == "clavicle" and info.cat == "arm")))
		if isStart then
			local kind = info.cat == "leg" and "leg" or "arm"
			local chain = chainFrom(info, function(x)
				return x.cat == "arm" or x.cat == "leg" or (info.cat == "clavicle" and x.cat == "clavicle")
			end)
			local startIdx = 1
			if info.cat == "clavicle" then
				startIdx = 2
			end
			local upper = chain[startIdx]
			-- The elbow / knee: the first bone named like one; a rig without such names
			-- (armL1, armL2...) bends at the next bone. Twist segments (Upperarm1, 2) are skipped.
			local lower, lowerIdx = nil, nil
			for i = startIdx + 1, #chain do
				local n = string.lower(chain[i].name)
				local isJoint = string.find(n, "forearm", 1, true) or string.find(n, "lowerarm", 1, true)
					or string.find(n, "elbow", 1, true) or string.find(n, "calf", 1, true) or string.find(n, "shin", 1, true)
					or string.find(n, "knee", 1, true) or (string.find(n, "leg", 1, true) and not string.find(n, "upleg", 1, true))
				if isJoint then
					lower, lowerIdx = chain[i], i
					break
				end
			end
			if not lower then
				lower, lowerIdx = chain[startIdx + 1], startIdx + 1
			end
			if upper then
				local tip = chain[#chain]
				local side = (tip.q.X >= upper.q.X - 0.01) and 1 or -1
				if math.abs(tip.q.X) > 0.05 then
					side = tip.q.X > 0 and 1 or -1
				end
				local limb = { kind = kind, side = side, chain = chain, clavicle = startIdx == 2 and chain[1] or nil,
					upper = upper, lower = lower, rest = {} }
				for i = (lowerIdx or startIdx + 1) + 1, #chain do
					table.insert(limb.rest, chain[i])
				end
				-- Spine bones this limb hangs from: their lean is taken back out of it.
				limb.anc = {}
				local a = upper.parent
				while a do
					if a.cat == "spine" or a.cat == "pelvis" then
						table.insert(limb.anc, a)
					end
					a = a.parent
				end
				upper.compAxis = localAxis(upper, RIGHT)
				upper.sweepAxis = localAxis(upper, UP)
				-- Phase group: legs alternate; arms swing against the leg on their side;
				-- a crawler moves diagonal pairs together.
				local left = side < 0
				if kind == "leg" then
					limb.group = left and 0 or 1
				else
					limb.group = left and 1 or 0
				end
				if crawl then
					limb.group = (kind == "arm") == left and 0 or 1
				end
				-- Axes (body space).
				local du = upper.d
				upper.strideAxis = localAxis(upper, turnAxis(du, FWD, RIGHT, 0.3))
				upper.liftAxis = localAxis(upper, turnAxis(du, UP, RIGHT * -1, 0.3))
				if lower then
					local dl = lower.d
					local bend = du:Cross(dl)
					local axis
					-- Trust the bend it was modelled with only if it bends front-to-back.
					-- A crawler's dragged legs always fold upwards, never into the floor.
					if crawl and kind == "leg" then
						axis = turnAxis(dl, UP, RIGHT * -1, 0.3)
					elseif bend.Magnitude > 0.12 and math.abs(bend.Unit:Dot(RIGHT)) > 0.6 then
						axis = bend.Unit
					elseif kind == "leg" then
						axis = turnAxis(dl, -FWD, RIGHT * -1, 0.3)
					else
						axis = turnAxis(dl, FWD, RIGHT, 0.3)
					end
					lower.bendAxis = localAxis(lower, axis)
					limb.bendBody = axis
					for _, r in ipairs(limb.rest) do
						r.bendAxis = localAxis(r, axis)
					end
				end
				table.insert(rig.limbs, limb)
			end
		end
	end
	-- Fingers: curl towards the body's centre line.
	for _, info in ipairs(rig.bones) do
		if info.cat == "finger" and (not info.parent or info.parent.cat ~= "finger") then
			local chain = chainFrom(info, function(x)
				return x.cat == "finger"
			end)
			local d = info.d
			local inward = Vector3.new(-info.q.X, 0, -info.q.Z)
			inward = inward - d * inward:Dot(d)
			local axis = turnAxis(d, unit(inward, FWD), turnAxis(d, FWD, RIGHT, 0.2), 0.05)
			local finger = { chain = chain, speed = 1.5 + math.random() * 2.5, seed = math.random() * 50, spasm = 0, spasmUntil = 0 }
			for _, b in ipairs(chain) do
				b.curlAxis = localAxis(b, axis)
				b.spreadAxis = localAxis(b, turnAxis(d, UP, RIGHT, 0.05))
			end
			table.insert(rig.fingers, finger)
		elseif info.cat == "hand" then
			info.flexAxis = localAxis(info, turnAxis(info.d, FWD, RIGHT, 0.2))
			info.twistAxis = localAxis(info, info.d)
			table.insert(rig.hands, info)
		end
	end
	-- Spine, neck, head, jaw.
	for _, info in ipairs(rig.bones) do
		local cat = info.cat
		if cat == "spine" or cat == "pelvis" then
			table.insert(rig.spine, info)
		elseif cat == "neck" then
			table.insert(rig.neck, info)
		elseif cat == "head" then
			table.insert(rig.heads, info)
		elseif cat == "jaw" then
			info.openAxis = localAxis(info, turnAxis(info.d, DOWN, RIGHT * -1, 0.2))
			table.insert(rig.jaws, info)
		elseif cat == "clavicle" then
			info.shrugAxis = localAxis(info, turnAxis(info.d, UP, FWD, 0.2))
		end
		if cat == "spine" or cat == "pelvis" or cat == "neck" or cat == "head" then
			info.yawAxis = localAxis(info, UP)
			info.pitchAxis = localAxis(info, RIGHT)
			info.rollAxis = localAxis(info, FWD)
		end
	end
	-- The topmost head wins (some rigs have a "head" helper under the real one).
	table.sort(rig.heads, function(a, b)
		return a.depth < b.depth
	end)
	-- Tails, tentacles and anything unnamed: waves along the chain, or a gentle drift.
	local claimed = {}
	for _, info in ipairs(rig.bones) do
		if (info.cat == "tail" or info.cat == nil) and not claimed[info] and (not info.parent or info.parent.cat ~= info.cat or info.cat == nil) then
			local chain = chainFrom(info, function(x)
				return (x.cat == "tail" or x.cat == nil) and not claimed[x]
			end)
			for _, b in ipairs(chain) do
				claimed[b] = true
				local d = b.d
				local s1 = turnAxis(d, UP, FWD, 0.2)
				local s2 = unit(d:Cross(s1), RIGHT)
				b.swayA = localAxis(b, s1)
				b.swayB = localAxis(b, s2)
			end
			local isTail = info.cat == "tail" or #chain >= 4
			table.insert(isTail and rig.chains or rig.extras, { chain = chain, speed = 1.2 + math.random() * 1.6, seed = math.random() * 50 })
		end
	end
	-- Top bones carry the whole body: the bob is a translation on them.
	for _, top in ipairs(rig.tops) do
		top.bobAxis = top.R:VectorToObjectSpace(UP)
	end
	local legLen = 0
	for _, limb in ipairs(rig.limbs) do
		if limb.kind == "leg" then
			local tip = limb.chain[#limb.chain]
			legLen = math.max(legLen, (tip.q - limb.upper.q).Magnitude)
		end
	end
	rig.legLen = legLen > 0.3 and legLen or rig.height * (rig.gait == "crawl" and 0.3 or 0.45)
end

-- Clips ----------------------------------------------------------------------------------
local decoded = {}
local function clipOf(setName, clipName, scale)
	local key = setName .. "/" .. clipName .. "/" .. scale
	if decoded[key] ~= nil then
		return decoded[key] or nil
	end
	decoded[key] = false
	if not ClipData then
		local ok, data = pcall(function()
			return require(ReplicatedStorage.Modules:WaitForChild("MonsterClips", 5))
		end)
		ClipData = ok and data or {}
	end
	local set = ClipData[setName]
	local raw = set and set[clipName]
	if not raw then
		return nil
	end
	local clip = { length = raw.length, times = raw.times, tracks = {} }
	for boneName, nums in pairs(raw.bones) do
		local frames = {}
		for i = 1, #nums, 7 do
			frames[#frames + 1] = CFrame.new(nums[i] * scale, nums[i + 1] * scale, nums[i + 2] * scale, nums[i + 3], nums[i + 4], nums[i + 5], nums[i + 6])
		end
		clip.tracks[boneName] = frames
	end
	decoded[key] = clip
	return clip
end

local function sample(clip, t, loop)
	local times = clip.times
	local n = #times
	if loop then
		t = t % math.max(clip.length, 1e-3)
	else
		t = math.clamp(t, 0, clip.length)
	end
	local i = 1
	-- Frames are evenly spaced: jump close, then settle.
	local step = n > 1 and (times[n] - times[1]) / (n - 1) or 1
	i = math.clamp(math.floor(t / math.max(step, 1e-3)) + 1, 1, n)
	while i < n and times[i + 1] <= t do
		i += 1
	end
	while i > 1 and times[i] > t do
		i -= 1
	end
	local j = math.min(i + 1, n)
	local span = times[j] - times[i]
	local a = span > 1e-5 and (t - times[i]) / span or 0
	return i, j, a
end

local function clipPose(clip, boneName, i, j, a)
	local frames = clip.tracks[boneName]
	if not frames then
		return IDENTITY
	end
	local f1, f2 = frames[i], frames[j]
	if not f1 then
		return IDENTITY
	end
	return a > 0 and f2 and f1:Lerp(f2, a) or f1
end

-- Which clip plays for a state.
local function clipFor(rig, state, attacking, speed)
	local c = rig.spec.clips
	if attacking then
		return "Attack"
	end
	if state == "Dead" then
		return c.Fall and "Fall" or "Idle"
	end
	if state == "Climb" or state == "Scale" then
		return "Run"
	end
	if speed > 12 or HUNT[state] and speed > 3 then
		return "Run"
	end
	if speed > 1.5 then
		return "Walk"
	end
	return "Idle"
end

local function pickClipName(rig, slot)
	local c = rig.spec.clips[slot]
	if type(c) == "table" then
		return c[math.random(1, #c)]
	end
	return c
end

-- Per-frame --------------------------------------------------------------------------------
local function lookTarget(rig)
	-- The creature looks at the nearest player within range (you, most of the time).
	local rootPos = rig.root.Position
	local best, bestD = nil, 90
	for _, p in ipairs(Players:GetPlayers()) do
		local ch = p.Character
		local head = ch and ch:FindFirstChild("Head")
		if head then
			local d = (head.Position - rootPos).Magnitude
			if d < bestD then
				best, bestD = head.Position, d
			end
		end
	end
	return best
end

local function rot(axis, angle)
	if not axis or math.abs(angle) < 1e-4 then
		return IDENTITY
	end
	return CFrame.fromAxisAngle(axis, angle)
end

local function step(rig, dt, now, serverNow)
	local model = rig.model
	local state = model:GetAttribute("State") or "Idle"
	if state == "Hidden" then
		return
	end
	local root = rig.root
	local vel = root.AssemblyLinearVelocity
	local speed = Vector3.new(vel.X, 0, vel.Z).Magnitude
	local hunting = HUNT[state] == true
	local still = state == "Still" or state == "Lurk"
	local dead = state == "Dead"
	local climbing = state == "Climb" or state == "Scale"
	local attackUntil = model:GetAttribute("AttackUntil") or 0
	local attackLeft = attackUntil - serverNow
	local attacking = attackLeft > -0.25 and attackLeft < 0.7
	local strike = attacking and math.sin(math.clamp(1 - (attackLeft + 0.25) / 0.7, 0, 1) * math.pi) or 0
	local flinch = state == "Flinch"
	local peeker = model:GetAttribute("Brain") == "Peeker"

	-- Gait.
	local moving = speed > 1.2 and not dead
	local targetWalk = moving and math.clamp(speed / 14, 0.25, 1.25) or 0
	if climbing then
		targetWalk = 1
	end
	if still then
		targetWalk = 0
	end
	rig.walk += (targetWalk - rig.walk) * math.min(dt * 6, 1)
	local w = rig.walk
	local cadence = math.clamp(speed / math.max(rig.legLen * 1.6, 0.5), 0.5, 3.4)
	if climbing then
		cadence = 1.4
	end
	if moving or climbing then
		rig.phase = (rig.phase + dt * TAU * cadence) % TAU
	end
	local phi = rig.phase
	local t = still and (rig.frozenT or now) or now
	if not still then
		rig.frozenT = now
	end
	local crawl = rig.gait == "crawl"

	-- Look.
	local target = lookTarget(rig)
	local yawWant, pitchWant = 0, 0
	local head = rig.heads[1]
	if target and not dead then
		local from = head and head.bone.TransformedWorldCFrame.Position or root.Position
		local v = root.CFrame:VectorToObjectSpace(target - from)
		local flat = math.sqrt(v.X * v.X + v.Z * v.Z)
		yawWant = math.clamp(math.atan2(-v.X, -v.Z), -1.15, 1.15)
		pitchWant = math.clamp(math.atan2(v.Y, math.max(flat, 0.1)), -0.55, 0.6)
		if not hunting and not peeker then
			-- Idle: only glances at you now and then.
			local glance = noise(now * 0.15, rig.seed) > 0.1
			if not glance then
				yawWant = noise(now * 0.2, rig.seed + 3) * 1.1
				pitchWant = noise(now * 0.17, rig.seed + 5) * 0.3
			end
		end
	else
		yawWant = noise(now * 0.2, rig.seed + 3) * 0.8
		pitchWant = noise(now * 0.17, rig.seed + 5) * 0.25
	end
	if dead then
		yawWant, pitchWant = 0, -0.6
	end
	local follow = math.min(dt * (hunting and 9 or 4), 1)
	rig.lookYaw += (yawWant - rig.lookYaw) * follow
	rig.lookPitch += (pitchWant - rig.lookPitch) * follow
	-- Twitches: it holds a pose, then snaps to another.
	if now >= (rig.nextTwitch or 0) then
		rig.nextTwitch = now + (hunting and (0.05 + math.random() * 0.12) or (0.35 + math.random() * 1.2))
		local amount = (hunting and 0.28 or 0.08) * (still and 0.2 or 1)
		rig.twitch = { (math.random() - 0.5) * amount, (math.random() - 0.5) * amount * 1.4, (math.random() - 0.5) * amount }
	end
	local tw = rig.twitch or { 0, 0, 0 }

	-- Clip (rigs with their own animation).
	local clipCtx = nil
	local spec = rig.spec
	if spec.clips then
		local scale = model:GetAttribute("AnimScale") or 1
		local slot = clipFor(rig, state, attacking, speed)
		local cur = rig.clip
		if not cur or cur.slot ~= slot or (slot == "Attack" and attackUntil ~= cur.attackUntil) then
			local name = pickClipName(rig, slot)
			local clip = name and clipOf(spec.clips.set, name, scale)
			if clip then
				rig.prevClip = cur and { clip = cur.clip, t = cur.t, loop = cur.loop } or nil
				rig.blend = 0
				rig.clip = { slot = slot, clip = clip, t = 0, loop = slot ~= "Attack" and slot ~= "Fall", attackUntil = attackUntil }
				cur = rig.clip
			end
		end
		if cur then
			local rate = 1
			if cur.slot == "Walk" then
				rate = math.clamp(speed / 9, 0.6, 1.6)
			elseif cur.slot == "Run" then
				rate = math.clamp(speed / 19, 0.7, 1.5)
			elseif cur.slot == "Attack" then
				rate = math.clamp(cur.clip.length / 0.7, 1, 2.2)
			end
			if still then
				rate = 0
			end
			cur.t += dt * rate
			rig.blend = math.min((rig.blend or 1) + dt / 0.22, 1)
			local i, j, a = sample(cur.clip, cur.t, cur.loop)
			clipCtx = { cur = cur, i = i, j = j, a = a }
			local prev = rig.prevClip
			if prev and rig.blend < 1 then
				local pi_, pj, pa = sample(prev.clip, prev.t, prev.loop)
				clipCtx.prev, clipCtx.pi, clipCtx.pj, clipCtx.pa = prev, pi_, pj, pa
			else
				rig.prevClip = nil
			end
		end
	end

	-- Per-bone rotations, collected as lists of {axis, angle} in each bone's frame
	-- (the lists are kept between frames and emptied, not rebuilt).
	local extra = rig.extra
	if not extra then
		extra = {}
		rig.extra = extra
	end
	for _, e in pairs(extra) do
		table.clear(e)
	end
	local function add(info, axis, angle)
		if not info or not axis or math.abs(angle) < 1e-4 then
			return
		end
		local e = extra[info]
		if not e then
			e = {}
			extra[info] = e
		end
		e[#e + 1] = axis
		e[#e + 1] = angle
	end
	local bob = 0

	if not clipCtx then
		-- Spine: sway with the steps, lean into a chase, breathe. A crawler keeps its
		-- body low and rears up with its neck instead.
		local pitchOf = {}
		local n = math.max(#rig.spine, 1)
		local lean = (hunting and 0.22 or 0.05 * w) + strike * 0.35 - (flinch and 0.35 or 0) + (dead and 0.7 or 0)
		for k, info in ipairs(rig.spine) do
			local share = 1 / n
			add(info, info.yawAxis, (crawl and 0.16 or 0.045) * w * math.sin(phi) * share * 2)
			add(info, info.rollAxis, 0.05 * w * math.cos(phi) * share * 2)
			local pitch = (crawl and 0 or -lean * share) + 0.025 * math.sin(t * 1.4 + k * 0.4)
			add(info, info.pitchAxis, pitch)
			pitchOf[info] = pitch
		end
		if crawl then
			local rear = strike * 0.5 + (hunting and 0.12 or 0) - (dead and 0.5 or 0)
			local nn = math.max(#rig.neck, 1)
			for _, info in ipairs(rig.neck) do
				add(info, info.pitchAxis, rear / nn)
			end
		end
		bob = rig.height * 0.014 * w * math.cos(2 * phi) - (dead and rig.height * 0.1 or 0)
		-- Limbs. Legs (and a crawler's arms) first take back the lean of the body above
		-- them, so the feet stay planted when it leans.
		for _, limb in ipairs(rig.limbs) do
			local psi = phi + limb.group * math.pi
			local s, c = math.sin(psi), math.cos(psi)
			local upper, lower = limb.upper, limb.lower
			if limb.kind == "leg" or crawl then
				local sum = 0
				for _, a in ipairs(limb.anc) do
					sum += pitchOf[a] or 0
				end
				add(upper, upper.compAxis, -sum)
			end
			if dead then
				add(upper, upper.liftAxis, limb.kind == "arm" and -0.4 or 0)
			elseif climbing then
				-- Clawing its way up: arms reach, legs push.
				if limb.kind == "arm" then
					add(upper, upper.liftAxis, 1.1 + 0.5 * s)
					add(lower, lower and lower.bendAxis, 0.5 + 0.4 * math.max(0, c))
				else
					add(upper, upper.strideAxis, 0.5 * s)
					add(lower, lower and lower.bendAxis, 0.7 * math.max(0, c))
				end
			elseif limb.kind == "leg" then
				if crawl then
					-- Dragged legs: they scrape side to side and kick up, never into the floor.
					add(upper, upper.sweepAxis, 0.2 * c * w)
					add(upper, upper.liftAxis, 0.22 * math.max(0, s) * w)
					add(lower, lower and lower.bendAxis, 0.35 * math.max(0, c) * w)
				else
					add(upper, upper.strideAxis, 0.55 * s * w - strike * 0.1)
					local knee = (0.95 * math.max(0, c) + 0.08) * w
					add(lower, lower and lower.bendAxis, knee)
					for k, r in ipairs(limb.rest) do
						add(r, r.bendAxis, (k == 1 and -0.45 or 0.3) * knee)
					end
				end
			else -- arm
				local swing = crawl and 0.65 or 0.42
				local breathe = 0.05 * math.sin(t * 1.1 + limb.side)
				local reach = strike * (crawl and 0.9 or 1.3) -- the blow
				add(upper, upper.strideAxis, swing * s * w + breathe + reach + (hunting and not crawl and 0.25 or 0))
				if crawl then
					add(upper, upper.liftAxis, 0.3 * math.max(0, c) * w)
				end
				if flinch then
					add(upper, upper.liftAxis, 0.6)
				end
				local elbow = 0.12 + 0.35 * math.max(0, s) * w + (hunting and 0.3 or 0) - strike * 0.5
				add(lower, lower and lower.bendAxis, elbow)
				if limb.clavicle then
					add(limb.clavicle, limb.clavicle.shrugAxis, 0.04 * math.sin(t * 1.4) + strike * 0.2 + (hunting and 0.08 or 0))
				end
			end
		end
	else
		-- A clip plays: the spine still breathes a little on top of it.
		for k, info in ipairs(rig.spine) do
			add(info, info.pitchAxis, 0.015 * math.sin(t * 1.4 + k * 0.4))
		end
	end

	-- Neck and head: look, plus the twitches.
	local lookers = {}
	for _, info in ipairs(rig.neck) do
		table.insert(lookers, info)
	end
	if head then
		table.insert(lookers, head)
	end
	local nl = #lookers
	for k, info in ipairs(lookers) do
		local share = (info == head) and (nl > 1 and 0.45 or 1) or (0.55 / math.max(nl - 1, 1))
		add(info, info.yawAxis, (rig.lookYaw + tw[2]) * share)
		add(info, info.pitchAxis, (rig.lookPitch + tw[1]) * share)
		add(info, info.rollAxis, (tw[3] + (peeker and 0.12 or 0) + 0.03 * math.sin(t * 0.7)) * share)
	end

	-- Jaw.
	for _, info in ipairs(rig.jaws) do
		local open = 0.04 + 0.03 * math.sin(t * 0.9)
		if hunting then
			open = 0.22 + 0.12 * math.abs(math.sin(t * 9 + rig.seed))
		end
		if peeker then
			open = 0.12 + 0.12 * math.max(0, math.sin(t * 0.5))
		end
		open += strike * 0.5
		if dead then
			open = 0.45
		end
		add(info, info.openAxis, open)
	end

	-- Fingers: each curls and twitches on its own; claws out when it hunts or strikes.
	local grip = (hunting and 0.35 or 0.12) + strike * 0.55 + (dead and -0.1 or 0) + (peeker and 0.15 or 0)
	for _, f in ipairs(rig.fingers) do
		if now >= f.spasmUntil then
			f.spasmUntil = now + (hunting and (0.1 + math.random() * 0.4) or (0.4 + math.random() * 1.6))
			f.spasm = (math.random() - 0.35) * (hunting and 0.5 or 0.25)
		end
		local wave = 0.12 * math.sin(t * f.speed + f.seed)
		for k, b in ipairs(f.chain) do
			add(b, b.curlAxis, grip + wave + f.spasm * (k == 1 and 0.6 or 1))
			if k == 1 then
				add(b, b.spreadAxis, 0.06 * math.sin(t * f.speed * 0.7 + f.seed))
			end
		end
	end
	for _, h in ipairs(rig.hands) do
		add(h, h.flexAxis, 0.1 * math.sin(t * 1.7 + rig.seed) + strike * 0.3)
		add(h, h.twistAxis, 0.08 * math.sin(t * 1.1 + rig.seed * 2))
	end

	-- Tails and tentacles: a wave running down the chain. Unnamed bones: a slow drift.
	local waveAmp = hunting and 0.24 or 0.15
	for _, ch in ipairs(rig.chains) do
		for k, b in ipairs(ch.chain) do
			local ph = t * ch.speed * (hunting and 1.8 or 1) - k * 0.55 + ch.seed
			add(b, b.swayA, waveAmp * math.sin(ph))
			add(b, b.swayB, waveAmp * 0.5 * math.sin(ph * 0.7 + 1.3))
		end
	end
	for _, ch in ipairs(rig.extras) do
		for k, b in ipairs(ch.chain) do
			add(b, b.swayA, 0.06 * noise(t * 0.6 * ch.speed, ch.seed + k))
			add(b, b.swayB, 0.05 * noise(t * 0.5 * ch.speed, ch.seed + k + 7))
		end
	end

	-- Write the bones.
	for _, info in ipairs(rig.bones) do
		local base = IDENTITY
		if clipCtx then
			local cur = clipCtx.cur
			base = clipPose(cur.clip, info.name, clipCtx.i, clipCtx.j, clipCtx.a)
			if clipCtx.prev then
				local was = clipPose(clipCtx.prev.clip, info.name, clipCtx.pi, clipCtx.pj, clipCtx.pa)
				base = was:Lerp(base, rig.blend)
			end
		elseif info.Cl then
			base = info.Cl
		end
		if info.bobAxis and bob ~= 0 then
			base = CFrame.new(info.bobAxis * bob) * base
		end
		local e = extra[info]
		if e then
			for k = 1, #e, 2 do
				base = base * rot(e[k], e[k + 1])
			end
		end
		info.bone.Transform = base
	end
end

-- Registry ---------------------------------------------------------------------------------
local function track(model)
	if Anim.rigs[model] ~= nil then
		return
	end
	if not model:GetAttribute("MeshName") then
		return
	end
	local ok, rig = pcall(function()
		local r = buildRig(model)
		if r then
			classify(r)
			corrections(r)
			setupParts(r)
		end
		return r
	end)
	if not ok then
		warn("[MonsterAnim] " .. model.Name .. ": " .. tostring(rig))
		Anim.rigs[model] = false
		return
	end
	Anim.rigs[model] = rig or false
end

function Anim.init(ctx)
	C = ctx
	local scan = 0
	RunService.RenderStepped:Connect(function(dt)
		scan -= dt
		if scan <= 0 then
			scan = 0.5
			local npcs = workspace:FindFirstChild("NPCs")
			if npcs then
				for _, m in ipairs(npcs:GetChildren()) do
					if m:IsA("Model") then
						track(m)
					end
				end
			end
			for m in pairs(Anim.rigs) do
				if not m.Parent then
					Anim.rigs[m] = nil
				end
			end
		end
		local camera = workspace.CurrentCamera
		if not camera then
			return
		end
		local camPos = camera.CFrame.Position
		local now = os.clock()
		local serverNow = workspace:GetServerTimeNow()
		for model, rig in pairs(Anim.rigs) do
			if rig and model.Parent and rig.root.Parent then
				local d = (rig.root.Position - camPos).Magnitude
				-- Far away: fewer updates; very far: frozen.
				local every = d < 110 and 1 or d < 220 and 2 or d < 400 and 4 or 0
				if every > 0 then
					rig.frame += 1
					rig.acc = (rig.acc or 0) + dt
					if rig.frame % every == 0 then
						local ok, err = pcall(step, rig, rig.acc, now, serverNow)
						rig.acc = 0
						if not ok and not rig.warned then
							rig.warned = true
							warn("[MonsterAnim] " .. model.Name .. ": " .. tostring(err))
						end
					end
				end
			end
		end
	end)
end

-- For the screamer (Client/Horror) ----------------------------------------------------------
-- The head bone of a creature model (or of a copy of one), or nil.
function Anim.headBone(model)
	local best, bestDepth
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("Bone") and category(d.Name) == "head" then
			local depth = 0
			local p = d.Parent
			while p and p:IsA("Bone") do
				depth += 1
				p = p.Parent
			end
			if not bestDepth or depth < bestDepth then
				best, bestDepth = d, depth
			end
		end
	end
	return best
end

-- Freezes a copy in the pose the original has right now.
function Anim.copyPose(from, to)
	local a, b = {}, {}
	for _, d in ipairs(from:GetDescendants()) do
		if d:IsA("Bone") then
			table.insert(a, d)
		end
	end
	for _, d in ipairs(to:GetDescendants()) do
		if d:IsA("Bone") then
			table.insert(b, d)
		end
	end
	for i = 1, math.min(#a, #b) do
		if a[i].Name == b[i].Name then
			b[i].Transform = a[i].Transform
		end
	end
end

return Anim
