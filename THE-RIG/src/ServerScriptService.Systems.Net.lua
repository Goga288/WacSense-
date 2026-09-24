-- ServerScriptService/Systems/Net
-- Single entry point for client requests. Every request is rate limited and routed to a
-- handler that validates it on the server. The client never tells the server results.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Net = {}
local handlers = {}
local lastCall = {}

function Net.init(G)
	Net.G = G
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	Net.Action = remotes:WaitForChild("Action")
	Net.Sync = remotes:WaitForChild("Sync")
	Net.Notify = remotes:WaitForChild("Notify")
	Net.Effect = remotes:WaitForChild("Effect")

	Net.Action.OnServerEvent:Connect(function(player, action, ...)
		if type(action) ~= "string" then
			return
		end
		local handler = handlers[action]
		if not handler then
			return
		end
		local now = os.clock()
		local bucket = lastCall[player]
		if not bucket then
			bucket = {}
			lastCall[player] = bucket
		end
		local last = bucket[action]
		if last and now - last < handler.rate then
			return
		end
		bucket[action] = now
		local ok, err = pcall(handler.fn, player, ...)
		if not ok then
			warn(string.format("[Net] %s from %s failed: %s", action, player.Name, tostring(err)))
		end
	end)
	Players.PlayerRemoving:Connect(function(p)
		lastCall[p] = nil
	end)
end

function Net.on(action, fn, rate)
	handlers[action] = { fn = fn, rate = rate or 0.12 }
end

-- Messages ------------------------------------------------------------------
function Net.toast(player, text, tone)
	Net.Notify:FireClient(player, "Toast", text, tone or "info")
end

function Net.toastAll(text, tone)
	Net.Notify:FireAllClients("Toast", text, tone or "info")
end

function Net.banner(title, subtitle, tone)
	Net.Notify:FireAllClients("Banner", title, subtitle or "", tone or "info")
end

function Net.bannerTo(player, title, subtitle, tone)
	Net.Notify:FireClient(player, "Banner", title, subtitle or "", tone or "info")
end

function Net.open(player, panel, data)
	Net.Notify:FireClient(player, "Open", panel, data)
end

function Net.effectAll(kind, ...)
	Net.Effect:FireAllClients(kind, ...)
end

-- Validation helpers --------------------------------------------------------
function Net.alive(player)
	local c = player.Character
	local h = c and c:FindFirstChildOfClass("Humanoid")
	local r = c and c:FindFirstChild("HumanoidRootPart")
	if h and r and h.Health > 0 then
		return c, h, r
	end
	return nil
end

function Net.posOf(t)
	if typeof(t) == "Vector3" then
		return t
	end
	if typeof(t) ~= "Instance" then
		return nil
	end
	if t:IsA("BasePart") then
		return t.Position
	end
	if t:IsA("Model") then
		local ok, cf = pcall(function()
			return t:GetPivot()
		end)
		if ok then
			return cf.Position
		end
	end
	if t:IsA("Attachment") then
		return t.WorldPosition
	end
	return nil
end

function Net.near(player, target, range)
	local c, _, root = Net.alive(player)
	if not c then
		return false
	end
	local pos = Net.posOf(target)
	if not pos then
		return false
	end
	return (root.Position - pos).Magnitude <= (range or 12)
end

function Net.isInt(v, min, max)
	return type(v) == "number" and v == v and v == math.floor(v) and v >= min and v <= max
end

function Net.isFiniteVector(v)
	if typeof(v) ~= "Vector3" then
		return false
	end
	for _, n in ipairs({ v.X, v.Y, v.Z }) do
		if n ~= n or n == math.huge or n == -math.huge then
			return false
		end
	end
	return true
end

function Net.isWorkspaceInstance(v)
	return typeof(v) == "Instance" and v:IsDescendantOf(workspace)
end

return Net
