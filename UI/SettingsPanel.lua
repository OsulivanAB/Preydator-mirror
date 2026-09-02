-- Preydator :: UI/SettingsPanel.lua
-- Author: RagingAltoholic
-- Responsibility: the in-game options UI. Renders from and writes back
-- through Core/Settings.lua's public API only -- never touches State or any
-- other runtime directly. Most categories use Blizzard's modern Settings API
-- (Settings.RegisterVerticalLayoutCategory + Settings.RegisterProxySetting +
-- Settings.CreateCheckbox/CreateDropdown/CreateSlider), which auto-handles
-- layout with zero pixel-position code. That API has no first-class control
-- for color swatches, free text entry, or action buttons, so the categories
-- that need those (Bar Colors, Text & Labels, Advanced) use a small custom
-- canvas frame instead, built with a shared vertical-stacking helper rather
-- than hardcoded coordinates.
-- Reads: Core/Settings.lua.
-- Writes: Core/Settings.lua, via Settings.Set only (every control's setter
-- calls this and nothing else -- BarFrame/SoundsRuntime/etc. already react to
-- Settings.Subscribe on their own, so no control here needs to know what to
-- refresh).

local Preydator = _G.Preydator
local CreateFrame = _G.CreateFrame
local Settings = _G.Settings

local SettingsPanel = {}

local ROW_SPACING = 50
local ROW_LEFT_MARGIN = 16
local CONTROL_INDENT = 6
local CONTROL_OFFSET = -4

local FONT_OPTIONS = {
    { value = "frizqt", label = "Friz Quadrata" },
    { value = "arialn", label = "Arial Narrow" },
    { value = "skurri", label = "Skurri" },
    { value = "morpheus", label = "Morpheus" },
}

local SOUND_FOLDER_FALLBACK = "Interface\\AddOns\\Preydator\\sounds\\"

-- text.* fields the "Restore Default Names" action resets.
local NAME_FIELD_KEYS = {
    "text.stage_prefix", "text.stage_suffix", "text.out_of_zone_prefix", "text.out_of_zone_suffix",
    "text.ambush_prefix", "text.ambush_suffix_template", "text.pack_ambush_prefix",
    "text.pack_ambush_suffix_template",
}

-- sound.* path fields the "Restore Default Sounds" action resets.
local SOUND_FIELD_KEYS = {
    "sound.stage_path", "sound.ambush_path", "sound.pack_ambush_path", "sound.exploding_corpse_snakes_path",
}

local function L(key)
    local localization = Preydator:GetModule("LocalizationAdapter")
    if localization and type(localization.L) == "function" then
        return localization.L(key)
    end
    return key
end

local function getSettings()
    return Preydator:GetModule("Settings")
end

local function getArrayValue(key, index)
    local settings = getSettings()
    local arr = settings and settings.Get(key)
    return (type(arr) == "table" and arr[index]) or ""
end

local function setArrayValue(key, index, value)
    local settings = getSettings()
    if not settings then
        return
    end
    local arr = settings.Get(key)
    local copy = {}
    if type(arr) == "table" then
        for k, v in pairs(arr) do
            copy[k] = v
        end
    end
    copy[index] = value
    settings.Set(key, copy)
end

local function restoreDefaults(keys)
    local settings = getSettings()
    if not settings then
        return
    end
    local defaults = settings.GetDefaults()
    for _, key in ipairs(keys) do
        local category, field = key:match("^([^.]+)%.(.+)$")
        local value = category and defaults[category] and defaults[category][field]
        settings.Set(key, value)
    end
end

-- ---------------------------------------------------------------------------
-- Custom-canvas row helpers (Bar Colors / Text & Labels / Advanced only).
-- Every row anchors below the previous one by one fixed constant -- no
-- control anywhere hardcodes an absolute y-coordinate, unlike the old code.
-- ---------------------------------------------------------------------------

local function anchorRowTop(region, previous, canvas)
    region:ClearAllPoints()
    if previous then
        region:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", 0, -ROW_SPACING)
    else
        region:SetPoint("TOPLEFT", canvas, "TOPLEFT", ROW_LEFT_MARGIN, -ROW_LEFT_MARGIN)
    end
    canvas.rowCount = (canvas.rowCount or 0) + 1
end

local function createColorSwatchRow(canvas, previous, label, getter, setter, allowAlpha, isEnabledFn)
    local title = canvas:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    title:SetText(label)
    anchorRowTop(title, previous, canvas)

    local swatch = CreateFrame("Button", nil, canvas)
    swatch:SetSize(20, 20)
    swatch:SetPoint("TOPLEFT", title, "BOTTOMLEFT", CONTROL_INDENT, CONTROL_OFFSET)
    local texture = swatch:CreateTexture(nil, "OVERLAY")
    texture:SetAllPoints(swatch)

    local function refresh()
        local color = getter() or { 1, 1, 1, 1 }
        texture:SetColorTexture(color[1], color[2], color[3], color[4])
        local enabled = (not isEnabledFn) or isEnabledFn()
        swatch:SetEnabled(enabled)
        texture:SetDesaturated(not enabled)
        swatch:SetAlpha(enabled and 1 or 0.4)
    end

    swatch:SetScript("OnClick", function()
        if isEnabledFn and not isEnabledFn() then
            return
        end
        local color = getter() or { 1, 1, 1, 1 }
        local info = {}
        info.r, info.g, info.b = color[1], color[2], color[3]
        info.opacity = color[4]
        info.hasOpacity = allowAlpha
        info.swatchFunc = function()
            local r, g, b = _G.ColorPickerFrame:GetColorRGB()
            local a = allowAlpha and _G.ColorPickerFrame:GetColorAlpha() or color[4]
            setter({ r, g, b, a })
            refresh()
        end
        info.opacityFunc = info.swatchFunc
        info.cancelFunc = function(previousValues)
            setter({ previousValues.r, previousValues.g, previousValues.b, previousValues.opacity or color[4] })
            refresh()
        end
        _G.ColorPickerFrame:SetupColorPickerAndShow(info)
    end)

    refresh()
    canvas.colorSwatchRefreshers = canvas.colorSwatchRefreshers or {}
    table.insert(canvas.colorSwatchRefreshers, refresh)

    return title
end

local function createEditBoxRow(canvas, previous, label, getter, setter, maxLetters)
    local title = canvas:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    title:SetText(label)
    anchorRowTop(title, previous, canvas)

    local editBox = CreateFrame("EditBox", nil, canvas, "InputBoxTemplate")
    editBox:SetSize(220, 20)
    editBox:SetAutoFocus(false)
    if maxLetters then
        editBox:SetMaxLetters(maxLetters)
    end
    editBox:SetPoint("TOPLEFT", title, "BOTTOMLEFT", CONTROL_INDENT + 6, CONTROL_OFFSET)
    editBox:SetText(getter() or "")
    editBox:SetScript("OnEnterPressed", function(self)
        setter(self:GetText())
        self:ClearFocus()
    end)
    editBox:SetScript("OnEscapePressed", function(self)
        self:SetText(getter() or "")
        self:ClearFocus()
    end)

    return title
end

-- Cycle-button "dropdown" for the custom-canvas categories -- avoids the
-- legacy UIDropDownMenu widget system entirely (one click advances to the
-- next option), which is simpler and lower-risk than reimplementing a real
-- dropdown by hand.
local function createDropdownRow(canvas, previous, label, options, getter, setter)
    local title = canvas:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    title:SetText(label)
    anchorRowTop(title, previous, canvas)

    local button = CreateFrame("Button", nil, canvas, "UIPanelButtonTemplate")
    button:SetSize(220, 22)
    button:SetPoint("TOPLEFT", title, "BOTTOMLEFT", CONTROL_INDENT, CONTROL_OFFSET)

    local function labelFor(value)
        for _, option in ipairs(options) do
            if option.value == value then
                return option.label
            end
        end
        return options[1] and options[1].label or ""
    end

    button:SetText(labelFor(getter()))
    button:SetScript("OnClick", function()
        local currentIndex = 1
        local currentValue = getter()
        for i, option in ipairs(options) do
            if option.value == currentValue then
                currentIndex = i
                break
            end
        end
        local nextOption = options[currentIndex + 1] or options[1]
        setter(nextOption.value)
        button:SetText(nextOption.label)
    end)

    return title
end

local sliderCounter = 0
local function createSliderRow(canvas, previous, label, minValue, maxValue, step, getter, setter)
    sliderCounter = sliderCounter + 1
    local slider = CreateFrame("Slider", "PreydatorSettingsSlider" .. sliderCounter, canvas, "OptionsSliderTemplate")
    slider:SetSize(220, 16)
    anchorRowTop(slider, previous, canvas)
    slider:SetMinMaxValues(minValue, maxValue)
    slider:SetValueStep(step)
    slider:SetObeyStepOnDrag(true)
    _G[slider:GetName() .. "Low"]:SetText(minValue)
    _G[slider:GetName() .. "High"]:SetText(maxValue)
    _G[slider:GetName() .. "Text"]:SetText(label)
    slider:SetValue(getter() or minValue)
    slider:SetScript("OnValueChanged", function(_, value)
        setter(value)
    end)

    return slider
end

local function createCheckboxRow(canvas, previous, label, getter, setter)
    local checkbox = CreateFrame("CheckButton", nil, canvas, "UICheckButtonTemplate")
    checkbox:SetSize(24, 24)
    anchorRowTop(checkbox, previous, canvas)
    checkbox.Text:SetText(label)
    checkbox:SetChecked(getter() == true)
    checkbox:SetScript("OnClick", function(self)
        setter(self:GetChecked() == true)
    end)

    return checkbox
end

local function createButtonRow(canvas, previous, label, onClick)
    local button = CreateFrame("Button", nil, canvas, "UIPanelButtonTemplate")
    button:SetSize(200, 22)
    button:SetText(label)
    anchorRowTop(button, previous, canvas)
    button:SetScript("OnClick", onClick)

    return button
end

-- ---------------------------------------------------------------------------
-- Native (Settings API) registration helpers -- used by every category
-- except Bar Colors / Text & Labels / Advanced.
-- ---------------------------------------------------------------------------

local function registerCheckbox(subcategory, key, name, tooltip, default)
    local settings = getSettings()
    local setting = Settings.RegisterProxySetting(subcategory, key, Settings.VarType.Boolean, name, default,
        function() return settings.Get(key) == true end,
        function(value) settings.Set(key, value == true) end)
    Settings.CreateCheckbox(subcategory, setting, tooltip)
end

local function registerDropdown(subcategory, key, name, tooltip, options, default)
    local settings = getSettings()
    local setting = Settings.RegisterProxySetting(subcategory, key, Settings.VarType.String, name, default,
        function() return settings.Get(key) end,
        function(value) settings.Set(key, value) end)
    local function getOptions()
        local container = Settings.CreateControlTextContainer()
        for _, option in ipairs(options) do
            container:Add(option.value, option.label)
        end
        return container:GetData()
    end
    Settings.CreateDropdown(subcategory, setting, getOptions, tooltip)
end

local function registerSlider(subcategory, key, name, tooltip, minValue, maxValue, step, default)
    local settings = getSettings()
    local setting = Settings.RegisterProxySetting(subcategory, key, Settings.VarType.Number, name, default,
        function() return settings.Get(key) end,
        function(value) settings.Set(key, value) end)
    local options = Settings.CreateSliderOptions(minValue, maxValue, step)
    Settings.CreateSlider(subcategory, setting, options, tooltip)
end

-- Sound-path dropdowns are native too, but need array-index awareness
-- (sound.stage_path[1..4]) and a dynamic option list built from
-- sound.custom_file_names -- both unlike registerDropdown's fixed list.
local function registerSoundPathDropdown(subcategory, key, index, name, tooltip)
    local settings = getSettings()

    local function getter()
        local value = settings.Get(key)
        if index then
            return type(value) == "table" and value[index] or nil
        end
        return value
    end

    local function setter(value)
        if index then
            local arr = settings.Get(key)
            local copy = {}
            if type(arr) == "table" then
                for k, v in pairs(arr) do
                    copy[k] = v
                end
            end
            copy[index] = value
            settings.Set(key, copy)
        else
            settings.Set(key, value)
        end
    end

    local defaults = settings.GetDefaults()
    local defaultCategory, defaultField = key:match("^([^.]+)%.(.+)$")
    local defaultValue = defaultCategory and defaults[defaultCategory] and defaults[defaultCategory][defaultField]
    if index and type(defaultValue) == "table" then
        defaultValue = defaultValue[index]
    end

    local variableKey = index and (key .. "." .. index) or key
    local setting = Settings.RegisterProxySetting(subcategory, variableKey, Settings.VarType.String, name,
        defaultValue, getter, setter)

    local function getOptions()
        local container = Settings.CreateControlTextContainer()
        local currentValue = getter()
        local prefix = (type(currentValue) == "string" and currentValue:match("^(.*[\\/])")) or SOUND_FOLDER_FALLBACK
        local fileNames = settings.Get("sound.custom_file_names")
        if type(fileNames) == "table" then
            for _, fileName in ipairs(fileNames) do
                container:Add(prefix .. fileName, fileName)
            end
        end
        return container:GetData()
    end
    Settings.CreateDropdown(subcategory, setting, getOptions, tooltip)
end

-- ---------------------------------------------------------------------------
-- Categories
-- ---------------------------------------------------------------------------

-- Registered directly on the root category, not a "General" subcategory --
-- the root page is otherwise empty (Settings.RegisterVerticalLayoutCategory
-- supports controls directly on it), so there's no reason to make these the
-- one extra click behind a tab.
local function buildGeneralSettings(category)
    registerCheckbox(category, "general.bar_enabled", L("Enable Bar"),
        L("Show the Prey Hunt progress bar."), true)
    registerCheckbox(category, "general.sounds_enabled", L("Enable Sounds"),
        L("Master toggle for all Preydator sounds."), true)
    registerCheckbox(category, "general.hunt_enabled", L("Enable Hunt Table Tracking"),
        L("Scan and track Hunt Table offers."), true)
    registerCheckbox(category, "general.only_show_in_prey_zone", L("Only Show Bar in Prey Zone"),
        L("Hide the bar entirely outside the active hunt's zone."), false)
    registerCheckbox(category, "general.disable_default_prey_icon", L("Hide Blizzard's Prey Icon"),
        L("Suppress the default Blizzard prey-hunt overlay icon."), false)
    registerCheckbox(category, "general.debug_logging_enabled", L("Enable Debug Logging"),
        L("Verbose logging for troubleshooting."), false)
    registerCheckbox(category, "general.lock_bar", L("Lock Bar"),
        L("Prevent dragging the bar."), false)
    registerCheckbox(category, "general.minimap_hidden", L("Hide Minimap Button"),
        L("Hide Preydator's minimap/Addon Compartment button."), false)
end

local function buildBarDisplayCategory(category)
    local subcategory = Settings.RegisterVerticalLayoutSubcategory(category, L("Bar Display"))

    registerDropdown(subcategory, "bar.orientation", L("Orientation"), L("Horizontal or vertical bar layout."), {
        { value = "horizontal", label = L("Horizontal") },
        { value = "vertical", label = L("Vertical") },
    }, "horizontal")

    registerDropdown(subcategory, "bar.texture_key", L("Bar Texture"), L("Fill texture preset."), {
        { value = "default", label = L("Default") },
        { value = "flat", label = L("Flat") },
        { value = "raid", label = L("Raid HP Fill") },
        { value = "classic", label = L("Classic Skill Bar") },
    }, "default")

    do
        -- Not a plain registerDropdown: picking a theme needs to bulk-apply
        -- Settings.ApplyBarAccessibilityTheme's six color fields, not just
        -- store the enum value itself.
        local settings = getSettings()
        local key = "bar.accessibility_theme"
        local setting = Settings.RegisterProxySetting(subcategory, key, Settings.VarType.String,
            L("Accessibility Theme"), "default",
            function() return settings.Get(key) end,
            function(value) settings.ApplyBarAccessibilityTheme(value) end)
        local function getOptions()
            local container = Settings.CreateControlTextContainer()
            container:Add("default", L("Default"))
            container:Add("deuteranopia", L("Deuteranopia"))
            container:Add("protanopia", L("Protanopia"))
            return container:GetData()
        end
        Settings.CreateDropdown(subcategory, setting, getOptions, L("One-click colorblind-friendly color preset."))
    end

    registerDropdown(subcategory, "bar.percent_display", L("Percent Text Placement"),
        L("Where the percent-complete text appears."), {
            { value = "inside", label = L("Inside Bar") },
            { value = "above_bar", label = L("Above Bar") },
            { value = "above_ticks", label = L("Above Ticks") },
            { value = "under_ticks", label = L("Under Ticks") },
            { value = "below_bar", label = L("Below Bar") },
            { value = "off", label = L("Off") },
        }, "inside")

    registerDropdown(subcategory, "bar.progress_segments", L("Progress Segments"),
        L("Tick/segment division used when Blizzard doesn't expose a precise percent."), {
            { value = "quarters", label = L("Quarters (25/50/75/100)") },
            { value = "thirds", label = L("Thirds (33/66/100)") },
        }, "quarters")

    registerDropdown(subcategory, "bar.vertical_fill_direction", L("Vertical Fill Direction"),
        L("Which way the bar fills in vertical orientation."), {
            { value = "up", label = L("Up") },
            { value = "down", label = L("Down") },
        }, "up")

    registerDropdown(subcategory, "bar.vertical_text_side", L("Vertical Text Side"),
        L("Which side of the bar the label text sits on in vertical orientation."), {
            { value = "left", label = L("Left") },
            { value = "right", label = L("Right") },
        }, "right")

    registerSlider(subcategory, "bar.scale_horizontal", L("Horizontal Scale"),
        L("Bar scale in horizontal orientation."), 0.5, 2, 0.05, 1.0)
    registerSlider(subcategory, "bar.scale_vertical", L("Vertical Scale"),
        L("Bar scale in vertical orientation."), 0.5, 2, 0.05, 0.9)
    registerSlider(subcategory, "bar.width_horizontal", L("Horizontal Width"),
        L("Bar width in horizontal orientation."), 100, 350, 1, 160)
    registerSlider(subcategory, "bar.height_horizontal", L("Horizontal Height"),
        L("Bar height in horizontal orientation."), 10, 60, 1, 30)
    registerSlider(subcategory, "bar.width_vertical", L("Vertical Width"),
        L("Bar width in vertical orientation."), 10, 60, 1, 40)
    registerSlider(subcategory, "bar.height_vertical", L("Vertical Height"),
        L("Bar height in vertical orientation."), 100, 350, 1, 160)

    registerCheckbox(subcategory, "bar.show_ticks", L("Show Tick Marks"),
        L("Show stage boundary tick marks on the bar."), true)
    registerCheckbox(subcategory, "bar.border_color_linked", L("Link Border Color to Fill Color"),
        L("Border color automatically mirrors the fill color."), true)
    registerCheckbox(subcategory, "bar.show_in_edit_mode", L("Show During Edit Mode"),
        L("Force the bar visible with placeholder text while Blizzard Edit Mode is open."), true)

    return subcategory
end

local function buildBarColorsCategory(category)
    local canvas = CreateFrame("Frame")
    local subcategory = Settings.RegisterCanvasLayoutSubcategory(category, canvas, L("Bar Colors"))
    local settings = getSettings()

    local function colorGetter(key)
        return function() return settings.Get(key) end
    end
    local function colorSetter(key)
        return function(value) settings.Set(key, value) end
    end

    local previous = createColorSwatchRow(canvas, nil, L("Fill Color"),
        colorGetter("bar.fill_color"), colorSetter("bar.fill_color"), true)
    previous = createColorSwatchRow(canvas, previous, L("Border Color"),
        colorGetter("bar.border_color"), colorSetter("bar.border_color"), true,
        function() return settings.Get("bar.border_color_linked") ~= true end)
    previous = createColorSwatchRow(canvas, previous, L("Title Text Color"),
        colorGetter("bar.title_color"), colorSetter("bar.title_color"), true)
    previous = createColorSwatchRow(canvas, previous, L("Percent Text Color"),
        colorGetter("bar.percent_color"), colorSetter("bar.percent_color"), true)
    previous = createColorSwatchRow(canvas, previous, L("Tick Color"),
        colorGetter("bar.tick_color"), colorSetter("bar.tick_color"), true)
    createColorSwatchRow(canvas, previous, L("Background Color"),
        colorGetter("bar.bg_color"), colorSetter("bar.bg_color"), true)

    -- The Border Color swatch's enabled state depends on bar.border_color_linked,
    -- which lives in the separate "Bar Display" native category -- re-check
    -- whenever this canvas becomes visible rather than wiring a cross-category
    -- live subscription for one cosmetic detail.
    canvas:SetScript("OnShow", function()
        for _, refresh in ipairs(canvas.colorSwatchRefreshers or {}) do
            refresh()
        end
    end)

    return subcategory
end

local function buildTextLabelsCategory(category)
    local canvas = CreateFrame("Frame")
    local subcategory = Settings.RegisterCanvasLayoutSubcategory(category, canvas, L("Text & Labels"))
    local settings = getSettings()

    local scrollFrame = CreateFrame("ScrollFrame", nil, canvas, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", canvas, "TOPLEFT", 0, -4)
    scrollFrame:SetPoint("BOTTOMRIGHT", canvas, "BOTTOMRIGHT", -24, 4)

    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetSize(1, 1)
    scrollFrame:SetScrollChild(scrollChild)
    scrollFrame:SetScript("OnSizeChanged", function(_, width)
        scrollChild:SetWidth(width)
    end)

    local previous = createDropdownRow(scrollChild, nil, L("Stage Label Mode"), {
        { value = "center", label = L("Centered") },
        { value = "left", label = L("Left (Prefix only)") },
        { value = "left_combined", label = L("Left (Prefix + Suffix)") },
        { value = "left_suffix", label = L("Left (Suffix only)") },
        { value = "right", label = L("Right (Suffix only)") },
        { value = "right_combined", label = L("Right (Prefix + Suffix)") },
        { value = "right_prefix", label = L("Right (Prefix only)") },
        { value = "separate", label = L("Separate (Prefix + Suffix)") },
        { value = "none", label = L("No Text") },
    }, function() return settings.Get("text.stage_label_mode") end,
        function(value) settings.Set("text.stage_label_mode", value) end)

    previous = createDropdownRow(scrollChild, previous, L("Label Row Position"), {
        { value = "above", label = L("Above Bar") },
        { value = "below", label = L("Below Bar") },
    }, function() return settings.Get("text.label_row_position") end,
        function(value) settings.Set("text.label_row_position", value) end)

    previous = createDropdownRow(scrollChild, previous, L("Title Font"), FONT_OPTIONS,
        function() return settings.Get("text.title_font_key") end,
        function(value) settings.Set("text.title_font_key", value) end)

    previous = createDropdownRow(scrollChild, previous, L("Percent Font"), FONT_OPTIONS,
        function() return settings.Get("text.percent_font_key") end,
        function(value) settings.Set("text.percent_font_key", value) end)

    previous = createSliderRow(scrollChild, previous, L("Font Size"), 8, 24, 1,
        function() return settings.Get("text.font_size") end,
        function(value) settings.Set("text.font_size", value) end)

    for stage = 1, 4 do
        previous = createEditBoxRow(scrollChild, previous, L("Stage " .. stage .. " Prefix"),
            function() return getArrayValue("text.stage_prefix", stage) end,
            function(value) setArrayValue("text.stage_prefix", stage, value) end)
    end
    for stage = 1, 4 do
        previous = createEditBoxRow(scrollChild, previous, L("Stage " .. stage .. " Label"),
            function() return getArrayValue("text.stage_suffix", stage) end,
            function(value) setArrayValue("text.stage_suffix", stage, value) end)
    end

    previous = createEditBoxRow(scrollChild, previous, L("Out of Zone Prefix"),
        function() return settings.Get("text.out_of_zone_prefix") end,
        function(value) settings.Set("text.out_of_zone_prefix", value) end)
    previous = createEditBoxRow(scrollChild, previous, L("Out of Zone Label"),
        function() return settings.Get("text.out_of_zone_suffix") end,
        function(value) settings.Set("text.out_of_zone_suffix", value) end)
    previous = createEditBoxRow(scrollChild, previous, L("Ambush Prefix"),
        function() return settings.Get("text.ambush_prefix") end,
        function(value) settings.Set("text.ambush_prefix", value) end)
    previous = createEditBoxRow(scrollChild, previous, L("Ambush Label (use {preyTargetName})"),
        function() return settings.Get("text.ambush_suffix_template") end,
        function(value) settings.Set("text.ambush_suffix_template", value) end)
    previous = createEditBoxRow(scrollChild, previous, L("Pack Ambush Prefix"),
        function() return settings.Get("text.pack_ambush_prefix") end,
        function(value) settings.Set("text.pack_ambush_prefix", value) end)
    createEditBoxRow(scrollChild, previous, L("Pack Ambush Label (use {packAmbushSourceName})"),
        function() return settings.Get("text.pack_ambush_suffix_template") end,
        function(value) settings.Set("text.pack_ambush_suffix_template", value) end)

    scrollChild:SetHeight(((scrollChild.rowCount or 1) * ROW_SPACING) + ROW_LEFT_MARGIN)

    return subcategory
end

local function buildSoundCategory(category)
    local subcategory = Settings.RegisterVerticalLayoutSubcategory(category, L("Sound & Alerts"))

    registerDropdown(subcategory, "sound.channel", L("Sound Channel"),
        L("Which audio channel Preydator sounds play on."), {
            { value = "Master", label = L("Master") },
            { value = "SFX", label = L("Sound Effects") },
            { value = "Dialog", label = L("Dialog") },
            { value = "Ambience", label = L("Ambience") },
            { value = "Music", label = L("Music") },
        }, "Master")

    for stage = 1, 4 do
        registerSoundPathDropdown(subcategory, "sound.stage_path", stage,
            L("Stage " .. stage .. " Sound"), L("Sound played on entering this stage."))
    end

    registerCheckbox(subcategory, "sound.ambush_enabled", L("Enable Ambush Sound"),
        L("Play a sound when an ambush is detected."), true)
    registerSoundPathDropdown(subcategory, "sound.ambush_path", nil, L("Ambush Sound"),
        L("Sound played on ambush."))
    registerSlider(subcategory, "sound.alert_cooldown_seconds", L("Alert Cooldown"),
        L("Minimum time between ambush/Pack Ambush/Exploding Corpse Snakes alert sounds, so a "
            .. "fast kill doesn't replay a sound awkwardly close together."), 0, 300, 5, 60)

    registerCheckbox(subcategory, "sound.pack_ambush_enabled", L("Enable Pack Ambush Sound"),
        L("Play a sound when a Pack Scout or Pack Hunter appears (Season 2's Pack Ambush mechanic)."), true)
    registerSoundPathDropdown(subcategory, "sound.pack_ambush_path", nil, L("Pack Ambush Sound"),
        L("Sound played when Pack Ambush's mobs appear."))

    registerCheckbox(subcategory, "sound.exploding_corpse_snakes_enabled", L("Enable Exploding Corpse Snakes Sound"),
        L("Play a sound when a Venom-Bloated Python appears (Season 2's Exploding Corpse Snakes mechanic)."), true)
    registerSoundPathDropdown(subcategory, "sound.exploding_corpse_snakes_path", nil,
        L("Exploding Corpse Snakes Sound"), L("Sound played when a Venom-Bloated Python appears."))

    return subcategory
end

local function buildHuntScannerCategory(category)
    local subcategory = Settings.RegisterVerticalLayoutSubcategory(category, L("Hunt Scanner"))

    registerCheckbox(subcategory, "hunt.enabled", L("Enable Hunt Table Panel"),
        L("Track and list Hunt Table offers."), true)

    registerDropdown(subcategory, "hunt.panel_side", L("Panel Side"),
        L("Which side of the screen the hunt list anchors to."), {
            { value = "left", label = L("Left") },
            { value = "right", label = L("Right") },
        }, "right")

    registerDropdown(subcategory, "hunt.group_by", L("Group By"), L("How hunts are grouped in the list."), {
        { value = "none", label = L("None") },
        { value = "difficulty", label = L("Difficulty") },
        { value = "zone", label = L("Zone") },
    }, "difficulty")

    registerDropdown(subcategory, "hunt.sort_by", L("Sort By"), L("Primary sort field for the hunt list."), {
        { value = "difficulty", label = L("Difficulty") },
        { value = "zone", label = L("Zone") },
        { value = "title", label = L("Title") },
    }, "zone")

    registerDropdown(subcategory, "hunt.sort_direction", L("Sort Direction"),
        L("Ascending or descending sort order."), {
            { value = "asc", label = L("Ascending") },
            { value = "desc", label = L("Descending") },
        }, "asc")

    registerDropdown(subcategory, "hunt.reward_display_style", L("Reward Display Style"),
        L("How quest rewards are shown per hunt row."), {
            { value = "icon_inline", label = L("Icons Inline") },
            { value = "icon_count", label = L("Icon + Count") },
        }, "icon_inline")

    registerDropdown(subcategory, "hunt.difficulty_icon_set", L("Difficulty Icon Set"),
        L("Which bundled icon set to use for difficulty badges."), {
            { value = "default", label = L("Default") },
        }, "default")

    registerCheckbox(subcategory, "hunt.achievement_signals_enabled", L("Show Achievement Badges"),
        L("Show a badge on each hunt row for still-needed Prey achievements, with a hover "
            .. "tooltip listing which ones."), true)

    registerSlider(subcategory, "hunt.width", L("Panel Width"), L("Hunt Table panel width."), 200, 600, 1, 336)
    registerSlider(subcategory, "hunt.height", L("Panel Height"), L("Hunt Table panel height."), 200, 800, 1, 460)
    registerSlider(subcategory, "hunt.scale", L("Panel Scale"), L("Hunt Table panel scale."), 0.5, 2, 0.05, 1.0)
    registerSlider(subcategory, "hunt.font_size", L("Font Size"), L("Hunt Table panel font size."), 8, 24, 1, 12)

    registerCheckbox(subcategory, "hunt.preview_enabled", L("Preview Hunt Panel"),
        L("Force-show the hunt panel while adjusting the settings above, using your "
            .. "current hunts if any are cached or placeholder rows otherwise -- so "
            .. "layout changes are visible without leaving Settings."), false)

    return subcategory
end

-- Custom confirm frame for "Reset All Settings" -- deliberately NOT a
-- _G.StaticPopupDialogs entry. Live taint elimination testing (2026-08-28,
-- see memory preydator-taint-staticpopupdialogs) proved that registering
-- ANY entry into Blizzard's shared StaticPopupDialogs table from this addon
-- causes an ADDON_ACTION_FORBIDDEN/SpellStopCasting taint on the very next
-- Escape (reproducing on both a plain relog and after Hunt Table
-- interaction), regardless of timing (file-load vs PLAYER_LOGIN-deferred)
-- or which optional fields (hideOnEscape, etc.) were set -- the shared
-- table itself was the problem, not one specific field. This frame is
-- entirely Preydator's own, never touches any Blizzard global table, and
-- has no Escape-key integration for the same reason (no UISpecialFrames
-- registration either).
local resetConfirmFrame = nil
local function ensureResetConfirmFrame()
    if resetConfirmFrame then
        return resetConfirmFrame
    end

    local frame = CreateFrame("Frame", "PreydatorResetConfirmFrame", _G.UIParent, "BackdropTemplate")
    frame:SetSize(320, 130)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 },
    })
    frame:EnableMouse(true)
    frame:Hide()

    local text = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    text:SetPoint("TOP", frame, "TOP", 0, -24)
    text:SetWidth(280)
    text:SetText(L("Reset ALL Preydator settings to their defaults? This cannot be undone."))

    local yesButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    yesButton:SetSize(100, 22)
    yesButton:SetPoint("BOTTOMLEFT", frame, "BOTTOM", 10, 16)
    yesButton:SetText(_G.YES)
    yesButton:SetScript("OnClick", function()
        local settings = getSettings()
        if settings then
            settings.ResetToDefaults()
        end
        frame:Hide()
    end)

    local noButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    noButton:SetSize(100, 22)
    noButton:SetPoint("BOTTOMRIGHT", frame, "BOTTOM", -10, 16)
    noButton:SetText(_G.NO)
    noButton:SetScript("OnClick", function()
        frame:Hide()
    end)

    resetConfirmFrame = frame
    return frame
end

local function buildAdvancedCategory(category)
    local canvas = CreateFrame("Frame")
    local subcategory = Settings.RegisterCanvasLayoutSubcategory(category, canvas, L("Advanced"))
    local settings = getSettings()

    -- No tooltip support in this canvas checkbox helper (unlike the native
    -- Settings-API checkboxes elsewhere in this file) -- the label itself
    -- names the command that reads this setting's recorded data.
    local previous = createCheckboxRow(canvas, nil, L("Record Nameplates Seen During Hunts (see /pd ninspect)"),
        function() return settings.Get("debug.pack_ambush_verbose") == true end,
        function(value) settings.Set("debug.pack_ambush_verbose", value) end)

    previous = createButtonRow(canvas, previous, L("Reset Bar Position"), function()
        local barFrame = Preydator:GetModule("BarFrame")
        if barFrame then
            barFrame.ResetPosition()
        end
    end)

    previous = createButtonRow(canvas, previous, L("Refresh Hunt Cache"), function()
        local huntScanner = Preydator:GetModule("HuntScannerRuntime")
        if huntScanner then
            huntScanner.RefreshFromAdapter()
        end
    end)

    previous = createButtonRow(canvas, previous, L("Restore Default Names"), function()
        restoreDefaults(NAME_FIELD_KEYS)
    end)

    previous = createButtonRow(canvas, previous, L("Restore Default Sounds"), function()
        restoreDefaults(SOUND_FIELD_KEYS)
    end)

    createButtonRow(canvas, previous, L("Reset All Settings"), function()
        ensureResetConfirmFrame():Show()
    end)

    return subcategory
end

-- ---------------------------------------------------------------------------
-- Self-initialization. Deferred to PLAYER_LOGIN, not run at file-load time:
-- registering proxy settings/dropdowns can cause Blizzard's own Settings
-- framework to read a setting's current value immediately (e.g. for its
-- search index), and SavedVariables (everything Settings.Get reads) aren't
-- populated until after this addon's files finish loading -- reading that
-- early would get Core/Settings.lua's cache permanently stuck on default
-- values for the whole session (this exact bug was found and fixed in
-- UI/BarFrame.lua's self-init; applying the same precaution here since the
-- Options menu can't be opened before PLAYER_LOGIN anyway, so there's no
-- downside to waiting).
-- ---------------------------------------------------------------------------

local function initializeSettingsPanel()
    if not (Settings and Settings.RegisterVerticalLayoutCategory) then
        return
    end

    local category = Settings.RegisterVerticalLayoutCategory(L("Preydator"))

    buildGeneralSettings(category)
    buildBarDisplayCategory(category)
    buildBarColorsCategory(category)
    buildTextLabelsCategory(category)
    buildSoundCategory(category)
    buildHuntScannerCategory(category)
    buildAdvancedCategory(category)

    Settings.RegisterAddOnCategory(category)
    SettingsPanel.category = category

    _G.SLASH_PREYDATOR1 = "/preydator"
    _G.SlashCmdList["PREYDATOR"] = SettingsPanel.OpenSettings
end

-- Public so UI/Launcher.lua's minimap button/Addon Compartment click can
-- reuse the exact same open path as `/preydator` -- single source of truth,
-- not a second copy of the OpenToCategory call.
function SettingsPanel.OpenSettings()
    if Settings and type(Settings.OpenToCategory) == "function" and SettingsPanel.category then
        Settings.OpenToCategory(SettingsPanel.category:GetID())
    end
end

do
    local initFrame = CreateFrame("Frame")
    initFrame:RegisterEvent("PLAYER_LOGIN")
    initFrame:SetScript("OnEvent", function(self)
        self:UnregisterEvent("PLAYER_LOGIN")
        initializeSettingsPanel()
    end)
end

Preydator:RegisterModule("SettingsPanel", SettingsPanel)
return SettingsPanel
