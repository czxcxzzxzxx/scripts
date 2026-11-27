local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local LocalPlayer = Players.LocalPlayer

local Enabled = true
local Last = 0
local Connection

local function FillStamina()
    local char = LocalPlayer.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")

    local gui = LocalPlayer:FindFirstChild("PlayerGui")
    local home = gui and gui:FindFirstChild("Home")
    local hud = home and home:FindFirstChild("hud")
    local bar = hud and hud:FindFirstChild("StaminaFrame")

    if not hum or not bar then return end

    local current = math.floor(bar.Size.X.Scale * 12 + 0.5)

    for _, signal in ipairs({hum.Jumping, hum.Changed}) do
        local ok, conns = pcall(getconnections, signal)

        if ok and type(conns) == "table" then
            for _, conn in ipairs(conns) do
                local fn = conn.Function

                if type(fn) == "function" and not iscclosure(fn) then
                    local okU, ups = pcall(debug.getupvalues, fn)

                    if okU and type(ups) == "table" then
                        for index, value in pairs(ups) do
                            if type(value) == "number"
                                and value >= 0
                                and value <= 12
                                and value == current then

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

Connection = RunService.Heartbeat:Connect(function()
    if not Enabled then return end
    if os.clock() - Last < 0.2 then return end

    Last = os.clock()
    pcall(FillStamina)
end)

-- Unload
getgenv().UnloadStamina = function()
    Enabled = false

    if Connection then
        Connection:Disconnect()
        Connection = nil
    end
end
