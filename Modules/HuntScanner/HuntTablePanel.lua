-- Preydator :: Modules/HuntScanner/HuntTablePanel.lua
-- Author: RagingAltoholic
-- Responsibility: renders HuntScannerRuntime.GetHuntList() as the hunt panel.
-- Row layout: icon/name/zone/reward icons/Accept, plus an achievement badge
-- (icon + still-needed count, hover for names) docked directly above the
-- Accept button -- that space sits empty otherwise (2026-09-01, product
-- owner). Reward icons show icon+quantity only (full name+quantity via hover
-- tooltip, see MAX_REWARD_ICONS' comment) -- grouping/sort UI remains
-- Full-scope (architecture doc Section 15 MVP table), not built here. Only
-- the Accept button and the reward/achievement tooltips are interactive --
-- the rest of each row is display-only. Never reads State directly and never
-- decides gameplay truth -- consumes HuntScannerRuntime's already-resolved
-- hunt list (including its reward and achievement-needs data) and reads
-- Settings for presentation only (panel side/size/scale), same split as
-- UI/BarFrame.lua.
-- Reads: Modules/HuntScanner/HuntScannerRuntime.lua, Core/Settings.lua,
-- Core/Adapters/MapContextAdapter.lua (zone name lookup only).
-- Writes: nothing (Accept forwards straight to HuntScannerRuntime.SelectHunt,
-- which already owns accepting a hunt).

local Preydator = _G.Preydator
local CreateFrame = _G.CreateFrame
local UIParent = _G.UIParent

local HuntTablePanel = {}

-- Bumped from 20: hunt.group_by can insert up to 3 extra header rows
-- (difficulty/zone buckets) alongside the real hunts.
local MAX_ROWS = 24
local ROW_HEIGHT = 56
-- Group header rows (hunt.group_by, Decisions Log item 48) are shorter than
-- a real hunt row -- just a clickable collapse/expand label, no icon/reward/
-- accept content.
local GROUP_HEADER_HEIGHT = 24
-- Bumped from 40: the source art is a detailed painted skull (glows,
-- gradients), not flat vector art, so it inherently reads softer than a
-- crisp icon at small sizes -- more display size (still within ROW_HEIGHT)
-- reduces how much that shows without changing the crop.
local ICON_SIZE = 48
local ROW_SPACING = 4

-- Three separate, pre-cropped files (2026-08-27) replace the original
-- shared-sheet-plus-texcoord approach -- that needed two rounds of
-- eyeballed-crop correction (full-height thirds squished the art; a tighter
-- manual crop still wasn't pixel-exact) to get right. Separate files
-- sidestep that entirely: each is already sized/cropped consistently, no
-- texcoord math needed here at all.
local DIFFICULTY_ICON_PATHS = {
    normal = "Interface\\AddOns\\Preydator\\media\\Preydator_Normal_Difficulty.png",
    hard = "Interface\\AddOns\\Preydator\\media\\Preydator_Hard_Difficulty.png",
    nightmare = "Interface\\AddOns\\Preydator\\media\\Preydator_Nightmare_Difficulty.png",
}

-- Reward row: icon + quantity only, per the product owner's own established
-- usage (2026-08-28) -- full names are too long to fit inline even under the
-- "icon + text" style, so the name only ever appears via the hover tooltip.
-- Bumped from 4 (2026-09-02): confirmed live that Nightmare hunts have 5
-- distinct rewards, and the 4-slot cap silently truncated the 5th --
-- specifically the chest/bag reward, since it always sorts last
-- (namedRewardPriority). +1 past the currently-known maximum for headroom.
local MAX_REWARD_ICONS = 6
local REWARD_ICON_SIZE = 16
-- Wide enough for icon + up to a 5-digit quantity ("10000") beside it, not
-- overlapping it -- the first layout badged the quantity over the icon's
-- bottom-right corner, which only works for single-digit counts and covered
-- the icon entirely for real reward amounts (found live, 2026-08-28).
local REWARD_SLOT_WIDTH = 48
local REWARD_SLOT_SPACING = 6

-- Confirmed live (2026-09-03): below this width the reward-icon row (up to
-- MAX_REWARD_ICONS wide) has nowhere to go but visually under the Accept
-- button and achievement badge, since neither is aware of the other's
-- width. Started at 420 (theoretical worst-case math), tuned down twice
-- after the product owner eyeballed it live -- 270, then settled at 330.
-- UI/SettingsPanel.lua's hunt.width slider floors at this same value, but
-- that alone doesn't protect someone with an already-saved smaller value
-- (the slider's min only stops new drags below it) -- this is the actual
-- render-time floor that does.
local MIN_SAFE_PANEL_WIDTH = 330
-- INV_Misc_QuestionMark -- generic placeholder for a bonus item/container
-- reward whose specific icon/name isn't resolvable until the hunt is
-- accepted (confirmed live, 2026-08-28: Blizzard doesn't expose item-reward
-- detail for these quests pre-accept, only currency/money/XP do resolve
-- that early -- see QuestApiAdapter.GetQuestRewardSummary's comment). Also
-- fitting since a mystery-reward chest's contents genuinely aren't known
-- until it's opened after completing the quest.
local MYSTERY_REWARD_ICON = 134400

-- Achievement badge: icon + still-needed count, docked directly above the
-- Accept button -- the same empty space the old codebase used for this
-- exact purpose (product owner, 2026-09-01). Only the "icon_count" style is
-- implemented (the only value SettingsRuntime currently allows for
-- hunt.achievement_signal_style); icon_only/count_only aren't built since
-- nothing offers them yet.
local ACHIEVEMENT_BADGE_ICON = "Interface\\AchievementFrame\\UI-Achievement-TinyShield"
local ACHIEVEMENT_ANCHOR_HEIGHT = 20
-- Doubled from 16 per the product owner's request (2026-09-01) -- the count
-- text stays at its normal font size, only the icon itself is bigger. The
-- anchor frame itself stays ACHIEVEMENT_ANCHOR_HEIGHT tall; the icon simply
-- extends past it symmetrically (a Texture isn't clipped by its parent
-- frame's bounds), using the same free space above the Accept button.
local ACHIEVEMENT_ICON_SIZE = 32

local panel = nil
local rows = {}

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

-- Used only when hunt.preview_enabled is on and there's no real cached hunt
-- list to show -- mapID 2561 (The Coiled Isle) is a real, currently-valid
-- zone so the preview's zone text resolves to something real instead of
-- blank. Built lazily (not a file-scope table) since L() reads
-- LocalizationAdapter, matching this file's other deferred-read precautions.
-- Real icon texture IDs from a live-tested hunt (2026-08-28) -- lets the
-- preview also demonstrate the reward icon row (icon + quantity, hover for
-- name), including the mystery-reward slot, without needing a real hunt.
local function buildPreviewRewardEntries()
    return {
        { icon = "7734062", iconIsAtlas = false, quantity = "10", name = L("Preview Reward") .. " A" },
        { icon = "7493985", iconIsAtlas = false, quantity = "1000", name = L("Preview Reward") .. " B" },
        { icon = "133016", iconIsAtlas = false, quantity = "50", name = L("Preview Reward") .. " C" },
    }
end

-- One placeholder need per preview row so the achievement badge is visible
-- while tuning its settings, same reasoning as buildPreviewRewardEntries.
local function buildPreviewAchievementNeeds()
    return { { achievementID = -1, name = L("Preview Achievement") } }
end

local function buildPreviewHunts()
    return {
        { questID = -1, title = L("Preview Hunt (Normal)"), zoneMapID = 2561, difficulty = "normal",
            rewardEntries = buildPreviewRewardEntries(), hasBonusItemReward = true,
            achievementNeeds = buildPreviewAchievementNeeds() },
        { questID = -2, title = L("Preview Hunt (Hard)"), zoneMapID = 2561, difficulty = "hard",
            rewardEntries = buildPreviewRewardEntries(), hasBonusItemReward = true,
            achievementNeeds = buildPreviewAchievementNeeds() },
        { questID = -3, title = L("Preview Hunt (Nightmare)"), zoneMapID = 2561, difficulty = "nightmare",
            rewardEntries = buildPreviewRewardEntries(), hasBonusItemReward = true,
            achievementNeeds = buildPreviewAchievementNeeds() },
    }
end

-- Delegates to HuntScannerRuntime.ResolveZoneDisplayName (single source of
-- truth for zone display names, including the display-only overrides table
-- there -- e.g. mapID 2561 shows as "The Coiled Isle," not Blizzard's own
-- "Quel'Thalas") rather than querying MapContextAdapter directly, so this
-- panel and HuntScannerRuntime's own zone-based sorting/grouping never see
-- two different names for the same mapID.
local function resolveZoneName(mapID)
    local huntScanner = Preydator:GetModule("HuntScannerRuntime")
    return (huntScanner and huntScanner.ResolveZoneDisplayName(mapID)) or ""
end

-- Row position/height are no longer fixed at creation time -- Render() sets
-- both every pass, since a group header row is shorter than a real hunt row
-- and which rows are headers changes with the live data/settings.
local function createRow(scrollChild)
    local row = CreateFrame("Frame", nil, scrollChild, "BackdropTemplate")
    row:SetPoint("RIGHT", scrollChild, "RIGHT", 0, 0)
    row:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
    row:SetBackdropColor(0, 0, 0, 0.25)

    -- Group header content -- see applyGroupHeaderRow. Everything else
    -- created below is the real-hunt-row content (applyRow).
    row.groupHeaderText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.groupHeaderText:SetPoint("LEFT", row, "LEFT", ROW_SPACING, 0)
    row.groupHeaderText:SetPoint("RIGHT", row, "RIGHT", -ROW_SPACING, 0)
    row.groupHeaderText:SetJustifyH("LEFT")
    row.groupHeaderText:Hide()

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(ICON_SIZE, ICON_SIZE)
    row.icon:SetPoint("LEFT", row, "LEFT", ROW_SPACING, 0)

    row.nameText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.nameText:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 8, -2)
    row.nameText:SetPoint("RIGHT", row, "RIGHT", -ROW_SPACING, 0)
    row.nameText:SetJustifyH("LEFT")

    row.zoneText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.zoneText:SetPoint("TOPLEFT", row.nameText, "BOTTOMLEFT", 0, -2)
    row.zoneText:SetPoint("RIGHT", row, "RIGHT", -ROW_SPACING, 0)
    row.zoneText:SetJustifyH("LEFT")

    row.acceptButton = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    row.acceptButton:SetSize(80, 20)
    row.acceptButton:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -ROW_SPACING, ROW_SPACING)
    row.acceptButton:SetText(L("Accept"))

    -- Achievement badge -- docked in the space directly above the Accept
    -- button (see ACHIEVEMENT_BADGE_ICON's comment). Hidden by default;
    -- applyAchievementBadge shows it only when there's at least one
    -- still-needed achievement to report.
    row.achievementAnchor = CreateFrame("Frame", nil, row)
    row.achievementAnchor:SetHeight(ACHIEVEMENT_ANCHOR_HEIGHT)
    row.achievementAnchor:SetPoint("BOTTOMLEFT", row.acceptButton, "TOPLEFT", 0, 2)
    row.achievementAnchor:SetPoint("BOTTOMRIGHT", row.acceptButton, "TOPRIGHT", 0, 2)
    row.achievementAnchor:EnableMouse(true)

    -- Count-in-row text removed (2026-09-01, product owner) -- the icon
    -- alone is the visible signal; the count and names only ever appear on
    -- hover now.
    row.achievementIcon = row.achievementAnchor:CreateTexture(nil, "ARTWORK")
    row.achievementIcon:SetTexture(ACHIEVEMENT_BADGE_ICON)
    row.achievementIcon:SetSize(ACHIEVEMENT_ICON_SIZE, ACHIEVEMENT_ICON_SIZE)
    row.achievementIcon:SetPoint("RIGHT", row.achievementAnchor, "RIGHT", 0, 0)
    row.achievementIcon:Hide()

    row.achievementAnchor:SetScript("OnEnter", function(self)
        if not self.tooltipLines or #self.tooltipLines == 0 then
            return
        end
        _G.GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        _G.GameTooltip:SetText(L("Achievements Needed") .. " (" .. #self.tooltipLines .. ")", 1, 1, 1)
        for _, line in ipairs(self.tooltipLines) do
            _G.GameTooltip:AddLine(line, 0.85, 0.85, 0.85, true)
        end
        _G.GameTooltip:Show()
    end)
    row.achievementAnchor:SetScript("OnLeave", function()
        _G.GameTooltip:Hide()
    end)

    -- Icon + quantity only (see MAX_REWARD_ICONS' comment); full name/quantity
    -- shown via GameTooltip on hover instead of trying to fit inline.
    row.rewardIcons = {}
    local previousRewardIcon = nil
    for i = 1, MAX_REWARD_ICONS do
        local rewardIcon = CreateFrame("Button", nil, row)
        rewardIcon:SetSize(REWARD_SLOT_WIDTH, REWARD_ICON_SIZE)
        if previousRewardIcon then
            rewardIcon:SetPoint("LEFT", previousRewardIcon, "RIGHT", REWARD_SLOT_SPACING, 0)
        else
            rewardIcon:SetPoint("BOTTOMLEFT", row.icon, "BOTTOMRIGHT", 8, 0)
        end

        rewardIcon.texture = rewardIcon:CreateTexture(nil, "ARTWORK")
        rewardIcon.texture:SetSize(REWARD_ICON_SIZE, REWARD_ICON_SIZE)
        rewardIcon.texture:SetPoint("LEFT", rewardIcon, "LEFT", 0, 0)

        rewardIcon.qtyText = rewardIcon:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
        rewardIcon.qtyText:SetPoint("LEFT", rewardIcon.texture, "RIGHT", 3, 0)
        rewardIcon.qtyText:SetJustifyH("LEFT")

        rewardIcon:SetScript("OnEnter", function(self)
            if not self.tooltipName then
                return
            end
            _G.GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            _G.GameTooltip:SetText(self.tooltipName, 1, 1, 1)
            if self.tooltipQuantity then
                _G.GameTooltip:AddLine(L("Quantity") .. ": " .. self.tooltipQuantity, 0.85, 0.85, 0.85)
            end
            _G.GameTooltip:Show()
        end)
        rewardIcon:SetScript("OnLeave", function()
            _G.GameTooltip:Hide()
        end)

        rewardIcon:Hide()
        row.rewardIcons[i] = rewardIcon
        previousRewardIcon = rewardIcon
    end

    return row
end

-- Builds the display list for applyRow's reward icons: the parsed
-- currency/money/XP entries, plus one generic mystery-reward entry appended
-- if hasBonusItemReward is true (see MYSTERY_REWARD_ICON's comment).
local function buildRewardDisplayEntries(hunt)
    local entries = {}
    for _, entry in ipairs(hunt.rewardEntries or {}) do
        entries[#entries + 1] = entry
    end
    if hunt.hasBonusItemReward then
        entries[#entries + 1] = {
            icon = MYSTERY_REWARD_ICON,
            iconIsAtlas = false,
            quantity = nil,
            name = L("Bonus item reward (revealed after accepting)"),
        }
    end
    return entries
end

-- showQuantity=false (icon_inline, the more compact default) shows just the
-- icons -- the quantity number only appears on hover (tooltipQuantity is
-- always set either way). showQuantity=true (icon_count) shows icon PLUS
-- the quantity number inline, still repeated on hover.
local function applyRewardIcons(row, hunt, showQuantity)
    local displayEntries = buildRewardDisplayEntries(hunt)

    for i = 1, MAX_REWARD_ICONS do
        local rewardIcon = row.rewardIcons[i]
        local entry = displayEntries[i]
        if entry then
            local okSet = pcall(function()
                if entry.iconIsAtlas and entry.icon then
                    rewardIcon.texture:SetAtlas(entry.icon)
                elseif entry.icon then
                    rewardIcon.texture:SetTexture(tonumber(entry.icon) or entry.icon)
                else
                    rewardIcon.texture:SetTexture(nil)
                end
            end)
            if not okSet then
                rewardIcon.texture:SetTexture(nil)
            end

            local quantityText = showQuantity and entry.quantity or nil
            rewardIcon.qtyText:SetText(quantityText or "")
            rewardIcon.tooltipName = entry.name
            rewardIcon.tooltipQuantity = entry.quantity

            -- Sized to fit this entry's own quantity text, not a blanket
            -- fixed width for every slot -- the old codebase's reward
            -- display packed icon+quantity into ordinary text flow (tight,
            -- proportional spacing); a fixed-width slot left a large gap
            -- for short quantities like "10" (found live, 2026-08-28).
            local textWidth = rewardIcon.qtyText:GetStringWidth() or 0
            rewardIcon:SetWidth(REWARD_ICON_SIZE + (quantityText and (3 + textWidth) or 0))
            rewardIcon:Show()
        else
            rewardIcon:Hide()
        end
    end
end


-- Icon-only badge (2026-09-01, product owner: dropped the in-row count text)
-- -- shows just the icon when HuntScannerRuntime reports at least one
-- incomplete achievement for this hunt, hidden otherwise. The count and the
-- still-needed achievement names are hover-only (GameTooltip), same pattern
-- as the reward icons.
local function applyAchievementBadge(row, hunt)
    local settings = getSettings()
    local enabled = settings and settings.Get("hunt.achievement_signals_enabled") ~= false
    local needs = enabled and hunt.achievementNeeds or nil

    if not needs or #needs == 0 then
        row.achievementIcon:Hide()
        row.achievementAnchor.tooltipLines = nil
        return
    end

    row.achievementIcon:Show()

    local lines = {}
    for _, need in ipairs(needs) do
        lines[#lines + 1] = need.name
    end
    row.achievementAnchor.tooltipLines = lines
end

local function applyRow(row, hunt)
    -- Undo anything a prior render pass left set while this row frame was
    -- being reused as a group header (rows are recycled across renders).
    row.groupHeaderText:Hide()
    row:EnableMouse(false)
    row:SetScript("OnMouseUp", nil)
    row.icon:Show()
    row.nameText:Show()
    row.zoneText:Show()
    row.acceptButton:Show()

    row.icon:SetTexture(DIFFICULTY_ICON_PATHS[hunt.difficulty] or DIFFICULTY_ICON_PATHS.normal)
    row.nameText:SetText(hunt.title or "")
    row.zoneText:SetText(resolveZoneName(hunt.zoneMapID))

    -- hunt.reward_display_style (corrected 2026-09-02 -- the two were
    -- swapped from what their names say): icon_inline (default) is icons
    -- only, no quantity number in the row -- hover for it; icon_count is
    -- icon PLUS the quantity number shown inline, and hover still shows it
    -- again (tooltipQuantity is always set regardless, see
    -- applyRewardIcons). "text_only" existed briefly (2026-09-02) but was
    -- removed the same day: live testing showed a plain comma-separated
    -- line wasn't a viable look for this row.
    local settings = getSettings()
    local rewardStyle = settings and settings.Get("hunt.reward_display_style") or "icon_inline"
    applyRewardIcons(row, hunt, rewardStyle == "icon_count")

    applyAchievementBadge(row, hunt)

    local questID = hunt.questID
    row.acceptButton:SetScript("OnClick", function()
        local huntScanner = Preydator:GetModule("HuntScannerRuntime")
        if huntScanner then
            huntScanner.SelectHunt(questID)
        end
    end)

    row:Show()
end

-- Group header row (hunt.group_by) -- a clickable label toggling
-- HuntScannerRuntime.ToggleGroupCollapsed via Settings (never mutates
-- state directly, per architecture doc Section 3). Hides every piece of
-- real-hunt-row content; applyRow restores it all if this same row frame
-- gets reused for a real hunt on a later render.
local function applyGroupHeaderRow(row, entry)
    row.icon:Hide()
    row.nameText:Hide()
    row.zoneText:Hide()
    row.acceptButton:Hide()
    for i = 1, MAX_REWARD_ICONS do
        row.rewardIcons[i]:Hide()
    end
    row.achievementIcon:Hide()

    local labelPrefix = (entry.groupBy == "zone") and (L("Zone") .. ": ") or (L("Difficulty") .. ": ")
    row.groupHeaderText:SetText((entry.collapsed and "+ " or "- ") .. labelPrefix .. tostring(entry.groupLabel or ""))
    row.groupHeaderText:Show()

    row:EnableMouse(true)
    local groupKey = entry.groupKey
    row:SetScript("OnMouseUp", function(_, button)
        if button ~= "LeftButton" then
            return
        end
        local huntScanner = Preydator:GetModule("HuntScannerRuntime")
        if huntScanner and type(huntScanner.ToggleGroupCollapsed) == "function" then
            huntScanner.ToggleGroupCollapsed(groupKey)
        end
    end)

    row:Show()
end

local function ensurePanel()
    if panel then
        return panel
    end

    panel = CreateFrame("Frame", "PreydatorHuntTablePanel", UIParent, "BackdropTemplate")
    panel:SetFrameStrata("MEDIUM")
    panel:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 12,
    })
    panel:SetBackdropColor(0, 0, 0, 0.75)

    panel.title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    panel.title:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, -10)
    panel.title:SetText(L("Prey Hunts"))

    -- Group/sort/direction controls directly on the panel (2026-09-01,
    -- product owner: shouldn't need Settings open just to change these).
    -- Same cycle-through-on-click design as the old codebase's Group/Sort
    -- buttons, extended with a third button for sort direction (the old
    -- panel only exposed that one via Settings). All three read/write the
    -- same hunt.group_by/sort_by/sort_direction settings HuntScannerRuntime
    -- already uses, so they stay in sync with the Settings UI automatically
    -- (Settings.Subscribe already re-renders this panel on any change).
    panel.groupButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    panel.groupButton:SetHeight(20)
    panel.groupButton:SetPoint("TOPLEFT", panel, "TOPLEFT", 8, -32)
    panel.groupButton:SetScript("OnClick", function()
        local settings = getSettings()
        if not settings then
            return
        end
        local order = { "none", "difficulty", "zone" }
        local current = settings.Get("hunt.group_by") or "difficulty"
        local nextIndex = 1
        for index, key in ipairs(order) do
            if current == key then
                nextIndex = (index % #order) + 1
                break
            end
        end
        settings.Set("hunt.group_by", order[nextIndex])
    end)

    panel.sortButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    panel.sortButton:SetHeight(20)
    panel.sortButton:SetPoint("LEFT", panel.groupButton, "RIGHT", 4, 0)
    panel.sortButton:SetScript("OnClick", function()
        local settings = getSettings()
        if not settings then
            return
        end
        local order = { "difficulty", "zone", "title" }
        local current = settings.Get("hunt.sort_by") or "zone"
        local nextIndex = 1
        for index, key in ipairs(order) do
            if current == key then
                nextIndex = (index % #order) + 1
                break
            end
        end
        settings.Set("hunt.sort_by", order[nextIndex])
    end)

    panel.sortDirButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    panel.sortDirButton:SetSize(28, 20)
    panel.sortDirButton:SetPoint("LEFT", panel.sortButton, "RIGHT", 4, 0)
    panel.sortDirButton:SetScript("OnClick", function()
        local settings = getSettings()
        if not settings then
            return
        end
        local current = settings.Get("hunt.sort_direction") or "asc"
        settings.Set("hunt.sort_direction", (current == "asc") and "desc" or "asc")
    end)

    panel.scrollFrame = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
    panel.scrollFrame:SetPoint("TOPLEFT", panel, "TOPLEFT", 8, -58)
    panel.scrollFrame:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -28, 10)

    panel.scrollChild = CreateFrame("Frame", nil, panel.scrollFrame)
    panel.scrollChild:SetSize(1, 1)
    panel.scrollFrame:SetScrollChild(panel.scrollChild)
    panel.scrollFrame:SetScript("OnSizeChanged", function(_, width)
        panel.scrollChild:SetWidth(width)
    end)

    for i = 1, MAX_ROWS do
        rows[i] = createRow(panel.scrollChild)
        rows[i]:Hide()
    end

    return panel
end

-- Docks beside Blizzard's own Hunt Table frame (the Adventure Map / Covenant
-- Mission frame the pins live on) when it's shown -- that's the frame
-- actually on screen when hunts are being offered, so anchoring to it keeps
-- the panel next to the UI the player is already looking at. While
-- hunt.preview_enabled is on and the Settings window is open instead (no
-- real Hunt Table to dock to), docks beside Settings -- found via live
-- testing (2026-08-28) that falling all the way back to a screen edge while
-- fine-tuning sliders in Settings could land the preview somewhere another
-- addon's UI already occupies. Falls back to a screen edge only when
-- neither frame is shown.
local function applyPanelPosition(settings, previewEnabled)
    local side = settings.Get("hunt.panel_side") or "right"
    local missionFrame = _G.CovenantMissionFrame
    local settingsFrame = _G.SettingsPanel
    panel:ClearAllPoints()

    if missionFrame and missionFrame.IsShown and missionFrame:IsShown() then
        if side == "left" then
            panel:SetPoint("TOPRIGHT", missionFrame, "TOPLEFT", -8, 0)
        else
            panel:SetPoint("TOPLEFT", missionFrame, "TOPRIGHT", 8, 0)
        end
    elseif previewEnabled and settingsFrame and settingsFrame.IsShown and settingsFrame:IsShown() then
        if side == "left" then
            panel:SetPoint("TOPRIGHT", settingsFrame, "TOPLEFT", -8, 0)
        else
            panel:SetPoint("TOPLEFT", settingsFrame, "TOPRIGHT", 8, 0)
        end
    elseif side == "left" then
        panel:SetPoint("LEFT", UIParent, "LEFT", 20, 0)
    else
        panel:SetPoint("RIGHT", UIParent, "RIGHT", -20, 0)
    end
end

-- Refreshes the group/sort/direction button labels from live Settings --
-- called every render so a change made from either this panel or the
-- Settings UI (both write through the same hunt.group_by/sort_by/
-- sort_direction keys) is always reflected here, not just where it was made.
local function updateHeaderControls(settings)
    local groupLabels = { none = L("None"), difficulty = L("Difficulty"), zone = L("Zone") }
    local sortLabels = { difficulty = L("Difficulty"), zone = L("Zone"), title = L("Title") }

    local groupBy = settings.Get("hunt.group_by") or "difficulty"
    local sortBy = settings.Get("hunt.sort_by") or "zone"
    local descending = settings.Get("hunt.sort_direction") == "desc"

    panel.groupButton:SetText(L("Group") .. ": " .. (groupLabels[groupBy] or groupBy))
    panel.groupButton:SetWidth(math.max(70, panel.groupButton:GetFontString():GetStringWidth() + 20))

    panel.sortButton:SetText(L("Sort") .. ": " .. (sortLabels[sortBy] or sortBy))
    panel.sortButton:SetWidth(math.max(60, panel.sortButton:GetFontString():GetStringWidth() + 20))

    panel.sortDirButton:SetText(descending and "v" or "^")
end

function HuntTablePanel.Render(huntList)
    local settings = getSettings()
    if not settings then
        return
    end
    huntList = huntList or {}

    -- hunt.preview_enabled bypasses every gate below -- it's a Settings-only
    -- visual aid (see UI/SettingsPanel.lua's Hunt Scanner category) for
    -- checking layout/scale/font changes without leaving Settings or being
    -- at a real Hunt Table. Uses the real cached list if one exists so it
    -- reflects actual data; falls back to buildPreviewHunts() otherwise.
    -- Routed through the same grouping/sorting as the real panel (2026-09-03,
    -- product owner) -- previously stayed deliberately flat, but that meant
    -- the preview couldn't actually be used to check group-header layout.
    local previewEnabled = settings.Get("hunt.preview_enabled") == true
    local displayList
    if previewEnabled then
        local huntScanner = Preydator:GetModule("HuntScannerRuntime")
        local baseList = (#huntList > 0) and huntList or buildPreviewHunts()
        displayList = (huntScanner and huntScanner.GetGroupedDisplayList(baseList)) or baseList
    else
        -- Sorted/grouped fresh every render (hunt.group_by/sort_by/
        -- sort_direction/collapsed_groups can all change independently of
        -- the hunt list itself) -- HuntScannerRuntime.lua is the sole owner
        -- of this logic (architecture doc Section 3), this file only renders
        -- whatever it returns.
        local huntScanner = Preydator:GetModule("HuntScannerRuntime")
        displayList = (huntScanner and huntScanner.GetGroupedDisplayList()) or huntList
    end

    local huntEnabled = settings.Get("general.hunt_enabled") ~= false and settings.Get("hunt.enabled") ~= false

    -- Direct gate, not just "is the list empty": the product owner's
    -- requirement is the panel is ONLY ever visible while the Hunt Table is
    -- actually active. Relying solely on the list going back to empty is
    -- fragile against any remaining rescan-timing edge case (a stale,
    -- non-empty list briefly surviving a close would otherwise still show
    -- the panel) -- this check is independent of list content entirely.
    local adapter = Preydator:GetModule("HuntTableAdapter")
    local tableActive = adapter and type(adapter.IsHuntTableActive) == "function" and adapter.IsHuntTableActive()

    if not previewEnabled and (not huntEnabled or not tableActive or #huntList == 0) then
        if panel then
            panel:Hide()
        end
        return
    end

    local frame = ensurePanel()
    updateHeaderControls(settings)
    -- Floored regardless of what's stored -- protects anyone with an
    -- already-saved value from before the slider's own min was raised (see
    -- MIN_SAFE_PANEL_WIDTH's comment), without needing a data migration.
    local width = math.max(MIN_SAFE_PANEL_WIDTH, settings.Get("hunt.width") or MIN_SAFE_PANEL_WIDTH)
    local height = settings.Get("hunt.height") or 460
    local scale = settings.Get("hunt.scale") or 1.0
    frame:SetSize(width, height)
    frame:SetScale(scale)
    applyPanelPosition(settings, previewEnabled)

    -- Variable row height (group headers are shorter than real hunt rows,
    -- see GROUP_HEADER_HEIGHT) means each row's Y position is an accumulated
    -- offset now, not a fixed index*ROW_HEIGHT.
    local fontSize = settings.Get("hunt.font_size") or 12
    local yOffset = 0
    for i = 1, MAX_ROWS do
        local entry = displayList[i]
        local row = rows[i]
        if entry then
            local isHeader = entry.isGroupHeader == true
            local rowHeight = isHeader and GROUP_HEADER_HEIGHT or ROW_HEIGHT
            row:SetHeight(rowHeight)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", panel.scrollChild, "TOPLEFT", 0, -yOffset)
            row:SetPoint("RIGHT", panel.scrollChild, "RIGHT", 0, 0)
            yOffset = yOffset + rowHeight

            if isHeader then
                applyGroupHeaderRow(row, entry)
            else
                local nameFont, _, nameFlags = row.nameText:GetFont()
                row.nameText:SetFont(nameFont, fontSize, nameFlags)
                local zoneFont, _, zoneFlags = row.zoneText:GetFont()
                row.zoneText:SetFont(zoneFont, math.max(8, fontSize - 2), zoneFlags)
                applyRow(row, entry)
            end
        else
            row:Hide()
        end
    end

    panel.scrollChild:SetHeight(math.max(1, yOffset))
    frame:Show()
end

function HuntTablePanel.RequestRender()
    local huntScanner = Preydator:GetModule("HuntScannerRuntime")
    if not huntScanner then
        return
    end
    HuntTablePanel.Render(huntScanner.GetHuntList())
end

do
    local huntScanner = Preydator:GetModule("HuntScannerRuntime")
    local Settings = getSettings()
    if huntScanner then
        huntScanner.Subscribe(function(huntList)
            HuntTablePanel.Render(huntList)
        end)
    end
    if Settings then
        Settings.Subscribe(HuntTablePanel.RequestRender)
    end

    -- Re-render on Settings opening so hunt.preview_enabled's dock position
    -- (beside Settings, see applyPanelPosition) updates immediately rather
    -- than waiting for the next unrelated Settings.Set/hunt-list change.
    -- On closing, auto-turns preview back off instead of leaving it running
    -- and falling back to the screen-edge dock -- live testing (2026-08-28)
    -- showed that fallback wasn't actually wanted; the preview only makes
    -- sense while Settings is open to compare against. settings.Set already
    -- notifies the Settings.Subscribe above, which re-renders (and hides,
    -- since preview is now off) -- no separate RequestRender() needed in
    -- that branch. Same established, taint-safe hook pattern as
    -- UI/BarFrame.lua's EditModeManagerFrame hook.
    local settingsFrame = _G.SettingsPanel
    if settingsFrame and settingsFrame.HookScript then
        settingsFrame:HookScript("OnShow", HuntTablePanel.RequestRender)
        settingsFrame:HookScript("OnHide", function()
            local settings = getSettings()
            if settings and settings.Get("hunt.preview_enabled") == true then
                settings.Set("hunt.preview_enabled", false)
            else
                HuntTablePanel.RequestRender()
            end
        end)
    end

    -- The "panel stayed empty while the Hunt Table was open" bug's real fix
    -- (a staggered rescan schedule, not a single delayed check) now lives in
    -- Core/Runtime/EventRuntime.lua, where the rest of Hunt Table rescan
    -- timing already lived -- this file doesn't need its own separate
    -- CovenantMissionFrame hook duplicating that concern.

    -- SavedVariables (and therefore every Settings.Get value) aren't
    -- populated until after this addon's files finish loading -- deferring
    -- the first real render to PLAYER_LOGIN, per the standing rule from
    -- architecture doc Decisions Log item 10 (found via UI/BarFrame.lua).
    local initFrame = CreateFrame("Frame")
    initFrame:RegisterEvent("PLAYER_LOGIN")
    initFrame:SetScript("OnEvent", function(self)
        self:UnregisterEvent("PLAYER_LOGIN")
        HuntTablePanel.RequestRender()
    end)
end

Preydator:RegisterModule("HuntTablePanel", HuntTablePanel)
return HuntTablePanel
