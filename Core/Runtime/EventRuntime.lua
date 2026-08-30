-- Preydator :: Core/Runtime/EventRuntime.lua
-- Author: RagingAltoholic
-- Responsibility: the single WoW event dispatcher (Section 7 of the
-- architecture doc). One sequencing order, always the same regardless of
-- event: validate -> fail-closed -> context check -> dispatch -> no UI calls.
-- Adds a 4th dispatch category beyond Section 7's three (quest/zone, chat,
-- widget) -- Hunt Table gossip/interaction events -> HuntScannerRuntime --
-- since the doc doesn't otherwise specify what triggers a hunt-list rescan.
-- Reads: MapContextAdapter, Core/State.lua.
-- Writes: Core/State.lua (SetPollingActive only, via PreyContextRuntime/its own
-- fail-closed gate).

local Preydator = _G.Preydator
local CreateFrame = _G.CreateFrame

local EventRuntime = {}

local CONTEXT_EVENTS = {
    PLAYER_ENTERING_WORLD = true,
    ZONE_CHANGED = true,
    ZONE_CHANGED_NEW_AREA = true,
    QUEST_LOG_UPDATE = true,
    QUEST_ACCEPTED = true,
    QUEST_TURNED_IN = true,
    QUEST_REMOVED = true,
}

-- CHAT_MSG_RAID_BOSS_EMOTE isn't a real WoW event (the actual event is
-- RAID_BOSS_EMOTE) -- both are kept so this stays classified as a chat/alert
-- event regardless of which name eventually fires.
local CHAT_EVENTS = {
    CHAT_MSG_SYSTEM = true,
    CHAT_MSG_MONSTER_SAY = true,
    CHAT_MSG_MONSTER_YELL = true,
    CHAT_MSG_MONSTER_EMOTE = true,
    CHAT_MSG_RAID_BOSS_EMOTE = true,
    RAID_BOSS_EMOTE = true,
}

-- Hunt Table gossip/interaction events -- trigger a HuntScannerRuntime rescan.
-- RefreshFromAdapter() trusts GetOfferedHunts()'s own empty-vs-populated
-- result (empty when the pin pool has nothing, e.g. after GOSSIP_CLOSED or
-- PLAYER_INTERACTION_MANAGER_FRAME_HIDE walking away). QUEST_DATA_LOAD_RESULT
-- re-scans once a pin's zone/title data (requested via
-- QuestApiAdapter.RequestLoadQuest) actually arrives from the server.
local HUNT_EVENTS = {
    GOSSIP_SHOW = true,
    GOSSIP_CLOSED = true,
    PLAYER_INTERACTION_MANAGER_FRAME_SHOW = true,
    PLAYER_INTERACTION_MANAGER_FRAME_HIDE = true,
    QUEST_DATA_LOAD_RESULT = true,
}

-- Delivered by Preydator.lua's bootstrap frame, not registered again here --
-- always allowed through the fail-closed gate so init/settings still work.
local ALWAYS_ALLOWED_EVENTS = {
    PLAYER_LOGIN = true,
    ADDON_LOADED = true,
}

local HANDLED_EVENTS = {}
for event in pairs(CONTEXT_EVENTS) do HANDLED_EVENTS[event] = true end
for event in pairs(CHAT_EVENTS) do HANDLED_EVENTS[event] = true end
for event in pairs(HUNT_EVENTS) do HANDLED_EVENTS[event] = true end
for event in pairs(ALWAYS_ALLOWED_EVENTS) do HANDLED_EVENTS[event] = true end

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
            return
        end
    end

    -- 3. CONTEXT CHECK -- context-relevant events (and login/init) refresh
    -- prey context; a chat event goes straight to AlertsRuntime instead.
    if CONTEXT_EVENTS[event] or ALWAYS_ALLOWED_EVENTS[event] then
        local preyContext = Preydator:GetModule("PreyContextRuntime")
        if preyContext then
            preyContext.RefreshPreyContext()
        end
    end

    -- 4. DISPATCH
    if CHAT_EVENTS[event] then
        local alerts = Preydator:GetModule("AlertsRuntime")
        if alerts then
            alerts.HandleChatEvent(event, ...)
        end
    end

    if HUNT_EVENTS[event] then
        -- QUEST_DATA_LOAD_RESULT fires for ANY quest's data loading anywhere
        -- in the game, not just Hunt Table pins -- gate it on actually being
        -- at a Hunt Table so normal questing elsewhere doesn't trigger
        -- constant needless rescans (the other HUNT_EVENTS are already
        -- Hunt-Table-specific, so they don't need this extra check).
        local shouldRescan = true
        if event == "QUEST_DATA_LOAD_RESULT" then
            local adapter = Preydator:GetModule("HuntTableAdapter")
            shouldRescan = (adapter and type(adapter.IsHuntTableActive) == "function"
                and adapter.IsHuntTableActive()) == true
        end

        if shouldRescan then
            local huntScanner = Preydator:GetModule("HuntScannerRuntime")
            if huntScanner then
                huntScanner.RefreshFromAdapter()
            end
        end
    end

    -- 5. NO UI CALLS -- State's own change notification (Core/State.lua
    -- Subscribe) drives UI updates, never a direct call from this dispatcher.
end

local eventFrame = CreateFrame("Frame")
for event in pairs(CONTEXT_EVENTS) do
    eventFrame:RegisterEvent(event)
end
for event in pairs(CHAT_EVENTS) do
    eventFrame:RegisterEvent(event)
end
for event in pairs(HUNT_EVENTS) do
    eventFrame:RegisterEvent(event)
end
eventFrame:SetScript("OnEvent", function(_, event, ...)
    EventRuntime:HandleEvent(event, ...)
end)

Preydator:RegisterModule("EventRuntime", EventRuntime)
return EventRuntime
