-- Apply the replicated aiming direction after Animator on every observing client.
-- C0 is restored when an item is put away, the avatar changes or the player leaves range.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Pose = {}
local cache = {}
local function restore(entry)
	for joint, base in pairs(entry.joints) do if joint.Parent then joint.C0 = base end end
end
function Pose.init(_ctx)
	RunService.PreSimulation:Connect(function(dt)
		local camera = workspace.CurrentCamera
		for _, player in ipairs(Players:GetPlayers()) do
			local ch = player.Character
			local root = ch and ch:FindFirstChild("HumanoidRootPart")
			local hum = ch and ch:FindFirstChildOfClass("Humanoid")
			local entry = cache[player]
			if entry and entry.character ~= ch then restore(entry);cache[player]=nil;entry=nil end
			local active = root and hum and hum.Health > 0 and not hum.Sit and ch:FindFirstChild("HeldLight")
			active = active and camera and (camera.CFrame.Position-root.Position).Magnitude < 180
			if active then
				if not entry then
					entry={character=ch,joints={}};cache[player]=entry
					for _,j in ipairs(ch:GetDescendants()) do
						if j:IsA("Motor6D") and (j.Name=="LeftShoulder" or j.Name=="Left Shoulder" or j.Name=="LeftElbow" or j.Name=="LeftWrist") then entry.joints[j]=j.C0 end
					end
				end
				local aim=player:GetAttribute("TorchAim") or root.CFrame.LookVector
				local localAim=root.CFrame:VectorToObjectSpace(aim)
				local pitch=math.asin(math.clamp(localAim.Y,-.85,.85))
				local yaw=math.clamp(math.atan2(-localAim.X,-localAim.Z),-.8,.8)
				for j,base in pairs(entry.joints) do
					if j.Parent and j.Part0 then
						local target=base
						if j.Name=="LeftShoulder" or j.Name=="Left Shoulder" then
							-- Desired upper-arm direction is -Y towards the camera aim.
							local armRotation=CFrame.Angles(math.pi/2+pitch,yaw,0)
							local worldRotation=root.CFrame.Rotation*armRotation
							target=CFrame.new(base.Position)*j.Part0.CFrame.Rotation:Inverse()*worldRotation*j.C1.Rotation
						elseif j.Name=="LeftElbow" then target=base*CFrame.Angles(-.12,0,0) end
						j.C0=j.C0:Lerp(target,1-math.exp(-dt*16))
						j.Transform=CFrame.identity
					end
				end
				local head=ch:FindFirstChild("Head")
				local mount=head and head:FindFirstChild("TorchMount")
				local held=ch:FindFirstChild("HeldLight")
				local lens=held and held:FindFirstChild("Lens")
				if mount and lens then
					mount.CFrame=head.CFrame:ToObjectSpace(CFrame.lookAt(lens.Position+aim*.12,lens.Position+aim))
				end
			elseif entry then restore(entry);cache[player]=nil end
		end
	end)
	Players.PlayerRemoving:Connect(function(p) if cache[p] then restore(cache[p]);cache[p]=nil end end)
end
return Pose
