local search = require("src/search")
local modelSearch = require("src/modelSearch")
local placement = require("src/placement")
local selection = require("src/assetSelection")

local viewer = {}
local window
local npcNames
local seqNames
local modelNames
local locNames
local objNames
local model
local group
local cameraId
local status
local npcInfo
local seqInfo
local distanceField
local yawField
local pitchField
local shapeInfo
local shapePage
local defaultBackground = 0x12110F

-- Each asset tab keeps its own model angle, camera distance, height, and pan.
local state = {
    npcId = 0,
    assetId = 0,
    locId = nil,
    objId = nil,
    seqId = nil,
    assetSeqId = nil,
    locSeqId = nil,
    objSeqId = nil,
    tab = "npc",
    distance = 2200,
    npcDistance = nil,
    assetDistance = nil,
    locDistance = nil,
    objDistance = nil,
    shapeIndex = 1,
    height = 700,
    lockPitch = true,
    background = defaultBackground,
    heightShift = { npc = 0, models = 0, loc = 0, obj = 0 },
    fitCentre = {},
    rotation = {
        npc = { yaw = 0, pitch = 0 },
        models = { yaw = 0, pitch = 0 },
        loc = { yaw = 0, pitch = 0 },
        obj = { yaw = 0, pitch = 0 },
    },
    pan = {
        npc = { x = 0, y = 0 },
        models = { x = 0, y = 0 },
        loc = { x = 0, y = 0 },
        obj = { x = 0, y = 0 },
    },
}

-- Asset handlers share the current preview and labels. The window fills in
-- component references when it opens or the host rebuilds its interface.
local view = {
    state = state,
    names = {},
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

placement.init(state, setStatus)

local function getCentre()
    return (state.fitCentre[state.tab] or (state.tab == "obj" and 0 or state.height / 2))
        + state.heightShift[state.tab]
end

-- Picking bounds are available for some NPCs and Locs, but they are not
-- rendered model bounds. Use their tile footprint as a minimum estimate.
local function getFitBounds()
    local asset, spanX, spanZ, height
    if state.tab == "npc" then
        asset = config.NPC.FromID(state.npcId)
        if not asset then return end
        spanX = math.max(1, asset.gridSize) * 512
        spanZ = spanX
        height = math.max(700, asset.overlayHeight, spanX * 1.6)
    elseif state.tab == "loc" and state.locId then
        asset = config.Loc.FromID(state.locId)
        if not asset then return end
        spanX = math.max(1, asset.width) * 512
        spanZ = math.max(1, asset.length) * 512
        height = math.max(700, math.max(spanX, spanZ) * 2.3)
    else
        return
    end

    local minX, maxX = -spanX / 2, spanX / 2
    local minY, maxY = 0, height
    local minZ, maxZ = -spanZ / 2, spanZ / 2
    local bounds = asset.customBounding
    if bounds then
        minX, maxX = math.min(minX, bounds.minX), math.max(maxX, bounds.maxX)
        minY, maxY = math.min(minY, bounds.minY), math.max(maxY, bounds.maxY)
        minZ, maxZ = math.min(minZ, bounds.minZ), math.max(maxZ, bounds.maxZ)
    end
    return minX, maxX, minY, maxY, minZ, maxZ
end

-- Model pitch follows the model's yawed local axis. Convert a tilt around the
-- screen's horizontal axis to yaw/pitch/roll so it keeps its direction at 180 degrees.
local function modelRotation(angle)
    local yaw, pitch = math.rad(angle.yaw), math.rad(angle.pitch)
    local sinYaw, cosYaw = math.sin(yaw), math.cos(yaw)
    local sinPitch, cosPitch = math.sin(pitch), math.cos(pitch)
    local localPitch = math.max(-1, math.min(1, sinPitch * cosYaw))
    return Vector3.new(
        math.atan(sinYaw, cosPitch * cosYaw),
        math.asin(localPitch),
        math.atan(sinPitch * sinYaw, cosPitch)
    )
end

local function applyPreviewTransform()
    -- Convert drag distance in interface units to model units at this zoom.
    -- Compensate for pitch around the same centre the camera looks at.
    local pan = state.pan[state.tab]
    local angle = state.rotation[state.tab]
    local pitch = math.rad(angle.pitch)
    local centre = getCentre()
    local worldPerUnit = state.distance * 2 * math.tan(math.rad(25)) / group.height
    local position = Vector3.new(
        pan.x * worldPerUnit,
        -pan.y * worldPerUnit + centre * (1 - math.cos(pitch)),
        -centre * math.sin(pitch)
    )
    angle.transform = modelRotation(angle)
    if state.tab == "loc" then
        selection.applyLocTransform(view, position, angle.transform)
    else
        model:SetTransform(position, angle.transform, Vector3.new(1, 1, 1), 0)
    end
end

-- Rebuild the fixed group camera when zoom or the displayed model's height changes.
local function applyCamera()
    -- Item models sit near their origin. Looking above it puts small Objs near
    -- the bottom of the preview; other tabs use their height estimate. The
    -- slider adjusts that starting point without changing the model itself.
    local centre = getCentre()
    local cameraType = ui.ModelCamera or ui.ModelCameraInfo
    local camera = cameraType.new()
    camera:SetFOV(50, 0)
    camera:SetPosition(Vector3.new(0, centre, -state.distance), 0)
    camera:SetLookAt(Vector3.new(0, centre, 0), 0)
    -- A near plane of 1 spreads depth precision too thin at normal zoom.
    -- Armour and clothing surfaces can then fight over which one is in front.
    camera:SetClipPlanes(math.max(1, state.distance * 0.05), math.max(state.distance * 10, centre * 10))
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

-- Each tab remembers its own camera distance.
local function setDistance(distance)
    state.distance = distance
    if state.tab == "npc" then
        state.npcDistance = distance
    elseif state.tab == "models" then
        state.assetDistance = distance
    elseif state.tab == "loc" then
        state.locDistance = distance
    else
        state.objDistance = distance
    end
    distanceField.content = string.format("%.0f", distance)
    applyCamera()
    applyPreviewTransform()
end

view.setStatus = setStatus
view.setDistance = setDistance

-- NPCs, Locs, Objs, Seqs, and raw assets use the same sparse-ID catalog search.
-- Each asset tab uses the same two search views. Each view keeps its
-- own query and scroll position while the selected asset stays in the preview.
local assetFields = { NPC = "npcId", Model = "assetId", Loc = "locId", Obj = "objId" }
local seqFields = { NPC = "seqId", Model = "assetSeqId", Loc = "locSeqId", Obj = "objSeqId" }
local function makeSearchTabs(parent, title, kind, names, selected, seqSelected, listHeight)
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

    local function createSearch(layer, catalogKind, catalog, select, selectedField, acceptsLoc)
        return modelSearch.create(layer, {
            kind = catalogKind,
            names = catalog,
            listHeight = listHeight or 226,
            select = select,
            getSelected = function() return state[selectedField] end,
            setStatus = setStatus,
            acceptsLoc = acceptsLoc,
            label = label,
            field = field,
            button = button,
        })
    end

    local acceptsLoc = kind == "Loc" and selection.findLocShape or nil
    createSearch(assetSearch, kind, names, selected, assetFields[kind], acceptsLoc)
    return createSearch(seqSearch, "Seq", seqNames, seqSelected, seqFields[kind])
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
    -- Lock pitch applies to typed rotation and dragging.
    local angle = state.rotation[state.tab]
    local pitch = state.lockPitch and angle.pitch or tonumber(pitchField.content)
    if not yaw or not pitch or math.abs(yaw) == math.huge or math.abs(pitch) == math.huge then
        setStatus("Yaw and pitch must be numbers in degrees.")
        return
    end
    angle.yaw, angle.pitch = yaw, pitch
    applyPreviewTransform()
    placement.setRotation(state.tab, angle)
    setStatus("Model rotation applied.")
end

-- PrettyUI hides this window on close, so reopening it keeps the player's
-- chosen position and the current viewer state.
function viewer.openWindow()
    if window and window.root and ui.Interfaces:GetInterface(window.interfaceID) then
        window:Show()
        return
    end
    -- The host can remove an interface on reload. Drop callbacks to its old
    -- components before building a new window.
    placement.setButton(nil)
    placement.cancel()
    window = nil
    selection.reset()

    -- Ask the active client for names when the viewer opens.
    npcNames = search.load("NPC")
    seqNames = search.load("Seq")
    view.names.npc = npcNames
    view.names.seq = seqNames
    local parent = ui.Interfaces:GetComponent(id.Component.TOPLEVEL_V2__PLUGIN_BUILD_LAYER_TOP)
    window = prettyui.Window.new(parent, {
        title = "Model Viewer",
        width = 900,
        height = 725,
        minWidth = 700,
        minHeight = 725,
        xAnchor = 0.5,
        yAnchor = 0.5,
        x = -450,
        y = -362,
        resizable = true,
        destroyOnClose = false,
    })
    local content = window.content
    status = label(content, "", 12, 650, 866)
    status:SetPos(12, -35, 0, 1)
    status:SetSize(-18, 22, 1, 0)

    -- Each tab owns its search controls; the preview and model controls
    -- stay in place so an asset can be inspected with the same gestures.
    local seqRefresh = {}
    local npcTab = ui.Layer.new(content)
    npcTab:SetPos(0, 40)
    npcTab:SetSize(326, 340)
    seqRefresh.npc = makeSearchTabs(npcTab, "NPCs", "NPC", npcNames,
        function(npcId) selection.selectNpc(view, npcId) end,
        function(seqId) selection.setSeq(view, "npc", seqId) end)

    local assetTab = ui.Layer.new(content)
    assetTab:SetPos(0, 40)
    assetTab:SetSize(326, 340)
    assetTab.hidden = true

    local locTab = ui.Layer.new(content)
    locTab:SetPos(0, 40)
    locTab:SetSize(326, 340)
    locTab.hidden = true

    local objTab = ui.Layer.new(content)
    objTab:SetPos(0, 40)
    objTab:SetSize(326, 340)
    objTab.hidden = true

    label(content, "Camera distance", 12, 386, 296)
    distanceField = field(content, "2200", 12, 410, 211)
    button(content, "Apply", 231, 410, 77, applyDistance)

    label(content, "Model yaw / pitch", 12, 447, 180)
    yawField = field(content, string.format("%.1f", state.rotation[state.tab].yaw), 12, 471, 72)
    pitchField = field(content, string.format("%.1f", state.rotation[state.tab].pitch), 92, 471, 72)
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
        if state.lockPitch then pitchField.content = string.format("%.1f", state.rotation[state.tab].pitch) end
    end)

    button(content, "Clear animation", 12, 508, 296, function()
        selection.clearSeq(view, state.tab)
        if seqRefresh[state.tab] then seqRefresh[state.tab]() end
        seqInfo.content = "No Seq selected"
        setStatus("Animation cleared.")
    end)

    label(content, "Background", 12, 545, 120)
    local background = ui.Rectangle.new(content)
    background:SetPos(334, 12)
    background:SetSize(-398, -124, 1, 1)
    background.fill = true
    background.rgba = state.background * 256 + 255

    local backgroundPicker = prettyui.ColourPicker.new(content, {
        x = 134, y = 544, buttonSize = 26,
        value = state.background * 256 + 255,
        alphaSlider = false,
        windowTitle = "Model preview background",
        onChange = function(_, colour)
            state.background = math.floor(colour / 256)
            background.rgba = state.background * 256 + 255
            applyCamera()
        end,
    })
    button(content, "Reset", 168, 544, 140, function()
        backgroundPicker:SetValue(defaultBackground * 256 + 255)
        setStatus("Background reset.")
    end, 26)

    local placeButton = button(content, "Place on tile...", 12, 581, 143, placement.toggle, 26)
    placement.setButton(placeButton)
    button(content, "Remove last", 163, 581, 80, function()
        placement.cancel()
        if placement.removeLast() then
            setStatus("Most recent placement removed.")
        else
            setStatus("No placed models to remove.")
        end
    end, 26)
    button(content, "Clear all", 247, 581, 61, function()
        placement.cancel()
        local count = placement.clear()
        setStatus(count > 0 and (count .. " placed models removed.") or "No placed models to remove.")
    end, 26)

    group = ui.ModelGroup.new(content)
    group:SetPos(338, 16)
    group:SetSize(-402, -132, 1, 1)
    group.clickthrough = true
    model = ui.Model.new(group)
    model:SetSize(0, 0, 1, 1)
    model.clickthrough = true
    view.group = group
    view.model = model
    -- Keep Shift+drag panning at the same screen offset as the preview grows.
    group:Subscribe(ui.Hook.ONRESIZE, function() applyPreviewTransform() end)
    cameraId = nil
    model:SetModel(ui.ModelType.NPC_MODEL, state.npcId)
    model.animID = -1

    -- The model can draw beyond its original click area after a resize. This
    -- layer follows the whole preview so every visible part gets the controls.
    local previewInput = ui.Layer.new(content)
    previewInput:SetPos(338, 16)
    previewInput:SetSize(-402, -132, 1, 1)
    previewInput.clickthrough = false

    -- Positive wheel deltas scroll down in the client, so they move the camera back.
    previewInput:Subscribe(ui.Hook.ONSCROLLWHEEL, function(_, delta)
        local distance = state.distance * (1.15 ^ delta)
        if distance < 10 then distance = 10 end
        if distance < math.huge then setDistance(distance) end
        return false
    end)

    -- Plain drag turns the model; Shift+drag pans it across the preview.
    local drag
    previewInput:Subscribe(ui.Hook.ONCLICK, function(_, x, y)
        local pan = state.pan[state.tab]
        drag = {
            x = x, y = y,
            moving = Keyboard.IsAvailable() and Keyboard.IsShiftDown(),
            panX = pan.x, panY = pan.y,
            yaw = state.rotation[state.tab].yaw, pitch = state.rotation[state.tab].pitch,
        }
        return false
    end)
    previewInput:Subscribe(ui.Hook.ONHOLD, function(_, x, y)
        if not drag then return end
        if drag.moving then
            local pan = state.pan[state.tab]
            pan.x = drag.panX + x - drag.x
            pan.y = drag.panY + y - drag.y
            applyPreviewTransform()
            return false
        end
        local angle = state.rotation[state.tab]
        local yaw = drag.yaw - (x - drag.x) * 1.0
        local pitch = angle.pitch
        if not state.lockPitch then
            pitch = math.max(-89, math.min(89, drag.pitch - (y - drag.y) * 1.0))
        end
        if angle.yaw == yaw and angle.pitch == pitch then return false end
        angle.yaw, angle.pitch = yaw, pitch
        applyPreviewTransform()
        placement.setRotation(state.tab, angle)
        yawField.content = string.format("%.1f", yaw)
        pitchField.content = string.format("%.1f", pitch)
        return false
    end)
    previewInput:Subscribe(ui.Hook.ONRELEASE, function()
        if not drag then return end
        drag = nil
        return false
    end)

    -- Native text does not break at a newline; use one label per line.
    local adjustLabel = label(content, "Adjust", 0, 16, 58)
    adjustLabel:SetPos(-60, 16, 1, 0)
    local centerLabel = label(content, "Center", 0, 36, 58)
    centerLabel:SetPos(-60, 36, 1, 0)
    local heightValue = label(content, "+0", 0, 0, 55)
    heightValue:SetPos(-59, -174, 1, 1)

    -- The native slider is horizontal. Keep this narrow vertical track beside
    -- the preview so it does not push the placement controls out of the window.
    local heightTrack = ui.Layer.new(content)
    heightTrack:SetPos(-46, 65, 1, 0)
    heightTrack:SetSize(24, -244, 0, 1)
    heightTrack.clickthrough = false
    local trackFill = ui.Rectangle.new(heightTrack)
    trackFill:SetPos(8, 0)
    trackFill:SetSize(8, 0, 0, 1)
    trackFill.fill = true
    trackFill.rgba = 0x383127FF
    trackFill.clickthrough = true
    local midpoint = ui.Rectangle.new(heightTrack)
    midpoint:SetSize(24, 2)
    midpoint.fill = true
    midpoint.rgba = 0x8E7853FF
    midpoint.clickthrough = true
    local thumb = ui.Rectangle.new(heightTrack)
    thumb:SetSize(20, 14)
    thumb.fill = true
    thumb.rgba = 0xCDA753FF
    thumb.clickthrough = false

    local function drawHeight()
        local travel = heightTrack.height - 14
        if travel <= 0 then return end
        local value = state.heightShift[state.tab]
        midpoint:SetPos(0, math.floor(heightTrack.height / 2))
        thumb:SetPos(2, math.floor((1500 - value) * travel / 3000 + 0.5))
        heightValue.content = string.format("%+d", value)
    end

    local centreButton = button(content, "Center", 346, 0, 84, function()
        local pan = state.pan[state.tab]
        pan.x, pan.y = 0, 0
        applyPreviewTransform()
        setStatus("Model centered.")
    end, 26)
    centreButton:SetPos(346, -150, 0, 1)

    local fitButton = button(content, "Fit model", 0, 0, 100, function()
        local minX, maxX, minY, maxY, minZ, maxZ = getFitBounds()
        local pan = state.pan[state.tab]
        pan.x, pan.y = 0, 0
        state.heightShift[state.tab] = 0
        if not minX then
            -- Raw models and Objs have no size data in the client API.
            state.fitCentre[state.tab] = nil
            drawHeight()
            setDistance(math.max(1200, state.height * 2.5))
            setStatus("No size data for this model; use zoom and Adjust Center.")
            return
        end

        local angle = state.rotation[state.tab]
        local yaw, pitch = math.rad(angle.yaw), math.rad(angle.pitch)
        local xRadius = math.max(math.abs(minX), math.abs(maxX))
        local yRadius = (maxY - minY) / 2
        local zRadius = math.max(math.abs(minZ), math.abs(maxZ))
        local across = math.abs(math.cos(yaw)) * xRadius + math.abs(math.sin(yaw)) * zRadius
        local along = math.abs(math.sin(yaw)) * xRadius + math.abs(math.cos(yaw)) * zRadius
        local vertical = math.abs(math.cos(pitch)) * yRadius + math.abs(math.sin(pitch)) * along
        local depth = math.abs(math.cos(pitch)) * along + math.abs(math.sin(pitch)) * yRadius
        local tanHalfFov = math.tan(math.rad(25))
        local distance = depth + 1.2 * math.max(
            vertical / tanHalfFov,
            across / (tanHalfFov * group.width / group.height)
        )
        state.fitCentre[state.tab] = (minY + maxY) / 2
        drawHeight()
        setDistance(math.max(1200, distance))
        setStatus("Fit estimated from config size. Adjust Center or zoom if needed.")
    end, 26)
    fitButton:SetPos(87, -150, 0.5, 1)

    local resetBackground = ui.Rectangle.new(content)
    resetBackground:SetPos(-101, -151, 1, 1)
    resetBackground:SetSize(34, 28)
    resetBackground.fill = true
    resetBackground.rgba = 0x211D18FF
    resetBackground.clickthrough = true
    local resetBorder = ui.Rectangle.new(content)
    resetBorder:SetPos(-101, -151, 1, 1)
    resetBorder:SetSize(34, 28)
    resetBorder.fill = false
    resetBorder.outlineThickness = 1
    resetBorder.rgba = 0x8E7853FF
    resetBorder.clickthrough = true
    local resetButton = prettyui.SpriteButton.new(content, "REFRESH", function()
        local angle = state.rotation[state.tab]
        local pan = state.pan[state.tab]
        angle.yaw, angle.pitch = 0, 0
        pan.x, pan.y = 0, 0
        state.fitCentre[state.tab] = nil
        state.heightShift[state.tab] = 0
        drawHeight()
        setDistance(math.max(1200, state.height * 2.5))
        placement.setRotation(state.tab, angle)
        yawField.content, pitchField.content = "0.0", "0.0"
        setStatus("Model and preview reset.")
    end, { x = 0, y = 0, size = 24 })
    resetButton.root:SetPos(-96, -149, 1, 1)

    local function chooseHeight(y)
        local travel = heightTrack.height - 14
        if travel <= 0 then return false end
        local fraction = math.max(0, math.min(1, (y - 7) / travel))
        state.heightShift[state.tab] = math.floor((1500 - fraction * 3000) / 25 + 0.5) * 25
        drawHeight()
        applyCamera()
        applyPreviewTransform()
        return false
    end

    heightTrack:Subscribe(ui.Hook.ONRESIZE, drawHeight)
    heightTrack:Subscribe(ui.Hook.ONCLICK, function(_, _, y) return chooseHeight(y) end)
    heightTrack:Subscribe(ui.Hook.ONHOLD, function(_, _, y) return chooseHeight(y) end)
    thumb:Subscribe(ui.Hook.ONCLICK, function(_, _, y) return chooseHeight(thumb.y + y) end)
    thumb:Subscribe(ui.Hook.ONHOLD, function(_, _, y) return chooseHeight(thumb.y + y) end)

    npcInfo = label(content, "", 338, 545, 540, 0xF3C971FF)
    seqInfo = label(content, "No Seq selected", 338, 568, 540)
    npcInfo:SetPos(338, -105, 0, 1)
    seqInfo:SetPos(338, -82, 0, 1)
    npcInfo:SetSize(-344, 22, 1, 0)
    seqInfo:SetSize(-344, 22, 1, 0)
    local dragHint = label(content, "Drag to turn model | Shift+drag to pan", 338, 0, 300, 0xB8AA90FF)
    dragHint:SetPos(338, -59, 0, 1)
    dragHint:SetSize(-344, 22, 1, 0)
    view.info = npcInfo
    view.seqInfo = seqInfo

    local tabLine = ui.Rectangle.new(content)
    tabLine:SetSize(71, 2)
    tabLine.fill = true
    tabLine.rgba = 0xF3C971FF
    tabLine.clickthrough = true
    local assetSearchBuilt = false
    local locSearchBuilt = false
    local objSearchBuilt = false
    local tabPos = { npc = 12, models = 87, loc = 162, obj = 237 }
    local shownTab
    -- Switching tabs restores that tab's selected asset and Seq.
    local function showTab(tab)
        local previous = shownTab
        shownTab = tab
        state.tab = tab
        drawHeight()
        yawField.content = string.format("%.1f", state.rotation[tab].yaw)
        pitchField.content = string.format("%.1f", state.rotation[tab].pitch)
        if previous and previous ~= tab then placement.cancel() end
        if previous == "loc" and tab ~= "loc" then selection.clearParts() end
        npcTab.hidden = tab ~= "npc"
        assetTab.hidden = tab ~= "models"
        locTab.hidden = tab ~= "loc"
        objTab.hidden = tab ~= "obj"
        tabLine:SetPos(tabPos[tab], 40)
        if tab == "models" then
            if not assetSearchBuilt then
                -- This is the largest catalog, so load it on first use.
                modelNames = modelNames or search.load("Model")
                view.names.models = modelNames
                seqRefresh.models = makeSearchTabs(assetTab, "Model assets", "Model", modelNames,
                    function(assetId) selection.selectModel(view, assetId) end,
                    function(seqId) selection.setSeq(view, "models", seqId) end)
                assetSearchBuilt = true
            end
            if previous ~= "models" then selection.selectModel(view, state.assetId) end
        elseif tab == "obj" then
            if not objSearchBuilt then
                objNames = objNames or search.load("Obj")
                view.names.obj = objNames
                seqRefresh.obj = makeSearchTabs(objTab, "Objs", "Obj", objNames,
                    function(objId) selection.selectObj(view, objId) end,
                    function(seqId) selection.setSeq(view, "obj", seqId) end)
                objSearchBuilt = true
            end
            if previous ~= "obj" then
                if state.objId then
                    selection.selectObj(view, state.objId)
                else
                    model:SetModel(ui.ModelType.NONE, 0)
                    model.animID = -1
                    npcInfo.content = "Select an Obj"
                    seqInfo.content = "No Seq selected"
                    setDistance(state.objDistance or 1750)
                    setStatus("Select an Obj to preview its item model.")
                end
            end
        elseif tab == "loc" then
            if not locSearchBuilt then
                locNames = locNames or search.load("Loc")
                view.names.loc = locNames
                shapeInfo = label(locTab, "", 12, 279, 296, 0xF3C971FF)
                shapePage = label(locTab, "", 12, 307, 166)
                view.shapeInfo = shapeInfo
                view.shapePage = shapePage
                seqRefresh.loc = makeSearchTabs(locTab, "Locs", "Loc", locNames,
                    function(locId) selection.selectLoc(view, locId) end,
                    function(seqId) selection.setSeq(view, "loc", seqId) end, 170)
                button(locTab, "Prev", 184, 306, 58, function() selection.stepShape(view, -1) end, 22)
                button(locTab, "Next", 248, 306, 60, function() selection.stepShape(view, 1) end, 22)
                locSearchBuilt = true
            end
            if previous ~= "loc" then
                if state.locId then
                    selection.selectLoc(view, state.locId)
                else
                    model:SetModel(ui.ModelType.NONE, 0)
                    model.animID = -1
                    npcInfo.content = "Select a Loc"
                    seqInfo.content = "No Seq selected"
                    shapeInfo.content = "Select a Loc to view its shapes"
                    shapePage.content = ""
                    setDistance(state.locDistance or 1750)
                    setStatus("Select a Loc to preview its models.")
                end
            end
        elseif not previous or previous ~= "npc" then
            selection.selectNpc(view, state.npcId)
        end
    end

    button(content, "NPC", 12, 8, 71, function() showTab("npc") end)
    button(content, "Models", 87, 8, 71, function() showTab("models") end)
    button(content, "Locs", 162, 8, 71, function() showTab("loc") end)
    button(content, "Objs", 237, 8, 71, function() showTab("obj") end)
    showTab(state.tab)
    window:Show()
    drawHeight()
end

function viewer.shutdown()
    placement.shutdown()
    if window then window:Destroy() end
end

return viewer
