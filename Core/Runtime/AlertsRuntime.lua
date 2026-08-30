-- Preydator :: Core/Runtime/AlertsRuntime.lua
-- Author: RagingAltoholic
-- Responsibility: chat-text pattern matching for ambush/Bloody Command
-- triggers, gated by settings + restricted-instance + active-prey-context.
-- Calls into SoundsRuntime and State -- never touches chat frames or UI.
-- Reads: Core/State.lua, Settings, MapContextAdapter.
-- Writes: nothing (delegates playback to SoundsRuntime).
--
-- Bloody Command (Astalor Bloodsworn) was a Season 1 mechanic; patch 12.1
-- discontinued it, so its chat phrases will never appear in current content.
-- Left dormant (default sound.bloody_command_enabled = false, see
-- SettingsStore) rather than removed, per the 2026-08-25 decision in the
-- architecture doc's Section 19.

local Preydator = _G.Preydator

local AlertsRuntime = {}

local BLOODY_COMMAND_CHAT_PHRASE = "kill for me. now!"
local BLOODY_COMMAND_CHAT_PHRASE_2 = "drain their anguish!"
local BLOODY_COMMAND_CHAT_SOURCE = "astalor bloodsworn"
local AMBUSH_CHAT_FALLBACK_PHRASES = {
    "ambush",
    "you've stumbled right into my trap",
    "a momentary setback",
}
local MAX_STAGE = 4

local CHAT_TRIGGER_EVENTS = {
    CHAT_MSG_SYSTEM = true,
    CHAT_MSG_MONSTER_SAY = true,
    CHAT_MSG_MONSTER_YELL = true,
    CHAT_MSG_MONSTER_EMOTE = true,
    CHAT_MSG_RAID_BOSS_EMOTE = true,
    RAID_BOSS_EMOTE = true,
}

local function containsInsensitive(haystack, needle)
    if type(haystack) ~= "string" or type(needle) ~= "string" or needle == "" then
        return false
    end

    local ok, found = pcall(function()
        return string.find(string.lower(haystack), string.lower(needle), 1, true) ~= nil
    end)
    return ok and found or false
end

local function preyNameTokenMatch(preyName, message, sender)
    if type(preyName) ~= "string" or preyName == "" then
        return false
    end

    for token in string.gmatch(string.lower(preyName), "[%a%d]+") do
        if #token >= 4 and (containsInsensitive(message, token) or containsInsensitive(sender, token)) then
            return true
        end
    end
    return false
end

local function isAmbushFallbackMessage(message)
    if type(message) ~= "string" then
        return false
    end

    local lowered = string.lower(message)
    for _, phrase in ipairs(AMBUSH_CHAT_FALLBACK_PHRASES) do
        if string.find(lowered, phrase, 1, true) then
            return true
        end
    end
    return false
end

local function isAmbushMessage(preyName, message, sender)
    if containsInsensitive(message, preyName) or containsInsensitive(sender, preyName) then
        return true
    end
    if preyNameTokenMatch(preyName, message, sender) then
        return true
    end
    return isAmbushFallbackMessage(message)
end

local function isBloodyCommandMessage(message, sender)
    if type(message) ~= "string" then
        return false
    end

    local lowered = string.lower(message)
    if string.find(lowered, BLOODY_COMMAND_CHAT_PHRASE, 1, true)
        or string.find(lowered, BLOODY_COMMAND_CHAT_PHRASE_2, 1, true) then
        return true
    end

    if type(sender) == "string" and string.find(string.lower(sender), BLOODY_COMMAND_CHAT_SOURCE, 1, true) then
        if string.find(lowered, BLOODY_COMMAND_CHAT_PHRASE, 1, true)
            or string.find(lowered, BLOODY_COMMAND_CHAT_PHRASE_2, 1, true) then
            return true
        end
    end

    return false
end

local function isNightmareDifficulty(difficulty)
    return type(difficulty) == "string" and string.find(string.lower(difficulty), "nightmare", 1, true) ~= nil
end

-- event, message and sender mirror EventRuntime's dispatch signature
-- (HandleChatEvent(event, ...) forwards every WoW chat-event payload arg).
function AlertsRuntime.HandleChatEvent(event, message, sender)
    if not CHAT_TRIGGER_EVENTS[event] then
        return
    end

    local state = Preydator:GetModule("State")
    local settings = Preydator:GetModule("Settings")
    local mapContext = Preydator:GetModule("MapContextAdapter")
    local sounds = Preydator:GetModule("SoundsRuntime")
    if not (state and settings and sounds) then
        return
    end

    if state.IsPollingActive() == false then
        return
    end
    if mapContext and mapContext.IsRestrictedInstance() then
        return
    end

    local snapshot = state.GetSnapshot()
    local activeQuestID = snapshot.activeQuestID
    local stage = tonumber(snapshot.stage)

    -- Ambush: only while a hunt is active, not yet at the final stage, and not
    -- confirmed outside the prey zone. Unknown zone (nil) does not block --
    -- receiving an NPC's ambush chat means the player is physically near it.
    if activeQuestID and stage and stage < MAX_STAGE and snapshot.inPreyZone ~= false then
        if settings.Get("general.sounds_enabled") ~= false
            and isAmbushMessage(snapshot.preyTargetName, message, sender) then
            sounds.PlayAmbushSound()
        end
    end

    -- Bloody Command: nightmare-difficulty hunts, stages 1-3 only.
    if stage and stage >= 1 and stage <= 3
        and isNightmareDifficulty(snapshot.preyTargetDifficulty)
        and isBloodyCommandMessage(message, sender) then
        sounds.PlayBloodyCommandSound()
    end
end

Preydator:RegisterModule("AlertsRuntime", AlertsRuntime)
return AlertsRuntime
