-- ServerScriptService/AI/Peeker
-- THE PEEKER (0.15). The model placed in the map as "the one that spawns somewhere behind
-- a crate and watches" (Modules/MonsterRigs). For now it only watches.
--
-- It turns up behind you: somewhere you are not looking, preferably where a crate, a
-- container or a corner hides its body and only its head shows. It stays there, turned
-- towards you, and you hear it (Config.Sounds.Peeker). Turn round and look at it and it
-- is gone; walk up to it, or put a focused beam on it, and it is gone. A while later it
-- is behind you again, somewhere else. A few visits a night; gone at dawn.
--
-- Anchored and placed, never walking, like the Tall One. Its bones are animated on the
-- clients (Client/MonsterAnim): it breathes, its fingers work and its head follows you.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Modules.Config)
local SFX = require(ReplicatedStorage.Modules.SFX)

local Peeker = { model = nil, want = false, visible = false }
local G, AI
local P = Config.Peeker
local HIDDEN = CFrame.new(0, -2000, 0)

function Peeker.init(g, ai)
	G = g
	AI = ai
end

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
local overlap = OverlapParams.new()
overlap.FilterType = Enum.RaycastFilterType.Exclude
local function refreshFilters()
	local list = { workspace:FindFirstChild("NPCs"), workspace:FindFirstChild("Effects") }
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Character then
			table.insert(list, p.Character)
		end
	end
	rayParams.FilterDescendantsInstances = list
	overlap.FilterDescendantsInstances = list
end

local function kind()
	return AI.Roster and AI.Roster.peeker()
end

local function build()
	local k = kind()
	if not k then
		return nil
	end
	local model = k.template:Clone()
	local root = model.PrimaryPart
	root.Anchored = true
	root.CanCollide = false
	local hum = model:FindFirstChildOfClass("Humanoid")
	if hum then
		-- It cannot be hurt: a crowbar only makes it go away (Peeker.onHit).
		hum.MaxHealth = math.huge
		hum.Health = math.huge
		pcall(function()
			hum.EvaluateStateMachine = false
		end)
	end
	model:PivotTo(HIDDEN)
	model:SetAttribute("State", "Hidden")
	model.Parent = G.World.NPCs
	AI.register(model, "Peeker")
	Peeker.model, Peeker.root, Peeker.info = model, root, k.info
	return model
end

-- Is anyone looking at this spot (with a clear line to it)?
local function seen(pos)
	for _, p in ipairs(Players:GetPlayers()) do
		if AI.lookingAt(p, pos, 220) then
			return true
		end
	end
	return false
end

local function headAt(base)
	return base + Vector3.new(0, Peeker.info.height * 0.88, 0)
end

local function eyesOf(info)
	local head = info.character:FindFirstChild("Head")
	return head and head.Position or info.root.Position + Vector3.new(0, 1.5, 0)
end

-- Somewhere to stand: dry level floor, no floodlight, room for its body.
local function standAt(x, z, fromY)
	local hit = workspace:Raycast(Vector3.new(x, fromY, z), Vector3.new(0, -30, 0), rayParams)
	if not hit or hit.Material == Enum.Material.Water or hit.Normal.Y < 0.75 then
		return nil
	end
	local base = hit.Position
	local info = Peeker.info
	-- Headroom for most of it (the top may brush a beam), nothing solid where it stands.
	if workspace:Raycast(base + Vector3.new(0, 0.5, 0), Vector3.new(0, info.height * 0.8, 0), rayParams) then
		return nil
	end
	local box = Vector3.new(math.max(info.rw, 1.5), math.min(info.height * 0.5, 6), math.max(info.rw, 1.5))
	for _, part in ipairs(workspace:GetPartBoundsInBox(CFrame.new(base + Vector3.new(0, box.Y / 2 + 0.4, 0)), box, overlap)) do
		if part.CanCollide then
			return nil
		end
	end
	if AI.lightAt(base + Vector3.new(0, 2, 0)) > 0 then
		return nil
	end
	return base
end

-- A spot behind `info`: first where only its head shows over cover, then anywhere unseen.
local function spotBehind(info)
	local pos = info.root.Position
	local aim = G.Equipment.aimOf(info.player) or info.root.CFrame.LookVector
	local back = -Vector3.new(aim.X, 0, aim.Z)
	back = back.Magnitude > 0.1 and back.Unit or Vector3.new(0, 0, 1)
	local eyes = eyesOf(info)
	local fallback
	for _ = 1, 18 do
		local a = math.rad(math.random(-75, 75))
		local dir = Vector3.new(back.X * math.cos(a) - back.Z * math.sin(a), 0, back.X * math.sin(a) + back.Z * math.cos(a))
		local dist = P.distance[1] + math.random() * (P.distance[2] - P.distance[1])
		local p = pos + dir * dist
		local base = standAt(p.X, p.Z, pos.Y + 8) or standAt(p.X, p.Z, pos.Y + 25)
		if base and math.abs(base.Y - pos.Y) < 14 then
			local head = headAt(base)
			if not seen(head) and not seen(base + Vector3.new(0, 2, 0)) then
				local headShows = AI.visible(eyes, head, nil, info.character)
				local bodyHidden = not AI.visible(eyes, base + Vector3.new(0, Peeker.info.height * 0.3, 0), nil, info.character)
				if headShows and bodyHidden then
					return base
				end
				if headShows and not fallback then
					fallback = base
				end
			end
		end
	end
	return fallback
end

local function prey()
	for _, info in ipairs(G.Util.alivePlayers()) do
		if info.player == Peeker.target then
			return info
		end
	end
	local alive = G.Util.alivePlayers()
	if #alive == 0 then
		return nil
	end
	local info = alive[math.random(1, #alive)]
	Peeker.target = info.player
	return info
end

local function face(base, toward)
	local info = Peeker.info
	local flat = Vector3.new(toward.X - base.X, 0, toward.Z - base.Z)
	local look = flat.Magnitude > 0.1 and flat.Unit or Vector3.new(0, 0, -1)
	local rootPos = base + Vector3.new(0, info.hip + info.rh / 2, 0)
	Peeker.model:PivotTo(CFrame.lookAt(rootPos, rootPos + look))
	Peeker.look = look
end

local function hide(now)
	if Peeker.model then
		Peeker.model:PivotTo(HIDDEN)
		Peeker.model:SetAttribute("State", "Hidden")
	end
	Peeker.visible = false
	Peeker.base = nil
	Peeker.nextAt = now + P.gap[1] + math.random() * (P.gap[2] - P.gap[1])
end

local function appear(now)
	refreshFilters()
	local info = prey()
	if not info then
		Peeker.nextAt = now + 5
		return
	end
	if not Peeker.model and not build() then
		Peeker.want = false
		return
	end
	local base = spotBehind(info)
	if not base then
		Peeker.nextAt = now + 3
		return
	end
	face(base, info.root.Position)
	Peeker.base = base
	Peeker.visible = true
	Peeker.since = now
	Peeker.stared = 0
	if not Peeker.relocating then
		Peeker.visits += 1
	end
	Peeker.relocating = false
	Peeker.model:SetAttribute("State", "Watch")
	SFX.play("Peeker", Peeker.root, { speed = 0.95 + math.random() * 0.1 })
end

-- The Director decides it comes tonight. Returns false when there is no Peeker model.
function Peeker.summon(force)
	if not kind() then
		return false
	end
	Peeker.want = true
	Peeker.visits = 0
	Peeker.target = nil
	Peeker.nextAt = os.clock() + (force and 1 or math.random(8, 25))
	return true
end

-- 5 Hz from AIService.
function Peeker.step(now, dt)
	if not Peeker.want then
		return
	end
	if Peeker.model and not Peeker.model.Parent then
		Peeker.model, Peeker.visible = nil, false
	end
	if not Peeker.visible then
		if now >= (Peeker.nextAt or 0) and Peeker.visits < P.visits then
			appear(now)
		end
		return
	end
	local info = prey()
	if not info then
		hide(now)
		return
	end
	local base = Peeker.base
	local head = headAt(base)
	local dist = Vector3.new(info.root.Position.X - base.X, 0, info.root.Position.Z - base.Z).Magnitude
	-- It keeps turned towards you.
	local flat = Vector3.new(info.root.Position.X - base.X, 0, info.root.Position.Z - base.Z)
	if flat.Magnitude > 0.1 and Peeker.look and flat.Unit:Dot(Peeker.look) < 0.94 then
		face(base, info.root.Position)
	end
	-- Looked at: it holds your gaze for a moment, then it is not there any more.
	if seen(head) or seen(base + Vector3.new(0, Peeker.info.height * 0.45, 0)) then
		Peeker.stared += dt
		if Peeker.stared > P.stare then
			hide(now)
		end
		return
	end
	if dist < P.approach or AI.focusedBeam(head, 90) or AI.focusedBeam(base + Vector3.new(0, 3, 0), 90) then
		hide(now)
		return
	end
	-- Unnoticed for long, or left far behind: it moves to be behind you again.
	if now - Peeker.since > 22 or dist > P.distance[2] * 1.8 then
		hide(now)
		Peeker.relocating = true
		Peeker.nextAt = now + 2
	end
end

-- Hit with a crowbar: it is simply not there any more.
function Peeker.onHit()
	if Peeker.visible then
		hide(os.clock())
	end
end

function Peeker.leave()
	if Peeker.model then
		Peeker.model:Destroy()
	end
	Peeker.model = nil
	Peeker.visible = false
	Peeker.want = false
	Peeker.target = nil
	Peeker.base = nil
end

return Peeker
