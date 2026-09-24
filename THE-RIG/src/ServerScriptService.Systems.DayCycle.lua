-- ServerScriptService/Systems/DayCycle
-- Server clock. The client derives the exact time from Day + CycleStart (server time) so the
-- sky moves smoothly without the server replicating Lighting every frame.
-- 06:00-18:00 day, 18:00-21:00 evening, 21:00-06:00 night. The day number increases at 06:00.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Modules.Config)

local DayCycle = { day = 1, cycleStart = 0, running = false, phase = "Day", listeners = {} }
local G

function DayCycle.init(g)
	G = g
	G.State.set("DaySeconds", Config.DaySeconds)
	G.State.set("Day", DayCycle.day)
	G.State.set("CycleStart", workspace:GetServerTimeNow())
end

function DayCycle.phaseOf(hour)
	if hour >= Config.StartHour and hour < Config.EveningHour then
		return "Day"
	elseif hour >= Config.EveningHour and hour < Config.NightHour then
		return "Evening"
	end
	return "Night"
end

function DayCycle.on(event, fn)
	DayCycle.listeners[event] = DayCycle.listeners[event] or {}
	table.insert(DayCycle.listeners[event], fn)
end

local function fire(event, ...)
	for _, fn in ipairs(DayCycle.listeners[event] or {}) do
		local ok, err = pcall(fn, ...)
		if not ok then
			warn("[DayCycle] " .. event .. " listener failed: " .. tostring(err))
		end
	end
end

function DayCycle.start()
	DayCycle.cycleStart = workspace:GetServerTimeNow()
	DayCycle.running = true
	DayCycle.phase = "Day"
	G.State.set("Day", DayCycle.day)
	G.State.set("CycleStart", DayCycle.cycleStart)
	G.State.set("Phase", "Day")
	fire("Phase", "Day", DayCycle.day)
end

function DayCycle.elapsed()
	return workspace:GetServerTimeNow() - DayCycle.cycleStart
end

function DayCycle.hour()
	return (Config.StartHour + DayCycle.elapsed() / Config.DaySeconds * 24) % 24
end

function DayCycle.isNight()
	return DayCycle.phase == "Night"
end

-- Jumps to a given hour of the current day (Studio test tools / events).
function DayCycle.setHour(hour)
	local offset = (hour - Config.StartHour) % 24
	DayCycle.cycleStart = workspace:GetServerTimeNow() - offset / 24 * Config.DaySeconds
	G.State.set("CycleStart", DayCycle.cycleStart)
end

function DayCycle.setDay(day)
	DayCycle.day = math.max(1, day)
	G.State.set("Day", DayCycle.day)
end

function DayCycle.step()
	if not DayCycle.running then
		return
	end
	local el = DayCycle.elapsed()
	if el >= Config.DaySeconds then
		DayCycle.cycleStart += Config.DaySeconds * math.floor(el / Config.DaySeconds)
		DayCycle.day += 1
		G.State.set("Day", DayCycle.day)
		G.State.set("CycleStart", DayCycle.cycleStart)
		DayCycle.phase = "Day"
		G.State.set("Phase", "Day")
		fire("Dawn", DayCycle.day)
		fire("Phase", "Day", DayCycle.day)
		return
	end
	local phase = DayCycle.phaseOf(DayCycle.hour())
	if phase ~= DayCycle.phase then
		DayCycle.phase = phase
		G.State.set("Phase", phase)
		fire("Phase", phase, DayCycle.day)
	end
end

return DayCycle
