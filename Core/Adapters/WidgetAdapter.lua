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
local C_Timer = _G.C_Timer

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

-- Defers a PreyContextRuntime.RefreshPreyContext() call to the next frame,
-- outside whatever hooksecurefunc/HookScript call chain triggered it (see
-- the Setup hook's own comment for the full taint-safety reasoning --
-- RefreshPreyContext transitively reaches applyFrameSuppression, unsafe to
-- call un-deferred from inside a hook). Shared by the Setup hook and the
-- OnShow hook below, since RefreshPreyContext already re-applies icon
-- suppression as its last step -- one deferred call covers both "read fresh
-- data" and "re-hide the icon" purposes.
local function scheduleDeferredPreyContextRefresh()
    if not (C_Timer and type(C_Timer.After) == "function") then
        return
    end
    C_Timer.After(0, function()
        local preyContext = Preydator:GetModule("PreyContextRuntime")
        if preyContext and type(preyContext.RefreshPreyContext) == "function" then
            preyContext.RefreshPreyContext()
        end
    end)
end

-- Frames already given an OnShow hook (see ensureOnShowHooked) -- guards
-- against hooking the same frame twice across repeated captureLiveFrames()
-- calls.
local hookedOnShowFrames = setmetatable({}, { __mode = "k" })

-- Fires the same deferred re-suppression as the Setup hook, but keyed off
-- the frame's own OnShow script instead of any specific Blizzard method.
-- Added 2026-08-28 to replace the earlier PlayGainProgressAnim hook: that
-- approach only caught the ONE specific code path that plays the pulse
-- animation, but the product owner confirmed live the icon still flashed
-- afterward -- meaning something else (most likely the generic UIWidget
-- container's own layout/pooling code, which calls Show() on the widget
-- frame directly as part of laying out newly-updated widgets, entirely
-- outside the PreyHunt-specific mixin methods this file hooks) was also
-- showing the frame. HookScript("OnShow", ...) is Blizzard/WoW's standard
-- taint-safe way to observe "this frame just became shown" regardless of
-- which code path caused it, so it covers every trigger at once instead of
-- chasing individual methods one at a time. Same taint-safety rule as every
-- other hook in this file: read-only observation, defers any protected work
-- via scheduleDeferredPreyContextRefresh rather than acting from inside the
-- hook itself.
local function ensureOnShowHooked(frameRef)
    if not frameRef or hookedOnShowFrames[frameRef] or type(frameRef.HookScript) ~= "function" then
        return
    end
    local ok = pcall(frameRef.HookScript, frameRef, "OnShow", function()
        scheduleDeferredPreyContextRefresh()
    end)
    if ok then
        hookedOnShowFrames[frameRef] = true
    end
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
            ensureOnShowHooked(child)
        end
    end
end

-- Reads progressState/tooltip/barText directly off a live widget frame's own
-- fields, rather than waiting for a Setup call to hand them over. Confirmed
-- live (2026-08-28, via a temporary deep field dump) that these are plain
-- fields already sitting on the frame instance at all times, always current
-- -- Setup only fires occasionally (once at creation, then again on some but
-- not all progress changes; a UI reload can miss its one initial call
-- entirely), so this direct read is the more reliable source, not just a
-- fallback. Same safe field list as the Setup-hook path (NUMERIC_SNAPSHOT_KEYS,
-- excludes widgetID/widgetType/shownState) -- no new taint surface, just a
-- different (more reliable) place to read the same kind of data from.
local function buildSnapshotFromLiveFrame(frame)
    if not frame then
        return nil
    end

    local snapshot = {
        tooltip = type(frame.tooltip) == "string" and frame.tooltip or nil,
        barText = (type(frame.barText) == "string" and frame.barText ~= "") and frame.barText or nil,
    }

    local foundAny = snapshot.tooltip ~= nil or snapshot.barText ~= nil
    for _, keyName in ipairs(NUMERIC_SNAPSHOT_KEYS) do
        local numericValue = safeToNumber(frame[keyName])
        if numericValue ~= nil then
            snapshot[keyName] = numericValue
            foundAny = true
        end
    end

    if not foundAny then
        return nil
    end
    return snapshot
end

-- Named sub-animation fields confirmed present on the live widget frame this
-- client build (2026-08-28, via the same deep field dump built for stage
-- tracking) -- FadeInAnim/FadeOutAnim/GainProgressAnim/TransitionAnim, not
-- the old codebase's AnimIn/AnimOut/GlowAnim/PulseAnim/Loop/LoopingGlow/Shine
-- list (those are function names on this build's frame, not animation
-- objects -- Blizzard restructured this between whatever patch the old code
-- was written against and now, same class of drift already found elsewhere
-- this session for map/zone APIs).
local ANIMATION_OBJECT_FIELDS = { "FadeInAnim", "FadeOutAnim", "GainProgressAnim", "TransitionAnim" }

local function stopFrameAnimations(frameRef)
    if not frameRef then
        return
    end

    if type(frameRef.GetAnimationGroups) == "function" then
        local ok, groups = pcall(function() return { frameRef:GetAnimationGroups() } end)
        if ok and type(groups) == "table" then
            for _, group in ipairs(groups) do
                if group and group.Stop then
                    pcall(group.Stop, group)
                end
            end
        end
    end

    for _, fieldName in ipairs(ANIMATION_OBJECT_FIELDS) do
        local candidate = frameRef[fieldName]
        if type(candidate) == "table" and type(candidate.Stop) == "function" then
            pcall(candidate.Stop, candidate)
        end
    end

    -- Found live (2026-08-28): the old codebase's suppression cancelled a
    -- separate "effectController" system (glow/shine visual effects,
    -- described by the product owner as a lingering "aura" that stayed
    -- visible even after the icon itself was hidden -- confirmed the current
    -- widget still has both effectController and a direct ClearEffects()
    -- method). Without this, Hide()/SetAlpha(0) on the frame doesn't stop
    -- effects this system is actively driving, since they aren't normal
    -- child-frame visibility.
    if type(frameRef.ClearEffects) == "function" then
        pcall(frameRef.ClearEffects, frameRef)
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
        --
        -- The bar previously only picked up a fresh snapshot whenever some
        -- unrelated event (zone change, quest log update) happened to
        -- trigger PreyContextRuntime.RefreshPreyContext() next -- found live
        -- (2026-08-28) this caused a 30-45 second lag between an actual
        -- stage change and the bar/sound reflecting it. Deferring the
        -- refresh to the next frame via C_Timer.After(0, ...) runs it
        -- completely outside this hook's own secure call chain (a
        -- standard, well-established WoW addon technique for exactly this
        -- situation), so it's safe even though RefreshPreyContext
        -- transitively reaches applyFrameSuppression -- calling it directly
        -- from here, un-deferred, would not be.
        scheduleDeferredPreyContextRefresh()
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
--
-- Retries ensureMixinHooked() on every call (cheap no-op once mixinHooked is
-- true) rather than relying solely on the one-shot ADDON_LOADED("Blizzard_UIWidgets")
-- trigger. Found live (2026-08-28) that mixinHooked could be stuck false with
-- the mixin itself already existing (_G.UIWidgetTemplatePreyHuntProgressMixin
-- ~= nil) and a live matching widget already on screen -- meaning the one-shot
-- ADDON_LOADED/initial-IsAddOnLoaded check ran before Blizzard_UIWidgets (or
-- the mixin specifically) was actually ready, and nothing ever gave the hook
-- a second chance. This function is already called every PreyContextRuntime
-- refresh tick while a hunt is tracked, so retrying here guarantees the hook
-- installs as soon as the mixin becomes available, without needing a new
-- event to key off.
function WidgetAdapter.GetWidgetStage()
    ensureMixinHooked()
    captureLiveFrames()

    -- Prefer a fresh direct read off the live widget frame (see
    -- buildSnapshotFromLiveFrame's comment) over the Setup-hook-captured
    -- snapshot -- the direct read is always current, whereas Setup only
    -- fires occasionally and can miss its one initial call entirely across
    -- a UI reload. Falls back to the hook-captured snapshot only if no live
    -- frame is currently found.
    local snapshot = buildSnapshotFromLiveFrame(iconFrame) or widgetSnapshot
    if not snapshot then
        return nil
    end

    local copy = {}
    for key, value in pairs(snapshot) do
        copy[key] = value
    end
    return copy
end

function WidgetAdapter.SuppressDefaultPreyIcon(suppress)
    desiredSuppression = suppress == true
    applyDesiredSuppression()
end

-- TEMP DIAGNOSTIC (2026-08-28) -- widgetSnapshot has stayed nil through
-- every live progress-tracking test so far, even with an active hunt and a
-- visibly-progressing Blizzard prey icon on screen, meaning
-- UIWidgetTemplatePreyHuntProgressMixin.Setup has never actually fired for
-- this hook. Checks whether that's because the mixin/hook itself never
-- installed, or because the real widget lives in a different container
-- frame than assumed (UIWidgetPowerBarContainerFrame) -- current-patch
-- widget container names have already proven stale for other assumptions
-- this session (map/zone APIs). Read-only: type()/GetName() checks only,
-- and deliberately never reads widgetID/widgetType/shownState (see
-- isPreyHuntProgressFrame's comment for why). Remove once the real cause is
-- found and WidgetAdapter is fixed for real.
function WidgetAdapter.DebugWidgetState()
    local lines = {}
    local function add(line) lines[#lines + 1] = tostring(line or "") end

    add("mixinExists=" .. tostring(_G.UIWidgetTemplatePreyHuntProgressMixin ~= nil))
    add("mixinHooked=" .. tostring(mixinHooked))
    add("widgetSnapshot=" .. (widgetSnapshot and "present" or "nil"))

    local containerNames = {
        "UIWidgetPowerBarContainerFrame",
        "UIWidgetTopCenterContainerFrame",
        "UIWidgetBelowMinimapContainerFrame",
    }
    for _, containerName in ipairs(containerNames) do
        local container = _G[containerName]
        if not container or type(container.GetChildren) ~= "function" then
            add(containerName .. "=missing")
        else
            local ok, children = pcall(function() return { container:GetChildren() } end)
            if not ok or type(children) ~= "table" then
                add(containerName .. "=GetChildren failed")
            else
                add(containerName .. " childCount=" .. tostring(#children))
                for i, child in ipairs(children) do
                    local okName, name = pcall(function() return child.GetName and child:GetName() end)
                    local hasResetAnimState = type(child.ResetAnimState) == "function"
                    local hasAnimIn = type(child.AnimIn) == "function"
                    local hasBar = child.Bar ~= nil
                    local hasSetup = type(child.Setup) == "function"
                    add("  [" .. i .. "] name=" .. tostring(okName and name)
                        .. " ResetAnimState=" .. tostring(hasResetAnimState)
                        .. " AnimIn=" .. tostring(hasAnimIn)
                        .. " Bar=" .. tostring(hasBar)
                        .. " Setup=" .. tostring(hasSetup))
                end
            end
        end
    end

    -- Deep field dump of the confirmed real prey-hunt widget (same
    -- ResetAnimState+AnimIn identification isPreyHuntProgressFrame uses) --
    -- looking for anything directly readable RIGHT NOW (current state)
    -- rather than only what arrives via a future Setup call. Same safe
    -- pairs()+type()/GetText()/GetValue() extraction validated for reward
    -- widgets earlier this session; deliberately still never reads
    -- widgetID/widgetType/shownState.
    local matchedFrame = nil
    for _, containerName in ipairs(containerNames) do
        local container = _G[containerName]
        if container and type(container.GetChildren) == "function" then
            local ok, children = pcall(function() return { container:GetChildren() } end)
            if ok and type(children) == "table" then
                for _, child in ipairs(children) do
                    if type(child.ResetAnimState) == "function" and type(child.AnimIn) == "function" then
                        matchedFrame = child
                        break
                    end
                end
            end
        end
        if matchedFrame then
            break
        end
    end

    if matchedFrame then
        add("-- deep field dump of matched widget --")
        local fieldNames = {}
        for key, value in pairs(matchedFrame) do
            if type(key) == "string" and key ~= "widgetID" and key ~= "widgetType" and key ~= "shownState" then
                local valueType = type(value)
                if valueType == "string" or valueType == "number" or valueType == "boolean" then
                    fieldNames[#fieldNames + 1] = key .. "=" .. tostring(value)
                elseif valueType == "table" and type(value.GetText) == "function" then
                    local okText, text = pcall(value.GetText, value)
                    fieldNames[#fieldNames + 1] = key .. ".GetText()=" .. tostring(okText and text)
                elseif valueType == "table" and type(value.GetValue) == "function" then
                    local okVal, val = pcall(value.GetValue, value)
                    fieldNames[#fieldNames + 1] = key .. ".GetValue()=" .. tostring(okVal and val)
                elseif valueType == "table" or valueType == "function" then
                    fieldNames[#fieldNames + 1] = key .. "=<" .. valueType .. ">"
                end
            end
        end
        table.sort(fieldNames)
        for _, entry in ipairs(fieldNames) do
            add("  " .. entry)
        end
    end

    return table.concat(lines, "\n")
end

Preydator:RegisterModule("WidgetAdapter", WidgetAdapter)
return WidgetAdapter
