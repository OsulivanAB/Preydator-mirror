-- Preydator :: Core/Runtime/BarRuntime.lua
-- Author: RagingAltoholic
-- Responsibility: pure computation of a bar view-model. Does not touch a single
-- Blizzard frame or texture -- that's UI/BarFrame.lua's job entirely. The
-- view-model carries only game-state-derived values (visible, fillPercent,
-- stage, prefixText, suffixText, tickPositions) -- pure presentation settings
-- (orientation, colors, fonts, texture, percent_display, etc.) have no
-- game-state dependency and are read directly by UI/BarFrame.lua instead.
-- Reads: Core/State.lua, Settings.
-- Writes: nothing (pure function of its inputs).

local Preydator = _G.Preydator

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
