-- ServerScriptService/Data/PlayerData
-- Personal progress that follows a player between worlds: credits, achievements,
-- unlocked items / logs, cosmetics, technologies, settings, lifetime stats.
-- Every DataStore call is wrapped in pcall with retries. If loading fails the profile is
-- marked read-only for the session so a bad load can never overwrite real data.
local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")

local PlayerData = { profiles = {} }
local STORE_NAME = "TheRig_PlayerData_v1"
local AUTOSAVE = 150
local G
local store

local ACHIEVEMENTS = {
	FIRST_NIGHT = { title = "First Night", credits = 25 },
	DAY_10 = { title = "Ten Days Adrift", credits = 50 },
	DAY_25 = { title = "Old Hand", credits = 100 },
	DAY_50 = { title = "Halfway There", credits = 200 },
	DAY_100 = { title = "Rescued", credits = 500 },
	ENGINEER = { title = "Engineer (10 repairs)", credits = 40 },
	BUILDER = { title = "Builder (10 structures)", credits = 40 },
	DIVER = { title = "Deep Diver (reach Station Marrow)", credits = 60 },
	HUNTER = { title = "Crowbar Diplomacy (10 creature kills)", credits = 40 },
	UNMASKED = { title = "Unmasked (kill a Mimic)", credits = 80 },
}
PlayerData.Achievements = ACHIEVEMENTS

local COSMETICS = {
	Suit_Standard = { name = "Standard Coverall", color = Color3.fromRGB(214, 120, 40) },
	Suit_Hazard = { name = "Hazard Yellow", color = Color3.fromRGB(220, 190, 40), unlock = "DAY_10" },
	Suit_Night = { name = "Night Shift", color = Color3.fromRGB(40, 50, 70), unlock = "FIRST_NIGHT" },
	Suit_Deep = { name = "Deep Teal", color = Color3.fromRGB(30, 130, 130), unlock = "DIVER" },
	Suit_Rescue = { name = "Rescue Red", color = Color3.fromRGB(190, 40, 40), unlock = "DAY_100" },
}
PlayerData.Cosmetics = COSMETICS

local function defaultProfile()
	return {
		Version = 1,
		Credits = 0,
		Achievements = {},
		Unlocks = {},
		Cosmetics = { Suit_Standard = true },
		Suit = "Suit_Standard",
		Tech = {},
		Settings = {},
		Stats = { Nights = 0, BestDay = 0, Deaths = 0, Repairs = 0, Builds = 0, Kills = 0 },
	}
end

local function reconcile(data)
	local def = defaultProfile()
	if type(data) ~= "table" then
		return def
	end
	for k, v in pairs(def) do
		if type(data[k]) ~= type(v) then
			data[k] = v
		end
	end
	for k, v in pairs(def.Stats) do
		if type(data.Stats[k]) ~= "number" then
			data.Stats[k] = v
		end
	end
	return data
end

local function isFatal(err)
	local s = tostring(err)
	return string.find(s, "StudioAccessToApisNotAllowed", 1, true) ~= nil
		or string.find(s, "403", 1, true) ~= nil
		or string.find(s, "publish", 1, true) ~= nil
end

local function retry(fn, attempts)
	local lastErr
	for i = 1, attempts do
		local ok, result = pcall(fn)
		if ok then
			return true, result
		end
		lastErr = result
		if isFatal(result) then
			break
		end
		task.wait(math.min(2 ^ i, 8))
	end
	return false, lastErr
end
PlayerData.retry = retry

function PlayerData.init(g)
	G = g
	-- Local .rbxlx has no persistence endpoint. Use an explicit session-only mode.
	if game.PlaceId == 0 then
		G.State.set("SessionOnly", true)
	else
		local ok, res = pcall(function() return DataStoreService:GetDataStore(STORE_NAME) end)
		if ok then store = res else warn("[PlayerData] DataStore unavailable: " .. tostring(res)) end
	end

	G.Net.on("Suit", function(player, suitId)
		local profile = PlayerData.profiles[player]
		if not profile or type(suitId) ~= "string" or not COSMETICS[suitId] then
			return
		end
		if not profile.Cosmetics[suitId] then
			G.Net.toast(player, "That suit is locked.", "warn")
			return
		end
		profile.Suit = suitId
		PlayerData.applySuit(player)
		PlayerData.push(player)
	end, 0.5)

	G.Net.on("Settings", function(player, settings)
		local profile = PlayerData.profiles[player]
		if not profile or type(settings) ~= "table" then
			return
		end
		local clean = {}
		for _, key in ipairs({ "Rain", "DepthOfField", "Bloom", "Shadows", "Music", "ScreenFilter" }) do
			if type(settings[key]) == "boolean" then
				clean[key] = settings[key]
			end
		end
		if type(settings.UIScale) == "number" and settings.UIScale >= 0.7 and settings.UIScale <= 1.3 then
			clean.UIScale = settings.UIScale
		end
		profile.Settings = clean
	end, 1)

	Players.PlayerRemoving:Connect(function(player)
		PlayerData.save(player)
		PlayerData.profiles[player] = nil
	end)

	task.spawn(function()
		while true do
			task.wait(AUTOSAVE)
			for _, p in ipairs(Players:GetPlayers()) do
				task.spawn(PlayerData.save, p)
			end
		end
	end)
end

function PlayerData.load(player)
	local profile
	if store then
		local ok, data = retry(function()
			return store:GetAsync("p_" .. player.UserId)
		end, 3)
		if ok then
			profile = reconcile(data)
			profile._canSave = true
		else
			warn(string.format("[PlayerData] Load failed for %s: %s", player.Name, tostring(data)))
			profile = reconcile(nil)
			profile._canSave = false
			G.Net.toast(player, "Profile service unavailable: personal progress will not be saved this session.", "warn")
		end
	else
		profile = reconcile(nil)
		profile._canSave = false
	end
	if not player.Parent then
		return nil
	end
	PlayerData.profiles[player] = profile
	PlayerData.refreshCosmetics(player)
	PlayerData.push(player)
	return profile
end

function PlayerData.save(player)
	local profile = PlayerData.profiles[player]
	if not profile or not profile._canSave or not store then
		return
	end
	local snapshot = {}
	for k, v in pairs(profile) do
		if string.sub(k, 1, 1) ~= "_" then
			snapshot[k] = v
		end
	end
	local ok, err = retry(function()
		store:UpdateAsync("p_" .. player.UserId, function()
			return snapshot
		end)
	end, 3)
	if not ok then
		warn(string.format("[PlayerData] Save failed for %s: %s", player.Name, tostring(err)))
	end
end

function PlayerData.saveAll()
	local pending = 0
	for _, p in ipairs(Players:GetPlayers()) do
		pending += 1
		task.spawn(function()
			PlayerData.save(p)
			pending -= 1
		end)
	end
	local t = os.clock()
	while pending > 0 and os.clock() - t < 20 do
		task.wait(0.2)
	end
end

-- Sends the client-visible part of the profile.
function PlayerData.push(player)
	local profile = PlayerData.profiles[player]
	if not profile then
		return
	end
	player:SetAttribute("Credits", profile.Credits)
	G.Net.Sync:FireClient(player, "Profile", {
		Credits = profile.Credits,
		Achievements = profile.Achievements,
		Cosmetics = profile.Cosmetics,
		Suit = profile.Suit,
		Tech = profile.Tech,
		Settings = profile.Settings,
		Stats = profile.Stats,
		Unlocks = profile.Unlocks,
		CanSave = profile._canSave == true,
	})
end

function PlayerData.get(player)
	return PlayerData.profiles[player]
end

function PlayerData.addCredits(player, n)
	local profile = PlayerData.profiles[player]
	if not profile then
		return
	end
	profile.Credits = math.max(0, profile.Credits + n)
	player:SetAttribute("Credits", profile.Credits)
end

function PlayerData.stat(player, key, delta)
	local profile = PlayerData.profiles[player]
	if not profile then
		return 0
	end
	profile.Stats[key] = (profile.Stats[key] or 0) + delta
	local v = profile.Stats[key]
	if key == "Repairs" and v >= 10 then
		PlayerData.award(player, "ENGINEER")
	elseif key == "Builds" and v >= 10 then
		PlayerData.award(player, "BUILDER")
	elseif key == "Kills" and v >= 10 then
		PlayerData.award(player, "HUNTER")
	end
	return v
end

function PlayerData.setBest(player, key, value)
	local profile = PlayerData.profiles[player]
	if profile and value > (profile.Stats[key] or 0) then
		profile.Stats[key] = value
	end
end

function PlayerData.award(player, id)
	local profile = PlayerData.profiles[player]
	local a = ACHIEVEMENTS[id]
	if not profile or not a or profile.Achievements[id] then
		return
	end
	profile.Achievements[id] = os.time()
	PlayerData.addCredits(player, a.credits)
	PlayerData.refreshCosmetics(player)
	G.Net.bannerTo(player, "ACHIEVEMENT", a.title .. "  +" .. a.credits .. " CR", "good")
	PlayerData.push(player)
end

function PlayerData.unlock(player, key)
	local profile = PlayerData.profiles[player]
	if not profile or profile.Unlocks[key] then
		return false
	end
	profile.Unlocks[key] = true
	return true
end

function PlayerData.hasTech(player, tech)
	local profile = PlayerData.profiles[player]
	return profile ~= nil and profile.Tech[tech] == true
end

function PlayerData.unlockTech(player, tech)
	local profile = PlayerData.profiles[player]
	if not profile or profile.Tech[tech] then
		return
	end
	profile.Tech[tech] = true
	PlayerData.push(player)
end

function PlayerData.refreshCosmetics(player)
	local profile = PlayerData.profiles[player]
	if not profile then
		return
	end
	for id, c in pairs(COSMETICS) do
		if not c.unlock or profile.Achievements[c.unlock] then
			profile.Cosmetics[id] = true
		end
	end
end

-- Suit colour is applied to the torso / legs through BodyColors on the character.
function PlayerData.applySuit(player)
	local profile = PlayerData.profiles[player]
	local character = player.Character
	if not profile or not character then
		return
	end
	local suit = COSMETICS[profile.Suit] or COSMETICS.Suit_Standard
	if character:FindFirstChild("CrewBadge") then
		for _, part in ipairs(character:GetChildren()) do
			if part:IsA("BasePart") and (part.Name == "Torso" or string.find(part.Name, " Arm") or string.find(part.Name, " Leg")) then part.Color = suit.color end
		end
		return
	end
	-- Real avatars keep the player's own colours and clothing: suits only tint the crew rig.
end

return PlayerData
