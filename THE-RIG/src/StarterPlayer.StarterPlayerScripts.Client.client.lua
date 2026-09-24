-- StarterPlayerScripts/Client (LocalScript)
-- Client entry point: wires remotes, input and the UI / environment modules (children).
-- The client never decides outcomes: it sends requests through Remotes/Action.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local StarterGui = game:GetService("StarterGui")
local ContextActionService = game:GetService("ContextActionService")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")

local player = Players.LocalPlayer
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local GameState = ReplicatedStorage:WaitForChild("GameState")
local ModulesFolder = ReplicatedStorage:WaitForChild("Modules")
for _, name in ipairs({ "Config", "Items", "Recipes", "Buildables", "Progression", "Story", "Expeditions" }) do
	ModulesFolder:WaitForChild(name)
end
local Config = require(ModulesFolder.Config)

local C = {
	player = player,
	state = GameState,
	inventory = { slots = {}, equipped = 0 },
	profile = { Tech = {}, Cosmetics = {}, Achievements = {}, Stats = {} },
	settings = { Rain = true, DepthOfField = true, Bloom = true, Shadows = true, ScreenFilter = true, UIScale = 1 },
	sprinting = false,
	menuOpen = true,
}

function C.send(action, ...)
	Remotes.Action:FireServer(action, ...)
end

function C.hour()
	local start = GameState:GetAttribute("CycleStart") or workspace:GetServerTimeNow()
	local len = GameState:GetAttribute("DaySeconds") or Config.DaySeconds
	return (Config.StartHour + (workspace:GetServerTimeNow() - start) / len * 24) % 24
end

function C.setSprint(on)
	on = on and not C.panelOpen
	if C.sprinting ~= on then
		C.sprinting = on
		C.send("Sprint", on)
	end
end

-- Focused flashlight beam: hold right mouse (PC) or toggle FOCUS (touch).
function C.setFocus(on)
	on = on and not C.panelOpen
	if C.focusing ~= on then
		C.focusing = on
		C.send("Focus", on)
	end
end

function C.useEquipped()
	if not C.panelOpen then C.send("UseEquipped") end
end

-- UI root (ScreenGui "MainUI" from StarterGui)
local playerGui = player:WaitForChild("PlayerGui")
local gui = playerGui:WaitForChild("MainUI", 10)
if not gui then
	gui = Instance.new("ScreenGui")
	gui.Name = "MainUI"
	gui.Parent = playerGui
end
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
C.gui = gui
C.uiScale = gui:FindFirstChildOfClass("UIScale") or Instance.new("UIScale")
C.uiScale.Parent = gui

pcall(function()
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, false)
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Health, false)
end)

C.UI = require(script:WaitForChild("UIKit"))
C.Env = require(script:WaitForChild("Env"))
C.HUD = require(script:WaitForChild("HUD"))
C.Panels = require(script:WaitForChild("Panels"))
C.Build = require(script:WaitForChild("BuildMode"))
C.Boat = require(script:WaitForChild("BoatControl"))
C.Viewmodel = require(script:WaitForChild("Viewmodel"))
C.Swim = require(script:WaitForChild("Swim"))
C.CarryClient = require(script:WaitForChild("CarryClient"))
C.Navigation = require(script:WaitForChild("Navigation"))
C.Horror = require(script:WaitForChild("Horror"))
C.Flashlight = require(script:WaitForChild("Flashlight"))
C.HeldPose = require(script:WaitForChild("HeldPose"))

-- Free camera: mouse wheel zooms from first person out to third person; V snaps between them.
player.CameraMode = Enum.CameraMode.Classic
player.CameraMinZoomDistance = 0.5
player.CameraMaxZoomDistance = 22
pcall(function()
	-- The character turns with the camera, so aiming works the same in third person.
	UserSettings():GetService("UserGameSettings").RotationType = Enum.RotationType.CameraRelative
end)
function C.toggleView()
	local head = player.Character and player.Character:FindFirstChild("Head")
	local cam = workspace.CurrentCamera
	local first = head and (cam.CFrame.Position - head.Position).Magnitude < 2
	if first then
		player.CameraMinZoomDistance = 10
		task.wait()
		player.CameraMinZoomDistance = 0.5
	else
		player.CameraMaxZoomDistance = 0.5
		task.wait()
		player.CameraMaxZoomDistance = 22
	end
end
local cursor = C.UI.new("TextButton", {Name = "ModalCursor", Size = UDim2.fromOffset(1, 1), Text = "", BackgroundTransparency = 1, Modal = true, Visible = false, ZIndex = 1}, gui)
local menuBlur = Instance.new("BlurEffect")
menuBlur.Name = "MenuBlur"
menuBlur.Size = 0
menuBlur.Parent = Lighting
function C.onPanel(open)
	C.panelOpen = open or C.Panels.current ~= nil or C.menuOpen or C.victoryOpen == true
	cursor.Visible = C.panelOpen
	UserInputService.MouseIconEnabled = C.panelOpen
	UserInputService.MouseBehavior = C.panelOpen and Enum.MouseBehavior.Default or Enum.MouseBehavior.LockCenter
	if C.panelOpen then C.setSprint(false); C.Build.stop() end
	if C.controls then
		if C.panelOpen then C.controls:Disable() else C.controls:Enable() end
	end
	C.UI.tween(menuBlur, .2, {Size = C.panelOpen and 12 or 0})
end
RunService:BindToRenderStep("RigCursor", Enum.RenderPriority.Camera.Value + 2, function()
	if C.panelOpen then UserInputService.MouseBehavior = Enum.MouseBehavior.Default end
end)

function C.applySettings(push)
	local st = C.settings
	local vp = workspace.CurrentCamera.ViewportSize
	local auto = math.clamp(math.min(vp.X / 1440, vp.Y / 900), 0.25, 1.15)
	C.uiScale.Scale = math.min(auto * (st.UIScale or 1), vp.X / 1180, math.max(vp.Y - 48, 100) / 660)
	local dof = Lighting:FindFirstChildOfClass("DepthOfFieldEffect")
	if dof then
		dof.Enabled = st.DepthOfField
	end
	local bloom = Lighting:FindFirstChildOfClass("BloomEffect")
	if bloom then
		bloom.Enabled = st.Bloom
	end
	Lighting.GlobalShadows = st.Shadows
	if push then
		C.send("Settings", st)
	end
end

require(script:WaitForChild("CrewMotion")).init()
C.Env.init(C)
C.HUD.init(C)
C.Build.init(C)
C.Panels.init(C)
C.Panels.hookDrag()
C.Boat.init(C)
C.Viewmodel.init(C)
C.Swim.init(C)
C.CarryClient.init(C)
C.Navigation.init(C)
C.Horror.init(C)
require(script:WaitForChild("Dread")).init(C)
C.Flashlight.init(C)
C.HeldPose.init(C)
C.applySettings(false)
task.spawn(function()
	local scripts = player:WaitForChild("PlayerScripts")
	local module = scripts:WaitForChild("PlayerModule", 10)
	if module then
		C.controls = require(module):GetControls()
		if C.panelOpen then C.controls:Disable() end
	end
end)
local aimTimer = 0
RunService.Heartbeat:Connect(function(dt)
	aimTimer += dt
	if aimTimer >= .12 and not C.panelOpen then
		aimTimer = 0
		C.send("Aim", workspace.CurrentCamera.CFrame.LookVector)
	end
end)
workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
	C.applySettings(false)
end)

-- Remotes -----------------------------------------------------------------
Remotes.Sync.OnClientEvent:Connect(function(kind, payload)
	if kind == "Inventory" then
		C.inventory = payload
		C.HUD.updateInventory()
		C.Panels.refresh("*")
	elseif kind == "Profile" then
		C.profile = payload
		for k, v in pairs(payload.Settings or {}) do
			C.settings[k] = v
		end
		C.applySettings(false)
		C.Panels.refresh("*")
	end
end)

Remotes.Notify.OnClientEvent:Connect(function(kind, a, b, c)
	if kind == "Toast" then
		C.HUD.toast(a, b)
	elseif kind == "Banner" then
		C.HUD.showBanner(a, b, c)
	elseif kind == "Open" then
		if C.menuOpen then
			C.Panels.showMenu(false)
		end
		C.Panels.open(a, b)
	elseif kind == "Death" then
		C.Panels.close()
		C.Build.stop()
		C.HUD.showDeath(a, b or 8)
	elseif kind == "Victory" then
		C.HUD.showVictory(a or {})
	elseif kind == "Intro" then
		C.HUD.showIntro()
	end
end)

Remotes.Effect.OnClientEvent:Connect(function(kind, a, b)
	C.Env.effect(kind, a, b)
	if kind == "Swing" then C.Viewmodel.kick() end
end)

-- Live refresh of state-driven panels.
GameState.AttributeChanged:Connect(function(attribute)
	if C.Panels.current == "Journal" and string.sub(attribute,1,5) == "Story" then C.Panels.refresh("Journal") end
	if C.menuOpen then C.Panels.refreshMenu() end
	if C.Panels.current == "Power" then
		C.Panels.refresh("Power")
	end
end)

player.CharacterAdded:Connect(function(character)
	C.HUD.hideDeath()
	C.HUD.lastHealth = nil
	C.setSprint(false)
	C.sprinting = false
	local hum = character:WaitForChild("Humanoid", 10)
	if hum then
		hum.HealthChanged:Connect(function()
			if C.Panels.current == "Repair" then
				C.Panels.refresh("Repair")
			end
		end)
	end
end)

-- Repair panel follows the target's health live.
task.spawn(function()
	while true do
		task.wait(0.5)
		if C.Panels.current == "Repair" then
			local d = C.Panels.data.Repair
			if d and d.target and d.target.Parent and d.target:GetAttribute("Health") ~= d.lastSeen then
				d.lastSeen = d.target:GetAttribute("Health")
				C.Panels.refresh("Repair")
			end
		end
	end
end)

-- Initial snapshots can be sent before this LocalScript connects its remotes.
task.spawn(function()
	while GameState:GetAttribute("Ready") ~= true do task.wait(.2) end
	C.send("ClientReady")
end)

-- Input ---------------------------------------------------------------------
local KEY_PANELS = {
	[Enum.KeyCode.I] = "Inventory",
	[Enum.KeyCode.J] = "Journal",
	[Enum.KeyCode.C] = "Craft",
	[Enum.KeyCode.B] = "Build",
	[Enum.KeyCode.P] = "Power",
}
local HOTKEYS = {
	[Enum.KeyCode.One] = 1,
	[Enum.KeyCode.Two] = 2,
	[Enum.KeyCode.Three] = 3,
	[Enum.KeyCode.Four] = 4,
	[Enum.KeyCode.Five] = 5,
	[Enum.KeyCode.Six] = 6,
}

local function toggleOverlay(_, state, input)
	if state ~= Enum.UserInputState.Begin then return Enum.ContextActionResult.Sink end
	if UserInputService:GetFocusedTextBox() then return Enum.ContextActionResult.Pass end
	if input.KeyCode == Enum.KeyCode.Tab then
		if C.menuOpen then C.Panels.showMenu(false) end
		C.Panels.toggle("Inventory")
	elseif C.menuOpen then C.Panels.showMenu(false)
	else C.Panels.open("Menu") end
	return Enum.ContextActionResult.Sink
end
ContextActionService:BindActionAtPriority("RigOverlays", toggleOverlay, false, 3000, Enum.KeyCode.Tab, Enum.KeyCode.Q)
ContextActionService:BindActionAtPriority("RigPanelMovement", function()
	return C.panelOpen and Enum.ContextActionResult.Sink or Enum.ContextActionResult.Pass
end, false, 2500, Enum.PlayerActions.CharacterForward, Enum.PlayerActions.CharacterBackward,
	Enum.PlayerActions.CharacterLeft, Enum.PlayerActions.CharacterRight, Enum.PlayerActions.CharacterJump)

UserInputService.InputBegan:Connect(function(input, processed)
	if processed or UserInputService:GetFocusedTextBox() then
		return
	end
	if C.Build.input(input) then
		return
	end
	local key = input.KeyCode
	if KEY_PANELS[key] then
		if C.menuOpen then
			C.Panels.showMenu(false)
		end
		C.Panels.toggle(KEY_PANELS[key])
	elseif key == Enum.KeyCode.M then
		if C.menuOpen then
			C.Panels.showMenu(false)
		else
			C.Panels.open("Menu")
		end
	elseif C.panelOpen then
		if key == Enum.KeyCode.Backspace then C.Panels.close() end
		return
	elseif HOTKEYS[key] then
		C.send("Hotbar", HOTKEYS[key])
	elseif key == Enum.KeyCode.V then
		task.spawn(C.toggleView)
	elseif key == Enum.KeyCode.F then
		C.send("Flashlight")
		C.Viewmodel.toggled()
	elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
		-- Right mouse: drag the object in front of you; with nothing to drag, focus the beam.
		if not C.CarryClient.grab() then
			C.setFocus(true)
		end
	elseif key == Enum.KeyCode.LeftShift or key == Enum.KeyCode.RightShift then
		C.setSprint(true)
	elseif key == Enum.KeyCode.Backspace then
		C.Panels.close()
	elseif input.UserInputType == Enum.UserInputType.MouseButton1 then
		if not C.Panels.current and not C.menuOpen then
			C.useEquipped()
		end
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.KeyCode == Enum.KeyCode.LeftShift or input.KeyCode == Enum.KeyCode.RightShift then
		C.setSprint(false)
	elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
		C.CarryClient.release()
		C.setFocus(false)
	end
end)
