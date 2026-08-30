-- Preydator :: Core/Adapters/QuestApiAdapter.lua
-- Author: RagingAltoholic
-- Responsibility: the only file that calls C_QuestLog / C_TaskQuest directly.
-- Reads: Blizzard quest APIs.
-- Writes: nothing (pure adapter).

local Preydator = _G.Preydator
local C_QuestLog = _G.C_QuestLog
local C_TaskQuest = _G.C_TaskQuest
local GetQuestLink = _G.GetQuestLink

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

Preydator:RegisterModule("QuestApiAdapter", QuestApiAdapter)
return QuestApiAdapter
