-- ReplicatedStorage/Modules/Buildables
-- Player-buildable structures. The server builds one template Model per entry into
-- ReplicatedStorage/Assets/BuildTemplates; the client clones the same template for the preview.
local Buildables = {}

Buildables.List = {
	{ id = "MetalWall", name = "Metal Wall", size = Vector3.new(8, 8, 1), cost = { ScrapMetal = 4 }, health = 260, repair = { ScrapMetal = 2 }, desc = "Blocks Climbers until torn down." },
	{ id = "Barricade", name = "Barricade", size = Vector3.new(8, 4, 1.6), cost = { ScrapMetal = 2, Plastic = 1 }, health = 160, repair = { ScrapMetal = 1 }, desc = "Cheap waist-high cover." },
	{ id = "Door", name = "Door", size = Vector3.new(6, 9, 1), cost = { ScrapMetal = 5, MechanicalParts = 1 }, health = 220, repair = { ScrapMetal = 2 }, desc = "A door the crew can open. Climbers must break it." },
	{ id = "Floodlight", name = "Floodlight", size = Vector3.new(2, 10, 2), cost = { ScrapMetal = 3, Electronics = 2, Copper = 2 }, health = 90, repair = { ScrapMetal = 1, Electronics = 1 }, power = "Lights", desc = "Uses LIGHTS power. Repels and burns Climbers." },
	{ id = "Ladder", name = "Ladder", size = Vector3.new(2, 12, 2), cost = { ScrapMetal = 2 }, health = 120, repair = { ScrapMetal = 1 }, desc = "Climbable truss." },
	{ id = "DefensePost", name = "Defense Post", size = Vector3.new(4, 6, 4), cost = { ScrapMetal = 6, Electronics = 3, Copper = 2 }, health = 200, repair = { ScrapMetal = 2, Electronics = 1 }, power = "Defense", tech = "Defense", desc = "Uses DEFENSE power. UV strobe burns Climbers within 18 studs." },
	{ id = "RainCollector", name = "Rain Collector", size = Vector3.new(4, 5, 4), cost = { Plastic = 3, ScrapMetal = 2 }, health = 80, repair = { Plastic = 1 }, desc = "Fills a Water Bottle every 40 s while it rains (stores 4)." },
	{ id = "ElectricFence", name = "Electric Fence", size = Vector3.new(8, 5, 1), cost = { Copper = 4, ScrapMetal = 2, Electronics = 1 }, health = 150, repair = { Copper = 1, ScrapMetal = 1 }, power = "Defense", tech = "Defense", desc = "Uses DEFENSE power. Shocks creatures that touch it." },
}

Buildables.ById = {}
for _, b in ipairs(Buildables.List) do
	Buildables.ById[b.id] = b
end

local function part(model, name, size, cf, color, material, extra)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or Enum.Material.Metal
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if extra then
		for k, v in pairs(extra) do
			p[k] = v
		end
	end
	p.Parent = model
	return p
end

local STEEL = Color3.fromRGB(88, 96, 100)
local DARK = Color3.fromRGB(58, 62, 66)
local HAZARD = Color3.fromRGB(214, 160, 40)

-- Returns a Model whose PrimaryPart "Bounds" is centred at the origin and has the def size.
function Buildables.makeTemplate(def)
	local model = Instance.new("Model")
	model.Name = def.id
	local bounds = part(model, "Bounds", def.size, CFrame.new(), Color3.new(1, 1, 1), Enum.Material.SmoothPlastic, {
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
	})
	model.PrimaryPart = bounds
	-- Every visual stays inside def.size: the server's overlap check uses that box.
	if def.id == "MetalWall" then
		part(model, "Plate", Vector3.new(8, 8, 0.8), CFrame.new(), STEEL, Enum.Material.CorrodedMetal)
		for _, y in ipairs({ -2.6, 0, 2.6 }) do
			part(model, "Rib", Vector3.new(8, 0.4, 1), CFrame.new(0, y, 0), DARK, Enum.Material.Metal)
		end
		part(model, "Stripe", Vector3.new(8, 0.5, 1.02), CFrame.new(0, -3.7, 0), HAZARD, Enum.Material.SmoothPlastic)
	elseif def.id == "Barricade" then
		for i, y in ipairs({ -1.3, 0, 1.3 }) do
			part(model, "Plank", Vector3.new(8, 1.1, 0.5), CFrame.new(0, y, 0.45) * CFrame.Angles(0, 0, math.rad(i == 2 and 4 or -3)), Color3.fromRGB(96, 74, 52), Enum.Material.WoodPlanks)
		end
		for _, x in ipairs({ -3.4, 3.4 }) do
			part(model, "Post", Vector3.new(0.6, 4, 0.6), CFrame.new(x, 0, -0.45), DARK, Enum.Material.Metal)
		end
	elseif def.id == "Door" then
		for _, x in ipairs({ -2.6, 2.6 }) do
			part(model, "Post", Vector3.new(0.8, 9, 1), CFrame.new(x, 0, 0), DARK, Enum.Material.Metal)
		end
		part(model, "Lintel", Vector3.new(6, 0.8, 1), CFrame.new(0, 4.1, 0), DARK, Enum.Material.Metal)
		part(model, "Panel", Vector3.new(4.4, 8.1, 0.5), CFrame.new(0, -0.45, 0), STEEL, Enum.Material.DiamondPlate)
		part(model, "Stripe", Vector3.new(4.4, 0.4, 0.55), CFrame.new(0, 1, 0), HAZARD, Enum.Material.SmoothPlastic, { CanCollide = false })
	elseif def.id == "Floodlight" then
		part(model, "Base", Vector3.new(2, 0.4, 2), CFrame.new(0, -4.8, 0), DARK, Enum.Material.DiamondPlate)
		part(model, "Pole", Vector3.new(0.5, 9, 0.5), CFrame.new(0, -0.2, 0), STEEL, Enum.Material.Metal)
		local lamp = part(model, "Lamp", Vector3.new(1.8, 1, 1.4), CFrame.new(0, 4.3, -0.3) * CFrame.Angles(math.rad(-38), 0, 0), Color3.fromRGB(255, 226, 170), Enum.Material.Glass)
		local light = Instance.new("SpotLight")
		light.Face = Enum.NormalId.Front
		light.Angle = 75
		light.Range = 40
		light.Brightness = 4
		light.Color = Color3.fromRGB(255, 228, 185)
		light.Enabled = false
		light.Parent = lamp
	elseif def.id == "Ladder" then
		local truss = Instance.new("TrussPart")
		truss.Name = "Truss"
		truss.Size = Vector3.new(2, 12, 2)
		truss.CFrame = CFrame.new()
		truss.Anchored = true
		truss.Color = HAZARD
		truss.Material = Enum.Material.Metal
		truss.Parent = model
	elseif def.id == "DefensePost" then
		for i = 0, 3 do
			local a = math.rad(i * 90)
			part(model, "Sandbag", Vector3.new(4, 1.6, 1), CFrame.Angles(0, a, 0) * CFrame.new(0, -2.2, 1.5), Color3.fromRGB(110, 102, 80), Enum.Material.Fabric)
		end
		part(model, "Mast", Vector3.new(0.5, 4.4, 0.5), CFrame.new(0, 0.6, 0), STEEL, Enum.Material.Metal)
		local lamp = part(model, "Lamp", Vector3.new(1.4, 1.4, 1.4), CFrame.new(0, 2.8, 0), Color3.fromRGB(120, 140, 255), Enum.Material.Glass, { Shape = Enum.PartType.Ball })
		local light = Instance.new("PointLight")
		light.Range = 18
		light.Brightness = 3
		light.Color = Color3.fromRGB(140, 150, 255)
		light.Enabled = false
		light.Parent = lamp
	elseif def.id == "ElectricFence" then
		for _, x in ipairs({ -3.8, 3.8 }) do
			part(model, "Post", Vector3.new(0.5, 5, 0.5), CFrame.new(x, 0, 0), DARK, Enum.Material.Metal)
		end
		for _, y in ipairs({ -1.2, 0.4, 2 }) do
			part(model, "Wire", Vector3.new(7.6, 0.15, 0.15), CFrame.new(0, y, 0), Color3.fromRGB(90, 110, 120), Enum.Material.Metal, { CanCollide = false })
		end
		part(model, "Barrier", Vector3.new(8, 5, 0.4), CFrame.new(), Color3.fromRGB(120, 220, 255), Enum.Material.ForceField, { Transparency = 0.92 })
	elseif def.id == "RainCollector" then
		part(model, "Tank", Vector3.new(3, 3.4, 3), CFrame.new(0, -0.8, 0) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(60, 110, 160), Enum.Material.Metal, { Shape = Enum.PartType.Cylinder })
		part(model, "Funnel", Vector3.new(4, 0.3, 4), CFrame.new(0, 1.3, 0), Color3.fromRGB(70, 90, 100), Enum.Material.Metal)
		part(model, "Tarp", Vector3.new(3.6, 0.1, 3.6), CFrame.new(0, 2.2, 0) * CFrame.Angles(math.rad(8), 0, math.rad(6)), Color3.fromRGB(40, 90, 150), Enum.Material.Fabric, { CanCollide = false })
		for _, x in ipairs({ -1.8, 1.8 }) do
			part(model, "Post", Vector3.new(0.25, 1.2, 0.25), CFrame.new(x, 1.8, 0), DARK, Enum.Material.Metal)
		end
	end
	return model
end

return Buildables
