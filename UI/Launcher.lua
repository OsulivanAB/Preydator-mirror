-- Preydator :: UI/Launcher.lua
-- Author: RagingAltoholic
-- Responsibility: the minimap button + Blizzard Addon Compartment entry
-- point. Left-click opens Settings (UI/SettingsPanel.lua's OpenSettings,
-- reused rather than duplicated); right-click prints a quick diagnostic
-- report (DiagnosticsRuntime.BuildGeneralInspectReport, the same content
-- `/pd inspect` prints) -- there is no separate report window in this
-- architecture (see Decisions Log item 38 for why one wasn't built).
-- Reads: Core/Settings.lua (general.minimap_hidden/minimap_angle),
-- Core/Runtime/DiagnosticsRuntime.lua.
-- Writes: general.minimap_angle only, while the fallback button is dragged.

local Preydator = _G.Preydator
local CreateFrame = _G.CreateFrame
local LibStub = _G.LibStub
local GetCursorPosition = _G.GetCursorPosition
local UIParent = _G.UIParent

local Launcher = {}

local ICON_PATH = "Interface\\AddOns\\Preydator\\media\\Preydator_64.png"
local LDB_NAME = "Preydator"

local function getSettings()
    return Preydator:GetModule("Settings")
end

local function normalizeAngle(angle)
    if type(angle) ~= "number" then
        return 225
    end
    angle = angle % 360
    if angle < 0 then
        angle = angle + 360
    end
    return angle
end

local function openSettings()
    local settingsPanel = Preydator:GetModule("SettingsPanel")
    if settingsPanel and type(settingsPanel.OpenSettings) == "function" then
        settingsPanel.OpenSettings()
    end
end

local function printQuickInspect()
    local diagnostics = Preydator:GetModule("DiagnosticsRuntime")
    local report = diagnostics and type(diagnostics.BuildGeneralInspectReport) == "function"
        and diagnostics.BuildGeneralInspectReport()
    print(report or "Preydator: report unavailable (DiagnosticsRuntime not loaded).")
end

local function handleClick(mouseButton)
    if mouseButton == "LeftButton" then
        openSettings()
    elseif mouseButton == "RightButton" then
        printQuickInspect()
    end
end

local function showTooltip(owner)
    local gameTooltip = _G.GameTooltip
    if not gameTooltip or type(gameTooltip.SetOwner) ~= "function" then
        return
    end
    gameTooltip:SetOwner(owner or UIParent, "ANCHOR_LEFT")
    gameTooltip:ClearLines()
    gameTooltip:AddLine("Preydator")
    gameTooltip:AddLine("Left Click: Open Settings", 1, 1, 1)
    gameTooltip:AddLine("Right Click: Quick Inspect", 1, 1, 1)
    gameTooltip:Show()
end

-- ---------------------------------------------------------------------------
-- Fallback custom-drawn minimap button, used only when LibDBIcon-1.0 isn't
-- present (it's an OptionalDep, per Preydator.toc -- many players already
-- have it loaded via another addon, so it's not bundled here). Ported from
-- the old codebase's inline Preydator.lua launcher block, rewired to the new
-- Settings API.
-- ---------------------------------------------------------------------------

local fallbackButton

local function updateFallbackPosition()
    if not fallbackButton then
        return
    end
    local settings = getSettings()
    local angle = normalizeAngle(settings and settings.Get("general.minimap_angle"))
    local minimap = _G.Minimap
    if not minimap then
        return
    end
    local radians = math.rad(angle)
    local minimapRadius = math.min(minimap:GetWidth(), minimap:GetHeight()) / 2
    local radius = minimapRadius + 8
    local x = math.cos(radians) * radius
    local y = math.sin(radians) * radius
    fallbackButton:ClearAllPoints()
    fallbackButton:SetPoint("CENTER", minimap, "CENTER", x, y)
end

local function createFallbackButton()
    if fallbackButton or not _G.Minimap then
        return fallbackButton
    end

    local button = CreateFrame("Button", "PreydatorMinimapButton", _G.Minimap)
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
    icon:SetTexture(ICON_PATH)
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
        handleClick(mouseButton)
    end)

    button:SetScript("OnEnter", function(self) showTooltip(self) end)
    button:SetScript("OnLeave", function() _G.GameTooltip:Hide() end)

    button:SetScript("OnDragStart", function(self)
        self.wasDragged = false
        self:SetScript("OnUpdate", function(s)
            local minimap = _G.Minimap
            if not minimap then
                return
            end
            local mx, my = GetCursorPosition()
            local scale = UIParent:GetEffectiveScale()
            mx, my = mx / scale, my / scale
            local cx, cy = minimap:GetCenter()
            if not cx or not cy then
                return
            end
            local angle = normalizeAngle(math.deg(math.atan(my - cy, mx - cx)))
            local settings = getSettings()
            if settings then
                settings.Set("general.minimap_angle", angle)
            end
            s.wasDragged = true
            updateFallbackPosition()
        end)
    end)

    button:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
        self.wasDragged = nil
    end)

    fallbackButton = button
    updateFallbackPosition()
    return button
end

-- ---------------------------------------------------------------------------
-- LibDataBroker-1.1 + LibDBIcon-1.0 (both OptionalDeps, per Preydator.toc --
-- not bundled, used only if another addon already loaded them this session).
-- ---------------------------------------------------------------------------

local ldbObject
local ldbRegistered = false

local function ensureLdbObject()
    if ldbObject then
        return ldbObject
    end
    local ldb = LibStub and LibStub:GetLibrary("LibDataBroker-1.1", true)
    if not ldb then
        return nil
    end
    ldbObject = ldb:NewDataObject(LDB_NAME, {
        type = "launcher",
        text = "Preydator",
        icon = ICON_PATH,
        OnClick = function(_, mouseButton) handleClick(mouseButton) end,
        OnTooltipShow = function(tooltip)
            if not tooltip then
                return
            end
            tooltip:AddLine("Preydator")
            tooltip:AddLine("Left Click: Open Settings", 1, 1, 1)
            tooltip:AddLine("Right Click: Quick Inspect", 1, 1, 1)
        end,
    })
    return ldbObject
end

local function updateVisibility()
    local settings = getSettings()
    local hidden = settings and settings.Get("general.minimap_hidden") == true
    local dbIcon = LibStub and LibStub:GetLibrary("LibDBIcon-1.0", true)
    if dbIcon and ldbRegistered then
        if hidden then
            dbIcon:Hide(LDB_NAME)
        else
            dbIcon:Show(LDB_NAME)
        end
    elseif fallbackButton then
        fallbackButton:SetShown(not hidden)
    end
end

local function ensureButton()
    local dbIcon = LibStub and LibStub:GetLibrary("LibDBIcon-1.0", true)
    local ldb = LibStub and LibStub:GetLibrary("LibDataBroker-1.1", true)

    if dbIcon and ldb then
        ensureLdbObject()
        if ldbObject and not ldbRegistered then
            -- LibDBIcon owns its own per-addon position table; a tiny shim
            -- table here (not the settings profile itself) is what it reads/
            -- writes minimapPos on -- kept in sync with the real setting via
            -- updatePositionShim below rather than handed the profile table
            -- directly, since LibDBIcon mutates whatever table it's given
            -- and Core/Settings.lua's Set/Get API is the only sanctioned
            -- write path into the profile (Section 4/CLAUDE.md single-
            -- source-of-truth rule).
            local settings = getSettings()
            local positionShim = { minimapPos = normalizeAngle(settings and settings.Get("general.minimap_angle")) }
            dbIcon:Register(LDB_NAME, ldbObject, positionShim)
            ldbRegistered = true
            Launcher.positionShim = positionShim
        end
        return
    end

    createFallbackButton()
end

-- LibDBIcon polls its own shim table's minimapPos on drag and writes back to
-- it directly -- mirror any drift back into the real setting so Settings UI/
-- SavedVariables stay the source of truth, checked on every settings change
-- (cheap: one read/compare, no work unless it actually drifted).
local function syncLdbPositionShim()
    if not Launcher.positionShim then
        return
    end
    local settings = getSettings()
    if not settings then
        return
    end
    local shimAngle = normalizeAngle(Launcher.positionShim.minimapPos)
    if shimAngle ~= settings.Get("general.minimap_angle") then
        settings.Set("general.minimap_angle", shimAngle)
    end
end

local function refresh()
    ensureButton()
    updateVisibility()
    updateFallbackPosition()
    syncLdbPositionShim()
end

-- ---------------------------------------------------------------------------
-- Addon Compartment (Preydator.toc's AddonCompartmentFunc entries call these
-- by name).
-- ---------------------------------------------------------------------------

function _G.Preydator_OnAddonCompartmentClick(_, buttonName)
    handleClick(buttonName or "LeftButton")
end

function _G.Preydator_OnAddonCompartmentEnter(button)
    showTooltip(button or _G.AddonCompartmentFrame or UIParent)
end

function _G.Preydator_OnAddonCompartmentLeave()
    if _G.GameTooltip and type(_G.GameTooltip.Hide) == "function" then
        _G.GameTooltip:Hide()
    end
end

-- ---------------------------------------------------------------------------
-- Init
-- ---------------------------------------------------------------------------

local Settings = Preydator:GetModule("Settings")
if Settings and type(Settings.Subscribe) == "function" then
    Settings.Subscribe(refresh)
end

-- SavedVariables (and therefore Settings.Get) aren't populated until after
-- every addon's files finish loading, right before ADDON_LOADED fires --
-- same PLAYER_LOGIN-deferral rule UI/BarFrame.lua's self-init already
-- established (reading settings any earlier would get Core/Settings.lua's
-- cache permanently stuck on default values for the whole session).
local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    refresh()
end)

Preydator:RegisterModule("Launcher", Launcher)
return Launcher
