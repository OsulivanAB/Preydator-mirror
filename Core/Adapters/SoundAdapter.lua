-- Preydator :: Core/Adapters/SoundAdapter.lua
-- Author: RagingAltoholic
-- Responsibility: the only file that calls PlaySoundFile. Pure playback mechanics
-- -- no path resolution, no settings knowledge (that belongs to SoundsRuntime).
-- Reads: nothing.
-- Writes: nothing (pure adapter).

local Preydator = _G.Preydator
local PlaySoundFile = _G.PlaySoundFile

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

Preydator:RegisterModule("SoundAdapter", SoundAdapter)
return SoundAdapter
