local placement = require("src/placement")

local selection = {}
local locConfig
local parts = {}


-- Each tab keeps its own Seq while sharing the preview and placed model.
local seqFields = { npc = "seqId", models = "assetSeqId", loc = "locSeqId" }
local seqStatus = {
    npc = "Seq applied. An incompatible skeleton may show no movement.",
    models = "Seq applied to model. An incompatible rig may show no movement.",
    loc = "Seq applied to Loc models. Some models may not animate.",
}

-- A Seq in the catalog may be absent from this game cache. Check it before
-- replacing the animation currently shown in the preview.
function selection.setSeq(view, kind, seqId)
    if not config.Seq.FromID(seqId) then
        view.setStatus("Seq " .. seqId .. " is unavailable in this game cache.")
        return
    end

    view.state[seqFields[kind]] = seqId
    view.model.animID = seqId
    if kind == "loc" then
        for _, part in ipairs(parts) do part.animID = seqId end
    end
    placement.setAnimation(kind, seqId)
    view.seqInfo.content = "Seq " .. seqId .. "  " .. view.names.seq[seqId]
    view.setStatus(seqStatus[kind])
end

function selection.clearSeq(view, kind)
    view.state[seqFields[kind]] = nil
    view.model.animID = -1
    if kind == "loc" then
        for _, part in ipairs(parts) do part.animID = -1 end
    end
    placement.setAnimation(kind, -1)
end

-- The catalog lists IDs from the client, but the active cache decides whether
-- a particular NPC can be drawn.
function selection.selectNpc(view, npcId)
    local npcConfig = config.NPC.FromID(npcId)
    if not npcConfig then
        view.setStatus("NPC " .. npcId .. " is unavailable in this game cache.")
        return
    end

    local state = view.state
    -- Returning from another tab keeps the chosen framing. A different NPC
    -- starts centered with a distance estimated from its overlay height.
    if state.npcId ~= npcId then
        state.npcDistance = nil
        state.pan.npc.x, state.pan.npc.y = 0, 0
    end
    state.npcId = npcId
    -- The overlay height can be absent or unrelated to a particular pose.
    state.height = npcConfig.overlayHeight > 0 and npcConfig.overlayHeight or 700

    view.model:SetModel(ui.ModelType.NPC_MODEL, npcId)
    -- Keep the selected Seq while comparing NPCs. A different skeleton may
    -- display that same animation differently or not move at all.
    view.model.animID = state.seqId or -1
    placement.setAsset("npc", npcId, view.model.animID, state.height)
    view.setDistance(state.npcDistance or math.max(1200, state.height * 2.5))
    view.info.content = "NPC " .. npcId .. "  " .. view.names.npc[npcId]
    view.seqInfo.content = state.seqId and ("Seq " .. state.seqId .. "  " .. view.names.seq[state.seqId])
        or "No Seq selected"
    view.setStatus("NPC loaded. Select a Seq to animate it.")
end

function selection.selectModel(view, assetId)
    local state = view.state
    if state.assetId ~= assetId then
        state.assetDistance = nil
        state.pan.models.x, state.pan.models.y = 0, 0
    end
    state.assetId = assetId
    -- Plain model IDs have no config object with bounds or cache validation.
    -- Start from a neutral camera and let the user adjust unusual assets.
    state.height = 700

    view.model:SetModel(ui.ModelType.MODEL, assetId)
    view.model.animID = state.assetSeqId or -1
    placement.setAsset("models", assetId, view.model.animID, state.height)
    view.setDistance(state.assetDistance or math.max(1200, state.height * 2.5))
    view.info.content = "Model " .. assetId .. "  " .. view.names.models[assetId]
    view.seqInfo.content = state.assetSeqId and ("Seq " .. state.assetSeqId .. "  " .. view.names.seq[state.assetSeqId])
        or "No Seq selected"
    view.setStatus("Model asset selected. Use camera distance to adjust the preview.")
end

function selection.clearParts()
    for _, part in ipairs(parts) do part:Destroy() end
    parts = {}
end

local shapeNames = {
    [0] = "WALL_STRAIGHT", [1] = "WALL_DIAGONALCORNER", [2] = "WALL_L",
    [3] = "WALL_SQUARECORNER", [4] = "WALLDECOR_STRAIGHT_NOOFFSET",
    [5] = "WALLDECOR_STRAIGHT_OFFSET", [6] = "WALLDECOR_DIAGONAL_OFFSET",
    [7] = "WALLDECOR_DIAGONAL_NOOFFSET", [8] = "WALLDECOR_DIAGONAL_BOTH",
    [9] = "WALL_DIAGONAL", [10] = "CENTREPIECE_STRAIGHT",
    [11] = "CENTREPIECE_DIAGONAL", [12] = "ROOF_STRAIGHT",
    [13] = "ROOF_DIAGONAL_WITH_ROOFEDGE", [14] = "ROOF_DIAGONAL",
    [15] = "ROOF_L_CONCAVE", [16] = "ROOF_L_CONVEX",
    [17] = "ROOF_FLAT", [18] = "ROOFEDGE_STRAIGHT",
    [19] = "ROOFEDGE_DIAGONALCORNER", [20] = "ROOFEDGE_L",
    [21] = "ROOFEDGE_SQUARECORNER", [22] = "GROUNDDECOR",
    [23] = "WALL_L_ALT", [24] = "WALLDECOR_DIAGONAL_BOTH_ALT",
}

-- The host can remove the previous window on reload. Its components are
-- already gone, so forget their references before building the new preview.
function selection.reset()
    parts = {}
    locConfig = nil
end

-- A Loc can use several model IDs, and each supported shape can use a
-- different set. Draw those IDs together in the same preview group.
local function setShape(view)
    selection.clearParts()
    local state = view.state
    local shapes = locConfig.locShapeTypes
    local shape = shapes[state.shapeIndex]
    state.height = 700
    view.info.content = "Loc " .. state.locId .. "  " .. view.names.loc[state.locId]

    if not shape then
        placement.setLoc(nil)
        view.model:SetModel(ui.ModelType.NONE, 0)
        view.model.animID = -1
        view.shapeInfo.content = locConfig.isMultiLoc and "MultiLoc: no direct shape" or "No model shapes"
        view.shapePage.content = "0 / 0"
        view.seqInfo.content = "No model for this Loc"
        view.setDistance(state.locDistance or 1750)
        view.setStatus("This Loc has no direct model to preview.")
        return
    end

    view.shapeInfo.content = (shapeNames[shape] or "Shape") .. " (" .. shape .. ")"
    view.shapePage.content = state.shapeIndex .. " / " .. #shapes
    local ids = locConfig:GetModelIDs(shape)
    if #ids == 0 then
        placement.setLoc(nil)
        view.model:SetModel(ui.ModelType.NONE, 0)
        view.model.animID = -1
        view.seqInfo.content = "No model for this shape"
        view.setDistance(state.locDistance or 1750)
        view.setStatus("This shape has no model to preview.")
        return
    end

    view.model:SetModel(ui.ModelType.MODEL, ids[1])
    view.model.animID = state.locSeqId or -1
    for index = 2, #ids do
        local part = ui.Model.new(view.group)
        part:SetSize(0, 0, 1, 1)
        part.clickthrough = true
        part:SetModel(ui.ModelType.MODEL, ids[index])
        part.animID = view.model.animID
        parts[#parts + 1] = part
    end
    placement.setLoc(ids, locConfig, state.locSeqId)
    view.seqInfo.content = state.locSeqId and ("Seq " .. state.locSeqId .. "  " .. view.names.seq[state.locSeqId])
        or "No Seq selected"
    view.setDistance(state.locDistance or 1750)
    view.setStatus("Loc shape loaded. Use camera distance to adjust the preview.")
end

function selection.selectLoc(view, locId)
    local found = config.Loc.FromID(locId)
    if not found then
        view.setStatus("Loc " .. locId .. " is unavailable in this game cache.")
        return
    end
    local state = view.state
    if state.locId ~= locId then
        state.locDistance = nil
        state.pan.loc.x, state.pan.loc.y = 0, 0
        state.shapeIndex = 1
    end
    state.locId = locId
    locConfig = found
    setShape(view)
end

function selection.stepShape(view, delta)
    if not locConfig then return end
    local count = #locConfig.locShapeTypes
    if count == 0 then return end
    view.state.shapeIndex = ((view.state.shapeIndex - 1 + delta) % count) + 1
    setShape(view)
end

function selection.applyLocTransform(view, position, rotation)
    local scale = Vector3.new(1, 1, 1)
    if locConfig then
        -- Loc offsets apply before scale, followed by the post-offset.
        local offset, post = locConfig.modelOffset, locConfig.modelPostOffset
        scale = locConfig.modelScale
        position = Vector3.new(
            position.x + offset.x * scale.x + post.x,
            position.y + offset.y * scale.y + post.y,
            position.z + offset.z * scale.z + post.z
        )
    end
    view.model:SetTransform(position, rotation, scale, 0)
    for _, part in ipairs(parts) do
        part:SetTransform(position, rotation, scale, 0)
    end
end

return selection
