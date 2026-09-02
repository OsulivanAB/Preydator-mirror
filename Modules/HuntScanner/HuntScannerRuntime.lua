-- Preydator :: Modules/HuntScanner/HuntScannerRuntime.lua
-- Author: RagingAltoholic
-- Responsibility: parses adapter output into hunt domain objects, derives and
-- caches each hunt's expected zone at scan time (architecture doc Section 8),
-- resolves achievement signals per hunt (Section 15 full-scope item, built
-- 2026-09-01), and delegates selection to the adapter. Does not create or
-- touch a single frame. Grouping/sorting/reward display remain full-scope
-- and not built in this slice.
-- Reads: HuntTableAdapter, QuestApiAdapter, MapContextAdapter, PreyQuestData,
-- AchievementAdapter, Settings.
-- Writes: its own hunt-list state, the expected-zone cache (published for
-- PreyContextRuntime to read), and the achievement-needs cache. Publishes a
-- Subscribe/notify pair (mirroring Core/State.lua and Core/Settings.lua's
-- existing pattern) so Modules/HuntScanner/HuntTablePanel.lua can react to
-- list changes without registering its own raw WoW events -- EventRuntime
-- stays the single event dispatcher (architecture doc Section 7's "no UI
-- calls" rule).

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
-- Session-lifetime memoization only (matches expectedZoneByQuestID's
-- pattern, CLAUDE.md Section 4) -- rewards don't change while a hunt sits in
-- the offered list, so this avoids rebuilding QuestApiAdapter's scratch
-- tooltip on every rescan pass.
local rewardSummaryByQuestID = {}
-- Session-lifetime, keyed by difficulty ("normal"/"hard"/"nightmare"), not
-- questID -- confirmed live (2026-08-28, product owner) that every hunt of
-- the same difficulty shares identical rewards, rotating together only
-- every 2 completions/week. One HuntTableAdapter.GetRewardWidgets() peek
-- per difficulty (on whichever quest of that difficulty is scanned first)
-- covers every hunt of that difficulty for the rest of the session --
-- avoids doing the off-screen dialog show/hide for all 15 offered hunts
-- when 3 (one per difficulty) already gives complete, accurate coverage.
local rewardWidgetsByDifficulty = {}
-- Named reward priority (2026-09-02, replaces a same-day generic type-based
-- attempt) -- the product owner specified an exact order after seeing real
-- reward names in-game: two specific currencies always lead in a fixed
-- order when present, any "Mistcrest"-family currency (its exact name
-- varies by tier/difficulty) comes next, sorted alphabetically among
-- themselves via the name tiebreaker below, and the actual chest/bag item
-- reward always comes last. Matched by name substring rather than
-- Blizzard's own .rewardType ("currency" vs "item") -- the product owner's
-- ordering is about which SPECIFIC reward it is, not its general category
-- (e.g. Coffer Key and Mistcrest are both "currency" but need different
-- priority). Case-insensitive since these are proper nouns the product
-- owner read directly off their own (English) client, not something to
-- localize.
local function containsIgnoreCase(haystack, needle)
    return string.find(string.lower(haystack), string.lower(needle), 1, true) ~= nil
end

local function namedRewardPriority(name)
    name = tostring(name or "")
    if containsIgnoreCase(name, "Coffer Key") then
        return 1
    end
    if containsIgnoreCase(name, "Preyseeker's Journey") then
        return 2
    end
    if containsIgnoreCase(name, "Mistcrest") then
        return 3
    end
    if containsIgnoreCase(name, "Chest") or containsIgnoreCase(name, "Bag") then
        return 5
    end
    return 4
end
-- Session-lifetime memoization only, same pattern as the caches above --
-- rebuilt wholesale (not per-questID) whenever ACHIEVEMENT_EARNED fires
-- (EventRuntime.lua), since one earned achievement can change the "still
-- needed" answer for every hunt of that difficulty at once.
local achievementNeedsByQuestID = {}
local achievementNeedsBuilt = {}
local subscribers = {}

local function notify()
    for _, callback in ipairs(subscribers) do
        pcall(callback, huntList)
    end
end

function HuntScannerRuntime.Subscribe(callback)
    if type(callback) ~= "function" then
        return
    end
    table.insert(subscribers, callback)
end

local DIFFICULTY_INDEX_TO_KEY = { [1] = "normal", [2] = "hard", [3] = "nightmare" }
local DIFFICULTY_KEY_TO_INDEX = { normal = 1, hard = 2, nightmare = 3 }
-- Checked most-specific-first so "nightmare"/"hard" don't get shadowed by a
-- shorter substring match.
local DIFFICULTY_TOKENS = { "nightmare", "hard", "normal" }

-- PreyQuestData's static questID->difficultyIndex table is authoritative for
-- the ~90 known hunts; text parsing is only a fallback for hunts not yet in
-- that table (e.g. new-patch content).
--
-- Locale fix (2026-09-02): this fallback previously searched only for the
-- literal English words "nightmare"/"hard"/"normal" -- on a non-English
-- client, a new-content hunt's title/description would never contain those
-- words, so this always fell through to the function's own final "normal"
-- default regardless of the hunt's real difficulty. Ported the old
-- codebase's already-validated fix (Modules/HuntScanner.lua's AddToken
-- calls, which register both the English word and L["Nightmare"]/L["Hard"]/
-- L["Normal"] as candidates) rather than inventing a new approach --
-- Locales/*.lua already carries real translations for these three exact
-- keys in 8 of the 11 bundled locales (confirmed: deDE/frFR/esES/esMX/ptBR/
-- itIT/ruRU/zhTW; koKR/zhCN only have compound keys like "Normal Difficulty"
-- today, a locale-content gap for a native speaker to fill later, not
-- something to guess a translation for here per CLAUDE.md Section 7.1).
-- LocalizationAdapter.L() falls back to the key itself when a locale has no
-- translation, so calling it is always safe even for those two locales.
local function resolveDifficulty(questID, title, description)
    local preyQuestData = Preydator:GetModule("PreyQuestData")
    local entry = preyQuestData and preyQuestData.PreyQuestData and preyQuestData.PreyQuestData[questID]
    if entry and DIFFICULTY_INDEX_TO_KEY[entry[1]] then
        return DIFFICULTY_INDEX_TO_KEY[entry[1]]
    end

    local candidates = {}
    if type(title) == "string" then candidates[#candidates + 1] = title end
    if type(description) == "string" then candidates[#candidates + 1] = description end

    local localization = Preydator:GetModule("LocalizationAdapter")
    local function L(key)
        return (localization and localization.L(key)) or key
    end
    -- Order matches DIFFICULTY_TOKENS (most-specific-first) so "nightmare"/
    -- "hard" don't get shadowed by a shorter substring match.
    local LOCALIZED_DIFFICULTY_TOKENS = {
        { key = "nightmare", text = L("Nightmare") },
        { key = "hard", text = L("Hard") },
        { key = "normal", text = L("Normal") },
    }

    for _, text in ipairs(candidates) do
        local lowered = string.lower(text)
        for _, token in ipairs(DIFFICULTY_TOKENS) do
            if string.find(lowered, token, 1, true) then
                return token
            end
        end
        -- Exact-case match against the localized text (safe for every
        -- script, including ones string.lower() can't case-fold, like
        -- Cyrillic/CJK) plus an ASCII-lowercase match as a second try for
        -- Latin-script locales with different capitalization than Blizzard's
        -- own in-game text happens to use.
        for _, localeToken in ipairs(LOCALIZED_DIFFICULTY_TOKENS) do
            if string.find(text, localeToken.text, 1, true)
                or string.find(lowered, string.lower(localeToken.text), 1, true) then
                return localeToken.key
            end
        end
    end

    return "normal"
end

-- Fuzzy-match fallback (2026-09-02) for a questID with no PreyQuestData
-- entry (new content Blizzard added after that table was last updated --
-- e.g. the 4 Nightmare hunts from Decisions Log item 46). Resolves this
-- hunt's own criteriaID by matching its quest title against every criterion
-- label of the given achievement, instead of requiring a hand-sourced
-- numeric ID. Locale-safe by construction: both strings being compared
-- (the quest title from HuntTableAdapter/QuestApiAdapter, and the criterion
-- label from AchievementAdapter.GetAllCriteria) are Blizzard's own live,
-- client-locale text -- this code never hardcodes an English word to search
-- for, it only normalizes formatting noise (case, punctuation, whitespace)
-- before comparing them, so it works the same in any locale the client
-- itself is running. Session-memoized per achievementID+questID -- each
-- lookup enumerates every criterion of a ~30-target achievement, not
-- something to redo on every scan pass.
local criteriaIDByAchievementAndQuest = {}
local function normalizeMatchText(text)
    text = tostring(text or ""):lower()
    return (text:gsub("[^%w]", ""))
end

local function resolveFallbackCriteriaID(questID, title, achievementID, achievementApi)
    local cacheKey = achievementID .. ":" .. questID
    local cached = criteriaIDByAchievementAndQuest[cacheKey]
    if cached ~= nil then
        return cached or nil
    end

    local normalizedTitle = normalizeMatchText(title)
    local foundID = nil
    if normalizedTitle ~= "" then
        for _, criterion in ipairs(achievementApi.GetAllCriteria(achievementID)) do
            local normalizedLabel = normalizeMatchText(criterion.label)
            if normalizedLabel ~= "" and (normalizedLabel == normalizedTitle
                or normalizedTitle:find(normalizedLabel, 1, true)
                or normalizedLabel:find(normalizedTitle, 1, true)) then
                foundID = criterion.criteriaID
                break
            end
        end
    end

    -- false, not nil, so a genuine "no match" is cached too and isn't
    -- re-enumerated every call (table.pcall-free equivalent of the other
    -- caches' nil-means-not-yet-tried convention).
    criteriaIDByAchievementAndQuest[cacheKey] = foundID or false
    return foundID
end

-- Resolves the still-needed achievements for a hunt: the per-difficulty Mode
-- III meta achievement and its Mode I/II progression siblings, plus any
-- explicit per-quest achievement from PreyQuestData.PREY_HUNT_ACHIEVEMENTS_BY_QUEST
-- (checked via whole-achievement completion only -- those are single-target
-- achievements, so that alone is the correct per-target answer). A Mode
-- achievement only counts as still needed when BOTH it isn't complete
-- overall (AchievementAdapter.IsAchievementComplete) AND this hunt's own
-- specific criterion isn't complete either (AchievementAdapter.IsCriteriaComplete)
-- -- confirmed live (2026-09-01) that whole-achievement-only gating flagged
-- every hunt of a difficulty as needed, including targets already killed,
-- since the parent meta achievement can cover ~30 targets and stays
-- incomplete until all of them are done. The per-target criteriaID comes
-- from PreyQuestData when available, falling back to name-matching
-- (resolveFallbackCriteriaID) for questIDs not yet in that table -- if
-- neither resolves a criteriaID, the Mode achievement is skipped entirely
-- for this hunt (still unverifiable, still not guessed, per Decisions Log
-- item 46) rather than falling back to the old whole-achievement-only bug.
local function computeAchievementNeeds(questID, difficultyIndex, title)
    local preyQuestData = Preydator:GetModule("PreyQuestData")
    local achievementApi = Preydator:GetModule("AchievementAdapter")
    if not (preyQuestData and achievementApi and difficultyIndex) then
        return {}
    end

    local entry = preyQuestData.PreyQuestData and preyQuestData.PreyQuestData[questID]
    local criteriaID = entry and entry[2]

    local needs = {}
    local seenAchievementIDs = {}

    local function addNeedIfIncomplete(achievementID, criteriaIDHint)
        if type(achievementID) ~= "number" or seenAchievementIDs[achievementID] then
            return
        end
        seenAchievementIDs[achievementID] = true
        if achievementApi.IsAchievementComplete(achievementID) then
            return
        end
        if criteriaIDHint and achievementApi.IsCriteriaComplete(achievementID, criteriaIDHint) then
            return
        end

        local label = (criteriaIDHint and achievementApi.GetCriteriaLabelIfIncomplete(achievementID, criteriaIDHint))
            or achievementApi.GetAchievementName(achievementID)
            or ("Achievement " .. tostring(achievementID))
        needs[#needs + 1] = { achievementID = achievementID, name = label }
    end

    -- Each Mode achievement needs its own resolved criteriaID -- the static
    -- table's value (when this questID is in PreyQuestData) is tried first;
    -- name-matching against this achievement's own criteria list is the
    -- fallback (2026-09-02) for questIDs not yet in that table. Confirmed
    -- live (2026-09-01, before the fallback existed) that several
    -- new-content Nightmare hunts always showed as needed for Mode III with
    -- no criteriaID at all to check, since the only signal left was "is the
    -- whole ~30-target meta achievement done" -- it wasn't, even though this
    -- specific target already was. If BOTH the table and the fallback come
    -- up empty, this achievement is skipped for this hunt entirely --
    -- unverifiable is still not the same as needed (CLAUDE.md Section 4's
    -- "never guess true/false" principle, applied here).
    local modeIDs = preyQuestData.PREY_HUNT_MODE_ACHIEVEMENT_IDS_BY_DIFFICULTY
        and preyQuestData.PREY_HUNT_MODE_ACHIEVEMENT_IDS_BY_DIFFICULTY[difficultyIndex]
    if modeIDs then
        for _, achievementID in ipairs(modeIDs) do
            local effectiveCriteriaID = criteriaID
                or resolveFallbackCriteriaID(questID, title, achievementID, achievementApi)
            if effectiveCriteriaID then
                addNeedIfIncomplete(achievementID, effectiveCriteriaID)
            end
        end
    end

    local mappedAchievements = preyQuestData.PREY_HUNT_ACHIEVEMENTS_BY_QUEST
        and preyQuestData.PREY_HUNT_ACHIEVEMENTS_BY_QUEST[questID]
    if mappedAchievements then
        for _, achievementID in ipairs(mappedAchievements) do
            addNeedIfIncomplete(achievementID, criteriaID)
        end
    end

    return needs
end

-- Session-lifetime memoization (see achievementNeedsByQuestID's comment) --
-- cheap to build once per questID per session, wiped wholesale on
-- ACHIEVEMENT_EARNED via HuntScannerRuntime.OnAchievementEarned.
local function getAchievementNeeds(questID, difficultyIndex, title)
    local settings = Preydator:GetModule("Settings")
    if not settings or settings.Get("hunt.achievement_signals_enabled") == false then
        return {}
    end

    if not achievementNeedsBuilt[questID] then
        achievementNeedsByQuestID[questID] = computeAchievementNeeds(questID, difficultyIndex, title)
        achievementNeedsBuilt[questID] = true
    end
    return achievementNeedsByQuestID[questID]
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

        -- Primary: resolve the pin's own map position. Confirmed live
        -- (2026-08-28, cross-referenced against the product owner's own
        -- flown-zone survey and direct C_Map.GetMapInfo/GetBestMapForUnit
        -- checks) that C_TaskQuest.GetQuestZoneID returns the broad
        -- continent/region map for these Hunt quests (e.g. mapID 2561,
        -- which Blizzard itself names "Quel'Thalas") rather than the
        -- specific leaf zone the pin -- and the player, once there -- is
        -- actually in (e.g. mapID 2512, "The Coiled Isle"). Position-based
        -- lookup resolves down the map hierarchy to the specific zone
        -- containing that exact point, which is what the panel should show.
        -- A live Blizzard API call using the pin's real coordinates, not
        -- the hardcoded coordinate-bucket heuristic the architecture doc
        -- drops, and not a per-quest override table either (CLAUDE.md
        -- Section 4 explicitly bans a persistent questID->zone mapping --
        -- this works for any zone/quest without needing one).
        local mapForLookup = adventureMapID or cachedAdventureMapID
        local zoneMapID = nil
        if mapContext and mapForLookup then
            local zoneInfo = mapContext.GetMapInfoAtPosition(mapForLookup, pin.normalizedX, pin.normalizedY)
            zoneMapID = zoneInfo and zoneInfo.mapID
        end

        -- Fallback: quest metadata's zone, used only when the position-based
        -- lookup isn't available (e.g. adventureMapID or pin coordinates
        -- missing this pass) -- broader than ideal in some cases, but still
        -- more useful than no zone at all.
        if not zoneMapID then
            zoneMapID = questApi.GetQuestZoneID(questID)
        end

        if zoneMapID then
            expectedZoneByQuestID[questID] = zoneMapID
        end

        -- Cached per session (see rewardSummaryByQuestID's comment) -- only
        -- built once per questID. Doesn't cache an empty result: quest data
        -- may not have arrived yet (same "not loaded yet" gap RequestLoadQuest
        -- exists for above), and caching an empty table would be truthy and
        -- permanently skip retrying even after real data becomes available.
        local rewardSummary = rewardSummaryByQuestID[questID]
        if not rewardSummary then
            rewardSummary = questApi.GetQuestRewardSummary(questID)
            if #rewardSummary.entries > 0 or rewardSummary.hasBonusItemReward then
                rewardSummaryByQuestID[questID] = rewardSummary
            end
        end

        -- Preferred source: one HuntTableAdapter.GetRewardWidgets() peek per
        -- difficulty (see rewardWidgetsByDifficulty's comment) -- gives real
        -- icon/name/quantity for every reward, item/container rewards
        -- included (rewardType == "item" identifies the chest/bag directly
        -- via Blizzard's own field, no name-guessing needed). Falls back to
        -- rewardSummary above (currency/money/XP only, generic mystery icon
        -- for any item reward) until this difficulty's first pass completes
        -- this session.
        local rewardEntries, hasBonusItemReward
        local widgetRewards = rewardWidgetsByDifficulty[difficulty]
        -- Only relevant on a fresh (uncached) peek -- a cached result was
        -- already judged complete before being cached, see below.
        local widgetRewardsIncomplete = false
        if not widgetRewards then
            local freshWidgetRewards = adapter.GetRewardWidgets(questID)
            local hasItemWidget = false
            for _, widgetReward in ipairs(freshWidgetRewards) do
                if widgetReward.rewardType == "item" then
                    hasItemWidget = true
                    break
                end
            end

            -- Confirmed live (2026-09-02): a difficulty's very first reward
            -- peek can catch AdventureMapQuestChoiceDialog's reward pool
            -- before its item/container widget has finished populating --
            -- currency/money widgets are apparently ready first. Caching
            -- that incomplete result unconditionally (the original
            -- behavior) silently dropped the chest/bag reward for every
            -- hunt of that difficulty for the rest of the session, since
            -- rewardWidgetsByDifficulty is never re-peeked once set.
            -- rewardSummary.hasBonusItemReward (GetNumQuestLogRewards,
            -- confirmed reliable even pre-accept, Decisions Log item 19) is
            -- an independent signal for "should there be an item reward
            -- here" -- only lock this peek in once it agrees with that
            -- signal; otherwise use it for just this render pass and let a
            -- later rescan (Hunt Table interaction rescans frequently) try
            -- again instead of freezing the gap in permanently.
            widgetRewardsIncomplete = rewardSummary.hasBonusItemReward and not hasItemWidget
            if #freshWidgetRewards > 0 then
                if not widgetRewardsIncomplete then
                    rewardWidgetsByDifficulty[difficulty] = freshWidgetRewards
                end
                widgetRewards = freshWidgetRewards
            end
        end

        if widgetRewards then
            rewardEntries = {}
            for _, widgetReward in ipairs(widgetRewards) do
                rewardEntries[#rewardEntries + 1] = {
                    icon = widgetReward.icon,
                    iconIsAtlas = false,
                    quantity = widgetReward.quantity,
                    name = widgetReward.name,
                }
            end
            -- Falls through to the generic mystery-item placeholder for
            -- just this pass when the peek is incomplete (above), rather
            -- than silently showing nothing for a reward Blizzard confirms
            -- exists -- corrected to the real icon automatically once a
            -- later peek succeeds and gets cached.
            hasBonusItemReward = widgetRewardsIncomplete
        else
            rewardEntries = rewardSummary.entries
            hasBonusItemReward = rewardSummary.hasBonusItemReward
        end

        -- Stable, difficulty-independent order (2026-09-02, refined twice
        -- same day -- see namedRewardPriority's comment for the final,
        -- product-owner-specified scheme this replaced a generic
        -- type-based guess with). Name/quantity remain only as the
        -- tiebreaker for two rewards sharing a priority (e.g. two different
        -- Mistcrest-tier currencies, sorted alphabetically between
        -- themselves as requested).
        table.sort(rewardEntries, function(a, b)
            local ap, bp = namedRewardPriority(a.name), namedRewardPriority(b.name)
            if ap ~= bp then
                return ap < bp
            end
            local an, bn = tostring(a.name or ""), tostring(b.name or "")
            if an == bn then
                return tostring(a.quantity or "") < tostring(b.quantity or "")
            end
            return an < bn
        end)

        local title = pin.title or questApi.GetQuestTitle(questID)
        local achievementNeeds = getAchievementNeeds(questID, DIFFICULTY_KEY_TO_INDEX[difficulty], title)

        newHuntList[#newHuntList + 1] = {
            questID = questID,
            title = title,
            difficulty = difficulty,
            zoneMapID = zoneMapID or expectedZoneByQuestID[questID],
            rewardEntries = rewardEntries,
            hasBonusItemReward = hasBonusItemReward,
            achievementNeeds = achievementNeeds,
        }
    end

    huntList = newHuntList
    notify()
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

local DIFFICULTY_LABELS = { normal = "Normal", hard = "Hard", nightmare = "Nightmare" }

-- Display-name overrides for mapIDs where Blizzard's own name is too broad
-- to mean anything to the player -- mapID 2561 is the specific case
-- Decisions Log item 18 already investigated: it's the broad continent map
-- (Blizzard's own name "Quel'Thalas") that C_TaskQuest.GetQuestZoneID falls
-- back to for a handful of hunts because there is no more specific zone
-- Blizzard's API exposes for them. That decision deliberately declined to
-- override the *gameplay* zone-matching for this (isOnMap stays Blizzard's
-- own authority, CLAUDE.md Section 4) -- this is a different, narrower
-- concern: only the player-facing label shown in the panel/diagnostics,
-- which is presentation, not a gameplay decision, so it doesn't reintroduce
-- the banned persistent questID->zone mapping pattern.
local ZONE_DISPLAY_NAME_OVERRIDES = {
    [2561] = "The Coiled Isle",
}

-- The single place a hunt's zone name is resolved for either display or
-- sort/group comparison -- HuntTablePanel.lua and DiagnosticsRuntime.lua
-- both call this instead of querying MapContextAdapter directly, so the
-- override above (and any future one) never has to be kept in sync across
-- multiple files.
function HuntScannerRuntime.ResolveZoneDisplayName(mapID)
    if not mapID then
        return ""
    end
    if ZONE_DISPLAY_NAME_OVERRIDES[mapID] then
        return ZONE_DISPLAY_NAME_OVERRIDES[mapID]
    end
    local mapContext = Preydator:GetModule("MapContextAdapter")
    local info = mapContext and mapContext.GetMapInfo(mapID)
    return (info and type(info.name) == "string" and info.name) or ""
end

local function zoneNameOf(hunt)
    return HuntScannerRuntime.ResolveZoneDisplayName(hunt.zoneMapID)
end

-- Leading-article-insensitive comparison key, sort/group ordering only --
-- e.g. "The Coiled Isle" sorts under "C", not "T" (product owner,
-- 2026-09-01). The article is never stripped from the displayed name or
-- from a zone group's own key/label -- only from the string actually
-- compared when deciding order.
local function sortKeyIgnoringArticle(text)
    return (tostring(text or ""):gsub("^%s*[Tt]he%s+", ""))
end

-- Sorts by hunt.sort_by (falling back to title, then the other field, as a
-- stable tiebreaker -- matches the old codebase's own tiebreaker pairing),
-- honoring hunt.sort_direction. Shared by both the flat and grouped paths
-- (grouped calls this once for overall order, then again per-bucket).
local function compareHunts(sortBy, descending, a, b)
    local cmp
    if sortBy == "zone" then
        local az, bz = sortKeyIgnoringArticle(zoneNameOf(a)), sortKeyIgnoringArticle(zoneNameOf(b))
        if az == bz then
            cmp = (tostring(a.title or "") < tostring(b.title or "")) and -1 or 1
        else
            cmp = (az < bz) and -1 or 1
        end
    elseif sortBy == "title" then
        local at, bt = tostring(a.title or ""), tostring(b.title or "")
        if at == bt then
            cmp = (sortKeyIgnoringArticle(zoneNameOf(a)) < sortKeyIgnoringArticle(zoneNameOf(b))) and -1 or 1
        else
            cmp = (at < bt) and -1 or 1
        end
    else -- "difficulty"
        local ar = DIFFICULTY_KEY_TO_INDEX[a.difficulty] or 99
        local br = DIFFICULTY_KEY_TO_INDEX[b.difficulty] or 99
        if ar == br then
            cmp = (tostring(a.title or "") < tostring(b.title or "")) and -1 or 1
        else
            cmp = (ar < br) and -1 or 1
        end
    end
    if descending then
        return cmp > 0
    end
    return cmp < 0
end

-- Sorted (hunt.sort_by/sort_direction) and, when hunt.group_by is
-- "difficulty" or "zone", clustered under a collapsible header pseudo-entry
-- (isGroupHeader=true) per group -- HuntTablePanel renders these as a
-- separate row style and toggles hunt.collapsed_groups on click; a
-- collapsed group's real hunts are omitted from the returned list entirely
-- (same as the old codebase's exact behavior, ported faithfully rather than
-- redesigned). Group ORDER (not the rows within each group) always lists
-- Nightmare before Hard before Normal for difficulty grouping, and
-- alphabetical for zone grouping -- independent of hunt.sort_direction,
-- matching the old codebase's own bucket-order rule, which that sort
-- setting was never wired to.
function HuntScannerRuntime.GetGroupedDisplayList()
    local settings = Preydator:GetModule("Settings")
    local sortBy = (settings and settings.Get("hunt.sort_by")) or "zone"
    local groupBy = (settings and settings.Get("hunt.group_by")) or "difficulty"
    local descending = settings and settings.Get("hunt.sort_direction") == "desc"

    local list = HuntScannerRuntime.GetHuntList()
    table.sort(list, function(a, b)
        return compareHunts(sortBy, descending, a, b)
    end)

    if groupBy ~= "difficulty" and groupBy ~= "zone" then
        return list
    end

    local buckets, bucketOrder = {}, {}
    for _, hunt in ipairs(list) do
        local key = (groupBy == "zone") and zoneNameOf(hunt) or hunt.difficulty
        if not key or key == "" then
            key = "unknown"
        end
        if not buckets[key] then
            buckets[key] = {}
            bucketOrder[#bucketOrder + 1] = key
        end
        table.insert(buckets[key], hunt)
    end

    table.sort(bucketOrder, function(a, b)
        if groupBy == "difficulty" then
            local ar = DIFFICULTY_KEY_TO_INDEX[a] or 99
            local br = DIFFICULTY_KEY_TO_INDEX[b] or 99
            if ar == br then
                return tostring(a) < tostring(b)
            end
            return ar > br
        end
        return sortKeyIgnoringArticle(a) < sortKeyIgnoringArticle(b)
    end)

    local collapsedGroups = (settings and settings.Get("hunt.collapsed_groups")) or {}
    local bucketSortBy = (sortBy == groupBy) and "title" or sortBy

    local grouped = {}
    for _, key in ipairs(bucketOrder) do
        local groupKey = groupBy .. ":" .. key
        local bucketRows = buckets[key]
        table.sort(bucketRows, function(a, b)
            return compareHunts(bucketSortBy, descending, a, b)
        end)

        grouped[#grouped + 1] = {
            isGroupHeader = true,
            groupKey = groupKey,
            collapsed = collapsedGroups[groupKey] == true,
            groupBy = groupBy,
            groupLabel = (groupBy == "difficulty") and (DIFFICULTY_LABELS[key] or key) or key,
        }

        if collapsedGroups[groupKey] ~= true then
            for _, hunt in ipairs(bucketRows) do
                grouped[#grouped + 1] = hunt
            end
        end
    end

    return grouped
end

-- Toggles one group's collapsed state and persists it via Settings (which
-- notifies subscribers, including HuntTablePanel, to re-render). Called by
-- HuntTablePanel's header-row click handler -- Settings stays the only
-- thing UI ever writes through, per architecture doc Section 3.
function HuntScannerRuntime.ToggleGroupCollapsed(groupKey)
    local settings = Preydator:GetModule("Settings")
    if not settings or not groupKey then
        return
    end
    local collapsedGroups = settings.Get("hunt.collapsed_groups") or {}
    collapsedGroups[groupKey] = collapsedGroups[groupKey] ~= true
    settings.Set("hunt.collapsed_groups", collapsedGroups)
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
-- Also invalidates the ENTIRE reward-widget cache (all 3 difficulties, not
-- just the completed hunt's own one) -- confirmed live (2026-08-28) that
-- completing hunts of a difficulty can rotate that difficulty's rewards,
-- and the product owner explicitly asked for a refresh after every single
-- completion since a full re-peek (3 dialog show/hides, already proven
-- taint-safe even done rapidly, Decisions Log item 19) is cheap. Clearing
-- all 3 rather than trying to determine just the completed hunt's own
-- difficulty is deliberate: a reliable post-completion difficulty lookup
-- isn't always available (PreyQuestData's static table doesn't cover every
-- hunt, and text-fallback resolution needs a title/description this
-- payload doesn't carry) -- correctness over precision. Doesn't force an
-- immediate re-scan (RefreshFromAdapter reads live pins, which would be
-- empty and wipe the list if called while not actually at the Hunt Table);
-- the cleared cache simply gets naturally repopulated next time a scan
-- happens for real.
function HuntScannerRuntime.OnPreyQuestEnded(payload)
    local questID = payload and payload.questID
    if questID then
        expectedZoneByQuestID[questID] = nil
        rewardSummaryByQuestID[questID] = nil
        achievementNeedsByQuestID[questID] = nil
        achievementNeedsBuilt[questID] = nil
    end
    rewardWidgetsByDifficulty = {}
    notify()
end

-- Called on Blizzard's own ACHIEVEMENT_EARNED event (EventRuntime.lua).
-- Wipes the ENTIRE achievement-needs cache, not just one questID -- earning
-- a shared meta achievement (Mode I/II/III, or the Mode III completion that
-- follows) changes the "still needed" answer for every hunt that references
-- it, not only whichever quest happened to trigger it. Doesn't force an
-- immediate re-scan for the same reason OnPreyQuestEnded doesn't -- the
-- cache repopulates naturally next time RefreshFromAdapter runs for real.
function HuntScannerRuntime.OnAchievementEarned()
    achievementNeedsByQuestID = {}
    achievementNeedsBuilt = {}
    notify()
end

Preydator:RegisterModule("HuntScannerRuntime", HuntScannerRuntime)
return HuntScannerRuntime
