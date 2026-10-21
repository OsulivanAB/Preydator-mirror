-- Preydator :: Core/Adapters/QuestApiAdapter.lua
-- Author: RagingAltoholic
-- Responsibility: the only file that calls C_QuestLog / C_TaskQuest directly.
-- Reads: Blizzard quest APIs.
-- Writes: nothing (pure adapter).

local Preydator = _G.Preydator
local C_QuestLog = _G.C_QuestLog
local C_TaskQuest = _G.C_TaskQuest
local GetQuestLink = _G.GetQuestLink
local GetNumQuestLogRewards = _G.GetNumQuestLogRewards

local QuestApiAdapter = {}

-- Safe numeric coercion: pcall(tostring) -> pattern match -> pcall(tonumber).
-- Never a raw tonumber() on a value that came from a Blizzard API.
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

function QuestApiAdapter.GetActivePreyQuestID()
    if type(C_QuestLog) ~= "table" or type(C_QuestLog.GetActivePreyQuest) ~= "function" then
        return nil
    end

    local ok, questID = pcall(C_QuestLog.GetActivePreyQuest)
    if not ok then
        return nil
    end
    return safeToNumber(questID)
end

function QuestApiAdapter.GetQuestIsOnMap(questID)
    questID = safeToNumber(questID)
    if not questID then
        return nil
    end
    if type(C_QuestLog) ~= "table"
        or type(C_QuestLog.GetLogIndexForQuestID) ~= "function"
        or type(C_QuestLog.GetInfo) ~= "function" then
        return nil
    end

    local okIndex, rawLogIndex = pcall(C_QuestLog.GetLogIndexForQuestID, questID)
    local logIndex = okIndex and safeToNumber(rawLogIndex) or nil
    if not logIndex then
        return nil
    end

    local okInfo, info = pcall(C_QuestLog.GetInfo, logIndex)
    if not okInfo or type(info) ~= "table" or info.isOnMap == nil then
        return nil
    end

    return info.isOnMap == true
end

function QuestApiAdapter.GetQuestZoneID(questID)
    questID = safeToNumber(questID)
    if not questID or type(C_TaskQuest) ~= "table" or type(C_TaskQuest.GetQuestZoneID) ~= "function" then
        return nil
    end

    local ok, zoneID = pcall(C_TaskQuest.GetQuestZoneID, questID)
    if not ok then
        return nil
    end
    return safeToNumber(zoneID)
end

function QuestApiAdapter.IsQuestFlaggedCompleted(questID)
    questID = safeToNumber(questID)
    if not questID
        or type(C_QuestLog) ~= "table"
        or type(C_QuestLog.IsQuestFlaggedCompleted) ~= "function" then
        return nil
    end

    local ok, completed = pcall(C_QuestLog.IsQuestFlaggedCompleted, questID)
    if not ok then
        return nil
    end
    return completed == true
end

function QuestApiAdapter.IsOnQuest(questID)
    questID = safeToNumber(questID)
    if not questID or type(C_QuestLog) ~= "table" or type(C_QuestLog.IsOnQuest) ~= "function" then
        return nil
    end

    local ok, onQuest = pcall(C_QuestLog.IsOnQuest, questID)
    if not ok then
        return nil
    end
    return onQuest == true
end

function QuestApiAdapter.GetQuestTitle(questID)
    questID = safeToNumber(questID)
    if not questID or type(C_QuestLog) ~= "table" or type(C_QuestLog.GetTitleForQuestID) ~= "function" then
        return nil
    end

    local ok, titleInfo = pcall(C_QuestLog.GetTitleForQuestID, questID)
    if not ok then
        return nil
    end

    if type(titleInfo) == "table" then
        return type(titleInfo.title) == "string" and titleInfo.title or nil
    end
    return type(titleInfo) == "string" and titleInfo or nil
end

function QuestApiAdapter.GetQuestLink(questID)
    questID = safeToNumber(questID)
    if not questID or type(GetQuestLink) ~= "function" then
        return nil
    end

    local ok, link = pcall(GetQuestLink, questID)
    if not ok or type(link) ~= "string" or link == "" then
        return nil
    end
    return link
end

-- Returns a shallow-copied array of {text, finished, numFulfilled, numRequired}
-- objective tables, or nil. Never exposes the raw Blizzard objective table by
-- reference.
function QuestApiAdapter.GetQuestObjectives(questID)
    questID = safeToNumber(questID)
    if not questID or type(C_QuestLog) ~= "table" or type(C_QuestLog.GetQuestObjectives) ~= "function" then
        return nil
    end

    local ok, objectives = pcall(C_QuestLog.GetQuestObjectives, questID)
    if not ok or type(objectives) ~= "table" then
        return nil
    end

    local copy = {}
    for i, objective in ipairs(objectives) do
        if type(objective) == "table" then
            copy[i] = {
                text = type(objective.text) == "string" and objective.text or nil,
                finished = objective.finished == true,
                numFulfilled = safeToNumber(objective.numFulfilled),
                numRequired = safeToNumber(objective.numRequired),
            }
        end
    end
    return copy
end

-- Asks the server to load full quest data (title, zone, objectives) for a
-- quest the client only knows about as an offered-but-unaccepted pin.
-- Fire-and-forget: the result arrives later via QUEST_DATA_LOAD_RESULT, not
-- synchronously. Without this, GetQuestZoneID/GetQuestTitle can return nil for
-- a hunt the player hasn't interacted with yet (confirmed in-game 2026-08-25:
-- offered hunts showed zoneMapID=nil until a quest was accepted, which
-- implicitly triggers this same load).
function QuestApiAdapter.RequestLoadQuest(questID)
    questID = safeToNumber(questID)
    if not questID or type(C_QuestLog) ~= "table" or type(C_QuestLog.RequestLoadQuestByID) ~= "function" then
        return
    end
    pcall(C_QuestLog.RequestLoadQuestByID, questID)
end

-- Builds reward entries ({icon, iconIsAtlas, quantity, name}) for questID
-- straight from the same data APIs Blizzard's own
-- QuestUtils_AddQuestRewardsToTooltip reads (C_QuestLog.GetQuestRewardCurrencies,
-- GetQuestLogRewardHonor, GetQuestLogRewardXP) -- no tooltip, no frames, no
-- widget code runs at all. Currency/honor/XP only; item/container reward
-- details still aren't exposed pre-accept (see GetQuestRewardSummary).
--
-- REPLACED in 4.0.10 (2026-10-21) the old getRewardTooltipLines, which drove the real
-- shared GameTooltip invisibly (SetOwner -> QuestUtils_AddQuestRewardsToTooltip
-- -> Hide) and scraped GameTooltipTextLeftN. 4.0.9 gated it off for
-- container-reward quests only; it still ran for every other hunt, and the
-- same persistent "secret number" taint kept showing up on unrelated AreaPOI
-- map tooltips (Holy_Z + the product owner on 4.0.9, hovering a World
-- Assault icon -- item widget for Aqir Research Satchel, nothing to do with
-- Prey). Mechanism, confirmed from Blizzard's source: GameTooltip_OnHide ->
-- GameTooltip_ClearWidgetSet -> UIWidgetContainerMixin:UnregisterForWidgetSet
-- writes widgetSetID = nil, widgetFrames = {}, etc. on
-- GameTooltip.widgetContainer. When our SetOwner/Hide caused that teardown
-- (any scan landing while the tooltip was showing a widget set), those writes
-- were tainted by 'Preydator'. The next RegisterForWidgetSet reads
-- self.widgetSetID on its first line, so every later widget tooltip runs
-- tainted -- and rewrites the same fields tainted again, which is why it
-- never cleared until /reload.
-- Rule: never call methods on the shared GameTooltip from non-hover code.
local function formatQuantity(amount)
    local okFmt, text = pcall(_G.BreakUpLargeNumbers, amount)
    if okFmt and type(text) == "string" then
        return text
    end
    return tostring(amount)
end

local function getRewardEntries(questID)
    local entries = {}

    local currencyRewards = nil
    if type(C_QuestLog) == "table" and type(C_QuestLog.GetQuestRewardCurrencies) == "function" then
        local ok, result = pcall(C_QuestLog.GetQuestRewardCurrencies, questID)
        if ok and type(result) == "table" then
            currencyRewards = result
        end
    end

    local C_CurrencyInfo = _G.C_CurrencyInfo
    local CurrencyContainerUtil = _G.CurrencyContainerUtil
    for _, reward in ipairs(currencyRewards or {}) do
        local currencyID = reward.currencyID
        local amount = safeToNumber(reward.totalRewardAmount)
        local name, icon, quantity = reward.name, reward.texture, amount and formatQuantity(amount)

        -- Currency containers (a bundle granting a variable amount) display
        -- as the container's own name/icon with no count, matching
        -- Blizzard's tooltip.
        if currencyID and amount and type(C_CurrencyInfo) == "table"
            and type(C_CurrencyInfo.IsCurrencyContainer) == "function"
            and type(CurrencyContainerUtil) == "table"
            and type(CurrencyContainerUtil.GetCurrencyContainerInfo) == "function" then
            local okContainer, isContainer = pcall(C_CurrencyInfo.IsCurrencyContainer, currencyID, amount)
            if okContainer and isContainer then
                local okInfo, containerName, containerIcon = pcall(CurrencyContainerUtil.GetCurrencyContainerInfo, currencyID, amount)
                if okInfo and type(containerName) == "string" then
                    name, icon, quantity = containerName, containerIcon, nil
                end
            end
        end

        if type(name) == "string" and name ~= "" then
            entries[#entries + 1] = { icon = icon, iconIsAtlas = false, quantity = quantity, name = name }
        end
    end

    if type(_G.GetQuestLogRewardHonor) == "function" then
        local ok, honor = pcall(_G.GetQuestLogRewardHonor, questID)
        honor = ok and safeToNumber(honor)
        if honor and honor > 0 then
            entries[#entries + 1] = {
                icon = "Interface\\ICONS\\Achievement_LegionPVPTier4", iconIsAtlas = false,
                quantity = formatQuantity(honor), name = _G.HONOR or "Honor",
            }
        end
    end

    if type(_G.GetQuestLogRewardXP) == "function" then
        local ok, _, baseXp = pcall(_G.GetQuestLogRewardXP, questID)
        baseXp = ok and safeToNumber(baseXp)
        if baseXp and baseXp > 0 then
            entries[#entries + 1] = {
                icon = nil, iconIsAtlas = false,
                quantity = formatQuantity(baseXp), name = _G.XP or "XP",
            }
        end
    end

    return entries
end

-- Returns { entries = {{icon, iconIsAtlas, quantity, name}, ...},
-- hasBonusItemReward = boolean }. entries covers currency/honor/XP rewards
-- (see getRewardEntries); hasBonusItemReward is true when Blizzard reports
-- an item reward slot exists (GetNumQuestLogRewards, confirmed reliable
-- even pre-accept) even though its specific icon/name/quantity aren't
-- resolvable until the quest is accepted.
--
-- getRewardEntries touches no frames, so it now runs regardless of
-- hasBonusItemReward -- restores currency icons on hunts with both a bonus
-- chest and a currency reward, which 4.0.9's gate had dropped.
function QuestApiAdapter.GetQuestRewardSummary(questID)
    questID = safeToNumber(questID)
    if not questID then
        return { entries = {}, hasBonusItemReward = false }
    end

    local hasBonusItemReward = false
    if type(GetNumQuestLogRewards) == "function" then
        local okCount, numItemRewards = pcall(GetNumQuestLogRewards, questID)
        local numeric = okCount and safeToNumber(numItemRewards)
        hasBonusItemReward = (numeric ~= nil and numeric > 0)
    end

    return { entries = getRewardEntries(questID), hasBonusItemReward = hasBonusItemReward }
end

Preydator:RegisterModule("QuestApiAdapter", QuestApiAdapter)
return QuestApiAdapter
