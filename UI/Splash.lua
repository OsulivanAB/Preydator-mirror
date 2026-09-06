-- Preydator :: UI/Splash.lua
-- Author: RagingAltoholic
-- Responsibility: the one-time "what's new" popup shown after an update to a
-- new splash-content version, plus a manual reopen from Settings > Advanced.
-- Pure UI -- renders a static summary and forwards the "seen" flag back
-- through Settings; never originates gameplay truth.
-- Reads: Settings (general.splash_seen_version), LocalizationAdapter.
-- Writes: Settings (general.splash_seen_version), via Settings.Set only.

local Preydator = _G.Preydator
local CreateFrame = _G.CreateFrame
local UIParent = _G.UIParent

local Splash = {}

-- Bumped only when the splash's own content changes, not on every addon
-- version -- so a routine patch release doesn't reopen this for someone who
-- already saw the same content. Mirrors the old codebase's
-- PREYDATOR_THREE_SPLASH_VERSION pattern (D:\Dev\PreydatorLive\Preydator.lua:634-712).
local SPLASH_CONTENT_VERSION = "4.0.0"

-- Fixed, generously-sized frame -- no scroll frame. A first version used a
-- UIPanelScrollFrameTemplate + scroll child sized dynamically via
-- OnSizeChanged/GetHeight(), and rendered completely blank in-game (confirmed
-- live, 2026-09-06): a hidden frame's freshly-created fontstrings can't be
-- trusted to report a real GetHeight()/have a nonzero parent width before the
-- frame has ever actually been shown once, so both the scroll child's size
-- and the body fontstrings' wrap width were unreliable at build time. The
-- old, actually-shipped 3.0 splash never used a scroll frame at all -- a
-- fixed-size frame with directly-anchored fontstrings -- so this reverts to
-- that same proven shape instead of an unproven "improvement."
local FRAME_WIDTH = 600
local FRAME_HEIGHT = 620
local CONTENT_WIDTH = FRAME_WIDTH - 40

local frame = nil

local function L(key)
    local localization = Preydator:GetModule("LocalizationAdapter")
    if localization and type(localization.L) == "function" then
        return localization.L(key)
    end
    return key
end

local function getSettings()
    return Preydator:GetModule("Settings")
end

-- One header + one word-wrapped paragraph, both a fixed CONTENT_WIDTH (not
-- anchored relative to the parent's own width, which is what broke the
-- scroll-frame version above), anchored below whatever was passed as
-- `previous` (nil anchors to the top of `parent`). Returns the paragraph
-- fontstring so the next section can anchor below it in turn.
local function addSection(parent, previous, headerText, bodyText)
    local header = parent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    header:SetWidth(CONTENT_WIDTH)
    header:SetJustifyH("LEFT")
    if previous then
        header:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", 0, -16)
    else
        header:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
    end
    header:SetText(headerText)

    local body = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    body:SetWidth(CONTENT_WIDTH)
    body:SetJustifyH("LEFT")
    body:SetJustifyV("TOP")
    body:SetWordWrap(true)
    body:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -6)
    body:SetText(bodyText)

    return body
end

local function ensureFrame()
    if frame then
        return frame
    end

    frame = CreateFrame("Frame", "PreydatorSplashFrame", UIParent, "BackdropTemplate")
    frame:SetSize(FRAME_WIDTH, FRAME_HEIGHT)
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 20)
    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    frame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    frame:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    frame:SetBackdropColor(0.05, 0.04, 0.03, 0.96)
    frame:SetBackdropBorderColor(0.78, 0.62, 0.20, 1)

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", frame, "TOPLEFT", 18, -16)
    title:SetText(L("Preydator 4.0.0 Splash Title"))

    local closeButton = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    closeButton:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -4, -4)
    closeButton:SetScript("OnClick", function()
        frame:Hide()
    end)

    local gotItButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    gotItButton:SetSize(120, 24)
    gotItButton:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -18, 16)
    gotItButton:SetText(L("Got It"))
    gotItButton:SetScript("OnClick", function()
        frame:Hide()
    end)

    local body = CreateFrame("Frame", nil, frame)
    body:SetPoint("TOPLEFT", frame, "TOPLEFT", 20, -52)
    body:SetPoint("BOTTOMRIGHT", gotItButton, "TOPRIGHT", 0, 10)

    local previous = addSection(body, nil,
        L("What's New"), L("PREYDATOR_4_0_0_HIGHLIGHTS_BODY"))
    previous = addSection(body, previous,
        L("Hunt Table Icons"), L("PREYDATOR_4_0_0_ICONS_BODY"))
    addSection(body, previous,
        L("Known Limitations"), L("PREYDATOR_4_0_0_LIMITATIONS_BODY"))

    frame:Hide()
    return frame
end

-- force=true (the Settings > Advanced "Show What's New" button) always shows
-- it, bypassing the seen-version gate. Called with no argument at
-- PLAYER_LOGIN, where it only shows for a version the player hasn't seen yet.
function Splash.Show(force)
    local settings = getSettings()
    if not settings then
        return
    end

    if force ~= true then
        local seenVersion = settings.Get("general.splash_seen_version")
        if seenVersion == SPLASH_CONTENT_VERSION then
            return
        end
    end

    settings.Set("general.splash_seen_version", SPLASH_CONTENT_VERSION)
    ensureFrame():Show()
end

do
    -- Defer to PLAYER_LOGIN, same standing rule as every other UI/*.lua
    -- self-init (session_status.md: a file-load-time Settings read gets
    -- permanently stuck on defaults, since SavedVariables haven't loaded yet).
    local initFrame = CreateFrame("Frame")
    initFrame:RegisterEvent("PLAYER_LOGIN")
    initFrame:SetScript("OnEvent", function(self)
        self:UnregisterEvent("PLAYER_LOGIN")
        Splash.Show()
    end)
end

Preydator:RegisterModule("Splash", Splash)
return Splash
