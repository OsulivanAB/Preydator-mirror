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
local C_Timer = _G.C_Timer

local SoundsRuntime = {}

-- Fixed window a volume boost (sound.amplify_enabled) stays active after a
-- play attempt, long enough to cover Preydator's own short alert clips
-- (roughly 2-3s each) without a real playback-finished callback --
-- PlaySoundFile doesn't hand back one. SoundAdapter's ref-counting is what
-- actually keeps this safe if two alerts overlap within the window (see its
-- own comment), not this specific number.
local AMPLIFY_RESTORE_DELAY_SECONDS = 4

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

    -- Amplification is opt-in (sound.amplify_enabled) since it touches the
    -- player's own volume CVars, not just Preydator's own playback -- see
    -- SoundAdapter.BoostVolume's comment for the mechanism. Boosted BEFORE
    -- Play so the raised volume is already in effect the instant the sound
    -- actually starts.
    local boosted = false
    if settings and settings.Get("sound.amplify_enabled") == true and type(adapter.BoostVolume) == "function" then
        boosted = adapter.BoostVolume(settings.Get("sound.amplify_scale"))
    end

    local willPlay, actualChannel = adapter.Play(path, channel)
    if willPlay then
        markPlayed(key)
        recordPlay(key, path, "played", actualChannel)
    else
        recordPlay(key, path, "blocked", "PlaySoundFile returned false")
    end

    if boosted then
        if willPlay and C_Timer and type(C_Timer.After) == "function" then
            C_Timer.After(AMPLIFY_RESTORE_DELAY_SECONDS, adapter.RestoreVolume)
        else
            -- Play itself failed, or no timer available -- nothing to wait
            -- on, restore immediately rather than leave the boost stuck.
            adapter.RestoreVolume()
        end
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

-- Same value SettingsStore.lua builds default sound paths from -- kept as
-- its own local copy here rather than a new cross-module export, matching
-- this codebase's existing precedent (UI/SettingsPanel.lua's
-- SOUND_FOLDER_FALLBACK is the same string, independently defined there too).
local SOUND_FOLDER_PREFIX = "Interface\\AddOns\\Preydator\\sounds\\"

-- Ported from the old codebase's Core/SoundsRuntime.lua NormalizeSoundFileName
-- (2026-09-03, for the custom sound file Add/Remove UI): trims whitespace,
-- lowercases (filenames are matched case-insensitively so a re-add/remove
-- can't create a near-duplicate differing only by case), strips the addon's
-- own sound folder prefix if the user pasted a full path instead of a bare
-- filename, rejects any remaining path separator (no subdirectories), and
-- appends .ogg if missing.
local function normalizeSoundFileName(fileName)
    if type(fileName) ~= "string" then
        return nil
    end

    local normalized = (fileName:match("^%s*(.-)%s*$") or ""):lower()
    if normalized == "" then
        return nil
    end

    local prefixLower = SOUND_FOLDER_PREFIX:lower()
    if normalized:sub(1, #prefixLower) == prefixLower then
        normalized = normalized:sub(#prefixLower + 1)
    end
    if normalized == "" then
        return nil
    end

    if normalized:find("[/\\]") then
        return nil
    end

    if not normalized:match("%.ogg$") then
        normalized = normalized .. ".ogg"
    end

    return normalized
end

-- Registers a filename in sound.custom_file_names so it appears in every
-- sound-path dropdown's option list (UI/SettingsPanel.lua's
-- registerSoundPathDropdown already reads that setting) -- the actual .ogg
-- file must already exist in Interface/AddOns/Preydator/sounds/; this only
-- adds/removes the addon's own record of the filename, same as the old
-- codebase's equivalent (addons can't write arbitrary files to disk).
function SoundsRuntime.AddCustomSoundFile(fileName)
    local normalized = normalizeSoundFileName(fileName)
    if not normalized then
        return false, "Use a valid sound filename (optionally with .ogg)"
    end

    local settings = getSettings()
    if not settings then
        return false, "Settings unavailable"
    end

    local existing = settings.Get("sound.custom_file_names")
    local list = {}
    if type(existing) == "table" then
        for _, name in ipairs(existing) do
            list[#list + 1] = name
            if type(name) == "string" and name:lower() == normalized then
                return false, "File is already in the list"
            end
        end
    end

    list[#list + 1] = normalized
    settings.Set("sound.custom_file_names", list)
    return true, normalized
end

-- Default/protected filenames are never hand-listed here a second time --
-- derived from Settings.GetDefaults(), since sound.custom_file_names'
-- default value IS the protected list (SettingsStore.lua's
-- PROTECTED_SOUND_FILENAMES seeds it directly), keeping one source of truth.
function SoundsRuntime.RemoveCustomSoundFile(fileName)
    local normalized = normalizeSoundFileName(fileName)
    if not normalized then
        return false, "Use a valid sound filename (optionally with .ogg)"
    end

    local settings = getSettings()
    if not settings then
        return false, "Settings unavailable"
    end

    local defaults = settings.GetDefaults()
    local protectedList = defaults and defaults.sound and defaults.sound.custom_file_names
    if type(protectedList) == "table" then
        for _, protectedName in ipairs(protectedList) do
            if type(protectedName) == "string" and protectedName:lower() == normalized then
                return false, "Default sound files cannot be removed"
            end
        end
    end

    local existing = settings.Get("sound.custom_file_names")
    local list = {}
    local removed = false
    if type(existing) == "table" then
        for _, name in ipairs(existing) do
            if not removed and type(name) == "string" and name:lower() == normalized then
                removed = true
            else
                list[#list + 1] = name
            end
        end
    end

    if not removed then
        return false, "File not found in the list"
    end

    settings.Set("sound.custom_file_names", list)
    return true, normalized
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
