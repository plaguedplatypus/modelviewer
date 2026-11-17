local search = require("src/search")

local modelSearch = {}

-- Build a search panel and return a callback that refreshes row highlighting.
-- acceptsLoc is optional and filters Loc IDs to shapes with a model.
function modelSearch.create(parent, options)
    local kind, names = options.kind, options.names
    local selected, getSelected = options.select, options.getSelected
    local setStatus, acceptsLoc = options.setStatus, options.acceptsLoc
    local label, field, button = options.label, options.field, options.button
    local y = 5
    label(parent, kind, 12, y, 68, 0xF3C971FF)
    local pageText = label(parent, "", 74, y, 104)
    local input = field(parent, "", 12, y + 24, 218)
    input.emptyText = "ID or name"

    -- Native lists keep selected rows, which prevents selecting the same NPC
    -- or Seq again. Reuse a few clickable rows and scroll their contents.
    local height = options.listHeight
    local panel = ui.Layer.new(parent)
    panel:SetPos(12, y + 62)
    panel:SetSize(296, height)
    panel.clickthrough = false
    local background = ui.Rectangle.new(panel)
    background:SetSize(296, height)
    background.fill = true
    background.rgba = 0x1B1917FF
    background.clickthrough = false

    local rowHeight = 20
    local visibleRows = math.floor((height - 8) / rowHeight)
    local rows = {}
    local matches = {}
    local pendingLocs
    local page = 1
    -- Paging avoids creating a UI component for every entry in a large catalog.
    local pageSize = 500
    local first, last = 1, 0
    local offset = 1
    local trackHeight = height - 8
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

    for index = 1, visibleRows do
        local rowIndex = index
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
            local matchId = rows[rowIndex].id
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
            shade.rgba = rows[rowIndex].isSelected and 0x806538FF or 0x494039FF
        end)
        row:Subscribe(ui.Hook.ONMOUSELEAVE, function()
            shade.rgba = rows[rowIndex].isSelected and 0x66502DFF or 0x282521FF
        end)
    end

    local track = ui.Layer.new(panel)
    track:SetPos(283, 4)
    track:SetSize(9, trackHeight)
    track.clickthrough = false
    local trackFill = ui.Rectangle.new(track)
    trackFill:SetSize(9, trackHeight)
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
        local selectedId = getSelected()
        for index, row in ipairs(rows) do
            local resultIndex = first + offset + index - 2
            row.id = resultIndex <= last and matches[resultIndex] or nil
            row.root.hidden = row.id == nil
            row.isSelected = row.id ~= nil and row.id == selectedId
            row.shade.rgba = row.isSelected and 0x66502DFF or 0x282521FF
            row.text.rgba = row.isSelected and 0xF3C971FF or 0xE8DDC7FF
            if row.id then row.text.content = row.id .. "  " .. names[row.id] end
        end
        track.hidden = count <= visibleRows
        if count > visibleRows then
            thumbHeight = math.max(14, math.floor(trackHeight * visibleRows / count))
            thumb:SetSize(9, thumbHeight)
            thumb:SetPos(0, math.floor((offset - 1) * (trackHeight - thumbHeight) / (maxOffset - 1)))
        end
    end

    -- The scrollbar covers the current page; Prev and Next reach other pages.
    local function jumpTo(yPos)
        local count = last - first + 1
        local maxOffset = math.max(1, count - visibleRows + 1)
        if maxOffset > 1 then
            local travel = trackHeight - thumbHeight
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
    border:SetSize(296, height)
    border.fill = false
    border.outlineThickness = 1
    border.rgba = 0x665B4DFF
    border.clickthrough = true

    local function showPage(keepScroll)
        local pageCount = math.max(1, math.ceil(#matches / pageSize))
        pageText.content = page .. " / " .. (pendingLocs and "..." or pageCount)
        first = (page - 1) * pageSize + 1
        last = math.min(first + pageSize - 1, #matches)
        if not keepScroll then offset = 1 end
        renderRows()
        local source = "Client catalog: " .. names.count .. ". "
        if pendingLocs then
            setStatus(source .. "Checking Locs for models: " .. #matches .. " found so far.")
        elseif #matches == 0 then
            setStatus(source .. "No " .. kind .. " matches. Try an exact ID or part of a name.")
        else
            setStatus(source .. kind .. " results " .. first .. "-" .. last .. " of " .. #matches
                .. ". Scroll or use Prev / Next.")
        end
    end

    local function runSearch()
        if pendingLocs then panel:Unsubscribe(ui.Hook.ONTIMER) end
        pendingLocs = nil
        matches = search.find(names, input.content)
        if acceptsLoc and #matches > 1 then
            -- Reading every Loc config in one callback can exceed the client's
            -- Lua time limit. Check a small batch each logic tick instead.
            pendingLocs, matches = matches, {}
            local nextLoc = 1
            panel:Subscribe(ui.Hook.ONTIMER, function()
                local lastLoc = math.min(nextLoc + 99, #pendingLocs)
                for index = nextLoc, lastLoc do
                    local locId = pendingLocs[index]
                    if acceptsLoc(locId) then matches[#matches + 1] = locId end
                end
                nextLoc = lastLoc + 1
                if nextLoc > #pendingLocs then
                    pendingLocs = nil
                    panel:Unsubscribe(ui.Hook.ONTIMER)
                end
                showPage(true)
                if not pendingLocs and #matches == 1 then
                    selected(matches[1])
                    renderRows()
                end
            end)
        elseif acceptsLoc and #matches == 1 and not acceptsLoc(matches[1]) then
            matches = {}
        end
        page = 1
        showPage()
        if not pendingLocs and #matches == 1 then
            selected(matches[1])
            renderRows()
        end
    end

    button(parent, "Search", 238, y + 24, 70, runSearch)
    button(parent, "Prev", 184, y, 58, function()
        if page > 1 then page = page - 1; showPage() end
    end, 22)
    button(parent, "Next", 248, y, 60, function()
        if page * pageSize < #matches then page = page + 1; showPage() end
    end, 22)
    runSearch()
    return renderRows
end

return modelSearch
