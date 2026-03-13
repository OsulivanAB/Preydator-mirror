# Changelog

## 1.1.3 - 2026-03-13

### Added
- New settings checkbox: **Show in Edit Mode preview** so the Preydator bar remains visible while Blizzard Edit Mode is open (improves layout workflow compatibility, including Luxthos-style presets).
- New setting: **Tick Mark Layer** with `Above Fill` or `Below Fill` modes.
- Expanded **Percent Display** modes with explicit in-bar layering: `In Bar (Above Fill)` and `In Bar (Below Fill)`.

### Changed
- Layering behavior for in-bar percent text is now driven directly by the selected percent display mode.

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
