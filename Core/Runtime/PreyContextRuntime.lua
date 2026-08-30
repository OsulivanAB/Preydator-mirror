-- Preydator :: Core/Runtime/PreyContextRuntime.lua
-- Author: RagingAltoholic
-- Responsibility: the single canonical owner of "what quest is active, are we in
-- its zone, what stage is it." Implements the zone-gating design from Section 8
-- of the architecture doc.
-- Reads: QuestApiAdapter, MapContextAdapter, WidgetAdapter, Settings,
-- Modules/HuntScanner/HuntScannerRuntime (expected-zone cache, read-only, via
-- its public API -- not yet built, looked up defensively).
-- Writes: Core/State.lua, via setters only.

local Preydator = _G.Preydator

local PreyContextRuntime = {}

-- The one and only stage-based progress fallback table (progress.fallback_mode
-- = "stage"), keyed by bar.progress_segments / progress.segment_mode.
local STAGE_PERCENT_BY_SEGMENT_MODE = {
    quarters = { [1] = 25, [2] = 50, [3] = 75, [4] = 100 },
    thirds = { [1] = 0, [2] = 33, [3] = 66, [4] = 100 },
}

local WIDGET_PERCENT_FIELDS = {
    "progressPercentage", "progressPercent", "fillPercentage", "percentage", "percent", "progress",
}

local function getModules()
    return
        Preydator:GetModule("QuestApiAdapter"),
        Preydator:GetModule("MapContextAdapter"),
        Preydator:GetModule("WidgetAdapter"),
        Preydator:GetModule("State"),
        Preydator:GetModule("Settings"),
        Preydator:GetModule("HuntScannerRuntime")
end

-- Parses "Prey: Name (Difficulty)" / "Prey: Name" quest titles. Single
-- implementation of this parse; nothing else re-derives it.
local function parsePreyTargetFromTitle(title)
    if type(title) ~= "string" or title == "" then
        return nil, nil
    end

    local name, difficulty = title:match("^%s*[Pp]rey:%s*(.-)%s*%((.-)%)%s*$")
    if name and name ~= "" then
        return name, difficulty
    end

    name = title:match("^%s*[Pp]rey:%s*(.-)%s*$")
    if name and name ~= "" then
        return name, nil
    end

    return nil, nil
end

-- widgetInfo.progressState is 0-based (0..3); stage is 1-based (1..4). An
-- unrecognized/missing value defaults to stage 1 rather than leaving stage
-- unset -- a quest is always considered "in stage 1" until told otherwise.
local function stageFromProgressState(progressState)
    if progressState == 0 then return 1 end
    if progressState == 1 then return 2 end
    if progressState == 2 then return 3 end
    if progressState == 3 then return 4 end
    return 1
end

local function resolveWidgetPercent(widgetSnapshot)
    if type(widgetSnapshot) ~= "table" then
        return nil
    end
    for _, fieldName in ipairs(WIDGET_PERCENT_FIELDS) do
        local value = widgetSnapshot[fieldName]
        if type(value) == "number" then
            return value
        end
    end
    return nil
end

local function resolveStageFallbackPercent(stage, settings)
    local segmentMode = (settings and settings.Get("bar.progress_segments")) or "quarters"
    local table_ = STAGE_PERCENT_BY_SEGMENT_MODE[segmentMode] or STAGE_PERCENT_BY_SEGMENT_MODE.quarters
    return table_[stage]
end

function PreyContextRuntime.RefreshPreyContext()
    local questApi, mapContext, widgetAdapter, state, settings, huntScanner = getModules()
    if not (questApi and mapContext and state) then
        return
    end

    if mapContext.IsRestrictedInstance() then
        state.SetPollingActive(false)
        state.SetInPreyZone(false)
        state.ClearActiveQuest()
        return
    end
    state.SetPollingActive(true)

    local activeQuestID = questApi.GetActivePreyQuestID()
    if not activeQuestID then
        state.ClearActiveQuest()
        state.SetInPreyZone(false)
        return
    end

    if state.GetSnapshot().activeQuestID ~= activeQuestID then
        -- New hunt: (re)resolve everything that's captured once per hunt.
        state.SetActiveQuestID(activeQuestID)

        local title = questApi.GetQuestTitle(activeQuestID)
        local name, difficulty = parsePreyTargetFromTitle(title)
        state.SetPreyTargetName(name)
        state.SetPreyTargetDifficulty(difficulty)

        local expectedZone = (huntScanner and type(huntScanner.GetExpectedZone) == "function")
            and huntScanner.GetExpectedZone(activeQuestID) or nil
        state.SetExpectedZoneMapID(expectedZone)
    end

    -- Section 8, steps 1-3: cheap map-ID pre-filter before the authoritative
    -- quest-log check. The pre-filter only ever short-circuits to false or
    -- defers -- it never itself asserts "in zone".
    local expectedZone = state.GetSnapshot().expectedZoneMapID
    local playerMapID = mapContext.GetPlayerMapID()

    if expectedZone and playerMapID and expectedZone ~= playerMapID then
        state.SetInPreyZone(false)
    else
        local isOnMap = questApi.GetQuestIsOnMap(activeQuestID)
        if isOnMap ~= nil then
            state.SetInPreyZone(isOnMap)
        end
        -- isOnMap == nil (unknown) leaves inPreyZone untouched; never guessed.
    end

    -- Stage/progress: prefer the live Blizzard widget snapshot; fall back to
    -- the single stage-based percent table (progress.fallback_mode = "stage")
    -- when Blizzard doesn't expose a precise value.
    local widgetSnapshot = widgetAdapter and widgetAdapter.GetWidgetStage()
    local stage = widgetSnapshot and stageFromProgressState(widgetSnapshot.progressState) or nil
    if stage == nil then
        stage = state.GetSnapshot().stage or 1
    end
    state.SetStage(stage)

    local percent = resolveWidgetPercent(widgetSnapshot)
    if percent == nil then
        percent = resolveStageFallbackPercent(stage, settings)
    end
    state.SetProgressPercent(percent)
end

function PreyContextRuntime.GetExpectedZoneForActiveQuest()
    local questApi, _, _, _, _, huntScanner = getModules()
    local activeQuestID = questApi and questApi.GetActivePreyQuestID()
    if not activeQuestID or not huntScanner or type(huntScanner.GetExpectedZone) ~= "function" then
        return nil
    end
    return huntScanner.GetExpectedZone(activeQuestID)
end

Preydator:RegisterModule("PreyContextRuntime", PreyContextRuntime)
return PreyContextRuntime
