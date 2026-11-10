local search = {}

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
