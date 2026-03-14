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
local CURRENCY_WHATS_NEW_VERSION = "1.6.0"
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
local currencyPanelPage = nil  -- the Tab content frame, built lazily
local lastKnownQuantity = {}   -- [currencyID] = quantity
local pollElapsed = 0
local ldbLauncher
local ldbIconRegistered = false
local warbandSortKey = "character"
local warbandSortAsc = true
local currencyWhatsNewFrame

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
    db = c
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
        if not sessionStart[entry.id] then
            sessionStart[entry.id] = qty
        end
        db.snapshots[key][entry.id] = { quantity = qty, lastSeen = GetTime(), classFile = classFile }
    end
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

    for _, entry in ipairs(CURRENCY_ALLOW_LIST) do
        if settings.currencyTrackedIDs[entry.id] == nil then
            settings.currencyTrackedIDs[entry.id] = true
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
    title:SetText("Preydator Currency: New in 1.6.0")
    SetTextColor(title, COLOR_GOLD)

    local body = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    body:SetPoint("TOPLEFT", frame, "TOPLEFT", 18, -52)
    body:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -18, -52)
    body:SetJustifyH("LEFT")
    body:SetJustifyV("TOP")
    body:SetText(
        "Currency tracking has arrived.\n\n"
        .. "- Currency and Warband windows now support tracked-currency filtering\n"
        .. "- Theme controls include Light, Brown, and Dark\n"
        .. "- Layout controls for width, height, scale, and font are in Options\n"
        .. "- Warband table auto-fits tracked columns and grouped realm rows\n\n"
        .. "Both windows default to OFF for new installs. Enable them anytime from the Currencies options page or minimap icon."
    )

    local closeButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    closeButton:SetSize(120, 24)
    closeButton:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -18, 16)
    closeButton:SetText("Got It")

    local settingsButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    settingsButton:SetSize(140, 24)
    settingsButton:SetPoint("RIGHT", closeButton, "LEFT", -8, 0)
    settingsButton:SetText("Open Settings")

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
    local radians = math.rad(angle)
    local radius = 80
    local x = math.cos(radians) * radius
    local y = math.sin(radians) * radius

    minimapButton:ClearAllPoints()
    minimapButton:SetPoint("CENTER", _G.Minimap, "CENTER", x, y)
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

local function EnsureCurrencyWindow()
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
    title:SetText("Preydator Currency")
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

local function EnsureWarbandWindow()
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
    title:SetText("Preydator Warband")
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
        { key = "realm", label = "Realm", width = 96 },
        { key = "character", label = "Character", width = 112 },
        { key = 3392, label = "Anguish", width = 56 },
        { key = 3316, label = "Voidlight", width = 64 },
        { key = 3383, label = "Adv", width = 48 },
        { key = 3341, label = "Vet", width = 48 },
        { key = 3343, label = "Champ", width = 56 },
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
        totalText:SetText(headerData.key == "character" and "Total" or "0")
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
        if IsCurrencyTracked(settings, currencyID) then
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
    local charWidth = 140
    local currencyDefaults = {
        [3392] = 56,
        [3316] = 64,
        [3383] = 48,
        [3341] = 48,
        [3343] = 56,
    }

    local requiredTableWidth = charWidth + realmWidth
    for _, currencyID in ipairs(trackedCurrencyIDs) do
        requiredTableWidth = requiredTableWidth + (currencyDefaults[currencyID] or 48)
    end
    local requiredWindowWidth = math.max(WARBAND_MIN_WIDTH, requiredTableWidth + 24)
    local finalWindowWidth = math.max(windowWidth, requiredWindowWidth)

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

    local charSlack = tableWidth - realmWidth - currencyWidth - charWidth
    if charSlack > 0 then
        charWidth = charWidth + charSlack
    end

    local currencyWidths = {}
    for _, currencyID in ipairs(orderedCurrencyIDs) do
        if IsCurrencyTracked(settings, currencyID) then
            currencyWidths[currencyID] = currencyDefaults[currencyID] or 48
        else
            currencyWidths[currencyID] = 0
        end
    end

    local effectiveWidths = {
        ["realm"] = realmWidth,
        ["character"] = charWidth,
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
            tooltip:AddLine("Left Click: Toggle Currency Window", 1, 1, 1)
            tooltip:AddLine("Right Click: Toggle Warband Window", 1, 1, 1)
            tooltip:AddLine("Shift + Right Click: Open Options", 1, 1, 1)
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
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:RegisterForDrag("LeftButton")

    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetTexture(MINIMAP_ICON_PATH)
    icon:SetAllPoints()
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    local border = button:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetAllPoints()

    button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    button:SetScript("OnClick", function(_, mouseButton)
        HandleMinimapClick(mouseButton)
    end)

    button:SetScript("OnDragStart", function(self)
        self.dragging = true
        self:SetScript("OnUpdate", function(s)
            local mx, my = GetCursorPosition()
            local scale = _G.UIParent:GetEffectiveScale()
            mx, my = mx / scale, my / scale
            local cx, cy = _G.Minimap:GetCenter()
            local angle = math.deg(math.atan(my - cy, mx - cx))
            local settings = GetSettings()
            if settings then
                if type(settings.currencyMinimap) ~= "table" then
                    settings.currencyMinimap = {}
                end
                settings.currencyMinimap.minimapPos = angle
                settings.currencyMinimapAngle = angle
            end
            UpdateMinimapButtonPosition()
        end)
    end)

    button:SetScript("OnDragStop", function(self)
        self.dragging = nil
        self:SetScript("OnUpdate", nil)
    end)

    minimapButton = button
    UpdateMinimapButtonPosition()
    return button
end

local function RefreshWarbandWindowDisplay()
    if not warbandWindow then
        return
    end

    local settings = GetSettings()
    local theme = GetThemePreset()
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
            displayRows[#displayRows + 1] = {
                type = "character",
                realm = realmName,
                charName = charName,
                charKey = rowData.charKey,
                snaps = rowData.snaps,
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
                rowData.cells.character:SetText("Subtotal")
                rowData.cells[3392]:SetText(tostring(data.totals[3392] or 0))
                rowData.cells[3316]:SetText(tostring(data.totals[3316] or 0))
                rowData.cells[3383]:SetText(tostring(data.totals[3383] or 0))
                rowData.cells[3341]:SetText(tostring(data.totals[3341] or 0))
                rowData.cells[3343]:SetText(tostring(data.totals[3343] or 0))
                SetTextColor(rowData.cells.realm, theme.title)
                SetTextColor(rowData.cells.character, theme.muted)
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
        warbandTotalTexts.realm:SetText("All Realms")
        SetTextColor(warbandTotalTexts.realm, theme.muted)
    end
    if warbandTotalTexts.character then
        warbandTotalTexts.character:SetText("Totals")
        SetTextColor(warbandTotalTexts.character, theme.muted)
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
        currencyWindowSummary:SetText("Normal " .. tostring(normalCount) .. " | Hard " .. tostring(hardCount) .. " | Nightmare " .. nightmareText)
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
    title:SetText("Currency Tracker")


    local controls = {}
    local function add(control)
        controls[#controls + 1] = control
        return control
    end

    -- Window toggles and quick theme controls (left column)
    local openButton = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    openButton:SetSize(120, 22)
    openButton:SetPoint("TOPLEFT", parent, "TOPLEFT", 18, -36)
    openButton:SetText("Toggle Tracker")
    openButton:SetScript("OnClick", function()
        ToggleCurrencyWindow()
        CurrencyTrackerModule:RefreshCurrencyPage()
    end)

    local openWarbandButton = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    openWarbandButton:SetSize(120, 22)
    openWarbandButton:SetPoint("TOPLEFT", parent, "TOPLEFT", 18, -64)
    openWarbandButton:SetText("Toggle Warband")
    openWarbandButton:SetScript("OnClick", function()
        ToggleWarbandWindow()
        CurrencyTrackerModule:RefreshCurrencyPage()
    end)

    local themeLabel = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    themeLabel:SetPoint("TOPLEFT", parent, "TOPLEFT", 18, -92)
    themeLabel:SetText("Currency Theme")

    local themeDropdown = CreateFrame("Frame", nil, parent, "UIDropDownMenuTemplate")
    themeDropdown:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -106)
    _G.UIDropDownMenu_SetWidth(themeDropdown, 150)
    _G.UIDropDownMenu_JustifyText(themeDropdown, "LEFT")

    local function ThemeLabelForKey(key)
        if key == "light" then
            return "Light"
        end
        if key == "dark" then
            return "Dark"
        end
        return "Brown"
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
    minimapToggle:SetPoint("TOPLEFT", parent, "TOPLEFT", 18, -136)
    minimapToggle.Text:SetText("Show Minimap Button")
    minimapToggle:SetScript("OnClick", function(self)
        settings.currencyMinimapButton = self:GetChecked() and true or false
        settings.currencyMinimap.hide = not (settings.currencyMinimapButton == true)
        UpdateVisibilityFromSettings()
    end)

    local affordableToggle = add(CreateFrame("CheckButton", nil, parent, "InterfaceOptionsCheckButtonTemplate"))
    affordableToggle:SetPoint("TOPLEFT", parent, "TOPLEFT", 18, -164)
    affordableToggle.Text:SetText("Show Affordable Hunts In Tracker")
    affordableToggle:SetScript("OnClick", function(self)
        settings.currencyShowAffordableHunts = self:GetChecked() and true or false
        CurrencyTrackerModule:RefreshCurrencyPage()
    end)

    local realmToggle = add(CreateFrame("CheckButton", nil, parent, "InterfaceOptionsCheckButtonTemplate"))
    realmToggle:SetPoint("TOPLEFT", parent, "TOPLEFT", 18, -192)
    realmToggle.Text:SetText("Show Group By Realm In Warband")
    realmToggle:SetScript("OnClick", function(self)
        settings.currencyShowRealmInWarband = self:GetChecked() and true or false
        CurrencyTrackerModule:RefreshCurrencyPage()
    end)

    local trackedTitle = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    trackedTitle:SetPoint("TOPLEFT", parent, "TOPLEFT", 18, -222)
    trackedTitle:SetText("Currencies to Track")
    SetTextColor(trackedTitle, COLOR_GOLD)

    local y = -248
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
    costsTitle:SetText("Random Hunt Cost (Anguish)")
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

    local normalBox = CreateCostInput("Normal", "normal", -64)
    local hardBox = CreateCostInput("Hard", "hard", -92)
    local nightmareBox = CreateCostInput("Nightmare", "nightmare", -120)

    local layoutTitle = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    layoutTitle:SetPoint("TOPLEFT", parent, "TOPLEFT", 260, -196)
    layoutTitle:SetText("Panel Layout")
    SetTextColor(layoutTitle, COLOR_GOLD)

    local layoutTargetLabel = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    layoutTargetLabel:SetPoint("TOPLEFT", parent, "TOPLEFT", 260, -222)
    layoutTargetLabel:SetText("Adjust")

    local activeLayoutTarget = "currency"
    local widthSlider
    local heightSlider
    local scaleSlider
    local fontSlider
    local isLayoutRefreshing = false

    local layoutTargetDropdown = CreateFrame("Frame", "PreydatorCurrencyLayoutTargetDropdown", parent, "UIDropDownMenuTemplate")
    layoutTargetDropdown:SetPoint("TOPLEFT", parent, "TOPLEFT", 242, -236)
    _G.UIDropDownMenu_SetWidth(layoutTargetDropdown, 150)
    _G.UIDropDownMenu_JustifyText(layoutTargetDropdown, "LEFT")

    local function GetLayoutSpec()
        if activeLayoutTarget == "warband" then
            return {
                width = { key = "currencyWarbandWidth", min = WARBAND_MIN_WIDTH, max = WARBAND_MAX_WIDTH, step = 4, isFloat = false },
                height = { key = "currencyWarbandHeight", min = WARBAND_MIN_HEIGHT, max = WARBAND_MAX_HEIGHT, step = 4, isFloat = false },
                scale = { key = "currencyWarbandScale", min = WARBAND_MIN_SCALE, max = WARBAND_MAX_SCALE, step = 0.01, isFloat = true, decimals = 2 },
                font = { key = "currencyWarbandFontSize", min = WARBAND_MIN_FONT, max = WARBAND_MAX_FONT, step = 1, isFloat = false },
            }
        end

        return {
            width = { key = "currencyWindowWidth", min = TRACKER_MIN_WIDTH, max = TRACKER_MAX_WIDTH, step = 4, isFloat = false },
            height = { key = "currencyWindowHeight", min = TRACKER_MIN_HEIGHT, max = TRACKER_MAX_HEIGHT, step = 4, isFloat = false },
            scale = { key = "currencyWindowScale", min = TRACKER_MIN_SCALE, max = TRACKER_MAX_SCALE, step = 0.01, isFloat = true, decimals = 2 },
            font = { key = "currencyWindowFontSize", min = TRACKER_MIN_FONT, max = TRACKER_MAX_FONT, step = 1, isFloat = false },
        }
    end

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

    widthSlider = CreateLayoutSlider(-266, "Width")
    heightSlider = CreateLayoutSlider(-312, "Height")
    scaleSlider = CreateLayoutSlider(-358, "Scale")
    fontSlider = CreateLayoutSlider(-404, "Font")

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
        local spec = GetLayoutSpec()

        local map = {
            { slider = widthSlider, field = spec.width },
            { slider = heightSlider, field = spec.height },
            { slider = scaleSlider, field = spec.scale },
            { slider = fontSlider, field = spec.font },
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

        _G.UIDropDownMenu_SetText(layoutTargetDropdown, activeLayoutTarget == "warband" and "Warband Window" or "Currency Window")
        isLayoutRefreshing = false
    end

    _G.UIDropDownMenu_Initialize(layoutTargetDropdown, function(self, level)
        local info = _G.UIDropDownMenu_CreateInfo()
        info.text = "Currency Window"
        info.func = function()
            activeLayoutTarget = "currency"
            RefreshLayoutControls()
        end
        info.checked = activeLayoutTarget == "currency"
        _G.UIDropDownMenu_AddButton(info, level)

        info = _G.UIDropDownMenu_CreateInfo()
        info.text = "Warband Window"
        info.func = function()
            activeLayoutTarget = "warband"
            RefreshLayoutControls()
        end
        info.checked = activeLayoutTarget == "warband"
        _G.UIDropDownMenu_AddButton(info, level)
    end)

    local gainColorButton = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    gainColorButton:SetSize(120, 22)
    gainColorButton:SetPoint("TOPLEFT", parent, "TOPLEFT", 260, -145)
    gainColorButton:SetText("Gain Color")
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
    lossColorButton:SetText("Spend Color")
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
    previewTitle:SetText("Delta Preview")

    local previewBoxes = {
        CreatePreviewBox(426, -132),
        CreatePreviewBox(472, -132),
        CreatePreviewBox(518, -132),
    }

    function parent:PreydatorCurrencyRefresh()
        minimapToggle:SetChecked(settings.currencyMinimap.hide ~= true)
        affordableToggle:SetChecked(settings.currencyShowAffordableHunts ~= false)
        realmToggle:SetChecked(settings.currencyShowRealmInWarband == true)

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

        openButton:SetText((settings.currencyWindowEnabled ~= false) and "Close Tracker" or "Open Tracker")
        openWarbandButton:SetText((settings.currencyWarbandWindowEnabled == true) and "Close Warband" or "Open Warband")

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
    UpdateLastKnownQuantities()
end

function CurrencyTrackerModule:OnEvent(event, ...)
    if event == "PLAYER_LOGIN" then
        EnsureDB()
        EnsureTrackerSettings()
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
        ShowCurrencyWhatsNewIfNeeded()
    end
end
