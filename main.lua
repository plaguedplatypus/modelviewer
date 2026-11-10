local search = require("data/search")

local window
local ribbon
local npcNames
local seqNames
local modelNames
local model
local group
local cameraId
local status
local npcInfo
local seqInfo
local distanceField
local yawField
local pitchField
local defaultBackground = 0x12110F

-- NPC and raw model views keep separate camera distance and pan settings.
local state = {
    npcId = 0,
    assetId = 0,
    seqId = nil,
    assetSeqId = nil,
    tab = "npc",
    distance = 2200,
    npcDistance = nil,
    assetDistance = nil,
    height = 700,
    yaw = 0,
    pitch = 0,
    lockPitch = true,
    background = defaultBackground,
    pan = {
        npc = { x = 0, y = 0 },
        models = { x = 0, y = 0 },
    },
}

-- Use the same native text, input, and button styles throughout the window.
local function label(parent, content, x, y, width, colour)
    local text = ui.Text.new(parent)
    text:SetPos(x, y)
    text:SetSize(width, 22)
    text.content = content
    text.font = id.Font.MUSEO_SANS_15PT_REGULAR
    text.rgba = colour or 0xE8DDC7FF
    text.clickthrough = true
    return text
end

local function field(parent, content, x, y, width)
    local input = ui.InputField.new(parent)
    input:SetPos(x, y)
    input:SetSize(width, 30)
    input.stylesheetID = id.StyleSheet.INPUT_DEFAULT
    input:Setup(ui.TextContentVisibilityMode.VISIBLE, ui.InputFieldFilterMode.NONE, 80)
    input.content = content
    return input
end

local function button(parent, caption, x, y, width, pressed, height)
    local control = ui.Button.new(parent)
    control:SetPos(x, y)
    control:SetSize(width, height or 30)
    control.stylesheetID = id.StyleSheet.BUTTON_DEFAULT
    control.label = caption
    control:Subscribe(ui.Hook.ONBUTTONPRESSED, pressed)
    return control
end

local function setStatus(message)
    status.content = message
end

local function applyTransform()
    -- Convert drag distance in interface units to model units at this zoom.
    -- This keeps the chosen screen position steady when the camera zooms.
    local pan = state.pan[state.tab == "models" and "models" or "npc"]
    local worldPerUnit = state.distance * 2 * math.tan(math.rad(25)) / group.height
    model:SetTransform(
        Vector3.new(pan.x * worldPerUnit, -pan.y * worldPerUnit, 0),
        Vector3.new(math.rad(state.yaw), math.rad(state.pitch), 0),
        Vector3.new(1, 1, 1),
        0
    )
end

-- Rebuild the group camera when zoom or the displayed model's height changes.
local function applyCamera()
    -- The game does not expose model bounds. NPC overlay height is a useful
    -- starting point; raw assets use a neutral estimate.
    local centre = state.height / 2
    local cameraType = ui.ModelCamera or ui.ModelCameraInfo
    local camera = cameraType.new()
    camera:SetFOV(50, 0)
    camera:SetPosition(Vector3.new(0, centre, -state.distance), 0)
    camera:SetLookAt(Vector3.new(0, centre, 0), 0)
    camera:SetClipPlanes(1, math.max(state.distance * 10, centre * 10))
    local colour = state.background
    camera.clearColour = Vector4.new(
        math.floor(colour / 65536) / 255,
        math.floor(colour / 256) % 256 / 255,
        colour % 256 / 255,
        1
    )
    camera.useLookAt = true

    local previous = cameraId
    cameraId = group:AddCamera(camera)
    group:SwitchCamera(cameraId, ui.ModelCameraTransition.NONE, -1, 0)
    -- Zoom changes create a new camera. Remove the old one after the switch.
    if previous then group:DeleteCamera(previous) end
end

-- NPC and raw model assets remember their own camera distance.
local function setDistance(distance)
    state.distance = distance
    if state.tab ~= "models" then
        state.npcDistance = distance
    else
        state.assetDistance = distance
    end
    distanceField.content = string.format("%.0f", distance)
    applyCamera()
    applyTransform()
end

-- NPC names come from the catalog, but the active cache decides
-- whether a particular NPC can be drawn.
local function setNpc(npcId)
    local npc = config.NPC.FromID(npcId)
    if not npc then
        setStatus("NPC " .. npcId .. " is unavailable in this game cache.")
        return
    end

    -- Returning from another tab keeps the chosen framing. A different NPC
    -- starts centered with a distance estimated from its overlay height.
    if state.npcId ~= npcId then
        state.npcDistance = nil
        state.pan.npc.x, state.pan.npc.y = 0, 0
    end
    state.npcId = npcId
    -- The overlay height can be absent or unrelated to a particular pose.
    state.height = npc.overlayHeight > 0 and npc.overlayHeight or 700
    model:SetModel(ui.ModelType.NPC_MODEL, npcId)
    -- Keep the selected Seq while comparing NPCs. A different skeleton may
    -- display that same animation differently or not move at all.
    model.animID = state.seqId or -1
    setDistance(state.npcDistance or math.max(1200, state.height * 2.5))
    npcInfo.content = "NPC " .. npcId .. "  " .. npcNames[npcId]
    seqInfo.content = state.seqId and ("Seq " .. state.seqId .. "  " .. seqNames[state.seqId])
        or "No Seq selected"
    setStatus("NPC loaded. Select a Seq to animate it.")
end

local function setAsset(assetId)
    if state.assetId ~= assetId then
        state.assetDistance = nil
        state.pan.models.x, state.pan.models.y = 0, 0
    end
    state.assetId = assetId
    -- Plain model IDs have no config object with bounds or cache validation.
    -- Start from a neutral camera and let the user adjust unusual assets.
    state.height = 700
    model:SetModel(ui.ModelType.MODEL, assetId)
    model.animID = state.assetSeqId or -1
    setDistance(state.assetDistance or math.max(1200, state.height * 2.5))
    npcInfo.content = "Model " .. assetId .. "  " .. modelNames[assetId]
    seqInfo.content = state.assetSeqId and ("Seq " .. state.assetSeqId .. "  " .. seqNames[state.assetSeqId])
        or "No Seq selected"
    setStatus("Model asset selected. Use camera distance to adjust the preview.")
end

-- A Seq in the catalog may be absent from this game cache. Check it before
-- replacing the animation currently shown on the NPC.
local function setSeq(seqId)
    if not config.Seq.FromID(seqId) then
        setStatus("Seq " .. seqId .. " is unavailable in this game cache.")
        return
    end
    state.seqId = seqId
    model.animID = seqId
    seqInfo.content = "Seq " .. seqId .. "  " .. seqNames[seqId]
    setStatus("Seq applied. An incompatible skeleton may show no movement.")
end

-- Raw model assets can use the same animation property as NPC previews.
-- A chat head or body part may still need a Seq built for its own rig.
local function setAssetSeq(seqId)
    if not config.Seq.FromID(seqId) then
        setStatus("Seq " .. seqId .. " is unavailable in this game cache.")
        return
    end
    state.assetSeqId = seqId
    model.animID = seqId
    seqInfo.content = "Seq " .. seqId .. "  " .. seqNames[seqId]
    setStatus("Seq applied to model. An incompatible rig may show no movement.")
end

-- NPCs, Seqs, and raw assets all use the same sparse-ID catalog search.
local function makeSearch(parent, kind, names, y, selected, listHeight)
    label(parent, kind, 12, y, 68, 0xF3C971FF)
    local pageText = label(parent, "", 74, y, 104)
    local input = field(parent, "", 12, y + 24, 218)
    input.emptyText = "ID or name"

    -- Native lists keep selected rows, which prevents selecting the same NPC
    -- or Seq again. Reuse a few clickable rows and scroll their contents.
    local height = listHeight or 92
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
            if matchId then selected(matchId) end
            return false
        end)
        row:Subscribe(ui.Hook.ONSCROLLWHEEL, function(_, delta)
            return scrollBy(delta)
        end)
        row:Subscribe(ui.Hook.ONMOUSEOVER, function()
            shade.rgba = 0x494039FF
        end)
        row:Subscribe(ui.Hook.ONMOUSELEAVE, function()
            shade.rgba = 0x282521FF
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
        for index, row in ipairs(rows) do
            local resultIndex = first + offset + index - 2
            row.id = resultIndex <= last and matches[resultIndex] or nil
            row.root.hidden = row.id == nil
            row.shade.rgba = 0x282521FF
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

    local function showPage()
        local pageCount = math.max(1, math.ceil(#matches / pageSize))
        pageText.content = page .. " / " .. pageCount
        first = (page - 1) * pageSize + 1
        last = math.min(first + pageSize - 1, #matches)
        offset = 1
        renderRows()
        if #matches == 0 then
            setStatus("No " .. kind .. " matches. Try an exact ID or part of a name.")
        else
            setStatus(kind .. " results " .. first .. "-" .. last .. " of " .. #matches
                .. ". Scroll this page or use Prev / Next.")
        end
    end

    local function runSearch()
        matches = search.find(names, input.content)
        page = 1
        showPage()
        if #matches == 1 then selected(matches[1]) end
    end

    button(parent, "Search", 238, y + 24, 70, runSearch)
    button(parent, "Prev", 184, y, 58, function()
        if page > 1 then page = page - 1; showPage() end
    end, 22)
    button(parent, "Next", 248, y, 60, function()
        if page * pageSize < #matches then page = page + 1; showPage() end
    end, 22)
    runSearch()
end

-- NPCs and raw models use the same two search views. Each view keeps its
-- own query and scroll position while the selected asset stays in the preview.
local function makeSearchTabs(parent, title, kind, names, selected, seqSelected)
    local assetSearch = ui.Layer.new(parent)
    assetSearch:SetPos(0, 34)
    assetSearch:SetSize(326, 306)
    local seqSearch = ui.Layer.new(parent)
    seqSearch:SetPos(0, 34)
    seqSearch:SetSize(326, 306)
    seqSearch.hidden = true

    local searchLine = ui.Rectangle.new(parent)
    searchLine:SetPos(12, 29)
    searchLine:SetSize(144, 2)
    searchLine.fill = true
    searchLine.rgba = 0xF3C971FF
    searchLine.clickthrough = true
    button(parent, title, 12, 3, 144, function()
        assetSearch.hidden = false
        seqSearch.hidden = true
        searchLine:SetPos(12, 29)
    end, 24)
    button(parent, "Seq animations", 164, 3, 144, function()
        assetSearch.hidden = true
        seqSearch.hidden = false
        searchLine:SetPos(164, 29)
    end, 24)

    makeSearch(assetSearch, kind, names, 5, selected, 226)
    makeSearch(seqSearch, "Seq", seqNames, 5, seqSelected, 226)
end

local function numberFrom(input, description)
    local value = tonumber(input.content)
    if not value or value <= 0 or value == math.huge or value ~= value then
        setStatus(description .. " must be a positive number.")
        return nil
    end
    return value
end

local function applyDistance()
    local value = numberFrom(distanceField, "Camera distance")
    if not value then return end
    setDistance(value)
    setStatus("Camera distance set to " .. value .. ".")
end

local function applyRotation()
    local yaw = tonumber(yawField.content)
    -- Lock pitch applies to typed rotation too, not only mouse dragging.
    local pitch = state.lockPitch and state.pitch or tonumber(pitchField.content)
    if not yaw or not pitch or math.abs(yaw) == math.huge or math.abs(pitch) == math.huge then
        setStatus("Yaw and pitch must be numbers in degrees.")
        return
    end
    state.yaw = yaw
    state.pitch = pitch
    applyTransform()
    setStatus("Rotation applied.")
end

-- PrettyUI hides this window on close, so reopening it keeps the player's
-- chosen position and the current viewer state.
local function openWindow()
    if window and window.root and ui.Interfaces:GetInterface(window.interfaceID) then
        window:Show()
        return
    end
    -- The host can remove an interface on reload. Drop callbacks to its old
    -- components before building a new window.
    window = nil

    -- Name tables are loaded only when the viewer opens, rather than at plugin startup.
    npcNames = require("data/npc")
    seqNames = require("data/seq")
    local parent = ui.Interfaces:GetComponent(id.Component.TOPLEVEL_V2__PLUGIN_BUILD_LAYER_TOP)
    window = prettyui.Window.new(parent, {
        title = "Model Viewer",
        width = 900,
        height = 690,
        minWidth = 700,
        minHeight = 690,
        xAnchor = 0.5,
        yAnchor = 0.5,
        x = -450,
        y = -345,
        resizable = true,
        destroyOnClose = false,
    })
    local content = window.content
    status = label(content, "", 12, 615, 866)
    status:SetPos(12, -35, 0, 1)
    status:SetSize(-18, 22, 1, 0)

    -- Each tab owns its search controls; the preview and transform controls
    -- stay in place so an asset can be inspected with the same gestures.
    local npcTab = ui.Layer.new(content)
    npcTab:SetPos(0, 40)
    npcTab:SetSize(326, 340)
    makeSearchTabs(npcTab, "NPCs", "NPC", npcNames, setNpc, setSeq)

    local assetTab = ui.Layer.new(content)
    assetTab:SetPos(0, 40)
    assetTab:SetSize(326, 340)
    assetTab.hidden = true

    label(content, "Camera distance", 12, 386, 296)
    distanceField = field(content, "2200", 12, 410, 211)
    button(content, "Apply", 231, 410, 77, applyDistance)

    label(content, "Rotation: yaw / pitch", 12, 447, 180)
    yawField = field(content, string.format("%.1f", state.yaw), 12, 471, 72)
    pitchField = field(content, string.format("%.1f", state.pitch), 92, 471, 72)
    pitchField.enabled = not state.lockPitch
    button(content, "Apply", 172, 471, 65, applyRotation)

    local pitchLock = ui.Check.new(content)
    pitchLock:SetPos(200, 447)
    pitchLock:SetSize(108, 22)
    pitchLock.stylesheetID = id.StyleSheet.CHECKBOX_DEFAULT
    pitchLock.label = "Lock pitch"
    pitchLock.value = state.lockPitch
    pitchLock.alignment = ui.CheckAlignMode.LEFT
    pitchLock.buttonSize = 18
    pitchLock:Subscribe(ui.Hook.ONBUTTONPRESSED, function()
        state.lockPitch = pitchLock.value
        pitchField.enabled = not state.lockPitch
        if state.lockPitch then pitchField.content = string.format("%.1f", state.pitch) end
    end)

    button(content, "Fit model", 12, 508, 140, function()
        setDistance(math.max(1200, state.height * 2.5))
        setStatus("Camera fitted using an approximate model height.")
    end)
    button(content, "Center model", 160, 508, 148, function()
        local pan = state.pan[state.tab == "models" and "models" or "npc"]
        pan.x, pan.y = 0, 0
        applyTransform()
        setStatus("Model centered.")
    end)
    button(content, "Clear animation", 12, 545, 296, function()
        if state.tab == "models" then
            state.assetSeqId = nil
        else
            state.seqId = nil
        end
        model.animID = -1
        seqInfo.content = "No Seq selected"
        setStatus("Animation cleared.")
    end)

    label(content, "Background", 12, 581, 120)
    local background = ui.Rectangle.new(content)
    background:SetPos(334, 12)
    background:SetSize(-340, -124, 1, 1)
    background.fill = true
    background.rgba = state.background * 256 + 255

    local backgroundPicker = prettyui.ColourPicker.new(content, {
        x = 134, y = 580, buttonSize = 26,
        value = state.background * 256 + 255,
        alphaSlider = false,
        windowTitle = "Model preview background",
        onChange = function(_, colour)
            state.background = math.floor(colour / 256)
            background.rgba = state.background * 256 + 255
            applyCamera()
        end,
    })
    button(content, "Reset", 168, 580, 140, function()
        backgroundPicker:SetValue(defaultBackground * 256 + 255)
        setStatus("Background reset.")
    end, 26)

    group = ui.ModelGroup.new(content)
    group:SetPos(338, 16)
    group:SetSize(-348, -132, 1, 1)
    group.clickthrough = true
    model = ui.Model.new(group)
    model:SetSize(0, 0, 1, 1)
    model.clickthrough = true
    -- Keep Shift+drag panning at the same screen offset as the preview grows.
    group:Subscribe(ui.Hook.ONRESIZE, function() applyTransform() end)
    cameraId = nil
    model:SetModel(ui.ModelType.NPC_MODEL, state.npcId)
    model.animID = -1

    -- The model can draw beyond its original click area after a resize. This
    -- layer follows the whole preview so every visible part gets the controls.
    local previewInput = ui.Layer.new(content)
    previewInput:SetPos(338, 16)
    previewInput:SetSize(-348, -132, 1, 1)
    previewInput.clickthrough = false

    -- Positive wheel deltas scroll down in the client, so they move the camera back.
    previewInput:Subscribe(ui.Hook.ONSCROLLWHEEL, function(_, delta)
        local distance = state.distance * (1.15 ^ delta)
        if distance < 10 then distance = 10 end
        if distance < math.huge then setDistance(distance) end
        return false
    end)

    -- Shift+drag pans the model; plain drag rotates it, with optional pitch lock.
    local drag
    previewInput:Subscribe(ui.Hook.ONCLICK, function(_, x, y)
        local pan = state.pan[state.tab == "models" and "models" or "npc"]
        drag = {
            x = x, y = y,
            moving = Keyboard.IsAvailable() and Keyboard.IsShiftDown(),
            panX = pan.x, panY = pan.y,
            yaw = state.yaw, pitch = state.pitch,
        }
        return false
    end)
    previewInput:Subscribe(ui.Hook.ONHOLD, function(_, x, y)
        if not drag then return end
        if drag.moving then
            local pan = state.pan[state.tab == "models" and "models" or "npc"]
            pan.x = drag.panX + x - drag.x
            pan.y = drag.panY + y - drag.y
            applyTransform()
            return false
        end
        state.yaw = drag.yaw - (x - drag.x) * 0.6
        if not state.lockPitch then
            state.pitch = drag.pitch - (y - drag.y) * 0.6
        end
        applyTransform()
        return false
    end)
    previewInput:Subscribe(ui.Hook.ONRELEASE, function()
        if not drag then return end
        local moved = drag.moving
        drag = nil
        if not moved then
            yawField.content = string.format("%.1f", state.yaw)
            pitchField.content = string.format("%.1f", state.pitch)
        end
        return false
    end)

    npcInfo = label(content, "", 338, 545, 540, 0xF3C971FF)
    seqInfo = label(content, "No Seq selected", 338, 568, 540)
    npcInfo:SetPos(338, -105, 0, 1)
    seqInfo:SetPos(338, -82, 0, 1)
    npcInfo:SetSize(-344, 22, 1, 0)
    seqInfo:SetSize(-344, 22, 1, 0)

    local tabLine = ui.Rectangle.new(content)
    tabLine:SetSize(144, 2)
    tabLine.fill = true
    tabLine.rgba = 0xF3C971FF
    tabLine.clickthrough = true
    local assetSearchBuilt = false
    local shownTab
    -- Switching tabs restores that tab's selected asset and Seq.
    local function showTab(tab)
        local previous = shownTab
        shownTab = tab
        state.tab = tab
        npcTab.hidden = tab ~= "npc"
        assetTab.hidden = tab ~= "models"
        tabLine:SetPos(tab == "npc" and 12 or 164, 40)
        if tab == "models" then
            if not assetSearchBuilt then
                -- This is the largest catalog, so load it on first use.
                modelNames = modelNames or require("data/model")
                makeSearchTabs(assetTab, "Model assets", "Model", modelNames, setAsset, setAssetSeq)
                assetSearchBuilt = true
            end
            if previous ~= "models" then setAsset(state.assetId) end
        elseif not previous or previous == "models" then
            setNpc(state.npcId)
        end
    end

    button(content, "NPC", 12, 8, 144, function() showTab("npc") end)
    button(content, "Models", 164, 8, 144, function() showTab("models") end)
    showTab(state.tab)
    window:Show()
end

local function onRibbonOpened(event)
    -- The host may already have cleared the previous ribbon content.
    if ribbon then pcall(function() ribbon:Destroy() end) end
    ribbon = prettyui.SimpleView.new(event.component, {
        width = event.component.width,
        height = event.component.height,
    })
    ribbon:AddTitle("Model Viewer")
    ribbon:AddText({ text = "Search NPCs, Seqs, and raw model assets in a separate window." })
    ribbon:AddFancyButton("Open Viewer", openWindow, {
        variant = "positive", width = event.component.width - 64,
    })
end

Event.ContentLayerReady.Subscribe("modelview_ribbon", onRibbonOpened)

function PluginShutdown()
    Event.ContentLayerReady.Unsubscribe("modelview_ribbon")
    if ribbon then pcall(function() ribbon:Destroy() end) end
    if window then window:Destroy() end
end
