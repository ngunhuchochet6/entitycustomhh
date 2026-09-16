-- Additional help: @ActualMasterOogway (Remastered for Cross-Platform, Update Resilience & Debugging)

-- \\ Services // --
local MarketplaceService = game:GetService("MarketplaceService")
local HttpService = game:GetService("HttpService")

-- \\ Executor Function Fallbacks // --
-- Ensures compatibility with strict sandboxes on Mobile and PC
local req = (request or http and http.request or http_request)
local is_file = isfile or function() return false end
local read_file = readfile or function() return "" end
local write_file = writefile or function() end
local del_file = delfile or function() end
local get_custom_asset = getcustomasset or getsynasset

-- \\ Variables // --
local Module = {}

-- \\ Helper Functions // --

-- Universal HTTP Get that works even if game:HttpGet is blocked/patched
local function SafeHttpGet(url: string): string
    local success, result = pcall(function()
        if type(game.HttpGet) == "function" then
            return game:HttpGet(url)
        elseif req then
            local response = req({Url = url, Method = "GET"})
            if response.Success then return response.Body end
        end
        error("No valid HTTP function found")
    end)
    if not success then error("HTTP Request failed for: " .. url .. "\nError: " .. tostring(result)) end
    return result
end

-- Safely converts timestamps, preventing crashes on invalid strings
local function timestampToMillis(timestamp: any): number
    if type(timestamp) == "number" then return timestamp end
    if type(timestamp) == "string" then
        local dt = DateTime.fromIsoDate(timestamp)
        return dt and dt.UnixTimestampMillis or 0
    end
    if typeof(timestamp) == "DateTime" then
        return timestamp.UnixTimestampMillis
    end
    return 0
end

-- \\ Main Module // --

Module.Require = function(s: string): any?
    local content = s
    if s:lower():sub(1, 4) == "http" then
        content = SafeHttpGet(s)
    elseif is_file(s) then
        content = read_file(s)
    end

    -- 1. Check for syntax errors when loading
    local func, err = loadstring(content, s) -- Passes the URL/Path as the chunk name for better error logs
    if not func then
        error(debug.traceback("Syntax Error in loaded module:\n" .. s .. "\nError: " .. tostring(err)))
    end
    
    -- 2. Catch RUNTIME errors (like the "missing method 'create'" error) and force a full trace
    local success, result = xpcall(func, function(runtimeErr)
        return "[RUNTIME ERROR] inside loaded module: " .. s .. "\n" .. 
               "Message: " .. tostring(runtimeErr) .. "\n" .. 
               "Traceback: \n" .. debug.traceback()
    end)
    
    if not success then
        error(result) -- This will print EXACTLY what script and line is failing
    end
    
    return result
end

Module.LoadCustomAsset = function(url: string): string?
    if get_custom_asset then
        if url:lower():sub(1, 4) == "http" then
            -- Fix for Mobile: Files must have valid extensions for custom assets to render properly
            local extension = url:match("%.(%w+)$") or url:match("%.(%w+)%?") or "bin"
            local fileName = `temp_{HttpService:GenerateGUID(false)}.{extension}`
            
            local success, result = pcall(function()
                write_file(fileName, SafeHttpGet(url))
                return get_custom_asset(fileName, true)
            end)
            
            -- Cleanup
            if is_file(fileName) then
                pcall(del_file, fileName)
            end
            
            if success and result then return result end
        elseif is_file(url) then
            local success, result = pcall(get_custom_asset, url, true)
            if success and result then return result end
        end
    else
        warn("[Warning]: Executor lacks 'getcustomasset'. Defaulting to rbxassetid.")
    end
    
    -- Fallback to asset id
    if url:find("rbxassetid") or tonumber(url) then
        return "rbxassetid://" .. url:match("%d+")
    end
    
    warn("[Warning]: Failed to load custom asset, returning empty string to prevent crash.")
    return ""
end

Module.LoadCustomInstance = function(url: string): Instance?
    -- Note: game:GetObjects() is frequently patched by Roblox. Pcall is mandatory here.
    local success, result = pcall(function()
        local asset = Module.LoadCustomAsset(url)
        if asset and asset ~= "" then
            return game:GetObjects(asset)[1]
        end
    end)
    if not success then
        warn("[Warning]: game:GetObjects failed. This is likely patched by Roblox or unsupported by your executor.")
    end
    return success and result or nil
end

Module.GetGameLastUpdate = function(): DateTime
    -- Added pcall because MarketplaceService yields and can fail if Roblox API is down
    local success, result = pcall(function()
        return MarketplaceService:GetProductInfo(game.PlaceId).Updated
    end)
    return success and DateTime.fromIsoDate(result) or DateTime.now()
end

Module.HasGameUpdated = function(timestamp: any): boolean
    local millis = timestampToMillis(timestamp)
    if millis > 0 then
        return millis < Module.GetGameLastUpdate().UnixTimestampMillis
    end
    return false
end

Module.GetGitLastUpdate = function(owner: string, repo: string, filePath: string): DateTime
    local url = `https://api.github.com/repos/{owner}/{repo}/commits?per_page=1&path={filePath}`
    
    -- Fix for GitHub API Rate Limiting (60 requests/hr).
    local success, result = pcall(function()
        return HttpService:JSONDecode(SafeHttpGet(url))
    end)
    
    if success and type(result) == "table" and result[1] and result[1].commit then
        return DateTime.fromIsoDate(result[1].commit.committer.date)
    else
        warn(`[Warning]: Failed to fetch Git update. You are likely rate-limited by GitHub API.`)
        return DateTime.now() -- Returns current time to prevent crashes
    end
end

Module.HasGitUpdated = function(owner: string, repo: string, filePath: string, timestamp: any): boolean
    local millis = timestampToMillis(timestamp)
    if millis > 0 then
        return millis < Module.GetGitLastUpdate(owner, repo, filePath).UnixTimestampMillis
    end
    return false
end

Module.TruncateNumber = function(num: number, decimals: number): number
    local shift = 10 ^ (decimals and math.max(decimals, 0) or 0)
    return math.floor(num * shift) / shift
end

-- \\ Global Implementation // --

local genv = getgenv and getgenv() or _G
for name, func in next, Module do
    if type(func) == "function" then
        genv[name] = func
    end
end

return Modulelocal function timestampToMillis(timestamp: any): number
    if type(timestamp) == "number" then return timestamp end
    if type(timestamp) == "string" then
        local dt = DateTime.fromIsoDate(timestamp)
        return dt and dt.UnixTimestampMillis or 0
    end
    if typeof(timestamp) == "DateTime" then
        return timestamp.UnixTimestampMillis
    end
    return 0
end

-- \\ Main Module // --

Module.Require = function(s: string): any?
    local content = s
    if s:lower():sub(1, 4) == "http" then
        content = SafeHttpGet(s)
    elseif is_file(s) then
        content = read_file(s)
    end

    local func, err = loadstring(content)
    if not func then
        error(debug.traceback("Failed to load module:\n" .. s .. "\nError: " .. tostring(err)))
    end
    return func()
end

Module.LoadCustomAsset = function(url: string): string?
    if get_custom_asset then
        if url:lower():sub(1, 4) == "http" then
            -- Fix for Mobile: Files must have valid extensions (not .txt) for custom assets to render properly
            local extension = url:match("%.(%w+)$") or url:match("%.(%w+)%?") or "bin"
            local fileName = `temp_{HttpService:GenerateGUID(false)}.{extension}`
            
            local success, result = pcall(function()
                write_file(fileName, SafeHttpGet(url))
                return get_custom_asset(fileName, true)
            end)
            
            -- Cleanup
            if is_file(fileName) then
                pcall(del_file, fileName)
            end
            
            if success and result then return result end
        elseif is_file(url) then
            local success, result = pcall(get_custom_asset, url, true)
            if success and result then return result end
        end
    else
        warn("[Warning]: Executor lacks 'getcustomasset'. Defaulting to rbxassetid.")
    end
    
    -- Fallback to asset id
    if url:find("rbxassetid") or tonumber(url) then
        return "rbxassetid://" .. url:match("%d+")
    end
    
    warn("[Warning]: Failed to load custom asset, returning empty string to prevent crash.")
    return ""
end

Module.LoadCustomInstance = function(url: string): Instance?
    -- Note: game:GetObjects() is frequently patched by Roblox. 
    -- Pcall is mandatory here to prevent execution halting.
    local success, result = pcall(function()
        local asset = Module.LoadCustomAsset(url)
        if asset and asset ~= "" then
            return game:GetObjects(asset)[1]
        end
    end)
    if not success then
        warn("[Warning]: game:GetObjects failed. This is likely patched by Roblox or unsupported by your executor.")
    end
    return success and result or nil
end

Module.GetGameLastUpdate = function(): DateTime
    -- Added pcall because MarketplaceService yields and can fail if Roblox API is down
    local success, result = pcall(function()
        return MarketplaceService:GetProductInfo(game.PlaceId).Updated
    end)
    return success and DateTime.fromIsoDate(result) or DateTime.now()
end

Module.HasGameUpdated = function(timestamp: any): boolean
    local millis = timestampToMillis(timestamp)
    if millis > 0 then
        return millis < Module.GetGameLastUpdate().UnixTimestampMillis
    end
    return false
end

Module.GetGitLastUpdate = function(owner: string, repo: string, filePath: string): DateTime
    local url = `https://api.github.com/repos/{owner}/{repo}/commits?per_page=1&path={filePath}`
    
    -- Fix for GitHub API Rate Limiting (60 requests/hr). 
    -- Without this check, result[1] throws a nil error and breaks the script.
    local success, result = pcall(function()
        return HttpService:JSONDecode(SafeHttpGet(url))
    end)
    
    if success and type(result) == "table" and result[1] and result[1].commit then
        return DateTime.fromIsoDate(result[1].commit.committer.date)
    else
        warn(`[Warning]: Failed to fetch Git update. You are likely rate-limited by GitHub API. Url: {url}`)
        return DateTime.now() -- Returns current time to prevent crashes
    end
end

Module.HasGitUpdated = function(owner: string, repo: string, filePath: string, timestamp: any): boolean
    local millis = timestampToMillis(timestamp)
    if millis > 0 then
        return millis < Module.GetGitLastUpdate(owner, repo, filePath).UnixTimestampMillis
    end
    return false
end

Module.TruncateNumber = function(num: number, decimals: number): number
    local shift = 10 ^ (decimals and math.max(decimals, 0) or 0)
    return math.floor(num * shift) / shift
end

-- \\ Global Implementation // --

local genv = getgenv and getgenv() or _G
for name, func in next, Module do
    if type(func) == "function" then
        genv[name] = func
    end
end

return Module
