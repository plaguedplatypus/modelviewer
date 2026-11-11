local modelviewer = require("src/modelviewer")
local fonts = require("src/fonts")

local ribbon

local function onRibbonOpened(event)
    -- The host may already have cleared the previous ribbon content.
    if ribbon then pcall(function() ribbon:Destroy() end) end
    ribbon = prettyui.SimpleView.new(event.component, {
        width = event.component.width,
        height = event.component.height,
    })
    ribbon:AddTitle("Model Viewer")
    ribbon:AddText({ text = "Search NPCs, Locs, Seqs, and raw model assets in a separate window." })
    ribbon:AddFancyButton("Open Viewer", modelviewer.openWindow, {
        variant = "positive", width = event.component.width - 64,
    })
    ribbon:AddText({ text = "Preview fonts in a separate window." })
    ribbon:AddFancyButton("Font Viewer", fonts.openWindow, {
        width = event.component.width - 64,
    })
end

Event.ContentLayerReady.Subscribe("modelview_ribbon", onRibbonOpened)

function PluginShutdown()
    modelviewer.shutdown()
    fonts.shutdown()
    Event.ContentLayerReady.Unsubscribe("modelview_ribbon")
    if ribbon then pcall(function() ribbon:Destroy() end) end
end
