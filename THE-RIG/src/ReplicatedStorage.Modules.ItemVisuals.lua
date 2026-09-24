-- Asset-free display models shared by inventory previews. No catalog downloads.
local Visuals = {}
local steel = Color3.fromRGB(143, 159, 165)
local dark = Color3.fromRGB(32, 42, 48)
local rubber = Color3.fromRGB(20, 24, 28)
local white = Color3.fromRGB(223, 225, 214)
local amber = Color3.fromRGB(228, 170, 52)
local red = Color3.fromRGB(190, 48, 40)
function Visuals.build(id)
	local m = Instance.new("Model")
	m.Name = id
	local function p(n, size, at, color, shape, rot)
		local o = Instance.new("Part")
		o.Name, o.Size, o.Color = n, Vector3.new(table.unpack(size)), color or steel
		o.Anchored, o.CanCollide, o.CanTouch, o.CanQuery = true, false, false, false
		o.Material = Enum.Material.SmoothPlastic
		o.CFrame = CFrame.new(table.unpack(at)) * (rot or CFrame.identity)
		if shape then o.Shape = shape end
		o.Parent = m
		return o
	end
	local function cyl(n, radius, length, at, color, rot)
		return p(n, {length,radius*2,radius*2}, at, color, Enum.PartType.Cylinder, rot or CFrame.Angles(0,0,math.pi/2))
	end
	local function box(color, width, height)
		p("Case", {width or 1.8,height or 1.25,.65}, {0,0,0}, color)
		p("Handle", {.9,.14,.22}, {0,.86,0}, rubber)
		for _,x in ipairs({-.4,.4}) do p("HandleMount", {.14,.27,.22},{x,.7,0}, rubber) end
		for _,x in ipairs({-.62,.62}) do p("Latch", {.17,.28,.12},{x,.12,-.37},steel) end
	end
	if id == "Flashlight" then
		cyl("Grip",.28,1.6,{0,0,0},dark)
		for y=-.6,.61,.2 do cyl("GripRing",.3,.06,{0,y,0},rubber) end
		cyl("Bezel",.44,.45,{0,1,0},steel)
		cyl("Lens",.36,.04,{0,1.24,0},Color3.fromRGB(251,232,176))
		p("Switch",{.16,.28,.12},{0,.4,-.29},amber)
	elseif id == "Crowbar" then
		p("Shaft",{.19,2.6,.19},{0,0,0},red)
		p("Hook",{.19,.5,.19},{.18,1.34,0},steel,nil,CFrame.Angles(0,0,-.8))
		p("Claw",{.45,.14,.23},{.4,1.52,0},steel)
		p("PryEnd",{.34,.35,.1},{0,-1.4,0},steel)
	elseif id == "Flare" then
		cyl("Tube",.35,1.55,{0,0,0},red)
		cyl("Top",.36,.16,{0,.84,0},amber)
		cyl("Bottom",.36,.12,{0,-.81,0},steel)
		p("Label",{.46,.55,.06},{0,0,-.34},white)
	elseif id=="Fuel" then
		box(amber,1.6,1.6)
		for _,r in ipairs({.8,-.8}) do p("PressedRib",{.1,1.28,.09},{0,0,-.37},dark,nil,CFrame.Angles(0,0,r)) end
		cyl("Cap",.2,.16,{-.53,.92,0},rubber)
	elseif id=="Medkit" or id=="Toolkit" or id=="RepairKit" then
		box(id=="Medkit" and white or (id=="Toolkit" and red or amber))
		if id=="Medkit" then
			p("Cross",{.2,.72,.06},{0,0,-.36},red);p("Cross",{.72,.2,.06},{0,0,-.36},red)
		else p("ToolShaft",{.14,.8,.08},{0,0,-.39},steel,nil,CFrame.Angles(0,0,-.65));cyl("ToolHead",.23,.1,{.27,.34,-.39},steel,CFrame.Angles(0,math.pi/2,0)) end
	elseif id=="Water" or id=="Chemicals" then
		cyl("Bottle",.43,1.3,{0,0,0},id=="Water" and Color3.fromRGB(70,147,183) or Color3.fromRGB(133,92,167))
		cyl("Neck",.22,.4,{0,.83,0},steel);cyl("Cap",.25,.16,{0,1.06,0},dark)
		p("Label",{.64,.56,.06},{0,0,-.43},white)
		if id=="Chemicals" then p("Hazard",{.28,.28,.02},{0,0,-.48},amber,nil,CFrame.Angles(0,0,.785)) end
	elseif id=="Food" then
		cyl("Can",.59,1.1,{0,0,0},red)
		for _,y in ipairs({-.57,.57}) do cyl("Rim",.62,.08,{0,y,0},steel) end
		cyl("Lid",.56,.03,{0,.62,0},dark);p("PullTab",{.17,.07,.38},{0,.67,0},steel)
		p("Label",{.8,.6,.05},{0,0,-.59},white)
	elseif id=="Electronics" then
		p("PCB",{1.7,1.45,.12},{0,0,0},Color3.fromRGB(35,113,76))
		p("Processor",{.6,.55,.16},{0,.1,-.12},dark)
		for x=-.7,.71,.2 do p("Contact",{.09,.26,.05},{x,-.66,-.08},amber);p("Trace",{.035,1.05,.03},{x,0,-.08},amber) end
		for _,x in ipairs({-.59,.59}) do cyl("Capacitor",.12,.34,{x,.42,-.2},steel,CFrame.Angles(0,math.pi/2,0)) end
	elseif id=="Copper" then
		cyl("Spool",.44,.9,{0,0,0},Color3.fromRGB(189,101,49),CFrame.identity)
		for _,x in ipairs({-.5,.5}) do cyl("Flange",.67,.12,{x,0,0},dark,CFrame.identity) end
		for x=-.36,.37,.12 do cyl("Winding",.47,.04,{x,0,0},amber,CFrame.identity) end
	elseif id=="MechanicalParts" then
		cyl("Hub",.54,.35,{0,0,0},steel,CFrame.Angles(0,math.pi/2,0))
		cyl("Axle",.17,.7,{0,0,-.2},dark,CFrame.Angles(0,math.pi/2,0))
		for k=0,9 do local a=k*math.pi/5;p("GearTooth",{.32,.35,.32},{math.sin(a)*.6,math.cos(a)*.6,0},steel,nil,CFrame.Angles(0,0,-a)) end
	elseif id=="OxygenTank" then
		cyl("Tank",.46,1.9,{0,0,0},Color3.fromRGB(71,147,186))
		for _,y in ipairs({-.6,.6}) do cyl("Strap",.48,.18,{0,y,0},rubber) end
		cyl("Valve",.15,.35,{0,1.08,0},steel);p("Tap",{.6,.1,.14},{0,1.3,0},red)
	elseif id=="DivingGear" then
		p("Mask",{1.65,.85,.4},{0,.35,0},rubber)
		for _,x in ipairs({-.42,.42}) do p("Lens",{.64,.56,.08},{x,.38,-.25},Color3.fromRGB(80,184,200)) end
		p("Snorkel",{.2,1.8,.2},{.97,.45,0},amber)
		p("Breather",{.5,.32,.4},{0,-.38,-.25},steel)
	elseif id=="ArmorVest" then
		p("Vest",{1.55,1.45,.65},{0,0,0},Color3.fromRGB(72,91,78))
		for _,x in ipairs({-.55,.55}) do p("Strap",{.3,.5,.65},{x,.85,0},dark);p("Pocket",{.53,.6,.2},{x*.8,-.2,-.4},dark) end
		p("Plate",{1.1,.48,.12},{0,.35,-.37},steel)
	elseif id=="FishingRod" then
		p("Rod",{.09,3.1,.09},{0,.3,0},dark);p("Grip",{.2,.6,.2},{0,-1.1,0},Color3.fromRGB(145,100,53))
		cyl("Reel",.28,.22,{.24,-.65,0},steel,CFrame.Angles(0,math.pi/2,0));p("Line",{.02,2.5,.02},{.22,.55,0},white)
	elseif id=="RareMaterials" then
		for k=-1,1 do p("Crystal",{.4,1.7-math.abs(k)*.5,.45},{k*.4,0,0},Color3.fromRGB(70,205,196),nil,CFrame.Angles(0,.5,k*-.3)) end
	elseif id=="GeneratorUpgrade" then
		box(dark);for x=-.6,.61,.3 do p("CoolingFin",{.1,.8,.15},{x,0,-.4},steel) end
		cyl("Terminal",.16,.18,{-.5,.78,0},red);cyl("Terminal",.16,.18,{.5,.78,0},amber)
	elseif id=="ScrapMetal" then
		p("BentPlate",{1.5,.15,.9},{0,-.12,0},steel,nil,CFrame.Angles(0,.25,.16))
		p("AngleIron",{.25,.95,.4},{-.5,.32,0},dark,nil,CFrame.Angles(0,0,-.35))
		for _,x in ipairs({.2,.6}) do cyl("Bolt",.12,.6,{x,.2,0},steel) end
	elseif id=="Plastic" then
		p("Shell",{1.5,.32,1},{0,0,0},white)
		for _,x in ipairs({-.68,.68}) do p("Edge",{.14,.5,1},{x,.35,0},white) end
		p("Fragment",{.65,.12,.8},{.2,.5,.15},Color3.fromRGB(166,177,167),nil,CFrame.Angles(.3,.4,.3))
	else
		error("Missing item display model: "..tostring(id))
	end
	return m
end
return Visuals
