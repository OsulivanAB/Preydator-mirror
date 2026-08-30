-- Preydator :: Core/Adapters/WidgetAdapter.lua
-- Author: RagingAltoholic
-- Responsibility: the only file that hooks Blizzard's prey-hunt UIWidget mixin
-- and reads/suppresses the default prey icon. Isolates the taint-sensitive
-- widget-hook code to one file instead of leaking it into bar rendering.
-- Reads: UIWidgetTemplatePreyHuntProgressMixin, UIWidgetPowerBarContainerFrame.
-- Writes: nothing external; tracks its own internal frame/snapshot state.

local Preydator = _G.Preydator
local CreateFrame = _G.CreateFrame
local hooksecurefunc = _G.hooksecurefunc
local InCombatLockdown = _G.InCombatLockdown
local IsAddOnLoaded = _G.IsAddOnLoaded

local WidgetAdapter = {}

-- Weak-keyed so frames can still be garbage-collected if Blizzard tears them down.
local trackedFrames = setmetatable({}, { __mode = "k" })
local suppressedAlpha = setmetatable({}, { __mode = "k" })
local suppressedShown = setmetatable({}, { __mode = "k" })

local iconFrame = nil
local mixinHooked = false
local widgetSnapshot = nil
local desiredSuppression = false
local pendingAfterCombat = false

-- Fields safe to snapshot from widgetInfo. Deliberately excludes widgetID,
-- widgetType, and shownState -- those are secret numbers/protected enums whose
-- mere comparison taints subsequent Blizzard layout code, even inside pcall.
local NUMERIC_SNAPSHOT_KEYS = {
    "progressState", "progressPercentage", "progressPercent",
    "fillPercentage", "percentage", "percent", "progress",
    "barMin", "barMax", "maxValue",
}

local QUEST_ID_FIELDS = { "questID", "questId", "associatedQuestID", "associatedQuestId" }

local function safeToNumber(value)
    local okStr, str = pcall(tostring, value)
    if not okStr or type(str) ~= "string" then
        return nil
    end

    local numericToken = string.match(str, "^%s*([%+%-]?%d+%.?%d*)%s*$")
        or string.match(str, "^%s*([%+%-]?%d*%.%d+)%s*$")
    if not numericToken then
        return nil
    end

    local okNum, num = pcall(tonumber, numericToken)
    if not okNum or type(num) ~= "number" then
        return nil
    end
    return num
end

local function extractQuestID(info)
    if type(info) ~= "table" then
        return nil
    end

    for _, fieldName in ipairs(QUEST_ID_FIELDS) do
        local numericValue = safeToNumber(info[fieldName])
        if numericValue ~= nil and numericValue > 0 then
            return numericValue
        end
    end
    return nil
end

-- ResetAnimState/AnimIn only exist on UIWidgetTemplatePreyHuntProgressMixin
-- frames, so this identifies prey-hunt frames without touching widgetID/widgetType.
local function isPreyHuntProgressFrame(frameRef)
    return frameRef ~= nil
        and type(frameRef.ResetAnimState) == "function"
        and type(frameRef.AnimIn) == "function"
end

local function captureLiveFrames()
    local container = _G.UIWidgetPowerBarContainerFrame
    if not container or not container.GetChildren then
        return
    end

    local ok, children = pcall(function() return { container:GetChildren() } end)
    if not ok or type(children) ~= "table" then
        return
    end

    for _, child in ipairs(children) do
        if isPreyHuntProgressFrame(child) then
            trackedFrames[child] = true
            iconFrame = child
        end
    end
end

local function stopFrameAnimations(frameRef)
    if not frameRef or not frameRef.GetAnimationGroups then
        return
    end

    local ok, groups = pcall(function() return { frameRef:GetAnimationGroups() } end)
    if not ok or type(groups) ~= "table" then
        return
    end

    for _, group in ipairs(groups) do
        if group and group.Stop then
            pcall(group.Stop, group)
        end
    end
end

local function applyFrameSuppression(frameRef, suppress)
    if not frameRef then
        return
    end

    if suppress then
        stopFrameAnimations(frameRef)

        if suppressedShown[frameRef] == nil and frameRef.IsShown then
            suppressedShown[frameRef] = frameRef:IsShown() and true or false
        end
        if suppressedAlpha[frameRef] == nil and frameRef.GetAlpha then
            local ok, alpha = pcall(frameRef.GetAlpha, frameRef)
            if ok and type(alpha) == "number" then
                suppressedAlpha[frameRef] = alpha
            end
        end

        if frameRef.SetAlpha then pcall(frameRef.SetAlpha, frameRef, 0) end
        if frameRef.Hide then pcall(frameRef.Hide, frameRef) end
    else
        local storedAlpha = suppressedAlpha[frameRef]
        if frameRef.SetAlpha then
            pcall(frameRef.SetAlpha, frameRef, storedAlpha or 1)
        end
        suppressedAlpha[frameRef] = nil

        if suppressedShown[frameRef] == true and frameRef.Show then
            pcall(frameRef.Show, frameRef)
        end
        suppressedShown[frameRef] = nil
    end
end

-- Applies (or reverts) suppression across every tracked frame. Must only ever be
-- called from a safe, non-hooked context -- never from inside the Setup hook
-- below. Calling protected frame methods inside a hooksecurefunc callback taints
-- the execution context and causes ADDON_ACTION_BLOCKED errors in unrelated
-- Blizzard code (e.g. SetPassThroughButtons during map operations).
local function applyDesiredSuppression()
    if type(InCombatLockdown) == "function" and InCombatLockdown() == true then
        if desiredSuppression then
            pendingAfterCombat = true
        end
        return
    end

    captureLiveFrames()

    if iconFrame then
        applyFrameSuppression(iconFrame, desiredSuppression)
    end
    for frameRef in pairs(trackedFrames) do
        if frameRef ~= iconFrame then
            applyFrameSuppression(frameRef, desiredSuppression)
        end
    end

    pendingAfterCombat = false
end

local function ensureMixinHooked()
    if mixinHooked then
        return
    end

    local mixin = _G.UIWidgetTemplatePreyHuntProgressMixin
    if not mixin or type(hooksecurefunc) ~= "function" then
        return
    end

    local ok = pcall(hooksecurefunc, mixin, "Setup", function(self, widgetInfo)
        iconFrame = self
        trackedFrames[self] = true

        if type(widgetInfo) == "table" then
            local snapshot = {
                questID = extractQuestID(widgetInfo),
                tooltip = type(widgetInfo.tooltip) == "string" and widgetInfo.tooltip or nil,
                barText = (type(widgetInfo.barText) == "string" and widgetInfo.barText ~= "")
                    and widgetInfo.barText or nil,
            }

            for _, keyName in ipairs(NUMERIC_SNAPSHOT_KEYS) do
                local numericValue = safeToNumber(widgetInfo[keyName])
                if numericValue ~= nil then
                    snapshot[keyName] = numericValue
                end
            end

            widgetSnapshot = snapshot
        end

        -- NOTE: never call applyDesiredSuppression()/applyFrameSuppression() from
        -- here -- see the comment on applyDesiredSuppression for why.
    end)

    if ok then
        mixinHooked = true
        captureLiveFrames()
    end
end

local bootFrame = CreateFrame("Frame")
bootFrame:RegisterEvent("ADDON_LOADED")
bootFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
bootFrame:SetScript("OnEvent", function(_, event, loadedAddonName)
    if event == "ADDON_LOADED" then
        if loadedAddonName == "Blizzard_UIWidgets" then
            ensureMixinHooked()
        end
        return
    end

    if event == "PLAYER_REGEN_ENABLED" and pendingAfterCombat then
        applyDesiredSuppression()
    end
end)

if type(IsAddOnLoaded) == "function" and IsAddOnLoaded("Blizzard_UIWidgets") then
    ensureMixinHooked()
end

-- Returns a shallow copy of the last widget Setup snapshot, or nil if the mixin
-- hasn't fired yet this session.
function WidgetAdapter.GetWidgetStage()
    if not widgetSnapshot then
        return nil
    end

    local copy = {}
    for key, value in pairs(widgetSnapshot) do
        copy[key] = value
    end
    return copy
end

function WidgetAdapter.SuppressDefaultPreyIcon(suppress)
    desiredSuppression = suppress == true
    applyDesiredSuppression()
end

Preydator:RegisterModule("WidgetAdapter", WidgetAdapter)
return WidgetAdapter
