-- ServerScriptService/Systems/Carry
-- Drag loose physical objects (crates, drums, toolboxes, spools, scrap piles). Hold G (or
-- GRAB on touch) while looking at one: the server attaches an AlignPosition that pulls it to a
-- point in front of your view. Release to drop it; it keeps its momentum (a light throw).
-- The server owns the physics while carrying, validates distance and mass, one object each.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Carry = { held = {} } -- [player] = {node, part, att, align, gyro}
local G

local MAX_START = 14
local MAX_KEEP = 22
local MAX_MASS = 250
local HOLD_DISTANCE = 6

function Carry.init(g)
	G = g
	G.Net.on("Grab", function(player, inst)
		if typeof(inst) == "Instance" then
			Carry.grab(player, inst)
		end
	end, 0.25)
	G.Net.on("Release", function(player)
		Carry.release(player)
	end, 0.05)
	Players.PlayerRemoving:Connect(Carry.release)
	RunService.Heartbeat:Connect(Carry.step)
end

function Carry.grab(player, inst)
	local entry = G.Loot.entryOf(inst)
	if not entry or not entry.physical or not entry.ready or entry.node:GetAttribute("Carried") then
		return
	end
	local _, _, root = G.Net.alive(player)
	if not root or (entry.part.Position - root.Position).Magnitude > MAX_START then
		return
	end
	if entry.part.AssemblyMass > MAX_MASS then
		G.Net.toast(player, "Too heavy to drag.", "warn")
		return
	end
	Carry.release(player)
	local part = entry.part
	pcall(function()
		part:SetNetworkOwner(nil)
	end)
	local att = Instance.new("Attachment")
	att.Name = "CarryAttachment"
	att.Parent = part
	local align = Instance.new("AlignPosition")
	align.Mode = Enum.PositionAlignmentMode.OneAttachment
	align.Attachment0 = att
	align.MaxForce = part.AssemblyMass * workspace.Gravity * 6 + 2000
	align.MaxVelocity = 60
	align.Responsiveness = 30
	align.Position = part.Position
	align.Parent = part
	local gyro = Instance.new("AlignOrientation")
	gyro.Mode = Enum.OrientationAlignmentMode.OneAttachment
	gyro.Attachment0 = att
	gyro.MaxTorque = part.AssemblyMass * 400 + 2000
	gyro.Responsiveness = 12
	gyro.CFrame = CFrame.new()
	gyro.Parent = part
	entry.node:SetAttribute("Carried", player.UserId)
	Carry.held[player] = { entry = entry, part = part, att = att, align = align, gyro = gyro }
	player:SetAttribute("Carrying", true)
end

function Carry.release(player)
	local h = Carry.held[player]
	if not h then
		return
	end
	Carry.held[player] = nil
	for _, obj in ipairs({ h.align, h.gyro, h.att }) do
		if obj then
			obj:Destroy()
		end
	end
	if h.entry.node.Parent then
		h.entry.node:SetAttribute("Carried", nil)
		pcall(function()
			h.part:SetNetworkOwnershipAuto()
		end)
	end
	if player.Parent then
		player:SetAttribute("Carrying", false)
	end
end

-- Used by Loot when a carried object is taken (it disappears).
function Carry.releaseNode(node)
	for player, h in pairs(Carry.held) do
		if h.entry.node == node then
			Carry.release(player)
		end
	end
end

function Carry.step()
	for player, h in pairs(Carry.held) do
		local character, _, root = G.Net.alive(player)
		local head = character and character:FindFirstChild("Head")
		if not head or not h.part.Parent or h.part.Anchored or (h.part.Position - root.Position).Magnitude > MAX_KEEP then
			Carry.release(player)
		else
			local s = G.Equipment.state[player]
			local look = (s and s.aim) or root.CFrame.LookVector
			local flat = Vector3.new(look.X, 0, look.Z)
			flat = flat.Magnitude > 0.05 and flat.Unit or root.CFrame.LookVector
			h.align.Position = head.Position + look * HOLD_DISTANCE + Vector3.new(0, -1, 0)
			h.gyro.CFrame = CFrame.lookAt(Vector3.zero, flat)
		end
	end
end

return Carry
