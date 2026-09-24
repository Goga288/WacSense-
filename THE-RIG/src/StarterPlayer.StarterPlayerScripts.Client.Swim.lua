-- StarterPlayerScripts/Client/Swim
-- Better swimming for our own (client-owned) character: SPACE rises, LEFT CTRL dives,
-- SHIFT is a fast stroke (server sets the speed and drains stamina). The character's
-- physics belongs to this client, so velocity tweaks here are the normal way to steer.
local RunService = game:GetService("RunService")
local Input = game:GetService("UserInputService")

local Swim = {}
local C
local hinted = false

function Swim.init(ctx)
	C = ctx
	RunService.Heartbeat:Connect(Swim.step)
end

function Swim.step()
	local character = C.player.Character
	local hum = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not hum or not root or hum.Health <= 0 then
		return
	end
	if hum:GetState() ~= Enum.HumanoidStateType.Swimming then
		return
	end
	if not hinted then
		hinted = true
		C.HUD.toast("SWIMMING — SPACE up · LEFT CTRL dive · SHIFT fast stroke. Ladders on every deck edge lead out of the water.", "info")
	end
	if C.panelOpen or Input:GetFocusedTextBox() then
		return
	end
	local v = root.AssemblyLinearVelocity
	if Input:IsKeyDown(Enum.KeyCode.Space) then
		root.AssemblyLinearVelocity = Vector3.new(v.X, math.max(v.Y, 14), v.Z)
	elseif Input:IsKeyDown(Enum.KeyCode.LeftControl) or C.diving then
		root.AssemblyLinearVelocity = Vector3.new(v.X, math.min(v.Y, -14), v.Z)
	end
end

return Swim
