# Preydator Rewrite Prompt

This file is meant to be edited to match your vision. It is not meant to lock the project into the original implementation.

Important design boundary:

- This document is a forward-looking product and architecture prompt.
- It should not be used as a code reconstruction guide for the current addon.
- The current addon may be used only as a historical reference for behavior and feature intent.
- If any historical implementation detail is referenced, it belongs in the appendix at the bottom of this document, not in the main design requirements.

---

## Purpose

Build a modern, maintainable version of Preydator as a World of Warcraft addon focused on tracking, displaying, and reacting to active prey hunt progression in a clean, API-first architecture.

The rewrite should preserve the addon’s core purpose while making the code easier to extend, easier to test, easier to debug, and easier to continue developing without coupling gameplay logic to UI code or scattered global state.

The project should follow the principle:

- API layer first
- runtime state second
- UI rendering third
- manual direct API access only where necessary and wrapped behind safe adapters

This is not a rebuild of the old implementation blindly. It is a clean architecture that matches the intent of the addon and can evolve with new features without turning into chaotic procedural code.

---

## Module Boundary Contract

Every module must communicate only through explicit public APIs.

- No module may mutate another module's state table directly.
- No module may read another module's internal locals.
- No module may depend on hidden shared state created ad hoc inside another module.
- All cross-module communication must go through the central addon object registry or a dedicated shared API surface.
- Modules must expose a clear contract for what they read, what they write, and what they publish.

This prevents accidental cross-talk, hidden dependencies, and brittle rewrites.

---

## File Layout Contract

The rewrite must produce a clear file layout with explicit responsibilities.

A recommended structure is:

- Preydator.lua — bootstrap, namespace, module registry
- Core/State.lua — centralized runtime state
- Core/Settings.lua — settings model and defaults
- Core/Adapters/ — Blizzard API wrappers and safe adapters
- Core/Runtime/ — prey context, bar runtime, sound runtime, alerts, diagnostics
- UI/ — bar frames, settings UI, edit mode, panel layout
- Modules/HuntScanner/ — hunt table / scanner logic
- Locals/ — localization data
- Media/ — icons, textures, shared visual assets
- Sounds/ — protected bundled sound files

The AI should not dump all logic into one file. This design encourages organized, multi-file growth and easier maintenance.

---

## State Snapshot Contract

UI must receive immutable state snapshots.

- UI must never mutate live runtime state.
- UI must never store canonical prey values.
- UI must never become the source of truth for quest, zone, or progress data.
- UI must only render what the runtime publishes.
- UI updates should be triggered by state-change events or explicit refresh calls.

This prevents UI-driven logic bugs and keeps gameplay decisions centralized in runtime code.

---

## Event Routing Contract

All events must route through a single dispatcher.

Each event handler must:

1. validate inputs
2. check restricted-instance fail-closed state
3. check active prey context
4. call the appropriate runtime module
5. never perform UI updates directly

The event system should remain lightweight and deterministic. Event handlers should fail fast, drop irrelevant events early, and do minimal work before handing off to a runtime.

---

## Testing & Debugging Expectations

The rewrite must include:

- a diagnostics module
- debug logging with timestamps
- safe pcall wrappers around all Blizzard API calls
- a /preydator debug slash command or equivalent debug UI
- a debug overlay, report window, or console output for logs and state snapshots

Debug support should help developers understand runtime decisions without exposing fragile internals to the UI layer.

---

## Future-proofing / Extensibility

The rewrite must allow future expansion without modifying core modules.

- New prey stages should be addable through stage definitions or runtime data structures.
- New alert types should be added through alert modules rather than editing core logic.
- New UI themes should be addable without changing the rendering core.
- New scan or hunt features should be added as modules instead of editing existing modules in place.

This encourages a plugin-like architecture rather than a rigid one-off implementation.

---

## Strict Naming Conventions

These naming rules must be followed consistently:

- Modules use PascalCase
- internal functions use camelCase
- constants use UPPER_SNAKE_CASE
- settings keys use lower_snake_case
- adapters end with Adapter
- runtimes end with Runtime

This produces consistent code across files and reduces ambiguity across the whole project.

---

## Minimal MVP vs Full Feature Set

The AI should produce both:

- a minimal MVP architecture
- and a full-feature expanded architecture

The product owner may choose which path to follow. This allows early validation without locking the project into an overbuilt design.

---

## Code Style Expectations

The code style should enforce clarity and maintainability:

- no global variables
- no magic numbers
- no inline Blizzard API calls in business logic
- no UI creation inside runtime modules
- no deeply nested conditionals
- prefer early returns
- prefer pure functions where possible
- keep runtime data flow explicit and easy to trace

This makes the generated code easier to maintain and extend.

---

## Model Output Format Expectations

The AI must produce:

- a high-level architecture overview
- module-by-module descriptions
- file layout
- settings catalog
- runtime pipeline
- event flow
- example code for each module
- optional full implementation if requested

This ensures output is comparable across models and easier to review side by side.

---

## Versioning & Migration Contract

SettingsStore must support versioned migrations.

Rules:

- every stored settings schema must include a version number
- old settings must be upgraded through explicit migration steps, not overwritten blindly
- migration logic must be centralized and deterministic
- migrations must preserve unknown or newer keys safely when possible
- invalid or partially corrupted settings must fail gracefully and fall back to defaults rather than crashing the addon
- migration behavior must be testable and traceable

The rewrite must never do a raw reset of the entire settings table unless the data is clearly invalid beyond repair.

The migration contract should explicitly describe:

- current version
- previous supported versions
- migration path from one version to the next
- default fallback behavior
- what gets preserved
- what gets cleaned up

This prevents settings corruption and makes future updates manageable.

---

## Performance Budget

The rewrite must be lightweight enough for WoW event-heavy gameplay.

Rules:

- avoid per-frame OnUpdate loops unless strictly necessary
- polling must be throttled and context-gated
- expensive lookups should be cached when the data is stable
- repeated calculations should be memoized or simplified
- update work should happen only on meaningful state changes
- runtime logic should exit early whenever the player is in a restricted or invalid context
- UI rendering should not trigger expensive work repeatedly during idle frames

The addon should favor event-driven updates over continuous polling. Performance is part of the architecture, not a later cleanup task.

---

## Threading / Async Behavior Rule

World of Warcraft addons are single-threaded and event-driven.

Rules:

- no asynchronous promises
- no threads
- no coroutine-based background work unless the addon already has a clearly defined WoW-safe pattern
- no fake async patterns in Lua or scheduler logic
- all logic must be synchronous and event-driven
- work must be triggered by Blizzard events, timers, or explicit state transitions

The rewrite must not assume modern JavaScript-style async behavior. Lua in WoW is synchronous by default; the addon should respect that runtime model and keep all logic deterministic.

---

## Localization Contract

All user-facing text must go through LocalizationAdapter.

Rules:

- no hardcoded English strings in runtime modules or UI modules
- no literal strings directly embedded in logic for labels, errors, status, or debug text
- localization keys must be centralized
- defaults should exist for missing translations
- UI strings and settings labels must be resolved through a single adapter layer
- addon-generated text and stage labels must respect the same localization path as user-facing UI

This prevents drift between UI text, settings labels, and debug output and keeps the rewrite maintainable for multiple locales.

---

## What the addon does today

Preydator is a prey hunt companion addon that tracks active prey quest progress and displays a progress bar with stage-based notifications.

Core behaviors observed in the current codebase:

- Tracks active prey quest state from Blizzard quest and widget APIs
- Monitors stage progression and current stage labels
- Displays a bar with customizable visuals, tick marks, percent display, and labels
- Shows/hides the bar based on active hunt conditions and prey-zone logic
- Uses stage-based progress fallback because Blizzard does not expose perfect prey percent completion
- Detects hunt zone status and active prey context using safe, sanitized checks
- Plays contextual sounds for stage transitions, ambush events, and Bloody Command / Echo of Predation triggers
- Supports debug inspection commands and runtime diagnostics
- Includes a hunt table / scanner feature that can group, sort, inspect, and provide hunt information
- Includes settings UI and edit mode for placement and customization
- Exposes slash commands for visibility, options, diagnostics, and debug output

---

## Addon scope to preserve

The rewrite should keep these user-facing capabilities at minimum unless explicitly removed intentionally by the product owner:

1. Active prey quest tracking
2. Stage-based progress display
3. In-zone / out-of-zone detection logic
4. Visual customization for the bar
5. Sound customization and playback controls
6. Settings UI and edit mode
7. Diagnostic tools and debug output
8. Hunt table / scanner integration as a major module if still in scope
9. Minimap or addon-compartment launcher support
10. Slash command controls and accessibility

The project owner may choose to simplify or expand these features later, but the initial rewrite should preserve them as modular capabilities rather than baking them into a single large script.

---

## Actual architecture pattern to use as the baseline

The current addon already suggests a workable modular pattern. The rewrite should keep the spirit of that structure but restructure it into a cleaner API-first model.

Use a central addon object with a clear split between:

- addon bootstrap and namespace setup
- runtime state
- user settings
- API adapters
- business logic
- UI layer
- event routing
- diagnostics
- module registration

Current project structure that should inform the rewrite:

- Preydator.lua
- Core/ directory for runtime logic
- Modules/ directory for feature-specific modules
- Locals/ for localization data
- issues/ for planning and prompts
- sounds/ for housing custom sounds files used in the app
- media/ for graphic files used for minimap and difficulties

The rewrite should not invent new top-level structure arbitrarily, but it should reorganize internals cleanly so that modules communicate through explicit APIs instead of direct hidden mutation.

---

## Recommended architecture model

### 1. Core API layer

Create small, well-defined API adapters that wrap Blizzard APIs and internal data. These adapters should be the only place that calls external APIs directly.

Examples of API zones to wrap:

- quest log queries
- map and zone checks
- UI widgets
- quest progression / stage data
- sound playback and file access
- settings persistence
- event registration

Examples of wrappers:

- QuestApiAdapter
- MapContextAdapter
- WidgetAdapter
- SoundAdapter
- SettingsStore
- LocalizationAdapter
- DiagnosticsAdapter

The rule:

- no direct Blizzard calls outside the API adapters
- no runtime code reading raw API values without using a validated adapter

### 2. Runtime state layer

Centralize state in a single authoritative state table.

Examples:

- activeQuestID
- stage
- preyTargetName
- preyTargetDifficulty
- inPreyZone
- lastKnownWidgetSetupAt
- questListenUntil
- huntScanner data
- settings versioning

State must be:

- clearly typed where possible
- updated through explicit setters or update functions
- validated before use
- safe under missing or partial Blizzard data

### 3. Feature runtimes

Break features into runtime modules with explicit responsibilities:

- PreyContextRuntime
- BarRuntime
- EventRuntime
- SoundsRuntime
- SettingsRuntime
- AlertsRuntime
- HuntScannerRuntime
- DiagnosticsRuntime

Each module should expose a clean API for the rest of the addon and should not mutate unrelated state directly.

### 4. UI layer

Keep UI rendering and user interaction separated from gameplay logic.

The bar should receive state and render from the runtime, not the other way around.

Rules:

- UI does not decide quest logic
- UI does not maintain hidden canonical state on its own
- UI updates are driven by state snapshots
- visual settings are applied from a settings model

### 5. Event system

Use one event dispatch path and keep event handling lightweight.

Event handling should:

- validate inputs
- discard irrelevant noisy events quickly
- perform context checks before any expensive work
- trigger runtimes only when the current quest context justifies it

---

## Important APIs currently used by the addon

This rewrite should respect and wrap the APIs already used in the project, not invent new ones.

Examples from the current codebase:

- C_QuestLog.GetLogIndexForQuestID
- C_QuestLog.GetInfo
- C_TaskQuest.GetQuestZoneID
- C_Map.GetMapInfo
- C_SuperTrack or equivalent supertrack features if used in the final product
- PlaySoundFile
- CreateFrame
- GetLocale
- IsInInstance
- GetTime
- UIParent
- Settings API
- SlashCmdList
- LibStub / LibSharedMedia integration
- custom sound validation and protected sound file handling
- chat event messages for ambush and Bloody Command detection

The rewrite should not assume APIs exist without wrapping them safely and guarding for missing values.

---

## Fail-closed behavior in restricted instances

This is a required behavior and must be explicit in the rewrite design.

When Preydator detects that the player is in a restricted instance, it should stop active runtime behavior rather than try to keep running in a partially useful way.

The current implementation does this by treating the following as restricted content:

- pvp
- arena
- party
- raid
- scenario
- delve

Historical traceability only: see Appendix A1 for the restricted-instance guard and Appendix A2 for the runtime event gate that enforce this behavior.

The required rewrite behavior is:

- Once the player is in one of these instance types, Preydator should fail closed.
- The addon should stop active prey polling, stage refresh logic, bar updates, and alert triggers.
- The runtime should disable the bar update loop and set polling inactive.
- The UI should not keep rendering or updating hunt state during restricted-instance play.
- The addon may still initialize safely at login and may still allow settings access, but active prey operation must stop.
- If a new instance begins or a player leaves a restricted zone, the runtime should re-enable only after a valid re-entry flow and clean state refresh.

This should be described as a strict product rule in the AI prompt:

- No runtime prey tracking while in restricted-instance content.
- No unnecessary sound or alert processing while in restricted-instance content.
- No stale state carryover from a prior safe-overworld state after entering a restricted instance.
- Clear a live prey state when the environment is invalid, instead of trying to continue processing it.

---

## Detailed settings catalog

The rewrite must include an explicit settings model and a descriptive list of what each group does. The addon already has a large settings surface, and the rewrite should not hide that detail behind vague names.

The settings should be organized by purpose, not by random UI sections. At minimum, the AI prompt should require these categories:

### 1. General / runtime behavior

These settings control whether the addon is active in normal play and whether the bar or hunt logic is enabled.

Examples:

- bar enabled / disabled
- sounds enabled / disabled
- hunt scanner enabled / disabled
- debug logging enabled / disabled
- module enable / disable state for features like bar, sounds, and hunt modules

### 2. Bar display configuration

These settings control the bar’s appearance and layout.

Examples:

- width, height, scale
- orientation: horizontal / vertical
- bar fill direction for vertical mode
- texture preset
- border color and linked border behavior
- fill color, background color, title color, percentage color, tick color
- bar position anchor and offset
- show/hide ticks
- show spark line
- percent display mode
- label placement above or below the bar
- label mode: centered, left, right, separate, no text
- tick mark visibility and percent text

### 3. Text and label styling

These settings control the text shown on the bar and stage labels.

Examples:

- title font
- percent font
- font size
- stage label values for each stage
- prefix / suffix labeling
- out-of-zone label
- ambush label and trigger text
- Bloody Command label and source text
- text alignment and offset values
- vertical text side and alignment

### 4. Progress logic and stage behavior

These settings change how progress is interpreted and displayed.

Examples:

- progress segment mode: quarters vs thirds
- fallback percentage mode: stage-based fallback
- stage percentage mapping
- stage label visibility
- display of percent inside, above, below, or off

### 5. Sound and alert configuration

These settings determine how sounds trigger and what audio is played.

Examples:

- stage 1-4 sound mappings
- ambush sound path
- Bloody Command sound path
- Echo of Predation sound path
- sound channel selection
- sound enhancement level
- sound enabled flag
- debugging sound toggles
- custom sound list and protected default file handling
- anti-spam or cooldown settings for ambush / echo triggers

### 6. Hunt scanner / hunt table settings

These settings control hunt listing and utility behavior.

Examples:

- hunt table enabled / disabled
- side: left or right
- group by difficulty or zone
- sorting options and direction
- width, height, scale, font size
- group collapse state
- diffilculty image on left / right side setting
- reward display style
- achievement signal style and badge styling
- theme selection for hunt panel

### 7. Accessibility and theme settings

These settings adjust layout and readability.

Examples:

- theme presets
- custom theme editor entries
- color blindness adjustments
- contrast and readability presets
- accessibility-specific palette overrides

### 8. Advanced / debug settings

These settings support diagnostics and troubleshooting.

Examples:

- debug logging enabled
- Bloody Command debug verbosity
- show debug logs
- clear debug logs
- display debug output in report window
- splash screen visibility / first-run welcome prompts

---

## Settings catalog requirement for the rewrite

The AI prompt should explicitly require that every settings value be documented in a settings catalog with the following fields:

- name
- category
- type
- default value
- purpose
- when it is used
- which runtime code reads it
- which runtime code writes it
- whether it is user-configurable or internal only
- whether it is required for safe operation or only cosmetic

This turns settings from a random UI dump into a proper configuration contract.

This is the exact kind of documentation the rewrite should include:

- stageSounds[1] = stage 1 sound path, set by Preydator defaults and user choice
- stageSounds[2] = stage 2 sound path
- stageSounds[3] = stage 3 sound path
- stageSounds[4] = stage 4 sound path
- ambushSoundPath = sound file used for ambush alert
- bloodyCommandSoundPath = sound file used for Bloody Command alert
- echoOfPredationSoundPath = sound file used for Echo of Predation alert
- onlyShowInPreyZone = whether the bar is hidden when not in the prey zone
- disableDefaultPreyIcon = whether the default prey icon is suppressed
- progressSegments = whether stages display as quarters or thirds
- showTicks = whether tick marks are displayed
- showSparkLine = whether a spark effect overlays the fill meter
- orientation = horizontal or vertical bar mode
- labelRowPosition = placement of text relative to the bar
- stageLabelMode = stage text alignment model
- customizationV2.moduleEnabled.bar = runtime gating for the bar module
- customizationV2.moduleEnabled.sounds = runtime gating for the sounds module
- customizationV2.moduleEnabled.hunt = runtime gating for the hunt feature

---

## Default sound files and stage triggers

The rewrite must preserve the current default sound file names and their trigger-purpose mapping. These are not cosmetic defaults; they are part of the addon’s current behavior.

### Default bundled sound files

Historical traceability only: see Appendix B1 for the current default sound file block that this section is describing.

- predator-alert.ogg
- predator-ambush.ogg
- predator-snarl-01.ogg
- predator-torment.ogg
- predator-kill.ogg
- well-we-ve-prepared-a-trap-for-this-predator.ogg
- predator-kills-its-prey-to-survive.ogg
- echo-of-predation.ogg

These are treated as protected default sounds and should not be deleted or replaced silently by the user without warning.

### Current default stage sound mapping

Historical traceability only: see Appendix B2 for the current stage-sound defaults tied to this mapping.

- Stage 1: predator-ambush.ogg
- Stage 2: predator-snarl-01.ogg
- Stage 3: predator-torment.ogg
- Stage 4: predator-kill.ogg

### Current trigger mapping for special alerts

- Ambush trigger sound: well-we-ve-prepared-a-trap-for-this-predator.ogg
- Bloody Command trigger sound: predator-kills-its-prey-to-survive.ogg
- Echo of Predation trigger sound: echo-of-predation.ogg

The rewrite should include these as explicit sound triggers and should keep the default file names as a baseline unless the user intentionally changes them.

The AI should be told to support:

- stage 1 sound config
- stage 2 sound config
- stage 3 sound config
- stage 4 sound config
- ambush sound config
- Bloody Command sound config
- Echo of Predation sound config
- custom sound file add / remove support
- default sound lock protection
- stable ordering for sound list selection

---

## Default stage wording and label behavior

Historical traceability only: see Appendix C1 for the current default stage labels tied to this behavior.

- Stage 1: Scent in the Wind
- Stage 2: Blood in the Shadows
- Stage 3: Echoes of the Kill
- Stage 4: Feast of the Fang

The rewrite must preserve these as the default stage wording unless the user chooses a custom label.

The AI should also preserve the current text placement model from the settings system:

- text can be centered
- text can appear on the left side
- text can appear on the right side
- text can be prefix-only, suffix-only, or prefix + suffix
- text can be placed above or below the bar
- the layout supports separate left and right text sections
- labels can be fully disabled when needed

The current config options and naming in the project point to this behavior:

- label mode: center, left, left combined, left suffix, right, right combined, right prefix, separate, none
- label row: above bar or below bar
- stage label prefix fields
- stage label suffix fields
- out-of-zone text field
- ambush label text field
- Bloody Command label field
- ability to add or remove custom text on either side of the stage label

The rewrite should explicitly support:

- custom prefix text on the left
- custom suffix text on the right
- custom text on either side of the center label area
- left / center / right placement options
- separate prefix and suffix entry boxes
- full custom wording for stage labels
- ability to remove text from a side without resetting the whole label format
- default values that can be restored if the user resets them

This should be treated as a core feature, not an afterthought, and should be reflected in the settings catalog and UI spec.

For traceability, the historical label-setting behavior is referenced in Appendix C2.

---

## Detailed runtime model and data ownership

The rewrite should clearly define ownership for each value used by the addon. This is critical because the current code mixes Blizzard-provided runtime data with addon-internal derived state.

Treat values in the following categories as separate concepts:

### 1. Blizzard truth values
These are authoritative values from the game API and should not be reinterpreted as addon state unless normalized.

Examples:

- active prey quest from quest log / quest progress APIs
- quest log entry details
- isOnMap from quest-log data
- map IDs and zone IDs from the world / quest APIs
- widget data and UIWidget data from Blizzard
- quest stage values surfaced by the Blizzard prey widget or quest APIs
- chat text from system and monster message events

These should always be considered external truth sources and should be read only through a safe adapter layer.

### 2. Preydator-derived state
These values are created by the addon for tracking and display logic.

Examples:

- activeQuestID: derived by Preydator after selecting the active prey quest from the live quest context
- inPreyZone: derived by Preydator from authoritative quest / map checks and current player context
- stage: derived by Preydator from prey-widget progression or fallback stage logic
- lastWidgetSetupAt: internal cache timestamp created by Preydator
- questListenUntil: internal state controlling how long the addon listens for quest changes
- preyTargetName: derived from the active prey quest / target data, normalized by Preydator
- preyTargetDifficulty: normalized difficulty label created by Preydator
- huntsSeen or huntTable cache entries: generated by Preydator for scanner and tracking features
- bar visibility decisions: internal derived state, not raw Blizzard truth

### 3. Settings and configuration state
These are user-controlled values and should be stored in a settings table with versioning.

Examples:

- width, height, scale
- color selections
- sound paths
- enabled / disabled toggles
- label text overrides
- orientation and positioning values
- debug settings
- hunt scanner preferences

### 4. UI state
These values exist only to render or manage the UI and should not become the source of truth for gameplay.

Examples:

- frame visibility
- anchor point
- selected rows in settings UI
- edit mode state
- open / close state of popup panels

---

## Current variable source summary

This is the exact type of source map the rewrite should preserve. The goal is to make it obvious which values are Blizzard-originated and which are Preydator-generated.

| Variable | Source | Meaning | Ownership |
| --- | --- | --- | --- |
| activeQuestID | Blizzard + Preydator | The live active prey quest ID as interpreted by Preydator | Derived by Preydator from Blizzard quest data |
| questID | Blizzard | Quest ID attached to a prey quest or tracker entry | Blizzard |
| isOnMap | Blizzard | Whether the quest is currently on the map according to the quest log / Blizzard state | Blizzard |
| inPreyZone | Preydator | Final zone-state value used for display and gating logic | Preydator |
| stage | Blizzard + Preydator | Current prey stage from widget or fallback logic | Derived by Preydator |
| progressPercent | Blizzard + Preydator | Partial or fallback percent used for the visual bar | Derived / normalized by Preydator |
| preyTargetName | Blizzard + Preydator | Name of the prey target / enemy | Normalized by Preydator |
| preyTargetDifficulty | Blizzard + Preydator | Difficulty label such as normal / hard / nightmare | Normalized by Preydator |
| playerMapID | Blizzard | Current player map ID | Blizzard |
| questMapID | Blizzard + lookup | Expected zone map for a prey quest | Blizzard authoritative; normalized by Preydator |
| lastWidgetSetupAt | Preydator | Timestamp of the last widget setup event used in fallback logic | Preydator |
| lastZoneStatusRefreshAt | Preydator | Timestamp of the last prey-zone refresh | Preydator |
| questListenUntil | Preydator | Internal guard for a short listen window after quest/zone transitions | Preydator |
| huntScanner data | Blizzard + Preydator | Hunt rows, rewards, and groupings assembled from multiple sources | Mixed; assembled by Preydator |
| sound file path | Blizzard + Preydator | Actual sound file used for stage / alert audio | User-selected and resolved by Preydator |
| settings values | User + Preydator | All modifiable behavior and visuals | Preydator |
| frame position and scale | User + Preydator | Bar placement and sizing | Preydator UI state |
| debug log entries | Preydator | Runtime diagnostics for troubleshooting | Preydator |

This should be written into the architecture as a rule:

- Blizzard API values are inputs.
- Preydator values are decisions, caches, and display state.
- The UI must never be treated as source of truth for gameplay data.

---

## Source-of-truth rules for a rewrite

The AI should be instructed to implement the following rules explicitly:

1. State values must be categorized as Blizzard-origin, user-configured, or Preydator-derived.
2. Only Blizzard-origin values may be read directly from Blizzard APIs.
3. Preydator-derived state must be updated through a validated update path.
4. The bar and any UI layer must render from the Preydator state model, never from raw Blizzard payloads.
5. Temporary caches must be labeled as caches and not confused with game truth.
6. Any map / zone / active quest value that cannot be trusted must be treated as unknown, not inferred without validation.

---

## Real-world implementation expectations for the rewrite

The AI should be told to build the system around a maintainable runtime pipeline like this:

1. Read raw Blizzard inputs through adapters.
2. Normalize and validate them.
3. Determine the active prey context.
4. Compute Preydator state.
5. Publish a state snapshot to the UI.
6. Trigger sounds, alerts, and diagnostics based on state transitions.
7. Persist user settings and version them safely.

This style keeps gameplay logic, rendering, and data interpretation cleanly separated.

---

## Safety requirements the rewrite must keep

The original addon contains multiple safety constraints that should be respected in the rewrite, especially because prey hunt widget and map data is sensitive.

Required behaviors:

- Fail closed in restricted content such as party, raid, scenario, delve, arena, PvP
- Avoid raw taint-prone widget value handling without sanitization
- Use pcall-safe wrappers around Blizzard APIs
- Validate and coerce numeric values before comparisons
- Never rely on untrusted map or quest values without canonicalization
- Preserve protected default sounds and avoid deleting bundled sound files
- Use anti-spam logic for alert triggers and sound playback
- Keep state updates deterministic and easy to reason about
- Ensure missing or partial data does not crash the addon

---

## Active prey and zone logic

The core gameplay is not just a bar. It is a live context engine built around a prey quest and a map/zone state machine.

The rewrite must keep the central intent:

- identify the active prey quest
- determine whether the quest is still valid and in progress
- determine whether the player is in the prey zone
- update the bar and alerts based on stage transitions
- keep state stable while the API may briefly fail or provide transitional values

This logic should not be spread across the UI. It should be managed by a dedicated prey context runtime with explicit update functions.

---

## Sound and alert behaviors to preserve

The addon includes important sound-driven alert features that are not optional fluff. They are part of the experience.

Required alerting patterns:

- stage sound triggers
- ambush trigger detection based on active prey context
- Bloody Command scenario and trigger gating
- Echo of Predation detection and sound behavior
- sound channel selection and enhancement settings
- custom sound validation and file ordering
- default sound protection

The rewrite should maintain the sound pipeline as a settings-driven system, not as hardcoded one-off trigger functions.

---

## Module and code quality expectations

The rewrite should be easier to continue building than the original code. That means:

- no giant monolithic script files
- no hidden cross-module mutation
- no ad hoc globals
- no repeated manual API calls in multiple modules
- no hardcoded UI values scattered across logic files
- clear boundaries between state, runtime, adapters, and UI
- easy to add new stages, triggers, or modules without editing unrelated systems

The architecture should feel like a real extension-ready addon, not only a one-off product build.

---

## Implementation goal for the AI

Write a clean, modern, maintainable Preydator rewrite based on the actual project behavior and intended design.

The result should include:

1. a clean bootstrap and namespace setup
2. centralized state and settings storage
3. API adapter layer that wraps Blizzard APIs
4. prey context and quest progress runtime logic
5. bar rendering and calculations
6. sound and alert systems
7. settings UI and edit mode
8. hunt scanner / table logic
9. slash command and debug infrastructure
10. modular architecture that can be extended without reworking the whole addon

Do not simply copy the old code into a cleaner layout. Rebuild the structure around a proper API-first architecture and a maintainable runtime model.

---

## Product owner editing guidance

This prompt is meant to be edited by you, not treated as a hardcoded specification.

Before using it with AI, adjust the sections below to match your current vision:

- remove features you no longer want
- add features you want to prioritize
- decide how much of the Hunt Scanner should stay in scope
- decide whether the bar is the primary focus or the addon should become a broader hunt companion
- decide how much settings UI complexity you want
- decide whether the rewrite should aim for minimal feature parity or a cleaner future product

Keep the AI prompt honest: it should reflect your actual vision now, not the original addon’s historical design.

---

## Short version for reuse in another AI chat

Build a clean rewrite of the Preydator addon for World of Warcraft as a maintainable, API-first prey hunt companion.

The rewrite must enforce a strict fail-closed model in restricted content. If the player is in pvp, arena, party, raid, scenario, or delve, the addon must stop active prey polling, alert processing, and bar updates. Initialize safely at login only, but do not continue prey tracking while the environment is restricted.

The rewrite must also include a fully documented settings catalog with each setting described by category, default value, purpose, usage, and ownership. Every setting should clearly identify whether it comes from Blizzard, the user, or Preydator-derived state.

Preserve the addon’s core intent: track active prey quests, stage progression, prey-zone awareness, visual progress display, sound triggers, settings UI, and debugging tools.

Use a modular architecture with clear separation between:

- addon bootstrap
- state management
- settings
- API adapters
- prey context logic
- event dispatch
- bar rendering
- sounds and alerts
- hunt scanner modules
- diagnostics

Do not invent fake APIs or hidden globals. Wrap all Blizzard API access behind safe adapters. Use sanitized numeric parsing, pcall guards, and fail-closed behavior in restricted content. Keep default bundled sounds protected, and keep alert logic anti-spam and context-gated.

The rewrite should be easier to continue building than the original code, with explicit runtime boundaries, clean modules, and a maintainable API-first design. The final code should be structurally clean, debuggable, safe, and extensible.

---

## Variable ownership checklist for future architecture work

When building or editing the rewrite, every new variable should be tagged with a source label:

- Blizzard
- User setting
- Preydator derived
- UI local only
- cached / temporary

Examples:

- isOnMap = Blizzard
- inPreyZone = Preydator
- activeQuestID = Preydator-derived from Blizzard data
- barVisibility = Preydator-derived
- width = User setting / default value
- soundPath = User setting resolved by Preydator
- frameAnchor = UI local state
- lastRefreshTimestamp = Preydator cache

This should be treated as part of the architecture review before implementation.

---

## Editing checklist

Before sending this prompt to an AI:

- [ ] Confirm the scope you want preserved
- [ ] Remove outdated features you no longer want
- [ ] Add new features you want to prioritize
- [ ] Decide whether Hunt Scanner remains part of the MVP
- [ ] Decide how much settings complexity is acceptable
- [ ] Decide whether this is a rewrite for compatibility or a fresh product direction
- [ ] Add your preferred naming conventions and module boundaries
- [ ] Adjust the tone to match your product vision
- [ ] Review the variable ownership list and correct any source assumptions
- [ ] Decide which values should remain Blizzard-source-of-truth versus addon-derived

This is your working prompt, not a fixed historical artifact.

---

## Appendix: Historical reference only

These code blocks are intentionally kept at the bottom of this document so they can be referenced for traceability without allowing the current implementation to become the design template for the rewrite.

### Appendix A1 — Restricted-instance guard

Section reference: Fail-closed behavior in restricted instances

```lua
local function IsRestrictedInstanceForPreyBar()
    local inInstance = false
    local instanceType = nil

    if IsInInstance then
        local ok, inInst, instType = pcall(IsInInstance)
        if ok then
            inInstance = inInst == true
            instanceType = instType
        end
    end

    if inInstance then
        return instanceType == "pvp"
            or instanceType == "arena"
            or instanceType == "party"
            or instanceType == "raid"
            or instanceType == "scenario"
            or instanceType == "delve"
    end

    if type(IsInScenario) == "function" then
        local okScenario, inScenario = pcall(IsInScenario)
        if okScenario and inScenario == true then
            return true
        end
    end

    return false
end
```

### Appendix A2 — Event gate that disables runtime work in restricted content

Section reference: Fail-closed behavior in restricted instances

```lua
local isRestrictedInstance = type(ctx.isRestrictedInstanceForPreyBar) == "function"
    and ctx.isRestrictedInstanceForPreyBar() == true

if isRestrictedInstance and event ~= "PLAYER_LOGIN" and event ~= "ADDON_LOADED" then
    if type(ctx.setPollingActive) == "function" then
        ctx.setPollingActive(false)
    end
    if type(ctx.updateBarDisplay) == "function" then
        ctx.updateBarDisplay()
    end
    return true
end
```

### Appendix B1 — Default sound file names

Section reference: Default sound files and stage triggers

```lua
local SOUND_FOLDER_PREFIX = "Interface\\AddOns\\Preydator\\sounds\\"
local DEFAULT_SOUND_FILENAMES = {
    "predator-alert.ogg",
    "predator-ambush.ogg",
    "predator-snarl-01.ogg",
    "predator-torment.ogg",
    "predator-kill.ogg",
    "well-we-ve-prepared-a-trap-for-this-predator.ogg",
    "predator-kills-its-prey-to-survive.ogg",
    "echo-of-predation.ogg",
}
```

### Appendix B2 — Current default stage sound mapping

Section reference: Default sound files and stage triggers

```lua
local DEFAULTS = {
    stageSounds = {
        [1] = AMBUSH_SOUND_PATH,
        [2] = "Interface\\AddOns\\Preydator\\sounds\\predator-snarl-01.ogg",
        [3] = TORMENT_SOUND_PATH,
        [4] = KILL_SOUND_PATH,
    },
    ambushSoundPath = "Interface\\AddOns\\Preydator\\sounds\\well-we-ve-prepared-a-trap-for-this-predator.ogg",
    bloodyCommandSoundPath = "Interface\\AddOns\\Preydator\\sounds\\predator-kills-its-prey-to-survive.ogg",
    echoOfPredationSoundPath = "Interface\\AddOns\\Preydator\\sounds\\echo-of-predation.ogg",
}
```

### Appendix C1 — Default stage labels

Section reference: Default stage wording and label behavior

```lua
local DEFAULT_STAGE_LABELS = {
    [1] = _G.PreydatorL["Scent in the Wind"],
    [2] = _G.PreydatorL["Blood in the Shadows"],
    [3] = _G.PreydatorL["Echoes of the Kill"],
    [4] = _G.PreydatorL["Feast of the Fang"],
}
```

### Appendix C2 — Label mode and placement options

Section reference: Default stage wording and label behavior

```lua
local LABEL_MODE_CENTER = "center"
local LABEL_MODE_LEFT = "left"
LABEL_MODE_LEFT_COMBINED = "left_combined"
local LABEL_MODE_RIGHT = "right"
LABEL_MODE_RIGHT_COMBINED = "right_combined"
LABEL_MODE_RIGHT_PREFIX = "right_prefix"
local LABEL_MODE_SEPARATE = "separate"
local LABEL_MODE_NONE = "none"
LABEL_ROW_ABOVE = "above"
LABEL_ROW_BELOW = "below"
```

This appendix is intentionally kept at the bottom. It exists only to show historical behavior and support traceability, not to define the future rewrite itself.

---

End of historical appendix.
