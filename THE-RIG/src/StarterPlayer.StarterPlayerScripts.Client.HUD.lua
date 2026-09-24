-- StarterPlayerScripts/Client/HUD
-- Always-visible HUD kept deliberately small: clock, objective, power line, vital bars,
-- hotbar, side buttons, toasts, banners, death / victory screens, damage vignette.
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Items = require(ReplicatedStorage.Modules.Items)
local Config = require(ReplicatedStorage.Modules.Config)

local Icons = require(script.Parent.ItemIcons)
local HUD = {}
local C, UI, col
local player = Players.LocalPlayer

local WEATHER_NAMES = { Clear = "CLEAR", Fog = "FOG", Rain = "RAIN", HeavyRain = "HEAVY RAIN", Thunderstorm = "THUNDERSTORM", Storm = "STORM" }

function HUD.init(ctx)
	C = ctx
	UI = C.UI
	col = UI.Colors
	local gui = C.gui
	local touch = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
	HUD.touch = touch
	HUD.hidden = false

	-- Compact HUD: thin readouts hugging the screen edges, translucent, nothing in the middle
	-- of the view. It dims itself when everything is fine; H hides it completely.
	local overlayGui = gui
	gui = UI.new("Frame", {Name = "FlightHUD", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1)}, gui)
	HUD.gameplay = gui
	local function shadow(l)
		l.TextStrokeTransparency = 0.55
		l.TextStrokeColor3 = Color3.new(0, 0, 0)
		return l
	end
	-- Top-left: day / clock / weather, then objective + tasks.
	HUD.day = shadow(UI.label(gui, "", {Position = UDim2.fromOffset(18, 12), Size = UDim2.fromOffset(420, 22), Font = UI.Black, TextSize = 18}))
	HUD.phase = shadow(UI.label(gui, "", {Position = UDim2.fromOffset(18, 34), Size = UDim2.fromOffset(420, 14), Font = UI.Mono, TextSize = 10, TextColor3 = col.Teal}))
	local obj = UI.frame(gui, {Name = "Objective", Position = UDim2.fromOffset(12, 54), Size = UDim2.fromOffset(350, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 0.55})
	UI.corner(obj, 6)
	UI.pad(obj, 10, 7, 10, 8)
	UI.list(obj, 3)
	UI.label(obj, "OBJECTIVE", {LayoutOrder = 1, Size = UDim2.new(1, 0, 0, 12), TextSize = 9, Font = UI.Mono, TextColor3 = col.Amber})
	HUD.objective = UI.label(obj, "", {LayoutOrder = 2, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, TextSize = 12, TextWrapped = true})
	HUD.scent = UI.label(obj, "THEY CAN SMELL YOU — KEEP MOVING", {LayoutOrder = 3, Size = UDim2.new(1, 0, 0, 14), TextSize = 11, Font = UI.Bold, TextColor3 = col.Red, Visible = false})
	UI.label(obj, "CREW TASKS", {LayoutOrder = 4, Size = UDim2.new(1, 0, 0, 12), TextSize = 9, Font = UI.Mono, TextColor3 = col.Teal})
	HUD.tasks = {}
	for k = 1, 3 do
		HUD.tasks[k] = UI.label(obj, "", {LayoutOrder = 4 + k, Size = UDim2.new(1, 0, 0, 14), TextSize = 11, TextColor3 = col.Dim, TextTruncate = Enum.TextTruncate.AtEnd})
	end
	HUD.attention = UI.frame(obj, {BackgroundColor3 = col.Red, Position = UDim2.new(0, 0, 1, -2), Size = UDim2.fromOffset(0, 2), Visible = false})
	-- Top-right: generator telemetry, one compact card.
	local power = UI.frame(gui, {Name = "Telemetry", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 12), Size = UDim2.fromOffset(250, 58), BackgroundTransparency = 0.55})
	UI.corner(power, 6)
	HUD.gen = shadow(UI.label(power, "", {Position = UDim2.fromOffset(10, 6), Size = UDim2.fromOffset(232, 16), TextSize = 12, Font = UI.Bold}))
	HUD.fuel = UI.label(power, "", {Position = UDim2.fromOffset(10, 23), Size = UDim2.fromOffset(232, 14), TextSize = 10, Font = UI.Mono})
	HUD.sonar = UI.label(power, "", {Position = UDim2.fromOffset(10, 39), Size = UDim2.fromOffset(232, 13), TextSize = 9, TextColor3 = col.Teal, TextTruncate = Enum.TextTruncate.AtEnd})
	HUD.powerBox = power
	-- Bottom-left: slim vital bars (they fade out while everything is healthy).
	local vit = UI.new("CanvasGroup", {Name = "CrewVitals", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 14, 1, -14), Size = UDim2.fromOffset(210, 90)}, gui)
	HUD.vitals = vit
	HUD.bars = {}
	for i, spec in ipairs({{"Health", "HP", col.Green}, {"Stamina", "STA", col.Amber}, {"Hunger", "FOOD", col.Amber}, {"Thirst", "H2O", col.Blue}}) do
		local bar = UI.bar(vit, spec[2], spec[3], {Position = UDim2.fromOffset(0, (i - 1) * 17), Size = UDim2.fromOffset(210, 15)})
		bar.label.TextSize = 9
		bar.label.Size = UDim2.new(0, 34, 1, 0)
		bar.value.TextSize = 9
		bar.value.Size = UDim2.new(0, 30, 1, 0)
		bar.value.Position = UDim2.new(1, -30, 0, 0)
		bar.fill.Parent.Position = UDim2.new(0, 38, 0.5, -2)
		bar.fill.Parent.Size = UDim2.new(1, -72, 0, 4)
		HUD.bars[spec[1]] = bar
	end
	HUD.extra = UI.label(vit, "", {Position = UDim2.fromOffset(0, 72), Size = UDim2.fromOffset(210, 14), Font = UI.Mono, TextSize = 9, TextColor3 = col.Dim})
	HUD.bars.Oxygen = UI.bar(gui, "O2", col.Teal, {AnchorPoint = Vector2.new(.5, 1), Position = UDim2.new(.5, 0, 1, -118), Size = UDim2.fromOffset(240, 18)})
	-- Bottom-centre: quick slots.
	local hot = UI.new("Frame", {Name = "QuickSlots", BackgroundTransparency = 1, AnchorPoint = Vector2.new(.5, 1), Position = UDim2.new(.5, 0, 1, -12), Size = UDim2.fromOffset(6 * 56 - 4, 46)}, gui)
	UI.new("UIListLayout", {FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder}, hot)
	HUD.hotSlots = {}
	for i = 1, Config.Inventory.Hotbar do
		local b = UI.button(hot, "", {Name = "Slot"..i, LayoutOrder = i, Size = UDim2.fromOffset(52, 46), BackgroundTransparency = .45}, function() C.send("Hotbar", i) end)
		local stroke = b:FindFirstChildOfClass("UIStroke")
		UI.label(b, tostring(i), {Position = UDim2.fromOffset(5, 3), Size = UDim2.fromOffset(12, 10), TextSize = 9, Font = UI.Mono, TextColor3 = col.Dim})
		local swatch = UI.frame(b, {Position = UDim2.fromOffset(5, 17), Size = UDim2.fromOffset(18, 3), Visible = false})
		local short = UI.label(b, "", {Position = UDim2.fromOffset(5, 26), Size = UDim2.fromOffset(44, 14), TextSize = 9, Font = UI.Bold, TextTruncate = Enum.TextTruncate.AtEnd})
		local count = UI.label(b, "", {Position = UDim2.fromOffset(26, 3), Size = UDim2.fromOffset(22, 10), TextSize = 9, Font = UI.Mono, TextXAlignment = Enum.TextXAlignment.Right})
		HUD.hotSlots[i] = {button=b,stroke=stroke,swatch=swatch,short=short,count=count}
	end
	HUD.held = shadow(UI.label(gui, "", {AnchorPoint=Vector2.new(.5,1),Position=UDim2.new(.5,0,1,-62),Size=UDim2.fromOffset(470,16),TextSize=10,TextXAlignment=Enum.TextXAlignment.Center,TextColor3=col.Amber}))
	HUD.boat = shadow(UI.label(gui, "", {AnchorPoint=Vector2.new(.5,1),Position=UDim2.new(.5,0,1,-80),Size=UDim2.fromOffset(470,16),TextSize=10,TextXAlignment=Enum.TextXAlignment.Center,TextColor3=col.Teal}))
	-- Shortcut buttons on touch screens; a one-line key hint on PC.
	if touch then
		local side = UI.new("Frame", {Name="Shortcuts", BackgroundTransparency=1, AnchorPoint=Vector2.new(1,0),Position=UDim2.new(1,-12,0,78),Size=UDim2.fromOffset(110,150)},gui)
		UI.list(side,4)
		for i,spec in ipairs({{"INVENTORY","Inventory"},{"CRAFTING","Craft"},{"BUILDING","Build"},{"POWER","Power"},{"MENU","Menu"}}) do
			UI.button(side,spec[1], {LayoutOrder=i,Size=UDim2.new(1,0,0,26),TextSize=9,TextColor3=col.Dim,BackgroundTransparency=.4}, function() C.Panels.toggle(spec[2]) end)
		end
	else
		shadow(UI.label(gui, "TAB inventory · C craft · B build · P power · J journal · V view · H hide HUD", {AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -14, 1, -12), Size = UDim2.fromOffset(460, 14), TextSize = 9, Font = UI.Mono, TextColor3 = col.Dim, TextXAlignment = Enum.TextXAlignment.Right, TextTransparency = 0.25}))
	end
	HUD.crosshair = UI.frame(overlayGui, {Name="Reticle",AnchorPoint=Vector2.new(.5,.5),Position=UDim2.fromScale(.5,.5),Size=UDim2.fromOffset(3,3),BackgroundColor3=col.Text,BackgroundTransparency=.3})
	UI.corner(HUD.crosshair,3)

	-- Touch action buttons
	if touch then
		local act = UI.new("Frame", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -150, 1, -150), Size = UDim2.new(0, 150, 0, 150) }, gui)
		local use = UI.button(act, "USE", { Position = UDim2.new(0, 70, 0, 70), Size = UDim2.new(0, 72, 0, 72), TextSize = 14 })
		UI.corner(use, 36)
		use.Activated:Connect(function()
			C.useEquipped()
		end)
		local sprint = UI.button(act, "RUN", { Position = UDim2.new(0, 0, 0, 80), Size = UDim2.new(0, 60, 0, 60), TextSize = 12 })
		UI.corner(sprint, 30)
		sprint.Activated:Connect(function()
			C.setSprint(not C.sprinting)
			sprint.TextColor3 = C.sprinting and col.Green or col.Amber
		end)
		local torch = UI.button(act, "LIGHT", { Position = UDim2.new(0, 80, 0, 0), Size = UDim2.new(0, 60, 0, 60), TextSize = 11 })
		UI.corner(torch, 30)
		torch.Activated:Connect(function()
			C.send("Flashlight")
			C.Viewmodel.toggled()
		end)
		local focus = UI.button(act, "FOCUS", { Position = UDim2.new(0, 0, 0, 0), Size = UDim2.new(0, 60, 0, 60), TextSize = 10 })
		UI.corner(focus, 30)
		focus.Activated:Connect(function()
			C.setFocus(not C.focusing)
			focus.TextColor3 = C.focusing and col.Green or col.Amber
		end)
	end

	UserInputService.InputBegan:Connect(function(input, processed)
		if not processed and input.KeyCode == Enum.KeyCode.H and not UserInputService:GetFocusedTextBox() and not C.panelOpen then
			HUD.hidden = not HUD.hidden
			HUD.toast(HUD.hidden and "HUD hidden — press H to show it again" or "HUD visible", "info")
		end
	end)

	gui = overlayGui
	-- Toasts
	HUD.toasts = UI.new("Frame", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -142), Size = UDim2.new(0, 440, 0, 160) }, gui)
	local tl = UI.list(HUD.toasts, 4)
	tl.VerticalAlignment = Enum.VerticalAlignment.Bottom
	tl.HorizontalAlignment = Enum.HorizontalAlignment.Center

	-- Banner
	local banner = UI.panelBox(gui, { Name = "Banner", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 64), Size = UDim2.new(0, 540, 0, 64), Visible = false, BackgroundTransparency = 0.25 })
	HUD.bannerStripe = UI.stripe(banner, col.Amber, { Size = UDim2.new(0, 5, 1, 0) })
	HUD.bannerTitle = UI.label(banner, "", { Position = UDim2.new(0, 16, 0, 6), Size = UDim2.new(1, -28, 0, 24), Font = UI.Black, TextSize = 19, TextColor3 = col.Amber })
	HUD.bannerSub = UI.label(banner, "", { Position = UDim2.new(0, 16, 0, 31), Size = UDim2.new(1, -28, 0, 30), TextSize = 12, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top })
	HUD.banner = banner
	HUD.bannerQueue = {}

	-- Damage vignette
	HUD.vignette = UI.new("Frame", { Name = "Vignette", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 1, 0), ZIndex = 0 }, gui)
	for _, spec in ipairs({
		{ UDim2.new(0, 0, 0, 0), UDim2.new(1, 0, 0, 60), 90 },
		{ UDim2.new(0, 0, 1, -60), UDim2.new(1, 0, 0, 60), -90 },
		{ UDim2.new(0, 0, 0, 0), UDim2.new(0, 60, 1, 0), 0 },
		{ UDim2.new(1, -60, 0, 0), UDim2.new(0, 60, 1, 0), 180 },
	}) do
		local f = UI.new("Frame", { Position = spec[1], Size = spec[2], BackgroundColor3 = col.Red, BorderSizePixel = 0, BackgroundTransparency = 0 }, HUD.vignette)
		UI.new("UIGradient", { Rotation = spec[3], Transparency = NumberSequence.new(0, 1) }, f)
	end
	HUD.vignette.Visible = false

	-- Loading overlay
	HUD.loading = UI.frame(gui, { Size = UDim2.new(1, 0, 1, 0), BackgroundColor3 = col.Bg, BackgroundTransparency = 0.2, ZIndex = 50, Visible = true })
	UI.label(HUD.loading, "PREPARING KESTREL-9…", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 0), Size = UDim2.new(0, 400, 0, 40), TextXAlignment = Enum.TextXAlignment.Center, Font = UI.Black, TextSize = 22, TextColor3 = col.Amber, ZIndex = 51 })

	-- Death screen
	local death = UI.frame(gui, { Name = "Death", Size = UDim2.new(1, 0, 1, 0), BackgroundColor3 = Color3.fromRGB(30, 4, 4), BackgroundTransparency = 0.25, Visible = false, ZIndex = 40 })
	UI.label(death, "YOU DIED", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.4, 0), Size = UDim2.new(0, 600, 0, 60), TextXAlignment = Enum.TextXAlignment.Center, Font = UI.Black, TextSize = 48, TextColor3 = col.Red, ZIndex = 41 })
	HUD.deathCause = UI.label(death, "", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.4, 50), Size = UDim2.new(0, 600, 0, 24), TextXAlignment = Enum.TextXAlignment.Center, Font = UI.Bold, TextSize = 16, ZIndex = 41 })
	HUD.deathTimer = UI.label(death, "", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.4, 84), Size = UDim2.new(0, 600, 0, 20), TextXAlignment = Enum.TextXAlignment.Center, Font = UI.Mono, TextSize = 14, TextColor3 = col.Dim, ZIndex = 41 })
	UI.label(death, "Your inventory is kept. The rig still needs you.", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.4, 112), Size = UDim2.new(0, 600, 0, 20), TextXAlignment = Enum.TextXAlignment.Center, TextSize = 13, TextColor3 = col.Dim, ZIndex = 41 })
	HUD.death = death

	-- Victory screen
	local win = UI.frame(gui, { Name = "Victory", Size = UDim2.new(1, 0, 1, 0), BackgroundColor3 = Color3.fromRGB(6, 14, 12), BackgroundTransparency = 0.1, Visible = false, ZIndex = 45 })
	UI.label(win, "RESCUED", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.35, 0), Size = UDim2.new(0, 700, 0, 70), TextXAlignment = Enum.TextXAlignment.Center, Font = UI.Black, TextSize = 60, TextColor3 = col.Green, ZIndex = 46 })
	HUD.winText = UI.label(win, "", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.35, 70), Size = UDim2.new(0, 700, 0, 96), TextXAlignment = Enum.TextXAlignment.Center, TextWrapped = true, TextSize = 16, ZIndex = 46 })
	UI.button(win, "CONTINUE (ENDLESS)", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.35, 190), Size = UDim2.new(0, 260, 0, 44), ZIndex = 46 }, function()
		win.Visible = false
		C.victoryOpen = false
		C.onPanel(false)
	end)
	HUD.victory = win

	-- Dev panel (Studio only)
	HUD.buildDev()

	task.spawn(HUD.loop)
end

function HUD.buildDev()
	local dev = UI.new("Frame", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 24, 1, -16), Size = UDim2.new(0, 250, 0, 30), Visible = false, ZIndex = 35 }, C.gui)
	local toggle = UI.button(dev, "DEV TOOLS (Studio)", { Size = UDim2.new(1, 0, 0, 26), TextSize = 11, TextColor3 = col.Teal })
	local grid = UI.panelBox(dev, { AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 0, -4), Size = UDim2.new(1, 0, 0, 292), Visible = false })
	UI.pad(grid, 6)
	UI.new("UIGridLayout", { CellSize = UDim2.new(0.5, -4, 0, 28), CellPadding = UDim2.new(0, 6, 0, 6) }, grid)
	for _, cmd in ipairs({ "Night", "Evening", "Dawn", "Climber", "Wave", "Watcher", "Mimic", "Silhouette", "Leviathan", "Lurker", "Storm", "Clear", "Event", "Supplies", "SkipDays", "DamageGen", "Tech" }) do
		UI.button(grid, cmd, { TextSize = 11 }, function()
			C.send("Test", cmd)
		end)
	end
	toggle.Activated:Connect(function()
		grid.Visible = not grid.Visible
	end)
	HUD.dev = dev
end

-- Inventory → hotbar
function HUD.updateInventory()
	local inv = C.inventory
	local bySlot = {}
	for _, s in ipairs(inv.slots) do
		bySlot[s.i] = s
	end
	for i, h in ipairs(HUD.hotSlots) do
		local s = bySlot[i]
		local def = s and Items.get(s.id)
		h.swatch.Visible = false
		Icons.show(h.button, def and s.id, {Position=UDim2.fromOffset(12,2),Size=UDim2.fromOffset(31,29)})
		if def then
			h.swatch.BackgroundColor3 = def.color or col.Dim
			h.short.Text = def.short
			h.count.Text = s.n > 1 and tostring(s.n) or ""
		else
			h.short.Text = ""
			h.count.Text = ""
		end
		local selected = inv.equipped == i
		h.stroke.Color = selected and col.Amber or col.Stroke
		h.stroke.Thickness = selected and 2 or 1
	end
	local eq = bySlot[inv.equipped]
	HUD.equipped = eq and eq.id or nil
end

function HUD.toast(text, tone)
	if not text or text == "" then
		return
	end
	local color = UI.Tones[tone] or col.Teal
	local f = UI.frame(HUD.toasts, { Size = UDim2.new(0, 440, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 0.35, LayoutOrder = math.floor(os.clock() * 100) % 1000000 })
	UI.corner(f, 3)
	UI.stripe(f, color)
	UI.pad(f, 12, 5, 10, 5)
	UI.label(f, text, { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, TextWrapped = true, TextSize = 12, TextXAlignment = Enum.TextXAlignment.Center })
	local items = {}
	for _, c in ipairs(HUD.toasts:GetChildren()) do
		if c:IsA("Frame") then
			table.insert(items, c)
		end
	end
	if #items > 3 then
		table.sort(items, function(a, b)
			return a.LayoutOrder < b.LayoutOrder
		end)
		items[1]:Destroy()
	end
	task.delay(4.5, function()
		if f.Parent then
			UI.tween(f, 0.4, { BackgroundTransparency = 1 })
			for _, d in ipairs(f:GetDescendants()) do
				if d:IsA("TextLabel") then
					UI.tween(d, 0.4, { TextTransparency = 1 })
				end
			end
			task.wait(0.45)
			f:Destroy()
		end
	end)
	if tone == "danger" or tone == "good" then
		C.Env.ping()
	end
end

function HUD.showBanner(title, sub, tone)
	table.insert(HUD.bannerQueue, { title = title, sub = sub, tone = tone })
	if HUD.bannerBusy then
		return
	end
	HUD.bannerBusy = true
	task.spawn(function()
		while #HUD.bannerQueue > 0 do
			local b = table.remove(HUD.bannerQueue, 1)
			local color = UI.Tones[b.tone] or col.Amber
			HUD.bannerTitle.Text = b.title
			HUD.bannerTitle.TextColor3 = color
			HUD.bannerSub.Text = b.sub or ""
			HUD.bannerStripe.BackgroundColor3 = color
			HUD.banner.Visible = true
			HUD.banner.Position = UDim2.new(0.5, 0, 0, 56)
			UI.tween(HUD.banner, 0.3, { Position = UDim2.new(0.5, 0, 0, 64) })
			C.Env.ping()
			task.wait(#HUD.bannerQueue > 0 and 3.2 or 5.5)
			HUD.banner.Visible = false
		end
		HUD.bannerBusy = false
	end)
end

function HUD.flashDamage(intensity)
	HUD.vignette.Visible = true
	for _, f in ipairs(HUD.vignette:GetChildren()) do
		f.BackgroundTransparency = 1 - math.clamp(intensity, 0.2, 0.9)
		UI.tween(f, 0.8, { BackgroundTransparency = 1 })
	end
	task.delay(0.85, function()
		HUD.vignette.Visible = false
	end)
end

function HUD.showDeath(cause, seconds)
	HUD.death.Visible = true
	HUD.deathCause.Text = "Cause: " .. tostring(cause)
	task.spawn(function()
		for t = seconds, 1, -1 do
			if not HUD.death.Visible then
				return
			end
			HUD.deathTimer.Text = "Respawning in " .. t .. "…"
			task.wait(1)
		end
		HUD.deathTimer.Text = "Respawning…"
	end)
end

function HUD.hideDeath()
	HUD.death.Visible = false
end

function HUD.showVictory(data)
	HUD.victory.Visible = true
	C.victoryOpen = true
	C.onPanel(true)
	HUD.winText.Text = (data.evidence and "THE TRUTH SURVIVED. Halvard’s recordings reached the world.\n" or "THE CREW SURVIVED. Halvard’s records remain offshore.\n") .. string.format("You held KESTREL-9 for %d days. The rescue vessel Aldmere has arrived.\nCredits: %d. The rig keeps running in endless mode.", data.day or 100, data.credits or 0)
end

-- Crew tasks arrive as a JSON list [{t = text, p = progress, g = goal}].
function HUD.updateTasks(json)
	if json == HUD.lastTasks then
		return
	end
	HUD.lastTasks = json
	local ok, list = pcall(function()
		return game:GetService("HttpService"):JSONDecode(json or "[]")
	end)
	list = ok and type(list) == "table" and list or {}
	for k, label in ipairs(HUD.tasks) do
		local q = list[k]
		label.Visible = q ~= nil
		if q then
			label.Text = (q.g or 1) > 1 and string.format("•  %s   %d/%d", tostring(q.t), q.p or 0, q.g) or ("•  " .. tostring(q.t))
		end
	end
end

-- Story intro, shown once per player on the first join.
local INTRO = {
	"KESTREL-9.  NORTH ATLANTIC.  DAY 1.",
	"Three weeks ago the company evacuated the rig. You were left behind.",
	"The launch counted eight people. Then it counted nine.",
	"Now generator E-01 is dying, the radio is dead, and every night something climbs the legs.",
	"The rescue ship Aldmere is one hundred days away.",
	"Keep the lights on. Find out what happened to the crew. Make the world hear it.",
}
local GOALS = "SURVIVE 100 NIGHTS — rescue arrives at dawn of day 100.\nFOLLOW THE STORY — the objective (top-left) and J journal lead you chapter by chapter across the sea.\nDO CREW TASKS — credits and supplies for everyone.\nLOOT IS EVERYWHERE — loose items glint on every deck, roof and island.\nNIGHT: stay near powered light, never sit in one place. They can smell you, and they climb anything."

function HUD.showIntro()
	if HUD.introOpen then
		return
	end
	HUD.introOpen = true
	local g = UI.new("ScreenGui", {Name = "Intro", IgnoreGuiInset = true, DisplayOrder = 60, ResetOnSpawn = false}, C.gui.Parent)
	local bg = UI.frame(g, {Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.05})
	local text = UI.label(bg, "", {AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.42, 0), Size = UDim2.fromOffset(760, 260), TextWrapped = true, TextSize = 20, Font = UI.Font, TextXAlignment = Enum.TextXAlignment.Center, TextYAlignment = Enum.TextYAlignment.Top, TextColor3 = col.Text})
	local goals = UI.label(bg, "", {AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0.62, 0), Size = UDim2.fromOffset(760, 150), TextWrapped = true, TextSize = 13, Font = UI.Mono, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, TextColor3 = col.Amber, TextTransparency = 1})
	local hint = UI.label(bg, "CLICK OR PRESS ANY KEY", {AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -30), Size = UDim2.fromOffset(400, 20), TextSize = 12, Font = UI.Mono, TextXAlignment = Enum.TextXAlignment.Center, TextColor3 = col.Dim})
	local skip = false
	local conn = UserInputService.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Keyboard or input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			skip = true
		end
	end)
	task.spawn(function()
		local shown = ""
		for _, line in ipairs(INTRO) do
			for c = 1, #line do
				if skip then
					break
				end
				text.Text = shown .. string.sub(line, 1, c)
				task.wait(0.025)
			end
			shown = shown .. line .. "\n\n"
			text.Text = shown
			if skip then
				break
			end
			task.wait(0.5)
		end
		text.Text = table.concat(INTRO, "\n\n")
		goals.Text = GOALS
		UI.tween(goals, 0.8, {TextTransparency = 0})
		skip = false
		hint.Text = "CLICK OR PRESS ANY KEY TO BEGIN"
		while not skip do
			task.wait(0.1)
		end
		conn:Disconnect()
		UI.tween(bg, 0.6, {BackgroundTransparency = 1})
		for _, l in ipairs({text, goals, hint}) do
			UI.tween(l, 0.5, {TextTransparency = 1})
		end
		task.wait(0.65)
		g:Destroy()
		HUD.introOpen = false
	end)
end

local function fmtHour(h)
	local hh = math.floor(h)
	local mm = math.floor((h - hh) * 60)
	return string.format("%02d:%02d", hh, mm)
end

function HUD.loop()
	local S = C.state
	while true do
		task.wait(0.2)
		local ok, err = pcall(function()
			HUD.loading.Visible = S:GetAttribute("Ready") ~= true and not C.menuOpen
			HUD.dev.Visible = S:GetAttribute("StudioTools") == true and C.menuOpen
			HUD.gameplay.Visible = not HUD.hidden and not C.panelOpen and not HUD.death.Visible and not HUD.victory.Visible and not HUD.introOpen
			local day = S:GetAttribute("Day") or 1
			local hour = C.hour()
			local phase = S:GetAttribute("Phase") or "Day"
			local weather = WEATHER_NAMES[S:GetAttribute("Weather") or "Clear"] or ""
			HUD.day.Text = string.format("DAY %d / %d   %s  %s · %s", day, Config.MaxDays, fmtHour(hour), string.upper(phase), weather)
			HUD.day.TextColor3 = phase == "Night" and col.Red or (phase == "Evening" and col.Amber or col.Text)
			HUD.phase.Text = S:GetAttribute("PhaseTitle") or ""
			HUD.objective.Text = S:GetAttribute("Objective") or "Restore generator E-01 before nightfall."
			HUD.scent.Visible = player:GetAttribute("Scented") == true
			HUD.updateTasks(S:GetAttribute("Quests"))
			local att = S:GetAttribute("WatcherAttention") or 0
			HUD.attention.Visible = att > 0
			HUD.attention.Size = UDim2.new(att / 100, 0, 0, 2)

			local online = S:GetAttribute("GenOnline") == true
			local tripped = S:GetAttribute("Tripped") == true
			local overload = S:GetAttribute("Overload") == true
			local fuel = S:GetAttribute("GenFuel") or 0
			local tank = S:GetAttribute("GenTank") or 100
			local hp = S:GetAttribute("GenHealth") or 0
			local cap = S:GetAttribute("PowerCapacity") or 100
			local demand = S:GetAttribute("PowerDemand") or 0
			local status = online and "ONLINE" or (tripped and "TRIPPED" or "OFFLINE")
			if overload then
				status = "OVERLOAD " .. (S:GetAttribute("OverloadTime") or 0) .. "s"
			end
			HUD.gen.Text = string.format("E-01 %s · L%d · HP %d", status, S:GetAttribute("GenLevel") or 1, math.floor(hp))
			HUD.gen.TextColor3 = overload and col.Red or (online and col.Green or col.Red)
			HUD.fuel.Text = string.format("FUEL %3d%%   LOAD %d/%d", math.floor(fuel / tank * 100), demand, cap)
			HUD.fuel.TextColor3 = fuel / tank < 0.25 and col.Red or col.Text
			local sonar = S:GetAttribute("Sonar") or ""
			local burn = Config.Generator.BaseBurn + Config.Generator.LoadBurn * math.clamp(demand / math.max(cap, 1), 0, 1.5)
			burn *= S:GetAttribute("FuelEfficiency") or 1
			local seconds = math.floor(fuel / math.max(burn, 0.001))
			HUD.sonar.Text = sonar ~= "" and ("SONAR: " .. sonar) or (online and string.format("FUEL ETA ~%d:%02d / CURRENT LOAD", math.floor(seconds/60), seconds%60) or "RESTORE E-01 / WEST WALKWAY")

			local character = player.Character
			local hum = character and character:FindFirstChildOfClass("Humanoid")
			-- Vitals fade while every value is comfortable and nothing changes.
			local calm = (not hum or hum.Health > hum.MaxHealth * 0.7) and (player:GetAttribute("Stamina") or 100) > 95
				and (player:GetAttribute("Hunger") or 100) > 45 and (player:GetAttribute("Thirst") or 100) > 45
			HUD.calmFor = calm and (HUD.calmFor or 0) + 0.2 or 0
			local fade = HUD.calmFor > 4 and 0.65 or 0
			if HUD.fadeTarget ~= fade then
				HUD.fadeTarget = fade
				UI.tween(HUD.vitals, 0.6, { GroupTransparency = fade })
			end
			if hum then
				HUD.bars.Health.set(hum.Health, hum.MaxHealth)
				if HUD.lastHealth and hum.Health < HUD.lastHealth - 1 then
					HUD.flashDamage((HUD.lastHealth - hum.Health) / 30)
				end
				HUD.lastHealth = hum.Health
			end
			HUD.bars.Stamina.set(player:GetAttribute("Stamina") or 100, 100)
			HUD.bars.Hunger.set(player:GetAttribute("Hunger") or 100, 100)
			HUD.bars.Thirst.set(player:GetAttribute("Thirst") or 100, 100)
			local o2 = player:GetAttribute("Oxygen") or 100
			HUD.bars.Oxygen.set(o2, 100)
			HUD.bars.Oxygen.frame.Visible = o2 < 99.5 or player:GetAttribute("Underwater") == true
			local armor = player:GetAttribute("Armor") or 0
			HUD.extra.Text = string.format("%s%s   CR %d", player:GetAttribute("TorchFocus") and "TORCH FOCUS" or "TORCH", armor > 0 and string.format("   VEST %d", math.floor(armor)) or "", player:GetAttribute("Credits") or 0)

			local eq = HUD.equipped
			if eq == "Flashlight" then
				eq = nil -- the flashlight lives in the left hand now
			end
			if eq then
				local def = Items.get(eq)
				local hint = HUD.touch and "USE" or "Click"
				HUD.held.Text = def.name .. " — " .. hint .. " to use"
			else
				HUD.held.Text = ""
			end
		end)
		if not ok then
			warn("[HUD] " .. tostring(err))
		end
	end
end

return HUD
