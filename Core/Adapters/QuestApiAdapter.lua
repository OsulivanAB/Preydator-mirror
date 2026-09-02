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

-- Returns the raw reward tooltip lines for questID (icon-tagged text, e.g.
-- "|T7734062:16:16|t 10 Veteran Mistcrest" per line) using Blizzard's own
-- QuestUtils_AddQuestRewardsToTooltip via the real shared GameTooltip (not a
-- custom-built one) -- confirmed live (2026-08-28) that a bare
-- CreateFrame(..., "GameTooltipTemplate") crashes on container-type rewards
-- (mystery chests) because QuestUtils_AddQuestRewardsToTooltip's embedded
-- item-preview step needs sub-widgets only a fully-built tooltip has; the
-- real GameTooltip already has them. Works for offered-but-unaccepted hunts
-- once RequestLoadQuest has been called for that questID (already happens
-- during normal HuntScannerRuntime scanning) -- currency/money/XP rewards
-- resolve this way; item/container reward details do not (Blizzard only
-- exposes those once the quest is an actual quest-log entry, confirmed live
-- by testing the same call both before and after accepting -- and a mystery
-- chest has nothing meaningful to preview pre-completion anyway).
local function getRewardTooltipLines(questID)
    local tooltip = _G.GameTooltip
    if not tooltip or type(tooltip.SetOwner) ~= "function" then
        return {}
    end

    local ok = pcall(function()
        tooltip:SetOwner(_G.UIParent, "ANCHOR_NONE")
        if type(_G.QuestUtils_AddQuestRewardsToTooltip) == "function"
            and type(_G.TOOLTIP_QUEST_REWARDS_STYLE_DEFAULT) == "table" then
            _G.QuestUtils_AddQuestRewardsToTooltip(tooltip, questID, _G.TOOLTIP_QUEST_REWARDS_STYLE_DEFAULT)
        end
    end)

    local lines = {}
    if ok then
        local numLines = (type(tooltip.NumLines) == "function") and tooltip:NumLines() or 0
        for i = 1, numLines do
            local fontString = _G["GameTooltipTextLeft" .. i]
            local okText, text = pcall(function()
                return fontString and fontString.GetText and fontString:GetText()
            end)
            if okText and type(text) == "string" and text ~= "" then
                lines[#lines + 1] = text
            end
        end
    end

    pcall(tooltip.Hide, tooltip)
    return lines
end

-- Parses one reward tooltip line into {icon, iconIsAtlas, quantity, name}.
-- Pure string pattern matching on text we already retrieved safely -- no
-- widget access, no taint risk. Handles both texture-ID icon tags
-- (|Tpath-or-id:w:h:...|t) and atlas tags (|Aname:w:h|a), and a leading
-- numeric quantity (e.g. "10 Veteran Mistcrest") -- falls back to
-- quantity=nil, name=the whole remaining text if there's no leading number
-- (e.g. a plain XP/honor line with no count).
local function parseRewardLine(line)
    if type(line) ~= "string" or line == "" then
        return nil
    end

    local icon, iconIsAtlas, rest = nil, false, line

    local atlasName, atlasRest = line:match("^|A(.-):%d+:%d+|a%s*(.*)$")
    if atlasName then
        icon, iconIsAtlas, rest = atlasName, true, atlasRest
    else
        local texturePath, textureRest = line:match("^|T(.-):%d+:%d+:?[%d:]*|t%s*(.*)$")
        if texturePath then
            icon, iconIsAtlas, rest = texturePath, false, textureRest
        end
    end

    local quantity, name = rest:match("^([%d,]+)%s+(.+)$")
    if not quantity then
        name = rest
    end

    return {
        icon = icon,
        iconIsAtlas = iconIsAtlas,
        quantity = quantity,
        name = (type(name) == "string" and name ~= "") and name or nil,
    }
end

-- Returns { entries = {{icon, iconIsAtlas, quantity, name}, ...},
-- hasBonusItemReward = boolean }. entries covers currency/money/XP rewards
-- (see getRewardTooltipLines' comment for why item/container rewards
-- aren't included there); hasBonusItemReward is true when Blizzard reports
-- an item reward slot exists (GetNumQuestLogRewards, confirmed reliable
-- even pre-accept) even though its specific icon/name/quantity aren't
-- resolvable until the quest is accepted.
function QuestApiAdapter.GetQuestRewardSummary(questID)
    questID = safeToNumber(questID)
    if not questID then
        return { entries = {}, hasBonusItemReward = false }
    end

    local entries = {}
    for _, line in ipairs(getRewardTooltipLines(questID)) do
        local entry = parseRewardLine(line)
        if entry then
            entries[#entries + 1] = entry
        end
    end

    local hasBonusItemReward = false
    if type(GetNumQuestLogRewards) == "function" then
        local okCount, numItemRewards = pcall(GetNumQuestLogRewards, questID)
        local numeric = okCount and safeToNumber(numItemRewards)
        hasBonusItemReward = (numeric ~= nil and numeric > 0)
    end

    return { entries = entries, hasBonusItemReward = hasBonusItemReward }
end

Preydator:RegisterModule("QuestApiAdapter", QuestApiAdapter)
return QuestApiAdapter
