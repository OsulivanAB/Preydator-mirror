-- Preydator :: Modules/HuntScanner/HuntTableAdapter.lua
-- Author: RagingAltoholic
-- Responsibility: the only file that touches CovenantMissionFrame,
-- C_AdventureMap, gossip/interaction-manager state, and the Adventure Map
-- pin pool. Returns validated hunt records; nothing downstream touches these
-- Blizzard objects directly.
-- Reads: CovenantMissionFrame, C_GossipInfo, C_PlayerInteractionManager,
-- quest reward APIs.
-- Writes: nothing. Never shows/hides AdventureMapQuestChoiceDialog (see the
-- comment above AcceptHunt).

local Preydator = _G.Preydator
local C_GossipInfo = _G.C_GossipInfo
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

-- Shared root cause for both functions below (fixed 2026-10-23): through
-- 4.0.10 they drove the real AdventureMapQuestChoiceDialog off-screen
-- (ShowWithQuest/AcceptQuest/Hide) from addon code. Its OnShow -> Refresh
-- -> RefreshDetails registers the dialog's own UIWidgetContainer for the
-- quest's AdventureMapDetails widget set, so Blizzard's widget manager ran
-- tainted by 'Preydator' and wrote shared state (UIWidgetManager's
-- registeredWidgetContainers/processingUnit, and the dialog's questID via
-- OnHide -> Finalize). Later widget tooltips read those fields and ran
-- tainted -- Holy_Z on 4.0.10: "attempt to perform arithmetic on local
-- 'textHeight' (a secret number value)" in UIWidgetTemplateTextWithState
-- Setup, AreaPOI map tooltip, 46x until /reload. Same self-perpetuating
-- pattern as the 4.0.10 GameTooltip fix (see QuestApiAdapter's
-- getRewardEntries comment).
-- Rule: never Show/Hide/ShowWithQuest AdventureMapQuestChoiceDialog (or any
-- Blizzard frame hosting a UIWidgetContainer) from addon code -- call the
-- underlying C_ API instead.

-- Accepts questID via C_AdventureMap.StartQuest -- the exact call
-- AdventureMapQuestChoiceDialogMixin:AcceptQuest makes, minus the dialog.
-- The old path already reached StartQuest from addon (tainted) execution,
-- so this doesn't change whether the accept is allowed.
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
    local C_AdventureMap = _G.C_AdventureMap
    if not (mission and mission.IsShown and mission:IsShown()
        and type(C_AdventureMap) == "table" and type(C_AdventureMap.StartQuest) == "function") then
        return false
    end

    -- Only accept hunts the table is actually offering right now.
    if not findPinByQuestID(questID) then
        return false
    end

    local ok = pcall(C_AdventureMap.StartQuest, questID)
    return ok == true
end

local function countText(count)
    count = safeToNumber(count)
    if count and count > 0 then
        return tostring(count)
    end
    return nil
end

-- Returns { {name, icon, quantity, rewardType}, ... } built from the same
-- data APIs AdventureMapQuestChoiceDialogMixin:RefreshRewards reads, in the
-- same order (XP below max level, currencies, items, money), with the same
-- "currency"/"item" rewardType strings the dialog stamps on its reward
-- frames -- same shape the old dialog-scraping version returned, no frames
-- involved. Item data can still arrive async pre-accept;
-- HuntScannerRuntime's widgetRewardsIncomplete retry already handles that.
-- Callers should only need to do this once per difficulty, not per quest --
-- rewards are shared across every hunt of the same difficulty and only
-- rotate every 2 completions/week (product owner, 2026-08-28) -- see
-- HuntScannerRuntime's rewardWidgetsByDifficulty cache.
function HuntTableAdapter.GetRewardWidgets(questID)
    questID = safeToNumber(questID)
    if not questID then
        return {}
    end

    local rewards = {}
    local function add(name, icon, quantity, rewardType)
        name = (type(name) == "string" and name ~= "") and name or nil
        if name or icon then
            rewards[#rewards + 1] = {
                name = name, icon = icon, quantity = quantity, rewardType = rewardType,
            }
        end
    end

    local GameRulesUtil = _G.GameRulesUtil
    local okLevel, atMaxLevel = false, false
    if type(GameRulesUtil) == "table" and type(GameRulesUtil.IsPlayerAtEffectiveMaxLevel) == "function" then
        okLevel, atMaxLevel = pcall(GameRulesUtil.IsPlayerAtEffectiveMaxLevel)
    end
    if not (okLevel and atMaxLevel) and type(_G.GetQuestLogRewardXP) == "function" then
        local okXP, xp = pcall(_G.GetQuestLogRewardXP, questID)
        xp = okXP and safeToNumber(xp)
        if xp and xp > 0 then
            local okFmt, text = pcall(_G.BreakUpLargeNumbers, xp)
            add(okFmt and text or tostring(xp), "Interface\\Icons\\XP_Icon", nil, nil)
        end
    end

    local C_QuestLog = _G.C_QuestLog
    if type(C_QuestLog) == "table" and type(C_QuestLog.GetQuestRewardCurrencies) == "function" then
        local okCur, currencies = pcall(C_QuestLog.GetQuestRewardCurrencies, questID)
        if okCur and type(currencies) == "table" then
            for _, currency in ipairs(currencies) do
                if type(currency) == "table" then
                    add(currency.name, currency.texture, countText(currency.totalRewardAmount), "currency")
                end
            end
        end
    end

    if type(_G.GetNumQuestLogRewards) == "function" and type(_G.GetQuestLogRewardInfo) == "function" then
        local okNum, numItems = pcall(_G.GetNumQuestLogRewards, questID)
        numItems = okNum and safeToNumber(numItems) or 0
        for itemIndex = 1, numItems do
            local okItem, name, texture, count = pcall(_G.GetQuestLogRewardInfo, itemIndex, questID)
            if okItem then
                add(name, texture, countText(count), "item")
            end
        end
    end

    if type(_G.GetQuestLogRewardMoney) == "function" and type(_G.GetMoneyString) == "function" then
        local okMoney, money = pcall(_G.GetQuestLogRewardMoney, questID)
        money = okMoney and safeToNumber(money)
        if money and money > 0 then
            local okFmt, text = pcall(_G.GetMoneyString, money)
            add(okFmt and text or nil, "Interface\\Icons\\inv_misc_coin_01", nil, nil)
        end
    end

    return rewards
end

Preydator:RegisterModule("HuntTableAdapter", HuntTableAdapter)
return HuntTableAdapter
