-- Preydator :: Core/Adapters/LocalizationAdapter.lua
-- Author: RagingAltoholic
-- Responsibility: the only place GetLocale() is read and the only place a locale
-- string table is resolved. Every user-facing string in Runtime/UI goes through
-- L(key). Locale files (Locales/*.lua) keep populating the shared _G.PreydatorL
-- table themselves, unchanged -- this adapter is just the sanctioned entry point
-- for reading it.
-- Reads: _G.PreydatorL, GetLocale().
-- Writes: nothing (pure adapter).

local Preydator = _G.Preydator
local GetLocale = _G.GetLocale

local LocalizationAdapter = {}

-- _G.PreydatorL falls back to the key itself via its __index metatable when a
-- string has no translation, so missing translations never need a caller-side
-- fallback branch.
function LocalizationAdapter.L(key)
    if type(key) ~= "string" or key == "" then
        return ""
    end

    local L = _G.PreydatorL
    if type(L) ~= "table" then
        return key
    end

    local ok, value = pcall(function() return L[key] end)
    if ok and type(value) == "string" and value ~= "" then
        return value
    end
    return key
end

-- Checks whether a *real* (non-fallback) translation is stored for key. locale
-- defaults to the client's current locale; since _G.PreydatorL only ever holds
-- the currently active locale's strings (each Locales/*.lua file gates itself on
-- GetLocale() at load time), asking about any other locale always returns false.
function LocalizationAdapter.HasTranslation(key, locale)
    if type(key) ~= "string" or key == "" then
        return false
    end

    local currentLocale = nil
    local ok, result = pcall(GetLocale)
    if ok then
        currentLocale = result
    end

    locale = locale or currentLocale
    if locale ~= nil and locale ~= currentLocale then
        return false
    end

    if locale == "enUS" then
        -- enUS strings are the keys themselves, so the key is always "translated".
        return true
    end

    local L = _G.PreydatorL
    if type(L) ~= "table" then
        return false
    end

    local raw = rawget(L, key)
    return type(raw) == "string" and raw ~= ""
end

Preydator:RegisterModule("LocalizationAdapter", LocalizationAdapter)
return LocalizationAdapter
