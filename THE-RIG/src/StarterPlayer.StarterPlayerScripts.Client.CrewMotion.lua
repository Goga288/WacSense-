-- Procedural locomotion on each client for Mimics and creatures, which have no animations
-- of their own. Players are animated by the Animate script Roblox gives every character.
local RunService = game:GetService("RunService")
local Motion = {}
local rigs = {}

local function track(model)
	if rigs[model] then return end
	local torso = model:FindFirstChild("Torso") or model:FindFirstChild("UpperTorso")
	local root = model:FindFirstChild("HumanoidRootPart")
	local hum = model:FindFirstChildOfClass("Humanoid")
	if root and hum and model:GetAttribute("Brain") == "Climber" then
		local joints = {}
		for _, item in ipairs(model:GetDescendants()) do
			if item:IsA("Motor6D") and item.Name == "CreatureJoint" then table.insert(joints, item) end
		end
		rigs[model] = {root=root, hum=hum, joints=joints, phase=0, stride=0, creature=true}
		return
	end
	if not torso or not root or not hum then return end
	local joints = {}
	for _, joint in ipairs(model:GetDescendants()) do
		if joint:IsA("Motor6D") and (string.find(joint.Name,"Shoulder") or string.find(joint.Name,"Hip") or string.find(joint.Name,"Knee") or joint.Name=="Neck") then
			joints[joint.Name] = joint
		end
	end
	rigs[model] = {root = root, hum = hum, joints = joints, phase = 0, stride = 0}
end

function Motion.init()
	local scan = 0
	RunService.PreSimulation:Connect(function(dt)
		scan -= dt
		if scan <= 0 then
			scan = .5
			local npcs = workspace:FindFirstChild("NPCs")
			if npcs then for _, m in ipairs(npcs:GetChildren()) do track(m) end end
		end
		for model, r in pairs(rigs) do
			if not model:IsDescendantOf(workspace) then rigs[model] = nil; continue end
			if not workspace.CurrentCamera or (r.root.Position - workspace.CurrentCamera.CFrame.Position).Magnitude > 200 then continue end
			local v = r.root.AssemblyLinearVelocity
			local speed = Vector3.new(v.X, 0, v.Z).Magnitude
			local state = r.hum:GetState()
			local swimming = state == Enum.HumanoidStateType.Swimming
			local airborne = state == Enum.HumanoidStateType.Freefall or state == Enum.HumanoidStateType.Jumping
			local seated = r.hum.Sit
			local target = r.hum.Health > 0 and math.clamp(speed / 14, 0, 1.3) or 0
			r.stride += (target - r.stride) * math.min(dt * 10, 1)
			r.phase += dt * (2 + speed * .65)
			local swing = math.sin(r.phase) * .65 * r.stride
			local breath = math.sin(os.clock() * 1.8) * .025
			local attacking = (model:GetAttribute("AttackUntil") or 0) > workspace:GetServerTimeNow()
			if r.creature then
				local climbing = model:GetAttribute("State") == "Climb"
				for _, joint in ipairs(r.joints) do
					local part = joint.Part1
					local side = joint.C0.Position.X < 0 and -1 or 1
					local limb = part.Name
					local arm = limb == "UpperArm" or limb == "Forearm" or limb == "Claw"
					local leg = limb == "Thigh" or limb == "Shin"
					local a = arm and swing * side * .5 or (leg and -swing * side or breath)
					if climbing and (arm or leg) then a = math.sin(os.clock()*5 + side*1.5)*.35 end
					if attacking and arm then a = -.65 end
					joint.Transform = CFrame.Angles(a,0,0)
				end
				continue
			end
			for name, joint in pairs(r.joints) do
				if not joint.Parent then rigs[model]=nil; break end
				local a = 0
				local left = string.find(name, "Left") ~= nil
				if string.find(name, "Shoulder") then
					a = (left and swing or -swing) + breath
					if swimming then a -= 1.2 elseif airborne then a = -.45 elseif seated then a = -.8 end
					if attacking and not left then a = -1.4 end
				elseif string.find(name, "Hip") then
					a = left and -swing or swing
					if seated then a = -math.pi / 2 elseif airborne then a = left and .25 or -.2 end
				elseif string.find(name,"Knee") then
					a = math.max(0,left and swing or -swing)*.7
					if seated then a=.9 end
				end
				joint.Transform = CFrame.Angles(a, 0, 0)
			end
		end
	end)
end
return Motion
