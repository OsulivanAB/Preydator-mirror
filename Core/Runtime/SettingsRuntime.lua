-- Preydator :: Core/Runtime/SettingsRuntime.lua
-- Author: RagingAltoholic
-- Responsibility: validation/normalization logic for settings fields (enum
-- checks, color clamping, numeric range clamps) and the legacy-schema-to-V1
-- migration step. Called exclusively by SettingsStore.lua -- the one place
-- this logic exists, replacing the old duplicate-fallback-copy pattern.
-- Reads: nothing external.
-- Writes: nothing (returns new/validated tables; never mutates SavedVariables
-- directly -- that stays SettingsStore's job).

local Preydator = _G.Preydator

local SettingsRuntime = {}

-- ---------------------------------------------------------------------------
-- NormalizeAll: field-by-field clamps/enum checks against Section 5's catalog.
-- Only fields with a documented range/enum are validated here; anything else
-- passes through untouched (Settings.Set()'s own type guard covers the rest).
-- ---------------------------------------------------------------------------

local function clampNumber(value, minValue, maxValue)
    if type(value) ~= "number" then
        return nil
    end
    if value < minValue then return minValue end
    if value > maxValue then return maxValue end
    return value
end

local function clampColor(value)
    if type(value) ~= "table" then
        return nil
    end
    local out = {}
    for i = 1, 4 do
        local channel = tonumber(value[i])
        out[i] = channel and clampNumber(channel, 0, 1) or (i == 4 and 1 or 0)
    end
    return out
end

local function validEnum(value, allowed)
    if type(value) ~= "string" then
        return nil
    end
    for _, candidate in ipairs(allowed) do
        if candidate == value then
            return value
        end
    end
    return nil
end

local NUMERIC_RANGES = {
    { path = { "bar", "scale_horizontal" }, min = 0.5, max = 2 },
    { path = { "bar", "scale_vertical" }, min = 0.5, max = 2 },
    { path = { "bar", "width_horizontal" }, min = 100, max = 350 },
    { path = { "bar", "height_horizontal" }, min = 10, max = 60 },
    { path = { "bar", "width_vertical" }, min = 10, max = 60 },
    { path = { "bar", "height_vertical" }, min = 100, max = 350 },
    { path = { "text", "font_size" }, min = 8, max = 24 },
    { path = { "sound", "alert_cooldown_seconds" }, min = 0, max = 300 },
}

local COLOR_FIELDS = {
    { "bar", "fill_color" }, { "bar", "border_color" }, { "bar", "title_color" },
    { "bar", "percent_color" }, { "bar", "tick_color" }, { "bar", "bg_color" },
}

local ENUM_FIELDS = {
    { path = { "bar", "orientation" }, allowed = { "horizontal", "vertical" } },
    { path = { "bar", "accessibility_theme" }, allowed = { "default", "deuteranopia", "protanopia" } },
    { path = { "bar", "percent_display" }, allowed = {
        "inside", "above_bar", "above_ticks", "under_ticks", "below_bar", "off",
    } },
    { path = { "bar", "progress_segments" }, allowed = { "quarters", "thirds" } },
    { path = { "bar", "vertical_fill_direction" }, allowed = { "up", "down" } },
    { path = { "bar", "vertical_text_side" }, allowed = { "left", "right" } },
    { path = { "sound", "channel" }, allowed = { "Master", "SFX", "Dialog", "Ambience", "Music" } },
    { path = { "hunt", "panel_side" }, allowed = { "left", "right" } },
    { path = { "hunt", "group_by" }, allowed = { "none", "difficulty", "zone" } },
    { path = { "hunt", "sort_by" }, allowed = { "difficulty", "zone", "title" } },
    { path = { "hunt", "sort_direction" }, allowed = { "asc", "desc" } },
    { path = { "hunt", "reward_display_style" }, allowed = { "icon_inline", "icon_count", "text_only" } },
    { path = { "hunt", "achievement_signal_style" }, allowed = { "icon_count" } },
    { path = { "text", "label_row_position" }, allowed = { "above", "below" } },
}

local function getPath(root, path)
    local node = root
    for _, key in ipairs(path) do
        if type(node) ~= "table" then return nil end
        node = node[key]
    end
    return node
end

local function setPath(root, path, value)
    local node = root
    for i = 1, #path - 1 do
        local key = path[i]
        if type(node[key]) ~= "table" then
            node[key] = {}
        end
        node = node[key]
    end
    node[path[#path]] = value
end

-- Normalizes settings in place against defaults: out-of-range/invalid fields
-- fall back to the matching field in `defaults` individually (Section 11:
-- corrupted settings fall back to defaults field by field, not as a whole).
function SettingsRuntime.NormalizeAll(rawSettings, defaults)
    if type(rawSettings) ~= "table" then
        return rawSettings
    end
    defaults = type(defaults) == "table" and defaults or {}

    for _, rule in ipairs(NUMERIC_RANGES) do
        local value = getPath(rawSettings, rule.path)
        local clamped = clampNumber(value, rule.min, rule.max)
        setPath(rawSettings, rule.path, clamped or getPath(defaults, rule.path))
    end

    for _, path in ipairs(COLOR_FIELDS) do
        local value = getPath(rawSettings, path)
        local clamped = clampColor(value)
        setPath(rawSettings, path, clamped or getPath(defaults, path))
    end

    for _, rule in ipairs(ENUM_FIELDS) do
        local value = getPath(rawSettings, rule.path)
        local validated = validEnum(value, rule.allowed)
        setPath(rawSettings, rule.path, validated or getPath(defaults, rule.path))
    end

    return rawSettings
end

-- ---------------------------------------------------------------------------
-- MigrateAll: legacy (pre-rewrite, flat/unversioned) PreydatorDB shape -> the
-- new nested dotted-category schema (schema_version 1). Runs once per profile
-- load, via SettingsStore.RunMigrations. Deliberately does NOT import fields
-- identified as dead/legacy in the architecture doc's Section 18: the
-- duplicate width/height mirrors, tickLayerMode, showAlignmentDot,
-- huntScannerDifficultyColors (replaced by an icon set), soundEnhance,
-- silenceArator, randomHuntCosts, customizationV2, or the bar's saved
-- position/point (not yet part of the Section 5 settings catalog).
-- ---------------------------------------------------------------------------

-- old flat key -> new dotted path. Values copied as-is (type-checked later by
-- SettingsStore's field-by-field default overlay).
local SIMPLE_KEY_MIGRATIONS = {
    locked = { "general", "lock_bar" },
    onlyShowInPreyZone = { "general", "only_show_in_prey_zone" },
    disableDefaultPreyIcon = { "general", "disable_default_prey_icon" },
    soundsEnabled = { "general", "sounds_enabled" },
    showInEditMode = { "bar", "show_in_edit_mode" },
    orientation = { "bar", "orientation" },
    textureKey = { "bar", "texture_key" },
    scale = { "bar", "scale_horizontal" },
    verticalScale = { "bar", "scale_vertical" },
    horizontalWidth = { "bar", "width_horizontal" },
    horizontalHeight = { "bar", "height_horizontal" },
    verticalWidth = { "bar", "width_vertical" },
    verticalHeight = { "bar", "height_vertical" },
    fillColor = { "bar", "fill_color" },
    bgColor = { "bar", "bg_color" },
    titleColor = { "bar", "title_color" },
    percentColor = { "bar", "percent_color" },
    tickColor = { "bar", "tick_color" },
    borderColor = { "bar", "border_color" },
    borderColorLinked = { "bar", "border_color_linked" },
    showTicks = { "bar", "show_ticks" },
    showSparkLine = { "bar", "show_spark_line" },
    percentDisplay = { "bar", "percent_display" },
    progressSegments = { "bar", "progress_segments" },
    verticalFillDirection = { "bar", "vertical_fill_direction" },
    verticalTextSide = { "bar", "vertical_text_side" },
    titleFontKey = { "text", "title_font_key" },
    percentFontKey = { "text", "percent_font_key" },
    fontSize = { "text", "font_size" },
    outOfZonePrefix = { "text", "out_of_zone_prefix" },
    outOfZoneLabel = { "text", "out_of_zone_suffix" },
    ambushPrefix = { "text", "ambush_prefix" },
    bloodyCommandPrefix = { "text", "bloody_command_prefix" },
    stageLabelMode = { "text", "stage_label_mode" },
    labelRowPosition = { "text", "label_row_position" },
    soundChannel = { "sound", "channel" },
    ambushSoundEnabled = { "sound", "ambush_enabled" },
    ambushSoundPath = { "sound", "ambush_path" },
    bloodyCommandSoundEnabled = { "sound", "bloody_command_enabled" },
    bloodyCommandSoundPath = { "sound", "bloody_command_path" },
    echoOfPredationSoundPath = { "sound", "echo_of_predation_path" },
    soundFileNames = { "sound", "custom_file_names" },
    huntScannerEnabled = { "hunt", "enabled" },
    huntScannerSide = { "hunt", "panel_side" },
    huntScannerGroupBy = { "hunt", "group_by" },
    huntScannerSortBy = { "hunt", "sort_by" },
    huntScannerSortDir = { "hunt", "sort_direction" },
    huntScannerWidth = { "hunt", "width" },
    huntScannerHeight = { "hunt", "height" },
    huntScannerFontSize = { "hunt", "font_size" },
    huntScannerScale = { "hunt", "scale" },
    huntScannerAchievementSignals = { "hunt", "achievement_signals_enabled" },
    huntScannerAchievementSignalStyle = { "hunt", "achievement_signal_style" },
    huntScannerTheme = { "hunt", "theme" },
    debugBloodyCommand = { "debug", "bloody_command_verbose" },
}

local function wrapToken(value, bareToken, token)
    if value == bareToken then
        return token
    end
    return value
end

function SettingsRuntime.MigrateAll(rawTable)
    if type(rawTable) ~= "table" then
        return rawTable
    end

    -- Already-migrated data has nested category tables; nothing to do.
    if type(rawTable.general) == "table" or type(rawTable.bar) == "table" then
        return rawTable
    end

    local migrated = {}

    for oldKey, newPath in pairs(SIMPLE_KEY_MIGRATIONS) do
        if rawTable[oldKey] ~= nil then
            setPath(migrated, newPath, rawTable[oldKey])
        end
    end

    -- The old schema's `stageLabels` (suffix) vs `stageSuffixLabels` (prefix)
    -- naming was inverted relative to what they actually rendered as (a real
    -- bug in the old UI, not a design choice) -- migrate accordingly.
    if type(rawTable.stageLabels) == "table" then
        setPath(migrated, { "text", "stage_suffix" }, rawTable.stageLabels)
    end
    if type(rawTable.stageSuffixLabels) == "table" then
        setPath(migrated, { "text", "stage_prefix" }, rawTable.stageSuffixLabels)
    end

    if rawTable.ambushSuffix ~= nil then
        setPath(migrated, { "text", "ambush_suffix_template" },
            wrapToken(rawTable.ambushSuffix, "preyTargetName", "{preyTargetName}"))
    end
    if rawTable.bloodyCommandSuffix ~= nil then
        setPath(migrated, { "text", "bloody_command_suffix_template" },
            wrapToken(rawTable.bloodyCommandSuffix, "bloodyCommandSourceName", "{bloodyCommandSourceName}"))
    end

    if type(rawTable.stageSounds) == "table" then
        setPath(migrated, { "sound", "stage_path" }, rawTable.stageSounds)
    end

    if rawTable.huntScannerRewardStyle ~= nil then
        local style = rawTable.huntScannerRewardStyle
        if style == "icon_text" then
            style = "icon_inline"
        end
        setPath(migrated, { "hunt", "reward_display_style" }, style)
    end

    return migrated
end

Preydator:RegisterModule("SettingsRuntime", SettingsRuntime)
return SettingsRuntime
