-- ReplicatedStorage/Modules/Progression
-- 100-day structure. Difficulty grows through new mechanics, events and creature types,
-- not by inflating creature health.
local Progression = {}

Progression.Phases = {
	{ from = 1, to = 10, id = "RECOVERY", title = "RESTORE THE RIG", goal = "Restore E-01, unlock rooms and stockpile fuel." },
	{ from = 11, to = 20, id = "ASSAULT", title = "FIRST ASSAULTS", goal = "Climbers attack in waves. Fortify doors and light the deck." },
	{ from = 21, to = 30, id = "OCEAN", title = "THE OPEN SEA", goal = "Take the boat out: wrecks, buoys and Rig B-7 hold supplies." },
	{ from = 31, to = 40, id = "DEPTHS", title = "INTO THE DEPTHS", goal = "Craft diving gear and reach Station Marrow on the seabed." },
	{ from = 41, to = 50, id = "FACES", title = "FAMILIAR FACES", goal = "Something walks among the crew. Power the cameras." },
	{ from = 51, to = 60, id = "STORMS", title = "STORM SEASON", goal = "Storms cut power. Keep spare fuel and repair kits." },
	{ from = 61, to = 70, id = "LEVIATHAN", title = "THE LEVIATHAN", goal = "Keep sonar online to get warning before it strikes." },
	{ from = 71, to = 80, id = "ATTRITION", title = "ATTRITION", goal = "Core systems are failing. Repair, repair, repair." },
	{ from = 81, to = 90, id = "REVELATION", title = "REVELATION", goal = "Listen to the radio. Learn what happened to KESTREL-9." },
	{ from = 91, to = 99, id = "PREPARATION", title = "PREPARATION", goal = "Stockpile, fortify, upgrade E-01. The last night is coming." },
	{ from = 100, to = 100, id = "FINAL", title = "DAY 100", goal = "Survive the final night. Rescue arrives at dawn." },
}

function Progression.phase(day)
	for _, p in ipairs(Progression.Phases) do
		if day >= p.from and day <= p.to then
			return p
		end
	end
	return Progression.Phases[#Progression.Phases]
end

local function lerp(a, b, t)
	return a + (b - a) * math.clamp(t, 0, 1)
end

-- Weather weights for a day and phase ("Day", "Evening", "Night").
function Progression.weather(day, phase)
	local w = { Clear = 50, Fog = 20, Rain = 12, HeavyRain = 0, Thunderstorm = 0, Storm = 0 }
	if phase ~= "Day" then
		w.Fog += 20
	end
	if day >= 4 then
		w.HeavyRain = 8
	end
	if day >= 8 then
		w.Thunderstorm = 6
	end
	if day >= 15 then
		w.Storm = 4
	end
	if day >= 51 and day <= 60 then
		w.Clear = 15
		w.Storm = 22
		w.Thunderstorm = 18
		w.HeavyRain = 15
	elseif day >= 61 then
		w.Storm += 6
		w.Thunderstorm += 6
		w.Clear = 30
	end
	if day == 100 and phase == "Night" then
		return { Storm = 1 }
	end
	return w
end

-- How much the creatures understand, by day.
--   0  days 1-5     nothing comes up out of the water at all
--   1  days 6-10    they come, but they are stupid: they walk straight at you,
--                   give up when they lose you, and cannot climb anything
--   2  days 11-30   they search, stalk, break doors and scale low walls
--   3  days 31-50   packs flank and cut you off, feint, dodge, heal in the
--                   dark, and scale anything
--   4  days 51-100  all of that, faster, with sharper senses, and relentless
function Progression.brain(day)
	if day <= 5 then return 0 end
	if day <= 10 then return 1 end
	if day <= 30 then return 2 end
	if day <= 50 then return 3 end
	return 4
end

-- Everything the Director needs for one night.
function Progression.profile(day)
	local t = (day - 1) / 99
	local p = {}
	p.day = day
	p.phase = Progression.phase(day).id
	p.brain = Progression.brain(day)
	local b = p.brain
	-- Climbers. Days 1-5: only the tier creatures from the map come (AI/Roster), a few at a
	-- time; the old creatures stay down until day 6.
	if b == 0 then
		-- Nights 1-3: nothing (Config.FirstMonsterNight); nights 4-5: two, then three.
		p.climberMax = day <= 3 and 0 or (day == 4 and 2 or 3)
	elseif b == 1 then
		p.climberMax = math.min(2 + (day - 6) // 2, 4)
	else
		p.climberMax = math.min(3 + math.floor(day / 3), 16)
	end
	p.climberInterval = b == 0 and 28 or b == 1 and 22 or math.max(7, math.floor(lerp(24, 7, t * 1.8)))
	p.climberWaves = b >= 2 -- burst spawns at 23:00 and 03:00
	p.waveSize = 2 + math.floor(day / 8)
	p.saboteurs = b >= 2 and day >= 16 -- some Climbers hunt powered floodlights
	p.doorBreakers = b >= 2 -- Climbers attack doors that block their path
	p.flankers = b >= 2 and day >= 15 -- Climbers use every edge of the rig, not just the nearest
	p.scouts = b >= 2 -- one may come up early in the evening to probe the rig
	p.hunters = b >= 2 -- sent to players far from the rig or standing still
	-- What comes up the legs. Each band adds a kind; the older ones keep coming.
	p.kinds = { Climber = 1 }
	if b >= 2 then p.kinds.Skitter = 0.45 end
	if b >= 3 then p.kinds.Brute = 0.22 end
	if b >= 4 then p.kinds.Pale = 0.3 end
	-- Other creatures.
	p.watcherChance = b >= 2 and math.min(0.25 + day * 0.01, 0.8) or 0
	p.mimicChance = b >= 2 and day >= 12 and math.min(0.3 + (day - 12) * 0.02, 0.9) or 0
	p.mimicMax = day >= 71 and 2 or 1
	p.lurkers = b >= 2
	p.leviathanChance = day >= 61 and math.min(0.35 + (day - 61) * 0.02, 0.8) or 0
	-- The tall one: seen from day 20, hunting from night 40.
	p.silhouetteChance = day >= 20 and math.min(0.35 + (day - 20) * 0.015, 0.9) or 0
	p.silhouetteHunts = day >= 40
	-- Events
	p.eventChance = math.min(0.07 + day * 0.0025, 0.35) -- per in-game hour
	p.malfunctionBias = day >= 71 and 3 or 1
	p.final = day >= 100
	if p.final then
		p.climberMax = 16
		p.climberInterval = 7
		p.waveSize = 8
		p.watcherChance = 1
		p.mimicChance = 1
		p.mimicMax = 2
		p.leviathanChance = 1
		p.silhouetteChance = 1
	end
	return p
end

return Progression
