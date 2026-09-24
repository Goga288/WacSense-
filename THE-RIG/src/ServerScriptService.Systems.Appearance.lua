-- ServerScriptService/Systems/Appearance
-- Makes sure every player wears their own avatar (skin, clothing, accessories).
-- StarterPlayer.LoadCharacterAppearance already requests it; when the character still spawns
-- bare (a slow or failed avatar request), the description is fetched again and applied, with
-- retries. Status is published on the player as the "AvatarStatus" attribute:
--   Loaded / Applied  - avatar is on the character
--   Offline           - test player without an account (Studio not signed in): Roblox cannot
--                       download any avatar; sign in to Studio to see your skin
--   Failed            - Roblox refused the request (network / web API down)
local Players = game:GetService("Players")

local Appearance = {}
local G
local pending = setmetatable({}, {__mode = "k"})
local descriptions = {}

local function dressed(character)
	return character:FindFirstChildOfClass("Shirt") ~= nil
		or character:FindFirstChildOfClass("Pants") ~= nil
		or character:FindFirstChildOfClass("ShirtGraphic") ~= nil
		or character:FindFirstChildOfClass("Accessory") ~= nil
end

-- Fallback look when Roblox cannot deliver the avatar: an offshore crew outfit
-- (orange coverall, hi-vis vest, hard hat with lamp, boots) instead of a grey dummy.
local function weldTo(base, p, offset)
	p:SetAttribute("CrewFallback", true)
	p.Anchored = false
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.CFrame = base.CFrame * offset
	local w = Instance.new("WeldConstraint")
	w.Part0 = base
	w.Part1 = p
	w.Parent = p
	p.Parent = base
	return p
end

local function piece(name, size, color, material, shape)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	if shape then
		p.Shape = shape
	end
	return p
end

function Appearance.crewOutfit(character)
	if character:FindFirstChild("CrewOutfit") then
		return
	end
	local tag = Instance.new("BoolValue")
	tag.Name = "CrewOutfit"
	tag.Parent = character
	local skin = Color3.fromRGB(204, 150, 118)
	local coverall = Color3.fromRGB(214, 96, 32)
	local bc = character:FindFirstChildOfClass("BodyColors") or Instance.new("BodyColors")
	bc.HeadColor3 = skin
	bc.LeftArmColor3, bc.RightArmColor3 = coverall, coverall
	bc.TorsoColor3 = coverall
	bc.LeftLegColor3, bc.RightLegColor3 = Color3.fromRGB(46, 54, 70), Color3.fromRGB(46, 54, 70)
	bc.Parent = character
	for _, p in ipairs(character:GetChildren()) do
		if p:IsA("BasePart") and p.Name ~= "HumanoidRootPart" then
			local n = p.Name
			if n == "Head" then
				p.Color = skin
			elseif string.find(n, "Hand") then
				p.Color = Color3.fromRGB(40, 40, 38) -- work gloves
			elseif string.find(n, "Foot") then
				p.Color = Color3.fromRGB(34, 28, 24) -- boots
			elseif string.find(n, "Leg") then
				p.Color = Color3.fromRGB(46, 54, 70)
			else
				p.Color = coverall
			end
			p.Material = n == "Head" and Enum.Material.SmoothPlastic or Enum.Material.Fabric
		end
	end
	local torso = character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso")
	local head = character:FindFirstChild("Head")
	if torso then
		local vest = weldTo(torso, piece("HiVisVest", torso.Size + Vector3.new(0.12, -0.2, 0.12), Color3.fromRGB(200, 230, 40), Enum.Material.Fabric), CFrame.new(0, 0.1, 0))
		for _, y in ipairs({ -0.25, 0.25 }) do
			weldTo(vest, piece("Reflector", Vector3.new(vest.Size.X + 0.02, 0.14, vest.Size.Z + 0.02), Color3.fromRGB(230, 230, 230), Enum.Material.Neon), CFrame.new(0, y, 0))
		end
	end
	if head then
		local hat = weldTo(head, piece("HardHat", Vector3.new(1.35, 0.62, 1.35), Color3.fromRGB(240, 200, 40), Enum.Material.SmoothPlastic, Enum.PartType.Ball), CFrame.new(0, head.Size.Y / 2 - 0.02, 0))
		weldTo(hat, piece("Brim", Vector3.new(0.1, 1.5, 1.5), Color3.fromRGB(230, 190, 36), Enum.Material.SmoothPlastic, Enum.PartType.Cylinder), CFrame.new(0, -0.18, 0) * CFrame.Angles(0, 0, math.rad(90)))
		weldTo(hat, piece("HatLamp", Vector3.new(0.2, 0.3, 0.3), Color3.fromRGB(255, 244, 210), Enum.Material.Neon, Enum.PartType.Cylinder), CFrame.new(0, 0, -0.66) * CFrame.Angles(0, math.rad(90), 0))
	end
end

function Appearance.ensure(player, character)
	if pending[character] then return end
	pending[character] = true
	player:SetAttribute("AvatarStatus", "Loading")
	local t0 = os.clock()
	while character.Parent and player.Character == character and not player:HasAppearanceLoaded() and os.clock() - t0 < 12 do
		task.wait(0.5)
	end
	if not character.Parent or player.Character ~= character then
		return
	end
	local hum = character:FindFirstChildOfClass("Humanoid")
	if not hum then
		return
	end
	-- Naked/block avatars are legitimate. Clothing presence is not a load-success test.
	if player:HasAppearanceLoaded() then
		player:SetAttribute("AvatarStatus", "Loaded")
		return
	end
	if player.UserId <= 0 then
		player:SetAttribute("AvatarStatus", "Offline")
		Appearance.crewOutfit(character)
		return
	end
	for attempt = 1, 2 do
		if not character.Parent or player.Character ~= character or hum.Health <= 0 then return end
		local ok, desc = pcall(function()
			return descriptions[player.UserId] or Players:GetHumanoidDescriptionFromUserIdAsync(player.UserId)
		end)
		if ok and desc and character.Parent and player.Character == character then
			descriptions[player.UserId] = desc
			local applied = pcall(function()
				hum:ApplyDescriptionResetAsync(desc)
			end)
			if applied and player.Character == character then
				for _,o in ipairs(character:GetDescendants()) do
					if o:GetAttribute("CrewFallback") or o.Name == "CrewOutfit" then o:Destroy() end
				end
				player:SetAttribute("AvatarStatus", "Applied")
				G.Equipment.onCharacter(player, character)
				return
			end
		end
		if attempt < 2 then task.wait(5) end
	end
	player:SetAttribute("AvatarStatus", "Failed")
	if character.Parent and player.Character == character and not dressed(character) then
		Appearance.crewOutfit(character)
	end
end

local function watch(player)
	player.CharacterAdded:Connect(function(character)
		task.spawn(Appearance.ensure, player, character)
	end)
	if player.Character then
		task.spawn(Appearance.ensure, player, player.Character)
	end
end

function Appearance.init(g)
	G = g
	Players.PlayerAdded:Connect(watch)
	Players.PlayerRemoving:Connect(function(player)
		local desc = descriptions[player.UserId]
		if desc then desc:Destroy(); descriptions[player.UserId] = nil end
	end)
	for _, p in ipairs(Players:GetPlayers()) do
		watch(p)
	end
end

return Appearance
