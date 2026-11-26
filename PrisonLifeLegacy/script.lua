local genv = getgenv()
if genv.PLL_LOADED then return end
genv.PLL_LOADED = true

local cloneref = cloneref or function(o) return o end
local Players = cloneref(game:GetService("Players"))
local RunService = cloneref(game:GetService("RunService"))
local UserInputService = cloneref(game:GetService("UserInputService"))
local ReplicatedStorage = cloneref(game:GetService("ReplicatedStorage"))
local Workspace = cloneref(game:GetService("Workspace"))
local LocalPlayer = Players.LocalPlayer
if not LocalPlayer then repeat task.wait() LocalPlayer = Players.LocalPlayer until LocalPlayer end

local Unloaded = false
local lib

local function Notify(title, text, duration, color)
    if lib then pcall(function() lib:Notification(title, text, duration or 3, color) end) end
end

-- LIP UI
local LIPUI = {}
LIPUI.__index = LIPUI
local LIPTab = {}
LIPTab.__index = LIPTab

do
    local C = {
        Panel = Color3.fromRGB(15, 15, 15),
        Box = Color3.fromRGB(20, 20, 22),
        Field = Color3.fromRGB(31, 50, 79),
        Hover = Color3.fromRGB(44, 83, 130),
        Press = Color3.fromRGB(50, 105, 170),
        Fill = Color3.fromRGB(61, 133, 224),
        Title = Color3.fromRGB(41, 74, 122),
        Tab = Color3.fromRGB(40, 70, 112),
        TabOn = Color3.fromRGB(51, 105, 173),
        TabHover = Color3.fromRGB(62, 128, 205),
        Text = Color3.fromRGB(255, 255, 255),
        Muted = Color3.fromRGB(150, 150, 150),
        Accent = Color3.fromRGB(66, 150, 250),
        Green = Color3.fromRGB(173, 255, 115),
        Red = Color3.fromRGB(255, 58, 94),
        Orange = Color3.fromRGB(255, 165, 92),
    }
    local WIN_W, WIN_H, TITLE_H, TAB_H = 820, 480, 24, 28
    local MIN_W, MIN_H = 520, 300
    local DIM_T = 1
    local FONT = Enum.Font.Code
    local WHITE = Color3.new(1, 1, 1)
    local TextService = cloneref(game:GetService("TextService"))

    local function make(class, props, parent)
        local o = Instance.new(class)
        for k, v in pairs(props) do o[k] = v end
        if parent then o.Parent = parent end
        return o
    end
    local TweenService = cloneref(game:GetService("TweenService"))

    local function tween(o, props, t)
        if not o or not o.Parent then return end
        pcall(function()
            TweenService:Create(o, TweenInfo.new(t or 0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), props):Play()
        end)
    end

    local function round(o, r) return make("UICorner", { CornerRadius = UDim.new(0, r) }, o) end
    local function outline(o, transparency)
        if not o:FindFirstChildOfClass("UICorner") then round(o, 4) end
        return make("UIStroke", { Color = Color3.fromRGB(110, 110, 128), Transparency = math.clamp(transparency - 0.2, 0.3, 0.9), Thickness = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, o)
    end

    -- Title bar with rounded top corners and a flat bottom edge
    local function titleBar(parent, color, h, r)
        r = r or 6
        local bar = make("Frame", { BackgroundColor3 = color, BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, h) }, parent)
        round(bar, r)
        make("Frame", { BackgroundColor3 = color, BorderSizePixel = 0, AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1),
            Size = UDim2.new(1, 0, 0, r + 1) }, bar)
        return bar
    end

    local function pad(o, l, t, r, b)
        return make("UIPadding", { PaddingLeft = UDim.new(0, l), PaddingTop = UDim.new(0, t), PaddingRight = UDim.new(0, r), PaddingBottom = UDim.new(0, b) }, o)
    end

    local function text(parent, str, size, font, color, props)
        local l = make("TextLabel", {
            BackgroundTransparency = 1, Text = str, TextSize = size, Font = font, TextColor3 = color,
            TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd,
        }, nil)
        if props then for k, v in pairs(props) do l[k] = v end end
        l.Parent = parent
        return l
    end

    local function isPress(input)
        return input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch
    end

    local function call(cb, ...)
        if typeof(cb) ~= "function" then return end
        local ok, err = pcall(cb, ...)
    end

    -- Window
    function LIPUI.new()
        local self = setmetatable({ Conns = {}, Tabs = {}, Binds = {}, Controls = {}, ControlOrder = {}, Loading = false, Toasts = {}, ToastN = 0, Visible = true, Mult = 1,
            Drag = nil, Slide = nil, Listening = nil, ToggleKey = Enum.KeyCode.LeftAlt, Active = nil }, LIPUI)
        local ok, parent = pcall(function() return (typeof(gethui) == "function" and gethui()) or cloneref(game:GetService("CoreGui")) end)
        if not ok or not parent then parent = LocalPlayer:WaitForChild("PlayerGui") end
        local gui = make("ScreenGui", { Name = "LIPDetector_UI", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 1000,
            ZIndexBehavior = Enum.ZIndexBehavior.Sibling }, nil)
        gui.Parent = parent
        self.Gui = gui
        self.Root = make("Frame", { Name = "Root", BackgroundTransparency = 1, BorderSizePixel = 0, Size = UDim2.fromScale(1, 1) }, gui)
        self.Dim = make("Frame", { Name = "Dim", BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = DIM_T, BorderSizePixel = 0,
            Size = UDim2.fromScale(1, 1), Active = false }, self.Root)
        self.RootScale = make("UIScale", { Scale = 1 }, self.Root)
        self.ToastRoot = make("Frame", { Name = "Toasts", BackgroundTransparency = 1, BorderSizePixel = 0, Size = UDim2.fromScale(1, 1) }, gui)
        self.ToastScale = make("UIScale", { Scale = 1 }, self.ToastRoot)
        self.ToastList = make("Frame", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 12),
            Size = UDim2.fromOffset(252, 0), AutomaticSize = Enum.AutomaticSize.Y }, self.ToastRoot)
        make("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder, HorizontalAlignment = Enum.HorizontalAlignment.Right }, self.ToastList)

        -- global input
        table.insert(self.Conns, UserInputService.InputChanged:Connect(function(input)
            local d = self.Drag
            if d and (input == d.Input or input.UserInputType == Enum.UserInputType.MouseMovement) then
                local s = self.RootScale.Scale
                local dx, dy = (input.Position.X - d.Start.X) / s, (input.Position.Y - d.Start.Y) / s
                d.Panel.Position = UDim2.fromOffset(d.Origin.X + dx, d.Origin.Y + dy)
                self:_clamp(d.Panel)
            end
            local rs = self.Resize
            if rs and (input == rs.Input or input.UserInputType == Enum.UserInputType.MouseMovement) then
                local sc = self.RootScale.Scale
                local dx, dy = (input.Position.X - rs.Start.X) / sc, (input.Position.Y - rs.Start.Y) / sc
                local win = self.Win
                local maxW = math.max(MIN_W, (self.RootW or 1280) - win.Position.X.Offset)
                local maxH = math.max(MIN_H, (self.RootH or 720) - win.Position.Y.Offset)
                if rs.X then self.WinW = math.clamp(rs.W + dx, MIN_W, maxW) end
                if rs.Y then self.WinH = math.clamp(rs.H + dy, MIN_H, maxH) end
                win.Size = UDim2.fromOffset(self.WinW, self.WinH)
            end
            local pd = self.Pending
            if pd and (input == pd.Input or input.UserInputType == Enum.UserInputType.MouseMovement) then
                if (input.Position - pd.Start).Magnitude > 10 then
                    self.Pending = nil
                    local g = pd.Group
                    local sc = self.RootScale.Scale
                    local abs, size = g.AbsolutePosition, g.AbsoluteSize
                    g.Parent = self.Root
                    g.AutomaticSize = Enum.AutomaticSize.Y
                    g.Size = UDim2.fromOffset(size.X / sc, 0)
                    g.Position = UDim2.fromOffset(abs.X / sc, abs.Y / sc)
                    pd.Dock.Visible = true
                    self.Drag = { Panel = g, Start = pd.Start, Origin = Vector2.new(abs.X / sc, abs.Y / sc), Input = pd.Input }
                end
            end
            local sl = self.Slide
            if sl and (input == sl.Input or input.UserInputType == Enum.UserInputType.MouseMovement) then sl.Update(input.Position.X) end
        end))
        table.insert(self.Conns, UserInputService.InputEnded:Connect(function(input)
            local d = self.Drag
            if d and (input == d.Input or (input.UserInputType == Enum.UserInputType.MouseButton1 and d.Input.UserInputType == Enum.UserInputType.MouseButton1)) then
                self.Drag = nil
            end
            local rs = self.Resize
            if rs and (input == rs.Input or (input.UserInputType == Enum.UserInputType.MouseButton1 and rs.Input.UserInputType == Enum.UserInputType.MouseButton1)) then
                self.Resize = nil
            end
            local pd = self.Pending
            if pd and (input == pd.Input or input.UserInputType == Enum.UserInputType.MouseButton1) then self.Pending = nil end
            local sl = self.Slide
            if sl and (input == sl.Input or (input.UserInputType == Enum.UserInputType.MouseButton1 and sl.Input.UserInputType == Enum.UserInputType.MouseButton1)) then
                self.Slide = nil
                if sl.Page then sl.Page.ScrollingEnabled = true end
            end
        end))
        table.insert(self.Conns, UserInputService.InputBegan:Connect(function(input)
            if input.UserInputType ~= Enum.UserInputType.Keyboard then return end
            local l = self.Listening
            if l then
                self.Listening = nil
                if input.KeyCode ~= Enum.KeyCode.Escape then l.Set(input.KeyCode) else l.Refresh() end
                return
            end
            if UserInputService:GetFocusedTextBox() then return end
            if input.KeyCode == self.ToggleKey then self:SetVisible(not self.Visible) return end
            for _, b in ipairs(self.Binds) do
                if b.Key == input.KeyCode then call(b.Cb) end
            end
        end))

        local cam = workspace.CurrentCamera
        if cam then
            table.insert(self.Conns, cam:GetPropertyChangedSignal("ViewportSize"):Connect(function() self:Fit() end))
        end
        return self
    end

    function LIPUI:_clamp(panel)
        local rw, rh = self.RootW or 1280, self.RootH or 720
        local w = panel.Size.X.Offset
        local x = math.clamp(panel.Position.X.Offset, -(w - 80), rw - 80)
        local y = math.clamp(panel.Position.Y.Offset, 0, rh - TITLE_H)
        panel.Position = UDim2.fromOffset(x, y)
    end

    function LIPUI:Fit()
        local cam = workspace.CurrentCamera
        local vp = cam and cam.ViewportSize or Vector2.new(1280, 720)
        local fit = math.min((vp.X - 16) / WIN_W, (vp.Y - 16) / WIN_H)
        local s = math.clamp(math.min(fit, 1) * self.Mult, 0.4, 1.5)
        self.RootScale.Scale = s
        self.ToastScale.Scale = math.clamp(math.min(fit, 1), 0.55, 1)
        self.RootW, self.RootH = vp.X / s, vp.Y / s
        self.Root.Size = UDim2.fromOffset(self.RootW, self.RootH)
        local ts = self.ToastScale.Scale
        self.ToastRoot.Size = UDim2.fromOffset(vp.X / ts, vp.Y / ts)
        if self.Win then self:_clamp(self.Win) end
    end

    function LIPUI:SetScale(mult)
        self.Mult = math.clamp(mult, 0.5, 1.5)
        self:Fit()
    end

    function LIPUI:SetVisible(v)
        self.Visible = v and true or false
        if self.Visible then
            self.Root.Visible = true
            tween(self.Dim, { BackgroundTransparency = DIM_T }, 0.22)
        else
            self.Drag = nil
            self.Slide = nil
            self.Resize = nil
            self.Pending = nil
            tween(self.Dim, { BackgroundTransparency = 1 }, 0.16)
            task.delay(0.22, function()
                if not self.Visible and self.Root.Parent then self.Root.Visible = false end
            end)
        end
    end

    local function bindDrag(self, handle, panel)
        handle.InputBegan:Connect(function(input)
            if isPress(input) then
                self.Drag = { Panel = panel, Start = input.Position, Origin = Vector2.new(panel.Position.X.Offset, panel.Position.Y.Offset), Input = input }
            end
        end)
    end

    -- Creates the window: title bar, tab row on top, page area underneath
    function LIPUI:Window(title, toggleKey)
        self.ToggleKey = toggleKey or self.ToggleKey
        self:Fit()
        local x0 = math.max(8, (self.RootW - WIN_W) / 2)
        local y0 = math.max(8, (self.RootH - WIN_H) / 2)

        self.WinW, self.WinH = WIN_W, WIN_H
        local win = make("Frame", { Name = "Window", BackgroundColor3 = C.Panel, BackgroundTransparency = 0.06, BorderSizePixel = 0,
            Position = UDim2.fromOffset(x0, y0), Size = UDim2.fromOffset(WIN_W, WIN_H), ClipsDescendants = true, Active = true }, self.Root)
        round(win, 6)
        outline(win, 0.7)
        self.Win = win

        local bar = titleBar(win, C.Title, TITLE_H, 6)
        bar.Active = true
        local arrow = make("TextButton", { Text = "v", Font = FONT, TextSize = 13, TextColor3 = C.Text, BackgroundTransparency = 1, AutoButtonColor = false,
            Size = UDim2.fromOffset(24, TITLE_H), ZIndex = 3 }, bar)
        text(bar, title or "LIP MENU", 13, FONT, C.Text, { Position = UDim2.fromOffset(26, 0), Size = UDim2.new(0.6, 0, 1, 0) })
        text(bar, self.ToggleKey.Name .. " hides the menu", 11, FONT, C.Muted, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 0),
            Size = UDim2.fromOffset(240, TITLE_H), TextXAlignment = Enum.TextXAlignment.Right })
        bindDrag(self, bar, win)

        self.TabBar = make("Frame", { BackgroundColor3 = Color3.fromRGB(18, 20, 25), BackgroundTransparency = 0, BorderSizePixel = 0, Position = UDim2.fromOffset(0, TITLE_H), Size = UDim2.new(1, 0, 0, TAB_H) }, win)
        make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder,
            VerticalAlignment = Enum.VerticalAlignment.Bottom }, self.TabBar)
        pad(self.TabBar, 8, 0, 8, 0)
        local tabLine = make("Frame", { BackgroundColor3 = Color3.fromRGB(60, 70, 92), BorderSizePixel = 0, Position = UDim2.fromOffset(0, TITLE_H + TAB_H),
            Size = UDim2.new(1, 0, 0, 1) }, win)

        self.Content = make("Frame", { BackgroundTransparency = 1, BorderSizePixel = 0, Position = UDim2.fromOffset(0, TITLE_H + TAB_H + 1),
            Size = UDim2.new(1, 0, 1, -(TITLE_H + TAB_H + 1)) }, win)
        -- Resize: right edge, bottom edge and the corner grip
        local handles = {}
        local function resizeHandle(props, rx, ry)
            local h = make("Frame", props, win)
            h.ZIndex = 20
            h.Active = true
            h.InputBegan:Connect(function(input)
                if isPress(input) then
                    self.Resize = { Start = input.Position, W = self.WinW, H = self.WinH, X = rx, Y = ry, Input = input }
                end
            end)
            table.insert(handles, h)
            return h
        end
        resizeHandle({ BackgroundTransparency = 1, BorderSizePixel = 0, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, TITLE_H),
            Size = UDim2.new(0, 5, 1, -(TITLE_H + 16)) }, true, false)
        resizeHandle({ BackgroundTransparency = 1, BorderSizePixel = 0, AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, 0),
            Size = UDim2.new(1, -16, 0, 5) }, false, true)
        local grip = resizeHandle({ BackgroundColor3 = C.Accent, BackgroundTransparency = 0, BorderSizePixel = 0, AnchorPoint = Vector2.new(1, 1),
            Position = UDim2.fromScale(1, 1), Size = UDim2.fromOffset(16, 16) }, true, true)
        make("UIGradient", { Rotation = 45, Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.5, 1),
            NumberSequenceKeypoint.new(0.501, 0.55), NumberSequenceKeypoint.new(1, 0.55) }) }, grip)
        grip.MouseEnter:Connect(function() tween(grip, { BackgroundColor3 = C.TabHover }, 0.1) end)
        grip.MouseLeave:Connect(function() tween(grip, { BackgroundColor3 = C.Accent }, 0.1) end)

        -- Collapse to the title bar, like an ImGui window
        local collapsed = false
        arrow.MouseButton1Click:Connect(function()
            collapsed = not collapsed
            arrow.Text = collapsed and ">" or "v"
            self.TabBar.Visible = not collapsed
            self.Content.Visible = not collapsed
            tabLine.Visible = not collapsed
            for _, h in ipairs(handles) do h.Visible = not collapsed end
            win.Size = UDim2.fromOffset(self.WinW, collapsed and TITLE_H or self.WinH)
        end)

        self:Fit()
        return self
    end

    function LIPUI:Select(tab)
        self.Active = tab
        for _, t in ipairs(self.Tabs) do
            local on = t == tab
            t.Page.Visible = on
            t.Paint(on and "on" or "off")
        end
    end

    function LIPUI:Tab(name)
        local tab = setmetatable({ Name = name, Lib = self, N = 0, ColH = { 0, 0 }, Group = nil }, LIPTab)
        local width = 70
        pcall(function() width = TextService:GetTextSize(name, 12, FONT, Vector2.new(1000, 100)).X + 22 end)
        local btn = make("Frame", { BackgroundTransparency = 1, BorderSizePixel = 0, Size = UDim2.fromOffset(width + 6, TAB_H),
            LayoutOrder = #self.Tabs + 1 }, self.TabBar)
        local body = make("Frame", { BackgroundColor3 = C.Field, BackgroundTransparency = 1, BorderSizePixel = 0, Size = UDim2.new(1, 0, 1, -1) }, btn)
        local line = make("Frame", { BackgroundColor3 = C.Accent, BackgroundTransparency = 1, BorderSizePixel = 0, AnchorPoint = Vector2.new(0, 1),
            Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, 2) }, btn)
        local lbl = text(btn, name, 12, FONT, Color3.fromRGB(170, 180, 200), { Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 3 })
        local hit = make("TextButton", { Text = "", BackgroundTransparency = 1, AutoButtonColor = false, Size = UDim2.fromScale(1, 1), ZIndex = 4 }, btn)
        tab.Btn = btn
        function tab.Paint(state)
            local on, hov = state == "on", state == "hover"
            tween(body, { BackgroundTransparency = on and 0.35 or (hov and 0.6 or 1) }, 0.1)
            tween(line, { BackgroundTransparency = on and 0 or 1 }, 0.1)
            tween(lbl, { TextColor3 = (on or hov) and C.Text or Color3.fromRGB(170, 180, 200) }, 0.1)
        end

        tab.Page = make("ScrollingFrame", { BackgroundTransparency = 1, BorderSizePixel = 0, Size = UDim2.fromScale(1, 1), ScrollBarThickness = 3,
            ScrollBarImageColor3 = Color3.fromRGB(110, 110, 110), CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y,
            ScrollingDirection = Enum.ScrollingDirection.Y, ElasticBehavior = Enum.ElasticBehavior.Never, Visible = false }, self.Content)
        pad(tab.Page, 8, 8, 10, 8)
        for i = 1, 2 do
            local col = make("Frame", { BackgroundTransparency = 1, BorderSizePixel = 0, Size = UDim2.new(0.5, -4, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
                Position = i == 1 and UDim2.new() or UDim2.new(0.5, 4, 0, 0) }, tab.Page)
            make("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, col)
            tab["Col" .. i] = col
        end

        hit.MouseButton1Click:Connect(function() self:Select(tab) end)
        hit.MouseEnter:Connect(function()
            if self.Active ~= tab then tab.Paint("hover") end
        end)
        hit.MouseLeave:Connect(function()
            if self.Active ~= tab then tab.Paint("off") end
        end)
        table.insert(self.Tabs, tab)
        if #self.Tabs == 1 then self:Select(tab) end
        return tab
    end

    -- Notifications
    local function toastColor(title, body)
        local t, b = string.lower(tostring(title)), string.lower(tostring(body))
        if string.find(t, "!!", 1, true) or string.find(t, "staff", 1, true) or string.find(t, "watch", 1, true) then return C.Red end
        if string.find(b, "enabled", 1, true) then return C.Green end
        if string.find(b, "disabled", 1, true) then return Color3.fromRGB(150, 150, 150) end
        if string.find(b, "fail", 1, true) or string.find(b, "could not", 1, true) or string.find(b, "not found", 1, true)
            or string.find(b, "missing", 1, true) or string.find(b, "error", 1, true) then return C.Orange end
        return C.Accent
    end

    function LIPUI:Notification(title, body, duration, color)
        self.ToastN += 1
        local accent = color or toastColor(title, body)
        local card = make("Frame", { BackgroundColor3 = C.Panel, BackgroundTransparency = 0.06, BorderSizePixel = 0,
            ClipsDescendants = true, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = self.ToastN }, self.ToastList)
        round(card, 6)
        outline(card, 0.7)
        make("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder }, card)

        -- ImGui window title bar, tinted by the toast kind
        local bar = titleBar(card, accent:Lerp(Color3.new(0, 0, 0), 0.45), 22, 6)
        bar.LayoutOrder = 1
        text(bar, "v", 13, FONT, C.Text, { Position = UDim2.fromOffset(7, 0), Size = UDim2.fromOffset(14, 22) })
        text(bar, tostring(title), 13, FONT, C.Text, { Position = UDim2.fromOffset(24, 0), Size = UDim2.new(1, -30, 1, 0) })

        local inner = make("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 2 }, card)
        pad(inner, 10, 8, 10, 6)
        make("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, inner)
        text(inner, tostring(body), 12, FONT, C.Text, { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
            TextWrapped = true, TextTruncate = Enum.TextTruncate.None, LayoutOrder = 1 })

        -- Time left, drawn like an ImGui progress bar
        local track = make("Frame", { BackgroundColor3 = C.Field, BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 6), LayoutOrder = 2, ClipsDescendants = true }, inner)
        round(track, 3)
        local life = make("Frame", { BackgroundColor3 = accent, BorderSizePixel = 0, Size = UDim2.fromScale(1, 1) }, track)
        round(life, 3)
        tween(life, { Size = UDim2.fromScale(0, 1) }, duration or 3)
        table.insert(self.Toasts, card)
        while #self.Toasts > 5 do
            local old = table.remove(self.Toasts, 1)
            pcall(function() old:Destroy() end)
        end
        task.delay(duration or 3, function()
            local i = table.find(self.Toasts, card)
            if i then table.remove(self.Toasts, i) end
            pcall(function() card:Destroy() end)
        end)
    end

    function LIPUI:Destroy()
        for _, c in ipairs(self.Conns) do pcall(function() c:Disconnect() end) end
        self.Conns = {}
        pcall(function() self.Gui:Destroy() end)
    end

    -- Elements
    local function nextOrder(tab)
        tab.N += 1
        return tab.N
    end

    -- Saveable controls, keyed by tab / group / name
    local NO_SAVE = { ["Enable Spectating"] = true, ["Surrender"] = true, ["Hands Up"] = true, ["Pray"] = true, ["Salute"] = true, ["T-Pose"] = true, ["Crate Sit"] = true }
    local function register(tab, name, kind, obj)
        local key = tab.Name .. " :: " .. (tab.GroupName or tab.Name) .. " :: " .. name
        local base, n = key, 1
        while tab.Lib.Controls[key] do n += 1 key = base .. " #" .. n end
        obj.Kind = kind
        obj.NoSave = NO_SAVE[name] or false
        tab.Lib.Controls[key] = obj
        table.insert(tab.Lib.ControlOrder, key)
        return obj
    end

    -- Starts a new group box in whichever column is shorter
    function LIPTab:Section(name)
        local col = self.ColH[1] <= self.ColH[2] and 1 or 2
        local g = make("Frame", { BackgroundColor3 = C.Box, BackgroundTransparency = 0.05, BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 0),
            AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = nextOrder(self) }, self["Col" .. col])
        outline(g, 0.86)
        make("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }, g)
        pad(g, 10, 4, 10, 10)
        local head = make("Frame", { BackgroundColor3 = C.Accent, BackgroundTransparency = 0.7, BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 20), LayoutOrder = 0 }, g)
        round(head, 3)
        local l = text(head, tostring(name), 13, FONT, C.Text, { Position = UDim2.fromOffset(6, 0), Size = UDim2.new(1, -26, 1, 0) })
        -- Drag the header out of the window to make it a floating panel; x puts it back
        head.Active = true
        local lib, home = self.Lib, g.Parent
        local dock = make("TextButton", { Text = "x", Font = FONT, TextSize = 12, TextColor3 = C.Text, BackgroundTransparency = 1, AutoButtonColor = false,
            AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -2, 0, 0), Size = UDim2.fromOffset(20, 20), Visible = false, ZIndex = 3 }, head)
        head.InputBegan:Connect(function(input)
            if not isPress(input) then return end
            if g.Parent == lib.Root then
                lib.Drag = { Panel = g, Start = input.Position, Origin = Vector2.new(g.Position.X.Offset, g.Position.Y.Offset), Input = input }
            else
                lib.Pending = { Group = g, Dock = dock, Start = input.Position, Input = input }
            end
        end)
        dock.MouseButton1Click:Connect(function()
            g.Parent = home
            g.Position = UDim2.new()
            g.Size = UDim2.new(1, 0, 0, 0)
            dock.Visible = false
        end)
        self.Group, self.GroupCol = g, col
        self.GroupName = tostring(name)
        self.ColH[col] += 40
        local obj = {}
        function obj:Set(t) l.Text = tostring(t) end
        return obj
    end

    -- Group the next element goes into (a default one named after the tab if none yet)
    function LIPTab:_g(h)
        if not self.Group then self:Section(self.Name) end
        self.ColH[self.GroupCol] += h
        return self.Group
    end

    function LIPTab:Paragraph(title, body)
        local lines = math.ceil(#tostring(body) / 44)
        local f = make("Frame", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, LayoutOrder = nextOrder(self) },
            self:_g(24 + lines * 14))
        make("UIListLayout", { Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder }, f)
        pad(f, 0, 2, 0, 4)
        text(f, tostring(title), 12, FONT, C.Text, { Size = UDim2.new(1, 0, 0, 15), LayoutOrder = 1 })
        text(f, tostring(body), 12, FONT, C.Muted, { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
            TextWrapped = true, TextTruncate = Enum.TextTruncate.None, LayoutOrder = 2 })
    end

    -- Small always-on info box (stays visible when the menu is hidden)
    function LIPUI:Watermark()
        local frame = make("Frame", { Name = "Watermark", BackgroundColor3 = C.Panel, BackgroundTransparency = 0.06, BorderSizePixel = 0,
            Position = UDim2.fromOffset(12, 12), Size = UDim2.fromOffset(220, 0), AutomaticSize = Enum.AutomaticSize.Y }, self.ToastRoot)
        round(frame, 6)
        outline(frame, 0.7)
        make("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder }, frame)
        local bar = titleBar(frame, C.Title, 20, 6)
        bar.LayoutOrder = 1
        text(bar, "LIP MENU", 12, FONT, C.Text, { Position = UDim2.fromOffset(8, 0), Size = UDim2.new(1, -16, 1, 0) })
        bar.Active = true
        local drag
        bar.InputBegan:Connect(function(input)
            if self.Visible and isPress(input) then
                drag = { Start = input.Position, Origin = Vector2.new(frame.Position.X.Offset, frame.Position.Y.Offset), Input = input }
            end
        end)
        table.insert(self.Conns, UserInputService.InputChanged:Connect(function(input)
            if drag and (input == drag.Input or input.UserInputType == Enum.UserInputType.MouseMovement) then
                local sc = self.ToastScale.Scale
                local maxX = self.ToastRoot.Size.X.Offset - frame.AbsoluteSize.X / sc
                local maxY = self.ToastRoot.Size.Y.Offset - frame.AbsoluteSize.Y / sc
                local x = math.clamp(drag.Origin.X + (input.Position.X - drag.Start.X) / sc, 0, math.max(maxX, 0))
                local y = math.clamp(drag.Origin.Y + (input.Position.Y - drag.Start.Y) / sc, 0, math.max(maxY, 0))
                frame.Position = UDim2.fromOffset(x, y)
            end
        end))
        table.insert(self.Conns, UserInputService.InputEnded:Connect(function(input)
            if drag and (input == drag.Input or input.UserInputType == Enum.UserInputType.MouseButton1) then drag = nil end
        end))
        local body = make("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 2 }, frame)
        pad(body, 8, 6, 8, 6)
        make("UIListLayout", { Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder }, body)
        local function line(order, color)
            return text(body, "", 12, FONT, color, { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, TextWrapped = true,
                TextTruncate = Enum.TextTruncate.None, LayoutOrder = order })
        end
        local l1, l2, l3 = line(1, C.Text), line(2, C.Text), line(3, Color3.fromRGB(170, 200, 255))
        local obj = {}
        function obj:Set(a, b, c) l1.Text, l2.Text, l3.Text = a, b, c end
        function obj:SetVisible(v) frame.Visible = v and true or false end
        return obj
    end

    -- Scrolling list of names; click one to select it
    function LIPTab:PlayerList(height, onSelect)
        local h = height or 170
        local holder = make("Frame", { Size = UDim2.new(1, 0, 0, h), BackgroundColor3 = C.Box, BorderSizePixel = 0, LayoutOrder = nextOrder(self) }, self:_g(h + 6))
        round(holder, 4)
        outline(holder, 0.8)
        local scroll = make("ScrollingFrame", { BackgroundTransparency = 1, BorderSizePixel = 0, Size = UDim2.fromScale(1, 1), ScrollBarThickness = 3,
            ScrollBarImageColor3 = Color3.fromRGB(110, 110, 110), CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y,
            ScrollingDirection = Enum.ScrollingDirection.Y, ElasticBehavior = Enum.ElasticBehavior.Never }, holder)
        pad(scroll, 4, 4, 6, 4)
        make("UIListLayout", { Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder }, scroll)
        local selected, buttons = nil, {}
        local obj = {}
        local function paint()
            for name, b in pairs(buttons) do
                b.BackgroundColor3 = name == selected and C.Press or C.Field
                b.BackgroundTransparency = name == selected and 0 or 0.45
            end
        end
        function obj.Get() return selected end
        function obj:Refresh(names)
            for _, child in ipairs(scroll:GetChildren()) do
                if child:IsA("TextButton") then child:Destroy() end
            end
            buttons = {}
            if selected and not table.find(names, selected) then
                selected = nil
                call(onSelect, nil)
            end
            for i, name in ipairs(names) do
                local b = make("TextButton", { Text = name, Font = FONT, TextSize = 12, TextColor3 = C.Text, TextXAlignment = Enum.TextXAlignment.Left,
                    AutoButtonColor = false, BackgroundColor3 = C.Field, BackgroundTransparency = 0.45, BorderSizePixel = 0,
                    Size = UDim2.new(1, 0, 0, 22), LayoutOrder = i }, scroll)
                round(b, 3)
                pad(b, 8, 0, 8, 0)
                buttons[name] = b
                b.MouseEnter:Connect(function() if name ~= selected then b.BackgroundColor3 = C.Hover b.BackgroundTransparency = 0.2 end end)
                b.MouseLeave:Connect(function() if name ~= selected then b.BackgroundColor3 = C.Field b.BackgroundTransparency = 0.45 end end)
                b.MouseButton1Click:Connect(function()
                    selected = name
                    paint()
                    call(onSelect, name)
                end)
            end
            paint()
        end
        return obj
    end

    function LIPTab:Label(str)
        local f = make("Frame", { Size = UDim2.new(1, 0, 0, 20), BackgroundTransparency = 1, LayoutOrder = nextOrder(self) }, self:_g(24))
        local l = text(f, tostring(str), 13, FONT, C.Text, { Size = UDim2.fromScale(1, 1) })
        local obj = {}
        function obj:Set(t) l.Text = tostring(t) end
        return obj
    end

    function LIPTab:Toggle(name, default, cb)
        local on = default and true or false
        local f = make("TextButton", { Text = "", AutoButtonColor = false, BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 22), LayoutOrder = nextOrder(self) },
            self:_g(26))
        local box = make("Frame", { Size = UDim2.fromOffset(14, 14), Position = UDim2.new(0, 0, 0.5, -7), BackgroundColor3 = C.Field, BorderSizePixel = 0 }, f)
        round(box, 3)
        local mark = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, BorderSizePixel = 0, Visible = on }, box)
        make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(4.5, 8.5), Size = UDim2.fromOffset(2, 5), Rotation = -45,
            BackgroundColor3 = C.Accent, BorderSizePixel = 0 }, mark)
        make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(8.5, 7), Size = UDim2.fromOffset(2, 9), Rotation = 45,
            BackgroundColor3 = C.Accent, BorderSizePixel = 0 }, mark)
        local lbl = text(f, name, 13, FONT, C.Text, { Position = UDim2.fromOffset(22, 0), Size = UDim2.new(1, -22, 1, 0) })
        f.MouseEnter:Connect(function() tween(box, { BackgroundColor3 = C.Hover }, 0.1) end)
        f.MouseLeave:Connect(function() tween(box, { BackgroundColor3 = C.Field }, 0.1) end)
        local function render() mark.Visible = on end
        f.MouseButton1Click:Connect(function()
            on = not on
            render()
            call(cb, on)
        end)
        local obj = {}
        function obj:Set(v) on = v and true or false render() end
        function obj.Get() return on end
        function obj.Fire(v)
            v = v and true or false
            if v ~= on then
                on = v
                render()
                call(cb, on)
            end
        end
        return register(self, name, "toggle", obj)
    end

    function LIPTab:Slider(name, min, max, default, cb)
        local val = math.clamp(math.floor((tonumber(default) or min) + 0.5), min, max)
        local f = make("Frame", { Size = UDim2.new(1, 0, 0, 40), BackgroundTransparency = 1, LayoutOrder = nextOrder(self) }, self:_g(44))
        text(f, name, 13, FONT, C.Text, { Size = UDim2.new(1, 0, 0, 16) })
        local track = make("TextButton", { Text = "", AutoButtonColor = false, BackgroundColor3 = C.Field, BorderSizePixel = 0,
            Size = UDim2.new(1, 0, 0, 18), Position = UDim2.fromOffset(0, 20) }, f)
        outline(track, 0.8)
        local grab = make("Frame", { Size = UDim2.new(0, 10, 1, -4), AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = C.Fill, BorderSizePixel = 0 }, track)
        round(grab, 3)
        local valLbl = text(track, "", 12, FONT, C.Text, { Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 2 })
        local span = math.max(max - min, 1)
        local function show()
            local frac = (val - min) / span
            grab.Position = UDim2.new(frac, (0.5 - frac) * 10, 0.5, 0)
            valLbl.Text = tostring(val)
        end
        show()
        local function update(x)
            local w = track.AbsoluteSize.X
            if w <= 0 then return end
            local frac = math.clamp((x - track.AbsolutePosition.X) / w, 0, 1)
            local v = math.clamp(math.floor(min + frac * span + 0.5), min, max)
            if v ~= val then
                val = v
                show()
                call(cb, v)
            end
        end
        local page = self.Page
        track.InputBegan:Connect(function(input)
            if isPress(input) then
                self.Lib.Slide = { Input = input, Update = update, Page = page }
                page.ScrollingEnabled = false
                update(input.Position.X)
            end
        end)
        local obj = {}
        function obj.Get() return val end
        function obj.Fire(v)
            v = tonumber(v)
            if not v then return end
            v = math.clamp(math.floor(v + 0.5), min, max)
            if v ~= val then
                val = v
                show()
                call(cb, v)
            end
        end
        return register(self, name, "slider", obj)
    end

    -- Name on top, the selector box underneath; the options open inline below it
    function LIPTab:Dropdown(name, list, cb, default)
        local value = default or list[1]
        local open = false
        local OPT_H, OPT_GAP = 22, 2
        local fullH = #list * (OPT_H + OPT_GAP) + 2
        local wrap = make("Frame", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, LayoutOrder = nextOrder(self) },
            self:_g(46))
        make("UIListLayout", { Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder }, wrap)
        text(wrap, name, 13, FONT, C.Text, { Size = UDim2.new(1, 0, 0, 16), LayoutOrder = 1 })
        local head = make("TextButton", { Text = "", AutoButtonColor = false, Size = UDim2.new(1, 0, 0, 22), BackgroundColor3 = C.Field,
            BorderSizePixel = 0, LayoutOrder = 2 }, wrap)
        outline(head, 0.8)
        local valLbl = text(head, tostring(value), 12, FONT, C.Text, { Position = UDim2.fromOffset(8, 0), Size = UDim2.new(1, -28, 1, 0) })
        local sign = text(head, "+", 13, FONT, C.Muted, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -6, 0, 0), Size = UDim2.fromOffset(14, 22),
            TextXAlignment = Enum.TextXAlignment.Center })
        head.MouseEnter:Connect(function() tween(head, { BackgroundColor3 = C.Hover }, 0.1) end)
        head.MouseLeave:Connect(function() tween(head, { BackgroundColor3 = C.Field }, 0.1) end)

        local clip = make("Frame", { Size = UDim2.new(1, 0, 0, 0), BackgroundTransparency = 1, BorderSizePixel = 0, ClipsDescendants = true, LayoutOrder = 3 }, wrap)
        local box = make("Frame", { Size = UDim2.new(1, 0, 0, fullH), BackgroundTransparency = 1, BorderSizePixel = 0 }, clip)
        make("UIListLayout", { Padding = UDim.new(0, OPT_GAP), SortOrder = Enum.SortOrder.LayoutOrder }, box)
        pad(box, 0, 2, 0, 0)
        local buttons = {}
        local function paint(animate)
            valLbl.Text = tostring(value)
            for opt, b in pairs(buttons) do
                local sel = opt == value
                local col = sel and C.Hover or C.Field
                if animate then tween(b, { BackgroundColor3 = col }, 0.12) else b.BackgroundColor3 = col end
                b.TextColor3 = sel and C.Text or C.Muted
            end
        end
        for i, opt in ipairs(list) do
            local b = make("TextButton", { Text = tostring(opt), TextXAlignment = Enum.TextXAlignment.Left, TextSize = 12, Font = FONT,
                TextColor3 = C.Muted, AutoButtonColor = false, BackgroundColor3 = C.Field, BorderSizePixel = 0,
                Size = UDim2.new(1, 0, 0, OPT_H), LayoutOrder = i }, box)
            outline(b, 0.86)
            pad(b, 8, 0, 8, 0)
            buttons[opt] = b
            b.MouseEnter:Connect(function() if opt ~= value then tween(b, { BackgroundColor3 = C.Hover }, 0.08) end end)
            b.MouseLeave:Connect(function() if opt ~= value then tween(b, { BackgroundColor3 = C.Field }, 0.08) end end)
            b.MouseButton1Click:Connect(function()
                value = opt
                open = false
                sign.Text = "+"
                tween(clip, { Size = UDim2.new(1, 0, 0, 0) }, 0.16)
                paint(true)
                call(cb, opt)
            end)
        end
        paint(false)
        head.MouseButton1Click:Connect(function()
            open = not open
            sign.Text = open and "-" or "+"
            tween(clip, { Size = UDim2.new(1, 0, 0, open and fullH or 0) }, 0.16)
        end)
        local obj = {}
        function obj.Get() return value end
        function obj.Fire(v)
            if buttons[v] and v ~= value then
                value = v
                paint(false)
                call(cb, v)
            end
        end
        return register(self, name, "dropdown", obj)
    end

    function LIPTab:Textbox(name, _, cb)
        local f = make("Frame", { Size = UDim2.new(1, 0, 0, 44), BackgroundTransparency = 1, LayoutOrder = nextOrder(self) }, self:_g(48))
        text(f, name, 13, FONT, C.Text, { Size = UDim2.new(1, 0, 0, 16) })
        local box = make("TextBox", { Text = "", PlaceholderText = "type here", PlaceholderColor3 = Color3.fromRGB(110, 110, 110), ClearTextOnFocus = false,
            Font = FONT, TextSize = 12, TextColor3 = C.Text, TextXAlignment = Enum.TextXAlignment.Left, BackgroundColor3 = C.Field, BorderSizePixel = 0,
            Size = UDim2.new(1, 0, 0, 22), Position = UDim2.fromOffset(0, 20) }, f)
        outline(box, 0.8)
        pad(box, 8, 0, 8, 0)
        box:GetPropertyChangedSignal("Text"):Connect(function() call(cb, box.Text) end)
        box.FocusLost:Connect(function() call(cb, box.Text) end)
    end

    function LIPTab:Button(name, cb)
        local f = make("Frame", { Size = UDim2.new(1, 0, 0, 28), BackgroundTransparency = 1, LayoutOrder = nextOrder(self) }, self:_g(32))
        local b = make("TextButton", { Text = name, Font = FONT, TextSize = 12, TextColor3 = C.Text, AutoButtonColor = false, BackgroundColor3 = C.Field,
            BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 24), Position = UDim2.fromOffset(0, 2) }, f)
        outline(b, 0.8)
        b.MouseEnter:Connect(function() tween(b, { BackgroundColor3 = C.Hover }, 0.1) end)
        b.MouseLeave:Connect(function() tween(b, { BackgroundColor3 = C.Field }, 0.1) end)
        b.MouseButton1Click:Connect(function()
            b.BackgroundColor3 = C.Press
            tween(b, { BackgroundColor3 = C.Field }, 0.25)
            call(cb)
        end)
    end

    function LIPTab:Bind(name, key, cb)
        local lib = self.Lib
        local f = make("Frame", { Size = UDim2.new(1, 0, 0, 22), BackgroundTransparency = 1, LayoutOrder = nextOrder(self) }, self:_g(26))
        text(f, name, 13, FONT, C.Text, { Size = UDim2.new(1, -76, 1, 0) })
        local chip = make("TextButton", { Text = "", AutoButtonColor = false, Size = UDim2.fromOffset(68, 18), AnchorPoint = Vector2.new(1, 0.5),
            Position = UDim2.new(1, 0, 0.5, 0), BackgroundColor3 = C.Field, BorderSizePixel = 0, Font = FONT, TextSize = 11, TextColor3 = C.Text }, f)
        local stroke = outline(chip, 0.75)
        local bind = { Key = key, Cb = cb }
        table.insert(lib.Binds, bind)
        local function refresh()
            chip.Text = bind.Key and bind.Key.Name or "None"
            stroke.Transparency = 0.75
        end
        refresh()
        chip.MouseButton1Click:Connect(function()
            chip.Text = "..."
            stroke.Transparency = 0.2
            lib.Listening = { Refresh = refresh, Set = function(k) bind.Key = k refresh() end }
        end)
        local obj = {}
        function obj.Get() return bind.Key and bind.Key.Name or "None" end
        function obj.Fire(v)
            local ok, key = pcall(function() return Enum.KeyCode[v] end)
            bind.Key = ok and key or nil
            refresh()
        end
        return register(self, name, "bind", obj)
    end

    -- A list with one row per saved config: Load, Save, Auto, Del
    function LIPTab:ConfigList(actions)
        local f = make("Frame", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, LayoutOrder = nextOrder(self) },
            self:_g(60))
        make("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }, f)

        local function rowButton(row, label, slot, cb)
            local b = make("TextButton", { Text = label, Font = FONT, TextSize = 11, TextColor3 = C.Text, AutoButtonColor = false,
                BackgroundColor3 = C.Box, BorderSizePixel = 0, Size = UDim2.fromOffset(42, 20), AnchorPoint = Vector2.new(1, 0.5),
                Position = UDim2.new(1, -4 - slot * 46, 0.5, 0) }, row)
            outline(b, 0.8)
            b.MouseEnter:Connect(function() tween(b, { BackgroundColor3 = C.Hover }, 0.1) end)
            b.MouseLeave:Connect(function() tween(b, { BackgroundColor3 = C.Box }, 0.1) end)
            b.MouseButton1Click:Connect(function() call(cb) end)
        end

        local obj = {}
        function obj:Refresh(names, auto)
            for _, child in ipairs(f:GetChildren()) do
                if not child:IsA("UIListLayout") then child:Destroy() end
            end
            if #names == 0 then
                text(f, "No configs saved yet", 12, FONT, C.Muted, { Size = UDim2.new(1, 0, 0, 20) })
                return
            end
            for i, name in ipairs(names) do
                local row = make("Frame", { Size = UDim2.new(1, 0, 0, 26), BackgroundColor3 = C.Field, BorderSizePixel = 0, LayoutOrder = i }, f)
                outline(row, 0.86)
                text(row, (name == auto and "* " or "") .. name, 12, FONT, C.Text, { Position = UDim2.fromOffset(8, 0),
                    Size = UDim2.new(1, -196, 1, 0), TextTruncate = Enum.TextTruncate.AtEnd })
                rowButton(row, "Del", 0, function() actions.Delete(name) end)
                rowButton(row, name == auto and "Auto*" or "Auto", 1, function() actions.Auto(name) end)
                rowButton(row, "Save", 2, function() actions.Save(name) end)
                rowButton(row, "Load", 3, function() actions.Load(name) end)
            end
        end
        return obj
    end
end

local Mods = {
    AutoReload = false,
    NoSpread = false,
    AutoFire = false,
    FastRate = false, Rate = 0.08,
    FastReload = false, ReloadTime = 0.5,
}
local Silent = { On = false, Part = "Head", FOV = 200, HitChance = 100, TeamCheck = true, ShowFOV = true }

local Originals = setmetatable({}, { __mode = "k" })
local StateCache = setmetatable({}, { __mode = "k" })
local Shots = setmetatable({}, { __mode = "k" })
local ReloadBusyUntil = {}

local function GetStates(tool)
    local cached = StateCache[tool]
    if cached ~= nil then return cached or nil end
    local module = tool:FindFirstChild("GunStates")
    if not module or not module:IsA("ModuleScript") then return nil end
    local ok, states = pcall(require, module)
    if ok and type(states) == "table" and type(states.MaxAmmo) == "number" and type(states.CurrentAmmo) == "number" then
        StateCache[tool] = states
        return states
    end
    StateCache[tool] = false
    return nil
end

local function EachTool(fn)
    local backpack = LocalPlayer:FindFirstChildOfClass("Backpack")
    for _, holder in ipairs({ backpack, LocalPlayer.Character }) do
        if holder then
            for _, item in ipairs(holder:GetChildren()) do
                if item:IsA("Tool") then fn(item) end
            end
        end
    end
end

local function Remember(states)
    if not Originals[states] then
        Originals[states] = { FireRate = states.FireRate, AutoFire = states.AutoFire, ReloadTime = states.ReloadTime }
    end
    return Originals[states]
end

local function Set(states, field, value)
    if states[field] ~= value then states[field] = value end
end

local function Apply(states)
    local o = Remember(states)
    if o.FireRate ~= nil then
        Set(states, "FireRate", Mods.FastRate and Mods.Rate or o.FireRate)
        Set(states, "AutoFire", Mods.AutoFire and true or o.AutoFire)
    end
    if o.ReloadTime ~= nil then
        Set(states, "ReloadTime", Mods.FastReload and Mods.ReloadTime or o.ReloadTime)
    end
end

local ShootEvent = ReplicatedStorage:FindFirstChild("ShootEvent")
local LastAutoReload = setmetatable({}, { __mode = "k" })

-- target selection
local function ScreenOrigin()
    local cam = Workspace.CurrentCamera
    local m = UserInputService:GetMouseLocation()
    return m, cam
end

local function GetTarget()
    local mouse, cam = ScreenOrigin()
    local best, bestDist = nil, Silent.FOV
    for _, player in ipairs(Players:GetPlayers()) do
        local char = player.Character
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        if player ~= LocalPlayer and hum and hum.Health > 0 then
            if not (Silent.TeamCheck and player.Team ~= nil and player.Team == LocalPlayer.Team) then
                local part = char:FindFirstChild(Silent.Part == "Head" and "Head" or "Torso") or char:FindFirstChild("HumanoidRootPart")
                if part then
                    local sp, on = cam:WorldToViewportPoint(part.Position)
                    if on and sp.Z > 0 then
                        local d = (Vector2.new(sp.X, sp.Y) - mouse).Magnitude
                        if d < bestDist then best, bestDist = part, d end
                    end
                end
            end
        end
    end
    return best
end

local function Rebuild(rays, tool)
    local first = rays[1]
    if type(first) ~= "table" or not first.RayObject then return rays end
    local origin = first.RayObject.Origin
    local range = first.RayObject.Direction.Magnitude
    local states = GetStates(tool)
    local count = #rays

    local aim
    if Silent.On and math.random(1, 100) <= Silent.HitChance then
        local target = GetTarget()
        if target then aim = target.Position end
    end
    if not aim then return rays end

    local muzzle = tool:FindFirstChild("Muzzle")
    local muzzlePos = muzzle and muzzle.Position or origin
    local direction = (aim - origin).Unit * range
    local ray = Ray.new(origin, direction)
    local part, pos = Workspace:FindPartOnRay(ray, LocalPlayer.Character)
    local mag = (pos - muzzlePos).Magnitude
    local hitObject = part
    if part and tool.Name == "Taser" then hitObject = part.Parent end
    local entry = {
        Hit = hitObject,
        Distance = mag,
        Cframe = CFrame.new(pos, muzzlePos) * CFrame.new(0, 0, -mag / 2),
        RayObject = ray,
    }
    local out = {}
    for i = 1, count do out[i] = entry end
    return out
end

local SpreadPatch = setmetatable({}, { __mode = "k" })
local LastPatchScan = 0
local HUGE_SPREAD = 1e9

local function FindCreateRay(tool)
    local candidates = {}
    local okF, found = pcall(function() return filtergc("function", { Name = "createRay" }, false) end)
    if okF and type(found) == "table" then candidates = found end
    if #candidates == 0 and getgc then
        local okG, gc = pcall(getgc, false)
        if okG and gc then
            for _, f in ipairs(gc) do
                if type(f) == "function" and not iscclosure(f) then
                    local okN, name = pcall(debug.info, f, "n")
                    if okN and name == "createRay" then candidates[#candidates + 1] = f end
                end
            end
        end
    end
    for _, f in ipairs(candidates) do
        local okE, env = pcall(getfenv, f)
        local scr = okE and type(env) == "table" and rawget(env, "script")
        if scr and typeof(scr) == "Instance" and scr.Parent == tool then return f end
    end
    return nil
end

local function SetSpread(tool, states, on)
    local entry = SpreadPatch[tool]
    if on then
        if entry == nil then
            if os.clock() - LastPatchScan < 1 then return end
            LastPatchScan = os.clock()
            local fn = FindCreateRay(tool)
            if not fn then return end
            local ups = debug.getupvalues(fn)
            local index
            for i, v in pairs(ups) do
                if type(v) == "number" and v == states.Spread then index = i break end
            end
            if not index then SpreadPatch[tool] = false return end
            SpreadPatch[tool] = { fn = fn, index = index, original = ups[index] }
            entry = SpreadPatch[tool]
        end
        if entry then
            local cur = debug.getupvalue(entry.fn, entry.index)
            if cur ~= HUGE_SPREAD then debug.setupvalue(entry.fn, entry.index, HUGE_SPREAD) end
        end
    elseif entry then
        pcall(debug.setupvalue, entry.fn, entry.index, entry.original)
    end
end

local ShotHook
local hookOk = pcall(function()
    local old
    old = hookmetamethod(game, "__namecall", newcclosure(function(self, ...)
        if Unloaded or not Silent.On then
            return old(self, ...)
        end
        if getnamecallmethod() ~= "FireServer" or checkcaller() then return old(self, ...) end
        local isShoot = false
        pcall(function() isShoot = typeof(self) == "Instance" and self.Name == "ShootEvent" end)
        if not isShoot then return old(self, ...) end

        local args = table.pack(...)
        local tool = args[2]
        pcall(function()
            if typeof(tool) ~= "Instance" then return end
            if type(args[1]) == "table" and Silent.On then
                local ok, rebuilt = pcall(Rebuild, args[1], tool)
                if ok and rebuilt then args[1] = rebuilt end
            end
        end)
        return old(self, table.unpack(args, 1, args.n))
    end))
    ShotHook = old
end)
if not hookOk then
    Notify("Hook failed", "Silent Aim, No Spread and the server reload need hookmetamethod", 6)
end

local circle
if typeof(Drawing) == "table" or typeof(Drawing) == "userdata" then
    pcall(function()
        circle = Drawing.new("Circle")
        circle.Thickness = 1
        circle.NumSides = 64
        circle.Filled = false
        circle.Color = Color3.fromRGB(255, 255, 255)
        circle.Visible = false
    end)
end

local Connection = RunService.RenderStepped:Connect(function()
    if Unloaded then return end
    EachTool(function(tool)
        local states = GetStates(tool)
        if not states then return end
        Apply(states)
        pcall(SetSpread, tool, states, Mods.NoSpread)
        if Mods.AutoReload and states.CurrentAmmo <= 0 and tool.Parent == LocalPlayer.Character then
            if os.clock() - (LastAutoReload[tool] or 0) > 0.4 then
                LastAutoReload[tool] = os.clock()
                local touchReload = ReplicatedStorage:FindFirstChild("touchReload")
                if touchReload then pcall(function() touchReload:Fire() end) end
            end
        end
    end)
    if circle then
        local show = Silent.On and Silent.ShowFOV
        circle.Visible = show
        if show then
            circle.Radius = Silent.FOV
            circle.Position = UserInputService:GetMouseLocation()
        end
    end
end)

local Stamina = { On = false, Last = 0 }

local function FillStamina()
    local char = LocalPlayer.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    local gui = LocalPlayer:FindFirstChild("PlayerGui")
    local home = gui and gui:FindFirstChild("Home")
    local hud = home and home:FindFirstChild("hud")
    local bar = hud and hud:FindFirstChild("StaminaFrame")
    if not hum or not bar then return end
    local current = math.floor(bar.Size.X.Scale * 12 + 0.5)
    for _, signal in ipairs({ hum.Jumping, hum.Changed }) do
        local okC, conns = pcall(getconnections, signal)
        if okC and type(conns) == "table" then
            for _, conn in ipairs(conns) do
                local fn = conn.Function
                if type(fn) == "function" and not iscclosure(fn) then
                    local okU, ups = pcall(debug.getupvalues, fn)
                    if okU and type(ups) == "table" then
                        for index, value in pairs(ups) do
                            if type(value) == "number" and value >= 0 and value <= 12 and value == current then
                                pcall(debug.setupvalue, fn, index, 12)
                            end
                        end
                    end
                end
            end
        end
    end
    bar.Size = UDim2.new(1, 0, 0, bar.Size.Y.Offset)
end

local StaminaConn = RunService.Heartbeat:Connect(function()
    if Unloaded or not Stamina.On then return end
    if os.clock() - Stamina.Last < 0.2 then return end
    Stamina.Last = os.clock()
    pcall(FillStamina)
end)

local Kill = { Busy = false, Cancel = false, Loop = false, Delay = 0, Depth = 4, Name = nil, Obj = nil }
local MeleeEvent = ReplicatedStorage:FindFirstChild("meleeEvent")

local KnifeUse = { On = true }

local function FindKnife()
    local char = LocalPlayer.Character
    local backpack = LocalPlayer:FindFirstChildOfClass("Backpack")
    for _, holder in ipairs({ char, backpack }) do
        if holder then
            for _, item in ipairs(holder:GetChildren()) do
                if item:IsA("Tool") and item:FindFirstChild("blade") and item:FindFirstChild("isHammer") then return item end
            end
        end
    end
    return nil
end

local function EquipKnife()
    local tool = FindKnife()
    if not tool then return nil end
    local char = LocalPlayer.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if hum and tool.Parent ~= char then pcall(function() hum:EquipTool(tool) end) end
    return tool
end

local function MeleeHit(plr)
    if not MeleeEvent then return end
    local knife = KnifeUse.On and EquipKnife()
    if knife and knife.Parent == LocalPlayer.Character then
        pcall(function() MeleeEvent:FireServer(plr, knife) end)
    else
        pcall(function() MeleeEvent:FireServer(plr) end)
    end
end

local function KillRoot(char) return char and (char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso")) end
local function HasFF(plr) local c = plr and plr.Character return c ~= nil and c:FindFirstChildOfClass("ForceField") ~= nil end

local function KillRun(target)
    local char = LocalPlayer.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    local root = KillRoot(char)
    if not (hum and root and MeleeEvent) then return false end
    local home = root.CFrame
    local killed = false
    local deadline = os.clock() + 25

    local conn = RunService.Heartbeat:Connect(function()
        local mine = KillRoot(LocalPlayer.Character)
        local tRoot = KillRoot(target.Character)
        if not mine or not tRoot or HasFF(target) then return end
        local below = tRoot.Position - Vector3.new(0, Kill.Depth, 0)
        mine.AssemblyLinearVelocity = Vector3.zero
        mine.CFrame = CFrame.lookAt(below, tRoot.Position, Vector3.zAxis)
    end)

    while not Kill.Cancel and not Unloaded and os.clock() < deadline do
        local tChar = target.Character
        local tHum = tChar and tChar:FindFirstChildOfClass("Humanoid")
        if not target.Parent then break end
        if tHum and tHum.Health <= 0 then killed = true break end
        if hum.Health <= 0 then break end
        if HasFF(target) then break end
        if tHum and KillRoot(tChar) then
            MeleeHit(target)
        end
        if Kill.Delay > 0 then task.wait(Kill.Delay) else RunService.Heartbeat:Wait() end
    end

    conn:Disconnect()
    local mine = KillRoot(LocalPlayer.Character)
    if mine and hum.Health > 0 then
        mine.AssemblyLinearVelocity = Vector3.zero
        mine.CFrame = home
    end
    return killed
end

function Kill.Start(name, loop)
    if Kill.Busy then Notify("Kill", "Already running. Press Stop Kill first", 3) return end
    local target = name and Players:FindFirstChild(name)
    if not target then Notify("Kill", "Pick a player in the list first", 3) return end
    if not MeleeEvent then Notify("Kill", "The punch event was not found", 3) return end
    if not loop and HasFF(target) then Notify("Kill", target.DisplayName .. " has a forcefield", 3) return end
    Kill.Busy, Kill.Cancel, Kill.Loop, Kill.Name = true, false, loop and true or false, name
    task.spawn(function()
        repeat
            if loop then
                repeat task.wait(0.2) until Kill.Cancel or Unloaded or not target.Parent
                    or (not HasFF(target) and LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid") and LocalPlayer.Character.Humanoid.Health > 0
                        and target.Character and target.Character:FindFirstChildOfClass("Humanoid") and target.Character.Humanoid.Health > 0)
            end
            if Kill.Cancel or Unloaded or not target.Parent then break end
            local ok = KillRun(target)
            if ok then Notify("Kill", target.DisplayName .. " is dead", 3)
            elseif HasFF(target) and not loop then Notify("Kill", target.DisplayName .. " got a forcefield, stopped", 3) end
            task.wait(0.5)
        until not loop or Kill.Cancel or Unloaded or not target.Parent
        Kill.Busy = false
        if Kill.Obj and Kill.Obj.Set and loop then pcall(function() Kill.Obj:Set(false) end) end
    end)
end

function Kill.Stop()
    Kill.Cancel = true
    Kill.Loop = false
end

local Aura = { On = false, Range = 12, Delay = 0.25, Max = 5, Last = 0, TeamCheck = true }

local AuraConn = RunService.Heartbeat:Connect(function()
    if Unloaded or not Aura.On or not MeleeEvent then return end
    if os.clock() - Aura.Last < Aura.Delay then return end
    Aura.Last = os.clock()
    local mine = KillRoot(LocalPlayer.Character)
    local myHum = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
    if not mine or not myHum or myHum.Health <= 0 then return end
    local guard = LocalPlayer.TeamColor == BrickColor.new("Bright blue")
    local hit = 0
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= LocalPlayer and hit < Aura.Max then
            local char = plr.Character
            local hum = char and char:FindFirstChildOfClass("Humanoid")
            local root = KillRoot(char)
            if hum and root and hum.Health > 0 and not HasFF(plr)
                and (root.Position - mine.Position).Magnitude <= Aura.Range
                and not (Aura.TeamCheck and guard and plr.TeamColor == LocalPlayer.TeamColor) then
                hit = hit + 1
                MeleeHit(plr)
            end
        end
    end
end)

-- Dinner / Breakfast: while on, flips every tool named "dinner" or "breakfast"
-- between held and backpack, one tool per step, taking turns if you have both.
-- Speed 100 = one flip per frame, lower speeds add a pause between flips.
local Dinner = { On = false, Speed = 100, Running = false, Turn = 0 }
local FOOD_NAMES = { dinner = true, breakfast = true }

local function FindFood()
    local found = {}
    local backpack = LocalPlayer:FindFirstChildOfClass("Backpack")
    for _, holder in ipairs({ LocalPlayer.Character, backpack }) do
        if holder then
            for _, item in ipairs(holder:GetChildren()) do
                if item:IsA("Tool") and FOOD_NAMES[string.lower(item.Name)] then found[#found + 1] = item end
            end
        end
    end
    table.sort(found, function(a, b) return a.Name < b.Name end)
    return found
end

local function DinnerLoop()
    if Dinner.Running then return end
    Dinner.Running = true
    while Dinner.On and not Unloaded do
        local char = LocalPlayer.Character
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        local backpack = LocalPlayer:FindFirstChildOfClass("Backpack")
        local tools = FindFood()
        if hum and hum.Health > 0 and backpack and #tools > 0 then
            Dinner.Turn = Dinner.Turn % #tools + 1
            local tool = tools[Dinner.Turn]
            if tool.Parent == char then
                pcall(function() tool.Parent = backpack end)
            else
                pcall(function() hum:EquipTool(tool) end)
            end
        end
        local pause = (100 - Dinner.Speed) * 0.01
        if pause > 0 then task.wait(pause) else RunService.Heartbeat:Wait() end
    end
    Dinner.Running = false
end

lib = LIPUI.new()
local win = lib:Window("PRISON LIFE LEGACY", Enum.KeyCode.LeftAlt)
local function onoff(name) return function(s) Notify(name, s and "Enabled" or "Disabled", 2) end end

local gunTab = win:Tab("Guns", "target")
gunTab:Section("Ammo")
gunTab:Paragraph("Auto Reload", "Reloads for you the moment a gun runs empty, using the game's own reload. Pair it with Custom Reload Time for short pauses.")
gunTab:Toggle("Auto Reload", Mods.AutoReload, function(s) Mods.AutoReload = s onoff("Auto Reload")(s) end)
gunTab:Section("Accuracy")
gunTab:Toggle("No Spread", Mods.NoSpread, function(s) Mods.NoSpread = s onoff("No Spread")(s) end)
gunTab:Section("Fire")
gunTab:Toggle("Make Every Gun Automatic", Mods.AutoFire, function(s) Mods.AutoFire = s onoff("Automatic")(s) end)
gunTab:Toggle("Custom Fire Rate", Mods.FastRate, function(s) Mods.FastRate = s onoff("Custom Fire Rate")(s) end)
gunTab:Slider("Milliseconds Between Shots", 0, 500, math.floor(Mods.Rate * 1000 + 0.5), function(v) Mods.Rate = v / 1000 end)
gunTab:Toggle("Custom Reload Time", Mods.FastReload, function(s) Mods.FastReload = s onoff("Custom Reload Time")(s) end)
gunTab:Slider("Reload Milliseconds", 0, 3000, math.floor(Mods.ReloadTime * 1000 + 0.5), function(v) Mods.ReloadTime = v / 1000 end)

local silentTab = win:Tab("Silent Aim", "crosshair")
silentTab:Section("Silent Aim")
silentTab:Paragraph("Silent Aim", "Your shots go toward the player closest to your crosshair inside the circle. A wall in the way still blocks the shot.")
silentTab:Toggle("Silent Aim", Silent.On, function(s) Silent.On = s onoff("Silent Aim")(s) end)
silentTab:Dropdown("Target Part", { "Head", "Torso" }, function(v) Silent.Part = v end, Silent.Part)
silentTab:Slider("FOV Radius", 20, 600, Silent.FOV, function(v) Silent.FOV = v end)
silentTab:Slider("Hit Chance %", 1, 100, Silent.HitChance, function(v) Silent.HitChance = v end)
silentTab:Toggle("Team Check", Silent.TeamCheck, function(s) Silent.TeamCheck = s end)
silentTab:Toggle("Show FOV Circle", Silent.ShowFOV, function(s) Silent.ShowFOV = s end)

local playerTab = win:Tab("Player", "user")
playerTab:Section("Stamina")
playerTab:Paragraph("Infinite Stamina", "Stamina in this game is your jump count. This keeps it full so you can jump as much as you want.")
playerTab:Toggle("Infinite Stamina", Stamina.On, function(s) Stamina.On = s onoff("Infinite Stamina")(s) end)

playerTab:Section("Kill")
playerTab:Paragraph("Kill", "Goes underneath the player and hits them with your knife (or punches if you have none) until they are dead, then takes you back. Pick a player first.")
local killTarget
local plist = playerTab:PlayerList(150, function(name) killTarget = name end)
local function refreshPlayers()
    local names = {}
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LocalPlayer then names[#names + 1] = p.Name end
    end
    table.sort(names)
    plist:Refresh(names)
end
refreshPlayers()
Players.PlayerAdded:Connect(function() if not Unloaded then refreshPlayers() end end)
Players.PlayerRemoving:Connect(function() if not Unloaded then task.defer(refreshPlayers) end end)
playerTab:Button("Refresh List", refreshPlayers)
playerTab:Button("Kill Selected", function() Kill.Start(killTarget, false) end)
Kill.Obj = playerTab:Toggle("Loop Kill Selected", false, function(s)
    if s then Kill.Start(killTarget, true) else Kill.Stop() end
end)
playerTab:Button("Stop Kill", function() Kill.Stop() end)
playerTab:Toggle("Use Knife When You Have One", KnifeUse.On, function(s) KnifeUse.On = s onoff("Use Knife")(s) end)
playerTab:Slider("Punch Delay (ms)", 0, 1000, math.floor(Kill.Delay * 1000 + 0.5), function(v) Kill.Delay = v / 1000 end)
playerTab:Slider("Kill Depth (studs below)", 1, 12, Kill.Depth, function(v) Kill.Depth = v end)

playerTab:Section("Kill Aura")
playerTab:Paragraph("Kill Aura", "Punches every player near you without moving you. Skips players with a forcefield.")
playerTab:Toggle("Kill Aura", Aura.On, function(s) Aura.On = s onoff("Kill Aura")(s) end)
playerTab:Slider("Aura Range (studs)", 3, 100, Aura.Range, function(v) Aura.Range = v end)
playerTab:Slider("Aura Delay (ms)", 0, 1000, math.floor(Aura.Delay * 1000 + 0.5), function(v) Aura.Delay = v / 1000 end)
playerTab:Slider("Aura Targets", 1, 20, Aura.Max, function(v) Aura.Max = v end)
playerTab:Toggle("Skip My Team (guards)", Aura.TeamCheck, function(s) Aura.TeamCheck = s end)

playerTab:Section("Dinner / Breakfast")
playerTab:Paragraph("Dinner / Breakfast", "Unequips and re-equips your tools named dinner and breakfast over and over, taking turns if you have both. Nothing happens if you have neither.")
playerTab:Toggle("Dinner / Breakfast Loop", Dinner.On, function(s)
    Dinner.On = s
    onoff("Dinner / Breakfast Loop")(s)
    if s then
        if #FindFood() == 0 then Notify("Dinner / Breakfast", "No tool named dinner or breakfast found yet, waiting for one", 3) end
        task.spawn(DinnerLoop)
    end
end)
playerTab:Slider("Food Loop Speed (100 = fastest)", 0, 100, Dinner.Speed, function(v) Dinner.Speed = v end)

local settings = win:Tab("Settings", "settings")
settings:Section("Script")
settings:Button("Unload", function()
    Unloaded = true
    Connection:Disconnect()
    StaminaConn:Disconnect()
    AuraConn:Disconnect()
    Kill.Cancel = true
    Dinner.On = false
    if circle then pcall(function() circle:Remove() end) end
    EachTool(function(tool)
        local states = GetStates(tool)
        local o = states and Originals[states]
        if o then
            states.FireRate, states.AutoFire, states.ReloadTime = o.FireRate, o.AutoFire, o.ReloadTime
        end
        if states then pcall(SetSpread, tool, states, false) end
    end)
    genv.PLL_LOADED = nil
    lib:Destroy()
end)

Notify("Prison Life Legacy", "Loaded. Press Left Alt to open the menu", 4)
