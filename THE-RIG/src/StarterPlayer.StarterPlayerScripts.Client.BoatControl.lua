-- StarterPlayerScripts/Client/BoatControl
-- The driver's client owns the boat physics (VehicleSeat gives network ownership), so it
-- steers here through the boat's LinearVelocity / AlignOrientation. Fuel, health, cargo and
-- speed sanity are owned by the server; with no fuel or a wrecked hull the boat won't move.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Modules.Config)

local Boat = {}
local C
local player = Players.LocalPlayer

function Boat.init(ctx)
	C = ctx
	RunService.Heartbeat:Connect(Boat.step)
end

local function currentBoat()
	local character = player.Character
	local hum = character and character:FindFirstChildOfClass("Humanoid")
	local seat = hum and hum.SeatPart
	if not seat or not seat:IsA("VehicleSeat") then
		return nil
	end
	local model = seat:FindFirstAncestorOfClass("Model")
	local hull = model and model:FindFirstChild("Hull")
	if not hull or not hull:FindFirstChild("Drive") then
		return nil
	end
	return model, seat, hull
end

function Boat.step(dt)
	local model, seat, hull = currentBoat()
	if not model then
		if Boat.driving then
			Boat.driving = false
			C.HUD.boat.Text = ""
		end
		return
	end
	if not Boat.driving then
		Boat.driving = true
		local look = hull.CFrame.LookVector
		Boat.yaw = math.atan2(-look.X, -look.Z)
	end
	local fuel = model:GetAttribute("Fuel") or 0
	local health = model:GetAttribute("Health") or 0
	local maxSpeed = model:GetAttribute("MaxSpeed") or Config.Boat.MaxSpeed
	local reverse = model:GetAttribute("ReverseSpeed") or Config.Boat.ReverseSpeed
	local turn = model:GetAttribute("TurnRate") or Config.Boat.TurnRate
	local throttle = seat.ThrottleFloat
	local steer = seat.SteerFloat
	if C.panelOpen then throttle = 0; steer = 0 end
	if fuel <= 0 or health <= 0 then
		throttle = 0
	end
	local speedFactor = math.clamp(hull.AssemblyLinearVelocity.Magnitude / 12, 0.35, 1)
	Boat.yaw -= steer * turn * dt * speedFactor
	local rot = CFrame.Angles(0, Boat.yaw, 0)
	local speed = throttle >= 0 and throttle * maxSpeed or throttle * reverse
	local v = rot.LookVector * speed
	-- Soft boundary: push back towards the rig at the edge of the map.
	local pos = hull.Position
	local flat = Vector3.new(pos.X, 0, pos.Z)
	if flat.Magnitude > Config.BoundaryRadius then
		v = -flat.Unit * 20
	end
	hull.Drive.PlaneVelocity = Vector2.new(v.X, v.Z)
	hull.Keel.CFrame = rot
	C.HUD.boat.Text = string.format("MOTORBOAT  ·  FUEL %d/%d  ·  HULL %d  ·  %d kn%s", math.floor(fuel), Config.Boat.FuelMax, math.floor(health), math.floor(hull.AssemblyLinearVelocity.Magnitude * 0.6), fuel <= 0 and "  ·  OUT OF FUEL" or (health <= 0 and "  ·  DISABLED" or ""))
end

return Boat
