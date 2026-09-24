local Visuals = require(game:GetService("ReplicatedStorage"):WaitForChild("Modules"):WaitForChild("ItemVisuals"))
local Icons = {}
function Icons.show(parent, id, props)
	local old = parent:FindFirstChild("ItemPreview")
	if old then
		if old:GetAttribute("ItemId") == id then return old end
		old:Destroy()
	end
	if not id then return end
	local view = Instance.new("ViewportFrame")
	view.Name, view.BackgroundTransparency = "ItemPreview", 1
	view.Size = UDim2.fromScale(1,1)
	view.Ambient = Color3.fromRGB(160,173,185)
	view.LightColor = Color3.fromRGB(255,235,206)
	view.LightDirection = Vector3.new(-1,-1,-2)
	view.Active = false
	view.ZIndex = parent.ZIndex + 1
	for k,v in pairs(props or {}) do view[k] = v end
	view:SetAttribute("ItemId", id)
	local model = Visuals.build(id)
	model.Parent = view
	local cf,size = model:GetBoundingBox()
	local camera = Instance.new("Camera")
	camera.FieldOfView = 32
	local distance = math.max(size.X,size.Y,size.Z) * 2.3
	camera.CFrame = CFrame.lookAt(cf.Position + Vector3.new(.6,.42,-1).Unit * distance, cf.Position)
	camera.Parent = view
	view.CurrentCamera = camera
	view.Parent = parent
	return view
end
return Icons
