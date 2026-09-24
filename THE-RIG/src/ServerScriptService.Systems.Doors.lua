-- ServerScriptService/Systems/Doors
-- Technical doors between zones. Some zones are locked at the start and open through
-- progression: power, a crowbar, a lock bypass, draining the flooded level, or lab power.
-- Doors can be broken by Climbers (then they stay open until repaired).
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Items = require(ReplicatedStorage.Modules.Items)

local Doors = { list = {}, drained = false, pumpProgress = 0, labAir = false }
local G
local PUMP_TIME = 30

local DOORS = {
	Door_Generator = { label = "GENERATOR ROOM" },
	Door_Workshop = { label = "WORKSHOP" },
	Door_Kitchen = { label = "KITCHEN" },
	Door_Quarters = { label = "LIVING QUARTERS" },
	Door_EngineRoom = { label = "ENGINE ROOM", lock = "Power", power = "Doors", hint = "Electronic lock. Switch DOORS power on at a power console." },
	Door_Storage = { label = "STORAGE", lock = "Pry", hint = "Jammed shut. Pry it open with a Crowbar." },
	Door_Security = { label = "SECURITY OFFICE", lock = "Bypass", cost = { Electronics = 3 }, hint = "Security keypad. Bypass needs Electronics x3." },
	Door_WellControl = { label = "WELL CONTROL", lock = "Power", power = "Doors", hint = "Blast door. Switch DOORS power on." },
	Door_Halvard = { label = "HALVARD'S OFFICE", lock = "Bypass", cost = { Electronics = 4 }, hint = "Company lock. Bypass needs Electronics x4." },
	Door_Medical = { label = "MEDICAL ROOM", lock = "Bypass", cost = { Electronics = 2 }, hint = "Keypad lock. Bypass needs Electronics x2." },
	Door_Control = { label = "CONTROL ROOM", lock = "Bypass", cost = { Electronics = 1, Copper = 1 }, hint = "Keypad lock. Bypass needs Electronics x1, Copper Wire x1." },
	Door_Tower = { label = "OBSERVATION TOWER", lock = "Power", power = "Doors", hint = "Electronic lock. Switch DOORS power on." },
	Door_Maintenance = { label = "MAINTENANCE LEVEL", lock = "Pumps", hint = "The level below is flooded. Repair the bilge pump and power PUMPS to drain it." },
	Door_Lab = { label = "STATION MARROW", lock = "Lab", power = "Lab", hint = "Airlock needs LAB power." },
}

function Doors.init(g)
	G = g
	local folder = workspace.Interactables:FindFirstChild("Doors")
	if not folder then
		return
	end
	for _, model in ipairs(folder:GetChildren()) do
		if model:IsA("Model") and model:FindFirstChild("Panel") then
			Doors.register(model)
		end
	end
end

function Doors.register(model)
	local cfg = DOORS[model.Name] or { label = string.upper(model.Name) }
	local panel = model.Panel
	-- Door detailing lives inside the panel: weld it so it slides with the door.
	for _, part in ipairs(panel:GetChildren()) do
		if part:IsA("BasePart") then
			part.Anchored = false
			part.Massless = true
			part.CanCollide = false
			part.CanQuery = false
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = panel
			weld.Part1 = part
			weld.Parent = part
		end
	end
	local d = {
		model = model,
		panel = panel,
		cfg = cfg,
		closedCF = panel.CFrame,
		openCF = panel.CFrame * CFrame.new(panel.Size.X * 0.95, 0, 0),
		unlocked = cfg.lock == nil,
		open = false,
		broken = false,
	}
	model:SetAttribute("Label", cfg.label)
	model:SetAttribute("Locked", not d.unlocked)
	model:SetAttribute("Open", false)
	local prompt = G.Util.prompt(panel, d.unlocked and "Open" or "Unlock", cfg.label, d.unlocked and 0 or 0.8, 9)
	d.prompt = prompt
	prompt.Triggered:Connect(function(player)
		Doors.interact(player, d)
	end)
	G.Repair.register(model, {
		name = cfg.label .. " DOOR",
		max = 200,
		cost = { ScrapMetal = 3 },
		promptPart = panel,
		onBroken = function()
			d.broken = true
			Doors.setOpen(d, true, true)
			G.Net.toastAll(cfg.label .. " door was torn open!", "danger")
		end,
		onRepaired = function()
			d.broken = false
			panel.Transparency = 0
		end,
	})
	Doors.list[model.Name] = d
	return d
end

function Doors.updatePrompt(d)
	if not d.unlocked then
		d.prompt.ActionText = "Unlock"
		d.prompt.HoldDuration = 0.8
	else
		d.prompt.ActionText = d.open and "Close" or "Open"
		d.prompt.HoldDuration = 0
	end
	d.model:SetAttribute("Locked", not d.unlocked)
	d.model:SetAttribute("Open", d.open)
end

function Doors.setOpen(d, open, instant)
	d.open = open
	d.panel.CanCollide = not open
	local goal = open and d.openCF or d.closedCF
	if instant then
		d.panel.CFrame = goal
	else
		TweenService:Create(d.panel, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { CFrame = goal }):Play()
	end
	if d.broken then
		d.panel.Transparency = 0.6
	end
	Doors.updatePrompt(d)
end

function Doors.unlock(d, player)
	d.unlocked = true
	Doors.setOpen(d, true)
	local who = player and player.DisplayName or "Someone"
	G.Net.toastAll(d.cfg.label .. " unlocked by " .. who, "good")
	if player then
		G.PlayerData.unlock(player, "zone_" .. d.model.Name)
	end
	G.Director.objectiveDirty()
end

function Doors.interact(player, d)
	if not G.Net.near(player, d.panel, 12) then
		return
	end
	local cfg = d.cfg
	if not d.unlocked then
		if cfg.lock == "Power" then
			if G.Power.isPowered(cfg.power) then
				Doors.unlock(d, player)
			else
				G.Net.toast(player, cfg.hint, "warn")
			end
		elseif cfg.lock == "Pry" then
			if G.Inventory.count(player, "Crowbar") > 0 or G.Inventory.count(player, "Toolkit") > 0 then
				G.AI.noise(d.panel.Position, 60)
				Doors.unlock(d, player)
			else
				G.Net.toast(player, cfg.hint, "warn")
			end
		elseif cfg.lock == "Bypass" then
			local ok, missing = G.Inventory.takeAll(player, cfg.cost)
			if ok then
				Doors.unlock(d, player)
			else
				G.Net.toast(player, cfg.hint .. " Missing: " .. missing, "warn")
			end
		elseif cfg.lock == "Pumps" then
			if Doors.drained then
				Doors.unlock(d, player)
			else
				G.Net.toast(player, string.format("%s Drained: %d%%", cfg.hint, math.floor(Doors.pumpProgress / PUMP_TIME * 100)), "warn")
			end
		elseif cfg.lock == "Lab" then
			if G.Power.isPowered("Lab") then
				Doors.unlock(d, player)
				G.PlayerData.award(player, "DIVER")
			else
				G.Net.toast(player, cfg.hint, "warn")
			end
		end
		return
	end
	if d.broken then
		G.Net.toast(player, "The door is broken. Repair it (R) to close it again.", "warn")
		return
	end
	if cfg.lock == "Lab" and not G.Power.isPowered("Lab") then
		G.Net.toast(player, "Airlock has no LAB power.", "warn")
		return
	end
	Doors.setOpen(d, not d.open)
end

-- 4 Hz: pumps drain the maintenance level; lab power keeps Station Marrow dry.
function Doors.step(dt)
	if not Doors.drained then
		if G.Power.isPowered("Pumps") then
			Doors.pumpProgress = math.min(PUMP_TIME, Doors.pumpProgress + dt)
			if Doors.pumpProgress >= PUMP_TIME then
				Doors.drained = true
				G.World.setFlooded(false)
				G.Net.banner("MAINTENANCE LEVEL DRAINED", "The hatch next to the drilling floor can now be opened.", "good")
				G.Director.objectiveDirty()
			end
		end
		G.State.set("PumpProgress", math.floor(Doors.pumpProgress / PUMP_TIME * 100))
	end
	local lab = Doors.list.Door_Lab
	local wantAir = lab ~= nil and lab.unlocked and G.Power.isPowered("Lab")
	if wantAir ~= Doors.labAir then
		Doors.labAir = wantAir
		G.World.setLabAir(wantAir)
		if wantAir then
			G.Net.toastAll("Station Marrow pressurised. Air inside the lab.", "good")
		elseif lab and lab.unlocked then
			G.Net.banner("LAB BREACH", "Station Marrow lost power and is flooding.", "danger")
		end
	end
	G.State.set("Drained", Doors.drained)
end

function Doors.serialize()
	local unlocked = {}
	for name, d in pairs(Doors.list) do
		if d.unlocked and d.cfg.lock then
			unlocked[name] = true
		end
	end
	return { unlocked = unlocked, drained = Doors.drained, pump = Doors.pumpProgress }
end

function Doors.deserialize(data)
	if type(data) ~= "table" then
		return
	end
	if type(data.unlocked) == "table" then
		for name in pairs(data.unlocked) do
			local d = Doors.list[name]
			if d then
				d.unlocked = true
				Doors.setOpen(d, true, true)
			end
		end
	end
	Doors.drained = data.drained == true
	if type(data.pump) == "number" then
		Doors.pumpProgress = math.clamp(data.pump, 0, PUMP_TIME)
	end
end

-- Called after the terrain exists and the save has been applied.
function Doors.applyTerrain()
	G.World.setFlooded(not Doors.drained)
	Doors.labAir = false
	G.World.setLabAir(false)
end

function Doors.reset()
	for _, d in pairs(Doors.list) do
		d.unlocked = d.cfg.lock == nil
		d.broken = false
		d.panel.Transparency = 0
		Doors.setOpen(d, false, true)
		G.Repair.setHealth(d.model, 200)
	end
	Doors.drained = false
	Doors.pumpProgress = 0
	Doors.applyTerrain()
end

Doors.costText = Items.costText

return Doors
