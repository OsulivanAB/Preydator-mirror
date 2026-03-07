---@diagnostic disable

local ADDON_NAME = ...

local CreateFrame = _G.CreateFrame
local PlaySoundFile = _G.PlaySoundFile
local C_Timer = _G.C_Timer
local ColorPickerFrame = _G.ColorPickerFrame
local OpacitySliderFrame = _G.OpacitySliderFrame
local Enum = _G.Enum
local C_QuestLog = _G["C_QuestLog"]
local C_UIWidgetManager = _G["C_UIWidgetManager"]
local C_TaskQuest = _G["C_TaskQuest"]
local C_Map = _G["C_Map"]
local GetQuestProgressBarPercent = _G.GetQuestProgressBarPercent
local UIParent = _G.UIParent
local GetTime = _G.GetTime
local GetZoneText = _G.GetZoneText
local IsInInstance = _G.IsInInstance
local SlashCmdList = _G["SlashCmdList"]
local Settings = _G["Settings"]
local collectgarbage = _G.collectgarbage
local UIDropDownMenu_Initialize = _G.UIDropDownMenu_Initialize
local UIDropDownMenu_CreateInfo = _G.UIDropDownMenu_CreateInfo
local UIDropDownMenu_SetWidth = _G.UIDropDownMenu_SetWidth
local UIDropDownMenu_SetText = _G.UIDropDownMenu_SetText
local UIDropDownMenu_AddButton = _G.UIDropDownMenu_AddButton

_G.SLASH_PREYDATOR1 = "/preydator"
_G.SLASH_PREYDATOR2 = "/pd"

local PREY_WIDGET_TYPE = 31
local PREY_PROGRESS_FINAL = 3
local MAX_STAGE = 4
local MAX_TICK_MARKS = 3
local WIDGET_SHOWN = 1
-- local IDLE_SOUND_PATH = "Interface\\AddOns\\Preydator\\sounds\\predator-idle.ogg"
local ALERT_SOUND_PATH = "Interface\\AddOns\\Preydator\\sounds\\predator-alert.ogg"
local AMBUSH_SOUND_PATH = "Interface\\AddOns\\Preydator\\sounds\\predator-ambush.ogg"
local TORMENT_SOUND_PATH = "Interface\\AddOns\\Preydator\\sounds\\predator-torment.ogg"
local KILL_SOUND_PATH = "Interface\\AddOns\\Preydator\\sounds\\predator-kill.ogg"
local DEBUG_LOG_LIMIT = 200
local DEFAULT_OUT_OF_ZONE_LABEL = "No Sign in These Fields"
local DEFAULT_AMBUSH_LABEL = "AMBUSH"
local PROGRESS_SEGMENTS_QUARTERS = "quarters"
local PROGRESS_SEGMENTS_THIRDS = "thirds"
local BAR_TICK_PCTS_BY_SEGMENT = {
    [PROGRESS_SEGMENTS_QUARTERS] = { 25, 50, 75 },
    [PROGRESS_SEGMENTS_THIRDS] = { 33, 66 },
}
local PERCENT_DISPLAY_INSIDE = "inside"
local PERCENT_DISPLAY_BELOW_BAR = "below_bar"
local PERCENT_DISPLAY_UNDER_TICKS = "under_ticks"
local PERCENT_DISPLAY_OFF = "off"
local PERCENT_FALLBACK_STAGE = "stage"
local AMBUSH_ALERT_DURATION_SECONDS = 6
local AMBUSH_SOUND_ALERT = "alert"
local AMBUSH_SOUND_AMBUSH = "ambush"
local AMBUSH_SOUND_TORMENT = "torment"
local AMBUSH_SOUND_KILL = "kill"
local SOUND_FOLDER_PREFIX = "Interface\\AddOns\\Preydator\\sounds\\"
local DEFAULT_SOUND_FILENAMES = {
    "predator-alert.ogg",
    "predator-ambush.ogg",
    "predator-torment.ogg",
    "predator-kill.ogg",
}
local PROTECTED_SOUND_FILENAMES = {
    ["predator-alert.ogg"] = true,
    ["predator-ambush.ogg"] = true,
    ["predator-torment.ogg"] = true,
    ["predator-kill.ogg"] = true,
}
local DEFAULT_STAGE_LABELS = {
    [1] = "Scent in the Wind",
    [2] = "Blood in the Shadows",
    [3] = "Echoes of the Kill",
    [4] = "Feast of the Fang",
}
local STAGE_PCT_BY_SEGMENT = {
    [PROGRESS_SEGMENTS_QUARTERS] = {
        [1] = 25,
        [2] = 50,
        [3] = 75,
        [4] = 100,
    },
    [PROGRESS_SEGMENTS_THIRDS] = {
        [1] = 0,
        [2] = 33,
        [3] = 66,
        [4] = 100,
    },
}

local TEXTURE_PRESETS = {
    default = "Interface\\TARGETINGFRAME\\UI-StatusBar",
    flat = "Interface\\Buttons\\WHITE8x8",
    raid = "Interface\\RaidFrame\\Raid-Bar-Hp-Fill",
    classic = "Interface\\PaperDollInfoFrame\\UI-Character-Skills-Bar",
}

local FONT_PRESETS = {
    frizqt = "Fonts\\FRIZQT__.TTF",
    arialn = "Fonts\\ARIALN.TTF",
    skurri = "Fonts\\SKURRI.TTF",
    morpheus = "Fonts\\MORPHEUS.TTF",
}

-- Forward declaration for helpers used before their implementation block.
local NormalizeSoundSettings
local GetSoundPathForKey
local IsValidQuestID

local DEFAULTS = {
    point = { anchor = "CENTER", relativePoint = "CENTER", x = 0, y = -200 },
    width = 260,
    height = 18,
    scale = 1,
    fontSize = 12,
    locked = true,
    forceShowBar = false,
    onlyShowInPreyZone = false,
    fillColor = { 0.85, 0.2, 0.2, 0.95 },
    bgColor = { 0, 0, 0, 0.6 },
    titleColor = { 1, 0.82, 0, 1 },
    percentColor = { 1, 1, 1, 1 },
    textureKey = "default",
    titleFontKey = "frizqt",
    percentFontKey = "frizqt",
    outOfZoneLabel = DEFAULT_OUT_OF_ZONE_LABEL,
    ambushLabel = DEFAULT_AMBUSH_LABEL,
    ambushCustomText = "",
    stageLabels = {
        [1] = DEFAULT_STAGE_LABELS[1],
        [2] = DEFAULT_STAGE_LABELS[2],
        [3] = DEFAULT_STAGE_LABELS[3],
        [4] = DEFAULT_STAGE_LABELS[4],
    },
    stageSounds = {
        [1] = ALERT_SOUND_PATH,
        [2] = AMBUSH_SOUND_PATH,
        [3] = TORMENT_SOUND_PATH,
        [4] = KILL_SOUND_PATH,
    },
    soundsEnabled = true,
    soundChannel = "SFX",
    soundEnhance = 0,
    soundFileNames = {
        "predator-alert.ogg",
        "predator-ambush.ogg",
        "predator-torment.ogg",
        "predator-kill.ogg",
    },
    debugSounds = false,
    ambushSoundEnabled = true,
    ambushVisualEnabled = true,
    ambushSoundPath = KILL_SOUND_PATH,
    showTicks = true,
    progressSegments = PROGRESS_SEGMENTS_QUARTERS,
    percentDisplay = PERCENT_DISPLAY_INSIDE,
    percentFallbackMode = PERCENT_FALLBACK_STAGE,
}

local settings
local debugDB
local Preydator = _G.Preydator or {}
_G.Preydator = Preydator
Preydator.modules = Preydator.modules or {}

function Preydator:RegisterModule(name, module)
    if type(name) ~= "string" or name == "" or type(module) ~= "table" then
        return
    end

    module.name = name
    self.modules[name] = module
end

local frame = CreateFrame("Frame")
local warnedMissingSoundPaths = {}
local barFrame
local barFillContainer
local barFill
local barText
local stageText
local barBorder
local barTickMarks = {}
local barTickLabels = {}
local optionsPanel
local optionsCategoryID
local optionsScrollFrame
local optionsContentFrame
local EnsureOptionsPanel
local candidateWidgetSetIDs = {}
local ExtractWidgetQuestID
local colorPickerSessionCounter = 0
local AddDebugLog
local TryPlaySound
local TryPlayStageSound
local UpdateBarDisplay

local function RunModuleHook(hookName, ...)
    for _, module in pairs(Preydator.modules) do
        local fn = module and module[hookName]
        if type(fn) == "function" then
            pcall(fn, module, ...)
        end
    end
end

local state = {
    activeQuestID = nil,
    progressState = nil,
    progressPercent = nil,
    stageSoundPlayed = {},
    forceShowBar = false,
    killStageUntil = 0,
    stage = 1,
    preyZoneName = nil,
    preyZoneMapID = nil,
    inPreyZone = nil,
    preyTooltipText = nil,
    elapsedSinceUpdate = 0,
    lastWidgetSeenAt = 0,
    lastStateDebugSnapshot = nil,
    lastDisplayPct = 0,
    lastDisplayReason = "init",
    lastPercentSource = "none",
    preyTargetName = nil,
    preyTargetDifficulty = nil,
    ambushAlertUntil = 0,
    lastAmbushSystemMessage = nil,
}

local UPDATE_INTERVAL_SECONDS = 0.5
local INSPECT_VERSION = "v4"

Preydator.GetState = function()
    return state
end

Preydator.GetSettings = function()
    return settings
end

Preydator.GetBarFrame = function()
    return barFrame
end

Preydator.RequestRefresh = function()
    if type(UpdateBarDisplay) == "function" then
        UpdateBarDisplay()
    end
end

local function ApplyDefaults(dst, src)
    for key, value in pairs(src) do
        if type(value) == "table" then
            if type(dst[key]) ~= "table" then
                dst[key] = {}
            end
            ApplyDefaults(dst[key], value)
        elseif dst[key] == nil then
            dst[key] = value
        end
    end
end

local function GetStageLabel(stage)
    if settings and settings.stageLabels and settings.stageLabels[stage] then
        return settings.stageLabels[stage]
    end

    return DEFAULT_STAGE_LABELS[stage] or "Unknown"
end

local function Clamp(value, minValue, maxValue)
    return math.max(minValue, math.min(maxValue, value))
end

local function Round(value)
    if value >= 0 then
        return math.floor(value + 0.5)
    end

    return math.ceil(value - 0.5)
end

local function NormalizeLabelSettings()
    if type(settings.stageLabels) ~= "table" then
        settings.stageLabels = {}
    end

    for stage = 1, MAX_STAGE do
        local label = settings.stageLabels[stage]
        if type(label) ~= "string" or label == "" then
            local legacy = settings.stageLabels[tostring(stage)]
            if type(legacy) == "string" and legacy ~= "" then
                label = legacy
            end
        end

        if type(label) ~= "string" or label == "" then
            label = DEFAULT_STAGE_LABELS[stage]
        end

        settings.stageLabels[stage] = label
    end

    if type(settings.outOfZoneLabel) ~= "string" or settings.outOfZoneLabel == "" then
        settings.outOfZoneLabel = DEFAULT_OUT_OF_ZONE_LABEL
    end

    if type(settings.ambushLabel) ~= "string" or settings.ambushLabel == "" then
        settings.ambushLabel = DEFAULT_AMBUSH_LABEL
    end

    if type(settings.ambushCustomText) ~= "string" then
        settings.ambushCustomText = ""
    end
end

local function NormalizeColorSettings()
    local function normalizeColor(source, fallback)
        local color = type(source) == "table" and source or {}
        local r = Clamp(tonumber(color[1] or color.r) or fallback[1], 0, 1)
        local g = Clamp(tonumber(color[2] or color.g) or fallback[2], 0, 1)
        local b = Clamp(tonumber(color[3] or color.b) or fallback[3], 0, 1)
        local a = Clamp(tonumber(color[4] or color.a) or fallback[4], 0, 1)
        return { r, g, b, a }
    end

    settings.fillColor = normalizeColor(settings.fillColor, DEFAULTS.fillColor)
    settings.bgColor = normalizeColor(settings.bgColor, DEFAULTS.bgColor)
    settings.titleColor = normalizeColor(settings.titleColor, DEFAULTS.titleColor)
    settings.percentColor = normalizeColor(settings.percentColor, DEFAULTS.percentColor)
end

local function NormalizeDisplaySettings()
    settings.showTicks = settings.showTicks ~= false

    local mode = settings.percentDisplay
    if mode == "below" then
        mode = PERCENT_DISPLAY_BELOW_BAR
    end

    if mode ~= PERCENT_DISPLAY_INSIDE and mode ~= PERCENT_DISPLAY_BELOW_BAR and mode ~= PERCENT_DISPLAY_UNDER_TICKS and mode ~= PERCENT_DISPLAY_OFF then
        settings.percentDisplay = PERCENT_DISPLAY_INSIDE
        return
    end

    settings.percentDisplay = mode

    settings.percentFallbackMode = PERCENT_FALLBACK_STAGE
end

local function NormalizeProgressSettings()
    local mode = settings.progressSegments
    if mode ~= PROGRESS_SEGMENTS_QUARTERS and mode ~= PROGRESS_SEGMENTS_THIRDS then
        settings.progressSegments = PROGRESS_SEGMENTS_QUARTERS
        return
    end

    settings.progressSegments = mode
end

local function NormalizeAmbushSettings()
    settings.ambushSoundEnabled = settings.ambushSoundEnabled ~= false
    settings.ambushVisualEnabled = settings.ambushVisualEnabled ~= false

    if type(settings.ambushSoundPath) ~= "string" or settings.ambushSoundPath == "" then
        local legacySoundKey = settings.ambushSoundKey
        settings.ambushSoundPath = GetSoundPathForKey(legacySoundKey, KILL_SOUND_PATH)
    end

    settings.ambushSoundKey = nil
    settings.ambushCustomSoundPath = nil
end

local function GetProgressTickPercents()
    local mode = (settings and settings.progressSegments) or PROGRESS_SEGMENTS_QUARTERS
    local tickPercents = BAR_TICK_PCTS_BY_SEGMENT[mode]
    if type(tickPercents) ~= "table" then
        return BAR_TICK_PCTS_BY_SEGMENT[PROGRESS_SEGMENTS_QUARTERS]
    end

    return tickPercents
end

local function GetStageFallbackPercent(stage)
    local mode = (settings and settings.progressSegments) or PROGRESS_SEGMENTS_QUARTERS
    local stagePercents = STAGE_PCT_BY_SEGMENT[mode] or STAGE_PCT_BY_SEGMENT[PROGRESS_SEGMENTS_QUARTERS]
    return stagePercents[stage] or 0
end

local function GetPreyZoneInfo(questID)
    if not questID then
        return nil, nil
    end

    if not (C_TaskQuest and C_TaskQuest.GetQuestZoneID and C_Map and C_Map.GetMapInfo) then
        return nil, nil
    end

    local mapID = C_TaskQuest.GetQuestZoneID(questID)
    if not mapID then
        return nil, nil
    end

    local mapInfo = C_Map.GetMapInfo(mapID)
    return (mapInfo and mapInfo.name or nil), mapID
end

local function IsPlayerInPreyZone(preyMapID)
    if not preyMapID then
        return nil
    end

    if not (C_Map and C_Map.GetBestMapForUnit and C_Map.GetMapInfo) then
        return nil
    end

    local playerMapID = C_Map.GetBestMapForUnit("player")
    if not playerMapID then
        return nil
    end

    if playerMapID == preyMapID then
        return true
    end

    local guard = 0
    local currentMapID = playerMapID
    while currentMapID and guard < 20 do
        local mapInfo = C_Map.GetMapInfo(currentMapID)
        if not mapInfo then
            break
        end

        if mapInfo.parentMapID == preyMapID then
            return true
        end

        currentMapID = mapInfo.parentMapID
        guard = guard + 1
    end

    return false
end

local function GetDefaultStageSoundPath(stage)
    if stage == 1 then
        return ALERT_SOUND_PATH
    end
    if stage == 2 then
        return AMBUSH_SOUND_PATH
    end
    if stage == 3 then
        return TORMENT_SOUND_PATH
    end
    if stage == 4 then
        return KILL_SOUND_PATH
    end

    return nil
end

local function BuildAddonSoundPath(fileName)
    if type(fileName) ~= "string" then
        return nil
    end

    local trimmed = fileName:match("^%s*(.-)%s*$")
    if trimmed == "" then
        return nil
    end

    if string.find(trimmed, "\\", 1, true) then
        return trimmed
    end

    return SOUND_FOLDER_PREFIX .. trimmed
end

local function ExtractAddonSoundFileName(path)
    if type(path) ~= "string" or path == "" then
        return nil
    end

    local lower = string.lower(path)
    local prefixLower = string.lower(SOUND_FOLDER_PREFIX)
    if string.sub(lower, 1, #prefixLower) ~= prefixLower then
        return nil
    end

    local fileName = string.sub(path, #SOUND_FOLDER_PREFIX + 1)
    if fileName == "" then
        return nil
    end

    return fileName
end

local function NormalizeSoundFileName(fileName)
    if type(fileName) ~= "string" then
        return nil
    end

    local normalized = string.lower(fileName:match("^%s*(.-)%s*$") or "")
    if normalized == "" then
        return nil
    end

    local prefixLower = string.lower(SOUND_FOLDER_PREFIX)
    if string.sub(normalized, 1, #prefixLower) == prefixLower then
        normalized = string.sub(normalized, #prefixLower + 1)
    end

    if normalized == "" then
        return nil
    end

    if normalized:find("[/\\]") then
        return nil
    end

    if not normalized:match("%.ogg$") then
        normalized = normalized .. ".ogg"
    end

    return normalized
end

local function AddSoundFileName(fileName)
    local normalized = NormalizeSoundFileName(fileName)
    if not normalized then
        return false, "Use a valid sound filename (optionally with .ogg)"
    end

    settings.soundFileNames = settings.soundFileNames or {}
    for _, existing in ipairs(settings.soundFileNames) do
        if NormalizeSoundFileName(existing) == normalized then
            return false, "File is already in the list"
        end
    end

    table.insert(settings.soundFileNames, normalized)
    NormalizeSoundSettings()
    return true, normalized
end

local function RemoveSoundFileName(fileName)
    local normalized = NormalizeSoundFileName(fileName)
    if not normalized then
        return false, "Use a valid sound filename (optionally with .ogg)"
    end

    if PROTECTED_SOUND_FILENAMES[normalized] then
        return false, "Default sound files cannot be removed"
    end

    settings.soundFileNames = settings.soundFileNames or {}
    local removed = false
    for index = #settings.soundFileNames, 1, -1 do
        local existing = NormalizeSoundFileName(settings.soundFileNames[index])
        if existing == normalized then
            table.remove(settings.soundFileNames, index)
            removed = true
            break
        end
    end

    if not removed then
        local rawInput = string.lower((tostring(fileName or ""):match("^%s*(.-)%s*$") or ""))
        local candidates = {}

        if rawInput ~= "" then
            for index = #settings.soundFileNames, 1, -1 do
                local existing = NormalizeSoundFileName(settings.soundFileNames[index])
                if existing then
                    local existingNoExt = existing:gsub("%.ogg$", "")
                    if rawInput == existing
                        or rawInput == existingNoExt
                        or string.sub(existingNoExt, -#rawInput) == rawInput
                    then
                        table.insert(candidates, { index = index, name = existing })
                    end
                end
            end
        end

        if #candidates == 1 then
            table.remove(settings.soundFileNames, candidates[1].index)
            removed = true
            normalized = candidates[1].name
        elseif #candidates > 1 then
            return false, "Multiple matches found. Type more of the file name."
        end
    end

    if not removed then
        return false, "File is not in the custom list"
    end

    NormalizeSoundSettings()
    return true, normalized
end

GetSoundPathForKey = function(soundKey, fallbackPath)
    if soundKey == AMBUSH_SOUND_ALERT then
        return ALERT_SOUND_PATH
    end
    if soundKey == AMBUSH_SOUND_AMBUSH then
        return AMBUSH_SOUND_PATH
    end
    if soundKey == AMBUSH_SOUND_TORMENT then
        return TORMENT_SOUND_PATH
    end
    if soundKey == AMBUSH_SOUND_KILL then
        return KILL_SOUND_PATH
    end
    return fallbackPath
end

local function BuildSoundDisplayName(fileName)
    local short = tostring(fileName or "")
    short = short:gsub("%.ogg$", "")
    short = short:gsub("[_%-]+", " ")
    short = short:gsub("%s+", " ")
    short = short:gsub("^%l", string.upper)
    short = short:gsub("%s%l", function(s)
        return string.upper(s)
    end)
    return short
end

local function BuildSoundDropdownOptions()
    local options = {}
    local files = (settings and settings.soundFileNames) or DEFAULT_SOUND_FILENAMES

    for _, fileName in ipairs(files) do
        local normalized = NormalizeSoundFileName(fileName)
        if normalized then
            local path = BuildAddonSoundPath(normalized)
            options[path] = {
                text = BuildSoundDisplayName(normalized),
            }
        end
    end

    return options
end

local function ResolveAmbushAlertSoundPath()
    local path = settings and settings.ambushSoundPath
    if type(path) == "string" and path ~= "" then
        return path
    end

    return KILL_SOUND_PATH
end

local function GetWidgetTypePreyHuntProgress()
    if Enum and Enum.UIWidgetVisualizationType and Enum.UIWidgetVisualizationType.PreyHuntProgress then
        return Enum.UIWidgetVisualizationType.PreyHuntProgress
    end

    return PREY_WIDGET_TYPE
end

local function GetShownStateShown()
    if Enum and Enum.WidgetShownState and Enum.WidgetShownState.Shown then
        return Enum.WidgetShownState.Shown
    end

    return WIDGET_SHOWN
end

local function GetCurrentActivePreyQuest()
    if C_QuestLog and C_QuestLog.GetActivePreyQuest then
        return C_QuestLog.GetActivePreyQuest()
    end

    return nil
end

local function GetQuestTitle(questID)
    if not (C_QuestLog and C_QuestLog.GetTitleForQuestID) then
        return nil
    end

    local titleInfo = C_QuestLog.GetTitleForQuestID(questID)
    if type(titleInfo) == "table" then
        return titleInfo.title
    end

    return titleInfo
end

local function ExtractPreyTargetFromQuestTitle(questID)
    if type(questID) ~= "number" or questID < 1 then
        return nil, nil
    end

    local title = GetQuestTitle(questID)
    if type(title) ~= "string" or title == "" then
        return nil, nil
    end

    local preyName, difficulty = title:match("^%s*[Pp]rey:%s*(.-)%s*%((.-)%)%s*$")
    if preyName and preyName ~= "" then
        return preyName, difficulty
    end

    preyName = title:match("^%s*[Pp]rey:%s*(.-)%s*$")
    if preyName and preyName ~= "" then
        return preyName, nil
    end

    return nil, nil
end

local function StringContainsInsensitiveSafe(haystack, needle)
    if type(haystack) ~= "string" or type(needle) ~= "string" or needle == "" then
        return false
    end

    local ok, found = pcall(function()
        local haystackLower = string.lower(haystack)
        local needleLower = string.lower(needle)
        return string.find(haystackLower, needleLower, 1, true) ~= nil
    end)

    return ok and found or false
end

local function IsAmbushSystemMessage(message, sender)
    if type(message) ~= "string" then
        return false
    end

    if StringContainsInsensitiveSafe(message, "ambush") then
        return true
    end

    local preyName = state and state.preyTargetName
    if type(preyName) == "string" and preyName ~= "" then
        if StringContainsInsensitiveSafe(message, preyName) or StringContainsInsensitiveSafe(sender, preyName) then
            return true
        end
    end

    return false
end

local function ShouldScanAmbushChat()
    if not state or not IsValidQuestID(state.activeQuestID) then
        return false
    end

    if not IsInInstance then
        return true
    end

    local ok, inInstance, instanceType = pcall(IsInInstance)
    if not ok or not inInstance then
        return true
    end

    return instanceType ~= "party"
        and instanceType ~= "raid"
        and instanceType ~= "scenario"
        and instanceType ~= "delve"
end

local function TriggerAmbushAlert(message, source)
    local now = GetTime and GetTime() or 0
    state.lastAmbushSystemMessage = message

    if settings.ambushVisualEnabled ~= false then
        state.ambushAlertUntil = now + AMBUSH_ALERT_DURATION_SECONDS
    end

    if settings.ambushSoundEnabled ~= false then
        local ambushPath = ResolveAmbushAlertSoundPath()
        TryPlaySound(ambushPath)
    end

    AddDebugLog("Ambush", "Detected from " .. tostring(source) .. ": " .. tostring(message), true)
    UpdateBarDisplay()
end

local function IsQuestStillActive(questID)
    if not questID or questID < 1 then
        return false
    end

    if C_QuestLog and C_QuestLog.IsOnQuest then
        return C_QuestLog.IsOnQuest(questID) and true or false
    end

    return true
end

IsValidQuestID = function(questID)
    return type(questID) == "number" and questID > 0
end

local function EnsureDebugDB()
    _G.PreydatorDebugDB = _G.PreydatorDebugDB or {}
    debugDB = _G.PreydatorDebugDB
    if type(debugDB.entries) ~= "table" then
        debugDB.entries = {}
    end
    if debugDB.enabled == nil then
        debugDB.enabled = true
    end
end

AddDebugLog = function(kind, message, forcePrint)
    if not debugDB then
        return
    end

    if not debugDB.enabled then
        return
    end

    local now = GetTime and GetTime() or 0
    local entry = string.format("%0.3f | %s | %s", now, tostring(kind or "?"), tostring(message or ""))
    table.insert(debugDB.entries, entry)

    while #debugDB.entries > DEBUG_LOG_LIMIT do
        table.remove(debugDB.entries, 1)
    end

    if forcePrint then
        print("Preydator DEBUG: " .. entry)
    end
end

TryPlaySound = function(path, ignoreSoundToggle)
    if not ignoreSoundToggle and settings and settings.soundsEnabled == false then
        AddDebugLog("TryPlaySound", "blocked by soundsEnabled=false | path=" .. tostring(path), false)
        return false
    end

    local channel = (settings and settings.soundChannel) or "SFX"
    local willPlay = PlaySoundFile(path, channel)
    AddDebugLog("TryPlaySound", "path=" .. tostring(path) .. " | channel=" .. tostring(channel) .. " | ignoreToggle=" .. tostring(ignoreSoundToggle) .. " | result=" .. tostring(willPlay), false)
    if willPlay then
        local enhance = (settings and tonumber(settings.soundEnhance)) or 0
        if enhance > 0 and C_Timer and C_Timer.After then
            local extraPlays = math.min(4, math.max(0, math.floor(enhance / 25)))
            for i = 1, extraPlays do
                local delay = i * 0.03
                C_Timer.After(delay, function()
                    PlaySoundFile(path, channel)
                end)
            end
            if extraPlays > 0 then
                AddDebugLog("TryPlaySound", "enhance=" .. tostring(enhance) .. " | extraPlays=" .. tostring(extraPlays), false)
            end
        end
        return true
    end

    local warnedKey = tostring(path or "")
    if warnedMissingSoundPaths[warnedKey] ~= true then
        warnedMissingSoundPaths[warnedKey] = true
        print("Preydator: Sound failed to play: '" .. warnedKey .. "'. Ensure the .ogg exists in Interface\\AddOns\\Preydator\\sounds\\ and is listed in Custom Sound Files.")
    end

    return false
end

local function ResolveStageSoundPath(stage)
    stage = tonumber(stage)
    if not stage then
        AddDebugLog("ResolveStageSoundPath", "invalid stage", false)
        return nil
    end

    local defaultPath = GetDefaultStageSoundPath(stage)

    if not settings then
        return defaultPath
    end

    settings.stageSounds = settings.stageSounds or {}
    local sounds = settings.stageSounds

    local savedPath = sounds[stage]
    if type(savedPath) == "string" and savedPath ~= "" then
        AddDebugLog("ResolveStageSoundPath", "stage=" .. stage .. " | source=saved | path=" .. savedPath, false)
        return savedPath
    end

    if defaultPath and defaultPath ~= "" then
        sounds[stage] = defaultPath
        AddDebugLog("ResolveStageSoundPath", "stage=" .. stage .. " | source=default | path=" .. defaultPath, false)
        return defaultPath
    end

    AddDebugLog("ResolveStageSoundPath", "stage=" .. stage .. " | source=none | default=nil", true)

    return nil
end

TryPlayStageSound = function(stage, ignoreSoundToggle)
    local path = ResolveStageSoundPath(stage)
    if not path then
        AddDebugLog("TryPlayStageSound", "stage=" .. tostring(stage) .. " | no resolved path", true)
        return false
    end

    if state.stageSoundPlayed[stage] then
        AddDebugLog("TryPlayStageSound", "stage=" .. tostring(stage) .. " | skipped already played", false)
        return false
    end

    if TryPlaySound(path, ignoreSoundToggle) then
        state.stageSoundPlayed[stage] = true
        AddDebugLog("TryPlayStageSound", "stage=" .. tostring(stage) .. " | success", false)
        return true
    end

    if stage == MAX_STAGE then
        local fallbackPath = ResolveStageSoundPath(MAX_STAGE - 1)
        if fallbackPath then
            AddDebugLog("TryPlayStageSound", "stage=" .. tostring(MAX_STAGE) .. " | primary failed, trying fallback stage=" .. tostring(MAX_STAGE - 1) .. " | path=" .. tostring(fallbackPath), true)
            if TryPlaySound(fallbackPath, ignoreSoundToggle) then
                state.stageSoundPlayed[stage] = true
                AddDebugLog("TryPlayStageSound", "stage=" .. tostring(MAX_STAGE) .. " | fallback stage=" .. tostring(MAX_STAGE - 1) .. " success", true)
                return true
            end
            AddDebugLog("TryPlayStageSound", "stage=" .. tostring(MAX_STAGE) .. " | fallback stage=" .. tostring(MAX_STAGE - 1) .. " also failed", true)
        end
    end

    local channel = (settings and settings.soundChannel) or "SFX"
    AddDebugLog("TryPlayStageSound", "stage=" .. tostring(stage) .. " | path=" .. tostring(path) .. " | channel=" .. tostring(channel) .. " | PlaySoundFile returned false", true)

    return false
end

local function ApplyBarSettings()
    if not barFrame then
        return
    end

    settings.point = settings.point or {}
    local point = settings.point
    local anchor = string.upper(tostring(point.anchor or DEFAULTS.point.anchor))
    local relativePoint = string.upper(tostring(point.relativePoint or DEFAULTS.point.relativePoint))
    local frameScale = Clamp(tonumber(settings.scale) or DEFAULTS.scale, 0.5, 2)
    local scaledWidth = math.max(160, Round((tonumber(settings.width) or DEFAULTS.width) * frameScale))
    local scaledHeight = math.max(10, Round((tonumber(settings.height) or DEFAULTS.height) * frameScale))
    if anchor ~= "CENTER" then
        anchor = "CENTER"
    end

    if relativePoint ~= "CENTER" then
        relativePoint = "CENTER"
    end

    point.x = Round(tonumber(point.x) or DEFAULTS.point.x)
    point.y = Round(tonumber(point.y) or DEFAULTS.point.y)
    point.anchor = anchor
    point.relativePoint = relativePoint

    settings.scale = frameScale

    barFrame:SetSize(scaledWidth, scaledHeight)
    barFrame:SetScale(1)
    barFrame:ClearAllPoints()
    barFrame:SetPoint("CENTER", UIParent, "CENTER", point.x, point.y)

    if barFill then
        local fill = settings.fillColor
        barFill:ClearAllPoints()
        barFill:SetPoint("left", barFrame, "left", 0, 0)
        barFill:SetSize(0, scaledHeight)
        barFill:SetTexture(TEXTURE_PRESETS[settings.textureKey] or TEXTURE_PRESETS.default)
        barFill:SetVertexColor(fill[1], fill[2], fill[3], fill[4])
        barFill:SetDrawLayer("ARTWORK", 0)

        if barBorder and barBorder.SetBackdropBorderColor then
            barBorder:SetBackdropBorderColor(fill[1], fill[2], fill[3], math.max(0.65, fill[4] or 0.85))
        end
    end

    if barFrame.BackgroundTexture then
        local bg = settings.bgColor
        barFrame.BackgroundTexture:SetColorTexture(bg[1], bg[2], bg[3], bg[4])
    end

    if stageText then
        local _, _, flags = stageText:GetFont()
        local titleFont = FONT_PRESETS[settings.titleFontKey] or FONT_PRESETS.frizqt
        stageText:SetFont(titleFont, math.max(8, Round((tonumber(settings.fontSize) or DEFAULTS.fontSize) * frameScale)), flags)
        local titleColor = settings.titleColor or DEFAULTS.titleColor
        stageText:SetTextColor(titleColor[1], titleColor[2], titleColor[3], titleColor[4] or 1)
    end

    if barText then
        local _, _, flags = barText:GetFont()
        local percentFont = FONT_PRESETS[settings.percentFontKey] or FONT_PRESETS.frizqt
        barText:SetFont(percentFont, math.max(8, Round(((tonumber(settings.fontSize) or DEFAULTS.fontSize) - 1) * frameScale)), flags)
        local percentColor = settings.percentColor or DEFAULTS.percentColor
        barText:SetTextColor(percentColor[1], percentColor[2], percentColor[3], percentColor[4] or 1)
        barText:SetDrawLayer("OVERLAY", 7)
    end

    local tickPercents = GetProgressTickPercents()
    for index, tickLabel in ipairs(barTickLabels) do
        local hasTick = tickPercents[index] ~= nil
        if tickLabel then
            local _, _, flags = tickLabel:GetFont()
            local percentFont = FONT_PRESETS[settings.percentFontKey] or FONT_PRESETS.frizqt
            tickLabel:SetFont(percentFont, math.max(7, Round(((tonumber(settings.fontSize) or DEFAULTS.fontSize) - 4) * frameScale)), flags)
            local percentColor = settings.percentColor or DEFAULTS.percentColor
            tickLabel:SetTextColor(percentColor[1], percentColor[2], percentColor[3], 0.9)
            tickLabel:SetShown(hasTick and settings.showTicks and settings.percentDisplay == PERCENT_DISPLAY_UNDER_TICKS)
        end

        local tickMark = barTickMarks[index]
        if tickMark then
            tickMark:SetColorTexture(1, 1, 1, 0.35)
            tickMark:SetDrawLayer("OVERLAY", 4)
            tickMark:SetShown(hasTick and settings.showTicks)
        end
    end

    local barWidth = scaledWidth
    local barHeight = scaledHeight
    local tickWidth = 1
    for index = 1, MAX_TICK_MARKS do
        local pct = tickPercents[index]
        local x = nil
        if pct then
            x = math.floor((barWidth * (pct / 100)) + 0.5)
            x = math.floor((x / tickWidth) + 0.5) * tickWidth
        end
        local tickMark = barTickMarks[index]
        if tickMark then
            if pct then
                tickMark:ClearAllPoints()
                if pct == 100 then
                    tickMark:SetPoint("BOTTOMLEFT", barFrame, "BOTTOMLEFT", barWidth - tickWidth, 0)
                else
                    tickMark:SetPoint("BOTTOMLEFT", barFrame, "BOTTOMLEFT", x, 0)
                end
                tickMark:SetSize(tickWidth, barHeight)
            else
                tickMark:Hide()
            end
        end

        local tickLabel = barTickLabels[index]
        if tickLabel then
            if pct then
                tickLabel:ClearAllPoints()
                if pct == 0 then
                    tickLabel:SetPoint("TOPLEFT", barFrame, "BOTTOMLEFT", 0, -1)
                elseif pct == 100 then
                    tickLabel:SetPoint("TOPRIGHT", barFrame, "BOTTOMRIGHT", 0, -1)
                else
                    tickLabel:SetPoint("TOP", barFrame, "BOTTOMLEFT", x, -1)
                end
                tickLabel:SetText(tostring(pct))
                tickLabel:SetDrawLayer("OVERLAY", 8)
            else
                tickLabel:SetText("")
                tickLabel:Hide()
            end
        end
    end

    if barText then
        if settings.percentDisplay == PERCENT_DISPLAY_OFF then
            barText:Hide()
        elseif settings.percentDisplay == PERCENT_DISPLAY_BELOW_BAR then
            barText:Show()
            barText:ClearAllPoints()
            barText:SetPoint("TOP", barFrame, "BOTTOM", 0, -14)
        elseif settings.percentDisplay == PERCENT_DISPLAY_UNDER_TICKS then
            barText:Hide()
        else
            barText:Show()
            barText:ClearAllPoints()
            barText:SetPoint("center", barFrame, "center", 0, 0)
        end
    end

    barFrame:SetMovable(true)
    barFrame:EnableMouse(not settings.locked)
end

local function EnsureBar()
    if barFrame then
        return
    end

    local createdBar = CreateFrame("Frame", "PreydatorProgressBar", UIParent)
    if not createdBar then
        return
    end

    createdBar:SetSize(260, 18)
    createdBar:SetPoint("CENTER", UIParent, "CENTER", 0, -220)
    createdBar:Hide()
    createdBar:SetClampedToScreen(false)
    barFrame = createdBar

    barFrame:SetScript("OnMouseDown", function(self, button)
        if button == "LeftButton" and settings and not settings.locked then
            self:StartMoving()
        end
    end)

    barFrame:SetScript("OnMouseUp", function(self)
        self:StopMovingOrSizing()
        settings.point.anchor = "CENTER"
        settings.point.relativePoint = "CENTER"

        local frameCenterX, frameCenterY = self:GetCenter()
        local parentCenterX, parentCenterY = UIParent:GetCenter()
        if frameCenterX and frameCenterY and parentCenterX and parentCenterY then
            settings.point.x = Round(frameCenterX - parentCenterX)
            settings.point.y = Round(frameCenterY - parentCenterY)
            return
        end

        local _, _, _, x, y = self:GetPoint(1)
        settings.point.x = Round(tonumber(x) or DEFAULTS.point.x)
        settings.point.y = Round(tonumber(y) or DEFAULTS.point.y)
    end)

    local bg = barFrame:CreateTexture(nil, "background")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.6)
    barFrame.BackgroundTexture = bg

    barFillContainer = CreateFrame("Frame", nil, barFrame)
    barFillContainer:SetAllPoints()
    barFillContainer:SetClipsChildren(true)

    barFill = barFillContainer:CreateTexture(nil, "artwork")
    barFill:SetPoint("left", barFillContainer, "left", 0, 0)
    barFill:SetSize(0, 18)
    barFill:SetTexCoord(0, 1, 0, 1)
    barFill:SetHorizTile(false)
    barFill:SetVertTile(false)
    barFill:SetColorTexture(0.85, 0.2, 0.2, 0.95)

    local border = CreateFrame("Frame", nil, barFrame, "BackdropTemplate")
    border:SetAllPoints()
    border:SetBackdrop({
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 12,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    border:SetBackdropBorderColor(0.8, 0.2, 0.2, 0.85)
    barBorder = border

    stageText = barFrame:CreateFontString(nil, "overlay", "GameFontNormal")
    stageText:SetPoint("BOTTOM", barFrame, "TOP", 0, 4)
    stageText:SetJustifyH("CENTER")
    stageText:SetText("Preydator")

    barText = barFrame:CreateFontString(nil, "overlay", "GameFontHighlightSmall")
    barText:SetPoint("center", barFrame, "center", 0, 0)
    barText:SetDrawLayer("OVERLAY", 9)
    barText:SetText("0%")

    for index = 1, MAX_TICK_MARKS do
        local pct = (index * 25)
        local tickMark = barFrame:CreateTexture(nil, "overlay")
        tickMark:SetColorTexture(1, 1, 1, 0.35)
        tickMark:SetDrawLayer("OVERLAY", 4)
        barTickMarks[index] = tickMark

        local tickLabel = barFrame:CreateFontString(nil, "overlay", "GameFontHighlightSmall")
        tickLabel:SetDrawLayer("OVERLAY", 8)
        tickLabel:SetText(tostring(pct))
        barTickLabels[index] = tickLabel
    end

    ApplyBarSettings()
end

local function GetStageFromState(progressState)
    if progressState == nil then
        return 1
    end

    if progressState == 0 then
        return 1
    end

    if progressState == 1 then
        return 2
    end

    if progressState == 2 then
        return 3
    end

    if progressState == PREY_PROGRESS_FINAL then
        return 4
    end

    return 1
end

local function ClampPercent(value)
    return Clamp(value, 0, 100)
end

local function NormalizePercentCandidate(value)
    if type(value) ~= "number" then
        return nil
    end

    if value >= 0 and value <= 1 then
        return ClampPercent(value * 100)
    end

    return ClampPercent(value)
end

local function ExtractProgressPercentFromInfoScan(info)
    if type(info) ~= "table" then
        return nil
    end

    for key, value in pairs(info) do
        if type(value) == "number" then
            local keyText = string.lower(tostring(key))
            if string.find(keyText, "percent", 1, true) then
                local pct = NormalizePercentCandidate(value)
                if pct ~= nil then
                    return pct
                end
            end
        end
    end

    local currentValues = {}
    local maxValues = {}
    for key, value in pairs(info) do
        if type(value) == "number" and value >= 0 then
            local keyText = string.lower(tostring(key))
            if string.find(keyText, "current", 1, true)
                or string.find(keyText, "value", 1, true)
                or string.find(keyText, "progress", 1, true)
                or string.find(keyText, "fulfilled", 1, true)
                or string.find(keyText, "completed", 1, true)
            then
                currentValues[#currentValues + 1] = value
            end

            if string.find(keyText, "max", 1, true)
                or string.find(keyText, "total", 1, true)
                or string.find(keyText, "required", 1, true)
            then
                maxValues[#maxValues + 1] = value
            end
        end
    end

    for _, current in ipairs(currentValues) do
        for _, maxValue in ipairs(maxValues) do
            if maxValue > 0 and current <= maxValue then
                local pct = ClampPercent((current / maxValue) * 100)
                if pct >= 0 and pct <= 100 then
                    return pct
                end
            end
        end
    end

    return nil
end

local function SummarizeInfoFields(info)
    if type(info) ~= "table" then
        return ""
    end

    local parts = {}
    local count = 0
    for key, value in pairs(info) do
        if key ~= "tooltip" and (type(value) == "number" or type(value) == "string" or type(value) == "boolean") then
            count = count + 1
            if count > 10 then
                parts[#parts + 1] = "..."
                break
            end
            parts[#parts + 1] = tostring(key) .. "=" .. tostring(value)
        end
    end

    return table.concat(parts, ", ")
end

local function ExtractProgressPercent(info, tooltipText)
    if type(info) == "table" then
        local directFields = {
            "progressPercentage",
            "progressPercent",
            "fillPercentage",
            "percentage",
            "percent",
            "progress",
            "progressValue",
        }

        for _, fieldName in ipairs(directFields) do
            local pct = NormalizePercentCandidate(info[fieldName])
            if pct ~= nil then
                return pct
            end
        end

        local valueFields = { "barValue", "value", "currentValue" }
        local maxFields = { "barMax", "maxValue", "totalValue", "total", "max" }
        for _, valueField in ipairs(valueFields) do
            local current = info[valueField]
            if type(current) == "number" then
                for _, maxField in ipairs(maxFields) do
                    local maxValue = info[maxField]
                    if type(maxValue) == "number" and maxValue > 0 then
                        return ClampPercent((current / maxValue) * 100)
                    end
                end
            end
        end
    end

    local scannedPct = ExtractProgressPercentFromInfoScan(info)
    if scannedPct ~= nil then
        return scannedPct
    end

    if type(tooltipText) == "string" then
        local pctText = tooltipText:match("(%d+)%s*%%")
        local pctValue = tonumber(pctText)
        if pctValue then
            return ClampPercent(pctValue)
        end
    end

    return nil
end

local function ExtractQuestObjectivePercent(questID)
    if not IsValidQuestID(questID) then
        return nil
    end

    local questBarPct = nil
    if GetQuestProgressBarPercent then
        local rawQuestBarPct = tonumber(GetQuestProgressBarPercent(questID))
        if rawQuestBarPct ~= nil then
            questBarPct = ClampPercent(rawQuestBarPct)
        end
    end

    if not (C_QuestLog and C_QuestLog.GetQuestObjectives) then
        return nil
    end

    local objectives = C_QuestLog.GetQuestObjectives(questID)
    if type(objectives) ~= "table" or #objectives == 0 then
        return nil
    end

    local totalFulfilled = 0
    local totalRequired = 0
    local anyNumericObjective = false

    for _, objective in ipairs(objectives) do
        if type(objective) == "table" then
            local fulfilled = tonumber(objective.numFulfilled)
            local required = tonumber(objective.numRequired)

            if fulfilled == nil then
                fulfilled = tonumber(objective.fulfilled)
            end
            if required == nil then
                required = tonumber(objective.required)
            end

            if fulfilled ~= nil and required == nil and objective.finished ~= nil then
                required = 1
                fulfilled = objective.finished and 1 or math.max(0, fulfilled)
            end

            if fulfilled and required and required > 0 then
                anyNumericObjective = true
                totalFulfilled = totalFulfilled + math.max(0, fulfilled)
                totalRequired = totalRequired + math.max(0, required)
            else
                local text = objective.text
                if type(text) == "string" and text ~= "" then
                    local curText, maxText = text:match("(%d+)%s*/%s*(%d+)")
                    local curValue = tonumber(curText)
                    local maxValue = tonumber(maxText)
                    if curValue and maxValue and maxValue > 0 then
                        anyNumericObjective = true
                        totalFulfilled = totalFulfilled + math.max(0, curValue)
                        totalRequired = totalRequired + math.max(0, maxValue)
                    else
                        local pctText = text:match("(%d+)%s*%%")
                        local pctValue = tonumber(pctText)
                        if pctValue then
                            return ClampPercent(pctValue)
                        end
                    end
                end
            end
        end
    end

    local objectivePct = nil
    if anyNumericObjective and totalRequired > 0 then
        objectivePct = ClampPercent((totalFulfilled / totalRequired) * 100)
    end

    if objectivePct ~= nil and questBarPct ~= nil then
        return math.max(objectivePct, questBarPct)
    end

    if objectivePct ~= nil then
        return objectivePct
    end

    if questBarPct ~= nil then
        return questBarPct
    end

    return nil
end

UpdateBarDisplay = function()
    EnsureBar()

    local now = GetTime and GetTime() or 0
    local hasActiveQuest = state.activeQuestID ~= nil
    local forceKillStage = now < (state.killStageUntil or 0)
    local forceAmbushAlert = now < (state.ambushAlertUntil or 0)
    local isOutOfPreyZone = hasActiveQuest and state.inPreyZone ~= true
    local onlyShowInPreyZone = settings.onlyShowInPreyZone == true
    local shouldShow = false

    if state.forceShowBar or forceKillStage or forceAmbushAlert then
        shouldShow = true
    elseif onlyShowInPreyZone then
        shouldShow = hasActiveQuest and not isOutOfPreyZone
    else
        shouldShow = true
    end

    if not shouldShow then
        barFrame:Hide()
        RunModuleHook("OnAfterUpdateBarDisplay", {
            shouldShowBar = false,
            forceAmbushAlert = forceAmbushAlert,
            forceKillStage = forceKillStage,
            hasActiveQuest = hasActiveQuest,
            displayPercent = 0,
            stage = state.stage,
        })
        return
    end

    barFrame:Show()

    local stage = forceKillStage and MAX_STAGE or GetStageFromState(state.progressState)
    local pct = 0
    local displayReason = "default"
    if forceKillStage then
        pct = 100
        displayReason = "killStage"
    elseif not hasActiveQuest then
        pct = 0
        displayReason = "noActiveQuest"
    elseif isOutOfPreyZone then
        pct = 0
        displayReason = "outOfPreyZone"
    else
        if stage == MAX_STAGE then
            pct = 100
            if state.lastPercentSource == "none" then
                state.lastPercentSource = "final"
            end
        else
            pct = state.progressPercent
            local shouldUseStageFallback = (pct == nil) or (stage >= 1 and pct <= 0)

            if shouldUseStageFallback then
                pct = GetStageFallbackPercent(stage)
                if state.lastPercentSource == "none" then
                    state.lastPercentSource = "stage"
                end
            end
        end
        displayReason = "activeQuest"
    end
    local label = GetStageLabel(stage)
    local barWidth = (barFrame and barFrame.GetWidth and barFrame:GetWidth()) or settings.width

    if barFill then
        local width = barWidth * (pct / 100)
        local shouldHideFill = (pct <= 0) or (not hasActiveQuest and not forceKillStage and not forceAmbushAlert)
        if shouldHideFill then
            barFill:SetWidth(0)
            barFill:Hide()
        else
            barFill:SetWidth(math.max(1, width))
            barFill:Show()
        end
    end

    state.lastDisplayPct = pct
    state.lastDisplayReason = displayReason

    state.stage = stage

    if forceAmbushAlert then
        local customAmbushText = settings and settings.ambushCustomText
        if type(customAmbushText) == "string" and customAmbushText ~= "" then
            stageText:SetText(customAmbushText)
        else
            local ambushSuffix = (settings and settings.ambushLabel) or DEFAULT_AMBUSH_LABEL
            if type(state.preyTargetName) == "string" and state.preyTargetName ~= "" then
                stageText:SetText(ambushSuffix .. ": " .. state.preyTargetName)
            else
                stageText:SetText(ambushSuffix)
            end
        end
    elseif isOutOfPreyZone and not forceKillStage then
        stageText:SetText(settings.outOfZoneLabel or DEFAULT_OUT_OF_ZONE_LABEL)
    elseif not hasActiveQuest and not forceKillStage then
        local zoneName = GetZoneText and GetZoneText() or "Unknown Zone"
        stageText:SetText(zoneName)
    else
        stageText:SetText(label)
    end

    barText:SetText(string.format("%d%%", pct))

    RunModuleHook("OnAfterUpdateBarDisplay", {
        shouldShowBar = true,
        forceAmbushAlert = forceAmbushAlert,
        forceKillStage = forceKillStage,
        hasActiveQuest = hasActiveQuest,
        displayPercent = pct,
        stage = stage,
    })
end

local function OpenOptionsPanel()
    EnsureOptionsPanel()

    if Settings and Settings.OpenToCategory then
        if type(optionsCategoryID) == "number" then
            Settings.OpenToCategory(optionsCategoryID)
            return
        end

        if optionsPanel and type(optionsPanel.categoryID) == "number" then
            Settings.OpenToCategory(optionsPanel.categoryID)
            return
        end
    end

    if _G.InterfaceOptionsFrame_OpenToCategory then
        _G.InterfaceOptionsFrame_OpenToCategory("Preydator")
    end
end

local function ClearPreyStateAndDisplay()
    state.activeQuestID = nil
    state.progressState = nil
    state.progressPercent = 0
    state.preyZoneName = nil
    state.preyZoneMapID = nil
    state.inPreyZone = nil
    state.preyTooltipText = nil
    state.stage = 1
    state.killStageUntil = 0
    state.lastWidgetSeenAt = 0
    state.stageSoundPlayed = {}
    state.lastStateDebugSnapshot = nil
    state.preyTargetName = nil
    state.preyTargetDifficulty = nil
    state.ambushAlertUntil = 0
    state.lastAmbushSystemMessage = nil

    if barFill then
        barFill:SetWidth(0)
    end
end

local function DebugLogPreyState(origin, questID, hasWidgetData, progressState, progressPercent, inPreyZone)
    if not (debugDB and debugDB.enabled) then
        return
    end

    local snapshot = table.concat({
        tostring(origin),
        tostring(questID),
        tostring(hasWidgetData),
        tostring(progressState),
        tostring(progressPercent),
        tostring(inPreyZone),
    }, "|")

    if snapshot == state.lastStateDebugSnapshot then
        return
    end

    state.lastStateDebugSnapshot = snapshot
    AddDebugLog("PreyState", "origin=" .. tostring(origin)
        .. " | questID=" .. tostring(questID)
        .. " | widget=" .. tostring(hasWidgetData)
        .. " | state=" .. tostring(progressState)
        .. " | pct=" .. tostring(progressPercent)
        .. " | inZone=" .. tostring(inPreyZone), false)
end

local function GetCandidateWidgetSetIDs()
    for index = #candidateWidgetSetIDs, 1, -1 do
        candidateWidgetSetIDs[index] = nil
    end

    if C_UIWidgetManager and C_UIWidgetManager.GetTopCenterWidgetSetID then
        candidateWidgetSetIDs[#candidateWidgetSetIDs + 1] = C_UIWidgetManager.GetTopCenterWidgetSetID()
    end
    if C_UIWidgetManager and C_UIWidgetManager.GetObjectiveTrackerWidgetSetID then
        candidateWidgetSetIDs[#candidateWidgetSetIDs + 1] = C_UIWidgetManager.GetObjectiveTrackerWidgetSetID()
    end
    if C_UIWidgetManager and C_UIWidgetManager.GetBelowMinimapWidgetSetID then
        candidateWidgetSetIDs[#candidateWidgetSetIDs + 1] = C_UIWidgetManager.GetBelowMinimapWidgetSetID()
    end
    if C_UIWidgetManager and C_UIWidgetManager.GetPowerBarWidgetSetID then
        candidateWidgetSetIDs[#candidateWidgetSetIDs + 1] = C_UIWidgetManager.GetPowerBarWidgetSetID()
    end

    return candidateWidgetSetIDs
end

local function FormatMemoryKB(value)
    return string.format("%.1f", value or 0)
end

local function PrintMemoryUsage()
    if not collectgarbage then
        print("Preydator: collectgarbage API unavailable.")
        return
    end

    local before = collectgarbage("count")
    collectgarbage("collect")
    local after = collectgarbage("count")
    local delta = before - after

    print("Preydator memory (KB): before=" .. FormatMemoryKB(before) .. " afterGC=" .. FormatMemoryKB(after) .. " reclaimed=" .. FormatMemoryKB(delta))
end

local function BuildStageSoundPlayedSummary()
    local parts = {}
    for stage = 1, MAX_STAGE do
        parts[#parts + 1] = tostring(stage) .. "=" .. tostring(state.stageSoundPlayed and state.stageSoundPlayed[stage] == true)
    end
    return table.concat(parts, ", ")
end

local function TrimText(value, maxLen)
    if type(value) ~= "string" then
        return ""
    end

    maxLen = tonumber(maxLen) or 80
    if #value <= maxLen then
        return value
    end

    return string.sub(value, 1, maxLen - 3) .. "..."
end

NormalizeSoundSettings = function()
    if type(settings.soundFileNames) ~= "table" then
        settings.soundFileNames = {}
    end

    local mergedNames = {}
    local seen = {}

    local function pushFileName(fileName)
        local normalized = NormalizeSoundFileName(fileName)
        if not normalized or seen[normalized] then
            return
        end
        seen[normalized] = true
        table.insert(mergedNames, normalized)
    end

    for _, defaultName in ipairs(DEFAULT_SOUND_FILENAMES) do
        pushFileName(defaultName)
    end

    for _, configuredName in ipairs(settings.soundFileNames) do
        pushFileName(configuredName)
    end

    for stage = 1, MAX_STAGE do
        local existingPath = settings.stageSounds and settings.stageSounds[stage]
        pushFileName(ExtractAddonSoundFileName(existingPath))
    end

    pushFileName(ExtractAddonSoundFileName(settings.ambushSoundPath))
    settings.soundFileNames = mergedNames

    local allowedPathLower = {}
    for _, fileName in ipairs(settings.soundFileNames) do
        local fullPath = BuildAddonSoundPath(fileName)
        if type(fullPath) == "string" and fullPath ~= "" then
            allowedPathLower[string.lower(fullPath)] = true
        end
    end

    if type(settings.stageSounds) ~= "table" then
        settings.stageSounds = {}
    end

    for stage = 1, MAX_STAGE do
        local configuredPath = settings.stageSounds[stage]
        if type(configuredPath) ~= "string" or configuredPath == "" then
            local legacyPath = settings.stageSounds[tostring(stage)]
            if type(legacyPath) == "string" and legacyPath ~= "" then
                configuredPath = legacyPath
            end
        end

        if type(configuredPath) == "string" and string.find(string.lower(configuredPath), "predator%-idle%.ogg", 1, false) then
            configuredPath = nil
        end

        if type(configuredPath) ~= "string" or configuredPath == "" then
            configuredPath = GetDefaultStageSoundPath(stage)
        end

        if type(configuredPath) ~= "string" or not allowedPathLower[string.lower(configuredPath)] then
            configuredPath = GetDefaultStageSoundPath(stage)
        end

        settings.stageSounds[stage] = configuredPath
    end

    if type(settings.ambushSoundPath) ~= "string" or not allowedPathLower[string.lower(settings.ambushSoundPath)] then
        settings.ambushSoundPath = KILL_SOUND_PATH
    end

    settings.stageSounds[5] = nil
end

local function ResetAllSettings()
    for key in pairs(settings) do
        settings[key] = nil
    end

    ApplyDefaults(settings, DEFAULTS)
    NormalizeLabelSettings()
    NormalizeColorSettings()
    NormalizeDisplaySettings()
    NormalizeProgressSettings()
    NormalizeAmbushSettings()
    NormalizeSoundSettings()

    state.forceShowBar = settings.forceShowBar
    state.stageSoundPlayed = {}

    ApplyBarSettings()
    UpdateBarDisplay()

    if optionsPanel and optionsPanel.PreydatorRefreshControls then
        optionsPanel.PreydatorRefreshControls()
    end
end

local function PrintInspectState()
    EnsureBar()
    UpdateBarDisplay()

    local now = GetTime and GetTime() or 0
    local liveQuestID = GetCurrentActivePreyQuest()
    local hasActiveQuest = IsValidQuestID(liveQuestID)
    local questOnLog = IsQuestStillActive(liveQuestID)
    local questCompleted = false
    if hasActiveQuest and C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted then
        questCompleted = C_QuestLog.IsQuestFlaggedCompleted(liveQuestID) and true or false
    end

    local playerMapID = (C_Map and C_Map.GetBestMapForUnit) and C_Map.GetBestMapForUnit("player") or nil
    local playerMapName = nil
    if playerMapID and C_Map and C_Map.GetMapInfo then
        local mapInfo = C_Map.GetMapInfo(playerMapID)
        playerMapName = mapInfo and mapInfo.name or nil
    end

    local shownWidgets = 0
    local objectivePct = ExtractQuestObjectivePercent(liveQuestID)
    local objectives = (hasActiveQuest and C_QuestLog and C_QuestLog.GetQuestObjectives) and C_QuestLog.GetQuestObjectives(liveQuestID) or nil
    local preyWidgetType = GetWidgetTypePreyHuntProgress()
    local shownStateShown = GetShownStateShown()

    print("Preydator Inspect (" .. INSPECT_VERSION .. ")")
    print("- time=" .. string.format("%.3f", now) .. " | zone=" .. tostring(GetZoneText and GetZoneText() or "?") .. " | playerMapID=" .. tostring(playerMapID) .. " | playerMap=" .. tostring(playerMapName))
    print("- quest live=" .. tostring(liveQuestID) .. " | hasActive=" .. tostring(hasActiveQuest) .. " | isOnQuest=" .. tostring(questOnLog) .. " | completed=" .. tostring(questCompleted))
    print("- quest tracked=" .. tostring(state.activeQuestID) .. " | progressState=" .. tostring(state.progressState) .. " | progressPercent=" .. tostring(state.progressPercent) .. " | stage=" .. tostring(state.stage) .. " (" .. tostring(GetStageLabel(state.stage)) .. ")")
    print("- prey target=" .. tostring(state.preyTargetName) .. " | difficulty=" .. tostring(state.preyTargetDifficulty) .. " | ambushAlertRemaining=" .. string.format("%.2f", math.max(0, (state.ambushAlertUntil or 0) - now)))
    print("- preyZone mapID=" .. tostring(state.preyZoneMapID) .. " | preyZoneName=" .. tostring(state.preyZoneName) .. " | inPreyZone=" .. tostring(state.inPreyZone))
    print("- killStageRemaining=" .. string.format("%.2f", math.max(0, (state.killStageUntil or 0) - now)) .. " | lastWidgetAge=" .. string.format("%.2f", math.max(0, now - (state.lastWidgetSeenAt or 0))))
    print("- sounds enabled=" .. tostring(settings and settings.soundsEnabled) .. " | channel=" .. tostring(settings and settings.soundChannel) .. " | stagePlayed={" .. BuildStageSoundPlayedSummary() .. "}")
    print("- percent source=" .. tostring(state.lastPercentSource) .. " | fallbackMode=" .. tostring(settings and settings.percentFallbackMode) .. " | objectivePct=" .. tostring(objectivePct))
    if type(objectives) == "table" and #objectives > 0 then
        local shown = 0
        for index, objective in ipairs(objectives) do
            if type(objective) == "table" then
                shown = shown + 1
                if shown > 4 then
                    print("  objective ... (" .. tostring(#objectives - 4) .. " more)")
                    break
                end

                print("  objective " .. tostring(index)
                    .. " fulfilled=" .. tostring(objective.numFulfilled or objective.fulfilled)
                    .. " required=" .. tostring(objective.numRequired or objective.required)
                    .. " finished=" .. tostring(objective.finished)
                    .. " text='" .. TrimText(objective.text, 80) .. "'")
            end
        end
    else
        print("  objective none")
    end
    print("- bar shown=" .. tostring(barFrame and barFrame:IsShown() or false)
        .. " | forceShow=" .. tostring(state.forceShowBar)
        .. " | onlyShowInPreyZone=" .. tostring(settings and settings.onlyShowInPreyZone))
    local frameWidth = barFrame and barFrame:GetWidth() or 0
    local fillWidth = barFill and barFill:GetWidth() or 0
    local fillPct = 0
    if frameWidth and frameWidth > 0 then
        fillPct = (fillWidth / frameWidth) * 100
    end
    print("- display pct=" .. tostring(state.lastDisplayPct) .. " | reason=" .. tostring(state.lastDisplayReason)
        .. " | frameWidth=" .. string.format("%.2f", frameWidth)
        .. " | fillWidth=" .. string.format("%.2f", fillWidth)
        .. " | fillPct=" .. string.format("%.2f", fillPct))

    local savedPoint = settings and settings.point or {}
    print("- point saved="
        .. " anchor=" .. tostring(savedPoint.anchor)
        .. " rel=" .. tostring(savedPoint.relativePoint)
        .. " x=" .. tostring(savedPoint.x)
        .. " y=" .. tostring(savedPoint.y))

    local livePoint, liveRelativeTo, liveRelativePoint, liveX, liveY = nil, nil, nil, nil, nil
    if barFrame and barFrame.GetPoint then
        livePoint, liveRelativeTo, liveRelativePoint, liveX, liveY = barFrame:GetPoint(1)
    end
    local liveRelativeName = "nil"
    if liveRelativeTo == UIParent then
        liveRelativeName = "UIParent"
    elseif liveRelativeTo ~= nil then
        liveRelativeName = tostring(liveRelativeTo)
    end
    print("- point live="
        .. " anchor=" .. tostring(livePoint)
        .. " relTo=" .. tostring(liveRelativeName)
        .. " rel=" .. tostring(liveRelativePoint)
        .. " x=" .. tostring(liveX)
        .. " y=" .. tostring(liveY))

    local frameScale = barFrame and barFrame.GetScale and barFrame:GetScale() or 1
    local frameEffectiveScale = barFrame and barFrame.GetEffectiveScale and barFrame:GetEffectiveScale() or 1
    local frameCenterX = barFrame and barFrame.GetCenter and select(1, barFrame:GetCenter()) or nil
    local frameCenterY = barFrame and barFrame.GetCenter and select(2, barFrame:GetCenter()) or nil
    local parentCenterX = UIParent and UIParent.GetCenter and select(1, UIParent:GetCenter()) or nil
    local parentCenterY = UIParent and UIParent.GetCenter and select(2, UIParent:GetCenter()) or nil
    local centerDX = (frameCenterX and parentCenterX) and (frameCenterX - parentCenterX) or nil
    local centerDY = (frameCenterY and parentCenterY) and (frameCenterY - parentCenterY) or nil
    print("- frame scale=" .. tostring(frameScale)
        .. " | effectiveScale=" .. tostring(frameEffectiveScale)
        .. " | centerDX=" .. tostring(centerDX)
        .. " | centerDY=" .. tostring(centerDY))

    print("- frame local=" .. tostring(barFrame) .. " | frame global=" .. tostring(_G.PreydatorProgressBar)
        .. " | same=" .. tostring(barFrame ~= nil and _G.PreydatorProgressBar ~= nil and barFrame == _G.PreydatorProgressBar))

    if C_UIWidgetManager and C_UIWidgetManager.GetAllWidgetsBySetID and C_UIWidgetManager.GetPreyHuntProgressWidgetVisualizationInfo then
        for _, setID in ipairs(GetCandidateWidgetSetIDs()) do
            local widgets = C_UIWidgetManager.GetAllWidgetsBySetID(setID)
            if widgets and #widgets > 0 then
                for _, widget in ipairs(widgets) do
                    if widget and widget.widgetType == preyWidgetType then
                        local info = C_UIWidgetManager.GetPreyHuntProgressWidgetVisualizationInfo(widget.widgetID)
                        if info and info.shownState == shownStateShown then
                            shownWidgets = shownWidgets + 1
                            local pct = ExtractProgressPercent(info, info.tooltip)
                            local widgetQuestID = ExtractWidgetQuestID(info)
                            print("  widget set=" .. tostring(setID) .. " widgetID=" .. tostring(widget.widgetID)
                                .. " questID=" .. tostring(widgetQuestID)
                                .. " state=" .. tostring(info.progressState)
                                .. " pct=" .. tostring(pct)
                                .. " tooltip='" .. TrimText(info.tooltip, 90) .. "'")
                            print("    fields: " .. TrimText(SummarizeInfoFields(info), 200))
                        end
                    end
                end
            end
        end
    end

    if shownWidgets == 0 then
        print("  widget none shown")
    end
end

ExtractWidgetQuestID = function(info)
    if type(info) ~= "table" then
        return nil
    end

    local possibleFields = {
        "questID",
        "questId",
        "associatedQuestID",
        "associatedQuestId",
    }

    for _, fieldName in ipairs(possibleFields) do
        local value = info[fieldName]
        if type(value) == "number" and value > 0 then
            return value
        end
    end

    return nil
end

local function FindPreyWidgetProgressState(activeQuestID)
    if not (C_UIWidgetManager and C_UIWidgetManager.GetAllWidgetsBySetID and C_UIWidgetManager.GetPreyHuntProgressWidgetVisualizationInfo) then
        return nil
    end

    local preyWidgetType = GetWidgetTypePreyHuntProgress()
    local shownStateShown = GetShownStateShown()
    local fallbackState, fallbackTooltip, fallbackPct = nil, nil, nil

    for _, setID in ipairs(GetCandidateWidgetSetIDs()) do
        local widgets = C_UIWidgetManager.GetAllWidgetsBySetID(setID)
        if widgets then
            for _, widget in ipairs(widgets) do
                if widget and widget.widgetType == preyWidgetType then
                    local info = C_UIWidgetManager.GetPreyHuntProgressWidgetVisualizationInfo(widget.widgetID)
                    if info and info.shownState == shownStateShown then
                        local pct = ExtractProgressPercent(info, info.tooltip)
                        if IsValidQuestID(activeQuestID) then
                            local widgetQuestID = ExtractWidgetQuestID(info)
                            if widgetQuestID == activeQuestID then
                                return info.progressState, info.tooltip, pct
                            end

                            if widgetQuestID == nil and fallbackState == nil then
                                fallbackState, fallbackTooltip, fallbackPct = info.progressState, info.tooltip, pct
                            end
                        else
                            return info.progressState, info.tooltip, pct
                        end
                    end
                end
            end
        end
    end

    if IsValidQuestID(activeQuestID) then
        return fallbackState, fallbackTooltip, fallbackPct
    end

    return nil, nil, nil
end

local function ResetStateForNewQuest(questID)
    if state.activeQuestID ~= questID then
        state.activeQuestID = questID
        state.progressState = nil
        state.progressPercent = nil
        state.stageSoundPlayed = {}
        state.stage = 1
        state.preyZoneName, state.preyZoneMapID = GetPreyZoneInfo(questID)
        state.inPreyZone = IsPlayerInPreyZone(state.preyZoneMapID)
        state.preyTooltipText = nil
        state.preyTargetName, state.preyTargetDifficulty = ExtractPreyTargetFromQuestTitle(questID)
        state.ambushAlertUntil = 0
        state.lastAmbushSystemMessage = nil
    end
end

local function UpdatePreyState()
    local questID = GetCurrentActivePreyQuest()
    local hasActiveQuest = IsValidQuestID(questID)
    local newProgressState, tooltipText, newProgressPercent = FindPreyWidgetProgressState(hasActiveQuest and questID or nil)
    local now = GetTime and GetTime() or 0
    local hasWidgetData = newProgressState ~= nil

    if hasWidgetData then
        state.lastWidgetSeenAt = now
    end

    local effectiveQuestID = hasActiveQuest and questID or nil

    local questCompleted = false
    if questID and C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted then
        questCompleted = C_QuestLog.IsQuestFlaggedCompleted(questID) and true or false
    end

    local questStillActive = IsQuestStillActive(questID)
    if (not hasActiveQuest and not ((state.killStageUntil or 0) > now)) or questCompleted or (hasActiveQuest and not questStillActive and not hasWidgetData) then
        DebugLogPreyState("clear", questID, hasWidgetData, state.progressState, state.progressPercent, state.inPreyZone)
        ClearPreyStateAndDisplay()
        UpdateBarDisplay()
        return
    end

    ResetStateForNewQuest(effectiveQuestID)
    if hasWidgetData then
        state.inPreyZone = true
    else
        state.inPreyZone = IsPlayerInPreyZone(state.preyZoneMapID)
    end

    local oldProgressState = state.progressState
    local percentSource = "none"
    if newProgressState ~= nil then
        state.progressState = newProgressState
        state.inPreyZone = true
    end
    if newProgressPercent ~= nil then
        state.progressPercent = newProgressPercent
        percentSource = "widget"
    else
        local objectivePercent = ExtractQuestObjectivePercent(questID)
        if objectivePercent ~= nil and (objectivePercent > 0 or newProgressState == PREY_PROGRESS_FINAL) then
            state.progressPercent = objectivePercent
            percentSource = "objective"
        end
    end

    if newProgressPercent == nil and percentSource == "none" and newProgressState ~= nil then
        if newProgressState == PREY_PROGRESS_FINAL then
            state.progressPercent = 100
            percentSource = "final"
        else
            state.progressPercent = nil
        end
    elseif newProgressPercent == nil and percentSource == "none" and (now - (state.lastWidgetSeenAt or 0)) > 2 then
        state.progressPercent = nil
        state.progressState = nil
    end
    state.lastPercentSource = percentSource
    state.preyTooltipText = tooltipText
    DebugLogPreyState("update", effectiveQuestID, hasWidgetData, state.progressState, state.progressPercent, state.inPreyZone)

    local oldStage = state.stage
    local newStage = GetStageFromState(state.progressState)

    local stageChanged = newStage ~= oldStage
    if stageChanged then
        TryPlayStageSound(newStage)
    end

    if newProgressState ~= PREY_PROGRESS_FINAL or oldProgressState == PREY_PROGRESS_FINAL then
        UpdateBarDisplay()
        return
    end

    if state.stageSoundPlayed[MAX_STAGE] then
        UpdateBarDisplay()
        return
    end

    TryPlayStageSound(MAX_STAGE)

    UpdateBarDisplay()
end

local function OnAddonLoaded()
    _G.PreydatorDB = _G.PreydatorDB or {}
    settings = _G.PreydatorDB
    ApplyDefaults(settings, DEFAULTS)
    EnsureDebugDB()
    settings.debugSounds = false
    debugDB.enabled = settings.debugSounds and true or false

    NormalizeSoundSettings()
    NormalizeLabelSettings()
    NormalizeColorSettings()
    NormalizeDisplaySettings()
    NormalizeProgressSettings()
    NormalizeAmbushSettings()
    AddDebugLog("OnAddonLoaded", "debug=" .. tostring(debugDB.enabled) .. " | stage" .. tostring(MAX_STAGE) .. "=" .. tostring(settings.stageSounds[MAX_STAGE]), true)

    state.forceShowBar = settings.forceShowBar

    frame:RegisterEvent("PLAYER_LOGIN")
    frame:RegisterEvent("QUEST_LOG_UPDATE")
    frame:RegisterEvent("UPDATE_ALL_UI_WIDGETS")
    frame:RegisterEvent("UPDATE_UI_WIDGET")
    frame:RegisterEvent("QUEST_TURNED_IN")
    frame:RegisterEvent("CHAT_MSG_SYSTEM")
    frame:RegisterEvent("CHAT_MSG_MONSTER_SAY")
    frame:RegisterEvent("CHAT_MSG_MONSTER_YELL")
    frame:RegisterEvent("CHAT_MSG_MONSTER_EMOTE")
    frame:RegisterEvent("RAID_BOSS_EMOTE")
    frame:RegisterEvent("ZONE_CHANGED")
    frame:RegisterEvent("ZONE_CHANGED_INDOORS")
    frame:RegisterEvent("ZONE_CHANGED_NEW_AREA")

    RunModuleHook("OnAddonLoaded")
end

local function AddCheckbox(parent, label, x, y, getter, setter)
    local checkbox = CreateFrame("CheckButton", nil, parent, "InterfaceOptionsCheckButtonTemplate")
    checkbox:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    checkbox.Text:SetText(label)
    checkbox:SetChecked(getter())
    checkbox:SetScript("OnClick", function(self)
        setter(self:GetChecked())
    end)
    return checkbox
end

local function AddSlider(parent, label, x, y, minValue, maxValue, step, getter, setter)
    local slider = CreateFrame("Slider", nil, parent, "OptionsSliderTemplate")
    slider:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    slider:SetWidth(240)
    slider:SetMinMaxValues(minValue, maxValue)
    slider:SetValueStep(step)
    slider:SetObeyStepOnDrag(true)
    slider:SetValue(getter())
    slider.Text:SetText(label)
    slider.Low:SetText(tostring(minValue))
    slider.High:SetText(tostring(maxValue))
    slider:SetScript("OnValueChanged", function(self, value)
        setter(value)
    end)
    return slider
end

local function AddDropdown(parent, label, x, y, width, options, getter, setter)
    local title = parent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    title:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    title:SetText(label)

    local dropdown = CreateFrame("Frame", nil, parent, "UIDropDownMenuTemplate")
    dropdown:SetPoint("TOPLEFT", title, "BOTTOMLEFT", -16, -4)

    local function GetOptions()
        if type(options) == "function" then
            return options() or {}
        end
        return options or {}
    end

    local function RefreshText()
        local key = getter()
        local entry = GetOptions()[key]
        UIDropDownMenu_SetText(dropdown, entry and entry.text or "Select")
    end

    UIDropDownMenu_SetWidth(dropdown, width)
    UIDropDownMenu_Initialize(dropdown, function(_, _, _)
        local optionList = {}
        for key, entry in pairs(GetOptions()) do
            table.insert(optionList, { key = key, entry = entry })
        end

        table.sort(optionList, function(a, b)
            local left = tostring(a.entry and a.entry.text or "")
            local right = tostring(b.entry and b.entry.text or "")
            return left < right
        end)

        for _, item in ipairs(optionList) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = item.entry.text
            info.func = function()
                setter(item.key)
                RefreshText()
            end
            info.checked = getter() == item.key
            UIDropDownMenu_AddButton(info)
        end
    end)

    dropdown.PreydatorRefreshText = RefreshText
    RefreshText()
    return dropdown
end

local function AddColorSwatch(parent, x, y, getter, setter, allowAlpha)
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetSize(28, 22)
    button:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    button:SetText("")

    local swatch = button:CreateTexture(nil, "ARTWORK")
    swatch:SetPoint("TOPLEFT", button, "TOPLEFT", 3, -3)
    swatch:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -3, 3)

    local function Refresh()
        local c = getter()
        local a = (allowAlpha and c[4]) or 1
        swatch:SetColorTexture(c[1], c[2], c[3], a)
    end

    local function NormalizeColorInput(value, fallback)
        local fb = fallback or { 1, 1, 1, 1 }
        local r = value and (value[1] or value.r) or fb[1]
        local g = value and (value[2] or value.g) or fb[2]
        local b = value and (value[3] or value.b) or fb[3]

        local a = fb[4]
        if allowAlpha then
            if value then
                if value[4] ~= nil then
                    a = value[4]
                elseif value.a ~= nil then
                    a = value.a
                elseif value.opacity ~= nil then
                    a = 1 - value.opacity
                end
            end
        else
            a = 1
        end

        r = Clamp(tonumber(r) or fb[1] or 1, 0, 1)
        g = Clamp(tonumber(g) or fb[2] or 1, 0, 1)
        b = Clamp(tonumber(b) or fb[3] or 1, 0, 1)
        a = Clamp(tonumber(a) or fb[4] or 1, 0, 1)

        return { r, g, b, a }
    end

    local function GetPickerColor(defaultA)
        local r, g, b
        if ColorPickerFrame.GetColorRGB then
            r, g, b = ColorPickerFrame:GetColorRGB()
        elseif ColorPickerFrame.Content and ColorPickerFrame.Content.ColorPicker and ColorPickerFrame.Content.ColorPicker.GetColorRGB then
            r, g, b = ColorPickerFrame.Content.ColorPicker:GetColorRGB()
        else
            r, g, b = 1, 1, 1
        end

        local a = defaultA
        if allowAlpha then
            if ColorPickerFrame.GetColorAlpha then
                a = ColorPickerFrame:GetColorAlpha()
            elseif OpacitySliderFrame and OpacitySliderFrame.GetValue then
                a = 1 - OpacitySliderFrame:GetValue()
            end
        end

        return r, g, b, a
    end

    button:SetScript("OnClick", function()
        if not ColorPickerFrame then
            return
        end

        colorPickerSessionCounter = colorPickerSessionCounter + 1
        local sessionID = colorPickerSessionCounter
        ColorPickerFrame.preydatorSessionID = sessionID

        local start = getter()
        local startColor = {
            start[1] or 1,
            start[2] or 1,
            start[3] or 1,
            start[4] or 1,
        }

        local function ApplyColor()
            if ColorPickerFrame.preydatorSessionID ~= sessionID then
                return
            end

            local r, g, b, a = GetPickerColor(startColor[4])

            setter(NormalizeColorInput({ r, g, b, a }, startColor))
            Refresh()
        end

        local function CancelColor(previousValues)
            if ColorPickerFrame.preydatorSessionID ~= sessionID then
                return
            end

            local pr, pg, pb, pa = nil, nil, nil, nil
            if type(previousValues) == "table" then
                pr = previousValues.r or previousValues[1]
                pg = previousValues.g or previousValues[2]
                pb = previousValues.b or previousValues[3]
                pa = previousValues.a or previousValues[4]
            elseif ColorPickerFrame.GetPreviousValues then
                pr, pg, pb, pa = ColorPickerFrame:GetPreviousValues()
            end

            if pr == nil or pg == nil or pb == nil then
                pr, pg, pb, pa = startColor[1], startColor[2], startColor[3], startColor[4]
            end

            setter(NormalizeColorInput({ pr, pg, pb, pa }, startColor))
            Refresh()
        end

        if ColorPickerFrame.SetupColorPickerAndShow then
            local info = {
                r = startColor[1],
                g = startColor[2],
                b = startColor[3],
                opacity = allowAlpha and startColor[4] or 0,
                hasOpacity = allowAlpha and true or false,
                func = ApplyColor,
                swatchFunc = ApplyColor,
                opacityFunc = ApplyColor,
                cancelFunc = CancelColor,
            }
            ColorPickerFrame:SetupColorPickerAndShow(info)
            return
        end

        ColorPickerFrame.hasOpacity = allowAlpha and true or false
        ColorPickerFrame.opacity = allowAlpha and (1 - startColor[4]) or 0
        ColorPickerFrame.previousValues = { startColor[1], startColor[2], startColor[3], startColor[4] }
        if ColorPickerFrame.SetColorRGB then
            ColorPickerFrame:SetColorRGB(startColor[1], startColor[2], startColor[3])
        elseif ColorPickerFrame.Content and ColorPickerFrame.Content.ColorPicker and ColorPickerFrame.Content.ColorPicker.SetColorRGB then
            ColorPickerFrame.Content.ColorPicker:SetColorRGB(startColor[1], startColor[2], startColor[3])
        end
        ColorPickerFrame.func = ApplyColor
        ColorPickerFrame.swatchFunc = ApplyColor
        ColorPickerFrame.opacityFunc = ApplyColor
        ColorPickerFrame.cancelFunc = CancelColor

        ColorPickerFrame:Hide()
        ColorPickerFrame:Show()
    end)

    button.PreydatorRefresh = Refresh
    Refresh()
    return button
end

EnsureOptionsPanel = function()
    if optionsPanel then
        return
    end

    local panel = CreateFrame("Frame", "PreydatorOptionsPanel")
    panel.name = "Preydator"
    local panelRoot = panel

    local scrollFrame = CreateFrame("ScrollFrame", "PreydatorOptionsScrollFrame", panelRoot, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", panelRoot, "TOPLEFT", 8, -8)
    scrollFrame:SetPoint("BOTTOMRIGHT", panelRoot, "BOTTOMRIGHT", -30, 8)

    local content = CreateFrame("Frame", "PreydatorOptionsContent", scrollFrame)
    content:SetSize(760, 900)
    scrollFrame:SetScrollChild(content)

    optionsScrollFrame = scrollFrame
    optionsContentFrame = content
    panel = content

    NormalizeLabelSettings()

    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("Preydator")

    local subtitle = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    subtitle:SetText("Bar movement, scale, font, texture, and sound settings.")
    subtitle:SetWidth(700)
    subtitle:SetJustifyH("LEFT")
    subtitle:SetWordWrap(true)

    local lockCheckbox = AddCheckbox(panel, "Lock Bar", 20, -55, function() return settings.locked end, function(value)
        settings.locked = value
        ApplyBarSettings()
    end)

    local onlyShowInPreyZoneCheckbox = AddCheckbox(panel, "Only show in prey zone", 20, -83, function() return settings.onlyShowInPreyZone end, function(value)
        settings.onlyShowInPreyZone = value
        UpdateBarDisplay()
    end)

    local scaleSlider = AddSlider(panel, "Scale", 20, -407, 0.5, 2, 0.05, function() return settings.scale end, function(value)
        settings.scale = Clamp(value, 0.5, 2)
        ApplyBarSettings()
    end)

    local widthSlider = AddSlider(panel, "Width", 20, -442, 160, 500, 1, function() return settings.width end, function(value)
        settings.width = Clamp(math.floor(value + 0.5), 160, 500)
        ApplyBarSettings()
        UpdateBarDisplay()
    end)

    local heightSlider = AddSlider(panel, "Height", 20, -477, 10, 40, 1, function() return settings.height end, function(value)
        settings.height = Clamp(math.floor(value + 0.5), 10, 40)
        ApplyBarSettings()
        UpdateBarDisplay()
    end)

    local fontSizeSlider = AddSlider(panel, "Font Size", 20, -512, 8, 24, 1, function() return settings.fontSize end, function(value)
        settings.fontSize = Clamp(math.floor(value + 0.5), 8, 24)
        ApplyBarSettings()
    end)

    local stageNamesTitle = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    stageNamesTitle:SetPoint("TOPLEFT", panel, "TOPLEFT", 320, -407)
    stageNamesTitle:SetText("Stage Names")

    local stageNameEdits = {}
    for stageIndex = 1, (MAX_STAGE - 1) do
        local rowY = -442 - ((stageIndex - 1) * 35)
        local label = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        label:SetPoint("TOPLEFT", panel, "TOPLEFT", 320, rowY)
        label:SetText(tostring(stageIndex) .. ":")

        local edit = CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
        edit:SetSize(180, 20)
        edit:SetAutoFocus(false)
        edit:SetTextInsets(6, 6, 0, 0)
        edit:SetPoint("TOPLEFT", panel, "TOPLEFT", 350, -441 - ((stageIndex - 1) * 35))
        edit:SetText(GetStageLabel(stageIndex))
        edit:SetScript("OnEnterPressed", function(self)
            settings.stageLabels[stageIndex] = self:GetText()
            NormalizeLabelSettings()
            self:SetText(settings.stageLabels[stageIndex])
            self:ClearFocus()
            UpdateBarDisplay()
        end)
        edit:SetScript("OnEditFocusLost", function(self)
            settings.stageLabels[stageIndex] = self:GetText()
            NormalizeLabelSettings()
            self:SetText(settings.stageLabels[stageIndex])
            UpdateBarDisplay()
        end)
        stageNameEdits[stageIndex] = edit
    end

    local outZoneRowY = -547
    local outZoneLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    outZoneLabel:SetPoint("TOPLEFT", panel, "TOPLEFT", 320, outZoneRowY)
    outZoneLabel:SetText("Zone:")

    local outZoneEdit = CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
    outZoneEdit:SetSize(156, 20)
    outZoneEdit:SetAutoFocus(false)
    outZoneEdit:SetTextInsets(6, 6, 0, 0)
    outZoneEdit:SetPoint("TOPLEFT", panel, "TOPLEFT", 365, -546)
    outZoneEdit:SetText(settings.outOfZoneLabel or DEFAULT_OUT_OF_ZONE_LABEL)
    outZoneEdit:SetScript("OnEnterPressed", function(self)
        settings.outOfZoneLabel = self:GetText()
        NormalizeLabelSettings()
        self:SetText(settings.outOfZoneLabel)
        self:ClearFocus()
        UpdateBarDisplay()
    end)
    outZoneEdit:SetScript("OnEditFocusLost", function(self)
        settings.outOfZoneLabel = self:GetText()
        NormalizeLabelSettings()
        self:SetText(settings.outOfZoneLabel)
        UpdateBarDisplay()
    end)

    local ambushLabelText = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    ambushLabelText:SetPoint("TOPLEFT", panel, "TOPLEFT", 320, -575)
    ambushLabelText:SetText("Ambush:")

    local ambushLabelEdit = CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
    ambushLabelEdit:SetSize(156, 20)
    ambushLabelEdit:SetAutoFocus(false)
    ambushLabelEdit:SetTextInsets(6, 6, 0, 0)
    ambushLabelEdit:SetPoint("TOPLEFT", panel, "TOPLEFT", 380, -574)
    ambushLabelEdit:SetText(settings.ambushCustomText or "")
    ambushLabelEdit:SetScript("OnEnterPressed", function(self)
        settings.ambushCustomText = self:GetText()
        NormalizeLabelSettings()
        self:SetText(settings.ambushCustomText)
        self:ClearFocus()
        UpdateBarDisplay()
    end)
    ambushLabelEdit:SetScript("OnEditFocusLost", function(self)
        settings.ambushCustomText = self:GetText()
        NormalizeLabelSettings()
        self:SetText(settings.ambushCustomText)
        UpdateBarDisplay()
    end)

    local restoreNamesButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    restoreNamesButton:SetSize(180, 24)
    restoreNamesButton:SetPoint("TOPLEFT", panel, "TOPLEFT", 320, -764)
    restoreNamesButton:SetText("Restore Default Names")
    restoreNamesButton:SetScript("OnClick", function()
        for stageIndex = 1, (MAX_STAGE - 1) do
            settings.stageLabels[stageIndex] = DEFAULT_STAGE_LABELS[stageIndex]
            stageNameEdits[stageIndex]:SetText(DEFAULT_STAGE_LABELS[stageIndex])
        end
        settings.outOfZoneLabel = DEFAULT_OUT_OF_ZONE_LABEL
        settings.ambushCustomText = ""
        outZoneEdit:SetText(DEFAULT_OUT_OF_ZONE_LABEL)
        ambushLabelEdit:SetText("")
        UpdateBarDisplay()
    end)

    local restoreSoundsButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    restoreSoundsButton:SetSize(180, 24)
    restoreSoundsButton:SetPoint("TOPLEFT", panel, "TOPLEFT", 320, -793)
    restoreSoundsButton:SetText("Restore Default Sounds")
    restoreSoundsButton:SetScript("OnClick", function()
        settings.soundsEnabled = DEFAULTS.soundsEnabled
        settings.soundChannel = DEFAULTS.soundChannel
        settings.soundEnhance = DEFAULTS.soundEnhance
        settings.ambushSoundEnabled = DEFAULTS.ambushSoundEnabled
        settings.ambushVisualEnabled = DEFAULTS.ambushVisualEnabled
        settings.ambushSoundPath = DEFAULTS.ambushSoundPath
        settings.soundFileNames = {}
        for _, fileName in ipairs(DEFAULT_SOUND_FILENAMES) do
            table.insert(settings.soundFileNames, fileName)
        end
        for stageIndex = 1, MAX_STAGE do
            settings.stageSounds[stageIndex] = DEFAULTS.stageSounds[stageIndex]
        end
        NormalizeSoundSettings()
        NormalizeAmbushSettings()
        if panel.PreydatorRefreshControls then
            panel.PreydatorRefreshControls()
        end
    end)

    local resetAllButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    resetAllButton:SetSize(180, 24)
    resetAllButton:SetPoint("TOPLEFT", panel, "TOPLEFT", 320, -821)
    resetAllButton:SetText("Reset All Defaults")
    resetAllButton:SetScript("OnClick", function()
        ResetAllSettings()
        if panel.PreydatorRefreshControls then
            panel.PreydatorRefreshControls()
        end
    end)

    local customSoundTitle = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    customSoundTitle:SetPoint("TOPLEFT", panel, "TOPLEFT", 20, -631)
    customSoundTitle:SetText("Custom Sound Files: No Spaces")

    local customSoundPathLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    customSoundPathLabel:SetPoint("TOPLEFT", panel, "TOPLEFT", 20, -659)
    customSoundPathLabel:SetText("Interface\\AddOns\\Preydator\\sounds\\")

    local customSoundEdit = CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
    customSoundEdit:SetSize(210, 20)
    customSoundEdit:SetAutoFocus(false)
    customSoundEdit:SetTextInsets(6, 6, 0, 0)
    customSoundEdit:SetPoint("TOPLEFT", panel, "TOPLEFT", 20, -687)
    customSoundEdit:SetText("")

    local addCustomSoundButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    addCustomSoundButton:SetSize(100, 22)
    addCustomSoundButton:SetPoint("TOPLEFT", panel, "TOPLEFT", 20, -715)
    addCustomSoundButton:SetText("Add File")
    addCustomSoundButton:SetScript("OnClick", function()
        local ok, message = AddSoundFileName(customSoundEdit:GetText())
        if not ok then
            print("Preydator: " .. tostring(message))
            return
        end

        customSoundEdit:SetText("")
        if panel.PreydatorRefreshControls then
            panel.PreydatorRefreshControls()
        end
        print("Preydator: Added sound file '" .. tostring(message) .. "'.")
    end)

    local removeCustomSoundButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    removeCustomSoundButton:SetSize(110, 22)
    removeCustomSoundButton:SetPoint("TOPLEFT", panel, "TOPLEFT", 130, -715)
    removeCustomSoundButton:SetText("Remove File")
    removeCustomSoundButton:SetScript("OnClick", function()
        local ok, message = RemoveSoundFileName(customSoundEdit:GetText())
        if not ok then
            print("Preydator: " .. tostring(message))
            return
        end

        customSoundEdit:SetText("")
        if panel.PreydatorRefreshControls then
            panel.PreydatorRefreshControls()
        end
        print("Preydator: Removed sound file '" .. tostring(message) .. "'.")
    end)

    panelRoot:SetScript("OnShow", function()
        NormalizeLabelSettings()
        if panelRoot.PreydatorRefreshControls then
            panelRoot.PreydatorRefreshControls()
        end
    end)

    local textureOptions = {
        default = { text = "Default" },
        flat = { text = "Flat" },
        raid = { text = "Raid HP Fill" },
        classic = { text = "Classic Skill Bar" },
    }

    local fontOptions = {
        frizqt = { text = "Friz Quadrata" },
        arialn = { text = "Arial Narrow" },
        skurri = { text = "Skurri" },
        morpheus = { text = "Morpheus" },
    }

    local channelOptions = {
        Master = { text = "Master" },
        SFX = { text = "SFX" },
        Dialog = { text = "Dialog" },
        Ambience = { text = "Ambience" },
    }

    local percentDisplayOptions = {
        [PERCENT_DISPLAY_INSIDE] = { text = "In Bar" },
        [PERCENT_DISPLAY_UNDER_TICKS] = { text = "Under Ticks" },
        [PERCENT_DISPLAY_BELOW_BAR] = { text = "Below Bar" },
        [PERCENT_DISPLAY_OFF] = { text = "Off" },
    }

    local progressSegmentOptions = {
        [PROGRESS_SEGMENTS_QUARTERS] = { text = "Quarters (25/50/75/100)" },
        [PROGRESS_SEGMENTS_THIRDS] = { text = "Thirds (33/66/100)" },
    }

    local textureDropdown = AddDropdown(panel, "Texture", 20, -243, 170, textureOptions, function()
        return settings.textureKey
    end, function(key)
        settings.textureKey = key
        ApplyBarSettings()
    end)
    local fillColorSwatch = AddColorSwatch(panel, 230, -263, function()
        return settings.fillColor
    end, function(color)
        settings.fillColor = { color[1], color[2], color[3], color[4] }
        ApplyBarSettings()
    end, true)

    local titleFontDropdown = AddDropdown(panel, "Title Font", 20, -295, 170, fontOptions, function()
        return settings.titleFontKey
    end, function(key)
        settings.titleFontKey = key
        ApplyBarSettings()
    end)
    local titleColorSwatch = AddColorSwatch(panel, 230, -315, function()
        return settings.titleColor
    end, function(color)
        settings.titleColor = { color[1], color[2], color[3], color[4] }
        ApplyBarSettings()
        UpdateBarDisplay()
    end, true)

    local percentFontDropdown = AddDropdown(panel, "Percent Font", 20, -347, 170, fontOptions, function()
        return settings.percentFontKey
    end, function(key)
        settings.percentFontKey = key
        ApplyBarSettings()
    end)
    local percentColorSwatch = AddColorSwatch(panel, 230, -367, function()
        return settings.percentColor
    end, function(color)
        settings.percentColor = { color[1], color[2], color[3], color[4] }
        ApplyBarSettings()
        UpdateBarDisplay()
    end, true)

    local soundsCheckbox = AddCheckbox(panel, "Enable sounds", 20, -111, function() return settings.soundsEnabled end, function(value)
        settings.soundsEnabled = value
    end)

    local ambushSoundCheckbox = AddCheckbox(panel, "Ambush sound alert", 320, -55, function() return settings.ambushSoundEnabled ~= false end, function(value)
        settings.ambushSoundEnabled = value
    end)

    local ambushVisualCheckbox = AddCheckbox(panel, "Ambush visual alert", 320, -83, function() return settings.ambushVisualEnabled ~= false end, function(value)
        settings.ambushVisualEnabled = value
        if not value then
            state.ambushAlertUntil = 0
            UpdateBarDisplay()
        end
    end)

    local stage1SoundDropdown = AddDropdown(panel, "Stage 1 Sound", 320, -191, 170, BuildSoundDropdownOptions, function()
        return settings.stageSounds[1]
    end, function(key)
        settings.stageSounds[1] = key
        NormalizeSoundSettings()
    end)

    local stage2SoundDropdown = AddDropdown(panel, "Stage 2 Sound", 320, -243, 170, BuildSoundDropdownOptions, function()
        return settings.stageSounds[2]
    end, function(key)
        settings.stageSounds[2] = key
        NormalizeSoundSettings()
    end)

    local stage3SoundDropdown = AddDropdown(panel, "Stage 3 Sound", 320, -295, 170, BuildSoundDropdownOptions, function()
        return settings.stageSounds[3]
    end, function(key)
        settings.stageSounds[3] = key
        NormalizeSoundSettings()
    end)

    local ambushSoundDropdown = AddDropdown(panel, "Ambush Sound", 320, -347, 170, BuildSoundDropdownOptions, function()
        return settings.ambushSoundPath
    end, function(key)
        settings.ambushSoundPath = key
        NormalizeAmbushSettings()
    end)

    local testAmbushAlertButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    testAmbushAlertButton:SetSize(170, 24)
    testAmbushAlertButton:SetPoint("TOPLEFT", panel, "TOPLEFT", 320, -715)
    testAmbushAlertButton:SetText("Test Ambush")
    testAmbushAlertButton:SetScript("OnClick", function()
        TriggerAmbushAlert("Manual test", "options")
    end)

    local soundChannelDropdown = AddDropdown(panel, "Sound Channel", 320, -139, 170, channelOptions, function()
        return settings.soundChannel
    end, function(key)
        settings.soundChannel = key
    end)

    local enhanceSlider = AddSlider(panel, "Enhance Sounds", 20, -547, 0, 100, 5, function()
        return settings.soundEnhance or 0
    end, function(value)
        settings.soundEnhance = Clamp(math.floor(value + 0.5), 0, 100)
    end)

    local showTicksCheckbox = AddCheckbox(panel, "Show tick marks", 320, -111, function() return settings.showTicks end, function(value)
        settings.showTicks = value
        ApplyBarSettings()
        UpdateBarDisplay()
    end)

    local percentDisplayDropdown = AddDropdown(panel, "Percent Display", 20, -191, 170, percentDisplayOptions, function()
        return settings.percentDisplay
    end, function(key)
        settings.percentDisplay = key
        NormalizeDisplaySettings()
        ApplyBarSettings()
        UpdateBarDisplay()
    end)

    local progressSegmentsDropdown = AddDropdown(panel, "Progress Segments", 20, -139, 170, progressSegmentOptions, function()
        return settings.progressSegments
    end, function(key)
        settings.progressSegments = key
        NormalizeProgressSettings()
        ApplyBarSettings()
        UpdateBarDisplay()
    end)

    local function RefreshOptionsControls()
        if lockCheckbox then lockCheckbox:SetChecked(settings.locked) end
        if onlyShowInPreyZoneCheckbox then onlyShowInPreyZoneCheckbox:SetChecked(settings.onlyShowInPreyZone) end
        if soundsCheckbox then soundsCheckbox:SetChecked(settings.soundsEnabled) end
        if ambushSoundCheckbox then ambushSoundCheckbox:SetChecked(settings.ambushSoundEnabled ~= false) end
        if ambushVisualCheckbox then ambushVisualCheckbox:SetChecked(settings.ambushVisualEnabled ~= false) end
        if showTicksCheckbox then showTicksCheckbox:SetChecked(settings.showTicks) end

        if scaleSlider then scaleSlider:SetValue(settings.scale) end
        if widthSlider then widthSlider:SetValue(settings.width) end
        if heightSlider then heightSlider:SetValue(settings.height) end
        if fontSizeSlider then fontSizeSlider:SetValue(settings.fontSize) end
        if enhanceSlider then enhanceSlider:SetValue(settings.soundEnhance or 0) end

        if textureDropdown and textureDropdown.PreydatorRefreshText then textureDropdown.PreydatorRefreshText() end
        if titleFontDropdown and titleFontDropdown.PreydatorRefreshText then titleFontDropdown.PreydatorRefreshText() end
        if percentFontDropdown and percentFontDropdown.PreydatorRefreshText then percentFontDropdown.PreydatorRefreshText() end
        if soundChannelDropdown and soundChannelDropdown.PreydatorRefreshText then soundChannelDropdown.PreydatorRefreshText() end
        if percentDisplayDropdown and percentDisplayDropdown.PreydatorRefreshText then percentDisplayDropdown.PreydatorRefreshText() end
        if progressSegmentsDropdown and progressSegmentsDropdown.PreydatorRefreshText then progressSegmentsDropdown.PreydatorRefreshText() end
        if ambushSoundDropdown and ambushSoundDropdown.PreydatorRefreshText then ambushSoundDropdown.PreydatorRefreshText() end
        if stage1SoundDropdown and stage1SoundDropdown.PreydatorRefreshText then stage1SoundDropdown.PreydatorRefreshText() end
        if stage2SoundDropdown and stage2SoundDropdown.PreydatorRefreshText then stage2SoundDropdown.PreydatorRefreshText() end
        if stage3SoundDropdown and stage3SoundDropdown.PreydatorRefreshText then stage3SoundDropdown.PreydatorRefreshText() end

        if fillColorSwatch and fillColorSwatch.PreydatorRefresh then fillColorSwatch.PreydatorRefresh() end
        if titleColorSwatch and titleColorSwatch.PreydatorRefresh then titleColorSwatch.PreydatorRefresh() end
        if percentColorSwatch and percentColorSwatch.PreydatorRefresh then percentColorSwatch.PreydatorRefresh() end

        for stageIndex = 1, (MAX_STAGE - 1) do
            stageNameEdits[stageIndex]:SetText(settings.stageLabels[stageIndex])
        end
        outZoneEdit:SetText(settings.outOfZoneLabel)
        ambushLabelEdit:SetText(settings.ambushCustomText)
    end

    panelRoot.PreydatorRefreshControls = RefreshOptionsControls

    local function AddSoundTestButton(text, x, y, stageIndex)
        local button = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
        button:SetSize(140, 24)
        button:SetPoint("TOPLEFT", panel, "TOPLEFT", x, y)
        button:SetText(text)
        button:SetScript("OnClick", function()
            state.stageSoundPlayed[stageIndex] = nil
            local path = ResolveStageSoundPath(stageIndex)
            if not path then
                print("Preydator: No stage " .. stageIndex .. " sound configured.")
                return
            end

            if not TryPlayStageSound(stageIndex, true) then
                print("Preydator: Stage " .. stageIndex .. " sound file failed to play. Ensure this file exists as .ogg: " .. tostring(path))
            end
        end)
    end

    AddSoundTestButton("Test Stage 1", 320, -631, 1)
    AddSoundTestButton("Test Stage 2", 320, -659, 2)
    AddSoundTestButton("Test Stage 3", 320, -687, 3)

    local note = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    note:SetPoint("TOPLEFT", panel, "TOPLEFT", 20, -575)
    note:SetWidth(260)
    note:SetJustifyH("LEFT")
    note:SetWordWrap(true)
    note:SetText("Enhance Sounds layers extra plays for perceived loudness. WoW does not expose true per-addon file volume.")

    if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
        local category = Settings.RegisterCanvasLayoutCategory(panelRoot, "Preydator", "Preydator")
        Settings.RegisterAddOnCategory(category)
        if type(category) == "table" then
            optionsCategoryID = category.ID or (category.GetID and category:GetID())
            panelRoot.categoryID = optionsCategoryID
        end
    elseif _G.InterfaceOptions_AddCategory then
        _G.InterfaceOptions_AddCategory(panelRoot)
    end

    optionsPanel = panelRoot
end

local function HandleSlashCommand(message)
    local trimmed = (message or ""):match("^%s*(.-)%s*$")
    local command, rest = trimmed:match("^(%S+)%s*(.-)$")
    local text = string.lower(command or "")

    if text == "debug" then
        EnsureDebugDB()
        local mode = string.lower(rest or "")

        if mode == "on" then
            settings.debugSounds = true
            debugDB.enabled = true
            print("Preydator: Debug logging enabled.")
            return
        end

        if mode == "off" then
            settings.debugSounds = false
            debugDB.enabled = false
            print("Preydator: Debug logging disabled.")
            return
        end

        if mode == "clear" then
            debugDB.entries = {}
            print("Preydator: Debug log cleared.")
            return
        end

        if mode == "show" or mode == "" then
            local total = #debugDB.entries
            if total == 0 then
                print("Preydator: Debug log is empty.")
                return
            end

            local fromIndex = math.max(1, total - 19)
            print("Preydator: Debug log (last " .. (total - fromIndex + 1) .. " of " .. total .. ")")
            for index = fromIndex, total do
                print("  " .. debugDB.entries[index])
            end
            return
        end

        print("Preydator: debug commands are 'debug on', 'debug off', 'debug show', 'debug clear'.")
        return
    end

    if text == "inspect" then
        PrintInspectState()
        return
    end

    if text == "show" then
        state.forceShowBar = true
        settings.forceShowBar = true
        UpdateBarDisplay()
        print("Preydator: Progress bar forced visible.")
        return
    end

    if text == "hide" then
        state.forceShowBar = false
        settings.forceShowBar = false
        UpdateBarDisplay()
        print("Preydator: Progress bar auto mode restored.")
        return
    end

    if text == "toggle" then
        state.forceShowBar = not state.forceShowBar
        settings.forceShowBar = state.forceShowBar
        UpdateBarDisplay()
        print("Preydator: Progress bar force show = " .. tostring(state.forceShowBar))
        return
    end

    if text == "options" or text == "open" then
        OpenOptionsPanel()
        return
    end

    if text == "mem" or text == "memory" then
        PrintMemoryUsage()
        return
    end

    print("Preydator commands: options | inspect | show | hide | toggle | mem | debug <on|off|show|clear>")
end

frame:SetScript("OnEvent", function(_, event, arg1, arg2)
    if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
        OnAddonLoaded()
        EnsureOptionsPanel()
        SlashCmdList["PREYDATOR"] = HandleSlashCommand
        return
    end

    if event == "ADDON_LOADED" then
        return
    end

    RunModuleHook("OnEvent", event, arg1, arg2)

    if event == "PLAYER_LOGIN" then
        EnsureBar()
        ApplyBarSettings()
        UpdateBarDisplay()
        return
    end

    if event == "CHAT_MSG_SYSTEM" or event == "CHAT_MSG_MONSTER_SAY" or event == "CHAT_MSG_MONSTER_YELL" or event == "CHAT_MSG_MONSTER_EMOTE" or event == "RAID_BOSS_EMOTE" then
        if ShouldScanAmbushChat() and IsAmbushSystemMessage(arg1, arg2) then
            TriggerAmbushAlert(arg1, event)
        end
        return
    end

    if event == "QUEST_TURNED_IN" and state.activeQuestID and arg1 == state.activeQuestID then
        state.killStageUntil = (GetTime and GetTime() or 0) + 8
        state.progressState = PREY_PROGRESS_FINAL
        state.progressPercent = 100
        UpdateBarDisplay()
    end

    UpdatePreyState()
end)

frame:SetScript("OnUpdate", function(_, elapsed)
    state.elapsedSinceUpdate = (state.elapsedSinceUpdate or 0) + (elapsed or 0)
    if state.elapsedSinceUpdate < UPDATE_INTERVAL_SECONDS then
        return
    end

    state.elapsedSinceUpdate = 0
    UpdatePreyState()
end)

frame:RegisterEvent("ADDON_LOADED")
