-- ServerScriptService/Systems/Donate
-- Receives donations made through the SUPPORT panel. A donation buys nothing: it is
-- thanked, out loud, in front of the whole crew, and that is all.
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Modules.Config)

local Donate = {}
local G

function Donate.init(g)
	G = g
	local tiers = {}
	for _, tier in ipairs(Config.Donate) do
		if tier.id ~= 0 then
			tiers[tier.id] = tier
		end
	end
	-- Roblox may deliver the same receipt more than once. Granting it again only
	-- repeats a thank-you, so every known receipt is simply granted.
	MarketplaceService.ProcessReceipt = function(receipt)
		local tier = tiers[receipt.ProductId]
		if not tier then
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end
		local player = Players:GetPlayerByUserId(receipt.PlayerId)
		if player then
			G.Net.banner("THANK YOU", player.DisplayName .. " supported the crew: " .. tier.label .. ".", "good")
		end
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
end

return Donate
