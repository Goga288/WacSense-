-- ReplicatedStorage/Modules/Story
-- Original lore for KESTREL-9. Logs are found on the map (parts named Log_<id>);
-- radio transmissions play at dawn on specific days.
local Story = {}

Story.Logs = {
	Log_Grave = {
		title = "GRAVE ISLAND — STATION JOURNAL, 1961",
		text = "The whales beach themselves here every autumn, always on the south shore, always at night, always facing the rig site. We never found what drove them. The old men say the sea has a mouth out there.",
	},
	Log_Radar = {
		title = "RADAR ISLAND — CONTACT SHEET",
		text = "Contact 'CHURCH': 90 m long, surfaces every 11 days near KESTREL-9, moves at 30 knots with no propeller signature. Company liaison ordered the tapes erased. I kept one copy.",
	},
	Log_Isles = {
		title = "NORTH ISLES — KEEPER'S LEDGER",
		text = "Lamp lit every night for forty years. The night I let it go out, the gulls vanished and something tall stood in the surf until dawn. I have not missed a night since. Keep your lights on.",
	},
	Log_K8 = {
		title = "KESTREL-8 — DECOMMISSION ORDER",
		text = "KESTREL-8 drilled the first test well into the Throat. Crew relocated to KESTREL-9 'to continue the program'. This platform is to be abandoned in place. Do not return. Do not record.",
	},
	Log_Mess = {
		title = "CREW MESS — WHITEBOARD",
		text = "ROTA WEEK 41: Voss — generator. Okafor — pumps. Lind — kitchen (NO MORE FISH AFTER DARK, something took the whole line and the rod). Tomas — ??? Tomas — ??? Tomas — see Security.",
	},
	Log_Security = {
		title = "SECURITY OFFICE — INCIDENT 0077",
		text = "Two Tomas Lindqvists on camera 4 at 02:11. Both walked to the mess. Only one came back. Halvard's order: do not report, do not detain, keep recording. The company wants to know how well it learns.",
	},
	Log_WellControl = {
		title = "WELL CONTROL — HANDOVER NOTE",
		text = "Heat exchanger valve HX-3 must stay OPEN per head office. Temperature at the drill string is 61C. Why does an oil well need to be kept warm? — M.V.",
	},
	Log_Refinery = {
		title = "DROWNED REFINERY — SHIFT BOARD",
		text = "Evacuated day 12. The sea came up under the east deck without a wave. Something the size of the deck pushed it. The tanks are still half full. Take what you need, whoever you are.",
	},
	Log_Graveyard = {
		title = "SHIP GRAVEYARD — SALVAGE TAG",
		text = "Four hulls, one shoal, one pattern: every ship here turned off its lights on the same night. The one that didn't is the one still floating.",
	},
	Log_Barge = {
		title = "COMMAND BARGE — HALVARD'S DESK",
		text = "Specimen yield projections: 400 viable juveniles per season if the nest stays warm. Crew attrition: acceptable. Rescue: to be delayed until the Adult is tagged.",
	},
	Log_Throat = {
		title = "THE THROAT — MARA'S SLATE (waterproof)",
		text = "If you are reading this down here you are braver than me. The eggs pulse when the rig's generator runs. They are listening to it. Keep it running anyway. Light is the only thing the young ones fear.",
	},
	Log_Quarters = {
		title = "BUNK 4 — PERSONAL NOTE",
		text = "Third week without a supply boat. Company says weather. Weather doesn't explain why the sonar keeps pinging something the size of a church under us every night at 02:10.",
	},
	Log_Control = {
		title = "CONTROL ROOM — SHIFT LOG",
		text = "Drill string punched through at 3,140 m into open cavity. No pressure kick. Instead the mud came back warm and full of... eggs? Halvard Deepwater ordered samples sent to Station Marrow. Nobody asked us.",
	},
	Log_Maintenance = {
		title = "MAINTENANCE — WORK ORDER #88",
		text = "Bilge pump seized again. Someone welded the hatch shut from the inside. I cut it open. Water came up to my neck in seconds. The water was moving AGAINST the pumps.",
	},
	Log_Tower = {
		title = "OBSERVATION TOWER — WATCH LOG",
		text = "It stands out there past the buoys. Doesn't move when the lights are off. Turn the floodlights on and it turns its head. Then the climbers come.",
	},
	Log_Lab1 = {
		title = "STATION MARROW — SPECIMEN C-12",
		text = "Juveniles (we call them Climbers) are photophobic but not photosensitive: they fear the light because the Adult responds to it. They are herding us toward the dark.",
	},
	Log_Lab2 = {
		title = "STATION MARROW — DR. OYELARAN",
		text = "The mimic behaviour is learned. Specimen D copied Tomas's walk. Then his voice. When Tomas went missing it kept wearing his face for two days before it got hungry.",
	},
	Log_B7 = {
		title = "RIG B-7 — LAST ENTRY",
		text = "We lost power on B-7 and the big one hit the legs. We're taking the boat to KESTREL-9. If you're reading this, don't let the generator die.",
	},
	Log_Cargo = {
		title = "MV ORRIN BAY — MANIFEST NOTE",
		text = "Cargo: 40 containers relief supplies for KESTREL-9. Something dragged the stern under in calm water. Crew in lifeboats. Supplies still aboard.",
	},
	Log_Island = {
		title = "CASTAWAY CAMP — SCRATCHED ON A CRATE",
		text = "Day 37. The rain collector works. Don't swim at night. Don't swim at all near the cave, the crystals glow when something is close.",
	},
	Log_Underdeck = {
		title = "UNDERDECK PUMP ROOM - OKAFOR'S NOTE",
		text = "They come up the legs and they come in under the deck. I heard them on the catwalks last night, right under the mess. Pumps 1 and 2 still work. If you are hiding down here: they can smell you if you stay put. Keep moving.",
	},
	Log_Radio = {
		title = "LIGHTHOUSE RELAY — AUTOMATED",
		text = "RELAY ACTIVE. RESCUE VESSEL ETA: 100 DAYS FROM INCIDENT. KEEP BEACON POWERED. KEEP LIGHTS POWERED. KEEP—",
	},
}

-- Radio transmissions heard at dawn.
Story.Radio = {
	[1] = "…this is KESTREL-9 automated. Generator E-01 critical. Crew status: unknown. Restore power.",
	[2] = "…static… if anyone is aboard: the fuel drums in the engine room are still full.",
	[3] = "…Mara Voss, engineer, KESTREL-9. If the lights go out, don't hide. They find the ones who hide.",
	[4] = "…whoever is on the rig: the black box in east logistics. Find it before they do.",
	[5] = "…Orrin Bay relief convoy delayed. Estimate… one hundred days…",
	[6] = "…they don't just climb the legs any more. They climb everything.",
	[7] = "…loose supplies wash up on every deck and island. Take what the sea gives you.",
	[8] = "…a voice on channel 4 keeps calling the crew by name. It isn't one of us.",
	[9] = "…the weather station never recorded a storm. Somebody lied.",
	[10] = "…ten days. If you can hear this, you are doing better than we did.",
	[13] = "…the Throat is breathing. Sonar shows it every time E-01 runs hot.",
	[15] = "…Mara here. I'm going to the refinery. If I don't come back, finish it.",
	[11] = "…they come up the legs now. Lock the doors. Light the deck. They hate the light.",
	[21] = "…Rig B-7 went dark last month. Their stores might still be there. East of you.",
	[31] = "…Station Marrow airlock needs lab power. You'll need proper gear to get that deep.",
	[41] = "…count your crew. Then count them again.",
	[51] = "…storm season. The grid will trip. Keep a Repair Kit by the generator.",
	[61] = "…sonar picked up the Adult. It is waking. Keep sonar online for warning.",
	[71] = "…everything on this rig was built to last ten years. It's been eleven.",
	[81] = "…Deepwater knew. The drill wasn't looking for oil. It was looking for the Throat.",
	[85] = "…the Throat is a nest. KESTREL-9 is sitting on its lid.",
	[91] = "…rescue vessel Aldmere confirmed. Nine days. Hold on.",
	[99] = "…Aldmere at the horizon tomorrow at dawn. Survive one more night. Whatever comes up, survive.",
	[100] = "…everything is coming up tonight.",
}

return Story
