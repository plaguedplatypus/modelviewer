-- A placed model is a UI preview lined up with a game tile each draw.
-- It is not part of the scene, so players and scenery cannot occlude it.
local placement = {}

-- Use the same field of view when working out the model's screen position.
local placedFov = 50
local placedCategory = 211
local maxTileRange = 40
-- Each tile gets its own UI group. The active one follows viewer changes;
-- earlier placements keep the asset, Seq, and rotation they were given.
local placed = {}
local active
local drawOrder = {}
local nextOrder = 0
local placing = false
local placeButton
local state
local setStatus

-- The viewer owns the current selection and the status line. Placement reads
-- those when the player chooses a tile, so it does not keep a second selection.
function placement.init(viewState, report)
    state = viewState
    setStatus = report
end

-- The viewer window can be rebuilt after a reload. Drop its old button then.
function placement.setButton(button)
    placeButton = button
end

-- The offset moves the model within the full-screen viewport. Its rotation
-- comes from the viewer, while its scale comes from the tile projection.
-- Loc model parts share the same transform, including the config offsets.
local function applyTransform(item)
    local scale = item.scale or 1
    local position = item.offset or Vector3.new(0, 0, 0)
    local modelScale = Vector3.new(scale, scale, scale)
    if item.kind == "loc" then
        local loc = item.loc
        local offset, post = loc.modelOffset, loc.modelPostOffset
        local locScale = loc.modelScale
        position = Vector3.new(
            position.x + (offset.x * locScale.x + post.x) * scale,
            position.y + (offset.y * locScale.y + post.y) * scale,
            position.z + (offset.z * locScale.z + post.z) * scale
        )
        modelScale = Vector3.new(scale * locScale.x, scale * locScale.y, scale * locScale.z)
    end
    local rotation = Vector3.new(math.rad(item.yaw), math.rad(item.pitch), 0)
    item.model:SetTransform(position, rotation, modelScale, 0)
    for _, part in ipairs(item.parts) do
        part:SetTransform(position, rotation, modelScale, 0)
    end
end

-- Changing tabs should not turn a model placed from the other tab.
function placement.setRotation(kind, yaw, pitch)
    local item = active
    if not item or item.kind ~= kind then return end
    item.yaw, item.pitch = yaw, pitch
    applyTransform(item)
end

-- Aim the UI camera in the same direction as the game camera. The API uses a
-- new camera for each change, so discard the old one after switching.
local function applyCamera(item)
    local centre = item.height / 2
    local yaw = item.cameraYaw or math.pi
    local pitch = item.cameraPitch or 0
    local horizontal = math.cos(pitch) * item.distance
    local cameraType = ui.ModelCamera or ui.ModelCameraInfo
    local camera = cameraType.new()
    camera:SetFOV(placedFov, 0)
    camera:SetPosition(Vector3.new(
        math.sin(yaw) * horizontal,
        centre + math.sin(pitch) * item.distance,
        math.cos(yaw) * horizontal
    ), 0)
    camera:SetLookAt(Vector3.new(0, centre, 0), 0)
    -- Keep the near plane proportional to camera distance. The old value of 1
    -- left too little depth precision for close armour and clothing surfaces.
    camera:SetClipPlanes(math.max(1, item.distance * 0.05), item.distance * 20)
    -- Leave the rest of the plugin layer clear around the model.
    camera.clearColour = Vector4.new(0, 0, 0, 0)
    camera.useLookAt = true

    local previous = item.cameraId
    item.cameraId = item.group:AddCamera(camera)
    item.group:SwitchCamera(item.cameraId, ui.ModelCameraTransition.NONE, -1, 0)
    if previous then item.group:DeleteCamera(previous) end
end

-- Project the tile's ground and head points each draw. Their screen distance
-- changes with game camera zoom, so use it to size the UI model like world art.
local function drawOne(item, player, cameraYaw, cameraPitch)
    -- Hide the old tile when the player changes floors, so it cannot appear
    -- over the current scene at the wrong level.
    if not player or player.coordGrid.level ~= item.coord.level then
        item.group.hidden = true
        return
    end
    -- Keep the placement, but stop drawing it beyond 40 tiles. It can appear
    -- again when the player returns without having to choose the tile twice.
    local dx = player.coordGrid.x - item.coord.x
    local dz = player.coordGrid.z - item.coord.z
    if dx * dx + dz * dz > maxTileRange * maxTileRange then
        item.group.hidden = true
        return
    end
    local point = ScreenConvert.CoordGridToScreen(item.coord, 0)
    local head = ScreenConvert.CoordGridToScreen(item.coord, math.floor(item.height))
    if not point or not head then
        item.group.hidden = true
        return
    end

    -- ScreenConvert returns screen coordinates; the plugin layer uses its own
    -- local coordinates. Convert before positioning the model in that layer.
    local origin = item.parent.xyGlobal
    local x = point.x - origin.x
    local y = point.y - origin.y
    item.group.hidden = x < 0 or y < 0 or x >= item.parent.width or y >= item.parent.height
    if item.group.hidden then return end

    local projectedPixels = point.y - head.y
    if projectedPixels <= 0 then
        item.group.hidden = true
        return
    end

    -- A large angle step is visible on tall models when the game camera moves.
    -- Keep the step small without rebuilding the UI camera on every draw.
    if not item.cameraId or not item.cameraYaw
        or math.abs(item.cameraYaw - cameraYaw) > 0.003
        or math.abs((item.cameraPitch or 0) - cameraPitch) > 0.003 then
        item.cameraYaw = cameraYaw
        item.cameraPitch = cameraPitch
        applyCamera(item)
    end

    -- Keep the viewport as large as the game view. Moving the model inside it
    -- gives it the off-centre perspective needed near the screen edges.
    local width = item.group.width
    local height = item.group.height
    local focalLength = height / (2 * math.tan(math.rad(placedFov) / 2))
    local halfHeight = item.height / 2
    local cosPitch = math.cos(item.cameraPitch)
    local sinPitch = math.sin(item.cameraPitch)
    local depth = item.distance + halfHeight * sinPitch
    local footOffset = focalLength * halfHeight * cosPitch / depth
    local right = (x - width / 2) * depth / focalLength
    local up = (height / 2 + footOffset - y) * depth / focalLength
    local cosYaw = math.cos(item.cameraYaw)
    local sinYaw = math.sin(item.cameraYaw)
    local offset = Vector3.new(
        -cosYaw * right - sinYaw * sinPitch * up,
        cosPitch * up,
        sinYaw * right - cosYaw * sinPitch * up
    )

    -- Match the game's projected ground-to-head span, including the vertical
    -- offset that changes when the tile moves away from screen centre.
    local topOffset = (height / 2 - y + projectedPixels) / focalLength
    local divisor = cosPitch + topOffset * sinPitch
    if divisor <= 0 then
        item.group.hidden = true
        return
    end
    local scale = (halfHeight + (topOffset * item.distance - up) / divisor) / item.height
    if scale <= 0 then
        item.group.hidden = true
        return
    end
    -- Follow each projected position. Holding the previous transform until it
    -- changed by a whole model unit made slow camera movement look stepped.
    item.offset = offset
    item.scale = scale
    applyTransform(item)
end

-- Use the game camera's direction for every model. Measuring from each tile
-- would make still models turn and lean when the player walks away from them.
local function drawPlaced()
    local player = Player.GetEntity()
    local cameraYaw = math.pi
    local cameraPitch = 0
    local cameraAvailable = Camera.IsAvailable()
    local cameraPos
    local focusPos
    if cameraAvailable then
        cameraPos = Camera.GetPosition()
        focusPos = Camera.GetFocusPosition()
        local dx = cameraPos.x - focusPos.x
        local dz = cameraPos.z - focusPos.z
        local dy = cameraPos.y - focusPos.y
        cameraYaw = math.atan(dx, dz)
        cameraPitch = math.atan(dy, math.sqrt(dx * dx + dz * dz))
    end
    for _, item in ipairs(placed) do
        drawOne(item, player, cameraYaw, cameraPitch)
    end

    if not cameraAvailable or not player then return end

    -- Separate model groups have no shared depth buffer. Put nearer tiles in
    -- front so a model placed earlier does not cover a model closer to camera.
    local order = {}
    local lookX = focusPos.x - cameraPos.x
    local lookY = focusPos.y - cameraPos.y
    local lookZ = focusPos.z - cameraPos.z
    for index, item in ipairs(placed) do
        local pos = item.worldPos
        item.depth = (pos.x - cameraPos.x) * lookX
            + (pos.y - cameraPos.y) * lookY
            + (pos.z - cameraPos.z) * lookZ
        order[index] = item
    end
    table.sort(order, function(a, b)
        if a.depth == b.depth then return a.order < b.order end
        return a.depth < b.depth
    end)
    local changed = #order ~= #drawOrder
    if not changed then
        for index, item in ipairs(order) do
            if item ~= drawOrder[index] then changed = true; break end
        end
    end
    if changed then
        -- MoveToBack keeps these overlays below other UI on the plugin layer.
        -- Moving near to far leaves the nearest group in front of the others.
        for _, item in ipairs(order) do item.group:MoveToBack() end
        drawOrder = order
    end
end

-- The host may have removed an interface during a reload, so destroying its
-- old group is protected. Once the last group is gone, stop the draw callback.
function placement.removeLast()
    local item = table.remove(placed)
    if not item then return false end
    if item == active then active = nil end
    drawOrder = {}
    if #placed == 0 then Event.Draw.Unsubscribe("modelview_placed") end
    pcall(function() item.group:Destroy() end)
    return true
end

function placement.clear()
    local count = #placed
    if count == 0 then return 0 end
    Event.Draw.Unsubscribe("modelview_placed")
    for _, item in ipairs(placed) do
        pcall(function() item.group:Destroy() end)
    end
    placed = {}
    active = nil
    drawOrder = {}
    return count
end

-- The menu callback is only needed while waiting for a tile selection.
function placement.cancel()
    if not placing then return end
    placing = false
    Event.MiniMenuReady.Unsubscribe("modelview_place")
    if placeButton then placeButton.label = "Place on tile..." end
end

-- The active placement follows the matching preview tab. Older ones retain
-- their chosen assets, even when another model is selected for placement.
function placement.setAsset(kind, id, animId, height)
    local item = active
    if not item or item.kind ~= kind then return end
    local modelType = ui.ModelType.NPC_MODEL
    if kind == "models" then
        modelType = ui.ModelType.MODEL
    elseif kind == "obj" then
        modelType = ui.ModelType.OBJECT
    end
    item.model:SetModel(modelType, id)
    item.model.animID = animId or -1
    item.height = height
    item.distance = math.max(1200, height * 2.5)
    applyCamera(item)
end

-- One Loc shape can contain several raw model IDs. Replace the previous parts
-- when the shape changes, and keep their Seq and config transform together.
function placement.setLoc(ids, loc, animId)
    local item = active
    if not item or item.kind ~= "loc" then return end
    if not ids or #ids == 0 then
        placement.removeLast()
        return
    end
    for _, part in ipairs(item.parts) do part:Destroy() end
    item.parts = {}
    item.loc = loc
    item.height = 700
    item.distance = 1750
    item.model:SetModel(ui.ModelType.MODEL, ids[1])
    item.model.animID = animId or -1
    for index = 2, #ids do
        local part = ui.Model.new(item.group, placedCategory)
        part:SetSize(0, 0, 1, 1)
        part.clickthrough = true
        part:SetModel(ui.ModelType.MODEL, ids[index])
        part.animID = animId or -1
        item.parts[#item.parts + 1] = part
    end
    applyTransform(item)
    applyCamera(item)
end

-- Seqs from another tab do not affect the active placement.
function placement.setAnimation(kind, seqId)
    local item = active
    if not item or item.kind ~= kind then return end
    item.model.animID = seqId or -1
    for _, part in ipairs(item.parts) do part.animID = seqId or -1 end
end

-- Give each chosen tile its own overlay so existing models stay in the scene.
local function placeAt(coord)
    if not placing then return end
    placement.cancel()
    local kind = state.tab
    local npc
    local loc
    local ids
    if kind == "npc" then
        npc = config.NPC.FromID(state.npcId)
        if not npc then setStatus("Select an available NPC before placing it."); return end
    elseif kind == "loc" then
        loc = state.locId and config.Loc.FromID(state.locId)
        local shape = loc and loc.locShapeTypes[state.shapeIndex]
        ids = shape and loc:GetModelIDs(shape)
        if not ids or #ids == 0 then
            setStatus("Select a Loc shape with a model before placing it.")
            return
        end
    elseif kind == "obj" and (not state.objId or not config.Obj.FromID(state.objId)) then
        setStatus("Select an available Obj before placing it.")
        return
    end

    -- Use the plugin bottom layer so models stay below plugin windows.
    local parent = ui.Interfaces:GetComponent(id.Component.TOPLEVEL_V2__PLUGIN_BUILD_LAYER_BOTTOM)
    local worldPos = coord:ToCoordFine(true).position
    local groundHeight, found = World.GetGroundHeight(coord.level, worldPos.x, worldPos.z)
    if found then worldPos = Vector3.new(worldPos.x, groundHeight, worldPos.z) end
    nextOrder = nextOrder + 1
    local item = {
        parent = parent, coord = coord, kind = kind, parts = {},
        worldPos = worldPos, order = nextOrder,
    }
    item.group = ui.ModelGroup.new(parent, placedCategory)
    -- This transparent viewport follows the game window so large models
    -- do not get cut off by a small fixed render area.
    item.group:SetSize(0, 0, 1, 1)
    item.group:SetPos(0, 0)
    item.group.clickthrough = true
    item.group:MoveToBack()
    item.model = ui.Model.new(item.group, placedCategory)
    item.model:SetSize(0, 0, 1, 1)
    item.model.clickthrough = true
    -- Raw models, Locs, and Objs have no exposed bounds. NPCs can use their overlay height.
    item.height = npc and (npc.overlayHeight > 0 and npc.overlayHeight or 700) or 700
    item.distance = math.max(1200, item.height * 2.5)
    item.yaw, item.pitch = state.yaw, state.pitch
    placed[#placed + 1] = item
    active = item
    drawOrder = {}
    if #placed == 1 then Event.Draw.Subscribe("modelview_placed", drawPlaced) end
    -- Each tab remembers its own Seq. Loc shapes can contain several models.
    if kind == "loc" then
        placement.setLoc(ids, loc, state.locSeqId)
    elseif kind == "models" then
        item.model:SetModel(ui.ModelType.MODEL, state.assetId)
        item.model.animID = state.assetSeqId or -1
    elseif kind == "obj" then
        item.model:SetModel(ui.ModelType.OBJECT, state.objId)
        item.model.animID = state.objSeqId or -1
    else
        item.model:SetModel(ui.ModelType.NPC_MODEL, state.npcId)
        item.model.animID = state.seqId or -1
    end
    applyTransform(item)
    drawPlaced()
    local name = "NPC"
    if kind == "loc" then
        name = "Loc"
    elseif kind == "models" then
        name = "Model"
    elseif kind == "obj" then
        name = "Obj"
    end
    setStatus(name .. " placed on the selected tile (" .. #placed .. " total).")
end

-- Use a menu action to choose the tile without walking or using an object.
function placement.toggle()
    if placing then
        placement.cancel()
        setStatus("Placement canceled.")
        return
    end
    if not Mouse.IsAvailable() then
        setStatus("Tile placement needs mouse input.")
        return
    end
    placing = true
    placeButton.label = "Cancel placement"
    -- Only add the action when the cursor points at a game tile. Selecting it
    -- captures that tile without sending a walk command to the game.
    Event.MiniMenuReady.Subscribe("modelview_place", function(event)
        if not placing then return end
        local cursor = Mouse.GetPosition()
        local coord = cursor and ScreenConvert.ScreenToCoordGrid(cursor)
        if coord then event.miniMenu:Add("Place model here", placeAt, coord) end
    end)
    setStatus("Right-click a tile, then choose 'Place model here' from the menu.")
end

-- Both callbacks must go away when the plugin unloads.
function placement.shutdown()
    placement.cancel()
    placement.clear()
end

return placement
