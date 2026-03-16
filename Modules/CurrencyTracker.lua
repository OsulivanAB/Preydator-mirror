---@diagnostic disable

--[[
    Preydator: CurrencyTracker
    Tracks approved Prey currencies across the current character and all known warband alts.
    Styled after profession app panels: clean rows, delta indicators, warband roll-up.

    Approved currency IDs (allow-list):
        3392  Remnant of Anguish          (primary Prey currency)
        3316  Voidlight Marl              (expansion permanent)
        3383  Adventurer Dawncrest        (Season 1)
        3341  Veteran Dawncrest           (Season 1)
        3343  Champion Dawncrest          (Season 1)
]]

local _, addonTable = ...
local Preydator = _G.Preydator or addonTable
local L = _G.PreydatorL or setmetatable({}, { __index = function(_, k) return k end })

local C_CurrencyInfo   = _G.C_CurrencyInfo
local C_Timer          = _G.C_Timer
local CreateFrame      = _G.CreateFrame
local GetTime          = _G.GetTime
local IsShiftKeyDown   = _G.IsShiftKeyDown
local LibStub          = _G.LibStub
local RAID_CLASS_COLORS = _G.RAID_CLASS_COLORS
local UnitClass        = _G.UnitClass
local UnitName         = _G.UnitName
local GetRealmName     = _G.GetRealmName
local GetZoneText      = _G.GetZoneText
local UIParent         = _G.UIParent
local math             = _G.math
local string           = _G.string
local table            = _G.table
local pairs            = _G.pairs
local ipairs           = _G.ipairs
local tostring         = _G.tostring
local tonumber         = _G.tonumber
local type             = _G.type

local LibDataBroker = LibStub and LibStub:GetLibrary("LibDataBroker-1.1", true)
local LibDBIcon = LibStub and LibStub:GetLibrary("LibDBIcon-1.0", true)

local function Atan2(y, x)
    if math.atan2 then
        return math.atan2(y, x)
    end
    if x > 0 then
        return math.atan(y / x)
    end
    if x < 0 then
        if y >= 0 then
            return math.atan(y / x) + math.pi
        end
        return math.atan(y / x) - math.pi
    end
    if y > 0 then
        return math.pi / 2
    end
    if y < 0 then
        return -math.pi / 2
    end
    return 0
end

local function NormalizeAngleDegrees(angle)
    if type(angle) ~= "number" then
        return 225
    end
    angle = angle % 360
    if angle < 0 then
        angle = angle + 360
    end
    return angle
end

--------------------------------------------------------------------------------
-- Constants
--------------------------------------------------------------------------------

local CURRENCY_ALLOW_LIST = {
    { id = 3392, name = "Anguish", label = "Anguish", season = nil },
    { id = 3316, name = "Voidlight Marl", label = "Voidlight", season = nil },
    { id = 3383, name = "Adventurer Dawncrest", label = "Adv. Crest", season = "S1" },
    { id = 3341, name = "Veteran Dawncrest", label = "Vet. Crest", season = "S1" },
    { id = 3343, name = "Champion Dawncrest", label = "Champ. Crest", season = "S1" },
}

local ALLOW_LIST_IDS = {}
for _, entry in ipairs(CURRENCY_ALLOW_LIST) do
    ALLOW_LIST_IDS[entry.id] = entry
end

-- UI geometry
local PANEL_PAD        = 16
local ROW_HEIGHT       = 42
local ROW_GAP          = 6
local SECTION_TITLE_H  = 22
local SECTION_GAP      = 10
local COL_LEFT_W       = 340
local ICON_SIZE        = 28
local ICON_PAD         = 8
local WARBAND_ROW_H    = 24
local WARBAND_COL_CHAR = 160
local WARBAND_COL_W    = 68
local POLL_INTERVAL_SECONDS = 0.5
local TRACKER_WINDOW_WIDTH = 276
local TRACKER_WINDOW_HEIGHT = 236
local TRACKER_ROW_WIDTH = 248
local TRACKER_ROW_HEIGHT = 28
local TRACKER_MIN_WIDTH = 240
local TRACKER_MAX_WIDTH = 520
local TRACKER_MIN_HEIGHT = 64
local TRACKER_MAX_HEIGHT = 700
local TRACKER_DEFAULT_FONT = 14
local TRACKER_MIN_FONT = 10
local TRACKER_MAX_FONT = 24
local TRACKER_DEFAULT_SCALE = 1.00
local TRACKER_MIN_SCALE = 0.70
local TRACKER_MAX_SCALE = 1.40
local WARBAND_DEFAULT_WIDTH = 420
local WARBAND_DEFAULT_HEIGHT = 250
local WARBAND_MIN_WIDTH = 150
local WARBAND_MAX_WIDTH = 900
local WARBAND_MIN_HEIGHT = 140
local WARBAND_MAX_HEIGHT = 800
local WARBAND_DEFAULT_FONT = 12
local WARBAND_MIN_FONT = 10
local WARBAND_MAX_FONT = 24
local WARBAND_DEFAULT_SCALE = 1.00
local WARBAND_MIN_SCALE = 0.70
local WARBAND_MAX_SCALE = 1.40
local CURRENCY_WHATS_NEW_VERSION = "1.7.0"
local MINIMAP_ICON_PATH = "Interface\\AddOns\\Preydator\\media\\Preydator_64.png"
local LDB_LAUNCHER_NAME = "PreydatorCurrencyTracker"

-- Colors
local COLOR_SECTION_BG  = { 0.08, 0.06, 0.03, 0.92 }
local COLOR_ROW_BG      = { 0.14, 0.11, 0.06, 0.92 }
local COLOR_ROW_BG_ALT  = { 0.10, 0.08, 0.05, 0.92 }
local COLOR_HOVER       = { 0.35, 0.27, 0.12, 0.45 }
local COLOR_BORDER      = { 0.78, 0.62, 0.20, 0.95 }
local COLOR_HEADER_BG   = { 0.21, 0.15, 0.06, 1.00 }
local COLOR_GOLD        = { 1.00, 0.82, 0.00, 1.00 }
local COLOR_WHITE       = { 1.00, 1.00, 1.00, 1.00 }
local COLOR_MUTED       = { 0.65, 0.65, 0.70, 1.00 }
local COLOR_GREEN       = { 0.00, 0.56, 0.32, 1.00 }
local COLOR_RED         = { 0.72, 0.24, 0.15, 1.00 }
local COLOR_SEASON      = { 0.60, 0.80, 1.00, 1.00 }
local LEGACY_GAIN_COLOR = { 0.25, 0.90, 0.65, 1.00 }
local LEGACY_LOSS_COLOR = { 0.98, 0.56, 0.36, 1.00 }

local THEME_PRESETS = {
    light = {
        section = { 0.87, 0.84, 0.79, 0.94 },
        row = { 0.95, 0.93, 0.90, 0.95 },
        rowAlt = { 0.90, 0.87, 0.83, 0.95 },
        border = { 0.27, 0.24, 0.19, 1.00 },
        header = { 0.78, 0.72, 0.64, 0.96 },
        title = { 0.12, 0.10, 0.08, 1.00 },
        text = { 0.10, 0.09, 0.07, 1.00 },
        muted = { 0.28, 0.25, 0.21, 1.00 },
        season = { 0.13, 0.34, 0.67, 1.00 },
    },
    brown = {
        section = { 0.08, 0.06, 0.03, 0.92 },
        row = { 0.14, 0.11, 0.06, 0.92 },
        rowAlt = { 0.10, 0.08, 0.05, 0.92 },
        border = { 0.78, 0.62, 0.20, 0.95 },
        header = { 0.21, 0.15, 0.06, 1.00 },
        title = { 1.00, 0.82, 0.00, 1 },
        text = { 1.00, 1.00, 1.00, 1 },
        muted = { 0.74, 0.70, 0.60, 1 },
        season = { 0.60, 0.80, 1.00, 1 },
    },
    dark = {
        section = { 0.07, 0.07, 0.09, 0.92 },
        row = { 0.14, 0.14, 0.16, 0.92 },
        rowAlt = { 0.11, 0.11, 0.13, 0.92 },
        border = { 0.30, 0.30, 0.35, 0.90 },
        header = { 0.18, 0.18, 0.22, 1.00 },
        title = { 1.00, 0.82, 0.00, 1 },
        text = { 1.00, 1.00, 1.00, 1 },
        muted = { 0.65, 0.65, 0.70, 1 },
        season = { 0.60, 0.80, 1.00, 1 },
    },
}

--------------------------------------------------------------------------------
-- Module skeleton
--------------------------------------------------------------------------------

local CurrencyTrackerModule = {}
Preydator:RegisterModule("CurrencyTracker", CurrencyTrackerModule)

-- Internal state (not persisted to SavedVariables — that happens via OnAddonLoaded/OnEvent)
local db                -- reference to PreydatorDB.currency sub-table
local sessionStart      = {}   -- [currencyID] = quantity at login/reload
local sessionBaselineReady = false
local currencyPanelPage = nil  -- the Tab content frame, built lazily
local lastKnownQuantity = {}   -- [currencyID] = quantity
local pollElapsed = 0
local ldbLauncher
local ldbIconRegistered = false
local warbandSortKey = "character"
local warbandSortAsc = true
local currencyWhatsNewFrame
local EnsureCurrencyWindow
local EnsureWarbandWindow

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

local function CharacterKey()
    local name  = UnitName and UnitName("player") or "Unknown"
    local realm = GetRealmName and GetRealmName() or "Unknown"
    return name .. "-" .. realm
end

local function GetCurrencyQuantity(currencyID)
    if not C_CurrencyInfo or not C_CurrencyInfo.GetCurrencyInfo then
        return 0
    end
    local info = C_CurrencyInfo.GetCurrencyInfo(currencyID)
    return (info and tonumber(info.quantity)) or 0
end

local function GetCurrencyIcon(currencyID)
    if not C_CurrencyInfo or not C_CurrencyInfo.GetCurrencyInfo then
        return nil
    end
    local info = C_CurrencyInfo.GetCurrencyInfo(currencyID)
    return info and info.iconFileID
end

local function EnsureDB()
    _G.PreydatorDB = _G.PreydatorDB or {}
    _G.PreydatorDB.currency = _G.PreydatorDB.currency or {}
    local c = _G.PreydatorDB.currency
    c.snapshots    = c.snapshots    or {}
    c.warbandTotal = c.warbandTotal or {}
    c.preySnapshots = c.preySnapshots or {}
    c.preyWeeklyProgress = c.preyWeeklyProgress or {}
    db = c
end

local function GetCurrentPreyState()
    if Preydator and type(Preydator.GetState) == "function" then
        return Preydator.GetState()
    end
    return nil
end

local function BuildPreyRankLabel(stage, difficulty)
    if type(difficulty) == "string" and difficulty ~= "" then
        return difficulty
    end

    local stageNumber = tonumber(stage)
    if stageNumber and stageNumber > 0 then
        return string.format("Stage %d", stageNumber)
    end

    return L["No active prey"]
end

local function GetWeeklyResetKey()
    local now = date("!*t")
    if type(now) ~= "table" then
        return date("%Y-%U")
    end

    return date("%Y-%U")
end

local function NormalizePreyDifficultyKey(diff)
    local text = tostring(diff or "")
    if text == tostring(L["Nightmare"]) or text:find("Nightmare", 1, true) then
        return "nightmare"
    end
    if text == tostring(L["Hard"]) or text:find("Hard", 1, true) then
        return "hard"
    end
    return "normal"
end

local function GetPreyWeeklyCompleted(charKey, weekKey)
    EnsureDB()
    local weeks = db.preyWeeklyProgress[charKey]
    if type(weeks) ~= "table" then
        weeks = {}
        db.preyWeeklyProgress[charKey] = weeks
    end

    local entry = weeks[weekKey]
    if type(entry) ~= "table" then
        entry = { normal = 0, hard = 0, nightmare = 0 }
        weeks[weekKey] = entry
    end

    entry.normal = math.max(0, tonumber(entry.normal) or 0)
    entry.hard = math.max(0, tonumber(entry.hard) or 0)
    entry.nightmare = math.max(0, tonumber(entry.nightmare) or 0)
    return entry
end

local function GetPreyAvailabilityFromHuntScanner()
    local scanner = Preydator and Preydator.GetModule and Preydator:GetModule("HuntScanner")
    if not scanner or type(scanner.GetAvailabilityCounts) ~= "function" then
        return nil, false
    end

    local counts = scanner:GetAvailabilityCounts()
    if type(counts) ~= "table" then
        return nil, false
    end

    if counts.known == false then
        return nil, false
    end

    return {
        normal = math.max(0, tonumber(counts.normal) or 0),
        hard = math.max(0, tonumber(counts.hard) or 0),
        nightmare = math.max(0, tonumber(counts.nightmare) or 0),
        capturedAt = GetTime and GetTime() or 0,
    }, true
end

local function RecordPreyTurnIn(questID)
    local id = tonumber(questID)
    if not id or id < 1 then
        return
    end

    local state = GetCurrentPreyState()
    if not state or tonumber(state.activeQuestID) ~= id then
        return
    end

    EnsureDB()
    local key = CharacterKey()
    local weekKey = GetWeeklyResetKey()
    local completed = GetPreyWeeklyCompleted(key, weekKey)
    local diffKey = NormalizePreyDifficultyKey(state.preyTargetDifficulty)
    completed[diffKey] = (tonumber(completed[diffKey]) or 0) + 1
end

local function BuildPreyProgressTriplet(snap, mode)
    local level = tonumber(snap and snap.level) or 0
    local maxNormal = 4
    local maxHard = (level >= 90) and 4 or 0
    local maxNightmare = (snap and snap.nightmareUnlocked == true) and 4 or 0

    local completed = type(snap and snap.weeklyCompleted) == "table" and snap.weeklyCompleted or {}
    local normalDone = math.max(0, tonumber(completed.normal) or 0)
    local hardDone = math.max(0, tonumber(completed.hard) or 0)
    local nightmareDone = math.max(0, tonumber(completed.nightmare) or 0)
    local availabilityKnown = (snap and snap.preyAvailabilityKnown == true)

    local available = type(snap and snap.preyAvailableCounts) == "table" and snap.preyAvailableCounts or nil

    if not availabilityKnown and not available and normalDone == 0 and hardDone == 0 and nightmareDone == 0 then
        return "?/?/?"
    end

    if maxNightmare == 0 and level >= 90 and type(snap and snap.preyTargetDifficulty) == "string" and tostring(snap.preyTargetDifficulty):find("Nightmare", 1, true) then
        maxNightmare = 4
    end

    if available then
        local availableNormal = math.max(0, tonumber(available.normal) or 0)
        local availableHard = math.max(0, tonumber(available.hard) or 0)
        local availableNightmare = math.max(0, tonumber(available.nightmare) or 0)

        if availableHard > 0 and maxHard == 0 then
            maxHard = 4
        end
        if availableNightmare > 0 and maxNightmare == 0 then
            maxNightmare = 4
        end

        maxNormal = math.max(maxNormal, availableNormal + normalDone)
        maxHard = math.max(maxHard, availableHard + hardDone)
        maxNightmare = math.max(maxNightmare, availableNightmare + nightmareDone)
    end

    if mode ~= "completed" then
        local nLeft
        local hLeft
        local niLeft

        if available then
            nLeft = math.max(0, tonumber(available.normal) or 0)
            hLeft = (maxHard > 0) and math.max(0, tonumber(available.hard) or 0) or nil
            niLeft = (maxNightmare > 0) and math.max(0, tonumber(available.nightmare) or 0) or nil
        else
            nLeft = math.max(0, maxNormal - normalDone)
            hLeft = (maxHard > 0) and math.max(0, maxHard - hardDone) or nil
            niLeft = (maxNightmare > 0) and math.max(0, maxNightmare - nightmareDone) or nil
        end

        local n = tostring(nLeft)
        local h = (hLeft ~= nil) and tostring(hLeft) or "-"
        local ni = (niLeft ~= nil) and tostring(niLeft) or "-"
        return n .. "/" .. h .. "/" .. ni
    end

    local nDoneDisplay = normalDone
    local hDoneDisplay = hardDone
    local niDoneDisplay = nightmareDone

    if available then
        nDoneDisplay = math.max(normalDone, math.max(0, maxNormal - (tonumber(available.normal) or 0)))
        if maxHard > 0 then
            hDoneDisplay = math.max(hardDone, math.max(0, maxHard - (tonumber(available.hard) or 0)))
        end
        if maxNightmare > 0 then
            niDoneDisplay = math.max(nightmareDone, math.max(0, maxNightmare - (tonumber(available.nightmare) or 0)))
        end
    end

    local n = tostring(nDoneDisplay)
    local h = (maxHard > 0) and tostring(hDoneDisplay) or "-"
    local ni = (maxNightmare > 0) and tostring(niDoneDisplay) or "-"
    return n .. "/" .. h .. "/" .. ni
end

local function SnapshotCurrentPreyCharacter()
    EnsureDB()
    local state = GetCurrentPreyState()
    if not state then
        return
    end

    local key = CharacterKey()
    local weekKey = GetWeeklyResetKey()
    local weeklyCompleted = GetPreyWeeklyCompleted(key, weekKey)
    local availableCounts, availabilityKnown = GetPreyAvailabilityFromHuntScanner()
    local existing = db.preySnapshots[key]
    if not availabilityKnown and type(existing) == "table" and existing.preyAvailabilityKnown == true and type(existing.preyAvailableCounts) == "table" then
        availableCounts = {
            normal = math.max(0, tonumber(existing.preyAvailableCounts.normal) or 0),
            hard = math.max(0, tonumber(existing.preyAvailableCounts.hard) or 0),
            nightmare = math.max(0, tonumber(existing.preyAvailableCounts.nightmare) or 0),
            capturedAt = math.max(0, tonumber(existing.preyAvailableCounts.capturedAt) or 0),
        }
        availabilityKnown = true
    end

    if not availabilityKnown then
        local hasWeeklyProgress = (tonumber(weeklyCompleted.normal) or 0) > 0
            or (tonumber(weeklyCompleted.hard) or 0) > 0
            or (tonumber(weeklyCompleted.nightmare) or 0) > 0
        if hasWeeklyProgress then
            availabilityKnown = true
        end
    end
    local classFile = nil
    if UnitClass then
        local _, token = UnitClass("player")
        classFile = token
    end

    db.preySnapshots[key] = {
        stage = tonumber(state.stage) or 0,
        level = UnitLevel and (tonumber(UnitLevel("player")) or 0) or 0,
        zoneName = state.preyZoneName or ((GetZoneText and GetZoneText()) or ""),
        activeQuestID = tonumber(state.activeQuestID) or 0,
        inPreyZone = state.inPreyZone == true,
        preyTargetName = state.preyTargetName,
        preyTargetDifficulty = state.preyTargetDifficulty,
        nightmareUnlocked = (type(state.preyTargetDifficulty) == "string" and tostring(state.preyTargetDifficulty):find("Nightmare", 1, true) ~= nil) and true or false,
        rankLabel = BuildPreyRankLabel(state.stage, state.preyTargetDifficulty),
        weeklyKey = weekKey,
        weeklyCompleted = {
            normal = tonumber(weeklyCompleted.normal) or 0,
            hard = tonumber(weeklyCompleted.hard) or 0,
            nightmare = tonumber(weeklyCompleted.nightmare) or 0,
        },
        preyAvailabilityKnown = availabilityKnown == true,
        preyAvailableCounts = availableCounts,
        lastSeen = GetTime(),
        classFile = classFile,
    }
end

local function GetPreySnapshotRows()
    if not db or type(db.preySnapshots) ~= "table" then
        return {}
    end

    local rows = {}
    for charKey, snap in pairs(db.preySnapshots) do
        rows[#rows + 1] = { charKey = charKey, snap = snap }
    end

    local currentKey = CharacterKey()
    table.sort(rows, function(a, b)
        local aIsCurrent = a.charKey == currentKey
        local bIsCurrent = b.charKey == currentKey
        if aIsCurrent ~= bIsCurrent then
            return aIsCurrent
        end
        return a.charKey < b.charKey
    end)

    return rows
end

local function IsCurrencyDebugEnabled()
    local api = Preydator and Preydator.API
    if not api or type(api.GetSettings) ~= "function" then
        return false
    end

    local settings = api.GetSettings()
    return settings and settings.currencyDebugEvents == true
end

local function LogCurrencyDebug(message)
    if not IsCurrencyDebugEnabled() then
        return
    end

    print("Preydator CurrencyDebug: " .. tostring(message))
end

local function SnapshotCurrentCharacter()
    EnsureDB()
    local key = CharacterKey()
    db.snapshots[key] = db.snapshots[key] or {}
    local classFile = nil
    if UnitClass then
        local _, token = UnitClass("player")
        classFile = token
    end

    for _, entry in ipairs(CURRENCY_ALLOW_LIST) do
        local qty = GetCurrencyQuantity(entry.id)
        db.snapshots[key][entry.id] = { quantity = qty, lastSeen = GetTime(), classFile = classFile }
    end
end

local function PrimeSessionBaseline(source)
    EnsureDB()

    local key = CharacterKey()
    local existing = db and db.snapshots and db.snapshots[key] or nil
    local allZero = true
    local hasExistingNonZero = false

    for _, entry in ipairs(CURRENCY_ALLOW_LIST) do
        local qty = GetCurrencyQuantity(entry.id)
        sessionStart[entry.id] = qty
        if qty ~= 0 then
            allZero = false
        end

        local prev = existing and existing[entry.id]
        if type(prev) == "table" and (tonumber(prev.quantity) or 0) > 0 then
            hasExistingNonZero = true
        end
    end

    -- If the API is still cold at login, keep deltas hidden until a valid baseline lands.
    if allZero and hasExistingNonZero then
        sessionBaselineReady = false
        LogCurrencyDebug("SessionBaseline pending [" .. tostring(source or "unknown") .. "]: API returned zeros while prior snapshot has non-zero totals")
        return false
    end

    sessionBaselineReady = true
    local parts = {}
    for _, entry in ipairs(CURRENCY_ALLOW_LIST) do
        parts[#parts + 1] = entry.label .. "=" .. tostring(sessionStart[entry.id] or 0)
    end
    LogCurrencyDebug("SessionBaseline ready [" .. tostring(source or "unknown") .. "]: " .. table.concat(parts, ", "))
    return true
end

local function UpdateLastKnownQuantities()
    local changedEntries = {}
    for _, entry in ipairs(CURRENCY_ALLOW_LIST) do
        local qty = GetCurrencyQuantity(entry.id)
        local oldQty = lastKnownQuantity[entry.id]
        if oldQty == nil then
            lastKnownQuantity[entry.id] = qty
        elseif oldQty ~= qty then
            changedEntries[#changedEntries + 1] = {
                id = entry.id,
                label = entry.label,
                old = oldQty,
                new = qty,
            }
            lastKnownQuantity[entry.id] = qty
        end
    end
    return changedEntries
end

local function SessionDelta(currencyID)
    if not sessionBaselineReady then
        return 0
    end
    local start = sessionStart[currencyID]
    if not start then return 0 end
    return GetCurrencyQuantity(currencyID) - start
end

-- Rebuild the warband aggregate from all known snapshots
local function RebuildWarbandTotals()
    if not db then return end
    db.warbandTotal = {}
    for _, charSnaps in pairs(db.snapshots) do
        for currencyID, snap in pairs(charSnaps) do
            db.warbandTotal[currencyID] = (db.warbandTotal[currencyID] or 0) + (snap.quantity or 0)
        end
    end
end

-- Returns sorted list of { charKey, snaps } for warband table display
local function GetWarbandRows()
    if not db then return {} end
    local rows = {}
    for charKey, snaps in pairs(db.snapshots) do
        rows[#rows + 1] = { charKey = charKey, snaps = snaps }
    end
    local currentKey = CharacterKey()
    table.sort(rows, function(a, b)
        -- Current character first, then alphabetical for stable ordering.
        local aIsCurrent = a.charKey == currentKey
        local bIsCurrent = b.charKey == currentKey
        if aIsCurrent ~= bIsCurrent then
            return aIsCurrent
        end
        return a.charKey < b.charKey
    end)
    return rows
end

-- UI helpers and tracker settings
--------------------------------------------------------------------------------

local function SetTextColor(fs, col)
    if col then
        fs:SetTextColor(col[1], col[2], col[3], col[4] or 1)
    end
end

local function ClampNumber(value, minValue, maxValue, fallback)
    local numeric = tonumber(value)
    if not numeric then
        return fallback
    end
    if numeric < minValue then
        return minValue
    end
    if numeric > maxValue then
        return maxValue
    end
    return math.floor(numeric + 0.5)
end

local function ClampFloat(value, minValue, maxValue, fallback, decimals)
    local numeric = tonumber(value)
    if not numeric then
        return fallback
    end
    if numeric < minValue then
        numeric = minValue
    elseif numeric > maxValue then
        numeric = maxValue
    end

    if type(decimals) == "number" and decimals >= 0 then
        local mult = 10 ^ decimals
        numeric = math.floor((numeric * mult) + 0.5) / mult
    end
    return numeric
end

local function SetFontSize(fs, size)
    if not fs or type(fs.GetFont) ~= "function" or type(fs.SetFont) ~= "function" then
        return
    end
    local fontPath, _, flags = fs:GetFont()
    if fontPath then
        fs:SetFont(fontPath, size, flags)
    end
end

local function ColorsClose(left, right)
    if type(left) ~= "table" or type(right) ~= "table" then
        return false
    end
    local epsilon = 0.001
    for i = 1, 4 do
        local l = tonumber(left[i] or 1) or 1
        local r = tonumber(right[i] or 1) or 1
        if math.abs(l - r) > epsilon then
            return false
        end
    end
    return true
end

local function OpenColorPicker(initialColor, callback)
    local picker = _G.ColorPickerFrame
    if not picker then
        return
    end

    local start = {
        (initialColor and initialColor[1]) or 1,
        (initialColor and initialColor[2]) or 1,
        (initialColor and initialColor[3]) or 1,
        (initialColor and initialColor[4]) or 1,
    }

    local function apply()
        local r, g, b
        if picker.GetColorRGB then
            r, g, b = picker:GetColorRGB()
        elseif picker.Content and picker.Content.ColorPicker and picker.Content.ColorPicker.GetColorRGB then
            r, g, b = picker.Content.ColorPicker:GetColorRGB()
        else
            r, g, b = start[1], start[2], start[3]
        end
        callback({ r, g, b, start[4] })
    end

    local function cancel(previousValues)
        if type(previousValues) == "table" then
            callback({ previousValues.r or start[1], previousValues.g or start[2], previousValues.b or start[3], previousValues.a or start[4] })
            return
        end
        callback(start)
    end

    if picker.SetupColorPickerAndShow then
        picker:SetupColorPickerAndShow({
            r = start[1],
            g = start[2],
            b = start[3],
            hasOpacity = false,
            swatchFunc = apply,
            func = apply,
            cancelFunc = cancel,
        })
        return
    end

    picker.hasOpacity = false
    picker.previousValues = { start[1], start[2], start[3], start[4] }
    picker.func = apply
    picker.swatchFunc = apply
    picker.cancelFunc = cancel
    picker:SetColorRGB(start[1], start[2], start[3])
    picker:Hide()
    picker:Show()
end

local function GetSettings()
    local api = Preydator and Preydator.API
    if not api or type(api.GetSettings) ~= "function" then
        return nil
    end
    return api.GetSettings()
end

local function GetThemePreset()
    local settings = GetSettings()
    local key = settings and settings.currencyTheme or "brown"
    return THEME_PRESETS[key] or THEME_PRESETS.brown
end

local function GetWarbandThemePreset()
    local settings = GetSettings()
    local useCurrencyTheme = not settings or settings.currencyWarbandUseCurrencyTheme ~= false
    local key = useCurrencyTheme and (settings and settings.currencyTheme or "brown") or (settings and settings.currencyWarbandTheme or "brown")
    return THEME_PRESETS[key] or THEME_PRESETS.brown
end

local function EnsureTrackerSettings()
    local settings = GetSettings()
    if not settings then
        return
    end

    if settings.currencyWindowEnabled == nil then
        settings.currencyWindowEnabled = false
    end

    if settings.currencyMinimapButton == nil then
        settings.currencyMinimapButton = true
    end

    if type(settings.currencyMinimapAngle) ~= "number" then
        settings.currencyMinimapAngle = 225
    end

    if type(settings.currencyMinimap) ~= "table" then
        settings.currencyMinimap = {}
    end
    if settings.currencyMinimap.hide == nil then
        settings.currencyMinimap.hide = settings.currencyMinimapButton == false
    end
    if type(settings.currencyMinimap.minimapPos) ~= "number" then
        settings.currencyMinimap.minimapPos = settings.currencyMinimapAngle
    end
    settings.currencyMinimapButton = settings.currencyMinimap.hide ~= true
    settings.currencyMinimapAngle = settings.currencyMinimap.minimapPos

    if type(settings.currencyWindowPoint) ~= "table" then
        settings.currencyWindowPoint = { anchor = "CENTER", relativePoint = "CENTER", x = 340, y = -80 }
    end

    if settings.currencyWarbandWindowEnabled == nil then
        settings.currencyWarbandWindowEnabled = false
    end

    if type(settings.currencyWarbandWindowPoint) ~= "table" then
        settings.currencyWarbandWindowPoint = { anchor = "CENTER", relativePoint = "CENTER", x = 660, y = -80 }
    end

    if settings.currencyShowAffordableHunts == nil then
        settings.currencyShowAffordableHunts = false
    end

    if settings.currencyShowRealmInWarband == nil then
        settings.currencyShowRealmInWarband = false
    end

    if settings.currencyWarbandShowPreyTrack == nil then
        settings.currencyWarbandShowPreyTrack = true
    end

    if settings.currencyWarbandPreyMode ~= "completed" and settings.currencyWarbandPreyMode ~= "available" then
        settings.currencyWarbandPreyMode = "available"
    end

    if settings.currencyWarbandUseCurrencyTheme == nil then
        settings.currencyWarbandUseCurrencyTheme = true
    end

    if type(settings.currencyWarbandTheme) ~= "string" then
        settings.currencyWarbandTheme = "brown"
    end

    if type(settings.currencyTheme) ~= "string" then
        settings.currencyTheme = "brown"
    end

    if type(settings.currencyDeltaGainColor) ~= "table" then
        settings.currencyDeltaGainColor = { COLOR_GREEN[1], COLOR_GREEN[2], COLOR_GREEN[3], COLOR_GREEN[4] }
    elseif ColorsClose(settings.currencyDeltaGainColor, LEGACY_GAIN_COLOR) then
        settings.currencyDeltaGainColor = { COLOR_GREEN[1], COLOR_GREEN[2], COLOR_GREEN[3], COLOR_GREEN[4] }
    end

    if type(settings.currencyDeltaLossColor) ~= "table" then
        settings.currencyDeltaLossColor = { COLOR_RED[1], COLOR_RED[2], COLOR_RED[3], COLOR_RED[4] }
    elseif ColorsClose(settings.currencyDeltaLossColor, LEGACY_LOSS_COLOR) then
        settings.currencyDeltaLossColor = { COLOR_RED[1], COLOR_RED[2], COLOR_RED[3], COLOR_RED[4] }
    end

    if type(settings.currencyTrackedIDs) ~= "table" then
        settings.currencyTrackedIDs = {}
    end

    if type(settings.currencyWarbandTrackedIDs) ~= "table" then
        settings.currencyWarbandTrackedIDs = {}
    end

    for _, entry in ipairs(CURRENCY_ALLOW_LIST) do
        if settings.currencyTrackedIDs[entry.id] == nil then
            settings.currencyTrackedIDs[entry.id] = true
        end
        if settings.currencyWarbandTrackedIDs[entry.id] == nil then
            settings.currencyWarbandTrackedIDs[entry.id] = true
        end
    end

    if type(settings.randomHuntCosts) ~= "table" then
        settings.randomHuntCosts = {}
    end
    if type(settings.randomHuntCosts.normal) ~= "number" or settings.randomHuntCosts.normal <= 0 then
        settings.randomHuntCosts.normal = 50
    end
    if type(settings.randomHuntCosts.hard) ~= "number" or settings.randomHuntCosts.hard <= 0 then
        settings.randomHuntCosts.hard = 50
    end
    if type(settings.randomHuntCosts.nightmare) ~= "number" then
        settings.randomHuntCosts.nightmare = 0
    end

    settings.currencyWindowWidth = ClampNumber(settings.currencyWindowWidth, TRACKER_MIN_WIDTH, TRACKER_MAX_WIDTH, TRACKER_WINDOW_WIDTH)
    settings.currencyWindowHeight = ClampNumber(settings.currencyWindowHeight, TRACKER_MIN_HEIGHT, TRACKER_MAX_HEIGHT, TRACKER_WINDOW_HEIGHT)
    settings.currencyWindowFontSize = ClampNumber(settings.currencyWindowFontSize, TRACKER_MIN_FONT, TRACKER_MAX_FONT, TRACKER_DEFAULT_FONT)
    settings.currencyWindowScale = ClampFloat(settings.currencyWindowScale, TRACKER_MIN_SCALE, TRACKER_MAX_SCALE, TRACKER_DEFAULT_SCALE, 2)

    settings.currencyWarbandWidth = ClampNumber(settings.currencyWarbandWidth, WARBAND_MIN_WIDTH, WARBAND_MAX_WIDTH, WARBAND_DEFAULT_WIDTH)
    settings.currencyWarbandHeight = ClampNumber(settings.currencyWarbandHeight, WARBAND_MIN_HEIGHT, WARBAND_MAX_HEIGHT, WARBAND_DEFAULT_HEIGHT)
    settings.currencyWarbandFontSize = ClampNumber(settings.currencyWarbandFontSize, WARBAND_MIN_FONT, WARBAND_MAX_FONT, WARBAND_DEFAULT_FONT)
    settings.currencyWarbandScale = ClampFloat(settings.currencyWarbandScale, WARBAND_MIN_SCALE, WARBAND_MAX_SCALE, WARBAND_DEFAULT_SCALE, 2)

    if type(settings.currencyWarbandCollapsedRealms) ~= "table" then
        settings.currencyWarbandCollapsedRealms = {}
    end
end

local function GetTrackedCurrencyEntries()
    local settings = GetSettings()
    if not settings or type(settings.currencyTrackedIDs) ~= "table" then
        return CURRENCY_ALLOW_LIST
    end

    local rows = {}
    for _, entry in ipairs(CURRENCY_ALLOW_LIST) do
        if settings.currencyTrackedIDs[entry.id] ~= false then
            rows[#rows + 1] = entry
        end
    end

    if #rows == 0 then
        rows[1] = CURRENCY_ALLOW_LIST[1]
    end

    return rows
end

local function IsCurrencyTracked(settings, currencyID)
    if not settings or type(settings.currencyTrackedIDs) ~= "table" then
        return true
    end
    return settings.currencyTrackedIDs[currencyID] ~= false
end

local function IsWarbandCurrencyTracked(settings, currencyID)
    if not settings or type(settings.currencyWarbandTrackedIDs) ~= "table" then
        return true
    end
    return settings.currencyWarbandTrackedIDs[currencyID] ~= false
end

local currencyWindow
local currencyWindowRows = {}
local currencyWindowSummary
local currencyPanelPage
local minimapButton
local warbandWindow
local warbandWindowSummary
local warbandWindowRows = {}
local warbandHeaderTexts = {}
local warbandTotalTexts = {}
local warbandHeaderButtons = {}
local warbandColumns = {}

local function OpenOptionsPanel()
    local settingsModule = Preydator:GetModule("Settings")
    if settingsModule and type(settingsModule.OpenOptionsPanel) == "function" then
        settingsModule:OpenOptionsPanel()
    end
end

local function EnsureCurrencyWhatsNewFrame()
    if currencyWhatsNewFrame then
        return currencyWhatsNewFrame
    end

    local frame = CreateFrame("Frame", "PreydatorCurrencyWhatsNewFrame", UIParent, "BackdropTemplate")
    frame:SetSize(520, 320)
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 20)
    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self)
        self:StartMoving()
    end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
    end)
    frame:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    frame:SetBackdropColor(0.05, 0.04, 0.03, 0.96)
    frame:SetBackdropBorderColor(COLOR_BORDER[1], COLOR_BORDER[2], COLOR_BORDER[3], 1)

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", frame, "TOPLEFT", 18, -18)
    title:SetText(L["Preydator Updates: New in 1.7.0"])
    SetTextColor(title, COLOR_GOLD)

    local body = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    body:SetPoint("TOPLEFT", frame, "TOPLEFT", 18, -52)
    body:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -18, -52)
    body:SetJustifyH("LEFT")
    body:SetJustifyV("TOP")
    body:SetText(L["WHATS_NEW_BODY"])

    local closeButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    closeButton:SetSize(120, 24)
    closeButton:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -18, 16)
    closeButton:SetText(L["Got It"])

    local settingsButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    settingsButton:SetSize(140, 24)
    settingsButton:SetPoint("RIGHT", closeButton, "LEFT", -8, 0)
    settingsButton:SetText(L["Open Settings"])

    closeButton:SetScript("OnClick", function()
        local settings = GetSettings()
        if settings then
            settings.currencyWhatsNewSeenVersion = CURRENCY_WHATS_NEW_VERSION
        end
        frame:Hide()
    end)

    settingsButton:SetScript("OnClick", function()
        local settings = GetSettings()
        if settings then
            settings.currencyWhatsNewSeenVersion = CURRENCY_WHATS_NEW_VERSION
        end
        frame:Hide()
        OpenOptionsPanel()
    end)

    frame:Hide()
    currencyWhatsNewFrame = frame
    return frame
end

local function ShowCurrencyWhatsNewIfNeeded()
    local settings = GetSettings()
    if not settings then
        return
    end

    if settings.currencyWhatsNewSeenVersion == CURRENCY_WHATS_NEW_VERSION then
        return
    end

    EnsureCurrencyWhatsNewFrame():Show()
end

function CurrencyTrackerModule:ShowCurrencyWhatsNew(force)
    local settings = GetSettings()
    if not settings then
        return
    end

    if force == true then
        settings.currencyWhatsNewSeenVersion = nil
    end

    ShowCurrencyWhatsNewIfNeeded()
end

local function ToggleCurrencyWindow()
    local settings = GetSettings()
    if not settings then
        return
    end

    settings.currencyWindowEnabled = not (settings.currencyWindowEnabled == true)
    if currencyWindow then
        currencyWindow:SetShown(settings.currencyWindowEnabled == true)
    end
    if settings.currencyWindowEnabled then
        CurrencyTrackerModule:RefreshCurrencyPage()
    end
end

local function ToggleWarbandWindow()
    local settings = GetSettings()
    if not settings then
        return
    end

    settings.currencyWarbandWindowEnabled = not (settings.currencyWarbandWindowEnabled == true)
    if warbandWindow then
        warbandWindow:SetShown(settings.currencyWarbandWindowEnabled == true)
    end
    if settings.currencyWarbandWindowEnabled then
        CurrencyTrackerModule:RefreshCurrencyPage()
    end
end

function CurrencyTrackerModule:ToggleWarbandWindow()
    EnsureTrackerSettings()
    EnsureWarbandWindow()
    ToggleWarbandWindow()
end

local function HandleMinimapClick(mouseButton)
    if mouseButton == "LeftButton" then
        ToggleCurrencyWindow()
        return
    end

    if mouseButton == "RightButton" and IsShiftKeyDown and IsShiftKeyDown() then
        OpenOptionsPanel()
        return
    end

    if mouseButton == "RightButton" then
        ToggleWarbandWindow()
    end
end

local function UpdateWindowPosition()
    if not currencyWindow then
        return
    end

    local settings = GetSettings()
    local point = settings and settings.currencyWindowPoint
    currencyWindow:ClearAllPoints()
    if type(point) == "table" then
        currencyWindow:SetPoint(point.anchor or "CENTER", UIParent, point.relativePoint or "CENTER", point.x or 340, point.y or -80)
    else
        currencyWindow:SetPoint("CENTER", UIParent, "CENTER", 340, -80)
    end
end

local function SaveWindowPosition(frame)
    local settings = GetSettings()
    if not settings then
        return
    end

    local point, _, relativePoint, x, y = frame:GetPoint(1)
    settings.currencyWindowPoint = {
        anchor = point or "CENTER",
        relativePoint = relativePoint or "CENTER",
        x = math.floor((x or 0) + 0.5),
        y = math.floor((y or 0) + 0.5),
    }
end

local function UpdateMinimapButtonPosition()
    if not minimapButton then
        return
    end

    local settings = GetSettings()
    local angle = 225
    if settings and type(settings.currencyMinimap) == "table" and type(settings.currencyMinimap.minimapPos) == "number" then
        angle = settings.currencyMinimap.minimapPos
    elseif settings and type(settings.currencyMinimapAngle) == "number" then
        angle = settings.currencyMinimapAngle
    end
    angle = NormalizeAngleDegrees(angle)
    local minimap = _G.Minimap
    if not minimap then
        return
    end

    local radians = math.rad(angle)
    local minimapRadius = (math.min(minimap:GetWidth(), minimap:GetHeight()) / 2)
    local radius = minimapRadius + 8
    local x = math.cos(radians) * radius
    local y = math.sin(radians) * radius

    minimapButton:ClearAllPoints()
    minimapButton:SetPoint("CENTER", minimap, "CENTER", x, y)
end

local function UpdateVisibilityFromSettings()
    local settings = GetSettings()
    if not settings then
        return
    end

    if currencyWindow then
        currencyWindow:SetShown(settings.currencyWindowEnabled ~= false)
    end

    if warbandWindow then
        warbandWindow:SetShown(settings.currencyWarbandWindowEnabled == true)
    end

    if LibDBIcon and ldbIconRegistered then
        settings.currencyMinimap.hide = settings.currencyMinimapButton == false
        if settings.currencyMinimap.hide then
            LibDBIcon:Hide(LDB_LAUNCHER_NAME)
        else
            LibDBIcon:Show(LDB_LAUNCHER_NAME)
        end
    end

    if minimapButton then
        minimapButton:SetShown((settings.currencyMinimapButton ~= false) and not (LibDBIcon and ldbIconRegistered))
    end
end

local function UpdateWarbandWindowPosition()
    if not warbandWindow then
        return
    end

    local settings = GetSettings()
    local point = settings and settings.currencyWarbandWindowPoint
    warbandWindow:ClearAllPoints()
    if type(point) == "table" then
        warbandWindow:SetPoint(point.anchor or "CENTER", UIParent, point.relativePoint or "CENTER", point.x or 660, point.y or -80)
    else
        warbandWindow:SetPoint("CENTER", UIParent, "CENTER", 660, -80)
    end
end

local function SaveWarbandWindowPosition(frame)
    local settings = GetSettings()
    if not settings then
        return
    end

    local point, _, relativePoint, x, y = frame:GetPoint(1)
    settings.currencyWarbandWindowPoint = {
        anchor = point or "CENTER",
        relativePoint = relativePoint or "CENTER",
        x = math.floor((x or 0) + 0.5),
        y = math.floor((y or 0) + 0.5),
    }
end

local function GetCurrencyWindowConfig()
    local settings = GetSettings()
    local width = ClampNumber(settings and settings.currencyWindowWidth, TRACKER_MIN_WIDTH, TRACKER_MAX_WIDTH, TRACKER_WINDOW_WIDTH)
    local height = ClampNumber(settings and settings.currencyWindowHeight, TRACKER_MIN_HEIGHT, TRACKER_MAX_HEIGHT, TRACKER_WINDOW_HEIGHT)
    local fontSize = ClampNumber(settings and settings.currencyWindowFontSize, TRACKER_MIN_FONT, TRACKER_MAX_FONT, TRACKER_DEFAULT_FONT)
    local scale = ClampFloat(settings and settings.currencyWindowScale, TRACKER_MIN_SCALE, TRACKER_MAX_SCALE, TRACKER_DEFAULT_SCALE, 2)
    return width, height, fontSize, scale
end

local function GetWarbandWindowConfig()
    local settings = GetSettings()
    local width = ClampNumber(settings and settings.currencyWarbandWidth, WARBAND_MIN_WIDTH, WARBAND_MAX_WIDTH, WARBAND_DEFAULT_WIDTH)
    local height = ClampNumber(settings and settings.currencyWarbandHeight, WARBAND_MIN_HEIGHT, WARBAND_MAX_HEIGHT, WARBAND_DEFAULT_HEIGHT)
    local fontSize = ClampNumber(settings and settings.currencyWarbandFontSize, WARBAND_MIN_FONT, WARBAND_MAX_FONT, WARBAND_DEFAULT_FONT)
    local scale = ClampFloat(settings and settings.currencyWarbandScale, WARBAND_MIN_SCALE, WARBAND_MAX_SCALE, WARBAND_DEFAULT_SCALE, 2)
    return width, height, fontSize, scale
end

local function CreateCurrencyWindowRow(parent, yOffset)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(TRACKER_ROW_WIDTH, TRACKER_ROW_HEIGHT)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", 12, yOffset)

    local bg = row:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(COLOR_ROW_BG[1], COLOR_ROW_BG[2], COLOR_ROW_BG[3], COLOR_ROW_BG[4])
    row.bg = bg

    local icon = row:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("LEFT", row, "LEFT", 6, 0)
    icon:SetSize(20, 20)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    local nameText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    nameText:SetPoint("LEFT", icon, "RIGHT", 8, 0)
    nameText:SetWidth(110)
    nameText:SetJustifyH("LEFT")

    local qtyText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    qtyText:SetPoint("RIGHT", row, "RIGHT", -8, 6)
    qtyText:SetJustifyH("RIGHT")

    local deltaText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    deltaText:SetPoint("RIGHT", row, "RIGHT", -8, -8)
    deltaText:SetJustifyH("RIGHT")

    row.icon = icon
    row.nameText = nameText
    row.qtyText = qtyText
    row.deltaText = deltaText
    return row
end

EnsureCurrencyWindow = function()
    if currencyWindow then
        return currencyWindow
    end

    local frame = CreateFrame("Frame", "PreydatorCurrencyTrackerWindow", UIParent, "BackdropTemplate")
    local windowWidth, windowHeight, _, windowScale = GetCurrencyWindowConfig()
    frame:SetSize(windowWidth, windowHeight)
    frame:SetScale(windowScale)
    frame:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 14,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    frame:SetBackdropColor(0.03, 0.03, 0.04, 0.95)
    frame:SetBackdropBorderColor(COLOR_BORDER[1], COLOR_BORDER[2], COLOR_BORDER[3], COLOR_BORDER[4])
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self)
        self:StartMoving()
    end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        SaveWindowPosition(self)
    end)

    local bg = frame:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.02, 0.02, 0.03, 0.88)

    local topBar = frame:CreateTexture(nil, "BORDER")
    topBar:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    topBar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    topBar:SetHeight(26)
    topBar:SetColorTexture(0.20, 0.14, 0.06, 0.95)

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("LEFT", frame, "TOPLEFT", 10, -13)
    title:SetText(L["Preydator Currency"])
    SetTextColor(title, COLOR_GOLD)
    frame.PreydatorTitle = title

    local closeButton = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    closeButton:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -2, -2)
    closeButton:SetScript("OnClick", function()
        local settings = GetSettings()
        if settings then
            settings.currencyWindowEnabled = false
        end
        frame:Hide()
    end)

    local summary = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    summary:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, -36)
    summary:SetWidth(windowWidth - 28)
    summary:SetJustifyH("LEFT")
    summary:SetWordWrap(true)
    currencyWindowSummary = summary

    frame.PreydatorBg = bg
    frame.PreydatorTopBar = topBar

    currencyWindowRows = {}
    for index = 1, #CURRENCY_ALLOW_LIST do
        currencyWindowRows[index] = CreateCurrencyWindowRow(frame, -68 - ((index - 1) * 30))
    end

    frame:SetScript("OnShow", function()
        CurrencyTrackerModule:RefreshCurrencyPage()
    end)

    currencyWindow = frame
    UpdateWindowPosition()
    return frame
end

EnsureWarbandWindow = function()
    if warbandWindow then
        return warbandWindow
    end

    local frame = CreateFrame("Frame", "PreydatorCurrencyWarbandWindow", UIParent, "BackdropTemplate")
    local windowWidth, windowHeight, _, windowScale = GetWarbandWindowConfig()
    frame:SetSize(windowWidth, windowHeight)
    frame:SetScale(windowScale)
    frame:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 14,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    frame:SetBackdropColor(0.03, 0.03, 0.04, 0.95)
    frame:SetBackdropBorderColor(COLOR_BORDER[1], COLOR_BORDER[2], COLOR_BORDER[3], COLOR_BORDER[4])
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self)
        self:StartMoving()
    end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        SaveWarbandWindowPosition(self)
    end)

    local bg = frame:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.02, 0.02, 0.03, 0.88)

    local topBar = frame:CreateTexture(nil, "BORDER")
    topBar:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    topBar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    topBar:SetHeight(26)
    topBar:SetColorTexture(0.20, 0.14, 0.06, 0.95)

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("LEFT", frame, "TOPLEFT", 10, -13)
    title:SetText(L["Preydator Warband"])
    SetTextColor(title, COLOR_GOLD)
    frame.PreydatorTitle = title

    local closeButton = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    closeButton:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -2, -2)
    closeButton:SetScript("OnClick", function()
        local settings = GetSettings()
        if settings then
            settings.currencyWarbandWindowEnabled = false
        end
        frame:Hide()
    end)

    local summary = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    summary:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, -36)
    summary:SetWidth(windowWidth - 24)
    summary:SetJustifyH("LEFT")
    summary:SetWordWrap(true)
    warbandWindowSummary = summary
    frame.PreydatorBg = bg
    frame.PreydatorTopBar = topBar

    warbandColumns = {
        { key = "realm",     label = L["Realm"],     width = 96 },
        { key = "character", label = L["Character"], width = 112 },
        { key = "prey",      label = L["N/H/Ni"],    width = 56 },
        { key = 3392, label = L["Anguish"],  width = 56 },
        { key = 3316, label = L["Voidlight"], width = 64 },
        { key = 3383, label = L["Adv"],      width = 48 },
        { key = 3341, label = L["Vet"],      width = 48 },
        { key = 3343, label = L["Champ"],    width = 56 },
    }

    warbandHeaderTexts = {}
    warbandHeaderButtons = {}
    warbandTotalTexts = {}
    local x = 12
    for _, headerData in ipairs(warbandColumns) do
        local totalText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        totalText:SetPoint("TOPLEFT", frame, "TOPLEFT", x + 2, -40)
        totalText:SetWidth(headerData.width - 4)
        totalText:SetJustifyH((headerData.key == "character" or headerData.key == "realm") and "LEFT" or "RIGHT")
        totalText:SetText(headerData.key == "character" and L["Total"] or "0")
        warbandTotalTexts[headerData.key] = totalText

        local headerButton = CreateFrame("Button", nil, frame)
        headerButton:SetSize(headerData.width, 16)
        headerButton:SetPoint("TOPLEFT", frame, "TOPLEFT", x, -56)
        local text = headerButton:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        text:SetAllPoints()
        text:SetJustifyH((headerData.key == "character" or headerData.key == "realm") and "LEFT" or "RIGHT")
        text:SetText(headerData.label)
        SetTextColor(text, COLOR_GOLD)
        warbandHeaderTexts[headerData.key] = text
        warbandHeaderButtons[headerData.key] = headerButton
        headerButton:SetScript("OnClick", function()
            if warbandSortKey == headerData.key then
                warbandSortAsc = not warbandSortAsc
            else
                warbandSortKey = headerData.key
                warbandSortAsc = true
            end
            CurrencyTrackerModule:RefreshCurrencyPage()
        end)
        x = x + headerData.width
    end

    warbandWindowRows = {}

    frame:SetScript("OnShow", function()
        CurrencyTrackerModule:RefreshCurrencyPage()
    end)

    warbandWindow = frame
    UpdateWarbandWindowPosition()
    return frame
end

local function EnsureWarbandRows(minCount)
    if not warbandWindow then
        return
    end

    while #warbandWindowRows < minCount do
        local index = #warbandWindowRows + 1
        local row = CreateFrame("Button", nil, warbandWindow)
        row:SetSize(396, 16)
        row:RegisterForClicks("LeftButtonUp")

        local rowBg = row:CreateTexture(nil, "BACKGROUND")
        rowBg:SetAllPoints()
        if index % 2 == 0 then
            rowBg:SetColorTexture(COLOR_ROW_BG_ALT[1], COLOR_ROW_BG_ALT[2], COLOR_ROW_BG_ALT[3], 0.55)
        else
            rowBg:SetColorTexture(COLOR_ROW_BG[1], COLOR_ROW_BG[2], COLOR_ROW_BG[3], 0.45)
        end
        row.bg = rowBg

        local cells = {}
        for _, headerData in ipairs(warbandColumns) do
            local cell = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            cell:SetJustifyH((headerData.key == "character" or headerData.key == "realm") and "LEFT" or "RIGHT")
            cells[headerData.key] = cell
        end

        warbandWindowRows[index] = { frame = row, cells = cells }
    end
end

local function ApplyWarbandColumnLayout(showRealm)
    if not warbandWindow then
        return
    end

    local settings = GetSettings()
    local windowWidth, windowHeight, fontSize, windowScale = GetWarbandWindowConfig()
    local orderedCurrencyIDs = { 3392, 3316, 3383, 3341, 3343 }
    local trackedCurrencyIDs = {}
    for _, currencyID in ipairs(orderedCurrencyIDs) do
        if IsWarbandCurrencyTracked(settings, currencyID) then
            trackedCurrencyIDs[#trackedCurrencyIDs + 1] = currencyID
        end
    end
    if #trackedCurrencyIDs == 0 then
        trackedCurrencyIDs[1] = 3392
    end

    local allRows = GetWarbandRows()
    local rowCount = #allRows
    if showRealm then
        local realms = {}
        for _, rowData in ipairs(allRows) do
            local _, realmName = rowData.charKey:match("^(.-)%-(.+)$")
            realmName = realmName or "Unknown"
            realms[realmName] = true
        end
        local realmCount = 0
        for _ in pairs(realms) do
            realmCount = realmCount + 1
        end
        rowCount = rowCount + realmCount
    end

    local realmWidth = showRealm and 96 or 0
    local charWidth = showRealm and 108 or 124
    local maxCharWidth = showRealm and 132 or 148
    local currencyDefaults = {
        [3392] = 56,
        [3316] = 64,
        [3383] = 48,
        [3341] = 48,
        [3343] = 56,
    }

    local preyWidth = (settings and settings.currencyWarbandShowPreyTrack ~= false) and 56 or 0
    local requiredTableWidth = charWidth + realmWidth + preyWidth
    for _, currencyID in ipairs(trackedCurrencyIDs) do
        requiredTableWidth = requiredTableWidth + (currencyDefaults[currencyID] or 48)
    end
    local requiredWindowWidth = math.max(WARBAND_MIN_WIDTH, requiredTableWidth + 24)
    local configuredWidth = tonumber(settings and settings.currencyWarbandWidth)
    local useAutoWidth = configuredWidth == nil or math.abs(configuredWidth - WARBAND_DEFAULT_WIDTH) < 0.01
    local finalWindowWidth = useAutoWidth and requiredWindowWidth or math.max(windowWidth, requiredWindowWidth)

    local rowHeight = math.max(16, fontSize + 4)
    local requiredWindowHeight = 86 + (math.max(1, rowCount) * rowHeight) + 12
    local finalWindowHeight = math.max(windowHeight, requiredWindowHeight)

    warbandWindow:SetSize(finalWindowWidth, finalWindowHeight)
    warbandWindow:SetScale(windowScale)

    local tableWidth = finalWindowWidth - 24

    local currencyWidth = 0
    for _, currencyID in ipairs(trackedCurrencyIDs) do
        currencyWidth = currencyWidth + (currencyDefaults[currencyID] or 48)
    end

    local charSlack = tableWidth - realmWidth - preyWidth - currencyWidth - charWidth
    if charSlack > 0 then
        charWidth = math.min(maxCharWidth, charWidth + charSlack)
    end

    local currencyWidths = {}
    for _, currencyID in ipairs(orderedCurrencyIDs) do
        if IsWarbandCurrencyTracked(settings, currencyID) then
            currencyWidths[currencyID] = currencyDefaults[currencyID] or 48
        else
            currencyWidths[currencyID] = 0
        end
    end

    local effectiveWidths = {
        ["realm"] = realmWidth,
        ["character"] = charWidth,
        ["prey"] = preyWidth,
        [3392] = currencyWidths[3392],
        [3316] = currencyWidths[3316],
        [3383] = currencyWidths[3383],
        [3341] = currencyWidths[3341],
        [3343] = currencyWidths[3343],
    }

    if warbandWindowSummary then
        warbandWindowSummary:SetWidth(tableWidth)
        SetFontSize(warbandWindowSummary, math.max(10, fontSize - 2))
    end
    if warbandWindow.PreydatorTitle then
        SetFontSize(warbandWindow.PreydatorTitle, fontSize)
    end

    local x = 12
    for _, column in ipairs(warbandColumns) do
        local key = column.key
        local width = effectiveWidths[key] or column.width
        local visible = not (key == "realm" and not showRealm)
        local headerButton = warbandHeaderButtons[key]
        local headerText = warbandHeaderTexts[key]
        local totalText = warbandTotalTexts[key]

        if headerButton and headerText and totalText then
            headerButton:SetShown(visible)
            headerText:SetShown(visible)
            totalText:SetShown(visible)
            if visible then
                headerButton:ClearAllPoints()
                headerButton:SetPoint("TOPLEFT", warbandWindow, "TOPLEFT", x, -56)
                headerButton:SetSize(width, 16)
                totalText:ClearAllPoints()
                totalText:SetPoint("TOPLEFT", warbandWindow, "TOPLEFT", x + 2, -40)
                totalText:SetWidth(width - 4)
                totalText:SetJustifyH((key == "character" or key == "realm") and "LEFT" or "RIGHT")
                SetFontSize(totalText, math.max(10, fontSize - 2))
                SetFontSize(headerText, math.max(10, fontSize - 2))
                x = x + width
            end
        end
    end

    local visibleRows = math.max(8, math.floor((finalWindowHeight - 86) / rowHeight))
    EnsureWarbandRows(visibleRows)

    for index, rowData in ipairs(warbandWindowRows) do
        local row = rowData.frame
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", warbandWindow, "TOPLEFT", 12, -76 - ((index - 1) * rowHeight))
        row:SetSize(tableWidth, rowHeight)

        local cellX = 0
        for _, column in ipairs(warbandColumns) do
            local key = column.key
            local width = effectiveWidths[key] or column.width
            local cell = rowData.cells[key]
            local visible = not (key == "realm" and not showRealm)
            if visible then
                cell:Show()
                cell:ClearAllPoints()
                cell:SetPoint("TOPLEFT", row, "TOPLEFT", cellX + 2, -1)
                cell:SetWidth(width - 4)
                cell:SetJustifyH((key == "character" or key == "realm") and "LEFT" or "RIGHT")
                SetFontSize(cell, math.max(10, fontSize - 1))
                cellX = cellX + width
            else
                cell:Hide()
            end
        end
    end
end

local function EnsureLDBLauncher()
    if ldbLauncher or not LibDataBroker then
        return ldbLauncher
    end

    ldbLauncher = LibDataBroker:NewDataObject(LDB_LAUNCHER_NAME, {
        type = "launcher",
        text = "Preydator Currency",
        icon = MINIMAP_ICON_PATH,
        OnClick = function(_, mouseButton)
            HandleMinimapClick(mouseButton)
        end,
        OnTooltipShow = function(tooltip)
            if not tooltip then
                return
            end
            tooltip:AddLine("Preydator")
            tooltip:AddLine(L["Left Click: Toggle Currency Window"], 1, 1, 1)
            tooltip:AddLine(L["Right Click: Toggle Warband Window"], 1, 1, 1)
            tooltip:AddLine(L["Shift + Right Click: Open Options"], 1, 1, 1)
        end,
    })

    return ldbLauncher
end

local function EnsureMinimapButton()
    local settings = GetSettings()
    if LibDBIcon and LibDataBroker and settings and type(settings.currencyMinimap) == "table" then
        EnsureLDBLauncher()
        if not ldbIconRegistered then
            LibDBIcon:Register(LDB_LAUNCHER_NAME, ldbLauncher, settings.currencyMinimap)
            ldbIconRegistered = true
        end
        return nil
    end

    if minimapButton or not _G.Minimap then
        return minimapButton
    end

    local button = CreateFrame("Button", "PreydatorCurrencyMiniMapButton", _G.Minimap)
    button:SetSize(32, 32)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(8)
    button:EnableMouse(true)
    button:SetMovable(true)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:RegisterForDrag("LeftButton")

    local background = button:CreateTexture(nil, "BACKGROUND")
    background:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    background:SetSize(20, 20)
    background:SetPoint("CENTER", button, "CENTER", 0, 0)

    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetTexture(MINIMAP_ICON_PATH)
    icon:SetSize(20, 20)
    icon:SetPoint("CENTER", button, "CENTER", 0, 0)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    local border = button:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetSize(53, 53)
    border:SetPoint("TOPLEFT", button, "TOPLEFT", 0, 0)

    button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    button:SetScript("OnClick", function(self, mouseButton)
        if self.wasDragged then
            return
        end
        HandleMinimapClick(mouseButton)
    end)

    button:SetScript("OnDragStart", function(self)
        self.dragging = true
        self.wasDragged = false
        self:SetScript("OnUpdate", function(s)
            local minimap = _G.Minimap
            if not minimap then
                return
            end
            local mx, my = GetCursorPosition()
            local scale = _G.UIParent:GetEffectiveScale()
            mx, my = mx / scale, my / scale
            local cx, cy = minimap:GetCenter()
            if not cx or not cy then
                return
            end
            local angle = NormalizeAngleDegrees(math.deg(Atan2(my - cy, mx - cx)))
            local settings = GetSettings()
            if settings then
                if type(settings.currencyMinimap) ~= "table" then
                    settings.currencyMinimap = {}
                end
                settings.currencyMinimap.minimapPos = angle
                settings.currencyMinimapAngle = angle
            end
            s.wasDragged = true
            UpdateMinimapButtonPosition()
        end)
    end)

    button:SetScript("OnDragStop", function(self)
        self.dragging = nil
        self:SetScript("OnUpdate", nil)
        C_Timer.After(0.05, function()
            if minimapButton then
                minimapButton.wasDragged = nil
            end
        end)
    end)

    minimapButton = button
    UpdateMinimapButtonPosition()
    return button
end

function CurrencyTrackerModule:SetMinimapButtonEnabled(enabled)
    local settings = GetSettings()
    if not settings then
        return
    end

    EnsureTrackerSettings()
    settings.currencyMinimapButton = enabled == true
    if type(settings.currencyMinimap) ~= "table" then
        settings.currencyMinimap = {}
    end
    settings.currencyMinimap.hide = not settings.currencyMinimapButton

    if settings.currencyMinimapButton then
        EnsureMinimapButton()
        UpdateMinimapButtonPosition()
    end

    UpdateVisibilityFromSettings()
end

local function RefreshWarbandWindowDisplay()
    if not warbandWindow then
        return
    end

    local settings = GetSettings()
    local theme = GetWarbandThemePreset()
    local showRealm = settings and settings.currencyShowRealmInWarband == true
    ApplyWarbandColumnLayout(showRealm)

    if warbandWindow.PreydatorBg then
        warbandWindow.PreydatorBg:SetColorTexture(theme.section[1], theme.section[2], theme.section[3], 0.88)
    end
    if warbandWindow.PreydatorTopBar then
        warbandWindow.PreydatorTopBar:SetColorTexture(theme.header[1], theme.header[2], theme.header[3], 0.95)
    end
    if warbandWindow.SetBackdropBorderColor then
        warbandWindow:SetBackdropBorderColor(theme.border[1], theme.border[2], theme.border[3], theme.border[4] or 1)
    end
    if warbandWindow.PreydatorTitle then
        SetTextColor(warbandWindow.PreydatorTitle, theme.title)
    end
    if warbandWindowSummary then
        SetTextColor(warbandWindowSummary, theme.muted)
    end

    RebuildWarbandTotals()
    local rows = GetWarbandRows()

    local function compareValues(leftValue, rightValue, fallbackLeft, fallbackRight)
        if leftValue == rightValue then
            return (fallbackLeft or "") < (fallbackRight or "")
        end
        if warbandSortAsc then
            return leftValue < rightValue
        end
        return leftValue > rightValue
    end

    table.sort(rows, function(left, right)
        local key = warbandSortKey
        if key == "realm" then
            local _, leftRealm = left.charKey:match("^(.-)%-(.+)$")
            local _, rightRealm = right.charKey:match("^(.-)%-(.+)$")
            leftRealm = leftRealm or "Unknown"
            rightRealm = rightRealm or "Unknown"
            return compareValues(leftRealm, rightRealm, left.charKey, right.charKey)
        end

        local leftValue
        local rightValue
        if key == "character" then
            leftValue = left.charKey
            rightValue = right.charKey
        elseif key == "prey" then
            local leftSnap = settings and settings.preySnapshots and settings.preySnapshots[left.charKey] or nil
            local rightSnap = settings and settings.preySnapshots and settings.preySnapshots[right.charKey] or nil
            leftValue = BuildPreyProgressTriplet(leftSnap, (settings and settings.currencyWarbandPreyMode) or "available")
            rightValue = BuildPreyProgressTriplet(rightSnap, (settings and settings.currencyWarbandPreyMode) or "available")
        else
            leftValue = (left.snaps[key] and left.snaps[key].quantity) or 0
            rightValue = (right.snaps[key] and right.snaps[key].quantity) or 0
        end
        return compareValues(leftValue, rightValue, left.charKey, right.charKey)
    end)

    local displayRows = {}
    if showRealm then
        local collapsedRealms = settings and settings.currencyWarbandCollapsedRealms or {}
        local groups = {}
        local orderedGroups = {}

        for _, rowData in ipairs(rows) do
            local charName, realmName = rowData.charKey:match("^(.-)%-(.+)$")
            if not charName then
                charName = rowData.charKey
                realmName = "Unknown"
            end

            local group = groups[realmName]
            if not group then
                group = {
                    realm = realmName,
                    chars = {},
                    totals = {
                        [3392] = 0,
                        [3316] = 0,
                        [3383] = 0,
                        [3341] = 0,
                        [3343] = 0,
                    },
                }
                groups[realmName] = group
                orderedGroups[#orderedGroups + 1] = group
            end

            local charEntry = {
                type = "character",
                realm = realmName,
                charName = charName,
                charKey = rowData.charKey,
                snaps = rowData.snaps,
                preyTriplet = (settings and settings.currencyWarbandShowPreyTrack ~= false and db and db.preySnapshots and db.preySnapshots[rowData.charKey])
                    and BuildPreyProgressTriplet(db.preySnapshots[rowData.charKey], (settings and settings.currencyWarbandPreyMode) or "available")
                    or "",
            }
            group.chars[#group.chars + 1] = charEntry
            group.totals[3392] = group.totals[3392] + ((rowData.snaps[3392] and rowData.snaps[3392].quantity) or 0)
            group.totals[3316] = group.totals[3316] + ((rowData.snaps[3316] and rowData.snaps[3316].quantity) or 0)
            group.totals[3383] = group.totals[3383] + ((rowData.snaps[3383] and rowData.snaps[3383].quantity) or 0)
            group.totals[3341] = group.totals[3341] + ((rowData.snaps[3341] and rowData.snaps[3341].quantity) or 0)
            group.totals[3343] = group.totals[3343] + ((rowData.snaps[3343] and rowData.snaps[3343].quantity) or 0)
        end

        table.sort(orderedGroups, function(left, right)
            if warbandSortKey == "realm" or warbandSortKey == "character" then
                return compareValues(left.realm, right.realm, left.realm, right.realm)
            end
            if type(warbandSortKey) == "number" then
                return compareValues(left.totals[warbandSortKey] or 0, right.totals[warbandSortKey] or 0, left.realm, right.realm)
            end
            return compareValues(left.realm, right.realm, left.realm, right.realm)
        end)

        for _, group in ipairs(orderedGroups) do
            table.sort(group.chars, function(left, right)
                if warbandSortKey == "character" then
                    return compareValues(left.charName, right.charName, left.charKey, right.charKey)
                end
                if warbandSortKey == "prey" then
                    return compareValues(left.preyTriplet or "", right.preyTriplet or "", left.charName, right.charName)
                end
                if type(warbandSortKey) == "number" then
                    local leftValue = (left.snaps[warbandSortKey] and left.snaps[warbandSortKey].quantity) or 0
                    local rightValue = (right.snaps[warbandSortKey] and right.snaps[warbandSortKey].quantity) or 0
                    return compareValues(leftValue, rightValue, left.charName, right.charName)
                end
                return compareValues(left.charName, right.charName, left.charKey, right.charKey)
            end)

            displayRows[#displayRows + 1] = {
                type = "realm",
                realm = group.realm,
                totals = group.totals,
                collapsed = collapsedRealms[group.realm] == true,
            }

            if collapsedRealms[group.realm] ~= true then
                for _, charEntry in ipairs(group.chars) do
                    displayRows[#displayRows + 1] = charEntry
                end
            end
        end
    else
        for _, rowData in ipairs(rows) do
            local charName, realmName = rowData.charKey:match("^(.-)%-(.+)$")
            if not charName then
                charName = rowData.charKey
                realmName = "Unknown"
            end
            local snap = db and db.preySnapshots and db.preySnapshots[rowData.charKey] or nil
            displayRows[#displayRows + 1] = {
                type = "character",
                realm = realmName,
                charName = charName,
                charKey = rowData.charKey,
                snaps = rowData.snaps,
                preyTriplet = (settings and settings.currencyWarbandShowPreyTrack ~= false and snap) and BuildPreyProgressTriplet(snap, (settings and settings.currencyWarbandPreyMode) or "available") or "",
            }
        end
    end

    for index, rowData in ipairs(warbandWindowRows) do
        local data = displayRows[index]
        if not data then
            rowData.frame:Hide()
        else
            rowData.frame:Show()
            if rowData.frame.bg then
                local rowColor = (index % 2 == 0) and theme.rowAlt or theme.row
                rowData.frame.bg:SetColorTexture(rowColor[1], rowColor[2], rowColor[3], rowColor[4] or 0.92)
            end

            if data.type == "realm" then
                local collapsed = data.collapsed == true
                local prefix = collapsed and "+ " or "- "
                rowData.cells.realm:SetText(prefix .. data.realm)
                rowData.cells.character:SetText(L["Subtotal"])
                rowData.cells.prey:SetText("")
                rowData.cells[3392]:SetText(tostring(data.totals[3392] or 0))
                rowData.cells[3316]:SetText(tostring(data.totals[3316] or 0))
                rowData.cells[3383]:SetText(tostring(data.totals[3383] or 0))
                rowData.cells[3341]:SetText(tostring(data.totals[3341] or 0))
                rowData.cells[3343]:SetText(tostring(data.totals[3343] or 0))
                SetTextColor(rowData.cells.realm, theme.title)
                SetTextColor(rowData.cells.character, theme.muted)
                SetTextColor(rowData.cells.prey, theme.muted)
                SetTextColor(rowData.cells[3392], theme.title)
                SetTextColor(rowData.cells[3316], theme.title)
                SetTextColor(rowData.cells[3383], theme.title)
                SetTextColor(rowData.cells[3341], theme.title)
                SetTextColor(rowData.cells[3343], theme.title)
                rowData.frame:SetScript("OnClick", function()
                    local collapsedRealms = settings.currencyWarbandCollapsedRealms
                    collapsedRealms[data.realm] = not (collapsedRealms[data.realm] == true)
                    CurrencyTrackerModule:RefreshCurrencyPage()
                end)
            else
                rowData.cells.realm:SetText("")  -- realm column blank on character rows; grouping is visual
                rowData.cells.character:SetText(data.charName)
                rowData.cells.prey:SetText(data.preyTriplet or "")
                rowData.cells[3392]:SetText(tostring((data.snaps[3392] and data.snaps[3392].quantity) or 0))
                rowData.cells[3316]:SetText(tostring((data.snaps[3316] and data.snaps[3316].quantity) or 0))
                rowData.cells[3383]:SetText(tostring((data.snaps[3383] and data.snaps[3383].quantity) or 0))
                rowData.cells[3341]:SetText(tostring((data.snaps[3341] and data.snaps[3341].quantity) or 0))
                rowData.cells[3343]:SetText(tostring((data.snaps[3343] and data.snaps[3343].quantity) or 0))

                SetTextColor(rowData.cells.realm, theme.muted)
                local classFile = data.snaps[3392] and data.snaps[3392].classFile
                local classColor = classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
                if classColor then
                    rowData.cells.character:SetTextColor(classColor.r, classColor.g, classColor.b, 1)
                else
                    SetTextColor(rowData.cells.character, theme.text)
                end
                SetTextColor(rowData.cells.prey, theme.muted)
                SetTextColor(rowData.cells[3392], theme.text)
                SetTextColor(rowData.cells[3316], theme.text)
                SetTextColor(rowData.cells[3383], theme.text)
                SetTextColor(rowData.cells[3341], theme.text)
                SetTextColor(rowData.cells[3343], theme.text)
                rowData.frame:SetScript("OnClick", nil)
            end
        end
    end

    if warbandTotalTexts.realm then
        warbandTotalTexts.realm:SetText(L["All Realms"])
        SetTextColor(warbandTotalTexts.realm, theme.muted)
    end
    if warbandTotalTexts.character then
        warbandTotalTexts.character:SetText(L["Totals"])
        SetTextColor(warbandTotalTexts.character, theme.muted)
    end
    if warbandTotalTexts.prey then
        warbandTotalTexts.prey:SetText("")
        SetTextColor(warbandTotalTexts.prey, theme.muted)
    end
    if warbandTotalTexts[3392] then
        warbandTotalTexts[3392]:SetText(tostring((db and db.warbandTotal and db.warbandTotal[3392]) or 0))
        SetTextColor(warbandTotalTexts[3392], theme.title)
    end
    if warbandTotalTexts[3316] then
        warbandTotalTexts[3316]:SetText(tostring((db and db.warbandTotal and db.warbandTotal[3316]) or 0))
        SetTextColor(warbandTotalTexts[3316], theme.title)
    end
    if warbandTotalTexts[3383] then
        warbandTotalTexts[3383]:SetText(tostring((db and db.warbandTotal and db.warbandTotal[3383]) or 0))
        SetTextColor(warbandTotalTexts[3383], theme.title)
    end
    if warbandTotalTexts[3341] then
        warbandTotalTexts[3341]:SetText(tostring((db and db.warbandTotal and db.warbandTotal[3341]) or 0))
        SetTextColor(warbandTotalTexts[3341], theme.title)
    end
    if warbandTotalTexts[3343] then
        warbandTotalTexts[3343]:SetText(tostring((db and db.warbandTotal and db.warbandTotal[3343]) or 0))
        SetTextColor(warbandTotalTexts[3343], theme.title)
    end

    for key, text in pairs(warbandHeaderTexts) do
        if key == warbandSortKey then
            SetTextColor(text, theme.title)
        else
            SetTextColor(text, theme.muted)
        end
    end
end

local function RefreshCurrencyWindowDisplay()
    if not currencyWindow then
        return
    end

    local settings = GetSettings()
    local theme = GetThemePreset()
    local showAffordableHunts = (not settings) or (settings.currencyShowAffordableHunts ~= false)
    local gainColor = (settings and settings.currencyDeltaGainColor) or COLOR_GREEN
    local lossColor = (settings and settings.currencyDeltaLossColor) or COLOR_RED
    local seasonColor = theme.season or COLOR_SEASON
    local configuredWidth, configuredHeight, configuredFontSize, configuredScale = GetCurrencyWindowConfig()
    local tracked = GetTrackedCurrencyEntries()

    local topPad = 34
    local summaryHeight = showAffordableHunts and 24 or 0
    local rowTopGap = 8
    local rowSpacing = 30
    local bottomPad = 14
    local rowsHeight = #tracked * rowSpacing
    local requiredHeight = topPad + summaryHeight + rowTopGap + rowsHeight + bottomPad
    local finalHeight = (requiredHeight > configuredHeight) and requiredHeight or configuredHeight

    currencyWindow:SetSize(configuredWidth, finalHeight)
    currencyWindow:SetScale(configuredScale)

    if currencyWindow.PreydatorBg then
        currencyWindow.PreydatorBg:SetColorTexture(theme.section[1], theme.section[2], theme.section[3], 0.88)
    end
    if currencyWindow.PreydatorTopBar then
        currencyWindow.PreydatorTopBar:SetColorTexture(theme.header[1], theme.header[2], theme.header[3], 0.95)
    end
    if currencyWindow.SetBackdropBorderColor then
        currencyWindow:SetBackdropBorderColor(theme.border[1], theme.border[2], theme.border[3], theme.border[4] or 1)
    end
    if currencyWindow.PreydatorTitle then
        SetTextColor(currencyWindow.PreydatorTitle, theme.title)
    end

    if currencyWindowSummary then
        currencyWindowSummary:SetShown(showAffordableHunts)
        currencyWindowSummary:SetWidth(configuredWidth - 28)
        SetTextColor(currencyWindowSummary, theme.muted)
        SetFontSize(currencyWindowSummary, math.max(10, configuredFontSize - 2))
    end

    local rowStartY = showAffordableHunts and -68 or -40
    for index, row in ipairs(currencyWindowRows) do
        local entry = tracked[index]
        if entry then
            row:Show()
            row:SetSize(configuredWidth - 28, TRACKER_ROW_HEIGHT)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", currencyWindow, "TOPLEFT", 12, rowStartY - ((index - 1) * 30))
            if row.bg then
                local rowColor = (index % 2 == 0) and theme.rowAlt or theme.row
                row.bg:SetColorTexture(rowColor[1], rowColor[2], rowColor[3], rowColor[4] or 0.92)
            end
            row.nameText:SetText(entry.label)
            SetTextColor(row.nameText, entry.season and seasonColor or theme.text)
            SetFontSize(row.nameText, configuredFontSize)

            local iconID = GetCurrencyIcon(entry.id)
            if iconID and iconID > 0 then
                row.icon:SetTexture(iconID)
            else
                row.icon:SetColorTexture(0.35, 0.35, 0.4, 0.8)
            end

            local qty = GetCurrencyQuantity(entry.id)
            row.qtyText:SetText(tostring(qty))
            SetTextColor(row.qtyText, qty > 0 and theme.text or theme.muted)
            SetFontSize(row.qtyText, configuredFontSize)

            local delta = SessionDelta(entry.id)
            if delta > 0 then
                row.deltaText:SetText("+" .. tostring(delta))
                SetTextColor(row.deltaText, gainColor)
                SetFontSize(row.deltaText, math.max(10, configuredFontSize - 2))
                row.deltaText:Show()
            elseif delta < 0 then
                row.deltaText:SetText(tostring(delta))
                SetTextColor(row.deltaText, lossColor)
                SetFontSize(row.deltaText, math.max(10, configuredFontSize - 2))
                row.deltaText:Show()
            else
                row.deltaText:SetText("")
                row.deltaText:Hide()
            end
        else
            row:Hide()
        end
    end

    local anguish = GetCurrencyQuantity(3392)
    local costs = settings and settings.randomHuntCosts or {}
    local normalCost = tonumber(costs.normal) or 50
    local hardCost = tonumber(costs.hard) or 50
    local nightmareCost = tonumber(costs.nightmare) or 0

    local normalCount = normalCost > 0 and math.floor(anguish / normalCost) or 0
    local hardCount = hardCost > 0 and math.floor(anguish / hardCost) or 0
    local nightmareText
    if nightmareCost > 0 then
        nightmareText = tostring(math.floor(anguish / nightmareCost))
    else
        nightmareText = "?"
    end

    if currencyWindowSummary and showAffordableHunts then
        currencyWindowSummary:SetText(string.format(L["Normal %d | Hard %d | Nightmare %s"], normalCount, hardCount, nightmareText))
        SetTextColor(currencyWindowSummary, theme.muted)
    end

    if currencyWindow.PreydatorTitle then
        SetFontSize(currencyWindow.PreydatorTitle, configuredFontSize)
    end
end

local function BuildCurrencyConfigPage(parent)
    local settings = GetSettings()
    if not settings then
        return
    end

    local title = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", parent, "TOPLEFT", 18, -12)
    title:SetText(L["Currency Tracker"])


    local controls = {}
    local function add(control)
        controls[#controls + 1] = control
        return control
    end

    -- Window toggles and quick theme controls (left column)
    local openButton = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    openButton:SetSize(120, 22)
    openButton:SetPoint("TOPLEFT", parent, "TOPLEFT", 18, -36)
    openButton:SetText(L["Toggle Tracker"])
    openButton:SetScript("OnClick", function()
        ToggleCurrencyWindow()
        CurrencyTrackerModule:RefreshCurrencyPage()
    end)

    local themeLabel = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    themeLabel:SetPoint("TOPLEFT", parent, "TOPLEFT", 18, -64)
    themeLabel:SetText(L["Currency Theme"])

    local themeDropdown = CreateFrame("Frame", nil, parent, "UIDropDownMenuTemplate")
    themeDropdown:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -78)
    _G.UIDropDownMenu_SetWidth(themeDropdown, 150)
    _G.UIDropDownMenu_JustifyText(themeDropdown, "LEFT")

    local function ThemeLabelForKey(key)
        if key == "light" then
            return L["Light"]
        end
        if key == "dark" then
            return L["Dark"]
        end
        return L["Brown"]
    end

    _G.UIDropDownMenu_Initialize(themeDropdown, function(self, level)
        for _, key in ipairs({ "light", "brown", "dark" }) do
            local info = _G.UIDropDownMenu_CreateInfo()
            info.text = ThemeLabelForKey(key)
            info.checked = (settings.currencyTheme or "brown") == key
            info.func = function()
                settings.currencyTheme = key
                CurrencyTrackerModule:RefreshCurrencyPage()
            end
            _G.UIDropDownMenu_AddButton(info, level)
        end
    end)

    local minimapToggle = add(CreateFrame("CheckButton", nil, parent, "InterfaceOptionsCheckButtonTemplate"))
    minimapToggle:SetPoint("TOPLEFT", parent, "TOPLEFT", 18, -108)
    minimapToggle.Text:SetText(L["Disable Minimap Button"])
    minimapToggle:SetScript("OnClick", function(self)
        CurrencyTrackerModule:SetMinimapButtonEnabled(not (self:GetChecked() and true or false))
    end)

    local affordableToggle = add(CreateFrame("CheckButton", nil, parent, "InterfaceOptionsCheckButtonTemplate"))
    affordableToggle:SetPoint("TOPLEFT", parent, "TOPLEFT", 18, -136)
    affordableToggle.Text:SetText(L["Show Affordable Hunts In Tracker"])
    affordableToggle:SetScript("OnClick", function(self)
        settings.currencyShowAffordableHunts = self:GetChecked() and true or false
        CurrencyTrackerModule:RefreshCurrencyPage()
    end)

    local trackedTitle = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    trackedTitle:SetPoint("TOPLEFT", parent, "TOPLEFT", 18, -192)
    trackedTitle:SetText(L["Currencies to Track"])
    SetTextColor(trackedTitle, COLOR_GOLD)

    local y = -218
    for _, entry in ipairs(CURRENCY_ALLOW_LIST) do
        local check = add(CreateFrame("CheckButton", nil, parent, "InterfaceOptionsCheckButtonTemplate"))
        check:SetPoint("TOPLEFT", parent, "TOPLEFT", 18, y)
        local info = C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo and C_CurrencyInfo.GetCurrencyInfo(entry.id)
        check.Text:SetText((info and info.name) or entry.name)
        check:SetScript("OnClick", function(self)
            settings.currencyTrackedIDs[entry.id] = self:GetChecked() and true or false
            CurrencyTrackerModule:RefreshCurrencyPage()
        end)
        check.currencyID = entry.id
        y = y - 26
    end

    local costsTitle = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    costsTitle:SetPoint("TOPLEFT", parent, "TOPLEFT", 260, -36)
    costsTitle:SetText(L["Random Hunt Cost (Anguish)"])
    SetTextColor(costsTitle, COLOR_GOLD)

    local function CreateCostInput(label, key, yOffset)
        local text = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        text:SetPoint("TOPLEFT", parent, "TOPLEFT", 260, yOffset)
        text:SetText(label)

        local box = add(CreateFrame("EditBox", nil, parent, "InputBoxTemplate"))
        box:SetSize(80, 20)
        box:SetPoint("LEFT", text, "RIGHT", 8, 0)
        box:SetAutoFocus(false)
        box:SetTextInsets(6, 6, 0, 0)
        box:SetJustifyH("CENTER")
        box.costKey = key

        local function commit()
            local value = tonumber(box:GetText())
            if not value then
                value = tonumber(settings.randomHuntCosts[key]) or 0
            end
            value = math.max(0, math.floor(value + 0.5))
            settings.randomHuntCosts[key] = value
            box:SetText(tostring(value))
            CurrencyTrackerModule:RefreshCurrencyPage()
        end

        box:SetScript("OnEnterPressed", function(self)
            commit()
            self:ClearFocus()
        end)
        box:SetScript("OnEditFocusLost", function()
            commit()
        end)

        return box
    end

    local normalBox = CreateCostInput(L["Normal"], "normal", -64)
    local hardBox = CreateCostInput(L["Hard"], "hard", -92)
    local nightmareBox = CreateCostInput(L["Nightmare"], "nightmare", -120)

    local layoutTitle = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    layoutTitle:SetPoint("TOPLEFT", parent, "TOPLEFT", 260, -201)
    layoutTitle:SetText(L["Panel Layout"])
    SetTextColor(layoutTitle, COLOR_GOLD)

    local widthSlider
    local heightSlider
    local scaleSlider
    local fontSlider
    local isLayoutRefreshing = false
    local layoutSpec = {
        width = { key = "currencyWindowWidth", min = TRACKER_MIN_WIDTH, max = TRACKER_MAX_WIDTH, step = 4, isFloat = false },
        height = { key = "currencyWindowHeight", min = TRACKER_MIN_HEIGHT, max = TRACKER_MAX_HEIGHT, step = 4, isFloat = false },
        scale = { key = "currencyWindowScale", min = TRACKER_MIN_SCALE, max = TRACKER_MAX_SCALE, step = 0.01, isFloat = true, decimals = 2 },
        font = { key = "currencyWindowFontSize", min = TRACKER_MIN_FONT, max = TRACKER_MAX_FONT, step = 1, isFloat = false },
    }

    local function NormalizeSliderValue(raw, field)
        local numeric = tonumber(raw)
        if not numeric then
            return nil
        end

        local stepped = field.min + (math.floor(((numeric - field.min) / field.step) + 0.5) * field.step)
        if field.isFloat then
            return ClampFloat(stepped, field.min, field.max, field.min, field.decimals or 2)
        end
        return ClampNumber(stepped, field.min, field.max, field.min)
    end

    local function FormatFieldValue(field, value)
        if field.isFloat then
            return string.format("%.2f", value)
        end
        return tostring(math.floor(value + 0.5))
    end

    local function CreateLayoutSlider(yOffset, label)
        local text = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        text:SetPoint("TOPLEFT", parent, "TOPLEFT", 260, yOffset)
        text:SetText(label)

        local slider = CreateFrame("Slider", nil, parent, "OptionsSliderTemplate")
        slider:SetWidth(170)
        slider:SetPoint("TOPLEFT", parent, "TOPLEFT", 260, yOffset - 18)
        slider:SetObeyStepOnDrag(true)
        if slider.Low then slider.Low:Hide() end
        if slider.High then slider.High:Hide() end

        local valueBox = add(CreateFrame("EditBox", nil, parent, "InputBoxTemplate"))
        valueBox:SetSize(56, 20)
        valueBox:SetPoint("LEFT", slider, "RIGHT", 12, 0)
        valueBox:SetAutoFocus(false)
        valueBox:SetTextInsets(6, 6, 0, 0)
        valueBox:SetJustifyH("CENTER")

        slider.PreydatorValueBox = valueBox
        return slider
    end

    widthSlider = CreateLayoutSlider(-236, L["Width"])
    heightSlider = CreateLayoutSlider(-282, L["Height"])
    scaleSlider = CreateLayoutSlider(-328, L["Scale"])
    fontSlider = CreateLayoutSlider(-374, L["Font Size"])

    local function ApplySliderValue(slider, rawValue)
        local field = slider.PreydatorField
        if not field then
            return
        end

        local normalized = NormalizeSliderValue(rawValue, field)
        if normalized == nil then
            normalized = settings[field.key]
        end
        if normalized == nil then
            normalized = field.min
        end

        settings[field.key] = normalized
        slider.PreydatorValueBox:SetText(FormatFieldValue(field, normalized))
        CurrencyTrackerModule:RefreshCurrencyPage()
    end

    for _, slider in ipairs({ widthSlider, heightSlider, scaleSlider, fontSlider }) do
        slider:SetScript("OnValueChanged", function(self, value)
            if isLayoutRefreshing then
                return
            end
            ApplySliderValue(self, value)
        end)

        slider.PreydatorValueBox:SetScript("OnEnterPressed", function(self)
            ApplySliderValue(slider, self:GetText())
            self:ClearFocus()
        end)

        slider.PreydatorValueBox:SetScript("OnEditFocusLost", function(self)
            local field = slider.PreydatorField
            if not field then
                return
            end
            local current = settings[field.key]
            if current == nil then
                current = field.min
            end
            self:SetText(FormatFieldValue(field, current))
        end)
    end

    local function RefreshLayoutControls()
        if isLayoutRefreshing then
            return
        end

        isLayoutRefreshing = true
        local map = {
            { slider = widthSlider, field = layoutSpec.width },
            { slider = heightSlider, field = layoutSpec.height },
            { slider = scaleSlider, field = layoutSpec.scale },
            { slider = fontSlider, field = layoutSpec.font },
        }

        for _, entry in ipairs(map) do
            local slider = entry.slider
            local field = entry.field
            slider.PreydatorField = field
            slider:SetMinMaxValues(field.min, field.max)
            slider:SetValueStep(field.step)

            local value = settings[field.key]
            if value == nil then
                value = field.min
            end
            value = NormalizeSliderValue(value, field) or field.min

            slider:SetValue(value)
            slider.PreydatorValueBox:SetText(FormatFieldValue(field, value))
        end
        isLayoutRefreshing = false
    end

    local gainColorButton = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    gainColorButton:SetSize(120, 22)
    gainColorButton:SetPoint("TOPLEFT", parent, "TOPLEFT", 260, -145)
    gainColorButton:SetText(L["Gain Color"])
    gainColorButton:SetScript("OnClick", function()
        OpenColorPicker(settings.currencyDeltaGainColor, function(color)
            settings.currencyDeltaGainColor = { color[1], color[2], color[3], color[4] or 1 }
            CurrencyTrackerModule:RefreshCurrencyPage()
        end)
    end)

    local gainSwatch = parent:CreateTexture(nil, "ARTWORK")
    gainSwatch:SetSize(16, 16)
    gainSwatch:SetPoint("LEFT", gainColorButton, "RIGHT", 8, 0)

    local lossColorButton = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    lossColorButton:SetSize(120, 22)
    lossColorButton:SetPoint("TOPLEFT", parent, "TOPLEFT", 260, -173)
    lossColorButton:SetText(L["Spend Color"])
    lossColorButton:SetScript("OnClick", function()
        OpenColorPicker(settings.currencyDeltaLossColor, function(color)
            settings.currencyDeltaLossColor = { color[1], color[2], color[3], color[4] or 1 }
            CurrencyTrackerModule:RefreshCurrencyPage()
        end)
    end)

    local lossSwatch = parent:CreateTexture(nil, "ARTWORK")
    lossSwatch:SetSize(16, 16)
    lossSwatch:SetPoint("LEFT", lossColorButton, "RIGHT", 8, 0)

    local function CreatePreviewBox(x, y)
        local box = CreateFrame("Frame", nil, parent, "BackdropTemplate")
        box:SetSize(42, 62)
        box:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
        box:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 8,
            insets = { left = 2, right = 2, top = 2, bottom = 2 },
        })
        box:SetBackdropBorderColor(0, 0, 0, 0.85)

        local gainText = box:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        gainText:SetPoint("TOP", box, "TOP", 0, -14)
        gainText:SetText("+123")

        local lossText = box:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        lossText:SetPoint("TOP", box, "TOP", 0, -40)
        lossText:SetText("-45")

        return {
            frame = box,
            gainText = gainText,
            lossText = lossText,
        }
    end

    local previewTitle = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    previewTitle:SetPoint("TOPLEFT", parent, "TOPLEFT", 426, -114)
    previewTitle:SetText(L["Delta Preview"])

    local previewBoxes = {
        CreatePreviewBox(426, -132),
        CreatePreviewBox(472, -132),
        CreatePreviewBox(518, -132),
    }

    function parent:PreydatorCurrencyRefresh()
        minimapToggle:SetChecked(settings.currencyMinimapButton == false)
        affordableToggle:SetChecked(settings.currencyShowAffordableHunts ~= false)

        for _, control in ipairs(controls) do
            if control.currencyID then
                control:SetChecked(settings.currencyTrackedIDs[control.currencyID] ~= false)
            end
        end

        normalBox:SetText(tostring(settings.randomHuntCosts.normal or 50))
        hardBox:SetText(tostring(settings.randomHuntCosts.hard or 50))
        nightmareBox:SetText(tostring(settings.randomHuntCosts.nightmare or 0))
        _G.UIDropDownMenu_SetText(themeDropdown, ThemeLabelForKey(settings.currencyTheme or "brown"))
        RefreshLayoutControls()

        openButton:SetText((settings.currencyWindowEnabled ~= false) and L["Close Tracker"] or L["Open Tracker"])

        local gain = settings.currencyDeltaGainColor or COLOR_GREEN
        local loss = settings.currencyDeltaLossColor or COLOR_RED
        local theme = GetThemePreset()
        gainSwatch:SetColorTexture(gain[1], gain[2], gain[3], 1)
        lossSwatch:SetColorTexture(loss[1], loss[2], loss[3], 1)
        SetTextColor(previewTitle, theme.title)

        local surfaces = {
            theme.section,
            theme.row,
            theme.rowAlt,
        }
        for i, box in ipairs(previewBoxes) do
            local surface = surfaces[i] or theme.row
            box.frame:SetBackdropColor(surface[1], surface[2], surface[3], surface[4] or 0.92)
            SetTextColor(box.gainText, gain)
            SetTextColor(box.lossText, loss)
        end
    end

    parent:PreydatorCurrencyRefresh()
end

function CurrencyTrackerModule:BuildCurrencyPage(owner, parent)
    currencyPanelPage = parent
    BuildCurrencyConfigPage(parent)
end

function CurrencyTrackerModule:RefreshCurrencyPage()
    SnapshotCurrentCharacter()
    SnapshotCurrentPreyCharacter()
    UpdateLastKnownQuantities()
    RefreshCurrencyWindowDisplay()
    RefreshWarbandWindowDisplay()
    if currencyPanelPage and currencyPanelPage:IsVisible() and type(currencyPanelPage.PreydatorCurrencyRefresh) == "function" then
        currencyPanelPage:PreydatorCurrencyRefresh()
    end
end

function CurrencyTrackerModule:RefreshIfChanged(force, source)
    local changedEntries = UpdateLastKnownQuantities()
    local hasDelta = #changedEntries > 0

    if force or hasDelta then
        self:RefreshCurrencyPage()
    end

    if force or hasDelta then
        if hasDelta then
            local parts = {}
            for _, entry in ipairs(changedEntries) do
                parts[#parts + 1] = entry.label .. "(" .. tostring(entry.id) .. "): " .. tostring(entry.old) .. " -> " .. tostring(entry.new)
            end
            LogCurrencyDebug(tostring(source or "unknown") .. " | " .. table.concat(parts, ", "))
        else
            LogCurrencyDebug(tostring(source or "unknown") .. " | forced refresh, no allow-list delta")
        end
    end
end

function CurrencyTrackerModule:QueueRefreshSweep(source)
    -- Immediate pass for fast event paths.
    self:RefreshCurrencyPage()
    LogCurrencyDebug(tostring(source or "unknown") .. " | immediate sweep")

    if not C_Timer or type(C_Timer.After) ~= "function" then
        return
    end

    -- Delayed passes catch server-delayed currency updates that land after the event tick.
    C_Timer.After(0.2, function()
        CurrencyTrackerModule:RefreshIfChanged(false, tostring(source or "unknown") .. "+200ms")
    end)
    C_Timer.After(1.0, function()
        CurrencyTrackerModule:RefreshIfChanged(false, tostring(source or "unknown") .. "+1000ms")
    end)
end

-- Live refresh via CURRENCY_DISPLAY_UPDATE
--------------------------------------------------------------------------------

local eventFrame = CreateFrame("Frame")

eventFrame:SetScript("OnEvent", function(_, event, ...)
    if event == "CURRENCY_DISPLAY_UPDATE" then
        local currencyID = ...
        if type(currencyID) == "number" and ALLOW_LIST_IDS[currencyID] then
            CurrencyTrackerModule:QueueRefreshSweep("CURRENCY_DISPLAY_UPDATE(" .. tostring(currencyID) .. ")")
            return
        end
        CurrencyTrackerModule:QueueRefreshSweep("CURRENCY_DISPLAY_UPDATE")
        return
    end

    if event == "QUEST_TURNED_IN" then
        local questID = ...
        RecordPreyTurnIn(questID)
    end

    if event == "CHAT_MSG_CURRENCY" or event == "CHAT_MSG_LOOT" or event == "QUEST_TURNED_IN" or event == "BAG_UPDATE_DELAYED" or event == "PLAYER_ENTERING_WORLD" then
        CurrencyTrackerModule:QueueRefreshSweep(event)
    end
end)

eventFrame:SetScript("OnUpdate", function(_, elapsed)
    local currencyVisible = currencyWindow and currencyWindow:IsVisible()
    local warbandVisible = warbandWindow and warbandWindow:IsVisible()
    if not currencyVisible and not warbandVisible then
        pollElapsed = 0
        return
    end

    pollElapsed = pollElapsed + (elapsed or 0)
    if pollElapsed < POLL_INTERVAL_SECONDS then
        return
    end

    pollElapsed = 0
    CurrencyTrackerModule:RefreshCurrencyPage()
    LogCurrencyDebug("OnUpdatePoll | visible window sweep")
end)

--------------------------------------------------------------------------------
-- Module lifecycle hooks
--------------------------------------------------------------------------------

function CurrencyTrackerModule:OnAddonLoaded()
    EnsureDB()
    EnsureTrackerSettings()
    eventFrame:RegisterEvent("CURRENCY_DISPLAY_UPDATE")
    eventFrame:RegisterEvent("CHAT_MSG_CURRENCY")
    eventFrame:RegisterEvent("CHAT_MSG_LOOT")
    eventFrame:RegisterEvent("QUEST_TURNED_IN")
    eventFrame:RegisterEvent("BAG_UPDATE_DELAYED")
    eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    sessionStart = {}
    sessionBaselineReady = false
    UpdateLastKnownQuantities()
    SnapshotCurrentPreyCharacter()
end

function CurrencyTrackerModule:OnEvent(event, ...)
    if event == "PLAYER_LOGIN" then
        EnsureDB()
        EnsureTrackerSettings()
        sessionStart = {}
        sessionBaselineReady = false
        PrimeSessionBaseline("PLAYER_LOGIN")
        SnapshotCurrentCharacter()
        UpdateLastKnownQuantities()
        EnsureCurrencyWindow()
        EnsureWarbandWindow()
        EnsureMinimapButton()
        UpdateVisibilityFromSettings()
        UpdateWindowPosition()
        UpdateWarbandWindowPosition()
        UpdateMinimapButtonPosition()
        self:RefreshCurrencyPage()

        if C_Timer and type(C_Timer.After) == "function" then
            C_Timer.After(0.5, function()
                if PrimeSessionBaseline("PLAYER_LOGIN+0.5s") then
                    CurrencyTrackerModule:RefreshCurrencyPage()
                end
            end)
            C_Timer.After(1.5, function()
                if PrimeSessionBaseline("PLAYER_LOGIN+1.5s") then
                    CurrencyTrackerModule:RefreshCurrencyPage()
                end
            end)
            C_Timer.After(3.0, function()
                if PrimeSessionBaseline("PLAYER_LOGIN+3.0s") then
                    CurrencyTrackerModule:RefreshCurrencyPage()
                end
            end)
        end

        ShowCurrencyWhatsNewIfNeeded()
        return
    end

    if event == "QUEST_LOG_UPDATE"
        or event == "UPDATE_ALL_UI_WIDGETS"
        or event == "UPDATE_UI_WIDGET"
        or event == "ZONE_CHANGED"
        or event == "ZONE_CHANGED_INDOORS"
        or event == "ZONE_CHANGED_NEW_AREA"
        or event == "PLAYER_ENTERING_WORLD"
    then
        SnapshotCurrentPreyCharacter()
        if currencyPanelPage and currencyPanelPage:IsVisible() then
            self:RefreshCurrencyPage()
        end
    end
end
