-- Preydator :: UI/SettingsPanel.lua
-- Author: RagingAltoholic
-- Responsibility: the in-game options UI. Renders from and writes back
-- through Core/Settings.lua's public API only -- never touches State or any
-- other runtime directly. Every category is a custom canvas frame
-- (Settings.RegisterCanvasLayoutCategory for the root, RegisterCanvasLayout-
-- Subcategory for every tab below it), built with a shared vertical-stacking
-- helper rather than hardcoded coordinates, and scrolled where a category
-- has more rows than fit the visible pane.
--
-- This used to be a mix: most categories used Blizzard's native Settings API
-- (RegisterVerticalLayoutCategory/Subcategory + RegisterProxySetting +
-- CreateCheckbox/CreateDropdown/CreateSlider) for its auto-layout, and only
-- Bar Colors/Text & Labels/Advanced (which needed color swatches, free text,
-- or action buttons the native API has no control for) used canvas frames.
-- Converted entirely to canvas (2026-09-08) after confirming live that every
-- native-API category came with Blizzard's own "Defaults" button, and its
-- "All Settings" choice resets every other native-API category in the
-- entire client -- Blizzard's own settings and every other addon's, not
-- just Preydator's, with no way for any addon to narrow or opt out of that.
-- The only way to guarantee that button can never touch anything Preydator
-- owns is to never register a setting through Blizzard's proxy-setting
-- system at all, for any category. See buildGeneralSettings' own comment
-- for the root-category-specific part of this (RegisterCanvasLayoutCategory
-- vs. RegisterVerticalLayoutCategory).
-- Reads: Core/Settings.lua.
-- Writes: Core/Settings.lua, via Settings.Set only (every control's setter
-- calls this and nothing else -- BarFrame/SoundsRuntime/etc. already react to
-- Settings.Subscribe on their own, so no control here needs to know what to
-- refresh).

local Preydator = _G.Preydator
local CreateFrame = _G.CreateFrame
local Settings = _G.Settings

local SettingsPanel = {}

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
-- Custom-canvas row helpers -- every category now uses these (2026-09-08;
-- previously only Bar Colors / Text & Labels / Advanced did, see the
-- category-registration section below for why that changed). Every row
-- anchors below the previous one by a fixed constant -- no control anywhere
-- hardcodes an absolute y-coordinate.
-- ---------------------------------------------------------------------------

-- A title-plus-control row (dropdown/slider/color swatch) needs room for
-- both stacked lines; a single-line row (checkbox/button, no separate title)
-- only needs its own height plus a little breathing room. Using one spacing
-- for both (confirmed live, 2026-09-08 -- see Advanced tab overflow report)
-- wastes a lot of vertical space on any category that's mostly checkboxes/
-- buttons, which is exactly what pushed Advanced's content below the
-- visible pane with no scroll frame to reach it.
local ROW_SPACING = 50
local COMPACT_ROW_SPACING = 30

local function anchorRowTop(region, previous, canvas, spacing)
    region:ClearAllPoints()
    if previous then
        region:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", 0, -(spacing or ROW_SPACING))
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

-- EditBox -> getter, so refreshEditBoxValues can resync every currently-
-- built text field's displayed text against Settings in one pass -- same
-- pattern as sliderValueLabelFrames/refreshSliderValueLabels above.
-- Confirmed live (2026-09-03): boxes that were never manually edited (still
-- holding their real default text, e.g. "Blood in the Shadows") showed up
-- blank instead -- SetText(getter()) at creation is a one-shot read with no
-- live resync, so any moment where Settings wasn't fully ready yet left the
-- box stuck empty for the rest of the session with no way to self-correct.
-- Routing through Settings.Subscribe (fires on any settings change, same
-- pub/sub every other file in this addon already reacts to) closes that
-- gap regardless of what the original timing issue actually was.
local editBoxRefreshFrames = {}
local editBoxRefreshSubscribed = false

local function refreshEditBoxValues()
    for editBox, getter in pairs(editBoxRefreshFrames) do
        -- Never yank text out of a box the player is actively typing in --
        -- Settings.Subscribe fires for ANY settings change, not just this
        -- box's own key, so an unrelated edit elsewhere must not fight
        -- whatever's currently being typed here.
        if not editBox:HasFocus() then
            editBox:SetText(getter() or "")
            editBox:SetCursorPosition(0)
        end
    end
end

-- Shared by createEditBoxRow and createEditBoxPairRow -- builds one
-- title-less editbox control; the caller positions and labels it. Kept as
-- its own function so the pair row below doesn't duplicate the
-- OnEnterPressed/OnEscapePressed commit/revert logic a second time.
local function buildEditBoxControl(canvas, width, maxLetters, getter, setter)
    local editBox = CreateFrame("EditBox", nil, canvas, "InputBoxTemplate")
    editBox:SetSize(width, 20)
    editBox:SetAutoFocus(false)
    if maxLetters then
        editBox:SetMaxLetters(maxLetters)
    end
    -- Root-caused live (2026-09-04) via a temporary diagnostic: GetText(),
    -- IsShown, and GetAlpha all confirmed correct on every box while the
    -- text was still visually blank on screen -- not a data or timing bug
    -- at all. This is a known WoW EditBox quirk: text set via SetText()
    -- before the box's true on-screen width is settled can leave its
    -- internal scroll/cursor position stuck past the visible area, even
    -- though the stored text and every other property are entirely
    -- correct. SetCursorPosition(0) forces the visible view back to the
    -- start, which is the standard fix for this class of bug.
    editBox:SetText(getter() or "")
    editBox:SetCursorPosition(0)
    -- Re-reads via getter() and re-displays that after every commit, rather
    -- than trusting the just-typed text is what's now actually stored --
    -- ported from the old codebase's own CreateTextInput helper
    -- (Modules/Settings.lua:866-875), which did the same round-trip after
    -- every write. Makes any silent normalization/rejection visible
    -- immediately in the box itself instead of only surfacing later.
    editBox:SetScript("OnEnterPressed", function(self)
        setter(self:GetText())
        self:SetText(getter() or "")
        self:SetCursorPosition(0)
        self:ClearFocus()
    end)
    editBox:SetScript("OnEscapePressed", function(self)
        self:SetText(getter() or "")
        self:SetCursorPosition(0)
        self:ClearFocus()
    end)
    -- Typing a value and clicking away without pressing Enter silently
    -- discarded it (confirmed live, 2026-09-03: the product owner edited a
    -- Stage Label field and the bar kept showing the untouched default,
    -- "Blood in the Shadows") -- only OnEnterPressed committed. This also
    -- commits on focus loss, matching how most players actually expect a
    -- text field to behave (also matches the old codebase's own
    -- OnEditFocusLost handler on the same helper). Harmless if it fires
    -- right after OnEnterPressed/OnEscapePressed's own ClearFocus() (both
    -- already left the box holding the value this would write anyway) -- a
    -- redundant identical write, not a second real change.
    editBox:SetScript("OnEditFocusLost", function(self)
        setter(self:GetText())
        self:SetText(getter() or "")
        self:SetCursorPosition(0)
    end)

    editBoxRefreshFrames[editBox] = getter
    local settings = getSettings()
    if settings and not editBoxRefreshSubscribed and type(settings.Subscribe) == "function" then
        editBoxRefreshSubscribed = true
        settings.Subscribe(refreshEditBoxValues)
    end

    return editBox
end

-- Two Prefix/Label fields side by side on one row instead of stacked as two
-- separate full-width rows -- halves the Text & Labels category's vertical
-- scroll length (product owner's own mockup, Decisions Log item 43). Only
-- advances the row position once (anchorRowTop on the left column only);
-- the right column offsets horizontally from the left column's own title
-- instead of counting as a second independent row.
local PAIR_COLUMN_WIDTH = 260
local PAIR_EDITBOX_WIDTH = 200

local function createEditBoxPairRow(canvas, previous, leftLabel, leftGetter, leftSetter,
        rightLabel, rightGetter, rightSetter, maxLetters)
    local leftTitle = canvas:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    leftTitle:SetText(leftLabel)
    anchorRowTop(leftTitle, previous, canvas)

    local leftEditBox = buildEditBoxControl(canvas, PAIR_EDITBOX_WIDTH, maxLetters, leftGetter, leftSetter)
    leftEditBox:SetPoint("TOPLEFT", leftTitle, "BOTTOMLEFT", CONTROL_INDENT + 6, CONTROL_OFFSET)

    local rightTitle = canvas:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    rightTitle:SetText(rightLabel)
    rightTitle:SetPoint("TOPLEFT", leftTitle, "TOPLEFT", PAIR_COLUMN_WIDTH, 0)

    local rightEditBox = buildEditBoxControl(canvas, PAIR_EDITBOX_WIDTH, maxLetters, rightGetter, rightSetter)
    rightEditBox:SetPoint("TOPLEFT", rightTitle, "BOTTOMLEFT", CONTROL_INDENT + 6, CONTROL_OFFSET)

    return leftTitle
end

-- Shared tooltip wiring for any row control -- matches what Settings.Create-
-- Checkbox/CreateDropdown/CreateSlider gave every native control for free;
-- added here so converting a category off the native API (2026-09-08, see
-- below) doesn't silently drop every field's help text along with it.
local function attachTooltip(control, tooltip)
    if not tooltip or tooltip == "" then
        return
    end
    control:SetScript("OnEnter", function(self)
        _G.GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        _G.GameTooltip:SetText(tooltip, nil, nil, nil, nil, true)
        _G.GameTooltip:Show()
    end)
    control:SetScript("OnLeave", function()
        _G.GameTooltip:Hide()
    end)
end

-- Cycle-button "dropdown" for the custom-canvas categories -- avoids the
-- legacy UIDropDownMenu widget system entirely (one click advances to the
-- next option), which is simpler and lower-risk than reimplementing a real
-- dropdown by hand. `options` may be a plain array (the common case) or a
-- zero-arg function returning one -- the latter lets a caller rebuild the
-- list fresh on every read/click (e.g. the sound-path rows below, whose
-- option list depends on sound.custom_file_names and must reflect a file
-- added/removed after this row was already created).
local function resolveOptions(options)
    if type(options) == "function" then
        return options()
    end
    return options
end

local function createDropdownRow(canvas, previous, label, options, getter, setter, tooltip)
    local title = canvas:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    title:SetText(label)
    anchorRowTop(title, previous, canvas)

    local button = CreateFrame("Button", nil, canvas, "UIPanelButtonTemplate")
    button:SetSize(220, 22)
    button:SetPoint("TOPLEFT", title, "BOTTOMLEFT", CONTROL_INDENT, CONTROL_OFFSET)
    attachTooltip(button, tooltip)

    local function labelFor(resolved, value)
        for _, option in ipairs(resolved) do
            if option.value == value then
                return option.label
            end
        end
        return resolved[1] and resolved[1].label or ""
    end

    button:SetText(labelFor(resolveOptions(options), getter()))
    button:SetScript("OnClick", function()
        local resolved = resolveOptions(options)
        local currentIndex = 1
        local currentValue = getter()
        for i, option in ipairs(resolved) do
            if option.value == currentValue then
                currentIndex = i
                break
            end
        end
        local nextOption = resolved[currentIndex + 1] or resolved[1]
        if not nextOption then
            return
        end
        setter(nextOption.value)
        button:SetText(nextOption.label)
    end)

    return title
end

-- Frame -> {getter, decimals}, so every currently-built slider's live value
-- label can resync in one pass (Settings.Subscribe fires for ANY settings
-- change, not just this row's own key -- e.g. Reset All Settings, or a
-- value changed via /pd). Mirrors the native sliders' identical value-label
-- feature (Decisions Log item 60) -- ported here so converting a slider off
-- the native API doesn't drop that already-shipped, live-confirmed UX.
local canvasSliderValueLabels = {}
local canvasSliderLabelsSubscribed = false

local function formatSliderValue(value, decimals)
    if value == nil then
        return ""
    end
    return string.format("%." .. decimals .. "f", value)
end

local function refreshCanvasSliderValueLabels()
    for fontString, info in pairs(canvasSliderValueLabels) do
        fontString:SetText(formatSliderValue(info.getter(), info.decimals))
    end
end

local sliderCounter = 0
local function createSliderRow(canvas, previous, label, minValue, maxValue, step, getter, setter, tooltip)
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
    attachTooltip(slider, tooltip)

    local decimals = (step % 1 == 0) and 0 or 2
    local valueText = canvas:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    valueText:SetPoint("LEFT", slider, "RIGHT", 12, 0)
    valueText:SetText(formatSliderValue(getter(), decimals))
    canvasSliderValueLabels[valueText] = { getter = getter, decimals = decimals }

    local settings = getSettings()
    if settings and not canvasSliderLabelsSubscribed and type(settings.Subscribe) == "function" then
        canvasSliderLabelsSubscribed = true
        settings.Subscribe(refreshCanvasSliderValueLabels)
    end

    slider:SetScript("OnValueChanged", function(_, value)
        setter(value)
        valueText:SetText(formatSliderValue(value, decimals))
    end)

    return slider
end

local function createCheckboxRow(canvas, previous, label, getter, setter, tooltip)
    local checkbox = CreateFrame("CheckButton", nil, canvas, "UICheckButtonTemplate")
    checkbox:SetSize(24, 24)
    anchorRowTop(checkbox, previous, canvas, COMPACT_ROW_SPACING)
    checkbox.Text:SetText(label)
    checkbox:SetChecked(getter() == true)
    checkbox:SetScript("OnClick", function(self)
        setter(self:GetChecked() == true)
    end)
    attachTooltip(checkbox, tooltip)

    return checkbox
end

local function createButtonRow(canvas, previous, label, onClick)
    local button = CreateFrame("Button", nil, canvas, "UIPanelButtonTemplate")
    button:SetSize(200, 22)
    button:SetText(label)
    anchorRowTop(button, previous, canvas, COMPACT_ROW_SPACING)
    button:SetScript("OnClick", onClick)

    return button
end

-- Canvas equivalent of a sound-path dropdown -- needs array-index awareness
-- (sound.stage_path[1..4]) and a dynamic option list built from
-- sound.custom_file_names, both handled by createDropdownRow's getter/
-- function-options support above.
local function createSoundPathDropdownRow(canvas, previous, key, index, label, tooltip)
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

    local function options()
        local currentValue = getter()
        local prefix = (type(currentValue) == "string" and currentValue:match("^(.*[\\/])")) or SOUND_FOLDER_FALLBACK
        local fileNames = settings.Get("sound.custom_file_names")
        local list = {}
        if type(fileNames) == "table" then
            for _, fileName in ipairs(fileNames) do
                table.insert(list, { value = prefix .. fileName, label = fileName })
            end
        end
        return list
    end

    return createDropdownRow(canvas, previous, label, options, getter, setter, tooltip)
end

-- ---------------------------------------------------------------------------
-- Categories
-- ---------------------------------------------------------------------------

-- General was previously registered directly on the root category via
-- Blizzard's native Settings API, since the root page was otherwise empty.
-- Every category using RegisterProxySetting/CreateCheckbox/CreateDropdown/
-- CreateSlider came with Blizzard's own "Defaults" button on that category
-- (confirmed live: absent from Bar Colors/Advanced, which never used the
-- native API; present on Preydator/Bar Display/Sound & Alerts/Hunt Scanner,
-- which did). That button's "All Settings" choice resets every other
-- native-API category in the entire client -- Blizzard's own settings and
-- every other addon's, not just Preydator's -- which no addon can narrow or
-- opt out of. The only way to guarantee Blizzard's Defaults button can never
-- touch anything of ours is to never register anything through that system
-- at all -- including the root category object itself, which is why
-- initializeSettingsPanel below now creates it via
-- Settings.RegisterCanvasLayoutCategory (a real, separately-confirmed API,
-- the top-level equivalent of RegisterCanvasLayoutSubcategory) instead of
-- RegisterVerticalLayoutCategory. That still allows arbitrary canvas
-- content directly on the root frame, so General's checkboxes stay exactly
-- where they were -- no new tab, no extra click, unlike an earlier version
-- of this fix that moved General into its own subcategory before this API
-- was confirmed to exist.
local function buildGeneralSettings(canvas)
    local settings = getSettings()

    local function checkbox(previous, key, label, tooltip)
        return createCheckboxRow(canvas, previous, label,
            function() return settings.Get(key) end,
            function(value) settings.Set(key, value) end,
            tooltip)
    end

    local previous = checkbox(nil, "general.bar_enabled", L("Enable Bar"),
        L("Show the Prey Hunt progress bar."))
    previous = checkbox(previous, "general.sounds_enabled", L("Enable Sounds"),
        L("Master toggle for all Preydator sounds."))
    previous = checkbox(previous, "general.hunt_enabled", L("Enable Hunt Table Tracking"),
        L("Scan and track Hunt Table offers."))
    previous = checkbox(previous, "general.only_show_in_prey_zone", L("Only Show Bar in Prey Zone"),
        L("Hide the bar entirely outside the active hunt's zone."))
    previous = checkbox(previous, "general.disable_default_prey_icon", L("Hide Blizzard's Prey Icon"),
        L("Suppress the default Blizzard prey-hunt overlay icon."))
    previous = checkbox(previous, "general.debug_logging_enabled", L("Enable Debug Logging"),
        L("Verbose logging for troubleshooting."))
    previous = checkbox(previous, "general.lock_bar", L("Lock Bar"),
        L("Prevent dragging the bar."))
    checkbox(previous, "general.minimap_hidden", L("Hide Minimap Button"),
        L("Hide Preydator's minimap/Addon Compartment button."))
end

-- Converted from Blizzard's native Settings API to custom canvas (2026-09-08)
-- -- see buildGeneralSettings's comment above for why. 15 rows needs a
-- scroll frame (same pattern as Text & Labels) since it no longer fits the
-- visible canvas area unscrolled.
local function buildBarDisplayCategory(category)
    local canvas = CreateFrame("Frame")
    local subcategory = Settings.RegisterCanvasLayoutSubcategory(category, canvas, L("Bar Display"))
    local settings = getSettings()

    local scrollFrame = CreateFrame("ScrollFrame", nil, canvas, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", canvas, "TOPLEFT", 0, -8)
    scrollFrame:SetPoint("BOTTOMRIGHT", canvas, "BOTTOMRIGHT", -24, 4)

    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetSize(1, 1)
    scrollFrame:SetScrollChild(scrollChild)
    scrollFrame:SetScript("OnSizeChanged", function(_, width)
        scrollChild:SetWidth(width)
    end)

    local previous = createDropdownRow(scrollChild, nil, L("Orientation"), {
        { value = "horizontal", label = L("Horizontal") },
        { value = "vertical", label = L("Vertical") },
    }, function() return settings.Get("bar.orientation") end,
        function(value) settings.Set("bar.orientation", value) end,
        L("Horizontal or vertical bar layout."))

    previous = createDropdownRow(scrollChild, previous, L("Bar Texture"), {
        { value = "default", label = L("Default") },
        { value = "flat", label = L("Flat") },
        { value = "raid", label = L("Raid HP Fill") },
        { value = "classic", label = L("Classic Skill Bar") },
    }, function() return settings.Get("bar.texture_key") end,
        function(value) settings.Set("bar.texture_key", value) end,
        L("Fill texture preset."))

    -- Picking a theme bulk-applies Settings.ApplyBarAccessibilityTheme's six
    -- color fields, not just the enum value itself -- same as the native
    -- version's own special-cased setter.
    previous = createDropdownRow(scrollChild, previous, L("Accessibility Theme"), {
        { value = "default", label = L("Default") },
        { value = "deuteranopia", label = L("Deuteranopia") },
        { value = "protanopia", label = L("Protanopia") },
    }, function() return settings.Get("bar.accessibility_theme") end,
        function(value) settings.ApplyBarAccessibilityTheme(value) end,
        L("One-click colorblind-friendly color preset."))

    previous = createDropdownRow(scrollChild, previous, L("Percent Text Placement"), {
        { value = "inside", label = L("Inside Bar") },
        { value = "above_bar", label = L("Above Bar") },
        { value = "above_ticks", label = L("Above Ticks") },
        { value = "under_ticks", label = L("Under Ticks") },
        { value = "below_bar", label = L("Below Bar") },
        { value = "off", label = L("Off") },
    }, function() return settings.Get("bar.percent_display") end,
        function(value) settings.Set("bar.percent_display", value) end,
        L("Where the percent-complete text appears."))

    previous = createDropdownRow(scrollChild, previous, L("Progress Segments"), {
        { value = "quarters", label = L("Quarters (25/50/75/100)") },
        { value = "thirds", label = L("Thirds (33/66/100)") },
    }, function() return settings.Get("bar.progress_segments") end,
        function(value) settings.Set("bar.progress_segments", value) end,
        L("Tick/segment division used when Blizzard doesn't expose a precise percent."))

    previous = createDropdownRow(scrollChild, previous, L("Vertical Fill Direction"), {
        { value = "up", label = L("Up") },
        { value = "down", label = L("Down") },
    }, function() return settings.Get("bar.vertical_fill_direction") end,
        function(value) settings.Set("bar.vertical_fill_direction", value) end,
        L("Which way the bar fills in vertical orientation."))

    previous = createDropdownRow(scrollChild, previous, L("Vertical Text Side"), {
        { value = "left", label = L("Left") },
        { value = "right", label = L("Right") },
    }, function() return settings.Get("bar.vertical_text_side") end,
        function(value) settings.Set("bar.vertical_text_side", value) end,
        L("Which side of the bar the label text sits on in vertical orientation."))

    previous = createSliderRow(scrollChild, previous, L("Horizontal Scale"), 0.5, 2, 0.05,
        function() return settings.Get("bar.scale_horizontal") end,
        function(value) settings.Set("bar.scale_horizontal", value) end,
        L("Bar scale in horizontal orientation."))
    previous = createSliderRow(scrollChild, previous, L("Vertical Scale"), 0.5, 2, 0.05,
        function() return settings.Get("bar.scale_vertical") end,
        function(value) settings.Set("bar.scale_vertical", value) end,
        L("Bar scale in vertical orientation."))
    previous = createSliderRow(scrollChild, previous, L("Horizontal Width"), 100, 350, 1,
        function() return settings.Get("bar.width_horizontal") end,
        function(value) settings.Set("bar.width_horizontal", value) end,
        L("Bar width in horizontal orientation."))
    previous = createSliderRow(scrollChild, previous, L("Horizontal Height"), 10, 60, 1,
        function() return settings.Get("bar.height_horizontal") end,
        function(value) settings.Set("bar.height_horizontal", value) end,
        L("Bar height in horizontal orientation."))
    previous = createSliderRow(scrollChild, previous, L("Vertical Width"), 10, 60, 1,
        function() return settings.Get("bar.width_vertical") end,
        function(value) settings.Set("bar.width_vertical", value) end,
        L("Bar width in vertical orientation."))
    previous = createSliderRow(scrollChild, previous, L("Vertical Height"), 100, 350, 1,
        function() return settings.Get("bar.height_vertical") end,
        function(value) settings.Set("bar.height_vertical", value) end,
        L("Bar height in vertical orientation."))

    previous = createCheckboxRow(scrollChild, previous, L("Show Tick Marks"),
        function() return settings.Get("bar.show_ticks") end,
        function(value) settings.Set("bar.show_ticks", value) end,
        L("Show stage boundary tick marks on the bar."))
    createCheckboxRow(scrollChild, previous, L("Show During Edit Mode"),
        function() return settings.Get("bar.show_in_edit_mode") end,
        function(value) settings.Set("bar.show_in_edit_mode", value) end,
        L("Force the bar visible with placeholder text while Blizzard Edit Mode is open."))

    scrollChild:SetHeight(((scrollChild.rowCount or 1) * ROW_SPACING) + ROW_LEFT_MARGIN)

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

    local function refreshColorSwatches()
        for _, refresh in ipairs(canvas.colorSwatchRefreshers or {}) do
            refresh()
        end
    end

    -- Moved here from the separate "Bar Display" native category (2026-09-03,
    -- product owner) -- it only ever affects the Border Color swatch directly
    -- below, so it belongs with the colors, not off in another category.
    -- Triggers an immediate refresh on toggle (now that it's co-located,
    -- not just on the canvas's own OnShow) so the Border Color swatch's
    -- enabled/disabled look updates the instant you click the checkbox.
    local previous = createCheckboxRow(canvas, nil, L("Link Border Color to Fill Color"),
        function() return settings.Get("bar.border_color_linked") == true end,
        function(value)
            settings.Set("bar.border_color_linked", value)
            refreshColorSwatches()
        end)

    previous = createColorSwatchRow(canvas, previous, L("Fill Color"),
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

    -- Kept as a safety-net refresh (e.g. if the value ever changes via /pd
    -- or another path outside this checkbox) on top of the immediate
    -- refresh above.
    canvas:SetScript("OnShow", refreshColorSwatches)

    return subcategory
end

local function buildTextLabelsCategory(category)
    local canvas = CreateFrame("Frame")
    local subcategory = Settings.RegisterCanvasLayoutSubcategory(category, canvas, L("Text & Labels"))
    local settings = getSettings()

    -- Product owner's request (2026-09-03): a reset button directly in this
    -- category, not just the one already in Advanced (Section "Restore
    -- Default Names", still there, unchanged) -- reuses the same
    -- NAME_FIELD_KEYS/restoreDefaults this category's fields already share
    -- with that one. Placed above the scroll area, not stacked as a normal
    -- row, so it's always visible without scrolling.
    local resetButton = CreateFrame("Button", nil, canvas, "UIPanelButtonTemplate")
    resetButton:SetSize(180, 22)
    resetButton:SetPoint("TOPRIGHT", canvas, "TOPRIGHT", -8, -4)
    resetButton:SetText(L("Restore Default Names"))
    resetButton:SetScript("OnClick", function()
        restoreDefaults(NAME_FIELD_KEYS)
    end)

    local scrollFrame = CreateFrame("ScrollFrame", nil, canvas, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", canvas, "TOPLEFT", 0, -32)
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
        previous = createEditBoxPairRow(scrollChild, previous,
            L("Stage " .. stage .. " Prefix"),
            function() return getArrayValue("text.stage_prefix", stage) end,
            function(value) setArrayValue("text.stage_prefix", stage, value) end,
            L("Stage " .. stage .. " Label"),
            function() return getArrayValue("text.stage_suffix", stage) end,
            function(value) setArrayValue("text.stage_suffix", stage, value) end)
    end

    previous = createEditBoxPairRow(scrollChild, previous,
        L("Out of Zone Prefix"),
        function() return settings.Get("text.out_of_zone_prefix") end,
        function(value) settings.Set("text.out_of_zone_prefix", value) end,
        L("Out of Zone Label"),
        function() return settings.Get("text.out_of_zone_suffix") end,
        function(value) settings.Set("text.out_of_zone_suffix", value) end)
    previous = createEditBoxPairRow(scrollChild, previous,
        L("Ambush Prefix"),
        function() return settings.Get("text.ambush_prefix") end,
        function(value) settings.Set("text.ambush_prefix", value) end,
        L("Ambush Label (use {preyTargetName})"),
        function() return settings.Get("text.ambush_suffix_template") end,
        function(value) settings.Set("text.ambush_suffix_template", value) end)
    createEditBoxPairRow(scrollChild, previous,
        L("Pack Ambush Prefix"),
        function() return settings.Get("text.pack_ambush_prefix") end,
        function(value) settings.Set("text.pack_ambush_prefix", value) end,
        L("Pack Ambush Label (use {packAmbushSourceName})"),
        function() return settings.Get("text.pack_ambush_suffix_template") end,
        function(value) settings.Set("text.pack_ambush_suffix_template", value) end)

    scrollChild:SetHeight(((scrollChild.rowCount or 1) * ROW_SPACING) + ROW_LEFT_MARGIN)

    -- REVERTED 2026-09-04: canvas:SetScript("OnShow", refreshEditBoxValues)
    -- was tried here (matching Bar Colors' identical OnShow pattern for its
    -- color swatches) but made things worse, not better -- confirmed live
    -- that afterward NO box showed any text at all, not even after clicking
    -- Restore Default Names (which previously did work). Root cause not yet
    -- understood -- reverted rather than guess again on top of a regression.
    -- See Decisions Log item 65 for the real fix.

    return subcategory
end

-- Converted from Blizzard's native Settings API to custom canvas (2026-09-08)
-- -- see buildGeneralSettings's comment above. registerSoundPathDropdown's
-- array-index/dynamic-option-list behavior now lives in
-- createSoundPathDropdownRow (reuses createDropdownRow's function-options
-- support).
local function buildSoundCategory(category)
    local canvas = CreateFrame("Frame")
    local subcategory = Settings.RegisterCanvasLayoutSubcategory(category, canvas, L("Sound & Alerts"))
    local settings = getSettings()

    local scrollFrame = CreateFrame("ScrollFrame", nil, canvas, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", canvas, "TOPLEFT", 0, -8)
    scrollFrame:SetPoint("BOTTOMRIGHT", canvas, "BOTTOMRIGHT", -24, 4)

    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetSize(1, 1)
    scrollFrame:SetScrollChild(scrollChild)
    scrollFrame:SetScript("OnSizeChanged", function(_, width)
        scrollChild:SetWidth(width)
    end)

    local previous = createDropdownRow(scrollChild, nil, L("Sound Channel"), {
        { value = "Master", label = L("Master") },
        { value = "SFX", label = L("Sound Effects") },
        { value = "Dialog", label = L("Dialog") },
        { value = "Ambience", label = L("Ambience") },
        { value = "Music", label = L("Music") },
    }, function() return settings.Get("sound.channel") end,
        function(value) settings.Set("sound.channel", value) end,
        L("Which audio channel Preydator sounds play on."))

    for stage = 1, 4 do
        previous = createSoundPathDropdownRow(scrollChild, previous, "sound.stage_path", stage,
            L("Stage " .. stage .. " Sound"), L("Sound played on entering this stage."))
    end

    previous = createCheckboxRow(scrollChild, previous, L("Enable Ambush Sound"),
        function() return settings.Get("sound.ambush_enabled") end,
        function(value) settings.Set("sound.ambush_enabled", value) end,
        L("Play a sound when an ambush is detected."))
    previous = createSoundPathDropdownRow(scrollChild, previous, "sound.ambush_path", nil,
        L("Ambush Sound"), L("Sound played on ambush."))
    previous = createSliderRow(scrollChild, previous, L("Alert Cooldown"), 0, 300, 5,
        function() return settings.Get("sound.alert_cooldown_seconds") end,
        function(value) settings.Set("sound.alert_cooldown_seconds", value) end,
        L("Minimum time between ambush/Pack Ambush/Exploding Corpse Snakes alert sounds, so a "
            .. "fast kill doesn't replay a sound awkwardly close together."))

    previous = createCheckboxRow(scrollChild, previous, L("Enable Pack Ambush Sound"),
        function() return settings.Get("sound.pack_ambush_enabled") end,
        function(value) settings.Set("sound.pack_ambush_enabled", value) end,
        L("Play a sound when a Pack Scout or Pack Hunter appears (Season 2's Pack Ambush mechanic)."))
    previous = createSoundPathDropdownRow(scrollChild, previous, "sound.pack_ambush_path", nil,
        L("Pack Ambush Sound"), L("Sound played when Pack Ambush's mobs appear."))

    previous = createCheckboxRow(scrollChild, previous, L("Enable Exploding Corpse Snakes Sound"),
        function() return settings.Get("sound.exploding_corpse_snakes_enabled") end,
        function(value) settings.Set("sound.exploding_corpse_snakes_enabled", value) end,
        L("Play a sound when a Venom-Bloated Python appears (Season 2's Exploding Corpse Snakes mechanic)."))
    previous = createSoundPathDropdownRow(scrollChild, previous, "sound.exploding_corpse_snakes_path", nil,
        L("Exploding Corpse Snakes Sound"), L("Sound played when a Venom-Bloated Python appears."))

    previous = createCheckboxRow(scrollChild, previous, L("Amplify Alert Sounds"),
        function() return settings.Get("sound.amplify_enabled") end,
        function(value) settings.Set("sound.amplify_enabled", value) end,
        L("Briefly mute ambience/music and boost SFX+Master volume while a Preydator alert plays, "
            .. "so it cuts through other game audio (modeled on the Better Fishing addon's "
            .. "\"Enhance Sounds\" feature). Your normal volume mix is restored right after."))
    createSliderRow(scrollChild, previous, L("Amplify Volume"), 0, 1, 0.05,
        function() return settings.Get("sound.amplify_scale") end,
        function(value) settings.Set("sound.amplify_scale", value) end,
        L("How much to boost your current SFX/Master volume while an alert plays, on top of "
            .. "wherever it's already set (WoW's volume can't exceed 1, so once you're already "
            .. "at max there's nothing left to add -- the ambience/music muting is what still "
            .. "helps at that point). 1 always plays alerts at full volume."))

    scrollChild:SetHeight(((scrollChild.rowCount or 1) * ROW_SPACING) + ROW_LEFT_MARGIN)

    return subcategory
end

-- Converted from Blizzard's native Settings API to custom canvas (2026-09-08)
-- -- see buildGeneralSettings's comment above.
local function buildHuntScannerCategory(category)
    local canvas = CreateFrame("Frame")
    local subcategory = Settings.RegisterCanvasLayoutSubcategory(category, canvas, L("Hunt Scanner"))
    local settings = getSettings()

    local scrollFrame = CreateFrame("ScrollFrame", nil, canvas, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", canvas, "TOPLEFT", 0, -8)
    scrollFrame:SetPoint("BOTTOMRIGHT", canvas, "BOTTOMRIGHT", -24, 4)

    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetSize(1, 1)
    scrollFrame:SetScrollChild(scrollChild)
    scrollFrame:SetScript("OnSizeChanged", function(_, width)
        scrollChild:SetWidth(width)
    end)

    local previous = createCheckboxRow(scrollChild, nil, L("Enable Hunt Table Panel"),
        function() return settings.Get("hunt.enabled") end,
        function(value) settings.Set("hunt.enabled", value) end,
        L("Track and list Hunt Table offers."))

    previous = createDropdownRow(scrollChild, previous, L("Panel Side"), {
        { value = "left", label = L("Left") },
        { value = "right", label = L("Right") },
    }, function() return settings.Get("hunt.panel_side") end,
        function(value) settings.Set("hunt.panel_side", value) end,
        L("Which side of the screen the hunt list anchors to."))

    previous = createDropdownRow(scrollChild, previous, L("Group By"), {
        { value = "none", label = L("None") },
        { value = "difficulty", label = L("Difficulty") },
        { value = "zone", label = L("Zone") },
    }, function() return settings.Get("hunt.group_by") end,
        function(value) settings.Set("hunt.group_by", value) end,
        L("How hunts are grouped in the list."))

    previous = createDropdownRow(scrollChild, previous, L("Sort By"), {
        { value = "difficulty", label = L("Difficulty") },
        { value = "zone", label = L("Zone") },
        { value = "title", label = L("Title") },
    }, function() return settings.Get("hunt.sort_by") end,
        function(value) settings.Set("hunt.sort_by", value) end,
        L("Primary sort field for the hunt list."))

    previous = createDropdownRow(scrollChild, previous, L("Sort Direction"), {
        { value = "asc", label = L("Ascending") },
        { value = "desc", label = L("Descending") },
    }, function() return settings.Get("hunt.sort_direction") end,
        function(value) settings.Set("hunt.sort_direction", value) end,
        L("Ascending or descending sort order."))

    previous = createDropdownRow(scrollChild, previous, L("Reward Display Style"), {
        { value = "icon_inline", label = L("Icons Inline") },
        { value = "icon_count", label = L("Icon + Count") },
    }, function() return settings.Get("hunt.reward_display_style") end,
        function(value) settings.Set("hunt.reward_display_style", value) end,
        L("How quest rewards are shown per hunt row."))

    previous = createDropdownRow(scrollChild, previous, L("Difficulty Icon Set"), {
        { value = "default", label = L("Default") },
    }, function() return settings.Get("hunt.difficulty_icon_set") end,
        function(value) settings.Set("hunt.difficulty_icon_set", value) end,
        L("Which bundled icon set to use for difficulty badges."))

    previous = createCheckboxRow(scrollChild, previous, L("Show Achievement Badges"),
        function() return settings.Get("hunt.achievement_signals_enabled") end,
        function(value) settings.Set("hunt.achievement_signals_enabled", value) end,
        L("Show a badge on each hunt row for still-needed Prey achievements, with a hover "
            .. "tooltip listing which ones."))

    -- Width floor raised 200->330 (2026-09-03, product owner confirmed live
    -- overlap, then tuned the floor twice after eyeballing it in-game: an
    -- initial 420 from theoretical worst-case math, down to 270, settled at
    -- 330). Default kept at the addon's original 336 (comfortably above this
    -- floor). See HuntTablePanel.lua's Render() for the matching
    -- render-time floor that also protects anyone with an already-saved
    -- smaller value.
    previous = createSliderRow(scrollChild, previous, L("Panel Width"), 330, 600, 1,
        function() return settings.Get("hunt.width") end,
        function(value) settings.Set("hunt.width", value) end,
        L("Hunt Table panel width."))
    -- Height floor raised 200->250 so at least ~3 real hunt rows plus the
    -- header/group controls stay visible -- not an overlap risk like width,
    -- just a usability floor against an unreadably short panel.
    previous = createSliderRow(scrollChild, previous, L("Panel Height"), 250, 800, 1,
        function() return settings.Get("hunt.height") end,
        function(value) settings.Set("hunt.height", value) end,
        L("Hunt Table panel height."))
    previous = createSliderRow(scrollChild, previous, L("Panel Scale"), 0.5, 2, 0.05,
        function() return settings.Get("hunt.scale") end,
        function(value) settings.Set("hunt.scale", value) end,
        L("Hunt Table panel scale."))
    previous = createSliderRow(scrollChild, previous, L("Font Size"), 8, 24, 1,
        function() return settings.Get("hunt.font_size") end,
        function(value) settings.Set("hunt.font_size", value) end,
        L("Hunt Table panel font size."))

    createCheckboxRow(scrollChild, previous, L("Preview Hunt Panel"),
        function() return settings.Get("hunt.preview_enabled") end,
        function(value) settings.Set("hunt.preview_enabled", value) end,
        L("Force-show the hunt panel while adjusting the settings above, using your "
            .. "current hunts if any are cached or placeholder rows otherwise -- so "
            .. "layout changes are visible without leaving Settings."))

    scrollChild:SetHeight(((scrollChild.rowCount or 1) * ROW_SPACING) + ROW_LEFT_MARGIN)

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

-- Wrapped in a scroll frame (2026-09-08) -- eight compact rows plus the
-- custom-sound-file block below no longer fit the visible canvas area
-- unscrolled (confirmed live: content ran off the bottom of the panel with
-- no way to reach it), same fix already applied to Bar Display/Sound &
-- Alerts/Hunt Scanner above and to Text & Labels previously.
local function buildAdvancedCategory(category)
    local canvas = CreateFrame("Frame")
    local subcategory = Settings.RegisterCanvasLayoutSubcategory(category, canvas, L("Advanced"))
    local settings = getSettings()

    local scrollFrame = CreateFrame("ScrollFrame", nil, canvas, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", canvas, "TOPLEFT", 0, -8)
    scrollFrame:SetPoint("BOTTOMRIGHT", canvas, "BOTTOMRIGHT", -24, 4)

    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetSize(1, 1)
    scrollFrame:SetScrollChild(scrollChild)
    scrollFrame:SetScript("OnSizeChanged", function(_, width)
        scrollChild:SetWidth(width)
    end)

    -- debug.enable_tracing gates the zone/icon/sound diagnostic traces (/pd
    -- zinspect, /pd iinspect, /pd sinspect) -- added 2026-09-07 (Decisions
    -- Log item 85) after those three previously recorded unconditionally for
    -- every player; product owner asked that no diagnostic tracing run at
    -- all without explicit opt-in. Kept as its own row, separate from
    -- pack_ambush_verbose below (which already had its own opt-in gate and
    -- didn't need to change) -- one flips on the nameplate trace specifically,
    -- this one flips on the other three together.
    local previous = createCheckboxRow(scrollChild, nil,
        L("Enable Diagnostic Tracing (see /pd zinspect, /pd iinspect, /pd sinspect)"),
        function() return settings.Get("debug.enable_tracing") == true end,
        function(value) settings.Set("debug.enable_tracing", value) end)

    previous = createCheckboxRow(scrollChild, previous, L("Record Nameplates Seen During Hunts (see /pd ninspect)"),
        function() return settings.Get("debug.pack_ambush_verbose") == true end,
        function(value) settings.Set("debug.pack_ambush_verbose", value) end)

    previous = createButtonRow(scrollChild, previous, L("Reset Bar Position"), function()
        local barFrame = Preydator:GetModule("BarFrame")
        if barFrame then
            barFrame.ResetPosition()
        end
    end)

    previous = createButtonRow(scrollChild, previous, L("Refresh Hunt Cache"), function()
        local huntScanner = Preydator:GetModule("HuntScannerRuntime")
        if huntScanner then
            huntScanner.RefreshFromAdapter()
        end
    end)

    previous = createButtonRow(scrollChild, previous, L("Restore Default Names"), function()
        restoreDefaults(NAME_FIELD_KEYS)
    end)

    previous = createButtonRow(scrollChild, previous, L("Restore Default Sounds"), function()
        restoreDefaults(SOUND_FIELD_KEYS)
    end)

    previous = createButtonRow(scrollChild, previous, L("Reset All Settings"), function()
        ensureResetConfirmFrame():Show()
    end)

    previous = createButtonRow(scrollChild, previous, L("Show What's New"), function()
        local splash = Preydator:GetModule("Splash")
        if splash then
            splash.Show(true)
        end
    end)

    -- Custom sound files: registers a filename in sound.custom_file_names so
    -- it appears in every sound-path dropdown (Sound & Alerts category) --
    -- the .ogg file itself must already exist in
    -- Interface/AddOns/Preydator/sounds/, this only adds/removes the addon's
    -- own record of it. Ported UI for the old codebase's Add File/Remove
    -- File flow (Modules/Settings.lua:2435-2468, product owner's own
    -- reference pointer, 2026-09-03) -- the normalize/validate/protected-
    -- filename logic lives in SoundsRuntime.AddCustomSoundFile/
    -- RemoveCustomSoundFile so this stays a thin UI caller, per this file's
    -- own "Settings.Set only, never business logic" header rule.
    local soundFileTitle = scrollChild:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    soundFileTitle:SetText(L("Custom Sound File"))
    anchorRowTop(soundFileTitle, previous, scrollChild, COMPACT_ROW_SPACING)

    local soundFileEditBox = CreateFrame("EditBox", nil, scrollChild, "InputBoxTemplate")
    soundFileEditBox:SetSize(220, 20)
    soundFileEditBox:SetAutoFocus(false)
    soundFileEditBox:SetPoint("TOPLEFT", soundFileTitle, "BOTTOMLEFT", CONTROL_INDENT + 6, CONTROL_OFFSET)
    soundFileEditBox:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
    end)

    -- Status line instead of a popup/dialog -- same low-friction feedback
    -- style as this category's other action buttons, no extra click to
    -- dismiss anything.
    local soundFileStatus = scrollChild:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    soundFileStatus:SetPoint("TOPLEFT", soundFileEditBox, "BOTTOMLEFT", 0, -4)
    soundFileStatus:SetJustifyH("LEFT")

    local addFileButton = CreateFrame("Button", nil, scrollChild, "UIPanelButtonTemplate")
    addFileButton:SetSize(105, 22)
    addFileButton:SetPoint("TOPLEFT", soundFileStatus, "BOTTOMLEFT", 0, -4)
    addFileButton:SetText(L("Add File"))

    local removeFileButton = CreateFrame("Button", nil, scrollChild, "UIPanelButtonTemplate")
    removeFileButton:SetSize(105, 22)
    removeFileButton:SetPoint("LEFT", addFileButton, "RIGHT", 4, 0)
    removeFileButton:SetText(L("Remove File"))

    local function setSoundFileStatus(ok, message)
        soundFileStatus:SetText(message or "")
        if ok then
            soundFileStatus:SetTextColor(0.4, 1, 0.4)
        else
            soundFileStatus:SetTextColor(1, 0.4, 0.4)
        end
    end

    addFileButton:SetScript("OnClick", function()
        local soundsRuntime = Preydator:GetModule("SoundsRuntime")
        if not soundsRuntime or type(soundsRuntime.AddCustomSoundFile) ~= "function" then
            setSoundFileStatus(false, L("Sound system unavailable"))
            return
        end
        local ok, message = soundsRuntime.AddCustomSoundFile(soundFileEditBox:GetText())
        setSoundFileStatus(ok, message)
        if ok then
            soundFileEditBox:SetText("")
        end
    end)

    removeFileButton:SetScript("OnClick", function()
        local soundsRuntime = Preydator:GetModule("SoundsRuntime")
        if not soundsRuntime or type(soundsRuntime.RemoveCustomSoundFile) ~= "function" then
            setSoundFileStatus(false, L("Sound system unavailable"))
            return
        end
        local ok, message = soundsRuntime.RemoveCustomSoundFile(soundFileEditBox:GetText())
        setSoundFileStatus(ok, message)
        if ok then
            soundFileEditBox:SetText("")
        end
    end)

    -- rowCount only tracks anchorRowTop calls (9: the 2 checkboxes, 6
    -- buttons, and the sound-file title) -- the editbox/status/Add-Remove
    -- buttons stacked below that title are anchored directly off it, not
    -- via anchorRowTop, so they'd otherwise be cut out of the scroll
    -- extent. The flat +90 covers that trailing block with room to spare.
    scrollChild:SetHeight(((scrollChild.rowCount or 1) * COMPACT_ROW_SPACING) + ROW_LEFT_MARGIN + 90)

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
    if not (Settings and Settings.RegisterCanvasLayoutCategory) then
        return
    end

    -- Root category is canvas-backed, not Settings.RegisterVerticalLayout-
    -- Category (2026-09-08) -- see buildGeneralSettings' comment above. This
    -- is the only reason General's checkboxes can still live directly on
    -- the root page with no extra tab: RegisterCanvasLayoutCategory permits
    -- arbitrary canvas content straight on a top-level category, same as
    -- RegisterCanvasLayoutSubcategory does one level down.
    local rootCanvas = CreateFrame("Frame")
    local category = Settings.RegisterCanvasLayoutCategory(rootCanvas, L("Preydator"))

    buildGeneralSettings(rootCanvas)
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
