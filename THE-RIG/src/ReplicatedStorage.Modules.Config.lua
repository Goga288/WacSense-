-- ReplicatedStorage/Modules/Config
-- Shared tuning values. Safe to read on the client: contains no secrets.
local Config = {}

Config.Version = "0.17.0"
Config.GameName = "THE RIG: 100 DAYS"

-- Time: one in-game day (24 h) lasts DaySeconds real seconds and starts at 06:00.
Config.MaxDays = 100
Config.DaySeconds = 300
Config.StartHour = 6
Config.EveningHour = 18
Config.NightHour = 21
-- Nights 1-3 are calm: no creature of any kind comes before this night.
-- (The DEV panel in Studio can still spawn them for testing.)
Config.FirstMonsterNight = 4

-- World
Config.WaterLevel = 0
Config.DeckHeight = 30
Config.SeabedY = -72
Config.OceanHalfSize = 6144
Config.BoundaryRadius = 5900
Config.RigCenter = Vector3.new(0, 30, 0)
Config.RigMin = Vector3.new(-230, 20, -256)
Config.RigMax = Vector3.new(230, 110, 256)

Config.Player = {
	WalkSpeed = 14,
	SprintSpeed = 22,
	StaminaDrain = 7, -- ~14 s of sprinting
	StaminaRegen = 20,
	SwimSpeed = 17,
	SwimSprintSpeed = 26,
	HungerDecay = 100 / 900,
	ThirstDecay = 100 / 660,
	StarveDamage = 1.5,
	OxygenDrain = 100 / 40,
	OxygenRegen = 45,
	DrownDamage = 10,
	PressureDepth = { None = -28, OxygenTank = -50, DivingGear = -100 },
	PressureDamage = 7,
	InteractRange = 12,
	RespawnTime = 8,
}

Config.Inventory = { Slots = 24, Hotbar = 6 }
Config.StarterKit = {
	{ "Flashlight", 1 },
	{ "Crowbar", 1 },
	{ "Food", 1 },
	{ "Water", 1 },
}

Config.Generator = {
	StartFuel = 30,
	StartHealth = 37,
	MaxHealth = 100,
	FuelPerCan = 25,
	RepairCost = { ScrapMetal = 4, Electronics = 2 },
	BaseBurn = 0.035, -- fuel per second while running
	LoadBurn = 0.16, -- extra fuel per second at 100 % load
	OverloadGrace = 8, -- seconds of overload before the breaker trips
	Levels = {
		{ capacity = 100, tank = 100 },
		{ capacity = 160, tank = 150 },
		{ capacity = 240, tank = 200 },
	},
}

-- Power consumers. Order = display order.
Config.Consumers = {
	{ id = "Lights", name = "LIGHTS", demand = 20, desc = "Floodlights and room lights. Climbers fear bright light." },
	{ id = "Doors", name = "DOORS", demand = 10, desc = "Unlocks powered technical doors." },
	{ id = "Pumps", name = "PUMPS", demand = 15, desc = "Drains the flooded maintenance level. Needs a working bilge pump." },
	{ id = "Sonar", name = "SONAR", demand = 25, desc = "Detects creatures and early-warns big events. Needs the sonar array." },
	{ id = "Cameras", name = "CAMERAS", demand = 15, desc = "Highlights creatures on the rig for the whole crew." },
	{ id = "Defense", name = "DEFENSE", demand = 40, desc = "Powers defense posts and electric fences." },
	{ id = "Lab", name = "LAB", demand = 30, desc = "Pressurises Station Marrow (underwater lab)." },
}

Config.Climber = {
	Health = 120,
	WalkSpeed = 15,
	ChaseSpeed = 21,
	Damage = 18,
	StructureDamage = 26,
	GeneratorDamage = 10,
	LampDamage = 32,
	AttackRange = 5.5,
	StructureRange = 7.5,
	AttackCooldown = 1.05,
	SightRange = 105,
	HearRange = 42,
	ActivationRange = 320,
	LightDamage = 6,
	FlashlightRange = 24,
	ClimbTime = 5,
}

Config.Mimic = { Health = 230, WalkSpeed = 13, HuntSpeed = 24, Damage = 27, RevealMin = 40, RevealMax = 85 }
Config.Watcher = { MinDistance = 430, MaxDistance = 620, StayMin = 70, StayMax = 130, AttentionLimit = 25 }
Config.Leviathan = { WarningTime = 15, StrikeDamage = 35, BoatDamage = 70 }
-- THE LURKER: night hunter of the open water. Circles swimmers and boats, then lunges.
Config.Lurker = { Health = 140, CircleSpeed = 24, LungeSpeed = 48, Damage = 22, BoatDamage = 14, SenseRange = 260, MaxBase = 1 }

-- 0.15: THE NIGHT ROSTER. The creature models placed in the map (see Modules/MonsterRigs)
-- are what comes up out of the sea at night, in three tiers. Every night the roster is
-- rolled: which kinds of each tier come tonight. Tier numbers are a base; each creature's
-- size adds reach, and the night adds speed and senses.
--   kinds   {min, max} different kinds of this tier in one night
--   chance  chance the tier comes at all tonight (+ grow per night, up to maxChance)
--   weight  how often a spawn picks this tier over the others
--   alive   most of this tier on the map at once (+1 every aliveGrowth nights)
--   minds   intelligence by night: {from night, level}. 1 = stupid (walks straight at
--           you, forgets you), 2 = searches / stalks / breaks doors, 3 = packs, flanks,
--           feints, dodges, heals in the dark, 4 = all of it, faster and sharper.
Config.Tiers = {
	D1 = { -- дефолт 1: каждую ночь, 2 разных вида
		kinds = { 2, 2 }, chance = 1, weight = 1,
		minds = { { 1, 1 }, { 15, 2 }, { 40, 3 }, { 70, 4 } },
		Health = 90, WalkSpeed = 13, ChaseSpeed = 19, Damage = 14, AttackCooldown = 1.15,
		StructureDamage = 20, LightDamage = 6,
	},
	D2 = { -- дефолт 2: довольно часто, но не всегда; 1-2 вида (рандом)
		kinds = { 1, 2 }, chance = 0.6, grow = 0.004, maxChance = 0.85, weight = 0.55,
		alive = 2, aliveGrowth = 25,
		minds = { { 1, 2 }, { 20, 3 }, { 50, 4 } },
		Health = 170, WalkSpeed = 14, ChaseSpeed = 21, Damage = 21, AttackCooldown = 1,
		StructureDamage = 32, LightDamage = 4,
	},
	D3 = { -- дефолт 3: редко, 1 вид за ночь
		kinds = { 1, 1 }, chance = 0.12, grow = 0.002, maxChance = 0.3, weight = 0.3,
		alive = 1, aliveGrowth = 40,
		minds = { { 1, 3 }, { 12, 4 } },
		Health = 320, WalkSpeed = 15, ChaseSpeed = 23, Damage = 32, AttackCooldown = 1.1,
		StructureDamage = 60, LightDamage = 2.5, voice = "Apex", quiet = true,
	},
	Boss = { spawn = false }, -- боссы: добавятся позже
	-- true: the old procedural Climbers / Skitters / Brutes / Pales keep coming as well.
	KeepOldCreatures = false,
	-- Size of every spawned creature relative to how it was placed in the map.
	Scale = 1,
}

-- The Peeker: waits behind a crate or a corner somewhere behind you and watches. Turn
-- round and look at it and it is gone. For now it only watches.
Config.Peeker = {
	chance = 0.42, -- chance it comes on a given night (from Config.FirstMonsterNight)
	evening = 0.15, -- chance it already comes in the evening
	distance = { 18, 55 }, -- how far behind you it waits
	stare = 0.6, -- seconds you can look at it before it is gone
	visits = 4, -- appearances per night
	gap = { 40, 75 }, -- seconds between appearances
	approach = 14, -- walk closer than this and it is gone
}

Config.Build = {
	Range = 30,
	MaxTotal = 180,
	MaxPerPlayer = 45,
	-- Axis-aligned boxes {min, max} where building is allowed.
	Zones = {
		{ Vector3.new(-226,28,-250), Vector3.new(-106,100,-130) }, -- south-west quarters
		{ Vector3.new(-226,28,-90), Vector3.new(-106,80,54) },
		{ Vector3.new(106,28,-90), Vector3.new(226,80,54) },
		{ Vector3.new(-88,28,132), Vector3.new(88,100,252) },
		{ Vector3.new(-81, 28, -61), Vector3.new(81, 80, 61) }, -- main deck
		{ Vector3.new(-6, 0, -82), Vector3.new(32, 20, -62) }, -- boat dock
		{ Vector3.new(39, 44, -59), Vector3.new(79, 70, -21) }, -- helipad
	},
}

Config.Boat = {
	FuelMax = 100,
	StartFuel = 85,
	FuelPerCan = 30,
	MaxSpeed = 46,
	ReverseSpeed = 14,
	TurnRate = 1.1,
	CargoSlots = 18,
	Health = 100,
}

-- Sound ids. Leave "" to disable. Built-in rbxasset sounds always exist.
Config.Sounds = {
	Splash = "rbxasset://sounds/impact_water.mp3",
	-- Any SFX recipe name (see Modules/SFX) can be replaced by a real "rbxassetid://..." here.
	Ping = "",
	Thunder = "",
	Growl = "",
	Shriek = "",
	ScreamA = "",
	-- 0.15: the game's own recordings. Upload each file to Roblox (Creator Hub -> Development
	-- Items -> Audio, or in Studio: Asset Manager -> Import), copy its id and paste it here,
	-- e.g. PlayerScream = 1234567890. Left empty, a built-in stand-in plays instead.
	-- 0.17: EASIER — ReplicatedStorage/GameSounds has a ready Sound for every slot below:
	-- select it in Studio and set its SoundId in Properties (it wins over the ids here).
	PlayerScream = "", -- крик игрока по кнопке X
	Corridors = "", -- звук для помещения коридорчиков (loops while you are inside corridors / tunnels)
	Distant = "", -- звук для фона, иногда кричит издалека (at night, far away)
	Jumpscare = "", -- звук скримера (the screamer)
	Peeker = "", -- звук монстра, который пока что просто смотрит из-за спины
	Apex = "", -- звук для самого сильного монстра в игре (for now: every D3 creature)
	-- Ballerina: removed for now (звук балерины пока убран) - nothing plays it.
}
-- Volume of each uploaded file (0-10). Tune by ear.
Config.SoundVolume = {
	PlayerScream = 1.3,
	Corridors = 0.5,
	Distant = 0.9,
	Jumpscare = 1.8,
	Peeker = 1.1,
	Apex = 1.8,
}

-- Donations. Each tier is a Developer Product: Creator Dashboard -> your experience ->
-- Monetization -> Developer Products -> Create. Put its id here. A tier left at 0 is not
-- offered; with none set, the SUPPORT button only shows in Studio, to remind you.
Config.Donate = {
	{ id = 0, robux = 25, label = "A HOT MEAL FOR THE CREW" },
	{ id = 0, robux = 100, label = "A CAN OF FUEL FOR E-01" },
	{ id = 0, robux = 500, label = "A RESCUE BOAT" },
}

-- In Studio a DEV panel appears (skip to night, spawn creatures...). Never active on live servers.
Config.StudioTools = true

return Config
