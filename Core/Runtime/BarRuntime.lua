-- Preydator :: Core/Runtime/BarRuntime.lua
-- Author: RagingAltoholic
-- Responsibility: pure computation of a bar view-model. Does not touch a single
-- Blizzard frame or texture -- that's UI/BarFrame.lua's job entirely. The
-- view-model carries only game-state-derived values (visible, fillPercent,
-- stage, prefixText, suffixText, tickPositions) -- pure presentation settings
-- (orientation, colors, fonts, texture, percent_display, etc.) have no
-- game-state dependency and are read directly by UI/BarFrame.lua instead.
-- While State's ambushTextKind hasn't expired (set by AlertsRuntime when an
-- ambush/Pack Ambush trigger actually fires), prefixText/suffixText
-- temporarily show text.ambush_prefix/pack_ambush_prefix + the rendered
-- suffix template instead of the normal per-stage text.
-- Reads: Core/State.lua, Settings.
-- Writes: nothing (pure function of its inputs).

local Preydator = _G.Preydator
local GetTime = _G.GetTime

local BarRuntime = {}

local TICK_POSITIONS_BY_SEGMENT_MODE = {
    quarters = { 25, 50, 75 },
    thirds = { 33, 66 },
}

local function L(key)
    local localization = Preydator:GetModule("LocalizationAdapter")
    if localization and type(localization.L) == "function" then
        return localization.L(key)
    end
    return key
end

-- Substitutes {tokenName} placeholders in text.ambush_suffix_template /
-- text.pack_ambush_suffix_template (e.g. {preyTargetName}, {packAmbushSourceName})
-- with the live value AlertsRuntime recorded when the trigger fired. `{` and
-- `}` aren't Lua pattern magic characters, so the search side needs no
-- escaping; the replacement side does, since gsub treats "%" specially there.
local function renderTemplate(template, tokens)
    if type(template) ~= "string" or template == "" then
        return ""
    end
    local rendered = template
    for token, value in pairs(tokens) do
        local escapedValue = (type(value) == "string" and value or ""):gsub("%%", "%%%%")
        rendered = rendered:gsub("{" .. token .. "}", escapedValue)
    end
    return rendered
end

-- Ambush/Pack Ambush text is transient: AlertsRuntime stamps an expiry
-- (GetTime() + a fixed display window) into State when a trigger actually
-- fires, and this just checks whether that window has passed -- no timer of
-- its own, consistent with BarRuntime being a pure function of its inputs.
local function computeAmbushTextOverride(snapshot, Settings)
    local kind = snapshot.ambushTextKind
    local expiresAt = snapshot.ambushTextExpiresAt
    if not kind or type(expiresAt) ~= "number" then
        return nil
    end

    local okTime, now = pcall(GetTime)
    if not okTime or type(now) ~= "number" or now >= expiresAt then
        return nil
    end

    if kind == "ambush" then
        return Settings.Get("text.ambush_prefix") or "",
            renderTemplate(Settings.Get("text.ambush_suffix_template"), {
                preyTargetName = snapshot.ambushTextSourceName,
            })
    elseif kind == "pack_ambush" then
        return Settings.Get("text.pack_ambush_prefix") or "",
            renderTemplate(Settings.Get("text.pack_ambush_suffix_template"), {
                packAmbushSourceName = snapshot.ambushTextSourceName,
            })
    end

    return nil
end

function BarRuntime.ComputeBarViewModel()
    local State = Preydator:GetModule("State")
    local Settings = Preydator:GetModule("Settings")
    if not (State and Settings) then
        return nil
    end

    local snapshot = State.GetSnapshot()
    local segmentMode = Settings.Get("bar.progress_segments") or "quarters"
    local tickPositions = Settings.Get("bar.show_ticks") ~= false
        and (TICK_POSITIONS_BY_SEGMENT_MODE[segmentMode] or TICK_POSITIONS_BY_SEGMENT_MODE.quarters)
        or {}

    if snapshot.inPreyZone ~= true then
        local prefix = Settings.Get("text.out_of_zone_prefix") or ""
        local suffix = Settings.Get("text.out_of_zone_suffix")
        if type(suffix) ~= "string" or suffix == "" then
            suffix = L("No Sign in These Fields")
        end

        return {
            visible = Settings.Get("general.only_show_in_prey_zone") ~= true,
            prefixText = prefix,
            suffixText = suffix,
            fillPercent = 0,
            stage = nil,
            tickPositions = tickPositions,
        }
    end

    local stage = snapshot.stage or 1
    local stagePrefixes = Settings.Get("text.stage_prefix")
    local stageSuffixes = Settings.Get("text.stage_suffix")
    local prefix = (type(stagePrefixes) == "table" and stagePrefixes[stage]) or ""
    local suffix = (type(stageSuffixes) == "table" and stageSuffixes[stage]) or ""

    local ambushPrefix, ambushSuffix = computeAmbushTextOverride(snapshot, Settings)
    if ambushPrefix then
        prefix = ambushPrefix
        suffix = ambushSuffix
    end

    return {
        visible = true,
        prefixText = prefix,
        suffixText = suffix,
        fillPercent = snapshot.progressPercent or 0,
        stage = stage,
        tickPositions = tickPositions,
    }
end

Preydator:RegisterModule("BarRuntime", BarRuntime)
return BarRuntime
