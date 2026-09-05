-- Preydator :: Core/Runtime/AlertsRuntime.lua
-- Author: RagingAltoholic
-- Responsibility: nameplate-based trigger detection for the true prey ambush
-- and the Mob Scanner (Pack Ambush / Exploding Corpse Snakes), gated by
-- settings + restricted-instance + active-prey-context. Calls into
-- SoundsRuntime and State -- never touches chat frames or UI.
-- Reads: Core/State.lua, Settings, MapContextAdapter, PreyContextRuntime
-- (ResolveQuestOnMap, the single source of truth for zone status).
-- Writes: nothing (delegates playback to SoundsRuntime).
--
-- Entirely nameplate-based (NAME_PLATE_UNIT_ADDED, dispatched by
-- EventRuntime.lua) -- there is no chat-text detection left in this file.
-- The true ambush ("Ambushed!") was redesigned off chat matching on
-- 2026-08-28 after three separate live-tested chat-based attempts, plus a
-- wide diagnostic net, all failed to ever observe it (see HandleNameplateEvent's
-- own comment). The Mob Scanner below was built the same session once the
-- product owner identified that Season 2's actual mechanics -- Pack Ambush
-- and Exploding Corpse Snakes -- "do not always say something" either, so
-- chat-text matching (the old Bloody Command phrase/sender matching this
-- file used to have) was never going to be reliable for them either.

local Preydator = _G.Preydator
local UnitName = _G.UnitName
local UnitExists = _G.UnitExists
local UnitGUID = _G.UnitGUID
local GetTime = _G.GetTime

local AlertsRuntime = {}

-- "Unknown" placeholder handling. Root-caused live 2026-08-28 via the
-- nameplate trace (below): NAME_PLATE_UNIT_ADDED can fire before the client
-- has actually cached a unit's name yet -- a well-documented WoW timing
-- quirk, most common for a mob that just became visible/spawned -- and
-- UnitName() returns the literal string "Unknown" in that window. This was
-- the real cause of the missed-ambush mystery (not chat, not old wiring):
-- the prey's own nameplate fired while still "Unknown," got compared against
-- preyTargetName, silently failed to match, and was never rechecked.
-- Blizzard's own UNIT_NAME_UPDATE event fires once a unit's name resolves --
-- track units seen as "Unknown" here and recheck them when it fires, rather
-- than giving up after one snapshot.
local PENDING_NAME_EXPIRY_SECONDS = 30
local pendingNameResolution = {}

local function prunePendingNameResolution(now)
    for unit, pending in pairs(pendingNameResolution) do
        if now - pending.recordedAt > PENDING_NAME_EXPIRY_SECONDS then
            pendingNameResolution[unit] = nil
        end
    end
end

-- Verbose nameplate trace, gated on debug.pack_ambush_verbose (previously an
-- unwired no-op setting -- wired up for real 2026-08-28). SoundsRuntime's
-- /pd sinspect only ever sees actual PlayXSound attempts, so it's silent for
-- a nameplate that never reached a match at all -- this answers a strictly
-- earlier question, "did NAME_PLATE_UNIT_ADDED even fire for this unit, and
-- what was its name," which sinspect structurally can't answer. Recorded
-- only while a hunt is active (otherwise every stray nameplate anywhere in
-- the open world would flood it) and only while this setting is on (default
-- off -- an opt-in recording session, not always-on overhead). Product owner
-- can flip it on, go find the mob in question, then dump the trace via
-- `/pd ninspect bs`.
local NAMEPLATE_TRACE_LIMIT = 50
local nameplateTrace = {}

local function isVerboseTraceEnabled()
    local settings = Preydator:GetModule("Settings")
    return settings and settings.Get("debug.pack_ambush_verbose") == true
end

local function recordTrace(name, note)
    local okTime, now = pcall(GetTime)
    table.insert(nameplateTrace, {
        name = name,
        note = note,
        time = (okTime and type(now) == "number") and now or 0,
    })
    while #nameplateTrace > NAMEPLATE_TRACE_LIMIT do
        table.remove(nameplateTrace, 1)
    end
end

-- Returns a shallow copy of the recent nameplate trace (oldest first), for
-- DiagnosticsRuntime.BuildNameplateTraceReport / `/pd ninspect`.
function AlertsRuntime.GetNameplateTrace()
    local copy = {}
    for i, entry in ipairs(nameplateTrace) do
        copy[i] = { name = entry.name, note = entry.note, time = entry.time }
    end
    return copy
end

-- Mob Scanner: nameplate name -> mechanic key. Both are Season 2 successors
-- to Season-1-only mechanics (patch 12.1 discontinued the originals),
-- confirmed live by the product owner (2026-08-28): "Pack Ambush" replaces
-- Bloody Command (Astalor Bloodsworn), attacking via "Pack Scout" and/or
-- "Pack Hunter"; "Exploding Corpse Snakes" replaces Echo of Predation,
-- attacking via "Venom-Bloated Python". Lowercased so more names can be
-- added later (per mechanic or per season) without touching the matching
-- logic below. See MOB_SCANNER_SOUND_FUNCTIONS for which SoundsRuntime
-- function each mechanic key plays.
local MOB_SCANNER_TRIGGERS = {
    ["pack scout"] = "pack_ambush",
    ["pack hunter"] = "pack_ambush",
    ["venom-bloated python"] = "exploding_corpse_snakes",
}

local MOB_SCANNER_SOUND_FUNCTIONS = {
    pack_ambush = "PlayPackAmbushSound",
    exploding_corpse_snakes = "PlayExplodingCorpseSnakesSound",
}

-- Ambush detection, redesigned 2026-08-28 from chat-message parsing to
-- nameplate-based detection (product owner's own suggestion, modeled on
-- RareScanner/SilverDragon): the standalone "Ambushed!" text never matched
-- any registered chat event across three separate live-tested iterations
-- (prey-dialogue matching, CHAT_MSG_SYSTEM-only, then every previously-
-- registered chat trigger type with an empty-sender check) -- even a
-- deliberately wide diagnostic net covering a dozen additional CHAT_MSG_*
-- types plus RaidNotice_AddMessage and UIErrorsFrame:AddMessage produced
-- zero output against a confirmed real ambush, so "Ambushed!" is not
-- reliably observable through any chat/banner API this addon can hook.
-- NAME_PLATE_UNIT_ADDED is not that kind of guess -- it fires whenever any
-- unit's nameplate becomes visible nearby, regardless of how or why it
-- appeared, so matching the newly-visible unit's name against the hunt's own
-- preyTargetName (already parsed from the quest title, no new data source)
-- directly answers "is the prey standing next to me right now" without
-- depending on Blizzard sending any message at all.
--
-- The Mob Scanner (MOB_SCANNER_TRIGGERS) reuses this same event but is a
-- deliberately different, simpler rule than the ambush check above --
-- confirmed by the product owner (2026-08-28): gated on the quest's own
-- isOnMap directly (not State's inPreyZone -- that's a display-purpose
-- pre-filter that has already needed two live fixes this session for edge
-- cases in its own map-hierarchy heuristic; the Mob Scanner sidesteps it
-- entirely by asking Blizzard directly), and -- unlike the ambush trigger,
-- which the product owner did not ask to change -- allowed for the hunt's
-- entire duration rather than being gated to any particular stage (it
-- already naturally stops once the hunt ends, since activeQuestID clears).
-- Deliberately not difficulty-gated either, unlike the old Bloody Command
-- mechanic's nightmare-only restriction: the product owner did not confirm
-- Pack Ambush/Exploding Corpse Snakes are nightmare-exclusive in Season 2,
-- and under-triggering (missing a real occurrence) is worse for an
-- awareness-only alert than over-triggering -- revisit if false positives
-- on non-Nightmare hunts turn up.
-- Gate order matters for diagnostics, not just correctness. A real ambush
-- produced zero /pd sinspect entries (2026-08-28) -- confirmed the previous
-- gate order (polling/instance/quest/settings checked BEFORE the name match)
-- could silently block a genuine prey nameplate match with no trace at all,
-- indistinguishable from the event never firing. Restructured so the name
-- match is checked FIRST (cheap: two Blizzard API calls already made for
-- every nameplate regardless), and only once something we actually care
-- about is confirmed does every remaining gate log a specific "blocked"
-- reason via SoundsRuntime.RecordBlockedAttempt if it stops playback -- the
-- same "every attempt visible" principle already applied inside
-- SoundsRuntime's own functions, now extended to this file's own gates.
-- Nameplates for every other mob nearby still bail immediately with no
-- logging (matching nothing we track), so this doesn't spam the diagnostic
-- history.
--
-- Shared by both HandleNameplateEvent (a fresh nameplate) and
-- HandleUnitNameUpdate (a previously-"Unknown" nameplate whose name just
-- resolved) -- same matching/gating logic either way, once a real name is
-- in hand.
local function processResolvedName(name)
    local loweredName = string.lower(name)

    local state = Preydator:GetModule("State")
    local sounds = Preydator:GetModule("SoundsRuntime")
    if not (state and sounds) then
        return
    end

    local snapshot = state.GetSnapshot()
    local preyTargetName = snapshot.preyTargetName
    local matchesPrey = type(preyTargetName) == "string" and preyTargetName ~= ""
        and loweredName == string.lower(preyTargetName)
    local mechanicKey = MOB_SCANNER_TRIGGERS[loweredName]

    if snapshot.activeQuestID and isVerboseTraceEnabled() then
        local matchNote
        if matchesPrey then
            matchNote = "matches prey"
        elseif mechanicKey then
            matchNote = "matches mob scanner (" .. mechanicKey .. ")"
        else
            matchNote = "no match"
        end
        recordTrace(name, matchNote)
    end

    if not matchesPrey and not mechanicKey then
        return
    end

    local key = matchesPrey and "ambush" or mechanicKey
    local nameSuffix = " (nameplate=" .. name .. ")"

    if state.IsPollingActive() == false then
        sounds.RecordBlockedAttempt(key, "polling inactive" .. nameSuffix)
        return
    end

    local mapContext = Preydator:GetModule("MapContextAdapter")
    if mapContext and mapContext.IsRestrictedInstance() then
        sounds.RecordBlockedAttempt(key, "restricted instance" .. nameSuffix)
        return
    end

    local activeQuestID = snapshot.activeQuestID
    if not activeQuestID then
        sounds.RecordBlockedAttempt(key, "no active quest" .. nameSuffix)
        return
    end

    local settings = Preydator:GetModule("Settings")
    if not settings or settings.Get("general.sounds_enabled") == false then
        sounds.RecordBlockedAttempt(key, "general.sounds_enabled is false" .. nameSuffix)
        return
    end

    -- Goes through PreyContextRuntime.ResolveQuestOnMap, not
    -- QuestApiAdapter.GetQuestIsOnMap directly, so the widget-visible
    -- fallback for isOnMap's own false negatives (Decisions Log item 69)
    -- applies to the ambush/Mob Scanner triggers too, not just the bar --
    -- single source of truth for "is this quest in zone" per this file's own
    -- prior comment about sidestepping the bar's old pre-filter (Decisions
    -- Log items 34/35), now updated to point at the one shared resolver
    -- instead of calling the adapter a second, independent time.
    local preyContext = Preydator:GetModule("PreyContextRuntime")
    local isOnMap = preyContext and preyContext.ResolveQuestOnMap(activeQuestID)

    -- True ambush: only while the player isn't confirmed outside the prey
    -- zone. Queries QuestApiAdapter.GetQuestIsOnMap() directly instead of
    -- state.inPreyZone -- found live (2026-08-28, Zul'Aman) that this still
    -- used the bar's pre-filtered inPreyZone, which blocked a real ambush
    -- (stage genuinely advanced 1->2, proving it happened) even though the
    -- authoritative isOnMap was true the whole time. Unknown/nil isOnMap
    -- still does not block (a nameplate appearing at all is itself strong
    -- evidence of proximity) -- only a CONFIRMED false blocks it.
    if matchesPrey then
        if isOnMap ~= false then
            sounds.PlayAmbushSound()
        else
            sounds.RecordBlockedAttempt("ambush", "isOnMap was false" .. nameSuffix)
        end
    end

    -- Mob Scanner: see this function's own header comment for why this rule
    -- (isOnMap, no stage/difficulty gate) is deliberately different from the
    -- ambush rule above.
    if mechanicKey then
        if isOnMap == true then
            local soundFnName = MOB_SCANNER_SOUND_FUNCTIONS[mechanicKey]
            local soundFn = soundFnName and sounds[soundFnName]
            if type(soundFn) == "function" then
                soundFn()
            end
        else
            sounds.RecordBlockedAttempt(mechanicKey, "isOnMap was not true" .. nameSuffix)
        end
    end
end

function AlertsRuntime.HandleNameplateEvent(unit)
    if type(unit) ~= "string" or type(UnitExists) ~= "function" or type(UnitName) ~= "function" then
        return
    end

    local ok, exists = pcall(UnitExists, unit)
    if not ok or exists ~= true then
        return
    end

    local okName, name = pcall(UnitName, unit)
    if not okName or type(name) ~= "string" or name == "" then
        return
    end

    -- "Unknown" placeholder -- see this file's own comment above
    -- pendingNameResolution for the full root-cause writeup. Remember this
    -- unit (keyed by token, GUID-verified at resolution time since nameplate
    -- tokens are pooled/reused) and wait for UNIT_NAME_UPDATE instead of
    -- silently discarding a nameplate we can't identify yet.
    if name == "Unknown" then
        local okGuid, guid = pcall(UnitGUID, unit)
        if okGuid and guid then
            local okTime, now = pcall(GetTime)
            now = (okTime and type(now) == "number") and now or 0
            prunePendingNameResolution(now)
            pendingNameResolution[unit] = { guid = guid, recordedAt = now }
        end
        return
    end

    processResolvedName(name)
end

-- Fires whenever any tracked unit's name resolves/changes -- only acted on
-- for units this file itself flagged as "Unknown" moments earlier (see
-- HandleNameplateEvent). GUID-checked against what was recorded at that
-- time: nameplate unit tokens are pooled and can be reassigned to a
-- different actual mob between the "Unknown" sighting and this event firing,
-- so the token alone isn't enough to trust it's still the same unit.
function AlertsRuntime.HandleUnitNameUpdate(unit)
    if type(unit) ~= "string" then
        return
    end

    local pending = pendingNameResolution[unit]
    if not pending then
        return
    end
    pendingNameResolution[unit] = nil

    if type(UnitGUID) ~= "function" or type(UnitExists) ~= "function" or type(UnitName) ~= "function" then
        return
    end

    local okExists, exists = pcall(UnitExists, unit)
    if not okExists or exists ~= true then
        return
    end

    local okGuid, guid = pcall(UnitGUID, unit)
    if not okGuid or guid ~= pending.guid then
        return
    end

    local okName, name = pcall(UnitName, unit)
    if not okName or type(name) ~= "string" or name == "" or name == "Unknown" then
        return
    end

    processResolvedName(name)
end

Preydator:RegisterModule("AlertsRuntime", AlertsRuntime)
return AlertsRuntime
