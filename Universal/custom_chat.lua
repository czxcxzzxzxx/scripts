-- Executor chat client (WebSocket with automatic HTTP-poll fallback)
local SERVER = "https://nonfq-chat.doorplayz123.workers.dev"

local env = (getgenv and getgenv()) or _G
if env.__ChatCleanup then pcall(env.__ChatCleanup) end

-- The admin token is NOT stored in this script (it's public). It is loaded from:
--   1) a file named chat_admin.txt in your executor's workspace folder (just the token, nothing else), or
--   2) getgenv().ChatAdminToken = "..." set in your own autoexec before this script runs.
-- If neither exists, admin commands are simply off.
local ADMIN_TOKEN = ""
do
	local ok, v = pcall(function()
		if env.ChatAdminToken then return env.ChatAdminToken end
		if isfile and readfile and isfile("chat_admin.txt") then return readfile("chat_admin.txt") end
	end)
	if ok and type(v) == "string" then ADMIN_TOKEN = (v:gsub("%s+", "")) end
end

local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local UIS = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local lp = Players.LocalPlayer

-- id must match CHANNELS in worker.js
local CHANNELS = {
	{ id = "main", name = "Main Chat" },
	{ id = "lounge", name = "Lounge" },
	{ id = "offtopic", name = "Off-Topic" },
}

local WS_URL = (SERVER:gsub("^http", "ws")) .. "/ws"
local MAX_LEN = 200
local WIN_W, WIN_H = 540, 360
local MIN_W, MIN_H = 420, 240
local TITLE_H = 36
local SIDE_W = 124

local req = request or http_request or (syn and syn.request) or (http and http.request) or (fluxus and fluxus.request)
local hasWS = (WebSocket and WebSocket.connect) and true or false

-- hardware id (used for HWID bans)
local HWID = ""
do
	local ok, v = pcall(function()
		if gethwid then return gethwid() end
		return game:GetService("RbxAnalyticsService"):GetClientId()
	end)
	if ok and type(v) == "string" then HWID = v end
end

local alive = true
local banned = false
local conns = {}
local function bind(signal, fn)
	local c = signal:Connect(fn)
	conns[#conns + 1] = c
	return c
end

-- ---------- emoji shortcodes (:sob: -> emoji) ----------
local EMOJI_RAW = {
	smile = 0x1F604, grin = 0x1F601, joy = 0x1F602, rofl = 0x1F923, smiley = 0x1F603, laughing = 0x1F606,
	sweat_smile = 0x1F605, wink = 0x1F609, blush = 0x1F60A, innocent = 0x1F607, slight_smile = 0x1F642,
	upside_down = 0x1F643, relaxed = 0x263A, relieved = 0x1F60C, heart_eyes = 0x1F60D, star_struck = 0x1F929,
	kissing_heart = 0x1F618, yum = 0x1F60B, stuck_out_tongue = 0x1F61B, stuck_out_tongue_winking_eye = 0x1F61C,
	zany = 0x1F92A, money_mouth = 0x1F911, hugging = 0x1F917, thinking = 0x1F914, shushing = 0x1F92B,
	zipper_mouth = 0x1F910, neutral_face = 0x1F610, expressionless = 0x1F611, unamused = 0x1F612,
	rolling_eyes = 0x1F644, smirk = 0x1F60F, grimacing = 0x1F62C, pensive = 0x1F614, sleepy = 0x1F62A,
	sleeping = 0x1F634, mask = 0x1F637, nauseated = 0x1F922, vomiting = 0x1F92E, hot_face = 0x1F975,
	cold_face = 0x1F976, dizzy_face = 0x1F635, exploding_head = 0x1F92F, cowboy = 0x1F920,
	partying_face = 0x1F973, sunglasses = 0x1F60E, nerd = 0x1F913, monocle = 0x1F9D0, confused = 0x1F615,
	worried = 0x1F61F, open_mouth = 0x1F62E, hushed = 0x1F62F, astonished = 0x1F632, flushed = 0x1F633,
	pleading = 0x1F97A, cry = 0x1F622, sob = 0x1F62D, scream = 0x1F631, fearful = 0x1F628, weary = 0x1F629,
	tired_face = 0x1F62B, triumph = 0x1F624, angry = 0x1F620, rage = 0x1F621, disappointed = 0x1F61E,
	sweat = 0x1F613, yawning = 0x1F971, melting_face = 0x1FAE0, salute = 0x1FAE1, face_holding_back_tears = 0x1F979,
	skull = 0x1F480, skull_crossbones = { 0x2620, 0xFE0F }, ghost = 0x1F47B, alien = 0x1F47D, robot = 0x1F916,
	poop = 0x1F4A9, clown = 0x1F921, smiling_imp = 0x1F608, imp = 0x1F47F, angel = 0x1F47C,
	see_no_evil = 0x1F648, hear_no_evil = 0x1F649, speak_no_evil = 0x1F64A,
	["+1"] = 0x1F44D, thumbsup = 0x1F44D, ["-1"] = 0x1F44E, thumbsdown = 0x1F44E, clap = 0x1F44F,
	raised_hands = 0x1F64C, pray = 0x1F64F, wave = 0x1F44B, ok_hand = 0x1F44C, muscle = 0x1F4AA,
	handshake = 0x1F91D, v = { 0x270C, 0xFE0F }, crossed_fingers = 0x1F91E, fist = 0x270A, punch = 0x1F44A,
	point_up = { 0x261D, 0xFE0F }, point_right = 0x1F449, point_left = 0x1F448, point_down = 0x1F447,
	middle_finger = 0x1F595, facepalm = 0x1F926, shrug = 0x1F937, eyes = 0x1F440, brain = 0x1F9E0,
	nail_care = 0x1F485, lips = 0x1F444, kiss = 0x1F48B,
	heart = { 0x2764, 0xFE0F }, broken_heart = 0x1F494, blue_heart = 0x1F499, green_heart = 0x1F49A,
	yellow_heart = 0x1F49B, purple_heart = 0x1F49C, black_heart = 0x1F5A4, orange_heart = 0x1F9E1,
	white_heart = 0x1F90D, sparkling_heart = 0x1F496,
	fire = 0x1F525, ["100"] = 0x1F4AF, sparkles = 0x2728, star = 0x2B50, boom = 0x1F4A5, zap = 0x26A1,
	tada = 0x1F389, balloon = 0x1F388, gift = 0x1F381, cake = 0x1F382, trophy = 0x1F3C6, crown = 0x1F451,
	gem = 0x1F48E, rocket = 0x1F680, bulb = 0x1F4A1, bomb = 0x1F4A3, anger = 0x1F4A2, zzz = 0x1F4A4,
	sweat_drops = 0x1F4A6, dash = 0x1F4A8, moyai = 0x1F5FF, cap = 0x1F9E2,
	sun = { 0x2600, 0xFE0F }, moon = 0x1F319, cloud = { 0x2601, 0xFE0F }, rainbow = 0x1F308,
	snowflake = { 0x2744, 0xFE0F },
	dog = 0x1F436, cat = 0x1F431, frog = 0x1F438, monkey = 0x1F435, unicorn = 0x1F984, snake = 0x1F40D,
	bug = 0x1F41B, skull_dog = 0x1F415,
	pizza = 0x1F355, hamburger = 0x1F354, fries = 0x1F35F, taco = 0x1F32E, beer = 0x1F37A, coffee = 0x2615,
	popcorn = 0x1F37F, cookie = 0x1F36A, apple = 0x1F34E, banana = 0x1F34C, strawberry = 0x1F353,
	watermelon = 0x1F349, cherries = 0x1F352, peach = 0x1F351, eggplant = 0x1F346,
	video_game = 0x1F3AE, game_die = 0x1F3B2, computer = 0x1F4BB, iphone = 0x1F4F1, headphones = 0x1F3A7,
	microphone = 0x1F3A4, musical_note = 0x1F3B5, key = 0x1F511, lock = 0x1F512, bell = 0x1F514,
	mute = 0x1F507, speaker = 0x1F50A, crossed_swords = { 0x2694, 0xFE0F }, shield = { 0x1F6E1, 0xFE0F },
	moneybag = 0x1F4B0, dollar = 0x1F4B5, chart_up = 0x1F4C8,
	white_check_mark = 0x2705, check = { 0x2714, 0xFE0F }, x = 0x274C, warning = { 0x26A0, 0xFE0F },
	question = 0x2753, exclamation = 0x2757, no_entry = 0x26D4, arrow_right = { 0x27A1, 0xFE0F },
	sos = 0x1F198, cool = 0x1F192, new = 0x1F195, ok = 0x1F197,
}
local EMOJI = {}
for k, v in pairs(EMOJI_RAW) do
	EMOJI[k] = type(v) == "table" and utf8.char(table.unpack(v)) or utf8.char(v)
end

local function emojify(s)
	local out, i = {}, 1
	while true do
		local a, b, name = s:find(":([%w_%+%-]+):", i)
		if not a then break end
		local e = EMOJI[name:lower()]
		if e then
			out[#out + 1] = s:sub(i, a - 1)
			out[#out + 1] = e
			i = b + 1
		else
			-- not a known shortcode: keep text, let the closing colon start the next match
			out[#out + 1] = s:sub(i, b - 1)
			i = b
		end
	end
	out[#out + 1] = s:sub(i)
	return table.concat(out)
end

-- character-aware clip (never cuts an emoji in half)
local function clip(s, n)
	local len = utf8.len(s)
	if not len then return s:sub(1, n) end
	if len <= n then return s end
	return s:sub(1, utf8.offset(s, n + 1) - 1)
end

-- ---------- http ----------
local function api(method, path, body)
	if not req then return nil end
	local ok, res = pcall(req, {
		Url = SERVER .. path,
		Method = method,
		Headers = {
			["Content-Type"] = "application/json",
			["x-uid"] = tostring(lp.UserId),
			["x-user"] = lp.Name,
			["x-hwid"] = HWID,
		},
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

-- ---------- window ----------
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
}, gui)
round(win, 10)
new("UIStroke", { Color = Color3.fromRGB(50, 54, 68), Thickness = 1 }, win)

-- title bar: its own rounded corners, plus a square filler so only the TOP corners are round
local titleBar = new("Frame", {
	Size = UDim2.new(1, 0, 0, TITLE_H),
	BackgroundColor3 = C.bar,
	BorderSizePixel = 0,
}, win)
round(titleBar, 10)
local titleFill = new("Frame", {
	Size = UDim2.new(1, 0, 0, 10),
	Position = UDim2.new(0, 0, 1, -10),
	BackgroundColor3 = C.bar,
	BorderSizePixel = 0,
}, titleBar)

-- left: connection status
local dot = new("Frame", {
	Size = UDim2.fromOffset(9, 9),
	Position = UDim2.fromOffset(12, (TITLE_H - 9) / 2),
	BackgroundColor3 = C.warn,
	BorderSizePixel = 0,
}, titleBar)
round(dot, 5)
local status = new("TextLabel", {
	Size = UDim2.fromOffset(90, TITLE_H),
	Position = UDim2.fromOffset(28, 0),
	BackgroundTransparency = 1,
	Text = "Connecting...",
	Font = Enum.Font.Gotham,
	TextSize = 12,
	TextColor3 = C.dim,
	TextXAlignment = Enum.TextXAlignment.Left,
}, titleBar)

-- center: title + online count
local center = new("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(0, 22),
	AutomaticSize = Enum.AutomaticSize.X,
	BackgroundTransparency = 1,
}, titleBar)
new("UIListLayout", {
	FillDirection = Enum.FillDirection.Horizontal,
	HorizontalAlignment = Enum.HorizontalAlignment.Center,
	VerticalAlignment = Enum.VerticalAlignment.Center,
	SortOrder = Enum.SortOrder.LayoutOrder,
	Padding = UDim.new(0, 8),
}, center)
new("TextLabel", {
	Size = UDim2.fromOffset(0, 22),
	AutomaticSize = Enum.AutomaticSize.X,
	BackgroundTransparency = 1,
	Text = "Chat",
	Font = Enum.Font.GothamBold,
	TextSize = 15,
	TextColor3 = C.text,
	LayoutOrder = 1,
}, center)
local pill = new("Frame", {
	Size = UDim2.fromOffset(0, 20),
	AutomaticSize = Enum.AutomaticSize.X,
	BackgroundColor3 = C.btn,
	BorderSizePixel = 0,
	LayoutOrder = 2,
}, center)
round(pill, 10)
new("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 9) }, pill)
new("UIListLayout", {
	FillDirection = Enum.FillDirection.Horizontal,
	VerticalAlignment = Enum.VerticalAlignment.Center,
	SortOrder = Enum.SortOrder.LayoutOrder,
	Padding = UDim.new(0, 5),
}, pill)
round(new("Frame", { Size = UDim2.fromOffset(7, 7), BackgroundColor3 = C.good, BorderSizePixel = 0, LayoutOrder = 1 }, pill), 4)
local countLbl = new("TextLabel", {
	Size = UDim2.fromOffset(0, 20),
	AutomaticSize = Enum.AutomaticSize.X,
	BackgroundTransparency = 1,
	Text = "-- online",
	Font = Enum.Font.Gotham,
	TextSize = 12,
	TextColor3 = C.text,
	LayoutOrder = 2,
}, pill)

-- right: minimize / close
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

-- ---------- body ----------
local body = new("Frame", {
	Position = UDim2.fromOffset(0, TITLE_H),
	Size = UDim2.new(1, 0, 1, -TITLE_H),
	BackgroundTransparency = 1,
}, win)

-- sidebar (channels)
local side = new("Frame", {
	Position = UDim2.fromOffset(8, 8),
	Size = UDim2.new(0, SIDE_W, 1, -16),
	BackgroundColor3 = C.panel,
	BorderSizePixel = 0,
}, body)
round(side, 8)
new("TextLabel", {
	Position = UDim2.fromOffset(12, 8),
	Size = UDim2.new(1, -24, 0, 16),
	BackgroundTransparency = 1,
	Text = "CHANNELS",
	Font = Enum.Font.GothamBold,
	TextSize = 11,
	TextColor3 = C.dim,
	TextXAlignment = Enum.TextXAlignment.Left,
}, side)
new("TextLabel", {
	Position = UDim2.new(0, 12, 1, -26),
	Size = UDim2.new(1, -24, 0, 18),
	BackgroundTransparency = 1,
	Text = lp.Name,
	Font = Enum.Font.Gotham,
	TextSize = 11,
	TextColor3 = C.dim,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextTruncate = Enum.TextTruncate.AtEnd,
}, side)

local CONTENT_X = SIDE_W + 16
local current = "main"
local unread, chBtns, chanName = {}, {}, {}

for i, ch in ipairs(CHANNELS) do
	chanName[ch.id] = ch.name
	local b = new("TextButton", {
		Position = UDim2.new(0, 6, 0, 28 + (i - 1) * 34),
		Size = UDim2.new(1, -12, 0, 30),
		BackgroundColor3 = C.btnHover,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Text = "# " .. ch.name,
		Font = Enum.Font.GothamMedium,
		TextSize = 13,
		TextColor3 = C.text,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		AutoButtonColor = false,
	}, side)
	round(b, 6)
	new("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 30) }, b)
	local badge = new("TextLabel", {
		Size = UDim2.fromOffset(24, 16),
		Position = UDim2.new(1, 24, 0.5, -8), -- inside the button's right padding
		BackgroundColor3 = C.danger,
		BorderSizePixel = 0,
		Text = "0",
		Font = Enum.Font.GothamBold,
		TextSize = 10,
		TextColor3 = Color3.new(1, 1, 1),
		Visible = false,
	}, b)
	round(badge, 8)
	chBtns[ch.id] = { btn = b, badge = badge }
	unread[ch.id] = 0
end

-- one scrolling list per channel
local lists = {}
for _, ch in ipairs(CHANNELS) do
	local l = new("ScrollingFrame", {
		Position = UDim2.new(0, CONTENT_X, 0, 8),
		Size = UDim2.new(1, -(CONTENT_X + 8), 1, -58),
		BackgroundColor3 = C.panel,
		BorderSizePixel = 0,
		ScrollBarThickness = 4,
		ScrollBarImageColor3 = C.btnHover,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		Visible = ch.id == current,
	}, body)
	round(l, 8)
	new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 3) }, l)
	new("UIPadding", {
		PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8),
		PaddingTop = UDim.new(0, 6), PaddingBottom = UDim.new(0, 6),
	}, l)
	lists[ch.id] = l
end

-- input row
local row = new("Frame", {
	Position = UDim2.new(0, CONTENT_X, 1, -42),
	Size = UDim2.new(1, -(CONTENT_X + 8), 0, 34),
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
	PlaceholderText = "Message #" .. chanName[current],
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
	Position = UDim2.new(1, -18, 1, -18),
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

-- ---------- channel switching ----------
local function refreshChannels()
	for id, b in pairs(chBtns) do
		local active = id == current
		b.btn.BackgroundColor3 = active and C.accent or C.btnHover
		tween(b.btn, 0.12, { BackgroundTransparency = active and 0 or 1 })
		local n = unread[id] or 0
		b.badge.Visible = n > 0 and not active
		b.badge.Text = n > 99 and "99+" or tostring(n)
	end
end

local function setChannel(id)
	if not lists[id] then return end
	current = id
	unread[id] = 0
	for cid, l in pairs(lists) do l.Visible = cid == id end
	box.PlaceholderText = "Message #" .. chanName[id]
	refreshChannels()
	task.defer(function()
		if alive then lists[id].CanvasPosition = Vector2.new(0, 1e6) end
	end)
end

for id, b in pairs(chBtns) do
	bind(b.btn.Activated, function() setChannel(id) end)
	bind(b.btn.MouseEnter, function()
		if current ~= id then tween(b.btn, 0.12, { BackgroundTransparency = 0.5 }) end
	end)
	bind(b.btn.MouseLeave, function()
		if current ~= id then tween(b.btn, 0.12, { BackgroundTransparency = 1 }) end
	end)
end

-- ---------- drag / resize (mouse + touch) ----------
-- Pure deltas applied to the starting UDim2, so the window stays under the cursor.
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
	win.Size = UDim2.fromOffset(math.max(MIN_W, sz.X.Offset + dx), math.max(MIN_H, sz.Y.Offset + dy))
end)

-- minimize
local minimized, savedSize = false, win.Size
bind(minBtn.Activated, function()
	minimized = not minimized
	if minimized then
		savedSize = win.Size
		body.Visible = false
		grip.Visible = false
		titleFill.Visible = false -- let the collapsed bar keep all four corners round
		win.Size = UDim2.fromOffset(win.AbsoluteSize.X, TITLE_H)
		minBtn.Text = "+"
	else
		win.Size = savedSize
		body.Visible = true
		grip.Visible = true
		titleFill.Visible = true
		minBtn.Text = "-"
	end
end)

-- ---------- messages ----------
local seen, queues = {}, {}
for _, ch in ipairs(CHANNELS) do queues[ch.id] = {} end
local lastId, order = 0, 0

local function addLabel(chId, richText, color)
	local list = lists[chId] or lists.main
	local q = queues[lists[chId] and chId or "main"]
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
	q[#q + 1] = l
	if #q > 200 then table.remove(q, 1):Destroy() end
	if atBottom then
		task.delay(0.05, function()
			if alive then list.CanvasPosition = Vector2.new(0, 1e6) end
		end)
	end
	return l
end

local function sys(text)
	addLabel(current, "<i>" .. esc(text) .. "</i>", C.sys)
end

local function addMessage(m, silent)
	if type(m) ~= "table" or type(m.id) ~= "number" or seen[m.id] then return end
	seen[m.id] = true
	if m.id > lastId then lastId = m.id end
	local chId = lists[m.ch] and m.ch or "main"
	local mine = m.userId == lp.UserId
	local ts = os.date("%H:%M", math.floor((m.ts or 0) / 1000))
	local nc = mine and C.mine or nameColor(m.userId)
	local rich = string.format(
		'<font color="#%s">%s</font> <b><font color="#%s">%s</font></b>  %s',
		C.dim:ToHex(), esc(ts), nc:ToHex(), esc(m.user), esc(m.text)
	)
	addLabel(chId, rich, C.text)
	if not silent and not mine and chId ~= current then
		unread[chId] = (unread[chId] or 0) + 1
		refreshChannels()
	end
end

-- status: connecting | online (websocket) | fallback (http polling) | offline | banned
local STATUS = {
	connecting = { "Connecting...", C.warn },
	online = { "Online", C.good },
	fallback = { "Online", C.warn }, -- yellow dot = working, but on the slower HTTP fallback
	offline = { "Offline", C.bad },
	banned = { "Banned", C.bad },
}
local function setStatus(s)
	local info = STATUS[s] or STATUS.connecting
	status.Text = info[1]
	status.TextColor3 = info[2]
	tween(dot, 0.2, { BackgroundColor3 = info[2] })
end

local function setCount(n)
	if type(n) == "number" then countLbl.Text = n .. " online" end
end

-- ---------- network ----------
local ws, wsLive = nil, false

local function onBanned(msg)
	if banned then return end
	banned = true
	setStatus("banned")
	sys(msg or "you are banned")
	if ws then pcall(function() ws:Close() end) end
end

local function handle(raw)
	local ok, d = pcall(HttpService.JSONDecode, HttpService, raw)
	if not ok or type(d) ~= "table" then return end
	if d.t == "hist" then
		for _, m in ipairs(d.msgs or {}) do addMessage(m, true) end
		setCount(d.n)
	elseif d.t == "msg" then
		addMessage(d.m)
	elseif d.t == "count" then
		setCount(d.n)
	elseif d.t == "sys" then
		sys(d.text)
	elseif d.t == "err" then
		sys(d.error)
	elseif d.t == "banned" then
		onBanned(d.error)
	end
end

local function wsSend(tbl)
	if wsLive and ws then
		return pcall(function() ws:Send(HttpService:JSONEncode(tbl)) end)
	end
	return false
end

local function sendCommand(text)
	local payload = { t = "cmd", token = ADMIN_TOKEN, text = text }
	if wsSend(payload) then return end
	task.spawn(function()
		local code, data = api("POST", "/cmd", payload)
		sys((data and (data.text or data.error)) or ("command failed (" .. tostring(code) .. ")"))
	end)
end

local function send(text)
	local t = tostring(text):match("^%s*(.-)%s*$")
	if t == "" then return end
	if banned then sys("you are banned"); return end

	if t:sub(1, 1) == "/" then
		if ADMIN_TOKEN == "" then
			sys("commands are admin-only")
		else
			sendCommand(t)
		end
		return
	end

	t = clip(emojify(t), MAX_LEN)
	local payload = { t = "send", ch = current, user = lp.Name, userId = lp.UserId, text = t }
	if wsSend(payload) then return end
	task.spawn(function()
		local code, data = api("POST", "/send", payload)
		if code == 200 and data and data.m then
			addMessage(data.m)
		else
			if code == 403 and data and data.error == "you are banned" then onBanned(data.error) end
			sys((data and data.error) or ("send failed (" .. tostring(code) .. ")"))
		end
	end)
end

-- websocket loop (reconnects)
if hasWS then
	task.spawn(function()
		while alive and not banned do
			local ok, sock = pcall(WebSocket.connect, WS_URL)
			if ok and sock then
				local closed = false
				sock.OnMessage:Connect(handle)
				sock.OnClose:Connect(function() closed = true end)
				ws, wsLive = sock, true
				setStatus("online")
				pcall(function()
					sock:Send(HttpService:JSONEncode({ t = "hello", user = lp.Name, userId = lp.UserId, hwid = HWID }))
				end)
				while alive and not closed do task.wait(1) end
				wsLive, ws = false, nil
				pcall(function() sock:Close() end)
			end
			if banned then break end
			task.wait(8)
		end
	end)

	-- keep-alive + refreshes the online count
	task.spawn(function()
		while alive do
			task.wait(20)
			if wsLive then wsSend({ t = "ping" }) end
		end
	end)
end

-- poll loop (only runs while the websocket isn't live)
task.spawn(function()
	while alive and not banned do
		if not wsLive then
			local first = lastId == 0
			local code, data = api("GET", "/poll?since=" .. lastId)
			if code == 200 and data then
				setStatus("fallback")
				for _, m in ipairs(data.msgs or {}) do addMessage(m, first) end
				setCount(data.n)
			elseif code == 403 and data and data.banned then
				onBanned(data.error)
			else
				setStatus("offline")
			end
		end
		task.wait(1.5)
	end
end)

-- ---------- input ----------
bind(box:GetPropertyChangedSignal("Text"), function()
	local txt = box.Text
	-- Discord-style: :sob: turns into the emoji as soon as you close the colon
	if box.CursorPosition == #txt + 1 then txt = emojify(txt) end
	txt = clip(txt, MAX_LEN)
	if txt ~= box.Text then
		box.Text = txt
		box.CursorPosition = #txt + 1
	end
	local n = utf8.len(txt) or #txt
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

setChannel("main")
setStatus("connecting")
if not req then sys("your executor has no request function; chat can't connect") end
sys("RightShift toggles the window")
if ADMIN_TOKEN ~= "" then sys("admin mode on. Type /help for commands") end
