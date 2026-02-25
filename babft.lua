local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local VirtualUser = game:GetService("VirtualUser")
local TeleportService = game:GetService("TeleportService")
local HttpService = game:GetService("HttpService")

local lp = Players.LocalPlayer
local TWEEN_SPEED = 150
local WAIT_TIME = 1
local HOP_INTERVAL = 3600
local SCRIPT_URL = "https://raw.githubusercontent.com/0xF7A/lua/refs/heads/main/babft.lua"

local positions = {
    CFrame.new(-58.5114212, 95.066906, 307.004639, -0.999982238, -0.000746380421, 0.005914988, -7.38730321e-09, 0.992132723, 0.125190616, -0.00596189313, 0.125188395, -0.99211508),
    CFrame.new(-48.6776848, 96.3841629, 8765.58594, -0.998173952, -0.00652021728, 0.0600522645, -8.03571076e-09, 0.994157255, 0.107941195, -0.0604051948, 0.10774409, -0.992341876),
    CFrame.new(-57.0145874, -350.229797, 9494.09766, -0.999981821, -0.0019966762, 0.00568846054, -1.00978035e-08, 0.943562925, 0.331193238, -0.00602870621, 0.331187218, -0.943545818),
}

local startTime = os.clock()
local loopCount = 0

local LOG_LEVELS = { DEBUG = 1, INFO = 2, WARN = 3, ERROR = 4 }
local LOG_LEVEL = LOG_LEVELS.INFO
local LOG_PREFIX = "[BABFT]"

local function log(level, levelName, ...)
    if level < LOG_LEVEL then return end
    local t = string.format("%.1f", os.clock() - startTime)
    local msg = ""
    for i, v in {... } do
        msg ..= (i > 1 and " " or "") .. tostring(v)
    end
    print(LOG_PREFIX, "[" .. t .. "s]", "[" .. levelName .. "]", msg)
end

local function logDebug(...) log(LOG_LEVELS.DEBUG, "DBG", ...) end
local function logInfo(...)  log(LOG_LEVELS.INFO,  "INF", ...) end
local function logWarn(...)  log(LOG_LEVELS.WARN,  "WRN", ...) end
local function logError(...) log(LOG_LEVELS.ERROR, "ERR", ...) end

local function getRoot()
    local char = lp.Character
    return char and char:FindFirstChild("HumanoidRootPart")
end

logInfo("Script started")
logInfo("Tween speed:", TWEEN_SPEED, "| Wait:", WAIT_TIME, "| Hop interval:", HOP_INTERVAL)

lp.Idled:Connect(function()
    logDebug("Anti-AFK triggered (Idled)")
    VirtualUser:CaptureController()
    VirtualUser:ClickButton2(Vector2.new())
end)

task.spawn(function()
    while true do
        task.wait(60)
        pcall(function()
            logDebug("Anti-AFK heartbeat")
            VirtualUser:CaptureController()
            VirtualUser:ClickButton2(Vector2.new())
        end)
    end
end)

pcall(function()
    if queue_on_teleport and SCRIPT_URL ~= "" then
        lp.OnTeleport:Connect(function()
            queue_on_teleport('loadstring(game:HttpGet("' .. SCRIPT_URL .. '"))()')
            logInfo("Queued script for teleport reload:", SCRIPT_URL)
        end)
    else
        logWarn("No SCRIPT_URL set, queue_on_teleport skipped")
    end
end)

local function serverHop()
    logInfo("Server hop initiated...")
    local placeId = game.PlaceId
    local servers = {}

    pcall(function()
        local url = "https://games.roblox.com/v1/games/" .. placeId .. "/servers/Public?sortOrder=Asc&limit=100"
        local data = HttpService:JSONDecode(game:HttpGet(url))
        for _, server in data.data do
            if server.playing < server.maxPlayers and server.id ~= game.JobId then
                table.insert(servers, server.id)
            end
        end
    end)

    logInfo("Found", #servers, "available servers")
    if #servers > 0 then
        local jobId = servers[math.random(1, #servers)]
        logInfo("Hopping to server:", jobId)
        TeleportService:TeleportToPlaceInstance(placeId, jobId, lp)
    else
        logWarn("No servers found, rejoining same place")
        TeleportService:Teleport(placeId, lp)
    end
end

task.spawn(function()
    while true do
        task.wait(1)
        local remaining = HOP_INTERVAL - (os.clock() - startTime)
        if remaining <= 0 then
            serverHop()
            startTime = os.clock()
        elseif remaining <= 60 then
            logDebug("Server hop in", string.format("%.0f", remaining), "sec")
        end
    end
end)

local function tweenTo(cf, label)
    local root = getRoot()
    if not root then
        logWarn("tweenTo(" .. label .. "): no root, skipping")
        return
    end

    local dist = (root.Position - cf.Position).Magnitude
    logDebug("Tweening to", label, "| dist:", string.format("%.1f", dist))

    root.Anchored = true
    root.Velocity = Vector3.zero
    root.AssemblyLinearVelocity = Vector3.zero

    local startCF = root.CFrame
    local duration = math.max(dist / TWEEN_SPEED, 0.1)
    local elapsed = 0

    while elapsed < duration do
        local dt = RunService.RenderStepped:Wait()
        elapsed += dt
        local alpha = math.clamp(elapsed / duration, 0, 1)
        root = getRoot()
        if not root then
            logError("Lost root mid-tween to", label)
            return
        end
        root.Anchored = true
        root.Velocity = Vector3.zero
        root.AssemblyLinearVelocity = Vector3.zero
        root.CFrame = startCF:Lerp(cf, alpha)
        root.Anchored = false
    end

    root = getRoot()
    if root then
        root.Anchored = true
        root.CFrame = cf
        root.Anchored = false
    end
    logDebug("Arrived at", label)
end

logInfo("Entering main loop")
while task.wait() do
    local root = getRoot()
    if root then
        loopCount += 1
        logInfo("Loop #" .. loopCount, "started")

        tweenTo(positions[1], "pos1")
        task.wait(WAIT_TIME)

        tweenTo(positions[2], "pos2")
        task.wait(WAIT_TIME)

        tweenTo(positions[3], "pos3")
        task.wait(WAIT_TIME)

        logInfo("Unanchoring at pos3, waiting 7s...")
        root = getRoot()
        if root then
            root.Anchored = false
            root.Velocity = Vector3.zero
            root.AssemblyLinearVelocity = Vector3.zero
        end
        task.wait(7)

        logInfo("Breaking joints")
        lp.Character:BreakJoints()
        task.wait(15)

        logInfo("Teleporting back to pos1")
        root = getRoot()
        if root then
            root.CFrame = positions[1]
        end

        logInfo("Loop #" .. loopCount, "completed")
    else
        logWarn("No character, waiting 3s for respawn...")
        task.wait(3)
    end
end
