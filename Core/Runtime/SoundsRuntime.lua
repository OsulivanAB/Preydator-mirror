-- Preydator :: Core/Runtime/SoundsRuntime.lua
-- Author: RagingAltoholic
-- Responsibility: resolves which sound path plays for a given stage/ambush/
-- Pack Ambush/Exploding Corpse Snakes event, honoring user overrides vs.
-- protected defaults, and anti-spam cooldown gating. Calls SoundAdapter.Play
-- for actual playback -- never PlaySoundFile directly.
-- Reads: Settings, Core/State.lua (for stage-transition detection).
-- Writes: its own cooldown-tracking state (last-played timestamps/stage) --
-- not shared state.

local Preydator = _G.Preydator
local GetTime = _G.GetTime

local SoundsRuntime = {}

-- Per-trigger-type timestamps, so an ambush trigger and a stage sound never
-- block each other (Section 10: cooldown applies per-trigger-type, not
-- globally).
local lastPlayedAt = {}

-- Plays at most once per stage per hunt -- otherwise every RefreshPreyContext
-- tick at the same stage would replay the stage sound. Private to this file
-- per its "own cooldown-tracking state" remit.
local lastPlayedStage = { questID = nil, stage = nil }

-- Small ring buffer of recent play attempts (played or blocked, with why) --
-- added 2026-08-28 after live debugging needed to know not just whether a
-- sound played but which trigger it was and, when it didn't play, why not
-- (cooldown, disabled, no path configured, etc.). Exposed via
-- DiagnosticsRuntime.BuildSoundInspectReport / `/pd sinspect`.
local RECENT_PLAYS_LIMIT = 12
local recentPlays = {}

local function recordPlay(key, path, outcome, detail)
    local okTime, now = pcall(GetTime)
    table.insert(recentPlays, {
        key = key,
        path = path,
        outcome = outcome,
        detail = detail,
        time = (okTime and type(now) == "number") and now or 0,
    })
    while #recentPlays > RECENT_PLAYS_LIMIT do
        table.remove(recentPlays, 1)
    end
end

-- Public wrapper so callers outside this file can leave a /pd sinspect trace
-- too. Added 2026-08-28 after a real ambush produced zero sinspect entries --
-- confirming AlertsRuntime.HandleNameplateEvent's OWN gates (polling active,
-- restricted instance, activeQuestID, sounds_enabled, isOnMap) blocked a
-- genuine nameplate match before ever calling PlayAmbushSound, with no trace
-- at all. Same "every attempt visible regardless of which gate stopped it"
-- principle this file already applies to its own internal blocked branches
-- (e.g. sound.ambush_enabled == false) -- now extended to the caller side.
function SoundsRuntime.RecordBlockedAttempt(key, detail)
    recordPlay(key, nil, "blocked", detail)
end

local function getSettings()
    return Preydator:GetModule("Settings")
end

local function getSoundAdapter()
    return Preydator:GetModule("SoundAdapter")
end

local function isPollingActive()
    local state = Preydator:GetModule("State")
    return not state or state.IsPollingActive() ~= false
end

local function isSoundsEnabled()
    local settings = getSettings()
    if not settings then
        return true
    end
    return settings.Get("general.sounds_enabled") ~= false
end

local function withinCooldown(key, cooldownSeconds)
    if type(cooldownSeconds) ~= "number" or cooldownSeconds <= 0 then
        return false
    end

    local last = lastPlayedAt[key]
    if not last then
        return false
    end

    local ok, now = pcall(GetTime)
    if not ok then
        return false
    end

    return (now - last) < cooldownSeconds
end

local function markPlayed(key)
    local ok, now = pcall(GetTime)
    lastPlayedAt[key] = ok and now or nil
end

local function playPath(key, path, cooldownSeconds)
    if not isPollingActive() then
        recordPlay(key, path, "blocked", "polling inactive")
        return false
    end
    if type(path) ~= "string" or path == "" then
        recordPlay(key, path, "blocked", "no path configured")
        return false
    end
    if not isSoundsEnabled() then
        recordPlay(key, path, "blocked", "sounds disabled")
        return false
    end
    if withinCooldown(key, cooldownSeconds) then
        recordPlay(key, path, "blocked", "cooldown")
        return false
    end

    local adapter = getSoundAdapter()
    if not adapter then
        recordPlay(key, path, "blocked", "SoundAdapter unavailable")
        return false
    end

    local settings = getSettings()
    local channel = settings and settings.Get("sound.channel") or nil

    local willPlay, actualChannel = adapter.Play(path, channel)
    if willPlay then
        markPlayed(key)
        recordPlay(key, path, "played", actualChannel)
    else
        recordPlay(key, path, "blocked", "PlaySoundFile returned false")
    end
    return willPlay
end

function SoundsRuntime.PlayStageSound(stage)
    stage = tonumber(stage)
    if not stage then
        return false
    end

    local state = Preydator:GetModule("State")
    local activeQuestID = state and state.GetSnapshot().activeQuestID or nil

    if lastPlayedStage.questID ~= activeQuestID then
        -- First observation of this questID this session -- can't tell a
        -- genuinely brand-new hunt (which does start at stage 1) apart from
        -- an already-in-progress one whose tracking just resumed after a
        -- /reload (lastPlayedStage is session-lifetime only, so a reload
        -- always looks like "first observation" either way). Found live
        -- (2026-08-28): treating this as a sound trigger replayed whatever
        -- stage a hunt was already at on every single reload, including in
        -- a completely different zone from where the hunt actually is.
        -- Baseline silently instead -- trades that for not playing the
        -- very-first-stage sound of a genuinely new hunt, a tradeoff the
        -- product owner asked for after hitting the reload-replay case live.
        lastPlayedStage.questID = activeQuestID
        lastPlayedStage.stage = stage
        return false
    end
    if lastPlayedStage.stage ~= nil and stage <= lastPlayedStage.stage then
        return false
    end

    local settings = getSettings()
    if not settings then
        return false
    end

    local stagePaths = settings.Get("sound.stage_path")
    local path = type(stagePaths) == "table" and stagePaths[stage] or nil

    local played = playPath("stage" .. tostring(stage), path, nil)
    if played then
        lastPlayedStage.stage = stage
    end
    return played
end

function SoundsRuntime.PlayAmbushSound()
    local settings = getSettings()
    if not settings or settings.Get("sound.ambush_enabled") == false then
        -- Recorded even though playPath is never reached -- found live
        -- (2026-08-28) that a blocked-before-playPath case like this shows
        -- up as *zero* entries in /pd sinspect, indistinguishable from the
        -- trigger never firing at all. Every play attempt should be
        -- visible in the history regardless of which gate stopped it.
        recordPlay("ambush", nil, "blocked", "sound.ambush_enabled is false")
        return false
    end

    local path = settings.Get("sound.ambush_path")
    local cooldown = settings.Get("sound.alert_cooldown_seconds")
    return playPath("ambush", path, cooldown)
end

-- Bloody Command (Season 1, Astalor Bloodsworn) and Echo of Predation
-- (Season 1) were both discontinued in patch 12.1 -- but Season 2 replaced
-- each with a live successor mechanic, confirmed by the product owner
-- (2026-08-28): Bloody Command -> "Pack Ambush" (mobs: Pack Scout, Pack
-- Hunter), Echo of Predation -> "Exploding Corpse Snakes" (mob: Venom-Bloated
-- Python). Both are detected by AlertsRuntime's nameplate-based Mob Scanner
-- (neither mechanic reliably announces itself in chat), not chat-text
-- matching -- the old `isBloodyCommandMessage`/`CHAT_TRIGGER_EVENTS` chat
-- path this file's Bloody Command function used to pair with is removed
-- entirely, along with the settings/detection code names it. These are live,
-- player-relevant mechanics now, not dormant Season-1 leftovers -- both
-- default enabled.
function SoundsRuntime.PlayPackAmbushSound()
    local settings = getSettings()
    if not settings or settings.Get("sound.pack_ambush_enabled") == false then
        recordPlay("pack_ambush", nil, "blocked", "sound.pack_ambush_enabled is false")
        return false
    end

    local path = settings.Get("sound.pack_ambush_path")
    local cooldown = settings.Get("sound.alert_cooldown_seconds")
    return playPath("pack_ambush", path, cooldown)
end

function SoundsRuntime.PlayExplodingCorpseSnakesSound()
    local settings = getSettings()
    if not settings or settings.Get("sound.exploding_corpse_snakes_enabled") == false then
        recordPlay("exploding_corpse_snakes", nil, "blocked", "sound.exploding_corpse_snakes_enabled is false")
        return false
    end

    local path = settings.Get("sound.exploding_corpse_snakes_path")
    local cooldown = settings.Get("sound.alert_cooldown_seconds")
    return playPath("exploding_corpse_snakes", path, cooldown)
end

-- Returns a shallow copy of the recent play-attempt history (see
-- recentPlays' comment), oldest first.
function SoundsRuntime.GetRecentPlays()
    local copy = {}
    for i, entry in ipairs(recentPlays) do
        copy[i] = {
            key = entry.key,
            path = entry.path,
            outcome = entry.outcome,
            detail = entry.detail,
            time = entry.time,
        }
    end
    return copy
end

Preydator:RegisterModule("SoundsRuntime", SoundsRuntime)
return SoundsRuntime
