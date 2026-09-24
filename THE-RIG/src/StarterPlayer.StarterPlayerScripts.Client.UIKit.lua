-- StarterPlayerScripts/Client/UIKit
-- Minimal industrial-horror UI toolkit: dark translucent steel panels, amber accents,
-- monospace readouts. Every element is built from code so the whole UI is versioned.
local TweenService = game:GetService("TweenService")
local Icons = require(script.Parent.ItemIcons)

local UI = {}

UI.Colors = {
	Bg = Color3.fromRGB(8, 17, 24),
	Panel = Color3.fromRGB(13, 26, 35),
	PanelLight = Color3.fromRGB(23, 41, 51),
	Stroke = Color3.fromRGB(54, 77, 87),
	Amber = Color3.fromRGB(237, 191, 108),
	AmberDim = Color3.fromRGB(150, 110, 40),
	Red = Color3.fromRGB(222, 70, 56),
	Green = Color3.fromRGB(96, 206, 128),
	Teal = Color3.fromRGB(84, 196, 186),
	Blue = Color3.fromRGB(96, 160, 230),
	Text = Color3.fromRGB(233, 240, 237),
	Dim = Color3.fromRGB(149, 173, 181),
	Black = Color3.new(0, 0, 0),
}
local C = UI.Colors
UI.Font = Enum.Font.GothamMedium
UI.Bold = Enum.Font.GothamBold
UI.Black = Enum.Font.GothamBlack
UI.Mono = Enum.Font.RobotoMono

UI.Tones = { info = C.Teal, good = C.Green, warn = C.Amber, danger = C.Red }

function UI.new(class, props, parent)
	local o = Instance.new(class)
	for k, v in pairs(props or {}) do
		o[k] = v
	end
	o.Parent = parent
	return o
end

function UI.stroke(parent, color, thickness, transparency)
	return UI.new("UIStroke", {
		Color = color or C.Stroke,
		Thickness = thickness or 1,
		Transparency = transparency or 0,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	}, parent)
end

function UI.corner(parent, r)
	return UI.new("UICorner", { CornerRadius = UDim.new(0, r or 3) }, parent)
end

function UI.pad(parent, l, t, r, b)
	return UI.new("UIPadding", {
		PaddingLeft = UDim.new(0, l or 8),
		PaddingTop = UDim.new(0, t or l or 8),
		PaddingRight = UDim.new(0, r or l or 8),
		PaddingBottom = UDim.new(0, b or t or l or 8),
	}, parent)
end

function UI.frame(parent, props)
	local f = UI.new("Frame", {
		BackgroundColor3 = C.Panel,
		BackgroundTransparency = 0.12,
		BorderSizePixel = 0,
	}, parent)
	for k, v in pairs(props or {}) do
		f[k] = v
	end
	return f
end

function UI.panelBox(parent, props)
	local f = UI.frame(parent, props)
	UI.stroke(f)
	UI.corner(f, 8)
	return f
end

function UI.label(parent, text, props)
	local l = UI.new("TextLabel", {
		BackgroundTransparency = 1,
		Text = text or "",
		TextColor3 = C.Text,
		Font = UI.Font,
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
		TextWrapped = false,
		RichText = false,
	}, parent)
	for k, v in pairs(props or {}) do
		l[k] = v
	end
	return l
end

-- props.Icon: an item id, drawn to the left of the label.
function UI.button(parent, text, props, onClick)
	local icon = props and props.Icon
	local b = UI.new("TextButton", {
		BackgroundColor3 = C.PanelLight,
		BackgroundTransparency = 0.05,
		BorderSizePixel = 0,
		AutoButtonColor = true,
		Text = text or "",
		TextColor3 = C.Amber,
		Font = UI.Bold,
		TextSize = 14,
	}, parent)
	for k, v in pairs(props or {}) do
		if k ~= "Icon" then
			b[k] = v
		end
	end
	UI.stroke(b, C.Stroke)
	UI.corner(b, 6)
	if icon then
		b.TextXAlignment = Enum.TextXAlignment.Left
		UI.pad(b, 42, 0, 8, 0)
		Icons.show(b, icon, { Position = UDim2.new(0, -38, 0.5, -15), Size = UDim2.fromOffset(32, 30) })
	end
	if onClick then
		b.Activated:Connect(function()
			if b:GetAttribute("Enabled") ~= false then onClick() end
		end)
	end
	return b
end

function UI.setEnabled(button, enabled)
	button.AutoButtonColor = enabled
	button.TextTransparency = enabled and 0 or 0.55
	button.BackgroundTransparency = enabled and 0.05 or 0.4
	button:SetAttribute("Enabled", enabled)
end

-- Thin labelled bar. Returns {frame, fill, label, value, set(value, max, text)}.
function UI.bar(parent, labelText, color, props)
	local holder = UI.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 20) }, parent)
	for k, v in pairs(props or {}) do
		holder[k] = v
	end
	local label = UI.label(holder, labelText, {
		Size = UDim2.new(0, 44, 1, 0),
		Font = UI.Bold,
		TextSize = 12,
		TextColor3 = C.Dim,
	})
	local track = UI.new("Frame", {
		BackgroundColor3 = Color3.fromRGB(34, 38, 40),
		BorderSizePixel = 0,
		Position = UDim2.new(0, 48, 0.5, -4),
		Size = UDim2.new(1, -96, 0, 8),
	}, holder)
	UI.corner(track, 2)
	local fill = UI.new("Frame", {
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 1, 0),
	}, track)
	UI.corner(fill, 2)
	local value = UI.label(holder, "", {
		Position = UDim2.new(1, -44, 0, 0),
		Size = UDim2.new(0, 44, 1, 0),
		Font = UI.Mono,
		TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Right,
	})
	local obj = { frame = holder, fill = fill, label = label, value = value, color = color }
	function obj.set(v, max, text)
		local a = math.clamp(v / math.max(max, 1), 0, 1)
		fill.Size = UDim2.new(a, 0, 1, 0)
		value.Text = text or tostring(math.floor(v + 0.5))
		fill.BackgroundColor3 = a < 0.25 and C.Red or obj.color
	end
	return obj
end

function UI.list(parent, padding)
	return UI.new("UIListLayout", {
		Padding = UDim.new(0, padding or 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
		FillDirection = Enum.FillDirection.Vertical,
	}, parent)
end

function UI.scroll(parent, props)
	local s = UI.new("ScrollingFrame", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 5,
		ScrollBarImageColor3 = C.AmberDim,
		CanvasSize = UDim2.new(0, 0, 0, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
	}, parent)
	for k, v in pairs(props or {}) do
		s[k] = v
	end
	return s
end

function UI.clear(container)
	for _, c in ipairs(container:GetChildren()) do
		if not c:IsA("UIListLayout") and not c:IsA("UIPadding") and not c:IsA("UIGridLayout") then
			c:Destroy()
		end
	end
end

function UI.tween(obj, time, goal)
	local t = TweenService:Create(obj, TweenInfo.new(time, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), goal)
	t:Play()
	return t
end

-- Hazard-stripe accent bar for headers.
function UI.stripe(parent, color, props)
	local s = UI.new("Frame", {
		BackgroundColor3 = color or C.Amber,
		BorderSizePixel = 0,
		Size = UDim2.new(0, 3, 1, 0),
	}, parent)
	for k, v in pairs(props or {}) do
		s[k] = v
	end
	return s
end

return UI
