-- Preydator :: Core/Settings.lua
-- Author: RagingAltoholic
-- Responsibility: the public settings surface every other module uses. Thin --
-- persistence, defaults, and migration live in Core/Adapters/SettingsStore.lua;
-- field validation/normalization will live in the not-yet-built
-- Core/Runtime/SettingsRuntime.lua. Nothing outside Core/ touches PreydatorDB.
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

function Settings.Subscribe(callback)
    if type(callback) ~= "function" then
        return
    end
    table.insert(subscribers, callback)
end

Preydator:RegisterModule("Settings", Settings)
return Settings
