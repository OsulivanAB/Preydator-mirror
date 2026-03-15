---@diagnostic disable: undefined-field, inject-field, param-type-mismatch

local _, addonTable = ...
local Preydator = _G.Preydator or addonTable
local L = _G.PreydatorL or setmetatable({}, { __index = function(_, k) return k end })

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
local C_CurrencyInfo = _G.C_CurrencyInfo

local COLUMN_LEFT_X = 18
local COLUMN_RIGHT_X = 364
local CONTROL_WIDTH = 250
local TAB_WIDTH = 101
local PANEL_WIDTH = 760
local PANEL_HEIGHT = 620

local TEXTURE_OPTIONS = {
    default = { text = L["Default"] },
    flat = { text = L["Flat"] },
    raid = { text = L["Raid HP Fill"] },
    classic = { text = L["Classic Skill Bar"] },
}

local FONT_OPTIONS = {
    frizqt = { text = L["Friz Quadrata"] },
    arialn = { text = L["Arial Narrow"] },
    skurri = { text = L["Skurri"] },
    morpheus = { text = L["Morpheus"] },
}

local CHANNEL_OPTIONS = {
    Master = { text = L["Master"] },
    SFX = { text = L["SFX"] },
    Dialog = { text = L["Dialog"] },
    Ambience = { text = L["Ambience"] },
}

local CURRENCY_THEME_OPTIONS = {
    light = { text = L["Light"] },
    brown = { text = L["Brown"] },
    dark = { text = L["Dark"] },
}

local HUNT_PANEL_SIDE_OPTIONS = {
    left = { text = L["Left"] },
    right = { text = L["Right"] },
}

local HUNT_GROUP_OPTIONS = {
    none = { text = L["None"] },
    difficulty = { text = L["Difficulty"] },
    zone = { text = L["Zone"] },
}

local HUNT_SORT_OPTIONS = {
    difficulty = { text = L["Difficulty"] },
    zone = { text = L["Zone"] },
    title = { text = L["Title"] },
}

local HUNT_ALIGN_OPTIONS = {
    { key = "top", text = L["Top"] },
    { key = "middle", text = L["Middle"] },
    { key = "bottom", text = L["Bottom"] },
}

local PERCENT_DISPLAY_OPTIONS = {
    [constants.PERCENT_DISPLAY_INSIDE] = { text = L["In Bar"] },
    [constants.PERCENT_DISPLAY_ABOVE_BAR] = { text = L["Above Bar"] },
    [constants.PERCENT_DISPLAY_ABOVE_TICKS] = { text = L["Above Ticks"] },
    [constants.PERCENT_DISPLAY_UNDER_TICKS] = { text = L["Under Ticks"] },
    [constants.PERCENT_DISPLAY_BELOW_BAR] = { text = L["Below Bar"] },
    [constants.PERCENT_DISPLAY_OFF] = { text = L["Off"] },
}

local VERTICAL_PERCENT_DISPLAY_OPTIONS = {
    [constants.PERCENT_DISPLAY_OFF]       = { text = L["Off"] },
    [constants.PERCENT_DISPLAY_ABOVE_BAR] = { text = L["Above"] },
    [constants.PERCENT_DISPLAY_INSIDE]    = { text = L["Inside"] },
    [constants.PERCENT_DISPLAY_BELOW_BAR] = { text = L["Below"] },
}

local LAYER_MODE_OPTIONS = {
    [constants.LAYER_MODE_ABOVE] = { text = L["Above Fill"] },
    [constants.LAYER_MODE_BELOW] = { text = L["Below Fill"] },
}

local PROGRESS_SEGMENT_OPTIONS = {
    [constants.PROGRESS_SEGMENTS_QUARTERS] = { text = L["Quarters (25/50/75/100)"] },
    [constants.PROGRESS_SEGMENTS_THIRDS] = { text = L["Thirds (33/66/100)"] },
}

local LABEL_MODE_OPTIONS = {
    [constants.LABEL_MODE_CENTER]       = { text = L["Centered"] },
    [constants.LABEL_MODE_LEFT]         = { text = L["Left (Prefix only)"] },
    [constants.LABEL_MODE_LEFT_COMBINED] = { text = L["Left (Prefix + Suffix)"] },
    [constants.LABEL_MODE_LEFT_SUFFIX]  = { text = L["Left (Suffix only)"] },
    [constants.LABEL_MODE_RIGHT]        = { text = L["Right (Suffix only)"] },
    [constants.LABEL_MODE_RIGHT_COMBINED] = { text = L["Right (Prefix + Suffix)"] },
    [constants.LABEL_MODE_RIGHT_PREFIX] = { text = L["Right (Prefix only)"] },
    [constants.LABEL_MODE_SEPARATE]     = { text = L["Separate (Prefix + Suffix)"] },
    [constants.LABEL_MODE_NONE]         = { text = L["No Text"] },
}

local LABEL_ROW_OPTIONS = {
    [constants.LABEL_ROW_ABOVE] = { text = L["Above Bar"] },
    [constants.LABEL_ROW_BELOW] = { text = L["Below Bar"] },
}

local ORIENTATION_OPTIONS = {
    [constants.ORIENTATION_HORIZONTAL] = { text = L["Horizontal"] },
    [constants.ORIENTATION_VERTICAL] = { text = L["Vertical"] },
}

local VERTICAL_FILL_DIRECTION_OPTIONS = {
    [constants.FILL_DIRECTION_UP] = { text = L["Fill Up"] },
    [constants.FILL_DIRECTION_DOWN] = { text = L["Fill Down"] },
}

local VERTICAL_SIDE_OPTIONS = {
    left = { text = L["Left"] },
    right = { text = L["Right"] },
}

local VERTICAL_PERCENT_SIDE_OPTIONS = {
    left   = { text = L["Left"] },
    center = { text = L["Center"] },
    right  = { text = L["Right"] },
}

local VERTICAL_TEXT_ALIGN_OPTIONS = {
    top = { text = L["Top Align"] },
    middle = { text = L["Middle Align"] },
    bottom = { text = L["Bottom Align"] },
    top_prefix_only = { text = L["Top Prefix Only"] },
    top_suffix_only = { text = L["Top Suffix Only"] },
    bottom_prefix_only = { text = L["Bottom Prefix Only"] },
    bottom_suffix_only = { text = L["Bottom Suffix Only"] },
    separate = { text = L["Separate Prefix/Suffix"] },
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

    function container:PreydatorSetEnabled(enabled)
        local isEnabled = enabled and true or false
        self:SetAlpha(isEnabled and 1 or 0.45)
        slider:SetEnabled(isEnabled)
        valueBox:SetEnabled(isEnabled)
        if valueBox.SetTextColor then
            local channel = isEnabled and 1 or 0.65
            valueBox:SetTextColor(channel, channel, channel)
        end
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
        local optionSource = GetOptions()
        local entry = optionSource[selected]
        if not entry and type(optionSource) == "table" and #optionSource > 0 then
            for _, item in ipairs(optionSource) do
                if item and item.key == selected then
                    entry = item
                    break
                end
            end
        end
        UIDropDownMenu_SetText(dropdown, entry and entry.text or "Select")
    end

    UIDropDownMenu_SetWidth(dropdown, width)
    UIDropDownMenu_Initialize(dropdown, function()
        local optionList = {}
        local optionSource = GetOptions()
        if type(optionSource) == "table" and #optionSource > 0 then
            for _, entry in ipairs(optionSource) do
                if type(entry) == "table" and entry.key ~= nil then
                    optionList[#optionList + 1] = { key = entry.key, entry = entry }
                end
            end
        else
            for key, entry in pairs(optionSource) do
                optionList[#optionList + 1] = { key = key, entry = entry }
            end

            table.sort(optionList, function(left, right)
                return tostring(left.entry and left.entry.text or "") < tostring(right.entry and right.entry.text or "")
            end)
        end

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
    function dropdown:PreydatorSetEnabled(enabled)
        local isEnabled = enabled and true or false
        self:SetAlpha(isEnabled and 1 or 0.45)
        if self.EnableMouse then
            self:EnableMouse(isEnabled)
        end
    end
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
    local tabGap = 4
    local tabStartX = 16
    local usableWidth = PANEL_WIDTH - (tabStartX * 2)
    local computedWidth = math.floor((usableWidth - (tabGap * (#labels - 1))) / #labels)
    local tabWidth = math.max(65, computedWidth - 15)
    for index, label in ipairs(labels) do
        local tab = CreateFrame("Button", nil, parent)
        tab:SetSize(tabWidth or TAB_WIDTH, 28)
        if index == 1 then
            tab:SetPoint("TOPLEFT", parent, "TOPLEFT", tabStartX, -72)
        else
            tab:SetPoint("LEFT", tabs[index - 1], "RIGHT", tabGap, 0)
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

local function RefreshHuntTrackerPanel()
    local huntScanner = Preydator:GetModule("HuntScanner")
    if huntScanner and type(huntScanner.ApplySettings) == "function" then
        huntScanner:ApplySettings()
    end
end

local function RefreshCurrencyTrackerPanel()
    local tracker = Preydator:GetModule("CurrencyTracker")
    if tracker and type(tracker.RefreshCurrencyPage) == "function" then
        tracker:RefreshCurrencyPage()
    end
end

local function BuildGeneralPage(owner, parent)
    local db = api.GetSettings()

    CreateSectionTitle(parent, COLUMN_LEFT_X, -10, L["Visibility"])
    RegisterRefresher(owner, CreateCheckbox(parent, COLUMN_LEFT_X, -38, L["Lock Bar"], function() return db.locked end, function(value)
        db.locked = value
        api.ApplyBarSettings()
    end))
    RegisterRefresher(owner, CreateCheckbox(parent, COLUMN_LEFT_X, -66, L["Only show in prey zone"], function() return db.onlyShowInPreyZone end, function(value)
        db.onlyShowInPreyZone = value
        api.UpdateBarDisplay()
    end))
    RegisterRefresher(owner, CreateCheckbox(parent, COLUMN_LEFT_X, -94, L["Disable Default Prey Icon"], function() return db.disableDefaultPreyIcon == true end, function(value)
        db.disableDefaultPreyIcon = value
        api.ApplyDefaultPreyIconVisibility()
        api.UpdateBarDisplay()
    end))
    RegisterRefresher(owner, CreateCheckbox(parent, COLUMN_LEFT_X, -122, L["Show in Edit Mode preview"], function() return db.showInEditMode ~= false end, function(value)
        db.showInEditMode = value
        api.NormalizeDisplaySettings()
        api.UpdateBarDisplay()
    end))
    RegisterRefresher(owner, CreateDropdown(parent, COLUMN_LEFT_X, -152, L["Panel Theme"], 170, CURRENCY_THEME_OPTIONS, function()
        return db.currencyTheme or "brown"
    end, function(key)
        db.currencyTheme = key
        RefreshCurrencyTrackerPanel()
    end))
    RegisterRefresher(owner, CreateCheckbox(parent, COLUMN_LEFT_X, -206, L["Disable Minimap Button"], function()
        return db.currencyMinimapButton == false
    end, function(value)
        local enabled = not value
        local tracker = Preydator:GetModule("CurrencyTracker")
        if tracker and type(tracker.SetMinimapButtonEnabled) == "function" then
            tracker:SetMinimapButtonEnabled(enabled)
            return
        end

        db.currencyMinimapButton = enabled
        db.currencyMinimap = db.currencyMinimap or {}
        db.currencyMinimap.hide = not enabled
    end))

    CreateSectionTitle(parent, COLUMN_RIGHT_X, -10, L["Behavior"])
    RegisterRefresher(owner, CreateCheckbox(parent, COLUMN_RIGHT_X, -38, L["Enable sounds"], function() return db.soundsEnabled end, function(value)
        db.soundsEnabled = value
    end))
    RegisterRefresher(owner, CreateCheckbox(parent, COLUMN_RIGHT_X, -66, L["Ambush sound alert"], function() return db.ambushSoundEnabled ~= false end, function(value)
        db.ambushSoundEnabled = value
    end))
    RegisterRefresher(owner, CreateCheckbox(parent, COLUMN_RIGHT_X, -94, L["Ambush visual alert"], function() return db.ambushVisualEnabled ~= false end, function(value)
        db.ambushVisualEnabled = value
        if not value then
            api.GetState().ambushAlertUntil = 0
            api.UpdateBarDisplay()
        end
    end))
    RegisterRefresher(owner, CreateCheckbox(parent, COLUMN_RIGHT_X, -122, L["Show tick marks"], function() return db.showTicks end, function(value)
        db.showTicks = value
        api.RequestBarRefresh()
    end))
    RegisterRefresher(owner, CreateDropdown(parent, COLUMN_RIGHT_X, -152, L["Progress Segments"], 170, PROGRESS_SEGMENT_OPTIONS, function()
        return db.progressSegments
    end, function(key)
        db.progressSegments = key
        api.NormalizeProgressSettings()
        api.RequestBarRefresh()
    end))
    RegisterRefresher(owner, CreateDropdown(parent, COLUMN_RIGHT_X, -206, L["Sound Channel"], 170, CHANNEL_OPTIONS, function()
        return db.soundChannel
    end, function(key)
        db.soundChannel = key
    end))
end

local function BuildHuntPage(owner, parent)
    local db = api.GetSettings()

    local function ToggleHuntPreview()
        db.huntScannerPreviewInOptions = not (db.huntScannerPreviewInOptions == true)
        local huntScanner = Preydator:GetModule("HuntScanner")
        if huntScanner and type(huntScanner.SetPreviewEnabled) == "function" then
            huntScanner:SetPreviewEnabled(db.huntScannerPreviewInOptions == true)
        end
        owner:RefreshControls()
    end

    CreateSectionTitle(parent, COLUMN_LEFT_X, -10, L["Hunt Table"])
    RegisterRefresher(owner, CreateCheckbox(parent, COLUMN_LEFT_X, -38, L["Enable Hunt Table Tracker"], function()
        return db.huntScannerEnabled ~= false
    end, function(value)
        db.huntScannerEnabled = value and true or false
        RefreshHuntTrackerPanel()
    end))
    RegisterRefresher(owner, CreateDropdown(parent, COLUMN_LEFT_X, -80, L["Hunt Panel Side"], 170, HUNT_PANEL_SIDE_OPTIONS, function()
        return db.huntScannerSide or "right"
    end, function(key)
        db.huntScannerSide = (key == "left") and "left" or "right"
        RefreshHuntTrackerPanel()
    end))
    RegisterRefresher(owner, CreateDropdown(parent, COLUMN_LEFT_X, -144, L["Group Hunts By"], 170, HUNT_GROUP_OPTIONS, function()
        return db.huntScannerGroupBy or "difficulty"
    end, function(key)
        db.huntScannerGroupBy = key
        RefreshHuntTrackerPanel()
    end))
    RegisterRefresher(owner, CreateDropdown(parent, COLUMN_LEFT_X, -196, L["Sort Hunts By"], 170, HUNT_SORT_OPTIONS, function()
        return db.huntScannerSortBy or "zone"
    end, function(key)
        db.huntScannerSortBy = key
        RefreshHuntTrackerPanel()
    end))
    RegisterRefresher(owner, CreateCheckbox(parent, COLUMN_LEFT_X, -248, L["Match Currency Theme"], function()
        return db.huntScannerUseCurrencyTheme ~= false
    end, function(value)
        db.huntScannerUseCurrencyTheme = value and true or false
        RefreshHuntTrackerPanel()
    end))
    RegisterRefresher(owner, CreateDropdown(parent, COLUMN_LEFT_X, -290, L["Hunt Theme"], 170, CURRENCY_THEME_OPTIONS, function()
        return db.huntScannerTheme or "brown"
    end, function(key)
        db.huntScannerTheme = key
        RefreshHuntTrackerPanel()
    end))
    RegisterRefresher(owner, CreateDropdown(parent, COLUMN_LEFT_X, -342, L["Anchor Align"], 170, HUNT_ALIGN_OPTIONS, function()
        return db.huntScannerAnchorAlign or "top"
    end, function(key)
        db.huntScannerAnchorAlign = (key == "middle" or key == "bottom") and key or "top"
        RefreshHuntTrackerPanel()
    end))

    CreateSectionTitle(parent, COLUMN_RIGHT_X, -10, L["Panel Layout"])
    RegisterRefresher(owner, CreateSlider(parent, COLUMN_RIGHT_X, -40, L["Hunt Panel Width"], 280, 620, 1, function()
        return db.huntScannerWidth or 336
    end, function(value)
        db.huntScannerWidth = math.floor(value + 0.5)
        RefreshHuntTrackerPanel()
    end, function(value)
        return tostring(math.floor(value + 0.5))
    end))
    RegisterRefresher(owner, CreateSlider(parent, COLUMN_RIGHT_X, -92, L["Hunt Panel Height"], 320, 900, 1, function()
        return db.huntScannerHeight or 460
    end, function(value)
        db.huntScannerHeight = math.floor(value + 0.5)
        RefreshHuntTrackerPanel()
    end, function(value)
        return tostring(math.floor(value + 0.5))
    end))

    RegisterRefresher(owner, CreateSlider(parent, COLUMN_RIGHT_X, -144, L["Hunt Panel Scale"], 0.70, 1.60, 0.05, function()
        return db.huntScannerScale or 1.00
    end, function(value)
        db.huntScannerScale = value
        RefreshHuntTrackerPanel()
    end, function(value)
        return string.format("%.2f", value)
    end))
    RegisterRefresher(owner, CreateSlider(parent, COLUMN_RIGHT_X, -196, L["Hunt Panel Font Size"], 10, 24, 1, function()
        return db.huntScannerFontSize or 12
    end, function(value)
        db.huntScannerFontSize = math.floor(value + 0.5)
        RefreshHuntTrackerPanel()
    end, function(value)
        return tostring(math.floor(value + 0.5))
    end))

    local previewButton = CreateActionButton(parent, COLUMN_RIGHT_X, -250, 180, L["Show Preview Pane"], function()
        ToggleHuntPreview()
    end)
    RegisterRefresher(owner, previewButton)
    previewButton.PreydatorRefresh = function(self)
        self:SetText((db.huntScannerPreviewInOptions == true) and L["Hide Preview Pane"] or L["Show Preview Pane"])
    end

    local note = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    note:SetPoint("TOPLEFT", parent, "TOPLEFT", COLUMN_RIGHT_X, -290)
    note:SetWidth(260)
    note:SetJustifyH("LEFT")
    note:SetWordWrap(true)
    note:SetText(L["Use Hunt Table controls here to manage sorting, grouping, panel size, and reward cache behavior."])
end

local function BuildWarbandPage(owner, parent)
    local db = api.GetSettings()
    local trackedIDs = { 3392, 3316, 3383, 3341, 3343 }

    CreateSectionTitle(parent, COLUMN_LEFT_X, -10, L["Warband Window"])
    local warbandToggleButton = CreateActionButton(parent, COLUMN_LEFT_X, -38, 180, L["Open Warband"], function()
        local tracker = Preydator:GetModule("CurrencyTracker")
        if tracker and type(tracker.ToggleWarbandWindow) == "function" then
            tracker:ToggleWarbandWindow()
        else
            db.currencyWarbandWindowEnabled = not (db.currencyWarbandWindowEnabled == true)
            RefreshCurrencyTrackerPanel()
        end
        owner:RefreshControls()
    end)
    RegisterRefresher(owner, warbandToggleButton)
    warbandToggleButton.PreydatorRefresh = function(self)
        self:SetText((db.currencyWarbandWindowEnabled == true) and L["Close Warband"] or L["Open Warband"])
    end

    RegisterRefresher(owner, CreateCheckbox(parent, COLUMN_LEFT_X, -68, L["Show Realm in Warband"], function()
        return db.currencyShowRealmInWarband == true
    end, function(value)
        db.currencyShowRealmInWarband = value and true or false
        RefreshCurrencyTrackerPanel()
    end))
    RegisterRefresher(owner, CreateCheckbox(parent, COLUMN_LEFT_X, -96, L["Match Currency Theme"], function()
        return db.currencyWarbandUseCurrencyTheme ~= false
    end, function(value)
        db.currencyWarbandUseCurrencyTheme = value and true or false
        RefreshCurrencyTrackerPanel()
    end))
    RegisterRefresher(owner, CreateDropdown(parent, COLUMN_LEFT_X, -138, L["Warband Theme"], 170, CURRENCY_THEME_OPTIONS, function()
        return db.currencyWarbandTheme or "brown"
    end, function(key)
        db.currencyWarbandTheme = key
        RefreshCurrencyTrackerPanel()
    end))

    RegisterRefresher(owner, CreateSlider(parent, COLUMN_LEFT_X, -190, L["Warband Width"], 150, 900, 1, function()
        return db.currencyWarbandWidth or 420
    end, function(value)
        db.currencyWarbandWidth = math.floor(value + 0.5)
        RefreshCurrencyTrackerPanel()
    end, function(value)
        return tostring(math.floor(value + 0.5))
    end))
    RegisterRefresher(owner, CreateSlider(parent, COLUMN_LEFT_X, -242, L["Warband Height"], 140, 800, 1, function()
        return db.currencyWarbandHeight or 250
    end, function(value)
        db.currencyWarbandHeight = math.floor(value + 0.5)
        RefreshCurrencyTrackerPanel()
    end, function(value)
        return tostring(math.floor(value + 0.5))
    end))
    RegisterRefresher(owner, CreateSlider(parent, COLUMN_LEFT_X, -294, L["Warband Font Size"], 10, 24, 1, function()
        return db.currencyWarbandFontSize or 12
    end, function(value)
        db.currencyWarbandFontSize = math.floor(value + 0.5)
        RefreshCurrencyTrackerPanel()
    end, function(value)
        return tostring(math.floor(value + 0.5))
    end))
    RegisterRefresher(owner, CreateSlider(parent, COLUMN_LEFT_X, -346, L["Warband Scale"], 0.7, 1.4, 0.05, function()
        return db.currencyWarbandScale or 1.0
    end, function(value)
        db.currencyWarbandScale = value
        RefreshCurrencyTrackerPanel()
    end, function(value)
        return string.format("%.2f", value)
    end))

    CreateSectionTitle(parent, COLUMN_RIGHT_X, -10, L["Tracked in Warband"])
    RegisterRefresher(owner, CreateCheckbox(parent, COLUMN_RIGHT_X, -38, L["Show Prey Track (Alts) in Warband"], function()
        return db.currencyWarbandShowPreyTrack ~= false
    end, function(value)
        db.currencyWarbandShowPreyTrack = value and true or false
        RefreshCurrencyTrackerPanel()
    end))
    RegisterRefresher(owner, CreateCheckbox(parent, COLUMN_RIGHT_X, -66, L["Prey Track Shows Completed"], function()
        return db.currencyWarbandPreyMode == "completed"
    end, function(value)
        db.currencyWarbandPreyMode = value and "completed" or "available"
        RefreshCurrencyTrackerPanel()
    end))
    for index, currencyID in ipairs(trackedIDs) do
        local currencyInfoAPI = _G.C_CurrencyInfo
        local info = currencyInfoAPI and currencyInfoAPI.GetCurrencyInfo and currencyInfoAPI.GetCurrencyInfo(currencyID)
        local label = (info and info.name) or ("Currency " .. tostring(currencyID))
        RegisterRefresher(owner, CreateCheckbox(parent, COLUMN_RIGHT_X, -104 - ((index - 1) * 28), label, function()
            db.currencyWarbandTrackedIDs = db.currencyWarbandTrackedIDs or {}
            return db.currencyWarbandTrackedIDs[currencyID] ~= false
        end, function(value)
            db.currencyWarbandTrackedIDs = db.currencyWarbandTrackedIDs or {}
            db.currencyWarbandTrackedIDs[currencyID] = value and true or false
            RefreshCurrencyTrackerPanel()
        end))
    end
end

local function BuildDisplayPage(owner, parent)
    local db = api.GetSettings()

    local function IsHorizontalMode()
        return (db.orientation or constants.ORIENTATION_HORIZONTAL) ~= constants.ORIENTATION_VERTICAL
    end

    CreateSectionTitle(parent, COLUMN_LEFT_X, -10, L["Bar Size"])
    local scaleSlider = RegisterRefresher(owner, CreateSlider(parent, COLUMN_LEFT_X, -40, L["Scale"], 0.5, 2, 0.05, function() return db.scale end, function(value)
        db.scale = value
        api.RequestBarRefresh()
    end, function(value) return string.format("%.2f", value) end))
    local widthSlider = RegisterRefresher(owner, CreateSlider(parent, COLUMN_LEFT_X, -100, L["Width"], 100, 350, 1, function() return db.horizontalWidth or db.width end, function(value)
        db.horizontalWidth = math.floor(value + 0.5)
        if IsHorizontalMode() then
            db.width = db.horizontalWidth
        end
        api.RequestBarRefresh()
    end, function(value) return tostring(math.floor(value + 0.5)) end))
    local heightSlider = RegisterRefresher(owner, CreateSlider(parent, COLUMN_LEFT_X, -160, L["Height"], 10, 60, 1, function() return db.horizontalHeight or db.height end, function(value)
        db.horizontalHeight = math.floor(value + 0.5)
        if IsHorizontalMode() then
            db.height = db.horizontalHeight
        end
        api.RequestBarRefresh()
    end, function(value) return tostring(math.floor(value + 0.5)) end))
    RegisterRefresher(owner, CreateSlider(parent, COLUMN_LEFT_X, -220, L["Font Size"], 8, 24, 1, function() return db.fontSize end, function(value)
        db.fontSize = math.floor(value + 0.5)
        api.RequestBarRefresh()
    end, function(value) return tostring(math.floor(value + 0.5)) end))

    local widthBaseRefresh = widthSlider.PreydatorRefresh
    widthSlider.PreydatorRefresh = function(self)
        widthBaseRefresh(self)
        if self.PreydatorSetEnabled then
            self:PreydatorSetEnabled(IsHorizontalMode())
        end
    end

    local heightBaseRefresh = heightSlider.PreydatorRefresh
    heightSlider.PreydatorRefresh = function(self)
        heightBaseRefresh(self)
        if self.PreydatorSetEnabled then
            self:PreydatorSetEnabled(IsHorizontalMode())
        end
    end

    local scaleBaseRefresh = scaleSlider.PreydatorRefresh
    scaleSlider.PreydatorRefresh = function(self)
        scaleBaseRefresh(self)
        if self.PreydatorSetEnabled then
            self:PreydatorSetEnabled(IsHorizontalMode())
        end
    end

    CreateSectionTitle(parent, COLUMN_LEFT_X, -264, L["Progress Display"])
    local percentDisplayDropdown = RegisterRefresher(owner, CreateDropdown(parent, COLUMN_LEFT_X, -294, L["Percent Display"], 170, PERCENT_DISPLAY_OPTIONS, function()
        return db.percentDisplay
    end, function(key)
        if not IsHorizontalMode() then
            return
        end
        db.percentDisplay = key
        api.NormalizeDisplaySettings()
        api.RequestBarRefresh()
    end))
    RegisterRefresher(owner, CreateDropdown(parent, COLUMN_LEFT_X, -350, L["Text Display"], 170, LABEL_ROW_OPTIONS, function()
        return db.labelRowPosition
    end, function(key)
        if not IsHorizontalMode() then
            return
        end
        db.labelRowPosition = key
        api.NormalizeDisplaySettings()
        api.RequestBarRefresh()
    end))
    RegisterRefresher(owner, CreateCheckbox(parent, COLUMN_LEFT_X, -406, L["Display Spark Line"], function()
        return db.showSparkLine == true
    end, function(value)
        db.showSparkLine = value and true or false
        api.NormalizeDisplaySettings()
        api.RequestBarRefresh()
    end))

    local percentDisplayBaseRefresh = percentDisplayDropdown.PreydatorRefresh
    percentDisplayDropdown.PreydatorRefresh = function(self)
        percentDisplayBaseRefresh(self)
        if self.PreydatorSetEnabled then
            self:PreydatorSetEnabled(IsHorizontalMode())
        end
    end

    CreateSectionTitle(parent, COLUMN_RIGHT_X, -10, L["Visual Style"])
    RegisterRefresher(owner, CreateDropdown(parent, COLUMN_RIGHT_X, -40, L["Texture"], 170, TEXTURE_OPTIONS, function()
        return db.textureKey
    end, function(key)
        db.textureKey = key
        api.ApplyBarSettings()
    end))
    RegisterRefresher(owner, CreateDropdown(parent, COLUMN_RIGHT_X, -104, L["Title Font"], 170, FONT_OPTIONS, function()
        return db.titleFontKey
    end, function(key)
        db.titleFontKey = key
        api.ApplyBarSettings()
    end))
    RegisterRefresher(owner, CreateDropdown(parent, COLUMN_RIGHT_X, -168, L["Percent Font"], 170, FONT_OPTIONS, function()
        return db.percentFontKey
    end, function(key)
        db.percentFontKey = key
        api.ApplyBarSettings()
    end))
    RegisterRefresher(owner, CreateColorButton(parent, COLUMN_RIGHT_X, -232, L["Fill Color"], function() return db.fillColor end, function(color)
        db.fillColor = color
        api.ApplyBarSettings()
    end, true))
    RegisterRefresher(owner, CreateColorButton(parent, COLUMN_RIGHT_X, -266, L["Background Color"], function() return db.bgColor end, function(color)
        db.bgColor = color
        api.ApplyBarSettings()
    end, true))
    RegisterRefresher(owner, CreateColorButton(parent, COLUMN_RIGHT_X, -300, L["Title Color"], function() return db.titleColor end, function(color)
        db.titleColor = color
        api.RequestBarRefresh()
    end, true))
    RegisterRefresher(owner, CreateColorButton(parent, COLUMN_RIGHT_X, -334, L["Percent Color"], function() return db.percentColor end, function(color)
        db.percentColor = color
        api.RequestBarRefresh()
    end, true))
    RegisterRefresher(owner, CreateColorButton(parent, COLUMN_RIGHT_X, -368, L["Tick Mark Color"], function() return db.tickColor end, function(color)
        db.tickColor = color
        api.RequestBarRefresh()
    end, true))
    RegisterRefresher(owner, CreateColorButton(parent, COLUMN_RIGHT_X, -402, L["Border Color"], function()
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
    local borderLinkCheck = CreateCheckbox(parent, COLUMN_RIGHT_X, -436, L["Link border color to fill"], function()
        return db.borderColorLinked ~= false
    end, function(value)
        db.borderColorLinked = value and true or false
        api.NormalizeColorSettings()
        api.ApplyBarSettings()
    end)
    RegisterRefresher(owner, borderLinkCheck)
end

local function BuildVerticalPage(owner, parent)
    local db = api.GetSettings()

    local function IsVerticalMode()
        return (db.orientation or constants.ORIENTATION_HORIZONTAL) == constants.ORIENTATION_VERTICAL
    end

    CreateSectionTitle(parent, COLUMN_LEFT_X, -10, L["Vertical Mode"])
    RegisterRefresher(owner, CreateDropdown(parent, COLUMN_LEFT_X, -40, L["Bar Orientation"], 170, ORIENTATION_OPTIONS, function()
        return db.orientation
    end, function(key)
        db.orientation = key
        api.NormalizeDisplaySettings()
        api.RequestBarRefresh()
        owner:RefreshControls()
    end))

    RegisterRefresher(owner, CreateDropdown(parent, COLUMN_LEFT_X, -96, L["Vertical Fill Direction"], 170, VERTICAL_FILL_DIRECTION_OPTIONS, function()
        return db.verticalFillDirection
    end, function(key)
        db.verticalFillDirection = key
        api.NormalizeDisplaySettings()
        api.RequestBarRefresh()
    end))

    RegisterRefresher(owner, CreateDropdown(parent, COLUMN_LEFT_X, -152, L["Vertical Text Side"], 170, VERTICAL_SIDE_OPTIONS, function()
        return db.verticalTextSide
    end, function(key)
        db.verticalTextSide = key
        api.NormalizeDisplaySettings()
        api.RequestBarRefresh()
    end))

    RegisterRefresher(owner, CreateDropdown(parent, COLUMN_LEFT_X, -208, L["Vertical Text Alignment"], 190, VERTICAL_TEXT_ALIGN_OPTIONS, function()
        return db.verticalTextAlign
    end, function(key)
        db.verticalTextAlign = key
        api.NormalizeDisplaySettings()
        api.RequestBarRefresh()
    end))

    local verticalPercentDisplayDropdown = RegisterRefresher(owner, CreateDropdown(parent, COLUMN_LEFT_X, -264, L["Vertical Percent Display"], 190, VERTICAL_PERCENT_DISPLAY_OPTIONS, function()
        return db.verticalPercentDisplay
    end, function(key)
        db.verticalPercentDisplay = key
        api.NormalizeDisplaySettings()
        api.RequestBarRefresh()
    end))

    local verticalPercentSideDropdown = RegisterRefresher(owner, CreateDropdown(parent, COLUMN_LEFT_X, -320, L["Vertical Percent Tick Mark"], 170, VERTICAL_PERCENT_SIDE_OPTIONS, function()
        return db.verticalPercentSide
    end, function(key)
        db.verticalPercentSide = key
        api.NormalizeDisplaySettings()
        api.RequestBarRefresh()
    end))

    local verticalTickPercentCheck = RegisterRefresher(owner, CreateCheckbox(parent, COLUMN_LEFT_X, -364, L["Show Percentage at Tick Marks"], function()
        return db.showVerticalTickPercent == true
    end, function(value)
        db.showVerticalTickPercent = value and true or false
        api.NormalizeDisplaySettings()
        api.RequestBarRefresh()
    end))

    local note = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    note:SetPoint("TOPLEFT", parent, "TOPLEFT", COLUMN_RIGHT_X, -36)
    note:SetWidth(260)
    note:SetJustifyH("LEFT")
    note:SetWordWrap(true)
    note:SetText(L["HINT_VERTICAL_PERCENT_OFFSET"])

    CreateSectionTitle(parent, COLUMN_RIGHT_X, -10, L["Vertical Dimensions"])
    local verticalScaleSlider = RegisterRefresher(owner, CreateSlider(parent, COLUMN_RIGHT_X, -64, L["Scale"], 0.5, 2, 0.05, function()
        return db.verticalScale or 0.9
    end, function(value)
        db.verticalScale = value
        api.RequestBarRefresh()
    end, function(value)
        return string.format("%.2f", value)
    end))

    local verticalWidthSlider = RegisterRefresher(owner, CreateSlider(parent, COLUMN_RIGHT_X, -116, L["Width"], 10, 60, 1, function()
        return db.verticalWidth or db.width
    end, function(value)
        db.verticalWidth = math.floor(value + 0.5)
        if IsVerticalMode() then
            db.width = db.verticalWidth
        end
        api.RequestBarRefresh()
    end, function(value)
        return tostring(math.floor(value + 0.5))
    end))

    local verticalHeightSlider = RegisterRefresher(owner, CreateSlider(parent, COLUMN_RIGHT_X, -168, L["Height"], 100, 350, 1, function()
        return db.verticalHeight or db.height
    end, function(value)
        db.verticalHeight = math.floor(value + 0.5)
        if IsVerticalMode() then
            db.height = db.verticalHeight
        end
        api.RequestBarRefresh()
    end, function(value)
        return tostring(math.floor(value + 0.5))
    end))

    local textOffsetSlider = RegisterRefresher(owner, CreateSlider(parent, COLUMN_RIGHT_X, -224, L["Vertical Text Offset"], 2, 60, 1, function()
        return db.verticalTextOffset or 10
    end, function(value)
        db.verticalTextOffset = math.floor(value + 0.5)
        api.NormalizeDisplaySettings()
        api.RequestBarRefresh()
    end, function(value)
        return tostring(math.floor(value + 0.5))
    end))

    local percentOffsetSlider = RegisterRefresher(owner, CreateSlider(parent, COLUMN_RIGHT_X, -280, L["Vertical Percent Offset"], 2, 60, 1, function()
        return db.verticalPercentOffset or 10
    end, function(value)
        db.verticalPercentOffset = math.floor(value + 0.5)
        api.NormalizeDisplaySettings()
        api.RequestBarRefresh()
    end, function(value)
        return tostring(math.floor(value + 0.5))
    end))

    local function ApplyVerticalControlState()
        local enabled = IsVerticalMode()
        local percentMode = db.verticalPercentDisplay or constants.PERCENT_DISPLAY_INSIDE
        local percentNotOff = percentMode ~= constants.PERCENT_DISPLAY_OFF
        local textSide = db.verticalTextSide or "right"
        local tickMarkSide = db.verticalPercentSide or "center"
        local percentOffsetApplies = enabled and (
            textSide == "left"
            or textSide == "right"
            or tickMarkSide == "left"
            or tickMarkSide == "right"
        )

        if verticalPercentSideDropdown and verticalPercentSideDropdown.PreydatorSetEnabled then
            verticalPercentSideDropdown:PreydatorSetEnabled(enabled and percentNotOff)
        end
        if verticalTickPercentCheck and verticalTickPercentCheck.PreydatorSetEnabled then
            verticalTickPercentCheck:PreydatorSetEnabled(enabled and percentNotOff)
        end
        if textOffsetSlider.PreydatorSetEnabled then
            textOffsetSlider:PreydatorSetEnabled(enabled)
        end
        if percentOffsetSlider.PreydatorSetEnabled then
            percentOffsetSlider:PreydatorSetEnabled(percentOffsetApplies)
        end
        if verticalWidthSlider.PreydatorSetEnabled then
            verticalWidthSlider:PreydatorSetEnabled(enabled)
        end
        if verticalHeightSlider.PreydatorSetEnabled then
            verticalHeightSlider:PreydatorSetEnabled(enabled)
        end
        if verticalScaleSlider.PreydatorSetEnabled then
            verticalScaleSlider:PreydatorSetEnabled(enabled)
        end
    end

    local textOffsetBaseRefresh = textOffsetSlider.PreydatorRefresh
    textOffsetSlider.PreydatorRefresh = function(self)
        textOffsetBaseRefresh(self)
        ApplyVerticalControlState()
    end

    local verticalPercentDisplayBaseRefresh = verticalPercentDisplayDropdown.PreydatorRefresh
    verticalPercentDisplayDropdown.PreydatorRefresh = function(self)
        verticalPercentDisplayBaseRefresh(self)
        ApplyVerticalControlState()
    end

    local verticalPercentSideBaseRefresh = verticalPercentSideDropdown.PreydatorRefresh
    verticalPercentSideDropdown.PreydatorRefresh = function(self)
        verticalPercentSideBaseRefresh(self)
        ApplyVerticalControlState()
    end

    local verticalTickPercentBaseRefresh = verticalTickPercentCheck.PreydatorRefresh
    verticalTickPercentCheck.PreydatorRefresh = function(self)
        verticalTickPercentBaseRefresh(self)
        ApplyVerticalControlState()
    end

    local percentOffsetBaseRefresh = percentOffsetSlider.PreydatorRefresh
    percentOffsetSlider.PreydatorRefresh = function(self)
        percentOffsetBaseRefresh(self)
        ApplyVerticalControlState()
    end

    local verticalWidthBaseRefresh = verticalWidthSlider.PreydatorRefresh
    verticalWidthSlider.PreydatorRefresh = function(self)
        verticalWidthBaseRefresh(self)
        ApplyVerticalControlState()
    end

    local verticalScaleBaseRefresh = verticalScaleSlider.PreydatorRefresh
    verticalScaleSlider.PreydatorRefresh = function(self)
        verticalScaleBaseRefresh(self)
        ApplyVerticalControlState()
    end

    local verticalHeightBaseRefresh = verticalHeightSlider.PreydatorRefresh
    verticalHeightSlider.PreydatorRefresh = function(self)
        verticalHeightBaseRefresh(self)
        ApplyVerticalControlState()
    end
end

local function BuildTextPage(owner, parent)
    local db = api.GetSettings()
    local defaults = api.GetDefaults()

    local function IsVerticalMode()
        return (db.orientation or constants.ORIENTATION_HORIZONTAL) == constants.ORIENTATION_VERTICAL
    end

    local function ApplyDropdownLockedState(control)
        local locked = IsVerticalMode()
        local enabled = not locked
        if control.SetEnabled then
            control:SetEnabled(enabled)
        end
        if control.EnableMouse then
            control:EnableMouse(enabled)
        end
        if control.SetAlpha then
            control:SetAlpha(enabled and 1 or 0.45)
        end
    end

    CreateSectionTitle(parent, COLUMN_LEFT_X, -10, L["Label Mode"])
    local labelModeDropdown = RegisterRefresher(owner, CreateDropdown(parent, COLUMN_LEFT_X, -40, L["Label Mode"], 170, LABEL_MODE_OPTIONS, function()
        return db.stageLabelMode
    end, function(key)
        if IsVerticalMode() then
            return
        end
        db.stageLabelMode = key
        api.NormalizeDisplaySettings()
        api.RequestBarRefresh()
    end))

    CreateSectionTitle(parent, COLUMN_LEFT_X, -92, L["Prefix Labels"])
    for stageIndex = 1, constants.MAX_STAGE do
        local offset = -122 - ((stageIndex - 1) * 46)
        RegisterRefresher(owner, CreateTextInput(parent, COLUMN_LEFT_X, offset, string.format(L["Stage %d"], stageIndex), 220, function()
            if not db.stageSuffixLabels then db.stageSuffixLabels = {} end
            return db.stageSuffixLabels[stageIndex] or ""
        end, function(value)
            if not db.stageSuffixLabels then db.stageSuffixLabels = {} end
            db.stageSuffixLabels[stageIndex] = value
            api.NormalizeDisplaySettings()
            api.UpdateBarDisplay()
        end))
    end

    RegisterRefresher(owner, CreateTextInput(parent, COLUMN_LEFT_X, -316, L["Out of Zone Prefix"], 220, function()
        return db.outOfZonePrefix or ""
    end, function(value)
        db.outOfZonePrefix = value
        api.NormalizeLabelSettings()
        api.UpdateBarDisplay()
    end))
    RegisterRefresher(owner, CreateTextInput(parent, COLUMN_LEFT_X, -362, L["Ambush Prefix"], 220, function()
        return db.ambushPrefix or ""
    end, function(value)
        db.ambushPrefix = value
        api.NormalizeLabelSettings()
        api.UpdateBarDisplay()
    end))

    CreateSectionTitle(parent, COLUMN_RIGHT_X, -10, L["Label Placement"])
    local labelRowDropdown = RegisterRefresher(owner, CreateDropdown(parent, COLUMN_RIGHT_X, -40, L["Prefix/Suffix Row"], 170, LABEL_ROW_OPTIONS, function()
        return db.labelRowPosition
    end, function(key)
        if IsVerticalMode() then
            return
        end
        db.labelRowPosition = key
        api.NormalizeDisplaySettings()
        api.RequestBarRefresh()
    end))

    CreateSectionTitle(parent, COLUMN_RIGHT_X, -92, L["Suffix Labels"])
    for stageIndex = 1, constants.MAX_STAGE do
        local offset = -122 - ((stageIndex - 1) * 46)
        RegisterRefresher(owner, CreateTextInput(parent, COLUMN_RIGHT_X, offset, string.format(L["Stage %d"], stageIndex), 220, function()
            return db.stageLabels[stageIndex] or ""
        end, function(value)
            db.stageLabels[stageIndex] = value
            api.NormalizeLabelSettings()
            api.UpdateBarDisplay()
        end))
    end

    RegisterRefresher(owner, CreateTextInput(parent, COLUMN_RIGHT_X, -316, L["Out of Zone Label"], 220, function()
        return db.outOfZoneLabel
    end, function(value)
        db.outOfZoneLabel = value
        api.NormalizeLabelSettings()
        api.UpdateBarDisplay()
    end))
    RegisterRefresher(owner, CreateTextInput(parent, COLUMN_RIGHT_X, -362, L["Ambush Override Text"], 220, function()
        return db.ambushCustomText
    end, function(value)
        db.ambushCustomText = value
        api.NormalizeLabelSettings()
        api.UpdateBarDisplay()
    end))
    CreateActionButton(parent, COLUMN_RIGHT_X, -420, 180, L["Restore Default Names"], function()
        for stageIndex = 1, constants.MAX_STAGE do
            db.stageLabels[stageIndex] = defaults.stageLabels[stageIndex] or ""
        end
        db.outOfZoneLabel = constants.DEFAULT_OUT_OF_ZONE_LABEL
        db.ambushCustomText = ""
        api.NormalizeLabelSettings()
        api.UpdateBarDisplay()
        owner:RefreshControls()
    end)

    local function WrapRefreshWithDropdownLock(control)
        if not control then
            return
        end
        local baseRefresh = control.PreydatorRefresh
        control.PreydatorRefresh = function(self)
            if baseRefresh then
                baseRefresh(self)
            end
            ApplyDropdownLockedState(self)
        end
    end

    WrapRefreshWithDropdownLock(labelModeDropdown)
    WrapRefreshWithDropdownLock(labelRowDropdown)

    local lockNote = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    lockNote:SetPoint("TOPLEFT", parent, "TOPLEFT", COLUMN_LEFT_X, -420)
    lockNote:SetWidth(320)
    lockNote:SetJustifyH("LEFT")
    lockNote:SetWordWrap(true)
    lockNote:SetText(L["HINT_VERTICAL_LOCK"])
end

local function BuildAudioPage(owner, parent)
    local db = api.GetSettings()
    CreateSectionTitle(parent, COLUMN_LEFT_X, -10, L["Sound Selection"])
    RegisterRefresher(owner, CreateDropdown(parent, COLUMN_LEFT_X, -40, string.format(L["Stage %d Sound"], 1), 170, function()
        return api.BuildSoundDropdownOptions()
    end, function()
        return db.stageSounds[1]
    end, function(key)
        db.stageSounds[1] = key
        api.NormalizeSoundSettings()
    end))
    RegisterRefresher(owner, CreateDropdown(parent, COLUMN_LEFT_X, -94, string.format(L["Stage %d Sound"], 2), 170, function()
        return api.BuildSoundDropdownOptions()
    end, function()
        return db.stageSounds[2]
    end, function(key)
        db.stageSounds[2] = key
        api.NormalizeSoundSettings()
    end))
    RegisterRefresher(owner, CreateDropdown(parent, COLUMN_LEFT_X, -148, string.format(L["Stage %d Sound"], 3), 170, function()
        return api.BuildSoundDropdownOptions()
    end, function()
        return db.stageSounds[3]
    end, function(key)
        db.stageSounds[3] = key
        api.NormalizeSoundSettings()
    end))
    RegisterRefresher(owner, CreateDropdown(parent, COLUMN_LEFT_X, -202, string.format(L["Stage %d Sound"], 4), 170, function()
        return api.BuildSoundDropdownOptions()
    end, function()
        return db.stageSounds[4]
    end, function(key)
        db.stageSounds[4] = key
        api.NormalizeSoundSettings()
    end))
    RegisterRefresher(owner, CreateDropdown(parent, COLUMN_LEFT_X, -256, L["Ambush Sound"], 170, function()
        return api.BuildSoundDropdownOptions()
    end, function()
        return db.ambushSoundPath
    end, function(key)
        db.ambushSoundPath = key
        api.NormalizeAmbushSettings()
    end))
    RegisterRefresher(owner, CreateSlider(parent, COLUMN_LEFT_X, -310, L["Enhance Sounds"], 0, 100, 5, function() return db.soundEnhance or 0 end, function(value)
        db.soundEnhance = math.floor(value + 0.5)
    end, function(value) return tostring(math.floor(value + 0.5)) end))

    CreateSectionTitle(parent, COLUMN_RIGHT_X, -10, L["Custom Files / Tests"])
    local customSoundInput = CreateTextInput(parent, COLUMN_RIGHT_X, -40, L["Custom Sound File"], 220, function()
        return ""
    end, function()
    end)
    customSoundInput:SetScript("OnEditFocusLost", nil)
    customSoundInput:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
    end)
    customSoundInput:SetText("")

    CreateActionButton(parent, COLUMN_RIGHT_X, -86, 105, L["Add File"], function()
        local ok, message = api.AddSoundFileName(customSoundInput:GetText())
        if ok then
            customSoundInput:SetText("")
            owner:RefreshControls()
            print(string.format(L["Preydator: Added sound file '%s'."], tostring(message)))
        else
            print("Preydator: " .. tostring(message))
        end
    end)
    CreateActionButton(parent, COLUMN_RIGHT_X + 115, -86, 105, L["Remove File"], function()
        local ok, message = api.RemoveSoundFileName(customSoundInput:GetText())
        if ok then
            customSoundInput:SetText("")
            owner:RefreshControls()
            print(string.format(L["Preydator: Removed sound file '%s'."], tostring(message)))
        else
            print("Preydator: " .. tostring(message))
        end
    end)
    CreateActionButton(parent, COLUMN_RIGHT_X, -130, 140, string.format(L["Test Stage %d"], 1), function()
        api.GetState().stageSoundPlayed[1] = nil
        local path = api.ResolveStageSoundPath(1)
        if not path then
            print(string.format(L["Preydator: No stage %d sound configured."], 1))
            return
        end
        if not api.TryPlayStageSound(1, true) then
            print(string.format(L["Preydator: Stage %d sound file failed to play. Ensure this file exists as .ogg: %s"], 1, tostring(path)))
        end
    end)
    CreateActionButton(parent, COLUMN_RIGHT_X, -160, 140, string.format(L["Test Stage %d"], 2), function()
        api.GetState().stageSoundPlayed[2] = nil
        local path = api.ResolveStageSoundPath(2)
        if not path then
            print(string.format(L["Preydator: No stage %d sound configured."], 2))
            return
        end
        if not api.TryPlayStageSound(2, true) then
            print(string.format(L["Preydator: Stage %d sound file failed to play. Ensure this file exists as .ogg: %s"], 2, tostring(path)))
        end
    end)
    CreateActionButton(parent, COLUMN_RIGHT_X, -190, 140, string.format(L["Test Stage %d"], 3), function()
        api.GetState().stageSoundPlayed[3] = nil
        local path = api.ResolveStageSoundPath(3)
        if not path then
            print(string.format(L["Preydator: No stage %d sound configured."], 3))
            return
        end
        if not api.TryPlayStageSound(3, true) then
            print(string.format(L["Preydator: Stage %d sound file failed to play. Ensure this file exists as .ogg: %s"], 3, tostring(path)))
        end
    end)
    CreateActionButton(parent, COLUMN_RIGHT_X, -220, 140, string.format(L["Test Stage %d"], 4), function()
        api.GetState().stageSoundPlayed[4] = nil
        local path = api.ResolveStageSoundPath(4)
        if not path then
            print(string.format(L["Preydator: No stage %d sound configured."], 4))
            return
        end
        if not api.TryPlayStageSound(4, true) then
            print(string.format(L["Preydator: Stage %d sound file failed to play. Ensure this file exists as .ogg: %s"], 4, tostring(path)))
        end
    end)
    CreateActionButton(parent, COLUMN_RIGHT_X, -250, 140, L["Test Ambush"], function()
        api.TriggerAmbushAlert("Manual test", "options")
    end)
    local note = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    note:SetPoint("TOPLEFT", parent, "TOPLEFT", COLUMN_RIGHT_X, -286)
    note:SetWidth(250)
    note:SetJustifyH("LEFT")
    note:SetWordWrap(true)
    note:SetText(L["HINT_AUDIO_SLIDER"])
end

local function BuildAdvancedPage(owner, parent)
    local db = api.GetSettings()
    local defaults = api.GetDefaults()
    CreateSectionTitle(parent, COLUMN_LEFT_X, -10, L["Restore / Reset"])
    CreateActionButton(parent, COLUMN_LEFT_X, -38, 180, L["Restore Default Names"], function()
        for stageIndex = 1, (constants.MAX_STAGE - 1) do
            db.stageLabels[stageIndex] = defaults.stageLabels[stageIndex]
        end
        db.outOfZoneLabel = constants.DEFAULT_OUT_OF_ZONE_LABEL
        db.ambushCustomText = ""
        api.NormalizeLabelSettings()
        api.UpdateBarDisplay()
        owner:RefreshControls()
    end)
    CreateActionButton(parent, COLUMN_LEFT_X, -66, 180, L["Restore Default Sounds"], function()
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
    CreateActionButton(parent, COLUMN_LEFT_X, -94, 180, L["Reset All Defaults"], function()
        api.ResetAllSettings()
        owner:RefreshControls()
    end)

    RegisterRefresher(owner, CreateCheckbox(parent, COLUMN_LEFT_X, -126, L["Enable Debug"], function()
        return db.debugSounds == true
    end, function(value)
        db.debugSounds = value and true or false
        _G.PreydatorDebugDB.enabled = db.debugSounds and true or false
    end))

    RegisterRefresher(owner, CreateCheckbox(parent, COLUMN_LEFT_X, -154, L["Currency Debug Events"], function()
        return db.currencyDebugEvents == true
    end, function(value)
        db.currencyDebugEvents = value and true or false
    end))

    CreateActionButton(parent, COLUMN_LEFT_X, -184, 180, L["Show What's New"], function()
        db.currencyWhatsNewSeenVersion = nil
        local tracker = Preydator:GetModule("CurrencyTracker")
        if tracker and type(tracker.ShowCurrencyWhatsNew) == "function" then
            tracker:ShowCurrencyWhatsNew(true)
        end
    end)
    CreateActionButton(parent, COLUMN_LEFT_X, -216, 180, L["Refresh Hunt Cache"], function()
        local huntScanner = Preydator:GetModule("HuntScanner")
        if huntScanner and type(huntScanner.RefreshRewardCache) == "function" then
            huntScanner:RefreshRewardCache()
            print("Preydator: Hunt reward cache refresh queued.")
        end
    end)
    CreateActionButton(parent, COLUMN_LEFT_X, -248, 180, L["Refresh Hunt Table Now"], function()
        local huntScanner = Preydator:GetModule("HuntScanner")
        if huntScanner and type(huntScanner.RefreshNow) == "function" then
            huntScanner:RefreshNow()
        end
    end)

    CreateSectionTitle(parent, COLUMN_RIGHT_X, -10, L["Notes"])
    local note = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    note:SetPoint("TOPLEFT", parent, "TOPLEFT", COLUMN_RIGHT_X, -44)
    note:SetWidth(260)
    note:SetJustifyH("LEFT")
    note:SetWordWrap(true)
    note:SetText(L["HINT_ADVANCED_NOTES"])
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
    local tabLabels = { L["General"], L["Display"], L["Vertical"], L["Text"], L["Audio"], L["Hunt Table"], L["Warband"], L["Currencies"], L["Advanced"] }
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

        if tabLabels[index] == L["Currencies"] or tabLabels[index] == L["Warband"] then
            RefreshCurrencyTrackerPanel()
        elseif tabLabels[index] == L["Hunt Table"] then
            RefreshHuntTrackerPanel()
        end
    end)

    self.tabs = tabs
    self.tabFrames = self.tabFrames or {}
    self.refreshers = self.refreshers or {}

    local function BuildCurrenciesPage(owner, frame)
        local tracker = Preydator:GetModule("CurrencyTracker")
        if tracker and type(tracker.BuildCurrencyPage) == "function" then
            tracker:BuildCurrencyPage(owner, frame)
        end
    end

    local pageBuilders = {
        BuildGeneralPage,
        BuildDisplayPage,
        BuildVerticalPage,
        BuildTextPage,
        BuildAudioPage,
        BuildHuntPage,
        BuildWarbandPage,
        BuildCurrenciesPage,
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
    subtitle:SetText(L["HINT_PANEL_SUBTITLE"])

    panel:SetScript("OnShow", function()
        self:RefreshControls()
        local huntScanner = Preydator:GetModule("HuntScanner")
        if huntScanner and type(huntScanner.HandleOptionsPanelVisibility) == "function" then
            huntScanner:HandleOptionsPanelVisibility(true)
        end
    end)

    panel:SetScript("OnHide", function()
        local huntScanner = Preydator:GetModule("HuntScanner")
        if huntScanner and type(huntScanner.HandleOptionsPanelVisibility) == "function" then
            huntScanner:HandleOptionsPanelVisibility(false)
        end
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