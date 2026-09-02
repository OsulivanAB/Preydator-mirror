-- Preydator :: UI/BarFrame.lua
-- Author: RagingAltoholic
-- Responsibility: CreateFrame calls, texture/font/color application, and
-- rendering. Consumes Core/Runtime/BarRuntime.lua's view-model for
-- game-state-derived values (visible/fillPercent/stage/prefixText/
-- suffixText/tickPositions) and reads Settings directly for every pure
-- presentation field (colors, texture, fonts, dimensions/scale, orientation,
-- label layout) -- those have no game-state dependency, so there is nothing
-- for BarRuntime to compute. Never reads State directly and never decides
-- gameplay truth (architecture doc Section 3).
-- Reads: Core/Runtime/BarRuntime.lua (view-model), Core/Settings.lua.
-- Writes: Core/Settings.lua (bar.position_x/position_y only, on drag-stop or
-- ResetPosition()).

local Preydator = _G.Preydator
local CreateFrame = _G.CreateFrame
local GetLocale = _G.GetLocale
local UIParent = _G.UIParent

local BarFrame = {}

local FILL_INSET = 3
local MAX_TICKS = 3
local TICK_LABEL_OFFSET = 4
local LABEL_ROW_OFFSET = 4
local DRAG_SCREEN_MARGIN = 8

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

-- Bundled Western fonts have no glyphs for these locales; forcing the
-- client's own standard font here is easy to silently drop when writing a UI
-- file from scratch (see issues/bar_rendering_research.md Section 1/9) so
-- it's called out explicitly rather than left implicit.
local LOCALE_SAFE_FONT_LOCALES = { ruRU = true, koKR = true, zhCN = true, zhTW = true }

-- Which text region a stage_label_mode value puts where, and which side of
-- the progress axis it anchors to ("start"/"end"/"center"). Table-driven so
-- the 9 values are one lookup, not a 9-branch if-chain.
local LABEL_MODE_LAYOUT = {
    center = { primary = "combined", primaryAxis = "center" },
    left = { primary = "prefix", primaryAxis = "start" },
    left_combined = { primary = "combined", primaryAxis = "start" },
    left_suffix = { primary = "suffix", primaryAxis = "start" },
    right = { primary = "suffix", primaryAxis = "end" },
    right_combined = { primary = "combined", primaryAxis = "end" },
    right_prefix = { primary = "prefix", primaryAxis = "end" },
    separate = { primary = "prefix", primaryAxis = "start", secondary = "suffix", secondaryAxis = "end" },
    none = {},
}

-- bar.percent_display values that replace the single running-percent text
-- with per-tick percent labels instead (screen-space above/below each tick,
-- regardless of orientation -- see design decision in the plan).
local TICK_LABEL_PERCENT_DISPLAY = { above_ticks = true, under_ticks = true }

local barFrame = nil

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

local function isEditModeActive()
    local editModeFrame = _G.EditModeManagerFrame
    return (editModeFrame and editModeFrame.IsShown and editModeFrame:IsShown()) == true
end

local function resolveFontPath(fontKey)
    local ok, locale = pcall(GetLocale)
    if ok and LOCALE_SAFE_FONT_LOCALES[locale] then
        return _G.STANDARD_TEXT_FONT
    end
    return FONT_PRESETS[fontKey] or FONT_PRESETS.frizqt
end

local function setFontPreservingFlags(fontString, path, size)
    local _, _, flags = fontString:GetFont()
    fontString:SetFont(path, size, flags)
end

-- One function, not two (the old code independently reimplements this same
-- orientation-based clamp-and-fallback math in two places).
local function resolveDimensions(orientation, settings)
    if orientation == "vertical" then
        return settings.Get("bar.width_vertical") or 40,
            settings.Get("bar.height_vertical") or 160,
            settings.Get("bar.scale_vertical") or 0.9
    end
    return settings.Get("bar.width_horizontal") or 160,
        settings.Get("bar.height_horizontal") or 30,
        settings.Get("bar.scale_horizontal") or 1.0
end

local function resolveLabelContent(kind, prefixText, suffixText)
    if kind == "prefix" then
        return prefixText
    end
    if kind == "suffix" then
        return suffixText
    end
    if kind == "combined" then
        if prefixText ~= "" and suffixText ~= "" then
            return prefixText .. " " .. suffixText
        end
        return prefixText .. suffixText
    end
    return ""
end

-- Anchors one text region at the given position along the bar's progress
-- axis ("start"/"end"/"center"). Horizontal mode: perpendicular offset is
-- text.label_row_position (above/below the bar), left/right/center is a
-- normal horizontal row. Vertical mode: the whole region rotates 90 degrees
-- (bar.vertical_text_side picks which side of the bar it sits on, and
-- start/end follow bar.vertical_fill_direction) -- this is the one place
-- orientation actually changes the anchoring math, per the design decision
-- to otherwise keep stage_label_mode identical in both orientations.
local function applyLabelRegionAnchor(fontString, frame, orientation, axisPosition, settings)
    fontString:ClearAllPoints()

    if orientation == "vertical" then
        local side = settings.Get("bar.vertical_text_side") or "right"
        local fillDirection = settings.Get("bar.vertical_fill_direction") or "up"
        local startAnchor = fillDirection == "up" and "BOTTOM" or "TOP"
        local endAnchor = fillDirection == "up" and "TOP" or "BOTTOM"
        local axisPart = (axisPosition == "start" and startAnchor)
            or (axisPosition == "end" and endAnchor)
            or "CENTER"
        local sidePoint = side == "left" and "LEFT" or "RIGHT"
        local sideOffset = side == "left" and -(LABEL_ROW_OFFSET + 14) or (LABEL_ROW_OFFSET + 14)

        -- Anchored by the fontstring's own CENTER, not an edge: rotation
        -- pivots around the region's center, so anchoring an edge point (as
        -- this used to) visually swings the auto-sized text away from the
        -- intended spot by roughly half its own length once rotated -- this
        -- was the cause of the reported ~70px vertical-mode text offset.
        local framePoint = (axisPart == "CENTER") and sidePoint or (axisPart .. sidePoint)
        fontString:SetPoint("CENTER", frame, framePoint, sideOffset, 0)
        fontString:SetJustifyH("CENTER")
        fontString:SetRotation(side == "left" and (math.pi / 2) or (-math.pi / 2))
        return
    end

    local rowPosition = settings.Get("text.label_row_position") or "above"
    local rowOffset = rowPosition == "above" and LABEL_ROW_OFFSET or -LABEL_ROW_OFFSET
    local outward = rowPosition == "above" and "TOP" or "BOTTOM"
    local inward = rowPosition == "above" and "BOTTOM" or "TOP"

    if axisPosition == "start" then
        fontString:SetPoint(inward .. "LEFT", frame, outward .. "LEFT", 2, rowOffset)
        fontString:SetJustifyH("LEFT")
    elseif axisPosition == "end" then
        fontString:SetPoint(inward .. "RIGHT", frame, outward .. "RIGHT", -2, rowOffset)
        fontString:SetJustifyH("RIGHT")
    else
        fontString:SetPoint(inward, frame, outward, 0, rowOffset)
        fontString:SetJustifyH("CENTER")
    end
    fontString:SetRotation(0)
end

local function applyLabelText(frame, viewModel, settings, orientation)
    local editModeActive = isEditModeActive() and settings.Get("bar.show_in_edit_mode") ~= false
    local prefixText, suffixText = viewModel.prefixText or "", viewModel.suffixText or ""
    if editModeActive then
        prefixText, suffixText = "", L("Preydator (Edit Mode Preview)")
    end

    local mode = settings.Get("text.stage_label_mode") or "center"
    local layout = LABEL_MODE_LAYOUT[mode] or LABEL_MODE_LAYOUT.center

    frame.prefixText:Hide()
    frame.suffixText:Hide()

    if layout.primary then
        frame.prefixText:SetText(resolveLabelContent(layout.primary, prefixText, suffixText))
        applyLabelRegionAnchor(frame.prefixText, frame, orientation, layout.primaryAxis, settings)
        frame.prefixText:Show()
    end

    if layout.secondary then
        frame.suffixText:SetText(resolveLabelContent(layout.secondary, prefixText, suffixText))
        applyLabelRegionAnchor(frame.suffixText, frame, orientation, layout.secondaryAxis, settings)
        frame.suffixText:Show()
    end
end

local function applyPercentText(frame, viewModel, settings, orientation)
    local percentDisplay = settings.Get("bar.percent_display") or "inside"
    if percentDisplay == "off" or TICK_LABEL_PERCENT_DISPLAY[percentDisplay] then
        frame.percentText:Hide()
        return
    end

    frame.percentText:Show()
    frame.percentText:SetText(string.format("%d%%", math.floor((viewModel.fillPercent or 0) + 0.5)))
    frame.percentText:ClearAllPoints()

    -- above_bar/below_bar sit in open space regardless of orientation and
    -- never rotate (a horizontal label above a narrow vertical bar is fine
    -- unrotated). Only "inside" rotates in vertical mode, and it's the one
    -- case safe to anchor by CENTER-to-CENTER either way, so it never hit the
    -- edge-anchor-plus-rotation offset bug applyLabelRegionAnchor had.
    if percentDisplay == "above_bar" then
        frame.percentText:SetPoint("BOTTOM", frame, "TOP", 0, LABEL_ROW_OFFSET)
        frame.percentText:SetRotation(0)
    elseif percentDisplay == "below_bar" then
        frame.percentText:SetPoint("TOP", frame, "BOTTOM", 0, -LABEL_ROW_OFFSET)
        frame.percentText:SetRotation(0)
    else
        frame.percentText:SetPoint("CENTER", frame, "CENTER", 0, 0)
        if orientation == "vertical" then
            local side = settings.Get("bar.vertical_text_side") or "right"
            frame.percentText:SetRotation(side == "left" and (math.pi / 2) or (-math.pi / 2))
        else
            frame.percentText:SetRotation(0)
        end
    end
end

local function applyTicks(frame, viewModel, settings, orientation)
    local showTicks = settings.Get("bar.show_ticks") ~= false
    local percentDisplay = settings.Get("bar.percent_display") or "inside"
    local showTickLabels = showTicks and TICK_LABEL_PERCENT_DISPLAY[percentDisplay] == true
    local tickPositions = viewModel.tickPositions or {}
    local tickColor = settings.Get("bar.tick_color") or { 1, 1, 1, 0.35 }

    local width, height = frame:GetSize()
    local innerWidth = math.max(0, width - (2 * FILL_INSET))
    local innerHeight = math.max(0, height - (2 * FILL_INSET))

    for i = 1, MAX_TICKS do
        local tick = frame.ticks[i]
        local label = frame.tickLabels[i]
        local percent = tickPositions[i]

        if not showTicks or not percent then
            tick:Hide()
            label:Hide()
        else
            tick:Show()
            tick:SetColorTexture(tickColor[1], tickColor[2], tickColor[3], tickColor[4])
            tick:ClearAllPoints()

            if orientation == "vertical" then
                tick:SetSize(innerWidth, 1)
                local y = FILL_INSET + math.floor((innerHeight * (percent / 100)) + 0.5)
                tick:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", FILL_INSET, y)
            else
                tick:SetSize(1, innerHeight)
                local x = FILL_INSET + math.floor((innerWidth * (percent / 100)) + 0.5)
                tick:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", x, FILL_INSET)
            end

            if showTickLabels then
                label:Show()
                label:SetText(percent .. "%")
                label:ClearAllPoints()
                if percentDisplay == "above_ticks" then
                    label:SetPoint("BOTTOM", tick, "TOP", 0, TICK_LABEL_OFFSET)
                else
                    label:SetPoint("TOP", tick, "BOTTOM", 0, -TICK_LABEL_OFFSET)
                end
            else
                label:Hide()
            end
        end
    end
end

local function applyFill(frame, viewModel, settings, orientation)
    local width, height = frame:GetSize()
    local innerWidth = math.max(1, width - (2 * FILL_INSET))
    local innerHeight = math.max(1, height - (2 * FILL_INSET))
    local percent = math.max(0, math.min(100, viewModel.fillPercent or 0))

    frame.fill:ClearAllPoints()
    if orientation == "vertical" then
        local fillDirection = settings.Get("bar.vertical_fill_direction") or "up"
        local fillHeight = math.max(1, math.floor((innerHeight * (percent / 100)) + 0.5))
        frame.fill:SetSize(innerWidth, fillHeight)
        if fillDirection == "down" then
            frame.fill:SetPoint("TOPLEFT", frame, "TOPLEFT", FILL_INSET, -FILL_INSET)
        else
            frame.fill:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", FILL_INSET, FILL_INSET)
        end
    else
        local fillWidth = math.max(1, math.floor((innerWidth * (percent / 100)) + 0.5))
        frame.fill:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", FILL_INSET, FILL_INSET)
        frame.fill:SetSize(fillWidth, innerHeight)
    end
end

local function applyBackgroundAndBorder(frame, settings)
    local bgColor = settings.Get("bar.bg_color") or { 0, 0, 0, 0.6 }
    frame.background:SetColorTexture(bgColor[1], bgColor[2], bgColor[3], bgColor[4])

    local fillColor = settings.Get("bar.fill_color") or { 0.85, 0.2, 0.2, 0.95 }
    local borderLinked = settings.Get("bar.border_color_linked") ~= false
    local borderColor = borderLinked and fillColor or (settings.Get("bar.border_color") or fillColor)
    frame.border:SetBackdropBorderColor(borderColor[1], borderColor[2], borderColor[3], borderColor[4])
end

local function applyFillTexture(frame, settings)
    local textureKey = settings.Get("bar.texture_key") or "default"
    frame.fill:SetTexture(TEXTURE_PRESETS[textureKey] or TEXTURE_PRESETS.default)
    local fillColor = settings.Get("bar.fill_color") or { 0.85, 0.2, 0.2, 0.95 }
    frame.fill:SetVertexColor(fillColor[1], fillColor[2], fillColor[3], fillColor[4])
end

local function applyFonts(frame, settings, scale)
    local baseFontSize = settings.Get("text.font_size") or 12
    local titleFont = resolveFontPath(settings.Get("text.title_font_key"))
    local percentFont = resolveFontPath(settings.Get("text.percent_font_key"))

    local titleSize = math.max(8, math.floor((baseFontSize * scale) + 0.5))
    local percentSize = math.max(8, math.floor(((baseFontSize - 1) * scale) + 0.5))
    local tickSize = math.max(7, math.floor(((baseFontSize - 4) * scale) + 0.5))

    setFontPreservingFlags(frame.prefixText, titleFont, titleSize)
    setFontPreservingFlags(frame.suffixText, titleFont, titleSize)
    setFontPreservingFlags(frame.percentText, percentFont, percentSize)
    for i = 1, MAX_TICKS do
        setFontPreservingFlags(frame.tickLabels[i], percentFont, tickSize)
    end

    local titleColor = settings.Get("bar.title_color") or { 1, 0.82, 0, 1 }
    frame.prefixText:SetTextColor(titleColor[1], titleColor[2], titleColor[3], titleColor[4])
    frame.suffixText:SetTextColor(titleColor[1], titleColor[2], titleColor[3], titleColor[4])

    local percentColor = settings.Get("bar.percent_color") or { 1, 1, 1, 1 }
    frame.percentText:SetTextColor(percentColor[1], percentColor[2], percentColor[3], percentColor[4])
    for i = 1, MAX_TICKS do
        frame.tickLabels[i]:SetTextColor(percentColor[1], percentColor[2], percentColor[3], percentColor[4])
    end
end

local function applyVisibilityAndMouse(frame, viewModel, settings)
    local editModeActive = isEditModeActive() and settings.Get("bar.show_in_edit_mode") ~= false
    local barEnabled = settings.Get("general.bar_enabled") ~= false
    local shouldShow = barEnabled and (editModeActive or viewModel.visible == true)

    if shouldShow then
        frame:Show()
    else
        frame:Hide()
    end

    -- One gate, not two: EnableMouse(false) means OnDragStart never fires, so
    -- there is no separate lock check needed inside the drag scripts (the old
    -- code checked "not locked" in both places -- see plan Decision 3).
    local lockBar = settings.Get("general.lock_bar") == true
    frame:EnableMouse((not lockBar) or editModeActive)
end

-- GetCenter()/GetLeft()/etc. return positions in UIParent's own (unscaled)
-- coordinate space, regardless of the frame's own SetScale -- but SetPoint's
-- offset arguments are interpreted in the CALLING frame's own scale. Storing
-- an absolute position (via GetCenter deltas) and feeding it straight back
-- into this frame's own SetPoint without dividing by this frame's scale
-- silently re-scales the offset -- invisible at scale 1.0, but a visible
-- jump at any other scale, and on every drag release if the player's overall
-- UI scale isn't exactly 1.0 either. This was the cause of the reported
-- drag-jump and scale-slider-recenters-the-bar bugs.
local function currentFrameScale(frame)
    local scale = frame:GetScale()
    if type(scale) ~= "number" or scale == 0 then
        return 1
    end
    return scale
end

function BarFrame.ApplyPosition(frame)
    local settings = getSettings()
    if not settings then
        return
    end
    local x = settings.Get("bar.position_x") or 0
    local y = settings.Get("bar.position_y") or 200
    local scale = currentFrameScale(frame)
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", UIParent, "CENTER", x / scale, y / scale)
end

function BarFrame.SavePosition(frame)
    local settings = getSettings()
    if not settings then
        return
    end

    local frameCenterX, frameCenterY = frame:GetCenter()
    local parentCenterX, parentCenterY = UIParent:GetCenter()
    if not (frameCenterX and parentCenterX) then
        return
    end

    -- Absolute (UIParent-space) position -- what actually gets persisted.
    local x = frameCenterX - parentCenterX
    local y = frameCenterY - parentCenterY

    local scale = currentFrameScale(frame)
    local width, height = frame:GetSize()
    local visualWidth, visualHeight = width * scale, height * scale
    local screenWidth, screenHeight = UIParent:GetSize()
    if screenWidth and screenHeight then
        local halfWidth = (screenWidth / 2) - (visualWidth / 2) - DRAG_SCREEN_MARGIN
        local halfHeight = (screenHeight / 2) - (visualHeight / 2) - DRAG_SCREEN_MARGIN
        if halfWidth > 0 then
            x = math.max(-halfWidth, math.min(halfWidth, x))
        end
        if halfHeight > 0 then
            y = math.max(-halfHeight, math.min(halfHeight, y))
        end
    end

    settings.Set("bar.position_x", x)
    settings.Set("bar.position_y", y)
    BarFrame.ApplyPosition(frame)
end

-- The Section 5.8 "Reset Bar Position" action; exposed now so UI/SettingsPanel
-- can wire a button to it once it exists.
function BarFrame.ResetPosition()
    local settings = getSettings()
    if not settings then
        return
    end
    local defaults = settings.GetDefaults()
    local defaultX = (defaults.bar and defaults.bar.position_x) or 0
    local defaultY = (defaults.bar and defaults.bar.position_y) or 200
    settings.Set("bar.position_x", defaultX)
    settings.Set("bar.position_y", defaultY)
    if barFrame then
        BarFrame.ApplyPosition(barFrame)
    end
end

function BarFrame.EnsureBar()
    if barFrame then
        return barFrame
    end

    local frame = CreateFrame("Frame", "PreydatorBarFrame", UIParent, "BackdropTemplate")
    frame:SetFrameStrata("MEDIUM")
    frame:SetFrameLevel(5)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")

    frame.background = frame:CreateTexture(nil, "BACKGROUND")
    frame.background:SetPoint("TOPLEFT", FILL_INSET, -FILL_INSET)
    frame.background:SetPoint("BOTTOMRIGHT", -FILL_INSET, FILL_INSET)

    frame.fill = frame:CreateTexture(nil, "ARTWORK")
    frame.fill:SetHorizTile(false)
    frame.fill:SetVertTile(false)

    frame.border = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    frame.border:SetAllPoints(frame)
    frame.border:SetFrameLevel(frame:GetFrameLevel() + 1)
    frame.border:SetBackdrop({
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 12,
    })

    frame.ticks = {}
    frame.tickLabels = {}
    for i = 1, MAX_TICKS do
        frame.ticks[i] = frame:CreateTexture(nil, "OVERLAY", nil, 4)
        frame.tickLabels[i] = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    end

    frame.prefixText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.suffixText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.percentText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")

    frame:SetScript("OnDragStart", function(self)
        self.isDragging = true
        self:StartMoving()
    end)
    frame:SetScript("OnDragStop", function(self)
        self.isDragging = false
        self:StopMovingOrSizing()
        BarFrame.SavePosition(self)
    end)

    barFrame = frame
    return frame
end

function BarFrame.Render(viewModel)
    local settings = getSettings()
    if not settings then
        return
    end
    viewModel = viewModel or {}

    local frame = BarFrame.EnsureBar()
    local orientation = settings.Get("bar.orientation") or "horizontal"
    local width, height, scale = resolveDimensions(orientation, settings)

    frame:SetSize(width, height)
    frame:SetScale(scale)
    -- Re-anchor every render, not just on drag/creation: SetPoint's stored
    -- offset is re-resolved against the frame's CURRENT scale continuously,
    -- so a scale change alone (no drag) would otherwise visibly shift the
    -- bar even though the stored absolute position never changed. Skipped
    -- mid-drag -- StartMoving() already has the frame correctly tracking the
    -- mouse, and a State/Settings change firing during the drag (routine in
    -- the ~60s after login while the quest log/zone events settle) would
    -- otherwise yank the frame back to its last-saved position every time it
    -- re-renders, fighting the mouse and producing exactly the "bounces
    -- around while dragging, but only right after login" bug this comment
    -- is here to prevent someone re-introducing.
    if not frame.isDragging then
        BarFrame.ApplyPosition(frame)
    end

    applyBackgroundAndBorder(frame, settings)
    applyFillTexture(frame, settings)
    applyFill(frame, viewModel, settings, orientation)
    applyTicks(frame, viewModel, settings, orientation)
    applyFonts(frame, settings, scale)
    applyLabelText(frame, viewModel, settings, orientation)
    applyPercentText(frame, viewModel, settings, orientation)
    applyVisibilityAndMouse(frame, viewModel, settings)
end

function BarFrame.RequestRender()
    local barRuntime = Preydator:GetModule("BarRuntime")
    if not barRuntime then
        return
    end
    BarFrame.Render(barRuntime.ComputeBarViewModel())
end

do
    local State = Preydator:GetModule("State")
    local Settings = Preydator:GetModule("Settings")
    if State then
        State.Subscribe(BarFrame.RequestRender)
    end
    if Settings then
        Settings.Subscribe(BarFrame.RequestRender)
    end

    -- Event-driven, not polled: hooks Blizzard's own show/hide scripts once,
    -- instead of re-checking EditModeManagerFrame:IsShown() on every render
    -- pass the way the old code did in three separate places. If
    -- Blizzard_EditMode hasn't loaded yet at this point, the bar simply won't
    -- force-show during Edit Mode until the next reload -- a minor known gap,
    -- not a crash risk (guarded, no error).
    local editModeFrame = _G.EditModeManagerFrame
    if editModeFrame and editModeFrame.HookScript then
        editModeFrame:HookScript("OnShow", BarFrame.RequestRender)
        editModeFrame:HookScript("OnHide", BarFrame.RequestRender)
    end

    -- SavedVariables (and therefore every Settings.Get value) aren't
    -- populated until after this addon's files finish loading, right before
    -- ADDON_LOADED fires -- calling RequestRender synchronously here, at
    -- file-load time, would read (and Core/Settings.lua's cache would
    -- permanently keep) default values instead of the real saved profile.
    -- Defer the first real render to PLAYER_LOGIN, which is guaranteed to
    -- fire only after every addon's files and SavedVariables have loaded.
    local initFrame = CreateFrame("Frame")
    initFrame:RegisterEvent("PLAYER_LOGIN")
    initFrame:SetScript("OnEvent", function(self)
        self:UnregisterEvent("PLAYER_LOGIN")
        BarFrame.RequestRender()
    end)
end

Preydator:RegisterModule("BarFrame", BarFrame)
return BarFrame
