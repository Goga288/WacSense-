-- Persistent bearing for the active chapter or a player-selected expedition destination.
local RunService=game:GetService("RunService")
local Navigation={}
local C
function Navigation.init(ctx)
	C=ctx
	local UI=C.UI
	local box=UI.panelBox(C.gui,{Name="Navigation",AnchorPoint=Vector2.new(.5,0),Position=UDim2.new(.5,0,0,10),Size=UDim2.fromOffset(330,44),BackgroundTransparency=.55})
	Navigation.box=box
	Navigation.label=UI.label(box,"",{Position=UDim2.fromOffset(12,5),Size=UDim2.new(1,-24,0,16),TextSize=10,Font=UI.Bold,TextColor3=UI.Colors.Teal,TextXAlignment=Enum.TextXAlignment.Center,TextTruncate=Enum.TextTruncate.AtEnd})
	Navigation.distance=UI.label(box,"",{Position=UDim2.fromOffset(12,23),Size=UDim2.new(1,-24,0,14),TextSize=9,Font=UI.Mono,TextColor3=UI.Colors.Dim,TextXAlignment=Enum.TextXAlignment.Center})
	local timer=0
	RunService.Heartbeat:Connect(function(dt)
		timer+=dt;if timer<.15 then return end;timer=0
		box.Visible=not C.panelOpen and not C.HUD.hidden and not C.HUD.introOpen
		local root=C.player.Character and C.player.Character:FindFirstChild("HumanoidRootPart")
		local target=Navigation.target or C.state:GetAttribute("StoryPosition")
		if not root or typeof(target)~="Vector3" then box.Visible=false;return end
		local delta=target-root.Position
		local localDirection=workspace.CurrentCamera.CFrame:VectorToObjectSpace(delta)
		local bearing=math.deg(math.atan2(delta.X,-delta.Z))%360
		local compass=({"N","NE","E","SE","S","SW","W","NW"})[math.floor((bearing+22.5)/45)%8+1]
		local hint=localDirection.Z>0 and "TURN BACK" or (math.abs(localDirection.X)>math.abs(localDirection.Z)*.4 and (localDirection.X>0 and "RIGHT" or "LEFT") or "AHEAD")
		Navigation.label.Text=Navigation.title or C.state:GetAttribute("StoryTitle") or "EXPEDITION"
		Navigation.distance.Text=string.format("%s  /  %s  /  %d STUDS   ·   J CHART",compass,hint,math.floor(delta.Magnitude))
	end)
end
function Navigation.set(title,position)
	Navigation.title=title;Navigation.target=position
	C.HUD.toast("Route set: "..title,"info")
end
function Navigation.followStory() Navigation.title=nil;Navigation.target=nil end
return Navigation
