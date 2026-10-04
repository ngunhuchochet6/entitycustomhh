--[[
    Utility Module
    Reworked for compatibility / capability detection.

    Original helper:
        @ActualMasterOogway

    Notes:
        - Does not assume executor-specific APIs exist.
        - Uses GetProductInfoAsync when available.
        - Keeps compatibility with older environments where possible.
        - Filesystem/custom-asset features gracefully report missing capabilities.
]]

--// Services //--

local MarketplaceService = game:GetService("MarketplaceService")
local HttpService = game:GetService("HttpService")

--// Module //--

local Module = {}

--// Capability Helpers //--

local function hasGlobal(name)
    return type(getfenv) == "function" and getfenv()[name] ~= nil
        or _G[name] ~= nil
end

local function getGlobal(name)
    local value

    pcall(function()
        if type(getfenv) == "function" then
            value = getfenv()[name]
        end
    end)

    if value == nil then
        value = _G[name]
    end

    return value
end

local function isCallable(value)
    return type(value) == "function"
end

local function isString(value)
    return type(value) == "string"
end

local function isNumber(value)
    return type(value) == "number"
end

local function isHttpUrl(value)
    return isString(value)
        and value:lower():match("^https?://") ~= nil
end

local function getFileApi()
    return {
        isfile = getGlobal("isfile"),
        readfile = getGlobal("readfile"),
        writefile = getGlobal("writefile"),
        delfile = getGlobal("delfile"),
    }
end

local function httpGet(url)
    if not isHttpUrl(url) then
        return nil, "Invalid HTTP URL"
    end

    -- Executor-provided game:HttpGet
    local gameHttpGet

    pcall(function()
        gameHttpGet = game.HttpGet
    end)

    if isCallable(gameHttpGet) then
        local success, result = pcall(function()
            return game:HttpGet(url)
        end)

        if success and isString(result) then
            return result
        end
    end

    -- Standard Roblox HttpService fallback.
    local success, result = pcall(function()
        return HttpService:GetAsync(url)
    end)

    if success and isString(result) then
        return result
    end

    return nil, tostring(result)
end

--// Timestamp //--

local function timestampToMillis(timestamp)
    local valueType = typeof(timestamp)

    if valueType == "DateTime" then
        return timestamp.UnixTimestampMillis
    end

    if valueType == "number" then
        return timestamp
    end

    if valueType == "string" then
        local success, result = pcall(function()
            return DateTime.fromIsoDate(timestamp).UnixTimestampMillis
        end)

        if success then
            return result
        end
    end

    return nil
end

--// Require //--

Module.Require = function(source)
    assert(
        isString(source),
        "Module.Require expected a string"
    )

    local content = source

    -- Remote source
    if isHttpUrl(source) then
        local result, err = httpGet(source)

        if not result then
            error(
                "Failed to download module:\n"
                .. source
                .. "\nError: "
                .. tostring(err),
                2
            )
        end

        content = result

    -- Local file
    else
        local fs = getFileApi()

        if isCallable(fs.isfile)
            and isCallable(fs.readfile)
            and fs.isfile(source)
        then
            local success, result = pcall(function()
                return fs.readfile(source)
            end)

            if not success then
                error(
                    "Failed to read module file:\n"
                    .. source
                    .. "\nError: "
                    .. tostring(result),
                    2
                )
            end

            content = result
        end
    end

    local loader = getGlobal("loadstring")

    if not isCallable(loader) then
        loader = loadstring
    end

    if not isCallable(loader) then
        error(
            "loadstring is unavailable in this environment.",
            2
        )
    end

    local success, func, err = pcall(function()
        return loader(
            content,
            "@" .. tostring(source)
        )
    end)

    if not success then
        error(
            "Failed to compile module:\n"
            .. tostring(source)
            .. "\nError: "
            .. tostring(func),
            2
        )
    end

    if not func then
        error(
            "Failed to compile module:\n"
            .. tostring(source)
            .. "\nError: "
            .. tostring(err),
            2
        )
    end

    local executed, result = pcall(func)

    if not executed then
        error(
            "Failed to execute module:\n"
            .. tostring(source)
            .. "\nError: "
            .. tostring(result),
            2
        )
    end

    return result
end

--// Load Custom Asset //--

Module.LoadCustomAsset = function(url)
    assert(
        isString(url),
        "LoadCustomAsset expected a string"
    )

    local customAsset = getGlobal("getcustomasset")

    -- Executor custom asset support
    if isCallable(customAsset) then

        -- Remote asset
        if isHttpUrl(url) then
            local fs = getFileApi()

            if not (
                isCallable(fs.writefile)
                and isCallable(fs.isfile)
            ) then
                warn(
                    "getcustomasset exists, but filesystem APIs "
                    .. "needed for remote assets are unavailable."
                )
            else
                local fileName =
                    "temp_asset_" ..
                    tostring(math.floor(os.clock() * 1000000)) ..
                    ".tmp"

                local content, err = httpGet(url)

                if not content then
                    error(
                        "Failed to download custom asset:\n"
                        .. url
                        .. "\nError: "
                        .. tostring(err),
                        2
                    )
                end

                local success, result = pcall(function()
                    fs.writefile(fileName, content)
                    return customAsset(fileName, true)
                end)

                if isCallable(fs.isfile)
                    and fs.isfile(fileName)
                    and isCallable(fs.delfile)
                then
                    pcall(function()
                        fs.delfile(fileName)
                    end)
                end

                if success and result then
                    return result
                end

                warn(
                    "getcustomasset failed for:\n"
                    .. url
                )
            end

        -- Existing local file
        else
            local fs = getFileApi()

            if isCallable(fs.isfile)
                and fs.isfile(url)
            then
                local success, result = pcall(function()
                    return customAsset(url, true)
                end)

                if success and result then
                    return result
                end
            end
        end
    end

    -- Standard Roblox asset ID fallback
    local assetId = url:match("rbxassetid://(%d+)")
        or url:match("(%d+)")

    if assetId then
        return "rbxassetid://" .. assetId
    end

    error(
        "Unable to load custom asset:\n"
        .. tostring(url)
        .. "\nNo compatible asset loader was found.",
        2
    )
end

--// Load Custom Instance //--

Module.LoadCustomInstance = function(url)
    local success, result = pcall(function()
        local asset = Module.LoadCustomAsset(url)

        local objects = game:GetObjects(asset)

        if type(objects) ~= "table" then
            return nil
        end

        return objects[1]
    end)

    if success then
        return result
    end

    warn(
        "LoadCustomInstance failed:\n"
        .. tostring(result)
    )

    return nil
end

--// Game Update //--

Module.GetGameLastUpdate = function()
    local success, info = pcall(function()
        -- Prefer modern API
        if MarketplaceService.GetProductInfoAsync then
            return MarketplaceService:GetProductInfoAsync(
                game.PlaceId
            )
        end

        -- Compatibility fallback
        return MarketplaceService:GetProductInfo(
            game.PlaceId
        )
    end)

    if not success or type(info) ~= "table" then
        error(
            "Failed to retrieve game information:\n"
            .. tostring(info),
            2
        )
    end

    if not info.Updated then
        error(
            "Game information does not contain an Updated timestamp.",
            2
        )
    end

    local successDate, date = pcall(function()
        return DateTime.fromIsoDate(info.Updated)
    end)

    if not successDate then
        error(
            "Failed to parse game Updated timestamp:\n"
            .. tostring(date),
            2
        )
    end

    return date
end

Module.HasGameUpdated = function(timestamp)
    local millis = timestampToMillis(timestamp)

    if not millis then
        return false
    end

    local success, lastUpdate = pcall(
        Module.GetGameLastUpdate
    )

    if not success or not lastUpdate then
        return false
    end

    return millis < lastUpdate.UnixTimestampMillis
end

--// GitHub Update //--

Module.GetGitLastUpdate = function(owner, repo, filePath)
    assert(
        isString(owner) and owner ~= "",
        "owner must be a non-empty string"
    )

    assert(
        isString(repo) and repo ~= "",
        "repo must be a non-empty string"
    )

    assert(
        isString(filePath) and filePath ~= "",
        "filePath must be a non-empty string"
    )

    local url =
        "https://api.github.com/repos/"
        .. owner
        .. "/"
        .. repo
        .. "/commits?per_page=1&path="
        .. HttpService:UrlEncode(filePath)

    local body, err = httpGet(url)

    if not body then
        error(
            "Failed to get GitHub commit:\n"
            .. url
            .. "\nError: "
            .. tostring(err),
            2
        )
    end

    local success, result = pcall(function()
        return HttpService:JSONDecode(body)
    end)

    if not success then
        error(
            "Failed to decode GitHub response:\n"
            .. tostring(result),
            2
        )
    end

    if type(result) ~= "table"
        or type(result[1]) ~= "table"
        or type(result[1].commit) ~= "table"
        or type(result[1].commit.committer) ~= "table"
        or not result[1].commit.committer.date
    then
        error(
            "GitHub returned an unexpected response for:\n"
            .. url,
            2
        )
    end

    local dateString =
        result[1].commit.committer.date

    local successDate, date = pcall(function()
        return DateTime.fromIsoDate(dateString)
    end)

    if not successDate then
        error(
            "Failed to parse GitHub timestamp:\n"
            .. tostring(date),
            2
        )
    end

    return date
end

Module.HasGitUpdated = function(
    owner,
    repo,
    filePath,
    timestamp
)
    local millis = timestampToMillis(timestamp)

    if not millis then
        return false
    end

    local success, lastUpdate = pcall(function()
        return Module.GetGitLastUpdate(
            owner,
            repo,
            filePath
        )
    end)

    if not success or not lastUpdate then
        return false
    end

    return millis < lastUpdate.UnixTimestampMillis
end

--// Number Utilities //--

Module.TruncateNumber = function(
    num,
    decimals
)
    assert(
        isNumber(num),
        "num must be a number"
    )

    decimals = isNumber(decimals)
        and math.max(0, math.floor(decimals))
        or 0

    local multiplier = 10 ^ decimals

    return math.floor(num * multiplier)
        / multiplier
end

--// Optional Global Export //--

local getgenvFunction = getGlobal("getgenv")

if isCallable(getgenvFunction) then
    local success, globalEnv = pcall(getgenvFunction)

    if success and type(globalEnv) == "table" then
        for name, value in pairs(Module) do
            if type(value) == "function" then
                globalEnv[name] = value
            end
        end
    end
end

return Module
