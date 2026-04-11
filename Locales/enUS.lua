---@diagnostic disable
-- Preydator: enUS (English) localization reference.
-- English strings are the keys, so no assignments are strictly required here.
-- This file exists as the authoritative translation guide for other locales.
-- To create a new translation, copy this file, change the locale guard, and fill in values.

-- if GetLocale() ~= "enUS" then return end
-- local L = _G.PreydatorL

--[[  TRANSLATION GUIDE
     Fill in each value with the translated text. Remove the comment markers.
     Entries left empty or commented out will fall back to the English key.
  Do not include Blizzard-static proper names (zone names, NPC names, dungeon/raid names)
  unless the addon itself owns the label text.

---- Stage defaults (displayed in the progress bar; players can override in Options > Text)
  L["No Sign in These Fields"]   = ""
  L["AMBUSH"]                    = ""
  L["Bloody Command"]            = ""
  L["Scent in the Wind"]         = ""
  L["Blood in the Shadows"]      = ""
  L["Echoes of the Kill"]        = ""
  L["Feast of the Fang"]         = ""

---- Options panel tabs
  L["Vertical"]   = ""

---- Section headers
  L["Visual Style"]          = ""
  L["Vertical Mode"]         = ""
  L["Vertical Dimensions"]   = ""
  L["Prefix Labels"]         = ""
  L["Suffix Labels"]         = ""
  L["Sound Selection"]       = ""
  L["Custom Files / Tests"]  = ""
  L["Restore / Reset"]       = ""
  L["Notes"]                 = ""

---- Checkboxes
  L["Lock Bar"]                          = ""
  L["Only show in prey zone"]            = ""
  L["Disable Default Prey Icon"]         = ""
  L["Enable Hunt Table Tracker"]         = ""
  L["Enable sounds"]                     = ""
  L["Ambush sound alert"]                = ""
  L["Ambush visual alert"]               = ""
  L["Bloody Command sound alert"]        = ""
  L["Bloody Command visual alert"]       = ""
  L["Display Spark Line"]                = ""
  L["Link border color to fill"]         = ""
  L["Show Percentage at Tick Marks"]     = ""
  L["Enable Debug"]                      = ""
  L["Currency Debug Events"]             = ""
  L["Show bar during Edit Mode"]         = ""

---- Dropdown field titles
  L["Progress Segments"]        = ""
  L["Sound Channel"]            = ""
  L["Hunt Panel Side"]          = ""
  L["Bar Orientation"]          = ""
  L["Vertical Fill Direction"]  = ""
  L["Vertical Text Side"]       = ""
  L["Vertical Text Alignment"]  = ""
  L["Vertical Percent Display"] = ""
  L["Vertical Percent Tick Mark"] = ""
  L["Percent Display"]          = ""
  L["Text Display"]             = ""
  L["Texture"]                  = ""
  L["Title Font"]               = ""
  L["Percent Font"]             = ""
  L["Ambush Sound"]             = ""
  L["Bloody Command Sound"]     = ""

---- Slider labels
  L["Scale"]                 = ""
  L["Width"]                 = ""
  L["Height"]                = ""
  L["Font Size"]             = ""
  L["Enhance Sounds"]        = ""
  L["Vertical Text Offset"]  = ""
  L["Vertical Percent Offset"] = ""

---- Sound dropdown labels (dynamic Stage N format)
  L["Stage %d Sound"] = ""   -- e.g. "Stage 1 Sound", "Stage 2 Sound"

---- Text input labels
  L["Stage %d"]              = ""   -- e.g. "Stage 1", "Stage 2"
  L["Out of Zone Prefix"]    = ""
  L["Ambush Prefix"]         = ""
  L["Out of Zone Label"]     = ""
  L["Ambush Override Text"]  = ""
  L["Custom Sound File"]     = ""

---- Color buttons
  L["Fill Color"]        = ""
  L["Background Color"]  = ""
  L["Title Color"]       = ""
  L["Percent Color"]     = ""
  L["Tick Mark Color"]   = ""
  L["Border Color"]      = ""

---- Action buttons
  L["Restore Default Names"]   = ""
  L["Restore Default Sounds"]  = ""
  L["Reset All Defaults"]      = ""
  L["Add File"]                = ""
  L["Remove File"]             = ""
  L["Test Stage %d"]           = ""   -- e.g. "Test Stage 1"
  L["Test Ambush"]             = ""
  L["Test Bloody Command"]     = ""
  L["Show What's New"]         = ""

---- Dropdown option values â€” Texture
  L["Default"]          = ""
  L["Flat"]             = ""
  L["Raid HP Fill"]     = ""
  L["Classic Skill Bar"] = ""

---- Dropdown option values â€” Font
  L["Friz Quadrata"]  = ""
  L["Arial Narrow"]   = ""
  L["Skurri"]         = ""
  L["Morpheus"]       = ""

---- Dropdown option values â€” Sound channel
  L["Master"]   = ""
  L["SFX"]      = ""
  L["Dialog"]   = ""
  L["Ambience"] = ""

---- Dropdown option values â€” Currency theme
  L["Light"]  = ""
  L["Brown"]  = ""
  L["Dark"]   = ""

---- Dropdown option values â€” Percent display
  L["In Bar"]      = ""
  L["Above Bar"]   = ""
  L["Above Ticks"] = ""
  L["Under Ticks"] = ""
  L["Below Bar"]   = ""
  L["Off"]         = ""

---- Dropdown option values â€” Tick layer
  L["Above Fill"] = ""
  L["Below Fill"] = ""

---- Dropdown option values â€” Progress segments
  L["Quarters (25/50/75/100)"] = ""
  L["Thirds (33/66/100)"]      = ""

---- Dropdown option values â€” Label mode
  L["Centered"]                 = ""
  L["Left (Prefix only)"]       = ""
  L["Left (Prefix + Suffix)"]   = ""
  L["Left (Suffix only)"]       = ""
  L["Right (Suffix only)"]      = ""
  L["Right (Prefix + Suffix)"]  = ""
  L["Right (Prefix only)"]      = ""
  L["Separate (Prefix + Suffix)"] = ""
  L["No Text"]                  = ""

---- Dropdown option values â€” Label row
  L["Above Bar"] = ""   -- shared key
  L["Below Bar"] = ""   -- shared key

---- Dropdown option values â€” Orientation
  L["Horizontal"] = ""
  L["Vertical"]   = ""

---- Dropdown option values â€” Vertical fill
  L["Fill Up"]   = ""
  L["Fill Down"] = ""

---- Dropdown option values â€” Sides
  L["Left"]   = ""
  L["Right"]  = ""
  L["Center"] = ""

---- Dropdown option values â€” Vertical text align
  L["Top Align"]           = ""
  L["Middle Align"]        = ""
  L["Bottom Align"]        = ""
  L["Top Prefix Only"]     = ""
  L["Top Suffix Only"]     = ""
  L["Bottom Prefix Only"]  = ""
  L["Bottom Suffix Only"]  = ""
  L["Separate Prefix/Suffix"] = ""

---- Dropdown option values â€” Vertical percent display (short form)
  L["Above"]  = ""
  L["Inside"] = ""
  L["Below"]  = ""

---- Hint/note blocks
  L["HINT_VERTICAL_PERCENT_OFFSET"] = "Vertical Percent Offset applies to vertical side/tick-mark side placements. Use tick marks to replace the single percent value."
  L["HINT_AUDIO_SLIDER"]            = "Slider values can be dragged or typed directly. Custom sound input accepts bare names, .ogg, or full addon paths."
  L["HINT_ADVANCED_NOTES"]          = "Existing installs keep their current saved values. New settings are only applied when a key is missing in PreydatorDB. This panel replaces the old long-form options page but uses the same database. The Inspect feature is compatible with BugSack."
  L["HINT_PANEL_SUBTITLE"]          = "Tabbed options layout with two-column pages. Slider values can be dragged or typed directly."

---- Print / chat messages
  L["Preydator: Added sound file '%s'."]    = ""
  L["Preydator: Removed sound file '%s'."]  = ""
  L["Preydator: No stage %d sound configured."] = ""
  L["Preydator: Stage %d sound file failed to play. Ensure this file exists as .ogg: %s"] = ""

---- EditMode window
  L["Preydator Edit Mode"]       = ""
  L["HINT_EDITMODE_SUBTITLE"]    = "Quick layout controls while Blizzard Edit Mode is open. Full Options can be found in Options > Addons > Preydator."

---- Currency Tracker windows
  L["Preydator Currency"]        = ""
  L["Preydator Warband"]         = ""
  L["Preydator Updates: New in 2.1.1"] = ""
  L["WHATS_NEW_BODY"]            = "Preydator 2.1.1 is live.\n\n- Hunt Tracker now shows achievement guidance on hunts that advance incomplete Prey achievements\n- Achievement marker layout, scaling, and count display were refined for the Hunt Table\n- Hunt reward display now supports icon + text, text only, or compact icon + count styles\n- Loot-triggered currency refreshes were trimmed to reduce unnecessary CPU spikes\n\nIf you already have windows placed, your saved layout stays intact."
  L["Got It"]                    = ""
  L["Open Settings"]             = ""
  L["Open Warband"]              = ""
  L["Close Warband"]             = ""
  L["Gain Color"]                = ""
  L["Spend Color"]               = ""

---- Hunt Table companion panel
  L["Preydator Hunt Tracker"]                          = ""
  L["Rewards unknown"]                                 = ""
  L["Reward data pending"]                             = ""
  L["No available hunts"]                              = ""

---- Currency config page labels
  L["Delta Preview"]                = ""
  L["Normal"]                       = ""
  L["Hard"]                         = ""
  L["Nightmare"]                    = ""
  L["Warband Window"]               = ""

---- Warband column headers
  L["Realm"]     = ""
  L["Character"] = ""
  L["Anguish"]   = ""
  L["N/H/Ni"]    = ""   -- Difficulty abbreviation (Normal/Hard/Nightmare); translators may provide their own

---- Warband dynamic row labels
  L["Total"]     = ""
  L["All Realms"] = ""
  L["Totals"]    = ""

---- Currency tracker summary format

---- Modules page
  L["Module Status"]                                                                                    = ""
  L["Bar Module"]                                                                                       = ""
  L["Controls the main prey progress bar display and behavior."]                                       = ""
  L["Sounds Module"]                                                                                    = ""
  L["Controls stage sounds and ambush audio settings."]                                                = ""
  L["Currency Module"]                                                                                  = ""
  L["Controls the currency tracker panel and currency displays."]                                      = ""
  L["Hunt Table Module"]                                                                               = ""
  L["Controls hunt table data, sorting, and panel features."]                                          = ""
  L["Warband Module"]                                                                                   = ""
  L["Controls the warband currency panel and roster view."]                                            = ""
  L["Reload"]                                                                                           = ""

---- Minimap / LDB tooltip
  L["Left Click: Toggle Currency Window"]  = ""
  L["Right Click: Toggle Warband Window"]  = ""
  L["Shift + Right Click: Open Options"]   = ""
---- Audit-discovered keys (code-referenced, missing from enUS guide)
  L["(no saved themes)"] = ""
  L["Accept"] = ""
  L["Accessibility"] = ""
  L["Achievement Badge Color"] = ""
  L["Achievement Icon Size"] = ""
  L["Achievement Progress"] = ""
  L["Achievement Signal Style"] = ""
  L["Achievements"] = ""
  L["Achievements Theme"] = ""
  L["Active Profile"] = ""
  L["Anchor Align"] = ""
  L["Ascending"] = ""
  L["Bar"] = ""
  L["Bloody Command Prefix"] = ""
  L["Bloody Command Suffix"] = ""
  L["Border"] = ""
  L["Both"] = ""
  L["Bottom"] = ""
  L["Category"] = ""
  L["Champ. Crest"] = ""
  L["Change active profile, create a new one, copy settings between profiles, reset the current profile, or delete an unused profile."] = ""
  L["Characters in Tracker"] = ""
  L["Choose where each currency appears: Currency panel, Warband panel, or both. Category checkboxes apply to all currencies in that section."] = ""
  L["Class color Names"] = ""
  L["Clear Achievement Cache"] = ""
  L["Click to toggle."] = ""
  L["Close Currency"] = ""
  L["Copy another profile into the current one."] = ""
  L["Copy current settings"] = ""
  L["Copy From"] = ""
  L["Copy Into Current"] = ""
  L["Crafting"] = ""
  L["Create Profile"] = ""
  L["Currency"] = ""
  L["Currency Font Size"] = ""
  L["Currency Height"] = ""
  L["Currency Panel"] = ""
  L["Currency Panel Theme"] = ""
  L["Currency Scale"] = ""
  L["Currency Selection"] = ""
  L["Currency Width"] = ""
  L["Current Profile"] = ""
  L["Current Profile:"] = ""
  L["Custom Theme Editor"] = ""
  L["Debug"] = ""
  L["Default Settings"] = ""
  L["Delete"] = ""
  L["Delete Profile"] = ""
  L["Delete Saved Theme"] = ""
  L["Descending"] = ""
  L["Deuteranopia"] = ""
  L["Developer logging toggles for diagnostics and currency event traces."] = ""
  L["Difficulty"] = ""
  L["Dimensions"] = ""
  L["Disable Minimap Button"] = ""
  L["Echo of Predation Sound"] = ""
  L["Enable Global Theme"] = ""
  L["Enter a name and optionally copy your current settings into the new profile."] = ""
  L["Expansion"] = ""
  L["Experience"] = ""
  L["Global Panel Theme"] = ""
  L["Global Theme"] = ""
  L["Group"] = ""
  L["Group Hunts By"] = ""
  L["Hard Difficulty"] = ""
  L["Header BG"] = ""
  L["Hide Currency in Instance"] = ""
  L["Hide Low Level Alts (78)"] = ""
  L["Hide Preview Pane"] = ""
  L["Hide Prey Icon"] = ""
  L["Hide Warband in Instance"] = ""
  L["Horizontal Dimensions"] = ""
  L["Horizontal Text Alignment"] = ""
  L["Horizontal Text Placement"] = ""
  L["Hunt Panel Font Size"] = ""
  L["Hunt Panel Height"] = ""
  L["Hunt Panel Scale"] = ""
  L["Hunt Panel Width"] = ""
  L["Hunt Table Panel"] = ""
  L["Hunt Table Theme"] = ""
  L["Hunt Tracker drives achievement indicators and tooltips in the hunt list. Use preview to test icon style, icon size, and tooltip names with sample achievement data."] = ""
  L["Icon + Count"] = ""
  L["Icon + Text"] = ""
  L["Icon Only"] = ""
  L["In combat it stays hidden until out of combat."] = ""
  L["Keys"] = ""
  L["Load from Preset"] = ""
  L["Lock Frame"] = ""
  L["Maintenance"] = ""
  L["Manage Profiles"] = ""
  L["Middle"] = ""
  L["Module changes require a reload to fully apply. Hunt Table also controls achievement tracking behavior."] = ""
  L["Modules"] = ""
  L["Mouseover Hide"] = ""
  L["Music"] = ""
  L["Muted Color"] = ""
  L["New Profile"] = ""
  L["Nightmare Difficulty"] = ""
  L["No active prey"] = ""
  L["No cached characters yet. Log into alts to populate this list."] = ""
  L["No removable profile is available."] = ""
  L["No tracked rewards"] = ""
  L["None"] = ""
  L["Normal Difficulty"] = ""
  L["On"] = ""
  L["Open Currency"] = ""
  L["Panel hides until moused over."] = ""
  L["Panels"] = ""
  L["Per-Module Themes"] = ""
  L["Per-module themes are ignored while Global Theme is enabled."] = ""
  L["Please enter a profile name."] = ""
  L["Please enter a theme name before saving."] = ""
  L["Position Reset"] = ""
  L["Preview Cache Reward"] = ""
  L["Preview Trinket"] = ""
  L["Preview Weapon"] = ""
  L["Preview: Hard Hunt"] = ""
  L["Preview: Nightmare Hunt"] = ""
  L["Preview: Normal Hunt"] = ""
  L["Prey Track Shows Completed"] = ""
  L["Profile Name:"] = ""
  L["Profiles"] = ""
  L["Protanopia"] = ""
  L["Random Hunts: %d"] = ""
  L["Refresh Hunt Cache"] = ""
  L["Refresh Hunt Table Now"] = ""
  L["Remove Unchecked Characters"] = ""
  L["Reset Bar Position"] = ""
  L["Reset frame anchors if windows are off-screen or misplaced."] = ""
  L["Reset the active profile or delete another unused profile."] = ""
  L["Reset to Defaults"] = ""
  L["Reset Tracker Positions"] = ""
  L["Restore text and audio defaults, or fully reset all profile settings."] = ""
  L["Reward Display Style"] = ""
  L["Row Alt BG"] = ""
  L["Row BG"] = ""
  L["Save Theme"] = ""
  L["Saved themes appear in all theme dropdowns."] = ""
  L["Season Color"] = ""
  L["Seasonal"] = ""
  L["Section BG"] = ""
  L["Select a source profile first."] = ""
  L["Select All Characters"] = ""
  L["Shards"] = ""
  L["Show Achievement Names On Mouseover"] = ""
  L["Show Achievement Signals In Hunt Tracker"] = ""
  L["Show Only In Zone"] = ""
  L["Show Preview Pane"] = ""
  L["Show Prey Track (Alts) in Warband"] = ""
  L["Show Prey Weekly Completed"] = ""
  L["Show Random Hunts Available"] = ""
  L["Show Realm"] = ""
  L["Show Realm in Warband"] = ""
  L["Silence Arator (Astalor Bloodsworn)"] = ""
  L["Sort"] = ""
  L["Sort Direction"] = ""
  L["Sort Hunts By"] = ""
  L["Sounds"] = ""
  L["Source Profile"] = ""
  L["Stage Text"] = ""
  L["Stage Title Color"] = ""
  L["Switch profiles to load a different saved setup immediately."] = ""
  L["Test Echo of Predation"] = ""
  L["Text Color"] = ""
  L["Text Only"] = ""
  L["Theme"] = ""
  L["Theme '%s' deleted."] = ""
  L["Theme '%s' saved."] = ""
  L["Theme Font"] = ""
  L["Theme is missing color elements. Load a preset first."] = ""
  L["Theme Name"] = ""
  L["Theme Preview Pane"] = ""
  L["This hunt helps:"] = ""
  L["Title"] = ""
  L["Top"] = ""
  L["Track Alts Weekly"] = ""
  L["Tracked in Warband"] = ""
  L["Unknown"] = ""
  L["Use Hunt Table controls here to manage sorting, grouping, panel size, and reward cache behavior."] = ""
  L["Use Icons for Warband Currencies"] = ""
  L["Utility actions for release notes and hunt scanner cache maintenance."] = ""
  L["Verbose Bloody Command Debug"] = ""
  L["Voidlight Marl"] = ""
  L["Warband"] = ""
  L["Warband Font Size"] = ""
  L["Warband Height"] = ""
  L["Warband Panel"] = ""
  L["Warband Scale"] = ""
  L["Warband Theme"] = ""
  L["Warband Width"] = ""
  L["When enabled, all panels use the global theme. Disable to set themes per-module below."] = ""
  L["Zone"] = ""

--]]

-- Runtime defaults for semantic keys. These are not English-as-key labels,
-- so they must be explicitly assigned to avoid showing raw key names.
local L = _G.PreydatorL
if not L then
    return
end

L["HINT_VERTICAL_PERCENT_OFFSET"] = "Vertical Percent Offset applies to vertical side/tick-mark side placements. Use tick marks to replace the single percent value."
L["HINT_AUDIO_SLIDER"] = "Slider values can be dragged or typed directly. Custom sound input accepts bare names, .ogg, or full addon paths."
L["HINT_ADVANCED_NOTES"] = "Existing installs keep their current saved values. New settings are only applied when a key is missing in PreydatorDB. This panel replaces the old long-form options page but uses the same database. The Inspect feature is compatible with BugSack."
L["HINT_PANEL_SUBTITLE"] = "Tabbed options layout with two-column pages. Slider values can be dragged or typed directly."
L["HINT_EDITMODE_SUBTITLE"] = "Quick layout controls while Blizzard Edit Mode is open. Full Options can be found in Options > Addons > Preydator."
L["WHATS_NEW_BODY"] = "Preydator 2.1.1 is live.\n\n- Hunt Tracker now shows achievement guidance on hunts that advance incomplete Prey achievements\n- Achievement marker layout, scaling, and count display were refined for the Hunt Table\n- Hunt reward display now supports icon + text, text only, or compact icon + count styles\n- Loot-triggered currency refreshes were trimmed to reduce unnecessary CPU spikes\n\nIf you already have windows placed, your saved layout stays intact."



