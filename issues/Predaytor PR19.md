---@diagnostic disable
-- luacheck: ignore 561

local ADDON_NAME = ...

local CreateFrame = _G.CreateFrame
local PlaySoundFile = _G.PlaySoundFile
local C_Timer = _G.C_Timer
local ColorPickerFrame = _G.ColorPickerFrame
local OpacitySliderFrame = _G.OpacitySliderFrame
local Enum = _G.Enum
local C_QuestLog = _G["C_QuestLog"]
local C_TaskQuest = _G["C_TaskQuest"]
local C_Map = _G["C_Map"]
local C_SuperTrack = _G["C_SuperTrack"]
local UIParent = _G.UIParent
local GetTime = _G.GetTime
local IsInInstance = _G.IsInInstance
local SlashCmdList = _G["SlashCmdList"]
local Settings = _G["Settings"]
local UIDropDownMenu_Initialize = _G.UIDropDownMenu_Initialize
local UIDropDownMenu_CreateInfo = _G.UIDropDownMenu_CreateInfo
local UIDropDownMenu_SetWidth = _G.UIDropDownMenu_SetWidth
local UIDropDownMenu_SetText = _G.UIDropDownMenu_SetText
local UIDropDownMenu_AddButton = _G.UIDropDownMenu_AddButton

_G.SLASH_PREYDATOR1 = "/pd"
_G.SLASH_PREYDATOR2 = nil

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
local DEFAULT_OUT_OF_ZONE_LABEL = _G.PreydatorL["No Sign in These Fields"]
local DEFAULT_AMBUSH_LABEL = _G.PreydatorL["AMBUSH"]
local DEFAULT_BLOODY_COMMAND_LABEL = _G.PreydatorL["Bloody Command"]
local PROGRESS_SEGMENTS_QUARTERS = "quarters"
local PROGRESS_SEGMENTS_THIRDS = "thirds"
local BAR_TICK_PCTS_BY_SEGMENT = {
    [PROGRESS_SEGMENTS_QUARTERS] = { 25, 50, 75 },
    [PROGRESS_SEGMENTS_THIRDS] = { 33, 66 },
-- Single core constants table to stay under WoW Lua ~200 locals per chunk limit.
local C = {}
C.PREY_PROGRESS_FINAL = 3
C.MAX_STAGE = 4
C.MAX_TICK_MARKS = 3
C.WIDGET_SHOWN = 1
-- C.IDLE_SOUND_PATH = "Interface\\AddOns\\Preydator\\sounds\\predator-idle.ogg"
C.ALERT_SOUND_PATH = "Interface\\AddOns\\Preydator\\sounds\\predator-alert.ogg"
C.AMBUSH_SOUND_PATH = "Interface\\AddOns\\Preydator\\sounds\\predator-ambush.ogg"
C.TORMENT_SOUND_PATH = "Interface\\AddOns\\Preydator\\sounds\\predator-torment.ogg"
C.KILL_SOUND_PATH = "Interface\\AddOns\\Preydator\\sounds\\predator-kill.ogg"
C.DEBUG_LOG_LIMIT = 200
C.DEFAULT_OUT_OF_ZONE_LABEL = _G.PreydatorL["No Sign in These Fields"]
C.DEFAULT_AMBUSH_LABEL = _G.PreydatorL["AMBUSH"]
C.DEFAULT_BLOODY_COMMAND_LABEL = _G.PreydatorL["Bloody Command"]
C.PROGRESS_SEGMENTS_QUARTERS = "quarters"
C.PROGRESS_SEGMENTS_THIRDS = "thirds"
C.BAR_TICK_PCTS_BY_SEGMENT = {
    [C.PROGRESS_SEGMENTS_QUARTERS] = { 25, 50, 75 },
    [C.PROGRESS_SEGMENTS_THIRDS] = { 33, 66 },
}
local PERCENT_DISPLAY_INSIDE = "inside"
local PERCENT_DISPLAY_INSIDE_BELOW = "inside_below"
local PERCENT_DISPLAY_BELOW_BAR = "below_bar"
PERCENT_DISPLAY_ABOVE_BAR = "above_bar"
PERCENT_DISPLAY_ABOVE_TICKS = "above_ticks"
local PERCENT_DISPLAY_UNDER_TICKS = "under_ticks"
local PERCENT_DISPLAY_OFF = "off"
local PERCENT_FALLBACK_STAGE = "stage"
local LAYER_MODE_ABOVE = "above"
local LAYER_MODE_BELOW = "below"
local LABEL_MODE_CENTER = "center"
local LABEL_MODE_LEFT = "left"
LABEL_MODE_LEFT_COMBINED = "left_combined"
local LABEL_MODE_LEFT_SUFFIX = "left_suffix"
local LABEL_MODE_RIGHT = "right"
LABEL_MODE_RIGHT_COMBINED = "right_combined"
local LABEL_MODE_RIGHT_PREFIX = "right_prefix"
local LABEL_MODE_SEPARATE = "separate"
local LABEL_MODE_NONE = "none"
LABEL_ROW_ABOVE = "above"
LABEL_ROW_BELOW = "below"
ORIENTATION_HORIZONTAL = "horizontal"
ORIENTATION_VERTICAL = "vertical"
FILL_DIRECTION_UP = "up"
FILL_DIRECTION_DOWN = "down"
local FILL_INSET = 3
local AMBUSH_ALERT_DURATION_SECONDS = 6
local AMBUSH_SOUND_COOLDOWN_SECONDS = 80
local QUEST_LISTEN_BURST_SECONDS = 6
local ACTIVE_PREY_QUEST_CACHE_SECONDS = 0.75
local AMBUSH_SOUND_ALERT = "alert"
local AMBUSH_SOUND_AMBUSH = "ambush"
local AMBUSH_SOUND_TORMENT = "torment"
local AMBUSH_SOUND_KILL = "kill"
local SOUND_FOLDER_PREFIX = "Interface\\AddOns\\Preydator\\sounds\\"
local DEFAULT_SOUND_FILENAMES = {
C.PERCENT_DISPLAY_INSIDE = "inside"
C.PERCENT_DISPLAY_INSIDE_BELOW = "inside_below"
C.PERCENT_DISPLAY_BELOW_BAR = "below_bar"
C.PERCENT_DISPLAY_ABOVE_BAR = "above_bar"
C.PERCENT_DISPLAY_ABOVE_TICKS = "above_ticks"
C.PERCENT_DISPLAY_UNDER_TICKS = "under_ticks"
C.PERCENT_DISPLAY_OFF = "off"
C.PERCENT_FALLBACK_STAGE = "stage"
C.LAYER_MODE_ABOVE = "above"
C.LAYER_MODE_BELOW = "below"
C.LABEL_MODE_CENTER = "center"
C.LABEL_MODE_LEFT = "left"
C.LABEL_MODE_LEFT_COMBINED = "left_combined"
C.LABEL_MODE_LEFT_SUFFIX = "left_suffix"
C.LABEL_MODE_RIGHT = "right"
C.LABEL_MODE_RIGHT_COMBINED = "right_combined"
C.LABEL_MODE_RIGHT_PREFIX = "right_prefix"
C.LABEL_MODE_SEPARATE = "separate"
C.LABEL_MODE_NONE = "none"
C.LABEL_ROW_ABOVE = "above"
C.LABEL_ROW_BELOW = "below"
C.ORIENTATION_HORIZONTAL = "horizontal"
C.ORIENTATION_VERTICAL = "vertical"
C.FILL_DIRECTION_UP = "up"
C.FILL_DIRECTION_DOWN = "down"
C.FILL_INSET = 3
C.AMBUSH_ALERT_DURATION_SECONDS = 6
C.AMBUSH_SOUND_COOLDOWN_SECONDS = 80
C.QUEST_LISTEN_BURST_SECONDS = 6
C.ACTIVE_PREY_QUEST_CACHE_SECONDS = 0.75
C.AMBUSH_SOUND_ALERT = "alert"
C.AMBUSH_SOUND_AMBUSH = "ambush"
C.AMBUSH_SOUND_TORMENT = "torment"
C.AMBUSH_SOUND_KILL = "kill"
C.SOUND_FOLDER_PREFIX = "Interface\\AddOns\\Preydator\\sounds\\"
C.DEFAULT_SOUND_FILENAMES = {
"predator-alert.ogg",
"predator-ambush.ogg",
"predator-snarl-01.ogg",
@@ -91,7 +93,7 @@
"predator-kills-its-prey-to-survive.ogg",
"echo-of-predation.ogg",
}
local PROTECTED_SOUND_FILENAMES = {
C.PROTECTED_SOUND_FILENAMES = {
["predator-alert.ogg"] = true,
["predator-ambush.ogg"] = true,
["predator-snarl-01.ogg"] = true,
@@ -102,81 +104,35 @@
["echo-of-predation.ogg"] = true,
}

local function GetExternalSoundCatalog()
    local entries = {}
    local seenPaths = {}

    local function addEntry(path, text)
        if type(path) ~= "string" or path == "" or type(text) ~= "string" or text == "" then
            return
        end

        local key = string.lower(path)
        if seenPaths[key] then
            return
        end

        seenPaths[key] = true
        entries[#entries + 1] = {
            key = path,
            text = text,
        }
    end

    local libStub = _G.LibStub
    if type(libStub) == "table" and type(libStub.GetLibrary) == "function" then
        local ok, lsm = pcall(libStub.GetLibrary, libStub, "LibSharedMedia-3.0", true)
        if ok and type(lsm) == "table" and type(lsm.List) == "function" and type(lsm.Fetch) == "function" then
            local soundNames = lsm:List("sound") or {}
            for _, soundName in ipairs(soundNames) do
                if soundName ~= "None" then
                    local path = lsm:Fetch("sound", soundName)
                    addEntry(path, "LSM: " .. soundName)
                end
            end
        end
    end

    table.sort(entries, function(left, right)
        local leftText = string.lower(tostring(left and left.text or ""))
        local rightText = string.lower(tostring(right and right.text or ""))
        if leftText == rightText then
            return tostring(left and left.key or "") < tostring(right and right.key or "")
        end
        return leftText < rightText
    end)

    return entries
end
local DEFAULT_STAGE_LABELS = {
C.DEFAULT_STAGE_LABELS = {
[1] = _G.PreydatorL["Scent in the Wind"],
[2] = _G.PreydatorL["Blood in the Shadows"],
[3] = _G.PreydatorL["Echoes of the Kill"],
[4] = _G.PreydatorL["Feast of the Fang"],
}
local STAGE_PCT_BY_SEGMENT = {
    [PROGRESS_SEGMENTS_QUARTERS] = {
C.STAGE_PCT_BY_SEGMENT = {
    [C.PROGRESS_SEGMENTS_QUARTERS] = {
[1] = 25,
[2] = 50,
[3] = 75,
[4] = 100,
},
    [PROGRESS_SEGMENTS_THIRDS] = {
    [C.PROGRESS_SEGMENTS_THIRDS] = {
[1] = 0,
[2] = 33,
[3] = 66,
[4] = 100,
},
}

local TEXTURE_PRESETS = {
C.TEXTURE_PRESETS = {
default = "Interface\\TARGETINGFRAME\\UI-StatusBar",
flat = "Interface\\Buttons\\WHITE8x8",
raid = "Interface\\RaidFrame\\Raid-Bar-Hp-Fill",
classic = "Interface\\PaperDollInfoFrame\\UI-Character-Skills-Bar",
}

local FONT_PRESETS = {
C.FONT_PRESETS = {
frizqt = "Fonts\\FRIZQT__.TTF",
arialn = "Fonts\\ARIALN.TTF",
skurri = "Fonts\\SKURRI.TTF",
@@ -185,7 +141,7 @@

-- Astalor Bloodsworn (Bloody Command) sound file IDs sourced from Blizzard game data.
-- Applied via MuteSoundFile / UnmuteSoundFile to suppress ambient dialogue during hunts.
local ARATOR_SOUND_IDS = {
C.ARATOR_SOUND_IDS = {
7507693, 7507690, 7507696, 7507699, 7507702, 7507712, 7507722,
7525928, 7525931, 7525934, 7525937, 7525940,
7250945, 7250953, 7250960, 7250968, 7250975, 7250984, 7250991, 7250998,
@@ -203,6 +159,53 @@
7250608, 7250614, 7250618, 7250629, 7250635, 7250642, 7250646, 7250652,
}

local function GetExternalSoundCatalog()
    local entries = {}
    local seenPaths = {}

    local function addEntry(path, text)
        if type(path) ~= "string" or path == "" or type(text) ~= "string" or text == "" then
            return
        end

        local key = string.lower(path)
        if seenPaths[key] then
            return
        end

        seenPaths[key] = true
        entries[#entries + 1] = {
            key = path,
            text = text,
        }
    end

    local libStub = _G.LibStub
    if type(libStub) == "table" and type(libStub.GetLibrary) == "function" then
        local ok, lsm = pcall(libStub.GetLibrary, libStub, "LibSharedMedia-3.0", true)
        if ok and type(lsm) == "table" and type(lsm.List) == "function" and type(lsm.Fetch) == "function" then
            local soundNames = lsm:List("sound") or {}
            for _, soundName in ipairs(soundNames) do
                if soundName ~= "None" then
                    local path = lsm:Fetch("sound", soundName)
                    addEntry(path, "LSM: " .. soundName)
                end
            end
        end
    end

    table.sort(entries, function(left, right)
        local leftText = string.lower(tostring(left and left.text or ""))
        local rightText = string.lower(tostring(right and right.text or ""))
        if leftText == rightText then
            return tostring(left and left.key or "") < tostring(right and right.key or "")
        end
        return leftText < rightText
    end)

    return entries
end

-- Forward declaration for helpers used before their implementation block.
local NormalizeSoundSettings
local GetSoundPathForKey
@@ -234,24 +237,24 @@
textureKey = "default",
titleFontKey = "frizqt",
percentFontKey = "frizqt",
    outOfZoneLabel = DEFAULT_OUT_OF_ZONE_LABEL,
    outOfZoneLabel = C.DEFAULT_OUT_OF_ZONE_LABEL,
outOfZonePrefix = "",
    ambushLabel = DEFAULT_AMBUSH_LABEL,
    ambushLabel = C.DEFAULT_AMBUSH_LABEL,
ambushPrefix = "AMBUSH: ",
ambushSuffix = "preyTargetName",
bloodyCommandPrefix = "Bloody Command: ",
bloodyCommandSuffix = "bloodyCommandSourceName",
stageLabels = {
        [1] = DEFAULT_STAGE_LABELS[1],
        [2] = DEFAULT_STAGE_LABELS[2],
        [3] = DEFAULT_STAGE_LABELS[3],
        [4] = DEFAULT_STAGE_LABELS[4],
        [1] = C.DEFAULT_STAGE_LABELS[1],
        [2] = C.DEFAULT_STAGE_LABELS[2],
        [3] = C.DEFAULT_STAGE_LABELS[3],
        [4] = C.DEFAULT_STAGE_LABELS[4],
},
stageSounds = {
        [1] = AMBUSH_SOUND_PATH,
        [1] = C.AMBUSH_SOUND_PATH,
[2] = "Interface\\AddOns\\Preydator\\sounds\\predator-snarl-01.ogg",
        [3] = TORMENT_SOUND_PATH,
        [4] = KILL_SOUND_PATH,
        [3] = C.TORMENT_SOUND_PATH,
        [4] = C.KILL_SOUND_PATH,
},
soundsEnabled = true,
soundChannel = "SFX",
@@ -356,21 +359,21 @@
soundDefaultsPromptSeenVersion = nil,
showTicks = true,
showSparkLine = false,
    tickLayerMode = LAYER_MODE_ABOVE,
    tickLayerMode = C.LAYER_MODE_ABOVE,
labelRowPosition = "above",
orientation = "horizontal",
verticalFillDirection = "up",
verticalTextSide = "right",
verticalPercentSide = "center",
showVerticalTickPercent = false,
    verticalPercentDisplay = PERCENT_DISPLAY_INSIDE,
    verticalPercentDisplay = C.PERCENT_DISPLAY_INSIDE,
verticalTextOffset = 10,
verticalPercentOffset = 10,
verticalTextAlign = "separate",
showAlignmentDot = false,
verticalSideOffset = 10,
    progressSegments = PROGRESS_SEGMENTS_THIRDS,
    stageLabelMode = LABEL_MODE_CENTER,
    progressSegments = C.PROGRESS_SEGMENTS_THIRDS,
    stageLabelMode = C.LABEL_MODE_CENTER,
stageSuffixLabels = {
[1] = "",
[2] = "",
@@ -379,8 +382,8 @@
},
borderColorLinked = true,
borderColor = { 0.8, 0.2, 0.2, 0.85 },
    percentDisplay = PERCENT_DISPLAY_INSIDE,
    percentFallbackMode = PERCENT_FALLBACK_STAGE,
    percentDisplay = C.PERCENT_DISPLAY_INSIDE,
    percentFallbackMode = C.PERCENT_FALLBACK_STAGE,
customizationV2 = {
moduleEnabled = {
bar = true,
@@ -397,6 +400,27 @@
local Preydator = _G.Preydator or {}
_G.Preydator = Preydator
Preydator.modules = Preydator.modules or {}
-- Attached to addon table instead of chunk-local table to stay under WoW's ~200
-- locals-per-chunk limit for monolithic core file.
Preydator.PreyWidgetNumericSnapshotKeys = {
    "progressPercentage",
    "progressPercent",
    "fillPercentage",
    "percentage",
    "percent",
    "progress",
    "progressValue",
    "barValue",
    "value",
    "currentValue",
    "barMin",
    "barMax",
    "maxValue",
    "totalValue",
    "total",
    "max",
    "range",
}

function Preydator:RegisterModule(name, module)
if type(name) ~= "string" or name == "" or type(module) ~= "table" then
@@ -461,9 +485,11 @@

Preydator:RegisterModule("CustomizationStateV2", CustomizationStateV2)

local frame = CreateFrame("Frame")
local warnedMissingSoundPaths = {}

-- Root event frame (ScriptDefer.lua only adds RunAfterCurrentScriptsPass).
local frame = CreateFrame("Frame")

-- UI frame references grouped in a table to reduce local variable count from ~30 to 1
local UI = {
barFrame = false,
@@ -506,10 +532,10 @@
end

settings.stageSounds = settings.stageSounds or {}
    settings.stageSounds[1] = AMBUSH_SOUND_PATH
    settings.stageSounds[1] = C.AMBUSH_SOUND_PATH
settings.stageSounds[2] = "Interface\\AddOns\\Preydator\\sounds\\predator-snarl-01.ogg"
    settings.stageSounds[3] = TORMENT_SOUND_PATH
    settings.stageSounds[4] = KILL_SOUND_PATH
    settings.stageSounds[3] = C.TORMENT_SOUND_PATH
    settings.stageSounds[4] = C.KILL_SOUND_PATH

settings.ambushSoundPath = "Interface\\AddOns\\Preydator\\sounds\\well-we-ve-prepared-a-trap-for-this-predator.ogg"
settings.bloodyCommandSoundPath = "Interface\\AddOns\\Preydator\\sounds\\predator-kills-its-prey-to-survive.ogg"
@@ -522,7 +548,7 @@
seen[string.lower(fileName)] = true
end
end
    for _, fileName in ipairs(DEFAULT_SOUND_FILENAMES) do
    for _, fileName in ipairs(C.DEFAULT_SOUND_FILENAMES) do
local key = string.lower(fileName)
if not seen[key] then
settings.soundFileNames[#settings.soundFileNames + 1] = fileName
@@ -677,10 +703,22 @@
}

local UPDATE_INTERVAL_SECONDS = 0.5
local WIDGET_SETUP_FRESH_SECONDS = 2.0
local ExtractWidgetQuestID
local FindPreyWidgetProgressState

ExtractWidgetQuestID = function(info)
    local PW = Preydator:GetModule("PreyWidgetRuntime")
    return PW and PW:ExtractQuestID(info) or nil
end

FindPreyWidgetProgressState = function(activeQuestID)
    local PW = Preydator:GetModule("PreyWidgetRuntime")
    if not PW then
        return nil, nil, nil, nil
    end
    return PW:FindProgressState(activeQuestID)
end

Preydator.GetState = function()
return state
end
@@ -729,7 +767,7 @@
end
end

    return DEFAULT_STAGE_LABELS[stage] or "Unknown"
    return C.DEFAULT_STAGE_LABELS[stage] or "Unknown"
end

local function Clamp(value, minValue, maxValue)
@@ -900,11 +938,11 @@
local runtime = GetRuntimeModule("SettingsRuntime")
if runtime and type(runtime.NormalizeLabelSettings) == "function" then
runtime:NormalizeLabelSettings(settings, {
            maxStage = MAX_STAGE,
            defaultStageLabels = DEFAULT_STAGE_LABELS,
            defaultOutOfZoneLabel = DEFAULT_OUT_OF_ZONE_LABEL,
            defaultAmbushLabel = DEFAULT_AMBUSH_LABEL,
            defaultBloodyCommandLabel = DEFAULT_BLOODY_COMMAND_LABEL,
            maxStage = C.MAX_STAGE,
            defaultStageLabels = C.DEFAULT_STAGE_LABELS,
            defaultOutOfZoneLabel = C.DEFAULT_OUT_OF_ZONE_LABEL,
            defaultAmbushLabel = C.DEFAULT_AMBUSH_LABEL,
            defaultBloodyCommandLabel = C.DEFAULT_BLOODY_COMMAND_LABEL,
})
return
end
@@ -913,7 +951,7 @@
settings.stageLabels = {}
end

    for stage = 1, MAX_STAGE do
    for stage = 1, C.MAX_STAGE do
local label = settings.stageLabels[stage]
if type(label) ~= "string" then
local legacy = settings.stageLabels[tostring(stage)]
@@ -923,22 +961,22 @@
end

if type(label) ~= "string" then
            label = DEFAULT_STAGE_LABELS[stage] or ""
            label = C.DEFAULT_STAGE_LABELS[stage] or ""
end

settings.stageLabels[stage] = label
end

if type(settings.outOfZoneLabel) ~= "string" or settings.outOfZoneLabel == "" then
        settings.outOfZoneLabel = DEFAULT_OUT_OF_ZONE_LABEL
        settings.outOfZoneLabel = C.DEFAULT_OUT_OF_ZONE_LABEL
end

if type(settings.outOfZonePrefix) ~= "string" then
settings.outOfZonePrefix = ""
end

if type(settings.ambushLabel) ~= "string" or settings.ambushLabel == "" then
        settings.ambushLabel = DEFAULT_AMBUSH_LABEL
        settings.ambushLabel = C.DEFAULT_AMBUSH_LABEL
end

if type(settings.ambushPrefix) ~= "string" then
@@ -1004,7 +1042,7 @@
runtime:NormalizeDisplaySettings(settings, {
constants = Preydator.Constants,
defaults = DEFAULTS,
            maxStage = MAX_STAGE,
            maxStage = C.MAX_STAGE,
clamp = Clamp,
})
return
@@ -1016,37 +1054,37 @@

local mode = settings.percentDisplay
if mode == "below" then
        mode = PERCENT_DISPLAY_BELOW_BAR
        mode = C.PERCENT_DISPLAY_BELOW_BAR
end

    if mode ~= PERCENT_DISPLAY_INSIDE
        and mode ~= PERCENT_DISPLAY_BELOW_BAR
    if mode ~= C.PERCENT_DISPLAY_INSIDE
        and mode ~= C.PERCENT_DISPLAY_BELOW_BAR
and mode ~= "above_bar"
and mode ~= "above_ticks"
        and mode ~= PERCENT_DISPLAY_UNDER_TICKS
        and mode ~= PERCENT_DISPLAY_OFF
        and mode ~= C.PERCENT_DISPLAY_UNDER_TICKS
        and mode ~= C.PERCENT_DISPLAY_OFF
then
        settings.percentDisplay = PERCENT_DISPLAY_INSIDE
        settings.percentDisplay = C.PERCENT_DISPLAY_INSIDE
else
settings.percentDisplay = mode
end

    settings.tickLayerMode = LAYER_MODE_ABOVE
    settings.tickLayerMode = C.LAYER_MODE_ABOVE

    settings.percentFallbackMode = PERCENT_FALLBACK_STAGE
    settings.percentFallbackMode = C.PERCENT_FALLBACK_STAGE

local labelMode = settings.stageLabelMode
    if labelMode ~= LABEL_MODE_CENTER
        and labelMode ~= LABEL_MODE_LEFT
    if labelMode ~= C.LABEL_MODE_CENTER
        and labelMode ~= C.LABEL_MODE_LEFT
and labelMode ~= "left_combined"
        and labelMode ~= LABEL_MODE_LEFT_SUFFIX
        and labelMode ~= LABEL_MODE_RIGHT
        and labelMode ~= C.LABEL_MODE_LEFT_SUFFIX
        and labelMode ~= C.LABEL_MODE_RIGHT
and labelMode ~= "right_combined"
        and labelMode ~= LABEL_MODE_RIGHT_PREFIX
        and labelMode ~= LABEL_MODE_SEPARATE
        and labelMode ~= LABEL_MODE_NONE
        and labelMode ~= C.LABEL_MODE_RIGHT_PREFIX
        and labelMode ~= C.LABEL_MODE_SEPARATE
        and labelMode ~= C.LABEL_MODE_NONE
then
        settings.stageLabelMode = LABEL_MODE_CENTER
        settings.stageLabelMode = C.LABEL_MODE_CENTER
end

if settings.labelRowPosition ~= "above" and settings.labelRowPosition ~= "below" then
@@ -1079,21 +1117,21 @@
end

local verticalPercentDisplay = settings.verticalPercentDisplay
    if verticalPercentDisplay == PERCENT_DISPLAY_INSIDE_BELOW then
        verticalPercentDisplay = PERCENT_DISPLAY_INSIDE
    if verticalPercentDisplay == C.PERCENT_DISPLAY_INSIDE_BELOW then
        verticalPercentDisplay = C.PERCENT_DISPLAY_INSIDE
end
    if verticalPercentDisplay ~= PERCENT_DISPLAY_INSIDE
        and verticalPercentDisplay ~= PERCENT_DISPLAY_BELOW_BAR
        and verticalPercentDisplay ~= PERCENT_DISPLAY_ABOVE_BAR
        and verticalPercentDisplay ~= PERCENT_DISPLAY_OFF
    if verticalPercentDisplay ~= C.PERCENT_DISPLAY_INSIDE
        and verticalPercentDisplay ~= C.PERCENT_DISPLAY_BELOW_BAR
        and verticalPercentDisplay ~= C.PERCENT_DISPLAY_ABOVE_BAR
        and verticalPercentDisplay ~= C.PERCENT_DISPLAY_OFF
then
        settings.verticalPercentDisplay = PERCENT_DISPLAY_INSIDE
        settings.verticalPercentDisplay = C.PERCENT_DISPLAY_INSIDE
else
settings.verticalPercentDisplay = verticalPercentDisplay
end

    if settings.percentDisplay == PERCENT_DISPLAY_INSIDE_BELOW then
        settings.percentDisplay = PERCENT_DISPLAY_INSIDE
    if settings.percentDisplay == C.PERCENT_DISPLAY_INSIDE_BELOW then
        settings.percentDisplay = C.PERCENT_DISPLAY_INSIDE
end

settings.showAlignmentDot = false
@@ -1128,7 +1166,7 @@

local verticalWidth = tonumber(settings.verticalWidth)
if not verticalWidth then
        if settings.orientation == ORIENTATION_VERTICAL and legacyWidth then
        if settings.orientation == C.ORIENTATION_VERTICAL and legacyWidth then
verticalWidth = legacyWidth
else
verticalWidth = DEFAULTS.verticalWidth
@@ -1138,7 +1176,7 @@

local verticalHeight = tonumber(settings.verticalHeight)
if not verticalHeight then
        if settings.orientation == ORIENTATION_VERTICAL and legacyHeight then
        if settings.orientation == C.ORIENTATION_VERTICAL and legacyHeight then
verticalHeight = legacyHeight
else
verticalHeight = DEFAULTS.verticalHeight
@@ -1165,7 +1203,7 @@

settings.verticalSideOffset = settings.verticalTextOffset

    if settings.orientation == ORIENTATION_VERTICAL then
    if settings.orientation == C.ORIENTATION_VERTICAL then
settings.width = settings.verticalWidth
settings.height = settings.verticalHeight
else
@@ -1188,15 +1226,15 @@
if type(settings.stageSuffixLabels) ~= "table" then
settings.stageSuffixLabels = {}
end
    for i = 1, MAX_STAGE do
    for i = 1, C.MAX_STAGE do
if type(settings.stageSuffixLabels[i]) ~= "string" then
settings.stageSuffixLabels[i] = ""
end
end
end

Preydator.GetRenderedVerticalPercent = function(rawPct, fillDirection)
    if fillDirection == FILL_DIRECTION_DOWN then
    if fillDirection == C.FILL_DIRECTION_DOWN then
return 100 - rawPct
end

@@ -1213,7 +1251,7 @@
local topRelative = "TOP" .. relSidePoint
local middleRelative = relSidePoint
local bottomRelative = "BOTTOM" .. relSidePoint
    local xOffset = (side == "left") and -(offset + FILL_INSET) or (offset + FILL_INSET)
    local xOffset = (side == "left") and -(offset + C.FILL_INSET) or (offset + C.FILL_INSET)
local gap = 14

if align == "top" then
@@ -1327,8 +1365,8 @@
end

local mode = settings.progressSegments
    if mode ~= PROGRESS_SEGMENTS_QUARTERS and mode ~= PROGRESS_SEGMENTS_THIRDS then
        settings.progressSegments = PROGRESS_SEGMENTS_QUARTERS
    if mode ~= C.PROGRESS_SEGMENTS_QUARTERS and mode ~= C.PROGRESS_SEGMENTS_THIRDS then
        settings.progressSegments = C.PROGRESS_SEGMENTS_QUARTERS
return
end

@@ -1455,13 +1493,17 @@
return IsAnyTrackedPreyWidgetShown()
end,
isTrackedPreyWidgetPresent = function()
                if preyHuntIconFrame ~= nil then
                local PW = Preydator:GetModule("PreyWidgetRuntime")
                if PW and PW.PrimaryIconFrame and PW:PrimaryIconFrame() ~= nil then
return true
end

                for frameRef in pairs(PREY_WIDGET_FRAMES) do
                    if frameRef ~= nil then
                        return true
                local framesWeak = PW and PW.TrackedWeakFrames and PW:TrackedWeakFrames()
                if framesWeak then
                    for frameRef in pairs(framesWeak) do
                        if frameRef ~= nil then
                            return true
                        end
end
end

@@ -1578,16 +1620,16 @@
if runtime and type(runtime.GetSoundPathForKey) == "function" then
return runtime:GetSoundPathForKey(soundKey, fallbackPath, {
soundKeys = {
                alert = AMBUSH_SOUND_ALERT,
                ambush = AMBUSH_SOUND_AMBUSH,
                torment = AMBUSH_SOUND_TORMENT,
                kill = AMBUSH_SOUND_KILL,
                alert = C.AMBUSH_SOUND_ALERT,
                ambush = C.AMBUSH_SOUND_AMBUSH,
                torment = C.AMBUSH_SOUND_TORMENT,
                kill = C.AMBUSH_SOUND_KILL,
},
soundPaths = {
                alert = ALERT_SOUND_PATH,
                ambush = AMBUSH_SOUND_PATH,
                torment = TORMENT_SOUND_PATH,
                kill = KILL_SOUND_PATH,
                alert = C.ALERT_SOUND_PATH,
                ambush = C.AMBUSH_SOUND_PATH,
                torment = C.TORMENT_SOUND_PATH,
                kill = C.KILL_SOUND_PATH,
},
})
end
@@ -1630,15 +1672,15 @@
if runtime and type(runtime.GetCurrentActivePreyQuestCached) == "function" then
return runtime:GetCurrentActivePreyQuestCached(maxAgeSeconds, state, {
getTime = GetTime,
            defaultMaxAgeSeconds = ACTIVE_PREY_QUEST_CACHE_SECONDS,
            defaultMaxAgeSeconds = C.ACTIVE_PREY_QUEST_CACHE_SECONDS,
getCurrentActivePreyQuest = GetCurrentActivePreyQuest,
})
end

local now = GetTime and GetTime() or 0
local maxAge = tonumber(maxAgeSeconds)
if not maxAge or maxAge < 0 then
        maxAge = ACTIVE_PREY_QUEST_CACHE_SECONDS
        maxAge = C.ACTIVE_PREY_QUEST_CACHE_SECONDS
end

if (now - (state.cachedActivePreyQuestAt or 0)) > maxAge then
@@ -1653,7 +1695,7 @@
if runtime and type(runtime.ArmQuestListenBurst) == "function" then
runtime:ArmQuestListenBurst(durationSeconds, state, {
getTime = GetTime,
            defaultBurstSeconds = QUEST_LISTEN_BURST_SECONDS,
            defaultBurstSeconds = C.QUEST_LISTEN_BURST_SECONDS,
getCurrentActivePreyQuest = GetCurrentActivePreyQuest,
})
return
@@ -1662,7 +1704,7 @@
local now = GetTime and GetTime() or 0
local duration = tonumber(durationSeconds)
if not duration or duration <= 0 then
        duration = QUEST_LISTEN_BURST_SECONDS
        duration = C.QUEST_LISTEN_BURST_SECONDS
end
local untilTime = now + duration
if untilTime > (state.questListenUntil or 0) then
@@ -1792,11 +1834,11 @@
end

if settings.ambushVisualEnabled ~= false then
        state.ambushAlertUntil = now + AMBUSH_ALERT_DURATION_SECONDS
        state.ambushAlertUntil = now + C.AMBUSH_ALERT_DURATION_SECONDS
end

if settings.ambushSoundEnabled ~= false then
        local nextSoundAt = (state.lastAmbushSoundAt or 0) + AMBUSH_SOUND_COOLDOWN_SECONDS
        local nextSoundAt = (state.lastAmbushSoundAt or 0) + C.AMBUSH_SOUND_COOLDOWN_SECONDS
if now >= nextSoundAt then
local ambushPath = Preydator.API.ResolveAmbushSoundPath()
TryPlaySound(ambushPath)
@@ -2013,7 +2055,7 @@
local entry = string.format("%0.3f | %s | %s", now, tostring(kind or "?"), tostring(message or ""))
table.insert(debugDB.entries, entry)

    while #debugDB.entries > DEBUG_LOG_LIMIT do
    while #debugDB.entries > C.DEBUG_LOG_LIMIT do
table.remove(debugDB.entries, 1)
end

@@ -2162,16 +2204,16 @@
return true
end

    if stage == MAX_STAGE then
        local fallbackPath = Preydator.API.ResolveStageSoundPath(MAX_STAGE - 1)
    if stage == C.MAX_STAGE then
        local fallbackPath = Preydator.API.ResolveStageSoundPath(C.MAX_STAGE - 1)
if fallbackPath then
            AddDebugLog("TryPlayStageSound", "stage=" .. tostring(MAX_STAGE) .. " | primary failed, trying fallback stage=" .. tostring(MAX_STAGE - 1) .. " | path=" .. tostring(fallbackPath), true)
            AddDebugLog("TryPlayStageSound", "stage=" .. tostring(C.MAX_STAGE) .. " | primary failed, trying fallback stage=" .. tostring(C.MAX_STAGE - 1) .. " | path=" .. tostring(fallbackPath), true)
if TryPlaySound(fallbackPath, ignoreSoundToggle) then
state.stageSoundPlayed[stage] = true
                AddDebugLog("TryPlayStageSound", "stage=" .. tostring(MAX_STAGE) .. " | fallback stage=" .. tostring(MAX_STAGE - 1) .. " success", true)
                AddDebugLog("TryPlayStageSound", "stage=" .. tostring(C.MAX_STAGE) .. " | fallback stage=" .. tostring(C.MAX_STAGE - 1) .. " success", true)
return true
end
            AddDebugLog("TryPlayStageSound", "stage=" .. tostring(MAX_STAGE) .. " | fallback stage=" .. tostring(MAX_STAGE - 1) .. " also failed", true)
            AddDebugLog("TryPlayStageSound", "stage=" .. tostring(C.MAX_STAGE) .. " | fallback stage=" .. tostring(C.MAX_STAGE - 1) .. " also failed", true)
end
end

@@ -2211,12 +2253,12 @@
end

function barPositionUtil.GetCurrentDimensions()
    local orientation = settings and settings.orientation or ORIENTATION_HORIZONTAL
    local orientation = settings and settings.orientation or C.ORIENTATION_HORIZONTAL
local frameScale
local baseWidth
local baseHeight

    if orientation == ORIENTATION_VERTICAL then
    if orientation == C.ORIENTATION_VERTICAL then
frameScale = Clamp(tonumber(settings and settings.verticalScale) or DEFAULTS.verticalScale, 0.5, 2)
baseWidth = Clamp(math.floor((tonumber(settings and settings.verticalWidth) or DEFAULTS.verticalWidth) + 0.5), 10, 60)
baseHeight = Clamp(math.floor((tonumber(settings and settings.verticalHeight) or DEFAULTS.verticalHeight) + 0.5), 100, 350)
@@ -2259,11 +2301,11 @@

ApplyAratorSilencing = function()
if settings and settings.silenceArator then
        for _, soundID in ipairs(ARATOR_SOUND_IDS) do
        for _, soundID in ipairs(C.ARATOR_SOUND_IDS) do
MuteSoundFile(soundID)
end
else
        for _, soundID in ipairs(ARATOR_SOUND_IDS) do
        for _, soundID in ipairs(C.ARATOR_SOUND_IDS) do
UnmuteSoundFile(soundID)
end
end
@@ -2352,7 +2394,7 @@
local isEditModePreview = editModeFrame and editModeFrame.IsShown and editModeFrame:IsShown()
local allowStageFourMapClickFallback = settings
and state
            and state.stage == MAX_STAGE
            and state.stage == C.MAX_STAGE

if allowStageFourMapClickFallback and not isEditModePreview and button == "LeftButton" then
self.PreydatorHandledMapClick = true
@@ -2419,28 +2461,28 @@
if button == "LeftButton"
and settings
and state
            and state.stage == MAX_STAGE
            and state.stage == C.MAX_STAGE
then
TryOpenPreyQuestOnMap()
end
end)

local bg = UI.barFrame:CreateTexture(nil, "background")
    bg:SetPoint("BOTTOMLEFT", UI.barFrame, "BOTTOMLEFT", FILL_INSET, FILL_INSET)
    bg:SetPoint("TOPRIGHT", UI.barFrame, "TOPRIGHT", -FILL_INSET, -FILL_INSET)
    bg:SetPoint("BOTTOMLEFT", UI.barFrame, "BOTTOMLEFT", C.FILL_INSET, C.FILL_INSET)
    bg:SetPoint("TOPRIGHT", UI.barFrame, "TOPRIGHT", -C.FILL_INSET, -C.FILL_INSET)
bg:SetColorTexture(0, 0, 0, 0.6)
UI.barFrame.BackgroundTexture = bg

UI.barFill = UI.barFrame:CreateTexture(nil, "artwork")
    UI.barFill:SetPoint("BOTTOMLEFT", UI.barFrame, "BOTTOMLEFT", FILL_INSET, FILL_INSET)
    UI.barFill:SetPoint("BOTTOMLEFT", UI.barFrame, "BOTTOMLEFT", C.FILL_INSET, C.FILL_INSET)
UI.barFill:SetSize(0, 18)
UI.barFill:SetTexCoord(0, 1, 0, 1)
UI.barFill:SetHorizTile(false)
UI.barFill:SetVertTile(false)
UI.barFill:SetColorTexture(0.85, 0.2, 0.2, 0.95)

UI.barSpark = UI.barFrame:CreateTexture(nil, "overlay")
    UI.barSpark:SetPoint("BOTTOMLEFT", UI.barFrame, "BOTTOMLEFT", FILL_INSET, FILL_INSET)
    UI.barSpark:SetPoint("BOTTOMLEFT", UI.barFrame, "BOTTOMLEFT", C.FILL_INSET, C.FILL_INSET)
UI.barSpark:SetSize(2, 18)
UI.barSpark:SetColorTexture(1, 0.95, 0.75, 0.9)
UI.barSpark:SetDrawLayer("OVERLAY", 3)
@@ -2479,7 +2521,7 @@
UI.barAlignmentDot:SetDrawLayer("OVERLAY", 7)
UI.barAlignmentDot:Hide()

    for index = 1, MAX_TICK_MARKS do
    for index = 1, C.MAX_TICK_MARKS do
local pct = (index * 25)
local tickMark = UI.barFrame:CreateTexture(nil, "overlay")
tickMark:SetColorTexture(1, 1, 1, 0.35)
@@ -2512,7 +2554,7 @@
return 3
end

    if progressState == PREY_PROGRESS_FINAL then
    if progressState == C.PREY_PROGRESS_FINAL then
return 4
end

@@ -2833,7 +2875,12 @@
state.lastWidgetSeenAt = 0
state.lastWidgetSetupAt = 0
state.lastWidgetBoundQuestID = nil
    preyWidgetInfoCache = nil
    do
        local PW = Preydator:GetModule("PreyWidgetRuntime")
        if PW and PW.ClearSnapshot then
            PW:ClearSnapshot()
        end
    end
state.stageSoundPlayed = {}
state.stageSoundAttempted = {}
state.lastStateDebugSnapshot = nil
@@ -2920,68 +2967,43 @@

local AttachStageFourMapClick

local WIDGET_SUPPRESSION_WAS_SHOWN = setmetatable({}, { __mode = "k" })
local WIDGET_SUPPRESSION_WAS_ALPHA = setmetatable({}, { __mode = "k" })
local WIDGET_SUPPRESSION_HOOKED = setmetatable({}, { __mode = "k" })
local STAGE_FOUR_CLICK_HOOKED = setmetatable({}, { __mode = "k" })
local PREY_WIDGET_FRAMES = setmetatable({}, { __mode = "k" })
local preyHuntMixinHooked = false
local preyHuntIconFrame = nil
local preyWidgetInfoCache = nil  -- snapshot from mixin Setup hook; avoids taint-prone GetAllWidgetsBySetID scans
local suppressionRetryPending = false
local suppressionRetryCount = 0

local function CancelFrameScriptedEffect(frameRef)
    local effectController = frameRef and frameRef.effectController or nil
    if effectController and type(effectController.CancelEffect) == "function" then
        pcall(effectController.CancelEffect, effectController)
    end
end

-- Safe: identifies prey hunt frames by checking mixin-specific function presence.
-- Does NOT read any secret-number fields (widgetID, widgetType, etc.).
local function IsPreyHuntProgressFrame(frameRef)
    if not frameRef then
        return false
    end
    -- ResetAnimState and AnimIn are defined only in UIWidgetTemplatePreyHuntProgressMixin.
    return type(frameRef.ResetAnimState) == "function"
        and type(frameRef.AnimIn) == "function"
local function PreyWidgetRuntimeModule()
    return Preydator:GetModule("PreyWidgetRuntime")
end

local function CaptureLivePreyHuntFrames()
    local container = _G.UIWidgetPowerBarContainerFrame
    if not container or not container.GetChildren then
        return
    end

    local okChildren, children = pcall(function()
        return { container:GetChildren() }
    end)
    if not okChildren or type(children) ~= "table" then
        return
    local PW = PreyWidgetRuntimeModule()
    if PW and PW.CaptureLiveFrames then
        PW:CaptureLiveFrames()
end
end

    for _, child in ipairs(children) do
        if IsPreyHuntProgressFrame(child) then
            PREY_WIDGET_FRAMES[child] = true
            preyHuntIconFrame = child
        end
local function EnsurePreyHuntMixinSuppressionHook()
    local PW = PreyWidgetRuntimeModule()
    if PW and PW.EnsureMixinHook then
        PW:EnsureMixinHook()
end
end

IsAnyTrackedPreyWidgetShown = function()
    if preyHuntIconFrame and preyHuntIconFrame.IsShown and preyHuntIconFrame:IsShown() then
        return true
    end
    local PW = PreyWidgetRuntimeModule()
    return PW and PW.IsAnyTrackedWidgetShown and PW:IsAnyTrackedWidgetShown() or false
end

    for frameRef in pairs(PREY_WIDGET_FRAMES) do
        if frameRef and frameRef.IsShown and frameRef:IsShown() then
            return true
        end
    end
local WIDGET_SUPPRESSION_WAS_SHOWN = setmetatable({}, { __mode = "k" })
local WIDGET_SUPPRESSION_WAS_ALPHA = setmetatable({}, { __mode = "k" })
local WIDGET_SUPPRESSION_HOOKED = setmetatable({}, { __mode = "k" })
local STAGE_FOUR_CLICK_HOOKED = setmetatable({}, { __mode = "k" })

    return false
local suppressionRetryPending = false
local suppressionRetryCount = 0

local function CancelFrameScriptedEffect(frameRef)
    local effectController = frameRef and frameRef.effectController or nil
    if effectController and type(effectController.CancelEffect) == "function" then
        pcall(effectController.CancelEffect, effectController)
    end
end

local function IsLikelyAnimatedVisualRegion(region)
@@ -3107,7 +3129,6 @@
WIDGET_SUPPRESSION_WAS_SHOWN[frameRef] = nil
end
end

end

local function ScheduleSuppressionRetry()
@@ -3144,7 +3165,11 @@
local hiddenFrames = 0
local effectControllers = 0

    for frameRef in pairs(PREY_WIDGET_FRAMES) do
    local PW = PreyWidgetRuntimeModule()
    local frameWeak = PW and PW.TrackedWeakFrames and PW:TrackedWeakFrames() or {}
    local preyHuntIconFrame = PW and PW.PrimaryIconFrame and PW:PrimaryIconFrame()

    for frameRef in pairs(frameWeak) do
trackedFrames = trackedFrames + 1
if frameRef and frameRef.IsShown and frameRef:IsShown() then
shownFrames = shownFrames + 1
@@ -3156,7 +3181,7 @@
end
end

    local preyIconTracked = preyHuntIconFrame and PREY_WIDGET_FRAMES[preyHuntIconFrame] == true or false
    local preyIconTracked = preyHuntIconFrame and frameWeak[preyHuntIconFrame] == true or false
local preyIconShown = nil
if preyHuntIconFrame and preyHuntIconFrame.IsShown then
preyIconShown = preyHuntIconFrame:IsShown() and true or false
@@ -3177,32 +3202,6 @@

Preydator.GetWidgetSuppressionDebug = GetWidgetSuppressionDebugSnapshot

local function ReadPreyValueFromObject(obj, keyName)
    if type(obj) ~= "table" then
        return nil
    end

    local okDirect, directValue = pcall(function()
        return obj[keyName]
    end)
    if okDirect and directValue ~= nil then
        return directValue
    end

    local getterName = "Get" .. string.upper(string.sub(keyName, 1, 1)) .. string.sub(keyName, 2)
    local okGetter, getter = pcall(function()
        return obj[getterName]
    end)
    if okGetter and type(getter) == "function" then
        local okCall, value = pcall(getter, obj)
        if okCall and value ~= nil then
            return value
        end
    end

    return nil
end

local function CoerceSanitizedNumber(value)
-- Accept number-like protected values too (secret-number wrappers).
-- Always sanitize via string-token roundtrip before tonumber.
@@ -3225,38 +3224,6 @@
return nil
end

local function ResolvePreyFieldsFromFrame(self)
    if type(self) ~= "table" then
        return nil, nil, nil, nil
    end

    local sources = {
        { name = "frame", value = self },
        { name = "frame.widgetInfo", value = ReadPreyValueFromObject(self, "widgetInfo") },
        { name = "frame.widgetData", value = ReadPreyValueFromObject(self, "widgetData") },
        { name = "frame.dataSource", value = ReadPreyValueFromObject(self, "dataSource") },
        { name = "frame.info", value = ReadPreyValueFromObject(self, "info") },
    }

    for _, source in ipairs(sources) do
        local obj = source.value
        if type(obj) == "table" then
            local shownState = CoerceSanitizedNumber(ReadPreyValueFromObject(obj, "shownState"))
            local progressState = CoerceSanitizedNumber(ReadPreyValueFromObject(obj, "progressState"))
            local tooltip = ReadPreyValueFromObject(obj, "tooltip")
            if type(tooltip) ~= "string" then
                tooltip = nil
            end

            if shownState ~= nil or progressState ~= nil or tooltip ~= nil then
                return shownState, progressState, tooltip, source.name
            end
        end
    end

    return nil, nil, nil, nil
end

local function ShouldSuppressEncounterNow()
return settings
and settings.disableDefaultPreyIcon == true
@@ -3301,6 +3268,10 @@

CaptureLivePreyHuntFrames()

    local PW = PreyWidgetRuntimeModule()
    local PREY_WIDGET_FRAMES = PW and PW.TrackedWeakFrames and PW:TrackedWeakFrames() or {}
    local preyHuntIconFrame = PW and PW.PrimaryIconFrame and PW:PrimaryIconFrame()

if settings.disableDefaultPreyIcon ~= true then
local function restoreFrame(frameRef)
if not frameRef then
@@ -3365,83 +3336,6 @@
end
end

local function EnsurePreyHuntMixinSuppressionHook()
    if preyHuntMixinHooked then
        return
    end

    local mixin = _G.UIWidgetTemplatePreyHuntProgressMixin
    if not mixin or type(hooksecurefunc) ~= "function" then
        return
    end

    local ok = pcall(hooksecurefunc, mixin, "Setup", function(self, widgetInfo)
        preyHuntIconFrame = self
        PREY_WIDGET_FRAMES[self] = true
        state.lastWidgetSetupAt = (GetTime and GetTime()) or 0

        local shownState = nil
        local progressState = nil
        local tooltipText = nil
        local captureSource = "none"

        if type(widgetInfo) == "table" then
            shownState = CoerceSanitizedNumber(widgetInfo.shownState)
            progressState = CoerceSanitizedNumber(widgetInfo.progressState)
            local widgetQuestID = ExtractWidgetQuestID(widgetInfo)
            if IsValidQuestID(widgetQuestID) then
                state.lastWidgetBoundQuestID = widgetQuestID
            elseif IsValidQuestID(state.activeQuestID) then
                -- Some clients omit questID from widget payloads. Bind to the
                -- currently tracked prey quest at Setup-time to keep updates
                -- stable without carrying state across new quest handoffs.
                state.lastWidgetBoundQuestID = state.activeQuestID
            end
            if type(widgetInfo.tooltip) == "string" then
                tooltipText = widgetInfo.tooltip
            end
            if shownState ~= nil or progressState ~= nil or tooltipText ~= nil then
                captureSource = "widgetInfo"
            end
        end

        if shownState ~= nil or progressState ~= nil or tooltipText ~= nil then
            preyWidgetInfoCache = {
                shownState = shownState,
                progressState = progressState,
                tooltip = tooltipText,
                questID = state.lastWidgetBoundQuestID,
                captureSource = captureSource,
                argType = type(widgetInfo),
            }
            -- Setup indicates widget payload freshness, not authoritative zone.
            -- Force a zone recompute on the normal runtime pass instead of
            -- certifying in-zone directly from widget visibility.
            state.zoneCacheDirty = true
            if type(UpdateBarDisplay) == "function" then
                UpdateBarDisplay()
            end
        else
            preyWidgetInfoCache = nil
        end

        -- Hide immediately after Blizzard Setup when the option is enabled.
        if settings and settings.disableDefaultPreyIcon == true then
            ApplyWidgetFrameSuppression(self, true)
            if self.IsShown and self:IsShown()
                and type(_G.InCombatLockdown) == "function" and _G.InCombatLockdown()
            then
                state.pendingWidgetSuppressionAfterCombat = true
            end
        end
    end)

    if ok then
        preyHuntMixinHooked = true
        CaptureLivePreyHuntFrames()
    end
end

ShouldSuppressDefaultPreyEncounter = function()
return settings and settings.disableDefaultPreyIcon == true
end
@@ -3495,6 +3389,8 @@
end

-- Set up OnShow hook to suppress the icon when it appears, if suppression is enabled.
    local PW = PreyWidgetRuntimeModule()
    local preyHuntIconFrame = PW and PW.PrimaryIconFrame and PW:PrimaryIconFrame()
if preyHuntIconFrame and settings.disableDefaultPreyIcon == true then
EnsureWidgetSuppressionHook(preyHuntIconFrame)
-- Re-apply suppression to any currently-shown frame.
@@ -3542,7 +3438,7 @@

local runtime = GetRuntimeModule("SoundsRuntime")
local soundContext = {
        soundFolderPrefix = SOUND_FOLDER_PREFIX,
        soundFolderPrefix = C.SOUND_FOLDER_PREFIX,
}

local mergedNames = {}
@@ -3602,15 +3498,15 @@
return runtime:BuildAddonSoundPath(fileName, soundContext) or path
end

    for _, defaultName in ipairs(DEFAULT_SOUND_FILENAMES) do
    for _, defaultName in ipairs(C.DEFAULT_SOUND_FILENAMES) do
pushFileName(defaultName)
end

for _, configuredName in ipairs(settings.soundFileNames) do
pushFileName(configuredName)
end

    for stage = 1, MAX_STAGE do
    for stage = 1, C.MAX_STAGE do
local existingPath = settings.stageSounds and settings.stageSounds[stage]
pushConfiguredSoundPath(existingPath)
end
@@ -3641,7 +3537,7 @@
settings.stageSounds = {}
end

    for stage = 1, MAX_STAGE do
    for stage = 1, C.MAX_STAGE do
local configuredPath = settings.stageSounds[stage]
if type(configuredPath) ~= "string" or configuredPath == "" then
local legacyPath = settings.stageSounds[tostring(stage)]
@@ -3658,17 +3554,17 @@

if configuredPath ~= "__NONE__" then
if type(configuredPath) ~= "string" or configuredPath == "" then
                configuredPath = (stage == 1 and ALERT_SOUND_PATH)
                    or (stage == 2 and AMBUSH_SOUND_PATH)
                    or (stage == 3 and TORMENT_SOUND_PATH)
                    or (stage == 4 and KILL_SOUND_PATH)
                configuredPath = (stage == 1 and C.ALERT_SOUND_PATH)
                    or (stage == 2 and C.AMBUSH_SOUND_PATH)
                    or (stage == 3 and C.TORMENT_SOUND_PATH)
                    or (stage == 4 and C.KILL_SOUND_PATH)
end

if type(configuredPath) ~= "string" or not allowedPathLower[string.lower(configuredPath)] then
                configuredPath = (stage == 1 and ALERT_SOUND_PATH)
                    or (stage == 2 and AMBUSH_SOUND_PATH)
                    or (stage == 3 and TORMENT_SOUND_PATH)
                    or (stage == 4 and KILL_SOUND_PATH)
                configuredPath = (stage == 1 and C.ALERT_SOUND_PATH)
                    or (stage == 2 and C.AMBUSH_SOUND_PATH)
                    or (stage == 3 and C.TORMENT_SOUND_PATH)
                    or (stage == 4 and C.KILL_SOUND_PATH)
end
end

@@ -3680,15 +3576,15 @@
if settings.ambushSoundPath ~= "__NONE__"
and (type(settings.ambushSoundPath) ~= "string" or not allowedPathLower[string.lower(settings.ambushSoundPath)])
then
        settings.ambushSoundPath = KILL_SOUND_PATH
        settings.ambushSoundPath = C.KILL_SOUND_PATH
end

settings.bloodyCommandSoundPath = canonicalizeConfiguredSoundPath(settings.bloodyCommandSoundPath)

if settings.bloodyCommandSoundPath ~= "__NONE__"
and (type(settings.bloodyCommandSoundPath) ~= "string" or not allowedPathLower[string.lower(settings.bloodyCommandSoundPath)])
then
        settings.bloodyCommandSoundPath = KILL_SOUND_PATH
        settings.bloodyCommandSoundPath = C.KILL_SOUND_PATH
end

settings.echoOfPredationSoundPath = canonicalizeConfiguredSoundPath(settings.echoOfPredationSoundPath)
@@ -3729,132 +3625,18 @@
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

-- Reads prey widget state from the snapshot captured by the mixin Setup hook.
-- Never calls GetAllWidgetsBySetID or reads widgetID/widgetType fields; those are
-- secret numbers that taint subsequent Blizzard layout/widget operations even inside pcall.
FindPreyWidgetProgressState = function(activeQuestID)
    local function TryBuildCacheFromFrame(frameRef, sourceTag)
        if not frameRef then
            return nil
        end

        local frameShown = frameRef.IsShown and frameRef:IsShown() or false
        local now = (GetTime and GetTime()) or 0
        local setupFresh = (now - (state.lastWidgetSetupAt or 0)) <= WIDGET_SETUP_FRESH_SECONDS
        if not frameShown and not setupFresh then
            return nil
        end

        local shownState, progressState, tooltipText, fieldSource = ResolvePreyFieldsFromFrame(frameRef)
        if shownState == nil and progressState == nil and tooltipText == nil then
            return nil
        end

        local captureSource = sourceTag
        if fieldSource and fieldSource ~= "" then
            captureSource = captureSource .. ":" .. fieldSource
        end

        return {
            shownState = shownState,
            progressState = progressState,
            tooltip = tooltipText,
            questID = state.lastWidgetBoundQuestID,
            captureSource = captureSource,
            argType = "frame-fallback",
        }
    end

    local function BuildCacheFromTrackedFrames()
        local refreshed = TryBuildCacheFromFrame(preyHuntIconFrame, "liveFrame")
        if refreshed then
            return refreshed
        end

        for frameRef in pairs(PREY_WIDGET_FRAMES) do
            refreshed = TryBuildCacheFromFrame(frameRef, "trackedFrame")
            if refreshed then
                return refreshed
            end
        end

        return nil
    end

    local info = preyWidgetInfoCache
    -- Keep the cache synchronized with live/tracked prey frames each pass.
    -- Some clients stop delivering full Setup payloads after the first update,
    -- which can freeze progression if we only trust stale cached state.
    local refreshed = BuildCacheFromTrackedFrames()
    if refreshed then
        if info ~= nil then
            if refreshed.questID == nil and info.questID ~= nil then
                refreshed.questID = info.questID
            end

            local existingProgressState = CoerceSanitizedNumber(info.progressState)
            local refreshedProgressState = CoerceSanitizedNumber(refreshed.progressState)
            if existingProgressState ~= nil and (refreshedProgressState == nil or refreshedProgressState < existingProgressState) then
                refreshed.progressState = info.progressState
            end
        end

        info = refreshed
        preyWidgetInfoCache = refreshed
    elseif not info then
        return nil, nil, nil, nil
    elseif info.progressState == nil then
        return nil, nil, nil, nil
    end

    local shownStateShown = (Enum and Enum.WidgetShownState and Enum.WidgetShownState.Shown) or WIDGET_SHOWN
    -- Only reject if shownState is explicitly a non-shown value; nil is allowed because
    -- shownState can be a protected number that reads as nil in insecure context.
    if info.shownState ~= nil and info.shownState ~= shownStateShown then
        return nil, nil, nil, nil
    end

    local pct = ExtractProgressPercent(info, info.tooltip)
    if IsValidQuestID(activeQuestID) then
        local widgetQuestID = ExtractWidgetQuestID(info)
        if widgetQuestID == activeQuestID or widgetQuestID == nil then
            return info.progressState, info.tooltip, pct, nil
        end
        return nil, nil, nil, nil
    end

    return info.progressState, info.tooltip, pct, nil
end

local function ResetStateForNewQuest(questID, forceReset)
if forceReset == true or state.activeQuestID ~= questID then
        local preySnap = nil
        do
            local PW = Preydator:GetModule("PreyWidgetRuntime")
            preySnap = PW and PW.GetSnapshot and PW:GetSnapshot()
        end
local cachedWidgetQuestID = CoerceSanitizedNumber(state.lastWidgetBoundQuestID)
            or CoerceSanitizedNumber(preyWidgetInfoCache and preyWidgetInfoCache.questID)
            or CoerceSanitizedNumber(preySnap and preySnap.questID)
local hasMatchingWidgetCache = forceReset ~= true
and cachedWidgetQuestID == questID
            and preyWidgetInfoCache ~= nil
            and preySnap ~= nil

state.activeQuestID = questID
state.lastNotifiedPreyEndQuestID = nil
@@ -3864,7 +3646,12 @@
state.lastWidgetSeenAt = 0
state.lastWidgetSetupAt = 0
state.lastWidgetBoundQuestID = nil
            preyWidgetInfoCache = nil
            do
                local PW = Preydator:GetModule("PreyWidgetRuntime")
                if PW and PW.ClearSnapshot then
                    PW:ClearSnapshot()
                end
            end
end
state.stageSoundPlayed = {}
state.stageSoundAttempted = {}
@@ -3904,7 +3691,7 @@

if not hasActiveQuest and not forceKillStage then
local endingQuestID = state.activeQuestID or questID
        local completedTransition = tonumber(state.stage) == MAX_STAGE
        local completedTransition = tonumber(state.stage) == C.MAX_STAGE
if endingQuestID and endingQuestID > 0 then
if completedTransition ~= true or state.lastNotifiedPreyEndQuestID ~= endingQuestID then
RunModuleHook("OnPreyQuestEnded", {
@@ -3945,7 +3732,7 @@
if hasActiveQuest then
newProgressState, tooltipText, newProgressPercent = FindPreyWidgetProgressState(questID)
end
    local hasWidgetData = newProgressState ~= nil
    local hasWidgetData = newProgressState ~= nil or newProgressPercent ~= nil

if hasWidgetData then
state.lastWidgetSeenAt = now
@@ -3961,7 +3748,7 @@
local questStillActive = IsQuestStillActive(questID)
if questCompleted or (hasActiveQuest and not questStillActive and not hasWidgetData) then
local endingQuestID = effectiveQuestID or state.activeQuestID or questID
        local completedTransition = questCompleted or (((not hasActiveQuest) or (not questStillActive)) and tonumber(state.stage) == MAX_STAGE)
        local completedTransition = questCompleted or (((not hasActiveQuest) or (not questStillActive)) and tonumber(state.stage) == C.MAX_STAGE)
if endingQuestID and endingQuestID > 0 then
if completedTransition ~= true or state.lastNotifiedPreyEndQuestID ~= endingQuestID then
RunModuleHook("OnPreyQuestEnded", {
@@ -4031,7 +3818,7 @@
or (CoerceSafeNumeric(second.numRequired) ~= nil))

if secondDone or (firstDone and secondObjectivePresent) then
                newProgressState = PREY_PROGRESS_FINAL
                newProgressState = C.PREY_PROGRESS_FINAL
elseif firstDone then
newProgressState = 1
else
@@ -4058,7 +3845,7 @@
end

if newProgressPercent == nil and percentSource == "none" and newProgressState ~= nil then
        if newProgressState == PREY_PROGRESS_FINAL then
        if newProgressState == C.PREY_PROGRESS_FINAL then
state.progressPercent = 100
percentSource = "final"
else
@@ -4089,19 +3876,19 @@
TryPlayStageSound(newStage)
end

    if newProgressState ~= PREY_PROGRESS_FINAL or oldProgressState == PREY_PROGRESS_FINAL then
    if newProgressState ~= C.PREY_PROGRESS_FINAL or oldProgressState == C.PREY_PROGRESS_FINAL then
ApplyDefaultPreyIconVisibility()
UpdateBarDisplay()
return
end

    if state.stageSoundPlayed[MAX_STAGE] or state.stageSoundAttempted[MAX_STAGE] then
    if state.stageSoundPlayed[C.MAX_STAGE] or state.stageSoundAttempted[C.MAX_STAGE] then
ApplyDefaultPreyIconVisibility()
UpdateBarDisplay()
return
end

    TryPlayStageSound(MAX_STAGE)
    TryPlayStageSound(C.MAX_STAGE)

ApplyDefaultPreyIconVisibility()
UpdateBarDisplay()
@@ -4128,7 +3915,7 @@
local now = GetTime and GetTime() or 0
local trackedQuestID = state and state.activeQuestID or nil
local hasTrackedQuest = IsValidQuestID(trackedQuestID) and IsQuestStillActive(trackedQuestID)
    local liveQuestID = GetCurrentActivePreyQuestCached(ACTIVE_PREY_QUEST_CACHE_SECONDS)
    local liveQuestID = GetCurrentActivePreyQuestCached(C.ACTIVE_PREY_QUEST_CACHE_SECONDS)
local hasLiveQuest = IsValidQuestID(liveQuestID) and IsQuestStillActive(liveQuestID)
local needsQuestBootstrap = hasLiveQuest and not hasTrackedQuest
local needsStaleQuestCleanup = IsValidQuestID(trackedQuestID) and not hasTrackedQuest and not hasLiveQuest
@@ -4580,10 +4367,28 @@
settings = _G.PreydatorDB
end

    do
        local PW = Preydator:GetModule("PreyWidgetRuntime")
        if PW and PW.Install and PW._coreCtxInstalled ~= true then
            PW:Install({
                state = state,
                getSettings = function()
                    return settings
                end,
                extractProgressPercent = ExtractProgressPercent,
                isValidQuestID = IsValidQuestID,
                updateBarDisplay = UpdateBarDisplay,
                applyWidgetFrameSuppression = ApplyWidgetFrameSuppression,
                widgetShownFallthrough = C.WIDGET_SHOWN,
            })
            PW._coreCtxInstalled = true
        end
    end

Preydator:ApplyRuntimeSettings(settings, false, false)
ApplyAratorSilencing()
Preydator:ShowSoundDefaultsPromptIfNeeded()
    AddDebugLog("OnAddonLoaded", "debug=" .. tostring(debugDB.enabled) .. " | stage" .. tostring(MAX_STAGE) .. "=" .. tostring(settings.stageSounds[MAX_STAGE]), true)
    AddDebugLog("OnAddonLoaded", "debug=" .. tostring(debugDB.enabled) .. " | stage" .. tostring(C.MAX_STAGE) .. "=" .. tostring(settings.stageSounds[C.MAX_STAGE]), true)

-- Reload/login bootstrap from live quest context only.
-- Do not seed stage/progress from snapshots here because prey quest IDs are
@@ -4951,7 +4756,7 @@
stageNamesTitle:SetText("Stage Names")

local stageNameEdits = {}
    for stageIndex = 1, (MAX_STAGE - 1) do
    for stageIndex = 1, (C.MAX_STAGE - 1) do
local rowY = -442 - ((stageIndex - 1) * 35)
local label = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
label:SetPoint("TOPLEFT", panel, "TOPLEFT", 320, rowY)
@@ -4989,7 +4794,7 @@
outZoneEdit:SetAutoFocus(false)
outZoneEdit:SetTextInsets(6, 6, 0, 0)
outZoneEdit:SetPoint("TOPLEFT", panel, "TOPLEFT", 365, -546)
    outZoneEdit:SetText(settings.outOfZoneLabel or DEFAULT_OUT_OF_ZONE_LABEL)
    outZoneEdit:SetText(settings.outOfZoneLabel or C.DEFAULT_OUT_OF_ZONE_LABEL)
outZoneEdit:SetScript("OnEnterPressed", function(self)
settings.outOfZoneLabel = self:GetText()
NormalizeLabelSettings()
@@ -5033,16 +4838,16 @@
restoreNamesButton:SetPoint("TOPLEFT", panel, "TOPLEFT", 320, -764)
restoreNamesButton:SetText("Restore Default Names")
restoreNamesButton:SetScript("OnClick", function()
        for stageIndex = 1, (MAX_STAGE - 1) do
            settings.stageLabels[stageIndex] = DEFAULT_STAGE_LABELS[stageIndex]
            stageNameEdits[stageIndex]:SetText(DEFAULT_STAGE_LABELS[stageIndex])
        for stageIndex = 1, (C.MAX_STAGE - 1) do
            settings.stageLabels[stageIndex] = C.DEFAULT_STAGE_LABELS[stageIndex]
            stageNameEdits[stageIndex]:SetText(C.DEFAULT_STAGE_LABELS[stageIndex])
end
        settings.outOfZoneLabel = DEFAULT_OUT_OF_ZONE_LABEL
        settings.outOfZoneLabel = C.DEFAULT_OUT_OF_ZONE_LABEL
settings.ambushPrefix = "AMBUSH: "
settings.ambushSuffix = "preyTargetName"
settings.bloodyCommandPrefix = "Bloody Command: "
settings.bloodyCommandSuffix = "bloodyCommandSourceName"
        outZoneEdit:SetText(DEFAULT_OUT_OF_ZONE_LABEL)
        outZoneEdit:SetText(C.DEFAULT_OUT_OF_ZONE_LABEL)
ambushLabelEdit:SetText("preyTargetName")
UpdateBarDisplay()
end)
@@ -5059,10 +4864,10 @@
settings.ambushVisualEnabled = DEFAULTS.ambushVisualEnabled
settings.ambushSoundPath = DEFAULTS.ambushSoundPath
settings.soundFileNames = {}
        for _, fileName in ipairs(DEFAULT_SOUND_FILENAMES) do
        for _, fileName in ipairs(C.DEFAULT_SOUND_FILENAMES) do
table.insert(settings.soundFileNames, fileName)
end
        for stageIndex = 1, MAX_STAGE do
        for stageIndex = 1, C.MAX_STAGE do
settings.stageSounds[stageIndex] = DEFAULTS.stageSounds[stageIndex]
end
NormalizeSoundSettings()
@@ -5163,20 +4968,20 @@
}

local percentDisplayOptions = {
        [PERCENT_DISPLAY_INSIDE] = { text = "In Bar" },
        [PERCENT_DISPLAY_UNDER_TICKS] = { text = "Under Ticks" },
        [PERCENT_DISPLAY_BELOW_BAR] = { text = "Below Bar" },
        [PERCENT_DISPLAY_OFF] = { text = "Off" },
        [C.PERCENT_DISPLAY_INSIDE] = { text = "In Bar" },
        [C.PERCENT_DISPLAY_UNDER_TICKS] = { text = "Under Ticks" },
        [C.PERCENT_DISPLAY_BELOW_BAR] = { text = "Below Bar" },
        [C.PERCENT_DISPLAY_OFF] = { text = "Off" },
}

local layerModeOptions = {
        [LAYER_MODE_ABOVE] = { text = "Above Fill" },
        [LAYER_MODE_BELOW] = { text = "Below Fill" },
        [C.LAYER_MODE_ABOVE] = { text = "Above Fill" },
        [C.LAYER_MODE_BELOW] = { text = "Below Fill" },
}

local progressSegmentOptions = {
        [PROGRESS_SEGMENTS_QUARTERS] = { text = "Quarters (25/50/75/100)" },
        [PROGRESS_SEGMENTS_THIRDS] = { text = "Thirds (33/66/100)" },
        [C.PROGRESS_SEGMENTS_QUARTERS] = { text = "Quarters (25/50/75/100)" },
        [C.PROGRESS_SEGMENTS_THIRDS] = { text = "Thirds (33/66/100)" },
}

local textureDropdown = AddDropdown(panel, "Texture", 20, -271, 170, textureOptions, function()
@@ -5357,7 +5162,7 @@
if titleColorSwatch and titleColorSwatch.PreydatorRefresh then titleColorSwatch.PreydatorRefresh() end
if percentColorSwatch and percentColorSwatch.PreydatorRefresh then percentColorSwatch.PreydatorRefresh() end

        for stageIndex = 1, (MAX_STAGE - 1) do
        for stageIndex = 1, (C.MAX_STAGE - 1) do
stageNameEdits[stageIndex]:SetText(settings.stageLabels[stageIndex])
end
outZoneEdit:SetText(settings.outOfZoneLabel)
@@ -5412,40 +5217,40 @@
end

Preydator.Constants = {
    MAX_STAGE = MAX_STAGE,
    DEFAULT_OUT_OF_ZONE_LABEL = DEFAULT_OUT_OF_ZONE_LABEL,
    DEFAULT_AMBUSH_LABEL = DEFAULT_AMBUSH_LABEL,
    DEFAULT_STAGE_LABELS = DEFAULT_STAGE_LABELS,
    DEFAULT_SOUND_FILENAMES = DEFAULT_SOUND_FILENAMES,
    PROTECTED_SOUND_FILENAMES = PROTECTED_SOUND_FILENAMES,
    PROGRESS_SEGMENTS_QUARTERS = PROGRESS_SEGMENTS_QUARTERS,
    PROGRESS_SEGMENTS_THIRDS = PROGRESS_SEGMENTS_THIRDS,
    PERCENT_DISPLAY_INSIDE = PERCENT_DISPLAY_INSIDE,
    PERCENT_DISPLAY_INSIDE_BELOW = PERCENT_DISPLAY_INSIDE_BELOW,
    PERCENT_DISPLAY_BELOW_BAR = PERCENT_DISPLAY_BELOW_BAR,
    PERCENT_DISPLAY_ABOVE_BAR = PERCENT_DISPLAY_ABOVE_BAR,
    PERCENT_DISPLAY_ABOVE_TICKS = PERCENT_DISPLAY_ABOVE_TICKS,
    PERCENT_DISPLAY_UNDER_TICKS = PERCENT_DISPLAY_UNDER_TICKS,
    PERCENT_DISPLAY_OFF = PERCENT_DISPLAY_OFF,
    LAYER_MODE_ABOVE = LAYER_MODE_ABOVE,
    LAYER_MODE_BELOW = LAYER_MODE_BELOW,
    LABEL_MODE_CENTER = LABEL_MODE_CENTER,
    LABEL_MODE_LEFT = LABEL_MODE_LEFT,
    LABEL_MODE_LEFT_COMBINED = LABEL_MODE_LEFT_COMBINED,
    LABEL_MODE_RIGHT = LABEL_MODE_RIGHT,
    LABEL_MODE_RIGHT_COMBINED = LABEL_MODE_RIGHT_COMBINED,
    LABEL_MODE_SEPARATE = LABEL_MODE_SEPARATE,
    LABEL_MODE_LEFT_SUFFIX = LABEL_MODE_LEFT_SUFFIX,
    LABEL_MODE_RIGHT_PREFIX = LABEL_MODE_RIGHT_PREFIX,
    LABEL_MODE_NONE = LABEL_MODE_NONE,
    LABEL_ROW_ABOVE = LABEL_ROW_ABOVE,
    LABEL_ROW_BELOW = LABEL_ROW_BELOW,
    ORIENTATION_HORIZONTAL = ORIENTATION_HORIZONTAL,
    ORIENTATION_VERTICAL = ORIENTATION_VERTICAL,
    FILL_DIRECTION_UP = FILL_DIRECTION_UP,
    FILL_DIRECTION_DOWN = FILL_DIRECTION_DOWN,
    TEXTURE_PRESETS = TEXTURE_PRESETS,
    FONT_PRESETS = FONT_PRESETS,
    MAX_STAGE = C.MAX_STAGE,
    DEFAULT_OUT_OF_ZONE_LABEL = C.DEFAULT_OUT_OF_ZONE_LABEL,
    DEFAULT_AMBUSH_LABEL = C.DEFAULT_AMBUSH_LABEL,
    DEFAULT_STAGE_LABELS = C.DEFAULT_STAGE_LABELS,
    DEFAULT_SOUND_FILENAMES = C.DEFAULT_SOUND_FILENAMES,
    PROTECTED_SOUND_FILENAMES = C.PROTECTED_SOUND_FILENAMES,
    PROGRESS_SEGMENTS_QUARTERS = C.PROGRESS_SEGMENTS_QUARTERS,
    PROGRESS_SEGMENTS_THIRDS = C.PROGRESS_SEGMENTS_THIRDS,
    PERCENT_DISPLAY_INSIDE = C.PERCENT_DISPLAY_INSIDE,
    PERCENT_DISPLAY_INSIDE_BELOW = C.PERCENT_DISPLAY_INSIDE_BELOW,
    PERCENT_DISPLAY_BELOW_BAR = C.PERCENT_DISPLAY_BELOW_BAR,
    PERCENT_DISPLAY_ABOVE_BAR = C.PERCENT_DISPLAY_ABOVE_BAR,
    PERCENT_DISPLAY_ABOVE_TICKS = C.PERCENT_DISPLAY_ABOVE_TICKS,
    PERCENT_DISPLAY_UNDER_TICKS = C.PERCENT_DISPLAY_UNDER_TICKS,
    PERCENT_DISPLAY_OFF = C.PERCENT_DISPLAY_OFF,
    LAYER_MODE_ABOVE = C.LAYER_MODE_ABOVE,
    LAYER_MODE_BELOW = C.LAYER_MODE_BELOW,
    LABEL_MODE_CENTER = C.LABEL_MODE_CENTER,
    LABEL_MODE_LEFT = C.LABEL_MODE_LEFT,
    LABEL_MODE_LEFT_COMBINED = C.LABEL_MODE_LEFT_COMBINED,
    LABEL_MODE_RIGHT = C.LABEL_MODE_RIGHT,
    LABEL_MODE_RIGHT_COMBINED = C.LABEL_MODE_RIGHT_COMBINED,
    LABEL_MODE_SEPARATE = C.LABEL_MODE_SEPARATE,
    LABEL_MODE_LEFT_SUFFIX = C.LABEL_MODE_LEFT_SUFFIX,
    LABEL_MODE_RIGHT_PREFIX = C.LABEL_MODE_RIGHT_PREFIX,
    LABEL_MODE_NONE = C.LABEL_MODE_NONE,
    LABEL_ROW_ABOVE = C.LABEL_ROW_ABOVE,
    LABEL_ROW_BELOW = C.LABEL_ROW_BELOW,
    ORIENTATION_HORIZONTAL = C.ORIENTATION_HORIZONTAL,
    ORIENTATION_VERTICAL = C.ORIENTATION_VERTICAL,
    FILL_DIRECTION_UP = C.FILL_DIRECTION_UP,
    FILL_DIRECTION_DOWN = C.FILL_DIRECTION_DOWN,
    TEXTURE_PRESETS = C.TEXTURE_PRESETS,
    FONT_PRESETS = C.FONT_PRESETS,
}

Preydator.API = {
@@ -5510,10 +5315,10 @@
local runtime = GetRuntimeModule("SoundsRuntime")
if runtime and type(runtime.BuildSoundDropdownOptions) == "function" then
return runtime:BuildSoundDropdownOptions(settings, {
                defaultSoundFileNames = DEFAULT_SOUND_FILENAMES,
                defaultSoundFileNames = C.DEFAULT_SOUND_FILENAMES,
additionalSoundEntries = GetExternalSoundCatalog(),
noneLabel = _G.PreydatorL["None"],
                soundFolderPrefix = SOUND_FOLDER_PREFIX,
                soundFolderPrefix = C.SOUND_FOLDER_PREFIX,
})
end

@@ -5523,9 +5328,9 @@
text = _G.PreydatorL["None"],
},
}
        local files = (settings and settings.soundFileNames) or DEFAULT_SOUND_FILENAMES
        local files = (settings and settings.soundFileNames) or C.DEFAULT_SOUND_FILENAMES
for _, fileName in ipairs(files) do
            local path = SOUND_FOLDER_PREFIX .. tostring(fileName or "")
            local path = C.SOUND_FOLDER_PREFIX .. tostring(fileName or "")
options[#options + 1] = {
key = path,
text = tostring(fileName or ""),
@@ -5540,7 +5345,7 @@
local runtime = GetRuntimeModule("SoundsRuntime")
if runtime and type(runtime.AddSoundFileName) == "function" then
return runtime:AddSoundFileName(fileName, settings, {
                soundFolderPrefix = SOUND_FOLDER_PREFIX,
                soundFolderPrefix = C.SOUND_FOLDER_PREFIX,
normalizeSoundSettings = NormalizeSoundSettings,
})
end
@@ -5551,8 +5356,8 @@
local runtime = GetRuntimeModule("SoundsRuntime")
if runtime and type(runtime.RemoveSoundFileName) == "function" then
return runtime:RemoveSoundFileName(fileName, settings, {
                soundFolderPrefix = SOUND_FOLDER_PREFIX,
                protectedSoundFileNames = PROTECTED_SOUND_FILENAMES,
                soundFolderPrefix = C.SOUND_FOLDER_PREFIX,
                protectedSoundFileNames = C.PROTECTED_SOUND_FILENAMES,
normalizeSoundSettings = NormalizeSoundSettings,
})
end
@@ -5565,10 +5370,10 @@
return runtime:ResolveStageSoundPath(stage, settings, {
addDebugLog = AddDebugLog,
getDefaultStageSoundPath = function(stageIndex)
                    return (stageIndex == 1 and ALERT_SOUND_PATH)
                        or (stageIndex == 2 and AMBUSH_SOUND_PATH)
                        or (stageIndex == 3 and TORMENT_SOUND_PATH)
                        or (stageIndex == 4 and KILL_SOUND_PATH)
                    return (stageIndex == 1 and C.ALERT_SOUND_PATH)
                        or (stageIndex == 2 and C.AMBUSH_SOUND_PATH)
                        or (stageIndex == 3 and C.TORMENT_SOUND_PATH)
                        or (stageIndex == 4 and C.KILL_SOUND_PATH)
end,
})
end
@@ -5579,10 +5384,10 @@
return nil
end

        local defaultPath = (stage == 1 and ALERT_SOUND_PATH)
            or (stage == 2 and AMBUSH_SOUND_PATH)
            or (stage == 3 and TORMENT_SOUND_PATH)
            or (stage == 4 and KILL_SOUND_PATH)
        local defaultPath = (stage == 1 and C.ALERT_SOUND_PATH)
            or (stage == 2 and C.AMBUSH_SOUND_PATH)
            or (stage == 3 and C.TORMENT_SOUND_PATH)
            or (stage == 4 and C.KILL_SOUND_PATH)
if not settings then
return defaultPath
end
@@ -5611,7 +5416,7 @@
local runtime = GetRuntimeModule("SoundsRuntime")
if runtime and type(runtime.ResolveAmbushAlertSoundPath) == "function" then
return runtime:ResolveAmbushAlertSoundPath(settings, {
                killSoundPath = KILL_SOUND_PATH,
                killSoundPath = C.KILL_SOUND_PATH,
})
end

@@ -5623,13 +5428,13 @@
return path
end

        return KILL_SOUND_PATH
        return C.KILL_SOUND_PATH
end,
ResolveBloodyCommandSoundPath = function()
local runtime = GetRuntimeModule("SoundsRuntime")
if runtime and type(runtime.ResolveBloodyCommandAlertSoundPath) == "function" then
return runtime:ResolveBloodyCommandAlertSoundPath(settings, {
                killSoundPath = KILL_SOUND_PATH,
                killSoundPath = C.KILL_SOUND_PATH,
})
end

@@ -5641,7 +5446,7 @@
return path
end

        return KILL_SOUND_PATH
        return C.KILL_SOUND_PATH
end,
ResolveEchoOfPredationSoundPath = function()
local path = settings and settings.echoOfPredationSoundPath
@@ -5703,8 +5508,8 @@
state = state,
defaults = DEFAULTS,
constants = Preydator.Constants,
            fillInset = FILL_INSET,
            maxTickMarks = MAX_TICK_MARKS,
            fillInset = C.FILL_INSET,
            maxTickMarks = C.MAX_TICK_MARKS,
clamp = Clamp,
round = Round,
getTime = function()
@@ -5723,31 +5528,31 @@
isRestrictedInstanceForPreyBar = IsRestrictedInstanceForPreyBar,
getStageFromState = GetStageFromState,
getStageFallbackPercent = function(stage)
                local mode = (settings and settings.progressSegments) or PROGRESS_SEGMENTS_QUARTERS
                local stagePercents = STAGE_PCT_BY_SEGMENT[mode] or STAGE_PCT_BY_SEGMENT[PROGRESS_SEGMENTS_QUARTERS]
                local mode = (settings and settings.progressSegments) or C.PROGRESS_SEGMENTS_QUARTERS
                local stagePercents = C.STAGE_PCT_BY_SEGMENT[mode] or C.STAGE_PCT_BY_SEGMENT[C.PROGRESS_SEGMENTS_QUARTERS]
return stagePercents[stage] or 0
end,
getStageLabel = GetStageLabel,
getProgressTickPercents = function()
                local mode = (settings and settings.progressSegments) or PROGRESS_SEGMENTS_QUARTERS
                local tickPercents = BAR_TICK_PCTS_BY_SEGMENT[mode]
                local mode = (settings and settings.progressSegments) or C.PROGRESS_SEGMENTS_QUARTERS
                local tickPercents = C.BAR_TICK_PCTS_BY_SEGMENT[mode]
if type(tickPercents) ~= "table" then
                    return BAR_TICK_PCTS_BY_SEGMENT[PROGRESS_SEGMENTS_QUARTERS]
                    return C.BAR_TICK_PCTS_BY_SEGMENT[C.PROGRESS_SEGMENTS_QUARTERS]
end

return tickPercents
end,
getPercentTextLayerSettings = function()
                local mode = settings and settings.percentDisplay or PERCENT_DISPLAY_INSIDE
                if settings and settings.orientation == ORIENTATION_VERTICAL and type(settings.verticalPercentDisplay) == "string" then
                local mode = settings and settings.percentDisplay or C.PERCENT_DISPLAY_INSIDE
                if settings and settings.orientation == C.ORIENTATION_VERTICAL and type(settings.verticalPercentDisplay) == "string" then
mode = settings.verticalPercentDisplay
end

                if mode == PERCENT_DISPLAY_INSIDE_BELOW then
                    mode = PERCENT_DISPLAY_INSIDE
                if mode == C.PERCENT_DISPLAY_INSIDE_BELOW then
                    mode = C.PERCENT_DISPLAY_INSIDE
end

                if mode == PERCENT_DISPLAY_ABOVE_TICKS then
                if mode == C.PERCENT_DISPLAY_ABOVE_TICKS then
return "OVERLAY", 10
end

@@ -5756,7 +5561,7 @@
getTickLayerSettings = function()
return "OVERLAY", 4
end,
            maxStage = MAX_STAGE,
            maxStage = C.MAX_STAGE,
getCurrentActivePreyQuestCached = GetCurrentActivePreyQuestCached,
refreshInPreyZoneStatus = RefreshInPreyZoneStatus,
isAnyTrackedPreyWidgetShown = IsAnyTrackedPreyWidgetShown,
@@ -5882,8 +5687,8 @@
addonName = ADDON_NAME,
state = state,
ui = UI,
            preyProgressFinal = PREY_PROGRESS_FINAL,
            activePreyQuestCacheSeconds = ACTIVE_PREY_QUEST_CACHE_SECONDS,
            preyProgressFinal = C.PREY_PROGRESS_FINAL,
            activePreyQuestCacheSeconds = C.ACTIVE_PREY_QUEST_CACHE_SECONDS,
onAddonLoaded = OnAddonLoaded,
onBlizzardWidgetsLoaded = OnBlizzardWidgetsLoaded,
onPlayerRegenEnabled = OnPlayerRegenEnabled,
@@ -5914,9 +5719,13 @@
return TryHandleEchoOfPredationNameplate(unitToken, source)
end,
clearPreyWidgetInfoCache = function()
                preyWidgetInfoCache = nil
                local PW = Preydator:GetModule("PreyWidgetRuntime")
                if PW and PW.ClearSnapshot then
                    PW:ClearSnapshot()
                end
state.progressState = nil
end,
            runAfterCurrentScriptsPass = Preydator.RunAfterCurrentScriptsPass,
})
Preydator:SyncCorePreyRuntimeEvents()
return