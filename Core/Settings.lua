-- Preydator :: Core/Settings.lua
-- Author: RagingAltoholic
-- Responsibility: the public settings surface every other module uses. Thin --
-- persistence, defaults, and migration live in Core/Adapters/SettingsStore.lua;
-- field validation/normalization lives in Core/Runtime/SettingsRuntime.lua.
-- Nothing outside Core/ touches PreydatorDB. Also owns
-- ApplyBarAccessibilityTheme -- the one settings action that needs to touch
-- several bar.* color fields at once rather than a single Get/Set pair.
-- Reads: Core/Adapters/SettingsStore.lua output.
-- Writes: delegates all writes to Core/Adapters/SettingsStore.lua.

local Preydator = _G.Preydator

local Settings = {}

-- Section 5.4 / 5.8: these dotted keys are documented aliases of a single
-- underlying field, not separate storage -- resolved here so nothing stores
-- (and drifts) two copies of the same value.
local ALIASES = {
    ["progress.segment_mode"] = "bar.progress_segments",
    ["debug.logging_enabled"] = "general.debug_logging_enabled",
}

-- The in-memory, loaded-and-merged settings table for the active profile.
-- Core/Settings.lua holds this in memory and does not re-read SavedVariables
-- per call (Section 12 of the architecture doc).
local cachedSettings = nil
local subscribers = {}

local function getStore()
    return Preydator:GetModule("SettingsStore")
end

local function ensureLoaded()
    if cachedSettings then
        return cachedSettings
    end

    local store = getStore()
    if not store or type(store.Load) ~= "function" then
        return nil
    end

    cachedSettings = store.Load()
    return cachedSettings
end

local function splitKey(key)
    if type(key) ~= "string" then
        return nil, nil
    end
    return string.match(key, "^([^.]+)%.(.+)$")
end

local function notify()
    for _, callback in ipairs(subscribers) do
        pcall(callback, cachedSettings)
    end
end

function Settings.Get(key)
    key = ALIASES[key] or key
    local category, field = splitKey(key)
    if not category then
        return nil
    end

    local loaded = ensureLoaded()
    if not loaded or type(loaded[category]) ~= "table" then
        return nil
    end

    return loaded[category][field]
end

function Settings.Set(key, value)
    key = ALIASES[key] or key
    local category, field = splitKey(key)
    if not category then
        return false
    end

    local loaded = ensureLoaded()
    if not loaded then
        return false
    end

    if type(loaded[category]) ~= "table" then
        loaded[category] = {}
    end

    -- Basic field-level type guard (full range/enum validation arrives with
    -- Core/Runtime/SettingsRuntime.lua): a value may only overwrite an existing
    -- one of the same type.
    local existing = loaded[category][field]
    if existing ~= nil and value ~= nil and type(existing) ~= type(value) then
        return false
    end

    loaded[category][field] = value

    local store = getStore()
    if store and type(store.Save) == "function" then
        store.Save(loaded)
    end

    notify()
    return true
end

function Settings.GetDefaults()
    local store = getStore()
    if not store or type(store.GetDefaults) ~= "function" then
        return {}
    end
    return store.GetDefaults()
end

function Settings.ResetToDefaults()
    local store = getStore()
    if not store or type(store.GetDefaults) ~= "function" then
        return false
    end

    cachedSettings = store.GetDefaults()
    if type(store.Save) == "function" then
        store.Save(cachedSettings)
    end

    notify()
    return true
end

-- deuteranopia/protanopia bar-color presets, ported verbatim from the old
-- Modules/Settings.lua (BAR_ACCESSIBILITY_PRESETS, :119-144). A one-shot bulk
-- overwrite of the six bar color fields + border-link flag, not a persistent
-- theme mode -- picking a preset writes plain color values once, so a later
-- manual color tweak silently drifts from the preset with no re-sync. That's
-- the old code's actual (deliberately kept) behavior, not an oversight -- see
-- architecture doc Decisions Log items 6/9.
local BAR_ACCESSIBILITY_PRESETS = {
    deuteranopia = {
        fill_color = { 0.90, 0.60, 0.10, 1.00 },
        border_color = { 0.90, 0.60, 0.10, 1.00 },
        title_color = { 1.00, 0.74, 0.00, 1.00 },
        percent_color = { 1.00, 1.00, 1.00, 1.00 },
        tick_color = { 0.65, 0.68, 0.84, 1.00 },
        bg_color = { 0.06, 0.07, 0.14, 0.88 },
        border_color_linked = false,
    },
    protanopia = {
        fill_color = { 0.00, 0.72, 0.82, 1.00 },
        border_color = { 0.00, 0.72, 0.82, 1.00 },
        title_color = { 0.00, 0.88, 1.00, 1.00 },
        percent_color = { 1.00, 1.00, 1.00, 1.00 },
        tick_color = { 0.50, 0.74, 0.80, 1.00 },
        bg_color = { 0.03, 0.10, 0.13, 0.88 },
        border_color_linked = false,
    },
}

-- Applies (or clears, for any key other than a known preset) an accessibility
-- color preset. Called by UI/SettingsPanel.lua's accessibility_theme control
-- instead of a plain Settings.Set, since this needs to touch seven fields at
-- once, not just the enum itself.
function Settings.ApplyBarAccessibilityTheme(themeKey)
    local preset = BAR_ACCESSIBILITY_PRESETS[themeKey]
    local defaults = Settings.GetDefaults()
    local fields = preset or {
        fill_color = defaults.bar.fill_color,
        border_color = defaults.bar.border_color,
        title_color = defaults.bar.title_color,
        percent_color = defaults.bar.percent_color,
        tick_color = defaults.bar.tick_color,
        bg_color = defaults.bar.bg_color,
        border_color_linked = defaults.bar.border_color_linked,
    }

    for field, value in pairs(fields) do
        Settings.Set("bar." .. field, value)
    end
    Settings.Set("bar.accessibility_theme", preset and themeKey or "default")
end

function Settings.Subscribe(callback)
    if type(callback) ~= "function" then
        return
    end
    table.insert(subscribers, callback)
end

Preydator:RegisterModule("Settings", Settings)
return Settings
