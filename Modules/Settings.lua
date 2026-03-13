---@diagnostic disable: undefined-field, inject-field, param-type-mismatch

local _, addonTable = ...
local Preydator = _G.Preydator or addonTable

local SettingsModule = {}
Preydator:RegisterModule("Settings", SettingsModule)

local api = Preydator.API
local constants = Preydator.Constants

local Settings = _G.Settings
local CreateFrame = _G.CreateFrame
local UIParent = _G.UIParent
local UIDropDownMenu_Initialize = _G.UIDropDownMenu_Initialize
local UIDropDownMenu_CreateInfo = _G.UIDropDownMenu_CreateInfo
local UIDropDownMenu_SetWidth = _G.UIDropDownMenu_SetWidth
local UIDropDownMenu_SetText = _G.UIDropDownMenu_SetText
local UIDropDownMenu_AddButton = _G.UIDropDownMenu_AddButton
local ColorPickerFrame = _G.ColorPickerFrame
local OpacitySliderFrame = _G.OpacitySliderFrame

local COLUMN_LEFT_X = 18
local COLUMN_RIGHT_X = 364
local CONTROL_WIDTH = 250
local TAB_WIDTH = 120
local PANEL_WIDTH = 760
local PANEL_HEIGHT = 620

local TEXTURE_OPTIONS = {
    default = { text = "Default" },
    flat = { text = "Flat" },
    raid = { text = "Raid HP Fill" },
    classic = { text = "Classic Skill Bar" },
}

local FONT_OPTIONS = {
    frizqt = { text = "Friz Quadrata" },
    arialn = { text = "Arial Narrow" },
    skurri = { text = "Skurri" },
    morpheus = { text = "Morpheus" },
}

local CHANNEL_OPTIONS = {
    Master = { text = "Master" },
    SFX = { text = "SFX" },
    Dialog = { text = "Dialog" },
    Ambience = { text = "Ambience" },
}

local PERCENT_DISPLAY_OPTIONS = {
    [constants.PERCENT_DISPLAY_INSIDE] = { text = "In Bar (Above Fill)" },
    [constants.PERCENT_DISPLAY_INSIDE_BELOW] = { text = "In Bar (Below Fill)" },
    [constants.PERCENT_DISPLAY_UNDER_TICKS] = { text = "Under Ticks" },
    [constants.PERCENT_DISPLAY_BELOW_BAR] = { text = "Below Bar" },
    [constants.PERCENT_DISPLAY_OFF] = { text = "Off" },
}

local LAYER_MODE_OPTIONS = {
    [constants.LAYER_MODE_ABOVE] = { text = "Above Fill" },
    [constants.LAYER_MODE_BELOW] = { text = "Below Fill" },
}

local PROGRESS_SEGMENT_OPTIONS = {
    [constants.PROGRESS_SEGMENTS_QUARTERS] = { text = "Quarters (25/50/75/100)" },
    [constants.PROGRESS_SEGMENTS_THIRDS] = { text = "Thirds (33/66/100)" },
}

local LABEL_MODE_OPTIONS = {
    [constants.LABEL_MODE_CENTER]       = { text = "Centered" },
    [constants.LABEL_MODE_LEFT]         = { text = "Left (Prefix only)" },
    [constants.LABEL_MODE_LEFT_SUFFIX]  = { text = "Left (Suffix only)" },
    [constants.LABEL_MODE_RIGHT]        = { text = "Right (Suffix only)" },
    [constants.LABEL_MODE_RIGHT_PREFIX] = { text = "Right (Prefix only)" },
    [constants.LABEL_MODE_SEPARATE]     = { text = "Separate (Prefix + Suffix)" },
    [constants.LABEL_MODE_NONE]         = { text = "No Text" },
}

local function Clamp(value, minValue, maxValue)
    return math.max(minValue, math.min(maxValue, value))
end

local function RoundToStep(value, step)
    if not step or step <= 0 then
        return value
    end

    return math.floor((value / step) + 0.5) * step
end

local function NormalizeSliderValue(value, minValue, maxValue, step)
    local numeric = tonumber(value)
    if not numeric then
        return nil
    end

    numeric = Clamp(numeric, minValue, maxValue)
    numeric = RoundToStep(numeric, step)
    return Clamp(numeric, minValue, maxValue)
end

local function OpenColorPicker(initial, allowAlpha, callback)
    if not ColorPickerFrame then
        return
    end

    local start = {
        initial[1] or 1,
        initial[2] or 1,
        initial[3] or 1,
        initial[4] or 1,
    }

    local function applyFromPicker()
        local r, g, b
        if ColorPickerFrame.GetColorRGB then
            r, g, b = ColorPickerFrame:GetColorRGB()
        elseif ColorPickerFrame.Content and ColorPickerFrame.Content.ColorPicker and ColorPickerFrame.Content.ColorPicker.GetColorRGB then
            r, g, b = ColorPickerFrame.Content.ColorPicker:GetColorRGB()
        else
            r, g, b = start[1], start[2], start[3]
        end

        local a = start[4]
        if allowAlpha then
            if ColorPickerFrame.GetColorAlpha then
                a = ColorPickerFrame:GetColorAlpha()
            elseif OpacitySliderFrame and OpacitySliderFrame.GetValue then
                a = 1 - OpacitySliderFrame:GetValue()
            end
        end

        callback({ r, g, b, a })
    end

    local function cancelColor(previousValues)
        local pr = start[1]
        local pg = start[2]
        local pb = start[3]
        local pa = start[4]

        if type(previousValues) == "table" then
            pr = previousValues.r or previousValues[1] or pr
            pg = previousValues.g or previousValues[2] or pg
            pb = previousValues.b or previousValues[3] or pb
            pa = previousValues.a or previousValues[4] or pa
        end

        callback({ pr, pg, pb, pa })
    end

    if ColorPickerFrame.SetupColorPickerAndShow then
        ColorPickerFrame:SetupColorPickerAndShow({
            r = start[1],
            g = start[2],
            b = start[3],
            opacity = allowAlpha and start[4] or 0,
            hasOpacity = allowAlpha and true or false,
            swatchFunc = applyFromPicker,
            opacityFunc = applyFromPicker,
            cancelFunc = cancelColor,
            func = applyFromPicker,
        })
        return
    end

    ColorPickerFrame.hasOpacity = allowAlpha and true or false
    ColorPickerFrame.opacity = allowAlpha and (1 - start[4]) or 0
    ColorPickerFrame.previousValues = { start[1], start[2], start[3], start[4] }
    ColorPickerFrame.func = applyFromPicker
    ColorPickerFrame.swatchFunc = applyFromPicker
    ColorPickerFrame.opacityFunc = applyFromPicker
    ColorPickerFrame.cancelFunc = cancelColor

    if ColorPickerFrame.SetColorRGB then
        ColorPickerFrame:SetColorRGB(start[1], start[2], start[3])
    end

    ColorPickerFrame:Hide()
    ColorPickerFrame:Show()
end

local function CreateSectionTitle(parent, x, y, text)
    local title = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    title:SetText(text)
    return title
end

local function CreateCheckbox(parent, x, y, label, getter, setter)
    local check = CreateFrame("CheckButton", nil, parent, "InterfaceOptionsCheckButtonTemplate")
    check:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    check.Text:SetText(label)
    check:SetChecked(getter() and true or false)
    check:SetScript("OnClick", function(self)
        setter(self:GetChecked() and true or false)
    end)

    function check:PreydatorRefresh()
        self:SetChecked(getter() and true or false)
    end

    return check
end

local function CreateSlider(parent, x, y, label, minValue, maxValue, step, getter, setter, formatValue)
    local container = CreateFrame("Frame", nil, parent)
    container:SetSize(CONTROL_WIDTH + 28, 56)
    container:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)

    local title = container:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", 0, 0)
    title:SetText(label)

    local slider = CreateFrame("Slider", nil, container, "OptionsSliderTemplate")
    slider:SetPoint("TOPLEFT", 0, -18)
    slider:SetWidth(170)
    slider:SetMinMaxValues(minValue, maxValue)
    slider:SetValueStep(step)
    slider:SetObeyStepOnDrag(true)
    if slider.Low then slider.Low:Hide() end
    if slider.High then slider.High:Hide() end

    local valueBox = CreateFrame("EditBox", nil, container, "InputBoxTemplate")
    valueBox:SetSize(52, 20)
    valueBox:SetPoint("LEFT", slider, "RIGHT", 12, 0)
    valueBox:SetAutoFocus(false)
    valueBox:SetTextInsets(6, 6, 0, 0)
    valueBox:SetJustifyH("CENTER")

    local formatter = formatValue or function(value)
        if step < 1 then
            return string.format("%.2f", value)
        end
        return tostring(math.floor(value + 0.5))
    end

    local function RefreshFromValue(rawValue)
        local normalized = NormalizeSliderValue(rawValue, minValue, maxValue, step)
        if normalized == nil then
            normalized = getter()
        end
        slider:SetValue(normalized)
        valueBox:SetText(formatter(normalized))
    end

    slider:SetScript("OnValueChanged", function(self, value)
        local normalized = NormalizeSliderValue(value, minValue, maxValue, step)
        if normalized == nil then
            return
        end

        valueBox:SetText(formatter(normalized))
        setter(normalized)
    end)

    valueBox:SetScript("OnEnterPressed", function(self)
        local normalized = NormalizeSliderValue(self:GetText(), minValue, maxValue, step)
        if normalized == nil then
            self:SetText(formatter(getter()))
            self:ClearFocus()
            return
        end

        slider:SetValue(normalized)
        self:ClearFocus()
    end)

    valueBox:SetScript("OnEditFocusLost", function(self)
        self:SetText(formatter(getter()))
    end)

    function container:PreydatorRefresh()
        RefreshFromValue(getter())
    end

    container:PreydatorRefresh()
    return container
end

local function CreateDropdown(parent, x, y, label, width, options, getter, setter)
    local title = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    title:SetText(label)

    local dropdown = CreateFrame("Frame", nil, parent, "UIDropDownMenuTemplate")
    dropdown:SetPoint("TOPLEFT", title, "BOTTOMLEFT", -16, -4)

    local function GetOptions()
        if type(options) == "function" then
            return options() or {}
        end
        return options or {}
    end

    local function RefreshText()
        local selected = getter()
        local entry = GetOptions()[selected]
        UIDropDownMenu_SetText(dropdown, entry and entry.text or "Select")
    end

    UIDropDownMenu_SetWidth(dropdown, width)
    UIDropDownMenu_Initialize(dropdown, function()
        local optionList = {}
        for key, entry in pairs(GetOptions()) do
            optionList[#optionList + 1] = { key = key, entry = entry }
        end

        table.sort(optionList, function(left, right)
            return tostring(left.entry and left.entry.text or "") < tostring(right.entry and right.entry.text or "")
        end)

        for _, item in ipairs(optionList) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = item.entry.text
            info.func = function()
                setter(item.key)
                RefreshText()
            end
            info.checked = getter() == item.key
            UIDropDownMenu_AddButton(info)
        end
    end)

    dropdown.PreydatorRefresh = RefreshText
    RefreshText()
    return dropdown
end

local function CreateTextInput(parent, x, y, label, width, getter, setter)
    local labelText = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    labelText:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    labelText:SetText(label)

    local edit = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    edit:SetSize(width, 20)
    edit:SetAutoFocus(false)
    edit:SetTextInsets(6, 6, 0, 0)
    edit:SetPoint("TOPLEFT", labelText, "BOTTOMLEFT", 0, -6)
    edit:SetText(getter() or "")
    edit:SetScript("OnEnterPressed", function(self)
        setter(self:GetText())
        self:SetText(getter() or "")
        self:ClearFocus()
    end)
    edit:SetScript("OnEditFocusLost", function(self)
        setter(self:GetText())
        self:SetText(getter() or "")
    end)

    function edit:PreydatorRefresh()
        self:SetText(getter() or "")
    end

    return edit
end

local function CreateColorButton(parent, x, y, label, getter, setter, allowAlpha)
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetSize(170, 22)
    button:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    button:SetText(label)

    local swatch = button:CreateTexture(nil, "OVERLAY")
    swatch:SetSize(18, 18)
    swatch:SetPoint("LEFT", button, "RIGHT", 8, 0)

    local function RefreshSwatch()
        local color = getter()
        swatch:SetColorTexture(color[1], color[2], color[3], (allowAlpha and color[4]) or 1)
    end

    button:SetScript("OnClick", function()
        OpenColorPicker(getter(), allowAlpha, function(color)
            setter({ color[1], color[2], color[3], color[4] })
            RefreshSwatch()
        end)
    end)

    button.PreydatorRefresh = RefreshSwatch
    RefreshSwatch()
    return button
end

local function CreateActionButton(parent, x, y, width, text, onClick)
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetSize(width, 24)
    button:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    button:SetText(text)
    button:SetScript("OnClick", onClick)
    return button
end

local function CreateCustomTabs(parent, labels, onSelect)
    local tabs = {}
    for index, label in ipairs(labels) do
        local tab = CreateFrame("Button", nil, parent)
        tab:SetSize(TAB_WIDTH, 28)
        if index == 1 then
            tab:SetPoint("TOPLEFT", parent, "TOPLEFT", 16, -72)
        else
            tab:SetPoint("LEFT", tabs[index - 1], "RIGHT", 4, 0)
        end

        local background = tab:CreateTexture(nil, "BACKGROUND")
        background:SetAllPoints()
        background:SetColorTexture(0.18, 0.18, 0.18, 0.9)
        tab.PreydatorBackground = background

        local text = tab:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        text:SetPoint("CENTER")
        text:SetText(label)
        tab.PreydatorText = text

        local highlight = tab:CreateTexture(nil, "HIGHLIGHT")
        highlight:SetAllPoints()
        highlight:SetColorTexture(0.45, 0.45, 0.45, 0.4)

        tab:SetScript("OnClick", function()
            onSelect(index)
        end)

        tabs[index] = tab
    end

    return tabs
end

local function RegisterRefresher(owner, control)
    owner.refreshers[#owner.refreshers + 1] = control
    return control
end

local function BuildGeneralPage(owner, parent)
    local db = api.GetSettings()
    CreateSectionTitle(parent, COLUMN_LEFT_X, -10, "Visibility")
    RegisterRefresher(owner, CreateCheckbox(parent, COLUMN_LEFT_X, -38, "Lock Bar", function() return db.locked end, function(value)
        db.locked = value
        api.ApplyBarSettings()
    end))
    RegisterRefresher(owner, CreateCheckbox(parent, COLUMN_LEFT_X, -66, "Only show in prey zone", function() return db.onlyShowInPreyZone end, function(value)
        db.onlyShowInPreyZone = value
        api.UpdateBarDisplay()
    end))
    RegisterRefresher(owner, CreateCheckbox(parent, COLUMN_LEFT_X, -94, "Disable Default Prey Icon", function() return db.disableDefaultPreyIcon == true end, function(value)
        db.disableDefaultPreyIcon = value
        api.ApplyDefaultPreyIconVisibility()
        api.UpdateBarDisplay()
    end))
    RegisterRefresher(owner, CreateCheckbox(parent, COLUMN_LEFT_X, -122, "Show in Edit Mode preview", function() return db.showInEditMode ~= false end, function(value)
        db.showInEditMode = value
        api.NormalizeDisplaySettings()
        api.UpdateBarDisplay()
    end))

    CreateSectionTitle(parent, COLUMN_RIGHT_X, -10, "Behavior")
    RegisterRefresher(owner, CreateCheckbox(parent, COLUMN_RIGHT_X, -38, "Enable sounds", function() return db.soundsEnabled end, function(value)
        db.soundsEnabled = value
    end))
    RegisterRefresher(owner, CreateCheckbox(parent, COLUMN_RIGHT_X, -66, "Ambush sound alert", function() return db.ambushSoundEnabled ~= false end, function(value)
        db.ambushSoundEnabled = value
    end))
    RegisterRefresher(owner, CreateCheckbox(parent, COLUMN_RIGHT_X, -94, "Ambush visual alert", function() return db.ambushVisualEnabled ~= false end, function(value)
        db.ambushVisualEnabled = value
        if not value then
            api.GetState().ambushAlertUntil = 0
            api.UpdateBarDisplay()
        end
    end))
    RegisterRefresher(owner, CreateCheckbox(parent, COLUMN_RIGHT_X, -122, "Show tick marks", function() return db.showTicks end, function(value)
        db.showTicks = value
        api.RequestBarRefresh()
    end))
    RegisterRefresher(owner, CreateDropdown(parent, COLUMN_RIGHT_X, -164, "Progress Segments", 170, PROGRESS_SEGMENT_OPTIONS, function()
        return db.progressSegments
    end, function(key)
        db.progressSegments = key
        api.NormalizeProgressSettings()
        api.RequestBarRefresh()
    end))
    RegisterRefresher(owner, CreateDropdown(parent, COLUMN_RIGHT_X, -228, "Sound Channel", 170, CHANNEL_OPTIONS, function()
        return db.soundChannel
    end, function(key)
        db.soundChannel = key
    end))
end

local function BuildDisplayPage(owner, parent)
    local db = api.GetSettings()
    CreateSectionTitle(parent, COLUMN_LEFT_X, -10, "Bar Size")
    RegisterRefresher(owner, CreateSlider(parent, COLUMN_LEFT_X, -40, "Scale", 0.5, 2, 0.05, function() return db.scale end, function(value)
        db.scale = value
        api.ApplyBarSettings()
    end, function(value) return string.format("%.2f", value) end))
    RegisterRefresher(owner, CreateSlider(parent, COLUMN_LEFT_X, -100, "Width", 160, 500, 1, function() return db.width end, function(value)
        db.width = math.floor(value + 0.5)
        api.RequestBarRefresh()
    end, function(value) return tostring(math.floor(value + 0.5)) end))
    RegisterRefresher(owner, CreateSlider(parent, COLUMN_LEFT_X, -160, "Height", 10, 40, 1, function() return db.height end, function(value)
        db.height = math.floor(value + 0.5)
        api.RequestBarRefresh()
    end, function(value) return tostring(math.floor(value + 0.5)) end))
    RegisterRefresher(owner, CreateSlider(parent, COLUMN_LEFT_X, -220, "Font Size", 8, 24, 1, function() return db.fontSize end, function(value)
        db.fontSize = math.floor(value + 0.5)
        api.RequestBarRefresh()
    end, function(value) return tostring(math.floor(value + 0.5)) end))

    CreateSectionTitle(parent, COLUMN_LEFT_X, -286, "Progress Display")
    RegisterRefresher(owner, CreateDropdown(parent, COLUMN_LEFT_X, -316, "Percent Display", 170, PERCENT_DISPLAY_OPTIONS, function()
        return db.percentDisplay
    end, function(key)
        db.percentDisplay = key
        api.NormalizeDisplaySettings()
        api.RequestBarRefresh()
    end))
    RegisterRefresher(owner, CreateDropdown(parent, COLUMN_LEFT_X, -380, "Tick Mark Layer", 170, LAYER_MODE_OPTIONS, function()
        return db.tickLayerMode
    end, function(key)
        db.tickLayerMode = key
        api.NormalizeDisplaySettings()
        api.RequestBarRefresh()
    end))
    RegisterRefresher(owner, CreateCheckbox(parent, COLUMN_LEFT_X, -444, "Display Spark Line", function()
        return db.showSparkLine == true
    end, function(value)
        db.showSparkLine = value and true or false
        api.NormalizeDisplaySettings()
        api.RequestBarRefresh()
    end))

    CreateSectionTitle(parent, COLUMN_RIGHT_X, -10, "Visual Style")
    RegisterRefresher(owner, CreateDropdown(parent, COLUMN_RIGHT_X, -40, "Texture", 170, TEXTURE_OPTIONS, function()
        return db.textureKey
    end, function(key)
        db.textureKey = key
        api.ApplyBarSettings()
    end))
    RegisterRefresher(owner, CreateDropdown(parent, COLUMN_RIGHT_X, -104, "Title Font", 170, FONT_OPTIONS, function()
        return db.titleFontKey
    end, function(key)
        db.titleFontKey = key
        api.ApplyBarSettings()
    end))
    RegisterRefresher(owner, CreateDropdown(parent, COLUMN_RIGHT_X, -168, "Percent Font", 170, FONT_OPTIONS, function()
        return db.percentFontKey
    end, function(key)
        db.percentFontKey = key
        api.ApplyBarSettings()
    end))
    RegisterRefresher(owner, CreateColorButton(parent, COLUMN_RIGHT_X, -232, "Fill Color", function() return db.fillColor end, function(color)
        db.fillColor = color
        api.ApplyBarSettings()
    end, true))
    RegisterRefresher(owner, CreateColorButton(parent, COLUMN_RIGHT_X, -266, "Background Color", function() return db.bgColor end, function(color)
        db.bgColor = color
        api.ApplyBarSettings()
    end, true))
    RegisterRefresher(owner, CreateColorButton(parent, COLUMN_RIGHT_X, -300, "Title Color", function() return db.titleColor end, function(color)
        db.titleColor = color
        api.RequestBarRefresh()
    end, true))
    RegisterRefresher(owner, CreateColorButton(parent, COLUMN_RIGHT_X, -334, "Percent Color", function() return db.percentColor end, function(color)
        db.percentColor = color
        api.RequestBarRefresh()
    end, true))
    RegisterRefresher(owner, CreateColorButton(parent, COLUMN_RIGHT_X, -368, "Tick Mark Color", function() return db.tickColor end, function(color)
        db.tickColor = color
        api.RequestBarRefresh()
    end, true))
    RegisterRefresher(owner, CreateColorButton(parent, COLUMN_RIGHT_X, -402, "Border Color", function()
        if db.borderColorLinked == false and db.borderColor then
            return db.borderColor
        end
        return db.fillColor
    end, function(color)
        db.borderColor = color
        db.borderColorLinked = false
        api.NormalizeColorSettings()
        api.ApplyBarSettings()
    end, true))
    local borderLinkCheck = CreateCheckbox(parent, COLUMN_RIGHT_X, -436, "Link border color to fill", function()
        return db.borderColorLinked ~= false
    end, function(value)
        db.borderColorLinked = value and true or false
        api.NormalizeColorSettings()
        api.ApplyBarSettings()
    end)
    RegisterRefresher(owner, borderLinkCheck)
end

local function BuildTextPage(owner, parent)
    local db = api.GetSettings()
    local defaults = api.GetDefaults()

    CreateSectionTitle(parent, COLUMN_LEFT_X, -10, "Label Mode")
    RegisterRefresher(owner, CreateDropdown(parent, COLUMN_LEFT_X, -40, "Label Mode", 170, LABEL_MODE_OPTIONS, function()
        return db.stageLabelMode
    end, function(key)
        db.stageLabelMode = key
        api.NormalizeDisplaySettings()
        api.RequestBarRefresh()
    end))

    CreateSectionTitle(parent, COLUMN_LEFT_X, -108, "Prefix Labels")
    for stageIndex = 1, constants.MAX_STAGE do
        local offset = -138 - ((stageIndex - 1) * 52)
        RegisterRefresher(owner, CreateTextInput(parent, COLUMN_LEFT_X, offset, "Stage " .. tostring(stageIndex), 220, function()
            if not db.stageSuffixLabels then db.stageSuffixLabels = {} end
            return db.stageSuffixLabels[stageIndex] or ""
        end, function(value)
            if not db.stageSuffixLabels then db.stageSuffixLabels = {} end
            db.stageSuffixLabels[stageIndex] = value
            api.NormalizeDisplaySettings()
            api.UpdateBarDisplay()
        end))
    end

    RegisterRefresher(owner, CreateTextInput(parent, COLUMN_LEFT_X, -346, "Out of Zone Prefix", 220, function()
        return db.outOfZonePrefix or ""
    end, function(value)
        db.outOfZonePrefix = value
        api.NormalizeLabelSettings()
        api.UpdateBarDisplay()
    end))
    RegisterRefresher(owner, CreateTextInput(parent, COLUMN_LEFT_X, -398, "Ambush Prefix", 220, function()
        return db.ambushPrefix or ""
    end, function(value)
        db.ambushPrefix = value
        api.NormalizeLabelSettings()
        api.UpdateBarDisplay()
    end))

    CreateSectionTitle(parent, COLUMN_RIGHT_X, -10, "Suffix Labels")
    for stageIndex = 1, constants.MAX_STAGE do
        local offset = -40 - ((stageIndex - 1) * 52)
        RegisterRefresher(owner, CreateTextInput(parent, COLUMN_RIGHT_X, offset, "Stage " .. tostring(stageIndex), 220, function()
            return db.stageLabels[stageIndex] or ""
        end, function(value)
            db.stageLabels[stageIndex] = value
            api.NormalizeLabelSettings()
            api.UpdateBarDisplay()
        end))
    end

    RegisterRefresher(owner, CreateTextInput(parent, COLUMN_RIGHT_X, -248, "Out of Zone Label", 220, function()
        return db.outOfZoneLabel
    end, function(value)
        db.outOfZoneLabel = value
        api.NormalizeLabelSettings()
        api.UpdateBarDisplay()
    end))
    RegisterRefresher(owner, CreateTextInput(parent, COLUMN_RIGHT_X, -300, "Ambush Override Text", 220, function()
        return db.ambushCustomText
    end, function(value)
        db.ambushCustomText = value
        api.NormalizeLabelSettings()
        api.UpdateBarDisplay()
    end))
    CreateActionButton(parent, COLUMN_RIGHT_X, -360, 180, "Restore Default Names", function()
        for stageIndex = 1, constants.MAX_STAGE do
            db.stageLabels[stageIndex] = defaults.stageLabels[stageIndex] or ""
        end
        db.outOfZoneLabel = constants.DEFAULT_OUT_OF_ZONE_LABEL
        db.ambushCustomText = ""
        api.NormalizeLabelSettings()
        api.UpdateBarDisplay()
        owner:RefreshControls()
    end)
end

local function BuildAudioPage(owner, parent)
    local db = api.GetSettings()
    CreateSectionTitle(parent, COLUMN_LEFT_X, -10, "Sound Selection")
    RegisterRefresher(owner, CreateDropdown(parent, COLUMN_LEFT_X, -40, "Stage 1 Sound", 170, function()
        return api.BuildSoundDropdownOptions()
    end, function()
        return db.stageSounds[1]
    end, function(key)
        db.stageSounds[1] = key
        api.NormalizeSoundSettings()
    end))
    RegisterRefresher(owner, CreateDropdown(parent, COLUMN_LEFT_X, -104, "Stage 2 Sound", 170, function()
        return api.BuildSoundDropdownOptions()
    end, function()
        return db.stageSounds[2]
    end, function(key)
        db.stageSounds[2] = key
        api.NormalizeSoundSettings()
    end))
    RegisterRefresher(owner, CreateDropdown(parent, COLUMN_LEFT_X, -168, "Stage 3 Sound", 170, function()
        return api.BuildSoundDropdownOptions()
    end, function()
        return db.stageSounds[3]
    end, function(key)
        db.stageSounds[3] = key
        api.NormalizeSoundSettings()
    end))
    RegisterRefresher(owner, CreateDropdown(parent, COLUMN_LEFT_X, -232, "Stage 4 Sound", 170, function()
        return api.BuildSoundDropdownOptions()
    end, function()
        return db.stageSounds[4]
    end, function(key)
        db.stageSounds[4] = key
        api.NormalizeSoundSettings()
    end))
    RegisterRefresher(owner, CreateDropdown(parent, COLUMN_LEFT_X, -296, "Ambush Sound", 170, function()
        return api.BuildSoundDropdownOptions()
    end, function()
        return db.ambushSoundPath
    end, function(key)
        db.ambushSoundPath = key
        api.NormalizeAmbushSettings()
    end))
    RegisterRefresher(owner, CreateSlider(parent, COLUMN_LEFT_X, -360, "Enhance Sounds", 0, 100, 5, function() return db.soundEnhance or 0 end, function(value)
        db.soundEnhance = math.floor(value + 0.5)
    end, function(value) return tostring(math.floor(value + 0.5)) end))

    CreateSectionTitle(parent, COLUMN_RIGHT_X, -10, "Custom Files / Tests")
    local customSoundInput = CreateTextInput(parent, COLUMN_RIGHT_X, -40, "Custom Sound File", 220, function()
        return ""
    end, function()
    end)
    customSoundInput:SetScript("OnEditFocusLost", nil)
    customSoundInput:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
    end)
    customSoundInput:SetText("")

    CreateActionButton(parent, COLUMN_RIGHT_X, -100, 105, "Add File", function()
        local ok, message = api.AddSoundFileName(customSoundInput:GetText())
        if ok then
            customSoundInput:SetText("")
            owner:RefreshControls()
            print("Preydator: Added sound file '" .. tostring(message) .. "'.")
        else
            print("Preydator: " .. tostring(message))
        end
    end)
    CreateActionButton(parent, COLUMN_RIGHT_X + 115, -100, 105, "Remove File", function()
        local ok, message = api.RemoveSoundFileName(customSoundInput:GetText())
        if ok then
            customSoundInput:SetText("")
            owner:RefreshControls()
            print("Preydator: Removed sound file '" .. tostring(message) .. "'.")
        else
            print("Preydator: " .. tostring(message))
        end
    end)
    CreateActionButton(parent, COLUMN_RIGHT_X, -148, 140, "Test Stage 1", function()
        api.GetState().stageSoundPlayed[1] = nil
        local path = api.ResolveStageSoundPath(1)
        if not path then
            print("Preydator: No stage 1 sound configured.")
            return
        end
        if not api.TryPlayStageSound(1, true) then
            print("Preydator: Stage 1 sound file failed to play. Ensure this file exists as .ogg: " .. tostring(path))
        end
    end)
    CreateActionButton(parent, COLUMN_RIGHT_X, -178, 140, "Test Stage 2", function()
        api.GetState().stageSoundPlayed[2] = nil
        local path = api.ResolveStageSoundPath(2)
        if not path then
            print("Preydator: No stage 2 sound configured.")
            return
        end
        if not api.TryPlayStageSound(2, true) then
            print("Preydator: Stage 2 sound file failed to play. Ensure this file exists as .ogg: " .. tostring(path))
        end
    end)
    CreateActionButton(parent, COLUMN_RIGHT_X, -208, 140, "Test Stage 3", function()
        api.GetState().stageSoundPlayed[3] = nil
        local path = api.ResolveStageSoundPath(3)
        if not path then
            print("Preydator: No stage 3 sound configured.")
            return
        end
        if not api.TryPlayStageSound(3, true) then
            print("Preydator: Stage 3 sound file failed to play. Ensure this file exists as .ogg: " .. tostring(path))
        end
    end)
    CreateActionButton(parent, COLUMN_RIGHT_X, -238, 140, "Test Stage 4", function()
        api.GetState().stageSoundPlayed[4] = nil
        local path = api.ResolveStageSoundPath(4)
        if not path then
            print("Preydator: No stage 4 sound configured.")
            return
        end
        if not api.TryPlayStageSound(4, true) then
            print("Preydator: Stage 4 sound file failed to play. Ensure this file exists as .ogg: " .. tostring(path))
        end
    end)
    CreateActionButton(parent, COLUMN_RIGHT_X, -268, 140, "Test Ambush", function()
        api.TriggerAmbushAlert("Manual test", "options")
    end)
    local note = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    note:SetPoint("TOPLEFT", parent, "TOPLEFT", COLUMN_RIGHT_X, -310)
    note:SetWidth(250)
    note:SetJustifyH("LEFT")
    note:SetWordWrap(true)
    note:SetText("Slider values can be dragged or typed directly. Custom sound input accepts bare names, .ogg, or full addon paths.")
end

local function BuildAdvancedPage(owner, parent)
    local db = api.GetSettings()
    local defaults = api.GetDefaults()
    CreateSectionTitle(parent, COLUMN_LEFT_X, -10, "Restore / Reset")
    CreateActionButton(parent, COLUMN_LEFT_X, -44, 180, "Restore Default Names", function()
        for stageIndex = 1, (constants.MAX_STAGE - 1) do
            db.stageLabels[stageIndex] = defaults.stageLabels[stageIndex]
        end
        db.outOfZoneLabel = constants.DEFAULT_OUT_OF_ZONE_LABEL
        db.ambushCustomText = ""
        api.NormalizeLabelSettings()
        api.UpdateBarDisplay()
        owner:RefreshControls()
    end)
    CreateActionButton(parent, COLUMN_LEFT_X, -76, 180, "Restore Default Sounds", function()
        db.soundsEnabled = defaults.soundsEnabled
        db.soundChannel = defaults.soundChannel
        db.soundEnhance = defaults.soundEnhance
        db.ambushSoundEnabled = defaults.ambushSoundEnabled
        db.ambushVisualEnabled = defaults.ambushVisualEnabled
        db.ambushSoundPath = defaults.ambushSoundPath
        db.soundFileNames = {}
        for _, fileName in ipairs(constants.DEFAULT_SOUND_FILENAMES) do
            db.soundFileNames[#db.soundFileNames + 1] = fileName
        end
        for stageIndex = 1, constants.MAX_STAGE do
            db.stageSounds[stageIndex] = defaults.stageSounds[stageIndex]
        end
        api.NormalizeSoundSettings()
        api.NormalizeAmbushSettings()
        owner:RefreshControls()
    end)
    CreateActionButton(parent, COLUMN_LEFT_X, -108, 180, "Reset All Defaults", function()
        api.ResetAllSettings()
        owner:RefreshControls()
    end)

    RegisterRefresher(owner, CreateCheckbox(parent, COLUMN_LEFT_X, -146, "Enable Debug", function()
        return db.debugSounds == true
    end, function(value)
        db.debugSounds = value and true or false
        _G.PreydatorDebugDB.enabled = db.debugSounds and true or false
    end))

    CreateSectionTitle(parent, COLUMN_RIGHT_X, -10, "Notes")
    local note = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    note:SetPoint("TOPLEFT", parent, "TOPLEFT", COLUMN_RIGHT_X, -44)
    note:SetWidth(260)
    note:SetJustifyH("LEFT")
    note:SetWordWrap(true)
    note:SetText("Existing installs keep their current saved values. New settings are only applied when a key is missing in PreydatorDB. This panel replaces the old long-form options page but uses the same database.")
end

function SettingsModule:RefreshControls()
    for _, control in ipairs(self.refreshers or {}) do
        local refresh = control and control.PreydatorRefresh
        if type(refresh) == "function" then
            refresh(control)
        end
    end
end

function SettingsModule:BuildTabbedOptions(parent, topOffset, bottomOffset)
    local tabLabels = { "General", "Display", "Text", "Audio", "Advanced" }
    local tabs = CreateCustomTabs(parent, tabLabels, function(index)
        for tabIndex, frame in ipairs(self.tabFrames) do
            frame:SetShown(tabIndex == index)
            if tabIndex == index then
                self.tabs[tabIndex].PreydatorBackground:SetColorTexture(0.28, 0.28, 0.28, 1)
                self.tabs[tabIndex].PreydatorText:SetTextColor(1, 1, 1)
            else
                self.tabs[tabIndex].PreydatorBackground:SetColorTexture(0.18, 0.18, 0.18, 0.9)
                self.tabs[tabIndex].PreydatorText:SetTextColor(0.8, 0.8, 0.8)
            end
        end
    end)

    self.tabs = tabs
    self.tabFrames = self.tabFrames or {}
    self.refreshers = self.refreshers or {}

    local pageBuilders = {
        BuildGeneralPage,
        BuildDisplayPage,
        BuildTextPage,
        BuildAudioPage,
        BuildAdvancedPage,
    }

    for index, builder in ipairs(pageBuilders) do
        local frame = CreateFrame("Frame", nil, parent)
        frame:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, topOffset or -108)
        frame:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, bottomOffset or 8)
        frame:SetShown(index == 1)
        self.tabFrames[index] = frame
        builder(self, frame)
    end

    tabs[1]:Click()
end

function SettingsModule:EnsureOptionsPanel()
    if self.optionsPanel then
        return self.optionsPanel, self.optionsCategoryID
    end

    local panel = CreateFrame("Frame", "PreydatorOptionsPanel_Modular")
    panel.name = "Preydator"

    local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("Preydator")

    local subtitle = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    subtitle:SetWidth(PANEL_WIDTH - 32)
    subtitle:SetJustifyH("LEFT")
    subtitle:SetWordWrap(true)
    subtitle:SetText("Tabbed options layout with two-column pages. Slider values can be dragged or typed directly.")

    panel:SetScript("OnShow", function()
        self:RefreshControls()
    end)

    self.refreshers = {}
    self.tabFrames = {}
    self:BuildTabbedOptions(panel, -108, 8)

    if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
        local category = Settings.RegisterCanvasLayoutCategory(panel, "Preydator", "Preydator")
        Settings.RegisterAddOnCategory(category)
        if type(category) == "table" then
            self.optionsCategoryID = category.ID or (category.GetID and category:GetID())
            panel.categoryID = self.optionsCategoryID
        end
    elseif _G.InterfaceOptions_AddCategory then
        _G.InterfaceOptions_AddCategory(panel)
    end

    self.optionsPanel = panel
    return self.optionsPanel, self.optionsCategoryID
end

function SettingsModule:OpenOptionsPanel()
    local panel, categoryID = self:EnsureOptionsPanel()
    if Settings and Settings.OpenToCategory and type(categoryID) == "number" then
        Settings.OpenToCategory(categoryID)
        return
    end

    if _G.InterfaceOptionsFrame_OpenToCategory then
        _G.InterfaceOptionsFrame_OpenToCategory("Preydator")
    end
end

function SettingsModule:BuildAdvancedContainer(parent, topOffset, bottomOffset)
    self.refreshers = self.refreshers or {}
    self.tabFrames = self.tabFrames or {}
    self:BuildTabbedOptions(parent, topOffset, bottomOffset)
end