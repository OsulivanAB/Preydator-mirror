-- Preydator :: Modules/HuntScanner/HuntTableAdapter.lua
-- Author: RagingAltoholic
-- Responsibility: the only file that touches CovenantMissionFrame,
-- AdventureMapQuestChoiceDialog, gossip/interaction-manager state, and the
-- Adventure Map pin pool. Returns validated hunt records; nothing downstream
-- touches these Blizzard objects directly.
-- Reads: CovenantMissionFrame, AdventureMapQuestChoiceDialog,
-- C_GossipInfo, C_PlayerInteractionManager.
-- Writes: nothing lasting -- AcceptHunt briefly repositions
-- AdventureMapQuestChoiceDialog off-screen and always restores it.

local Preydator = _G.Preydator
local C_GossipInfo = _G.C_GossipInfo
local UIParent = _G.UIParent
local UnitGUID = _G.UnitGUID
local strsplit = _G.strsplit

local HuntTableAdapter = {}

local ADVENTURE_PIN_POOL_TEMPLATE = "AdventureMap_QuestOfferPinTemplate"
-- The Hunt Table gossip controller's spellID -- only reliable in the brief
-- window right when gossip first opens, before the map/pin view replaces it.
local HUNT_TABLE_CONTROLLER_SPELL_ID = 1271464
-- Known Hunt Table NPC IDs -- a secondary signal that (unlike the gossip
-- spellID) stays valid for as long as the player's target doesn't change.
local HUNT_TABLE_NPC_IDS = { [245824] = true, [246231] = true }

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

local function getMissionFrame()
    return _G.CovenantMissionFrame
end

local function getPinPool()
    local mission = getMissionFrame()
    local mapTab = mission and mission.MapTab
    local pinPools = mapTab and mapTab.pinPools
    return pinPools and pinPools[ADVENTURE_PIN_POOL_TEMPLATE]
end

-- The UI map ID that pin normalizedX/Y coordinates are relative to -- needed
-- to resolve a pin's zone via MapContextAdapter.GetMapInfoAtPosition when
-- C_TaskQuest.GetQuestZoneID doesn't have data yet for an unaccepted hunt.
-- MapTab implements the map-canvas interface directly on the current client
-- (confirmed in-game 2026-08-25: MapTab:GetMapID() returns a valid map ID) --
-- the old code's nested ScrollContainer/MapCanvas child lookup no longer
-- applies, though ScrollContainer is kept as a fallback in case MapTab itself
-- lacks GetMapID in some other client state.
function HuntTableAdapter.GetAdventureMapID()
    local mission = getMissionFrame()
    local mapTab = mission and mission.MapTab
    if not mapTab then
        return nil
    end

    if type(mapTab.GetMapID) == "function" then
        local ok, mapID = pcall(mapTab.GetMapID, mapTab)
        local numeric = ok and safeToNumber(mapID) or nil
        if numeric then
            return numeric
        end
    end

    local scrollContainer = mapTab.ScrollContainer
    if scrollContainer and type(scrollContainer.GetMapID) == "function" then
        local ok, mapID = pcall(scrollContainer.GetMapID, scrollContainer)
        if ok then
            return safeToNumber(mapID)
        end
    end

    return nil
end

local function findPinByQuestID(questID)
    local pool = getPinPool()
    if not pool or type(pool.EnumerateActive) ~= "function" then
        return nil
    end

    local ok, iterator = pcall(pool.EnumerateActive, pool)
    if not ok or type(iterator) ~= "function" then
        return nil
    end

    for pin in iterator do
        if type(pin) == "table" and safeToNumber(pin.questID) == questID then
            return pin
        end
    end
    return nil
end

-- Extracts the numeric NPC ID from the player's current target GUID (format
-- "Creature-0-<server>-<instance>-<zone>-<npcID>-<spawnUID>"), or nil if
-- there's no target/it's not a creature.
local function getTargetNPCID()
    if type(UnitGUID) ~= "function" then
        return nil
    end
    local okGUID, guid = pcall(UnitGUID, "target")
    if not okGUID or type(guid) ~= "string" then
        return nil
    end

    local okSplit, unitType, _, _, _, _, npcIDStr = pcall(strsplit, "-", guid)
    if not okSplit or unitType ~= "Creature" then
        return nil
    end
    return safeToNumber(npcIDStr)
end

local function hasHuntTableGossipOption()
    if type(C_GossipInfo) ~= "table" or type(C_GossipInfo.GetOptions) ~= "function" then
        return false
    end

    local ok, options = pcall(C_GossipInfo.GetOptions)
    if not ok or type(options) ~= "table" then
        return false
    end

    for _, option in ipairs(options) do
        if type(option) == "table" and option.spellID == HUNT_TABLE_CONTROLLER_SPELL_ID then
            return true
        end
    end
    return false
end

-- True while the player is actually at a Hunt Table. Three signals, in order
-- of reliability once the map/pin view is open (matches the old code's
-- combined check, since no single signal covers the whole interaction):
--  1. A gossip option for the Hunt Table controller spell -- only reliable in
--     the brief window right when gossip first opens.
--  2. The player's current target is a known Hunt Table NPC -- stays valid
--     for as long as the target doesn't change, but only once the mission
--     frame is actually shown (a raw NPC-ID match alone isn't enough; some of
--     these NPCs have unrelated gossip/quest dialogue too).
--  3. Pins are actually present once the mission frame is shown -- the most
--     robust signal once the map tab itself is open, regardless of gossip state.
--
-- The `missionVisible` gate below is confirmed (live trace, 2026-08-27) to
-- lag several seconds behind the interaction actually starting -- a single
-- call right when GOSSIP_SHOW/PLAYER_INTERACTION_MANAGER_FRAME_SHOW fires
-- can genuinely see this whole function return false even though the player
-- really is opening a Hunt Table. This is why Core/Runtime/EventRuntime.lua
-- calls this function repeatedly over a staggered watch rather than once --
-- not a bug in this gate itself, just a real limitation callers must handle.
function HuntTableAdapter.IsHuntTableActive()
    local mission = getMissionFrame()
    local missionVisible = mission and mission.IsShown and mission:IsShown()
    if not missionVisible then
        return false
    end

    if hasHuntTableGossipOption() then
        return true
    end

    local npcID = getTargetNPCID()
    if npcID and HUNT_TABLE_NPC_IDS[npcID] then
        return true
    end

    if #HuntTableAdapter.GetOfferedHunts() > 0 then
        return true
    end

    return false
end

-- Returns an array of {questID, title, description, normalizedX, normalizedY}
-- read directly off the live Adventure Map quest-offer pins. Raw/unparsed --
-- difficulty parsing and zone resolution are HuntScannerRuntime's job.
function HuntTableAdapter.GetOfferedHunts()
    local hunts = {}

    local pool = getPinPool()
    if not pool or type(pool.EnumerateActive) ~= "function" then
        return hunts
    end

    local ok, iterator = pcall(pool.EnumerateActive, pool)
    if not ok or type(iterator) ~= "function" then
        return hunts
    end

    for pin in iterator do
        if type(pin) == "table" then
            local questID = safeToNumber(pin.questID)
            if questID then
                hunts[#hunts + 1] = {
                    questID = questID,
                    title = type(pin.title) == "string" and pin.title or nil,
                    description = type(pin.description) == "string" and pin.description or nil,
                    normalizedX = safeToNumber(pin.normalizedX),
                    normalizedY = safeToNumber(pin.normalizedY),
                }
            end
        end
    end

    return hunts
end

-- Shows the Blizzard quest-choice dialog for questID (visible, for browsing).
-- Not wired to anything in the panel today; kept available for a future
-- tooltip/preview. Prefers simulating the real pin click (routes through
-- Blizzard's own data provider) before falling back to a direct dialog call.
function HuntTableAdapter.OpenHuntDialog(questID)
    questID = safeToNumber(questID)
    if not questID then
        return false
    end

    local pin = findPinByQuestID(questID)
    if not pin then
        return false
    end

    if type(pin.GetDataProvider) == "function" then
        local okProvider, provider = pcall(pin.GetDataProvider, pin)
        if okProvider and provider and type(provider.OnQuestOfferPinClicked) == "function" then
            local okClick = pcall(provider.OnQuestOfferPinClicked, provider, pin)
            if okClick then
                return true
            end
        end
    end

    local mission = getMissionFrame()
    local dialog = _G.AdventureMapQuestChoiceDialog
    if mission and dialog and type(dialog.ShowWithQuest) == "function" then
        local ok = pcall(dialog.ShowWithQuest, dialog, mission, pin, questID)
        return ok == true
    end

    return false
end

-- Accepts questID by driving the real AdventureMapQuestChoiceDialog off-screen
-- (SetAlpha 0, moved off-parent) so the player never sees it flash, then
-- restores it. This is the same call chain Blizzard's own pin-click uses, so
-- AcceptQuest() stays inside Blizzard's secure call chain rather than being
-- reimplemented.
function HuntTableAdapter.AcceptHunt(questID)
    questID = safeToNumber(questID)
    if not questID then
        return false
    end

    local questApi = Preydator:GetModule("QuestApiAdapter")
    local activeQuestID = questApi and questApi.GetActivePreyQuestID()
    if activeQuestID and activeQuestID ~= questID then
        -- Refuse to accept a second hunt while one is already in progress.
        return false
    end

    local mission = getMissionFrame()
    local dialog = _G.AdventureMapQuestChoiceDialog
    if not (mission and mission.IsShown and mission:IsShown()
        and dialog and type(dialog.ShowWithQuest) == "function"
        and type(dialog.AcceptQuest) == "function") then
        return false
    end

    local pin = findPinByQuestID(questID)
    if not pin then
        return false
    end

    local prevAlpha = (dialog.GetAlpha and dialog:GetAlpha()) or 1

    local ok = pcall(function()
        dialog:SetAlpha(0)
        dialog:ClearAllPoints()
        dialog:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -4000, 4000)
        dialog:Hide()
        dialog:ShowWithQuest(mission, pin, questID)
        dialog:AcceptQuest()
        dialog:Hide()
        dialog:SetAlpha(prevAlpha)
    end)

    return ok == true
end

-- Returns { {name, icon, quantity, rewardType}, ... } (rewardType is
-- Blizzard's own "currency"/"item" string, straight off the widget -- no
-- name-guessing needed to identify the chest/bag) by briefly showing the
-- real AdventureMapQuestChoiceDialog off-screen (the same technique
-- AcceptHunt already uses safely) and reading its rewardPool widgets'
-- .Name/.Icon/.Count fields. Confirmed live (2026-08-28, no taint on
-- Escape immediately after) that this read-only extraction -- type()/
-- GetText()/GetTexture() only, no arithmetic on any scraped value, no
-- protected-method calls on any widget -- does not reproduce the taint the
-- old codebase's own comments flagged for "reward-frame introspection."
-- Field names (.Name/.Icon/.Count/.rewardType) confirmed against this
-- client's actual live structure via a temporary diagnostic dump, not
-- guessed from the old (different-patch) codebase's ~8-alias approach.
-- Callers should only need to do this once per difficulty, not per quest --
-- rewards are shared across every hunt of the same difficulty and only
-- rotate every 2 completions/week (product owner, 2026-08-28) -- see
-- HuntScannerRuntime's rewardWidgetsByDifficulty cache.
function HuntTableAdapter.GetRewardWidgets(questID)
    questID = safeToNumber(questID)
    if not questID then
        return {}
    end

    local mission = getMissionFrame()
    local dialog = _G.AdventureMapQuestChoiceDialog
    if not (mission and mission.IsShown and mission:IsShown()
        and dialog and type(dialog.ShowWithQuest) == "function") then
        return {}
    end

    local pin = findPinByQuestID(questID)
    if not pin then
        return {}
    end

    local prevAlpha = (dialog.GetAlpha and dialog:GetAlpha()) or 1
    local rewards = {}

    local ok = pcall(function()
        dialog:SetAlpha(0)
        dialog:ClearAllPoints()
        dialog:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -4000, 4000)
        dialog:Hide()
        dialog:ShowWithQuest(mission, pin, questID)

        local pool = dialog.rewardPool
        if pool and type(pool.EnumerateActive) == "function" then
            for reward in pool:EnumerateActive() do
                if type(reward) == "table" then
                    local name = nil
                    if type(reward.Name) == "table" and type(reward.Name.GetText) == "function" then
                        local okName, text = pcall(reward.Name.GetText, reward.Name)
                        name = (okName and type(text) == "string" and text ~= "") and text or nil
                    end

                    local icon = nil
                    if type(reward.Icon) == "table" and type(reward.Icon.GetTexture) == "function" then
                        local okIcon, tex = pcall(reward.Icon.GetTexture, reward.Icon)
                        icon = okIcon and tex or nil
                    end

                    local quantity = nil
                    if type(reward.Count) == "table" and type(reward.Count.GetText) == "function" then
                        local okCount, text = pcall(reward.Count.GetText, reward.Count)
                        quantity = (okCount and type(text) == "string" and text ~= "") and text or nil
                    end

                    local rewardType = type(reward.rewardType) == "string" and reward.rewardType or nil

                    if name or icon then
                        rewards[#rewards + 1] = {
                            name = name, icon = icon, quantity = quantity, rewardType = rewardType,
                        }
                    end
                end
            end
        end

        dialog:Hide()
        dialog:SetAlpha(prevAlpha)
    end)

    if not ok then
        pcall(function()
            dialog:Hide()
            dialog:SetAlpha(prevAlpha)
        end)
        return {}
    end

    return rewards
end

Preydator:RegisterModule("HuntTableAdapter", HuntTableAdapter)
return HuntTableAdapter
