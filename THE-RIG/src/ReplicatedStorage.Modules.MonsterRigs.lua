-- ReplicatedStorage/Modules/MonsterRigs
-- The creature models placed in the map, described once for the server (which builds a
-- walking body around each) and the clients (which animate its bones).
--
-- A model's TIER comes from its name, the way the models are named in Workspace:
--   "дефолт 1" / "default 1" / "D1"  -> D1   every night, 2 different kinds a night
--   "дефолт 2" / "D2"                -> D2   often but not every night, 1-2 kinds
--   "дефолт 3" / "D3"                -> D3   rare, 1 kind a night
--   "босс" / "boss"                  -> Boss not spawned yet (bosses come later)
--   "...за коробкой..." / "Peeker"   -> Peeker, the one that watches from behind you
-- or from a "Tier" attribute on the model (D1, D2, D3, Boss, Peeker), which wins.
--
-- Each kind is keyed by the name of its skinned MeshPart. `up` and `forward` are that
-- MeshPart's own axes: where its back and its face point. Models not listed here are
-- assumed to stand upright (+Y) and face -Z, like everything Roblox imports.
local MonsterRigs = {}

local Y, X, NZ = Vector3.new(0, 1, 0), Vector3.new(1, 0, 0), Vector3.new(0, 0, -1)

MonsterRigs.Models = {
	-- дефолт 1: the human-dog. Imported lying on its side: its back is the mesh's +X.
	-- Its imported clips hold raw FBX transforms, so it is animated procedurally.
	Plane = { name = "The Crawler", up = X, forward = NZ, gait = "crawl" },
	-- дефолт 1: the grinning mouse with two tentacles. Its own clips play on its bones.
	cartoon_mouse_cartoonmouse_killer_ref = {
		name = "The Grinner", up = Y, forward = NZ, gait = "biped",
		clips = {
			set = "Grinner",
			Idle = "idle", Walk = "walk", Run = "run", Fall = "fall", Reveal = "reveal",
			Attack = { "attack1", "attack2", "attack3", "attack4" },
		},
	},
	-- дефолт 2: tall and thin, arms hanging from the top of its body.
	Cube = { name = "The Stilt", up = Y, forward = NZ, gait = "biped" },
	-- дефолт 3: the giant. Imported in a T-pose; its arms are lowered when it animates.
	humanBody = { name = "The Colossus", up = Y, forward = NZ, gait = "biped" },
	-- The one that waits behind a crate and watches you.
	Manthing = { name = "The Peeker", up = Y, forward = NZ, gait = "biped" },
}

function MonsterRigs.spec(meshName)
	return MonsterRigs.Models[meshName] or { name = "The Thing", up = Y, forward = NZ, gait = "biped" }
end

local TIERS = { D1 = true, D2 = true, D3 = true, Boss = true, Peeker = true }

-- Tier of a placed model, or nil when it is not a creature model.
function MonsterRigs.tierOf(model)
	local attr = model:GetAttribute("Tier")
	if type(attr) == "string" and TIERS[attr] then
		return attr
	end
	local name = string.lower(model.Name)
	if string.find(name, "за коробкой", 1, true) or string.find(name, "наблюда", 1, true)
		or string.find(name, "peeker", 1, true) or string.find(name, "из-за спины", 1, true) then
		return "Peeker"
	end
	if string.find(name, "босс", 1, true) or string.find(name, "boss", 1, true) then
		return "Boss"
	end
	local n = string.match(name, "дефолт%s*(%d)") or string.match(model.Name, "Дефолт%s*(%d)")
		or string.match(model.Name, "ДЕФОЛТ%s*(%d)") or string.match(name, "default%s*(%d)") or string.match(name, "^d%s*(%d)$")
	if n == "1" or n == "2" or n == "3" then
		return "D" .. n
	end
	-- Named after its mesh? (a template the server has already moved to storage)
	local mesh = MonsterRigs.meshOf(model)
	if mesh and mesh.Name == "Manthing" then
		return "Peeker"
	end
	return nil
end

-- The skinned MeshPart that is the creature's body (the one with the most bones).
function MonsterRigs.meshOf(model)
	local best, bestCount = nil, 0
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("MeshPart") then
			local n = 0
			for _, b in ipairs(d:GetDescendants()) do
				if b:IsA("Bone") then
					n += 1
				end
			end
			if n > bestCount then
				best, bestCount = d, n
			end
		end
	end
	return best, bestCount
end

return MonsterRigs
