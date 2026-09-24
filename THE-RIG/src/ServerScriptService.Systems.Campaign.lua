-- Shared, saved chapter progression. No client may submit progress or rewards.
-- Chapter kinds: recover (walk up to a terminal), deliver (chapter.cost), hold (chapter.hold:
-- stay near the console with the listed systems powered for N seconds while waves attack).
-- chapter.minDay gates pacing across the 100 days.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Data = require(ReplicatedStorage.Modules.Expeditions)
local Campaign = { completed = 0, upload = 0, transmitting = false, noiseTimer = 0, waveTimer = 0 }
local G
local terminals = {}

local function current()
	return Data.Chapters[Campaign.completed + 1]
end

local function holdOf(chapter)
	return chapter and chapter.hold
end

function Campaign.locked(chapter)
	return chapter ~= nil and chapter.minDay ~= nil and G.DayCycle.day < chapter.minDay
end

function Campaign.publish()
	local chapter = current()
	local hold = holdOf(chapter)
	G.State.set("StoryCompleted", Campaign.completed)
	G.State.set("StoryTitle", chapter and chapter.title or "EVIDENCE DELIVERED")
	local objective = chapter and chapter.objective or "Aldmere has the truth. Survive until the day-100 rescue."
	if Campaign.locked(chapter) then
		objective = string.format("Survive until DAY %d — then: %s", chapter.minDay, chapter.objective)
	end
	G.State.set("StoryObjective", objective)
	G.State.set("StoryLockedUntil", Campaign.locked(chapter) and chapter.minDay or 0)
	G.State.set("StoryPosition", chapter and chapter.position or Vector3.new(0, 33, 218))
	G.State.set("StoryUpload", hold and math.floor(Campaign.upload / hold.seconds * 100) or 0)
	G.State.set("StoryTransmitting", Campaign.transmitting)
	G.State.set("FuelEfficiency", Campaign.fuelMultiplier())
end

function Campaign.fuelMultiplier()
	return Campaign.completed >= 3 and 0.85 or 1
end

-- Chapter 10 cools the nest: Climbers arrive 30 % less often.
function Campaign.threatMultiplier()
	return Campaign.completed >= 10 and 1.3 or 1
end

function Campaign.complete()
	local chapter = current()
	if not chapter then
		return
	end
	Campaign.completed += 1 -- commit before reward delivery; repeated prompt triggers are idempotent
	Campaign.transmitting = false
	Campaign.upload = 0
	Campaign.publish()
	for _, p in ipairs(Players:GetPlayers()) do
		G.PlayerData.addCredits(p, chapter.reward)
		G.PlayerData.unlock(p, "chapter_" .. Campaign.completed)
		G.PlayerData.push(p)
	end
	G.Net.banner(chapter.title, chapter.reveal, "good")
	G.Director.objectiveDirty()
	task.spawn(G.WorldSave.save, "chapter")
end

function Campaign.interact(player, id)
	local terminal = terminals[id]
	if not terminal or not G.Net.alive(player) or not G.Net.near(player, terminal, 12) then
		return
	end
	local chapter = current()
	if not chapter or chapter.target ~= id then
		G.Net.open(player, "Journal")
		return
	end
	if Campaign.locked(chapter) then
		G.Net.toast(player, string.format("Not yet. The trail picks up on DAY %d.", chapter.minDay), "warn")
		return
	end
	local hold = holdOf(chapter)
	if hold then
		if Campaign.transmitting then
			G.Net.open(player, "Journal")
			return
		end
		for _, power in ipairs(hold.powers) do
			if not G.Power.isPowered(power) then
				G.Net.toast(player, string.format("%s needs %s power.", hold.label, table.concat(hold.powers, " + ")), "warn")
				return
			end
		end
		Campaign.transmitting = true
		Campaign.noiseTimer = 0
		Campaign.waveTimer = 20
		G.Director.spawnWave(hold.wave, true)
		G.Net.banner(hold.label .. " ACTIVE", string.format("Stay within %d studs for %d seconds. Keep %s powered. They can hear it.", hold.radius, hold.seconds, table.concat(hold.powers, " + ")), "danger")
		Campaign.publish()
		return
	end
	if chapter.cost then
		local ok, missing = G.Inventory.takeAll(player, chapter.cost)
		if not ok then
			G.Net.toast(player, "Missing: " .. tostring(missing), "warn")
			return
		end
	end
	Campaign.complete()
	G.Net.open(player, "Journal")
end

function Campaign.init(g)
	G = g
	for i, chapter in ipairs(Data.Chapters) do
		if i == 1 then
			continue
		end
		local terminal = workspace.Interactables:FindFirstChild(chapter.target, true)
		if terminal then
			terminals[chapter.target] = terminal
			local action = chapter.hold and ("Start " .. string.lower(chapter.hold.label)) or (chapter.cost and "Install" or "Recover recording")
			local prompt = G.Util.prompt(terminal, action, chapter.title, 1.5, 10)
			prompt.Triggered:Connect(function(p)
				Campaign.interact(p, chapter.target)
			end)
		else
			warn("[Campaign] Missing terminal: " .. chapter.target)
		end
	end
	for _, name in ipairs({ "ExpeditionBoard", "ExpeditionBoardHome" }) do
		local board = workspace.Interactables:FindFirstChild(name, true)
		if board then
			G.Util.prompt(board, "Open expedition chart", "KESTREL-9 / CHART", 0, 10).Triggered:Connect(function(p)
				if G.Net.alive(p) and G.Net.near(p, board, 12) then
					G.Net.open(p, "Journal")
				end
			end)
		end
	end
	G.DayCycle.on("Dawn", function(day)
		local chapter = current()
		if chapter and chapter.minDay == day then
			G.Net.banner("NEW LEAD", chapter.title .. " — " .. chapter.objective, "info")
		end
		Campaign.publish()
	end)
	Campaign.publish()
end

function Campaign.step(dt)
	if Campaign.completed == 0 and G.Power.online and (G.State.get("GenHealth") or 0) >= 60 then
		Campaign.complete()
	end
	if not Campaign.transmitting then
		return
	end
	local chapter = current()
	local hold = holdOf(chapter)
	local console = chapter and terminals[chapter.target]
	if not hold or not console then
		Campaign.transmitting = false
		return
	end
	local crew = false
	for _, info in ipairs(G.Util.alivePlayers()) do
		if (info.root.Position - console.Position).Magnitude <= hold.radius then
			crew = true
			break
		end
	end
	local powered = true
	for _, power in ipairs(hold.powers) do
		powered = powered and G.Power.isPowered(power)
	end
	G.State.set("StoryUploadPaused", not crew or not powered)
	if crew and powered then
		Campaign.upload = math.min(hold.seconds, Campaign.upload + math.clamp(dt, 0, 1))
		Campaign.noiseTimer -= dt
		if Campaign.noiseTimer <= 0 then
			Campaign.noiseTimer = 4
			G.AI.noise(console.Position, 160)
		end
		Campaign.waveTimer -= dt
		if Campaign.waveTimer <= 0 then
			Campaign.waveTimer = 20
			G.Director.spawnWave(2, true)
		end
		if Campaign.upload >= hold.seconds then
			Campaign.complete()
			return
		end
	end
	G.State.set("StoryUpload", math.floor(Campaign.upload / hold.seconds * 100))
end

function Campaign.objective()
	local chapter = current()
	local hold = holdOf(chapter)
	if Campaign.transmitting and hold then
		return string.format("%s %d%% — %s", hold.label, math.floor(Campaign.upload / hold.seconds * 100),
			G.State.get("StoryUploadPaused") and ("restore " .. table.concat(hold.powers, " + ") .. " and stay at the console") or "defend the console")
	end
	if not chapter then
		return nil
	end
	if Campaign.locked(chapter) then
		return nil -- the Director shows survival goals until the lead opens
	end
	return chapter.objective
end

function Campaign.serialize()
	return { completed = Campaign.completed }
end

function Campaign.deserialize(data)
	local n = type(data) == "table" and data.completed or 0
	Campaign.completed = type(n) == "number" and n == n and math.abs(n) < math.huge and math.clamp(math.floor(n), 0, #Data.Chapters) or 0
	Campaign.upload = 0
	Campaign.transmitting = false
	G.State.set("StoryUploadPaused", false)
	Campaign.publish()
end

function Campaign.reset()
	Campaign.deserialize(nil)
end

return Campaign
