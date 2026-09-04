-- Preydator :: Core/Runtime/DiagnosticsRuntime.lua
-- Author: RagingAltoholic
-- Responsibility: assembles the hinspect/qinspect/pinspect/inspect/sinspect
-- reports by reading State, Settings, and Adapters, and returning formatted
-- text for a caller (Core/SlashCommands.lua) to print/dispatch to BugSack.
-- Reads: Core/State.lua, Settings, QuestApiAdapter, MapContextAdapter,
-- WidgetAdapter, DiagnosticsAdapter, HuntTableAdapter, HuntScannerRuntime,
-- BarRuntime (pure computation, read-only), SoundsRuntime (recent play
-- history only, via its GetRecentPlays getter), EventRuntime (debug state
-- only, via its GetHuntTrackingDebugState getter), and UI/BarFrame.lua's
-- PreydatorBarFrame global for its live IsShown() state only (no writes).
-- Writes: nothing.

local Preydator = _G.Preydator
local GetTime = _G.GetTime
local GetZoneText = _G.GetZoneText
local C_AddOns = _G.C_AddOns

local DiagnosticsRuntime = {}

local function safeValue(value)
    if value == nil then
        return "nil"
    end
    local ok, converted = pcall(tostring, value)
    return ok and converted or "<tostring failed>"
end

local function formatTablePairs(tbl)
    if type(tbl) ~= "table" then
        return safeValue(tbl)
    end
    local parts = {}
    for key, value in pairs(tbl) do
        parts[#parts + 1] = tostring(key) .. "=" .. safeValue(value)
    end
    table.sort(parts)
    return "{" .. table.concat(parts, ", ") .. "}"
end

local function getAddonVersion()
    if type(C_AddOns) == "table" and type(C_AddOns.GetAddOnMetadata) == "function" then
        local ok, version = pcall(C_AddOns.GetAddOnMetadata, "Preydator", "Version")
        if ok and type(version) == "string" and version ~= "" then
            return version
        end
    end
    return "?"
end

local function nowTime()
    local ok, value = pcall(GetTime)
    return (ok and type(value) == "number") and value or 0
end

function DiagnosticsRuntime.BuildGeneralInspectReport()
    local state = Preydator:GetModule("State")
    local settings = Preydator:GetModule("Settings")
    local questApi = Preydator:GetModule("QuestApiAdapter")
    local mapContext = Preydator:GetModule("MapContextAdapter")
    local widgetAdapter = Preydator:GetModule("WidgetAdapter")

    local lines = {}
    local function add(line) lines[#lines + 1] = tostring(line or "") end

    add("Preydator General Inspect | addon=" .. getAddonVersion())
    add("- time=" .. string.format("%.3f", nowTime()) .. " | zone=" .. safeValue(GetZoneText and GetZoneText()))

    local playerMapID = mapContext and mapContext.GetPlayerMapID()
    local mapInfo = playerMapID and mapContext.GetMapInfo(playerMapID)
    add("- playerMapID=" .. safeValue(playerMapID) .. " | playerMap=" .. safeValue(mapInfo and mapInfo.name))
    add("- restrictedInstance=" .. safeValue(mapContext and mapContext.IsRestrictedInstance()))

    local liveQuestID = questApi and questApi.GetActivePreyQuestID()
    local snapshot = state and state.GetSnapshot() or {}
    add("- quest live=" .. safeValue(liveQuestID) .. " | tracked=" .. safeValue(snapshot.activeQuestID))
    add("- pollingActive=" .. safeValue(state and state.IsPollingActive()))
    add("- inPreyZone=" .. safeValue(snapshot.inPreyZone)
        .. " | expectedZoneMapID=" .. safeValue(snapshot.expectedZoneMapID))

    add("- settings bar_enabled=" .. safeValue(settings and settings.Get("general.bar_enabled"))
        .. " | sounds_enabled=" .. safeValue(settings and settings.Get("general.sounds_enabled"))
        .. " | hunt_enabled=" .. safeValue(settings and settings.Get("general.hunt_enabled"))
        .. " | only_show_in_prey_zone=" .. safeValue(settings and settings.Get("general.only_show_in_prey_zone")))

    local widgetSnapshot = widgetAdapter and widgetAdapter.GetWidgetStage()
    add("- widgetSnapshot=" .. formatTablePairs(widgetSnapshot))

    -- Bridges all 3 layers (State -> BarRuntime -> UI/BarFrame) in one line so
    -- a "bar isn't showing" report can pinpoint which layer is wrong, rather
    -- than the caller having to manually reason through settings + inPreyZone
    -- themselves. BarRuntime.ComputeBarViewModel is a pure function of
    -- State/Settings (no frame access, per its own header comment), so
    -- calling it here for inspection is safe/side-effect-free.
    local barRuntime = Preydator:GetModule("BarRuntime")
    local viewModel = barRuntime and barRuntime.ComputeBarViewModel()
    add("- BarRuntime viewModel=" .. formatTablePairs(viewModel))
    local barFrame = _G.PreydatorBarFrame
    add("- UI/BarFrame.lua frame IsShown=" .. safeValue(barFrame and barFrame.IsShown and barFrame:IsShown()))

    return table.concat(lines, "\n")
end

function DiagnosticsRuntime.BuildProgressInspectReport()
    local state = Preydator:GetModule("State")
    local settings = Preydator:GetModule("Settings")
    local widgetAdapter = Preydator:GetModule("WidgetAdapter")

    local lines = {}
    local function add(line) lines[#lines + 1] = tostring(line or "") end

    local snapshot = state and state.GetSnapshot() or {}
    add("Preydator Progress Inspect | addon=" .. getAddonVersion())
    add("- activeQuestID=" .. safeValue(snapshot.activeQuestID)
        .. " | stage=" .. safeValue(snapshot.stage)
        .. " | progressPercent=" .. safeValue(snapshot.progressPercent))
    add("- preyTargetName=" .. safeValue(snapshot.preyTargetName)
        .. " | preyTargetDifficulty=" .. safeValue(snapshot.preyTargetDifficulty))
    add("- inPreyZone=" .. safeValue(snapshot.inPreyZone)
        .. " | questListenUntil=" .. safeValue(snapshot.questListenUntil))
    add("- progress.fallback_mode=" .. safeValue(settings and settings.Get("progress.fallback_mode"))
        .. " | bar.progress_segments=" .. safeValue(settings and settings.Get("bar.progress_segments")))

    local widgetSnapshot = widgetAdapter and widgetAdapter.GetWidgetStage()
    add("- widgetSnapshot=" .. formatTablePairs(widgetSnapshot))

    return table.concat(lines, "\n")
end

function DiagnosticsRuntime.BuildQuestInspectReport(requestedQuestID)
    local state = Preydator:GetModule("State")
    local questApi = Preydator:GetModule("QuestApiAdapter")
    local mapContext = Preydator:GetModule("MapContextAdapter")

    local lines = {}
    local function add(line) lines[#lines + 1] = tostring(line or "") end

    local liveQuestID = questApi and questApi.GetActivePreyQuestID()
    local snapshot = state and state.GetSnapshot() or {}
    local questID = tonumber(requestedQuestID) or liveQuestID or snapshot.activeQuestID

    add("Preydator Quest Inspect | addon=" .. getAddonVersion())
    add("- requestedQuestID=" .. safeValue(requestedQuestID)
        .. " | livePreyQuestID=" .. safeValue(liveQuestID)
        .. " | trackedQuestID=" .. safeValue(snapshot.activeQuestID)
        .. " | inspectQuestID=" .. safeValue(questID))

    if not questID or questID <= 0 then
        add("- No valid quest ID available to inspect.")
        return table.concat(lines, "\n")
    end

    if not questApi then
        add("- QuestApiAdapter unavailable.")
        return table.concat(lines, "\n")
    end

    local title = questApi.GetQuestTitle(questID)
    local link = questApi.GetQuestLink(questID)
    local isOnMap = questApi.GetQuestIsOnMap(questID)
    local zoneID = questApi.GetQuestZoneID(questID)
    local zoneInfo = zoneID and mapContext and mapContext.GetMapInfo(zoneID)
    local isOnQuest = questApi.IsOnQuest(questID)
    local isCompleted = questApi.IsQuestFlaggedCompleted(questID)

    add("- basic | title=" .. safeValue(title) .. " | link=" .. safeValue(link))
    add("- zone | zoneID=" .. safeValue(zoneID) .. " | zoneName=" .. safeValue(zoneInfo and zoneInfo.name)
        .. " | isOnMap=" .. safeValue(isOnMap))
    add("- flags | isOnQuest=" .. safeValue(isOnQuest) .. " | isFlaggedCompleted=" .. safeValue(isCompleted))

    local objectives = questApi.GetQuestObjectives(questID)
    if type(objectives) == "table" and #objectives > 0 then
        add("- objectives count=" .. tostring(#objectives))
        for i, objective in ipairs(objectives) do
            add("  - [" .. tostring(i) .. "] " .. formatTablePairs(objective))
        end
    else
        add("- objectives count=0")
    end

    return table.concat(lines, "\n")
end

-- New (2026-08-28), built for diagnosing "why hunts are/aren't appearing"
-- live reports. Covers the whole Hunt Table detection/scan pipeline in one
-- shot: is the table considered active, what does EventRuntime's private
-- interaction-tracking state say (only reachable via its debug getter,
-- otherwise invisible), and the actually-scanned hunt list with each hunt's
-- resolved zone/reward summary.
function DiagnosticsRuntime.BuildHuntInspectReport()
    local adapter = Preydator:GetModule("HuntTableAdapter")
    local huntScanner = Preydator:GetModule("HuntScannerRuntime")
    local eventRuntime = Preydator:GetModule("EventRuntime")
    local settings = Preydator:GetModule("Settings")

    local lines = {}
    local function add(line) lines[#lines + 1] = tostring(line or "") end

    add("Preydator Hunt Inspect | addon=" .. getAddonVersion())

    local isActive = adapter and type(adapter.IsHuntTableActive) == "function" and adapter.IsHuntTableActive()
    add("- IsHuntTableActive=" .. safeValue(isActive))

    local trackingState = eventRuntime and type(eventRuntime.GetHuntTrackingDebugState) == "function"
        and eventRuntime.GetHuntTrackingDebugState()
    add("- EventRuntime tracking=" .. formatTablePairs(trackingState))

    add("- settings hunt.enabled=" .. safeValue(settings and settings.Get("hunt.enabled"))
        .. " | general.hunt_enabled=" .. safeValue(settings and settings.Get("general.hunt_enabled"))
        .. " | hunt.preview_enabled=" .. safeValue(settings and settings.Get("hunt.preview_enabled")))
    add("- settings hunt.achievement_signals_enabled="
        .. safeValue(settings and settings.Get("hunt.achievement_signals_enabled"))
        .. " | hunt.achievement_signal_style=" .. safeValue(settings and settings.Get("hunt.achievement_signal_style")))

    local offeredHunts = adapter and type(adapter.GetOfferedHunts) == "function" and adapter.GetOfferedHunts() or {}
    add("- raw offered pins (HuntTableAdapter)=" .. tostring(#offeredHunts))

    local huntList = huntScanner and type(huntScanner.GetHuntList) == "function" and huntScanner.GetHuntList() or {}
    add("- scanned hunt list (HuntScannerRuntime)=" .. tostring(#huntList))

    for i, hunt in ipairs(huntList) do
        -- Routed through HuntScannerRuntime.ResolveZoneDisplayName (not a
        -- direct MapContextAdapter.GetMapInfo call) so this diagnostic shows
        -- the same name the panel/sorting actually use, overrides included.
        local zoneName = huntScanner and type(huntScanner.ResolveZoneDisplayName) == "function"
            and huntScanner.ResolveZoneDisplayName(hunt.zoneMapID)
        local rewardCount = type(hunt.rewardEntries) == "table" and #hunt.rewardEntries or 0
        local achievementNeeds = type(hunt.achievementNeeds) == "table" and hunt.achievementNeeds or {}
        add("  - [" .. i .. "] questID=" .. safeValue(hunt.questID)
            .. " | difficulty=" .. safeValue(hunt.difficulty)
            .. " | zoneMapID=" .. safeValue(hunt.zoneMapID) .. " (" .. safeValue(zoneName) .. ")"
            .. " | rewards=" .. tostring(rewardCount)
            .. " | hasBonusItemReward=" .. safeValue(hunt.hasBonusItemReward)
            .. " | achievementNeeds=" .. tostring(#achievementNeeds))
        for _, need in ipairs(achievementNeeds) do
            add("      * achievementID=" .. safeValue(need.achievementID) .. " | " .. safeValue(need.name))
        end
    end

    return table.concat(lines, "\n")
end

-- New (2026-08-28), built after live debugging needed to know not just
-- whether a sound played but which trigger it was and, when it didn't,
-- why not. Shows the most recent play attempts oldest-first (SoundsRuntime
-- keeps the last 12).
function DiagnosticsRuntime.BuildSoundInspectReport()
    local sounds = Preydator:GetModule("SoundsRuntime")
    local settings = Preydator:GetModule("Settings")

    local lines = {}
    local function add(line) lines[#lines + 1] = tostring(line or "") end

    add("Preydator Sound Inspect | addon=" .. getAddonVersion())
    add("- settings sounds_enabled=" .. safeValue(settings and settings.Get("general.sounds_enabled"))
        .. " | channel=" .. safeValue(settings and settings.Get("sound.channel"))
        .. " | alert_cooldown_seconds=" .. safeValue(settings and settings.Get("sound.alert_cooldown_seconds")))

    local recentPlays = sounds and type(sounds.GetRecentPlays) == "function" and sounds.GetRecentPlays() or {}
    add("- recent play attempts=" .. tostring(#recentPlays) .. " (oldest first)")
    for i, entry in ipairs(recentPlays) do
        add("  - [" .. i .. "] time=" .. string.format("%.3f", entry.time or 0)
            .. " | trigger=" .. safeValue(entry.key)
            .. " | outcome=" .. safeValue(entry.outcome)
            .. " | detail=" .. safeValue(entry.detail)
            .. " | path=" .. safeValue(entry.path))
    end

    return table.concat(lines, "\n")
end

-- New (2026-08-28), built after a real ambush miss produced zero /pd
-- sinspect entries -- sinspect only ever sees actual sound-play attempts,
-- so it's silent for a nameplate that never reached a match at all. This
-- shows the raw nameplate trace instead (AlertsRuntime.GetNameplateTrace,
-- gated on debug.pack_ambush_verbose -- opt-in recording, off by default).
function DiagnosticsRuntime.BuildNameplateTraceReport()
    local alerts = Preydator:GetModule("AlertsRuntime")
    local settings = Preydator:GetModule("Settings")

    local lines = {}
    local function add(line) lines[#lines + 1] = tostring(line or "") end

    add("Preydator Nameplate Trace | addon=" .. getAddonVersion())
    add("- debug.pack_ambush_verbose=" .. safeValue(settings and settings.Get("debug.pack_ambush_verbose")))

    local trace = alerts and type(alerts.GetNameplateTrace) == "function" and alerts.GetNameplateTrace() or {}
    add("- recent nameplates seen during active hunts=" .. tostring(#trace) .. " (oldest first)")
    for i, entry in ipairs(trace) do
        add("  - [" .. i .. "] time=" .. string.format("%.3f", entry.time or 0)
            .. " | name=" .. safeValue(entry.name)
            .. " | " .. safeValue(entry.note))
    end

    return table.concat(lines, "\n")
end

-- Built 2026-09-04 after the product owner reported the default prey icon
-- reappearing "randomly" and too briefly to react to live with /pd
-- pinspect. WidgetAdapter.GetSuppressionTrace() records passively (not
-- opt-in), so this always has the answer by the time anyone thinks to
-- check it, same reasoning as sinspect/ninspect above.
function DiagnosticsRuntime.BuildIconSuppressionInspectReport()
    local widgetAdapter = Preydator:GetModule("WidgetAdapter")
    local settings = Preydator:GetModule("Settings")

    local lines = {}
    local function add(line) lines[#lines + 1] = tostring(line or "") end

    add("Preydator Icon Suppression Inspect | addon=" .. getAddonVersion())
    local iconSetting = settings and settings.Get("general.disable_default_prey_icon")
    add("- settings disable_default_prey_icon=" .. safeValue(iconSetting))

    local trace = widgetAdapter and type(widgetAdapter.GetSuppressionTrace) == "function"
        and widgetAdapter.GetSuppressionTrace() or {}
    add("- recent suppression events=" .. tostring(#trace) .. " (oldest first)")
    for i, entry in ipairs(trace) do
        add("  - [" .. i .. "] time=" .. string.format("%.3f", entry.time or 0)
            .. " | action=" .. safeValue(entry.action)
            .. " | inCombat=" .. safeValue(entry.inCombat)
            .. " | " .. safeValue(entry.detail))
    end

    return table.concat(lines, "\n")
end

Preydator:RegisterModule("DiagnosticsRuntime", DiagnosticsRuntime)
return DiagnosticsRuntime
