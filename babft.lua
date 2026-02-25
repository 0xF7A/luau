local Players        = game:GetService("Players")
local RunService     = game:GetService("RunService")
local TeleportService = game:GetService("TeleportService")
local HttpService    = game:GetService("HttpService")
local VirtualUser    = game:GetService("VirtualUser")

local CONFIG = {
    TWEEN_SPEED   = 100,
    WAIT_TIME     = 1,
    RESPAWN_WAIT  = 5,
    DEATH_WAIT    = 15,
    UNANCHOR_WAIT = 10,
    HOP_INTERVAL  = 3600,
    SCRIPT_URL    = "https://raw.githubusercontent.com/0xF7A/lua/refs/heads/main/babft.lua",
    LOG_LEVEL     = 2,
}

local POSITIONS = {
    CFrame.new(-58.5114212,  95.066906,  307.004639,
        -0.999982238, -0.000746380421, 0.005914988,
        -7.38730321e-09, 0.992132723, 0.125190616,
        -0.00596189313, 0.125188395, -0.99211508),

    CFrame.new(-48.6776848,  96.3841629, 8765.58594,
        -0.998173952, -0.00652021728, 0.0600522645,
        -8.03571076e-09, 0.994157255, 0.107941195,
        -0.0604051948, 0.10774409, -0.992341876),

    CFrame.new(-57.0145874, -350.229797, 9494.09766,
        -0.999981821, -0.0019966762, 0.00568846054,
        -1.00978035e-08, 0.943562925, 0.331193238,
        -0.00602870621, 0.331187218, -0.943545818),
}

local startTime  = os.clock()
local loopCount  = 0
local LOG_PREFIX = "[BABFT]"

local function log(level, tag, ...)
    if level < CONFIG.LOG_LEVEL then return end
    local parts = { LOG_PREFIX, string.format("[%.1fs]", os.clock() - startTime), "[" .. tag .. "]" }
    for _, v in { ... } do
        parts[#parts + 1] = tostring(v)
    end
    print(table.concat(parts, " "))
end

local logD = function(...) log(1, "DBG", ...) end
local logI = function(...) log(2, "INF", ...) end
local logW = function(...) log(3, "WRN", ...) end
local logE = function(...) log(4, "ERR", ...) end

if not game:IsLoaded() then
    logI("Waiting for game to load...")
    game.Loaded:Wait()
end

local lp = Players.LocalPlayer
if not lp then
    logI("Waiting for LocalPlayer...")
    lp = Players:GetPropertyChangedSignal("LocalPlayer"):Wait()
    lp = Players.LocalPlayer
end

logI("LocalPlayer:", lp.Name)

local function getRoot()
    local char = lp.Character
    return char and char:FindFirstChild("HumanoidRootPart")
end

local function getHumanoid()
    local char = lp.Character
    return char and char:FindFirstChildOfClass("Humanoid")
end

local function zeroVelocity(root)
    root.AssemblyLinearVelocity  = Vector3.zero
    root.AssemblyAngularVelocity = Vector3.zero
end

pcall(function()
    lp.Idled:Connect(function()
        logD("Anti-AFK: Idled fired")
        VirtualUser:CaptureController()
        VirtualUser:ClickButton2(Vector2.zero)
    end)
    logI("Anti-AFK enabled")
end)

pcall(function()
    if queue_on_teleport and CONFIG.SCRIPT_URL ~= "" then
        lp.OnTeleport:Connect(function(state)
            queue_on_teleport(('loadstring(game:HttpGet(%q))()'):format(CONFIG.SCRIPT_URL))
            logI("Queued script for teleport reload")
        end)
    else
        logW("queue_on_teleport unavailable or SCRIPT_URL empty, skipping")
    end
end)

local function serverHop()
    logI("Server hop initiated...")
    local placeId = game.PlaceId
    local servers = {}

    pcall(function()
        local url = ("https://games.roblox.com/v1/games/%d/servers/Public?sortOrder=Asc&limit=100"):format(placeId)
        local ok, result = pcall(HttpService.JSONDecode, HttpService, game:HttpGet(url))
        if not ok or not result or not result.data then
            logW("Failed to parse server list")
            return
        end
        for _, server in result.data do
            if server.id ~= game.JobId and server.playing < server.maxPlayers then
                servers[#servers + 1] = server.id
            end
        end
    end)

    logI("Found", #servers, "candidate servers")

    if #servers > 0 then
        local jobId = servers[math.random(1, #servers)]
        logI("Hopping to:", jobId)
        TeleportService:TeleportToPlaceInstance(placeId, jobId, lp)
    else
        logW("No candidate servers found — rejoining same place")
        TeleportService:Teleport(placeId, lp)
    end
end

task.spawn(function()
    local hopTimer = os.clock()
    while true do
        task.wait(1)
        local elapsed = os.clock() - hopTimer
        local remaining = CONFIG.HOP_INTERVAL - elapsed

        if remaining <= 0 then
            serverHop()
            hopTimer = os.clock()
        elseif remaining <= 60 then
            logD("Server hop in", math.ceil(remaining), "sec")
        end
    end
end)

local function tweenTo(targetCF, label)
    local root = getRoot()
    if not root then
        logW("tweenTo(" .. label .. "): no HumanoidRootPart, skipping")
        return
    end

    local dist     = (root.Position - targetCF.Position).Magnitude
    local duration = math.max(dist / CONFIG.TWEEN_SPEED, 0.05)
    local startCF  = root.CFrame
    local elapsed  = 0

    logD("Tweening to", label, "| dist:", math.round(dist), "| eta:", string.format("%.2fs", duration))

    while elapsed < duration do
        local dt = RunService.Heartbeat:Wait()
        elapsed += dt

        root = getRoot()
        if not root then
            logE("Lost root mid-tween to", label)
            return
        end

        local alpha = math.clamp(elapsed / duration, 0, 1)
        root.Anchored = true
        zeroVelocity(root)
        root.CFrame = startCF:Lerp(targetCF, alpha)
    end

    root = getRoot()
    if root then
        root.CFrame   = targetCF
        root.Anchored = false
        zeroVelocity(root)
    end

    logD("Arrived at", label)
end

logI("Entering main loop")

while true do
    task.wait()

    local root = getRoot()
    if not root then
        logW("No character — waiting", CONFIG.RESPAWN_WAIT, "s for respawn...")
        task.wait(CONFIG.RESPAWN_WAIT)
        continue
    end

    loopCount += 1
    logI("Loop #" .. loopCount .. " started")

    tweenTo(POSITIONS[1], "pos1")
    task.wait(CONFIG.WAIT_TIME)

    tweenTo(POSITIONS[2], "pos2")
    task.wait(CONFIG.WAIT_TIME)

    tweenTo(POSITIONS[3], "pos3")
    task.wait(CONFIG.WAIT_TIME)

    root = getRoot()
    if root then
        logI("Unanchoring at pos3, waiting", CONFIG.UNANCHOR_WAIT, "s...")
        root.Anchored = false
        zeroVelocity(root)
    end
    task.wait(CONFIG.UNANCHOR_WAIT)

    local hum = getHumanoid()
    if hum then
        logI("Killing character via Humanoid.Health")
        hum.Health = 0
    else
        logW("No Humanoid found for kill step")
    end

    logI("Waiting", CONFIG.DEATH_WAIT, "s for respawn...")
    task.wait(CONFIG.DEATH_WAIT)

    logI("Loop #" .. loopCount .. " complete")
end
