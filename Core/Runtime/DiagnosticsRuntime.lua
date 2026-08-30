-- Preydator :: Core/Runtime/DiagnosticsRuntime.lua
-- Author: RagingAltoholic
-- Responsibility: assembles the qinspect/pinspect/inspect reports by reading
-- State, Settings, and Adapters, and returning formatted text for a caller
-- (a future UI/ReportWindow.lua, or chat) to display.
-- Reads: Core/State.lua, Settings, QuestApiAdapter, MapContextAdapter,
-- WidgetAdapter, DiagnosticsAdapter.
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

Preydator:RegisterModule("DiagnosticsRuntime", DiagnosticsRuntime)
return DiagnosticsRuntime
