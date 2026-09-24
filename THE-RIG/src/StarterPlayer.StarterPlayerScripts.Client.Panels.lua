-- StarterPlayerScripts/Client/Panels
-- Modal panels (one at a time): Inventory (drag & drop, use, drop, give), Crafting, Build,
-- Power Management, Repair, Boat Cargo, Research, Log, Settings, How to play + Main Menu.
-- Panels only display state and send requests; the server decides every outcome.
local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Items = require(ReplicatedStorage.Modules.Items)
local Recipes = require(ReplicatedStorage.Modules.Recipes)
local Buildables = require(ReplicatedStorage.Modules.Buildables)
local Config = require(ReplicatedStorage.Modules.Config)
local Story = require(ReplicatedStorage.Modules.Story)
local Expeditions = require(ReplicatedStorage.Modules.Expeditions)

local Icons = require(script.Parent.ItemIcons)
local Panels = { current = nil, data = {} }
local C, UI, col
local player = Players.LocalPlayer
local builders = {}
local drag = nil

local SLOT = 62
local GAP = 6

local function countOf(id)
	local n = 0
	for _, s in ipairs(C.inventory.slots) do
		if s.id == id then
			n += s.n
		end
	end
	return n
end
Panels.countOf = countOf

local function costRich(cost)
	local parts = {}
	for _, id in ipairs(Items.Order) do
		local need = cost[id]
		if need then
			local have = countOf(id)
			local color = have >= need and "#78D08A" or "#E0584A"
			table.insert(parts, string.format('<font color="%s">%s %d/%d</font>', color, Items.name(id), have, need))
		end
	end
	return table.concat(parts, "  ·  ")
end

local function canAfford(cost)
	for id, n in pairs(cost) do
		if countOf(id) < n then
			return false
		end
	end
	return true
end

function Panels.init(ctx)
	C = ctx
	UI = C.UI
	col = UI.Colors
	local gui = C.gui
	local root = UI.panelBox(gui, { Name = "Panel", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 0), Size = UDim2.new(0, 920, 0, 560), Visible = false, BackgroundTransparency = 0.04, ZIndex = 10 })
	local header = UI.frame(root, { Size = UDim2.new(1, 0, 0, 40), BackgroundColor3 = col.PanelLight, BackgroundTransparency = 0, ZIndex = 10 })
	UI.stripe(header, col.Amber, { ZIndex = 11 })
	Panels.title = UI.label(header, "", { Position = UDim2.new(0, 16, 0, 0), Size = UDim2.new(1, -80, 1, 0), Font = UI.Black, TextSize = 18, TextColor3 = col.Amber, ZIndex = 11 })
	UI.button(header, "✕", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -6, 0.5, 0), Size = UDim2.new(0, 30, 0, 30), TextSize = 16, ZIndex = 11 }, function()
		Panels.close()
	end)
	Panels.body = UI.new("Frame", { Name = "Body", BackgroundTransparency = 1, Position = UDim2.new(0, 218, 0, 68), Size = UDim2.new(1, -238, 1, -88), ZIndex = 10 }, root)
	Panels.root = root
	Panels.shade = UI.frame(gui, {Name="PanelBackdrop",Size=UDim2.fromScale(1,1),BackgroundColor3=col.Bg,BackgroundTransparency=.4,ZIndex=9,Visible=false})
	local rail = UI.new("Frame", {Position=UDim2.fromOffset(16,68),Size=UDim2.new(0,180,1,-88),BackgroundTransparency=1,ZIndex=10},root)
	UI.label(rail,"CREW TERMINAL",{Size=UDim2.fromOffset(180,18),Font=UI.Mono,TextSize=10,TextColor3=col.Teal,ZIndex=11})
	Panels.nav = {}
	local entries = {{"Journal","J","EXPEDITIONS","DivingGear"},{"Inventory","TAB","INVENTORY","Toolkit"},{"Craft","C","CRAFTING","MechanicalParts"},{"Build","B","BUILDING","ScrapMetal"},{"Power","P","POWER GRID","Fuel"},{"Settings","","SETTINGS","Electronics"},{"Help","","FIELD GUIDE","Flashlight"}}
	if Panels.supportOffered() then
		table.insert(entries, {"Support","","SUPPORT","RareMaterials"})
	end
	for i,spec in ipairs(entries) do
		Panels.nav[spec[1]]=UI.button(rail,spec[3]..(spec[2]~="" and "  /  "..spec[2] or ""),{Position=UDim2.fromOffset(0,36+(i-1)*46),Size=UDim2.fromOffset(180,40),TextSize=11,ZIndex=11,TextColor3=col.Dim,Icon=spec[4]},function() Panels.open(spec[1]) end)
	end
	UI.button(rail,"Q  /  MAIN MENU",{AnchorPoint=Vector2.new(0,1),Position=UDim2.fromScale(0,1),Size=UDim2.fromOffset(180,36),TextSize=11,ZIndex=11},function() Panels.open("Menu") end)
	Panels.buildMenu()
end

-- SUPPORT is offered when a donation tier exists, and always in Studio as a reminder
-- that none has been set up.
function Panels.supportOffered()
	for _, tier in ipairs(Config.Donate) do
		if tier.id ~= 0 then
			return true
		end
	end
	return RunService:IsStudio()
end

function Panels.isOpen(name)
	return Panels.current == name
end

function Panels.open(name, data)
	if name == "Menu" then
		Panels.close()
		Panels.showMenu(true)
		return
	end
	local builder = builders[name]
	if not builder then
		return
	end
	if data ~= nil then
		Panels.data[name] = data
	end
	if C.menuOpen then Panels.showMenu(false) end
	Panels.current = name
	Panels.shade.Visible = true
	for key, button in pairs(Panels.nav) do
		button.TextColor3 = key == name and col.Amber or col.Dim
		button.BackgroundColor3 = key == name and col.PanelLight or col.Panel
	end
	Panels.root.Visible = true
	UI.clear(Panels.body)
	builder.build(Panels.body, Panels.data[name])
	Panels.title.Text = builder.title(Panels.data[name])
	C.onPanel(true)
end

function Panels.close()
	Panels.current = nil
	if drag and drag.ghost then drag.ghost:Destroy() end
	drag = nil
	Panels.shade.Visible = false
	Panels.root.Visible = false
	UI.clear(Panels.body)
	C.onPanel(false)
end

function Panels.toggle(name)
	if Panels.current == name then
		Panels.close()
	else
		Panels.open(name)
	end
end

-- Rebuild the open panel when inventory / profile / state change.
function Panels.refresh(which)
	local name = Panels.current
	if not name or (which and which ~= name and which ~= "*") then
		return
	end
	local builder = builders[name]
	if builder.refresh then
		builder.refresh(Panels.body, Panels.data[name])
	else
		UI.clear(Panels.body)
		builder.build(Panels.body, Panels.data[name])
	end
end

local function row(parent, order, height)
	local r = UI.frame(parent, { LayoutOrder = order, Size = UDim2.new(1, -8, 0, height or 54), BackgroundColor3 = col.PanelLight, BackgroundTransparency = 0.25, ZIndex = 10 })
	UI.corner(r, 3)
	return r
end

local function z(obj)
	obj.ZIndex = 11
	for _, d in ipairs(obj:GetDescendants()) do
		if d:IsA("GuiObject") then
			d.ZIndex = 11
		end
	end
	return obj
end

------------------------------------------------------------------------------
-- INVENTORY
------------------------------------------------------------------------------

builders.Inventory = {
	title = function()
		return "INVENTORY  //  " .. string.upper(player.DisplayName)
	end,
}

function builders.Inventory.build(body)
	local grid = UI.new("Frame", { Name = "Grid", BackgroundTransparency = 1, Size = UDim2.new(0, 6 * SLOT + 5 * GAP, 1, 0), ZIndex = 10 }, body)
	UI.label(grid, "HOTBAR (1-6)", { Size = UDim2.new(1, 0, 0, 14), TextSize = 10, Font = UI.Bold, TextColor3 = col.Dim, ZIndex = 11 })
	UI.label(grid, "BACKPACK", { Position = UDim2.new(0, 0, 0, SLOT + 22), Size = UDim2.new(1, 0, 0, 14), TextSize = 10, Font = UI.Bold, TextColor3 = col.Dim, ZIndex = 11 })
	Panels.slotFrames = {}
	local bySlot = {}
	for _, s in ipairs(C.inventory.slots) do
		bySlot[s.i] = s
	end
	for i = 1, Config.Inventory.Slots do
		local r = math.floor((i - 1) / 6)
		local c = (i - 1) % 6
		local y = 16 + r * (SLOT + GAP) + (r >= 1 and 22 or 0)
		local b = UI.new("TextButton", {
			Name = "Slot" .. i,
			Position = UDim2.new(0, c * (SLOT + GAP), 0, y),
			Size = UDim2.new(0, SLOT, 0, SLOT),
			BackgroundColor3 = i <= 6 and Color3.fromRGB(30, 28, 22) or col.Bg,
			BackgroundTransparency = 0.1,
			BorderSizePixel = 0,
			AutoButtonColor = false,
			Text = "",
			ZIndex = 11,
		}, grid)
		UI.corner(b, 3)
		local selected = Panels.selected == i
		UI.stroke(b, selected and col.Amber or (C.inventory.equipped == i and col.Teal or col.Stroke), selected and 2 or 1)
		local s = bySlot[i]
		local def = s and Items.get(s.id)
		if def then
			Icons.show(b, s.id, {Position=UDim2.fromOffset(4, 4), Size=UDim2.new(1,-8,1,-22), ZIndex=12})
			UI.label(b, def.short, { Position = UDim2.new(0, 0, 1, -17), Size = UDim2.new(1, 0, 0, 14), TextXAlignment = Enum.TextXAlignment.Center, Font = UI.Bold, TextSize = 10, ZIndex = 12 })
			if s.n > 1 then
				UI.label(b, tostring(s.n), { Position = UDim2.new(1, -28, 0, 2), Size = UDim2.new(0, 25, 0, 12), TextXAlignment = Enum.TextXAlignment.Right, Font = UI.Mono, TextSize = 11, ZIndex = 12 })
			end
		end
		b.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
				Panels.beginDrag(i, def, input)
			end
		end)
		Panels.slotFrames[i] = b
	end

	-- Details pane
	local detail = UI.panelBox(body, { Position = UDim2.new(0, 6 * SLOT + 5 * GAP + 14, 0, 16), Size = UDim2.new(1, -(6 * SLOT + 5 * GAP + 14), 1, -16), BackgroundColor3 = col.Bg, ZIndex = 10 })
	UI.pad(detail, 10)
	UI.list(detail, 6)
	local sel = Panels.selected and bySlot[Panels.selected]
	local def = sel and Items.get(sel.id)
	if not def then
		z(UI.label(detail, "Drag items between slots.\nDrag outside the grid to drop.\nClick an item for actions.\n\nSlots 1-6 are the hotbar:\npress 1-6 to equip.", { Size = UDim2.new(1, 0, 0, 120), TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top, TextSize = 13, TextColor3 = col.Dim }))
		return
	end
	z(UI.label(detail, def.name .. "  x" .. sel.n, { LayoutOrder = 1, Size = UDim2.new(1, 0, 0, 22), Font = UI.Black, TextSize = 16, TextColor3 = col.Amber }))
	z(UI.label(detail, def.desc, { LayoutOrder = 2, Size = UDim2.new(1, 0, 0, 64), TextWrapped = true, TextSize = 12, TextColor3 = col.Dim, TextYAlignment = Enum.TextYAlignment.Top }))
	local slot = Panels.selected
	if def.use or def.equip then
		z(UI.button(detail, def.equip and "EQUIP / UNEQUIP" or "USE", { LayoutOrder = 3, Size = UDim2.new(1, 0, 0, 32) }, function()
			C.send("InvUse", slot)
		end))
	end
	z(UI.button(detail, "DROP 1", { LayoutOrder = 4, Size = UDim2.new(1, 0, 0, 30) }, function()
		C.send("InvDrop", slot, 1)
	end))
	z(UI.button(detail, "DROP ALL", { LayoutOrder = 5, Size = UDim2.new(1, 0, 0, 30) }, function()
		C.send("InvDrop", slot, sel.n)
	end))
	-- Give to nearby crew
	local myRoot = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	local any = false
	for _, other in ipairs(Players:GetPlayers()) do
		local r = other ~= player and other.Character and other.Character:FindFirstChild("HumanoidRootPart")
		if r and myRoot and (r.Position - myRoot.Position).Magnitude < 14 then
			any = true
			z(UI.button(detail, "GIVE → " .. other.DisplayName, { LayoutOrder = 10, Size = UDim2.new(1, 0, 0, 30), TextColor3 = col.Teal }, function()
				C.send("InvGive", slot, other.UserId)
			end))
		end
	end
	if not any then
		z(UI.label(detail, "Stand next to a crew mate to give items.", { LayoutOrder = 11, Size = UDim2.new(1, 0, 0, 30), TextWrapped = true, TextSize = 11, TextColor3 = col.Dim }))
	end
end

function Panels.beginDrag(slot, def, input)
	drag = { slot = slot, def = def, start = Panels.pointer(input), moved = false, ghost = nil }
end

local function slotAt(pos)
	if not Panels.slotFrames then
		return nil
	end
	for i, f in pairs(Panels.slotFrames) do
		if f.Parent then
			local p, s = f.AbsolutePosition, f.AbsoluteSize
			if pos.X >= p.X and pos.X <= p.X + s.X and pos.Y >= p.Y and pos.Y <= p.Y + s.Y then
				return i
			end
		end
	end
	return nil
end

-- Pointer position in the same space as GuiObject.AbsolutePosition (MainUI does not ignore the inset).
local function pointer(input)
	if input and input.UserInputType == Enum.UserInputType.Touch then
		return Vector2.new(input.Position.X, input.Position.Y)
	end
	local m = UserInputService:GetMouseLocation()
	return m - Vector2.new(0, game:GetService("GuiService"):GetGuiInset().Y)
end
Panels.pointer = pointer

function Panels.hookDrag()
	UserInputService.InputChanged:Connect(function(input)
		if not drag then
			return
		end
		if input.UserInputType ~= Enum.UserInputType.MouseMovement and input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end
		local pos = pointer(input)
		if not drag.moved and drag.def and (pos - drag.start).Magnitude > 8 then
			drag.moved = true
			drag.ghost = UI.new("Frame", { Size = UDim2.new(0, 40, 0, 40), AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = drag.def.color or col.Dim, BackgroundTransparency = 0.2, ZIndex = 60 }, C.gui)
			UI.corner(drag.ghost, 4)
			UI.label(drag.ghost, drag.def.short, { Size = UDim2.new(1, 0, 1, 0), TextXAlignment = Enum.TextXAlignment.Center, Font = UI.Bold, TextSize = 10, ZIndex = 61 })
		end
		if drag.ghost then
			local scale = C.uiScale.Scale
			drag.ghost.Position = UDim2.new(0, pos.X / scale, 0, pos.Y / scale)
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if not drag then
			return
		end
		if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end
		local d = drag
		drag = nil
		if d.ghost then
			d.ghost:Destroy()
		end
		if not d.moved then
			Panels.selected = d.slot
			Panels.refresh("Inventory")
			return
		end
		local target = slotAt(pointer(input))
		if target and target ~= d.slot then
			C.send("InvMove", d.slot, target)
			Panels.selected = target
		elseif not target then
			local p, s = Panels.root.AbsolutePosition, Panels.root.AbsoluteSize
			local at = pointer(input)
			local outside = at.X < p.X or at.X > p.X + s.X or at.Y < p.Y or at.Y > p.Y + s.Y
			if outside then
				local item = nil
				for _, slot in ipairs(C.inventory.slots) do
					if slot.i == d.slot then
						item = slot
					end
				end
				if item then
					C.send("InvDrop", d.slot, item.n)
				end
			end
		end
	end)
end

------------------------------------------------------------------------------
-- CRAFT
------------------------------------------------------------------------------
builders.Craft = {
	title = function()
		return "CRAFTING BENCH"
	end,
}
function builders.Craft.build(body)
	UI.label(body, "Crafting only works next to a Crafting Bench (Workshop, Living Quarters). Materials are checked by the server.", { Size = UDim2.new(1, 0, 0, 18), TextSize = 12, TextColor3 = col.Dim, ZIndex = 11, TextTruncate = Enum.TextTruncate.AtEnd })
	local list = UI.scroll(body, { Position = UDim2.new(0, 0, 0, 24), Size = UDim2.new(1, 0, 1, -24), ZIndex = 10 })
	UI.list(list, 6)
	local tech = C.profile.Tech or {}
	for i, r in ipairs(Recipes.List) do
		local def = Items.get(r.out)
		local rw = row(list, i, 56)
		UI.new("Frame", { Position = UDim2.new(0, 10, 0.5, -14), Size = UDim2.new(0, 28, 0, 28), BackgroundColor3 = def.color or col.Dim, BorderSizePixel = 0, ZIndex = 11 }, rw)
		UI.label(rw, def.name .. (r.count > 1 and (" x" .. r.count) or ""), { Position = UDim2.new(0, 48, 0, 6), Size = UDim2.new(1, -170, 0, 20), Font = UI.Bold, TextSize = 14, ZIndex = 11 })
		local locked = r.tech and not tech[r.tech]
		local info = locked and ('<font color="#E0584A">LOCKED — research ' .. r.tech .. "</font>") or costRich(r.cost)
		UI.label(rw, info, { Position = UDim2.new(0, 48, 0, 28), Size = UDim2.new(1, -170, 0, 18), TextSize = 11, RichText = true, ZIndex = 11, TextTruncate = Enum.TextTruncate.AtEnd })
		local b = UI.button(rw, "CRAFT", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 0), Size = UDim2.new(0, 100, 0, 34), ZIndex = 11 }, function()
			C.send("Craft", r.id)
		end)
		UI.setEnabled(b, not locked and canAfford(r.cost))
	end
end

------------------------------------------------------------------------------
-- BUILD
------------------------------------------------------------------------------
builders.Build = {
	title = function()
		return "BUILD"
	end,
}
function builders.Build.build(body)
	local hint = C.Build.touch and "Aim at the deck with the screen centre. PLACE / ROTATE / CANCEL buttons." or "Mouse to aim · Click to place · R rotate · X cancel. Green preview = valid."
	UI.label(body, hint, { Size = UDim2.new(1, 0, 0, 18), TextSize = 12, TextColor3 = col.Dim, ZIndex = 11 })
	local list = UI.scroll(body, { Position = UDim2.new(0, 0, 0, 24), Size = UDim2.new(1, 0, 1, -24), ZIndex = 10 })
	UI.list(list, 6)
	local tech = C.profile.Tech or {}
	for i, b in ipairs(Buildables.List) do
		local rw = row(list, i, 58)
		UI.label(rw, b.name, { Position = UDim2.new(0, 12, 0, 5), Size = UDim2.new(1, -150, 0, 20), Font = UI.Bold, TextSize = 14, ZIndex = 11 })
		local locked = b.tech and not tech[b.tech]
		local info = locked and ('<font color="#E0584A">LOCKED — research ' .. b.tech .. "</font>") or costRich(b.cost)
		UI.label(rw, info, { Position = UDim2.new(0, 12, 0, 24), Size = UDim2.new(1, -150, 0, 16), TextSize = 11, RichText = true, ZIndex = 11, TextTruncate = Enum.TextTruncate.AtEnd })
		UI.label(rw, b.desc, { Position = UDim2.new(0, 12, 0, 39), Size = UDim2.new(1, -150, 0, 14), TextSize = 10, TextColor3 = col.Dim, ZIndex = 11, TextTruncate = Enum.TextTruncate.AtEnd })
		local btn = UI.button(rw, "BUILD", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 0), Size = UDim2.new(0, 110, 0, 36), ZIndex = 11 }, function()
			Panels.close()
			C.Build.start(b.id)
		end)
		UI.setEnabled(btn, not locked)
	end
end

------------------------------------------------------------------------------
-- POWER
------------------------------------------------------------------------------
builders.Power = {
	title = function()
		return "POWER MANAGEMENT  //  E-01"
	end,
}
function builders.Power.build(body)
	local S = C.state
	local top = UI.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 118), ZIndex = 10 }, body)
	Panels.powerStatus = UI.label(top, "", { Size = UDim2.new(1, 0, 0, 20), Font = UI.Black, TextSize = 16, ZIndex = 11 })
	local bars = UI.new("Frame", { BackgroundTransparency = 1, Position = UDim2.new(0, 0, 0, 24), Size = UDim2.new(0.55, 0, 0, 66), ZIndex = 10 }, top)
	UI.list(bars, 2)
	Panels.pBars = {
		fuel = UI.bar(bars, "FUEL", col.Amber, { LayoutOrder = 1 }),
		hp = UI.bar(bars, "HP", col.Red, { LayoutOrder = 2 }),
		load = UI.bar(bars, "LOAD", col.Green, { LayoutOrder = 3 }),
	}
	for _, b in pairs(Panels.pBars) do
		z(b.frame)
		b.frame.Size = UDim2.new(1, 0, 0, 20)
		b.value.Size = UDim2.new(0, 70, 1, 0)
		b.value.Position = UDim2.new(1, -70, 0, 0)
		b.fill.Parent.Size = UDim2.new(1, -122, 0, 8)
	end
	Panels.overload = UI.label(top, "", { Position = UDim2.new(0, 0, 0, 94), Size = UDim2.new(1, 0, 0, 20), Font = UI.Bold, TextSize = 13, TextColor3 = col.Red, ZIndex = 11 })
	local actions = UI.new("Frame", { BackgroundTransparency = 1, Position = UDim2.new(0.58, 0, 0, 24), Size = UDim2.new(0.42, 0, 0, 66), ZIndex = 10 }, top)
	UI.new("UIGridLayout", { CellSize = UDim2.new(1, 0, 0, 20), CellPadding = UDim2.new(0, 0, 0, 3) }, actions)
	z(UI.button(actions, "REFUEL  (Fuel Can → +25)", { TextSize = 11 }, function()
		C.send("Refuel")
	end))
	z(UI.button(actions, "INSTALL UPGRADE", { TextSize = 11 }, function()
		C.send("UpgradeGenerator")
	end))
	z(UI.button(actions, "REPAIR E-01", { TextSize = 11 }, function()
		local gen = workspace:FindFirstChild("Interactables") and workspace.Interactables:FindFirstChild("Generator")
		if gen then
			C.send("InspectRepair", gen)
		end
	end))

	local list = UI.scroll(body, { Position = UDim2.new(0, 0, 0, 124), Size = UDim2.new(1, 0, 1, -124), ZIndex = 10 })
	UI.list(list, 4)
	Panels.consumerRows = {}
	for i, c in ipairs(Config.Consumers) do
		local rw = row(list, i, 40)
		UI.label(rw, c.name, { Position = UDim2.new(0, 12, 0, 0), Size = UDim2.new(0, 110, 1, 0), Font = UI.Black, TextSize = 14, ZIndex = 11 })
		UI.label(rw, tostring(c.demand), { Position = UDim2.new(0, 120, 0, 0), Size = UDim2.new(0, 40, 1, 0), Font = UI.Mono, TextSize = 14, TextColor3 = col.Amber, ZIndex = 11 })
		local status = UI.label(rw, "", { Position = UDim2.new(0, 166, 0, 0), Size = UDim2.new(1, -290, 1, 0), TextSize = 11, TextColor3 = col.Dim, ZIndex = 11, TextTruncate = Enum.TextTruncate.AtEnd })
		local toggle = UI.button(rw, "OFF", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -8, 0.5, 0), Size = UDim2.new(0, 100, 0, 28), ZIndex = 11 }, function()
			C.send("Grid", c.id, not (S:GetAttribute("Grid_" .. c.id) == true))
		end)
		Panels.consumerRows[c.id] = { status = status, toggle = toggle, def = c }
	end
	builders.Power.refresh()
end

function builders.Power.refresh()
	if not Panels.consumerRows then
		return
	end
	local S = C.state
	local online = S:GetAttribute("GenOnline") == true
	local fuel = S:GetAttribute("GenFuel") or 0
	local tank = S:GetAttribute("GenTank") or 100
	local hp = S:GetAttribute("GenHealth") or 0
	local cap = S:GetAttribute("PowerCapacity") or 100
	local demand = S:GetAttribute("PowerDemand") or 0
	Panels.powerStatus.Text = string.format("GENERATOR %s  ·  LEVEL %d  ·  POWER AVAILABLE: %d", online and "ONLINE" or "OFFLINE", S:GetAttribute("GenLevel") or 1, cap)
	Panels.powerStatus.TextColor3 = online and col.Green or col.Red
	Panels.pBars.fuel.set(fuel, tank, string.format("%d/%d", math.floor(fuel), tank))
	Panels.pBars.hp.set(hp, 100, string.format("%d/100", math.floor(hp)))
	Panels.pBars.load.set(demand, cap, string.format("%d/%d", demand, cap))
	Panels.pBars.load.fill.BackgroundColor3 = demand > cap and col.Red or col.Green
	if demand > cap then
		Panels.overload.Text = string.format("⚠ OVERLOAD %d / %d — breaker trips in %d s. Switch something off!", demand, cap, S:GetAttribute("OverloadTime") or 0)
	elseif S:GetAttribute("Tripped") then
		Panels.overload.Text = "⚠ GRID TRIPPED — power returns in a few seconds."
	else
		Panels.overload.Text = ""
	end
	for id, r in pairs(Panels.consumerRows) do
		local on = S:GetAttribute("Grid_" .. id) == true
		local powered = S:GetAttribute("Pow_" .. id) == true
		local ok = S:GetAttribute("Ok_" .. id) ~= false
		r.toggle.Text = on and "ON" or "OFF"
		r.toggle.TextColor3 = on and col.Green or col.Dim
		local status
		if not ok then
			status = "MACHINE BROKEN — repair it"
		elseif powered then
			status = "POWERED · " .. r.def.desc
		elseif on then
			status = "NO POWER"
		else
			status = r.def.desc
		end
		if id == "Pumps" and not S:GetAttribute("Drained") then
			status = string.format("DRAINED %d%% · ", S:GetAttribute("PumpProgress") or 0) .. status
		end
		r.status.Text = status
		r.status.TextColor3 = (not ok) and col.Red or (powered and col.Green or col.Dim)
	end
end

------------------------------------------------------------------------------
-- REPAIR
------------------------------------------------------------------------------
builders.Repair = {
	title = function(d)
		return "REPAIR  //  " .. (d and d.name or "")
	end,
}
function builders.Repair.build(body, d)
	if not d then
		return
	end
	local health = d.target and d.target.Parent and d.target:GetAttribute("Health") or d.health
	z(UI.label(body, d.name, { Size = UDim2.new(1, 0, 0, 26), Font = UI.Black, TextSize = 22, TextColor3 = col.Amber }))
	z(UI.label(body, "HEALTH:", { Position = UDim2.new(0, 0, 0, 34), Size = UDim2.new(0, 120, 0, 20), Font = UI.Bold, TextSize = 13, TextColor3 = col.Dim }))
	local bar = UI.bar(body, "", col.Green, { Position = UDim2.new(0, 0, 0, 56), Size = UDim2.new(1, 0, 0, 22) })
	z(bar.frame)
	bar.label.Size = UDim2.new(0, 0, 1, 0)
	bar.fill.Parent.Position = UDim2.new(0, 0, 0.5, -5)
	bar.fill.Parent.Size = UDim2.new(1, -110, 0, 10)
	bar.value.Size = UDim2.new(0, 100, 1, 0)
	bar.value.Position = UDim2.new(1, -100, 0, 0)
	bar.value.TextSize = 16
	bar.set(health, d.max, string.format("%d / %d", math.floor(health), d.max))
	z(UI.label(body, "REQUIRED:", { Position = UDim2.new(0, 0, 0, 90), Size = UDim2.new(1, 0, 0, 20), Font = UI.Bold, TextSize = 13, TextColor3 = col.Dim }))
	local y = 114
	local affordable = true
	for _, id in ipairs(Items.Order) do
		local need = d.cost[id]
		if need then
			local have = d.have[id] or countOf(id)
			if have < need then
				affordable = false
			end
			z(UI.label(body, string.format("%s x%d   (you have %d)", Items.name(id), need, have), { Position = UDim2.new(0, 12, 0, y), Size = UDim2.new(1, 0, 0, 20), TextSize = 15, Font = UI.Mono, TextColor3 = have >= need and col.Green or col.Red }))
			y += 22
		end
	end
	if d.heavy then
		z(UI.label(body, d.hasToolkit and "Heavy machinery — Toolkit: OK" or "Heavy machinery — requires a TOOLKIT", { Position = UDim2.new(0, 12, 0, y + 4), Size = UDim2.new(1, 0, 0, 20), TextSize = 13, TextColor3 = d.hasToolkit and col.Green or col.Red }))
		y += 24
	end
	local full = health >= d.max
	local rb = z(UI.button(body, full and "FULLY REPAIRED" or "REPAIR", { Position = UDim2.new(0, 0, 1, -44), Size = UDim2.new(0.5, -6, 0, 40), TextSize = 16 }, function()
		C.send("Repair", d.target, false)
	end))
	UI.setEnabled(rb, not full and affordable)
	local kb = z(UI.button(body, string.format("USE REPAIR KIT (+50)  x%d", d.kits or 0), { Position = UDim2.new(0.5, 6, 1, -44), Size = UDim2.new(0.5, -6, 0, 40), TextSize = 13 }, function()
		C.send("Repair", d.target, true)
	end))
	UI.setEnabled(kb, not full and (d.kits or 0) > 0)
end

------------------------------------------------------------------------------
-- CARGO
------------------------------------------------------------------------------
builders.Cargo = {
	title = function()
		return "MOTORBOAT  //  CARGO"
	end,
}
function builders.Cargo.build(body, d)
	if not d then
		return
	end
	z(UI.label(body, string.format("FUEL %d / %d   ·   HULL %d / %d   ·   cargo %d / %d stacks", math.floor(d.fuel), d.fuelMax, math.floor(d.health), d.maxHealth, #d.cargo, d.slots), { Size = UDim2.new(1, 0, 0, 20), Font = UI.Mono, TextSize = 13, TextColor3 = col.Teal }))
	local left = UI.scroll(body, { Position = UDim2.new(0, 0, 0, 50), Size = UDim2.new(0.5, -6, 1, -50), ZIndex = 10 })
	UI.list(left, 4)
	local right = UI.scroll(body, { Position = UDim2.new(0.5, 6, 0, 50), Size = UDim2.new(0.5, -6, 1, -50), ZIndex = 10 })
	UI.list(right, 4)
	z(UI.label(body, "BOAT CARGO — click to take", { Position = UDim2.new(0, 0, 0, 26), Size = UDim2.new(0.5, 0, 0, 18), Font = UI.Bold, TextSize = 12, TextColor3 = col.Dim }))
	z(UI.label(body, "YOUR ITEMS — click to load", { Position = UDim2.new(0.5, 6, 0, 26), Size = UDim2.new(0.5, 0, 0, 18), Font = UI.Bold, TextSize = 12, TextColor3 = col.Dim }))
	for k, c in ipairs(d.cargo) do
		z(UI.button(left, Items.name(c.id) .. "  x" .. c.n, { LayoutOrder = k, Size = UDim2.new(1, -8, 0, 32), TextSize = 12, TextColor3 = col.Text }, function()
			C.send("CargoTake", d.boat, c.i)
		end))
	end
	for k, s in ipairs(C.inventory.slots) do
		z(UI.button(right, Items.name(s.id) .. "  x" .. s.n, { LayoutOrder = k, Size = UDim2.new(1, -8, 0, 32), TextSize = 12, TextColor3 = col.Text }, function()
			C.send("CargoDeposit", d.boat, s.i)
		end))
	end
end

------------------------------------------------------------------------------
-- RESEARCH
------------------------------------------------------------------------------
builders.Research = {
	title = function()
		return "RESEARCH TERMINAL"
	end,
}
function builders.Research.build(body)
	z(UI.label(body, "Research is shared with the whole crew and saved to every profile.", { Size = UDim2.new(1, 0, 0, 18), TextSize = 12, TextColor3 = col.Dim }))
	local list = UI.scroll(body, { Position = UDim2.new(0, 0, 0, 24), Size = UDim2.new(1, 0, 1, -24), ZIndex = 10 })
	UI.list(list, 6)
	local tech = C.profile.Tech or {}
	for i, t in ipairs(Recipes.Tech) do
		local rw = row(list, i, 58)
		UI.label(rw, t.name, { Position = UDim2.new(0, 12, 0, 5), Size = UDim2.new(1, -150, 0, 20), Font = UI.Bold, TextSize = 14, ZIndex = 11 })
		UI.label(rw, t.desc, { Position = UDim2.new(0, 12, 0, 24), Size = UDim2.new(1, -150, 0, 14), TextSize = 11, TextColor3 = col.Dim, ZIndex = 11 })
		UI.label(rw, costRich(t.cost), { Position = UDim2.new(0, 12, 0, 39), Size = UDim2.new(1, -150, 0, 14), TextSize = 11, RichText = true, ZIndex = 11 })
		local done = tech[t.id] == true
		local b = UI.button(rw, done and "DONE" or "RESEARCH", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 0), Size = UDim2.new(0, 110, 0, 36), ZIndex = 11 }, function()
			C.send("Research", t.id)
		end)
		UI.setEnabled(b, not done and canAfford(t.cost))
	end
end

------------------------------------------------------------------------------
-- LOG
------------------------------------------------------------------------------
builders.Log = {
	title = function(d)
		if d and d.id and Story.Logs[d.id] then
			return Story.Logs[d.id].title
		end
		return d and d.title or "LOG"
	end,
}
function builders.Log.build(body, d)
	local text = d and d.text or ""
	if d and d.id and Story.Logs[d.id] then
		text = Story.Logs[d.id].text
	end
	z(UI.label(body, text, { Size = UDim2.new(1, 0, 1, -50), TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top, Font = UI.Mono, TextSize = 16 }))
	z(UI.button(body, "CLOSE", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, 0), Size = UDim2.new(0, 160, 0, 36) }, function()
		Panels.close()
	end))
end

------------------------------------------------------------------------------
-- SETTINGS
------------------------------------------------------------------------------
builders.Settings = {
	title = function()
		return "SETTINGS"
	end,
}
function builders.Settings.build(body)
	local list = UI.scroll(body, { Size = UDim2.new(1, 0, 1, 0), ZIndex = 10 })
	UI.list(list, 6)
	local st = C.settings
	local function toggle(order, key, label)
		local rw = row(list, order, 40)
		UI.label(rw, label, { Position = UDim2.new(0, 12, 0, 0), Size = UDim2.new(1, -140, 1, 0), TextSize = 14, ZIndex = 11 })
		UI.button(rw, st[key] and "ON" or "OFF", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -8, 0.5, 0), Size = UDim2.new(0, 100, 0, 28), ZIndex = 11, TextColor3 = st[key] and col.Green or col.Dim }, function()
			st[key] = not st[key]
			C.applySettings(true)
			Panels.refresh("Settings")
		end)
	end
	toggle(1, "Rain", "Rain particles")
	toggle(2, "DepthOfField", "Depth of field")
	toggle(3, "Bloom", "Bloom")
	toggle(4, "Shadows", "Global shadows")
	toggle(5, "ScreenFilter", "Horror screen filter")
	local scaleRow = row(list, 6, 40)
	UI.label(scaleRow, string.format("UI scale  %.1f", st.UIScale), { Position = UDim2.new(0, 12, 0, 0), Size = UDim2.new(1, -140, 1, 0), TextSize = 14, ZIndex = 11 })
	UI.button(scaleRow, "–", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -60, 0.5, 0), Size = UDim2.new(0, 44, 0, 28), ZIndex = 11 }, function()
		st.UIScale = math.max(0.7, st.UIScale - 0.1)
		C.applySettings(true)
		Panels.refresh("Settings")
	end)
	UI.button(scaleRow, "+", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -8, 0.5, 0), Size = UDim2.new(0, 44, 0, 28), ZIndex = 11 }, function()
		st.UIScale = math.min(1.3, st.UIScale + 0.1)
		C.applySettings(true)
		Panels.refresh("Settings")
	end)
	-- Cosmetics
	local suits = row(list, 7, 76)
	UI.label(suits, "SUIT (cosmetic, unlocked by achievements)", { Position = UDim2.new(0, 12, 0, 4), Size = UDim2.new(1, -20, 0, 18), TextSize = 12, TextColor3 = col.Dim, ZIndex = 11 })
	local holder = UI.new("Frame", { BackgroundTransparency = 1, Position = UDim2.new(0, 12, 0, 26), Size = UDim2.new(1, -24, 0, 40), ZIndex = 10 }, suits)
	UI.new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6) }, holder)
	local owned = C.profile.Cosmetics or {}
	for _, id in ipairs({ "Suit_Standard", "Suit_Night", "Suit_Hazard", "Suit_Deep", "Suit_Rescue" }) do
		local name = string.upper(string.gsub(id, "Suit_", ""))
		local b = UI.button(holder, name, { Size = UDim2.new(0, 100, 0, 36), TextSize = 11, ZIndex = 11, TextColor3 = C.profile.Suit == id and col.Green or col.Amber }, function()
			C.send("Suit", id)
		end)
		UI.setEnabled(b, owned[id] == true)
	end
	-- Progress
	local stats = C.profile.Stats or {}
	local ach = 0
	for _ in pairs(C.profile.Achievements or {}) do
		ach += 1
	end
	local info = row(list, 8, 44)
	UI.label(info, string.format("Credits %d · Achievements %d · Nights survived %d · Best day %d · Deaths %d%s", C.profile.Credits or 0, ach, stats.Nights or 0, stats.BestDay or 0, stats.Deaths or 0, C.profile.CanSave == false and "  (not saving this session)" or ""), { Position = UDim2.new(0, 12, 0, 0), Size = UDim2.new(1, -20, 1, 0), TextSize = 12, TextWrapped = true, ZIndex = 11 })
	-- Host world reset
	if player.UserId == C.state:GetAttribute("HostId") then
		local rr = row(list, 9, 44)
		UI.label(rr, "Restart this world from DAY 1 (host only)", { Position = UDim2.new(0, 12, 0, 0), Size = UDim2.new(1, -160, 1, 0), TextSize = 13, ZIndex = 11 })
		local armed = false
		local rb
		rb = UI.button(rr, "RESET WORLD", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -8, 0.5, 0), Size = UDim2.new(0, 140, 0, 30), ZIndex = 11, TextColor3 = col.Red }, function()
			if not armed then
				armed = true
				rb.Text = "CONFIRM RESET"
				return
			end
			C.send("ResetWorld")
			Panels.close()
		end)
	end
end

------------------------------------------------------------------------------
-- SUPPORT
------------------------------------------------------------------------------
builders.Support = {
	title = function()
		return "SUPPORT THE CREW"
	end,
}
function builders.Support.build(body)
	local list = UI.scroll(body, { Size = UDim2.new(1, 0, 1, 0), ZIndex = 10 })
	UI.list(list, 8)
	UI.label(list, "If THE RIG kept you up at night, you can say thanks here.\nIt buys nothing in the game: no items, no credits, no advantage.", { LayoutOrder = 1, Size = UDim2.new(1, -8, 0, 44), TextWrapped = true, TextSize = 14, TextColor3 = col.Dim, ZIndex = 11 })
	local offered = 0
	for i, tier in ipairs(Config.Donate) do
		if tier.id ~= 0 then
			offered += 1
			local rw = row(list, 1 + i, 58)
			Icons.show(rw, "RareMaterials", { Position = UDim2.fromOffset(10, 6), Size = UDim2.fromOffset(46, 46), ZIndex = 12 })
			UI.label(rw, tier.label, { Position = UDim2.new(0, 66, 0, 0), Size = UDim2.new(1, -210, 1, 0), Font = UI.Bold, TextSize = 15, ZIndex = 11 })
			UI.button(rw, "R$ " .. tier.robux, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 0), Size = UDim2.new(0, 124, 0, 38), TextSize = 15, ZIndex = 11 }, function()
				MarketplaceService:PromptProductPurchase(Players.LocalPlayer, tier.id)
			end)
		end
	end
	if offered == 0 then
		UI.label(list, "STUDIO: no donation tiers yet. Create Developer Products on the Creator Dashboard and put their ids in ReplicatedStorage.Modules.Config, Config.Donate. Players will not see this panel until you do.", { LayoutOrder = 10, Size = UDim2.new(1, -8, 0, 64), TextWrapped = true, TextSize = 13, Font = UI.Mono, TextColor3 = col.Amber, ZIndex = 11 })
	end
end

------------------------------------------------------------------------------
-- HOW TO PLAY
------------------------------------------------------------------------------
builders.Help = {
	title = function()
		return "HOW TO SURVIVE"
	end,
}
function builders.Help.build(body)
	local text = table.concat({
		"GOAL — survive 100 days on the rig KESTREL-9 and learn what happened here.",
		"DAY (06-18) — search containers (E), bring Fuel to generator E-01, repair it (R), unlock rooms.",
		"EVENING (18-21) — refuel, close doors, switch LIGHTS on at a power console.",
		"UNDER THE DECK — service tunnels run from the underdeck walkways out to every outer deck and down to the boat dock. The lamps are old. Some are dead.",
		"NIGHT (21-06) — Climbers climb the legs. They fear floodlights and flares, break doors and attack E-01. Hold RIGHT MOUSE to focus your flashlight: the hot beam burns them. It never runs out.",
		"FOOD & FUEL — craft a Fishing Rod and fish at FISHING spots (not at night). Repair the CRUDE EXTRACTOR (south-west deck) and power PUMPS: it refines 1 Fuel Can per minute. Rain Collectors (build menu) fill water while it rains.",
		"THE SEA — the ocean is 8 km across. Upgrade the boat at the dock console (R engine, T tank) and refuel at the three RELAY BUOYS. Story leads open on later days (J).",
		"POWER — more systems than power: pick what to run. Overload trips the breaker.",
		"",
		"CONTROLS — WASD move · Shift sprint · E interact · R repair · 1-6 hotbar · Click use item · F flashlight (left hand) · hold RMB focus beam",
		"TAB inventory · C crafting · B build (R rotate, X cancel) · P power · Q menu · J expedition journal",
		"Boat — sit at the helm, WASD to drive. Refuel it with Fuel Cans. Cargo box stores loot.",
		"Diving — Oxygen drains underwater. Oxygen Tank / Diving Gear let you go deeper.",
	}, "\n")
	z(UI.label(body, text, { Size = UDim2.new(1, 0, 1, 0), TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top, TextSize = 14 }))
end


------------------------------------------------------------------------------
-- EXPEDITION JOURNAL: chapter progression and selectable navigation destinations.
------------------------------------------------------------------------------
builders.Journal = {title=function()return "EXPEDITION JOURNAL  /  KESTREL-9" end}
function builders.Journal.build(body)
	local done=C.state:GetAttribute("StoryCompleted") or 0
	local chapter=Expeditions.Chapters[done+1]
	local list=UI.scroll(body,{Size=UDim2.fromScale(1,1),ZIndex=10})
	UI.list(list,10)
	local card=row(list,1,210)
	UI.label(card,chapter and chapter.title or "THE TRUTH IS OUT",{Position=UDim2.fromOffset(14,10),Size=UDim2.new(1,-28,0,24),Font=UI.Bold,TextSize=18,TextColor3=col.Amber,ZIndex=11})
	local lockedUntil=C.state:GetAttribute("StoryLockedUntil") or 0
	local brief=chapter and chapter.brief
	if brief and lockedUntil>0 then brief=string.format("[ OPENS ON DAY %d ]  ",lockedUntil)..brief end
	UI.label(card,brief or "Aldmere received the recordings and the real coordinates. Survive until the day-100 rescue to bring the crew home.",{Position=UDim2.fromOffset(14,44),Size=UDim2.new(1,-28,0,88),TextWrapped=true,TextYAlignment=Enum.TextYAlignment.Top,TextSize=14,TextColor3=col.Dim,ZIndex=11})
	local progress=string.format("CHAPTERS %d / %d",done,#Expeditions.Chapters)
	if C.state:GetAttribute("StoryTransmitting") then progress..=string.format("  ·  UPLOAD %d%%  %s",C.state:GetAttribute("StoryUpload") or 0,C.state:GetAttribute("StoryUploadPaused") and "PAUSED" or "TRANSMITTING") end
	UI.label(card,progress,{Position=UDim2.fromOffset(14,136),Size=UDim2.new(1,-28,0,20),TextSize=11,Font=UI.Mono,TextColor3=col.Teal,ZIndex=11})
	UI.button(card,"TRACK CURRENT CHAPTER",{Position=UDim2.fromOffset(14,168),Size=UDim2.fromOffset(260,30),TextSize=11,ZIndex=11},function() C.Navigation.followStory();Panels.close() end)
	local chart=row(list,2,math.max(400,70+#Expeditions.Destinations*22))
	local mapSize=Config.OceanHalfSize*2
	UI.label(chart,"OFFSHORE CHART / NORTH UP",{Position=UDim2.fromOffset(14,8),Size=UDim2.new(1,-28,0,18),TextSize=11,Font=UI.Mono,TextColor3=col.Teal,ZIndex=11})
	local sea=UI.frame(chart,{Position=UDim2.fromOffset(14,34),Size=UDim2.fromOffset(278,278),BackgroundColor3=Color3.fromRGB(8,25,35),ZIndex=11})
	for i=1,3 do
		UI.frame(sea,{Position=UDim2.fromScale(i/4,0),Size=UDim2.new(0,1,1,0),BackgroundColor3=col.Stroke,BackgroundTransparency=.5,ZIndex=12})
		UI.frame(sea,{Position=UDim2.fromScale(0,i/4),Size=UDim2.new(1,0,0,1),BackgroundColor3=col.Stroke,BackgroundTransparency=.5,ZIndex=12})
	end
	for i,destination in ipairs(Expeditions.Destinations) do
		local v=destination.position
		UI.button(sea,tostring(i),{AnchorPoint=Vector2.new(.5,.5),Position=UDim2.fromScale(.5+v.X/mapSize,.5+v.Z/mapSize),Size=UDim2.fromOffset(20,20),TextSize=11,ZIndex=13},function() C.Navigation.set(destination.name,destination.position);Panels.close() end)
		UI.label(chart,tostring(i).." / "..destination.name,{Position=UDim2.fromOffset(310,34+(i-1)*22),Size=UDim2.new(1,-322,0,20),TextWrapped=true,TextSize=10,TextColor3=col.Dim,ZIndex=11})
	end
	UI.label(chart,string.format("%d x %d STUDS / refuel at relay buoys / board at the low jetties / J returns here",mapSize,mapSize),{Position=UDim2.fromOffset(14,318),Size=UDim2.new(1,-322,0,46),TextWrapped=true,TextSize=10,Font=UI.Mono,TextColor3=col.Teal,ZIndex=11})
	UI.label(list,"CLICK A DESTINATION TO SET YOUR BEARING",{LayoutOrder=3,Size=UDim2.new(1,-8,0,24),TextSize=11,Font=UI.Mono,TextColor3=col.Teal,ZIndex=11})
	for i,destination in ipairs(Expeditions.Destinations) do
		local r=row(list,3+i,70)
		UI.label(r,destination.name,{Position=UDim2.fromOffset(12,6),Size=UDim2.new(1,-150,0,22),Font=UI.Bold,TextSize=13,ZIndex=11})
		UI.label(r,destination.note,{Position=UDim2.fromOffset(12,30),Size=UDim2.new(1,-150,0,34),TextSize=11,TextWrapped=true,TextColor3=col.Dim,ZIndex=11})
		UI.button(r,"SET ROUTE",{AnchorPoint=Vector2.new(1,.5),Position=UDim2.new(1,-12,.5,0),Size=UDim2.fromOffset(112,34),TextSize=11,ZIndex=11},function() C.Navigation.set(destination.name,destination.position);Panels.close() end)
	end
	UI.label(list,"RECOVERED RECORDINGS",{LayoutOrder=20,Size=UDim2.new(1,-8,0,24),TextSize=11,Font=UI.Mono,TextColor3=col.Teal,ZIndex=11})
	for i=1,done do
		local entry=Expeditions.Chapters[i]
		local r=row(list,20+i,126)
		UI.label(r,entry.title,{Position=UDim2.fromOffset(12,6),Size=UDim2.new(1,-24,0,24),Font=UI.Bold,TextSize=13,TextColor3=col.Amber,ZIndex=11})
		UI.label(r,entry.reveal,{Position=UDim2.fromOffset(12,34),Size=UDim2.new(1,-24,0,80),TextWrapped=true,TextYAlignment=Enum.TextYAlignment.Top,TextSize=13,ZIndex=11})
	end
end

------------------------------------------------------------------------------
-- MAIN MENU (full-screen overlay)
------------------------------------------------------------------------------
function Panels.buildMenu()
	local menu = UI.frame(C.gui, {Name="MainMenu",Size=UDim2.fromScale(1,1),BackgroundColor3=col.Bg,BackgroundTransparency=.07,ZIndex=30})
	UI.new("UIGradient", {Rotation=25,Color=ColorSequence.new(col.Bg,Color3.fromRGB(29,51,59))},menu)
	local box = UI.new("Frame", {BackgroundTransparency=1,AnchorPoint=Vector2.new(.5,.5),Position=UDim2.fromScale(.5,.5),Size=UDim2.fromOffset(1080,560),ZIndex=31},menu)
	UI.label(box,"K E S T R E L – 9  /  NORTH ATLANTIC",{Size=UDim2.fromOffset(510,20),TextSize=11,Font=UI.Mono,TextColor3=col.Teal,ZIndex=31})
	UI.label(box,"THE RIG",{Position=UDim2.fromOffset(-4,32),Size=UDim2.fromOffset(600,106),Font=UI.Black,TextSize=96,ZIndex=31})
	UI.label(box,"100 DAYS",{Position=UDim2.fromOffset(0,139),Size=UDim2.fromOffset(510,40),Font=UI.Bold,TextSize=34,TextColor3=col.Amber,ZIndex=31})
	UI.label(box,"Keep the lights alive.",{Position=UDim2.fromOffset(0,194),Size=UDim2.fromOffset(510,30),TextSize=21,ZIndex=31})
	UI.label(box,"An abandoned platform. A failing generator.\nA crew that must hold out until rescue.",{Position=UDim2.fromOffset(0,230),Size=UDim2.fromOffset(490,48),TextSize=14,TextColor3=col.Dim,TextWrapped=true,ZIndex=31})
	local support=Panels.supportOffered()
	local play=UI.button(box,"ENTER THE RIG    →",{Position=UDim2.fromOffset(0,316),Size=UDim2.fromOffset(support and 300 or 460,58),BackgroundColor3=col.Amber,TextColor3=col.Bg,TextSize=17,ZIndex=31,Icon="Flashlight"},function() Panels.showMenu(false) end)
	if support then
		UI.button(box,"SUPPORT",{Position=UDim2.fromOffset(316,316),Size=UDim2.fromOffset(144,58),TextSize=13,TextColor3=col.Amber,ZIndex=31,Icon="RareMaterials"},function() Panels.open("Support") end)
	end
	Panels.playButton=play
	for i,spec in ipairs({{"EXPEDITIONS / J","Journal","DivingGear"},{"SETTINGS","Settings","Electronics"},{"INVENTORY","Inventory","Toolkit"}}) do
		UI.button(box,spec[1],{Position=UDim2.fromOffset((i-1)*158,386),Size=UDim2.fromOffset(144,42),TextSize=11,TextColor3=col.Text,ZIndex=31,Icon=spec[3]},function() Panels.open(spec[2]) end)
	end
	UI.label(box,"TAB  inventory     Q  return to game",{Position=UDim2.fromOffset(0,458),Size=UDim2.fromOffset(490,22),TextSize=11,Font=UI.Mono,TextColor3=col.Dim,ZIndex=31})
	Panels.menuInfo=UI.label(box,"",{Position=UDim2.fromOffset(0,504),Size=UDim2.fromOffset(510,48),TextWrapped=true,TextSize=11,Font=UI.Mono,TextColor3=col.Teal,ZIndex=31})
	local card=UI.panelBox(box,{Position=UDim2.fromOffset(600,0),Size=UDim2.fromOffset(480,560),BackgroundTransparency=.2,ZIndex=31})
	UI.label(card,"PLATFORM STATUS     /     LIVE",{Position=UDim2.fromOffset(26,22),Size=UDim2.fromOffset(430,18),Font=UI.Mono,TextSize=11,TextColor3=col.Dim,ZIndex=32})
	-- Native UI schematic: no web images, meshes or texture downloads.
	local diagram=UI.new("Frame",{Position=UDim2.fromOffset(32,74),Size=UDim2.fromOffset(416,266),BackgroundTransparency=1,ZIndex=32},card)
	for i=0,8 do UI.frame(diagram,{Position=UDim2.fromOffset(i*52,0),Size=UDim2.fromOffset(1,266),BackgroundColor3=col.Stroke,BackgroundTransparency=.7,ZIndex=32}) end
	for i=0,5 do UI.frame(diagram,{Position=UDim2.fromOffset(0,i*52),Size=UDim2.fromOffset(416,1),BackgroundColor3=col.Stroke,BackgroundTransparency=.7,ZIndex=32}) end
	for _,spec in ipairs({{28,98,126,14},{154,98,206,14},{54,112,14,144},{326,112,14,144},{180,27,16,70},{158,78,62,8},{144,124,144,7}}) do
		UI.frame(diagram,{Position=UDim2.fromOffset(spec[1],spec[2]),Size=UDim2.fromOffset(spec[3],spec[4]),BackgroundColor3=col.Teal,BackgroundTransparency=.25,ZIndex=33})
	end
	UI.label(diagram,"E–01",{Position=UDim2.fromOffset(60,62),Size=UDim2.fromOffset(60,24),TextSize=12,Font=UI.Mono,TextColor3=col.Amber,ZIndex=33})
	UI.label(diagram,"SEA LEVEL  /  −30m",{Position=UDim2.fromOffset(94,220),Size=UDim2.fromOffset(250,20),TextSize=10,Font=UI.Mono,TextColor3=col.Dim,ZIndex=33})
	Panels.menuStatus=UI.label(card,"",{Position=UDim2.fromOffset(26,364),Size=UDim2.fromOffset(430,26),Font=UI.Bold,TextSize=19,ZIndex=32})
	Panels.menuObjective=UI.label(card,"",{Position=UDim2.fromOffset(26,408),Size=UDim2.fromOffset(428,76),TextWrapped=true,TextYAlignment=Enum.TextYAlignment.Top,TextSize=15,TextColor3=col.Dim,ZIndex=32})
	UI.label(card,"SURVIVE  /  REPAIR  /  HOLD THE LIGHT",{Position=UDim2.fromOffset(26,515),Size=UDim2.fromOffset(430,20),TextSize=10,Font=UI.Mono,TextColor3=col.Amber,ZIndex=32})
	UI.label(menu,"v"..Config.Version.."  •  1–8 CREW",{AnchorPoint=Vector2.new(1,1),Position=UDim2.new(1,-24,1,-18),Size=UDim2.fromOffset(240,18),TextXAlignment=Enum.TextXAlignment.Right,TextSize=10,Font=UI.Mono,TextColor3=col.Dim,ZIndex=31})
	Panels.menu=menu
	Panels.showMenu(true)
end

function Panels.refreshMenu()
	local S=C.state
	Panels.menuInfo.Text=string.format("WORLD OF %s  /  DAY %d OF %d\n%s",string.upper(S:GetAttribute("HostName") or "CREW"),S:GetAttribute("Day") or 1,Config.MaxDays,S:GetAttribute("SessionOnly") and "LOCAL SESSION · PROGRESS IS NOT SAVED" or "COOPERATIVE SURVIVAL")
	local online=S:GetAttribute("GenOnline")==true
	Panels.menuStatus.Text=online and "E–01 / POWER ONLINE" or "E–01 / POWER OFFLINE"
	Panels.menuStatus.TextColor3=online and col.Green or col.Amber
	Panels.menuObjective.Text=S:GetAttribute("Objective") or "Restore generator E-01 before nightfall."
end

function Panels.showMenu(show)
	Panels.menu.Visible=show
	C.menuOpen=show
	if show then Panels.refreshMenu() else Panels.playButton.Text="RESUME SHIFT    →" end
	C.onPanel(show)
end

return Panels
