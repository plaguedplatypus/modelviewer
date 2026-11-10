-- A placed model is a UI preview lined up with a game tile each draw.
-- It is not part of the scene, so players and scenery cannot occlude it.
local placement = {}

-- Use the same field of view when working out the model's screen position.
local placedFov = 50
local placedCategory = 211
local maxTileRange = 40
-- Only one model can be placed at a time. A new tile or asset reuses it.
local placed = {}
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
local function applyTransform()
    if not placed.model then return end
    local scale = placed.scale or 1
    local position = placed.offset or Vector3.new(0, 0, 0)
    local modelScale = Vector3.new(scale, scale, scale)
    if placed.kind == "loc" then
        local loc = placed.loc
        local offset, post = loc.modelOffset, loc.modelPostOffset
        local locScale = loc.modelScale
        position = Vector3.new(
            position.x + (offset.x * locScale.x + post.x) * scale,
            position.y + (offset.y * locScale.y + post.y) * scale,
            position.z + (offset.z * locScale.z + post.z) * scale
        )
        modelScale = Vector3.new(scale * locScale.x, scale * locScale.y, scale * locScale.z)
    end
    local rotation = Vector3.new(math.rad(placed.yaw), math.rad(placed.pitch), 0)
    placed.model:SetTransform(position, rotation, modelScale, 0)
    for _, part in ipairs(placed.parts or {}) do
        part:SetTransform(position, rotation, modelScale, 0)
    end
end

-- Changing tabs should not turn a model placed from the other tab.
function placement.setRotation(kind, yaw, pitch)
    if placed.kind ~= kind then return end
    placed.yaw, placed.pitch = yaw, pitch
    applyTransform()
end

-- Aim the UI camera in the same direction as the game camera. The API uses a
-- new camera for each change, so discard the old one after switching.
local function applyCamera()
    if not placed.group then return end
    local centre = placed.height / 2
    local yaw = placed.cameraYaw or math.pi
    local pitch = placed.cameraPitch or 0
    local horizontal = math.cos(pitch) * placed.distance
    local cameraType = ui.ModelCamera or ui.ModelCameraInfo
    local camera = cameraType.new()
    camera:SetFOV(placedFov, 0)
    camera:SetPosition(Vector3.new(
        math.sin(yaw) * horizontal,
        centre + math.sin(pitch) * placed.distance,
        math.cos(yaw) * horizontal
    ), 0)
    camera:SetLookAt(Vector3.new(0, centre, 0), 0)
    -- Keep the near plane proportional to camera distance. The old value of 1
    -- left too little depth precision for close armour and clothing surfaces.
    camera:SetClipPlanes(math.max(1, placed.distance * 0.05), placed.distance * 20)
    -- Leave the rest of the plugin layer clear around the model.
    camera.clearColour = Vector4.new(0, 0, 0, 0)
    camera.useLookAt = true

    local previous = placed.cameraId
    placed.cameraId = placed.group:AddCamera(camera)
    placed.group:SwitchCamera(placed.cameraId, ui.ModelCameraTransition.NONE, -1, 0)
    if previous then placed.group:DeleteCamera(previous) end
end

-- Project the tile's ground and head points each draw. Their screen distance
-- changes with game camera zoom, so use it to size the UI model like world art.
local function drawPlaced()
    if not placed.group or not placed.coord then return end
    -- Hide the old tile when the player changes floors, so it cannot appear
    -- over the current scene at the wrong level.
    local player = Player.GetEntity()
    if not player or player.coordGrid.level ~= placed.coord.level then
        placed.group.hidden = true
        return
    end
    -- Keep the placement, but stop drawing it beyond 40 tiles. It can appear
    -- again when the player returns without having to choose the tile twice.
    local dx = player.coordGrid.x - placed.coord.x
    local dz = player.coordGrid.z - placed.coord.z
    if dx * dx + dz * dz > maxTileRange * maxTileRange then
        placed.group.hidden = true
        return
    end
    local point = ScreenConvert.CoordGridToScreen(placed.coord, 0)
    local head = ScreenConvert.CoordGridToScreen(placed.coord, math.floor(placed.height))
    if not point or not head then
        placed.group.hidden = true
        return
    end

    -- ScreenConvert returns screen coordinates; the plugin layer uses its own
    -- local coordinates. Convert before positioning the model in that layer.
    local origin = placed.parent.xyGlobal
    local x = point.x - origin.x
    local y = point.y - origin.y
    placed.group.hidden = x < 0 or y < 0 or x >= placed.parent.width or y >= placed.parent.height
    if placed.group.hidden then return end

    local projectedPixels = point.y - head.y
    if projectedPixels <= 0 then
        placed.group.hidden = true
        return
    end

    -- Use the game camera's direction. Measuring from the tile makes a still
    -- model turn and lean when the player walks away from it.
    local cameraYaw = math.pi
    local cameraPitch = 0
    if Camera.IsAvailable() then
        local cameraPos = Camera.GetPosition()
        local focusPos = Camera.GetFocusPosition()
        local dx = cameraPos.x - focusPos.x
        local dz = cameraPos.z - focusPos.z
        local dy = cameraPos.y - focusPos.y
        cameraYaw = math.atan(dx, dz)
        cameraPitch = math.atan(dy, math.sqrt(dx * dx + dz * dz))
    end
    -- A large angle step is visible on tall models when the game camera moves.
    -- Keep the step small without rebuilding the UI camera on every draw.
    if not placed.cameraId or not placed.cameraYaw
        or math.abs(placed.cameraYaw - cameraYaw) > 0.003
        or math.abs((placed.cameraPitch or 0) - cameraPitch) > 0.003 then
        placed.cameraYaw = cameraYaw
        placed.cameraPitch = cameraPitch
        applyCamera()
    end

    -- Keep the viewport as large as the game view. Moving the model inside it
    -- gives it the off-centre perspective needed near the screen edges.
    local width = placed.group.width
    local height = placed.group.height
    local focalLength = height / (2 * math.tan(math.rad(placedFov) / 2))
    local halfHeight = placed.height / 2
    local cosPitch = math.cos(placed.cameraPitch)
    local sinPitch = math.sin(placed.cameraPitch)
    local depth = placed.distance + halfHeight * sinPitch
    local footOffset = focalLength * halfHeight * cosPitch / depth
    local right = (x - width / 2) * depth / focalLength
    local up = (height / 2 + footOffset - y) * depth / focalLength
    local cosYaw = math.cos(placed.cameraYaw)
    local sinYaw = math.sin(placed.cameraYaw)
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
        placed.group.hidden = true
        return
    end
    local scale = (halfHeight + (topOffset * placed.distance - up) / divisor) / placed.height
    if scale <= 0 then
        placed.group.hidden = true
        return
    end
    -- Follow each projected position. Holding the previous transform until it
    -- changed by a whole model unit made slow camera movement look stepped.
    placed.offset = offset
    placed.scale = scale
    applyTransform()
end

-- Stop the draw callback before destroying its model group. The host may have
-- removed the interface already during a reload, hence the protected destroy.
function placement.clear()
    if not placed.group then return end
    Event.Draw.Unsubscribe("modelview_placed")
    pcall(function() placed.group:Destroy() end)
    placed = {}
end

-- The menu callback is only needed while waiting for a tile selection.
function placement.cancel()
    if not placing then return end
    placing = false
    Event.MiniMenuReady.Unsubscribe("modelview_place")
    if placeButton then placeButton.label = "Place on tile..." end
end

-- Keep the placed model in sync when the matching NPC or raw asset changes.
-- A different asset can need a different height estimate and camera distance.
function placement.setAsset(kind, id, animId, height)
    if placed.kind ~= kind then return end
    placed.model:SetModel(kind == "models" and ui.ModelType.MODEL or ui.ModelType.NPC_MODEL, id)
    placed.model.animID = animId or -1
    placed.height = height
    placed.distance = math.max(1200, height * 2.5)
    applyCamera()
end

-- One Loc shape can contain several raw model IDs. Replace the previous parts
-- when the shape changes, and keep their Seq and config transform together.
function placement.setLoc(ids, loc, animId)
    if placed.kind ~= "loc" then return end
    if not ids or #ids == 0 then
        placement.clear()
        return
    end
    for _, part in ipairs(placed.parts or {}) do part:Destroy() end
    placed.parts = {}
    placed.loc = loc
    placed.height = 700
    placed.distance = 1750
    placed.model:SetModel(ui.ModelType.MODEL, ids[1])
    placed.model.animID = animId or -1
    for index = 2, #ids do
        local part = ui.Model.new(placed.group, placedCategory)
        part:SetSize(0, 0, 1, 1)
        part.clickthrough = true
        part:SetModel(ui.ModelType.MODEL, ids[index])
        part.animID = animId or -1
        placed.parts[#placed.parts + 1] = part
    end
    applyTransform()
    applyCamera()
end

-- Seqs from the other tab do not affect the model already on the tile.
function placement.setAnimation(kind, seqId)
    if placed.kind ~= kind then return end
    placed.model.animID = seqId or -1
    for _, part in ipairs(placed.parts or {}) do part.animID = seqId or -1 end
end

-- Reuse the single overlay for another tile or create it on first placement.
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
    end

    if not placed.group then
        -- Use the plugin bottom layer so the model stays below plugin windows.
        local parent = ui.Interfaces:GetComponent(id.Component.TOPLEVEL_V2__PLUGIN_BUILD_LAYER_BOTTOM)
        placed.parent = parent
        placed.group = ui.ModelGroup.new(parent, placedCategory)
        -- This transparent viewport follows the game window so large models
        -- do not get cut off by a small fixed render area.
        placed.group:SetSize(0, 0, 1, 1)
        placed.group:SetPos(0, 0)
        placed.group.clickthrough = true
        placed.group:MoveToBack()
        placed.model = ui.Model.new(placed.group, placedCategory)
        placed.model:SetSize(0, 0, 1, 1)
        placed.model.clickthrough = true
        Event.Draw.Subscribe("modelview_placed", drawPlaced)
    end

    -- Reset the camera and offset so the next draw aligns the new selection.
    for _, part in ipairs(placed.parts or {}) do part:Destroy() end
    placed.parts = {}
    placed.coord = coord
    placed.kind = kind
    placed.loc = nil
    -- Raw models and Locs have no exposed bounds. NPCs can use their overlay height.
    placed.height = npc and (npc.overlayHeight > 0 and npc.overlayHeight or 700) or 700
    placed.distance = math.max(1200, placed.height * 2.5)
    placed.cameraYaw = nil
    placed.offset = nil
    placed.yaw, placed.pitch = state.yaw, state.pitch
    -- Each tab remembers its own Seq. Loc shapes can contain several models.
    if kind == "loc" then
        placement.setLoc(ids, loc, state.locSeqId)
    elseif kind == "models" then
        placed.model:SetModel(ui.ModelType.MODEL, state.assetId)
        placed.model.animID = state.assetSeqId or -1
    else
        placed.model:SetModel(ui.ModelType.NPC_MODEL, state.npcId)
        placed.model.animID = state.seqId or -1
    end
    applyTransform()
    drawPlaced()
    local name = kind == "loc" and "Loc" or (kind == "models" and "Model" or "NPC")
    setStatus(name .. " placed on the selected tile.")
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
