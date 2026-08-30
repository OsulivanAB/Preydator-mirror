-- Preydator :: Core/Runtime/SoundsRuntime.lua
-- Author: RagingAltoholic
-- Responsibility: resolves which sound path plays for a given stage/ambush/
-- Bloody Command/Echo of Predation event, honoring user overrides vs. protected
-- defaults, and anti-spam cooldown gating. Calls SoundAdapter.Play for actual
-- playback -- never PlaySoundFile directly.
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
        return false
    end
    if type(path) ~= "string" or path == "" then
        return false
    end
    if not isSoundsEnabled() then
        return false
    end
    if withinCooldown(key, cooldownSeconds) then
        return false
    end

    local adapter = getSoundAdapter()
    if not adapter then
        return false
    end

    local settings = getSettings()
    local channel = settings and settings.Get("sound.channel") or nil

    local willPlay = adapter.Play(path, channel)
    if willPlay then
        markPlayed(key)
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
        lastPlayedStage.questID = activeQuestID
        lastPlayedStage.stage = nil
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
        return false
    end

    local path = settings.Get("sound.ambush_path")
    local cooldown = settings.Get("sound.alert_cooldown_seconds")
    return playPath("ambush", path, cooldown)
end

-- Bloody Command and Echo of Predation were Season 1 mechanics; patch 12.1
-- discontinued both. These stay callable (dormant, not removed -- 2026-08-25
-- decision, architecture doc Section 19) but nothing currently triggers them:
-- sound.bloody_command_enabled defaults false, and Echo of Predation never had
-- a working automatic trigger even in the old codebase.
function SoundsRuntime.PlayBloodyCommandSound()
    local settings = getSettings()
    if not settings or settings.Get("sound.bloody_command_enabled") == false then
        return false
    end

    local path = settings.Get("sound.bloody_command_path")
    local cooldown = settings.Get("sound.alert_cooldown_seconds")
    return playPath("bloody_command", path, cooldown)
end

function SoundsRuntime.PlayEchoOfPredationSound()
    local settings = getSettings()
    if not settings then
        return false
    end

    local path = settings.Get("sound.echo_of_predation_path")
    local cooldown = settings.Get("sound.alert_cooldown_seconds")
    return playPath("echo", path, cooldown)
end

Preydator:RegisterModule("SoundsRuntime", SoundsRuntime)
return SoundsRuntime
