-- Preydator :: Core/Adapters/SoundAdapter.lua
-- Author: RagingAltoholic
-- Responsibility: the only file that calls PlaySoundFile or touches sound
-- CVars. Pure playback/volume mechanics -- no path resolution, no settings
-- knowledge, no decision about when to amplify (that belongs to
-- SoundsRuntime).
-- Reads: nothing.
-- Writes: nothing addon-visible -- BoostVolume/RestoreVolume mutate the
-- player's own sound CVars (restored on the matching RestoreVolume call) and
-- a private ref-count/cache local to this file, not shared/domain state.

local Preydator = _G.Preydator
local PlaySoundFile = _G.PlaySoundFile
local GetCVar = _G.GetCVar
local SetCVar = _G.SetCVar

local SoundAdapter = {}

local VALID_CHANNELS = {
    Master = true,
    SFX = true,
    Dialog = true,
    Ambience = true,
    Music = true,
}

function SoundAdapter.IsChannelValid(channel)
    return type(channel) == "string" and VALID_CHANNELS[channel] == true
end

-- Plays path on channel (falls back to "SFX" if channel is invalid). Returns
-- willPlay (boolean) and the channel actually used.
function SoundAdapter.Play(path, channel)
    if type(path) ~= "string" or path == "" then
        return false
    end
    if type(PlaySoundFile) ~= "function" then
        return false
    end

    if not SoundAdapter.IsChannelValid(channel) then
        channel = "SFX"
    end

    local ok, willPlay = pcall(PlaySoundFile, path, channel)
    if not ok then
        return false
    end

    return willPlay == true, channel
end

-- Volume amplification, modeled on the Better Fishing addon's "Enhance
-- Sounds" mechanic (product owner's reference, 2026-09-04): while a
-- Preydator alert plays, silence ambience/music/pet sounds and push
-- SFX+Master volume up so the alert cuts through other game audio, then
-- restore the player's normal mix afterward. Purely own-client CVars --
-- nothing protected/secret, no taint surface.
--
-- `scale` is an ADDITIVE boost on top of the player's own current
-- Sound_SFXVolume/Sound_MasterVolume, clamped to WoW's 1.0 ceiling -- not an
-- absolute target. A first attempt (2026-09-04) set the CVars directly to
-- `scale`, which meant a player whose normal volume was already above the
-- chosen scale actually got QUIETER during an alert, not louder -- confirmed
-- live (product owner: scale 0.5 produced no audible amplification). The
-- additive form guarantees the boosted volume is never lower than the
-- player's own current volume; higher `scale` only ever helps, and 1 always
-- forces both to full (WoW volume CVars can't exceed 1, so once a player is
-- already at max there's nothing left to add -- the audible improvement at
-- that point comes entirely from the ambience/music/pet-sound muting below).
--
-- Ref-counted (boostRefCount) rather than a plain on/off flag: SoundsRuntime
-- can have two alerts overlap within a few seconds (e.g. an ambush landing
-- right as a stage sound fires), and a naive "restore after N seconds" per
-- call would let the first alert's restore clobber the volume boost the
-- second alert still needs. Only the first BoostVolume call (0 -> 1) caches
-- and applies; only the call that brings the count back to 0 restores.
local AMPLIFY_CVARS_TO_SILENCE = { "Sound_EnableAmbience", "Sound_MusicVolume", "Sound_EnablePetSounds" }
local AMPLIFY_CVARS_TO_ENABLE = { "Sound_EnableSFX", "Sound_EnableAllSound", "Sound_EnableSoundWhenGameIsInBG" }
local AMPLIFY_VOLUME_CVARS = { "Sound_SFXVolume", "Sound_MasterVolume" }

-- Which of AMPLIFY_CVARS_TO_SILENCE would mute the very channel an alert is
-- about to play on -- silencing it during a boost self-blocks the alert.
-- Confirmed live (2026-09-09): Sound Channel set to "Ambience" plus Amplify
-- Alert Sounds enabled meant every boost disabled Sound_EnableAmbience an
-- instant before PlaySoundFile(path, "Ambience") ran, so PlaySoundFile
-- correctly returned false every time -- not a Blizzard bug, a self-inflicted
-- one. "Music" has the same shape via Sound_MusicVolume (silent instead of
-- blocked, since that CVar is a volume level, not an on/off switch). Only
-- these two channels appear here -- SFX/Master/Dialog aren't in
-- AMPLIFY_CVARS_TO_SILENCE at all, so they have no such conflict.
local SILENCE_CVAR_BY_CHANNEL = {
    Ambience = "Sound_EnableAmbience",
    Music = "Sound_MusicVolume",
}

local boostRefCount = 0
local cachedCVars = nil

-- Last BoostVolume call's requested scale plus the before/after value of
-- every volume CVar it touched -- not used for playback logic, exists so
-- /pd sinspect can show whether a boost actually ran and what it computed,
-- instead of the player having to guess from perceived loudness alone
-- (found necessary live, 2026-09-04: the first implementation's bug was only
-- diagnosable once actual before/after numbers were visible).
local lastBoostSnapshot = nil

-- activeChannel is the channel the alert about to play will actually use
-- (sound.channel) -- see SILENCE_CVAR_BY_CHANNEL's own comment for why this
-- matters: silencing the same channel the alert plays on self-blocks it.
-- Returns true if a boost is now active (caller owes a matching
-- RestoreVolume call) and false if CVar access itself isn't available.
function SoundAdapter.BoostVolume(scale, activeChannel)
    if type(GetCVar) ~= "function" or type(SetCVar) ~= "function" then
        return false
    end

    scale = tonumber(scale) or 1
    if scale < 0 then
        scale = 0
    elseif scale > 1 then
        scale = 1
    end

    if boostRefCount == 0 then
        local ok, snapshot = pcall(function()
            local values = {}
            for _, cvar in ipairs(AMPLIFY_CVARS_TO_SILENCE) do
                values[cvar] = GetCVar(cvar)
            end
            for _, cvar in ipairs(AMPLIFY_CVARS_TO_ENABLE) do
                values[cvar] = GetCVar(cvar)
            end
            for _, cvar in ipairs(AMPLIFY_VOLUME_CVARS) do
                values[cvar] = GetCVar(cvar)
            end
            return values
        end)
        if not ok then
            return false
        end
        cachedCVars = snapshot

        local before = { Sound_SFXVolume = snapshot.Sound_SFXVolume, Sound_MasterVolume = snapshot.Sound_MasterVolume }
        local after = {}

        local skipCvar = SILENCE_CVAR_BY_CHANNEL[activeChannel]

        pcall(function()
            for _, cvar in ipairs(AMPLIFY_CVARS_TO_SILENCE) do
                if cvar ~= skipCvar then
                    SetCVar(cvar, 0)
                end
            end
            for _, cvar in ipairs(AMPLIFY_CVARS_TO_ENABLE) do
                SetCVar(cvar, 1)
            end
            for _, cvar in ipairs(AMPLIFY_VOLUME_CVARS) do
                local current = tonumber(snapshot[cvar]) or 1
                local boosted = current + scale
                if boosted > 1 then
                    boosted = 1
                elseif boosted < 0 then
                    boosted = 0
                end
                SetCVar(cvar, boosted)
                after[cvar] = boosted
            end
        end)

        local okTime, now = pcall(_G.GetTime)
        local snapshotTime = (okTime and type(now) == "number") and now or nil
        lastBoostSnapshot = { scale = scale, before = before, after = after, time = snapshotTime }
    end

    boostRefCount = boostRefCount + 1
    return true
end

-- Matching call for every successful BoostVolume -- decrements the ref count
-- and only restores the player's own cached CVar values once it reaches 0.
function SoundAdapter.RestoreVolume()
    if boostRefCount <= 0 then
        return
    end

    boostRefCount = boostRefCount - 1
    if boostRefCount > 0 then
        return
    end

    local snapshot = cachedCVars
    cachedCVars = nil
    if type(snapshot) ~= "table" or type(SetCVar) ~= "function" then
        return
    end

    pcall(function()
        for cvar, value in pairs(snapshot) do
            SetCVar(cvar, value)
        end
    end)
end

-- Shallow copy of the last BoostVolume call's requested scale and the
-- before/after SFX/Master volume it computed, or nil if none has run yet
-- this session. See lastBoostSnapshot's own comment.
function SoundAdapter.GetLastBoostSnapshot()
    if type(lastBoostSnapshot) ~= "table" then
        return nil
    end
    return {
        scale = lastBoostSnapshot.scale,
        before = {
            Sound_SFXVolume = lastBoostSnapshot.before.Sound_SFXVolume,
            Sound_MasterVolume = lastBoostSnapshot.before.Sound_MasterVolume,
        },
        after = {
            Sound_SFXVolume = lastBoostSnapshot.after.Sound_SFXVolume,
            Sound_MasterVolume = lastBoostSnapshot.after.Sound_MasterVolume,
        },
        time = lastBoostSnapshot.time,
    }
end

Preydator:RegisterModule("SoundAdapter", SoundAdapter)
return SoundAdapter
