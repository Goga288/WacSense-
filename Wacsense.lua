
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local Stats = game:GetService("Stats")
local VirtualUser = game:GetService("VirtualUser")
local HttpService = game:GetService("HttpService")
local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")
local Camera = workspace.CurrentCamera
local Mouse = LocalPlayer:GetMouse()

local function RN()
    local c = "qwertyuiopasdfghjklzxcvbnm0123456789"
    local s = ""
    for i = 1, math.random(12, 20) do
        local x = math.random(1, #c)
        s = s .. c:sub(x, x)
    end
    return s
end

for _, g in ipairs(PlayerGui:GetChildren()) do
    if g:IsA("ScreenGui") and g:GetAttribute("_ws") then g:Destroy() end
end
pcall(function()
    for _, g in ipairs(game:GetService("CoreGui"):GetChildren()) do
        if g:GetAttribute("_ws") then g:Destroy() end
    end
end)

local Settings = {
    Rage_Enabled = false,
    Rage_SilentAim = false,
    Rage_AutoShoot = false,
    Rage_LockOn = false,
    Rage_FOV360 = true,
    Rage_FOV = 360,
    Rage_ShowFOV = false,
    Rage_TeamCheck = true,
    Rage_WallCheck = false,
    Rage_HitChance = 100,
    Rage_Smoothness = 1,
    Rage_AutoBody = false,
    Rage_ShootDelay = 100,
    Rage_Prediction = 0,
    AA_Enabled = false,
    AA_Spin = false,
    AA_SpinSpeed = 15,
    AA_Jitter = false,
    AA_JitterRange = 45,
    AA_CrouchSpam = false,
    AA_CrouchSpeed = 5,
    AA_BodyTwist = false,
    AA_RandomYaw = false,
    ESP_Enabled = false,
    ESP_Box = false,
    ESP_Name = false,
    ESP_HealthBar = false,
    ESP_Distance = false,
    ESP_Tracers = false,
    ESP_TeamCheck = true,
    ESP_MaxDistance = 2000,
    Chams_Enabled = false,
    Chams_Transparency = 30,
    Chams_ColorR = 180,
    Chams_ColorG = 120,
    Chams_ColorB = 255,
    Chams_OutlineR = 255,
    Chams_OutlineG = 255,
    Chams_OutlineB = 255,
    Crosshair_Enabled = false,
    Crosshair_Size = 6,
    Crosshair_Gap = 3,
    FullBright = false,
    NoFog = false,
    Speed_Enabled = false,
    Speed_Value = 32,
    Jump_Enabled = false,
    Jump_Value = 75,
    BHop_Enabled = false,
    InfJump = false,
    AirStrafe_Enabled = false,
    AirStrafe_Speed = 50,
    Fly_Enabled = false,
    Fly_Speed = 60,
    Noclip_Enabled = false,
    ThirdPerson_Enabled = false,
    ThirdPerson_Distance = 15,
    ThirdPerson_FOV = 90,
    Watermark_Enabled = true,
    Watermark_ShowFPS = true,
    Watermark_ShowPing = true,
    AntiDetect_Enabled = true,
    AntiDetect_SpoofSpeed = true,
    AntiDetect_SpoofJump = true,
}

local silentTarget = nil
local silentTargetPart = nil

-- Anti-Detect hooks
pcall(function()
    if not hookmetamethod or not getrawmetatable then return end
    local mt = getrawmetatable(game)
    if setreadonly then setreadonly(mt, false) end

    local oldNamecall
    oldNamecall = hookmetamethod(game, "__namecall", newcclosure(function(self, ...)
        local method = getnamecallmethod()
        local args = {...}

        if method == "GetChildren" or method == "GetDescendants" then
            local result = oldNamecall(self, ...)
            if typeof(result) == "table" then
                local filtered = {}
                for _, v in ipairs(result) do
                    if typeof(v) == "Instance" and not v:GetAttribute("_ws") then
                        table.insert(filtered, v)
                    end
                end
                return filtered
            end
            return result
        end

        if method == "FindFirstChild" or method == "FindFirstChildOfClass" or method == "FindFirstChildWhichIsA" then
            local result = oldNamecall(self, ...)
            if typeof(result) == "Instance" and result:GetAttribute("_ws") then
                return nil
            end
            return result
        end

        if Settings.Rage_Enabled and Settings.Rage_SilentAim and silentTargetPart then
            local pp = silentTargetPart.Position
            if Settings.Rage_Prediction > 0 then
                pcall(function()
                    local r = silentTargetPart.Parent:FindFirstChild("HumanoidRootPart")
                    if r then pp = pp + r.Velocity * (Settings.Rage_Prediction / 60) end
                end)
            end

            if method == "Raycast" and self == workspace and typeof(args[1]) == "Vector3" then
                args[2] = (pp - args[1]).Unit * 5000
                return oldNamecall(self, unpack(args))
            end

            if (method == "FindPartOnRay" or method == "FindPartOnRayWithWhitelist" or method == "FindPartOnRayWithIgnoreList") and typeof(args[1]) == "Ray" then
                args[1] = Ray.new(args[1].Origin, (pp - args[1].Origin).Unit * 5000)
                return oldNamecall(self, unpack(args))
            end

            if method == "FireServer" or method == "InvokeServer" then
                for i, arg in ipairs(args) do
                    if typeof(arg) == "CFrame" then
                        args[i] = CFrame.new(Camera.CFrame.Position, pp)
                    elseif typeof(arg) == "Vector3" then
                        if arg.Magnitude > 10 then
                            args[i] = pp
                        else
                            args[i] = (pp - Camera.CFrame.Position).Unit
                        end
                    end
                end
                return oldNamecall(self, unpack(args))
            end
        end

        return oldNamecall(self, ...)
    end))

    local oldIdx = mt.__index
    mt.__index = newcclosure(function(self, key)
        if Settings.Rage_Enabled and Settings.Rage_SilentAim and silentTargetPart then
            if self == Mouse then
                local pp = silentTargetPart.Position
                if key == "Hit" then return CFrame.new(pp) end
                if key == "Target" then return silentTargetPart end
                if key == "X" then return (Camera:WorldToViewportPoint(pp)).X end
                if key == "Y" then return (Camera:WorldToViewportPoint(pp)).Y end
                if key == "UnitRay" then
                    local o = Camera.CFrame.Position
                    return Ray.new(o, (pp - o).Unit)
                end
            end
        end

        if Settings.AntiDetect_Enabled then
            if typeof(self) == "Instance" and self:IsA("Humanoid") then
                if key == "WalkSpeed" and Settings.AntiDetect_SpoofSpeed and Settings.Speed_Enabled then
                    return 16
                end
                if key == "JumpPower" and Settings.AntiDetect_SpoofJump and Settings.Jump_Enabled then
                    return 50
                end
            end
        end

        return oldIdx(self, key)
    end)
end)

-- Config система
local ConfigFolder = "Wacsense"

local function EnsureFolder()
    pcall(function()
        if not isfolder(ConfigFolder) then makefolder(ConfigFolder) end
    end)
end

local function SaveConfig(name)
    EnsureFolder()
    pcall(function()
        writefile(ConfigFolder .. "/" .. name .. ".json", HttpService:JSONEncode(Settings))
    end)
end

local function LoadConfig(name)
    pcall(function()
        local path = ConfigFolder .. "/" .. name .. ".json"
        if isfile(path) then
            local loaded = HttpService:JSONDecode(readfile(path))
            for k, v in pairs(loaded) do
                if Settings[k] ~= nil then Settings[k] = v end
            end
        end
    end)
end

local function DeleteConfig(name)
    pcall(function()
        local path = ConfigFolder .. "/" .. name .. ".json"
        if isfile(path) then delfile(path) end
    end)
end

local function GetConfigs()
    local configs = {}
    pcall(function()
        if isfolder(ConfigFolder) then
            for _, f in ipairs(listfiles(ConfigFolder)) do
                local name = f:match("([^/\\]+)%.json$")
                if name then table.insert(configs, name) end
            end
        end
    end)
    return configs
end

-- Цвета
local C = {
    MainBG = Color3.fromRGB(8, 8, 10),
    SectionBG = Color3.fromRGB(12, 12, 15),
    TopBG = Color3.fromRGB(5, 5, 7),
    TabBG = Color3.fromRGB(6, 6, 8),
    TabActive = Color3.fromRGB(14, 14, 18),
    InputBG = Color3.fromRGB(4, 4, 6),
    Border = Color3.fromRGB(55, 55, 65),
    BorderBright = Color3.fromRGB(80, 80, 95),
    Accent = Color3.fromRGB(180, 120, 255),
    AccentHover = Color3.fromRGB(200, 150, 255),
    AccentDark = Color3.fromRGB(140, 80, 220),
    AccentBright = Color3.fromRGB(220, 180, 255),
    TextPrimary = Color3.fromRGB(240, 240, 245),
    TextNormal = Color3.fromRGB(190, 190, 200),
    TextDim = Color3.fromRGB(110, 110, 125),
    CheckOff = Color3.fromRGB(4, 4, 6),
    CheckBorder = Color3.fromRGB(70, 70, 85),
    EnemyColor = Color3.fromRGB(255, 70, 70),
    ButtonBG = Color3.fromRGB(20, 20, 25),
}

-- Watermark
local WMGui = Instance.new("ScreenGui")
WMGui.Name = RN()
WMGui.ResetOnSpawn = false
WMGui.IgnoreGuiInset = true
WMGui.DisplayOrder = 999
pcall(function() WMGui.Parent = game:GetService("CoreGui") end)
if not WMGui.Parent then WMGui.Parent = PlayerGui end
WMGui:SetAttribute("_ws", true)

local WMFrame = Instance.new("Frame")
WMFrame.Size = UDim2.new(0, 260, 0, 28)
WMFrame.Position = UDim2.new(1, -270, 0, 8)
WMFrame.BackgroundColor3 = Color3.new(0, 0, 0)
WMFrame.BackgroundTransparency = 0.35
WMFrame.BorderSizePixel = 0
WMFrame.ZIndex = 1000
WMFrame.Parent = WMGui

local WMTopLine = Instance.new("Frame")
WMTopLine.Size = UDim2.new(1, 0, 0, 2)
WMTopLine.BackgroundColor3 = Color3.new(1, 1, 1)
WMTopLine.BorderSizePixel = 0
WMTopLine.ZIndex = 1001
WMTopLine.Parent = WMFrame

local WMGrad = Instance.new("UIGradient")
WMGrad.Color = ColorSequence.new({
    ColorSequenceKeypoint.new(0, Color3.fromRGB(100, 60, 255)),
    ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 80, 180)),
    ColorSequenceKeypoint.new(1, Color3.fromRGB(120, 80, 255)),
})
WMGrad.Parent = WMTopLine

task.spawn(function()
    while WMTopLine.Parent do
        WMGrad.Offset = Vector2.new((WMGrad.Offset.X + 0.008) % 1, 0)
        task.wait(0.03)
    end
end)

local WMText = Instance.new("TextLabel")
WMText.Size = UDim2.new(1, -12, 1, -2)
WMText.Position = UDim2.new(0, 6, 0, 2)
WMText.BackgroundTransparency = 1
WMText.Text = "Wacsense | fps: 0 | ping: 0ms"
WMText.TextColor3 = C.AccentBright
WMText.TextSize = 12
WMText.Font = Enum.Font.GothamBold
WMText.TextXAlignment = Enum.TextXAlignment.Left
WMText.ZIndex = 1002
WMText.Parent = WMFrame

local fpsCount = 0
local fpsTmr = 0
local curFPS = 0

task.spawn(function()
    while WMGui.Parent do
        if Settings.Watermark_Enabled then
            WMFrame.Visible = true
            local parts = {"Wacsense"}
            if Settings.Watermark_ShowFPS then
                table.insert(parts, "fps: " .. curFPS)
            end
            local ping = 0
            pcall(function()
                ping = math.floor(Stats.Network.ServerStatsItem["Data Ping"]:GetValue())
            end)
            if Settings.Watermark_ShowPing then
                table.insert(parts, "ping: " .. ping .. "ms")
            end
            WMText.Text = table.concat(parts, " | ")
            local w = #WMText.Text * 7 + 20
            WMFrame.Size = UDim2.new(0, math.max(w, 100), 0, 28)
            WMFrame.Position = UDim2.new(1, -math.max(w, 100) - 8, 0, 8)
        else
            WMFrame.Visible = false
        end
        task.wait(0.3)
    end
end)

-- Main GUI
local SG = Instance.new("ScreenGui")
SG.Name = RN()
SG.ResetOnSpawn = false
SG.IgnoreGuiInset = true
SG.Parent = PlayerGui
SG:SetAttribute("_ws", true)

local Box = Instance.new("Frame")
Box.Size = UDim2.new(0, 680, 0, 440)
Box.Position = UDim2.new(0.5, -340, 0.5, -220)
Box.BackgroundColor3 = C.MainBG
Box.BorderSizePixel = 0
Box.Parent = SG

local BoxStroke = Instance.new("UIStroke")
BoxStroke.Color = C.BorderBright
BoxStroke.Thickness = 2
BoxStroke.Parent = Box

-- Top purple line
local TopLine = Instance.new("Frame")
TopLine.Size = UDim2.new(1, 0, 0, 2)
TopLine.BackgroundColor3 = Color3.new(1, 1, 1)
TopLine.BorderSizePixel = 0
TopLine.ZIndex = 10
TopLine.Parent = Box

local TLG = Instance.new("UIGradient")
TLG.Color = ColorSequence.new({
    ColorSequenceKeypoint.new(0, Color3.fromRGB(100, 60, 255)),
    ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 80, 180)),
    ColorSequenceKeypoint.new(1, Color3.fromRGB(120, 80, 255)),
})
TLG.Parent = TopLine
task.spawn(function()
    while TopLine.Parent do
        TLG.Offset = Vector2.new((TLG.Offset.X + 0.005) % 1, 0)
        task.wait(0.03)
    end
end)

-- Bottom red-purple line
local BottomLine = Instance.new("Frame")
BottomLine.Size = UDim2.new(1, 0, 0, 2)
BottomLine.Position = UDim2.new(0, 0, 1, -2)
BottomLine.BackgroundColor3 = Color3.new(1, 1, 1)
BottomLine.BorderSizePixel = 0
BottomLine.ZIndex = 10
BottomLine.Parent = Box

local BLG = Instance.new("UIGradient")
BLG.Color = ColorSequence.new({
    ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 40, 80)),
    ColorSequenceKeypoint.new(0.3, Color3.fromRGB(255, 60, 160)),
    ColorSequenceKeypoint.new(0.6, Color3.fromRGB(200, 60, 255)),
    ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 40, 80)),
})
BLG.Parent = BottomLine
task.spawn(function()
    while BottomLine.Parent do
        BLG.Offset = Vector2.new((BLG.Offset.X + 0.004) % 1, 0)
        task.wait(0.03)
    end
end)

-- Drag
local dragging = false
local dragStart = nil
local startPos = nil

Box.InputBegan:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.MouseButton1 then
        dragging = true
        dragStart = i.Position
        startPos = Box.Position
    end
end)

Box.InputChanged:Connect(function(i)
    if dragging and i.UserInputType == Enum.UserInputType.MouseMovement then
        local d = i.Position - dragStart
        Box.Position = UDim2.new(
            startPos.X.Scale, startPos.X.Offset + d.X,
            startPos.Y.Scale, startPos.Y.Offset + d.Y
        )
    end
end)

UserInputService.InputEnded:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.MouseButton1 then
        dragging = false
    end
end)

-- Top bar
local Top = Instance.new("Frame")
Top.Size = UDim2.new(1, 0, 0, 30)
Top.Position = UDim2.new(0, 0, 0, 2)
Top.BackgroundColor3 = C.TopBG
Top.BorderSizePixel = 0
Top.ZIndex = 5
Top.Parent = Box

local TopDivider = Instance.new("Frame")
TopDivider.Size = UDim2.new(1, 0, 0, 1)
TopDivider.Position = UDim2.new(0, 0, 1, 0)
TopDivider.BackgroundColor3 = C.Border
TopDivider.BorderSizePixel = 0
TopDivider.ZIndex = 6
TopDivider.Parent = Top

local Logo = Instance.new("TextLabel")
Logo.Size = UDim2.new(0, 120, 1, 0)
Logo.Position = UDim2.new(0, 12, 0, 0)
Logo.BackgroundTransparency = 1
Logo.RichText = true
Logo.Text = '<font color="rgb(200,150,255)">Wac</font><font color="rgb(240,240,245)">sense</font>'
Logo.TextSize = 15
Logo.Font = Enum.Font.GothamBlack
Logo.TextXAlignment = Enum.TextXAlignment.Left
Logo.ZIndex = 7
Logo.Parent = Top

-- Tab bar
local TabBar = Instance.new("Frame")
TabBar.Size = UDim2.new(1, 0, 0, 32)
TabBar.Position = UDim2.new(0, 0, 0, 33)
TabBar.BackgroundColor3 = C.TabBG
TabBar.BorderSizePixel = 0
TabBar.ZIndex = 4
TabBar.Parent = Box

local TabBarLine = Instance.new("Frame")
TabBarLine.Size = UDim2.new(1, 0, 0, 1)
TabBarLine.Position = UDim2.new(0, 0, 1, 0)
TabBarLine.BackgroundColor3 = C.Border
TabBarLine.BorderSizePixel = 0
TabBarLine.ZIndex = 5
TabBarLine.Parent = TabBar

local Content = Instance.new("Frame")
Content.Size = UDim2.new(1, -12, 1, -72)
Content.Position = UDim2.new(0, 6, 0, 68)
Content.BackgroundTransparency = 1
Content.ZIndex = 2
Content.Parent = Box

local function MkSec(parent, title, size, pos)
    local s = Instance.new("Frame")
    s.Size = size
    s.Position = pos
    s.BackgroundColor3 = C.SectionBG
    s.BorderSizePixel = 0
    s.ZIndex = 2
    s.Parent = parent

    local st = Instance.new("UIStroke")
    st.Color = C.Border
    st.Thickness = 1
    st.Parent = s

    local hdr = Instance.new("Frame")
    hdr.Size = UDim2.new(1, 0, 0, 22)
    hdr.BackgroundColor3 = Color3.fromRGB(8, 8, 10)
    hdr.BorderSizePixel = 0
    hdr.ZIndex = 3
    hdr.Parent = s

    local acc = Instance.new("Frame")
    acc.Size = UDim2.new(0, 3, 0, 12)
    acc.Position = UDim2.new(0, 6, 0.5, -6)
    acc.BackgroundColor3 = C.Accent
    acc.BorderSizePixel = 0
    acc.ZIndex = 4
    acc.Parent = hdr

    local tl = Instance.new("TextLabel")
    tl.Size = UDim2.new(1, -16, 1, 0)
    tl.Position = UDim2.new(0, 14, 0, 0)
    tl.BackgroundTransparency = 1
    tl.Text = title:upper()
    tl.TextColor3 = C.TextPrimary
    tl.TextSize = 10
    tl.Font = Enum.Font.GothamBold
    tl.TextXAlignment = Enum.TextXAlignment.Left
    tl.ZIndex = 4
    tl.Parent = hdr

    local hl = Instance.new("Frame")
    hl.Size = UDim2.new(1, 0, 0, 1)
    hl.Position = UDim2.new(0, 0, 1, 0)
    hl.BackgroundColor3 = C.Border
    hl.BorderSizePixel = 0
    hl.ZIndex = 4
    hl.Parent = hdr

    local pad = Instance.new("UIPadding")
    pad.PaddingTop = UDim.new(0, 26)
    pad.PaddingLeft = UDim.new(0, 4)
    pad.PaddingRight = UDim.new(0, 4)
    pad.PaddingBottom = UDim.new(0, 4)
    pad.Parent = s

    local lay = Instance.new("UIListLayout")
    lay.Padding = UDim.new(0, 1)
    lay.Parent = s

    return s
end

local function MkChk(parent, text, key, ord)
    local f = Instance.new("Frame")
    f.Size = UDim2.new(1, 0, 0, 18)
    f.BackgroundTransparency = 1
    f.LayoutOrder = ord or 0
    f.ZIndex = 3
    f.Parent = parent

    local en = Settings[key]

    local bx = Instance.new("Frame")
    bx.Size = UDim2.new(0, 10, 0, 10)
    bx.Position = UDim2.new(0, 8, 0, 4)
    bx.BackgroundColor3 = en and C.Accent or C.CheckOff
    bx.BorderSizePixel = 0
    bx.ZIndex = 4
    bx.Parent = f

    local bs = Instance.new("UIStroke", bx)
    bs.Color = en and C.AccentDark or C.CheckBorder
    bs.Thickness = 1

    local lb = Instance.new("TextLabel")
    lb.Size = UDim2.new(1, -28, 0, 18)
    lb.Position = UDim2.new(0, 24, 0, 0)
    lb.BackgroundTransparency = 1
    lb.Text = text
    lb.TextColor3 = en and C.TextPrimary or C.TextNormal
    lb.TextSize = 11
    lb.Font = Enum.Font.Gotham
    lb.TextXAlignment = Enum.TextXAlignment.Left
    lb.ZIndex = 4
    lb.Parent = f

    local bt = Instance.new("TextButton")
    bt.Size = UDim2.new(1, 0, 1, 0)
    bt.BackgroundTransparency = 1
    bt.Text = ""
    bt.ZIndex = 5
    bt.Parent = f

    bt.MouseButton1Click:Connect(function()
        Settings[key] = not Settings[key]
        local e = Settings[key]
        bx.BackgroundColor3 = e and C.Accent or C.CheckOff
        bs.Color = e and C.AccentDark or C.CheckBorder
        lb.TextColor3 = e and C.TextPrimary or C.TextNormal
    end)
end

local function MkSld(parent, text, key, mn, mx, suf, ord)
    suf = suf or ""
    local f = Instance.new("Frame")
    f.Size = UDim2.new(1, 0, 0, 28)
    f.BackgroundTransparency = 1
    f.LayoutOrder = ord or 0
    f.ZIndex = 3
    f.Parent = parent

    local lb = Instance.new("TextLabel")
    lb.Size = UDim2.new(0, 130, 0, 12)
    lb.Position = UDim2.new(0, 8, 0, 0)
    lb.BackgroundTransparency = 1
    lb.Text = text
    lb.TextColor3 = C.TextNormal
    lb.TextSize = 10
    lb.Font = Enum.Font.Gotham
    lb.TextXAlignment = Enum.TextXAlignment.Left
    lb.ZIndex = 4
    lb.Parent = f

    local cur = Settings[key]
    local pct = math.clamp((cur - mn) / (mx - mn), 0, 1)

    local vl = Instance.new("TextLabel")
    vl.Size = UDim2.new(0, 50, 0, 12)
    vl.Position = UDim2.new(1, -58, 0, 0)
    vl.BackgroundTransparency = 1
    vl.Text = math.floor(cur) .. suf
    vl.TextColor3 = C.AccentBright
    vl.TextSize = 10
    vl.Font = Enum.Font.GothamBold
    vl.TextXAlignment = Enum.TextXAlignment.Right
    vl.ZIndex = 4
    vl.Parent = f

    local tk = Instance.new("Frame")
    tk.Size = UDim2.new(1, -16, 0, 6)
    tk.Position = UDim2.new(0, 8, 0, 16)
    tk.BackgroundColor3 = C.InputBG
    tk.BorderSizePixel = 0
    tk.ZIndex = 4
    tk.Parent = f

    local tks = Instance.new("UIStroke", tk)
    tks.Color = C.Border
    tks.Thickness = 1

    local fl = Instance.new("Frame")
    fl.Size = UDim2.new(pct, -1, 1, -2)
    fl.Position = UDim2.new(0, 1, 0, 1)
    fl.BackgroundColor3 = C.Accent
    fl.BorderSizePixel = 0
    fl.ZIndex = 5
    fl.Parent = tk

    local fg = Instance.new("UIGradient")
    fg.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, C.AccentHover),
        ColorSequenceKeypoint.new(1, C.AccentDark),
    })
    fg.Parent = fl

    local sb = Instance.new("TextButton")
    sb.Size = UDim2.new(1, 0, 0, 14)
    sb.Position = UDim2.new(0, 0, 0, -4)
    sb.BackgroundTransparency = 1
    sb.Text = ""
    sb.ZIndex = 6
    sb.Parent = tk

    local sliding = false

    sb.MouseButton1Down:Connect(function()
        sliding = true
    end)

    UserInputService.InputEnded:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 then
            sliding = false
        end
    end)

    UserInputService.InputChanged:Connect(function(i)
        if sliding and i.UserInputType == Enum.UserInputType.MouseMovement then
            local p = math.clamp((i.Position.X - tk.AbsolutePosition.X) / tk.AbsoluteSize.X, 0, 1)
            fl.Size = UDim2.new(p, -1, 1, -2)
            local val = math.floor(mn + (mx - mn) * p)
            Settings[key] = val
            vl.Text = val .. suf
        end
    end)
end

local function MkBtn(parent, text, callback, ord)
    local bt = Instance.new("TextButton")
    bt.Size = UDim2.new(1, -16, 0, 20)
    bt.BackgroundColor3 = C.ButtonBG
    bt.BorderSizePixel = 0
    bt.Text = text
    bt.TextColor3 = C.TextPrimary
    bt.TextSize = 10
    bt.Font = Enum.Font.GothamBold
    bt.AutoButtonColor = false
    bt.ZIndex = 4
    bt.LayoutOrder = ord or 0
    bt.Parent = parent

    local bts = Instance.new("UIStroke", bt)
    bts.Color = C.Border

    bt.MouseEnter:Connect(function()
        bt.BackgroundColor3 = Color3.fromRGB(30, 30, 38)
    end)
    bt.MouseLeave:Connect(function()
        bt.BackgroundColor3 = C.ButtonBG
    end)
    bt.MouseButton1Click:Connect(callback or function() end)
end

-- Pages
local pages = {}
local function MkPage(name)
    local p = Instance.new("Frame")
    p.Size = UDim2.new(1, 0, 1, 0)
    p.BackgroundTransparency = 1
    p.Visible = false
    p.ZIndex = 2
    p.Parent = Content
    pages[name] = p
    return p
end


local P1 = MkPage("Rage")
P1.Visible = true

local RS = MkSec(P1, "Rage Aimbot", UDim2.new(0, 330, 1, 0), UDim2.new(0, 0, 0, 0))
local o = 0
MkChk(RS, "Enable", "Rage_Enabled", o); o += 1
MkChk(RS, "Silent Aim", "Rage_SilentAim", o); o += 1
MkChk(RS, "Auto Shoot", "Rage_AutoShoot", o); o += 1
MkChk(RS, "Lock On (RMB)", "Rage_LockOn", o); o += 1
MkChk(RS, "360° FOV", "Rage_FOV360", o); o += 1
MkSld(RS, "FOV", "Rage_FOV", 10, 360, "°", o); o += 1
MkChk(RS, "Show FOV", "Rage_ShowFOV", o); o += 1
MkSld(RS, "Hit Chance", "Rage_HitChance", 1, 100, "%", o); o += 1
MkSld(RS, "Smoothness", "Rage_Smoothness", 1, 20, "", o); o += 1
MkSld(RS, "Delay", "Rage_ShootDelay", 50, 500, "ms", o); o += 1
MkSld(RS, "Prediction", "Rage_Prediction", 0, 20, "", o); o += 1
MkChk(RS, "Team Check", "Rage_TeamCheck", o); o += 1
MkChk(RS, "Wall Check", "Rage_WallCheck", o); o += 1
MkChk(RS, "Auto Body", "Rage_AutoBody", o); o += 1

local AS = MkSec(P1, "Anti-Aim", UDim2.new(0, 330, 1, 0), UDim2.new(0, 338, 0, 0))
local a = 0
MkChk(AS, "Enable", "AA_Enabled", a); a += 1
MkChk(AS, "Spin", "AA_Spin", a); a += 1
MkSld(AS, "Speed", "AA_SpinSpeed", 1, 50, "", a); a += 1
MkChk(AS, "Jitter", "AA_Jitter", a); a += 1
MkSld(AS, "Range", "AA_JitterRange", 5, 180, "°", a); a += 1
MkChk(AS, "Crouch Spam", "AA_CrouchSpam", a); a += 1
MkSld(AS, "Crouch Speed", "AA_CrouchSpeed", 1, 20, "", a); a += 1
MkChk(AS, "Body Twist", "AA_BodyTwist", a); a += 1
MkChk(AS, "Random Yaw", "AA_RandomYaw", a); a += 1


local P2 = MkPage("Visuals")

local ES = MkSec(P2, "ESP", UDim2.new(0, 330, 1, 0), UDim2.new(0, 0, 0, 0))
o = 0
MkChk(ES, "Enable", "ESP_Enabled", o); o += 1
MkChk(ES, "Box", "ESP_Box", o); o += 1
MkChk(ES, "Name", "ESP_Name", o); o += 1
MkChk(ES, "Health Bar", "ESP_HealthBar", o); o += 1
MkChk(ES, "Distance", "ESP_Distance", o); o += 1
MkChk(ES, "Tracers", "ESP_Tracers", o); o += 1
MkChk(ES, "Team Check", "ESP_TeamCheck", o); o += 1
MkSld(ES, "Max Dist", "ESP_MaxDistance", 100, 5000, "m", o); o += 1

local EF = MkSec(P2, "Chams / Effects", UDim2.new(0, 330, 1, 0), UDim2.new(0, 338, 0, 0))
local v = 0
MkChk(EF, "Chams", "Chams_Enabled", v); v += 1
MkSld(EF, "Transparency", "Chams_Transparency", 0, 100, "%", v); v += 1
MkSld(EF, "Fill R", "Chams_ColorR", 0, 255, "", v); v += 1
MkSld(EF, "Fill G", "Chams_ColorG", 0, 255, "", v); v += 1
MkSld(EF, "Fill B", "Chams_ColorB", 0, 255, "", v); v += 1
MkSld(EF, "Outline R", "Chams_OutlineR", 0, 255, "", v); v += 1
MkSld(EF, "Outline G", "Chams_OutlineG", 0, 255, "", v); v += 1
MkSld(EF, "Outline B", "Chams_OutlineB", 0, 255, "", v); v += 1
MkChk(EF, "Crosshair", "Crosshair_Enabled", v); v += 1
MkSld(EF, "Size", "Crosshair_Size", 2, 20, "px", v); v += 1
MkSld(EF, "Gap", "Crosshair_Gap", 0, 15, "px", v); v += 1
MkChk(EF, "Fullbright", "FullBright", v); v += 1
MkChk(EF, "No Fog", "NoFog", v); v += 1


local P3 = MkPage("Misc")

local MV = MkSec(P3, "Movement", UDim2.new(0, 330, 1, 0), UDim2.new(0, 0, 0, 0))
local m = 0
MkChk(MV, "Speed", "Speed_Enabled", m); m += 1
MkSld(MV, "Value", "Speed_Value", 16, 200, "", m); m += 1
MkChk(MV, "Jump", "Jump_Enabled", m); m += 1
MkSld(MV, "Power", "Jump_Value", 50, 300, "", m); m += 1
MkChk(MV, "Inf Jump", "InfJump", m); m += 1
MkChk(MV, "BHop", "BHop_Enabled", m); m += 1
MkChk(MV, "Air Strafe", "AirStrafe_Enabled", m); m += 1
MkSld(MV, "Strafe Spd", "AirStrafe_Speed", 10, 150, "", m); m += 1
MkChk(MV, "Fly", "Fly_Enabled", m); m += 1
MkSld(MV, "Fly Speed", "Fly_Speed", 10, 200, "", m); m += 1
MkChk(MV, "Noclip", "Noclip_Enabled", m); m += 1

local CF = MkSec(P3, "Config / Settings", UDim2.new(0, 330, 1, 0), UDim2.new(0, 338, 0, 0))
local cf = 0

local cfgNameFrame = Instance.new("Frame")
cfgNameFrame.Size = UDim2.new(1, -16, 0, 22)
cfgNameFrame.BackgroundColor3 = C.InputBG
cfgNameFrame.BorderSizePixel = 0
cfgNameFrame.LayoutOrder = cf
cfgNameFrame.ZIndex = 4
cfgNameFrame.Parent = CF
Instance.new("UIStroke", cfgNameFrame).Color = C.Border
cf += 1

local cfgInput = Instance.new("TextBox")
cfgInput.Size = UDim2.new(1, -8, 1, 0)
cfgInput.Position = UDim2.new(0, 4, 0, 0)
cfgInput.BackgroundTransparency = 1
cfgInput.Text = ""
cfgInput.PlaceholderText = "config name..."
cfgInput.TextColor3 = C.TextPrimary
cfgInput.PlaceholderColor3 = C.TextDim
cfgInput.TextSize = 11
cfgInput.Font = Enum.Font.Gotham
cfgInput.TextXAlignment = Enum.TextXAlignment.Left
cfgInput.ZIndex = 5
cfgInput.ClearTextOnFocus = false
cfgInput.Parent = cfgNameFrame

MkBtn(CF, "SAVE CONFIG", function()
    local name = cfgInput.Text
    if name and #name > 0 then
        SaveConfig(name)
        print("[Wacsense] Saved: " .. name)
    end
end, cf); cf += 1

MkBtn(CF, "LOAD CONFIG", function()
    local name = cfgInput.Text
    if name and #name > 0 then
        LoadConfig(name)
        print("[Wacsense] Loaded: " .. name)
    end
end, cf); cf += 1

MkBtn(CF, "DELETE CONFIG", function()
    local name = cfgInput.Text
    if name and #name > 0 then
        DeleteConfig(name)
        print("[Wacsense] Deleted: " .. name)
    end
end, cf); cf += 1

MkBtn(CF, "LIST CONFIGS", function()
    local cfgs = GetConfigs()
    print("[Wacsense] Configs: " .. table.concat(cfgs, ", "))
end, cf); cf += 1

MkChk(CF, "Anti-Detect", "AntiDetect_Enabled", cf); cf += 1
MkChk(CF, "Spoof Speed", "AntiDetect_SpoofSpeed", cf); cf += 1
MkChk(CF, "Spoof Jump", "AntiDetect_SpoofJump", cf); cf += 1
MkChk(CF, "Watermark", "Watermark_Enabled", cf); cf += 1
MkChk(CF, "Show FPS", "Watermark_ShowFPS", cf); cf += 1
MkChk(CF, "Show Ping", "Watermark_ShowPing", cf); cf += 1


local P4 = MkPage("Player")

local CM = MkSec(P4, "Camera", UDim2.new(0, 330, 1, 0), UDim2.new(0, 0, 0, 0))
local c = 0
MkChk(CM, "3rd Person", "ThirdPerson_Enabled", c); c += 1
MkSld(CM, "Distance", "ThirdPerson_Distance", 5, 50, "", c); c += 1
MkSld(CM, "FOV", "ThirdPerson_FOV", 30, 120, "°", c); c += 1


local tabIcons = {}
local tabNames = {"Rage", "Visuals", "Misc", "Player"}
local TW = 120

for i, name in ipairs(tabNames) do
    local active = (name == "Rage")
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(0, TW, 1, -2)
    btn.Position = UDim2.new(0, (i - 1) * TW + 6, 0, 1)
    btn.BackgroundColor3 = active and C.TabActive or C.TabBG
    btn.BorderSizePixel = 0
    btn.Text = name:upper()
    btn.TextColor3 = active and C.AccentBright or C.TextDim
    btn.TextSize = 11
    btn.Font = Enum.Font.GothamBold
    btn.AutoButtonColor = false
    btn.ZIndex = 5
    btn.Parent = TabBar

    local ind = Instance.new("Frame")
    ind.Size = UDim2.new(1, 0, 0, 2)
    ind.Position = UDim2.new(0, 0, 1, -2)
    ind.BackgroundColor3 = C.Accent
    ind.BorderSizePixel = 0
    ind.Visible = active
    ind.ZIndex = 6
    ind.Parent = btn

    tabIcons[name] = {button = btn, indicator = ind}
end

local currentTab = "Rage"

local function SwitchTab(name)
    if currentTab == name then return end
    currentTab = name
    for n, d in pairs(tabIcons) do
        local act = (n == name)
        d.button.BackgroundColor3 = act and C.TabActive or C.TabBG
        d.button.TextColor3 = act and C.AccentBright or C.TextDim
        d.indicator.Visible = act
    end
    for _, pg in pairs(pages) do
        pg.Visible = false
    end
    if pages[name] then
        pages[name].Visible = true
    end
end

for name, data in pairs(tabIcons) do
    data.button.MouseButton1Click:Connect(function()
        SwitchTab(name)
    end)
    data.button.MouseEnter:Connect(function()
        if currentTab ~= name then
            data.button.TextColor3 = C.TextNormal
        end
    end)
    data.button.MouseLeave:Connect(function()
        if currentTab ~= name then
            data.button.TextColor3 = C.TextDim
        end
    end)
end



local function IsAlive(p)
    local c = p.Character
    if not c then return false end
    local h = c:FindFirstChildOfClass("Humanoid")
    return h and h.Health > 0
end

local function CanSee(fp, tp)
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    local fl = {}
    if LocalPlayer.Character then table.insert(fl, LocalPlayer.Character) end
    params.FilterDescendantsInstances = fl
    local r = workspace:Raycast(fp, (tp.Position - fp), params)
    if r then
        return r.Instance:FindFirstAncestorOfClass("Model") == tp:FindFirstAncestorOfClass("Model")
    end
    return true
end

local function GetTP(p)
    if not p or not p.Character then return nil end
    if Settings.Rage_AutoBody then
        return p.Character:FindFirstChild("HumanoidRootPart") or p.Character:FindFirstChild("Torso")
    end
    return p.Character:FindFirstChild("Head")
end

local function GetTarget()
    if not Settings.Rage_Enabled then return nil end
    local cl, cd = nil, math.huge
    local mc = LocalPlayer.Character
    if not mc then return nil end
    local mr = mc:FindFirstChild("HumanoidRootPart")
    if not mr then return nil end
    local mp = UserInputService:GetMouseLocation()

    for _, p in ipairs(Players:GetPlayers()) do
        if p == LocalPlayer or not IsAlive(p) then continue end
        if Settings.Rage_TeamCheck and p.Team == LocalPlayer.Team and p.Team ~= nil then continue end
        local tp = GetTP(p)
        if not tp then continue end
        if Settings.Rage_WallCheck and not CanSee(Camera.CFrame.Position, tp) then continue end

        if Settings.Rage_FOV360 then
            local d = (tp.Position - mr.Position).Magnitude
            if d < cd then cd = d; cl = p end
        else
            local sp, os = Camera:WorldToViewportPoint(tp.Position)
            if os then
                local d2 = (Vector2.new(sp.X, sp.Y) - mp).Magnitude
                if d2 < Settings.Rage_FOV and d2 < cd then cd = d2; cl = p end
            end
        end
    end
    return cl
end

local lastShoot = 0

local function Shoot()
    local c = LocalPlayer.Character
    if not c then return end
    pcall(function()
        local t = c:FindFirstChildOfClass("Tool")
        if t then t:Activate() end
    end)
    pcall(function()
        VirtualUser:CaptureController()
        VirtualUser:Button1Down(Vector2.new(0, 0), Camera.CFrame)
        task.delay(0.05, function()
            pcall(function() VirtualUser:Button1Up(Vector2.new(0, 0), Camera.CFrame) end)
        end)
    end)
    pcall(function()
        if mouse1click then mouse1click() end
    end)
end

local aaAngle = 0
local aaTick = 0
local crouchTick = 0

local function DoAA(dt)
    if not Settings.AA_Enabled then return end
    local c = LocalPlayer.Character
    if not c then return end
    local r = c:FindFirstChild("HumanoidRootPart")
    local h = c:FindFirstChildOfClass("Humanoid")
    if not r or not h then return end

    aaTick += 1
    local yaw = 0

    if Settings.AA_Spin then
        aaAngle = (aaAngle + Settings.AA_SpinSpeed * 6 * dt) % 360
        yaw = aaAngle
    end

    if Settings.AA_Jitter then
        local rg = Settings.AA_JitterRange
        yaw = yaw + (aaTick % 2 == 0 and rg or -rg)
    end

    if Settings.AA_RandomYaw then
        yaw = yaw + math.random(-180, 180)
    end

    if Settings.AA_BodyTwist then
        yaw = yaw + math.sin(tick() * 8) * 90
    end

    local cl = Camera.CFrame.LookVector
    r.CFrame = CFrame.new(r.Position) * CFrame.Angles(0, math.atan2(cl.X, cl.Z) + math.rad(yaw + 180), 0)

    if Settings.AA_CrouchSpam then
        crouchTick += 1
        if crouchTick % math.max(1, math.floor(20 / Settings.AA_CrouchSpeed)) == 0 then
            h:ChangeState(Enum.HumanoidStateType.Seated)
            task.delay(0.05, function()
                pcall(function() h:ChangeState(Enum.HumanoidStateType.Running) end)
            end)
        end
    end
end

-- ESP
local ESPObj = {}

local function MkESP(p)
    if ESPObj[p] then return end
    local d = {}
    pcall(function()
        d.BoxO = Drawing.new("Square"); d.BoxO.Visible = false; d.BoxO.Color = Color3.new(0,0,0); d.BoxO.Thickness = 3; d.BoxO.Filled = false
        d.Box = Drawing.new("Square"); d.Box.Visible = false; d.Box.Color = C.EnemyColor; d.Box.Thickness = 1; d.Box.Filled = false
        d.Name = Drawing.new("Text"); d.Name.Visible = false; d.Name.Color = Color3.new(1,1,1); d.Name.Size = 13; d.Name.Center = true; d.Name.Outline = true; d.Name.Font = 2
        d.HBG = Drawing.new("Line"); d.HBG.Visible = false; d.HBG.Color = Color3.new(0,0,0); d.HBG.Thickness = 4
        d.HB = Drawing.new("Line"); d.HB.Visible = false; d.HB.Thickness = 2
        d.Dist = Drawing.new("Text"); d.Dist.Visible = false; d.Dist.Color = Color3.fromRGB(200,200,200); d.Dist.Size = 12; d.Dist.Center = true; d.Dist.Outline = true; d.Dist.Font = 2
        d.TO = Drawing.new("Line"); d.TO.Visible = false; d.TO.Color = Color3.new(0,0,0); d.TO.Thickness = 3
        d.T = Drawing.new("Line"); d.T.Visible = false; d.T.Color = C.EnemyColor; d.T.Thickness = 1
    end)
    ESPObj[p] = d
end

local function RmESP(p)
    if ESPObj[p] then
        for _, o in pairs(ESPObj[p]) do pcall(function() o:Remove() end) end
        ESPObj[p] = nil
    end
end

local function HdESP(d)
    for _, o in pairs(d) do pcall(function() o.Visible = false end) end
end

local function UpdESP(p, d)
    if not d.Box then HdESP(d); return end
    local ch = p.Character
    if not ch then HdESP(d); return end
    local h = ch:FindFirstChildOfClass("Humanoid")
    local r = ch:FindFirstChild("HumanoidRootPart")
    local hd = ch:FindFirstChild("Head")
    if not h or not r or not hd or h.Health <= 0 then HdESP(d); return end
    if Settings.ESP_TeamCheck and p.Team == LocalPlayer.Team and p.Team ~= nil then HdESP(d); return end

    local mr = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
    local dist = mr and (r.Position - mr.Position).Magnitude or 0
    if dist > Settings.ESP_MaxDistance then HdESP(d); return end

    local pos, os = Camera:WorldToViewportPoint(r.Position)
    if not os then HdESP(d); return end

    local hp_v = Camera:WorldToViewportPoint(hd.Position + Vector3.new(0, 1.5, 0))
    local fp_v = Camera:WorldToViewportPoint(r.Position - Vector3.new(0, 3, 0))
    local bH = math.abs(fp_v.Y - hp_v.Y)
    local bW = bH * 0.55

    if Settings.ESP_Box then
        d.BoxO.Size = Vector2.new(bW, bH)
        d.BoxO.Position = Vector2.new(pos.X - bW/2, hp_v.Y)
        d.BoxO.Visible = true
        d.Box.Size = Vector2.new(bW, bH)
        d.Box.Position = Vector2.new(pos.X - bW/2, hp_v.Y)
        d.Box.Color = C.EnemyColor
        d.Box.Visible = true
    else
        d.BoxO.Visible = false
        d.Box.Visible = false
    end

    if Settings.ESP_Name then
        d.Name.Position = Vector2.new(pos.X, hp_v.Y - 16)
        d.Name.Text = p.DisplayName
        d.Name.Visible = true
    else
        d.Name.Visible = false
    end

    local hp = math.clamp(h.Health / h.MaxHealth, 0, 1)

    if Settings.ESP_HealthBar then
        local bx = pos.X - bW/2 - 5
        d.HBG.From = Vector2.new(bx, fp_v.Y)
        d.HBG.To = Vector2.new(bx, hp_v.Y)
        d.HBG.Visible = true
        d.HB.From = Vector2.new(bx, fp_v.Y)
        d.HB.To = Vector2.new(bx, fp_v.Y - bH * hp)
        d.HB.Color = Color3.fromRGB(255 * (1 - hp), 255 * hp, 0)
        d.HB.Visible = true
    else
        d.HBG.Visible = false
        d.HB.Visible = false
    end

    if Settings.ESP_Distance then
        d.Dist.Position = Vector2.new(pos.X, fp_v.Y + 2)
        d.Dist.Text = math.floor(dist) .. "m"
        d.Dist.Visible = true
    else
        d.Dist.Visible = false
    end

    if Settings.ESP_Tracers then
        local ss = Camera.ViewportSize
        d.TO.From = Vector2.new(ss.X/2, ss.Y)
        d.TO.To = Vector2.new(pos.X, fp_v.Y)
        d.TO.Visible = true
        d.T.From = Vector2.new(ss.X/2, ss.Y)
        d.T.To = Vector2.new(pos.X, fp_v.Y)
        d.T.Color = C.EnemyColor
        d.T.Visible = true
    else
        d.TO.Visible = false
        d.T.Visible = false
    end
end

-- Chams
local ChamsObj = {}

local function UpdChams(p)
    local ch = p.Character
    if not ch or not Settings.Chams_Enabled then
        if ChamsObj[p] then
            pcall(function() ChamsObj[p]:Destroy() end)
            ChamsObj[p] = nil
        end
        return
    end

    local h = ch:FindFirstChildOfClass("Humanoid")
    if not h or h.Health <= 0 then
        if ChamsObj[p] then
            pcall(function() ChamsObj[p]:Destroy() end)
            ChamsObj[p] = nil
        end
        return
    end

    if Settings.ESP_TeamCheck and p.Team == LocalPlayer.Team and p.Team ~= nil then
        if ChamsObj[p] then
            pcall(function() ChamsObj[p]:Destroy() end)
            ChamsObj[p] = nil
        end
        return
    end

    local fillColor = Color3.fromRGB(Settings.Chams_ColorR, Settings.Chams_ColorG, Settings.Chams_ColorB)
    local outlineColor = Color3.fromRGB(Settings.Chams_OutlineR, Settings.Chams_OutlineG, Settings.Chams_OutlineB)

    if not ChamsObj[p] then
        local hi = Instance.new("Highlight")
        hi.FillColor = fillColor
        hi.OutlineColor = outlineColor
        hi.FillTransparency = Settings.Chams_Transparency / 100
        hi.OutlineTransparency = 0.2
        hi.Adornee = ch
        hi.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
        hi.Parent = game:GetService("CoreGui")
        hi:SetAttribute("_ws", true)
        ChamsObj[p] = hi
    else
        ChamsObj[p].FillColor = fillColor
        ChamsObj[p].OutlineColor = outlineColor
        ChamsObj[p].FillTransparency = Settings.Chams_Transparency / 100
        ChamsObj[p].Adornee = ch
    end
end

-- Drawing objects
local FOVCircle = nil
pcall(function()
    FOVCircle = Drawing.new("Circle")
    FOVCircle.Color = C.Accent
    FOVCircle.Thickness = 1
    FOVCircle.Filled = false
    FOVCircle.Visible = false
    FOVCircle.NumSides = 64
end)

local crosshairLines = {}
pcall(function()
    for i = 1, 4 do
        local l = Drawing.new("Line")
        l.Color = C.Accent
        l.Thickness = 1
        l.Visible = false
        crosshairLines[i] = l
    end
end)

-- World effects
local origL = {}
local savedF = {}

local function DoFB()
    local l = game:GetService("Lighting")
    if Settings.FullBright then
        if not origL.s then
            origL.A = l.Ambient
            origL.B = l.Brightness
            origL.O = l.OutdoorAmbient
            origL.s = true
        end
        l.Ambient = Color3.fromRGB(200, 200, 200)
        l.Brightness = 2
        l.OutdoorAmbient = Color3.fromRGB(200, 200, 200)
    elseif origL.s then
        l.Ambient = origL.A
        l.Brightness = origL.B
        l.OutdoorAmbient = origL.O
        origL.s = false
    end
end

local function DoNF()
    local l = game:GetService("Lighting")
    if Settings.NoFog then
        if not savedF.s then
            savedF.E = l.FogEnd
            savedF.S = l.FogStart
            savedF.s = true
        end
        l.FogEnd = 9e9
        l.FogStart = 9e9
    elseif savedF.s then
        l.FogEnd = savedF.E
        l.FogStart = savedF.S
        savedF.s = false
    end
end

-- Movement
local flyBV = nil

UserInputService.JumpRequest:Connect(function()
    if Settings.InfJump then
        local c = LocalPlayer.Character
        if c then
            local h = c:FindFirstChildOfClass("Humanoid")
            if h then
                h:ChangeState(Enum.HumanoidStateType.Jumping)
            end
        end
    end
end)

-- Camera
local origCam = {}
local tp3 = false

local function Do3P()
    if Settings.ThirdPerson_Enabled then
        if not tp3 then
            origCam.CM = LocalPlayer.CameraMode
            origCam.MN = LocalPlayer.CameraMinZoomDistance
            origCam.MX = LocalPlayer.CameraMaxZoomDistance
            origCam.FV = Camera.FieldOfView
            tp3 = true
        end
        LocalPlayer.CameraMode = Enum.CameraMode.Classic
        LocalPlayer.CameraMinZoomDistance = Settings.ThirdPerson_Distance
        LocalPlayer.CameraMaxZoomDistance = Settings.ThirdPerson_Distance
        Camera.FieldOfView = Settings.ThirdPerson_FOV
    elseif tp3 then
        LocalPlayer.CameraMode = origCam.CM or Enum.CameraMode.Classic
        LocalPlayer.CameraMinZoomDistance = origCam.MN or 0.5
        LocalPlayer.CameraMaxZoomDistance = origCam.MX or 128
        Camera.FieldOfView = origCam.FV or 70
        tp3 = false
    end
end

-- ==================== MAIN LOOPS ====================
RunService.Heartbeat:Connect(function(dt)
    local c = LocalPlayer.Character
    local h = c and c:FindFirstChildOfClass("Humanoid")
    local r = c and c:FindFirstChild("HumanoidRootPart")

    if h then
        if Settings.Speed_Enabled then h.WalkSpeed = Settings.Speed_Value end
        if Settings.Jump_Enabled then h.JumpPower = Settings.Jump_Value; h.UseJumpPower = true end
    end

    if Settings.BHop_Enabled and h and r then
        if h.FloorMaterial ~= Enum.Material.Air then
            h:ChangeState(Enum.HumanoidStateType.Jumping)
        end
    end

    if Settings.AirStrafe_Enabled and h and r then
        if h:GetState() == Enum.HumanoidStateType.Freefall then
            local md = h.MoveDirection
            if md.Magnitude > 0 then
                local sf = md * Settings.AirStrafe_Speed * dt * 60
                r.Velocity = Vector3.new(r.Velocity.X + sf.X, r.Velocity.Y, r.Velocity.Z + sf.Z)
            end
        end
    end

    if Settings.Fly_Enabled and r then
        if not flyBV then
            flyBV = Instance.new("BodyVelocity")
            flyBV.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
            flyBV.Parent = r
        end
        local d = Vector3.zero
        if UserInputService:IsKeyDown(Enum.KeyCode.W) then d = d + Camera.CFrame.LookVector end
        if UserInputService:IsKeyDown(Enum.KeyCode.S) then d = d - Camera.CFrame.LookVector end
        if UserInputService:IsKeyDown(Enum.KeyCode.A) then d = d - Camera.CFrame.RightVector end
        if UserInputService:IsKeyDown(Enum.KeyCode.D) then d = d + Camera.CFrame.RightVector end
        if UserInputService:IsKeyDown(Enum.KeyCode.Space) then d = d + Vector3.yAxis end
        if UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) then d = d - Vector3.yAxis end
        if d.Magnitude > 0 then d = d.Unit end
        flyBV.Velocity = d * Settings.Fly_Speed
    else
        if flyBV then flyBV:Destroy(); flyBV = nil end
    end

    if Settings.Noclip_Enabled and c then
        for _, p in ipairs(c:GetDescendants()) do
            if p:IsA("BasePart") then p.CanCollide = false end
        end
    end

    DoAA(dt)
end)

RunService.RenderStepped:Connect(function(dt)
    Camera = workspace.CurrentCamera
    fpsCount = fpsCount + 1
    fpsTmr = fpsTmr + dt
    if fpsTmr >= 0.5 then
        curFPS = math.floor(fpsCount / fpsTmr)
        fpsCount = 0
        fpsTmr = 0
    end

    -- Rage aimbot
    if Settings.Rage_Enabled then
        silentTarget = GetTarget()
        silentTargetPart = silentTarget and GetTP(silentTarget) or nil

        if silentTarget and silentTargetPart then
            local pp = silentTargetPart.Position
            if Settings.Rage_Prediction > 0 then
                pcall(function()
                    local r = silentTargetPart.Parent:FindFirstChild("HumanoidRootPart")
                    if r then pp = pp + r.Velocity * (Settings.Rage_Prediction / 60) end
                end)
            end

            if Settings.Rage_LockOn and UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2) then
                if math.random(1, 100) <= Settings.Rage_HitChance then
                    local tcf = CFrame.new(Camera.CFrame.Position, pp)
                    local sm = Settings.Rage_Smoothness
                    Camera.CFrame = sm <= 1 and tcf or Camera.CFrame:Lerp(tcf, 1 / sm)
                end
            end

            if Settings.Rage_AutoShoot then
                local now = tick() * 1000
                if now - lastShoot >= Settings.Rage_ShootDelay then
                    if math.random(1, 100) <= Settings.Rage_HitChance then
                        if not Settings.Rage_SilentAim then
                            Camera.CFrame = CFrame.new(Camera.CFrame.Position, pp)
                        end
                        task.spawn(Shoot)
                        lastShoot = now
                    end
                end
            end
        end
    else
        silentTarget = nil
        silentTargetPart = nil
    end

    -- FOV Circle
    if FOVCircle then
        if Settings.Rage_Enabled and Settings.Rage_ShowFOV and not Settings.Rage_FOV360 then
            local mp = UserInputService:GetMouseLocation()
            FOVCircle.Position = mp
            FOVCircle.Radius = Settings.Rage_FOV
            FOVCircle.Visible = true
            FOVCircle.Color = C.Accent
        else
            FOVCircle.Visible = false
        end
    end

    -- ESP & Chams
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LocalPlayer then
            if Settings.ESP_Enabled then
                if not ESPObj[p] then MkESP(p) end
                if ESPObj[p] then UpdESP(p, ESPObj[p]) end
            else
                if ESPObj[p] then HdESP(ESPObj[p]) end
            end
            UpdChams(p)
        end
    end

    -- Crosshair
    if #crosshairLines >= 4 then
        if Settings.Crosshair_Enabled then
            local ctr = Camera.ViewportSize / 2
            local s = Settings.Crosshair_Size
            local g = Settings.Crosshair_Gap

            crosshairLines[1].From = Vector2.new(ctr.X - g - s, ctr.Y)
            crosshairLines[1].To = Vector2.new(ctr.X - g, ctr.Y)
            crosshairLines[1].Visible = true
            crosshairLines[1].Color = C.Accent

            crosshairLines[2].From = Vector2.new(ctr.X + g, ctr.Y)
            crosshairLines[2].To = Vector2.new(ctr.X + g + s, ctr.Y)
            crosshairLines[2].Visible = true
            crosshairLines[2].Color = C.Accent

            crosshairLines[3].From = Vector2.new(ctr.X, ctr.Y - g - s)
            crosshairLines[3].To = Vector2.new(ctr.X, ctr.Y - g)
            crosshairLines[3].Visible = true
            crosshairLines[3].Color = C.Accent

            crosshairLines[4].From = Vector2.new(ctr.X, ctr.Y + g)
            crosshairLines[4].To = Vector2.new(ctr.X, ctr.Y + g + s)
            crosshairLines[4].Visible = true
            crosshairLines[4].Color = C.Accent
        else
            for _, l in ipairs(crosshairLines) do
                l.Visible = false
            end
        end
    end

    Do3P()
    DoFB()
    DoNF()
end)

-- Cleanup
Players.PlayerRemoving:Connect(function(p)
    RmESP(p)
    if ChamsObj[p] then
        pcall(function() ChamsObj[p]:Destroy() end)
        ChamsObj[p] = nil
    end
end)

UserInputService.InputBegan:Connect(function(input, gp)
    if gp then return end
    if input.KeyCode == Enum.KeyCode.Insert or input.KeyCode == Enum.KeyCode.RightControl then
        Box.Visible = not Box.Visible
    end
end)

SG.Destroying:Connect(function()
    for _, p in pairs(ESPObj) do
        for _, o in pairs(p) do pcall(function() o:Remove() end) end
    end
    if FOVCircle then pcall(function() FOVCircle:Remove() end) end
    for _, l in ipairs(crosshairLines) do pcall(function() l:Remove() end) end
    for _, h in pairs(ChamsObj) do pcall(function() h:Destroy() end) end
    if flyBV then pcall(function() flyBV:Destroy() end) end
    if WMGui then WMGui:Destroy() end
end)

print("[Wacsense v8] Full version loaded!")
print("  INSERT / RIGHT CTRL — toggle menu")
print("  Config: type name → SAVE/LOAD/DELETE")
print("  Chams: RGB sliders for fill & outline")
print("  Anti-Detect: GetChildren/FindFirstChild hidden")
print("  Anti-Detect: WalkSpeed/JumpPower spoofed")