local search = require("src/search")
local catalogCategories = require("src/catalogCategories")

local modelSearch = {}
local catalogBatchSize = 3000
local locBatchSize = 100

-- Return callbacks to refresh highlighting and replace the catalog.
-- Replacing the catalog keeps the query without applying a matching result.
-- acceptsLoc is optional and filters Loc IDs to shapes with a model.
function modelSearch.create(parent, options)
    local kind, names = options.kind, options.names
    local selected, getSelected = options.select, options.getSelected
    local setStatus, acceptsLoc = options.setStatus, options.acceptsLoc
    local label, field, button = options.label, options.field, options.button
    local groups = catalogCategories[kind]
    local includeName
    local y = groups and 41 or 5
    local pageX = options.caption and 112 or 74
    label(parent, options.caption or kind, 12, y, pageX - 12, 0xF3C971FF)
    local pageText = label(parent, "", pageX, y, 178 - pageX)
    local input = field(parent, "", 12, y + 24, 218)
    input.emptyText = "ID or name"

    -- Native lists keep selected rows, which prevents selecting the same NPC
    -- or Seq again. Reuse a few clickable rows and scroll their contents.
    local listTop = y + 62
    local panel = ui.Layer.new(parent)
    panel:SetPos(12, listTop)
    panel:SetSize(296, -listTop, 0, 1)
    panel.clickthrough = false
    local background = ui.Rectangle.new(panel)
    background:SetSize(0, 0, 1, 1)
    background.fill = true
    background.rgba = 0x1B1917FF
    background.clickthrough = false

    local rowHeight = 20
    local visibleRows = 0
    local rows = {}
    local displayNames = {}
    local matches = {}
    local filtering = false
    local page = 1
    -- Paging avoids creating a UI component for every entry in a large catalog.
    local pageSize = 500
    local first, last = 1, 0
    local offset = 1
    local thumbHeight = 16
    local renderRows

    local function scrollBy(delta)
        local count = last - first + 1
        local maxOffset = math.max(1, count - visibleRows + 1)
        offset = math.max(1, math.min(maxOffset, offset + delta * 3))
        renderRows()
        return false
    end

    background:Subscribe(ui.Hook.ONSCROLLWHEEL, function(_, delta)
        return scrollBy(delta)
    end)

    local function addRow(index)
        local row = ui.Layer.new(panel)
        row:SetPos(4, 4 + (index - 1) * rowHeight)
        row:SetSize(276, rowHeight)
        row.clickthrough = false
        local shade = ui.Rectangle.new(row)
        shade:SetSize(276, rowHeight)
        shade.fill = true
        shade.rgba = 0x282521FF
        shade.clickthrough = true
        local text = label(row, "", 5, 0, 266)
        rows[index] = { root = row, shade = shade, text = text }
        row:Subscribe(ui.Hook.ONCLICK, function()
            local matchId = rows[index].id
            if matchId then
                selected(matchId)
                renderRows()
            end
            return false
        end)
        row:Subscribe(ui.Hook.ONSCROLLWHEEL, function(_, delta)
            return scrollBy(delta)
        end)
        row:Subscribe(ui.Hook.ONMOUSEOVER, function()
            shade.rgba = rows[index].isSelected and 0x806538FF or 0x494039FF
        end)
        row:Subscribe(ui.Hook.ONMOUSELEAVE, function()
            shade.rgba = rows[index].isSelected and 0x66502DFF or 0x282521FF
        end)
    end

    local track = ui.Layer.new(panel)
    track:SetPos(283, 4)
    track:SetSize(9, -8, 0, 1)
    track.clickthrough = false
    local trackFill = ui.Rectangle.new(track)
    trackFill:SetSize(0, 0, 1, 1)
    trackFill.fill = true
    trackFill.rgba = 0x383127FF
    trackFill.clickthrough = true
    local thumb = ui.Rectangle.new(track)
    thumb:SetSize(9, thumbHeight)
    thumb.fill = true
    thumb.rgba = 0xCDA753FF
    thumb.clickthrough = false

    -- Refill the visible rows as the page scrolls. Reusing row components also
    -- avoids the native List selection state that blocked repeated clicks.
    renderRows = function()
        local count = last - first + 1
        local maxOffset = math.max(1, count - visibleRows + 1)
        offset = math.min(offset, maxOffset)
        local selectedId = getSelected()
        for index, row in ipairs(rows) do
            local resultIndex = first + offset + index - 2
            row.id = index <= visibleRows and resultIndex <= last and matches[resultIndex] or nil
            row.root.hidden = row.id == nil
            row.isSelected = row.id ~= nil and row.id == selectedId
            row.shade.rgba = row.isSelected and 0x66502DFF or 0x282521FF
            row.text.rgba = row.isSelected and 0xF3C971FF or 0xE8DDC7FF
            if row.id then
                local displayName = displayNames[row.id]
                if displayName == nil then
                    displayName = search.displayName(kind, row.id) or names[row.id]
                    displayNames[row.id] = displayName
                end
                row.text.content = row.id .. "  " .. displayName
            end
        end
        track.hidden = visibleRows == 0 or count <= visibleRows
        if not track.hidden then
            local trackHeight = panel.height - 8
            thumbHeight = math.max(14, math.floor(trackHeight * visibleRows / count))
            thumb:SetSize(9, thumbHeight)
            thumb:SetPos(0, math.floor((offset - 1) * (trackHeight - thumbHeight) / (maxOffset - 1)))
        end
    end

    local function resizeRows()
        visibleRows = math.max(0, math.floor((panel.height - 8) / rowHeight))
        for index = #rows + 1, visibleRows do addRow(index) end
        renderRows()
    end

    -- The scrollbar covers the current page; Prev and Next reach other pages.
    local function jumpTo(yPos)
        local count = last - first + 1
        local maxOffset = math.max(1, count - visibleRows + 1)
        if maxOffset > 1 then
            local travel = panel.height - 8 - thumbHeight
            if travel <= 0 then return false end
            local ratio = math.max(0, math.min(1, (yPos - thumbHeight / 2) / travel))
            offset = 1 + math.floor(ratio * (maxOffset - 1) + 0.5)
            renderRows()
        end
        return false
    end

    track:Subscribe(ui.Hook.ONCLICK, function(_, _, clickY)
        return jumpTo(clickY)
    end)
    track:Subscribe(ui.Hook.ONHOLD, function(_, _, holdY)
        return jumpTo(holdY)
    end)
    track:Subscribe(ui.Hook.ONSCROLLWHEEL, function(_, delta)
        return scrollBy(delta)
    end)
    thumb:Subscribe(ui.Hook.ONCLICK, function(_, _, clickY)
        return jumpTo(thumb.y + clickY)
    end)
    thumb:Subscribe(ui.Hook.ONHOLD, function(_, _, holdY)
        return jumpTo(thumb.y + holdY)
    end)
    thumb:Subscribe(ui.Hook.ONSCROLLWHEEL, function(_, delta)
        return scrollBy(delta)
    end)

    local border = ui.Rectangle.new(panel)
    border:SetSize(0, 0, 1, 1)
    border.fill = false
    border.outlineThickness = 1
    border.rgba = 0x665B4DFF
    border.clickthrough = true

    local function showPage(keepScroll, quiet)
        local pageCount = math.max(1, math.ceil(#matches / pageSize))
        pageText.content = page .. " / " .. (filtering and "..." or pageCount)
        first = (page - 1) * pageSize + 1
        last = math.min(first + pageSize - 1, #matches)
        if not keepScroll then offset = 1 end
        renderRows()
        if quiet then return end
        local source = (names.source or "Client catalog") .. ": " .. names.count .. ". "
        if filtering then
            local action = acceptsLoc and "Checking Locs for models" or "Applying filters"
            setStatus(source .. action .. ": " .. #matches .. " found so far.")
        elseif #matches == 0 then
            local hint = includeName and "Check the filters or change the search."
                or "Try an exact ID or part of a name."
            setStatus(source .. "No " .. kind .. " matches. " .. hint)
        else
            setStatus(source .. kind .. " results " .. first .. "-" .. last .. " of " .. #matches
                .. ". Scroll or use Prev / Next.")
        end
    end

    local function runSearch(autoSelect, quiet)
        if filtering then panel:Unsubscribe(ui.Hook.ONTIMER) end
        filtering = false
        local candidates = search.find(names, input.content)
        matches = candidates
        if acceptsLoc or includeName then
            local nameFilter = includeName
            local batchSize = acceptsLoc and locBatchSize or catalogBatchSize
            matches = {}
            local function appendMatches(firstIndex, lastIndex)
                for index = firstIndex, lastIndex do
                    local assetId = candidates[index]
                    if (not acceptsLoc or acceptsLoc(assetId)) and (not nameFilter or nameFilter(names[assetId])) then
                        matches[#matches + 1] = assetId
                    end
                end
            end
            if #candidates > batchSize then
                -- Keep large catalog scans within the client's Lua time limit.
                filtering = true
                local nextIndex = 1
                panel:Subscribe(ui.Hook.ONTIMER, function()
                    local lastIndex = math.min(nextIndex + batchSize - 1, #candidates)
                    appendMatches(nextIndex, lastIndex)
                    nextIndex = lastIndex + 1
                    if nextIndex > #candidates then
                        filtering = false
                        panel:Unsubscribe(ui.Hook.ONTIMER)
                    end
                    showPage(true, quiet)
                    if autoSelect and not filtering and #matches == 1 and panel.visibleGlobal then
                        selected(matches[1])
                        renderRows()
                    end
                end)
            else
                appendMatches(1, #candidates)
            end
        end
        page = 1
        showPage(false, quiet)
        if autoSelect and not filtering and #matches == 1 then
            selected(matches[1])
            renderRows()
        end
    end

    button(parent, "Search", 238, y + 24, 70, function() runSearch(true) end)
    button(parent, "Prev", 184, y, 58, function()
        if page > 1 then page = page - 1; showPage() end
    end, 22)
    button(parent, "Next", 248, y, 60, function()
        if page * pageSize < #matches then page = page + 1; showPage() end
    end, 22)
    if groups then
        local filterMenu = ui.Layer.new(parent)
        local checkHeight = 24
        filterMenu:SetPos(12, 34)
        filterMenu:SetSize(218, (#groups + 1) * checkHeight + 12)
        filterMenu.clickthrough = false
        filterMenu.hidden = true
        local frame = ui.Rectangle.new(filterMenu)
        frame:SetSize(0, 0, 1, 1)
        frame.fill = true
        frame.rgba = 0x665B4DFF
        frame.clickthrough = true
        local fill = ui.Rectangle.new(filterMenu)
        fill:SetPos(1, 1)
        fill:SetSize(-2, -2, 1, 1)
        fill.fill = true
        fill.rgba = 0x1B1917FF
        fill.clickthrough = true

        local filterButton = button(parent, "Filters", 12, 5, 128, function()
            filterMenu.hidden = not filterMenu.hidden
            if not filterMenu.hidden then filterMenu:MoveToFront() end
        end, 28)

        local checks = {}
        for index = 1, #groups + 1 do
            local group = groups[index]
            local check = ui.Check.new(filterMenu)
            check:SetPos(8, 6 + (index - 1) * checkHeight)
            check:SetSize(202, checkHeight)
            check.stylesheetID = id.StyleSheet.CHECKBOX_DEFAULT
            check.label = group and group.label or "Other"
            check.buttonSize = 18
            check.value = true
            checks[index] = check
        end

        local function applyFilters()
            local hiddenGroups, checkedGroups = {}, {}
            for index, group in ipairs(groups) do
                local target = checks[index].value and checkedGroups or hiddenGroups
                target[#target + 1] = group
            end
            local showOther = checks[#checks].value
            includeName = search.catalogFilter(hiddenGroups, not showOther and checkedGroups or nil)
            local unchecked = #hiddenGroups + (showOther and 0 or 1)
            filterButton.label = unchecked == 0 and "Filters" or ("Filters (" .. unchecked .. " off)")
            runSearch()
        end
        for _, check in ipairs(checks) do check:Subscribe(ui.Hook.ONBUTTONPRESSED, applyFilters) end
    end
    resizeRows()
    panel:Subscribe(ui.Hook.ONRESIZE, resizeRows)
    runSearch(true)
    return renderRows, function(catalog)
        names = catalog
        displayNames = {}
        runSearch(false, true)
    end
end

return modelSearch
