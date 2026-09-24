-- ServerScriptService/Systems/State
-- Replicated game state lives as attributes on ReplicatedStorage/GameState.
-- Attributes replicate automatically to every client; we only write when a value changes.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local State = {}

function State.init(G)
	State.G = G
	local f = ReplicatedStorage:FindFirstChild("GameState")
	if not f then
		f = Instance.new("Folder")
		f.Name = "GameState"
		f.Parent = ReplicatedStorage
	end
	State.folder = f
end

function State.set(key, value)
	if State.folder:GetAttribute(key) ~= value then
		State.folder:SetAttribute(key, value)
	end
end

function State.get(key)
	return State.folder:GetAttribute(key)
end

return State
