-- made with claude.

local SOURCE = [===[
local SELF_SOURCE = ...
if getgenv().RoChessFarm and getgenv().RoChessFarm.Stop then
    pcall(getgenv().RoChessFarm.Stop)
    task.wait(0.3)
end

local Configs = {
    AutoMove = false,
    AutoQueue = false,
    ShowArrow = true,
    ShowEval = true,
    ReExecute = true,
    AntiAfk = true,
    ThinkTime = 6,

    JitterPct = 0.25,
    LongThinkChance = 0.1,
    LongThinkExtra = {3, 6},
    PostMoveDelay = {0.4, 1.0},
    QueueDelay = {2, 5},
    DepthMain = 15,
    DepthFallback = 16,
    AntiAfkInterval = 240,
    Debug = true,
}

local function svc(name)
    local s = game:GetService(name)
    return (cloneref and cloneref(s)) or s
end

local HttpService = svc("HttpService")
local Players = svc("Players")
local VirtualUser = svc("VirtualUser")
local UIS = svc("UserInputService")
local LocalPlayer = Players.LocalPlayer

local httpRequest = request or http_request or (syn and syn.request) or (http and http.request)

local alive = true
local connections = {}
local guis = {}
local rng = Random.new()

local function log(...)
    if Configs.Debug then print("[RoChess]", ...) end
end

local function rand(a, b)
    return a + rng:NextNumber() * (b - a)
end

local function track(conn)
    table.insert(connections, conn)
    return conn
end

local SAVE_FILE = "RoChessFarm.json"
local SAVE_KEYS = {"AutoMove", "AutoQueue", "ShowArrow", "ShowEval", "ReExecute", "AntiAfk", "ThinkTime"}

local function loadSettings()
    if not (isfile and readfile) then return end
    pcall(function()
        if isfile(SAVE_FILE) then
            local data = HttpService:JSONDecode(readfile(SAVE_FILE))
            for _, k in ipairs(SAVE_KEYS) do
                if data[k] ~= nil and type(data[k]) == type(Configs[k]) then
                    Configs[k] = data[k]
                end
            end
        end
    end)
end

local function saveSettings()
    if not writefile then return end
    pcall(function()
        local out = {}
        for _, k in ipairs(SAVE_KEYS) do out[k] = Configs[k] end
        writefile(SAVE_FILE, HttpService:JSONEncode(out))
    end)
end

loadSettings()

local STOP_FLAG = "RoChessFarm_stop"
local queueTeleport = queue_on_teleport or queueonteleport
    or (syn and syn.queue_on_teleport) or (fluxus and fluxus.queue_on_teleport)
local reloadStatus = "starting"
local teleQueued = false

local function setStopFlag(on)
    if not (writefile and isfile) then return end
    pcall(function()
        if on then
            writefile(STOP_FLAG, "1")
        elseif isfile(STOP_FLAG) and delfile then
            delfile(STOP_FLAG)
        end
    end)
end

local function buildReloader()
    if type(SELF_SOURCE) ~= "string" then return nil end
    return string.format(
        "if not game:IsLoaded() then game.Loaded:Wait() end\n"
        .. "if game.GameId ~= %d then return end\n"
        .. "if getgenv().RoChessFarm then return end\n"
        .. "if isfile and isfile(%q) then return end\n"
        .. "local S = %s\nloadstring(S)(S)\n",
        game.GameId, STOP_FLAG, string.format("%q", SELF_SOURCE))
end

local function queueReload()
    if not Configs.ReExecute then
        reloadStatus = "off"
        return
    end
    if not queueTeleport then
        reloadStatus = "executor has no queue_on_teleport"
        return
    end
    local code = buildReloader()
    if not code then
        reloadStatus = "needs the full script file"
        return
    end
    if pcall(queueTeleport, code) then
        reloadStatus = "armed"
    else
        reloadStatus = "queue failed"
    end
end

setStopFlag(false)
queueReload()

track(LocalPlayer.OnTeleport:Connect(function(state)
    log("teleport state: " .. tostring(state))
    if state == Enum.TeleportState.Failed then
        teleQueued = false
        return
    end
    if not teleQueued and (state == Enum.TeleportState.RequestedFromServer or state == Enum.TeleportState.Started) then
        teleQueued = true
        queueReload()
    end
end))

local function pingAfk()
    pcall(function()
        VirtualUser:CaptureController()
        VirtualUser:ClickButton2(Vector2.new(rng:NextInteger(0, 50), rng:NextInteger(0, 50)))
    end)
end

if getconnections then
    pcall(function()
        for _, c in ipairs(getconnections(LocalPlayer.Idled)) do
            if c.Disable then c:Disable() end
        end
    end)
end

track(LocalPlayer.Idled:Connect(function()
    if Configs.AntiAfk then pingAfk() end
end))

task.spawn(function()
    while alive do
        task.wait(Configs.AntiAfkInterval + rand(-20, 20))
        if alive and Configs.AntiAfk then pingAfk() end
    end
end)

local function urlEncode(s) return HttpService:UrlEncode(tostring(s)) end

local function httpGet(url)
    if not httpRequest then return nil end
    local ok, res = pcall(httpRequest, {
        Url = url,
        Method = "GET",
        Headers = {
            ["User-Agent"] = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36",
            ["Accept"] = "application/json",
        },
    })
    if ok and res and (res.Success or res.StatusCode == 200) then return res.Body end
    return nil
end

local function httpPost(url, tbl)
    if not httpRequest then return nil end
    local ok, res = pcall(httpRequest, {
        Url = url,
        Method = "POST",
        Headers = { ["Content-Type"] = "application/json", ["User-Agent"] = "Mozilla/5.0" },
        Body = HttpService:JSONEncode(tbl),
    })
    if ok and res and (res.Success or res.StatusCode == 200) then return res.Body end
    return nil
end

local function decode(body)
    if not body then return nil end
    local ok, data = pcall(function() return HttpService:JSONDecode(body) end)
    if ok then return data end
    return nil
end

local function extractUci(text)
    if type(text) ~= "string" then return nil end
    text = string.lower(text)
    local m = text:match("bestmove%s+([a-h][1-8][a-h][1-8][qrbn]?)")
    if m then return m end
    return text:match("([a-h][1-8][a-h][1-8][qrbn]?)")
end

local Engines = {
    function(fen)
        local url = "https://stockfish.online/api/s/v2.php?fen=" .. urlEncode(fen)
            .. "&depth=" .. math.min(Configs.DepthMain, 15)
        local data = decode(httpGet(url))
        if data and data.success and data.bestmove then
            return extractUci(data.bestmove), tonumber(data.evaluation), tonumber(data.mate)
        end
    end,
    function(fen)
        local data = decode(httpPost("https://chess-api.com/v1", { fen = fen, depth = Configs.DepthFallback }))
        if data then
            local mv
            if data.move then
                mv = extractUci(data.move)
            elseif data.from and data.to then
                mv = extractUci(data.from .. data.to .. (data.promotion or ""))
            end
            if mv then return mv, tonumber(data.eval), tonumber(data.mate) end
        end
    end,
    function(fen)
        local data = decode(httpGet("https://lichess.org/api/cloud-eval?multiPv=1&fen=" .. urlEncode(fen)))
        local pv = data and data.pvs and data.pvs[1]
        if pv and pv.moves then
            return extractUci(pv.moves), pv.cp and (pv.cp / 100) or nil, tonumber(pv.mate)
        end
    end,
}

local engineOffset = 0

local function CalculateBestMove(fen)
    if not fen or fen == "" then return nil end
    for i = 0, #Engines - 1 do
        local idx = ((engineOffset + i) % #Engines) + 1
        local ok, move, ev, mate = pcall(Engines[idx], fen)
        if ok and move then return move, idx, ev, mate end
    end
    return nil
end

local cachedClient

local function ChessClient()
    if cachedClient and cachedClient.debug and cachedClient.inLiveGame then return cachedClient end
    cachedClient = nil
    local ok, found = pcall(function()
        return filtergc("table", {
            Keys = {"serverNow", "send", "build", "handlers", "debug", "start", "setSession"},
        }, true)
    end)
    if ok and found then cachedClient = found end
    return cachedClient
end

local function ChessSession()
    local client = ChessClient()
    return client and client.session or nil
end

local function InGame()
    local client = ChessClient()
    if not client then return nil end
    local ok, res = pcall(function() return client:inLiveGame() end)
    if ok then return res end
    return nil
end

local function OurTurn()
    local session = ChessSession()
    if not session then return false end
    local ok, res = pcall(function() return session:isMyTurn() end)
    return ok and res == true
end

local function GetFen()
    local session = ChessSession()
    if not session or not session.engine then return nil end
    local ok, fen = pcall(function() return session.engine:getFen() end)
    if ok then return fen end
    return nil
end

local function MoveChessPiece(uci)
    if not uci then return false end
    local client = ChessClient()
    if not client or not client.debug then return false end
    local ok, moved = pcall(function() return client.debug({ ["type"] = "move", uci = uci }) end)
    if ok and moved then
        log("moved: " .. uci)
        return true
    end
    log("move rejected: " .. uci)
    return false
end

local function FindMatch()
    local client = ChessClient()
    if not client or not client.debug then return end
    if client.searching or client.joining then return end
    local ok, err = pcall(function() client.debug({ ["type"] = "search" }) end)
    if ok then log("searching...") else log("search failed: " .. tostring(err)) end
end

local S = {
    status = "Starting...",
    best = nil,
    evalUs = nil,
    mateUs = nil,
    engine = nil,
    boardMode = "not found",
}

local function getGuiParent()
    if gethui then
        local ok, h = pcall(gethui)
        if ok and h then return h end
    end
    local ok, cg = pcall(function() return svc("CoreGui") end)
    if ok and cg then return cg end
    return LocalPlayer:WaitForChild("PlayerGui")
end

local function new(class, props, parent)
    local inst = Instance.new(class)
    for k, v in pairs(props) do inst[k] = v end
    inst.Parent = parent
    return inst
end

local function makeScreenGui(name, order)
    local g = Instance.new("ScreenGui")
    g.Name = name
    g.ResetOnSpawn = false
    g.IgnoreGuiInset = true
    g.DisplayOrder = order
    g.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    if syn and syn.protect_gui then pcall(syn.protect_gui, g) end
    g.Parent = getGuiParent()
    table.insert(guis, g)
    return g
end

local C = {
    win = Color3.fromRGB(15, 15, 18),
    title = Color3.fromRGB(41, 74, 122),
    frame = Color3.fromRGB(32, 44, 64),
    frameHover = Color3.fromRGB(45, 70, 105),
    check = Color3.fromRGB(66, 150, 250),
    grab = Color3.fromRGB(61, 133, 224),
    text = Color3.fromRGB(235, 235, 235),
    dim = Color3.fromRGB(150, 150, 160),
    sep = Color3.fromRGB(70, 70, 82),
    border = Color3.fromRGB(110, 110, 128),
}
local FONT = Enum.Font.Code

local function isPress(i)
    return i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch
end
local function isMove(i)
    return i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch
end

local arrowGui = makeScreenGui("RoChessArrows", 999990)
local arrowLayer = new("Frame", {
    Name = "Layer", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Active = false,
}, arrowGui)

local holder = new("Frame", {
    Name = "Holder", BackgroundTransparency = 1, Active = false, Visible = false,
}, arrowLayer)
local markLayer = new("Frame", {
    Name = "Marks", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Active = false,
}, holder)

local arrowGroup = new("CanvasGroup", {
    Name = "Arrow", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1,
    GroupTransparency = 0.25, Active = false,
}, holder)

local ARROW_COLOR = Color3.fromRGB(60, 220, 120)
local FROM_COLOR = Color3.fromRGB(240, 210, 60)

local BOARD_KEYS = {"frame", "flipped", "sqPx", "arrowLayer", "pieceLayer", "squares"}
local boardObj
local frameCache
local lastDetect = 0
local lastScan = 0

local function validBoard(b)
    if type(b) ~= "table" then return false end
    local ok, res = pcall(function()
        return typeof(b.frame) == "Instance" and b.frame.Parent ~= nil and b.frame:IsDescendantOf(game)
    end)
    return ok and res == true
end

local function findBoardObject()
    if not filtergc then return nil, "no filtergc" end
    local ok, res = pcall(filtergc, "table", { Keys = BOARD_KEYS }, false)
    if not ok then return nil, "filtergc error" end
    local list = {}
    if type(res) == "table" then
        if res.frame ~= nil then list[1] = res else list = res end
    end
    local best, bestSize
    for _, b in ipairs(list) do
        if validBoard(b) then
            local okv, size = pcall(function()
                return b.frame.Visible and b.frame.AbsoluteSize.X or -1
            end)
            size = okv and size or -1
            if not best or size > bestSize then best, bestSize = b, size end
        end
    end
    return best, "filtergc matches: " .. #list
end

local function findBoardFrame()
    if frameCache and frameCache.Parent then return frameCache end
    frameCache = nil
    if os.clock() - lastScan < 2 then return nil end
    lastScan = os.clock()
    local pg = LocalPlayer:FindFirstChildOfClass("PlayerGui")
    if not pg then return nil end
    local ui = pg:FindFirstChild("ChessUI")
    local root = ui and ui:FindFirstChild("Root")
    local f = root and root:FindFirstChild("Board")
    if not f then
        for _, d in ipairs(pg:GetDescendants()) do
            if d.Name == "Board" and d:IsA("Frame") and d:FindFirstChild("Squares") and d:FindFirstChild("Pieces") then
                f = d
                break
            end
        end
    end
    if f and f:IsA("GuiObject") then
        frameCache = f
        return f
    end
    return nil
end

local function frameFlipped(frame)
    local coords = frame:FindFirstChild("Coords")
    local f1 = coords and coords:FindFirstChild("File1")
    return (f1 and f1:IsA("TextLabel") and f1.Text == "h") or false
end

local function getBoard()
    if boardObj and not validBoard(boardObj) then boardObj = nil end
    if not boardObj and os.clock() - lastDetect > 2 then
        lastDetect = os.clock()
        local info
        boardObj, info = findBoardObject()
        S.boardInfo = info
    end
    if boardObj then
        S.boardMode = "native"
        return boardObj.frame, boardObj.flipped == true
    end
    local f = findBoardFrame()
    if f then
        S.boardMode = "frame"
        return f, frameFlipped(f)
    end
    S.boardMode = "not found"
    return nil
end

task.spawn(function()
    local last
    while alive do
        pcall(getBoard)
        if S.boardMode ~= last then
            last = S.boardMode
            log("board: " .. tostring(last), S.boardInfo or "")
        end
        task.wait(1)
    end
end)

local arrowKey
local function clearArrow()
    markLayer:ClearAllChildren()
    arrowGroup:ClearAllChildren()
    holder.Visible = false
    arrowKey = nil
end

local function bar(p1, p2, thick)
    local d = p2 - p1
    local len = d.Magnitude
    if len < 0.5 then return end
    local mid = (p1 + p2) / 2
    local f = new("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromOffset(mid.X, mid.Y),
        Size = UDim2.fromOffset(len, thick),
        Rotation = math.deg(math.atan2(d.Y, d.X)),
        BackgroundColor3 = ARROW_COLOR,
        BorderSizePixel = 0,
        Active = false,
    }, arrowGroup)
    new("UICorner", { CornerRadius = UDim.new(0.5, 0) }, f)
end

local function head(tip, u, length, width)
    local ang = math.deg(math.atan2(u.Y, u.X))
    local slices = 14
    local base = tip - u * length
    for i = 0, slices - 1 do
        local t = (i + 0.5) / slices
        local c = base + u * (length * t)
        new("Frame", {
            AnchorPoint = Vector2.new(0.5, 0.5),
            Position = UDim2.fromOffset(c.X, c.Y),
            Size = UDim2.fromOffset(length / slices + 1.5, math.max(width * (1 - t), 1)),
            Rotation = ang,
            BackgroundColor3 = ARROW_COLOR,
            BorderSizePixel = 0,
            Active = false,
        }, arrowGroup)
    end
end

local function mark(center, sq, color)
    new("Frame", {
        Position = UDim2.fromOffset(center.X - sq / 2, center.Y - sq / 2),
        Size = UDim2.fromOffset(sq, sq),
        BackgroundColor3 = color,
        BackgroundTransparency = 0.55,
        BorderSizePixel = 0,
        Active = false,
    }, markLayer)
end

local function drawArrow(uci)
    local frame, flipped = getBoard()
    if not frame then clearArrow() return end

    local gui = frame:FindFirstAncestorOfClass("ScreenGui")
    local size = frame.AbsoluteSize.X
    if not frame.Visible or size <= 0 or (gui and not gui.Enabled) then
        clearArrow()
        return
    end

    local pos = frame.AbsolutePosition - arrowLayer.AbsolutePosition

    local key = string.format("%s|%.1f|%.1f|%.1f|%s", uci, pos.X, pos.Y, size, tostring(flipped))
    if key == arrowKey then return end
    arrowKey = key

    markLayer:ClearAllChildren()
    arrowGroup:ClearAllChildren()
    holder.Position = UDim2.fromOffset(pos.X, pos.Y)
    holder.Size = UDim2.fromOffset(size, size)
    holder.Visible = true

    local sq = size / 8

    local function center(s)
        local file = string.byte(s, 1) - 97
        local rank = (tonumber(s:sub(2, 2)) or 1) - 1
        local col = flipped and (7 - file) or file
        local row = flipped and rank or (7 - rank)
        return Vector2.new((col + 0.5) * sq, (row + 0.5) * sq)
    end

    local a, b = center(uci:sub(1, 2)), center(uci:sub(3, 4))
    mark(a, sq, FROM_COLOR)
    mark(b, sq, ARROW_COLOR)

    local d = b - a
    if d.Magnitude < 1 then return end

    local thick = math.max(5, sq * 0.2)
    local headLen = sq * 0.5
    local headWid = sq * 0.66
    local startPad = sq * 0.2

    local dx, dy = math.floor(math.abs(d.X) / sq + 0.5), math.floor(math.abs(d.Y) / sq + 0.5)
    local corner
    if (dx == 1 and dy == 2) or (dx == 2 and dy == 1) then
        corner = (dx < dy) and Vector2.new(a.X, b.Y) or Vector2.new(b.X, a.Y)
    end

    local lastFrom = corner or a
    local u2 = (b - lastFrom).Unit
    local tip = b - u2 * (sq * 0.06)
    local headBase = tip - u2 * headLen
    local shaftEnd = headBase + u2 * (headLen * 0.2)

    if corner then
        local u1v = (corner - a).Unit
        bar(a + u1v * startPad, corner, thick)
        bar(corner, shaftEnd, thick)
    else
        bar(a + u2 * startPad, shaftEnd, thick)
    end
    head(tip, u2, headLen, headWid)
end

task.spawn(function()
    while alive do
        if Configs.ShowArrow and S.best then
            pcall(drawArrow, S.best)
        elseif arrowKey or holder.Visible then
            clearArrow()
        end
        task.wait(0.1)
    end
end)

local uiGui = makeScreenGui("RoChessUI", 999999)

local window = new("Frame", {
    Name = "Window",
    Position = UDim2.fromOffset(20, 90),
    Size = UDim2.fromOffset(300, 0),
    AutomaticSize = Enum.AutomaticSize.Y,
    BackgroundColor3 = C.win,
    BorderSizePixel = 0,
}, uiGui)
new("UIStroke", { Color = C.border, Transparency = 0.5, Thickness = 1 }, window)
new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder }, window)

local titleBar = new("Frame", {
    Size = UDim2.new(1, 0, 0, 26), BackgroundColor3 = C.title, BorderSizePixel = 0, LayoutOrder = 1,
}, window)
new("TextLabel", {
    Text = "RoChess AutoFarm v3.2", Font = FONT, TextSize = 15, TextColor3 = C.text,
    BackgroundTransparency = 1, Position = UDim2.fromOffset(10, 0), Size = UDim2.new(1, -40, 1, 0),
    TextXAlignment = Enum.TextXAlignment.Left,
}, titleBar)
local collapseBtn = new("TextButton", {
    Text = "-", Font = FONT, TextSize = 18, TextColor3 = C.text, BackgroundTransparency = 1,
    Size = UDim2.fromOffset(26, 26), Position = UDim2.new(1, -26, 0, 0),
}, titleBar)

local body = new("Frame", {
    Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
    BackgroundTransparency = 1, LayoutOrder = 2,
}, window)
new("UIPadding", {
    PaddingTop = UDim.new(0, 8), PaddingBottom = UDim.new(0, 8),
    PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8),
}, body)
new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 6) }, body)

collapseBtn.Activated:Connect(function()
    body.Visible = not body.Visible
    collapseBtn.Text = body.Visible and "-" or "+"
end)

do
    local dragging, startPos, startUi = false, nil, nil
    titleBar.InputBegan:Connect(function(i)
        if isPress(i) then
            dragging, startPos, startUi = true, i.Position, window.Position
        end
    end)
    track(UIS.InputEnded:Connect(function(i)
        if isPress(i) then dragging = false end
    end))
    track(UIS.InputChanged:Connect(function(i)
        if dragging and isMove(i) then
            local d = i.Position - startPos
            window.Position = UDim2.new(startUi.X.Scale, startUi.X.Offset + d.X, startUi.Y.Scale, startUi.Y.Offset + d.Y)
        end
    end))
end

local order = 0
local function nextOrder() order = order + 1 return order end

local function addLabel(text, color, wrap)
    return new("TextLabel", {
        Text = text, Font = FONT, TextSize = 14, TextColor3 = color or C.text,
        BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 16),
        AutomaticSize = Enum.AutomaticSize.Y, TextWrapped = wrap or false,
        TextXAlignment = Enum.TextXAlignment.Left, LayoutOrder = nextOrder(),
    }, body)
end

local function addSeparator()
    new("Frame", { Size = UDim2.new(1, 0, 0, 1), BackgroundColor3 = C.sep, BorderSizePixel = 0, LayoutOrder = nextOrder() }, body)
end

local function addCheckbox(text, key, onChange)
    local row = new("TextButton", {
        Text = "", AutoButtonColor = false, Size = UDim2.new(1, 0, 0, 22),
        BackgroundTransparency = 1, LayoutOrder = nextOrder(),
    }, body)
    local box = new("Frame", {
        Size = UDim2.fromOffset(18, 18), Position = UDim2.new(0, 0, 0.5, -9),
        BackgroundColor3 = C.frame, BorderSizePixel = 0,
    }, row)
    local mark = new("Frame", {
        Size = UDim2.fromOffset(10, 10), Position = UDim2.fromOffset(4, 4),
        BackgroundColor3 = C.check, BorderSizePixel = 0, Visible = Configs[key],
    }, box)
    new("TextLabel", {
        Text = text, Font = FONT, TextSize = 14, TextColor3 = C.text, BackgroundTransparency = 1,
        Position = UDim2.fromOffset(26, 0), Size = UDim2.new(1, -26, 1, 0),
        TextXAlignment = Enum.TextXAlignment.Left,
    }, row)
    row.MouseEnter:Connect(function() box.BackgroundColor3 = C.frameHover end)
    row.MouseLeave:Connect(function() box.BackgroundColor3 = C.frame end)
    row.Activated:Connect(function()
        Configs[key] = not Configs[key]
        mark.Visible = Configs[key]
        saveSettings()
        if onChange then onChange(Configs[key]) end
    end)
end

local function addSlider(text, key, min, max, fmt)
    local row = new("TextButton", {
        Text = "", AutoButtonColor = false, Size = UDim2.new(1, 0, 0, 24),
        BackgroundColor3 = C.frame, BorderSizePixel = 0, LayoutOrder = nextOrder(),
    }, body)
    local grab = new("Frame", {
        Size = UDim2.new(0, 12, 1, -4), AnchorPoint = Vector2.new(0, 0.5),
        BackgroundColor3 = C.grab, BorderSizePixel = 0,
    }, row)
    local lbl = new("TextLabel", {
        Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Font = FONT, TextSize = 14,
        TextColor3 = C.text, ZIndex = 2,
    }, row)

    local function refresh()
        local v = Configs[key]
        local pct = (v - min) / (max - min)
        grab.Position = UDim2.new(pct, -12 * pct, 0.5, 0)
        lbl.Text = text .. ": " .. string.format(fmt, v)
    end
    refresh()

    local dragging = false
    local function setFromX(x)
        local w = math.max(1, row.AbsoluteSize.X - 12)
        local pct = math.clamp((x - row.AbsolutePosition.X - 6) / w, 0, 1)
        Configs[key] = math.floor((min + pct * (max - min)) * 10 + 0.5) / 10
        refresh()
    end
    row.InputBegan:Connect(function(i)
        if isPress(i) then dragging = true setFromX(i.Position.X) end
    end)
    track(UIS.InputEnded:Connect(function(i)
        if isPress(i) and dragging then dragging = false saveSettings() end
    end))
    track(UIS.InputChanged:Connect(function(i)
        if dragging and isMove(i) then setFromX(i.Position.X) end
    end))
end

local function addButton(text, cb)
    local b = new("TextButton", {
        Text = text, Font = FONT, TextSize = 14, TextColor3 = C.text, BackgroundColor3 = C.frame,
        BorderSizePixel = 0, AutoButtonColor = false, Size = UDim2.new(1, 0, 0, 24), LayoutOrder = nextOrder(),
    }, body)
    b.MouseEnter:Connect(function() b.BackgroundColor3 = C.frameHover end)
    b.MouseLeave:Connect(function() b.BackgroundColor3 = C.frame end)
    b.Activated:Connect(cb)
    return b
end

local statusLabel = addLabel("Status: starting...", C.text, true)
local paceLabel = addLabel("", C.dim, true)

local evalRow = new("Frame", {
    Size = UDim2.new(1, 0, 0, 22), BackgroundColor3 = Color3.fromRGB(190, 65, 65),
    BorderSizePixel = 0, LayoutOrder = nextOrder(),
}, body)
local evalFill = new("Frame", {
    Size = UDim2.fromScale(0.5, 1), BackgroundColor3 = Color3.fromRGB(55, 175, 105), BorderSizePixel = 0,
}, evalRow)
local evalLabel = new("TextLabel", {
    Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Font = FONT, TextSize = 13,
    TextColor3 = Color3.new(1, 1, 1), TextStrokeTransparency = 0.45, ZIndex = 2,
    Text = "Eval: waiting for your turn",
}, evalRow)

local function winPct(ev, mate)
    if mate then return mate > 0 and 100 or 0 end
    if not ev then return 50 end
    return 50 + 50 * (2 / (1 + math.exp(-0.368 * ev)) - 1)
end

local function evalText(ev, mate)
    if mate then
        if mate > 0 then return string.format("WINNING - you mate in %d", math.abs(mate)) end
        return string.format("LOSING - mated in %d", math.abs(mate))
    end
    if not ev then return "Eval: waiting for your turn" end
    local word = ev >= 3 and "WINNING BIG" or ev >= 0.8 and "Winning"
        or ev <= -3 and "LOSING BADLY" or ev <= -0.8 and "Losing" or "Equal"
    return string.format("%s  %+.1f", word, ev)
end
addSeparator()
addCheckbox("Auto Move", "AutoMove")
addSlider("Think time", "ThinkTime", 0.5, 15, "%.1fs")
addCheckbox("Best Move Arrow", "ShowArrow")
addCheckbox("Show Eval (winning/losing)", "ShowEval")
addCheckbox("Auto Queue", "AutoQueue")
addCheckbox("Anti-AFK", "AntiAfk")
addCheckbox("Re-execute on server move", "ReExecute", function(on)
    setStopFlag(not on)
    if on then queueReload() else reloadStatus = "off" end
end)
local reloadLabel = addLabel("", C.dim, true)
addSeparator()
local boardLabel = addLabel("Board: not found", C.dim, true)
addButton("Re-detect board", function()
    boardObj = nil
    frameCache = nil
    lastDetect = 0
    lastScan = 0
    arrowKey = nil
end)
addSeparator()
local isMobile = UIS.TouchEnabled and not UIS.KeyboardEnabled
addLabel(isMobile and "RC button = hide or show" or "RightShift = hide or show", C.dim, true)

local function Stop()
    alive = false
    setStopFlag(true)
    for _, c in ipairs(connections) do pcall(function() c:Disconnect() end) end
    table.clear(connections)
    for _, g in ipairs(guis) do pcall(function() g:Destroy() end) end
    table.clear(guis)
    log("stopped")
end

addButton("Unload script", Stop)

local toggleBtn = new("TextButton", {
    Text = "RC", Font = FONT, TextSize = 14, TextColor3 = C.text, BackgroundColor3 = C.title,
    BorderSizePixel = 0, Size = UDim2.fromOffset(36, 36), Position = UDim2.new(0, 6, 0.5, -18),
}, uiGui)
toggleBtn.Visible = isMobile
toggleBtn.Activated:Connect(function() window.Visible = not window.Visible end)
track(UIS.InputBegan:Connect(function(i, gp)
    if not gp and i.KeyCode == Enum.KeyCode.RightShift then window.Visible = not window.Visible end
end))

task.spawn(function()
    while alive do
        statusLabel.Text = "Status: " .. S.status
        boardLabel.Text = "Board: " .. S.boardMode .. (S.boardMode == "not found" and S.boardInfo and (" (" .. S.boardInfo .. ")") or "")
        evalRow.Visible = Configs.ShowEval
        reloadLabel.Text = "Re-execute: " .. (Configs.ReExecute and reloadStatus or "off")
        if Configs.ShowEval then
            evalLabel.Text = evalText(S.evalUs, S.mateUs)
            evalFill.Size = UDim2.fromScale(winPct(S.evalUs, S.mateUs) / 100, 1)
        end
        local t = Configs.ThinkTime
        paceLabel.Text = t < 2.5 and "Pace: fast (more noticeable)" or (t < 4.5 and "Pace: medium" or "Pace: slow (natural)")
        task.wait(0.15)
    end
end)

task.spawn(function()
    local turnFen, turnStart, jitter, extra, failed = nil, 0, 0, 0, 0
    local lastAuto = Configs.AutoMove
    local lastFetch = 0
    local queuedAt = 0

    while alive do

        if Configs.AutoMove and not lastAuto then turnStart = os.clock() end
        lastAuto = Configs.AutoMove

        local inGame = InGame()

        if inGame then
            queuedAt = 0
            if OurTurn() then
                local fen = GetFen()
                if fen then
                    if fen ~= turnFen then
                        turnFen = fen
                        turnStart = os.clock()
                        S.best = nil
                        failed = 0
                        jitter = rng:NextNumber() * 2 - 1
                        extra = (rng:NextNumber() < Configs.LongThinkChance)
                            and rand(Configs.LongThinkExtra[1], Configs.LongThinkExtra[2]) or 0
                    end

                    if not S.best and (Configs.AutoMove or Configs.ShowArrow or Configs.ShowEval) and os.clock() - lastFetch > 1 then
                        S.status = "Calculating..."
                        local mv, eng, ev, mt = CalculateBestMove(fen)
                        lastFetch = os.clock()
                        if mv and GetFen() == fen then
                            S.best, S.engine = mv, eng

                            local us = (fen:match("^%S+%s+([wb])") == "b") and -1 or 1
                            S.evalUs = ev and ev * us or nil
                            S.mateUs = mt and mt * us or nil
                        end
                    end

                    if S.best then
                        if Configs.AutoMove then
                            local target = turnStart + math.max(0.5, Configs.ThinkTime * (1 + jitter * Configs.JitterPct) + extra)
                            local left = target - os.clock()
                            if left > 0 then
                                S.status = string.format("Thinking... %.1fs (%s)", left, S.best)
                            elseif OurTurn() and GetFen() == fen then
                                if MoveChessPiece(S.best) then
                                    S.status = "Moved " .. S.best
                                    S.best = nil
                                    turnFen = nil
                                    task.wait(rand(Configs.PostMoveDelay[1], Configs.PostMoveDelay[2]))
                                else
                                    failed = failed + 1
                                    engineOffset = engineOffset + 1
                                    S.best = nil
                                    S.status = "Move failed, retrying (" .. failed .. ")"
                                    task.wait(failed >= 3 and 3 or 1)
                                end
                            end
                        else
                            S.status = "Best move: " .. S.best .. " (Auto Move off)"
                        end
                    elseif not (Configs.AutoMove or Configs.ShowArrow or Configs.ShowEval) then
                        S.status = "Idle (everything is off)"
                    end
                else
                    task.wait(0.4)
                end
            else
                S.best = nil
                turnFen = nil
                S.status = "Opponent's turn"
            end
            task.wait(0.15)
        elseif inGame == false then
            S.best = nil
            S.evalUs = nil
            S.mateUs = nil
            turnFen = nil
            if Configs.AutoQueue then
                if queuedAt == 0 then
                    queuedAt = os.clock() + rand(Configs.QueueDelay[1], Configs.QueueDelay[2])
                    S.status = "Queueing soon..."
                elseif os.clock() >= queuedAt then
                    FindMatch()
                    queuedAt = os.clock() + 4
                    S.status = "Searching for a match..."
                end
            else
                queuedAt = 0
                S.status = "Not in a game"
            end
            task.wait(0.5)
        else
            S.status = "Looking for chess client..."
            task.wait(1)
        end
    end
end)

getgenv().RoChessFarm = { Stop = Stop, Configs = Configs, State = S }
log("RoChess AutoFarm v3.2 loaded. Stop with getgenv().RoChessFarm.Stop()")
]===]
loadstring(SOURCE)(SOURCE)
