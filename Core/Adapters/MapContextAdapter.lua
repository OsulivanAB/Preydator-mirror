-- Preydator :: Core/Adapters/MapContextAdapter.lua
-- Author: RagingAltoholic
-- Responsibility: the only file that calls C_Map, IsInInstance, IsInScenario, and
-- C_ScenarioInfo.GetScenarioInfo. Owns the canonical restricted-instance check.
-- Reads: Blizzard map/instance APIs.
-- Writes: nothing (pure adapter).

local Preydator = _G.Preydator
local C_Map = _G.C_Map
local C_ScenarioInfo = _G.C_ScenarioInfo
local IsInInstance = _G.IsInInstance
local IsInScenario = _G.IsInScenario

local MapContextAdapter = {}

local RESTRICTED_INSTANCE_TYPES = {
    pvp = true,
    arena = true,
    party = true,
    raid = true,
    scenario = true,
    delve = true,
}

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

function MapContextAdapter.GetPlayerMapID()
    if type(C_Map) ~= "table" or type(C_Map.GetBestMapForUnit) ~= "function" then
        return nil
    end

    local ok, mapID = pcall(C_Map.GetBestMapForUnit, "player")
    if not ok then
        return nil
    end
    return safeToNumber(mapID)
end

function MapContextAdapter.GetMapInfo(mapID)
    mapID = safeToNumber(mapID)
    if not mapID or type(C_Map) ~= "table" or type(C_Map.GetMapInfo) ~= "function" then
        return nil
    end

    local ok, info = pcall(C_Map.GetMapInfo, mapID)
    if not ok or type(info) ~= "table" then
        return nil
    end
    return info
end

-- Resolves which zone a normalized (x, y) position on mapID falls in. Used as
-- a fallback zone signal for offered-but-unaccepted Hunt Table pins, where
-- C_TaskQuest.GetQuestZoneID can return nil until the client has cached full
-- quest data (confirmed in-game 2026-08-25). This is a live, general-purpose
-- Blizzard API call, not the hardcoded coordinate-bucket heuristic the
-- architecture doc's Section 8 says to drop -- that was a fixed, calibrated
-- lookup table; this asks Blizzard directly for any position on any map.
function MapContextAdapter.GetMapInfoAtPosition(mapID, x, y)
    mapID = safeToNumber(mapID)
    x = safeToNumber(x)
    y = safeToNumber(y)
    if not mapID or not x or not y
        or type(C_Map) ~= "table" or type(C_Map.GetMapInfoAtPosition) ~= "function" then
        return nil
    end

    local ok, info = pcall(C_Map.GetMapInfoAtPosition, mapID, x, y)
    if not ok or type(info) ~= "table" then
        return nil
    end
    return info
end

-- Returns one of "pvp" | "arena" | "party" | "raid" | "scenario" | "delve" | nil.
function MapContextAdapter.IsRestrictedInstance()
    local inInstance, instanceType = false, nil

    if type(IsInInstance) == "function" then
        local ok, inInst, instType = pcall(IsInInstance)
        if ok then
            inInstance = inInst == true
            instanceType = instType
        end
    end

    if inInstance and RESTRICTED_INSTANCE_TYPES[instanceType] then
        return instanceType
    end

    -- Some delve/scenario transitions can lag behind IsInInstance()'s type reporting.
    if type(IsInScenario) == "function" then
        local ok, inScenario = pcall(IsInScenario)
        if ok and inScenario == true then
            return "scenario"
        end
    end

    if type(C_ScenarioInfo) == "table" and type(C_ScenarioInfo.GetScenarioInfo) == "function" then
        local ok, scenarioInfo = pcall(C_ScenarioInfo.GetScenarioInfo)
        if ok and type(scenarioInfo) == "table" then
            local hasScenarioName = type(scenarioInfo.name) == "string" and scenarioInfo.name ~= ""
            local stage = safeToNumber(scenarioInfo.currentStage)
            local stages = safeToNumber(scenarioInfo.numStages)
            -- Require explicit stage metadata to avoid false positives from stale names.
            if hasScenarioName and (stage ~= nil or stages ~= nil) then
                return "scenario"
            end
        end
    end

    return nil
end

Preydator:RegisterModule("MapContextAdapter", MapContextAdapter)
return MapContextAdapter
