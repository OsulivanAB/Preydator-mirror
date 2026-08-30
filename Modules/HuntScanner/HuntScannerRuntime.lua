-- Preydator :: Modules/HuntScanner/HuntScannerRuntime.lua
-- Author: RagingAltoholic
-- Responsibility: parses adapter output into hunt domain objects, derives and
-- caches each hunt's expected zone at scan time (architecture doc Section 8),
-- and delegates selection to the adapter. Does not create or touch a single
-- frame. Grouping/sorting/reward display/achievement signals are full-scope
-- (Section 15 MVP table) and not built in this slice.
-- Reads: HuntTableAdapter, QuestApiAdapter, MapContextAdapter, PreyQuestData.
-- Writes: its own hunt-list state and the expected-zone cache (published for
-- PreyContextRuntime to read).

local Preydator = _G.Preydator

local HuntScannerRuntime = {}

local expectedZoneByQuestID = {}
local huntList = {}
-- Guards RequestLoadQuest from ever being re-issued for the same questID.
-- Without this, QUEST_DATA_LOAD_RESULT -> RefreshFromAdapter() ->
-- RequestLoadQuest() -> QUEST_DATA_LOAD_RESULT forms an unbounded loop that
-- hangs the client (hit this in testing, 2026-08-25) -- each questID's data
-- must only ever be requested once per session.
local requestedLoadForQuestID = {}
-- Remembers the last known Adventure Map ID so the mapapi zone fallback still
-- works if HuntTableAdapter.GetAdventureMapID() briefly returns nil on a
-- later pass (e.g. mid-transition) while pins are still being processed.
local cachedAdventureMapID = nil

local DIFFICULTY_INDEX_TO_KEY = { [1] = "normal", [2] = "hard", [3] = "nightmare" }
-- Checked most-specific-first so "nightmare"/"hard" don't get shadowed by a
-- shorter substring match.
local DIFFICULTY_TOKENS = { "nightmare", "hard", "normal" }

-- PreyQuestData's static questID->difficultyIndex table is authoritative for
-- the ~90 known hunts; text parsing is only a fallback for hunts not yet in
-- that table (e.g. new-patch content).
local function resolveDifficulty(questID, title, description)
    local preyQuestData = Preydator:GetModule("PreyQuestData")
    local entry = preyQuestData and preyQuestData.PreyQuestData and preyQuestData.PreyQuestData[questID]
    if entry and DIFFICULTY_INDEX_TO_KEY[entry[1]] then
        return DIFFICULTY_INDEX_TO_KEY[entry[1]]
    end

    local candidates = {}
    if type(title) == "string" then candidates[#candidates + 1] = title end
    if type(description) == "string" then candidates[#candidates + 1] = description end

    for _, text in ipairs(candidates) do
        local lowered = string.lower(text)
        for _, token in ipairs(DIFFICULTY_TOKENS) do
            if string.find(lowered, token, 1, true) then
                return token
            end
        end
    end

    return "normal"
end

-- Rescans the live Hunt Table. Trusts HuntTableAdapter.GetOfferedHunts()'s own
-- empty-vs-populated result directly rather than gating on a separate
-- "am I active" predicate first -- pin presence is itself the most reliable
-- signal once the map/pin view is open (see IsHuntTableActive's own doc
-- comment for why a pre-check alone is unreliable there).
function HuntScannerRuntime.RefreshFromAdapter()
    local adapter = Preydator:GetModule("HuntTableAdapter")
    local questApi = Preydator:GetModule("QuestApiAdapter")
    if not (adapter and questApi) then
        return
    end

    local offeredHunts = adapter.GetOfferedHunts()
    local newHuntList = {}

    local mapContext = Preydator:GetModule("MapContextAdapter")
    local adventureMapID = type(adapter.GetAdventureMapID) == "function" and adapter.GetAdventureMapID() or nil
    if adventureMapID then
        cachedAdventureMapID = adventureMapID
    end

    for _, pin in ipairs(offeredHunts) do
        local questID = pin.questID
        local difficulty = resolveDifficulty(questID, pin.title, pin.description)

        -- The client may not have full quest data cached yet for a hunt the
        -- player hasn't interacted with (confirmed in-game: zone/title come
        -- back nil until this fires). Requested at most once per questID per
        -- session -- see requestedLoadForQuestID's comment for why.
        if not expectedZoneByQuestID[questID] and not requestedLoadForQuestID[questID] then
            requestedLoadForQuestID[questID] = true
            questApi.RequestLoadQuest(questID)
        end

        -- Primary: ask Blizzard directly for the zone from quest metadata --
        -- authoritative once the client has it (Section 8, step 1).
        local zoneMapID = questApi.GetQuestZoneID(questID)

        -- Fallback: resolve the pin's own map position instead. Confirmed
        -- in-game (2026-08-25) that GetQuestZoneID alone returns nil for
        -- offered-but-unaccepted hunts even after RequestLoadQuest -- this is
        -- a live Blizzard API call using the pin's real coordinates, not the
        -- hardcoded coordinate-bucket heuristic the architecture doc drops.
        if not zoneMapID then
            local mapForLookup = adventureMapID or cachedAdventureMapID
            if mapContext and mapForLookup then
                local zoneInfo = mapContext.GetMapInfoAtPosition(mapForLookup, pin.normalizedX, pin.normalizedY)
                zoneMapID = zoneInfo and zoneInfo.mapID
            end
        end

        if zoneMapID then
            expectedZoneByQuestID[questID] = zoneMapID
        end

        newHuntList[#newHuntList + 1] = {
            questID = questID,
            title = pin.title or questApi.GetQuestTitle(questID),
            difficulty = difficulty,
            zoneMapID = zoneMapID or expectedZoneByQuestID[questID],
        }
    end

    huntList = newHuntList
end

function HuntScannerRuntime.GetExpectedZone(questID)
    return expectedZoneByQuestID[questID]
end

function HuntScannerRuntime.GetHuntList()
    local copy = {}
    for i, hunt in ipairs(huntList) do
        copy[i] = hunt
    end
    return copy
end

function HuntScannerRuntime.SelectHunt(questID)
    local adapter = Preydator:GetModule("HuntTableAdapter")
    if not adapter then
        return false
    end
    return adapter.AcceptHunt(questID)
end

-- Session-lifetime memoization only -- never a stored, permanent
-- questID->zone map (CLAUDE.md Section 4, architecture doc Section 8.5).
function HuntScannerRuntime.OnPreyQuestEnded(payload)
    local questID = payload and payload.questID
    if questID then
        expectedZoneByQuestID[questID] = nil
    end
end

Preydator:RegisterModule("HuntScannerRuntime", HuntScannerRuntime)
return HuntScannerRuntime
