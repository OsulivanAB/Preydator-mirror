-- Preydator :: Core/Runtime/PreyContextRuntime.lua
-- Author: RagingAltoholic
-- Responsibility: the single canonical owner of "what quest is active, are we in
-- its zone, what stage is it." Implements the zone-gating design from Section 8
-- of the architecture doc.
-- Reads: QuestApiAdapter, MapContextAdapter, WidgetAdapter, Settings,
-- Modules/HuntScanner/HuntScannerRuntime (expected-zone cache, read-only, via
-- its public API -- not yet built, looked up defensively).
-- Writes: Core/State.lua, via setters only. Also triggers
-- SoundsRuntime.PlayStageSound and WidgetAdapter.SuppressDefaultPreyIcon on
-- every refresh (both self-guarded/idempotent, safe to call every tick) --
-- not State writes, but the two side effects this file causes outside its
-- own State ownership.

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

-- The final stage ("prey found") -- matches STAGE_PERCENT_BY_SEGMENT_MODE's
-- last entry (both tables map stage 4 to 100%).
local FOUND_STAGE = 4

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

-- Applies general.disable_default_prey_icon while a hunt is actively being
-- tracked -- found live (2026-08-28) that WidgetAdapter.SuppressDefaultPreyIcon
-- was fully built but never actually called from anywhere, same gap as
-- SoundsRuntime.PlayStageSound.
--
-- Deliberately ONLY ever called while a hunt is active (from the end of a
-- successful refresh below) -- an earlier version of this function also
-- called an explicit un-suppress (desiredSuppress=false) from the "no active
-- quest"/restricted-instance early-return branches, intending to "restore"
-- the icon once tracking stopped. That was itself the bug: un-suppressing
-- calls WidgetAdapter's applyFrameSuppression(frame, false), which explicitly
-- calls frame:Show() if the frame was shown at the moment suppression was
-- captured -- forcing Blizzard's default prey icon to visibly reappear,
-- showing its last (now-stale, "partially completed") progress, right as a
-- hunt turned in. Blizzard's own icon is never shown at all without an
-- active/in-zone hunt (product owner's own domain knowledge, 2026-08-28) --
-- so there is nothing to "restore" once a hunt ends; simply not touching
-- suppression state at all is correct, and leaves the live in-hunt case
-- (the setting toggled off mid-hunt) as the only place un-suppression
-- legitimately happens, which the every-refresh-tick call below still covers.
local function applyIconSuppression(widgetAdapter, settings)
    if not widgetAdapter or type(widgetAdapter.SuppressDefaultPreyIcon) ~= "function" then
        return
    end
    local desiredSuppress = settings and settings.Get("general.disable_default_prey_icon") == true
    widgetAdapter.SuppressDefaultPreyIcon(desiredSuppress == true)
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

    -- Section 8's original design used a cheap map-ID pre-filter
    -- (expectedZoneMapID vs playerMapID) to short-circuit to "not in zone"
    -- before ever calling the authoritative quest-log check. Removed
    -- 2026-08-28 after three separate live false negatives from the
    -- pre-filter's own heuristic (Decisions 29, 32, 35) -- each a different
    -- zone-hierarchy shape (a continent map containing a specific leaf zone;
    -- a specific sub-area nested inside a broader zone; and a third shape in
    -- Zul'Aman that didn't fit either pattern) -- while GetQuestIsOnMap()
    -- itself was correct in every one of them. It's two lightweight,
    -- pcall-guarded quest-log lookups (GetLogIndexForQuestID + GetInfo, no
    -- map/pathing work at all) -- not meaningfully more expensive than the
    -- pre-filter's own up-to-10-hop parentMapID walk it replaces, so calling
    -- it directly every refresh isn't a performance concern. Both
    -- AlertsRuntime sound triggers (ambush, Mob Scanner) already made this
    -- same switch (Decisions 34/35); this brings the bar in line with them
    -- instead of leaving it on the older, repeatedly-patched heuristic.
    -- expectedZoneMapID is still captured above (for Hunt Table zone display
    -- and diagnostics) -- just no longer used to gate inPreyZone.
    local isOnMap = questApi.GetQuestIsOnMap(activeQuestID)
    if isOnMap ~= nil then
        state.SetInPreyZone(isOnMap)
    end
    -- isOnMap == nil (unknown) leaves inPreyZone untouched; never guessed.

    -- Stage/progress: prefer the live Blizzard widget snapshot; fall back to
    -- the single stage-based percent table (progress.fallback_mode = "stage")
    -- when Blizzard doesn't expose a precise value.
    local widgetSnapshot = widgetAdapter and widgetAdapter.GetWidgetStage()
    local stage = widgetSnapshot and stageFromProgressState(widgetSnapshot.progressState) or nil
    if stage == nil then
        stage = state.GetSnapshot().stage or 1
    end

    -- The quest's own "Hunt your Prey" objective reaching finished=true is a
    -- reliable, widget-independent signal for the final stage (product
    -- owner's own domain knowledge, 2026-08-28: ambushes only occur through
    -- stages 1-3; the objective flips to finished exactly at stage 4,
    -- regardless of whether the widget system has reported anything).
    -- Overrides whatever the widget/fallback path computed, never lowers a
    -- stage that's already correctly at FOUND_STAGE.
    local objectives = questApi.GetQuestObjectives(activeQuestID)
    local firstObjective = type(objectives) == "table" and objectives[1]
    if firstObjective and firstObjective.finished == true then
        stage = FOUND_STAGE
    end

    state.SetStage(stage)

    -- SoundsRuntime.PlayStageSound was defined but never called anywhere in
    -- the rewrite (found live, 2026-08-28) -- it already self-guards against
    -- replaying the same/a lower stage for the current quest
    -- (lastPlayedStage), so calling it every refresh tick is safe; it only
    -- actually plays on a genuine stage advance.
    local sounds = Preydator:GetModule("SoundsRuntime")
    if sounds then
        sounds.PlayStageSound(stage)
    end

    local percent = resolveWidgetPercent(widgetSnapshot)
    if percent == nil then
        percent = resolveStageFallbackPercent(stage, settings)
    end
    state.SetProgressPercent(percent)

    applyIconSuppression(widgetAdapter, settings)
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
