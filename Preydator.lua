-- Preydator :: Preydator.lua
-- Author: RagingAltoholic
-- Responsibility: create the Preydator namespace, the module registry, and
-- load-order-safe event bootstrap. No settings defaults, no state table, no UI
-- construction, no business logic -- all of that lives in the modules below.
-- Reads: nothing.
-- Writes: the module registry only.

local ADDON_NAME = ...

_G.Preydator = _G.Preydator or {}
local Preydator = _G.Preydator

Preydator.modules = Preydator.modules or {}
-- Thin, extensible façade for cross-cutting public functions. Modules add their
-- own entries here as they land; bootstrap only creates the container.
Preydator.API = Preydator.API or {}

function Preydator:RegisterModule(name, moduleTable)
    assert(type(name) == "string" and name ~= "", "module name must be a non-empty string")
    assert(type(moduleTable) == "table", "module table must be a table")
    assert(self.modules[name] == nil, "module '" .. name .. "' already registered")
    moduleTable.name = name
    self.modules[name] = moduleTable
    return moduleTable
end

function Preydator:GetModule(name)
    if type(name) ~= "string" or name == "" then
        return nil
    end
    return self.modules[name]
end

local CreateFrame = _G.CreateFrame

local bootstrapFrame = CreateFrame("Frame", "PreydatorBootstrapFrame")
bootstrapFrame:RegisterEvent("ADDON_LOADED")
bootstrapFrame:RegisterEvent("PLAYER_LOGIN")
bootstrapFrame:SetScript("OnEvent", function(_, event, ...)
    if event == "ADDON_LOADED" then
        local loadedAddonName = ...
        if loadedAddonName ~= ADDON_NAME then
            return
        end
    end

    local eventRuntime = Preydator:GetModule("EventRuntime")
    if eventRuntime and type(eventRuntime.HandleEvent) == "function" then
        eventRuntime:HandleEvent(event, ...)
    end
end)
