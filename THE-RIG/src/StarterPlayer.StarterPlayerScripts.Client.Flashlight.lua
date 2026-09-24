-- StarterPlayerScripts/Client/Flashlight
-- Your own flashlight beam, rendered locally so it follows the camera instantly (no network
-- lag, no beam stuck inside your own head). Other players still see the server beam on your
-- character; your copy of that server beam is switched off locally so it is never doubled.
-- The beam comes out of the flashlight in your left hand (first person) or from in front of
-- your face (third person), lags a touch behind fast turns, and flickers when something is
-- close.
-- 0.15: the light part lives in a client-only folder in Workspace, not under the Camera
-- (lights under the Camera do not reliably light the world), and F switches the beam at
-- once on this client while the server confirms. It has no battery: it never runs out.
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")

local Flash = { dir = nil, flickerUntil = 0, nextFlicker = 0, predicted = nil, predictUntil = 0 }
local C
local camera = workspace.CurrentCamera

-- 1 stud = 0.28 m; normal beam reaches 16.8 m, focused beam 19.6 m.
local NORMAL = { Angle = 50, Range = 60, Brightness = 4.5 }
local FOCUS = { Angle = 22, Range = 70, Brightness = 8 }

-- Client-only folder for local lights. Anything a LocalScript puts in Workspace stays on
-- this client; the server and other players never see it.
function Flash.localFolder()
	local f = workspace:FindFirstChild("LocalFX")
	if not f or not f:IsA("Folder") then
		f = Instance.new("Folder")
		f.Name = "LocalFX"
		f.Parent = workspace
	end
	return f
end

local function carrying()
	local player = C.player
	if player:GetAttribute("HasFlashlight") == true then
		return true
	end
	for _, slot in ipairs(C.inventory and C.inventory.slots or {}) do
		if slot and slot.id == "Flashlight" then
			return true
		end
	end
	return false
end

-- F / LIGHT button: flip the beam right away; the server's TorchOn takes over as soon as
-- it arrives (or after a second, if the request was refused).
function Flash.toggle()
	if not carrying() then
		return
	end
	local now = os.clock()
	local current = Flash.isOn(true)
	Flash.predicted = not current
	Flash.predictUntil = now + 1
end

function Flash.isOn(raw)
	local server = C.player:GetAttribute("TorchOn") == true
	if Flash.predicted ~= nil then
		if server == Flash.predicted or os.clock() > Flash.predictUntil then
			Flash.predicted = nil
		else
			return Flash.predicted
		end
	end
	return server
end

function Flash.init(ctx)
	C = ctx
	local p = Instance.new("Part")
	p.Name = "LocalTorch"
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Transparency = 1
	p.Size = Vector3.new(0.2, 0.2, 0.2)
	p.CastShadow = false
	p.Parent = Flash.localFolder()
	local spot = Instance.new("SpotLight")
	spot.Face = Enum.NormalId.Front
	spot.Shadows = true
	spot.Color = Color3.fromRGB(255, 242, 218)
	spot.Enabled = false
	spot.Parent = p
	-- Faint spill so the area right around you is not pitch black next to the beam.
	local spill = Instance.new("PointLight")
	spill.Range = 9
	spill.Brightness = 0.35
	spill.Color = Color3.fromRGB(255, 236, 205)
	spill.Shadows = false
	spill.Enabled = false
	spill.Parent = p
	Flash.part, Flash.spot, Flash.spill = p, spot, spill
	RunService:BindToRenderStep("RigFlashlight", Enum.RenderPriority.Camera.Value + 6, function(dt)
		local ok, err = pcall(Flash.render, dt)
		if not ok and not Flash.warned then
			Flash.warned = true
			warn("[Flashlight] " .. tostring(err))
		end
	end)
end

local function monsterNear(pos, range)
	for _, m in ipairs(CollectionService:GetTagged("Monster")) do
		local r = m.PrimaryPart or m:FindFirstChild("HumanoidRootPart")
		if r and (r.Position - pos).Magnitude < range then
			local brain = m:GetAttribute("Brain")
			if brain ~= "Mimic" or m:GetAttribute("State") == "Hunt" then
				return true
			end
		end
	end
	return false
end

function Flash.render(dt)
	camera = workspace.CurrentCamera
	if not camera then return end
	if not Flash.part.Parent or Flash.part.Parent.Parent ~= workspace then
		Flash.part.Parent = Flash.localFolder()
	end
	local player = C.player
	local character = player.Character
	local head = character and character:FindFirstChild("Head")
	local hum = character and character:FindFirstChildOfClass("Humanoid")
	-- Never draw the replicated copy of our own server beam.
	local mount = head and head:FindFirstChild("TorchMount")
	local serverTorch = mount and mount:FindFirstChild("Torch")
	if serverTorch and serverTorch.Enabled then
		serverTorch.Enabled = false
	end
	local on = not C.panelOpen and Flash.isOn() and hum ~= nil and hum.Health > 0
	if not on or not head then
		Flash.spot.Enabled = false
		Flash.spill.Enabled = false
		Flash.dir = nil
		return
	end
	local cam = camera.CFrame
	local look = cam.LookVector
	-- A little inertia: the beam trails fast turns slightly, like a real hand-held torch.
	Flash.dir = Flash.dir and Flash.dir:Lerp(look, math.clamp(dt * 16, 0, 1)).Unit or look
	local origin
	local lens
	if C.Viewmodel and C.Viewmodel.items and C.Viewmodel.firstPerson then
		for _, it in ipairs(C.Viewmodel.items.Left or {}) do
			if it.part.Name == "Lens" and it.part.Transparency < 0.5 then
				lens = it.part
			end
		end
	end
	if lens then
		origin = lens.Position + Flash.dir * 0.15
	elseif (cam.Position - head.Position).Magnitude < 2 then
		origin = cam.Position + cam.RightVector * -0.4 + cam.UpVector * -0.35 + look * 0.6
	else
		origin = head.Position + Flash.dir * 1.2
	end
	Flash.part.CFrame = CFrame.lookAt(origin, origin + Flash.dir)
	local beam = player:GetAttribute("TorchFocus") and FOCUS or NORMAL
	for k, v in pairs(beam) do
		Flash.spot[k] = v
	end
	-- Flicker: something close by.
	local now = os.clock()
	if now >= Flash.nextFlicker then
		Flash.nextFlicker = now + 0.25
		local chance = monsterNear(head.Position, 28) and 0.3 or 0
		if math.random() < chance then
			Flash.flickerUntil = now + 0.05 + math.random() * 0.25
		end
	end
	local flicker = now < Flash.flickerUntil
	Flash.spot.Enabled = true
	Flash.spot.Brightness = flicker and beam.Brightness * (math.random() < 0.5 and 0.05 or 0.4) or beam.Brightness
	Flash.spill.Enabled = not flicker
	Flash.spill.Brightness = 0.35
end

return Flash
