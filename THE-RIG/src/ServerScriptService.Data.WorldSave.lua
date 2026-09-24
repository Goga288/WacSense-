-- ServerScriptService/Data/WorldSave
-- Saves one specific world (run): day, generator, grid, doors, flooding, structures and
-- the crew's inventories. Private servers use their own id; public servers use the
-- world of the first player who joined (the host).
local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")

local WorldSave = { key = nil, loaded = false, canSave = false, data = nil }
local STORE_NAME = "TheRig_Worlds_v1"
local G
local store

function WorldSave.init(g)
	G = g
	-- Local .rbxlx has no persistence endpoint. Use an explicit session-only mode.
	if game.PlaceId == 0 then
		G.State.set("SessionOnly", true)
	else
		local ok, res = pcall(function() return DataStoreService:GetDataStore(STORE_NAME) end)
		if ok then store = res else warn("[WorldSave] DataStore unavailable: " .. tostring(res)) end
	end

	G.Net.on("ResetWorld", function(player)
		if player.UserId ~= G.State.get("HostId") then
			G.Net.toast(player, "Only the world host can reset the world.", "warn")
			return
		end
		WorldSave.reset(player)
	end, 5)
end

function WorldSave.resolveKey(host)
	if game.PrivateServerId ~= "" then
		return "ps_" .. game.PrivateServerId
	end
	return "host_" .. host.UserId
end

function WorldSave.load(host)
	WorldSave.key = WorldSave.resolveKey(host)
	G.State.set("HostId", host.UserId)
	G.State.set("HostName", host.DisplayName)
	if not store then
		WorldSave.canSave = false
		WorldSave.loaded = true
		return nil
	end
	local ok, data = G.PlayerData.retry(function()
		return store:GetAsync(WorldSave.key)
	end, 3)
	WorldSave.loaded = true
	if not ok then
		warn("[WorldSave] Load failed, world will not be saved this session: " .. tostring(data))
		WorldSave.canSave = false
		return nil
	end
	WorldSave.canSave = true
	if type(data) ~= "table" or data.Version ~= 1 then
		return nil
	end
	WorldSave.data = data
	return data
end

function WorldSave.collect()
	return {
		Version = 1,
		SavedAt = os.time(),
		Day = G.DayCycle.day,
		Completed = G.State.get("Completed") == true,
		Power = G.Power.serialize(),
		Doors = G.Doors.serialize(),
		Structures = G.Building.serialize(),
		Inventories = G.Inventory.serializeAll(),
		Boats = G.Boats.serialize(),
		Campaign = G.Campaign.serialize(),
		Industry = G.Industry.serialize(),
	}
end

function WorldSave.apply(data)
	if type(data) ~= "table" then
		return
	end
	local function safe(name, fn, arg)
		local ok, err = pcall(fn, arg)
		if not ok then
			warn("[WorldSave] Could not restore " .. name .. ": " .. tostring(err))
		end
	end
	if type(data.Day) == "number" then
		G.DayCycle.day = math.clamp(math.floor(data.Day), 1, 1000)
	end
	G.State.set("Completed", data.Completed == true)
	safe("power", G.Power.deserialize, data.Power)
	safe("doors", G.Doors.deserialize, data.Doors)
	safe("structures", G.Building.deserialize, data.Structures)
	safe("inventories", G.Inventory.deserializeAll, data.Inventories)
	safe("boats", G.Boats.deserialize, data.Boats)
	safe("campaign", G.Campaign.deserialize, data.Campaign)
	safe("industry", G.Industry.deserialize, data.Industry)
end

function WorldSave.save(reason)
	if not store or not WorldSave.key or not WorldSave.canSave then
		return false
	end
	local ok, snapshot = pcall(WorldSave.collect)
	if not ok then
		warn("[WorldSave] Collect failed: " .. tostring(snapshot))
		return false
	end
	local saved, err = G.PlayerData.retry(function()
		store:UpdateAsync(WorldSave.key, function()
			return snapshot
		end)
	end, 3)
	if not saved then
		warn("[WorldSave] Save failed (" .. tostring(reason) .. "): " .. tostring(err))
		return false
	end
	return true
end

function WorldSave.reset(byPlayer)
	G.Net.banner("WORLD RESET", byPlayer.DisplayName .. " restarted the run. Back to DAY 1.", "danger")
	G.Director.resetRun()
	task.spawn(WorldSave.save, "reset")
end

function WorldSave.bindToClose()
	game:BindToClose(function()
		WorldSave.save("shutdown")
		G.PlayerData.saveAll()
	end)
	Players.PlayerRemoving:Connect(function()
		if #Players:GetPlayers() <= 1 then
			WorldSave.save("empty")
		end
	end)
end

return WorldSave
