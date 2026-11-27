
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local LocalPlayer = Players.LocalPlayer
local SpreadPatch = setmetatable({}, {__mode = "k"})
local LastPatchScan = 0
local HUGE_SPREAD = 1e9
local Enabled = true

local function GetStates(tool)
    local module = tool:FindFirstChild("GunStates")
    if not module then return nil end

    local ok, states = pcall(require, module)

    if ok and type(states) == "table" then
        return states
    end

    return nil
end

local function FindCreateRay(tool)
    local candidates = {}

    local ok, found = pcall(function()
        return filtergc("function", {Name = "createRay"}, false)
    end)

    if ok and type(found) == "table" then
        candidates = found
    end

    if #candidates == 0 and getgc then
        local okG, gc = pcall(getgc, false)

        if okG and gc then
            for _, f in ipairs(gc) do
                if type(f) == "function" and not iscclosure(f) then
                    local okN, name = pcall(debug.info, f, "n")

                    if okN and name == "createRay" then
                        candidates[#candidates + 1] = f
                    end
                end
            end
        end
    end

    for _, f in ipairs(candidates) do
        local okE, env = pcall(getfenv, f)
        local scr = okE and type(env) == "table"
            and rawget(env, "script")

        if scr and typeof(scr) == "Instance"
            and scr.Parent == tool then
            return f
        end
    end

    return nil
end

local function SetSpread(tool, states, on)
    local entry = SpreadPatch[tool]

    if on then
        if entry == nil then
            if os.clock() - LastPatchScan < 1 then
                return
            end

            LastPatchScan = os.clock()

            local fn = FindCreateRay(tool)
            if not fn then return end

            local ups = debug.getupvalues(fn)
            local index

            for i, v in pairs(ups) do
                if type(v) == "number"
                    and v == states.Spread then
                    index = i
                    break
                end
            end

            if not index then
                SpreadPatch[tool] = false
                return
            end

            SpreadPatch[tool] = {
                fn = fn,
                index = index,
                original = ups[index]
            }

            entry = SpreadPatch[tool]
        end

        if entry then
            local cur = debug.getupvalue(
                entry.fn,
                entry.index
            )

            if cur ~= HUGE_SPREAD then
                debug.setupvalue(
                    entry.fn,
                    entry.index,
                    HUGE_SPREAD
                )
            end
        end

    elseif entry then
        pcall(
            debug.setupvalue,
            entry.fn,
            entry.index,
            entry.original
        )
    end
end

local Connection = RunService.RenderStepped:Connect(function()
    if not Enabled then return end

    local backpack = LocalPlayer:FindFirstChildOfClass("Backpack")

    for _, holder in ipairs({
        backpack,
        LocalPlayer.Character
    }) do
        if holder then
            for _, tool in ipairs(holder:GetChildren()) do
                if tool:IsA("Tool") then
                    local states = GetStates(tool)

                    if states then
                        pcall(SetSpread, tool, states, true)
                    end
                end
            end
        end
    end
end)

-- Unload and restore original spread
getgenv().UnloadNoSpread = function()
    Enabled = false

    if Connection then
        Connection:Disconnect()
        Connection = nil
    end

    for tool, entry in pairs(SpreadPatch) do
        if entry then
            pcall(function()
                SetSpread(tool, nil, false)
            end)
        end
    end

    table.clear(SpreadPatch)
end
