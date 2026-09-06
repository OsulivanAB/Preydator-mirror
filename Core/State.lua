-- Preydator :: Core/State.lua
-- Author: RagingAltoholic
-- Responsibility: the single authoritative runtime-state table. Nothing outside
-- this file mutates it -- every write goes through one of the setters below,
-- which validate before writing and notify subscribers after.
-- Reads: nothing external.
-- Writes: its own table, via setters only.

local Preydator = _G.Preydator

local State = {}

local state = {
    activeQuestID = nil,
    stage = nil,
    progressPercent = nil,
    preyTargetName = nil,
    preyTargetDifficulty = nil,
    inPreyZone = false,
    expectedZoneMapID = nil,
    questListenUntil = nil,
    pollingActive = true,
    ambushTextKind = nil,
    ambushTextSourceName = nil,
    ambushTextExpiresAt = nil,
}

local subscribers = {}

local function notify()
    local snapshot = State.GetSnapshot()
    for _, callback in ipairs(subscribers) do
        pcall(callback, snapshot)
    end
end

function State.GetSnapshot()
    local snapshot = {}
    for key, value in pairs(state) do
        snapshot[key] = value
    end
    return snapshot
end

function State.Subscribe(callback)
    if type(callback) ~= "function" then
        return
    end
    table.insert(subscribers, callback)
end

function State.SetActiveQuestID(questID)
    if questID ~= nil and type(questID) ~= "number" then
        return
    end
    state.activeQuestID = questID
    notify()
end

function State.SetStage(stage)
    if stage ~= nil and type(stage) ~= "number" then
        return
    end
    state.stage = stage
    notify()
end

function State.SetProgressPercent(percent)
    if percent ~= nil and type(percent) ~= "number" then
        return
    end
    state.progressPercent = percent
    notify()
end

function State.SetPreyTargetName(name)
    if name ~= nil and type(name) ~= "string" then
        return
    end
    state.preyTargetName = name
    notify()
end

function State.SetPreyTargetDifficulty(difficulty)
    if difficulty ~= nil and type(difficulty) ~= "string" and type(difficulty) ~= "number" then
        return
    end
    state.preyTargetDifficulty = difficulty
    notify()
end

function State.SetInPreyZone(value)
    state.inPreyZone = value == true
    notify()
end

function State.SetExpectedZoneMapID(mapID)
    if mapID ~= nil and type(mapID) ~= "number" then
        return
    end
    state.expectedZoneMapID = mapID
    notify()
end

function State.SetQuestListenUntil(timestamp)
    if timestamp ~= nil and type(timestamp) ~= "number" then
        return
    end
    state.questListenUntil = timestamp
    notify()
end

-- Transient ambush/Pack Ambush bar-text state. `kind` is "ambush",
-- "pack_ambush", or nil to clear; `sourceName` is the token value BarRuntime
-- substitutes into text.ambush_suffix_template/text.pack_ambush_suffix_template
-- ({preyTargetName}/{packAmbushSourceName}); `expiresAt` is a GetTime()
-- timestamp -- BarRuntime treats the text as active only while GetTime() is
-- still before it. AlertsRuntime is the only caller (it owns "how long should
-- this display" as part of the trigger it just fired), so this setter just
-- stores whatever it's given rather than computing a duration itself.
function State.SetAmbushText(kind, sourceName, expiresAt)
    if kind ~= nil and kind ~= "ambush" and kind ~= "pack_ambush" then
        return
    end
    if sourceName ~= nil and type(sourceName) ~= "string" then
        return
    end
    if expiresAt ~= nil and type(expiresAt) ~= "number" then
        return
    end
    state.ambushTextKind = kind
    state.ambushTextSourceName = sourceName
    state.ambushTextExpiresAt = expiresAt
    notify()
end

function State.SetPollingActive(value)
    state.pollingActive = value == true
end

function State.IsPollingActive()
    return state.pollingActive
end

function State.ClearActiveQuest()
    state.activeQuestID = nil
    state.stage = nil
    state.progressPercent = nil
    state.preyTargetName = nil
    state.preyTargetDifficulty = nil
    state.expectedZoneMapID = nil
    state.questListenUntil = nil
    state.ambushTextKind = nil
    state.ambushTextSourceName = nil
    state.ambushTextExpiresAt = nil
    notify()
end

Preydator:RegisterModule("State", State)
return State
