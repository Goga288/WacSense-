-- ReplicatedStorage/Modules/SFX
-- Horror sound design built only from the audio files that ship with every Roblox client
-- (rbxasset://sounds/...). They always load, even in a Studio session that is not signed in.
-- Slowed down, pitch-shifted, distorted and drenched in reverb they become growls, shrieks,
-- skittering claws and a heartbeat. Any recipe can be swapped for a real asset id through
-- Config.Sounds (same key) once the game is published.
-- 0.15: slots for the game's own recordings (PlayerScream, Corridors, Distant, Jumpscare,
-- Peeker, Apex). An id may be written as a number, "123" or "rbxassetid://123"; until one
-- is set, the stand-in recipe below plays so every hook can be heard in Studio.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local Debris = game:GetService("Debris")

local SFX = {}
local S = "rbxasset://sounds/"
local OOF, OUCH = S .. "oof.ogg", S .. "ouch.ogg"
local STEPS, SWIM, FALL = S .. "action_footsteps_plastic.mp3", S .. "action_swim.mp3", S .. "action_falling.ogg"
local BOOM, SPLASH, LAND = S .. "impact_explosion_03.mp3", S .. "impact_water.mp3", S .. "action_jump_land.mp3"
local CLICK = S .. "volume_slider.ogg"

-- fx: Distortion (level), Pitch (octave), Reverb (true | wet dB), Echo (delay s), Tremolo (Hz), Low (true = muffled)
SFX.Recipes = {
	Growl = { id = OOF, speed = 0.27, volume = 1.6, range = 110, fx = { Distortion = 0.62, Pitch = 0.85, Reverb = -4 } },
	GrowlLow = { id = OUCH, speed = 0.3, volume = 1.5, range = 110, fx = { Distortion = 0.7, Pitch = 0.75, Reverb = -4 } },
	Shriek = { id = OUCH, speed = 0.72, volume = 2.2, range = 190, fx = { Distortion = 0.86, Pitch = 1.3, Echo = 0.16, Reverb = -2 } },
	Snarl = { id = OOF, speed = 0.55, volume = 1.8, range = 70, fx = { Distortion = 0.9, Pitch = 0.9 } },
	Skitter = { id = STEPS, speed = 2.2, volume = 1.2, range = 70, loop = true, fx = { Distortion = 0.45, Tremolo = 14 } },
	Breath = { id = SWIM, speed = 0.42, volume = 1.1, range = 40, loop = true, fx = { Low = true, Reverb = -6, Tremolo = 1.6 } },
	Emerge = { id = SPLASH, speed = 0.55, volume = 1.8, range = 150, fx = { Reverb = -6 } },
	Slam = { id = BOOM, speed = 1.1, volume = 0.9, range = 120, fx = { Distortion = 0.3 } },
	Horn = { id = BOOM, speed = 0.16, volume = 3, range = 3000, fx = { Reverb = 0, Echo = 0.45, Low = true } },
	-- 2D (no parent part): played on the listener
	Stinger = { id = BOOM, speed = 0.42, volume = 1.3, fx = { Distortion = 0.55, Reverb = -2, Echo = 0.22 } },
	Heartbeat = { id = LAND, speed = 0.5, volume = 1.2, fx = { Low = true, Distortion = 0.2 } },
	ScreamA = { id = OUCH, speed = 0.64, volume = 3.2, fx = { Distortion = 0.95, Pitch = 1.35, Echo = 0.07 } },
	ScreamB = { id = OOF, speed = 0.42, volume = 3.2, fx = { Distortion = 0.9, Pitch = 0.7 } },
	ScreamC = { id = FALL, speed = 1.7, volume = 2.2, fx = { Distortion = 0.8, Pitch = 1.6 } },
	Wind = { id = FALL, speed = 0.22, volume = 0.32, loop = true, fx = { Low = true, Reverb = -8 } },
	Distant = { id = OUCH, speed = 0.36, volume = 0.9, range = 400, fx = { Distortion = 0.7, Reverb = 0, Echo = 0.35, Low = true } },
	Thunder = { id = BOOM, speed = 0.35, volume = 1.4, fx = { Reverb = -2, Low = true } },
	Ping = { id = CLICK, speed = 1.4, volume = 0.5 },
	Pickup = { id = CLICK, speed = 0.9, volume = 0.6 },
	-- 0.15 slots (stand-ins until Config.Sounds has the real file).
	PlayerScream = { id = OUCH, speed = 0.82, volume = 2.2, range = 160, fx = { Distortion = 0.4, Reverb = -5 } },
	Corridors = { id = FALL, speed = 0.16, volume = 0.3, loop = true, fx = { Low = true, Reverb = -3, Tremolo = 0.4 } },
	Jumpscare = { id = OUCH, speed = 0.64, volume = 3.2, fx = { Distortion = 0.95, Pitch = 1.35, Echo = 0.07 } },
	Peeker = { id = SWIM, speed = 0.28, volume = 1.3, range = 70, fx = { Low = true, Reverb = -2, Tremolo = 3 } },
	Apex = { id = OOF, speed = 0.19, volume = 2.6, range = 280, fx = { Distortion = 0.8, Pitch = 0.6, Reverb = -1, Echo = 0.25 } },
}

local function addFx(sound, fx)
	if not fx then
		return
	end
	local order = 0
	local function add(class, props)
		local e = Instance.new(class)
		for k, v in pairs(props) do
			e[k] = v
		end
		order += 1
		e.Priority = 10 - order
		e.Parent = sound
	end
	if fx.Pitch then
		add("PitchShiftSoundEffect", { Octave = fx.Pitch })
	end
	if fx.Distortion then
		add("DistortionSoundEffect", { Level = fx.Distortion })
	end
	if fx.Low then
		add("EqualizerSoundEffect", { HighGain = -30, MidGain = -6, LowGain = 6 })
	end
	if fx.Tremolo then
		add("TremoloSoundEffect", { Depth = 0.7, Duty = 0.5, Frequency = fx.Tremolo })
	end
	if fx.Echo then
		add("EchoSoundEffect", { Delay = fx.Echo, Feedback = 0.45, DryLevel = 0, WetLevel = -4 })
	end
	if fx.Reverb then
		add("ReverbSoundEffect", { DecayTime = 3.5, Density = 1, Diffusion = 1, DryLevel = 0, WetLevel = type(fx.Reverb) == "number" and fx.Reverb or -3 })
	end
end

local function config()
	local ok, Config = pcall(function()
		return require(ReplicatedStorage.Modules.Config)
	end)
	return ok and Config or nil
end

-- A real asset id from Config.Sounds, normalised to "rbxassetid://N", or nil.
local function override(name)
	local Config = config()
	local id = Config and Config.Sounds and Config.Sounds[name]
	if type(id) == "number" and id > 0 then
		return "rbxassetid://" .. string.format("%d", id)
	end
	if type(id) ~= "string" or id == "" then
		return nil
	end
	local digits = string.match(id, "^%s*(%d+)%s*$") or string.match(id, "^rbxassetid://(%d+)$")
	if digits then
		return "rbxassetid://" .. digits
	end
	return nil
end

-- True once the game's own file is configured for this slot.
function SFX.custom(name)
	return override(name) ~= nil
end

-- Creates (does not play) a configured Sound. parent nil = 2D sound in SoundService.
function SFX.make(name, parent)
	local r = SFX.Recipes[name]
	if not r then
		return nil
	end
	local s = Instance.new("Sound")
	s.Name = "SFX_" .. name
	local custom = override(name)
	s.SoundId = custom or r.id
	s.PlaybackSpeed = custom and 1 or (r.speed or 1)
	s.Volume = r.volume or 0.8
	if custom then
		local Config = config()
		local v = Config and Config.SoundVolume and Config.SoundVolume[name]
		s.Volume = type(v) == "number" and v or math.min(s.Volume, 1.5)
	end
	s.Looped = r.loop == true
	if parent then
		s.RollOffMode = Enum.RollOffMode.InverseTapered
		s.RollOffMinDistance = 8
		s.RollOffMaxDistance = r.range or 120
	end
	if not custom then
		addFx(s, r.fx)
	end
	s.Parent = parent or SoundService
	return s
end

-- Fire and forget. opts: {volume = multiplier, speed = multiplier}
function SFX.play(name, parent, opts)
	local s = SFX.make(name, parent)
	if not s then
		return nil
	end
	if opts then
		s.Volume *= opts.volume or 1
		s.PlaybackSpeed *= opts.speed or 1
	end
	s:Play()
	if not s.Looped then
		-- Uploaded Apex recording is longer than twelve seconds.
        s.Ended:Once(function() if s.Parent then s:Destroy() end end)
        Debris:AddItem(s, 180)
	end
	return s
end

return SFX
