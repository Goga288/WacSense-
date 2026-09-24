-- ServerScriptService/Systems/Environment
-- Weather state machine: Clear, Fog, Rain, HeavyRain, Thunderstorm, Storm.
-- The server owns the state, waves and lightning strikes; clients render rain, fog and flashes.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Modules.Config)
local Progression = require(ReplicatedStorage.Modules.Progression)

local Environment = { weather = "Clear", forced = nil, nextStrike = math.huge }
local G

local WEATHER = {
	Clear = { waves = 0.25, speed = 8, wind = 0.1 },
	Fog = { waves = 0.2, speed = 6, wind = 0.05 },
	Rain = { waves = 0.45, speed = 12, wind = 0.3 },
	HeavyRain = { waves = 0.7, speed = 15, wind = 0.5 },
	Thunderstorm = { waves = 0.9, speed = 18, wind = 0.7, strike = { 10, 22 } },
	Storm = { waves = 1.5, speed = 24, wind = 1, strike = { 5, 12 }, surges = true },
}
Environment.Types = WEATHER

-- Tall conductive points lightning likes to hit (derrick, tower, crane).
local rods = {}

function Environment.init(g)
	G = g
	for _, name in ipairs({ "DerrickTop", "TowerTop", "CraneTop" }) do
		local p = workspace:FindFirstChild(name, true)
		if p and p:IsA("BasePart") then
			table.insert(rods, p.Position)
		end
	end
	G.DayCycle.on("Phase", function(phase, day)
		if Environment.forced and phase ~= "Day" then
			Environment.set(Environment.forced)
			Environment.forced = nil
			return
		end
		local weights = Progression.weather(day, phase)
		Environment.set(G.Util.weighted(weights) or "Clear")
	end)
	Environment.set("Clear")
end

function Environment.set(name)
	local w = WEATHER[name]
	if not w then
		return
	end
	Environment.weather = name
	G.State.set("Weather", name)
	G.State.set("Wind", w.wind)
	local terrain = workspace.Terrain
	terrain.WaterWaveSize = w.waves
	terrain.WaterWaveSpeed = w.speed
	if w.strike then
		Environment.nextStrike = os.clock() + math.random(w.strike[1], w.strike[2])
	else
		Environment.nextStrike = math.huge
	end
end

-- Forces the next evening / night to be stormy (STORM APPROACHING event).
function Environment.forceNext(name)
	Environment.forced = name
end

function Environment.strike()
	local w = WEATHER[Environment.weather]
	local pos
	local nearRig = math.random() < (w.surges and 0.35 or 0.15)
	if nearRig and #rods > 0 then
		pos = rods[math.random(1, #rods)]
	else
		local a = math.random() * math.pi * 2
		local r = math.random(120, 520)
		pos = Vector3.new(math.cos(a) * r, Config.WaterLevel, math.sin(a) * r)
	end
	G.Net.effectAll("Lightning", pos)
	if nearRig then
		-- Players standing next to the struck structure get hurt.
		for _, info in ipairs(G.Util.alivePlayers()) do
			if (info.root.Position - pos).Magnitude < 14 then
				G.Survival.damage(info.humanoid, 30, "Struck by lightning")
			end
		end
		if w.surges and math.random() < 0.6 then
			G.Power.trip(6 + math.random() * 6, "POWER SURGE", "Lightning hit the rig. Grid offline for a few seconds.")
		end
	end
end

function Environment.step()
	if os.clock() >= Environment.nextStrike then
		local w = WEATHER[Environment.weather]
		if w and w.strike then
			Environment.nextStrike = os.clock() + math.random(w.strike[1], w.strike[2])
			Environment.strike()
		else
			Environment.nextStrike = math.huge
		end
	end
end

-- Temporary wave boost used by the Leviathan.
function Environment.surge(size, seconds)
	local terrain = workspace.Terrain
	terrain.WaterWaveSize = size
	task.delay(seconds, function()
		local w = WEATHER[Environment.weather]
		terrain.WaterWaveSize = w and w.waves or 0.3
	end)
end

return Environment
