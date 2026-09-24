-- StarterPlayerScripts/Client/Dread
-- The screen is afraid too.
--   * film grain that never holds still, dust drifting over the lens, faint scan lines
--   * the edges of the picture darkening in time with the heart as something comes
--     closer: slow and faint at forty studs, fast and hard at arm's length
--   * when fear peaks, the picture tears for a frame or two; at night it happens now
--     and then anyway
-- It also makes the service tunnels' lamps flicker. That runs here, on each client,
-- so a flicker costs the server nothing.
-- Everything is built from Roblox's own particle textures: nothing to upload.
local RunService = game:GetService("RunService")

local Dread = { lamps = {}, nextTear = 0, tearUntil = 0 }
local C
local gui, grain, dust, edges, bands

local function new(class, props, parent)
	local o = Instance.new(class)
	for k, v in pairs(props) do
		o[k] = v
	end
	o.Parent = parent
	return o
end

function Dread.init(ctx)
	C = ctx
	gui = new("ScreenGui", { Name = "Dread", IgnoreGuiInset = true, ResetOnSpawn = false, DisplayOrder = -4 }, C.gui.Parent)
	-- Grain: tiny specks, tiled small, jumping to a new offset every frame.
	grain = new("ImageLabel", {
		BackgroundTransparency = 1, Image = "rbxasset://textures/particles/sparkles_main.dds",
		ScaleType = Enum.ScaleType.Tile, TileSize = UDim2.fromOffset(3, 3),
		ImageColor3 = Color3.fromRGB(214, 210, 198), ImageTransparency = 0.975,
		Size = UDim2.new(1, 128, 1, 128), Position = UDim2.fromOffset(-64, -64),
	}, gui)
	-- Dust: soft dark smudges, tiled large, drifting slowly.
	dust = new("ImageLabel", {
		BackgroundTransparency = 1, Image = "rbxasset://textures/particles/smoke_main.dds",
		ScaleType = Enum.ScaleType.Tile, TileSize = UDim2.fromOffset(420, 420),
		ImageColor3 = Color3.fromRGB(30, 26, 22), ImageTransparency = 0.93,
		Size = UDim2.new(1, 420, 1, 420),
	}, gui)
	-- Scan lines: built once, tall enough for any screen.
	local lines = new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ClipsDescendants = true }, gui)
	for y = 0, 2160, 8 do
		new("Frame", {
			BorderSizePixel = 0, BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.93,
			Size = UDim2.new(1, 0, 0, 1), Position = UDim2.fromOffset(0, y),
		}, lines)
	end
	-- The heart: four gradient edges, deep red-black.
	edges = {}
	for _, spec in ipairs({
		{ UDim2.new(0, 0, 0, 0), UDim2.new(1, 0, 0.3, 0), 90 },
		{ UDim2.new(0, 0, 0.7, 0), UDim2.new(1, 0, 0.3, 0), -90 },
		{ UDim2.new(0, 0, 0, 0), UDim2.new(0.25, 0, 1, 0), 0 },
		{ UDim2.new(0.75, 0, 0, 0), UDim2.new(0.25, 0, 1, 0), 180 },
	}) do
		local f = new("Frame", {
			Position = spec[1], Size = spec[2], BorderSizePixel = 0,
			BackgroundColor3 = Color3.fromRGB(40, 0, 2), BackgroundTransparency = 1,
		}, gui)
		new("UIGradient", {
			Rotation = spec[3],
			Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) }),
		}, f)
		table.insert(edges, f)
	end
	-- Tears: a few bands that appear for a frame or two.
	bands = {}
	for _ = 1, 4 do
		local band = new("Frame", { BorderSizePixel = 0, BackgroundColor3 = Color3.new(0, 0, 0), Visible = false, ZIndex = 3 }, gui)
		new("Frame", {
			BorderSizePixel = 0, BackgroundColor3 = Color3.fromRGB(200, 196, 188), BackgroundTransparency = 0.55,
			Size = UDim2.new(1, 0, 0, 1), ZIndex = 4,
		}, band)
		table.insert(bands, band)
	end
	RunService.RenderStepped:Connect(Dread.render)
	task.spawn(Dread.lampLoop)
end

local function night()
	local hour = C.hour and C.hour() or 12
	return hour >= 21 or hour < 6
end

local function tear(now)
	for _, band in ipairs(bands) do
		band.Visible = math.random() < 0.7
		band.Size = UDim2.new(1, 0, 0, math.random(3, 28))
		band.Position = UDim2.new(0, math.random(-40, 40), math.random(), 0)
		band.BackgroundTransparency = 0.25 + math.random() * 0.35
	end
	Dread.tearUntil = now + 0.05 + math.random() * 0.08
end

function Dread.render()
	local on = C.settings.ScreenFilter ~= false
	gui.Enabled = on
	if not on then
		return
	end
	local now = os.clock()
	local fear = C.Env and C.Env.fear or 0
	local dark = night()
	grain.Position = UDim2.fromOffset(-math.random(0, 64), -math.random(0, 64))
	grain.ImageTransparency = 0.975 - fear * 0.018
	dust.Position = UDim2.fromOffset(-((now * 7) % 420), -((now * 2) % 420))
	-- A thump, then nothing, like a pulse: faster and harder the closer it is.
	local rate = 1.05 + fear * 1.5
	local beat = math.max(0, math.sin(now * math.pi * 2 * rate)) ^ 6
	local edge = fear * (0.3 + beat * 0.5)
	for _, f in ipairs(edges) do
		f.BackgroundTransparency = 1 - edge
	end
	if now >= Dread.nextTear then
		if fear > 0.5 then
			Dread.nextTear = now + 0.4 + math.random() * 1.4
			tear(now)
		elseif dark and math.random() < 0.5 then
			Dread.nextTear = now + 18 + math.random() * 30
			tear(now)
		else
			Dread.nextTear = now + 8 + math.random() * 20
		end
	end
	if now >= Dread.tearUntil then
		for _, band in ipairs(bands) do
			band.Visible = false
		end
	end
end

-- Lamps in the tunnels that are marked to flicker. With streaming, parts of the tunnels
-- arrive and leave as the player moves, so lamps are picked up as they arrive.
local function watchLamp(p)
	if p:IsA("BasePart") and p:GetAttribute("Flicker") then
		local light = p:FindFirstChildOfClass("PointLight")
		if light then
			Dread.lamps[p] = { light = light, base = light.Brightness, color = p.Color }
		end
	end
end

function Dread.lampLoop()
	local rig = workspace:WaitForChild("Rig", 60)
	local structure = rig and rig:WaitForChild("Structure", 60)
	local tunnels = structure and structure:WaitForChild("ServiceTunnels", 60)
	if not tunnels then
		return
	end
	for _, p in ipairs(tunnels:GetDescendants()) do
		watchLamp(p)
	end
	tunnels.DescendantAdded:Connect(watchLamp)
	while true do
		task.wait(0.07)
		local camera = workspace.CurrentCamera
		if camera then
			local at = camera.CFrame.Position
			for p, l in pairs(Dread.lamps) do
				if not p.Parent then
					Dread.lamps[p] = nil
				elseif (p.Position - at).Magnitude < 110 then
					local off = math.random() < 0.18
					l.light.Brightness = off and l.base * 0.08 or l.base * (0.8 + math.random() * 0.25)
					p.Color = off and Color3.fromRGB(70, 56, 40) or l.color
				end
			end
		end
	end
end

return Dread
