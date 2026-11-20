local search = {}

-- Only these asset configs expose an in-game name. Reuse a config when the
-- caller has already loaded it for the preview.
function search.displayName(kind, assetId, asset)
    if kind ~= "NPC" and kind ~= "Loc" and kind ~= "Obj" then return nil end
    asset = asset or config[kind].FromID(assetId)
    local name = asset and asset.name
    if type(name) == "string" and name:find("%S") and name:lower() ~= "null" then
        return name
    end
end
local ignoredObjPrefixes = { "CERT_", "BOUGHT_", "MARKETPLACE_STORE_", "LENT_", "MACRO_", }

local function matchesPrefix(name, prefixes)
    if prefixes then
        for _, prefix in ipairs(prefixes) do
            if name:sub(1, #prefix) == prefix then return true end
        end
    end
    return false
end

local function matchesGroup(name, group)
    if matchesPrefix(name, group.prefixes) then return true end
    if group.suffixes then
        for _, suffix in ipairs(group.suffixes) do
            if name:sub(-#suffix) == suffix then return true end
        end
    end
    if group.contains then
        for _, part in ipairs(group.contains) do
            if name:find(part, 1, true) then return true end
        end
    end
    if group.tokens then
        local delimitedName = "_" .. name .. "_"
        for _, token in ipairs(group.tokens) do
            if delimitedName:find("_" .. token .. "_", 1, true) then return true end
        end
    end
    return false
end

-- Unchecked groups take precedence. When Other is unchecked, only names
-- matching one of the remaining checked groups can pass.
function search.catalogFilter(hiddenGroups, requiredGroups)
    if #hiddenGroups == 0 and not requiredGroups then return nil end
    if requiredGroups and #requiredGroups == 0 then return function() return false end end
    return function(name)
        for _, group in ipairs(hiddenGroups) do
            if matchesGroup(name, group) then return false end
        end
        if not requiredGroups then return true end
        for _, group in ipairs(requiredGroups) do
            if matchesGroup(name, group) then return true end
        end
        return false
    end
end

-- Read names from the active client's ID table when a catalog is opened.
-- Report an unavailable table instead of showing an empty search list.
function search.load(kind)
    local names = { maxId = 0 }
    local count = 0
    local ok, reason = pcall(function()
        for key, value in pairs(id[kind]) do
            local number = type(value) == "number" and value or (type(key) == "number" and key)
            local name = type(key) == "number" and tostring(value) or tostring(key)
            local ignored = kind == "Obj" and matchesPrefix(name, ignoredObjPrefixes)
            if number and number >= 0 and not ignored then
                if not names[number] then count = count + 1 end
                names[number] = name
                names.maxId = math.max(names.maxId, number)
            end
        end
    end)
    if not ok then error("Cannot read client " .. kind .. " IDs: " .. tostring(reason), 2) end
    if count == 0 then error("The client returned no " .. kind .. " IDs.", 2) end
    names.count = count
    return names
end

-- The name tables are indexed by game IDs, including gaps.
function search.find(names, query)
    -- A number is an exact game ID. Missing IDs must not become a name search.
    local id = tonumber(query)
    if id and id % 1 == 0 then
        if names[id] then return { id } end
        return {}
    end

    -- Config names use underscores, but players may type spaces in the box.
    local term = query:match("^%s*(.-)%s*$"):upper():gsub("%s+", "_")
    local matches = {}
    for current = 0, names.maxId do
        local name = names[current]
        if name and (term == "" or name:find(term, 1, true)) then
            matches[#matches + 1] = current
        end
    end
    return matches
end

return search
