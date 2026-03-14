# Changelog

## 1.6.0 - 2026-03-14

### Added
- New Currency Tracker system for approved Prey currencies (`3392`, `3316`, `3383`, `3341`, `3343`).
- New Warband currency window with sortable columns and optional realm grouping/subtotals.
- New currency-focused options page controls for tracked IDs, random hunt cost context, gain/spend delta colors, and layout controls.
- New one-time "What's New" splash for the currency feature rollout.
- New Advanced-tab action button: `Show What's New`.

### Changed
- Currency and Warband windows now default to OFF for fresh installs.
- Currency theme naming cleaned up (`Light` instead of `Light (Tan)`).
- Currency options panel streamlined to keep core controls in one place, including a local theme selector.
- Release metadata updated for `1.6.0`.

### Fixed
- Light theme readability improved for text/title contrast.
- Currency window now expands and contracts correctly with tracked-row count.
- Warband table columns remain inside window bounds and auto-fit tracked currency columns.
- Warband sizing now grows and contracts with content demand without forcing manual slider correction.

## 1.5.5 - 2026-03-13

### Added
- Expanded vertical bar setup in Display settings with dedicated controls for orientation, fill direction, vertical scale, text side/alignment, and vertical percent behavior.
- Added vertical tick-percent workflow so percent labels can be shown at tick marks and replace the single vertical percent text when enabled.

### Changed
- Repurposed Display tab control from `Tick Mark Layer` to `Text Display` (`Above Bar` / `Below Bar`) for prefix/suffix stage name placement.
- `Vertical Percent Side` is now focused on tick-mark behavior (`Vertical Percent Tick Mark`) and no longer drives single percent placement logic.
- `Above Ticks` percent mode now renders tick-mark percentages above the bar instead of showing one top-aligned percent value.
- Tick mark rendering now stays above fill by default for consistent readability.

### Fixed
- Corrected a Lua syntax regression in display settings normalization caused by an incomplete conditional branch (`Missed symbol 'then'`).

## 1.5.1 - 2026-03-13

### Added
- New label modes for combined output on one side: `Left (Prefix + Suffix)` and `Right (Prefix + Suffix)`.
- New percent display modes: `Above Bar` and `Above Ticks`.
- New text layout control: `Prefix/Suffix Row` with `Above Bar` or `Below Bar` placement.
- New orientation controls in Display settings: `Bar Orientation` (`Horizontal` or `Vertical`) and `Vertical Fill Direction` (`Fill Up` or `Fill Down`).

### Changed
- Text tab right column is now aligned with left-column prefix/suffix sections for a more symmetrical layout.
- Vertical orientation now supports vertical prefix/suffix rendering while percent text remains horizontal.

### Notes
- Vertical mode is implemented as a practical beta-style option due Blizzard UI constraints around true font rotation; labels are rendered in stacked vertical text.

## 1.5.0 - 2026-03-13

### Added
- New settings checkbox: **Show in Edit Mode preview** so the Preydator bar remains visible while Blizzard Edit Mode is open.
- New setting: **Tick Mark Layer** with `Above Fill` or `Below Fill` modes.
- Expanded **Percent Display** modes with explicit in-bar layering: `In Bar (Above Fill)` and `In Bar (Below Fill)`.
- New modular **tabbed settings UI** that replaces the old single long-form options layout.
- New compact **Edit Mode quick settings** window for common layout controls while Blizzard Edit Mode is open.
- Sliders now include a live value field that can also be typed into directly.
- **Label Mode** dropdown with centered, left-only, right-only, separate prefix/suffix, and no-text layouts.
- Prefix and suffix label support for all four stages, plus dedicated out-of-zone and ambush prefix fields.
- **Border Color** picker with optional link-to-fill behavior.
- **Tick Mark Color** picker in Display settings.
- Static spark line at the right edge of the fill bar for clearer fill-end visibility.

### Changed
- Layering behavior for in-bar percent text is now driven directly by the selected percent display mode.
- Options layout now stays within a strict two-column structure across tabs instead of expanding into an overlong stacked panel.
- Default bar size updated to match the preferred in-game look: **Width 160, Height 29, Scale 0.9**. Existing installs keep their saved values.
- Default **Progress Segments** changed from Quarters to **Thirds**. Existing installs keep their saved value.
- Fill bar and tick marks are inset inside the border so scaling, texture changes, and color changes do not bleed outside the frame.

### Compatibility
- Existing installs keep current saved values; new settings defaults are only applied when a key is missing in `PreydatorDB`.

### Note for users reporting "bar shows 25% at stage start"
This is expected behavior. Blizzard only exposes a stage number (1–4), not a true percent. Stage 1 = entered prey zone = 25% (or 33% in Thirds mode) is the first meaningful progress state the addon can report. Stage 4 = prey visible on map = 100%.

## 1.1.2 - 2026-03-06

### Changed
- Release polish pass for stage-4 prey encounter behavior and map-open fallback interactions.
- Core slash help now only lists user-facing commands.
- Encounter suppression gating tightened to active prey hunt flow only (`active quest` + `in zone` + `stage > 1`).

### Fixed
- Stage-4 bar click fallback no longer depends on waypoint availability; map opening proceeds even when quest coordinates are unavailable.
- Prevented duplicate map toggles from mouse down/up double execution in stage-4 fallback mode.
- Hardened widget suppression paths against restricted/forbidden table access and animation-group API misuse.

### Dev / Internal
- Debug inspect slash handling moved out of core command flow and delegated to optional modules.
- Added optional debug module: `Modules/DebugInspect.lua` (not loaded by default in `Preydator.toc`).

## 1.1.1 - 2026-03-06

### Added
- New settings checkbox: **Disable Default Prey Icon**.
- Stage 4 quick-navigation: click the default prey encounter icon to open the world map and set a waypoint for the active prey quest.
- Stage 4 fallback when icon is hidden: click the locked Preydator bar to open the world map and set prey quest waypoint.

### Fixed
- Resolved startup/runtime Lua error from calling `NormalizeSoundSettings` before local function initialization.
- Resolved a second ordering regression where `GetSoundPathForKey` could be called before local function initialization.
- Added explicit forward declarations for both helpers to prevent nil global-call failures during early settings normalization paths.
- Hardened ambush chat detection against tainted/secret chat strings to avoid `attempt to compare local 'message'` runtime errors.
- Disabled ambush chat scanning while in `party`, `raid`, `scenario`, or `delve` instances where Blizzard restricts actionable chat payloads.
- Disabled ambush chat scanning when no active prey quest is tracked.
- Improved default prey icon toggle behavior by scanning prey widget frame regions so icon hide/show applies more reliably across widget containers.
- Default prey encounter suppression now only applies during active prey hunt stages (in-zone or while progress data is active).

## 1.1.0 - 2026-03-05

### Added
- Ambush alert system updates: configurable ambush sound/visual toggles and custom ambush text override support.
- In-settings **Custom Sound Files** tools to add and remove entries without slash commands.
- Flexible custom sound input handling: accepts names without spaces, optional `.ogg`, and optional full addon sound path prefix.

### Changed
- Ambush sound default is now `predator-kill.ogg`.
- Sound failure warning text now points to the current custom file workflow.
- Debug logging now defaults to **off** at startup.

### Fixed
- Removal logic now handles legacy malformed custom sound entries more reliably (without enabling space-containing names).

## 1.0.2 - 2026-03-04

### Changed
- `Only show in prey zone` behavior now works as: unchecked = bar visible, checked = hide unless active prey is in-zone.
- Progress tick marks now show only `25`, `50`, and `75` (removed `0`).

## 1.0.1 - 2026-03-04

### Added
- New settings option: **Only show in prey zone** to hide the bar while you are outside the active prey zone.

### Changed
- Replaced **Show when no active prey** with **Only show in prey zone** for clearer visibility behavior.
- README now clarifies out-of-zone visibility behavior and the new zone-gated display option.

### Fixed
- `/preydator options` and `/pd options` now open the settings category using a valid numeric category ID in modern Settings API flows.
- Resolved Lua error: `bad argument #1 to 'OpenSettingsPanel'` caused by passing a string category name to `Settings.OpenToCategory`.

## 1.0.0 - 2026-03-03

### Added
- Full settings panel for bar visuals, fonts, colors, labels, and sound behavior.
- Stage sound test buttons directly in settings.
- `/pd inspect` diagnostics for live quest/widget/bar state.
- Full reset-to-defaults support from settings.

### Changed
- Stage model finalized to 4 hunt stages:
  1. Scent in the Wind
  2. Blood in the Shadows
  3. Echoes of the Kill
  4. Feast of the Fang
- Final stage display is locked to 100% for consistent end-stage feedback.
- Bar scaling behavior updated to resize around a stable center anchor.
- README refreshed for release usage and customization guidance.

### Fixed
- Color picker callback/session handling issues across multiple swatches.
- Reset workflow now refreshes controls and values correctly in the settings UI.
- Bar position persistence/lock behavior regressions during iterative tuning.

### Removed
- Redundant slash sound test commands (replaced by settings test buttons).
- Redundant slash reset command (replaced by settings reset controls).
- Nameplate texture preset from texture options.
