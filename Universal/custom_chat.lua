-- Executor chat client (WebSocket with automatic HTTP-poll fallback)
local SERVER = "https://nonfq-chat.doorplayz123.workers.dev"

local env = (getgenv and getgenv()) or _G
if env.__ChatCleanup then pcall(env.__ChatCleanup) end

local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local UIS = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local lp = Players.LocalPlayer

local ROOM = "place-" .. game.PlaceId
local WS_URL = (SERVER:gsub("^http", "ws")) .. "/ws?room=" .. ROOM
local MAX_LEN = 200
local WIN_W, WIN_H = 440, 340
local TITLE_H = 34

local req = request or http_request or (syn and syn.request) or (http and http.request) or (fluxus and fluxus.request)
local hasWS = (WebSocket and WebSocket.connect) and true or false

local alive = true
local conns = {}
local function bind(signal, fn)
	local c = signal:Connect(fn)
	conns[#conns + 1] = c
	return c
end

-- ---------- http ----------
local function api(method, path, body)
	if not req then return nil end
	local ok, res = pcall(req, {
		Url = SERVER .. path,
		Method = method,
		Headers = { ["Content-Type"] = "application/json" },
		Body = body and HttpService:JSONEncode(body) or nil,
	})
	if not ok or type(res) ~= "table" then return nil end
	local dok, data = pcall(HttpService.JSONDecode, HttpService, res.Body or "")
	return res.StatusCode, dok and data or nil
end

-- ---------- theme ----------
local C = {
	bg = Color3.fromRGB(17, 18, 23),
	bar = Color3.fromRGB(24, 26, 33),
	panel = Color3.fromRGB(23, 25, 31),
	input = Color3.fromRGB(33, 36, 45),
	accent = Color3.fromRGB(88, 101, 242),
	accentHover = Color3.fromRGB(110, 122, 255),
	btn = Color3.fromRGB(40, 43, 54),
	btnHover = Color3.fromRGB(58, 62, 78),
	danger = Color3.fromRGB(237, 66, 69),
	text = Color3.fromRGB(230, 232, 240),
	mine = Color3.fromRGB(140, 200, 255),
	sys = Color3.fromRGB(255, 205, 110),
	dim = Color3.fromRGB(125, 130, 145),
	good = Color3.fromRGB(67, 214, 120),
	warn = Color3.fromRGB(250, 190, 70),
	bad = Color3.fromRGB(237, 66, 69),
}

local function new(class, props, parent)
	local o = Instance.new(class)
	for k, v in pairs(props) do o[k] = v end
	o.Parent = parent
	return o
end

local function round(obj, r)
	return new("UICorner", { CornerRadius = UDim.new(0, r or 8) }, obj)
end

local function tween(obj, t, props)
	TweenService:Create(obj, TweenInfo.new(t, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), props):Play()
end

local function esc(s)
	return (tostring(s):gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"):gsub('"', "&quot;"):gsub("'", "&apos;"))
end

local function nameColor(userId)
	return Color3.fromHSV(((tonumber(userId) or 0) * 47 % 360) / 360, 0.45, 1)
end

-- ---------- ui ----------
local parentGui = (gethui and gethui()) or game:GetService("CoreGui")
local gui = new("ScreenGui", {
	Name = HttpService:GenerateGUID(false),
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
	DisplayOrder = 999,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
}, parentGui)
if syn and syn.protect_gui then pcall(syn.protect_gui, gui) end

local cam = workspace.CurrentCamera
local vp = cam and cam.ViewportSize or Vector2.new(1280, 720)

local win = new("Frame", {
	Size = UDim2.fromOffset(WIN_W, WIN_H),
	Position = UDim2.fromOffset(math.floor((vp.X - WIN_W) / 2), math.floor((vp.Y - WIN_H) / 2)),
	BackgroundColor3 = C.bg,
	BorderSizePixel = 0,
	ClipsDescendants = true,
}, gui)
round(win, 10)
new("UIStroke", { Color = Color3.fromRGB(50, 54, 68), Thickness = 1 }, win)

-- title bar
local titleBar = new("Frame", {
	Size = UDim2.new(1, 0, 0, TITLE_H),
	BackgroundColor3 = C.bar,
	BorderSizePixel = 0,
}, win)

local dot = new("Frame", {
	Size = UDim2.fromOffset(9, 9),
	Position = UDim2.fromOffset(12, (TITLE_H - 9) / 2),
	BackgroundColor3 = C.warn,
	BorderSizePixel = 0,
}, titleBar)
round(dot, 5)

new("TextLabel", {
	Size = UDim2.new(1, -200, 1, 0),
	Position = UDim2.fromOffset(28, 0),
	BackgroundTransparency = 1,
	Text = "Chat",
	Font = Enum.Font.GothamBold,
	TextSize = 14,
	TextColor3 = C.text,
	TextXAlignment = Enum.TextXAlignment.Left,
}, titleBar)

local status = new("TextLabel", {
	Size = UDim2.fromOffset(110, TITLE_H),
	Position = UDim2.new(1, -176, 0, 0),
	BackgroundTransparency = 1,
	Text = "Connecting...",
	Font = Enum.Font.Gotham,
	TextSize = 12,
	TextColor3 = C.dim,
	TextXAlignment = Enum.TextXAlignment.Right,
}, titleBar)

local function titleButton(text, x)
	return new("TextButton", {
		Size = UDim2.fromOffset(26, 22),
		Position = UDim2.new(1, x, 0, (TITLE_H - 22) / 2),
		BackgroundColor3 = C.btn,
		BorderSizePixel = 0,
		Text = text,
		Font = Enum.Font.GothamBold,
		TextSize = 14,
		TextColor3 = C.text,
		AutoButtonColor = false,
	}, titleBar)
end
local minBtn = titleButton("-", -62)
local closeBtn = titleButton("X", -32)
round(minBtn, 6)
round(closeBtn, 6)

-- body
local body = new("Frame", {
	Position = UDim2.fromOffset(0, TITLE_H),
	Size = UDim2.new(1, 0, 1, -TITLE_H),
	BackgroundTransparency = 1,
}, win)

local list = new("ScrollingFrame", {
	Position = UDim2.fromOffset(8, 8),
	Size = UDim2.new(1, -16, 1, -58),
	BackgroundColor3 = C.panel,
	BorderSizePixel = 0,
	ScrollBarThickness = 4,
	ScrollBarImageColor3 = C.btnHover,
	CanvasSize = UDim2.new(),
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
}, body)
round(list, 8)
new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 3) }, list)
new("UIPadding", {
	PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8),
	PaddingTop = UDim.new(0, 6), PaddingBottom = UDim.new(0, 6),
}, list)

local row = new("Frame", {
	Position = UDim2.new(0, 8, 1, -42),
	Size = UDim2.new(1, -16, 0, 34),
	BackgroundTransparency = 1,
}, body)

local boxBg = new("Frame", {
	Size = UDim2.new(1, -78, 1, 0),
	BackgroundColor3 = C.input,
	BorderSizePixel = 0,
}, row)
round(boxBg, 8)
local boxStroke = new("UIStroke", { Color = C.input, Thickness = 1 }, boxBg)

local box = new("TextBox", {
	Size = UDim2.new(1, -58, 1, 0),
	Position = UDim2.fromOffset(10, 0),
	BackgroundTransparency = 1,
	Text = "",
	PlaceholderText = "Type a message...",
	PlaceholderColor3 = C.dim,
	ClearTextOnFocus = false,
	Font = Enum.Font.Gotham,
	TextSize = 13,
	TextColor3 = C.text,
	TextXAlignment = Enum.TextXAlignment.Left,
}, boxBg)

local counter = new("TextLabel", {
	Size = UDim2.fromOffset(48, 34),
	Position = UDim2.new(1, -52, 0, 0),
	BackgroundTransparency = 1,
	Text = "",
	Font = Enum.Font.Gotham,
	TextSize = 11,
	TextColor3 = C.dim,
	TextXAlignment = Enum.TextXAlignment.Right,
}, boxBg)

local sendBtn = new("TextButton", {
	Size = UDim2.new(0, 70, 1, 0),
	Position = UDim2.new(1, -70, 0, 0),
	BackgroundColor3 = C.accent,
	BorderSizePixel = 0,
	Text = "Send",
	Font = Enum.Font.GothamBold,
	TextSize = 13,
	TextColor3 = Color3.new(1, 1, 1),
	AutoButtonColor = false,
}, row)
round(sendBtn, 8)

local grip = new("TextButton", {
	Size = UDim2.fromOffset(16, 16),
	Position = UDim2.new(1, -16, 1, -16),
	BackgroundTransparency = 1,
	Text = "◢",
	Font = Enum.Font.Code,
	TextSize = 12,
	TextColor3 = C.dim,
	AutoButtonColor = false,
	ZIndex = 5,
}, win)

-- hover effects
local function hover(b, normal, over)
	bind(b.MouseEnter, function() tween(b, 0.12, { BackgroundColor3 = over }) end)
	bind(b.MouseLeave, function() tween(b, 0.12, { BackgroundColor3 = normal }) end)
end
hover(sendBtn, C.accent, C.accentHover)
hover(minBtn, C.btn, C.btnHover)
hover(closeBtn, C.btn, C.danger)

bind(box.Focused, function() tween(boxStroke, 0.15, { Color = C.accent }) end)
bind(box.FocusLost, function() tween(boxStroke, 0.15, { Color = C.input }) end)

-- ---------- drag / resize (mouse + touch) ----------
-- Uses pure deltas applied to the starting UDim2, so it never depends on
-- AbsolutePosition / GUI inset and the window stays exactly under the cursor.
local function makeDrag(handle, getStart, apply)
	bind(handle.InputBegan, function(input)
		local ut = input.UserInputType
		if ut ~= Enum.UserInputType.MouseButton1 and ut ~= Enum.UserInputType.Touch then return end
		local startPos = input.Position
		local state = getStart()
		local moveConn, endConn
		moveConn = UIS.InputChanged:Connect(function(i)
			if i.UserInputType == Enum.UserInputType.MouseMovement or i == input then
				apply(state, i.Position.X - startPos.X, i.Position.Y - startPos.Y)
			end
		end)
		endConn = input.Changed:Connect(function()
			if input.UserInputState == Enum.UserInputState.End then
				moveConn:Disconnect()
				endConn:Disconnect()
			end
		end)
	end)
end

makeDrag(titleBar, function() return win.Position end, function(sp, dx, dy)
	local v = (workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize) or Vector2.new(1280, 720)
	local w = win.AbsoluteSize.X
	local x = math.clamp(sp.X.Offset + dx, 60 - w, v.X - 60)
	local y = math.clamp(sp.Y.Offset + dy, 0, v.Y - TITLE_H)
	win.Position = UDim2.new(sp.X.Scale, x, sp.Y.Scale, y)
end)

makeDrag(grip, function() return win.Size end, function(sz, dx, dy)
	win.Size = UDim2.fromOffset(math.max(320, sz.X.Offset + dx), math.max(200, sz.Y.Offset + dy))
end)

-- minimize
local minimized, savedSize = false, win.Size
bind(minBtn.Activated, function()
	minimized = not minimized
	if minimized then
		savedSize = win.Size
		body.Visible = false
		grip.Visible = false
		win.Size = UDim2.fromOffset(win.AbsoluteSize.X, TITLE_H)
		minBtn.Text = "+"
	else
		win.Size = savedSize
		body.Visible = true
		grip.Visible = true
		minBtn.Text = "-"
	end
end)

-- ---------- messages ----------
local seen, labels, queue = {}, {}, {}
local lastId, order = 0, 0

local function addLabel(richText, color)
	local atBottom = list.CanvasPosition.Y + list.AbsoluteWindowSize.Y >= list.AbsoluteCanvasSize.Y - 40
	order += 1
	local l = new("TextLabel", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Text = richText,
		RichText = true, -- all user content is escaped via esc() before it gets here
		TextWrapped = true,
		Font = Enum.Font.Gotham,
		TextSize = 13,
		TextColor3 = color,
		TextTransparency = 1,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		LayoutOrder = order,
	}, list)
	tween(l, 0.2, { TextTransparency = 0 })
	queue[#queue + 1] = l
	if #queue > 200 then table.remove(queue, 1):Destroy() end
	if atBottom then
		task.delay(0.05, function()
			if alive then list.CanvasPosition = Vector2.new(0, 1e6) end
		end)
	end
	return l
end

local function sys(text)
	addLabel("<i>" .. esc(text) .. "</i>", C.sys)
end

local function addMessage(m)
	if type(m) ~= "table" or not m.id or seen[m.id] then return end
	seen[m.id] = true
	if m.id > lastId then lastId = m.id end
	local mine = m.userId == lp.UserId
	local ts = os.date("%H:%M", math.floor((m.ts or 0) / 1000))
	local nc = mine and C.mine or nameColor(m.userId)
	local rich = string.format(
		'<font color="#%s">%s</font> <b><font color="#%s">%s</font></b>  %s',
		C.dim:ToHex(), esc(ts), nc:ToHex(), esc(m.user), esc(m.text)
	)
	labels[m.id] = addLabel(rich, C.text)
end

local function removeMsg(id)
	local l = labels[id]
	if l then
		l:Destroy()
		labels[id] = nil
	end
end

-- status: "connecting" | "online" (websocket) | "fallback" (http polling) | "offline"
local STATUS = {
	connecting = { "Connecting...", C.warn },
	online = { "Online", C.good },
	fallback = { "Online", C.warn }, -- yellow dot = working, but on the slower HTTP fallback
	offline = { "Offline", C.bad },
}
local function setStatus(s)
	local info = STATUS[s] or STATUS.connecting
	status.Text = info[1]
	status.TextColor3 = info[2]
	tween(dot, 0.2, { BackgroundColor3 = info[2] })
end

-- ---------- network ----------
local ws, wsLive = nil, false

local function handle(raw)
	local ok, d = pcall(HttpService.JSONDecode, HttpService, raw)
	if not ok or type(d) ~= "table" then return end
	if d.t == "hist" then
		for _, m in ipairs(d.msgs or {}) do addMessage(m) end
	elseif d.t == "msg" then
		addMessage(d.m)
	elseif d.t == "del" then
		removeMsg(d.id)
	elseif d.t == "err" then
		sys(d.error)
	end
end

local function send(text)
	local t = tostring(text):match("^%s*(.-)%s*$")
	if t == "" then return end
	t = t:sub(1, MAX_LEN)
	local payload = { t = "send", user = lp.Name, userId = lp.UserId, text = t }
	if wsLive and ws then
		if pcall(function() ws:Send(HttpService:JSONEncode(payload)) end) then return end
	end
	task.spawn(function()
		local code, data = api("POST", "/send?room=" .. ROOM, payload)
		if code == 200 and data and data.m then
			addMessage(data.m)
		else
			sys((data and data.error) or ("send failed (" .. tostring(code) .. ")"))
		end
	end)
end

-- websocket loop (reconnects)
if hasWS then
	task.spawn(function()
		while alive do
			local ok, sock = pcall(WebSocket.connect, WS_URL)
			if ok and sock then
				ws, wsLive = sock, true
				setStatus("online")
				local closed = false
				sock.OnMessage:Connect(handle)
				sock.OnClose:Connect(function() closed = true end)
				while alive and not closed do task.wait(1) end
				wsLive, ws = false, nil
				pcall(function() sock:Close() end)
			end
			task.wait(8)
		end
	end)
end

-- poll loop (only runs while the websocket isn't live)
task.spawn(function()
	while alive do
		if not wsLive then
			local code, data = api("GET", "/poll?room=" .. ROOM .. "&since=" .. lastId)
			if code == 200 and data then
				setStatus("fallback")
				for _, m in ipairs(data.msgs or {}) do addMessage(m) end
				for _, id in ipairs(data.dels or {}) do removeMsg(id) end
			else
				setStatus("offline")
			end
		end
		task.wait(1.5)
	end
end)

-- ---------- input ----------
bind(box:GetPropertyChangedSignal("Text"), function()
	if #box.Text > MAX_LEN then box.Text = box.Text:sub(1, MAX_LEN) end
	local n = #box.Text
	counter.Text = n >= 150 and (n .. "/" .. MAX_LEN) or ""
	counter.TextColor3 = n >= MAX_LEN and C.bad or C.dim
end)
bind(box.FocusLost, function(enter)
	if enter then
		send(box.Text)
		box.Text = ""
		task.defer(function() if alive then box:CaptureFocus() end end)
	end
end)
bind(sendBtn.Activated, function()
	send(box.Text)
	box.Text = ""
end)
bind(UIS.InputBegan, function(i, gp)
	if not gp and i.KeyCode == Enum.KeyCode.RightShift then win.Visible = not win.Visible end
end)

local function cleanup()
	alive = false
	for _, c in ipairs(conns) do pcall(function() c:Disconnect() end) end
	if ws then pcall(function() ws:Close() end) end
	gui:Destroy()
	env.__ChatCleanup = nil
end
env.__ChatCleanup = cleanup
bind(closeBtn.Activated, cleanup)

setStatus("connecting")
if not req then sys("your executor has no request function; chat can't connect") end
sys("RightShift toggles the window")
