-- ServerScriptService/Systems/Stations
-- Small interactive stations: radio, binoculars, sonar screen.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Story = require(ReplicatedStorage.Modules.Story)

local Stations = {}
local G

local function find(name)
	return workspace.Interactables:FindFirstChild(name, true)
end

function Stations.init(g)
	G = g

	local radio = find("Radio")
	if radio then
		local prompt = G.Util.prompt(radio, "Listen", "RADIO", 0.3, 9)
		prompt.Triggered:Connect(function(player)
			if not G.Net.near(player, radio, 12) then
				return
			end
			local day = G.DayCycle.day
			local best, bestDay = nil, 0
			for d, text in pairs(Story.Radio) do
				if d <= day and d > bestDay then
					best, bestDay = text, d
				end
			end
			G.Net.open(player, "Log", { title = "RADIO — DAY " .. bestDay, text = best or "Static." })
		end)
	end

	local binoculars = find("Binoculars")
	if binoculars then
		local prompt = G.Util.prompt(binoculars, "Observe", "BINOCULARS", 0.5, 8)
		prompt.Triggered:Connect(function(player)
			if not G.Net.near(player, binoculars, 10) then
				return
			end
			local pos = G.AI.watcherPosition()
			if pos then
				G.Net.effectAll("Ping", pos, "THE WATCHER")
				G.Net.toastAll(player.DisplayName .. " spotted the Watcher. Marked for 20 s.", "warn")
			else
				G.Net.toast(player, "Only fog and black water.", "info")
			end
		end)
	end

	local screen = find("SonarScreen")
	if screen then
		local prompt = G.Util.prompt(screen, "Read sonar", "SONAR", 0, 9)
		prompt.Triggered:Connect(function(player)
			if not G.Net.near(player, screen, 12) then
				return
			end
			if not G.Power.isPowered("Sonar") then
				G.Net.toast(player, "Sonar offline. Repair the array and power SONAR.", "warn")
				return
			end
			G.Net.toast(player, "SONAR: " .. (G.State.get("Sonar") or "no contacts"), "info")
		end)
	end
end

return Stations
