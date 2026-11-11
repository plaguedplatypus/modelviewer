local search = require("src/search")

local viewer = {}
local window
local defaultBackground = 0x1B1917
local backgroundColour = defaultBackground
local defaultFontColour = 0xE8DDC7
local fontColour = defaultFontColour

local function label(parent, content, x, y, width, colour)
    local text = ui.Text.new(parent)
    text:SetPos(x, y)
    text:SetSize(width, 24)
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
    input:Setup(ui.TextContentVisibilityMode.VISIBLE, ui.InputFieldFilterMode.NONE, 160)
    input.content = content
    return input
end

local function button(parent, caption, x, y, width, pressed)
    local control = ui.Button.new(parent)
    control:SetPos(x, y)
    control:SetSize(width, 30)
    control.stylesheetID = id.StyleSheet.BUTTON_DEFAULT
    control.label = caption
    control:Subscribe(ui.Hook.ONBUTTONPRESSED, pressed)
    return control
end

-- The text component does not break a long unspaced word by itself. Use the
-- chosen font's widths so glyph samples stay inside the preview panel.
local function wrap(font, content, width)
    local lines = {}
    for _, line in ipairs(font:SplitString(content, width, true, false)) do
        if font:GetStringWidth(line, true) > width then
            for _, part in ipairs(font:SplitString(line, width, true, true)) do
                lines[#lines + 1] = part
            end
        else
            lines[#lines + 1] = line
        end
    end
    return table.concat(lines, "\n")
end

function viewer.openWindow()
    if window and window.root and ui.Interfaces:GetInterface(window.interfaceID) then
        window:Show()
        return
    end
    window = nil
    local names = search.load("Font")
    local parent = ui.Interfaces:GetComponent(id.Component.TOPLEVEL_V2__PLUGIN_BUILD_LAYER_TOP)
    window = prettyui.Window.new(parent, {
        title = "Font Viewer",
        width = 760,
        height = 600,
        minWidth = 760,
        minHeight = 600,
        xAnchor = 0.5,
        yAnchor = 0.5,
        x = -380,
        y = -300,
        resizable = false,
        destroyOnClose = false,
    })
    local content = window.content
    local status = label(content, "", 12, 500, 724)
    status:SetPos(12, -34, 0, 1)
    status:SetSize(-18, 22, 1, 0)

    local count = label(content, "", 12, 10, 296, 0xF3C971FF)
    local query = field(content, "", 12, 39, 214)
    query.emptyText = "Font ID or name"
    local list = ui.List.new(content)
    list:SetPos(12, 80)
    list:SetSize(296, 420)
    list.stylesheetID = id.StyleSheet.DROPDOWN_DEFAULT
    list.dropdownMaxVisibleEntries = 0
    list.entryHeight = 24
    list.maxSelected = 1

    label(content, "Preview text", 336, 10, 390, 0xF3C971FF)
    local sample = field(content, "The quick brown fox jumps over the lazy dog 0123456789", 336, 39, 390)
    local chosen = label(content, "Select a font", 336, 85, 390, 0xF3C971FF)
    local panel = ui.Rectangle.new(content)
    panel:SetPos(336, 120)
    panel:SetSize(390, 320)
    panel.fill = true
    panel.rgba = backgroundColour * 256 + 255
    panel.clickthrough = true
    local preview = label(content, "", 344, 128, 374)
    preview:SetSize(374, 304)
    preview.maxLines = 0
    preview.rgba = fontColour * 256 + 255
    local selectedId

    local function updateSample()
        if not selectedId then return end
        local font = config.Font.FromID(selectedId)
        if not font then
            preview.content = ""
            status.content = "Font " .. selectedId .. " is unavailable in this cache."
            return
        end
        local contentText = wrap(font, sample.content, 366) .. "\n\n"
            .. wrap(font, "ABCDEFGHIJKLMNOPQRSTUVWXYZ", 366) .. "\n"
            .. wrap(font, "abcdefghijklmnopqrstuvwxyz", 366)
        preview.maxLines = math.min(255, math.max(1,
            math.floor((304 - font.maxAscent - font.maxDescent) / math.max(1, font.baseline))))
        preview.content = contentText
        local lineCount = select(2, contentText:gsub("\n", "")) + 1
        if lineCount > preview.maxLines then
            status.content = "Preview is clipped. Try a shorter sample or a smaller font."
        end
    end

    local function selectFont(fontId)
        selectedId = fontId
        chosen.content = fontId .. "  " .. names[fontId]
        preview.font = fontId
        status.content = "Some fonts contain only icons or special glyphs."
        updateSample()
    end

    list:Subscribe(ui.Hook.ONSELECTIONCHANGED, function(_, fontId, isSelected)
        if isSelected == 1 then selectFont(fontId) end
    end)

    local function runSearch()
        local matches = search.find(names, query.content)
        list:Clear()
        for _, fontId in ipairs(matches) do
            list:Add(fontId .. "  " .. names[fontId], fontId)
        end
        count.content = "Fonts  " .. #matches .. " results"
        if #matches == 0 then
            status.content = "No fonts match that ID or name."
        elseif #matches == 1 then
            list:SetEntrySelected(matches[1], true, false)
            selectFont(matches[1])
        elseif selectedId and list:HasEntry(selectedId) then
            list:SetEntrySelected(selectedId, true, false)
        end
    end

    button(content, "Search", 234, 39, 74, runSearch)
    label(content, "Background", 336, 453, 96)
    local backgroundPicker = prettyui.ColourPicker.new(content, {
        x = 432, y = 452, buttonSize = 26,
        value = backgroundColour * 256 + 255,
        alphaSlider = false,
        windowTitle = "Font preview background",
        onChange = function(_, colour)
            backgroundColour = math.floor(colour / 256)
            panel.rgba = backgroundColour * 256 + 255
        end,
    })
    label(content, "Font colour", 490, 453, 96)
    local fontPicker = prettyui.ColourPicker.new(content, {
        x = 576, y = 452, buttonSize = 26,
        value = fontColour * 256 + 255,
        alphaSlider = false,
        windowTitle = "Font preview colour",
        onChange = function(_, colour)
            fontColour = math.floor(colour / 256)
            preview.rgba = fontColour * 256 + 255
        end,
    })
    button(content, "Reset colours", 616, 450, 110, function()
        backgroundPicker:SetValue(defaultBackground * 256 + 255)
        fontPicker:SetValue(defaultFontColour * 256 + 255)
        backgroundColour = defaultBackground
        fontColour = defaultFontColour
        panel.rgba = defaultBackground * 256 + 255
        preview.rgba = defaultFontColour * 256 + 255
    end)
    button(content, "Update sample", 336, 485, 160, updateSample)
    runSearch()
    if names[id.Font.MUSEO_SANS_15PT_REGULAR] then
        list:SetEntrySelected(id.Font.MUSEO_SANS_15PT_REGULAR, true, false)
        selectFont(id.Font.MUSEO_SANS_15PT_REGULAR)
    end
    window:Show()
end

function viewer.shutdown()
    if window then window:Destroy() end
end

return viewer
