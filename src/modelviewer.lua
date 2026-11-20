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
local columnStep = 312
local previewX = 642
local previewRight = 64
local assetTabTop = 42
local locAnimationTop = 30
local locAnimationHeight = 237
local locShapeTop = locAnimationTop + locAnimationHeight + 8

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
-- Each asset tab keeps its own asset and Seq searches visible side by side.
local assetFields = { NPC = "npcId", Model = "assetId", Loc = "locId", Obj = "objId" }
local seqFields = { NPC = "seqId", Model = "assetSeqId", Loc = "locSeqId", Obj = "objSeqId" }
local function makeSearchPanels(parent, kind, names, selected, seqSelected)
    local assetSearch = ui.Layer.new(parent)
    assetSearch:SetSize(320, -20, 0, 1)

    local isLoc = kind == "Loc"
    local seqTop = isLoc and locAnimationTop or 0
    local seqHeight = isLoc and locAnimationHeight or 293
    local function makeSeqLayer(hidden)
        local layer = ui.Layer.new(parent)
        layer:SetPos(columnStep, seqTop)
        layer:SetSize(320, seqHeight)
        layer.hidden = hidden
        return layer
    end

    local function createSearch(layer, options, selectedField)
        options.getSelected = function() return state[selectedField] end
        options.setStatus = function(message)
            if not parent.hidden then setStatus(message) end
        end
        options.label = label
        options.field = field
        options.button = button
        return modelSearch.create(layer, options)
    end

    createSearch(assetSearch, {
        kind = kind,
        names = names,
        select = selected,
        acceptsLoc = isLoc and selection.findLocShape or nil,
    }, assetFields[kind])

    local seqSearch = makeSeqLayer(isLoc)
    local refreshAll = createSearch(seqSearch, {
        kind = "Seq", names = seqNames, select = seqSelected,
        caption = not isLoc and "All animations" or nil,
    }, seqFields[kind])
    if not isLoc then return refreshAll end

    local configuredSearch = makeSeqLayer(false)
    local refreshConfigured, setCatalog = createSearch(configuredSearch, {
        kind = "Seq", names = { count = 0, maxId = 0, source = "Configured animations" },
        select = seqSelected,
    }, seqFields[kind])
    view.setLocSeqCatalog = setCatalog
    if view.locSeqNames then view.setLocSeqCatalog(view.locSeqNames) end

    local configuredX, allX = columnStep + 12, columnStep + 113
    local modeLine = ui.Rectangle.new(parent)
    modeLine:SetPos(configuredX, 26)
    modeLine:SetSize(94, 2)
    modeLine.fill = true
    modeLine.rgba = 0xF3C971FF
    modeLine.clickthrough = true
    local function showConfigured(configured)
        configuredSearch.hidden = not configured
        seqSearch.hidden = configured
        modeLine:SetPos(configured and configuredX or allX, 26)
        if configured then
            refreshConfigured()
            if not view.locSeqNames then
                setStatus("Select a Loc to see its configured animations.")
            elseif view.locSeqNames.count == 0 then
                setStatus("This Loc has no configured animations. Choose All to try a Seq.")
            end
        else
            refreshAll()
        end
    end
    button(parent, "Configured", configuredX, 0, 94, function() showConfigured(true) end, 24)
    button(parent, "All", allX, 0, 94, function() showConfigured(false) end, 24)
    return function()
        refreshAll()
        refreshConfigured()
    end
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
    view.locSeqNames = nil
    view.setLocSeqCatalog = nil

    local parent = ui.Interfaces:GetComponent(id.Component.TOPLEVEL_V2__PLUGIN_BUILD_LAYER_TOP)
    if not parent then return end

    -- Ask the active client for names when the viewer opens.
    npcNames = search.load("NPC")
    seqNames = search.load("Seq")
    view.names.npc = npcNames
    view.names.seq = seqNames
    local minWidth = 1020
    local width = math.max(minWidth, math.min(1200, parent.width))
    window = prettyui.Window.new(parent, {
        title = "Model Viewer",
        width = width,
        height = 725,
        minWidth = minWidth,
        minHeight = 725,
        xAnchor = 0.5,
        yAnchor = 0.5,
        x = -math.floor(width / 2),
        y = -362,
        resizable = true,
        -- Classic mode keeps the native interface locked.
        respectInterfaceLock = false,
        scrollable = false,
        destroyOnClose = false,
    })
    local content = window.content
    local previewLabelWidth = -(previewX + 6)
    status = label(content, "", previewX, 650, 540)
    status:SetPos(previewX, -35, 0, 1)
    status:SetSize(previewLabelWidth, 22, 1, 0)

    npcInfo = label(content, "", previewX, 0, 540, 0xF3C971FF)
    npcInfo:SetPos(previewX, -123, 0, 1)
    npcInfo:SetSize(previewLabelWidth, 22, 1, 0)
    local clientInfo = label(content, "", previewX, 0, 540)
    clientInfo:SetPos(previewX, -102, 0, 1)
    clientInfo:SetSize(previewLabelWidth, 40, 1, 0)
    clientInfo.maxLines = 2
    seqInfo = label(content, "No Seq selected", previewX, 0, 540)
    seqInfo:SetPos(previewX, -59, 0, 1)
    seqInfo:SetSize(previewLabelWidth, 22, 1, 0)
    view.info = npcInfo
    view.seqInfo = seqInfo

    local clientName = ""
    local infoFont = config.Font.FromID(clientInfo.font)
    local function wrapClientName()
        -- Config names have no spaces, so wrap within long words.
        if infoFont and clientName ~= "" and clientInfo.width > 0 then
            clientInfo.content = table.concat(infoFont:SplitString(clientName, clientInfo.width, true, true), "\n")
        else
            clientInfo.content = clientName
        end
    end
    view.setClientName = function(name)
        clientName = name
        wrapClientName()
    end
    clientInfo:Subscribe(ui.Hook.ONRESIZE, wrapClientName)

    -- Keep each tab's queries while the shared controls and preview stay in place.
    local seqRefresh = {}
    local function makeAssetTab(hidden)
        local tab = ui.Layer.new(content)
        tab:SetPos(0, assetTabTop)
        tab:SetSize(previewX - 8, -assetTabTop, 0, 1)
        tab.hidden = hidden
        return tab
    end
    local npcTab = makeAssetTab(false)
    local assetTab = makeAssetTab(true)
    local locTab = makeAssetTab(true)
    local objTab = makeAssetTab(true)

    local controls = ui.Layer.new(content)
    controls:SetPos(columnStep, 386)
    controls:SetSize(320, 278)

    label(controls, "Camera distance", 12, 0, 296)
    distanceField = field(controls, "2200", 12, 24, 211)
    button(controls, "Apply", 231, 24, 77, applyDistance)

    label(controls, "Model yaw / pitch", 12, 61, 180)
    yawField = field(controls, string.format("%.1f", state.rotation[state.tab].yaw), 12, 85, 72)
    pitchField = field(controls, string.format("%.1f", state.rotation[state.tab].pitch), 92, 85, 72)
    pitchField.enabled = not state.lockPitch
    button(controls, "Apply", 172, 85, 65, applyRotation)

    local pitchLock = ui.Check.new(controls)
    pitchLock:SetPos(200, 61)
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

    button(controls, "Clear animation", 12, 122, 296, function()
        selection.clearSeq(view, state.tab)
        if seqRefresh[state.tab] then seqRefresh[state.tab]() end
        setStatus("Animation cleared.")
    end)

    label(controls, "Background", 12, 159, 120)
    local background = ui.Rectangle.new(content)
    background:SetPos(previewX - 4, 12)
    background:SetSize(-(previewX + previewRight - 4), -142, 1, 1)
    background.fill = true
    background.rgba = state.background * 256 + 255

    local backgroundPicker = prettyui.ColourPicker.new(content, {
        x = columnStep + 134, y = 544, buttonSize = 26,
        value = state.background * 256 + 255,
        alphaSlider = false,
        windowTitle = "Model preview background",
        onChange = function(_, colour)
            state.background = math.floor(colour / 256)
            background.rgba = state.background * 256 + 255
            applyCamera()
        end,
    })
    button(controls, "Reset", 168, 158, 140, function()
        backgroundPicker:SetValue(defaultBackground * 256 + 255)
        setStatus("Background reset.")
    end, 26)

    local placeButton = button(controls, "Place on tile...", 12, 195, 143, placement.toggle, 26)
    placement.setButton(placeButton)
    button(controls, "Remove last", 163, 195, 80, function()
        placement.cancel()
        if placement.removeLast() then
            setStatus("Most recent placement removed.")
        else
            setStatus("No placed models to remove.")
        end
    end, 26)
    button(controls, "Clear all", 247, 195, 61, function()
        placement.cancel()
        local count = placement.clear()
        setStatus(count > 0 and (count .. " placed models removed.") or "No placed models to remove.")
    end, 26)

    group = ui.ModelGroup.new(content)
    group:SetPos(previewX, 16)
    group:SetSize(-(previewX + previewRight), -150, 1, 1)
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
    previewInput:SetPos(previewX, 16)
    previewInput:SetSize(-(previewX + previewRight), -150, 1, 1)
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
    heightValue:SetPos(-59, -192, 1, 1)

    -- The native slider is horizontal. Keep this narrow vertical track beside
    -- the preview so it does not push the placement controls out of the window.
    local heightTrack = ui.Layer.new(content)
    heightTrack:SetPos(-46, 65, 1, 0)
    heightTrack:SetSize(24, -262, 0, 1)
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

    local centreButton = button(content, "Center", previewX + 8, 0, 84, function()
        local pan = state.pan[state.tab]
        pan.x, pan.y = 0, 0
        applyPreviewTransform()
        setStatus("Model centered.")
    end, 26)
    centreButton:SetPos(previewX + 8, -168, 0, 1)

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
    fitButton:SetPos((previewX - previewRight) / 2, -168, 0.5, 1, -0.5)

    local resetBackground = ui.Rectangle.new(content)
    resetBackground:SetPos(-101, -169, 1, 1)
    resetBackground:SetSize(34, 28)
    resetBackground.fill = true
    resetBackground.rgba = 0x211D18FF
    resetBackground.clickthrough = true
    local resetBorder = ui.Rectangle.new(content)
    resetBorder:SetPos(-101, -169, 1, 1)
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
    resetButton.root:SetPos(-96, -167, 1, 1)

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

    label(controls, "Drag to turn model", 12, 232, 296, 0xB8AA90FF)
    label(controls, "Shift+Drag to pan", 12, 254, 296, 0xB8AA90FF)

    local tabLine = ui.Rectangle.new(content)
    tabLine:SetSize(71, 2)
    tabLine.fill = true
    tabLine.rgba = 0xF3C971FF
    tabLine.clickthrough = true
    local tabPos = { npc = 12, models = 87, loc = 162, obj = 237 }
    local shownTab
    local function selectLoc(locId)
        -- A Loc search can finish after the user switches to another asset tab.
        if state.tab ~= "loc" then return end
        selection.selectLoc(view, locId)
        if seqRefresh.loc then seqRefresh.loc() end
    end
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
            if not seqRefresh.models then
                -- This is the largest catalog, so load it on first use.
                modelNames = modelNames or search.load("Model")
                view.names.models = modelNames
                seqRefresh.models = makeSearchPanels(assetTab, "Model", modelNames,
                    function(assetId) selection.selectModel(view, assetId) end,
                    function(seqId) selection.setSeq(view, "models", seqId) end)
            end
            if previous ~= "models" then selection.selectModel(view, state.assetId) end
        elseif tab == "obj" then
            if not seqRefresh.obj then
                objNames = objNames or search.load("Obj")
                view.names.obj = objNames
                seqRefresh.obj = makeSearchPanels(objTab, "Obj", objNames,
                    function(objId) selection.selectObj(view, objId) end,
                    function(seqId) selection.setSeq(view, "obj", seqId) end)
            end
            if previous ~= "obj" then
                if state.objId then
                    selection.selectObj(view, state.objId)
                else
                    model:SetModel(ui.ModelType.NONE, 0)
                    model.animID = -1
                    npcInfo.content = "Select an Obj"
                    view.setClientName("")
                    seqInfo.content = "No Seq selected"
                    setDistance(state.objDistance or 1750)
                    setStatus("Select an Obj to preview its item model.")
                end
            end
        elseif tab == "loc" then
            if not seqRefresh.loc then
                locNames = locNames or search.load("Loc")
                view.names.loc = locNames
                shapeInfo = label(locTab, "", columnStep + 12, locShapeTop, 296, 0xF3C971FF)
                shapePage = label(locTab, "", columnStep + 12, locShapeTop + 28, 166)
                view.shapeInfo = shapeInfo
                view.shapePage = shapePage
                seqRefresh.loc = makeSearchPanels(locTab, "Loc", locNames, selectLoc,
                    function(seqId) selection.setSeq(view, "loc", seqId) end)
                button(locTab, "Prev", columnStep + 184, locShapeTop + 27, 58,
                    function() selection.stepShape(view, -1) end, 22)
                button(locTab, "Next", columnStep + 248, locShapeTop + 27, 60,
                    function() selection.stepShape(view, 1) end, 22)
            end
            if previous ~= "loc" then
                if state.locId then
                    selectLoc(state.locId)
                else
                    model:SetModel(ui.ModelType.NONE, 0)
                    model.animID = -1
                    npcInfo.content = "Select a Loc"
                    view.setClientName("")
                    seqInfo.content = "No Seq selected"
                    shapeInfo.content = "Select a Loc to view its shapes"
                    shapePage.content = ""
                    setDistance(state.locDistance or 1750)
                    setStatus("Select a Loc to preview its models.")
                end
            end
        elseif not previous or previous ~= "npc" then
            if not seqRefresh.npc then
                seqRefresh.npc = makeSearchPanels(npcTab, "NPC", npcNames,
                    function(npcId) selection.selectNpc(view, npcId) end,
                    function(seqId) selection.setSeq(view, "npc", seqId) end)
            end
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
