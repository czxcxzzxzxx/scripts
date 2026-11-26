-- Online Chat client (WebSocket with automatic HTTP-poll fallback)
local SERVER = "https://nonfq-chat.doorplayz123.workers.dev"

local env = (getgenv and getgenv()) or _G
if env.__ChatCleanup then pcall(env.__ChatCleanup) end

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
local MAX_LEN = 9000
local WIN_W, WIN_H = 760, 480
local MIN_W, MIN_H = 570, 365
local TITLE_H = 46
local SIDE_W = 172
local GIF_MAX_W, GIF_MAX_H = 240, 170
local MAX_ASSET_BYTES = 4 * 1024 * 1024
local SETTINGS_FILE = "chat_settings.json"
local CACHE_DIR = "chatgif"
local TICK = string.char(96)
local FENCE = string.rep(TICK, 3)

local req = request or http_request or (syn and syn.request) or (http and http.request) or (fluxus and fluxus.request)
local hasWS = (WebSocket and WebSocket.connect) and true or false
local copyFn = (type(setclipboard) == "function" and setclipboard) or (type(toclipboard) == "function" and toclipboard) or nil

-- hardware id (used by server-side bans)
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

-- ---------- settings (saved in your executor's workspace) ----------
local toggleKey = Enum.KeyCode.RightShift
local textSize = 13
do
	local ok, raw = pcall(function()
		if isfile and readfile and isfile(SETTINGS_FILE) then return readfile(SETTINGS_FILE) end
	end)
	if ok and type(raw) == "string" then
		local dok, d = pcall(HttpService.JSONDecode, HttpService, raw)
		if dok and type(d) == "table" then
			if type(d.toggleKey) == "string" then
				local kok, kc = pcall(function() return Enum.KeyCode[d.toggleKey] end)
				if kok and kc and kc ~= Enum.KeyCode.Unknown then toggleKey = kc end
			end
			if type(d.textSize) == "number" then textSize = math.clamp(math.floor(d.textSize), 10, 22) end
		end
	end
end
local function saveSettings()
	if writefile then
		pcall(writefile, SETTINGS_FILE, HttpService:JSONEncode({ toggleKey = toggleKey.Name, textSize = textSize }))
	end
end

-- ---------- emoji ----------
local function toChar(v)
	if type(v) == "table" then return utf8.char(table.unpack(v)) end
	return utf8.char(v)
end

-- items = flat list: name, codepoint (or {codepoints}), name, codepoint, ...
local CATS = {
	{ icon = 0x1F600, name = "Faces", items = {
		"smile", 0x1F604, "grin", 0x1F601, "joy", 0x1F602, "rofl", 0x1F923, "smiley", 0x1F603,
		"laughing", 0x1F606, "sweat_smile", 0x1F605, "wink", 0x1F609, "blush", 0x1F60A, "innocent", 0x1F607,
		"slight_smile", 0x1F642, "upside_down", 0x1F643, "relieved", 0x1F60C, "heart_eyes", 0x1F60D,
		"star_struck", 0x1F929, "kissing_heart", 0x1F618, "yum", 0x1F60B, "stuck_out_tongue", 0x1F61B,
		"stuck_out_tongue_winking_eye", 0x1F61C, "zany", 0x1F92A, "money_mouth", 0x1F911, "hugging", 0x1F917,
		"thinking", 0x1F914, "shushing", 0x1F92B, "zipper_mouth", 0x1F910, "neutral_face", 0x1F610,
		"expressionless", 0x1F611, "unamused", 0x1F612, "rolling_eyes", 0x1F644, "smirk", 0x1F60F,
		"grimacing", 0x1F62C, "pensive", 0x1F614, "sleepy", 0x1F62A, "sleeping", 0x1F634, "mask", 0x1F637,
		"nauseated", 0x1F922, "vomiting", 0x1F92E, "hot_face", 0x1F975, "cold_face", 0x1F976,
		"dizzy_face", 0x1F635, "exploding_head", 0x1F92F, "cowboy", 0x1F920, "partying_face", 0x1F973,
		"sunglasses", 0x1F60E, "nerd", 0x1F913, "monocle", 0x1F9D0, "confused", 0x1F615, "worried", 0x1F61F,
		"open_mouth", 0x1F62E, "hushed", 0x1F62F, "astonished", 0x1F632, "flushed", 0x1F633,
		"pleading", 0x1F97A, "cry", 0x1F622, "sob", 0x1F62D, "scream", 0x1F631, "fearful", 0x1F628,
		"weary", 0x1F629, "tired_face", 0x1F62B, "triumph", 0x1F624, "angry", 0x1F620, "rage", 0x1F621,
		"disappointed", 0x1F61E, "sweat", 0x1F613, "yawning", 0x1F971, "melting_face", 0x1FAE0,
		"salute", 0x1FAE1, "face_holding_back_tears", 0x1F979, "skull", 0x1F480, "ghost", 0x1F47B,
		"alien", 0x1F47D, "robot", 0x1F916, "poop", 0x1F4A9, "clown", 0x1F921, "smiling_imp", 0x1F608,
		"imp", 0x1F47F, "angel", 0x1F47C, "see_no_evil", 0x1F648, "hear_no_evil", 0x1F649,
		"speak_no_evil", 0x1F64A,
	} },
	{ icon = 0x1F44D, name = "Hands", items = {
		"+1", 0x1F44D, "-1", 0x1F44E, "clap", 0x1F44F, "raised_hands", 0x1F64C, "pray", 0x1F64F,
		"wave", 0x1F44B, "ok_hand", 0x1F44C, "muscle", 0x1F4AA, "handshake", 0x1F91D,
		"v", { 0x270C, 0xFE0F }, "crossed_fingers", 0x1F91E, "fist", 0x270A, "punch", 0x1F44A,
		"point_up", { 0x261D, 0xFE0F }, "point_right", 0x1F449, "point_left", 0x1F448, "point_down", 0x1F447,
		"middle_finger", 0x1F595, "facepalm", 0x1F926, "shrug", 0x1F937, "eyes", 0x1F440, "brain", 0x1F9E0,
		"nail_care", 0x1F485, "lips", 0x1F444, "kiss", 0x1F48B,
	} },
	{ icon = 0x1F496, name = "Hearts", items = {
		"heart", { 0x2764, 0xFE0F }, "broken_heart", 0x1F494, "blue_heart", 0x1F499, "green_heart", 0x1F49A,
		"yellow_heart", 0x1F49B, "purple_heart", 0x1F49C, "black_heart", 0x1F5A4, "orange_heart", 0x1F9E1,
		"white_heart", 0x1F90D, "sparkling_heart", 0x1F496,
	} },
	{ icon = 0x1F525, name = "Fun", items = {
		"fire", 0x1F525, "100", 0x1F4AF, "sparkles", 0x2728, "star", 0x2B50, "boom", 0x1F4A5, "zap", 0x26A1,
		"tada", 0x1F389, "balloon", 0x1F388, "gift", 0x1F381, "cake", 0x1F382, "trophy", 0x1F3C6,
		"crown", 0x1F451, "gem", 0x1F48E, "rocket", 0x1F680, "bulb", 0x1F4A1, "bomb", 0x1F4A3,
		"anger", 0x1F4A2, "zzz", 0x1F4A4, "sweat_drops", 0x1F4A6, "dash", 0x1F4A8, "moyai", 0x1F5FF,
		"cap", 0x1F9E2, "sun", { 0x2600, 0xFE0F }, "moon", 0x1F319, "cloud", { 0x2601, 0xFE0F },
		"rainbow", 0x1F308, "snowflake", { 0x2744, 0xFE0F },
	} },
	{ icon = 0x1F355, name = "Animals & Food", items = {
		"dog", 0x1F436, "cat", 0x1F431, "frog", 0x1F438, "monkey", 0x1F435, "unicorn", 0x1F984,
		"snake", 0x1F40D, "bug", 0x1F41B, "pizza", 0x1F355, "hamburger", 0x1F354, "fries", 0x1F35F,
		"taco", 0x1F32E, "beer", 0x1F37A, "coffee", 0x2615, "popcorn", 0x1F37F, "cookie", 0x1F36A,
		"apple", 0x1F34E, "banana", 0x1F34C, "strawberry", 0x1F353, "watermelon", 0x1F349,
		"cherries", 0x1F352, "peach", 0x1F351, "eggplant", 0x1F346,
	} },
	{ icon = 0x1F3AE, name = "Objects", items = {
		"video_game", 0x1F3AE, "game_die", 0x1F3B2, "computer", 0x1F4BB, "iphone", 0x1F4F1,
		"headphones", 0x1F3A7, "microphone", 0x1F3A4, "musical_note", 0x1F3B5, "key", 0x1F511,
		"lock", 0x1F512, "bell", 0x1F514, "mute", 0x1F507, "speaker", 0x1F50A,
		"crossed_swords", { 0x2694, 0xFE0F }, "shield", { 0x1F6E1, 0xFE0F }, "moneybag", 0x1F4B0,
		"dollar", 0x1F4B5, "chart_up", 0x1F4C8, "white_check_mark", 0x2705, "check", { 0x2714, 0xFE0F },
		"x", 0x274C, "warning", { 0x26A0, 0xFE0F }, "question", 0x2753, "exclamation", 0x2757,
		"no_entry", 0x26D4, "arrow_right", { 0x27A1, 0xFE0F }, "sos", 0x1F198, "cool", 0x1F192,
		"new", 0x1F195, "ok", 0x1F197, "skull_crossbones", { 0x2620, 0xFE0F },
	} },
}

local EMOJI, ALL = {}, {}
for _, cat in ipairs(CATS) do
	cat.list = {}
	for i = 1, #cat.items, 2 do
		local name, ch = cat.items[i], toChar(cat.items[i + 1])
		EMOJI[name] = ch
		local e = { name = name, char = ch }
		cat.list[#cat.list + 1] = e
		ALL[#ALL + 1] = e
	end
end
EMOJI.thumbsup = EMOJI["+1"]
EMOJI.thumbsdown = EMOJI["-1"]

local QUICK_REACTIONS = {
	toChar(0x1F44D), toChar({ 0x2764, 0xFE0F }), toChar(0x1F602),
	toChar(0x1F62D), toChar(0x1F525), toChar(0x1F480),
}

-- :sob: -> emoji
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

-- ---------- download cache (GIF previews / clips) ----------
local assetCache = {}
local function hashStr(s)
	local h = 5381
	for i = 1, #s do h = (h * 33 + s:byte(i)) % 4294967296 end
	return string.format("%08x%x", h, #s)
end
local function extOf(url, default)
	local p = url:match("^[^?#]+")
	return ((p and p:match("%.(%w+)$")) or default):lower()
end
-- returns a rbxasset:// content string, or nil if this executor can't do it
local function getAsset(url, defaultExt)
	if assetCache[url] ~= nil then return assetCache[url] or nil end
	if not (req and writefile and getcustomasset) then
		assetCache[url] = false
		return nil
	end
	local path = CACHE_DIR .. "/" .. hashStr(url) .. "." .. extOf(url, defaultExt)
	local ok, id = pcall(function()
		if makefolder and isfolder and not isfolder(CACHE_DIR) then makefolder(CACHE_DIR) end
		if not (isfile and isfile(path)) then
			local res = req({ Url = url, Method = "GET" })
			if type(res) ~= "table" or res.StatusCode ~= 200 or type(res.Body) ~= "string"
				or #res.Body == 0 or #res.Body > MAX_ASSET_BYTES then
				error("download failed")
			end
			writefile(path, res.Body)
		end
		return getcustomasset(path)
	end)
	assetCache[url] = (ok and id) or false
	return (ok and id) or nil
end

-- ---------- theme ----------
local C = {
	bg = Color3.fromRGB(24, 24, 24),
	bar = Color3.fromRGB(24, 24, 24),
	panel = Color3.fromRGB(36, 36, 36),
	input = Color3.fromRGB(36, 36, 36),
	accent = Color3.fromRGB(44, 103, 197),
	accentHover = Color3.fromRGB(53, 111, 204),
	accentSoft = Color3.fromRGB(35, 45, 62),
	btn = Color3.fromRGB(36, 36, 36),
	btnHover = Color3.fromRGB(46, 46, 46),
	divider = Color3.fromRGB(56, 56, 56),
	danger = Color3.fromRGB(215, 89, 89),
	text = Color3.fromRGB(255, 255, 255),
	mine = Color3.fromRGB(139, 181, 239),
	sys = Color3.fromRGB(192, 188, 174),
	dim = Color3.fromRGB(155, 155, 155),
	good = Color3.fromRGB(218, 218, 218),
	warn = Color3.fromRGB(180, 180, 180),
	bad = Color3.fromRGB(220, 130, 130),
	ok = Color3.fromRGB(88, 201, 124),
	caution = Color3.fromRGB(235, 190, 80),
	off = Color3.fromRGB(226, 96, 96),
}
local UiFont = Font.fromId(12187365364, Enum.FontWeight.SemiBold)
local BodyFont = Font.fromId(12187365364, Enum.FontWeight.Regular)

local function new(class, props, parent)
	local object = Instance.new(class)
	for key, value in pairs(props) do object[key] = value end
	object.Parent = parent
	return object
end

local function round(object, radius)
	return new("UICorner", { CornerRadius = UDim.new(0, radius) }, object)
end

local function tween(object, duration, props, style, direction)
	local motion = TweenService:Create(object,
		TweenInfo.new(duration, style or Enum.EasingStyle.Quart, direction or Enum.EasingDirection.Out), props)
	motion:Play()
	return motion
end

local function esc(value)
	return (tostring(value):gsub("&", "&amp;"):gsub("<", "&lt;")
		:gsub(">", "&gt;"):gsub('"', "&quot;"):gsub("'", "&apos;"))
end
local function nameColor(id)
	return Color3.fromHSV(((tonumber(id) or 0) * 47 % 360) / 360, 0.34, 0.94)
end

-- Lucide icon atlas (same icons as the original UI)
local Lucide48 = table.freeze({
	["arrow-left"] = { Image = "rbxassetid://16898612629", Offset = Vector2.new(98, 918) },
	["arrow-right"] = { Image = "rbxassetid://16898612629", Offset = Vector2.new(453, 820) },
	["search"] = { Image = "rbxassetid://16898613699", Offset = Vector2.new(918, 857) },
	["x"] = { Image = "rbxassetid://16898613869", Offset = Vector2.new(869, 906) },
	["copy"] = { Image = "rbxassetid://16898613044", Offset = Vector2.new(918, 612) },
	["check"] = { Image = "rbxassetid://16898612819", Offset = Vector2.new(710, 869) },
	["minus"] = { Image = "rbxassetid://16898613613", Offset = Vector2.new(771, 196) },
	["square"] = { Image = "rbxassetid://16898613777", Offset = Vector2.new(869, 710) },
	["chevron-down"] = { Image = "rbxassetid://16898612819", Offset = Vector2.new(196, 918) },
	["code"] = { Image = "rbxassetid://16898613044", Offset = Vector2.new(355, 869) },
	["link"] = { Image = "rbxassetid://16898613509", Offset = Vector2.new(918, 453) },
	["reply"] = { Image = "rbxassetid://16898613699", Offset = Vector2.new(612, 918) },
	["maximize"] = { Image = "rbxassetid://16898613613", Offset = Vector2.new(771, 563) },
	["minimize"] = { Image = "rbxassetid://16898613613", Offset = Vector2.new(918, 49) },
})
local function lucideIcon(parent, name, size, color, zIndex)
	local data = Lucide48[name]
	assert(data, "Unknown Lucide icon: " .. tostring(name))
	return new("ImageLabel", {
		Name = "Icon", AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(size, size), BackgroundTransparency = 1,
		BorderSizePixel = 0, Image = data.Image,
		ImageRectOffset = data.Offset, ImageRectSize = Vector2.new(48, 48),
		ImageColor3 = color or C.text, ScaleType = Enum.ScaleType.Fit,
		ZIndex = zIndex or parent.ZIndex + 1,
	}, parent)
end

-- sliders-style settings icon, drawn from frames
local function settingsIcon(parent, color, z)
	local holder = new("Frame", {
		Name = "Icon", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(16, 14), BackgroundTransparency = 1, ZIndex = z,
	}, parent)
	local ys, xs = { 2, 7, 12 }, { 11, 4, 8 }
	for i = 1, 3 do
		new("Frame", {
			Position = UDim2.fromOffset(0, ys[i]), Size = UDim2.fromOffset(16, 1.5),
			BackgroundColor3 = color, BorderSizePixel = 0, ZIndex = z,
		}, holder)
		local knob = new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(xs[i], ys[i] + 0.75),
			Size = UDim2.fromOffset(5, 5), BackgroundColor3 = color, BorderSizePixel = 0, ZIndex = z + 1,
		}, holder)
		round(knob, 3)
	end
	return holder
end

local function hover(button, amount)
	tween(button, 0.17, { BackgroundTransparency = amount })
end

-- fade a whole subtree in (used for new messages)
local function fadeIn(root, duration)
	local targets = {}
	local function grab(obj)
		if obj:IsA("GuiObject") then
			local rec = { obj = obj, bg = obj.BackgroundTransparency }
			obj.BackgroundTransparency = 1
			if obj:IsA("TextLabel") or obj:IsA("TextButton") or obj:IsA("TextBox") then
				rec.tx = obj.TextTransparency
				obj.TextTransparency = 1
			elseif obj:IsA("ImageLabel") or obj:IsA("ImageButton") then
				rec.img = obj.ImageTransparency
				obj.ImageTransparency = 1
			end
			targets[#targets + 1] = rec
		elseif obj:IsA("UIStroke") then
			targets[#targets + 1] = { obj = obj, st = obj.Transparency }
			obj.Transparency = 1
		end
	end
	grab(root)
	for _, d in ipairs(root:GetDescendants()) do grab(d) end
	for _, r in ipairs(targets) do
		local goal = {}
		if r.bg then goal.BackgroundTransparency = r.bg end
		if r.tx then goal.TextTransparency = r.tx end
		if r.img then goal.ImageTransparency = r.img end
		if r.st then goal.Transparency = r.st end
		tween(r.obj, duration or 0.25, goal)
	end
end

-- scale-in for popups / menus (uses the frame's own UIScale)
local function popIn(frame)
	local s = frame:FindFirstChildOfClass("UIScale")
	frame.Visible = true
	if s then
		s.Scale = 0.9
		tween(s, 0.22, { Scale = 1 }, Enum.EasingStyle.Back)
	end
end

local sizedLabels = {} -- label -> TextSize offset, so the Settings text-size slider can resize everything

-- ---------- window ----------
local parentGui = (gethui and gethui()) or game:GetService("CoreGui")
local gui = new("ScreenGui", {
	Name = HttpService:GenerateGUID(false), ResetOnSpawn = false,
	IgnoreGuiInset = true, DisplayOrder = 999,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
}, parentGui)
if syn and syn.protect_gui then pcall(syn.protect_gui, gui) end

local camera = workspace.CurrentCamera
local viewport = camera and camera.ViewportSize or Vector2.new(1280, 720)
local initialWidth = math.min(WIN_W, math.max(340, viewport.X - 28))
local initialHeight = math.min(WIN_H, math.max(260, viewport.Y - 28))
local win = new("Frame", {
	Name = "ChatWindow", Active = true,
	Size = UDim2.fromOffset(initialWidth, initialHeight),
	Position = UDim2.fromOffset(
		math.max(0, math.floor((viewport.X - initialWidth) / 2)),
		math.max(0, math.floor((viewport.Y - initialHeight) / 2))),
	BackgroundColor3 = C.bg, BorderSizePixel = 0,
	ClipsDescendants = true,
}, gui)
round(win, 8)

local titleBar = new("Frame", {
	Name = "Header", Size = UDim2.new(1, 0, 0, TITLE_H),
	BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 3,
}, win)
local titleDrag = new("Frame", {
	Name = "DragRegion", Position = UDim2.fromOffset(0, 0),
	Size = UDim2.new(1, -150, 1, 0),
	BackgroundTransparency = 1, Active = true, ZIndex = 3,
}, titleBar)
new("Frame", {
	Name = "Divider", Position = UDim2.new(0, 0, 1, -1),
	Size = UDim2.new(1, 0, 0, 1), BackgroundColor3 = C.divider,
	BackgroundTransparency = 0.35, BorderSizePixel = 0, ZIndex = 4,
}, titleBar)

-- "Online Chat" + status circle on its right
local titleGroup = new("Frame", {
	Name = "TitleGroup", Position = UDim2.fromOffset(15, 0),
	Size = UDim2.new(0, 0, 1, 0), AutomaticSize = Enum.AutomaticSize.X,
	BackgroundTransparency = 1, ZIndex = 4,
}, titleBar)
new("UIListLayout", {
	FillDirection = Enum.FillDirection.Horizontal,
	VerticalAlignment = Enum.VerticalAlignment.Center,
	SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 8),
}, titleGroup)
new("TextLabel", {
	Name = "Title", LayoutOrder = 1,
	Size = UDim2.fromOffset(0, TITLE_H), AutomaticSize = Enum.AutomaticSize.X,
	BackgroundTransparency = 1, Text = "Online Chat",
	FontFace = UiFont, TextSize = 14, TextColor3 = C.text, ZIndex = 4,
}, titleGroup)
local statusDot = new("Frame", {
	Name = "Status", LayoutOrder = 2,
	Size = UDim2.fromOffset(9, 9), BackgroundColor3 = C.dim,
	BorderSizePixel = 0, ZIndex = 4,
}, titleGroup)
round(statusDot, 5)

local controls = new("Frame", {
	Name = "Controls", AnchorPoint = Vector2.new(1, 0.5),
	Position = UDim2.new(1, -9, 0.5, 0),
	Size = UDim2.fromOffset(125, 30),
	BackgroundTransparency = 1, ZIndex = 5,
}, titleBar)
new("UIListLayout", {
	FillDirection = Enum.FillDirection.Horizontal,
	HorizontalAlignment = Enum.HorizontalAlignment.Right,
	VerticalAlignment = Enum.VerticalAlignment.Center,
	SortOrder = Enum.SortOrder.LayoutOrder,
	Padding = UDim.new(0, 3),
}, controls)
local function windowControl(name, order, glyph)
	local button = new("TextButton", {
		Name = name, LayoutOrder = order,
		Size = UDim2.fromOffset(29, 28),
		BackgroundColor3 = C.panel, BackgroundTransparency = 1,
		BorderSizePixel = 0, AutoButtonColor = false, Text = "",
		ZIndex = 6,
	}, controls)
	round(button, 14)
	local image
	if glyph then
		image = lucideIcon(button, glyph, 18, C.text, 7)
	else
		image = settingsIcon(button, C.text, 7)
	end
	bind(button.MouseEnter, function() hover(button, 0) end)
	bind(button.MouseLeave, function() hover(button, 1) end)
	bind(button.MouseButton1Down, function() hover(button, 0.24) end)
	bind(button.MouseButton1Up, function() hover(button, 0) end)
	return button, image
end
local settingsBtn = windowControl("Settings", 1, nil)
local minBtn, minIcon = windowControl("Minimize", 2, "minus")
local maximizeBtn, maximizeIcon = windowControl("Maximize", 3, "maximize")
local closeBtn = windowControl("Close", 4, "x")

local body = new("Frame", {
	Name = "Content", Position = UDim2.fromOffset(0, TITLE_H),
	Size = UDim2.new(1, 0, 1, -TITLE_H),
	BackgroundTransparency = 1, BorderSizePixel = 0,
	ClipsDescendants = true,
}, win)

-- ---------- sidebar ----------
local side = new("Frame", {
	Name = "Channels", Position = UDim2.fromOffset(0, 0),
	Size = UDim2.new(0, SIDE_W, 1, 0),
	BackgroundColor3 = C.bg, BorderSizePixel = 0,
	ZIndex = 6,
}, body)
new("Frame", {
	Name = "Divider", Position = UDim2.new(1, -1, 0, 0),
	Size = UDim2.new(0, 1, 1, 0),
	BackgroundColor3 = C.divider, BackgroundTransparency = 0.45,
	BorderSizePixel = 0, ZIndex = 7,
}, side)
new("TextLabel", {
	Name = "Heading", Position = UDim2.fromOffset(14, 16),
	Size = UDim2.new(1, -28, 0, 18),
	BackgroundTransparency = 1, Text = "Channels",
	FontFace = UiFont, TextSize = 13, TextColor3 = C.text,
	TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 7,
}, side)
local current = "main"
local drafts, unread, chBtns, chanName, lists = {}, {}, {}, {}, {}
local mentionsUnread = {}
for index, channel in ipairs(CHANNELS) do
	chanName[channel.id] = channel.name
	unread[channel.id] = 0
	local button = new("TextButton", {
		Name = channel.id, Position = UDim2.fromOffset(9, 49 + (index - 1) * 38),
		Size = UDim2.new(1, -18, 0, 34),
		BackgroundColor3 = C.panel, BackgroundTransparency = 1,
		BorderSizePixel = 0, AutoButtonColor = false, Text = "", ZIndex = 7,
	}, side)
	round(button, 8)
	local hash = new("TextLabel", {
		Name = "Hash", Position = UDim2.fromOffset(11, 0),
		Size = UDim2.fromOffset(17, 34), BackgroundTransparency = 1,
		Text = "#", FontFace = UiFont, TextSize = 16,
		TextColor3 = C.dim, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 8,
	}, button)
	local name = new("TextLabel", {
		Name = "ChannelName", Position = UDim2.fromOffset(35, 0),
		Size = UDim2.new(1, -67, 1, 0), BackgroundTransparency = 1,
		Text = channel.name, FontFace = UiFont, TextSize = 12,
		TextColor3 = C.dim, TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 8,
	}, button)
	local badge = new("TextLabel", {
		Name = "Unread", AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -7, 0.5, 0),
		Size = UDim2.fromOffset(22, 17),
		BackgroundColor3 = C.accent, BorderSizePixel = 0,
		Text = "0", Visible = false,
		FontFace = UiFont, TextSize = 10,
		TextColor3 = C.text, ZIndex = 8,
	}, button)
	round(badge, 8)
	chBtns[channel.id] = { btn = button, badge = badge, nameLabel = name, hashLabel = hash }
end

local identity = new("Frame", {
	Name = "Identity", Position = UDim2.new(0, 9, 1, -56),
	Size = UDim2.new(1, -18, 0, 45),
	BackgroundColor3 = C.panel, BorderSizePixel = 0, ZIndex = 7,
}, side)
round(identity, 8)
local avatar = new("ImageLabel", {
	Name = "Avatar", Position = UDim2.fromOffset(8, 7),
	Size = UDim2.fromOffset(30, 30),
	BackgroundColor3 = C.btn, BorderSizePixel = 0,
	ScaleType = Enum.ScaleType.Crop,
	Image = "rbxthumb://type=AvatarHeadShot&id=" .. tostring(lp.UserId) .. "&w=150&h=150",
	ZIndex = 8,
}, identity)
round(avatar, 7)
new("TextLabel", {
	Name = "Username", Position = UDim2.fromOffset(46, 0),
	Size = UDim2.new(1, -54, 1, 0),
	BackgroundTransparency = 1, Text = lp.Name,
	FontFace = UiFont, TextSize = 12, TextColor3 = C.text,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 8,
}, identity)

-- ---------- conversation header ----------
local roomHead = new("Frame", {
	Name = "ConversationHeader", Position = UDim2.fromOffset(SIDE_W, 0),
	Size = UDim2.new(1, -SIDE_W, 0, 53),
	BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 2,
}, body)
local sidebarButton = new("TextButton", {
	Name = "ExpandChannels", Position = UDim2.fromOffset(13, 12),
	Size = UDim2.fromOffset(29, 28),
	BackgroundColor3 = C.panel, BackgroundTransparency = 1,
	BorderSizePixel = 0, AutoButtonColor = false, Text = "", ZIndex = 3,
}, roomHead)
round(sidebarButton, 14)
local sidebarIcon = lucideIcon(sidebarButton, "arrow-left", 16, C.text, 4)
bind(sidebarButton.MouseEnter, function() hover(sidebarButton, 0) end)
bind(sidebarButton.MouseLeave, function() hover(sidebarButton, 1) end)

local roomName = new("TextLabel", {
	Name = "ChannelTitle", Position = UDim2.fromOffset(51, 0),
	Size = UDim2.new(1, -215, 1, 0),
	BackgroundTransparency = 1, Text = "Main Chat",
	FontFace = UiFont, TextSize = 15, TextColor3 = C.text,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 3,
}, roomHead)

local presencePill = new("Frame", {
	Name = "Presence", AnchorPoint = Vector2.new(1, 0.5),
	Position = UDim2.new(1, -51, 0.5, 0),
	Size = UDim2.fromOffset(82, 25),
	BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 3,
}, roomHead)
local countLbl = new("TextLabel", {
	Name = "Count", Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1, Text = "-- online",
	FontFace = BodyFont, TextSize = 11, TextColor3 = C.dim,
	TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 4,
}, presencePill)
local findButton = new("TextButton", {
	Name = "FindMessages", AnchorPoint = Vector2.new(1, 0.5),
	Position = UDim2.new(1, -11, 0.5, 0),
	Size = UDim2.fromOffset(29, 28),
	BackgroundColor3 = C.panel, BackgroundTransparency = 1,
	BorderSizePixel = 0, AutoButtonColor = false, Text = "", ZIndex = 3,
}, roomHead)
round(findButton, 14)
lucideIcon(findButton, "search", 15, C.text, 4)
bind(findButton.MouseEnter, function() hover(findButton, 0) end)
bind(findButton.MouseLeave, function() hover(findButton, 1) end)
new("Frame", {
	Name = "Divider", Position = UDim2.new(0, 0, 1, -1),
	Size = UDim2.new(1, 0, 0, 1),
	BackgroundColor3 = C.divider, BackgroundTransparency = 0.5,
	BorderSizePixel = 0, ZIndex = 2,
}, roomHead)

local findPanel = new("Frame", {
	Name = "FindPanel", Position = UDim2.fromOffset(49, 7),
	Size = UDim2.new(1, -61, 0, 37),
	BackgroundColor3 = C.panel, BorderSizePixel = 0,
	ZIndex = 9, Visible = false,
}, roomHead)
round(findPanel, 8)
local findInput = new("TextBox", {
	Name = "FindInput", Position = UDim2.fromOffset(11, 0),
	Size = UDim2.new(1, -107, 1, 0),
	BackgroundTransparency = 1, ClearTextOnFocus = false,
	Text = "", PlaceholderText = "Search messages",
	PlaceholderColor3 = C.dim, FontFace = BodyFont,
	TextSize = 12, TextColor3 = C.text,
	TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 10,
}, findPanel)
local findResult = new("TextLabel", {
	Name = "ResultCount", AnchorPoint = Vector2.new(1, 0.5),
	Position = UDim2.new(1, -35, 0.5, 0),
	Size = UDim2.fromOffset(52, 20),
	BackgroundTransparency = 1, Text = "",
	FontFace = BodyFont, TextSize = 10,
	TextColor3 = C.dim,
	TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 10,
}, findPanel)
local exitFind = new("TextButton", {
	Name = "CloseFind", AnchorPoint = Vector2.new(1, 0.5),
	Position = UDim2.new(1, -5, 0.5, 0),
	Size = UDim2.fromOffset(27, 27),
	BackgroundColor3 = C.panel, BackgroundTransparency = 1,
	BorderSizePixel = 0, AutoButtonColor = false,
	Text = "", ZIndex = 10,
}, findPanel)
round(exitFind, 13)
lucideIcon(exitFind, "x", 14, C.text, 11)
local searchOpen = false
local updateSearch, updateJump

for _, channel in ipairs(CHANNELS) do
	local list = new("ScrollingFrame", {
		Name = "Messages_" .. channel.id,
		Position = UDim2.fromOffset(SIDE_W + 1, 53),
		Size = UDim2.new(1, -SIDE_W - 1, 1, -116),
		BackgroundTransparency = 1, BorderSizePixel = 0,
		CanvasSize = UDim2.fromOffset(0, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ScrollBarThickness = 3, ScrollBarImageColor3 = C.divider,
		VerticalScrollBarInset = Enum.ScrollBarInset.ScrollBar,
		Visible = channel.id == current, ZIndex = 2,
	}, body)
	new("UIListLayout", {
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 5),
	}, list)
	new("UIPadding", {
		PaddingLeft = UDim.new(0, 14), PaddingRight = UDim.new(0, 12),
		PaddingTop = UDim.new(0, 12), PaddingBottom = UDim.new(0, 12),
	}, list)
	lists[channel.id] = list
end

-- ---------- composer ----------
local row = new("Frame", {
	Name = "Composer", Position = UDim2.new(0, SIDE_W, 1, -62),
	Size = UDim2.new(1, -SIDE_W, 0, 61),
	BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 3,
}, body)
new("Frame", {
	Name = "Divider", Size = UDim2.new(1, 0, 0, 1),
	BackgroundColor3 = C.divider, BackgroundTransparency = 0.5,
	BorderSizePixel = 0, ZIndex = 3,
}, row)
local boxBg = new("Frame", {
	Name = "InputSurface", Position = UDim2.fromOffset(14, 10),
	Size = UDim2.new(1, -73, 0, 40),
	BackgroundColor3 = C.panel, BorderSizePixel = 0, ZIndex = 4,
}, row)
round(boxBg, 8)
local boxStroke = new("UIStroke", {
	Color = C.accent, Thickness = 1, Transparency = 1,
	ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
}, boxBg)
local box = new("TextBox", {
	Name = "Message", Position = UDim2.fromOffset(12, 0),
	Size = UDim2.new(1, -96, 1, 0),
	BackgroundTransparency = 1,
	Text = "", PlaceholderText = "Message #main",
	PlaceholderColor3 = C.dim, ClearTextOnFocus = false,
	FontFace = BodyFont, TextSize = textSize, TextColor3 = C.text,
	TextWrapped = true, MultiLine = true,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextYAlignment = Enum.TextYAlignment.Center, ZIndex = 5,
}, boxBg)
new("UIPadding", { PaddingTop = UDim.new(0, 11), PaddingBottom = UDim.new(0, 11) }, box)
sizedLabels[box] = 0

local counter = new("TextLabel", {
	Name = "CharacterCount", AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -8, 0, 3),
	Size = UDim2.fromOffset(70, 12),
	BackgroundTransparency = 1, Text = "",
	FontFace = BodyFont, TextSize = 10,
	TextColor3 = C.dim, TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 5,
}, boxBg)

local emojiBtn = new("TextButton", {
	Name = "EmojiButton", AnchorPoint = Vector2.new(1, 1),
	Position = UDim2.new(1, -8, 1, -6),
	Size = UDim2.fromOffset(28, 28),
	BackgroundColor3 = C.btnHover, BackgroundTransparency = 1,
	BorderSizePixel = 0, AutoButtonColor = false,
	Text = utf8.char(0x1F600), FontFace = UiFont, TextSize = 16,
	TextColor3 = C.text, ZIndex = 6,
}, boxBg)
round(emojiBtn, 8)
local gifBtn = new("TextButton", {
	Name = "GifButton", AnchorPoint = Vector2.new(1, 1),
	Position = UDim2.new(1, -40, 1, -6),
	Size = UDim2.fromOffset(34, 28),
	BackgroundColor3 = C.btnHover, BackgroundTransparency = 1,
	BorderSizePixel = 0, AutoButtonColor = false,
	Text = "GIF", FontFace = UiFont, TextSize = 11,
	TextColor3 = C.text, ZIndex = 6,
}, boxBg)
round(gifBtn, 8)
for _, b in ipairs({ emojiBtn, gifBtn }) do
	bind(b.MouseEnter, function() hover(b, 0) end)
	bind(b.MouseLeave, function() hover(b, 1) end)
end

local sendBtn = new("TextButton", {
	Name = "Send", AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -12, 0, 10),
	Size = UDim2.fromOffset(40, 40),
	BackgroundColor3 = C.accent, BackgroundTransparency = 0.5,
	BorderSizePixel = 0, AutoButtonColor = false, Text = "", ZIndex = 4,
}, row)
round(sendBtn, 8)
local sendIcon = lucideIcon(sendBtn, "arrow-right", 18, C.text, 5)

local pendingReplies = {}
local composerHeight = 61
local refreshInput
local replyBanner = new("Frame", {
	Name = "ReplyPreview", Position = UDim2.fromOffset(14, -33),
	Size = UDim2.new(1, -26, 0, 30),
	BackgroundColor3 = C.panel, BorderSizePixel = 0, Visible = false, ZIndex = 10,
}, row)
round(replyBanner, 8)
local replyLabel = new("TextLabel", {
	Name = "ReplyText", Position = UDim2.fromOffset(10, 0),
	Size = UDim2.new(1, -44, 1, 0),
	BackgroundTransparency = 1, Text = "", TextTruncate = Enum.TextTruncate.AtEnd,
	FontFace = BodyFont, TextColor3 = C.text, TextSize = 11,
	TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 11,
}, replyBanner)
local replyCancel = new("TextButton", {
	Name = "CancelReply", AnchorPoint = Vector2.new(1, 0.5),
	Position = UDim2.new(1, -4, 0.5, 0),
	Size = UDim2.fromOffset(25, 25), BackgroundTransparency = 1,
	BorderSizePixel = 0, AutoButtonColor = false, Text = "", ZIndex = 11,
}, replyBanner)
lucideIcon(replyCancel, "x", 14, C.dim, 12)
local function refreshReply()
	local selected = pendingReplies[current]
	local wasVisible = replyBanner.Visible
	replyBanner.Visible = selected ~= nil
	replyLabel.Text = selected and ("Replying to " .. selected.user .. "  ·  " .. selected.text) or ""
	if selected and not wasVisible then
		replyBanner.Position = UDim2.fromOffset(14, -22)
		tween(replyBanner, 0.22, { Position = UDim2.fromOffset(14, -33) })
	end
	if refreshInput then refreshInput() end
end
bind(replyCancel.Activated, function()
	pendingReplies[current] = nil
	refreshReply()
end)

-- ---------- message text helpers ----------
local function looksLikeCode(value)
	if not value:find("\n", 1, true) then return false end
	local v = value:match("^%s*(.-)%s*$")
	return v:match("^local%s") ~= nil
		or v:match("^function%s") ~= nil
		or v:match("^print%(") ~= nil
		or v:match("^if%s") ~= nil
		or v:match("^for%s") ~= nil
		or v:match("^while%s") ~= nil
		or v:match("^return%s") ~= nil
end

-- splits "text ```lua\ncode\n``` text" into { {kind="text"}, {kind="code", lang=...}, ... }
local function splitSegments(text)
	local segs, pos = {}, 1
	local function addText(s)
		s = s:gsub("^\n+", ""):gsub("\n+$", "")
		if s ~= "" then segs[#segs + 1] = { kind = "text", text = s } end
	end
	while true do
		local a, b, lang, code = text:find(FENCE .. "([%w%-_%+#]*)\n(.-)\n?" .. FENCE, pos)
		if not a then break end
		if a > pos then addText(text:sub(pos, a - 1)) end
		segs[#segs + 1] = { kind = "code", lang = lang ~= "" and lang or "luau", text = code }
		pos = b + 1
	end
	if pos <= #text then addText(text:sub(pos)) end
	return segs
end

-- text we send: code stays untouched, everything else gets :emoji: conversion
local function prepareOutgoing(raw)
	local trimmed = tostring(raw):gsub("\r\n", "\n"):gsub("\r", "\n"):match("^%s*(.-)%s*$")
	if not trimmed:find(FENCE, 1, true) and looksLikeCode(trimmed) then
		trimmed = FENCE .. "luau\n" .. trimmed .. "\n" .. FENCE
	end
	if not trimmed:find(FENCE, 1, true) then return emojify(trimmed) end
	local out, pos = {}, 1
	while true do
		local a, b = trimmed:find(FENCE .. "[%w%-_%+#]*\n.-\n?" .. FENCE, pos)
		if not a then break end
		out[#out + 1] = emojify(trimmed:sub(pos, a - 1))
		out[#out + 1] = trimmed:sub(a, b)
		pos = b + 1
	end
	out[#out + 1] = emojify(trimmed:sub(pos))
	return table.concat(out)
end

-- Roblox text labels cap out around 16k characters including rich-text tags
local function safeRich(rich, plain)
	if #rich <= 15000 then return rich end
	local flat = esc(clip(plain, 6000))
	if #flat > 15000 then flat = flat:sub(1, 15000) end
	return flat
end

-- ---------- popups: emoji / gif / settings ----------
local sendGif, sendReact, startReply
local capturing = false
local keyBtn
local applyTextSize

local function newPopup(name, w, h)
	local f = new("Frame", {
		Name = name, AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -14, 1, -70),
		Size = UDim2.fromOffset(w, h),
		BackgroundColor3 = C.panel, BorderSizePixel = 0,
		Visible = false, ZIndex = 30, Active = true,
	}, win)
	round(f, 10)
	new("UIStroke", { Color = C.divider, Thickness = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, f)
	new("UIScale", { Scale = 1 }, f)
	return f
end

local function popupSearch(parent, y, placeholder)
	local bg = new("Frame", {
		Position = UDim2.fromOffset(10, y), Size = UDim2.new(1, -20, 0, 30),
		BackgroundColor3 = C.bg, BorderSizePixel = 0, ZIndex = 31,
	}, parent)
	round(bg, 8)
	return new("TextBox", {
		Position = UDim2.fromOffset(10, 0), Size = UDim2.new(1, -20, 1, 0),
		BackgroundTransparency = 1, Text = "", PlaceholderText = placeholder,
		PlaceholderColor3 = C.dim, ClearTextOnFocus = false,
		FontFace = BodyFont, TextSize = 12, TextColor3 = C.text,
		TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 32,
	}, bg)
end

local function insertIntoBox(s)
	local cur = box.Text
	if (utf8.len(cur) or #cur) >= MAX_LEN then return end
	box:CaptureFocus()
	box.Text = cur .. s
	box.CursorPosition = #box.Text + 1
end

-- ----- emoji picker (also used to pick a reaction) -----
local emojiPop = newPopup("EmojiPicker", 292, 282)
local emojiAction = insertIntoBox
local emojiCat = 1
local emojiTabs = {}
for i, cat in ipairs(CATS) do
	local t = new("TextButton", {
		Position = UDim2.fromOffset(10 + (i - 1) * 40, 8), Size = UDim2.fromOffset(36, 28),
		BackgroundColor3 = C.accent, BackgroundTransparency = 1,
		BorderSizePixel = 0, AutoButtonColor = false,
		Text = utf8.char(cat.icon), FontFace = UiFont, TextSize = 16,
		TextColor3 = C.text, ZIndex = 32,
	}, emojiPop)
	round(t, 8)
	emojiTabs[i] = t
end
local emojiSearch = popupSearch(emojiPop, 42, "Search emoji")
local emojiGrid = new("ScrollingFrame", {
	Position = UDim2.fromOffset(10, 80), Size = UDim2.new(1, -20, 1, -108),
	BackgroundTransparency = 1, BorderSizePixel = 0,
	ScrollBarThickness = 3, ScrollBarImageColor3 = C.divider,
	CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, ZIndex = 31,
}, emojiPop)
new("UIGridLayout", {
	CellSize = UDim2.fromOffset(36, 36), CellPadding = UDim2.fromOffset(2, 2),
	SortOrder = Enum.SortOrder.LayoutOrder,
}, emojiGrid)
local emojiHint = new("TextLabel", {
	Position = UDim2.new(0, 12, 1, -24), Size = UDim2.new(1, -24, 0, 18),
	BackgroundTransparency = 1, Text = "",
	FontFace = BodyFont, TextSize = 11, TextColor3 = C.dim,
	TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 32,
}, emojiPop)

local function buildEmojiGrid()
	for _, c in ipairs(emojiGrid:GetChildren()) do
		if c:IsA("TextButton") then c:Destroy() end
	end
	local q = (emojiSearch.Text:lower():gsub("[%s:]", ""))
	local src = {}
	if q == "" then
		src = CATS[emojiCat].list
	else
		for _, e in ipairs(ALL) do
			if e.name:find(q, 1, true) then
				src[#src + 1] = e
				if #src >= 150 then break end
			end
		end
	end
	for i, e in ipairs(src) do
		local b = new("TextButton", {
			BackgroundColor3 = C.btnHover, BackgroundTransparency = 1,
			BorderSizePixel = 0, Text = e.char, FontFace = UiFont, TextSize = 21,
			TextColor3 = C.text, AutoButtonColor = false, LayoutOrder = i, ZIndex = 32,
		}, emojiGrid)
		round(b, 8)
		b.MouseEnter:Connect(function()
			tween(b, 0.1, { BackgroundTransparency = 0.3 })
			emojiHint.Text = ":" .. e.name .. ":"
		end)
		b.MouseLeave:Connect(function() tween(b, 0.1, { BackgroundTransparency = 1 }) end)
		b.Activated:Connect(function() if emojiAction then emojiAction(e.char) end end)
	end
	emojiGrid.CanvasPosition = Vector2.new(0, 0)
	if #src == 0 then emojiHint.Text = "No emoji found" end
end

local function selectEmojiCat(i)
	emojiCat = i
	emojiSearch.Text = ""
	for idx, t in ipairs(emojiTabs) do
		tween(t, 0.15, { BackgroundTransparency = idx == i and 0.45 or 1 })
	end
	emojiHint.Text = CATS[i].name
	buildEmojiGrid()
end
for i, t in ipairs(emojiTabs) do bind(t.Activated, function() selectEmojiCat(i) end) end
bind(emojiSearch:GetPropertyChangedSignal("Text"), buildEmojiGrid)
selectEmojiCat(1)

-- ----- GIF picker (Klipy, the GIF search Discord uses now) -----
local gifPop = newPopup("GifPicker", 292, 306)
local gifSearch = popupSearch(gifPop, 10, "Search GIFs (press Enter)")
local gifList = new("ScrollingFrame", {
	Position = UDim2.fromOffset(10, 48), Size = UDim2.new(1, -20, 1, -76),
	BackgroundTransparency = 1, BorderSizePixel = 0,
	ScrollBarThickness = 3, ScrollBarImageColor3 = C.divider,
	CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, ZIndex = 31,
}, gifPop)
new("UIGridLayout", {
	CellSize = UDim2.fromOffset(86, 64), CellPadding = UDim2.fromOffset(4, 4),
	SortOrder = Enum.SortOrder.LayoutOrder,
}, gifList)
local gifMsg = new("TextLabel", {
	Position = UDim2.fromOffset(10, 48), Size = UDim2.new(1, -20, 1, -76),
	BackgroundTransparency = 1, Text = "", TextWrapped = true,
	FontFace = BodyFont, TextSize = 12, TextColor3 = C.dim, Visible = false, ZIndex = 33,
}, gifPop)
new("TextLabel", {
	Position = UDim2.new(0, 12, 1, -24), Size = UDim2.new(1, -24, 0, 18),
	BackgroundTransparency = 1, Text = "Powered by KLIPY",
	FontFace = BodyFont, TextSize = 11, TextColor3 = C.dim,
	TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 32,
}, gifPop)

local gifToken, gifPage, gifQuery, gifCount, gifOpened = 0, 1, "", 0, false
local loadGifs

local function addGifTile(item)
	gifCount += 1
	local t = new("TextButton", {
		BackgroundColor3 = C.bg, BorderSizePixel = 0, Text = "",
		AutoButtonColor = false, LayoutOrder = gifCount,
		ClipsDescendants = true, ZIndex = 32,
	}, gifList)
	round(t, 8)
	local cap = new("TextLabel", {
		Position = UDim2.fromOffset(5, 5), Size = UDim2.new(1, -10, 1, -10),
		BackgroundTransparency = 1, Text = item.t ~= "" and item.t or "GIF",
		TextWrapped = true, FontFace = BodyFont, TextSize = 10, TextColor3 = C.dim, ZIndex = 33,
	}, t)
	local img = new("ImageLabel", {
		Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1,
		ScaleType = Enum.ScaleType.Crop, ZIndex = 34,
	}, t)
	t.MouseEnter:Connect(function() tween(t, 0.12, { BackgroundColor3 = C.btnHover }) end)
	t.MouseLeave:Connect(function() tween(t, 0.12, { BackgroundColor3 = C.bg }) end)
	t.Activated:Connect(function() if sendGif then sendGif(item) end end)
	if item.th then
		task.spawn(function()
			local a = getAsset(item.th, "jpg")
			if a and alive and img.Parent then
				img.Image = a
				cap.Visible = false
			end
		end)
	end
end

local function addMoreTile()
	local m = new("TextButton", {
		Name = "More", BackgroundColor3 = C.btnHover, BorderSizePixel = 0,
		Text = "Load more", FontFace = UiFont, TextSize = 12, TextColor3 = C.text,
		AutoButtonColor = false, LayoutOrder = 1000000, ZIndex = 32,
	}, gifList)
	round(m, 8)
	m.Activated:Connect(function() loadGifs(gifQuery, gifPage + 1) end)
end

function loadGifs(q, pageNo)
	gifToken += 1
	local my = gifToken
	gifQuery, gifPage = q, pageNo
	local old = gifList:FindFirstChild("More")
	if old then old:Destroy() end
	if pageNo == 1 then
		gifCount = 0
		for _, c in ipairs(gifList:GetChildren()) do
			if c:IsA("GuiButton") then c:Destroy() end
		end
	end
	gifMsg.Text = "Loading..."
	gifMsg.Visible = pageNo == 1
	if not req then
		gifMsg.Text = "Your executor has no request function, so GIF search can't work."
		gifMsg.Visible = true
		return
	end
	task.spawn(function()
		local code, data = api("GET", "/gifs?q=" .. HttpService:UrlEncode(q) .. "&page=" .. pageNo)
		if my ~= gifToken or not alive then return end
		if code == 200 and data and type(data.items) == "table" then
			if #data.items == 0 and pageNo == 1 then
				gifMsg.Text = "No GIFs found"
				gifMsg.Visible = true
			else
				gifMsg.Visible = false
			end
			for _, item in ipairs(data.items) do addGifTile(item) end
			if data.next then addMoreTile() end
		else
			gifMsg.Text = (data and data.error) or ("GIF search failed (" .. tostring(code) .. ")")
			gifMsg.Visible = true
		end
	end)
end

bind(gifSearch.FocusLost, function(enter)
	if enter then loadGifs((gifSearch.Text:gsub("^%s+", ""):gsub("%s+$", "")), 1) end
end)

-- ----- settings -----
local setPop = new("Frame", {
	Name = "Settings", AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -10, 0, TITLE_H + 6),
	Size = UDim2.fromOffset(296, 214),
	BackgroundColor3 = C.panel, BorderSizePixel = 0,
	Visible = false, ZIndex = 30, Active = true,
}, win)
round(setPop, 10)
new("UIStroke", { Color = C.divider, Thickness = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, setPop)
new("UIScale", { Scale = 1 }, setPop)

local function settingText(props)
	props.BackgroundTransparency = 1
	props.FontFace = props.FontFace or BodyFont
	props.TextXAlignment = props.TextXAlignment or Enum.TextXAlignment.Left
	props.ZIndex = 31
	return new("TextLabel", props, setPop)
end
local function settingButton(props)
	props.BackgroundColor3 = C.btnHover
	props.BorderSizePixel = 0
	props.AutoButtonColor = false
	props.FontFace = UiFont
	props.TextSize = props.TextSize or 12
	props.TextColor3 = C.text
	props.ZIndex = 32
	local b = new("TextButton", props, setPop)
	round(b, 8)
	b.MouseEnter:Connect(function() tween(b, 0.12, { BackgroundColor3 = C.divider }) end)
	b.MouseLeave:Connect(function() tween(b, 0.12, { BackgroundColor3 = C.btnHover }) end)
	return b
end

settingText({ Position = UDim2.fromOffset(18, 14), Size = UDim2.new(1, -36, 0, 20), Text = "Settings", FontFace = UiFont, TextSize = 14, TextColor3 = C.text })
new("Frame", { Position = UDim2.fromOffset(0, 44), Size = UDim2.new(1, 0, 0, 1), BackgroundColor3 = C.divider, BackgroundTransparency = 0.5, BorderSizePixel = 0, ZIndex = 31 }, setPop)

settingText({ Position = UDim2.fromOffset(18, 58), Size = UDim2.fromOffset(150, 30), Text = "Open / close key", TextSize = 12, TextColor3 = C.text })
keyBtn = settingButton({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -18, 0, 58), Size = UDim2.fromOffset(112, 30), Text = toggleKey.Name })

settingText({ Position = UDim2.fromOffset(18, 102), Size = UDim2.fromOffset(110, 30), Text = "Text size", TextSize = 12, TextColor3 = C.text })
local sizeUp = settingButton({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -18, 0, 102), Size = UDim2.fromOffset(30, 30), Text = "+", TextSize = 16 })
local sizeValue = settingText({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -52, 0, 102), Size = UDim2.fromOffset(36, 30), Text = tostring(textSize), FontFace = UiFont, TextSize = 13, TextColor3 = C.text, TextXAlignment = Enum.TextXAlignment.Center })
local sizeDown = settingButton({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -92, 0, 102), Size = UDim2.fromOffset(30, 30), Text = "-", TextSize = 16 })

local preview = settingText({ Position = UDim2.fromOffset(18, 142), Size = UDim2.new(1, -36, 0, 26), Text = "The quick brown fox jumps over", TextSize = textSize, TextColor3 = C.text, TextTruncate = Enum.TextTruncate.AtEnd })
sizedLabels[preview] = 0
settingText({ Position = UDim2.fromOffset(18, 176), Size = UDim2.new(1, -36, 0, 30), Text = "Click the key button, then press the key you want. Esc cancels.", TextWrapped = true, TextSize = 11, TextColor3 = C.dim, TextYAlignment = Enum.TextYAlignment.Top })

function applyTextSize(n)
	n = math.clamp(math.floor(n), 10, 22)
	if n == textSize then return end
	textSize = n
	for label, delta in pairs(sizedLabels) do
		if label.Parent then
			label.TextSize = textSize + delta
		else
			sizedLabels[label] = nil
		end
	end
	sizeValue.Text = tostring(textSize)
	saveSettings()
	if refreshInput then refreshInput() end
end
bind(sizeUp.Activated, function() applyTextSize(textSize + 1) end)
bind(sizeDown.Activated, function() applyTextSize(textSize - 1) end)

bind(keyBtn.Activated, function()
	capturing = true
	box:ReleaseFocus()
	keyBtn.Text = "Press a key..."
end)
local function cancelCapture()
	if capturing then
		capturing = false
		keyBtn.Text = toggleKey.Name
	end
end

-- ----- right-click / action menu for a message -----
local menuTarget
local menuCatcher = new("TextButton", {
	Name = "MenuCatcher", Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1, Text = "", AutoButtonColor = false,
	Visible = false, ZIndex = 40, Active = true,
}, gui)
local menu = new("Frame", {
	Name = "MessageMenu", Size = UDim2.fromOffset(254, 120),
	BackgroundColor3 = C.panel, BorderSizePixel = 0,
	Visible = false, ZIndex = 41, Active = true,
}, gui)
round(menu, 10)
new("UIStroke", { Color = C.divider, Thickness = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, menu)
new("UIScale", { Scale = 1 }, menu)

local function closeMenu()
	menu.Visible = false
	menuCatcher.Visible = false
	menuTarget = nil
end
bind(menuCatcher.Activated, closeMenu)
bind(menuCatcher.MouseButton2Click, closeMenu)

for i, emoji in ipairs(QUICK_REACTIONS) do
	local b = new("TextButton", {
		Position = UDim2.fromOffset(8 + (i - 1) * 34, 6), Size = UDim2.fromOffset(32, 32),
		BackgroundColor3 = C.btnHover, BackgroundTransparency = 1,
		BorderSizePixel = 0, AutoButtonColor = false,
		Text = emoji, FontFace = UiFont, TextSize = 19, TextColor3 = C.text, ZIndex = 42,
	}, menu)
	round(b, 8)
	bind(b.MouseEnter, function() tween(b, 0.1, { BackgroundTransparency = 0.2 }) end)
	bind(b.MouseLeave, function() tween(b, 0.1, { BackgroundTransparency = 1 }) end)
	bind(b.Activated, function()
		local t = menuTarget
		closeMenu()
		if t and sendReact then sendReact(t.channelId, t.id, emoji) end
	end)
end
local moreBtn = new("TextButton", {
	Position = UDim2.fromOffset(8 + #QUICK_REACTIONS * 34, 6), Size = UDim2.fromOffset(32, 32),
	BackgroundColor3 = C.btnHover, BackgroundTransparency = 1,
	BorderSizePixel = 0, AutoButtonColor = false,
	Text = "+", FontFace = UiFont, TextSize = 18, TextColor3 = C.text, ZIndex = 42,
}, menu)
round(moreBtn, 8)
bind(moreBtn.MouseEnter, function() tween(moreBtn, 0.1, { BackgroundTransparency = 0.2 }) end)
bind(moreBtn.MouseLeave, function() tween(moreBtn, 0.1, { BackgroundTransparency = 1 }) end)
new("Frame", {
	Position = UDim2.fromOffset(0, 44), Size = UDim2.new(1, 0, 0, 1),
	BackgroundColor3 = C.divider, BackgroundTransparency = 0.5, BorderSizePixel = 0, ZIndex = 42,
}, menu)

local function menuItem(y, iconName, text)
	local b = new("TextButton", {
		Position = UDim2.fromOffset(6, y), Size = UDim2.new(1, -12, 0, 30),
		BackgroundColor3 = C.btnHover, BackgroundTransparency = 1,
		BorderSizePixel = 0, AutoButtonColor = false, Text = "", ZIndex = 42,
	}, menu)
	round(b, 8)
	local icon = lucideIcon(b, iconName, 15, C.text, 43)
	icon.AnchorPoint = Vector2.new(0, 0.5)
	icon.Position = UDim2.new(0, 10, 0.5, 0)
	new("TextLabel", {
		Position = UDim2.fromOffset(34, 0), Size = UDim2.new(1, -40, 1, 0),
		BackgroundTransparency = 1, Text = text, FontFace = UiFont, TextSize = 12,
		TextColor3 = C.text, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 43,
	}, b)
	bind(b.MouseEnter, function() tween(b, 0.1, { BackgroundTransparency = 0.3 }) end)
	bind(b.MouseLeave, function() tween(b, 0.1, { BackgroundTransparency = 1 }) end)
	return b
end
local replyItem = menuItem(50, "reply", "Reply")
local copyItem = copyFn and menuItem(82, "copy", "Copy text") or nil
local menuHeight = copyFn and 120 or 88
menu.Size = UDim2.fromOffset(254, menuHeight)

bind(replyItem.Activated, function()
	local t = menuTarget
	closeMenu()
	if t and startReply then startReply(t) end
end)
if copyItem then
	bind(copyItem.Activated, function()
		local t = menuTarget
		closeMenu()
		if t and copyFn then pcall(copyFn, t.text) end
	end)
end

local function closePopups()
	emojiPop.Visible = false
	gifPop.Visible = false
	setPop.Visible = false
	cancelCapture()
end
local function openEmojiPicker(action)
	emojiAction = action or insertIntoBox
	emojiPop.Visible = false
	gifPop.Visible = false
	setPop.Visible = false
	cancelCapture()
	popIn(emojiPop)
end
moreBtn.Activated:Connect(function()
	local t = menuTarget
	closeMenu()
	if not t then return end
	openEmojiPicker(function(char)
		emojiPop.Visible = false
		if sendReact then sendReact(t.channelId, t.id, char) end
	end)
end)

local function openContextMenu(target, x, y)
	closePopups()
	menuTarget = target
	local screen = gui.AbsoluteSize
	local w, h = 254, menuHeight
	menu.Position = UDim2.fromOffset(
		math.clamp(x, 6, math.max(6, screen.X - w - 6)),
		math.clamp(y, 6, math.max(6, screen.Y - h - 6)))
	menuCatcher.Visible = true
	popIn(menu)
end

local function togglePopup(which)
	closeMenu()
	local pop = which == "emoji" and emojiPop or which == "gif" and gifPop or setPop
	local was = pop.Visible
	closePopups()
	if not was then
		if which == "emoji" then emojiAction = insertIntoBox end
		popIn(pop)
		if which == "gif" and not gifOpened then
			gifOpened = true
			loadGifs("", 1)
		end
	end
end
bind(emojiBtn.Activated, function() togglePopup("emoji") end)
bind(gifBtn.Activated, function() togglePopup("gif") end)
bind(settingsBtn.Activated, function() togglePopup("settings") end)

-- ---------- resize handle + layout ----------
local grip = new("TextButton", {
	Name = "ResizeHandle", AnchorPoint = Vector2.new(1, 1),
	Position = UDim2.new(1, -3, 1, -3),
	Size = UDim2.fromOffset(18, 18),
	BackgroundTransparency = 1, BorderSizePixel = 0,
	AutoButtonColor = false, Text = "", ZIndex = 12,
}, win)
local function resizeLine(ax, ay, bx, by)
	local dx, dy = bx - ax, by - ay
	new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset((ax + bx) / 2, (ay + by) / 2),
		Size = UDim2.fromOffset(math.sqrt(dx * dx + dy * dy), 1.2),
		Rotation = math.deg(math.atan2(dy, dx)),
		BackgroundColor3 = C.dim, BorderSizePixel = 0, ZIndex = 13,
	}, grip)
end
resizeLine(9, 15, 15, 9)
resizeLine(13, 15, 15, 13)

-- bubbles size themselves to their text, up to this width
local widthBounds = {}
local boundTicket = 0
local sidebarCollapsed = initialWidth < 600
local function sidebarOffset()
	local narrow = win.AbsoluteSize.X < 580
	if sidebarCollapsed or narrow then return 0 end
	return SIDE_W
end
local function maxBubble()
	local w = win.AbsoluteSize.X - sidebarOffset() - 1
	return math.max(170, math.floor((w - 29 - 42 - 12) * 0.9))
end
local function refreshBounds()
	local m = maxBubble()
	local alivePack = {}
	for _, rec in ipairs(widthBounds) do
		if rec.c.Parent then
			rec.c.MaxSize = Vector2.new(math.max(60, m - rec.pad), math.huge)
			alivePack[#alivePack + 1] = rec
		end
	end
	widthBounds = alivePack
end
local function trackBound(constraint, pad)
	widthBounds[#widthBounds + 1] = { c = constraint, pad = pad }
	constraint.MaxSize = Vector2.new(math.max(60, maxBubble() - pad), math.huge)
end

local function layoutWorkspace()
	local narrow = win.AbsoluteSize.X < 580
	local offset = sidebarOffset()
	side.Visible = not sidebarCollapsed
	side.ZIndex = narrow and 9 or 6
	sidebarIcon.ImageRectOffset = Lucide48[sidebarCollapsed and "arrow-right" or "arrow-left"].Offset
	roomHead.Position = UDim2.fromOffset(offset, 0)
	roomHead.Size = UDim2.new(1, -offset, 0, 53)
	row.Position = UDim2.new(0, offset, 1, -composerHeight - 1)
	row.Size = UDim2.new(1, -offset, 0, composerHeight)
	boxBg.Size = UDim2.new(1, -73, 0, composerHeight - 21)
	sendBtn.Position = UDim2.new(1, -12, 1, -51)
	for _, list in pairs(lists) do
		list.Position = UDim2.fromOffset(offset + 1, 53)
		list.Size = UDim2.new(1, -offset - 1, 1, -55 - composerHeight)
	end
	local available = win.AbsoluteSize.X - offset
	roomName.Size = UDim2.new(1, available < 365 and -105 or -215, 1, 0)
	presencePill.Visible = not searchOpen and available >= 365
	findButton.Position = UDim2.new(1, -11, 0.5, 0)
	local popY = -(composerHeight + 10)
	emojiPop.Position = UDim2.new(1, -14, 1, popY)
	gifPop.Position = UDim2.new(1, -14, 1, popY)
	if updateJump then updateJump() end
	boundTicket += 1
	local ticket = boundTicket
	task.delay(0.06, function()
		if alive and ticket == boundTicket then refreshBounds() end
	end)
end
bind(sidebarButton.Activated, function()
	sidebarCollapsed = not sidebarCollapsed
	layoutWorkspace()
end)
bind(win:GetPropertyChangedSignal("AbsoluteSize"), layoutWorkspace)
layoutWorkspace()

-- ---------- scrolling ----------
local followLatest, autoScrolling, userScrolling, settleUntil, scrollTicket = {}, {}, {}, {}, {}
for _, channel in ipairs(CHANNELS) do
	followLatest[channel.id] = true
	scrollTicket[channel.id] = 0
end

local function bottomY(list)
	return math.max(0, list.AbsoluteCanvasSize.Y - list.AbsoluteWindowSize.Y)
end

local function atBottom(list)
	return bottomY(list) - list.CanvasPosition.Y <= 12
end

local function scheduleLatest(id)
	local list = lists[id]
	if not alive or not list or not followLatest[id] or searchOpen then return end
	scrollTicket[id] = scrollTicket[id] + 1
	local ticket = scrollTicket[id]
	local function sync()
		if not alive or not list.Parent or not followLatest[id] or searchOpen
			or scrollTicket[id] ~= ticket then return end
		autoScrolling[id] = true
		list.CanvasPosition = Vector2.new(0, bottomY(list))
		task.defer(function() autoScrolling[id] = false end)
	end
	task.defer(sync)
	task.delay(0.05, sync)
	task.delay(0.16, sync)
	task.delay(0.4, sync)
end

local jumpButton = new("TextButton", {
	Name = "JumpToLatest", AnchorPoint = Vector2.new(1, 1),
	Position = UDim2.new(1, -14, 1, -70),
	Size = UDim2.fromOffset(100, 29),
	BackgroundColor3 = C.panel, BorderSizePixel = 0,
	AutoButtonColor = false, Text = "", Visible = false, ZIndex = 7,
}, body)
round(jumpButton, 8)
local jumpScale = new("UIScale", { Scale = 1 }, jumpButton)
local jumpIcon = lucideIcon(jumpButton, "chevron-down", 15, C.text, 8)
jumpIcon.AnchorPoint = Vector2.new(0, 0.5)
jumpIcon.Position = UDim2.new(0, 10, 0.5, 0)
new("TextLabel", {
	Position = UDim2.fromOffset(32, 0),
	Size = UDim2.new(1, -36, 1, 0),
	BackgroundTransparency = 1, Text = "Latest",
	FontFace = UiFont, TextSize = 11, TextColor3 = C.text,
	TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 8,
}, jumpButton)
updateJump = function()
	local list = lists[current]
	if not list or not alive then return end
	local show = not searchOpen and not followLatest[current] and not atBottom(list)
	if show and not jumpButton.Visible then
		jumpScale.Scale = 0.85
		jumpButton.Visible = true
		tween(jumpScale, 0.2, { Scale = 1 }, Enum.EasingStyle.Back)
	elseif not show then
		jumpButton.Visible = false
	end
end
bind(jumpButton.Activated, function()
	followLatest[current] = true
	scheduleLatest(current)
	updateJump()
end)
for id, list in pairs(lists) do
	bind(list:GetPropertyChangedSignal("CanvasPosition"), function()
		if not alive then return end
		if not autoScrolling[id] and not searchOpen
			and (userScrolling[id] or os.clock() >= (settleUntil[id] or 0)) then
			followLatest[id] = atBottom(list)
		end
		if id == current then updateJump() end
	end)
	bind(list:GetPropertyChangedSignal("AbsoluteCanvasSize"), function()
		if followLatest[id] then scheduleLatest(id) end
		if id == current then updateJump() end
	end)
	bind(list:GetPropertyChangedSignal("AbsoluteWindowSize"), function()
		if followLatest[id] then scheduleLatest(id) end
		if id == current then updateJump() end
	end)
	bind(list.InputChanged, function(input)
		if input.UserInputType == Enum.UserInputType.MouseWheel then
			if input.Position.Z > 0 then
				followLatest[id] = false
			else
				task.defer(function()
					if alive and atBottom(list) then
						followLatest[id] = true
						scheduleLatest(id)
					end
				end)
			end
			if id == current then updateJump() end
		end
	end)
	bind(list.InputBegan, function(input)
		if input.UserInputType == Enum.UserInputType.Touch
			or input.UserInputType == Enum.UserInputType.MouseButton1 then
			userScrolling[id] = true
		end
	end)
	bind(list.InputEnded, function(input)
		if input.UserInputType == Enum.UserInputType.Touch
			or input.UserInputType == Enum.UserInputType.MouseButton1 then
			task.defer(function()
				userScrolling[id] = false
				if alive and atBottom(list) then
					followLatest[id] = true
					scheduleLatest(id)
				end
				if id == current then updateJump() end
			end)
		end
	end)
end
bind(box.Focused, function() tween(boxStroke, 0.17, { Transparency = 0 }) end)
bind(box.FocusLost, function() tween(boxStroke, 0.17, { Transparency = 1 }) end)

-- ---------- channels ----------
local function refreshChannels()
	for id, entry in pairs(chBtns) do
		local active = id == current
		entry.btn.BackgroundColor3 = C.panel
		hover(entry.btn, active and 0 or 1)
		tween(entry.nameLabel, 0.17, { TextColor3 = active and C.text or C.dim })
		tween(entry.hashLabel, 0.17, { TextColor3 = active and C.accent or C.dim })
		local count = unread[id] or 0
		entry.badge.Visible = not active and count > 0
		local pings = mentionsUnread[id] or 0
		entry.badge.Text = pings > 0 and ("@" .. tostring(math.min(pings, 9)))
			or count > 99 and "99+" or tostring(count)
	end
end

local function setChannel(id)
	if not lists[id] then return end
	local changed = id ~= current
	drafts[current] = box.Text
	current = id
	box.Text = drafts[id] or ""
	unread[id] = 0
	mentionsUnread[id] = 0
	for other, list in pairs(lists) do list.Visible = other == id end
	if changed then
		local list = lists[id]
		local base = list.Position
		list.Position = base + UDim2.fromOffset(16, 0)
		tween(list, 0.22, { Position = base })
	end
	roomName.Text = chanName[id]
	refreshReply()
	box.PlaceholderText = "Message #" .. id
	findInput.PlaceholderText = "Find in #" .. id
	if win.AbsoluteSize.X < 580 and not sidebarCollapsed then
		sidebarCollapsed = true
		layoutWorkspace()
	end
	refreshChannels()
	if updateSearch then updateSearch() end
	if updateJump then updateJump() end
	if followLatest[id] then scheduleLatest(id) end
end

for id, entry in pairs(chBtns) do
	bind(entry.btn.Activated, function() setChannel(id) end)
	bind(entry.btn.MouseEnter, function()
		if current ~= id then hover(entry.btn, 0.48) end
	end)
	bind(entry.btn.MouseLeave, function()
		if current ~= id then hover(entry.btn, 1) end
	end)
end

-- ---------- dragging / maximize / minimize ----------
local dragAction
local function makeDrag(handle, capture, apply)
	bind(handle.InputBegan, function(input)
		if not alive or dragAction or not win.Visible then return end
		local kind = input.UserInputType
		if kind ~= Enum.UserInputType.MouseButton1 and kind ~= Enum.UserInputType.Touch then return end
		dragAction = {
			input = input, touch = kind == Enum.UserInputType.Touch,
			origin = input.Position, state = capture(), apply = apply,
		}
	end)
end
bind(UIS.InputChanged, function(input)
	local action = dragAction
	if not alive or not action then return end
	if action.touch then
		if input ~= action.input then return end
	elseif input.UserInputType ~= Enum.UserInputType.MouseMovement then
		return
	end
	local delta = input.Position - action.origin
	action.apply(action.state, delta.X, delta.Y)
end)
bind(UIS.InputEnded, function(input)
	if dragAction and (input == dragAction.input or
		(not dragAction.touch and input.UserInputType == Enum.UserInputType.MouseButton1)) then
		dragAction = nil
	end
end)
makeDrag(titleDrag, function() return win.Position end, function(start, dx, dy)
	local currentCamera = workspace.CurrentCamera
	local screen = currentCamera and currentCamera.ViewportSize or Vector2.new(1280, 720)
	local width = win.AbsoluteSize.X
	win.Position = UDim2.fromOffset(
		math.clamp(start.X.Offset + dx, 54 - width, screen.X - 54),
		math.clamp(start.Y.Offset + dy, 0, screen.Y - TITLE_H))
end)
makeDrag(grip, function() return win.Size end, function(start, dx, dy)
	if not body.Visible then return end
	local currentCamera = workspace.CurrentCamera
	local screen = currentCamera and currentCamera.ViewportSize or Vector2.new(1280, 720)
	local maxW = math.max(340, screen.X - win.AbsolutePosition.X - 8)
	local maxH = math.max(260, screen.Y - win.AbsolutePosition.Y - 8)
	win.Size = UDim2.fromOffset(
		math.clamp(start.X.Offset + dx, math.min(MIN_W, maxW), maxW),
		math.clamp(start.Y.Offset + dy, math.min(MIN_H, maxH), maxH))
end)

local maximized, fullSize, fullPosition = false, nil, nil
bind(maximizeBtn.Activated, function()
	if not body.Visible then return end
	local currentCamera = workspace.CurrentCamera
	local screen = currentCamera and currentCamera.ViewportSize or Vector2.new(1280, 720)
	if not maximized then
		fullSize, fullPosition = win.Size, win.Position
		tween(win, 0.28, {
			Size = UDim2.fromOffset(math.max(340, screen.X - 14), math.max(260, screen.Y - 14)),
			Position = UDim2.fromOffset(7, 7),
		})
		maximized = true
		grip.Visible = false
		maximizeIcon.ImageRectOffset = Lucide48.minimize.Offset
		maximizeIcon.Image = Lucide48.minimize.Image
	else
		maximized = false
		tween(win, 0.28, { Size = fullSize, Position = fullPosition })
		grip.Visible = true
		maximizeIcon.ImageRectOffset = Lucide48.maximize.Offset
		maximizeIcon.Image = Lucide48.maximize.Image
	end
end)
local minimized, savedSize = false, win.Size
bind(minBtn.Activated, function()
	minimized = not minimized
	closePopups()
	if minimized then
		savedSize = win.Size
		body.Visible = false
		grip.Visible = false
		tween(win, 0.2, { Size = UDim2.fromOffset(win.AbsoluteSize.X, TITLE_H) })
		minIcon.ImageRectOffset = Lucide48.square.Offset
		minIcon.Image = Lucide48.square.Image
	else
		tween(win, 0.2, { Size = savedSize })
		body.Visible = true
		grip.Visible = not maximized
		minIcon.ImageRectOffset = Lucide48.minus.Offset
		minIcon.Image = Lucide48.minus.Image
		task.delay(0.22, function() if alive then layoutWorkspace() end end)
	end
end)

-- open / close the whole window with the keybind
local winLock = 0
local function toggleWindow()
	if os.clock() < winLock then return end
	winLock = os.clock() + 0.22
	local base = win.Position
	if win.Visible then
		closePopups()
		closeMenu()
		tween(win, 0.16, { Position = base + UDim2.fromOffset(0, 14) })
		task.delay(0.16, function()
			if not alive then return end
			win.Visible = false
			win.Position = base
		end)
	else
		win.Position = base + UDim2.fromOffset(0, 14)
		win.Visible = true
		tween(win, 0.22, { Position = base })
	end
end

-- ---------- message store / search ----------
local seen, queues = {}, {}
local seenOrder = {}
local indexed = {}
for _, channel in ipairs(CHANNELS) do
	queues[channel.id] = {}
	indexed[channel.id] = {}
end
local function indexMessage(channelId, node, contents)
	local entries = indexed[channelId]
	entries[#entries + 1] = { node = node, text = tostring(contents):lower() }
	if #entries > 200 then table.remove(entries, 1) end
	if searchOpen and updateSearch then updateSearch() end
end
updateSearch = function()
	local query = searchOpen and findInput.Text:lower():sub(1, 80) or ""
	local hits = 0
	for id, entries in pairs(indexed) do
		for _, entry in ipairs(entries) do
			if entry.node.Parent then
				local match = query == "" or entry.text:find(query, 1, true) ~= nil
				entry.node.Visible = id ~= current or match
				if id == current and match then hits += 1 end
			end
		end
	end
	findResult.Text = query == "" and "" or tostring(hits) .. " found"
	if updateJump then updateJump() end
end
local function toggleSearch(open)
	searchOpen = open
	findPanel.Visible = open
	findButton.Visible = not open
	roomName.Visible = not open
	presencePill.Visible = not open
	if not open then findInput.Text = "" end
	layoutWorkspace()
	updateSearch()
	if not open and followLatest[current] then scheduleLatest(current) end
	if open then
		task.defer(function()
			if alive and searchOpen then findInput:CaptureFocus() end
		end)
	end
end
bind(findButton.Activated, function() toggleSearch(true) end)
bind(exitFind.Activated, function() toggleSearch(false) end)
bind(findInput:GetPropertyChangedSignal("Text"), function()
	if updateSearch then updateSearch() end
end)
local lastId, order = 0, 0
local grouped = {}

local function insertMessage(channelId, node)
	local id = lists[channelId] and channelId or "main"
	local queue = queues[id]
	settleUntil[id] = os.clock() + 0.2
	order += 1
	node.LayoutOrder = order
	queue[#queue + 1] = node
	if #queue > 200 then table.remove(queue, 1):Destroy() end
	if followLatest[id] then scheduleLatest(id) end
end

local function addLabel(channelId, richText, color)
	local id = lists[channelId] and channelId or "main"
	grouped[id] = nil
	local frame = new("Frame", {
		Name = "Notice", Size = UDim2.new(1, -4, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1, BorderSizePixel = 0,
	}, lists[id])
	new("UIPadding", { PaddingTop = UDim.new(0, 4), PaddingBottom = UDim.new(0, 6) }, frame)
	new("TextLabel", {
		Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1, RichText = true, Text = richText,
		TextWrapped = true, Font = Enum.Font.Gotham,
		TextSize = 11, TextColor3 = color,
		TextXAlignment = Enum.TextXAlignment.Center, TextYAlignment = Enum.TextYAlignment.Top,
	}, frame)
	insertMessage(id, frame)
	indexMessage(id, frame, richText)
	return frame
end

local function sys(text)
	addLabel(current, esc(text), C.sys)
end

local messageViews = {}
local knownUsers = {}
local refreshMentions
knownUsers[lp.Name:lower()] = lp.Name
for _, channel in ipairs(CHANNELS) do
	messageViews[channel.id] = {}
	mentionsUnread[channel.id] = 0
end

local function containsOwnMention(value)
	for name in value:gmatch("@([%w_]+)") do
		if name:lower() == lp.Name:lower() then return true end
	end
	return false
end

-- inline `code`, @mentions and links
local function formatText(value)
	local parts, i = {}, 1
	while i <= #value do
		local char = value:sub(i, i)
		if char == TICK then
			local finish = value:find(TICK, i + 1, true)
			if finish and finish - i < 180 then
				parts[#parts + 1] = '<font color="#ACCBFA">'
					.. esc(value:sub(i + 1, finish - 1)) .. '</font>'
				i = finish + 1
			else
				parts[#parts + 1] = esc(char)
				i += 1
			end
		elseif char == "@" then
			local handle = value:sub(i + 1):match("^([%w_]+)")
			if handle and knownUsers[handle:lower()] then
				parts[#parts + 1] = '<font color="#' .. C.mine:ToHex()
					.. '"><b>@' .. esc(handle) .. '</b></font>'
				i += #handle + 1
			else
				parts[#parts + 1] = esc(char)
				i += 1
			end
		elseif char == "h" and (value:sub(i, i + 6) == "http://" or value:sub(i, i + 7) == "https://") then
			local url = value:sub(i):match("^https?://[^%s<>]+")
			if url then
				parts[#parts + 1] = '<font color="#' .. C.mine:ToHex() .. '"><u>' .. esc(url) .. '</u></font>'
				i += #url
			else
				parts[#parts + 1] = esc(char)
				i += 1
			end
		else
			parts[#parts + 1] = esc(char)
			i += 1
		end
	end
	return table.concat(parts)
end

local keyWords = {
	["and"] = true, ["break"] = true, ["continue"] = true, ["do"] = true,
	["else"] = true, ["elseif"] = true, ["end"] = true, ["false"] = true,
	["for"] = true, ["function"] = true, ["if"] = true, ["in"] = true,
	["local"] = true, ["nil"] = true, ["not"] = true, ["or"] = true,
	["repeat"] = true, ["return"] = true, ["then"] = true, ["true"] = true,
	["until"] = true, ["while"] = true, ["type"] = true,
}
local function codeHighlight(value)
	local parts, i = {}, 1
	local function color(part, hex)
		parts[#parts + 1] = '<font color="' .. hex .. '">' .. esc(part) .. '</font>'
	end
	while i <= #value do
		local ch = value:sub(i, i)
		if ch == "-" and value:sub(i, i + 1) == "--" then
			local finish = value:find("\n", i, true) or (#value + 1)
			color(value:sub(i, finish - 1), "#929292")
			i = finish
		elseif ch == '"' or ch == "'" then
			local finish, escaped = i + 1, false
			while finish <= #value do
				local nextChar = value:sub(finish, finish)
				if nextChar == ch and not escaped then break end
				if nextChar == "\\" then escaped = not escaped else escaped = false end
				finish += 1
			end
			finish = math.min(finish, #value)
			color(value:sub(i, finish), "#A1D4AE")
			i = finish + 1
		elseif ch:match("[%a_]") then
			local word = value:sub(i):match("^[%a_][%w_]*")
			if word then
				if keyWords[word] then color(word, "#91BAFF")
				else parts[#parts + 1] = esc(word) end
				i += #word
			else
				parts[#parts + 1] = esc(ch)
				i += 1
			end
		elseif ch:match("%d") then
			local number = value:sub(i):match("^%d+%.?%d*")
			if number then color(number, "#F4C68C"); i += #number
			else parts[#parts + 1] = esc(ch); i += 1 end
		else
			parts[#parts + 1] = esc(ch)
			i += 1
		end
	end
	return table.concat(parts)
end

local function findSharedUrl(value)
	local candidate = value:match("https?://[^%s<>]+")
	if not candidate then return nil end
	candidate = candidate:gsub("[,%.!%?%)%]]+$", "")
	local host = candidate:match("^https?://([%w%.%-]+)")
	if not host or not host:find("%.", 1, true) or #candidate > 250 then
		return nil
	end
	return candidate, host
end

local function jumpToMessage(channelId, id)
	local target = messageViews[channelId] and messageViews[channelId][id]
	if not target or not target.node or not target.node.Parent then return false end
	if current ~= channelId then setChannel(channelId) end
	if searchOpen then toggleSearch(false) end
	followLatest[channelId] = false
	scrollTicket[channelId] += 1
	local list = lists[channelId]
	task.defer(function()
		if not alive or not target.node.Parent then return end
		local y = list.CanvasPosition.Y + target.node.AbsolutePosition.Y
			- list.AbsolutePosition.Y - 24
		list.CanvasPosition = Vector2.new(0, math.clamp(y, 0, math.max(0,
			list.AbsoluteCanvasSize.Y - list.AbsoluteWindowSize.Y)))
		local highlight = new("UIStroke", {
			Color = C.accent, Thickness = 1.5, Transparency = 0,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		}, target.bubble)
		tween(highlight, 0.9, { Transparency = 1 })
		task.delay(0.95, function()
			if highlight.Parent then highlight:Destroy() end
		end)
		if updateJump then updateJump() end
	end)
	return true
end

-- ---------- reactions ----------
local function renderReactions(view)
	local holder = view.reactHolder
	if not holder or not holder.Parent then return end
	for _, c in ipairs(holder:GetChildren()) do
		if c:IsA("TextButton") then c:Destroy() end
	end
	local list = type(view.r) == "table" and view.r or {}
	local previous, now, shown = view.counts or {}, {}, 0
	for i, g in ipairs(list) do
		local users = type(g) == "table" and type(g.u) == "table" and g.u or {}
		local count = #users
		if type(g) == "table" and type(g.e) == "string" and count > 0 then
			shown += 1
			local mineReact = table.find(users, lp.UserId) ~= nil
			local chip = new("TextButton", {
				Name = "Reaction", LayoutOrder = i,
				Size = UDim2.fromOffset(0, 24), AutomaticSize = Enum.AutomaticSize.X,
				BackgroundColor3 = mineReact and C.accentSoft or C.btnHover, BorderSizePixel = 0,
				AutoButtonColor = false, Text = g.e .. "  " .. tostring(count),
				FontFace = UiFont, TextSize = 12, TextColor3 = C.text, ZIndex = 3,
			}, holder)
			round(chip, 12)
			new("UIPadding", { PaddingLeft = UDim.new(0, 9), PaddingRight = UDim.new(0, 9) }, chip)
			if mineReact then
				new("UIStroke", { Color = C.accent, Thickness = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, chip)
			end
			if previous[g.e] ~= count then
				local s = new("UIScale", { Scale = 0.6 }, chip)
				tween(s, 0.28, { Scale = 1 }, Enum.EasingStyle.Back)
			end
			now[g.e] = count
			chip.Activated:Connect(function()
				if sendReact then sendReact(view.channelId, view.id, g.e) end
			end)
		end
	end
	view.counts = now
	holder.Visible = shown > 0
	view.sizeC.MinSize = Vector2.new(shown > 0 and math.max(view.baseMin, 120) or view.baseMin, 0)
end

local function applyReactions(channelId, id, r)
	local views = messageViews[channelId]
	local view = views and views[id]
	if not view then return end
	view.r = r
	renderReactions(view)
end

-- ---------- messages ----------
local function buildText(parent, text, layoutOrder)
	local label = new("TextLabel", {
		Name = "Content", LayoutOrder = layoutOrder,
		Size = UDim2.fromOffset(0, 0), AutomaticSize = Enum.AutomaticSize.XY,
		BackgroundTransparency = 1, Text = safeRich(formatText(text), text), RichText = true,
		TextWrapped = true, FontFace = BodyFont, TextSize = textSize, TextColor3 = C.text,
		TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, ZIndex = 3,
	}, parent)
	sizedLabels[label] = 0
	trackBound(new("UISizeConstraint", {}, label), 24)
	return label
end

local function buildCode(parent, seg, layoutOrder)
	local panel = new("Frame", {
		Name = "CodeBlock", LayoutOrder = layoutOrder,
		Size = UDim2.fromOffset(0, 0), AutomaticSize = Enum.AutomaticSize.XY,
		BackgroundColor3 = C.bg, BorderSizePixel = 0, ZIndex = 3,
	}, parent)
	round(panel, 7)
	new("UIPadding", {
		PaddingTop = UDim.new(0, 8), PaddingBottom = UDim.new(0, 10),
		PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10),
	}, panel)
	new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 5) }, panel)
	new("UISizeConstraint", { MinSize = Vector2.new(150, 0) }, panel)
	local head = new("Frame", {
		LayoutOrder = 1, Size = UDim2.new(1, 0, 0, 19),
		BackgroundTransparency = 1, ZIndex = 4,
	}, panel)
	new("TextLabel", {
		Size = UDim2.new(1, -40, 1, 0),
		BackgroundTransparency = 1, Text = seg.lang or "luau",
		FontFace = UiFont, TextSize = 10, TextColor3 = C.dim,
		TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 5,
	}, head)
	local source = seg.text
	local src = new("TextLabel", {
		Name = "Source", LayoutOrder = 2,
		Size = UDim2.fromOffset(0, 0), AutomaticSize = Enum.AutomaticSize.XY,
		BackgroundTransparency = 1,
		Text = safeRich(codeHighlight(source), source), RichText = true, TextWrapped = true,
		Font = Enum.Font.Code, TextSize = math.max(9, textSize - 1), TextColor3 = C.text,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top, ZIndex = 4,
	}, panel)
	sizedLabels[src] = -1
	trackBound(new("UISizeConstraint", {}, src), 44)
	if copyFn then
		local button = new("TextButton", {
			Name = "CopyCode", AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, 0, 0, -4),
			Size = UDim2.fromOffset(29, 27),
			BackgroundColor3 = C.btn, BorderSizePixel = 0,
			AutoButtonColor = false, Text = "", ZIndex = 5,
		}, head)
		round(button, 7)
		local glyph = lucideIcon(button, "copy", 14, C.text, 6)
		button.Activated:Connect(function()
			if alive and pcall(copyFn, source) then
				glyph.Image = Lucide48.check.Image
				glyph.ImageRectOffset = Lucide48.check.Offset
				task.delay(1, function()
					if alive and glyph.Parent then
						glyph.Image = Lucide48.copy.Image
						glyph.ImageRectOffset = Lucide48.copy.Offset
					end
				end)
			end
		end)
	end
end

local function buildGif(parent, gif, layoutOrder)
	local w, h = tonumber(gif.w) or 200, tonumber(gif.h) or 150
	local scale = math.min(1, GIF_MAX_W / w, GIF_MAX_H / h)
	local fw, fh = math.max(60, math.floor(w * scale)), math.max(40, math.floor(h * scale))
	local holder = new("Frame", {
		Name = "Gif", LayoutOrder = layoutOrder,
		Size = UDim2.fromOffset(fw, fh), BackgroundColor3 = C.bg,
		BorderSizePixel = 0, ClipsDescendants = true, ZIndex = 3,
	}, parent)
	round(holder, 8)
	local cap = new("TextLabel", {
		Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1,
		Text = (type(gif.t) == "string" and gif.t ~= "") and ("GIF · " .. gif.t) or "GIF",
		TextWrapped = true, FontFace = BodyFont, TextSize = 11, TextColor3 = C.dim, ZIndex = 4,
	}, holder)
	task.spawn(function()
		-- 1) static preview (works anywhere images work)
		if type(gif.th) == "string" then
			local a = getAsset(gif.th, "jpg")
			if a and alive and holder.Parent then
				new("ImageLabel", {
					Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1,
					Image = a, ScaleType = Enum.ScaleType.Crop, ZIndex = 5,
				}, holder)
				cap.Visible = false
			end
		end
		-- 2) animated version (video), if this executor can play it
		if type(gif.v) == "string" then
			local a = getAsset(gif.v, "webm")
			if a and alive and holder.Parent then
				local ok, vf = pcall(function()
					return new("VideoFrame", {
						Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1,
						Video = a, Looped = true, Volume = 0, Playing = true, ZIndex = 6,
					}, holder)
				end)
				if ok and vf then
					cap.Visible = false
					task.delay(6, function()
						-- didn't load? drop it and keep the static preview
						if alive and vf.Parent and not vf.IsLoaded then vf:Destroy() end
					end)
				end
			end
		end
	end)
	return holder
end

local function removeMessage(id)
	for cid, views in pairs(messageViews) do
		local v = views[id]
		if v then
			views[id] = nil
			local q = queues[cid]
			local qi = table.find(q, v.node)
			if qi then table.remove(q, qi) end
			for k, e in ipairs(indexed[cid]) do
				if e.node == v.node then
					table.remove(indexed[cid], k)
					break
				end
			end
			grouped[cid] = nil
			pcall(function() v.node:Destroy() end)
			if updateSearch then updateSearch() end
			return
		end
	end
end

local function clearChannel(cid)
	if not lists[cid] then return end
	for _, n in ipairs(queues[cid]) do pcall(function() n:Destroy() end) end
	queues[cid] = {}
	indexed[cid] = {}
	messageViews[cid] = {}
	grouped[cid] = nil
	addLabel(cid, esc("Channel cleared"), C.sys)
end

local function addMessage(message, silent)
	if type(message) ~= "table" or type(message.id) ~= "number" or seen[message.id] then
		return
	end
	seen[message.id] = true
	seenOrder[#seenOrder + 1] = message.id
	if #seenOrder > 2000 then
		seen[table.remove(seenOrder, 1)] = nil
	end
	if message.id > lastId then lastId = message.id end

	local channelId = lists[message.ch] and message.ch or "main"
	local mine = message.userId == lp.UserId
	local user = clip(type(message.user) == "string" and message.user or "Unknown", 48)
	local raw = clip(type(message.text) == "string" and message.text or "", MAX_LEN)
	local gif = type(message.gif) == "table" and message.gif or nil
	local reply = type(message.reply) == "table" and type(message.reply.id) == "number" and message.reply or nil
	local segments = splitSegments(raw)
	local hasCode = false
	for _, s in ipairs(segments) do
		if s.kind == "code" then hasCode = true end
	end
	local timestamp = tonumber(message.ts)
	if not timestamp or timestamp ~= timestamp or timestamp <= 0
		or timestamp > 9999999999999 then
		timestamp = os.time() * 1000
	end
	timestamp = math.floor(timestamp)
	-- the server already converted the time to America/New_York
	local shortTime = (type(message.tm) == "string" and message.tm ~= "") and message.tm
		or os.date("%I:%M %p", math.floor(timestamp / 1000))
	local previous = grouped[channelId]
	local compact = previous and previous.id == message.userId
		and timestamp >= previous.ts and timestamp - previous.ts <= 180000
		and not reply and not hasCode and not gif
	grouped[channelId] = { id = message.userId, ts = timestamp }

	local safeName = user:match("^[%w_]+$")
	if safeName and #safeName <= 28 then
		knownUsers[safeName:lower()] = safeName
	end
	if refreshMentions then refreshMentions() end
	local mentioned = not mine and not hasCode and containsOwnMention(raw)

	local node = new("Frame", {
		Name = mine and "OwnMessage" or "Message",
		Size = UDim2.new(1, -4, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1, BorderSizePixel = 0,
	}, lists[channelId])
	-- sits behind the bubble so right-click works anywhere on the row
	local hit = new("TextButton", {
		Name = "Hit", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1,
		Text = "", AutoButtonColor = false, ZIndex = 1,
	}, node)
	if not mine and not compact then
		local face = new("ImageLabel", {
			Name = "Avatar", Position = UDim2.fromOffset(2, 5),
			Size = UDim2.fromOffset(31, 31), BackgroundColor3 = C.btn,
			BorderSizePixel = 0, ScaleType = Enum.ScaleType.Crop,
			Image = "rbxthumb://type=AvatarHeadShot&id=" .. tostring(message.userId or 0)
				.. "&w=150&h=150",
		}, node)
		round(face, 8)
	end

	-- the bubble sizes itself to its content (clamped by the width constraint)
	local bubblePosition = mine and UDim2.new(1, -6, 0, 2) or UDim2.fromOffset(42, 2)
	local bubble = new("Frame", {
		Name = mentioned and "Mention" or mine and "Outgoing" or "Incoming",
		AnchorPoint = mine and Vector2.new(1, 0) or Vector2.new(0, 0),
		Position = bubblePosition,
		Size = UDim2.fromOffset(0, 0),
		AutomaticSize = Enum.AutomaticSize.XY,
		BackgroundColor3 = (mine or mentioned) and C.accentSoft or C.panel,
		BorderSizePixel = 0, ZIndex = 2,
	}, node)
	round(bubble, 10)
	new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 5) }, bubble)
	new("UIPadding", {
		PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12),
		PaddingTop = UDim.new(0, 9), PaddingBottom = UDim.new(0, 9),
	}, bubble)
	local baseMin = 44
	if reply or hasCode then baseMin = 210 end
	local linkUrl, linkDomain
	for _, s in ipairs(segments) do
		if s.kind == "text" and not linkUrl then
			linkUrl, linkDomain = findSharedUrl(s.text)
		end
	end
	if linkUrl then baseMin = math.max(baseMin, 240) end
	local sizeC = new("UISizeConstraint", { MinSize = Vector2.new(baseMin, 0) }, bubble)
	trackBound(sizeC, 0)

	if not compact then
		local author = new("TextButton", {
			Name = "Author", LayoutOrder = 1,
			Size = UDim2.fromOffset(0, 18), AutomaticSize = Enum.AutomaticSize.X,
			BackgroundTransparency = 1, RichText = true,
			Text = "", FontFace = UiFont,
			TextSize = 12, TextColor3 = C.text,
			AutoButtonColor = false, ZIndex = 3,
		}, bubble)
		local tone = mine and C.mine or nameColor(message.userId)
		author.Text = '<font color="#' .. tone:ToHex() .. '">'
			.. esc(mine and "You" or user)
			.. '</font>  <font color="#' .. C.dim:ToHex() .. '" size="10">'
			.. esc(shortTime) .. '</font>'
		author.Activated:Connect(function()
			if not alive or mine or not safeName then return end
			local suffix = box.Text ~= "" and " " or ""
			box.Text = box.Text .. suffix .. "@" .. safeName .. " "
			box.CursorPosition = #box.Text + 1
			box:CaptureFocus()
		end)
	end

	if reply then
		local original = messageViews[channelId][reply.id]
		local toAuthor = original and original.user or (type(reply.user) == "string" and reply.user) or "Unknown"
		local toBody = original and original.excerpt or (type(reply.text) == "string" and reply.text) or "Original message unavailable"
		local quote = new("TextButton", {
			Name = "ReplyReference", LayoutOrder = 2,
			Size = UDim2.new(1, 0, 0, 44),
			BackgroundColor3 = C.btn, BorderSizePixel = 0,
			AutoButtonColor = false, Text = "", ZIndex = 3,
		}, bubble)
		round(quote, 7)
		new("Frame", {
			Position = UDim2.fromOffset(0, 5), Size = UDim2.fromOffset(2, 34),
			BorderSizePixel = 0, BackgroundColor3 = C.accent, ZIndex = 4,
		}, quote)
		new("TextLabel", {
			Position = UDim2.fromOffset(10, 5), Size = UDim2.new(1, -18, 0, 17),
			BackgroundTransparency = 1, Text = toAuthor,
			TextColor3 = C.mine, FontFace = UiFont, TextSize = 11,
			TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd,
			ZIndex = 4,
		}, quote)
		new("TextLabel", {
			Position = UDim2.fromOffset(10, 22), Size = UDim2.new(1, -18, 0, 16),
			BackgroundTransparency = 1, Text = toBody,
			TextColor3 = C.dim, FontFace = BodyFont, TextSize = 10,
			TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd,
			ZIndex = 4,
		}, quote)
		local originalId = reply.id
		quote.Activated:Connect(function()
			if not jumpToMessage(channelId, originalId) then
				sys("That message is no longer in the loaded history")
			end
		end)
	end

	local layoutOrder = 3
	for _, seg in ipairs(segments) do
		if seg.kind == "code" then
			buildCode(bubble, seg, layoutOrder)
		else
			buildText(bubble, seg.text, layoutOrder)
		end
		layoutOrder += 1
	end

	if linkUrl then
		local card = new("TextButton", {
			Name = "SharedLink", LayoutOrder = 50,
			Size = UDim2.new(1, 0, 0, 44),
			BackgroundColor3 = C.bg, BorderSizePixel = 0,
			AutoButtonColor = false, Text = "", ZIndex = 3,
		}, bubble)
		round(card, 7)
		local linkIcon = lucideIcon(card, "link", 15, C.mine, 4)
		linkIcon.AnchorPoint = Vector2.new(0, 0.5)
		linkIcon.Position = UDim2.new(0, 10, 0.5, 0)
		new("TextLabel", {
			Position = UDim2.fromOffset(34, 4),
			Size = UDim2.new(1, -43, 0, 17),
			BackgroundTransparency = 1, Text = linkDomain,
			TextTruncate = Enum.TextTruncate.AtEnd,
			FontFace = UiFont, TextSize = 11, TextColor3 = C.text,
			TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 4,
		}, card)
		new("TextLabel", {
			Position = UDim2.fromOffset(34, 21),
			Size = UDim2.new(1, -43, 0, 17),
			BackgroundTransparency = 1, Text = linkUrl,
			TextTruncate = Enum.TextTruncate.AtEnd,
			FontFace = BodyFont, TextSize = 10, TextColor3 = C.dim,
			TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 4,
		}, card)
		card.Activated:Connect(function()
			if not alive then return end
			local ok = pcall(function()
				game:GetService("GuiService"):OpenBrowserWindow(linkUrl)
			end)
			if not ok then
				if copyFn and pcall(copyFn, linkUrl) then
					sys("Link copied to clipboard")
				else
					sys("Could not open or copy the link")
				end
			end
		end)
	end

	if gif then buildGif(bubble, gif, 60) end

	local reactHolder = new("Frame", {
		Name = "Reactions", LayoutOrder = 90,
		Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1, Visible = false, ZIndex = 3,
	}, bubble)
	new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal, Wraps = true,
		SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 4),
	}, reactHolder)

	local view = {
		node = node, bubble = bubble, user = user, userId = message.userId,
		text = raw ~= "" and raw or (gif and "GIF" or ""),
		excerpt = clip((raw ~= "" and raw or "GIF"):gsub("[\r\n]+", " "), 110),
		channelId = channelId, id = message.id,
		reactHolder = reactHolder, sizeC = sizeC, baseMin = baseMin,
		r = type(message.r) == "table" and message.r or nil,
	}

	-- hover action bar (desktop) / tap to show (touch)
	local buttonsWanted = copyFn and 3 or 2
	local actionsW = buttonsWanted * 28 + (buttonsWanted - 1) * 2 + 6
	local actions = new("Frame", {
		Name = "MessageActions", Size = UDim2.fromOffset(actionsW, 30),
		BackgroundColor3 = C.panel, BorderSizePixel = 0,
		Visible = false, ZIndex = 8,
	}, node)
	round(actions, 8)
	new("UIStroke", { Color = C.divider, Thickness = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, actions)
	new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 2),
	}, actions)
	new("UIPadding", { PaddingLeft = UDim.new(0, 3), PaddingRight = UDim.new(0, 3) }, actions)
	local function actionButton(order)
		local b = new("TextButton", {
			LayoutOrder = order, Size = UDim2.fromOffset(28, 26),
			BackgroundColor3 = C.btnHover, BackgroundTransparency = 1,
			BorderSizePixel = 0, AutoButtonColor = false, Text = "", ZIndex = 9,
		}, actions)
		round(b, 6)
		b.MouseEnter:Connect(function() hover(b, 0) end)
		b.MouseLeave:Connect(function() hover(b, 1) end)
		return b
	end
	local replyB = actionButton(1)
	lucideIcon(replyB, "reply", 14, C.text, 10)
	replyB.Activated:Connect(function()
		if alive and startReply then actions.Visible = false; startReply(view) end
	end)
	local reactB = actionButton(2)
	new("TextLabel", {
		Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1,
		Text = utf8.char(0x1F642), FontFace = UiFont, TextSize = 14, TextColor3 = C.text, ZIndex = 10,
	}, reactB)
	reactB.Activated:Connect(function()
		if not alive then return end
		actions.Visible = false
		openContextMenu(view, reactB.AbsolutePosition.X - 120, reactB.AbsolutePosition.Y + 32)
	end)
	if copyFn then
		local copyB = actionButton(3)
		local glyph = lucideIcon(copyB, "copy", 14, C.text, 10)
		copyB.Activated:Connect(function()
			if alive and pcall(copyFn, view.text) then
				glyph.Image = Lucide48.check.Image
				glyph.ImageRectOffset = Lucide48.check.Offset
				task.delay(1, function()
					if alive and glyph.Parent then
						glyph.Image = Lucide48.copy.Image
						glyph.ImageRectOffset = Lucide48.copy.Offset
					end
				end)
			end
		end)
	end
	local function placeActions()
		if not (bubble.Parent and node.Parent) then return end
		local bx = bubble.AbsolutePosition.X - node.AbsolutePosition.X
		local by = bubble.AbsolutePosition.Y - node.AbsolutePosition.Y
		actions.Position = UDim2.fromOffset(
			math.max(0, bx + bubble.AbsoluteSize.X - actionsW - 6), by - 16)
	end
	local overNode, overActions = false, false
	local function refreshActions()
		task.delay(0.08, function()
			if not alive or not actions.Parent then return end
			local show = overNode or overActions
			if show and not actions.Visible then
				placeActions()
				actions.Visible = true
			elseif not show then
				actions.Visible = false
			end
		end)
	end
	if not UIS.TouchEnabled or UIS.MouseEnabled then
		node.MouseEnter:Connect(function() overNode = true; refreshActions() end)
		node.MouseLeave:Connect(function() overNode = false; refreshActions() end)
		actions.MouseEnter:Connect(function() overActions = true; refreshActions() end)
		actions.MouseLeave:Connect(function() overActions = false; refreshActions() end)
	end
	hit.MouseButton2Click:Connect(function()
		if not alive then return end
		local mouse = UIS:GetMouseLocation()
		openContextMenu(view, mouse.X, mouse.Y)
	end)
	if UIS.TouchEnabled and not UIS.MouseEnabled then
		hit.Activated:Connect(function()
			if actions.Visible then
				actions.Visible = false
			else
				placeActions()
				actions.Visible = true
			end
		end)
	end

	insertMessage(channelId, node)
	indexMessage(channelId, node, user .. " " .. view.text)
	messageViews[channelId][message.id] = view
	node.Destroying:Connect(function()
		if messageViews[channelId][message.id] and
			messageViews[channelId][message.id].node == node then
			messageViews[channelId][message.id] = nil
		end
	end)
	if view.r then renderReactions(view) end

	if not silent then
		fadeIn(node, 0.25)
		bubble.Position = bubblePosition + UDim2.fromOffset(0, 8)
		tween(bubble, 0.28, { Position = bubblePosition })
	end

	if not silent and not mine then
		if mentioned and channelId ~= current then
			mentionsUnread[channelId] += 1
		end
		if channelId ~= current then
			unread[channelId] = (unread[channelId] or 0) + 1
			refreshChannels()
		elseif mentioned then
			refreshChannels()
		end
	end
end

-- ---------- status ----------
local STATUS_COLORS = {
	connecting = C.dim, online = C.ok, fallback = C.caution, offline = C.off, banned = C.off,
}
local statusState = "connecting"
local function setStatus(state)
	statusState = state
	tween(statusDot, 0.3, {
		BackgroundColor3 = STATUS_COLORS[state] or C.dim, BackgroundTransparency = 0,
	})
end
task.spawn(function()
	while alive do
		if statusState == "connecting" then
			tween(statusDot, 0.7, { BackgroundTransparency = 0.7 })
			task.wait(0.7)
			if statusState == "connecting" then tween(statusDot, 0.7, { BackgroundTransparency = 0 }) end
			task.wait(0.7)
		else
			task.wait(0.25)
		end
	end
end)

local function setCount(n)
	if type(n) == "number" then countLbl.Text = tostring(n) .. " online" end
end

-- ---------- network ----------
local ws, wsLive = nil, false
local lastClear, lastRv, clearBaselined = 0, 0, false

local function onBanned(msg)
	if banned then return end
	banned = true
	setStatus("banned")
	sys(msg or "you are banned")
	if ws then pcall(function() ws:Close() end) end
end

local function handle(raw)
	if not alive or banned then return end
	local ok, d = pcall(HttpService.JSONDecode, HttpService, raw)
	if not ok or type(d) ~= "table" then return end
	if d.t == "hist" then
		for _, m in ipairs(d.msgs or {}) do addMessage(m, true) end
		lastClear = math.max(lastClear, tonumber(d.cs) or 0)
		clearBaselined = true
		setCount(d.n)
	elseif d.t == "msg" then
		addMessage(d.m)
	elseif d.t == "del" then
		for _, id in ipairs(d.ids or {}) do removeMessage(id) end
	elseif d.t == "clear" then
		lastClear = math.max(lastClear, tonumber(d.s) or 0)
		clearChannel(d.ch)
	elseif d.t == "react" then
		applyReactions(d.ch, d.id, d.r)
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

-- one place that sends a message payload (text or gif)
local function transmit(payload, onFail)
	if wsSend(payload) then return true end
	if not req then
		sys("Unable to send while disconnected")
		return false
	end
	task.spawn(function()
		local code, data = api("POST", "/send", payload)
		if not alive then return end
		if code == 200 and data and data.m then
			addMessage(data.m)
		else
			if code == 403 and data and data.error == "you are banned" then
				onBanned(data.error)
			end
			if onFail and not banned then onFail() end
			sys((data and data.error) or ("Send failed (" .. tostring(code) .. ")"))
		end
	end)
	return true
end

sendReact = function(channelId, id, emoji)
	if banned then return end
	local payload = { t = "react", ch = channelId, id = id, e = emoji, user = lp.Name, userId = lp.UserId }
	if wsSend(payload) then return end
	if not req then return end
	task.spawn(function()
		local code, data = api("POST", "/react", payload)
		if not alive then return end
		if code == 200 and data and data.r then
			applyReactions(channelId, id, data.r)
		else
			sys((data and data.error) or ("Reaction failed (" .. tostring(code) .. ")"))
		end
	end)
end

local function send(text, channelOverride)
	local channel = channelOverride or current
	if not lists[channel] then return false end
	local original = tostring(text)
	local trimmed = original:match("^%s*(.-)%s*$")
	if trimmed == "" then return false end
	if banned then sys("You are banned"); return false end
	local reply = pendingReplies[channel]

	-- "/something" can be handled by an add-on script that registered itself in ChatHooks
	if trimmed:sub(1, 1) == "/" and not reply then
		local hooks = env.ChatHooks
		local handler = type(hooks) == "table" and hooks.command or nil
		if type(handler) == "function" then
			task.spawn(function()
				local ok, err = pcall(handler, trimmed, { request = api, sys = sys, channel = channel })
				if not ok then sys("Command failed: " .. tostring(err)) end
			end)
			return true
		end
	end

	local encoded = prepareOutgoing(trimmed)
	local length = utf8.len(encoded) or #encoded
	if length > MAX_LEN then
		sys("Message is too long (" .. tostring(length) .. "/" .. MAX_LEN .. ")")
		return false
	end
	if not req and not wsLive then
		sys("Not connected: cannot send")
		return false
	end
	local payload = {
		t = "send", ch = channel, user = lp.Name,
		userId = lp.UserId, text = encoded, reply = reply and reply.id or nil,
	}
	local function finishReply()
		if reply and pendingReplies[channel] == reply then
			pendingReplies[channel] = nil
			if current == channel then refreshReply() end
		end
	end
	local function restore()
		if reply and not pendingReplies[channel] then
			pendingReplies[channel] = reply
			if current == channel then refreshReply() end
		end
		if drafts[channel] == nil or drafts[channel] == "" then
			drafts[channel] = original
			if current == channel and box.Text == "" then box.Text = original end
		end
	end
	if transmit(payload, restore) then
		finishReply()
		return true
	end
	return false
end

sendGif = function(item)
	if banned then sys("You are banned"); return end
	closePopups()
	local reply = pendingReplies[current]
	local channel = current
	local payload = {
		t = "send", ch = channel, user = lp.Name, userId = lp.UserId, text = "",
		reply = reply and reply.id or nil,
		gif = { v = item.v, th = item.th, w = item.w, h = item.h, t = item.t },
	}
	if transmit(payload) and reply and pendingReplies[channel] == reply then
		pendingReplies[channel] = nil
		refreshReply()
	end
end

startReply = function(view)
	if not alive then return end
	pendingReplies[view.channelId] = {
		id = view.id,
		user = (view.user or "Unknown"):match("^[%w_]+$") or "Unknown",
		text = clip(view.text:gsub("[\r\n|]+", " "), 48),
	}
	if current ~= view.channelId then setChannel(view.channelId) end
	if searchOpen then toggleSearch(false) end
	refreshReply()
	box:CaptureFocus()
end

if hasWS then
	task.spawn(function()
		while alive and not banned do
			local ok, sock = pcall(WebSocket.connect, WS_URL)
			if ok and sock then
				local closed = false
				sock.OnMessage:Connect(function(raw)
					if alive and ws == sock then handle(raw) end
				end)
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

-- HTTP fallback (only runs while the websocket isn't live)
task.spawn(function()
	while alive and not banned do
		if not wsLive then
			local first = lastId == 0
			local code, data = api("GET", "/poll?since=" .. lastId .. "&rv=" .. lastRv)
			if not alive then break end
			if wsLive then
				-- websocket came up while we were waiting
			elseif code == 200 and data then
				setStatus("fallback")
				for _, m in ipairs(data.msgs or {}) do addMessage(m, first) end
				for _, id in ipairs(data.dels or {}) do removeMessage(id) end
				for _, x in ipairs(data.rx or {}) do
					if type(x) == "table" then applyReactions(x.ch, x.id, x.r) end
				end
				lastRv = math.max(lastRv, tonumber(data.rv) or 0)
				if not clearBaselined then
					-- first contact: remember the newest clear without replaying old ones
					lastClear = math.max(lastClear, tonumber(data.cs) or 0)
					clearBaselined = true
				else
					for _, c in ipairs(data.clears or {}) do
						if type(c) == "table" and (tonumber(c.s) or 0) > lastClear then
							lastClear = tonumber(c.s)
							clearChannel(c.ch)
						end
					end
				end
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

-- ---------- mentions ----------
local mentionPanel = new("Frame", {
	Name = "MentionSuggestions", Position = UDim2.fromOffset(14, -40),
	Size = UDim2.new(1, -87, 0, 35),
	BackgroundColor3 = C.panel, BorderSizePixel = 0,
	Visible = false, ZIndex = 12,
}, row)
round(mentionPanel, 8)
local suggestionButtons = {}
local mentionCandidates = {}
local completingMention = false
local hoveringSuggestions = false
local lastMention
bind(mentionPanel.MouseEnter, function() hoveringSuggestions = true end)
bind(mentionPanel.MouseLeave, function() hoveringSuggestions = false end)

local function mentionAtCursor()
	local caret = box.CursorPosition
	if caret < 1 then return nil end
	local before = box.Text:sub(1, caret - 1)
	local index, query = before:match("()@([%w_]*)$")
	if not index then return nil end
	if index > 1 and before:sub(index - 1, index - 1):match("[%w_@]") then
		return nil
	end
	return index, query, caret
end

local function insertMention(name)
	local startAt, _, caret = mentionAtCursor()
	if not startAt and lastMention and lastMention.text == box.Text then
		startAt, caret = lastMention.startAt, lastMention.caret
	end
	if not startAt then return end
	local replacement = "@" .. name .. " "
	box.Text = box.Text:sub(1, startAt - 1)
		.. replacement .. box.Text:sub(caret)
	box.CursorPosition = startAt + #replacement
	mentionPanel.Visible = false
	lastMention = nil
	completingMention = false
	box:CaptureFocus()
end

for i = 1, 5 do
	local choice = new("TextButton", {
		Name = "Suggestion" .. tostring(i),
		Position = UDim2.fromOffset(5, 5 + (i - 1) * 30),
		Size = UDim2.new(1, -10, 0, 28),
		BackgroundColor3 = C.btn, BackgroundTransparency = 1,
		BorderSizePixel = 0, AutoButtonColor = false,
		Text = "", Visible = false, ZIndex = 13,
	}, mentionPanel)
	round(choice, 6)
	local handle = new("TextLabel", {
		Name = "Username", Position = UDim2.fromOffset(9, 0),
		Size = UDim2.new(1, -18, 1, 0),
		BackgroundTransparency = 1, Text = "",
		FontFace = UiFont, TextSize = 12, TextColor3 = C.text,
		TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 14,
	}, choice)
	bind(choice.MouseEnter, function() hover(choice, 0) end)
	bind(choice.MouseLeave, function() hover(choice, 1) end)
	bind(choice.Activated, function()
		local name = mentionCandidates[i]
		if name then insertMention(name) end
	end)
	suggestionButtons[i] = { button = choice, label = handle }
end

refreshMentions = function()
	if not alive or UIS:GetFocusedTextBox() ~= box then
		if not hoveringSuggestions then mentionPanel.Visible = false end
		return
	end
	local startAt, query = mentionAtCursor()
	if not startAt then
		mentionPanel.Visible = false
		lastMention = nil
		return
	end
	lastMention = { startAt = startAt, caret = box.CursorPosition, text = box.Text }
	local matches = {}
	local needle = query:lower()
	for key, name in pairs(knownUsers) do
		if key:sub(1, #needle) == needle and name:lower() ~= lp.Name:lower() then
			matches[#matches + 1] = name
		end
	end
	table.sort(matches, function(a, b) return a:lower() < b:lower() end)
	local count = math.min(#matches, 5)
	mentionPanel.Visible = count > 0
	if count > 0 then
		local height = count * 30 + 10
		mentionPanel.Position = UDim2.fromOffset(14, -height - 3)
		mentionPanel.Size = UDim2.new(1, -87, 0, height)
	end
	for i, entry in ipairs(suggestionButtons) do
		local name = matches[i]
		mentionCandidates[i] = name
		entry.button.Visible = i <= count
		entry.label.Text = name and ("@" .. name) or ""
	end
end

-- ---------- composer behaviour ----------
refreshInput = function()
	if not alive then return end
	local text = box.Text
	local length = utf8.len(text) or #text
	-- the input surface grows with the text (up to ~6 lines, then it scrolls)
	local lineHeight = textSize + 5
	local textHeight = math.max(box.TextBounds.Y, lineHeight)
	local boxHeight = math.clamp(math.ceil(textHeight) + 22, 40, 40 + lineHeight * 5)
	local newHeight = boxHeight + 21
	if composerHeight ~= newHeight then
		composerHeight = newHeight
		box.TextYAlignment = boxHeight > 40 and Enum.TextYAlignment.Top or Enum.TextYAlignment.Center
		layoutWorkspace()
		if followLatest[current] then scheduleLatest(current) end
	end
	local nonempty = text:match("%S") ~= nil
	counter.Text = length >= 7500 and (tostring(length) .. "/" .. MAX_LEN) or ""
	counter.TextColor3 = length > MAX_LEN and C.bad or C.dim
	local ready = nonempty and length <= MAX_LEN
	tween(sendBtn, 0.15, { BackgroundTransparency = ready and 0 or 0.5 })
	sendIcon.ImageTransparency = ready and 0 or 0.22
	if not completingMention then refreshMentions() end
end

bind(box:GetPropertyChangedSignal("Text"), function()
	-- :sob: turns into the emoji as soon as you close the colon (not inside code)
	if box.CursorPosition == #box.Text + 1
		and not box.Text:find(FENCE, 1, true)
		and not looksLikeCode(box.Text) then
		local replaced = emojify(box.Text)
		if replaced ~= box.Text then
			box.Text = replaced
			box.CursorPosition = #replaced + 1
		end
	end
	drafts[current] = box.Text
	refreshInput()
end)
bind(box:GetPropertyChangedSignal("TextBounds"), function() refreshInput() end)
bind(box:GetPropertyChangedSignal("CursorPosition"), function()
	if not completingMention then refreshMentions() end
end)
bind(box.Focused, function()
	refreshMentions()
end)
bind(box.FocusLost, function(enter)
	if not hoveringSuggestions then mentionPanel.Visible = false end
	if enter and not UIS:IsKeyDown(Enum.KeyCode.LeftShift)
		and not UIS:IsKeyDown(Enum.KeyCode.RightShift) then
		local content = box.Text:gsub("\n+$", "")
		if send(content) then box.Text = "" end
	end
end)
local function sendCurrent()
	local content = box.Text:gsub("\n+$", "")
	if send(content) then box.Text = "" end
end
bind(sendBtn.Activated, sendCurrent)

bind(UIS.InputBegan, function(input, processed)
	-- key capture for the Settings panel
	if capturing then
		if input.UserInputType == Enum.UserInputType.Keyboard then
			capturing = false
			if input.KeyCode ~= Enum.KeyCode.Escape and input.KeyCode ~= Enum.KeyCode.Unknown then
				toggleKey = input.KeyCode
				saveSettings()
			end
			keyBtn.Text = toggleKey.Name
		end
		return
	end
	if UIS:GetFocusedTextBox() == box then
		if input.KeyCode == Enum.KeyCode.Tab and mentionPanel.Visible then
			local name = mentionCandidates[1]
			if name then
				completingMention = true
				insertMention(name)
			end
			return
		end
		if input.KeyCode == Enum.KeyCode.Return
			or input.KeyCode == Enum.KeyCode.KeypadEnter then
			if UIS:IsKeyDown(Enum.KeyCode.LeftShift)
				or UIS:IsKeyDown(Enum.KeyCode.RightShift) then
				return -- Shift+Enter = new line (paragraphs)
			end
			task.defer(function()
				if alive then sendCurrent() end
			end)
			return
		end
		if input.KeyCode == Enum.KeyCode.Escape then
			if pendingReplies[current] then
				pendingReplies[current] = nil
				refreshReply()
			end
			mentionPanel.Visible = false
			return
		end
	end
	if not processed and input.KeyCode == toggleKey then
		toggleWindow()
	elseif input.KeyCode == Enum.KeyCode.F and win.Visible
		and (UIS:IsKeyDown(Enum.KeyCode.LeftControl)
			or UIS:IsKeyDown(Enum.KeyCode.RightControl)) then
		toggleSearch(true)
	elseif input.KeyCode == Enum.KeyCode.Escape then
		if menu.Visible then
			closeMenu()
		elseif emojiPop.Visible or gifPop.Visible or setPop.Visible then
			closePopups()
		elseif searchOpen then
			toggleSearch(false)
		end
	end
end)
refreshInput()

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
sys(toggleKey.Name .. " opens and closes the chat. Right-click a message to reply or react.")
