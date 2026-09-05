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
-- own State ownership. Also maintains its own private zone-resolution trace
-- (see zoneResolutionTrace) for /pd zinspect -- not shared/domain state.

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

-- Passive trace of every ResolveQuestOnMap call where the raw Blizzard
-- isOnMap answer was false -- always recording, no setting to remember to
-- flip on, same reasoning as WidgetAdapter's own suppression trace (built
-- 2026-09-04 after a real "isOnMap=false, resolvedIsOnMap=false" report
-- resolved itself before it could be caught mid-failure for a second look,
-- leaving no way to tell whether the widget-visible fallback or its
-- container-scan widening actually worked). Only the false case is recorded
-- -- isOnMap=true is the routine, uninteresting outcome, and a hunt's
-- refresh tick fires every ~2s for the whole hunt, so logging every call
-- unconditionally would flood a small ring buffer with nothing but "true"
-- entries. Exposed via GetZoneResolutionTrace / DiagnosticsRuntime.
-- BuildZoneInspectReport / `/pd zinspect`.
local ZONE_TRACE_LIMIT = 20
local zoneResolutionTrace = {}

local function recordZoneResolution(questID, isOnMap, resolvedIsOnMap, widgetInfo, resolvedVia, latchAgeSeconds)
    local okTime, now = pcall(_G.GetTime)
    table.insert(zoneResolutionTrace, {
        time = (okTime and type(now) == "number") and now or 0,
        questID = questID,
        isOnMap = isOnMap,
        resolvedIsOnMap = resolvedIsOnMap,
        resolvedVia = resolvedVia,
        latchAgeSeconds = latchAgeSeconds,
        widgetIconFrameFound = widgetInfo and widgetInfo.iconFrameFound,
        widgetDesiredSuppression = widgetInfo and widgetInfo.desiredSuppression,
        widgetInCombat = widgetInfo and widgetInfo.inCombat,
        widgetDirectShown = widgetInfo and widgetInfo.directShown,
        widgetLastShownAtAge = widgetInfo and widgetInfo.lastShownAtAge,
    })
    while #zoneResolutionTrace > ZONE_TRACE_LIMIT do
        table.remove(zoneResolutionTrace, 1)
    end
end

-- Returns a shallow copy of the recent zone-resolution trace (oldest first).
function PreyContextRuntime.GetZoneResolutionTrace()
    local copy = {}
    for i, entry in ipairs(zoneResolutionTrace) do
        copy[i] = {
            time = entry.time,
            questID = entry.questID,
            isOnMap = entry.isOnMap,
            resolvedIsOnMap = entry.resolvedIsOnMap,
            resolvedVia = entry.resolvedVia,
            latchAgeSeconds = entry.latchAgeSeconds,
            widgetIconFrameFound = entry.widgetIconFrameFound,
            widgetDesiredSuppression = entry.widgetDesiredSuppression,
            widgetInCombat = entry.widgetInCombat,
            widgetDirectShown = entry.widgetDirectShown,
            widgetLastShownAtAge = entry.widgetLastShownAtAge,
        }
    end
    return copy
end

-- "Confirmed active" latch (Decisions Log item 74): a genuine hunt-progress
-- signal (isOnMap itself, or the widget-visible fallback) confirming this
-- quest as in-zone is remembered for CONFIRMED_ACTIVE_WINDOW_SECONDS, so a
-- brief confirming moment (an ambush/Mob Scanner nameplate match, which
-- typically starts combat and is exactly when the widget-visible fallback is
-- most reliable -- see WidgetAdapter.IsPreyWidgetVisible's combat-lockdown
-- handling) keeps the bar/sounds active through the gaps until the next one,
-- instead of re-deriving zone status from scratch on every ~2s tick and
-- flickering off between confirming events. Product owner's own diagnosis
-- (2026-09-04, Voidstorm): the bar only ever appeared during brief windows
-- right after a container/ambush/Pack Ambush/Exploding Corpse Snakes event,
-- then vanished again immediately after -- "if we can show it during those
-- brief windows why can we not show it the entire time."
--
-- Deliberately bounded, not sticky for the whole hunt -- a genuinely
-- unbounded latch would reintroduce the exact false-positive shape that
-- caused the old pre-rewrite codebase's Eversong Woods bug (Decisions Log
-- items 29/32/35/36's own history) if the player travels far away from the
-- prey zone while still holding the same quest. 120s is a starting value,
-- not a confirmed-safe one -- chosen to comfortably bridge normal gaps
-- between combat encounters within one continuous hunt (the default ambush
-- alert cooldown is 60s, so confirming events can naturally be tens of
-- seconds apart) without staying latched for many minutes after genuinely
-- leaving. If live testing shows false positives (bar staying lit well after
-- clearly leaving the area) OR gaps still slipping through (bar still
-- vanishing between genuinely-close-together events), this single constant
-- is the place to retune -- not a redesign either direction.
local CONFIRMED_ACTIVE_WINDOW_SECONDS = 120
local lastConfirmedTrue = { questID = nil, time = nil }

local function markConfirmedTrue(questID)
    local okTime, now = pcall(_G.GetTime)
    if okTime and type(now) == "number" then
        lastConfirmedTrue.questID = questID
        lastConfirmedTrue.time = now
    end
end

-- Returns the age in seconds of the last confirmation for questID (nil if
-- none/expired/for a different quest -- never carries over between hunts,
-- since a fresh activeQuestID means lastConfirmedTrue.questID no longer
-- matches).
local function confirmedTrueAgeSeconds(questID)
    if lastConfirmedTrue.questID ~= questID or lastConfirmedTrue.time == nil then
        return nil
    end
    local okTime, now = pcall(_G.GetTime)
    if not okTime or type(now) ~= "number" then
        return nil
    end
    return now - lastConfirmedTrue.time
end

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

-- Single source of truth for "should this quest be considered in the prey
-- zone" -- everything that used to call QuestApiAdapter.GetQuestIsOnMap()
-- directly (this file's own zone-gating step below, plus AlertsRuntime's
-- true-ambush/Mob-Scanner checks) now goes through this instead, so the one
-- fallback below applies everywhere at once rather than needing a matching
-- fix in every caller.
--
-- Found live 2026-09-04 (a Voidstorm PvP-optional sub-zone): a genuinely
-- active hunt reported isOnMap=false for the WHOLE time the player was
-- there, while Blizzard's own default prey icon stayed visible the entire
-- time -- proof C_QuestLog's isOnMap isn't authoritative for every zone
-- shape, contrary to this file's own previous assumption (Decisions Log item
-- 36). Rather than reintroducing the map-hierarchy pre-filter that item 36
-- deliberately removed after three separate false negatives of its own
-- (Decisions 29/32/35) -- a different, already-rejected class of heuristic
-- -- this instead trusts a second, independent Blizzard signal:
-- WidgetAdapter.IsPreyWidgetVisible(), which reflects whether Blizzard's own
-- widget system currently considers a prey-hunt relevant to the player,
-- exactly the same signal the product owner used to notice the bug in the
-- first place ("the Blizzard icon stays on the screen for it"). Only
-- overrides a CONFIRMED false -- an unresolved/nil isOnMap is left alone,
-- same "never guess" rule as before.
function PreyContextRuntime.ResolveQuestOnMap(questID)
    local questApi = Preydator:GetModule("QuestApiAdapter")
    if not questApi then
        return nil
    end

    local isOnMap = questApi.GetQuestIsOnMap(questID)
    if isOnMap == true then
        markConfirmedTrue(questID)
        return true
    end
    if isOnMap == nil then
        -- Never guess on unresolved -- leave inPreyZone/callers untouched,
        -- same rule as before. Does not touch or consume the latch either.
        return nil
    end

    -- isOnMap == false from here down.
    local widgetAdapter = Preydator:GetModule("WidgetAdapter")
    local widgetVisible = false
    local widgetInfo = nil
    if widgetAdapter then
        if type(widgetAdapter.IsPreyWidgetVisible) == "function" then
            widgetVisible = widgetAdapter.IsPreyWidgetVisible() == true
        end
        if type(widgetAdapter.GetVisibilityDebugInfo) == "function" then
            widgetInfo = widgetAdapter.GetVisibilityDebugInfo()
        end
    end

    if widgetVisible then
        markConfirmedTrue(questID)
        recordZoneResolution(questID, isOnMap, true, widgetInfo, "widget", nil)
        return true
    end

    -- Neither isOnMap nor the widget-visible check currently confirms zone
    -- membership -- bridge the gap using the last time THIS quest was
    -- confirmed true (see CONFIRMED_ACTIVE_WINDOW_SECONDS' own comment)
    -- rather than immediately flipping off.
    local latchAge = confirmedTrueAgeSeconds(questID)
    local latchedTrue = latchAge ~= nil and latchAge <= CONFIRMED_ACTIVE_WINDOW_SECONDS
    recordZoneResolution(questID, isOnMap, latchedTrue, widgetInfo,
        latchedTrue and "latch" or "none", latchAge)
    return latchedTrue
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
    -- and diagnostics) -- just no longer used to gate inPreyZone. Goes
    -- through ResolveQuestOnMap (above), not GetQuestIsOnMap directly, so the
    -- widget-visible fallback for isOnMap's own false negatives (Decisions
    -- Log item 69) applies here too.
    local isOnMap = PreyContextRuntime.ResolveQuestOnMap(activeQuestID)
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
