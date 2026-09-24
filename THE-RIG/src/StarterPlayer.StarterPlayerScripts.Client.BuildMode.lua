-- StarterPlayerScripts/Client/BuildMode
-- Transparent preview that follows the mouse (or the screen centre on touch devices).
-- Green = the local checks pass, red = something is wrong. The server re-checks everything
-- when the player places the object, so the preview is only a convenience.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Modules.Config)
local Buildables = require(ReplicatedStorage.Modules.Buildables)
local Items = require(ReplicatedStorage.Modules.Items)

local Build = { active = false, yaw = 0 }
local C, UI
local player = Players.LocalPlayer
local camera = workspace.CurrentCamera
local STEP = math.rad(15)

function Build.init(ctx)
	C = ctx
	UI = C.UI
	Build.touch = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
	local bar = UI.panelBox(C.gui, { Name = "BuildBar", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -120), Size = UDim2.new(0, 520, 0, 64), Visible = false })
	UI.pad(bar, 10, 6, 10, 6)
	Build.info = UI.label(bar, "", { Size = UDim2.new(1, 0, 0, 20), Font = UI.Bold, TextSize = 14, TextColor3 = UI.Colors.Amber })
	Build.reason = UI.label(bar, "", { Position = UDim2.new(0, 0, 0, 22), Size = UDim2.new(1, -250, 0, 28), TextSize = 12, TextWrapped = true, TextColor3 = UI.Colors.Dim })
	local function btn(x, text, fn)
		UI.button(bar, text, { AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, x, 1, 0), Size = UDim2.new(0, 76, 0, 30), TextSize = 12 }, fn)
	end
	btn(0, "CANCEL", Build.stop)
	btn(-82, "ROTATE", Build.rotate)
	btn(-164, "PLACE", Build.place)
	Build.bar = bar
	RunService.RenderStepped:Connect(Build.update)
end

function Build.start(id)
	local def = Buildables.ById[id]
	local templates = ReplicatedStorage:FindFirstChild("Assets") and ReplicatedStorage.Assets:FindFirstChild("BuildTemplates")
	local template = templates and templates:FindFirstChild(id)
	if not def or not template then
		C.HUD.toast("Build templates are still loading.", "warn")
		return
	end
	Build.stop()
	local preview = template:Clone()
	for _, p in ipairs(preview:GetDescendants()) do
		if p:IsA("BasePart") then
			p.CanCollide = false
			p.CanQuery = false
			p.CanTouch = false
			p.CastShadow = false
			if p.Name ~= "Bounds" then
				p.Transparency = math.max(p.Transparency, 0.45)
			end
		elseif p:IsA("Light") then
			p.Enabled = false
		end
	end
	local hl = Instance.new("Highlight")
	hl.FillTransparency = 0.6
	hl.OutlineTransparency = 0.2
	hl.DepthMode = Enum.HighlightDepthMode.Occluded
	hl.Parent = preview
	preview.Parent = camera
	Build.preview = preview
	Build.highlight = hl
	Build.def = def
	Build.active = true
	Build.bar.Visible = true
	Build.info.Text = def.name .. "  —  " .. Items.costText(def.cost)
	ProximityPromptService.Enabled = false
end

function Build.stop()
	if Build.preview then
		Build.preview:Destroy()
	end
	Build.preview = nil
	Build.active = false
	Build.bar.Visible = false
	ProximityPromptService.Enabled = true
end

function Build.rotate()
	Build.yaw = (Build.yaw + STEP) % (math.pi * 2)
end

local function inZone(pos)
	for _, zn in ipairs(Config.Build.Zones) do
		local a, b = zn[1], zn[2]
		if pos.X >= a.X and pos.X <= b.X and pos.Y >= a.Y and pos.Y <= b.Y and pos.Z >= a.Z and pos.Z <= b.Z then
			return true
		end
	end
	return false
end

local function screenRay()
	local pos
	if Build.touch then
		local vp = camera.ViewportSize
		pos = Vector2.new(vp.X / 2, vp.Y / 2)
	else
		pos = UserInputService:GetMouseLocation()
	end
	return camera:ViewportPointToRay(pos.X, pos.Y)
end

function Build.update()
	if not Build.active or not Build.preview then
		return
	end
	local def = Build.def
	local ray = screenRay()
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ignore = { camera, workspace:FindFirstChild("NPCs"), workspace:FindFirstChild("Effects") }
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Character then
			table.insert(ignore, p.Character)
		end
	end
	params.FilterDescendantsInstances = ignore
	local hit = workspace:Raycast(ray.Origin, ray.Direction * 80, params)
	if not hit then
		Build.preview:PivotTo(CFrame.new(ray.Origin + ray.Direction * 25))
		Build.valid = false
		Build.highlight.FillColor = UI.Colors.Red
		Build.reason.Text = "Aim at the deck."
		return
	end
	local p = hit.Position
	local pos = Vector3.new(math.floor(p.X * 2 + 0.5) / 2, p.Y + def.size.Y / 2 + 0.02, math.floor(p.Z * 2 + 0.5) / 2)
	local cf = CFrame.new(pos) * CFrame.Angles(0, Build.yaw, 0)
	Build.preview:PivotTo(cf)
	Build.pos = pos

	local reason
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not root or (root.Position - pos).Magnitude > Config.Build.Range then
		reason = "Too far away."
	elseif not inZone(pos) then
		reason = "Outside the build area (deck, dock, helipad)."
	elseif hit.Normal.Y < 0.7 or hit.Instance:IsA("Terrain") then
		reason = "Needs flat solid support."
	else
		local overlap = OverlapParams.new()
		overlap.FilterType = Enum.RaycastFilterType.Exclude
		overlap.FilterDescendantsInstances = { camera }
		for _, part in ipairs(workspace:GetPartBoundsInBox(cf * CFrame.new(0, 0.15, 0), def.size - Vector3.new(0.3, 0.4, 0.3), overlap)) do
			local model = part:FindFirstAncestorOfClass("Model")
			if model and model:FindFirstChildOfClass("Humanoid") then
				reason = "Someone is standing there."
				break
			elseif part.CanCollide then
				reason = "Blocked by " .. part.Name .. "."
				break
			end
		end
	end
	if not reason and def.tech and not (C.profile.Tech or {})[def.tech] then
		reason = "Locked: research " .. def.tech .. "."
	end
	if not reason then
		for id, n in pairs(def.cost) do
			if C.Panels.countOf(id) < n then
				reason = "Not enough " .. Items.name(id) .. "."
				break
			end
		end
	end
	Build.valid = reason == nil
	Build.highlight.FillColor = Build.valid and UI.Colors.Green or UI.Colors.Red
	Build.highlight.OutlineColor = Build.valid and UI.Colors.Green or UI.Colors.Red
	Build.reason.Text = reason or (Build.touch and "Valid spot — tap PLACE." or "Valid spot — click to place · R rotate · X cancel")
end

function Build.place()
	if not Build.active or not Build.pos then
		return
	end
	if not Build.valid then
		C.HUD.toast(Build.reason.Text, "warn")
		return
	end
	C.send("Build", Build.def.id, Build.pos, Build.yaw)
end

function Build.input(input)
	if not Build.active then
		return false
	end
	if input.KeyCode == Enum.KeyCode.R then
		Build.rotate()
		return true
	elseif input.KeyCode == Enum.KeyCode.X then
		Build.stop()
		return true
	elseif input.UserInputType == Enum.UserInputType.MouseButton1 and not Build.touch then
		Build.place()
		return true
	end
	return false
end

return Build
