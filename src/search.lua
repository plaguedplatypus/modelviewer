local search = {}

-- Read names from the active client's ID table when a catalog is opened.
-- Report an unavailable table instead of showing an empty search list.
function search.load(kind)
    local names = { maxId = 0 }
    local count = 0
    local ok, reason = pcall(function()
        for key, value in pairs(id[kind]) do
            local number = type(value) == "number" and value or (type(key) == "number" and key)
            local name = type(key) == "number" and tostring(value) or tostring(key)
            if number and number >= 0 then
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
