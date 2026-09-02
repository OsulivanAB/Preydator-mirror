-- Preydator :: Core/Runtime/EventRuntime.lua
-- Author: RagingAltoholic
-- Responsibility: the single WoW event dispatcher (Section 7 of the
-- architecture doc). One sequencing order, always the same regardless of
-- event: validate -> fail-closed -> context check -> dispatch -> no UI calls.
-- Adds a 4th dispatch category beyond Section 7's original three (quest/zone,
-- chat, widget) -- Hunt Table interaction tracking -> HuntScannerRuntime
-- rescans. The chat category itself was removed 2026-08-28 once
-- AlertsRuntime's last chat-text detector (Bloody Command) was replaced by
-- nameplate-based detection -- see NAMEPLATE_EVENTS below, which now covers
-- everything chat used to (ambush, Pack Ambush, Exploding Corpse Snakes).
-- Also owns a small bounded ticker (2026-08-28) that re-runs
-- PreyContextRuntime.RefreshPreyContext() every few seconds for the whole
-- duration a hunt is actively tracked, since the Blizzard widget system
-- doesn't reliably notify when its own data changes -- see the "Prey Hunt
-- progress-tracking ticker" section below for why a ticker instead of a
-- Blizzard event.
--
-- This Hunt Table section started as a faithful port (2026-08-27) of the old
-- codebase's Modules/HuntScanner.lua interaction-tracking state machine, but
-- live testing with the port in place found a real timing problem the old
-- code's own design has: GOSSIP_SHOW's gossip-option check and
-- PLAYER_INTERACTION_MANAGER_FRAME_SHOW's CovenantMissionFrame:IsShown()
-- check are BOTH evaluated once, synchronously, at the instant each event
-- fires -- and a live trace showed both reading false at that exact instant
-- for this NPC/interaction type (missionVisible only flips true several
-- seconds later). Since neither the old code nor the first port re-checks
-- after that single failed instant, the whole mechanism silently never
-- activates. Fixed here by having both "just opened" events start a
-- staggered *watch* (reusing the same 0.05-10s schedule) where EVERY pass
-- re-evaluates HuntTableAdapter.IsHuntTableActive() fresh, instead of
-- deciding once and giving up -- whichever pass lands after the frame
-- actually becomes ready is the one that activates tracking.
--
-- Explicitly NOT ported: the old panel's own rendering
-- (Modules/HuntScanner/HuntTablePanel.lua already owns that, freshly
-- designed, untouched by this), the Settings-preview concept (doesn't exist
-- in this architecture), the classic gossip-quest-dialog events
-- (QUEST_DETAIL/QUEST_PROGRESS/QUEST_COMPLETE -- this rewrite only targets
-- CovenantMissionFrame-based Hunt Tables, not the older gossip-dialog UI),
-- ACHIEVEMENT_EARNED (2026-09-01) invalidates HuntScannerRuntime's
-- achievement-needs cache wholesale -- see ACHIEVEMENT_EVENTS below.
--
-- Reads: MapContextAdapter, Core/State.lua, Core/Settings.lua,
-- Modules/HuntScanner/HuntTableAdapter.lua (read-only signals only --
-- HuntTableAdapter remains the only file that reads actual pin/quest data).
-- Writes: Core/State.lua (SetPollingActive only, via PreyContextRuntime/its own
-- fail-closed gate).

local Preydator = _G.Preydator
local CreateFrame = _G.CreateFrame
local C_Timer = _G.C_Timer
local GetTime = _G.GetTime

local EventRuntime = {}

-- Root event frame -- declared up top so the noisy-event toggle below can
-- reference it as an upvalue.
local eventFrame = CreateFrame("Frame")

local CONTEXT_EVENTS = {
    PLAYER_ENTERING_WORLD = true,
    ZONE_CHANGED = true,
    ZONE_CHANGED_NEW_AREA = true,
    QUEST_LOG_UPDATE = true,
    QUEST_ACCEPTED = true,
    QUEST_TURNED_IN = true,
    QUEST_REMOVED = true,
}

-- Ambush detection was redesigned 2026-08-28 from chat-message parsing to
-- this: the standalone "Ambushed!" text never matched any registered chat
-- event across three separate iterations (see AlertsRuntime.lua's own
-- history), including a deliberately wide diagnostic net covering every
-- plausible CHAT_MSG_* type plus RaidNotice/UIErrorsFrame banners -- none of
-- them ever fired for a confirmed real ambush. Per the product owner's own
-- suggestion (an approach modeled on RareScanner/SilverDragon): detect the
-- prey becoming targetable nearby instead of waiting on an announcement that
-- doesn't reliably arrive. The same event now also drives AlertsRuntime's
-- Mob Scanner (Pack Ambush/Exploding Corpse Snakes) -- both mechanics were
-- confirmed live (2026-08-28) not to reliably announce themselves in chat
-- either, so the whole CHAT_MSG_*-based dispatch category this file used to
-- have (solely to feed the now-removed chat-text Bloody Command detection)
-- was removed entirely rather than left dead.
local NAMEPLATE_EVENTS = {
    NAME_PLATE_UNIT_ADDED = true,
}

-- UNIT_NAME_UPDATE: added 2026-08-28 after live nameplate-trace data
-- (AlertsRuntime.lua's debug.pack_ambush_verbose recording) caught the real
-- cause of a missed ambush -- NAME_PLATE_UNIT_ADDED had genuinely fired for
-- the prey, but UnitName() returned the literal placeholder "Unknown" in
-- that instant (a well-documented WoW race: the client hadn't cached the
-- unit's name yet). This event fires once a tracked unit's name resolves;
-- AlertsRuntime.HandleUnitNameUpdate only acts on units it explicitly
-- flagged as "Unknown" moments earlier, so this doesn't add meaningful
-- dispatch overhead for the vast majority of firings that are irrelevant.
local UNIT_NAME_EVENTS = {
    UNIT_NAME_UPDATE = true,
}

local HUNT_EVENTS = {
    GOSSIP_SHOW = true,
    GOSSIP_CLOSED = true,
    PLAYER_INTERACTION_MANAGER_FRAME_SHOW = true,
    PLAYER_INTERACTION_MANAGER_FRAME_HIDE = true,
    QUEST_DATA_LOAD_RESULT = true,
    QUEST_FINISHED = true,
}

-- All five mean "the interaction state might have just changed, recheck" --
-- none of them, on their own, reliably means "definitely entered" or
-- "definitely left." A live debug-print trace (2026-08-28) proved this NPC's
-- actual flow is GOSSIP_SHOW -> PLAYER_INTERACTION_MANAGER_FRAME_SHOW ->
-- GOSSIP_CLOSED -> PLAYER_INTERACTION_MANAGER_FRAME_HIDE, all within roughly
-- one frame, BEFORE CovenantMissionFrame (the actual Hunt Table map) ever
-- opens -- gossip closing here is an intermediate UI transition (gossip ->
-- map), not the player leaving. Treating GOSSIP_CLOSED/..._HIDE as an
-- immediate "player left" signal (the previous design) called hidePanel(),
-- which bumps rescanSequence and cancels the in-flight watch from the SHOW
-- event a moment earlier -- killing the mechanism before any staggered pass
-- ever got a chance to see the map become visible. This was the actual
-- reason the panel never rendered, not a rendering bug. All five events now
-- trigger the same re-checking watch; HuntTableAdapter.IsHuntTableActive()'s
-- 3-signal check is the single source of truth for enter/leave, never a raw
-- event name.
local HUNT_RECHECK_EVENTS = {
    GOSSIP_SHOW = true,
    PLAYER_INTERACTION_MANAGER_FRAME_SHOW = true,
    GOSSIP_CLOSED = true,
    PLAYER_INTERACTION_MANAGER_FRAME_HIDE = true,
    QUEST_FINISHED = true,
}

local NOISY_WIDGET_EVENTS = { "UPDATE_UI_WIDGET", "UPDATE_ALL_UI_WIDGETS" }

-- Earning ANY achievement (not just a Prey one) can change whether a hunt
-- row's badge should still show -- HuntScannerRuntime.OnAchievementEarned
-- wipes its cache wholesale rather than trying to filter to Prey-relevant
-- IDs here, since that filtering already lives in one place (PreyQuestData's
-- tables, read by HuntScannerRuntime itself) and this event is cheap/rare
-- enough that a full wipe costs nothing.
local ACHIEVEMENT_EVENTS = {
    ACHIEVEMENT_EARNED = true,
}

-- Delivered by Preydator.lua's bootstrap frame, not registered again here --
-- always allowed through the fail-closed gate so init/settings still work.
local ALWAYS_ALLOWED_EVENTS = {
    PLAYER_LOGIN = true,
    ADDON_LOADED = true,
}

-- ---------------------------------------------------------------------------
-- Prey Hunt progress-tracking ticker.
-- ---------------------------------------------------------------------------

-- RefreshPreyContext only ran on CONTEXT_EVENTS (zone change, quest log
-- update, etc.) or a widget Setup call -- found live (2026-08-28) that
-- Setup doesn't fire reliably (WidgetAdapter.GetWidgetStage now reads the
-- live widget frame directly instead, see its own comment, which fixed
-- data *accuracy*), leaving stage changes invisible on the bar for a long
-- time whenever no incidental context event happened to fire either.
-- Registering UPDATE_UI_WIDGET/UPDATE_ALL_UI_WIDGETS for the whole duration
-- of a tracked hunt (unlike the Hunt Table's bounded ~10s watch) would
-- reintroduce the same "fires for everything, indefinitely" overhead this
-- file already fixed once for Hunt Table scanning (see the "noisy events
-- must be time-bounded" note further down) -- a hunt can be tracked for
-- many minutes, not a bounded interaction window. A plain, predictable
-- ticker while a hunt is active is simpler and bounded in cost instead.
local PROGRESS_POLL_INTERVAL_SECONDS = 2
local progressTicker = nil

local function stopProgressTicker()
    if progressTicker then
        progressTicker:Cancel()
        progressTicker = nil
    end
end

local function ensureProgressTicker()
    if progressTicker or not C_Timer or type(C_Timer.NewTicker) ~= "function" then
        return
    end
    progressTicker = C_Timer.NewTicker(PROGRESS_POLL_INTERVAL_SECONDS, function()
        local preyContext = Preydator:GetModule("PreyContextRuntime")
        if preyContext then
            preyContext.RefreshPreyContext()
        end
    end)
end

-- Starts/stops the ticker to match whether a hunt is currently tracked.
-- RefreshPreyContext() itself already re-derives activeQuestID fresh every
-- call (including its own fail-closed/restricted-instance gate) -- this
-- only decides whether the ticker should keep waking it up, no gameplay
-- logic duplicated here.
local function syncProgressTicker()
    local state = Preydator:GetModule("State")
    local activeQuestID = state and state.GetSnapshot().activeQuestID
    if activeQuestID then
        ensureProgressTicker()
    else
        stopProgressTicker()
    end
end

-- ---------------------------------------------------------------------------
-- Hunt Table interaction-tracking state machine.
-- ---------------------------------------------------------------------------

local noisyEventsRegistered = false
local huntInteractionActive = false
local rescanSequence = 0
local lastRescanTime = 0
-- Matches the old codebase's SNAPSHOT_QUEUE_DEBOUNCE_SECONDS exactly --
-- used for the frequent "still active, keep data fresh" triggers
-- (QUEST_DATA_LOAD_RESULT/the noisy widget events), not the watch below.
local RESCAN_DEBOUNCE_SECONDS = 0.15
local WATCH_DELAYS = { 0.05, 0.20, 0.50, 1.00, 2.00, 4.00, 7.00, 10.00 }

local function setNoisyEventsRegistered(shouldRegister)
    if shouldRegister == noisyEventsRegistered then
        return
    end
    noisyEventsRegistered = shouldRegister
    for _, event in ipairs(NOISY_WIDGET_EVENTS) do
        if shouldRegister then
            eventFrame:RegisterEvent(event)
        else
            eventFrame:UnregisterEvent(event)
        end
    end
end

local function isHuntRuntimeEnabled()
    local settings = Preydator:GetModule("Settings")
    if not settings then
        return false
    end
    return settings.Get("general.hunt_enabled") ~= false and settings.Get("hunt.enabled") ~= false
end

local function isRestrictedInstance()
    local mapContext = Preydator:GetModule("MapContextAdapter")
    return (mapContext and mapContext.IsRestrictedInstance()) == true
end

local function rescanHuntList()
    local huntScanner = Preydator:GetModule("HuntScannerRuntime")
    if huntScanner then
        huntScanner.RefreshFromAdapter()
    end
end

-- Immediate, non-debounced hide -- used only by the fail-closed paths
-- (restricted instance entered, hunt runtime disabled mid-interaction),
-- where an instant stop matters more than tolerating a brief UI-transition
-- flicker. Normal Hunt Table leave detection goes through
-- checkHuntInteraction's active -> inactive transition instead (see the
-- HUNT_RECHECK_EVENTS comment above for why an immediate hide on every
-- GOSSIP_CLOSED/..._HIDE event used to break the whole mechanism). Resets
-- interaction state, cancels any watch/rescan passes still pending, does one
-- final rescan (finds an empty pin pool, so HuntScannerRuntime's list --
-- and HuntTablePanel's own render gate -- both clear naturally), and stops
-- listening for noisy events.
local function hidePanel()
    huntInteractionActive = false
    rescanSequence = rescanSequence + 1
    rescanHuntList()
    setNoisyEventsRegistered(false)
end

-- Re-evaluates whether we're genuinely at a Hunt Table right now (using
-- HuntTableAdapter's own robust 3-signal check, not a narrower single
-- signal) and rescans if so. Called immediately and on every staggered pass
-- of beginHuntTableWatch -- so even if this specific call sees stale/not-
-- ready state, a later pass in the same watch will catch it once it's real.
local function checkHuntInteraction()
    if not isHuntRuntimeEnabled() or isRestrictedInstance() then
        if huntInteractionActive then
            hidePanel()
        end
        return
    end

    local adapter = Preydator:GetModule("HuntTableAdapter")
    local isActive = adapter and type(adapter.IsHuntTableActive) == "function"
        and adapter.IsHuntTableActive() == true

    local wasActive = huntInteractionActive
    if isActive ~= huntInteractionActive then
        huntInteractionActive = isActive
        setNoisyEventsRegistered(isActive)
    end

    -- Rescan both while staying active (keeps the list fresh) and on the
    -- active -> inactive transition (so the panel actually clears when the
    -- player genuinely leaves -- previously only the isActive branch ran,
    -- so leaving via this path left a stale list on screen).
    if isActive or wasActive then
        rescanHuntList()
    end
end

-- Starts (or restarts) a staggered re-check sequence. Deliberately does NOT
-- gate on whether the interaction looks like a Hunt Table right this
-- instant -- live testing (2026-08-27) showed CovenantMissionFrame:IsShown()
-- and the gossip-option check can both read false for several seconds after
-- the interaction genuinely begins, so a single synchronous decision here
-- would silently miss it (as the first port of this file did). Each pass
-- re-checks fresh via checkHuntInteraction; the token check means a watch
-- started by an interaction that has since ended does nothing once it fires.
local function beginHuntTableWatch()
    rescanSequence = rescanSequence + 1
    local token = rescanSequence

    checkHuntInteraction()

    if not C_Timer or type(C_Timer.After) ~= "function" then
        return
    end
    for _, delay in ipairs(WATCH_DELAYS) do
        C_Timer.After(delay, function()
            if token == rescanSequence then
                checkHuntInteraction()
            end
        end)
    end

    -- UPDATE_UI_WIDGET/UPDATE_ALL_UI_WIDGETS fire for ANY UI widget change
    -- anywhere in the game, not just Preydator's -- staying registered for
    -- the full open-ended duration of huntInteractionActive (which "pins
    -- are visible" alone can sustain indefinitely just from the map being
    -- left open, independent of genuinely interacting with the NPC) meant
    -- this fired continuously and re-scanned forever while the map was
    -- simply open (found live 2026-08-28, product owner: the underlying
    -- pin data barely changes -- weekly, or on prey completion -- so this
    -- was pure waste, not a correctness need). Auto-unregister once this
    -- watch's bounded window (its last WATCH_DELAYS entry) concludes,
    -- scheduled slightly after so it always runs after that pass's own
    -- checkHuntInteraction() and wins regardless of what that just decided.
    -- A fresh HUNT_RECHECK_EVENTS event (real gossip/interaction-manager
    -- show or hide) re-arms both the watch and noisy-event listening from
    -- scratch via a new call to this function. Panel visibility itself is
    -- unaffected -- it stays driven by huntInteractionActive/the last
    -- fetched list, not by this listener.
    C_Timer.After(WATCH_DELAYS[#WATCH_DELAYS] + 0.1, function()
        if token == rescanSequence then
            setNoisyEventsRegistered(false)
        end
    end)
end

-- For the frequent "still at the table, data may have changed" triggers
-- (QUEST_DATA_LOAD_RESULT, the noisy widget events) -- only fires while
-- already confirmed active (detecting NEWLY active is beginHuntTableWatch's
-- job), and debounced since these can fire many times in quick succession.
local function debouncedRescan()
    if not huntInteractionActive then
        return
    end
    local now = (GetTime and GetTime()) or 0
    if now - lastRescanTime < RESCAN_DEBOUNCE_SECONDS then
        return
    end
    lastRescanTime = now
    rescanHuntList()
end

-- Includes the dynamically-registered noisy widget events too, even though
-- they aren't always actually registered -- this is "events we know how to
-- handle," separate from "events currently registered."
local HANDLED_EVENTS = {}
for event in pairs(CONTEXT_EVENTS) do HANDLED_EVENTS[event] = true end
for event in pairs(NAMEPLATE_EVENTS) do HANDLED_EVENTS[event] = true end
for event in pairs(UNIT_NAME_EVENTS) do HANDLED_EVENTS[event] = true end
for event in pairs(HUNT_EVENTS) do HANDLED_EVENTS[event] = true end
for event in pairs(ACHIEVEMENT_EVENTS) do HANDLED_EVENTS[event] = true end
for event in pairs(ALWAYS_ALLOWED_EVENTS) do HANDLED_EVENTS[event] = true end
for _, event in ipairs(NOISY_WIDGET_EVENTS) do HANDLED_EVENTS[event] = true end

function EventRuntime.HandleEvent(_, event, ...)
    -- 1. VALIDATE
    if not HANDLED_EVENTS[event] then
        return
    end

    local mapContext = Preydator:GetModule("MapContextAdapter")
    local state = Preydator:GetModule("State")

    -- 2. FAIL-CLOSED
    if not ALWAYS_ALLOWED_EVENTS[event] then
        if mapContext and mapContext.IsRestrictedInstance() then
            if state then
                state.SetPollingActive(false)
            end
            if huntInteractionActive then
                hidePanel()
            end
            stopProgressTicker()
            return
        end
    end

    -- 3. CONTEXT CHECK -- context-relevant events (and login/init) refresh
    -- prey context; a nameplate event goes straight to AlertsRuntime instead.
    if CONTEXT_EVENTS[event] or ALWAYS_ALLOWED_EVENTS[event] then
        local preyContext = Preydator:GetModule("PreyContextRuntime")
        if preyContext then
            preyContext.RefreshPreyContext()
        end
        syncProgressTicker()
    end

    -- 4. DISPATCH
    -- HuntScannerRuntime.OnPreyQuestEnded existed (clears its per-quest zone
    -- cache) but was never actually called from anywhere -- found live
    -- (2026-08-28) after the product owner completed two Normal-difficulty
    -- hunts and correctly expected the Hunt Table's cached reward data for
    -- that difficulty to refresh (rewards can rotate on completion, per
    -- their own earlier observation). PreyQuestData's static table (the
    -- same one HuntScannerRuntime's own difficulty resolution already
    -- trusts) identifies whether the turned-in quest was actually a Prey
    -- Hunt, without needing to race against RefreshPreyContext's own
    -- State.ClearActiveQuest() call later in this same dispatch.
    if event == "QUEST_TURNED_IN" then
        local questID = ...
        local preyQuestData = Preydator:GetModule("PreyQuestData")
        local isPreyHunt = preyQuestData and type(preyQuestData.PreyQuestData) == "table"
            and preyQuestData.PreyQuestData[questID] ~= nil
        if isPreyHunt then
            local huntScanner = Preydator:GetModule("HuntScannerRuntime")
            if huntScanner and type(huntScanner.OnPreyQuestEnded) == "function" then
                huntScanner.OnPreyQuestEnded({ questID = questID })
            end
        end
    end

    if NAMEPLATE_EVENTS[event] then
        local alerts = Preydator:GetModule("AlertsRuntime")
        if alerts and type(alerts.HandleNameplateEvent) == "function" then
            alerts.HandleNameplateEvent(...)
        end
    end

    if ACHIEVEMENT_EVENTS[event] then
        local huntScanner = Preydator:GetModule("HuntScannerRuntime")
        if huntScanner and type(huntScanner.OnAchievementEarned) == "function" then
            huntScanner.OnAchievementEarned()
        end
    end

    if UNIT_NAME_EVENTS[event] then
        local alerts = Preydator:GetModule("AlertsRuntime")
        if alerts and type(alerts.HandleUnitNameUpdate) == "function" then
            alerts.HandleUnitNameUpdate(...)
        end
    end

    if HUNT_RECHECK_EVENTS[event] then
        beginHuntTableWatch()
    elseif event == "QUEST_DATA_LOAD_RESULT" or event == "UPDATE_UI_WIDGET"
        or event == "UPDATE_ALL_UI_WIDGETS" or event == "QUEST_LOG_UPDATE" then
        debouncedRescan()
    end

    -- 5. NO UI CALLS -- State's own change notification (Core/State.lua
    -- Subscribe) drives UI updates, never a direct call from this dispatcher.
end

-- Read-only snapshot of this file's private Hunt Table interaction-tracking
-- state, for DiagnosticsRuntime.BuildHuntInspectReport -- otherwise
-- huntInteractionActive/noisyEventsRegistered/rescanSequence are only
-- visible as local upvalues, invisible to any diagnostic tooling.
function EventRuntime.GetHuntTrackingDebugState()
    return {
        huntInteractionActive = huntInteractionActive,
        noisyEventsRegistered = noisyEventsRegistered,
        rescanSequence = rescanSequence,
    }
end

for event in pairs(CONTEXT_EVENTS) do
    eventFrame:RegisterEvent(event)
end
for event in pairs(NAMEPLATE_EVENTS) do
    eventFrame:RegisterEvent(event)
end
for event in pairs(UNIT_NAME_EVENTS) do
    eventFrame:RegisterEvent(event)
end
for event in pairs(HUNT_EVENTS) do
    eventFrame:RegisterEvent(event)
end
for event in pairs(ACHIEVEMENT_EVENTS) do
    eventFrame:RegisterEvent(event)
end
eventFrame:SetScript("OnEvent", function(_, event, ...)
    EventRuntime:HandleEvent(event, ...)
end)

Preydator:RegisterModule("EventRuntime", EventRuntime)
return EventRuntime
