-- Preydator :: Core/SlashCommands.lua
-- Author: RagingAltoholic
-- Responsibility: the /pd diagnostic slash command -- inspect/qinspect/
-- hinspect/pinspect, each optionally routed to BugSack via a trailing "bs"
-- (matches the old codebase's exact naming convention). Thin dispatcher
-- only: report content lives in Core/Runtime/DiagnosticsRuntime.lua.
-- Reads: Core/Runtime/DiagnosticsRuntime.lua.
-- Writes: nothing.

local Preydator = _G.Preydator
local geterrorhandler = _G.geterrorhandler

local SlashCommands = {}

-- Routes text through BugGrabber's error handler for easy copy-paste out of
-- BugSack (same pattern validated this session during reward-API research) --
-- always falls back to a plain chat print too rather than depending on it.
local function emit(text, toBugSack)
    if toBugSack then
        local dispatched = pcall(function()
            local handler = geterrorhandler()
            if type(handler) ~= "function" then
                error("no error handler installed")
            end
            handler(text)
        end)
        print(dispatched and "Preydator (also sent to BugSack):"
            or "Preydator (BugSack dispatch failed, chat only):")
    end
    print(text)
end

local function getDiagnostics()
    return Preydator:GetModule("DiagnosticsRuntime")
end

local COMMANDS = {
    inspect = function()
        local d = getDiagnostics()
        return d and d.BuildGeneralInspectReport()
    end,
    hinspect = function()
        local d = getDiagnostics()
        return d and d.BuildHuntInspectReport()
    end,
    pinspect = function()
        local d = getDiagnostics()
        return d and d.BuildProgressInspectReport()
    end,
    qinspect = function(arg)
        local d = getDiagnostics()
        return d and d.BuildQuestInspectReport(arg)
    end,
    sinspect = function()
        local d = getDiagnostics()
        return d and d.BuildSoundInspectReport()
    end,
    ninspect = function()
        local d = getDiagnostics()
        return d and d.BuildNameplateTraceReport()
    end,
    -- TEMP DIAGNOSTIC (2026-08-28) -- widgetSnapshot investigation, see
    -- WidgetAdapter.DebugWidgetState's comment. Remove once the real cause
    -- is found and fixed.
    wdebug = function()
        local widgetAdapter = Preydator:GetModule("WidgetAdapter")
        return widgetAdapter and type(widgetAdapter.DebugWidgetState) == "function"
            and widgetAdapter.DebugWidgetState()
    end,
}

local USAGE = "Preydator commands: /pd inspect [bs] | qinspect [questID] [bs] | hinspect [bs] "
    .. "| pinspect [bs] | sinspect [bs] | ninspect [bs] (nameplate trace, needs Settings > "
    .. "Advanced > Verbose Pack Ambush Debug Logging on) | segments (toggle bar.progress_segments "
    .. "quarters/thirds, macro-friendly)"

local function handleCommand(msg)
    msg = (msg or ""):match("^%s*(.-)%s*$")
    local command, rest = msg:match("^(%S*)%s*(.-)$")
    command = string.lower(command or "")

    -- Toggles the real bar.progress_segments setting (not a separate
    -- preview) so it's a single macro-able command, per the product owner's
    -- request (2026-08-28) -- a prior text-overlay-preview approach didn't
    -- work out well in practice and was removed in favor of this.
    if command == "segments" then
        local settings = Preydator:GetModule("Settings")
        if not settings then
            print("Preydator: Settings module unavailable.")
            return
        end
        local current = settings.Get("bar.progress_segments") or "quarters"
        local nextMode = (current == "quarters") and "thirds" or "quarters"
        settings.Set("bar.progress_segments", nextMode)
        print("Preydator: bar.progress_segments = " .. nextMode)
        return
    end

    local builder = COMMANDS[command]
    if not builder then
        print(USAGE)
        return
    end

    -- rest may be "bs", "<questID>", "<questID> bs", or empty -- "bs" as a
    -- standalone trailing word toggles BugSack dispatch, whatever's left
    -- (if anything) is passed through as the command's own argument
    -- (currently only qinspect's optional questID uses this).
    local toBugSack = false
    local arg = rest
    if rest:lower():match("%f[%a]bs%f[%A]") then
        toBugSack = true
        arg = rest:gsub("%f[%a]bs%f[%A]", ""):match("^%s*(.-)%s*$")
    end

    local report = builder(arg ~= "" and arg or nil)
    if not report then
        emit("Preydator: report unavailable (DiagnosticsRuntime not loaded).", toBugSack)
        return
    end
    emit(report, toBugSack)
end

_G.SLASH_PREYDATORDIAG1 = "/pd"
_G.SlashCmdList["PREYDATORDIAG"] = handleCommand

Preydator:RegisterModule("SlashCommands", SlashCommands)
return SlashCommands
