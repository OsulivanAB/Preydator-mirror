-- Preydator :: Core/Adapters/AchievementAdapter.lua
-- Author: RagingAltoholic
-- Responsibility: the only file that calls GetAchievementInfo,
-- GetAchievementCriteriaInfoByID, GetAchievementNumCriteria, and
-- GetAchievementCriteriaInfo directly (achievement signals, Full-scope
-- per architecture doc Section 15). Returns plain booleans/strings/arrays;
-- nothing downstream calls these Blizzard globals itself.
-- Reads: GetAchievementInfo, GetAchievementCriteriaInfoByID,
-- GetAchievementNumCriteria, GetAchievementCriteriaInfo.
-- Writes: nothing (pure adapter).

local Preydator = _G.Preydator
local GetAchievementInfo = _G.GetAchievementInfo
local GetAchievementCriteriaInfoByID = _G.GetAchievementCriteriaInfoByID
local GetAchievementNumCriteria = _G.GetAchievementNumCriteria
local GetAchievementCriteriaInfo = _G.GetAchievementCriteriaInfo

local AchievementAdapter = {}

-- Whole-achievement completion. Blizzard's own return order is
-- (id, name, points, completed, month, day, year, description, flags, icon,
-- rewardText, isGuild, wasEarnedByMe, eligible) -- completed is the 4th value.
function AchievementAdapter.IsAchievementComplete(achievementID)
    if type(GetAchievementInfo) ~= "function" then
        return false
    end
    local ok, _, _, _, completed = pcall(GetAchievementInfo, achievementID)
    return ok == true and completed == true
end

function AchievementAdapter.GetAchievementName(achievementID)
    if type(GetAchievementInfo) ~= "function" then
        return nil
    end
    local ok, _, name = pcall(GetAchievementInfo, achievementID)
    return (ok and type(name) == "string" and name ~= "") and name or nil
end

-- Per-criteria completion via the criterion's own stable numeric ID (the
-- ...ByID lookup -- PreyQuestData's stored criteriaIDs are meant for this
-- call specifically). Used to gate a specific hunt out of "still needed"
-- once its own target has already been credited, even while the parent
-- meta achievement (which can cover ~30 targets) remains incomplete overall
-- -- confirmed live (2026-09-01) that whole-achievement completion alone
-- left every hunt of a difficulty flagged as needed, including targets
-- already killed. Return order is (criteriaString, criteriaType, completed,
-- quantity, reqQuantity, ...).
function AchievementAdapter.IsCriteriaComplete(achievementID, criteriaID)
    if type(GetAchievementCriteriaInfoByID) ~= "function" then
        return false
    end
    local ok, _, _, completed = pcall(GetAchievementCriteriaInfoByID, achievementID, criteriaID)
    return ok == true and completed == true
end

-- This criterion's own label (e.g. the specific target's name), via its
-- stable numeric ID (the ...ByID lookup, not a positional index --
-- PreyQuestData's stored criteriaIDs are meant for this call specifically).
-- Returns nil once the criterion is already complete, so callers fall back
-- to the achievement's own name instead -- matches the old codebase's
-- tooltip behavior (only surface the specific-target label while it's still
-- the reason the achievement isn't done). Return order is (criteriaString,
-- criteriaType, completed, quantity, reqQuantity, ...).
function AchievementAdapter.GetCriteriaLabelIfIncomplete(achievementID, criteriaID)
    if type(GetAchievementCriteriaInfoByID) ~= "function" then
        return nil
    end
    local ok, criteriaString, _, completed = pcall(GetAchievementCriteriaInfoByID, achievementID, criteriaID)
    if not ok or completed == true then
        return nil
    end
    return (type(criteriaString) == "string" and criteriaString ~= "") and criteriaString or nil
end

-- Every criterion of an achievement as { {criteriaID, label}, ... } -- the
-- raw material HuntScannerRuntime's name-matching fallback needs to resolve
-- a criteriaID for a questID that isn't in PreyQuestData's static table
-- (new content). `label` is Blizzard's own localized criterion text (for
-- these achievements, generally the target's name) -- this adapter does no
-- matching/normalization itself, that's HuntScannerRuntime's job (Section 3:
-- adapters wrap the API, runtimes hold the logic).
function AchievementAdapter.GetAllCriteria(achievementID)
    if type(GetAchievementNumCriteria) ~= "function" or type(GetAchievementCriteriaInfo) ~= "function" then
        return {}
    end
    local okCount, count = pcall(GetAchievementNumCriteria, achievementID)
    if not okCount or type(count) ~= "number" then
        return {}
    end

    local criteria = {}
    for index = 1, count do
        local ok, criteriaString, _, _, _, _, _, _, _, criteriaID =
            pcall(GetAchievementCriteriaInfo, achievementID, index)
        if ok and type(criteriaString) == "string" and criteriaString ~= "" and type(criteriaID) == "number" then
            criteria[#criteria + 1] = { criteriaID = criteriaID, label = criteriaString }
        end
    end
    return criteria
end

Preydator:RegisterModule("AchievementAdapter", AchievementAdapter)
return AchievementAdapter
