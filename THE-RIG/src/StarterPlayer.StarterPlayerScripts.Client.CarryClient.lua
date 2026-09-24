-- StarterPlayerScripts/Client/CarryClient
-- Hold RIGHT MOUSE (or G, or tap GRAB on touch) while looking at a loose crate / drum /
-- toolbox / spool / scrap pile to drag it; release to drop or throw it. Shows a hint when one
-- is in reach. Right mouse only focuses the flashlight when there is nothing to drag.
local RunService = game:GetService("RunService")
local Input = game:GetService("UserInputService")

local Carry = { holding = false }
local C
local REACH = 14

local function nodeOf(part)
	local cur = part
	while cur and cur ~= workspace do
		if cur:GetAttribute("Draggable") then
			return cur
		end
		cur = cur.Parent
	end
	return nil
end

local function aimed()
	local camera = workspace.CurrentCamera
	local character = C.player.Character
	if not camera or not character then
		return nil
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character, camera }
	local hit = workspace:Raycast(camera.CFrame.Position, camera.CFrame.LookVector * REACH, params)
	return hit and nodeOf(hit.Instance)
end

function Carry.grab()
	if C.panelOpen then
		return false
	end
	local node = aimed()
	if node then
		Carry.holding = true
		C.send("Grab", node)
		return true
	end
	return false
end

function Carry.release()
	if Carry.holding then
		Carry.holding = false
		C.send("Release")
	end
end

function Carry.init(ctx)
	C = ctx
	local UI = C.UI
	Carry.hint = UI.label(C.gui, "", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 34),
		Size = UDim2.new(0, 320, 0, 18),
		TextXAlignment = Enum.TextXAlignment.Center,
		Font = UI.Bold,
		TextSize = 12,
		TextColor3 = UI.Colors.Amber,
	})
	Input.InputBegan:Connect(function(input, processed)
		if processed or Input:GetFocusedTextBox() then
			return
		end
		if input.KeyCode == Enum.KeyCode.G then
			Carry.grab()
		end
	end)
	Input.InputEnded:Connect(function(input)
		if input.KeyCode == Enum.KeyCode.G then
			Carry.release()
		end
	end)
	if C.HUD.touch then
		local b = UI.button(C.gui, "GRAB", { AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -310, 1, -160), Size = UDim2.new(0, 60, 0, 60), TextSize = 11 })
		UI.corner(b, 30)
		b.Activated:Connect(function()
			if Carry.holding then
				Carry.release()
			else
				Carry.grab()
			end
			b.TextColor3 = Carry.holding and UI.Colors.Green or UI.Colors.Amber
		end)
	end
	local timer = 0
	RunService.Heartbeat:Connect(function(dt)
		timer += dt
		if timer < 0.15 then
			return
		end
		timer = 0
		local held = Input:IsKeyDown(Enum.KeyCode.G) or Input:IsMouseButtonPressed(Enum.UserInputType.MouseButton2)
		if C.player:GetAttribute("Carrying") ~= true and Carry.holding and not held and not C.HUD.touch then
			Carry.holding = false
		end
		if C.panelOpen then
			Carry.hint.Text = ""
			return
		end
		if C.player:GetAttribute("Carrying") then
			Carry.hint.Text = C.HUD.touch and "GRAB again to drop" or "Release RIGHT MOUSE to drop · swing the view + release to throw"
		elseif aimed() then
			Carry.hint.Text = C.HUD.touch and "GRAB to drag · E to take" or "Hold RIGHT MOUSE to drag · E to take"
		else
			Carry.hint.Text = ""
		end
	end)
end

return Carry
