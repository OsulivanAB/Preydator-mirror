---@diagnostic disable
-- Preydator Localization Bootstrap
-- Must load before all other Preydator files (listed first in .toc).
-- Creates PreydatorL global; any string not found falls back to its English key.

if not _G.PreydatorL then
    _G.PreydatorL = setmetatable({}, {
        __index = function(_, k) return k end,
    })
end

-- Default English launch strings for 3.0; these remain available even when an
-- active locale file is intentionally a translation guide instead of a live map.
_G.PreydatorL["Preydator Updates: New in 3.0"] = "Preydator 3.0 is live."
_G.PreydatorL["PREYDATOR_3_0_WHATS_NEW_BODY"] = "Preydator 3.0 is live.\n\n- Removed Currency and Warband modules from the core addon.\n- Hunt, Bar, and Sounds features remain intact.\n- Added a safe new splash flow and runtime cleanup.\n\nIf you already have windows placed, your saved layout stays intact."
_G.PreydatorL["Got It"] = "Got It"
_G.PreydatorL["Open Settings"] = "Open Settings"

-- Default English strings for UI/Splash.lua's 4.0.0 "what's new" popup. Same
-- reasoning as the 3.0 strings above: these keys aren't plain English on
-- their own (unlike most L() calls elsewhere, which use the English text
-- itself as the key), so they need an explicit default here rather than
-- relying on LocalizationAdapter's key-as-fallback behavior.
_G.PreydatorL["Preydator 4.0.0 Splash Title"] = "Preydator 4.0.0 is live!"
_G.PreydatorL["PREYDATOR_4_0_0_HIGHLIGHTS_BODY"] = "Preydator has been rebuilt from the ground up. Highlights:\n\n"
    .. "- Redesigned, draggable/resizable bar with a full vertical layout option.\n"
    .. "- Settings moved into Blizzard's own Options window (Escape > Options > AddOns > Preydator, or /preydator).\n"
    .. "- Redesigned Hunt Table panel: reward icons, achievement badges, and on-panel grouping/sorting.\n"
    .. "- New Mob Scanner sounds for Pack Ambush and Exploding Corpse Snakes, detected reliably "
    .. "instead of guessing from chat.\n"
    .. "- The bar's text now changes too during a real ambush or Pack Ambush, not just the sound.\n"
    .. "- New \"Amplify Alert Sounds\" option and custom sound file support.\n\n"
    .. "See the full CHANGELOG for everything else."
_G.PreydatorL["PREYDATOR_4_0_0_ICONS_BODY"] = "Hunt Table icons, explained:\n\n"
    .. "- Skull icon (Normal / Hard / Nightmare): the hunt's difficulty.\n"
    .. "- Small badge icon on a hunt row: this hunt still counts toward a Prey achievement you "
    .. "haven't finished. Hover it for details.\n"
    .. "- Reward icons: hover any of them for the item/currency's full name and quantity."
_G.PreydatorL["PREYDATOR_4_0_0_LIMITATIONS_BODY"] = "A couple of things worth knowing:\n\n"
    .. "- Blizzard's own prey icon can briefly reappear if that happens while you're in combat -- "
    .. "addons can't hide UI during combat. It corrects itself once combat ends.\n"
    .. "- A small number of unusual zone shapes may cause a brief bar flicker right at the very "
    .. "start of a hunt.\n"
    .. "- The \"Dialog\" sound channel can cut alerts short if two fire close together -- use "
    .. "\"Master\" or \"SFX\" to avoid this.\n"
    .. "- Korean/Simplified Chinese difficulty-text detection is incomplete for hunts not yet in the addon's data.\n\n"
    .. "Full details in CHANGELOG.md."
