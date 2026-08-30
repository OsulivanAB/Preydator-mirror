-- Preydator :: Core/Adapters/SettingsStore.lua
-- Author: RagingAltoholic
-- Responsibility: SavedVariables (PreydatorDB) read/write, profile management
-- (create/switch/copy/delete), the default-settings catalog (Section 5 of the
-- architecture doc), and the versioned migration pipeline entry point. Nothing
-- outside this file touches _G.PreydatorDB directly.
-- Reads: _G.PreydatorDB.
-- Writes: _G.PreydatorDB.

local Preydator = _G.Preydator

local SettingsStore = {}

local SCHEMA_VERSION = 1

-- Fields whose defaults live in this file but are localized lazily (built the
-- first time defaults are requested, by which point LocalizationAdapter is
-- guaranteed to be registered regardless of file load order within Adapters/).
local LOCALIZED_STRING_DEFAULTS = {
    { path = { "text", "out_of_zone_suffix" }, key = "No Sign in These Fields" },
    { path = { "text", "ambush_prefix" }, key = "AMBUSH: " },
    { path = { "text", "bloody_command_prefix" }, key = "Bloody Command: " },
}

local LOCALIZED_STAGE_SUFFIX_KEYS = {
    "Scent in the Wind",
    "Blood in the Shadows",
    "Echoes of the Kill",
    "Feast of the Fang",
}

local SOUND_FOLDER_PREFIX = "Interface\\AddOns\\Preydator\\sounds\\"

local PROTECTED_SOUND_FILENAMES = {
    "predator-alert.ogg",
    "predator-ambush.ogg",
    "predator-snarl-01.ogg",
    "predator-torment.ogg",
    "predator-kill.ogg",
    "well-we-ve-prepared-a-trap-for-this-predator.ogg",
    "predator-kills-its-prey-to-survive.ogg",
    "echo-of-predation.ogg",
}

-- Dotted keys whose value is a user-growable container (a plain list or a name
-- -> value map) rather than a fixed-shape struct. These are copied wholesale
-- from saved data instead of merged field-by-field against the default shape.
local GROWABLE_LIST_FIELDS = {
    ["sound.custom_file_names"] = true,
    ["theme.custom_themes"] = true,
}

local function deepCopy(value)
    if type(value) ~= "table" then
        return value
    end
    local out = {}
    for key, v in pairs(value) do
        out[key] = deepCopy(v)
    end
    return out
end

local function buildRawDefaults()
    return {
        general = {
            bar_enabled = true,
            sounds_enabled = true,
            hunt_enabled = true,
            debug_logging_enabled = false,
            lock_bar = false,
            only_show_in_prey_zone = false,
            disable_default_prey_icon = false,
            schema_version = SCHEMA_VERSION,
        },
        bar = {
            orientation = "horizontal",
            texture_key = "default",
            scale_horizontal = 1.0,
            scale_vertical = 0.9,
            width_horizontal = 160,
            height_horizontal = 30,
            width_vertical = 40,
            height_vertical = 160,
            fill_color = { 0.85, 0.2, 0.2, 0.95 },
            border_color = { 0.8, 0.2, 0.2, 0.85 },
            title_color = { 1, 0.82, 0, 1 },
            percent_color = { 1, 1, 1, 1 },
            tick_color = { 1, 1, 1, 0.35 },
            bg_color = { 0, 0, 0, 0.6 },
            border_color_linked = true,
            accessibility_theme = "default",
            show_ticks = true,
            show_spark_line = false,
            percent_display = "inside",
            progress_segments = "quarters",
            vertical_fill_direction = "up",
            vertical_text_side = "right",
            show_in_edit_mode = true,
        },
        text = {
            title_font_key = "frizqt",
            percent_font_key = "frizqt",
            font_size = 12,
            stage_prefix = { "", "", "", "" },
            stage_suffix = { "", "", "", "" }, -- filled in by applyLocalizedDefaults
            out_of_zone_prefix = "",
            out_of_zone_suffix = "", -- filled in by applyLocalizedDefaults
            ambush_prefix = "", -- filled in by applyLocalizedDefaults
            ambush_suffix_template = "{preyTargetName}",
            bloody_command_prefix = "", -- filled in by applyLocalizedDefaults
            bloody_command_suffix_template = "{bloodyCommandSourceName}",
            stage_label_mode = "center",
            label_row_position = "above",
        },
        progress = {
            -- progress.segment_mode is an alias of bar.progress_segments (Section
            -- 5.4) and is resolved in Core/Settings.lua -- not stored twice here.
            fallback_mode = "stage",
        },
        sound = {
            channel = "Master",
            stage_path = {
                SOUND_FOLDER_PREFIX .. "predator-ambush.ogg",
                SOUND_FOLDER_PREFIX .. "predator-snarl-01.ogg",
                SOUND_FOLDER_PREFIX .. "predator-torment.ogg",
                SOUND_FOLDER_PREFIX .. "predator-kill.ogg",
            },
            ambush_enabled = true,
            ambush_path = SOUND_FOLDER_PREFIX .. "well-we-ve-prepared-a-trap-for-this-predator.ogg",
            -- Bloody Command (Astalor Bloodsworn) and Echo of Predation were Season 1
            -- mechanics; patch 12.1 discontinued them. Left dormant rather than removed
            -- (2026-08-25 decision, see architecture doc Section 19) -- default off so a
            -- future settings UI doesn't present a toggle for something that can't fire.
            bloody_command_enabled = false,
            bloody_command_path = SOUND_FOLDER_PREFIX .. "predator-kills-its-prey-to-survive.ogg",
            echo_of_predation_path = SOUND_FOLDER_PREFIX .. "echo-of-predation.ogg",
            custom_file_names = deepCopy(PROTECTED_SOUND_FILENAMES),
            alert_cooldown_seconds = 30,
        },
        hunt = {
            enabled = true,
            panel_side = "right",
            group_by = "difficulty",
            sort_by = "zone",
            sort_direction = "asc",
            reward_display_style = "icon_inline",
            width = 336,
            height = 460,
            scale = 1.0,
            font_size = 12,
            difficulty_icon_set = "default",
            achievement_signals_enabled = true,
            achievement_signal_style = "icon_count",
            theme = "brown",
        },
        theme = {
            enabled = false,
            global_key = "brown",
            use_class_colors = true,
            custom_themes = {},
        },
        debug = {
            -- debug.logging_enabled aliases general.debug_logging_enabled
            -- (Section 5.8) and is resolved in Core/Settings.lua.
            bloody_command_verbose = false,
        },
    }
end

local function setPath(root, path, value)
    local node = root
    for i = 1, #path - 1 do
        node = node[path[i]]
    end
    node[path[#path]] = value
end

local function applyLocalizedDefaults(defaults)
    local localization = Preydator:GetModule("LocalizationAdapter")
    local L = localization and localization.L

    local function localize(key)
        if type(L) == "function" then
            return L(key)
        end
        return key
    end

    for _, entry in ipairs(LOCALIZED_STRING_DEFAULTS) do
        setPath(defaults, entry.path, localize(entry.key))
    end

    for i, key in ipairs(LOCALIZED_STAGE_SUFFIX_KEYS) do
        defaults.text.stage_suffix[i] = localize(key)
    end
end

local builtDefaultsCache = nil

local function getDefaultsInternal()
    if not builtDefaultsCache then
        local defaults = buildRawDefaults()
        applyLocalizedDefaults(defaults)
        builtDefaultsCache = defaults
    end
    return deepCopy(builtDefaultsCache)
end

function SettingsStore.GetDefaults()
    return getDefaultsInternal()
end

-- ---------------------------------------------------------------------------
-- Profile management (folded in from the old ProfileManager.lua).
-- ---------------------------------------------------------------------------

local function getDbRoot()
    _G.PreydatorDB = _G.PreydatorDB or {}
    return _G.PreydatorDB
end

local function ensureProfileRoot()
    local db = getDbRoot()

    if type(db.profiles) ~= "table" then
        db.profiles = { Default = {} }
        db.activeProfile = "Default"
    end

    if type(db.activeProfile) ~= "string" or db.activeProfile == "" then
        db.activeProfile = "Default"
    end

    if type(db.profiles[db.activeProfile]) ~= "table" then
        db.profiles[db.activeProfile] = {}
    end

    if type(db.profiles.Default) ~= "table" then
        db.profiles.Default = {}
    end

    return db
end

function SettingsStore.GetActiveProfile()
    local db = ensureProfileRoot()
    return db.activeProfile
end

function SettingsStore.SwitchProfile(name)
    local db = ensureProfileRoot()
    name = type(name) == "string" and name or ""
    if name == "" then
        return false, "Profile name is required."
    end
    if type(db.profiles[name]) ~= "table" then
        return false, "Profile does not exist."
    end

    db.activeProfile = name
    return true
end

function SettingsStore.CreateProfile(name, copyFromName)
    local db = ensureProfileRoot()
    name = (type(name) == "string" and name or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if name == "" then
        return false, "Please enter a profile name."
    end
    if db.profiles[name] ~= nil then
        return false, "A profile with that name already exists."
    end

    local source = type(copyFromName) == "string" and db.profiles[copyFromName] or nil
    if type(source) == "table" then
        db.profiles[name] = deepCopy(source)
    else
        db.profiles[name] = getDefaultsInternal()
    end

    return true
end

function SettingsStore.DeleteProfile(name)
    local db = ensureProfileRoot()
    name = type(name) == "string" and name or ""
    if name == "" then
        return false, "Profile name is required."
    end
    if name == db.activeProfile then
        return false, "Cannot delete the active profile."
    end
    if db.profiles[name] == nil then
        return false, "Profile does not exist."
    end

    db.profiles[name] = nil
    if next(db.profiles) == nil then
        db.profiles.Default = {}
        db.activeProfile = "Default"
    end
    if db.profiles.Default == nil then
        db.profiles.Default = {}
    end

    return true
end

function SettingsStore.CopyProfileFrom(sourceName)
    local db = ensureProfileRoot()
    sourceName = type(sourceName) == "string" and sourceName or ""
    if sourceName == "" then
        return false, "Source profile is required."
    end

    local source = db.profiles[sourceName]
    if type(source) ~= "table" then
        return false, "Source profile does not exist."
    end

    db.profiles[db.activeProfile] = deepCopy(source)
    return true
end

-- ---------------------------------------------------------------------------
-- Load / Save / Migrate
-- ---------------------------------------------------------------------------

-- Overlays src onto dst in place, field by field, only where the incoming
-- value's type matches the default's type -- a corrupted/invalid field falls
-- back to its default individually rather than resetting the whole table
-- (Section 11 of the architecture doc).
local function deepOverlayValid(dst, src, pathPrefix)
    if type(dst) ~= "table" or type(src) ~= "table" then
        return
    end

    for key, defaultValue in pairs(dst) do
        local dottedKey = pathPrefix and (pathPrefix .. "." .. tostring(key)) or tostring(key)
        local incoming = src[key]

        if dottedKey and GROWABLE_LIST_FIELDS[dottedKey] then
            if type(incoming) == "table" then
                dst[key] = deepCopy(incoming)
            end
        elseif type(defaultValue) == "table" then
            if type(incoming) == "table" then
                deepOverlayValid(defaultValue, incoming, dottedKey)
            end
        elseif incoming ~= nil and type(incoming) == type(defaultValue) then
            dst[key] = incoming
        end
    end
end

-- Delegates to the (not-yet-built) Core/Runtime/SettingsRuntime.lua when it's
-- registered; otherwise passes the raw table through unchanged except for
-- stamping the current schema version, so this file stays load-order-safe
-- ahead of the Runtime slice.
function SettingsStore.RunMigrations(rawTable)
    rawTable = type(rawTable) == "table" and rawTable or {}

    local runtime = Preydator:GetModule("SettingsRuntime")
    if runtime and type(runtime.MigrateAll) == "function" then
        local ok, migrated = pcall(runtime.MigrateAll, rawTable)
        if ok and type(migrated) == "table" then
            rawTable = migrated
        end
    end

    if type(rawTable.general) ~= "table" then
        rawTable.general = {}
    end
    rawTable.general.schema_version = SCHEMA_VERSION

    return rawTable
end

function SettingsStore.Load()
    local db = ensureProfileRoot()
    local rawProfile = db.profiles[db.activeProfile]

    local migrated = SettingsStore.RunMigrations(deepCopy(rawProfile))

    local defaults = getDefaultsInternal()
    local merged = deepCopy(defaults)
    deepOverlayValid(merged, migrated, nil)

    -- Range/enum validation (Section 5's clamps/enums), on top of the
    -- field-by-field default fallback deepOverlayValid already did.
    local runtime = Preydator:GetModule("SettingsRuntime")
    if runtime and type(runtime.NormalizeAll) == "function" then
        local ok, normalized = pcall(runtime.NormalizeAll, merged, defaults)
        if ok and type(normalized) == "table" then
            merged = normalized
        end
    end

    return merged
end

function SettingsStore.Save(profileTable)
    if type(profileTable) ~= "table" then
        return false
    end

    local db = ensureProfileRoot()
    db.profiles[db.activeProfile] = deepCopy(profileTable)
    return true
end

Preydator:RegisterModule("SettingsStore", SettingsStore)
return SettingsStore
