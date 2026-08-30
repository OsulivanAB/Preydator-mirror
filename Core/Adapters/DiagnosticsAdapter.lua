-- Preydator :: Core/Adapters/DiagnosticsAdapter.lua
-- Author: RagingAltoholic
-- Responsibility: the only file that reads/writes PreydatorDebugDB; timestamped
-- debug log ring buffer and memory-usage reporting.
-- Reads: PreydatorDebugDB.
-- Writes: PreydatorDebugDB.

local Preydator = _G.Preydator
local GetTime = _G.GetTime
local collectgarbage = _G.collectgarbage

local DiagnosticsAdapter = {}

local LOG_LIMIT = 200

local function getLogDB()
    _G.PreydatorDebugDB = _G.PreydatorDebugDB or {}
    local db = _G.PreydatorDebugDB
    if type(db.entries) ~= "table" then
        db.entries = {}
    end
    return db
end

-- message may be a plain string or a string.format template consumed by ...
function DiagnosticsAdapter.Log(message, ...)
    if type(message) ~= "string" or message == "" then
        return
    end

    local formatted = message
    if select("#", ...) > 0 then
        local ok, result = pcall(string.format, message, ...)
        if ok and type(result) == "string" then
            formatted = result
        end
    end

    local okTime, now = pcall(GetTime)
    local timestamp = (okTime and type(now) == "number") and now or 0

    local db = getLogDB()
    table.insert(db.entries, string.format("%0.3f | %s", timestamp, formatted))

    while #db.entries > LOG_LIMIT do
        table.remove(db.entries, 1)
    end
end

function DiagnosticsAdapter.GetLogs()
    local db = getLogDB()
    local snapshot = {}
    for i, entry in ipairs(db.entries) do
        snapshot[i] = entry
    end
    return snapshot
end

function DiagnosticsAdapter.ClearLogs()
    local db = getLogDB()
    db.entries = {}
end

-- Returns {beforeKB, afterKB, reclaimedKB} from a forced GC pass, or nil if the
-- collectgarbage API is unavailable.
function DiagnosticsAdapter.ReportMemoryUsage()
    if type(collectgarbage) ~= "function" then
        return nil
    end

    local okBefore, before = pcall(collectgarbage, "count")
    if not okBefore or type(before) ~= "number" then
        return nil
    end

    pcall(collectgarbage, "collect")

    local okAfter, after = pcall(collectgarbage, "count")
    if not okAfter or type(after) ~= "number" then
        return nil
    end

    return {
        beforeKB = before,
        afterKB = after,
        reclaimedKB = before - after,
    }
end

Preydator:RegisterModule("DiagnosticsAdapter", DiagnosticsAdapter)
return DiagnosticsAdapter
