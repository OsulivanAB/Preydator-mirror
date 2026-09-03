# Preydator Rewrite — Architecture Document

Author: RagingAltoholic
Status: Draft v1 — scope and deployment model confirmed; ready to start implementation planning
Scope of this document: architecture overview, module boundaries, file layout, settings catalog, runtime pipeline, event flow, and illustrative (non-final) example code for each module. No production Lua is included yet — this is the design pass we agreed to do first.

---

## 0. Decisions locked in before writing this

These came out of our discussion and are treated as settled unless you say otherwise:

- **Single-purpose addon.** Preydator does Prey Hunts and only Prey Hunts. `CurrencyTracker.lua` and every currency/warband-ledger feature are dropped entirely — not deprecated, not stubbed, removed from scope. Other addons already do general currency tracking better; Preydator should not compete with them.
- **Both an MVP and a full-feature architecture are specified** (Section 15). You choose which to build first; the module boundaries are the same either way, so nothing here locks you out of the other path later.
- **Hunt Table / Hunt Scanner is not deferrable.** It's the mechanism by which a player selects the prey quest Preydator tracks, so its core (scan → list → select) is part of MVP, not a "full scope only" extra. Its cosmetic layers (grouping, sorting, reward icons, achievement badges, per-panel theming) are full-scope.
- **Zone gating is redesigned around your proposal**: Hunt Scanner derives and caches the *expected* zone for a hunt at scan time (when the data is fresh and authoritative), and the prey-context runtime uses that cached expected zone as a cheap pre-filter before it ever asks Blizzard's quest log for the authoritative `isOnMap` answer — so the addon stops polling/refreshing quest state while the player is nowhere near the hunt. Full design in Section 8.
- **No duplicate logic across files.** The current codebase reimplements the same zone check, sound-path resolution, and map-ID table in three or four places, and they've already drifted from each other. This rewrite makes each concern live in exactly one file; every other file calls it, none reimplement it. This is treated as a hard rule, not a preference (Section 2).

---

## 1. High-Level Architecture Overview

Preydator is a synchronous, event-driven WoW addon. Nothing in this design uses coroutines, promises, or background threads — WoW's Lua runtime is single-threaded, and the addon respects that throughout.

The addon is organized in four strict layers, and data only flows one direction through them:

```
Blizzard APIs
     │  (raw, untrusted, may be missing/partial/protected)
     ▼
Adapters            — the ONLY code allowed to call a Blizzard API directly
     │  (validated, coerced, safe values)
     ▼
Runtime             — business logic; owns and mutates addon state
     │  (immutable state snapshots)
     ▼
UI                  — renders snapshots; never decides gameplay logic
```

Settings are a parallel input that both Runtime and UI read from, but only through `Core/Settings.lua` — never a raw table reference passed around by hand.

Every module communicates with every other module through one of two channels:

1. **The central module registry** (`Preydator:RegisterModule` / `Preydator:GetModule`), for lifecycle wiring.
2. **A named public API function**, exposed by the module that owns the data or behavior in question.

No module reaches into another module's local variables, no module receives a live reference to another module's internal state table, and no module reimplements logic another module already owns. This last rule is the one the current codebase violates most (see Appendix D), so it's called out again in Section 2 as a standing rule, not just a description of intent.

---

## 2. Design Principles (non-negotiable)

These map directly to the contracts in your original prompt, tightened with what we found in the historical code:

1. **Module boundary contract.** A module exposes a table of public functions. Everything else in the file is `local`. No module mutates another module's table directly, reads another module's locals, or depends on ad hoc shared state. Cross-module calls go through `Preydator.API` (cross-cutting utilities) or a module's own registered public methods (feature-specific behavior) — never a raw field read like `someModule.internalThing`.
2. **Single source of truth per concern.** Each piece of logic — zone/`isOnMap` determination, sound-path resolution, settings normalization, map-ID canonicalization — is implemented in exactly one file. Every caller invokes that file's function. If a second file needs the same answer, it imports the function; it does not re-derive the answer. (The old codebase has the "is the active quest on the current map" check implemented four separate times, with one copy already silently wrong relative to the others — that class of bug is what this rule exists to prevent.)
3. **State is owned, not shared by reference.** `Core/State.lua` is the only place runtime state lives. Nothing outside it holds a live pointer to the state table. Everything else gets either (a) a read-only snapshot, or (b) calls an explicit setter function that validates before writing.
4. **UI never originates gameplay truth.** The bar, the hunt panel, the settings UI — none of them decide whether a quest is active, what stage we're in, or whether we're in the prey zone. They render what Runtime publishes and forward user intent (clicks, drags, slider changes) back through Runtime/Settings APIs.
5. **Adapters are the only Blizzard API boundary.** If a file calls `C_QuestLog.*`, `C_Map.*`, `CreateFrame`, `PlaySoundFile`, or any other Blizzard global directly, and that file is not in `Core/Adapters/`, that's a defect. Adapters return validated, `pcall`-guarded, coerced values — never raw API results.
6. **Fail closed, fail quiet.** Missing or partial Blizzard data becomes "unknown," never a guessed `true`/`false`. Restricted instances halt active tracking entirely rather than degrade gracefully. This is the one place the old code already got the philosophy right (its tri-state discipline around zone detection is worth keeping) even though the implementation duplicated itself.
7. **No file grows into a monolith.** The old `Preydator.lua` is 6,169 lines and is bumping against Lua's 200-local-per-chunk compiler ceiling — a real, currently-managed constraint, not a hypothetical one. Every module in this design is scoped small enough on purpose to never get there again.

---

## 3. File Layout

This keeps the top-level shape you specified — it doesn't invent new top-level folders — but resolves internal responsibilities so nothing is a monolith and nothing duplicates another file's logic.

```
Preydator.lua                          -- bootstrap, namespace, module registry only

Core/
  State.lua                            -- the one authoritative runtime-state table + setters
  Settings.lua                         -- public settings API surface (thin; delegates to Adapters/SettingsStore)

  Adapters/
    QuestApiAdapter.lua                -- C_QuestLog, C_TaskQuest wrappers
    MapContextAdapter.lua              -- C_Map, IsInInstance, IsInScenario wrappers
    WidgetAdapter.lua                  -- Blizzard prey-widget mixin hooks, UIWidget reads
    SoundAdapter.lua                   -- PlaySoundFile / channel handling
    SettingsStore.lua                  -- SavedVariables read/write + versioned migrations
    LocalizationAdapter.lua            -- GetLocale + string table resolution
    DiagnosticsAdapter.lua             -- debug log ring buffer, memory reporting

  Runtime/
    PreyContextRuntime.lua             -- active quest ID, stage, zone-gating (Section 8)
    BarRuntime.lua                     -- state -> bar view-model (NOT rendering)
    SoundsRuntime.lua                  -- stage/ambush/Pack Ambush/Exploding Corpse Snakes sound resolution + playback
    AlertsRuntime.lua                  -- nameplate-driven ambush / Mob Scanner (Pack Ambush, Exploding Corpse Snakes) detection
    DiagnosticsRuntime.lua             -- debug snapshot assembly (qinspect/pinspect/inspect)
    EventRuntime.lua                   -- the single event dispatcher (Section 7)
    SettingsRuntime.lua                -- settings validation/normalization (called only by SettingsStore)

UI/
  BarFrame.lua                        -- bar frame creation + rendering from BarRuntime snapshots
  SettingsPanel.lua                   -- options UI (general/bar/bar colors/text/sound/hunt/advanced categories)
  Launcher.lua                        -- minimap button + Addon Compartment integration (built 2026-08-28, in-game confirmed)
  ThemeEditor.lua                     -- [full-feature] custom theme editor UI
  -- EditMode.lua and ReportWindow.lua are permanently not built -- Decisions
  -- Log items 38/39: EditMode's entire desired behavior already lives in
  -- BarFrame.lua and the product owner confirmed nothing else is wanted, and
  -- ReportWindow is superseded by the working /pd chat+BugSack flow.

Modules/
  HuntScanner/
    HuntTableAdapter.lua              -- Blizzard AdventureMap/gossip/quest-dialog wrapper (Blizzard-facing only)
    HuntScannerRuntime.lua            -- parse hunts, derive expected zone, grouping/sorting, selection delegation
    HuntTablePanel.lua                -- UI rendering only, consumes HuntScannerRuntime snapshots
    PreyQuestData.lua                 -- static questID -> {difficulty, achievementCriteriaID} table (kept as-is; it was already clean)

Locals/
  Locales.lua, enUS.lua, deDE.lua, ... -- unchanged structure, resolved only through LocalizationAdapter

Media/
  ...                                  -- unchanged

Sounds/
  ...                                  -- unchanged; protected defaults, see Section 10
```

**File header convention:** every new file opens with a standard comment block —

```lua
-- Preydator :: Core/Runtime/PreyContextRuntime.lua
-- Author: RagingAltoholic
-- Responsibility: <one line>
-- Reads: <state/settings fields this file reads>
-- Writes: <state fields this file is allowed to write>
```

This gives every file an explicit, greppable contract, which doubles as enforcement for Principle 3 (only the file listed under "Writes" for a given state field may write it).

---

## 4. Module-by-Module Descriptions

### Preydator.lua (bootstrap)
**Responsibility:** create `_G.Preydator`, the module registry (`RegisterModule`/`GetModule`), and load-order-safe wiring. Nothing else. No settings defaults, no state table, no UI construction, no business logic — all of that moves to the modules below. This directly fixes the old file's core problem: today it *is* the state table, the settings schema, the options UI, and the prey-quest state machine, all at once.
**Reads:** nothing.
**Writes:** the module registry only.
**Publishes:** `Preydator:RegisterModule`, `Preydator:GetModule`, `Preydator.API` (assembled here as a thin façade that re-exports each module's public functions — not a dumping ground of implementation).

### Core/State.lua
**Responsibility:** the single authoritative runtime-state table (`activeQuestID`, `stage`, `progressPercent`, `preyTargetName`, `preyTargetDifficulty`, `inPreyZone`, `expectedZoneMapID`, `questListenUntil`, etc.) plus explicit setter functions that validate before writing and notify subscribers after.
**Reads:** nothing external.
**Writes:** its own table, via setters only (`State.SetStage(stage)`, `State.SetInPreyZone(bool)`, ...) — never a raw `state.stage = x` from outside this file.
**Publishes:** `State.GetSnapshot()` (returns a shallow-copied, read-only table — this is the "immutable snapshot" the State Snapshot Contract requires), `State.Subscribe(callback)` for change notification, and the typed setters.

### Core/Settings.lua
**Responsibility:** the public settings surface every other module uses (`Settings.Get(key)`, `Settings.Set(key, value)`, `Settings.GetDefaults()`, `Settings.ResetToDefaults()`). It is intentionally thin — persistence and migration live in `SettingsStore.lua`, validation lives in `SettingsRuntime.lua`. This file exists so nothing outside `Core/` ever touches `_G.PreydatorDB` directly (today, three different files write straight to that global — `ProfileManager`, the old `CurrencyTracker`, and `Preydator.lua` itself).
**Reads:** `SettingsStore` output.
**Writes:** delegates all writes to `SettingsStore`.
**Publishes:** `Get`, `Set`, `GetDefaults`, `ResetToDefaults`, `Subscribe` (for UI to react to changes without polling).

### Core/Adapters/QuestApiAdapter.lua
**Responsibility:** the only file that calls `C_QuestLog.*` and `C_TaskQuest.*`. Wraps `GetActivePreyQuest`, `GetLogIndexForQuestID`, `GetInfo` (specifically `.isOnMap`), `GetQuestZoneID`, `IsOnQuest`, `IsQuestFlaggedCompleted` — every one `pcall`-guarded, returning `nil` on any failure or protected-value read rather than propagating an error or a guessed value.
**Reads:** Blizzard quest APIs.
**Writes:** nothing (pure adapter).
**Publishes:** `GetActivePreyQuestID()`, `GetQuestIsOnMap(questID)`, `GetQuestZoneID(questID)`, `IsQuestFlagged Completed(questID)`.

### Core/Adapters/MapContextAdapter.lua
**Responsibility:** the only file that calls `C_Map.*`, `IsInInstance`, `IsInScenario`, `C_ScenarioInfo.GetScenarioInfo`. Owns the restricted-instance check as one canonical function (today this exists in at least two places).
**Publishes:** `GetPlayerMapID()`, `GetMapInfo(mapID)`, `IsRestrictedInstance()` — returns one of `pvp | arena | party | raid | scenario | delve | nil`.

### Core/Adapters/WidgetAdapter.lua
**Responsibility:** the only file that hooks Blizzard's prey-hunt UIWidget mixin and reads/suppresses the default prey icon. Isolates the taint-sensitive widget-hook code (the old suppression hook has an explicit "this creates a taint context" disabled block — that fragility gets contained to one file instead of leaking into bar rendering).
**Publishes:** `GetWidgetStage()`, `SuppressDefaultPreyIcon(bool)`.

### Core/Adapters/SoundAdapter.lua
**Responsibility:** the only file that calls `PlaySoundFile`, channel selection, and mute/unmute. Pure playback mechanics — no path resolution, no settings knowledge (that's `SoundsRuntime`'s job).
**Publishes:** `Play(path, channel)`, `IsChannelValid(channel)`.

### Core/Adapters/SettingsStore.lua
**Responsibility:** SavedVariables read/write (`PreydatorDB`), profile management (create/switch/copy/delete — the one feature `ProfileManager.lua` already did cleanly, folded in here rather than kept as a separate ad hoc global), and the versioned migration pipeline (Section 11).
**Publishes:** `Load()`, `Save(table)`, `GetActiveProfile()`, `SwitchProfile(name)`, `CreateProfile`/`DeleteProfile`/`CopyProfileFrom`, `RunMigrations(rawTable)`.

### Core/Adapters/LocalizationAdapter.lua
**Responsibility:** the only place `GetLocale()` is read and the only place a locale string table is resolved. Every user-facing string in Runtime or UI goes through `L(key)` from this adapter — no literal English strings anywhere else, per the Localization Contract.
**Publishes:** `L(key)`, `HasTranslation(key, locale)`.

### Core/Adapters/DiagnosticsAdapter.lua
**Responsibility:** timestamped debug log ring buffer (`AddDebugLog`), memory-usage reporting. This existed cleanly already as `DebugRuntime.lua` (the best-isolated file in the old codebase — no Blizzard calls, fully dependency-injected) and is kept essentially as-is, just renamed to match the Adapter suffix convention since its job is really "wrap a diagnostic capability," not "run business logic."
**Publishes:** `Log(message, ...)`, `GetLogs()`, `ClearLogs()`, `ReportMemoryUsage()`.

### Core/Runtime/PreyContextRuntime.lua
**Responsibility:** the single canonical owner of "what quest is active, are we in its zone, what stage is it." Full design in Section 8 — this is the module most directly reshaped by your zone-gating proposal.
**Reads:** `QuestApiAdapter`, `MapContextAdapter`, `Modules/HuntScanner/HuntScannerRuntime` (for the expected-zone cache — read-only, via its public API, never its internals).
**Writes:** `Core/State.lua`, via setters only.
**Publishes:** `RefreshPreyContext()` (event-triggered, not polled), `GetExpectedZoneForActiveQuest()`.

### Core/Runtime/BarRuntime.lua
**Responsibility:** pure computation — turns `State.GetSnapshot()` + `Settings` into a bar view-model containing only game-state-derived values: `{visible, fillPercent, stage, prefixText, suffixText, tickPositions}`. Does **not** touch a single Blizzard frame or texture — that's `UI/BarFrame.lua`'s job entirely. This is the single biggest structural change from the old code, where `Core/BarRuntime.lua` is actually ~1,000 lines of direct frame/texture/font manipulation despite its "Runtime" name. Pure presentation settings (orientation, colors, fonts, texture, dimensions/scale, label layout) have no game-state dependency, so `BarRuntime` does not read or pass them through at all — `UI/BarFrame.lua` reads those directly from `Settings` (a correction from an earlier draft of this doc, which had `BarRuntime` also reading/passing through `bar.orientation`/`bar.percent_display`).
**Reads:** `Core/State.lua`, `Core/Settings.lua` (only `bar.progress_segments`, to pick which tick-percent table to return — `bar.show_ticks` is a pure visibility toggle with no computation attached, so `UI/BarFrame.lua` reads it directly instead).
**Writes:** nothing (pure function of its inputs).
**Publishes:** `ComputeBarViewModel()`.

### Core/Runtime/SoundsRuntime.lua
**Responsibility:** resolves which sound path plays for a given stage/ambush/Pack Ambush/Exploding Corpse Snakes event, honoring user overrides vs. protected defaults, and anti-spam cooldown gating. Calls `SoundAdapter.Play` for actual playback — never `PlaySoundFile` directly.
**Reads:** `Core/Settings.lua`, `Core/State.lua` (for stage-transition detection).
**Writes:** its own cooldown-tracking state (last-played timestamps) — not shared state.
**Publishes:** `PlayStageSound(stage)`, `PlayAmbushSound()`, `PlayPackAmbushSound()`, `PlayExplodingCorpseSnakesSound()`.

### Core/Runtime/AlertsRuntime.lua
**Responsibility:** nameplate-based detection (`NAME_PLATE_UNIT_ADDED`) for the true prey ambush and the Mob Scanner (Pack Ambush / Exploding Corpse Snakes), gated by settings + restricted-instance + active-prey-context. Calls into `SoundsRuntime` and `State` — never touches chat frames or UI. No chat-text detection remains in this file as of 2026-08-28 (Decisions Log items 30/34) — the last chat-text detector (Bloody Command) was replaced once its Season 2 successor turned out not to reliably announce itself in chat either.
**Publishes:** `HandleNameplateEvent(unit)`.

### Core/Runtime/DiagnosticsRuntime.lua
**Responsibility:** assembles the `qinspect`/`pinspect`/`inspect` reports by reading `State`, `Settings`, and adapters, and handing formatted text to `UI/ReportWindow.lua`. This was already a clean, well-isolated module (`DebugInspect.lua`) — kept largely as-is, moved to match the new naming convention.
**Publishes:** `BuildQuestInspectReport(questID)`, `BuildProgressInspectReport()`, `BuildGeneralInspectReport()`.

### Core/Runtime/EventRuntime.lua
**Responsibility:** the single WoW event dispatcher. Full sequencing in Section 7.
**Publishes:** `HandleEvent(event, ...)` — called only from `Preydator.lua`'s one `OnEvent` script.

### Core/Runtime/SettingsRuntime.lua
**Responsibility:** validation/normalization logic for every settings field (enum checks, color clamping, numeric range clamps). Called exclusively by `SettingsStore.lua` — this is the *one* place normalization logic exists, replacing the current split where Preydator.lua keeps a full duplicate fallback copy of every normalize function "in case the runtime module isn't loaded."
**Publishes:** `NormalizeAll(rawSettings)`.

### UI/BarFrame.lua
**Responsibility:** `CreateFrame` calls, texture/font/color application, and rendering — consumes `BarRuntime.ComputeBarViewModel()` output for game-state-derived values and reads `Settings` directly for every pure-presentation field (colors, texture, fonts, dimensions/scale, orientation, label layout, position). Never reads `State` directly and never decides gameplay truth. Self-initializes at file load (subscribes to `State.Subscribe`/`Settings.Subscribe`, hooks `EditModeManagerFrame`'s `OnShow`/`OnHide` for event-driven — not polled — Edit Mode preview support), matching `EventRuntime.lua`'s existing convention of doing real work at top level rather than waiting for an explicit lifecycle call.
**Publishes:** `EnsureBar()`, `Render(viewModel)`, `RequestRender()` (recomputes the view-model and renders), `ApplyPosition(frame)`, `SavePosition(frame)`, `ResetPosition()` (the Section 5.8 "Reset Bar Position" action).

### UI/SettingsPanel.lua
**Responsibility:** the in-game options UI. Renders from and writes back through `Core/Settings.lua`'s public API only (`Settings.Get`/`Settings.Set`/`Settings.GetDefaults`/`Settings.ResetToDefaults`) — never touches `State` or any other runtime directly, and never needs to know what to refresh after a change, since `BarFrame`/`SoundsRuntime`/etc. already react to `Settings.Subscribe` on their own. Seven categories: General, Bar Display, Bar Colors, Text & Labels, Sound & Alerts, Hunt Scanner, Advanced — resolving Section 3's file-layout comment, which named only "general/bar/text/progress/sound" and omitted hunt; `hunt.*` settings live in this same panel (Section 5.6's catalog already said "Written by: Settings UI" for every one, and no separate hunt-settings file exists anywhere in the file layout). Full-scope-only fields (theme system, profiles, achievement signals, `hunt.theme`) are not exposed here yet, per Section 15.

Built on a **hybrid** of Blizzard's modern Settings API and a small custom canvas, not a fully custom `CreateFrame` panel like the old code: `Settings.RegisterVerticalLayoutCategory` + `Settings.RegisterProxySetting` + `Settings.CreateCheckbox`/`CreateDropdown`/`CreateSlider` handle every category that's just booleans/enums/numbers (General, Bar Display, Sound & Alerts, Hunt Scanner) with zero pixel-position code — `RegisterProxySetting` bridges directly to `Settings.Get`/`Settings.Set` closures since it's designed for addons with their own config storage, not a native CVar. The three categories needing controls the native API doesn't have (color swatches, free text entry, action buttons) — Bar Colors, Text & Labels, Advanced — use `Settings.RegisterCanvasLayoutSubcategory` with a shared `anchorRowTop` stacking helper instead: every row anchors below the previous one by one fixed spacing constant, so even the hand-built parts never hardcode an absolute y-coordinate the way the old `Modules/Settings.lua` did for every single control. See Decisions Log item 9 for the full reasoning and the six Section 5.8 actions' resolution.

**Publishes:** `category` (the registered root `Settings` category object, for other modules that may need `Settings.OpenToCategory` later). Also registers a `/preydator` slash command that opens straight to this panel.

### UI/EditMode.lua, UI/ThemeEditor.lua, UI/ReportWindow.lua, UI/Launcher.lua
Each renders from and writes back through `Core/Settings.lua`'s public API only. `ReportWindow.lua` and `EditMode.lua` were already the two cleanest UI-adjacent files in the old codebase (generic, hunt-agnostic, properly using the sanctioned API surface) — they carry forward with minimal structural change, just relocated under `UI/`.

### Modules/HuntScanner/HuntTableAdapter.lua
**Responsibility:** the only file that touches `CovenantMissionFrame`, `AdventureMapQuestChoiceDialog`, gossip/interaction-manager state, and the Adventure Map pin pool. `GetOfferedHunts()` returns `{questID, title, description, normalizedX, normalizedY}` per hunt — no difficulty, zone, or reward data at this layer (that's `HuntScannerRuntime`'s job to derive/enrich); nothing downstream touches these Blizzard objects directly. (Corrected 2026-08-27: an earlier draft of this doc described this function's return shape as `{questID, title, rawDifficultyText, zoneMapIDFromPin, rewardWidgets}` — that never matched the as-built adapter and no reward data exists anywhere in the codebase; see Decisions Log item 12.)
**Publishes:** `GetOfferedHunts()`, `GetAdventureMapID()`, `IsHuntTableActive()`, `OpenHuntDialog(questID)`, `AcceptHunt(questID)`.

### Modules/HuntScanner/HuntScannerRuntime.lua
**Responsibility:** parses adapter output into hunt domain objects (`{questID, title, difficulty, zoneMapID}`), derives and caches each hunt's **expected zone** at scan time (Section 8), and delegates selection to the adapter. Does not create or touch a single frame. Grouping/sorting/reward display are Full-scope only (Section 15) and not implemented here — an earlier draft of this doc's prose claimed this runtime "handles grouping/sorting," which was aspirational, not built; corrected 2026-08-27 (Decisions Log item 12). Publishes a `Subscribe(callback)`/notify pair (mirroring `Core/State.lua`/`Core/Settings.lua`'s existing pattern, added 2026-08-27) so `HuntTablePanel.lua` can react to list changes without registering its own raw WoW events — `EventRuntime` stays the sole WoW event dispatcher (Section 7).
**Reads:** `HuntTableAdapter`, `QuestApiAdapter`, `MapContextAdapter`, `PreyQuestData`.
**Writes:** its own hunt-list state and the expected-zone cache (published for `PreyContextRuntime` to read).
**Publishes:** `GetHuntList()`, `SelectHunt(questID)`, `GetExpectedZone(questID)`, `Subscribe(callback)`.

### Modules/HuntScanner/HuntTablePanel.lua
**Responsibility:** renders `HuntScannerRuntime.GetHuntList()` as the hunt panel — the MVP row subset only (icon, name, zone, Accept button); the rewards line described below is Full-scope (Section 15) and not rendered until reward-data plumbing exists (see Decisions Log item 12). **Only the Accept button is interactive** — it calls `HuntScannerRuntime.SelectHunt(questID)`. The rest of the row (icon, name, zone) is display-only; there is no row-click-to-preview behavior. `HuntTableAdapter`'s dialog-preview call (`OpenHuntDialog`) stays available on the adapter for possible future use (e.g. a tooltip), but the panel does not wire it to anything today. Anchors to `UIParent`'s left/right edge per `hunt.panel_side` rather than being freely draggable like the bar — there is no `hunt.position_x`/`position_y` in the settings catalog, and this was a deliberate choice, not an oversight (Decisions Log item 12).
**Reads:** `HuntScannerRuntime` (via `Subscribe`), `Core/Settings.lua`, `Core/Adapters/MapContextAdapter.lua` (zone name lookup only).
**Writes:** nothing.
**Publishes:** `Render(huntList)`, `RequestRender()`.

**Row layout (confirmed design, per `Hunt Table design template.png`):** each hunt row is a fixed two-column layout — a difficulty icon on the left, and a four-line info stack on the right (the MVP build renders lines 1-2 and the Accept button; line 3 is Full-scope):

```
┌──────────┬────────────────────────────────────┐
│          │ Quest Name                   (left) │
│  [icon]  │ Zone Name                     (left) │
│          │ [rwd][rwd][rwd] Quest Rewards (left) │
│          │                     [Accept]  (right) │
└──────────┴────────────────────────────────────┘
```

The old text-based difficulty badge (`[N]`/`[H]`/`[Ni]`) is retired entirely in favor of a bundled difficulty icon per row — normal/hard/nightmare each get a distinct icon asset rather than a color-coded abbreviation. This is a deliberate localization win: an icon needs no translation, where the old badge text did. The Quest Rewards line renders every reward as a small inline icon (not a compact "+N" summary) — same spirit as the old `icon_text`/`icon_count` styles, just laid out horizontally within the row's fixed height rather than in a card. See Section 5.6 for the settings-catalog impact.

### Modules/HuntScanner/PreyQuestData.lua
**Responsibility:** unchanged from today — static questID → `{difficultyIndex, achievementCriteriaID}` data, no functions, no Blizzard calls. Already matched this architecture's expectations for a pure data file.

---

## 5. Settings Catalog

Organized by category per your requirement. Every row: name, type, default, purpose, when used, which runtime reads it, which runtime writes it, user-configurable vs internal, and safety-required vs cosmetic. Currency/warband settings are omitted entirely (removed from scope). Legacy-only fields from the old schema (duplicate `width`/`height` mirrors, `ambushSoundKey`, `tickLayerMode`, `showAlignmentDot`, the disabled `achievementTheme` control) are **not** carried forward as live settings — Section 11 covers how existing users' data is imported once, then those fields are retired for good.

### 5.1 General / Runtime Behavior

| Name | Type | Default | Purpose | Used when | Read by | Written by | Configurable | Safety/cosmetic |
|---|---|---|---|---|---|---|---|---|
| `general.bar_enabled` | boolean | `true` | Enables the bar module | Always evaluated on module init and settings change | `BarRuntime`, `UI/BarFrame` | `UI/SettingsPanel` | Yes | Cosmetic |
| `general.sounds_enabled` | boolean | `true` | Master sound on/off | Every alert/stage-sound trigger | `SoundsRuntime` | `UI/SettingsPanel` | Yes | Cosmetic |
| `general.hunt_enabled` | boolean | `true` | Enables Hunt Table tracking module | Module init, event gating | `HuntScannerRuntime`, `EventRuntime` | `UI/SettingsPanel` | Yes | Cosmetic |
| `general.debug_logging_enabled` | boolean | `false` | Enables verbose debug log capture | Every `DiagnosticsAdapter.Log` call | `DiagnosticsAdapter` | `UI/SettingsPanel` | Yes | Cosmetic |
| `general.lock_bar` | boolean | `false` | Prevents dragging the bar frame | Bar mouse-down handler | `UI/BarFrame` | `UI/SettingsPanel` (during Edit Mode, `UI/BarFrame` itself temporarily overrides mouse-enable regardless of this value rather than mutating it — Decisions Log item 39) | Yes | Cosmetic |
| `general.only_show_in_prey_zone` | boolean | `false` | Hides the bar entirely outside the prey zone | Every `BarRuntime.ComputeBarViewModel` call | `BarRuntime` | `UI/SettingsPanel` | Yes | Cosmetic |
| `general.disable_default_prey_icon` | boolean | `false` | Suppresses Blizzard's built-in prey icon overlay | Widget-shown hook | `WidgetAdapter` | `UI/SettingsPanel` | Yes | Cosmetic |
| `general.minimap_hidden` | boolean | `false` | Hides `UI/Launcher.lua`'s minimap/Addon Compartment button | `UI/Launcher` visibility refresh | `UI/Launcher` | `UI/SettingsPanel` | Yes | Cosmetic |
| `general.minimap_angle` | number | `225` | Minimap button position, degrees | `UI/Launcher` position refresh | `UI/Launcher` | `UI/Launcher` (drag) | Yes (drag-only, no direct Settings UI control) | Cosmetic |
| `general.schema_version` | number | current version constant | Settings schema version gate | Every `SettingsStore.Load()` | `SettingsStore` | `SettingsStore` only | No (internal) | **Required** — corrupting this breaks migration |

### 5.2 Bar Display

| Name | Type | Default | Purpose | Read by | Written by | Configurable |
|---|---|---|---|---|---|---|
| `bar.orientation` | enum(`horizontal`,`vertical`) | `horizontal` | Bar layout mode | `UI/BarFrame` | Settings UI | Yes |
| `bar.texture_key` | enum | `default` | Fill texture preset | `UI/BarFrame` | Settings UI | Yes |
| `bar.scale_horizontal` | number(0.5–2) | `1.0` | Horizontal-mode scale | `UI/BarFrame` | Settings UI | Yes |
| `bar.scale_vertical` | number(0.5–2) | `0.9` | Vertical-mode scale | `UI/BarFrame` | Settings UI | Yes |
| `bar.width_horizontal` | number(100–350) | `160` | Bar width, horizontal mode | `UI/BarFrame` | Settings UI | Yes |
| `bar.height_horizontal` | number(10–60) | `30` | Bar height, horizontal mode | `UI/BarFrame` | Settings UI | Yes |
| `bar.width_vertical` | number(10–60) | `40` | Bar width, vertical mode | `UI/BarFrame` | Settings UI | Yes |
| `bar.height_vertical` | number(100–350) | `160` | Bar height, vertical mode | `UI/BarFrame` | Settings UI | Yes |
| `bar.fill_color` / `border_color` / `title_color` / `percent_color` / `tick_color` / `bg_color` | color RGBA | preset per field | Visual coloring | `UI/BarFrame` | Settings UI | Yes |
| `bar.border_color_linked` | boolean | `true` | Border mirrors fill color | `UI/BarFrame` | Settings UI | Yes |
| `bar.accessibility_theme` | enum(`default`,`deuteranopia`,`protanopia`) | `default` | One-click colorblind preset | `UI/BarFrame` | Settings UI | Yes |
| `bar.show_ticks` | boolean | `true` | Tick-mark visibility | `UI/BarFrame` | Settings UI | Yes |
| `bar.show_spark_line` | boolean | `false` | Animated fill-edge spark — **not built**; deferred, see Section 19 Decisions Log | `UI/BarFrame` | Settings UI | Yes |
| `bar.percent_display` | enum(`inside`,`above_bar`,`above_ticks`,`under_ticks`,`below_bar`,`off`) | `inside` | Percent text placement — applies unchanged in both orientations (screen-space above/below), not horizontal-only; `above_ticks`/`under_ticks` also gate per-tick percent labels in place of the single running-percent text, replacing the old code's separate `showVerticalTickPercent` boolean for vertical mode (dropped, not carried forward — one enum now covers both orientations) | `UI/BarFrame` | Settings UI | Yes |
| `bar.progress_segments` | enum(`quarters`,`thirds`) | `quarters` | Tick/segment division for progress fallback | `PreyContextRuntime`, `BarRuntime` | Settings UI | Yes |
| `bar.vertical_fill_direction` | enum(`up`,`down`) | `up` | Fill direction, vertical mode | `UI/BarFrame` | Settings UI | Yes |
| `bar.vertical_text_side` | enum(`left`,`right`) | `right` | Which side of the bar text sits, vertical mode (text rotates 90°; `text.stage_label_mode` still applies, mapped onto the progress axis — see Decisions Log) | `UI/BarFrame` | Settings UI | Yes |
| `bar.show_in_edit_mode` | boolean | `true` | Force the bar visible with placeholder text while Blizzard Edit Mode is open; wired via `EditModeManagerFrame:HookScript("OnShow"/"OnHide", ...)`, not polling | `UI/BarFrame` | Settings UI | Yes |
| `bar.position_x` / `bar.position_y` | number | `0` / `200` | Bar position, always a `CENTER`-to-`UIParent CENTER` pixel offset — no separate anchor/relativePoint fields, since the old schema's were hardcoded to `"CENTER"` at both save and load time despite looking general-purpose (see Decisions Log) | `UI/BarFrame` | `UI/BarFrame` (drag-stop, `ResetPosition()`) | No (drag/reset only, not a settings-UI field) |

### 5.3 Text and Label Styling

| Name | Type | Default | Purpose | Read by | Written by | Configurable |
|---|---|---|---|---|---|---|
| `text.title_font_key` / `percent_font_key` | enum | `frizqt` | Font selection | `UI/BarFrame` | Settings UI | Yes |
| `text.font_size` | number(8–24) | `12` | Text size | `UI/BarFrame` | Settings UI | Yes |
| `text.stage_prefix[1..4]` | string | `""` | Prefix text per stage | `BarRuntime` | Settings UI | Yes |
| `text.stage_suffix[1..4]` | string | localized default stage name | Suffix text per stage (the actual visible stage label) | `BarRuntime` | Settings UI | Yes |
| `text.out_of_zone_prefix` | string | `""` | Prefix shown out of zone | `BarRuntime` | Settings UI | Yes |
| `text.out_of_zone_suffix` | string | localized default | Suffix shown out of zone | `BarRuntime` | Settings UI | Yes |
| `text.ambush_prefix` | string | localized `"AMBUSH: "` | Ambush alert prefix | `BarRuntime` | Settings UI | Yes |
| `text.ambush_suffix_template` | string | `{preyTargetName}` token | Ambush alert suffix (supports the target-name token) | `BarRuntime` | Settings UI | Yes |
| `text.pack_ambush_prefix` | string | localized default (`"Pack Ambush: "`) | Pack Ambush alert prefix (renamed from Bloody Command, 2026-08-28) | `BarRuntime` | Settings UI | Yes |
| `text.pack_ambush_suffix_template` | string | `{packAmbushSourceName}` token | Pack Ambush alert suffix | `BarRuntime` | Settings UI | Yes |
| `text.stage_label_mode` | enum(9 values, see Appendix C) | `center` | Horizontal label layout mode | `BarRuntime` | Settings UI | Yes |
| `text.label_row_position` | enum(`above`,`below`) | `above` | Text row placement relative to bar | `BarRuntime` | Settings UI | Yes |

*Note:* the old schema's `stageLabels` (suffix) vs. `stageSuffixLabels` (prefix) naming was inverted relative to their own UI section headers — a real bug, not a design choice. The rewrite names these `stage_prefix`/`stage_suffix` to match what they actually do.

### 5.4 Progress Logic and Stage Behavior

| Name | Type | Default | Purpose | Read by | Written by | Configurable |
|---|---|---|---|---|---|---|
| `progress.segment_mode` | enum(`quarters`,`thirds`) | `quarters` | Same field as `bar.progress_segments` — listed once, referenced from both categories | `PreyContextRuntime` | Settings UI | Yes |
| `progress.fallback_mode` | enum | `stage` | How percent is derived when Blizzard doesn't expose a precise value | `PreyContextRuntime` | Internal (fixed) | No — this is a real behavior, not a leftover; kept internal because there is currently no second fallback mode to choose between | **Required** |

### 5.5 Sound and Alert Configuration

| Name | Type | Default | Purpose | Read by | Written by | Configurable | Safety/cosmetic |
|---|---|---|---|---|---|---|---|
| `sound.channel` | enum(`Master`,`SFX`,`Dialog`,`Ambience`,`Music`) | `Master` | Playback channel | `SoundAdapter` | Settings UI | Yes | Cosmetic |
| `sound.stage_path[1..4]` | string(path) | protected defaults (Section 10) | Per-stage sound file | `SoundsRuntime` | Settings UI / `Restore Default Sounds` | Yes | Cosmetic |
| `sound.ambush_enabled` / `ambush_path` | boolean / string | `true` / protected default | Ambush alert sound | `SoundsRuntime` | Settings UI | Yes | Cosmetic |
| `sound.pack_ambush_enabled` / `pack_ambush_path` | boolean / string | `true` / protected default | Pack Ambush alert sound (renamed from Bloody Command, 2026-08-28 — live Season 2 mechanic, mobs Pack Scout/Pack Hunter, detected by AlertsRuntime's nameplate-based Mob Scanner) | `SoundsRuntime` | Settings UI | Yes | Cosmetic |
| `sound.exploding_corpse_snakes_enabled` / `exploding_corpse_snakes_path` | boolean / string | `true` / protected default | Exploding Corpse Snakes alert sound (renamed from Echo of Predation, 2026-08-28 — live Season 2 mechanic, mob Venom-Bloated Python, detected by the same Mob Scanner) | `SoundsRuntime` | Settings UI | Yes | Cosmetic |
| `sound.custom_file_names` | list\<string\> | seeded from protected defaults | User-added sound files available in pickers | `SoundsRuntime` | Settings UI (`Add`/`Remove File`) | Yes | Cosmetic |
| `sound.alert_cooldown_seconds` | number | `60` | Anti-spam cooldown shared by ambush/Pack Ambush/Exploding Corpse Snakes triggers | `SoundsRuntime` | Internal (fixed) | No | **Required** — prevents alert spam under rapid trigger conditions |

### 5.6 Hunt Scanner / Hunt Table

| Name | Type | Default | Purpose | Read by | Written by | Configurable |
|---|---|---|---|---|---|---|
| `hunt.enabled` | boolean | `true` | Master toggle | `HuntScannerRuntime` | Settings UI | Yes |
| `hunt.preview_enabled` | boolean | `false` | Settings-only visual aid (2026-08-28, product owner request): force-shows the panel while adjusting `width`/`height`/`scale`/`font_size` below, using the real cached list if any or `HuntTablePanel.buildPreviewHunts()`'s 3 placeholder rows (mapID `2561`/The Coiled Isle) otherwise — bypasses `hunt.enabled` and the live "at a real Hunt Table" gate entirely, purely cosmetic | `HuntTablePanel` | Settings UI | Yes |
| `hunt.panel_side` | enum(`left`,`right`) | `right` | Screen anchor side | `HuntTablePanel` | Settings UI | Yes |
| `hunt.group_by` | enum(`none`,`difficulty`,`zone`) | `difficulty` | Grouping mode | `HuntScannerRuntime` | Settings UI / panel button | Yes |
| `hunt.sort_by` | enum(`difficulty`,`zone`,`title`) | `zone` | Sort field | `HuntScannerRuntime` | Settings UI / panel button | Yes |
| `hunt.sort_direction` | enum(`asc`,`desc`) | `asc` | Sort direction | `HuntScannerRuntime` | Settings UI | Yes |
| `hunt.reward_display_style` | enum(`icon_inline`,`icon_count`) | `icon_inline` | Reward row format — `icon_inline` shows every reward as a small icon+quantity strip (confirmed default, per Section 19.2); `icon_count` drops the quantity number (icons only, still on hover) as a more compact fallback for narrower panel widths. A third `text_only` option (plain comma-separated text, no icons) was built and live-tested 2026-09-02 but removed the same day — the product owner found it not a viable look for this row (Decisions Log item 53) | `HuntTablePanel` | Settings UI | Yes |
| `hunt.width` / `height` / `scale` / `font_size` | number | `336` / `460` / `1.0` / `12` | Panel sizing | `HuntTablePanel` | Settings UI | Yes |
| `hunt.difficulty_icon_set` | enum (bundled icon set key) | `default` (sourced from `Media/PreyHuntTableDifficulty_light.png`, sliced into 3 texture regions) | **Replaces** the old `hunt.difficulty_colors.*` color swatches — difficulty is now conveyed by a bundled icon per row (normal/hard/nightmare), not a user-recolorable text badge. Retired the per-color settings entirely since the icon art itself carries the meaning. | `HuntTablePanel` | Settings UI (icon-set picker, not a color picker) | Yes, at the "which icon set" level — not per-color |
| `hunt.achievement_signals_enabled` | boolean | `true` | [full] Show achievement badges | `HuntTablePanel` | Settings UI | Yes |
| `hunt.achievement_signal_style` | enum | `icon_count` | [full] Badge display style | `HuntTablePanel` | Settings UI | Yes |
| `hunt.theme` | enum | `brown` | [full] Panel theme | `HuntTablePanel` | Settings UI | Yes |

### 5.7 Accessibility and Theme [full-feature]

| Name | Type | Default | Purpose | Configurable |
|---|---|---|---|---|
| `theme.enabled` | boolean | `false` | Force one global theme across all panels | Yes |
| `theme.global_key` | enum | `brown` | Which theme when `theme.enabled` is true | Yes |
| `theme.use_class_colors` | boolean | `true` | Class-color character names in themed panels | Yes |
| `theme.custom_themes` | map\<name, colorset\> | `{}` | User-saved custom themes | Yes (via Theme Editor) |

### 5.8 Advanced / Debug

| Name | Type | Default | Purpose | Configurable | Safety/cosmetic |
|---|---|---|---|---|---|
| `debug.logging_enabled` | boolean | `false` | Same as `general.debug_logging_enabled`; kept in Advanced page for discoverability, single underlying field | Yes | Cosmetic |
| `debug.pack_ambush_verbose` | boolean | `false` | Extra logging for Pack Ambush path specifically (renamed from Bloody Command, 2026-08-28 — still unwired/no-op) | Yes | Cosmetic |

Actions exposed but not settings values (kept for parity — implemented as functions, not fields): Reset Bar Position, Reset Hunt Table Position, Refresh Hunt Cache, Restore Default Names, Restore Default Sounds, Reset All Settings.

---

## 6. Runtime Pipeline

```
1. Adapters read raw Blizzard inputs (pcall-guarded).
2. Adapters normalize/validate — numeric coercion via safe-parse, unknown stays nil, never guessed.
3. PreyContextRuntime determines active prey context:
     a. Cheap zone pre-filter using HuntScannerRuntime's cached expected zone (Section 8).
     b. Only if the pre-filter passes, confirm with QuestApiAdapter's authoritative isOnMap.
4. PreyContextRuntime computes derived state (stage, progress, inPreyZone) and writes it
   through Core/State.lua's setters.
5. Core/State.lua publishes a change notification; BarRuntime and HuntScannerRuntime compute
   fresh view-models on demand (not on a timer).
6. UI layer (BarFrame, HuntTablePanel) renders the view-models.
7. SoundsRuntime / AlertsRuntime react to the same state-change notifications to trigger
   sound/alert playback, independently of UI rendering.
8. SettingsStore persists any settings changes, running them through SettingsRuntime validation
   first.
```

Nothing in this pipeline polls on a fixed interval by default. The only timer-driven work is the bounded login-bootstrap retry sequence (a handful of `C_Timer.After` calls at increasing delays right after login, to handle Blizzard quest data not being ready yet) and the Hunt Table's reward-cache warm-up (also bounded and only active while the Hunt Table UI is actually open).

---

## 7. Event Routing / Dispatch Design

One dispatcher, one sequencing order, always the same regardless of event:

```
EventRuntime.HandleEvent(event, ...):
    1. VALIDATE       — is this an event we care about at all? Early return if not.
    2. FAIL-CLOSED    — MapContextAdapter.IsRestrictedInstance()?
                         If yes: State.SetPollingActive(false), and return —
                         except for PLAYER_LOGIN / ADDON_LOADED, which are always allowed
                         through so the addon can still initialize and settings remain reachable.
    3. CONTEXT CHECK  — PreyContextRuntime.RefreshPreyContext() if this event is
                         context-relevant (quest/zone/widget events); skipped entirely
                         for events that can't affect prey context (e.g. a chat event
                         goes straight to AlertsRuntime instead).
    4. DISPATCH       — hand off to exactly one runtime module based on event category:
                         quest/zone events -> PreyContextRuntime
                         chat events       -> AlertsRuntime
                         widget events     -> WidgetAdapter -> PreyContextRuntime
    5. NO UI CALLS    — EventRuntime never calls UI/BarFrame or UI/HuntTablePanel directly.
                         State changes from step 4 trigger UI updates via the State
                         change-notification from Section 6, not from inside the dispatcher.
```

This directly fixes the old `EventRuntime.lua`'s biggest structural problem: today `ctx.updateBarDisplay()` is called from *inside* the event handler at four different points, and the restricted-instance check happens twice with a state-mutating zone-trigger block sitting in between them (so a restricted-instance zone write can happen even though the display update is later suppressed). The rewrite's dispatcher has one restricted-instance gate, evaluated once, before any state mutation happens — not after.

---

## 8. Zone & Prey Context Model (your zone-gating proposal)

This is the part of the design most directly shaped by what you asked for, so it's worth spelling out in full.

**The problem in the old code:** "is the player in the prey zone" is answered by asking Blizzard's quest log (`C_QuestLog.GetInfo(logIndex).isOnMap`) — which is correctly treated as the sole source of truth — but that question gets asked repeatedly, on many events, regardless of whether the player is anywhere near the hunt. Separately, when the addon needs to guess *which* zone a hunt is even supposed to happen in, it falls back through a chain ending in a hardcoded coordinate-bucket heuristic calibrated to a specific, fixed set of hunt locations — fragile, and disconnected from the one moment the addon actually has good zone data: when the Hunt Table itself is open and showing the pins.

**The redesign:**

1. **Expected zone is captured at the source, not guessed later.** When `HuntScannerRuntime` parses hunts from `HuntTableAdapter.GetOfferedHunts()` (i.e., while the player is physically at a Hunt Table and the Adventure Map pins are live), it resolves each hunt's zone via `QuestApiAdapter.GetQuestZoneID(questID)` — the same authoritative call the old code already trusts most — and writes it into a small cache: `expectedZoneByQuestID[questID] = mapID`. This cache is published (`HuntScannerRuntime.GetExpectedZone(questID)`), not private.

2. **PreyContextRuntime gates expensive work behind a cheap check first.** When it needs to know whether the player is in the prey zone for the active quest:
   - It reads `MapContextAdapter.GetPlayerMapID()` — cheap, already-cached-by-Blizzard read, refreshed only on zone-change events, not polled.
   - It compares that against `HuntScannerRuntime.GetExpectedZone(activeQuestID)`.
   - **If they don't match**, it sets `inPreyZone = false` immediately and stops — it does *not* call `QuestApiAdapter.GetQuestIsOnMap()` at all. No quest-log query, no stage recompute, no bar-relevant work happens while the player is somewhere the hunt can't possibly be.
   - **If they match** (or the expected zone is unknown — e.g., the player tracked a hunt without ever having it show in the Hunt Table this session), it proceeds to the authoritative `QuestApiAdapter.GetQuestIsOnMap()` check, exactly as today, and that answer — not the map-ID comparison — remains the actual source of truth for `inPreyZone`.

3. **This is a pre-filter, not a replacement for the source of truth.** The explicit design comment from the old code — "Blizzard's quest-log answer is the sole source of truth for this bar; we intentionally do not infer zone state from map IDs" — still holds. Step 2's map-ID comparison never *sets* `inPreyZone = true` by itself; it only ever short-circuits to `false` early, or defers to the real check. That preserves correctness while cutting the actual polling/latency cost you were pointing at.

4. **Refresh is event-driven, not timer-driven.** `RefreshPreyContext()` runs on `ZONE_CHANGED`, `ZONE_CHANGED_NEW_AREA`, `PLAYER_ENTERING_WORLD`, quest-log-changed events, and the bounded login-bootstrap sequence — never on a repeating `OnUpdate`/ticker. Because step 2 is so cheap, there's no performance reason to throttle it further; the throttling that matters (avoiding the expensive quest-log call) is structural, not time-based.

5. **Cache invalidation:** `expectedZoneByQuestID` entries are cleared when their quest ends (`HuntScannerRuntime` already receives an end-of-hunt notification in the old design via `OnPreyQuestEnded` — kept in the rewrite) and are never persisted as a growing-forever table — only hunts seen this session are cached, which matches the existing non-negotiable constraint your team already documented: *never build a persistent QuestID→zone map; zone must always be derived at runtime.* This rewrite honors that — the cache is a session-lifetime memoization of a runtime-derived value, not a stored mapping.

---

## 9. Fail-Closed Behavior in Restricted Instances

Restricted types: `pvp`, `arena`, `party`, `raid`, `scenario`, `delve` (from `MapContextAdapter.IsRestrictedInstance()`).

- On entering a restricted instance: `EventRuntime` calls `State.SetPollingActive(false)` and `PreyContextRuntime` stops issuing any further zone/quest checks. `State.SetInPreyZone(false)` and `State.ClearActiveQuest()` — no stale overworld state survives into restricted content.
- Sound/alert processing (`SoundsRuntime`, `AlertsRuntime`) is gated on `State.IsPollingActive()` and short-circuits before doing any work.
- The bar itself may still exist and settings remain reachable — only *active* tracking stops. This matches "the addon may still initialize safely at login and allow settings access, but active prey operation must stop."
- On leaving: the next zone-change event runs a clean `RefreshPreyContext()` from scratch — no carried-over stage/target data from before the restricted instance.

**MVP acceptance criterion, audited and confirmed 2026-08-28** (product owner flagged this explicitly — it was a real taint source during this session's own taint-elimination work): no part of Preydator functions inside a restricted instance. Confirmed at every layer: `PreyContextRuntime.RefreshPreyContext()` (the master gate, checked first), `EventRuntime`'s FAIL-CLOSED dispatch step (re-checks independently before every event dispatch, including the Mob Scanner's `NAME_PLATE_UNIT_ADDED`), `EventRuntime.checkHuntInteraction()` (blocks Hunt Table scanning/the taint-sensitive dialog-widget introspection), `AlertsRuntime.HandleNameplateEvent` (double-checks directly), and `SoundsRuntime.playPath()` (the final gate before any sound plays, regardless of caller). No gaps found. Not a new build — already comprehensive from the Section 9 design; just wasn't previously called out as its own MVP checklist line.

---

## 10. Sound and Alert System

Default bundled sounds are unchanged and remain protected (cannot be deleted, only supplemented):

| File | Trigger |
|---|---|
| `predator-ambush.ogg` | Stage 1 |
| `predator-snarl-01.ogg` | Stage 2 |
| `predator-torment.ogg` | Stage 3 |
| `predator-kill.ogg` | Stage 4 |
| `well-we-ve-prepared-a-trap-for-this-predator.ogg` | Ambush trigger |
| `predator-kills-its-prey-to-survive.ogg` | Pack Ambush trigger (renamed from Bloody Command, 2026-08-28) |
| `echo-of-predation.ogg` | Exploding Corpse Snakes trigger (renamed from Echo of Predation, 2026-08-28) |
| `predator-alert.ogg` | Available as a custom/general-purpose default option |

`SoundsRuntime` is the only file that decides *which* path to play; `SoundAdapter` is the only file that calls `PlaySoundFile`. Anti-spam cooldown (Section 5.5) applies per-trigger-type, not globally, so a stage sound and an ambush sound can both play without one blocking the other, but two ambush triggers within the cooldown window collapse to one.

---

## 11. Versioning & Migration Contract

- `general.schema_version` (number) is written by `SettingsStore` and checked on every `Load()`.
- **Current version: 1** (this is a from-scratch schema; there is no "version 0" of the new schema, but there *is* existing user data from the old, unversioned addon that needs a one-time import).
- Migration steps are ordered functions in `SettingsRuntime.lua`, each named for the version transition it performs, e.g. `MigrateLegacyToV1(oldSavedVariables)`. This one runs once per profile, imports the specific old fields that map cleanly to the new schema (colors, sizes, sound paths, stage labels swapped into their correctly-named prefix/suffix fields), and explicitly does **not** import the dead/legacy fields identified in the audit (`ambushSoundKey`, the duplicate `width`/`height` mirrors, `tickLayerMode`, `showAlignmentDot`, `achievementTheme`) — those are left behind on purpose.
- Unknown keys encountered during load (e.g. from a future version, or the removed CurrencyTracker's old settings block) are preserved but ignored — never deleted outright — in case of downgrade, per your migration contract's "preserve unknown/newer keys safely" rule.
- Corrupted or partially-invalid settings fall back to defaults **field by field**, not as a whole-table reset — `SettingsRuntime.NormalizeAll` already has to validate every field individually, so a bad `bar.scale_horizontal` value doesn't wipe out the user's sound paths.
- A full reset (`Settings.ResetToDefaults()`) is only ever user-triggered via the Advanced page button — never automatic.

---

## 12. Performance Budget

- No `OnUpdate` loops anywhere in this design. The only per-frame-adjacent code is `UI/BarFrame.lua`'s spark-line animation, if enabled, and even that is a WoW animation-group (`AnimationGroup`), not a scripted `OnUpdate`.
- The zone-gating redesign in Section 8 is the primary performance mechanism: expensive quest-log calls are skipped entirely when the player is nowhere near an active hunt.
- `HuntScannerRuntime`'s reward-cache warming (already a bounded polling loop in the old code, capped at 4 seconds with a 3-stable-poll exit condition) is kept as-is — it's already correctly throttled and only active while the Hunt Table UI is open.
- Noisy, high-frequency events (`UPDATE_UI_WIDGET`, `UPDATE_ALL_UI_WIDGETS`) are registered only while hunt-relevant UI is actually visible, exactly as the old code already does — that part of the old design was correct and is kept.
- Settings reads are cheap in-memory table lookups (`Core/Settings.lua` holds the loaded/normalized table in memory; it does not re-read SavedVariables per call).

---

## 13. Localization Contract

- `LocalizationAdapter.L(key)` is the only way any Runtime or UI file produces user-facing text. No literal English strings in `Core/Runtime/` or `UI/`.
- Missing translations fall back to the enUS table automatically inside the adapter — callers never need a fallback branch of their own.
- Stage labels, out-of-zone text, and alert prefixes/suffixes have localized *defaults*, but remain fully user-overridable per Section 5.3 — the localization contract governs the addon's own generated text (labels the addon writes when the user hasn't customized them), not user-entered custom text.

---

## 14. Naming Conventions (recap, applied consistently across this document)

- Modules: PascalCase (`PreyContextRuntime`, `HuntScannerRuntime`).
- Internal functions: camelCase.
- Constants: UPPER_SNAKE_CASE.
- Settings keys: lower_snake_case, dotted by category (`bar.fill_color`).
- Adapters end with `Adapter` (`QuestApiAdapter`, `SoundAdapter`).
- Runtimes end with `Runtime` (`BarRuntime`, `EventRuntime`).

---

## 15. MVP vs Full-Feature Architecture

The module boundaries in Sections 3–4 are identical for both paths — MVP is a subset, not a different shape, so nothing here is a dead end if you start with MVP and grow into Full later.

| Module | MVP | Full |
|---|:---:|:---:|
| Bootstrap, State, Settings, all Adapters | ✅ | ✅ |
| PreyContextRuntime (incl. zone-gating) | ✅ | ✅ |
| Fail-closed in restricted instances (Section 9) — audited 2026-08-28, no gaps | ✅ | ✅ |
| BarRuntime + UI/BarFrame | ✅ | ✅ |
| SoundsRuntime + AlertsRuntime (stage/ambush/Pack Ambush/Exploding Corpse Snakes) | ✅ | ✅ |
| DiagnosticsRuntime + slash debug commands (`/pd`) — UI/ReportWindow itself descoped, see below | ✅ | ✅ |
| HuntScanner: scan, list, select, expected-zone derivation | ✅ | ✅ |
| HuntScanner: grouping/sorting — built and live-confirmed 2026-09-01 (Decisions Log items 48-49): full collapsible headers matching the old addon, on-panel Group/Sort/Direction buttons, zone display-name override + article-insensitive zone sort. Product owner confirmed all settings (group/sort/direction/collapsed state) persist across both `/reload` and a full relog | — | ✅ |
| HuntScanner: reward display, including stable ordering and full `reward_display_style` differentiation — built and closed out 2026-09-02 (Decisions Log item 52) | — | ✅ |
| HuntScanner: achievement signals/badges — built and live-confirmed 2026-09-01 (Decisions Log items 44-47). **Fully closed 2026-09-03**: the `ACHIEVEMENT_EARNED` cache-wipe path (badge disappearing the moment an achievement is actually earned, no `/reload` needed) confirmed live — completing quest 95023 (Batani the Scaled) immediately cleared quest 95024 (Kadani the Claw)'s badge on the next `hinspect`, no reload in between. Also closed same day: the tooltip name-vs-target-label bug (Decisions Log item 58) and the new override-achievement architecture for side-questline achievements outside the Mode I/II/III series (Decisions Log item 59) | — | ✅ |
| Accessibility bar-color presets (`bar.accessibility_theme`) | ✅ (cheap, high value) | ✅ |
| Additional bar appearance presets (flatter/more modern texture+border combos, beyond the existing `bar.texture_key` values ported from the old code) | — | ✅ |
| Vertical bar orientation — *testing/polish priority only, not code scope* (see Decisions Log item 13): `bar.orientation = vertical` is already implemented in `UI/BarFrame.lua`, since the architecture keeps one code shape for both orientations rather than a separate MVP-only horizontal path. Deprioritized for QA/visual-tuning until `UI/SettingsPanel.lua` exists to actually toggle it in-game | ✅ (built, untested) | ✅ (polished) |
| Full theme system + ThemeEditor UI | — | ✅ |
| Settings profiles (multiple named profiles) | — | ✅ |
| UI/EditMode quick-settings window — *permanently descoped, confirmed by product owner 2026-08-28* (Decisions Log item 39): its core function (drag the bar during Blizzard Edit Mode, then return to whatever `general.lock_bar` says on exit) is already built directly into `UI/BarFrame.lua`, and the product owner confirmed that's the *entire* desired behavior — no floating settings window wanted at all, not even as a Full-scope item | — | — |
| UI/Launcher (minimap/compartment button) — built 2026-08-28, **in-game confirmed working** (left-click Settings, right-click quick inspect) | ✅ | ✅ |
| UI/ReportWindow — *descoped, 2026-08-28*: superseded by the working `/pd` chat+BugSack diagnostic flow (Decisions Log item 38) | — | — |
| Full locale translations (beyond enUS) | partial (framework required, translations can lag) | ✅ |
| Sound amplification/loudness boost, modeled on the "Better Fishing" addon's technique (product owner, 2026-08-28) — the specific mechanism isn't confirmed yet, needs research before design; candidate approach is layering multiple simultaneous `PlaySoundFile` calls of the same file, since WoW addons can't raise a sound's actual playback volume beyond the channel volume slider | — | ✅ |
| Slider value-number display in `UI/SettingsPanel.lua` — **built and live-confirmed 2026-09-03** (Decisions Log item 60): every `registerSlider` row now shows its live current value beside the slider, found via `findSliderDescendant` (searches by actual widget type, not a guessed field name) rather than Blizzard's native API, which turned out to have no built-in support for this at all | ✅ | ✅ |
| Custom sound files: a real "Add File"/"Remove File" UI flow for `sound.custom_file_names`, so users can add their own `.ogg` files to the sound-path dropdowns beyond the protected defaults. The setting/dropdown-population plumbing already exists (`registerSoundPathDropdown` reads `sound.custom_file_names`), but there's no UI to actually grow that list yet — the old codebase had this built (product owner: "see old code for how that was implemented"), needs porting/redesigning against the new Settings API | — | ✅ |
| Text & Labels category two-column layout — currently one long single-column list of `createEditBoxRow`s (Stage 1-4 Prefix, Stage 1-4 Label, Out of Zone Prefix/Label, Ambush Prefix/Label, Pack Ambush Prefix/Label), each field on its own full-width row, causing a long vertical scroll. Product owner provided a before/after mockup (2026-08-28): pair each Prefix field with its corresponding Label (suffix) field on the *same row*, Prefix in a left column and Label in a right column (e.g. "Stage 3 Prefix" and "Stage 3 Label" side by side, not stacked) — roughly halves the section's height. The Stage Label Mode/Label Row Position dropdowns, Title/Percent Font dropdowns, and Font Size slider above the field list stay as they are (full-width, not part of the two-column pairing) | — | ✅ |

---

## 16. Example Code Per Module

These are illustrative skeletons to validate the module boundaries before real implementation — not final code.

### Preydator.lua
```lua
local ADDON_NAME, ns = ...
_G.Preydator = _G.Preydator or {}
local Preydator = _G.Preydator

Preydator.modules = Preydator.modules or {}

function Preydator:RegisterModule(name, moduleTable)
    assert(type(name) == "string", "module name must be a string")
    assert(self.modules[name] == nil, "module '" .. name .. "' already registered")
    moduleTable.name = name
    self.modules[name] = moduleTable
    return moduleTable
end

function Preydator:GetModule(name)
    return self.modules[name]
end

local bootstrapFrame = CreateFrame("Frame")
bootstrapFrame:RegisterEvent("ADDON_LOADED")
bootstrapFrame:RegisterEvent("PLAYER_LOGIN")
bootstrapFrame:SetScript("OnEvent", function(_, event, ...)
    local eventRuntime = Preydator:GetModule("EventRuntime")
    if eventRuntime then
        eventRuntime:HandleEvent(event, ...)
    end
end)
```

### Core/State.lua
```lua
-- Preydator :: Core/State.lua
-- Author: RagingAltoholic
-- Responsibility: the single authoritative runtime-state table.
-- Reads: nothing external.
-- Writes: its own table, via setters only.

local Preydator = _G.Preydator

local state = {
    activeQuestID = nil,
    stage = nil,
    progressPercent = nil,
    preyTargetName = nil,
    preyTargetDifficulty = nil,
    inPreyZone = false,
    pollingActive = true,
}

local subscribers = {}

local State = {}

function State.GetSnapshot()
    local snapshot = {}
    for k, v in pairs(state) do
        snapshot[k] = v
    end
    return snapshot
end

function State.Subscribe(callback)
    table.insert(subscribers, callback)
end

local function notify()
    for _, callback in ipairs(subscribers) do
        callback(State.GetSnapshot())
    end
end

function State.SetStage(stage)
    if stage ~= nil and type(stage) ~= "number" then return end
    state.stage = stage
    notify()
end

function State.SetInPreyZone(value)
    state.inPreyZone = value == true
    notify()
end

function State.ClearActiveQuest()
    state.activeQuestID = nil
    state.stage = nil
    state.progressPercent = nil
    state.preyTargetName = nil
    state.preyTargetDifficulty = nil
    notify()
end

function State.SetPollingActive(value)
    state.pollingActive = value == true
end

function State.IsPollingActive()
    return state.pollingActive
end

Preydator:RegisterModule("State", State)
return State
```

### Core/Adapters/QuestApiAdapter.lua
```lua
-- Preydator :: Core/Adapters/QuestApiAdapter.lua
-- Author: RagingAltoholic
-- Responsibility: the only file that calls C_QuestLog / C_TaskQuest directly.

local Preydator = _G.Preydator
local QuestApiAdapter = {}

local function safeToNumber(value)
    local ok, str = pcall(tostring, value)
    if not ok or not str then return nil end
    local n = tonumber(str)
    return n
end

function QuestApiAdapter.GetActivePreyQuestID()
    if type(C_QuestLog) ~= "table" or type(C_QuestLog.GetActivePreyQuest) ~= "function" then
        return nil
    end
    local ok, questID = pcall(C_QuestLog.GetActivePreyQuest)
    if not ok then return nil end
    return safeToNumber(questID)
end

function QuestApiAdapter.GetQuestIsOnMap(questID)
    if not questID then return nil end
    local ok, logIndex = pcall(C_QuestLog.GetLogIndexForQuestID, questID)
    if not ok or not logIndex then return nil end
    local okInfo, info = pcall(C_QuestLog.GetInfo, logIndex)
    if not okInfo or type(info) ~= "table" then return nil end
    if info.isOnMap == nil then return nil end
    return info.isOnMap == true
end

function QuestApiAdapter.GetQuestZoneID(questID)
    if not questID or type(C_TaskQuest) ~= "table" then return nil end
    local ok, zoneID = pcall(C_TaskQuest.GetQuestZoneID, questID)
    if not ok then return nil end
    return safeToNumber(zoneID)
end

Preydator:RegisterModule("QuestApiAdapter", QuestApiAdapter)
return QuestApiAdapter
```

### Core/Runtime/PreyContextRuntime.lua
```lua
-- Preydator :: Core/Runtime/PreyContextRuntime.lua
-- Author: RagingAltoholic
-- Responsibility: the single canonical owner of active-quest / zone / stage determination.
-- Reads: QuestApiAdapter, MapContextAdapter, HuntScannerRuntime (expected-zone cache).
-- Writes: Core/State.lua, via setters only.

local Preydator = _G.Preydator
local PreyContextRuntime = {}

local function getModules()
    return
        Preydator:GetModule("QuestApiAdapter"),
        Preydator:GetModule("MapContextAdapter"),
        Preydator:GetModule("State"),
        Preydator:GetModule("HuntScannerRuntime")
end

function PreyContextRuntime.RefreshPreyContext()
    local questApi, mapContext, State, huntScanner = getModules()
    if not (questApi and mapContext and State) then return end

    if mapContext.IsRestrictedInstance() then
        State.SetInPreyZone(false)
        return
    end

    local activeQuestID = questApi.GetActivePreyQuestID()
    if not activeQuestID then
        State.ClearActiveQuest()
        return
    end

    -- Step 1: cheap pre-filter using the expected zone HuntScanner already derived
    -- at scan time, before we spend a call on the authoritative quest-log check.
    local expectedZone = huntScanner and huntScanner.GetExpectedZone(activeQuestID)
    local playerMapID = mapContext.GetPlayerMapID()

    if expectedZone and playerMapID and expectedZone ~= playerMapID then
        State.SetInPreyZone(false)
        return
    end

    -- Step 2: authoritative check — the only source of truth for inPreyZone.
    local isOnMap = questApi.GetQuestIsOnMap(activeQuestID)
    if isOnMap == nil then
        return -- unknown stays unknown; do not guess
    end
    State.SetInPreyZone(isOnMap)
end

function PreyContextRuntime.GetExpectedZoneForActiveQuest()
    local questApi, _, _, huntScanner = getModules()
    local activeQuestID = questApi and questApi.GetActivePreyQuestID()
    if not activeQuestID or not huntScanner then return nil end
    return huntScanner.GetExpectedZone(activeQuestID)
end

Preydator:RegisterModule("PreyContextRuntime", PreyContextRuntime)
return PreyContextRuntime
```

### Core/Runtime/EventRuntime.lua
```lua
-- Preydator :: Core/Runtime/EventRuntime.lua
-- Author: RagingAltoholic
-- Responsibility: the single WoW event dispatcher.

local Preydator = _G.Preydator
local EventRuntime = {}

local CONTEXT_EVENTS = {
    PLAYER_ENTERING_WORLD = true,
    ZONE_CHANGED = true,
    ZONE_CHANGED_NEW_AREA = true,
    QUEST_LOG_UPDATE = true,
    QUEST_ACCEPTED = true,
    QUEST_TURNED_IN = true,
    QUEST_REMOVED = true,
}

-- Updated 2026-08-28 to match the real dispatcher: chat-text detection
-- (CHAT_EVENTS/HandleChatEvent) was fully removed once both ambush and the
-- Mob Scanner turned out to need nameplate detection instead (Decisions Log
-- items 30/34) -- see the real Core/Runtime/EventRuntime.lua for the actual,
-- more complete dispatcher (Hunt Table tracking, the progress ticker, etc.
-- all omitted here for brevity, same as this whole section's own intro says).
local NAMEPLATE_EVENTS = {
    NAME_PLATE_UNIT_ADDED = true,
}

local UNIT_NAME_EVENTS = {
    UNIT_NAME_UPDATE = true,
}

function EventRuntime:HandleEvent(event, ...)
    local mapContext = Preydator:GetModule("MapContextAdapter")
    local state = Preydator:GetModule("State")

    -- Always allowed through, even while restricted, so init/settings still work.
    if event ~= "PLAYER_LOGIN" and event ~= "ADDON_LOADED" then
        if mapContext and mapContext.IsRestrictedInstance() then
            if state then state.SetPollingActive(false) end
            return
        end
    end

    if state then state.SetPollingActive(true) end

    if CONTEXT_EVENTS[event] then
        local preyContext = Preydator:GetModule("PreyContextRuntime")
        if preyContext then preyContext.RefreshPreyContext() end
        return
    end

    if NAMEPLATE_EVENTS[event] then
        local alerts = Preydator:GetModule("AlertsRuntime")
        if alerts then alerts.HandleNameplateEvent(...) end
        return
    end

    if UNIT_NAME_EVENTS[event] then
        local alerts = Preydator:GetModule("AlertsRuntime")
        if alerts then alerts.HandleUnitNameUpdate(...) end
        return
    end
end

Preydator:RegisterModule("EventRuntime", EventRuntime)
return EventRuntime
```

### Core/Runtime/BarRuntime.lua
```lua
-- Preydator :: Core/Runtime/BarRuntime.lua
-- Author: RagingAltoholic
-- Responsibility: pure computation of a bar view-model. No frame/texture access.

local Preydator = _G.Preydator
local BarRuntime = {}

function BarRuntime.ComputeBarViewModel()
    local State = Preydator:GetModule("State")
    local Settings = Preydator:GetModule("Settings")
    if not (State and Settings) then return nil end

    local snapshot = State.GetSnapshot()
    local L = Preydator:GetModule("LocalizationAdapter").L

    if not snapshot.inPreyZone then
        return {
            visible = Settings.Get("general.only_show_in_prey_zone") ~= true,
            labelText = Settings.Get("text.out_of_zone_suffix") or L("OUT_OF_ZONE_DEFAULT"),
            fillPercent = 0,
        }
    end

    return {
        visible = true,
        labelText = Settings.Get("text.stage_suffix")[snapshot.stage or 1],
        fillPercent = snapshot.progressPercent or 0,
        stage = snapshot.stage,
    }
end

Preydator:RegisterModule("BarRuntime", BarRuntime)
return BarRuntime
```

### Modules/HuntScanner/HuntScannerRuntime.lua
```lua
-- Preydator :: Modules/HuntScanner/HuntScannerRuntime.lua
-- Author: RagingAltoholic
-- Responsibility: parse hunts, derive+cache expected zone, grouping/sorting, selection.

local Preydator = _G.Preydator
local HuntScannerRuntime = {}

local expectedZoneByQuestID = {}
local huntList = {}

function HuntScannerRuntime.RefreshFromAdapter()
    local adapter = Preydator:GetModule("HuntTableAdapter")
    local questApi = Preydator:GetModule("QuestApiAdapter")
    if not (adapter and questApi) then return end

    local offeredHunts = adapter.GetOfferedHunts()
    huntList = {}
    for _, hunt in ipairs(offeredHunts) do
        expectedZoneByQuestID[hunt.questID] = questApi.GetQuestZoneID(hunt.questID)
        table.insert(huntList, hunt)
    end
end

function HuntScannerRuntime.GetExpectedZone(questID)
    return expectedZoneByQuestID[questID]
end

function HuntScannerRuntime.GetHuntList()
    return huntList
end

function HuntScannerRuntime.SelectHunt(questID)
    local adapter = Preydator:GetModule("HuntTableAdapter")
    if adapter then adapter.AcceptHunt(questID) end
end

function HuntScannerRuntime.OnPreyQuestEnded(payload)
    if payload and payload.questID then
        expectedZoneByQuestID[payload.questID] = nil
    end
end

Preydator:RegisterModule("HuntScannerRuntime", HuntScannerRuntime)
return HuntScannerRuntime
```

---

## 17. Variable Ownership Map

| Variable | Source | Owner | Notes |
|---|---|---|---|
| `activeQuestID` | Blizzard (`C_QuestLog.GetActivePreyQuest`) | `PreyContextRuntime` writes into `State` | Never read raw elsewhere |
| `isOnMap` | Blizzard | `QuestApiAdapter` (read-only) | Sole authority for `inPreyZone` |
| `expectedZoneMapID` | Blizzard, captured at Hunt Table scan time | `HuntScannerRuntime` | Session-lifetime cache only, never persisted long-term |
| `inPreyZone` | Preydator-derived | `State` (written only by `PreyContextRuntime`) | Gated per Section 8 |
| `stage` | Blizzard widget + Preydator fallback | `PreyContextRuntime` | Single fallback implementation, not duplicated |
| `progressPercent` | Preydator-derived | `PreyContextRuntime` | Stage-based fallback per `progress.fallback_mode` |
| `preyTargetName` / `preyTargetDifficulty` | Blizzard + Preydator normalization | `PreyContextRuntime` | |
| sound file paths | User setting, resolved by `SoundsRuntime` | `SettingsStore` (storage) / `SoundsRuntime` (resolution) | |
| all settings values | User + defaults | `SettingsStore` | Only writer of `PreydatorDB` |
| bar frame position/scale | User + UI | `UI/BarFrame.lua`, persisted via `Core/Settings.lua` | UI-local until saved |
| debug log entries | Preydator | `DiagnosticsAdapter` | |

---

## 18. What This Rewrite Deliberately Does Not Carry Forward

Called out explicitly so nothing here is a silent regression from your perspective — these are removals, not oversights:

- **CurrencyTracker.lua in full** — currency ledger, warband/alt tracking, minimap currency button, currency-specific theming. Per your direction, out of scope entirely.
- **The "runtime module, else duplicate inline fallback" pattern.** The old `Preydator.lua` keeps a full second copy of nearly every normalize/resolve function in case the corresponding Core module isn't loaded — given the `.toc` load order guarantees it always is, this rewrite has exactly one implementation per concern and no fallback copy.
- **Coordinate-bucket zone guessing** (`InferZoneFromCoords`) — superseded entirely by the scan-time zone derivation in Section 8.
- **Dead/neutered code paths**: `BuildQuestCurrencyRewardList` (already hardcoded to return empty due to a taint issue), the disabled `achievementTheme` UI control, the legacy `PrintInspectState`/`SendInspectReportToErrorHandler` gated-but-unreferenced debug path.
- **Global namespace leaks** — several bar-orientation/label constants in the old `Preydator.lua` are missing `local` and leak into `_G`; every constant in the rewrite is explicitly scoped.
- **Direct `_G.PreydatorDB` access from feature modules** — only `SettingsStore.lua` touches SavedVariables now; the old code has three separate files writing to it directly.
- **Legacy-only settings fields** — `ambushSoundKey`/`ambushCustomSoundPath`, the `width`/`height` legacy mirrors, `verticalSideOffset`, `tickLayerMode`, `showAlignmentDot` — imported once during migration if present, then never written again.

---

## 19. Decisions Log

Resolved in review:

1. **Deployment model — resolved, see Section 19.1 below.** Git worktree, not a second unrelated folder: same repo, same history, physically separate working directory so nothing bleeds together during testing, and reintegration is a normal `git merge`, not a manual file copy.
2. **Profile management — resolved.** Stays full-release-only, exactly as Section 15 already had it. No change to the module boundaries.
3. **`PreyQuestData.lua` — resolved.** Carried forward as-is (the ~90-entry questID table and achievement-ID lists). Nothing to regenerate; can be revisited later if it ever needs updating for new hunts.
4. **Worktree base branch — resolved: `main`.** Section 19.1's original text recommended `release` (with `dev` ruled out as "currently broken"), but that was phrased pending confirmation and no branch was actually named `release` at cutover time — the repo had `main` (current, matches `origin/main`, contains this architecture doc), `release/3.0.2` (3 commits behind `main`), and `dev/3.1.0` (missing this doc, but ahead by one unrelated `isOnMap` fix). Asked directly; `main` was chosen since it's the most current baseline and already includes this document. `rewrite/v2-architecture` was cut from `main` and the worktree was created at `D:\Dev\PreydatorRewrite` per the steps below.
5. **Bloody Command / Echo of Predation — resolved: dormant, not removed.** Confirmed by the product owner (2026-08-25): both were Season 1 mechanics and patch 12.1 discontinued them, so their trigger phrases/events will never occur in current content. Unlike `CurrencyTracker.lua` (Decision 0, permanently out of scope), this code isn't deleted — `sound.bloody_command_enabled`/`sound.bloody_command_path`/`sound.echo_of_predation_path` stay in the settings catalog (Section 5.5), `AlertsRuntime` keeps the Bloody Command chat-pattern detection, and `SoundsRuntime.PlayBloodyCommandSound()`/`PlayEchoOfPredationSound()` stay callable — but `sound.bloody_command_enabled` now defaults to `false` (was `true`) so a future settings UI doesn't present a live-looking toggle for a mechanic that can't fire. Echo of Predation never had a working automatic trigger even in the old codebase (`tryHandleEchoOfPredationNameplate` was referenced but never implemented) and none was added here. Ambush remains fully active — the product owner confirmed it's still relevant.
6. **`UI/BarFrame.lua` — resolved: designed fresh, not ported; `bar.accessibility_theme` values ARE ported.** A bar-rendering research pass (2026-08-27, `issues/bar_rendering_research.md`) found that a prior session's claim of `bar.accessibility_theme` being "net-new work" was wrong — the deuteranopia/protanopia RGBA presets already exist in the old `Modules/Settings.lua` (`BAR_ACCESSIBILITY_PRESETS`, `ApplyBarAccessibilityTheme`) and will be ported as-is; the settings catalog entry (Section 5.6) and MVP table (Section 15) are correct as written, no data changes needed. Separately, and independently of that correction, the product owner asked that `UI/BarFrame.lua` itself — the frame/texture/rendering code — be designed fresh rather than translated line-by-line from the old ~1,000-line `Core/BarRuntime.lua`, to see if a cleaner implementation is possible (the old code's horizontal/vertical text-placement logic in particular took heavy trial-and-error to get right, per the product owner, and is suspected of being inefficient). This is explicitly not a one-way door: the old implementation stays fully intact in the `main` branch/`D:\Dev\PreydatorLive` worktree, so the fresh design can be compared against or abandoned in favor of a closer port later with no lost work either way. The color/coordinate *values* (accessibility presets, stage-percent tables, tick percents) are ported as data; the rendering code that consumes them is new. User-facing customization of bar coloring (including the accessibility presets) stays a requirement either way.
7. **`UI/BarFrame.lua` implementation decisions (2026-08-27).** Building the fresh design from Decision 6 required resolving several specific behaviors the old code and the settings catalog left ambiguous or silently inconsistent (all detailed in `issues/bar_rendering_research.md`):
   - **`text.stage_label_mode` applies identically in both orientations — no silent override.** The old code force-overrides vertical mode to `separate` regardless of the user's chosen mode; the new settings catalog already dropped every old vertical-only text setting in favor of just `bar.vertical_text_side` + `text.label_row_position` + the shared `stage_label_mode`, so the rewrite honors the user's mode in vertical mode too. The 9 modes' "left"/"right" concept is reinterpreted as "start"/"end" of the progress axis (which follows `bar.vertical_fill_direction` in vertical mode) rather than literal screen left/right; `bar.vertical_text_side` picks which side of the bar the (rotated) text sits on, replacing `text.label_row_position`'s above/below role, which only applies in horizontal mode.
   - **One lock/mouse gate, not two.** `frame:EnableMouse(not lockBar or editModeShown)` is the only check; the old code's redundant second check inside `OnDragStart` is dropped since a mouse-disabled frame never receives drag events at all.
   - **Edit Mode integration is event-driven (`EditModeManagerFrame:HookScript("OnShow"/"OnHide", ...)`), not polled** — cleaner than the old code's three separate `IsShown()` checks scattered across the render pass and mouse handlers, and consistent with Section 12's "no `OnUpdate` loops" rule. The old "click the bar during Edit Mode to open Preydator's settings" affordance is not ported (`UI/EditMode.lua`/`UI/SettingsPanel.lua` don't exist yet); revisit once they do.
   - **Position persistence is new schema, simplified.** `bar.position_x`/`bar.position_y` (see Section 5.2) replace the old `point.anchor`/`point.relativePoint`/`x`/`y` table — the first two never actually varied from `"CENTER"` in the old code despite looking general-purpose, so they're dropped rather than ported. No flat-field backup pair either (the old `barPointX`/`barPointY` recovery mechanism) — `SettingsRuntime`'s existing per-field default-fallback behavior already covers corruption recovery for these like any other field.
   - **`bar.show_spark_line` is a real, still-open gap, not resolved by this pass.** The old code has no animation at all (a static texture repositioned to the fill's leading edge); an earlier draft of this doc's Section 12 described an `AnimationGroup`-based animated spark as if porting existing behavior, which was wrong — that would be new visual work. `UI/BarFrame.lua` does not implement `show_spark_line` at all yet; decide before shipping whether to (a) port the old static-texture behavior, (b) build a real animated spark, or (c) drop the setting.
   - **`text.stage_label_mode` was missing from `SettingsRuntime.ENUM_FIELDS` validation entirely** — a pre-existing gap unrelated to this task, fixed while the same file was open for other reasons (the 9 values are now validated like every other enum field).
8. **"Modern" bar appearance presets — resolved: Full-scope, not MVP (2026-08-27).** After the first in-game look at `UI/BarFrame.lua`, the product owner noted it looks visually identical to the old bar — expected, since the rewrite deliberately ported the old default *values* (texture, colors, font, border) as data, per Decision 6, even though the rendering code itself is new. The product owner wants more modern-looking appearance options (e.g. a flatter texture/border combo, using the existing `flat` entry in `bar.texture_key` as a starting point) but didn't have a concrete target in mind and agreed this is additional-settings work for the full release, not something to design now. Added to Section 15's MVP/Full table.
9. **`UI/SettingsPanel.lua` design (2026-08-27).** Like `BarFrame.lua`, this file has no dedicated spec anywhere in this doc (Section 3's file-layout comment is the only mention, and it doesn't even name a `hunt` category — resolved above). The old `Modules/Settings.lua` (3600 lines) was reviewed as a cautionary reference, not a template: it's a single custom canvas panel with every control hardcoded to absolute pixel `x,y` coordinates, a ~500-line single-function tab builder, and a fully-written but never-wired dead tab (`BuildVerticalPage`) — concrete evidence for the product owner's suspicion that this file was AI-overengineered. Decisions made building the new one:
    - **Blizzard's modern Settings API as the backbone, custom canvas only where the native API has no matching control type.** Four categories (General, Bar Display, Sound & Alerts, Hunt Scanner) are 100% native — `Settings.RegisterVerticalLayoutCategory`/`RegisterProxySetting`/`CreateCheckbox`/`CreateDropdown`/`CreateSlider`, zero pixel-position code, and it's reachable via the standard Escape → Options → AddOns → Preydator menu with no `Launcher.lua` dependency. Three categories (Bar Colors, Text & Labels, Advanced) need color swatches, free text entry, or action buttons, which the native API doesn't support — those use `Settings.RegisterCanvasLayoutSubcategory` (a plain Lua frame, no XML) with one shared `anchorRowTop` vertical-stacking helper, so even the hand-built parts never hardcode a y-coordinate.
    - **Dropdowns and sliders inside the three custom-canvas categories are hand-rolled** (a cycle-through button instead of the legacy `UIDropDownMenuTemplate` widget system, and an `OptionsSliderTemplate` slider) rather than reusing the native `Settings.CreateDropdown`/`CreateSlider`, since those only attach to a real Settings category/subcategory object, not an arbitrary canvas frame. Scoped to just the ~6 fields that need it (Text & Labels' font/label-mode dropdowns and font-size slider).
    - **`bar.accessibility_theme` needed more than a plain dropdown.** Building the control
      surfaced that `Core/Settings.lua` never actually got the ported preset-apply function
      Decision 6 promised — the dropdown would have only stored the enum value, not touched
      any color. Fixed in the same pass: `Settings.ApplyBarAccessibilityTheme(themeKey)` now
      carries `BAR_ACCESSIBILITY_PRESETS` (the deuteranopia/protanopia RGBA values, ported
      verbatim from the old `Modules/Settings.lua:119-144`) and bulk-writes the six
      `bar.*_color` fields plus `border_color_linked` in one call; the dropdown's setter
      calls this instead of a plain `Settings.Set`.
    - **Sound-path dropdowns derive their folder prefix from the current setting's own value** (`path:match("^(.*[\\/])")`) rather than duplicating `SettingsStore.lua`'s private `SOUND_FOLDER_PREFIX` constant or exporting it — keeps "single source of truth per concern" intact.
    - **The six Section 5.8 actions, resolved:** Reset Bar Position → `BarFrame.ResetPosition()` (already built). Reset All Settings → `Settings.ResetToDefaults()` (already built), gated behind a confirmation popup since it's destructive and irreversible. Refresh Hunt Cache → `HuntScannerRuntime.RefreshFromAdapter()` (already built, just wired). Restore Default Names / Restore Default Sounds → new but small: `SettingsPanel.lua` iterates a fixed local list of `text.*`/`sound.*` keys and resets each to `Settings.GetDefaults()`'s value — UI-triggered convenience logic, not business logic, so no new module needed. **Reset Hunt Table Position is not built** — there's no `hunt.position_x`/`position_y` field in the settings catalog and no `HuntTablePanel.lua` yet for a position to even mean anything; genuinely blocked, not silently dropped.
    - **A `/preydator` slash command** opens straight to the panel (`Settings.OpenToCategory`) — partially resolves the open "`Modules/SlashCommands.lua` home not yet decided" note (Section 18) for this one command, without taking on the full slash-command migration now.
    - **Known risk, same category as `BarFrame.lua`'s untested geometry:** the exact Settings API call shapes (`RegisterProxySetting`, `CreateControlTextContainer`, `CreateSliderOptions`, etc.) were written from API knowledge, not tested against this client build — `luacheck` catches syntax errors but not a wrong Blizzard call signature. First in-game open of the panel is the real test.
10. **CRITICAL — file-scope UI self-init must never read Settings/State before `PLAYER_LOGIN` (found via live testing, 2026-08-27).** `UI/BarFrame.lua`'s self-init called `RequestRender()` synchronously at file-load time, following what looked like `EventRuntime.lua`'s established convention of "do real work at file scope, don't wait for an explicit lifecycle call." That convention is only safe for *setup* (creating a frame, registering events/hooks) — `RequestRender()` additionally *reads* `Settings.Get(...)`, and SavedVariables (`_G.PreydatorDB`, and therefore everything `Settings.Get` returns) aren't populated by the client until **after** an addon's files finish loading, immediately before its `ADDON_LOADED` fires. Calling it earlier reads an empty/default table — and since `Core/Settings.lua` caches its first load permanently for the session (by design, Section 12), that default snapshot stuck around for the rest of the session regardless of what was actually saved. Symptom: the bar visibly reset to its default position on every `/reload` (found by the product owner in live testing), even though position, and every other setting, appeared to save correctly *within* a session. Fixed by deferring the first `RequestRender()` to a one-shot `PLAYER_LOGIN` listener; the same precaution was applied to `UI/SettingsPanel.lua`'s entire category-registration block as well, since Blizzard's Settings framework may read a proxy setting's current value immediately upon registration (e.g. for its search index) — unconfirmed whether it actually does, but the Options menu can't be opened before `PLAYER_LOGIN` anyway, so deferring cost nothing. **Any future `UI/*.lua` file with file-scope self-init (`Launcher.lua`, `EditMode.lua`, `ThemeEditor.lua`, `ReportWindow.lua`) must gate its first Settings/State-reading call behind `PLAYER_LOGIN` the same way — registering frames/hooks/subscriptions at file scope remains fine, only the first actual *read* needs to wait.**
11. **`UI/SettingsPanel.lua`'s General settings moved to the root category page, not a subcategory (2026-08-27).** The product owner pointed out the root "Preydator" page (shown before clicking into any subcategory) was otherwise empty, making the "General" tab an unnecessary extra click for settings that are used constantly (enable bar/sounds/hunt, lock bar, etc.). `Settings.RegisterVerticalLayoutCategory`'s root category object accepts controls directly, the same as any subcategory — `buildGeneralCategory` was renamed `buildGeneralSettings` and now registers its 7 checkboxes straight onto the root `category` instead of creating a `Settings.RegisterVerticalLayoutSubcategory(category, "General")` first.
12. **`Modules/HuntScanner/HuntTablePanel.lua` design (2026-08-27).** Research turned up two real doc/implementation mismatches, both corrected above rather than carried forward: `HuntTableAdapter.GetOfferedHunts()`'s actual return shape has no reward field at all (the doc's earlier `rewardWidgets` was aspirational, never built), and `HuntScannerRuntime` does not do grouping/sorting despite an earlier draft's prose claiming it does — Section 15's MVP/Full table already correctly marks "HuntScanner: grouping/sorting/reward display" as Full-scope, so this is a doc-accuracy fix, not a new scope cut. Decisions made building the panel:
    - **MVP row subset only: icon + name + zone + Accept, no rewards line.** Matches Section 15 as written; the rewards line stays reserved in the row-layout diagram for the Full-scope follow-up once real reward-data plumbing exists (a new `QuestApiAdapter` function wrapping `C_QuestLog`'s reward APIs — the old code's approach of scraping reward widgets out of Blizzard's live dialog pool via ~8-alias field-name guessing was reviewed and explicitly rejected as a pattern to port).
    - **`HuntScannerRuntime.Subscribe(callback)` added**, mirroring `Core/State.lua`/`Core/Settings.lua`'s existing pattern — `RefreshFromAdapter()` and `OnPreyQuestEnded()` now call `notify()`. Without this, nothing would tell the panel when the hunt list actually changed, short of the panel registering its own raw WoW events (which would violate `EventRuntime`'s "single event dispatcher, no UI calls" rule, Section 7).
    - **Docks beside Blizzard's own `CovenantMissionFrame` (the Hunt Table's Adventure Map frame), not a fixed `UIParent` edge, and not freely draggable like the bar.** First pass anchored to a fixed screen edge instead — in-game testing showed this landed nowhere near Blizzard's own Hunt Table UI, which is what a player is actually looking at; corrected to dock to `CovenantMissionFrame`'s left/right edge (per `hunt.panel_side`), falling back to a screen edge only if that frame isn't shown. The old code auto-docked the same way (beside whichever of `CovenantMissionFrame`/`GossipFrame`/`QuestFrame` was open) and had no drag at all; the new settings catalog still only has `hunt.panel_side`, no `hunt.position_x`/`position_y` — free-drag remains deliberately not built, to avoid reintroducing the class of scale/anchor bugs already found and fixed once this session for `UI/BarFrame.lua`.
    - **Difficulty icon slicing is new work, not a port** — the old code never touched `Media/PreyHuntTableDifficulty_light.png`, using a colored text badge (`[N]`/`[H]`/`[Ni]`) instead. First-pass texcoords assumed the 3 skull icons filled three full-height thirds of the 1536×1024 sheet; live testing showed this squished them (mapping mostly-transparent vertical space into a square icon box). Corrected after actually viewing the sheet to a tighter eyeballed crop — still imprecise. **Superseded entirely (2026-08-27):** the product owner supplied three separate, pre-cropped files (`media/Preydator_{Normal,Hard,Nightmare}_Difficulty.png`) instead of continuing to tune texcoords against the shared sheet. `HuntTablePanel.lua` now does a plain `SetTexture(path)` per difficulty with no texcoord math at all — `DIFFICULTY_ICON_PATHS` replaces `DIFFICULTY_TEXCOORDS`. The original shared sheet stays in the tree but is no longer referenced. One thing flagged for the product owner to verify live: `Normal`'s preview rendered with a black background (typical of real alpha transparency in this environment's image preview) while `Hard`/`Nightmare` rendered with white backgrounds — possibly missing alpha on those two, unconfirmed without live in-game viewing.
    - **Self-init defers its first real render to `PLAYER_LOGIN`**, per the standing rule from Decisions Log item 10.
    - **Panel stayed empty for the whole time the Hunt Table was open, only picking up real hunts once it was closed — first "fixed" by a full port, then found to still regress, and finally resolved by removing a bad assumption the old code itself had, not by porting more of it.** Seven rounds of reconstructing pieces of the old codebase's rescan-timing mechanism one at a time (a staggered `C_Timer` schedule; a direct `CovenantMissionFrame:HookScript` pair, later removed as a taint-elimination test; dynamic `UPDATE_UI_WIDGET`/`UPDATE_ALL_UI_WIDGETS` registration; a debounce) each fixed something real but kept surfacing the next missing piece, because the old code's actual mechanism is one coherent state machine, not independent parts. Two real bugs found along the way: `QUEST_DATA_LOAD_RESULT` (fired once per quest by this addon's own `RequestLoadQuest` calls, up to 15 times per scan) was falling into the same dispatch branch as "table closed," completely undebounced; and `UPDATE_UI_WIDGET`/`UPDATE_ALL_UI_WIDGETS` were being registered but never added to `HANDLED_EVENTS`, so every firing was silently dropped before dispatch — dead code, not a contributor either way. After the product owner explicitly called out the reactive pattern, a first fix attempt did a deliberate, faithful **port** (not a redesign) of the old `Modules/HuntScanner.lua` interaction-tracking state machine into `EventRuntime.lua`, including its exact `GOSSIP_SHOW`/`PLAYER_INTERACTION_MANAGER_FRAME_SHOW` dispatch branching. **That port regressed the bug further** (panel didn't render even after clicking a quest pin) — root-caused via a live debug-print trace (2026-08-27) to a real design flaw the old code itself has, not a porting mistake: both of those "just opened" events make one synchronous check (a gossip-option scan / `CovenantMissionFrame:IsShown()`) at the exact instant the event fires, decide `huntInteractionActive` once from that single result, and never recheck. The trace proved `CovenantMissionFrame:IsShown()` is still `false` even on its own `..._FRAME_SHOW` event and only flips `true` several seconds later — so the old code's mechanism only ever appeared to work because some *other*, unrelated event (`QUEST_DATA_LOAD_RESULT`, firing for unrelated reasons) happened to land after that delay and coincidentally re-triggered a scan; the port made this worse by also depending on `HasHuntTableGossipOption()`'s narrower single-instant check. **Final fix (2026-08-27):** `GOSSIP_SHOW`/`PLAYER_INTERACTION_MANAGER_FRAME_SHOW` now both call `beginHuntTableWatch()`, which checks `HuntTableAdapter.IsHuntTableActive()` immediately and then again on each of the existing staggered delays (`0.05` through `10.00` seconds, same schedule as the old debounce-then-burst timing) — a sequence token cancels a stale watch if the interaction ends first. Every pass re-evaluates fresh instead of deciding once, so whichever pass lands after `CovenantMissionFrame` actually becomes visible is the one that activates tracking, closing the gap the trace proved exists. This also simplified the dispatcher: the two small adapter functions the port had added (`IsMissionFrameVisible()`, `HasHuntTableGossipOption()`) turned out to be exactly the kind of single-instant check that caused the regression, so both were removed again from `HuntTableAdapter.lua` — `EventRuntime.lua` now reads only the one already-robust `IsHuntTableActive()` signal, repeatedly. Explicitly **not** ported, per the product owner's direction, in either the port or the final fix: the old panel's own rendering (`HuntTablePanel.lua` stays exactly as already built), the Settings-preview concept (doesn't exist here), the classic gossip-quest-dialog events (`QUEST_DETAIL`/`QUEST_PROGRESS`/`QUEST_COMPLETE` — this rewrite only targets `CovenantMissionFrame`, not the older gossip-dialog UI some Hunt Tables historically used), achievement-signal events (Full-scope per Section 15), and the old code's redundant "active prey quest, not in hunt context -> force hide" branch (`HuntTablePanel.Render()`'s own explicit `IsHuntTableActive()` gate, added earlier this session, already covers this more directly). **Still unresolved:** the `ADDON_ACTION_FORBIDDEN`/`SpellStopCasting` taint error narrowed to Hunt Table interaction — never definitively root-caused; needs re-testing against this final fix, since the earlier hypothesis it might share a root cause with the rescan-timing bug was never confirmed.
13. **Vertical bar orientation — resolved: QA/polish deprioritized to Full, code stays as-is (2026-08-27).** The product owner suggested vertical orientation might belong in Full release rather than MVP, reasoning MVP should focus on getting the core loop operational while Full carries the "bells and whistles." The architecture's module boundaries are one shape for both paths (Section 15's header note), and `bar.orientation`'s vertical branch is already woven through `UI/BarFrame.lua`'s geometry/label functions rather than being a separable chunk of code — ripping it out would cost effort, not save it. So the resolution is: the code stays exactly as built, but *verifying and visually tuning* vertical mode (it hasn't been seen rendered yet — it's blocked on `UI/SettingsPanel.lua` existing to toggle `bar.orientation` in-game) is deprioritized until Full release, alongside the other polish items. Added to Section 15's MVP/Full table.
14. **Root-caused and fixed the `ADDON_ACTION_FORBIDDEN`/`SpellStopCasting` taint (2026-08-28) — resolved: never register into `_G.StaticPopupDialogs`, use a Preydator-owned confirm frame instead.** This taint (Decision 12's "still unresolved" callout) had been narrowed to Hunt Table interaction in the prior session but not root-caused. Live elimination testing this session (systematically disabling/re-enabling whole files, then individual code paths, via `Preydator.toc` and targeted early-returns, retesting after each change) found it reproduced on *two* independent triggers — a plain relog with zero Hunt Table interaction, and any Hunt Table touch — and traced both to the same single line: `UI/SettingsPanel.lua`'s "Reset All Settings" button registering a confirmation dialog into Blizzard's shared `_G.StaticPopupDialogs` table (`StaticPopupDialogs["PREYDATOR_RESET_ALL_SETTINGS"] = {...}`). Ruled out first: the entire `Modules/HuntScanner/*` set, `WidgetAdapter.lua`'s `hooksecurefunc(UIWidgetTemplatePreyHuntProgressMixin, "Setup", ...)` hook, and `BarFrame.lua`'s `EditModeManagerFrame:HookScript(...)` pair — all taint-shaped patterns that turned out to be innocent. Within `SettingsPanel.lua`, deferring the registration to `PLAYER_LOGIN` (matching every other Settings-API call in the file) did **not** fix it, and removing the `hideOnEscape` field specifically did **not** fix it either — the table write itself was the trigger, not its timing or any one field. Rather than keep bisecting individual fields (diminishing returns, several more relog cycles for an uncertain payoff), replaced the whole mechanism: `ensureResetConfirmFrame()` builds a small Preydator-owned frame (`BackdropTemplate`, Yes/No `UIPanelButtonTemplate` buttons) that never touches any Blizzard global table, with no `UISpecialFrames`/Escape-key integration either (deliberately, for the same reason). Confirmed clean in-game across all three original repro paths (plain reload, full relog, Hunt Table interaction) plus the rebuilt "Reset All Settings" flow itself. See memory `preydator-taint-staticpopupdialogs` for the full elimination method, reusable for any future Preydator taint report.
15. **Root-caused and fixed the Hunt Table panel never rendering (2026-08-28) — resolved: hide events are re-checks, not immediate hides; noisy widget events must be time-bounded.** A temporary event-name print at the top of `EventRuntime.HandleEvent` (the diagnostic step queued up from Decision 12) proved the trigger events do fire, and showed why the panel never activated: this NPC's real flow is `GOSSIP_SHOW` → `PLAYER_INTERACTION_MANAGER_FRAME_SHOW` → `GOSSIP_CLOSED` → `PLAYER_INTERACTION_MANAGER_FRAME_HIDE`, all within about one frame, *before* `CovenantMissionFrame` (the actual map) ever becomes visible — gossip closing here is an intermediate UI transition (gossip → map), not the player leaving. The design up to this point treated `GOSSIP_CLOSED`/`..._HIDE` as an immediate "player left" signal (`hidePanel()`), which bumped the watch's sequence token and cancelled the in-flight staggered watch from the `SHOW` event a moment earlier — killing the mechanism before any of its staggered passes ever got a chance to see the map become visible. Not a rendering bug at all; every fix attempt up through Decision 12 was correctly reasoned but aimed at the wrong layer. **Fix:** all five lifecycle events (`GOSSIP_SHOW`, `PLAYER_INTERACTION_MANAGER_FRAME_SHOW`, `GOSSIP_CLOSED`, `PLAYER_INTERACTION_MANAGER_FRAME_HIDE`, `QUEST_FINISHED`) now trigger the identical re-checking watch (merged into one `HUNT_RECHECK_EVENTS` set, replacing the old separate watch/hide sets) — `HuntTableAdapter.IsHuntTableActive()`'s existing 3-signal check remains the single source of truth for enter/leave, never a raw event name. `checkHuntInteraction()` also now rescans on the active→inactive transition (previously only while staying active, so a genuine leave via this path left a stale list on screen). **Follow-on bug found during live confirmation:** once active, `UPDATE_UI_WIDGET`/`UPDATE_ALL_UI_WIDGETS` (fire for *any* UI widget change anywhere in the game) stayed registered for the full open-ended duration of `huntInteractionActive` — and since "pins visible" alone can sustain that indefinitely just from the map being left open, the noisy events kept firing and re-scanning forever with no further genuine interaction. Per the product owner, the underlying pin data barely changes (weekly, or on prey completion), so this was pure waste, not a correctness need. Fixed: `beginHuntTableWatch()` now auto-unregisters the noisy widget events once its bounded window (`WATCH_DELAYS`'s last entry, ~10s) concludes; a fresh `HUNT_RECHECK_EVENTS` event re-arms both the watch and noisy-event listening from scratch. Confirmed live: panel renders correctly on interaction, and only a single one-shot `UPDATE_UI_WIDGET` fires afterward instead of a continuous loop.
16. **`hunt.preview_enabled` added (2026-08-28) — a Settings-only preview toggle for `HuntTablePanel`.** During live scanning/display testing, the product owner asked for a way to see `hunt.width`/`height`/`scale`/`font_size` changes without leaving Settings to check the real Hunt Table each time. Added a checkbox on the same Hunt Scanner subcategory as those sliders (`UI/SettingsPanel.lua`) that sets `hunt.preview_enabled`; `HuntTablePanel.Render()` bypasses its `hunt.enabled`/`IsHuntTableActive()`/empty-list gate entirely when it's on, reusing the real panel (not a separate mockup, so it's exactly WYSIWYG) with the real cached hunt list if one exists or 3 placeholder rows (`HuntTablePanel.buildPreviewHunts()`, using mapID `2561` — a real, currently-valid zone the product owner had just confirmed, though later zone-phase testing revealed `2561` is actually the broad "Quel'Thalas" region map, not the specific "The Coiled Isle" zone the product owner meant; see Decision 18 (the zone-resolution fix) — harmless for a placeholder's purposes either way, not worth a follow-up patch) otherwise. Initially a pure checkbox-driven toggle with no auto-hide-on-Settings-close, confirmed with the product owner as intended -- **reversed after live testing the following behavior**: with the checkbox still checked, closing Settings fell back to the screen-edge dock instead of disappearing, which the product owner then flagged as not actually wanted -- the preview only makes sense while Settings is open to compare against. `_G.SettingsPanel`'s `OnHide` hook now auto-sets `hunt.preview_enabled` back to `false` (which itself notifies `Settings.Subscribe` and re-renders/hides the panel) rather than just re-rendering at its old position. **Docking refined the same session:** initially fell all the way back to the same screen-edge anchor as the real panel when Settings was open, which the product owner flagged as likely to overlap other addons' UI while fine-tuning sliders. `applyPanelPosition()` now has a three-tier priority: real Hunt Table (`CovenantMissionFrame`, unchanged) → the Settings window itself (`_G.SettingsPanel`, new, only while `hunt.preview_enabled` is on) → screen edge (unchanged fallback for when neither is shown). A `HookScript("OnShow"/"OnHide", ...)` on `_G.SettingsPanel` (same established, already taint-tested pattern as `UI/BarFrame.lua`'s `EditModeManagerFrame` hook) re-renders immediately when Settings opens or closes so the dock target updates without waiting for an unrelated setting change.
*(Numbering note: item 17 doesn't exist — an early draft's item 16 referenced a not-yet-written "Decision 17" that became this item 18 once actually written up; corrected to point here rather than renumbering every subsequent entry. Not a missing/lost decision.)*

18. **Root-caused and fixed the "Quel'Thalas" zone-name issue (2026-08-28) — resolved: prefer the pin's own map position over quest metadata, no hardcoded override table.** During the zones testing phase, the product owner reported a hunt's zone showing as "Quel'Thalas" when they expected "The Coiled Isle." Live `/run` diagnostics (`C_Map.GetMapInfo`, `C_Map.GetBestMapForUnit`, cross-referenced against the product owner physically flying the zone and recording mapIDs) proved `C_TaskQuest.GetQuestZoneID` returns the broad continent/region map (`2561`, which Blizzard itself names "Quel'Thalas") for these Hunt quests, not the specific leaf zone the pin is actually in (e.g. `2512`, "The Coiled Isle" — confirmed by `GetBestMapForUnit` while standing there). `HuntScannerRuntime.RefreshFromAdapter()` already had a pin-coordinate-based lookup (`MapContextAdapter.GetMapInfoAtPosition`, using the pin's own `normalizedX`/`normalizedY`) but only used it as a fallback when quest metadata returned `nil` — since quest metadata wasn't nil here, just too broad, the fallback never triggered. **Fix:** swapped the priority so the position-based lookup runs first (resolves down the map hierarchy to the specific zone at that exact point), falling back to quest metadata only when position data isn't available. Confirmed live: 12 of 15 hunts now resolve to their specific zone with no regression on the rest. For the remaining 3, a follow-up diagnostic (calling `C_Map.GetMapInfoAtPosition` directly with the same coordinates) proved *both* signals independently agree on `2561` — Blizzard's own API has no more specific answer for those particular hunts, so this was accepted as "as accurate as the live API gets," not chased further with a hardcoded per-quest override (which would violate `CLAUDE.md` Section 4's ban on a persistent questID→zone mapping, and go stale every content rotation).
19. **Reward display built end-to-end (2026-08-28), including real item/container icons with no taint — resolved via two complementary safe data sources, deliberately not the old codebase's exact technique.** During live scanning of the actual reward APIs, found that `C_TaskQuest`/`C_QuestLog` reward-detail calls (`GetQuestLogRewardInfo`, `QuestUtils_AddQuestRewardsToTooltip`) never resolve item/container reward data for these Hunt quests pre-*or*-post-accept (tested both), but currency/money/XP rewards resolve reliably via `QuestUtils_AddQuestRewardsToTooltip` against the real shared `_G.GameTooltip` (a custom-built scratch tooltip crashes on container-type rewards — `EmbeddedItemTooltip_SetItemByQuestReward` needs sub-widgets only a fully-built tooltip has). `QuestApiAdapter.GetQuestRewardSummary(questID)` wraps this (parses the returned icon-tagged tooltip lines via pure string pattern matching, e.g. `|T7734062:16:16|t 10 Veteran Mistcrest` → `{icon, quantity, name}` — no widget access at all for this path). For the item/container reward specifically, the product owner explicitly asked to chase full parity (a generic placeholder icon isn't enough for user retention) rather than accept the gap, pointing at the old codebase's `WarmRewardCacheFromPins` (`Modules/HuntScanner.lua:2906`) as reference — which got real chest/bag icons by briefly showing the real `AdventureMapQuestChoiceDialog` off-screen (the exact alpha/position technique `HuntTableAdapter.AcceptHunt` already uses safely) and reading its `rewardPool` widgets. That same file's own hotfix comment warns this "has repeatedly tainted Blizzard tooltip/money arithmetic paths (secret number values)," so before building anything real on it: (1) a temporary diagnostic dumped this client's *actual* current widget field names (`.Name.GetText()`, `.Icon.GetTexture()`, `.Count.GetText()`, `.rewardType` — a clean, precise set, not the old code's ~8-alias per-field guessing, and notably `rewardType` is Blizzard's own `"currency"`/`"item"` string, identifying the chest directly with no name-heuristics needed); (2) live-tested immediately after with an Escape check — no taint, confirming the *read-only* extraction (`type()`/`GetText()`/`GetTexture()` only, zero arithmetic on any scraped value, zero protected-method calls) doesn't reproduce whatever the old code's fuller implementation (polling/retry state machine, broader field access, per-difficulty write-back logic) actually tripped. `HuntTableAdapter.GetRewardWidgets(questID)` is the resulting production function. Per the product owner's own observation that hunt rewards are identical across every quest of a difficulty and only rotate every 2 completions/week, `HuntScannerRuntime.rewardWidgetsByDifficulty` caches one peek per difficulty (not per quest) for the session — covers all 15 offered hunts from 3 dialog show/hides total, re-confirmed live with no taint even across 3 rapid back-to-back cycles. Falls back to `QuestApiAdapter.GetQuestRewardSummary`'s currency-only data (plus a generic mystery-reward icon, `HuntTablePanel.MYSTERY_REWARD_ICON`) until a difficulty's first widget peek completes. `HuntTablePanel.lua`'s row rendering (icon + quantity only, full name+quantity via a new per-icon hover tooltip — not something the old code had either, per the product owner) needed no changes between the fallback and upgraded-to-real-icon paths since both feed the same `{icon, iconIsAtlas, quantity, name}` entry shape. See memory `preydator-safe-widget-introspection` for the reusable safety finding (which specific technique is confirmed safe vs. which part of the old code's approach remains unconfirmed/unrecommended).

20. **Two "built but never called" gaps found and fixed while starting live Prey Hunt tracking (2026-08-28), plus `Core/SlashCommands.lua` built to make catching more of these faster.** Testing an active hunt found two settings that visibly did nothing: `general.only_show_in_prey_zone` (bar didn't appear in the correct zone) and `general.disable_default_prey_icon` (Blizzard's own prey icon stayed visible). Root cause for both, same shape as each other: `SoundsRuntime.PlayStageSound` and `WidgetAdapter.SuppressDefaultPreyIcon` were both fully implemented (from the 2026-08-25 build pass) but neither was ever actually *called* from anywhere — `PreyContextRuntime.RefreshPreyContext()` computed stage/zone state and wrote it to `State`, but never triggered either side effect. Fixed by calling both from `RefreshPreyContext()` (both self-guard/are idempotent, so safe to call every refresh tick); icon suppression is gated on `hasActiveQuest` so it correctly un-suppresses when tracking stops rather than leaving the icon hidden forever. The product owner asked for a proper diagnostic tool to catch more of these while testing the progress-tracking system, referencing the old codebase's `/pd inspect|qinspect|hinspect|pinspect [bs]` convention (`bs` = dispatch to BugSack). Found that `Core/Runtime/DiagnosticsRuntime.lua` already had `BuildGeneralInspectReport`/`BuildProgressInspectReport`/`BuildQuestInspectReport` built from the same 2026-08-25 pass — also never wired to a slash command. Built `Core/SlashCommands.lua` (the file the old `Modules/DebugInspect.lua`/`Modules/SlashCommands.lua` glue is retired in favor of, per Decisions Log item 18's note) as a thin `/pd` dispatcher reusing those three existing reports, plus a new fourth: `BuildHuntInspectReport` (Hunt Table active-state, `HuntTableAdapter`'s raw pin count vs `HuntScannerRuntime`'s scanned list with each hunt's resolved zone/reward summary, and `EventRuntime`'s private interaction-tracking state via a new read-only `GetHuntTrackingDebugState()` getter — otherwise invisible outside that file). BugSack dispatch reuses the `geterrorhandler()` pattern validated during the rewards phase (Decisions Log item 19). `ainspect` (achievement inspect) from the old convention was not built — achievements are Full-scope and not currently testable on this account (product owner would need a different account/region/level).
21. **Root-caused and fixed live Prey Hunt stage/progress tracking end-to-end (2026-08-28), plus a redesign of ambush detection based on a real live chat log.** `/pd wdebug` (built for this) showed `UIWidgetTemplatePreyHuntProgressMixin` existed (`mixinExists=true`) but the hook never installed (`mixinHooked=false`), while a live matching widget already sat in `UIWidgetPowerBarContainerFrame` — the one-shot `ADDON_LOADED("Blizzard_UIWidgets")`/initial-`IsAddOnLoaded` trigger ran before the mixin was actually ready, and nothing ever gave the hook a second chance. Fixed by having `WidgetAdapter.GetWidgetStage()` retry `ensureMixinHooked()` on every call (already invoked every `PreyContextRuntime` refresh tick while a hunt is tracked; cheap no-op once hooked) instead of depending solely on that one-shot trigger. Separately, even once the hook fired correctly, the bar/sound only reflected a fresh widget snapshot whenever some *unrelated* event (zone change, quest log update) happened to trigger the next `RefreshPreyContext()` — confirmed live as a 30-45 second lag. Fixed by having the `Setup` hook schedule a `RefreshPreyContext()` call via `C_Timer.After(0, ...)` — deferred to the next frame specifically so it runs outside the hook's own secure call chain (this file's own comment already establishes that calling protected frame methods, which `RefreshPreyContext` transitively reaches via `applyFrameSuppression`, is unsafe *un-deferred* from inside this hook; deferring sidesteps that entirely, a standard WoW addon technique). Also added a widget-independent safety net for the final stage: the quest's own "Hunt your Prey" objective reaching `finished = true` now forces `stage = FOUND_STAGE` (4) regardless of what the widget system reports, based on the product owner's own domain knowledge (ambushes only occur through stages 1-3; the objective flips to finished exactly at stage 4). **Ambush detection redesigned entirely**, from a real live chat log showing the previous approach's actual failure modes: matching the prey's name/dialogue content against a short guessed list of fallback phrases (`"ambush"`, `"you've stumbled right into my trap"`, `"a momentary setback"`) both missed a real ambush (the prey's actual line, "The flames obey me, as you should!", matched none of them) and would have false-matched an unrelated NPC's line in the same log (Astalor Bloodsworn's "I suspect an ambush," which contains the word "ambush" incidentally). The same log showed a clean, standalone `CHAT_MSG_SYSTEM` message, "Ambushed!" — sender-independent and identical for every prey NPC. `AlertsRuntime.lua` now keys ambush detection off that system message exclusively (`isAmbushSystemMessage`), dropping the old per-NPC name/phrase matching entirely; Bloody Command detection is unchanged. Also exposed `sound.alert_cooldown_seconds` in the Sound & Alerts settings UI for the first time (existed in code with validation since the initial build pass, never had a UI control) and raised its default from 30 to 60 seconds per the product owner's live-testing feedback (some hunts die fast enough that the shorter cooldown let the ambush sound replay awkwardly close together). A separate, lower-priority finding not yet fixed: `SoundsRuntime`'s stage-sound anti-replay tracking is session-lifetime only, so a hunt already past stage 1 replays that stage's sound on every `/reload` — fixing it trades that for "no sound on the very first stage of a genuinely new hunt" (can't distinguish the two cases), so it's parked pending the product owner's call on which behavior they'd rather have.
22. **Stage tracking still didn't update live after Decision 21's fixes — root-caused further and fixed for real (2026-08-28).** Live retesting after Decision 21 showed `mixinHooked=true` but `widgetSnapshot` still `nil` for the entire session (`Setup` never fired even once since the reload). A new deep, read-only field dump added to `/pd wdebug` (same safe `pairs()`+`type()`/`GetText()` technique as the reward-widget work, still never reading `widgetID`/`widgetType`/`shownState`) revealed `progressState` and `tooltip` sitting as **plain fields directly on the live widget frame instance itself** — always current, not something that requires waiting for `Setup` to hand them over at all. `WidgetAdapter.GetWidgetStage()` now reads these live off the frame directly (`buildSnapshotFromLiveFrame`) as the *preferred* source, falling back to the `Setup`-hook-captured snapshot only if no live frame is found — this fixed data *accuracy* (confirmed live: `progressState`/`stage`/`fillPercent` all correct on demand via `/pd inspect`) but not update *frequency*: the bar still only visibly changed on a zone/subzone change, because nothing was calling `RefreshPreyContext()` on any faster cadence, and `Setup` (the only non-context-event trigger) still isn't firing reliably. Considered registering `UPDATE_UI_WIDGET`/`UPDATE_ALL_UI_WIDGETS` (Blizzard's general "a widget changed" events) for the whole tracked-hunt duration, but rejected it — those fire for *any* widget change anywhere in the game, and a hunt can be tracked for many minutes, unlike the Hunt Table's already-fixed bounded ~10s watch (Decision 15); registering them for an unbounded duration would reintroduce the same class of overhead. Instead, `EventRuntime.lua` now owns a plain, bounded `C_Timer.NewTicker` (2s interval) that starts when a hunt becomes tracked and stops when it isn't (restricted instance entered, or `activeQuestID` clears) — simpler and more predictable than filtering a very-noisy global event stream. The ticker only decides *when* to re-run `RefreshPreyContext()`; all actual gameplay logic (fail-closed gating, zone/stage re-derivation) stays exactly where it already lived, nothing duplicated. **Confirmed live immediately after: stage tracked correctly through the full 1→2→3→4 sequence, sounds played on each transition, bar reflected 100%/stage 4 at the finish — the progress-tracking MVP milestone is functionally complete.** One more gap found in the same test: an ambush that led directly into the stage 3→4 transition played no sound, because the ambush gate required `stage < 4` and the polling ticker had already raced ahead to stage 4 by the time the chat message was processed. Removed the stage upper bound entirely rather than tuning it — the "Ambushed!" system message is already the authoritative signal (that was the whole point of Decision 21's redesign), so it doesn't need a second-guessing stage check on top of it, especially one sourced from a polled value that can legitimately be stale by up to the ticker's own interval.
23. **Fixed a lingering glow/shine "aura" staying visible on the default prey icon after suppression (2026-08-28).** The product owner noticed the icon itself correctly disappeared when "Hide Blizzard's Prey Icon" was on, but a glow/shine effect stayed visible. Checked the old codebase's `main` branch (`git show main:Preydator.lua`) for its `ApplyWidgetFrameSuppression`/`StopFrameAnimations` — it explicitly cancelled a separate `effectController` system on the widget frame, described in its own comment as handling exactly this kind of lingering visual. The old code's hardcoded list of named animation sub-fields to stop (`AnimIn`/`AnimOut`/`GlowAnim`/`PulseAnim`/`Loop`/`LoopingGlow`/`Shine`) doesn't match this client's actual structure (confirmed via the same deep field dump built for stage tracking, Decision 22 — those names are functions on the current frame, not animation objects; the real ones are `FadeInAnim`/`FadeOutAnim`/`GainProgressAnim`/`TransitionAnim`). `WidgetAdapter.lua`'s `stopFrameAnimations` now also stops those four, and calls the frame's own `ClearEffects()` method (confirmed present on the live widget, a cleaner direct equivalent to the old code's `effectController:CancelEffect()`). Kept exclusively in the same already-established safe call path (`applyFrameSuppression`, never called from inside the `Setup` hook) — same taint-safety boundary as the existing `SetAlpha`/`Hide` calls there, nothing new introduced.
24. **Fixed stage-transition sounds replaying on every `/reload` (2026-08-28) — the tradeoff parked in Decision 21 was resolved in favor of fixing it.** Caused a real, confusing symptom live: a `/reload` before starting a new hunt replayed the previous hunt's current-stage sound regardless of location ("sounds playing in the wrong zone"). `SoundsRuntime.PlayStageSound`'s first-observation-per-quest-per-session case now baselines silently (stores the current stage without playing) instead of falling through to the normal play path — accepting the traded-off cost (no sound on the very first stage of a genuinely new hunt, since a reload can't be distinguished from a new hunt with current state) since the product owner hit the replay case live and wanted it fixed.
25. **Added `/pd sinspect [bs]`, and it immediately caught a real bug (2026-08-28).** Product owner asked for visibility into recent sound plays while debugging the above. `SoundsRuntime.GetRecentPlays()` exposes the last 12 `playPath` attempts (trigger, played/blocked, and why if blocked, via a new `recordPlay` call inside `playPath`). Used immediately to debug a real ambush that produced no sound: live chat showed "Ambushed!" but `sinspect` showed *zero* ambush attempts, not even a blocked one — proving `AlertsRuntime`'s `event == "CHAT_MSG_SYSTEM"` gate (Decision 21) itself rejected the message before ever checking its text, meaning "Ambushed!" is delivered via some other event type (unconfirmed which). Broadening to check every `CHAT_TRIGGER_EVENTS` type would have reintroduced the exact false-positive Decision 21 fixed (Astalor Bloodsworn's own "I suspect an ambush" dialogue matching on text alone) — fixed properly instead by requiring an empty `sender` (no NPC-name attribution) alongside the "ambush" text match, which distinguishes the real notification from any NPC's own dialogue regardless of which event type carries it, so the exact type doesn't need to be pinned down. Also closed the diagnostic blind spot that let this slip past `sinspect` in the first place: `PlayAmbushSound`/`PlayBloodyCommandSound` now call `recordPlay` directly when their own `sound.*_enabled` check stops them before ever reaching `playPath`, so a report showing zero attempts is now only possible when a trigger genuinely never fired at all, not ambiguous with "blocked before logging."
26. **Fixed the default prey icon flashing briefly on every progress-contributing action, even with suppression on (2026-08-28).** Root cause: Blizzard's own `PlayGainProgressAnim` (confirmed present on the widget via Decision 22's deep field dump) shows the icon and plays a pulse animation directly, independent of our suppression state -- our re-hide only ran on the next deferred/ticker refresh, so the icon flashed for up to a couple seconds each time. Fixed the same safe way as the stage-tracking lag (Decision 22): `hooksecurefunc` on `PlayGainProgressAnim` (read-only observe, same mixin as the existing `Setup` hook) schedules a `C_Timer.After(0, ...)`-deferred re-suppression, narrowing the flash to at most one frame -- can't be fully eliminated without calling a protected method (`Hide`) from inside the hook itself, which the file's own established taint-safety rule forbids. **Current behavior is hardcoded, not configurable**: when `general.disable_default_prey_icon` is on, the icon is suppressed as completely as this mechanism allows, full stop. The product owner explicitly asked for this to become a toggleable option later (some users may want to see the brief flash) -- noted here as a real, scoped Full-scope follow-up, not built now. Recording the exact current configuration for when that's built: suppression applies only while a hunt is actively tracked (`PreyContextRuntime`'s `hasActiveQuest` gate, Decision 20), driven purely by the one boolean setting, with no user control over the flash/animation behavior at all.
27. **Wired `HuntScannerRuntime.OnPreyQuestEnded` for real (2026-08-28) — another "built but never called" gap, and a genuine cache-freshness fix.** The product owner completed two Normal-difficulty hunts and correctly expected the cached reward data for that difficulty to refresh (rewards can rotate on completion, per their own earlier observation about weekly/completion-based rotation) — but `OnPreyQuestEnded` (built during the initial pass, clears the per-quest zone cache) was never actually called from anywhere in the rewrite. Wired in `EventRuntime.lua`'s `QUEST_TURNED_IN` dispatch, gated on `PreyQuestData`'s static table (the same one `HuntScannerRuntime`'s own difficulty resolution already trusts) to confirm the turned-in quest was actually a Prey Hunt — avoids racing against `RefreshPreyContext`'s own `State.ClearActiveQuest()` call earlier in the same dispatch, which would make a State-based "was this our tracked hunt" check unreliable. `OnPreyQuestEnded` now also clears the *entire* `rewardWidgetsByDifficulty` cache (all 3 difficulties), not just the completed hunt's own one — deliberately not trying to determine precisely which one difficulty changed, since a reliable post-completion difficulty lookup isn't always available (not every hunt is in `PreyQuestData`'s static table, and text-fallback resolution needs a title/description this event doesn't carry), and the product owner explicitly said a full re-peek is cheap enough to just always do. Does not force an immediate re-scan (`RefreshFromAdapter` reads live pins, which would be empty and wipe the list if called while not actually at the Hunt Table) — the cleared cache simply gets naturally repopulated next time a real scan happens.

28. **Full-scope backlog item added: stable reward icon/text ordering (2026-08-28).** The product owner asked that reward icons and their quantity text always render in the same order within a hunt row, rather than whatever order the underlying source returns. Currently `HuntTablePanel.applyRewardIcons` renders `hunt.rewardEntries` exactly as `HuntScannerRuntime.RefreshFromAdapter` built it — either straight from `HuntTableAdapter.GetRewardWidgets`'s `rewardPool:EnumerateActive()` iteration order (a Blizzard widget pool, no ordering guarantee) or from `QuestApiAdapter.GetQuestRewardSummary`'s tooltip-line parse order — neither is a stable, addon-controlled sort. Not built now: no sort key has been chosen yet (candidates: `rewardType` grouping i.e. currency before items, then by icon/name, or quantity descending) and this only matters once reward display itself is considered stable. Added to Section 15's MVP/Full table under HuntScanner.

29. **Root-caused and fixed the bar not appearing for a hunt the player was genuinely standing in (2026-08-28) — the zone pre-filter's equality check didn't account for map hierarchy.** Product owner reported no bar on The Coiled Isle while tracking an active Nightmare hunt (`/pd qinspect` confirmed `isOnMap=true`, but `/pd inspect` showed `inPreyZone=false | expectedZoneMapID=2561` against `playerMapID=2512`) and correctly guessed the cause themselves: the Section 8 pre-filter in `PreyContextRuntime.RefreshPreyContext()` was short-circuiting to `inPreyZone=false` without ever reaching the authoritative `QuestApiAdapter.GetQuestIsOnMap()` call. Confirmed: `state.expectedZoneMapID` for this hunt had resolved to `2561` (Quel'Thalas, the broad continent map — `HuntScannerRuntime`'s `GetQuestZoneID` fallback path, same one documented in Decision 15's zone-resolution fix as "accepted as accurate" for the Hunt Table panel's *display* purposes) while `playerMapID` is `2512` (The Coiled Isle, the specific leaf zone nested inside it). The pre-filter's raw `expectedZone ~= playerMapID` equality check treats "broader" and "wrong" identically, so a player standing in the correct specific zone under a hunt whose expected zone only resolved to the broad continent map could never pass the pre-filter, regardless of the real answer. **Fix:** added `MapContextAdapter.DoesMapContain(ancestorMapID, mapID)` — walks `C_Map.GetMapInfo(mapID).parentMapID` up to 10 hops, matching if `ancestorMapID` appears anywhere in the chain. `PreyContextRuntime`'s pre-filter now only short-circuits to `false` when the maps mismatch *and* `DoesMapContain(expectedZone, playerMapID)` is also false — preserves the existing "pre-filter never asserts 'in zone' by itself, only decides whether to defer to the authoritative check" design (CLAUDE.md's `isOnMap` rule, Section 8), just makes the mismatch test hierarchy-aware instead of exact-match-only. Not yet re-tested live.

30. **Redesigned ambush detection from chat-message parsing to nameplate-based detection (2026-08-28) — the product owner's own suggested approach, modeled on RareScanner/SilverDragon.** A real ambush's chat log (`/pd sinspect`, no ambush entry at all) confirmed the third chat-based redesign attempt (Decision — see AlertsRuntime's own file history: prey-dialogue matching → `CHAT_MSG_SYSTEM`-only → every `CHAT_TRIGGER_EVENTS` type with an empty-sender check) still didn't work, and the TEMP wide-net diagnostic deployed to find the real event (a dozen additional `CHAT_MSG_*` types, plus `RaidNotice_AddMessage` and `UIErrorsFrame:AddMessage` hooks) produced zero output against that same confirmed real ambush. Conclusion: "Ambushed!" is not reliably observable through any chat/banner API this addon can hook, so no amount of further guessing at event types would fix it. The product owner proposed detecting the prey mob's own presence directly instead, the way rare-spawn-tracking addons work. **Implementation:** `EventRuntime.lua` registers `NAME_PLATE_UNIT_ADDED` (new `NAMEPLATE_EVENTS` category, dispatched the same way `CHAT_EVENTS` already is) and forwards to a new `AlertsRuntime.HandleNameplateEvent(unit)`, which compares `UnitName(unit)` against `state.preyTargetName` (already parsed from the quest title by `PreyContextRuntime`, no new data source needed) and plays the ambush sound on a match — same settings/zone/restricted-instance/cooldown gating as the old chat-based path, just a different trigger signal. The old `isAmbushNotification` chat-matching function and the entire TEMP wide-net diagnostic block are removed from `AlertsRuntime.lua`; Bloody Command detection (dormant, unrelated mechanic) keeps its existing chat-text matching untouched. Not yet re-tested live — needs the product owner to trigger a real ambush and confirm the sound plays.

31. **Root-caused (more precisely) and re-fixed the default prey icon still flashing/pulsing on progress gain, after Decision 26's fix proved incomplete (2026-08-28).** Decision 26 hooked Blizzard's `PlayGainProgressAnim` mixin method specifically, reasoning it was the one function driving the pulse. Product owner confirmed live the icon still pulsed every time afterward — meaning that hook wasn't catching every code path that shows the icon. Most likely cause: the generic Blizzard UIWidget container system (which owns the widget's pooling/layout, entirely separate from the PreyHunt-specific mixin this file hooks) can call `Show()` on the widget frame directly as part of laying out updated widget data, independent of `PlayGainProgressAnim`/`Setup` ever being invoked. Chasing individual Blizzard methods one at a time is exactly the kind of guessing that already needed two rounds for the stage-lag bug (Decision 22) and the aura bug (Decision 24) — the durable fix is to stop guessing which method causes the show and instead observe the effect itself. **Fix:** `WidgetAdapter.lua` now hooks the icon frame's own `OnShow` script (`frameRef:HookScript("OnShow", ...)`, a standard taint-safe WoW pattern for exactly this — "notify me whenever this frame becomes shown, regardless of what code caused it") via a new `ensureOnShowHooked()`, called from `captureLiveFrames()` so every newly-discovered prey-hunt frame gets it automatically (guarded by a weak-keyed table so the same frame is never hooked twice). This fires the same `scheduleDeferredPreyContextRefresh()` deferred re-suppression Decision 22's `Setup` hook already uses. The now-redundant `PlayGainProgressAnim` hook from Decision 26 is removed — `OnShow` is a strict superset of what it caught (anything that plays the pulse animation also shows the frame), so keeping both would just be two overlapping mechanisms doing the same job, against CLAUDE.md's single-source-of-truth-per-concern rule. Not yet re-tested live.

32. **A second live zone mismatch, in the opposite direction from Decision 29, plus confirmation that Season 2 renamed the ambush mechanic and gave it a different mob name (2026-08-28).** Product owner reported both the bar not rendering AND the newly-built nameplate ambush detection (Decision 30) not firing, on a different hunt (Janoa the Fang, Voidstorm): `/pd inspect` showed `inPreyZone=false | expectedZoneMapID=2479` against `playerMapID=2405`, while `/pd qinspect` again confirmed the authoritative `isOnMap=true`. Decision 29's `DoesMapContain(expectedZone, playerMapID)` fix only covers "playerMapID nested under a broader expectedZone" (the Coiled Isle/Quel'Thalas case); this is the reverse — `expectedZoneMapID` here came from the Hunt Table pin's own position-based lookup and resolved to a specific named sub-area narrower than what `C_Map.GetBestMapForUnit` reports for the player standing in the same physical place. **Fix:** added `MapContextAdapter.AreMapsRelated(mapIDA, mapIDB)`, a symmetric wrapper checking `DoesMapContain` in both directions; `PreyContextRuntime`'s pre-filter now uses it instead of the one-directional check. This single root-cause fix unblocks both symptoms at once, since `HandleNameplateEvent` (Decision 30) also gates on `inPreyZone ~= false`. **Separately, real new information:** the product owner confirmed Season 2 replaced the old "Echo of Predation" ambush mechanic with one now called "Pack Ambush," and a real ambush's chat log showed the attacking add is named "Pack Hunter" — not the hunt's own prey. Nameplate-name matching against `preyTargetName` alone would never catch this mechanic's actual mob, so added `AMBUSH_TRIGGER_NAMES` (currently just `"pack hunter"`, lowercased, extensible for future season-specific ambush-add names) to `AlertsRuntime.HandleNameplateEvent` — matches either the prey's own name or a known ambush-add name. Loosened the function's early-return guard to no longer require `preyTargetName` to be set at all (only `activeQuestID` and zone), since the `AMBUSH_TRIGGER_NAMES` path doesn't need it. Not yet re-tested live.

33. **Corrected Season 2 mechanic lineage: "Pack Ambush" replaces Bloody Command, not Echo of Predation (2026-08-28).** Decision 32 recorded a guess (from context alone) that Season 2's "Pack Ambush"/"Pack Hunter" mechanic was the replacement for Echo of Predation. The product owner corrected this directly, taking responsibility for the earlier ambiguity: Pack Ambush is Season 2's replacement for **Bloody Command** (the Astalor Bloodsworn mechanic `isBloodyCommandMessage`/`PlayBloodyCommandSound` already model, currently dormant). Separately, **Echo of Predation's current-content form involves "Venom-Bloated Python" mobs as part of an "Exploding Corpse Snakes" mechanic** — genuinely new information, since `PlayEchoOfPredationSound` never had a working trigger in either codebase (no mob/event name was ever known to key off). Updated `AlertsRuntime.lua`'s header and `AMBUSH_TRIGGER_NAMES` comments to reflect the corrected lineage. **Deliberately not changed:** `AlertsRuntime.HandleNameplateEvent` still routes a "Pack Hunter" nameplate match to `SoundsRuntime.PlayAmbushSound()`, not `PlayBloodyCommandSound()` — whether Pack Ambush should play through the Bloody Command sound slot (its functional successor, with its own nightmare/stage-1-3 gating and dormant-by-default setting) instead of the generic ambush sound is a real open question, but the product owner explicitly wants to confirm what's actually triggering the sound through further live testing first (a real ambush produced 3 `/pd sinspect` attempts within ~41 seconds — 2 played, 1 correctly blocked by the 35s cooldown — and the product owner wants to verify these were all genuine triggers, not a false-positive burst, before any further design decision here). Echo of Predation/Venom-Bloated Python is not wired to anything yet — recorded as a real, newly-unblocked Full-scope opportunity, not built now.

34. **Built the Mob Scanner: renamed Bloody Command/Echo of Predation to their live Season 2 successors and gave each its own nameplate-detected sound (2026-08-28).** The product owner confirmed the earlier "Pack Hunter" ambush sound (Decision 30/32) was working, but flagged it as semantically wrong: Pack Hunter isn't the hunt's own prey, and reusing the hard-won generic ambush sound for it was confusing ("Not sure why we would set a sound we have had a VERY hard time to track as the sound for multiple mobs"). Combined with Decision 33's corrected lineage (Pack Ambush = Bloody Command's successor, Exploding Corpse Snakes = Echo of Predation's), the direction was clear: **replace** the Season 1 mechanic names/settings with their Season 2 names throughout, give each its own dedicated, player-configurable sound, and detect both via the nameplate mechanism already proven for ambush — not chat, since "they do not always say something." Mapping (product owner's own words): "Exploding Corpse Snakes = Venom-Bloated Python" and "Pack Ambush = Pack Scout and/or Pack Hunters."
    - **`AlertsRuntime.lua` rewritten as a pure nameplate-based Mob Scanner.** `HandleNameplateEvent` now runs two independent checks per nameplate: (1) the existing true-ambush check (nameplate name == `preyTargetName`, gated on `inPreyZone ~= false`, unchanged), and (2) a new `MOB_SCANNER_TRIGGERS` lookup (`"pack scout"`/`"pack hunter"` → `pack_ambush`, `"venom-bloated python"` → `exploding_corpse_snakes`) gated by a rule the product owner specified directly: **`QuestApiAdapter.GetQuestIsOnMap(activeQuestID)` queried directly** (not `state.inPreyZone` — that pre-filter's map-hierarchy heuristic has already needed two live fixes this session, Decisions 29/32; the Mob Scanner sidesteps it by asking Blizzard's authoritative signal directly, exactly as CLAUDE.md's own "isOnMap remains sole authority" rule already prefers), and **no stage restriction** — "unlike the ambushes they can trigger until we are all the way done" (already naturally satisfied since the check requires `activeQuestID`, which clears once the hunt ends). Deliberately **not difficulty-gated** either, unlike old Bloody Command's nightmare-only restriction — not confirmed to still apply, and under-triggering is worse than over-triggering for an awareness-only alert; noted as a real assumption to revisit if false positives on non-Nightmare hunts turn up.
    - **The old chat-text detection path is fully removed, not left dormant.** `isBloodyCommandMessage`, `BLOODY_COMMAND_CHAT_PHRASE*`, `CHAT_TRIGGER_EVENTS`, and `HandleChatEvent` are gone from `AlertsRuntime.lua`; `EventRuntime.lua`'s entire `CHAT_EVENTS` category (registration, `HANDLED_EVENTS` inclusion, dispatch block) is gone too, since nothing consumed it anymore once Bloody Command's replacement turned out to need nameplate detection like everything else. This is a genuine deletion, not a dormant-but-kept pattern like Decision 5's original Bloody-Command-is-dead-content call — that call is superseded now that Season 2 gave both mechanics real successors.
    - **Settings renamed, not added alongside.** `sound.bloody_command_enabled`/`_path` → `sound.pack_ambush_enabled`/`_path` (default flipped `false` → `true` — this is a live mechanic now, not dormant Season 1 content); `sound.echo_of_predation_path` → `sound.exploding_corpse_snakes_path`, plus a **new** `sound.exploding_corpse_snakes_enabled` (Echo of Predation never had an enabled toggle before — added for parity with Pack Ambush's, default `true`). `text.bloody_command_prefix`/`_suffix_template` → `text.pack_ambush_prefix`/`_suffix_template` (still unwired to `BarRuntime`, same as before the rename — a pre-existing gap, not introduced here). `debug.bloody_command_verbose` → `debug.pack_ambush_verbose` (also still unwired/no-op). `SoundsRuntime.PlayBloodyCommandSound`/`PlayEchoOfPredationSound` renamed to `PlayPackAmbushSound`/`PlayExplodingCorpseSnakesSound`, reading the renamed settings; `PlayExplodingCorpseSnakesSound` gained the enabled-check `PlayBloodyCommandSound` always had (Echo of Predation's version never checked one). `UI/SettingsPanel.lua`'s Sound & Alerts / Text & Labels / Advanced categories updated to match (labels, keys, and — since this is now live content — the checkbox description no longer says "Season 1 mechanic, currently dead content").
    - **Old-schema migration preserved, not dropped.** `SettingsRuntime.lua`'s `SIMPLE_KEY_MIGRATIONS` (which brings a real, already-shipped `main`-branch user's flat SavedVariables into the new schema) still maps `bloodyCommandSoundEnabled`/`bloodyCommandSoundPath`/`bloodyCommandPrefix`/`bloodyCommandSuffix`/`debugBloodyCommand` from the old key names — but now targets the new `pack_ambush_*` paths instead of dropping into now-nonexistent `bloody_command_*` ones, so an upgrading user's real preference (e.g. having Bloody Command sound customized/enabled) carries forward through the rename rather than being silently lost. This is migration-compatibility for real shipped users, not a backwards-compat shim for the rewrite's own unshipped history (CLAUDE.md's "no compat hacks" guidance is about the latter).
    - Not built now, real open items: `text.pack_ambush_prefix`/`_suffix_template` bar-text wiring (pre-existing gap, listed in session_status.md's Full-scope follow-ups), and no equivalent text-prefix/suffix settings were added for Exploding Corpse Snakes (Echo of Predation never had any either — not invented here without being asked). Not yet re-tested live.

35. **A third zone-detection false negative, this time blocking the true ambush sound directly, not the bar (2026-08-28, Zul'Aman).** Product owner reported `isOnMap=True` and a confirmed real ambush (stage genuinely advanced 1→2), but no ambush sound. Root cause: `AlertsRuntime.HandleNameplateEvent`'s true-ambush check still gated on `state.inPreyZone` (the pre-filtered, heuristic value Decisions 29/32 already had to patch twice for the bar), not on `QuestApiAdapter.GetQuestIsOnMap()` directly the way the Mob Scanner (Decision 34) already does. This is a third real bug from the same root design — the map-ID pre-filter comparing `expectedZoneMapID` against `playerMapID`, patched reactively per zone pairing so far (continent-parent, sub-area-child, and now apparently a third shape in Zul'Aman that neither `DoesMapContain` direction covers) rather than fixed as a class. **Fix:** the true-ambush check now also queries `GetQuestIsOnMap()` directly, matching the Mob Scanner's already-proven-reliable approach, and no longer depends on `state.inPreyZone` at all. Kept the original permissive rule (`isOnMap ~= false`, not `== true`) since a nameplate physically appearing is itself strong proximity evidence and this trigger was never meant to require positive confirmation. **Deliberately not yet changed:** `PreyContextRuntime`'s own `inPreyZone` (which drives the bar's `Only show in prey zone` visibility) still uses the map-ID pre-filter, unlike the two sound triggers now. This is an open question, not an oversight — the pre-filter exists specifically because the *old*, pre-rewrite codebase had a documented opposite-direction bug (`CHANGELOG.md`, pre-rewrite history): Blizzard's `isOnMap` returning `true` from broad quest-log membership alone, with no reliable zone match, showing a **Zul'Aman** hunt's bar while the player was actually in Eversong Woods — the same zone now involved in this fix, on the other side of the false-positive/false-negative tradeoff. Whether to also switch the bar to isOnMap-direct (accepting that old false-positive risk in exchange for eliminating this now-3-times-recurring false-negative class) is being put to the product owner rather than decided unilaterally.

36. **Removed the map-ID pre-filter entirely; the bar now trusts isOnMap directly too (2026-08-28).** After Decision 35 fixed the ambush sound the same way, the product owner asked whether extending this to the bar's own `inPreyZone` would be resource-intensive. It is not: `QuestApiAdapter.GetQuestIsOnMap()` is two lightweight, pcall-guarded quest-log lookups (`GetLogIndexForQuestID` + `GetInfo`, no map/pathing computation), cheaper than the pre-filter's own up-to-10-hop `parentMapID` walk it replaces — confirmed before making the change, not assumed. With that resolved, `PreyContextRuntime.RefreshPreyContext()`'s zone-gating step now calls `GetQuestIsOnMap()` unconditionally and no longer reads `expectedZoneMapID`/`playerMapID` to gate `inPreyZone` at all — three live false negatives from that heuristic (Decisions 29, 32, 35), each a different zone-hierarchy shape, against zero false answers from `isOnMap` itself in any of them, made continuing to patch new shapes reactively the wrong path forward. `expectedZoneMapID` is still captured and stored on `state` (Hunt Table zone display and diagnostics still use it) — only its use as an `inPreyZone` gate is gone. `MapContextAdapter.DoesMapContain`/`AreMapsRelated` (Decisions 29/32) are now dead code with this removed and were deleted outright rather than left unused. **Accepted, explicit tradeoff:** the pre-rewrite codebase had a documented opposite-direction bug — `isOnMap` true from broad quest-log membership alone with no real zone match, showing a Zul'Aman hunt's bar while standing in Eversong Woods. `isOnMap` has been correct in every live test this session (Coiled Isle, Voidstorm, and Zul'Aman itself, the same zone from that old bug), so the product owner accepted this risk in exchange for eliminating a now-3-times-recurring, actively-hunt-blocking bug class. If that old failure mode resurfaces, the fix is scoped to this one function (`PreyContextRuntime.RefreshPreyContext`), not a wide blast radius. Not yet re-tested live.

37. **Fixed the default prey icon reappearing with stale progress on hunt turn-in (2026-08-28).** Product owner reported that after everything else checked out end-to-end, turning in a Prey Hunt made Blizzard's default icon become visible again, showing whatever progress it was at right before completion — even with `general.disable_default_prey_icon` on. Confirmed via the product owner's own domain knowledge: Blizzard's default icon is never shown at all without an active, in-zone hunt, so there is nothing for the addon to legitimately "restore" once a hunt ends. Root cause: `PreyContextRuntime.RefreshPreyContext()`'s two early-return branches (no active quest, restricted instance) both called `applyIconSuppression(widgetAdapter, settings, false)` — explicit un-suppression, which `WidgetAdapter.applyFrameSuppression(frame, false)` implements as `frame:SetAlpha(1)` + a conditional `frame:Show()` (fires whenever the frame was shown at the moment suppression was originally captured, which it always was mid-hunt) — i.e. the addon was itself forcing Blizzard's icon frame to reappear at exactly the moment tracking stopped. **Fix:** removed both un-suppress call sites entirely; `applyIconSuppression` (now `(widgetAdapter, settings)`, no `hasActiveQuest` parameter — it's only ever called from the one place that has a confirmed active hunt) is called exclusively at the end of a successful refresh. The only case where un-suppression should legitimately happen — the user toggles the setting off while a hunt is still active — remains correctly covered, since this same call re-evaluates the setting fresh on every refresh tick during an active hunt. `WidgetAdapter.lua` itself needed no changes; the bug was entirely in when its caller invoked it. **Confirmed live 2026-08-28: not seen again across 6 Prey Hunts since the fix.**

38. **Built `UI/Launcher.lua` for MVP; descoped `UI/EditMode.lua` and `UI/ReportWindow.lua` after finding their core functionality already exists or is superseded (2026-08-28).** Continuing toward MVP after the icon-suppression fix (Decision 37), audited the two remaining unbuilt MVP-table rows before porting either wholesale from the old codebase:
    - **`UI/EditMode.lua`'s actual function, per the old code, is two things: (1) auto-unlock the bar and allow dragging while Blizzard's Edit Mode is open, restoring the prior lock state on exit, and (2) a small floating quick-settings window (Lock Bar, Only show in prey zone, Disable Default Prey Icon, Show bar during Edit Mode, Reset Bar Position, Scale, Width, Height) anchored near the Edit Mode manager frame.** (1) turned out to already be built — `UI/BarFrame.lua`'s `frame:EnableMouse((not lockBar) or editModeActive)` (from this session's earlier bar-rendering work) already makes the bar draggable during Edit Mode regardless of the lock setting, with no separate unlock/relock step needed. (2) is a straight subset duplicate of `UI/SettingsPanel.lua`, which already exposes every one of those same fields in its General/Bar Display categories, reachable via Escape → Options or `/preydator` — Blizzard's modern Edit Mode doesn't block opening Options alongside it. Given the functional need is already met and the remaining piece is pure UI convenience duplicating an existing surface, `UI/EditMode.lua` is not built; the Section 15 table now reflects this as an explicit MVP descope rather than an oversight, moved to Full-scope if still wanted later.
    - **`UI/ReportWindow.lua`** was meant to be a generic scrollable viewer for `DiagnosticsRuntime`'s reports. That need has been fully covered all session by `Core/SlashCommands.lua`'s `/pd` commands printing directly to chat (with optional BugSack routing for easy copy-paste) — used successfully throughout every diagnostic investigation this session. Building a second, redundant report-viewing UI surface isn't needed; not built.
    - **`UI/Launcher.lua` was built**, since nothing already covers a minimap/Addon Compartment entry point. Ported the structure from the old codebase's inline `Preydator.lua` launcher block (LibDataBroker-1.1 + LibDBIcon-1.0 optional integration, both already declared as `OptionalDeps` in `Preydator.toc` and not bundled — many players already have them loaded via another addon — with a custom-drawn fallback minimap button when neither is present), rewired entirely to the new architecture: left-click calls the new `UI/SettingsPanel.OpenSettings()` (added as a public function so `/preydator` and the launcher share one code path, not two copies of the `Settings.OpenToCategory` call); right-click prints `DiagnosticsRuntime.BuildGeneralInspectReport()` directly to chat (replacing the old right-click's now-nonexistent ReportWindow) — a deliberate design choice, not a guess ported from old behavior, since there's no report window to open anymore. Two new settings added: `general.minimap_hidden` (boolean, default `false`) and `general.minimap_angle` (number 0-360, default `225`) — old flat `currencyMinimapButton`/`currencyMinimapAngle` keys (historically CurrencyTracker-adjacent naming, but the launcher itself was always "decoupled from CurrencyTracker" per the old code's own comment) are migrated into these on `SettingsRuntime.MigrateAll`, preserving a real upgrading user's button position/hidden preference. When LibDBIcon is present, a small position-shim table (not the settings profile itself) is handed to it, since it mutates whatever table it's given directly — `Settings.Get`/`Set` stays the only sanctioned write path into the real profile, with the shim synced back on every `Settings.Subscribe` firing. Not yet tested live.

39. **`UI/Launcher.lua` confirmed working in-game; `UI/EditMode.lua` permanently confirmed unneeded (2026-08-28).** Product owner tested the minimap button live: left-click opens Settings, right-click prints the quick inspect report, both working as built. Separately, confirmed Decision 38's EditMode.lua reasoning directly rather than just accepting my inference — the desired behavior really is exactly "drag the bar during Edit Mode, then return to whatever the Settings panel's lock checkbox says," nothing more; no floating quick-settings window wanted at all, even as a later Full-scope nice-to-have. `UI/BarFrame.lua` already does this in full (`EnableMouse((not lockBar) or editModeActive)`, no explicit unlock/relock step needed since it never actually mutates `general.lock_bar` — the checkbox's own saved value is just temporarily overridden for mouse-enable purposes during Edit Mode, then naturally takes over again once Edit Mode closes). No code change from this decision; it closes out both Section 15 rows for good.

40. **Closed a diagnostic blind spot in the nameplate handler after a real ambush produced zero `/pd sinspect` entries (2026-08-28).** Product owner reported a missed ambush on the actual prey objective, then found the same mob again moments later and it worked — `/pd sinspect` confirmed literally zero entries for the missed attempt, meaning `SoundsRuntime.PlayAmbushSound()` was never even called. Root cause of the *blind spot* (not yet the missed trigger itself, which still needs a live catch): `AlertsRuntime.HandleNameplateEvent`'s own early gates (`IsPollingActive`, `IsRestrictedInstance`, `activeQuestID` presence, `general.sounds_enabled`) all ran *before* the prey-name match check, and none of them recorded anything if they blocked — the exact same "blocked before ever reaching playPath is invisible" blind spot Decision 19's `sinspect` work already fixed once for `SoundsRuntime`'s own internal gates, just one layer further out. **Fix:** reordered the function so the cheap unit-name lookup and prey-name/Mob-Scanner match check happen first (nameplates for unrelated mobs still bail immediately with no logging — this doesn't spam the diagnostic history); once a nameplate is confirmed to match something tracked, every remaining gate that can block it now calls a new public `SoundsRuntime.RecordBlockedAttempt(key, detail)` (thin wrapper around the existing private `recordPlay`) before returning, including the `isOnMap` check for both the ambush and Mob Scanner branches. The product owner's own theory (something from "old chat wiring" reacting differently when the mob spoke in chat vs not) was checked and ruled out directly — grepped the entire active file set for `CHAT_MSG`/chat event registration and confirmed zero live chat listeners remain anywhere (only historical comments) — so whatever the real cause is, it isn't chat-related code. The correlation with chat dialogue may still be a real clue (e.g. a scripted ambush vignette briefly perturbing quest-log state), but that's now something the new logging can confirm or rule out directly next time, rather than guessed at. Not yet re-tested live — the underlying missed-trigger cause is still unknown, only the diagnostic gap is fixed.

41. **Built an opt-in nameplate trace, wiring up the previously-unused `debug.pack_ambush_verbose` setting for real (2026-08-28).** Product owner asked for a way to record and share what's happening around a missed trigger, specifically so `/pd sinspect` (Decision 40's fix) isn't the only signal — `sinspect` only ever sees actual `PlayXSound` attempts, so it's structurally silent for a nameplate that never even reached a match (e.g. if `NAME_PLATE_UNIT_ADDED` simply never fired for the prey, a real possibility still not ruled out). `debug.pack_ambush_verbose` already existed as a Settings → Advanced checkbox (renamed from `debug.bloody_command_verbose`, Decision 34) but had never been wired to anything — the perfect existing hook for this. **Implementation:** `AlertsRuntime.lua` gained a 50-entry ring buffer (`nameplateTrace`, same pattern as `SoundsRuntime.recentPlays`) recording every nameplate seen while a hunt is active and the setting is on — name, timestamp, and whether it matched the prey, a Mob Scanner mob, or neither — regardless of whether any of the later gates would go on to block it. Exposed via `AlertsRuntime.GetNameplateTrace()`, a new `DiagnosticsRuntime.BuildNameplateTraceReport()`, and `/pd ninspect [bs]`. Deliberately gated on both "hunt active" and the opt-in setting (default off) — an always-on trace of every nameplate in the open world would be pure noise; this is a recording session the product owner turns on before going to find the mob in question, then dumps to BugSack via the existing `bs` convention. The canvas-based Advanced-category checkbox has no tooltip support (unlike the native-Settings-API checkboxes elsewhere in this file), so the checkbox label itself now names the command that reads the data (`/pd ninspect`) rather than relying on a tooltip nobody will see. Not yet tested live.

42. **Root-caused the missed-ambush mystery for real, using the nameplate trace built the same session (2026-08-28).** Product owner ran the new `/pd ninspect` trace across a couple of hunts and found the smoking gun directly: entry 45, `name=Unknown | no match`, immediately followed (confirmed by the product owner cross-referencing the timing) by the real prey's nameplate appearing again later with its actual name and matching correctly. This is a well-documented WoW timing quirk: `NAME_PLATE_UNIT_ADDED` can fire before the client has actually cached a unit's name, and `UnitName()` returns the literal placeholder string `"Unknown"` in that window — most common for a mob that just became visible/spawned, which describes an ambush exactly. The prey's nameplate genuinely fired; the one-shot name comparison against it just happened to run during the "Unknown" window and silently never got a second chance. Not chat, not old wiring, not a zone/isOnMap issue — a pure client-side name-caching race, invisible without the raw nameplate trace (Decision 41) that was built specifically because `/pd sinspect` alone couldn't see this class of miss.
    - **Fix:** `AlertsRuntime.lua` now tracks units seen as `"Unknown"` (keyed by unit token, with the `UnitGUID` captured at that moment) in a bounded, 30-second-expiring `pendingNameResolution` table, and listens for Blizzard's own `UNIT_NAME_UPDATE` event (new `UNIT_NAME_EVENTS` category in `EventRuntime.lua`, same dispatch pattern as `NAMEPLATE_EVENTS`) to recheck once the name actually resolves. The GUID check at resolution time matters: nameplate unit tokens are pooled and can be reassigned to a completely different mob between the "Unknown" sighting and `UNIT_NAME_UPDATE` firing, so the token alone isn't trustworthy across that gap — only a GUID match confirms it's still the same unit.
    - The shared matching/gating logic (name match, all the gates, `RecordBlockedAttempt` calls) was extracted from `HandleNameplateEvent` into a new local `processResolvedName(name)`, called from both the original nameplate-add path and the new `HandleUnitNameUpdate` path — no duplicated logic between "got a real name immediately" and "got a real name after an Unknown placeholder resolved."
    - `UNIT_NAME_UPDATE` fires for any tracked unit, not just nameplates — kept cheap for the common case by having `HandleUnitNameUpdate` bail immediately (a single table lookup) unless the unit was specifically flagged pending, so this doesn't add meaningful dispatch overhead.
    - This also retroactively explains why finding the mob a second time always "just worked" throughout this session's whole debugging saga — the SECOND `NAME_PLATE_UNIT_ADDED` (or manually re-approaching) reliably happened after the name had already resolved client-side, so the one-shot check by chance succeeded the second time, disguising the timing race as something else entirely across every previous live test. **Confirmed live 2026-08-28: product owner ran two full Prey Hunts with no errors, all sounds (ambush, Pack Ambush, Exploding Corpse Snakes) working, nameplate scanning issue-free.**

43. **Four Full-scope items logged after MVP declared feature-complete, not built this session (2026-08-28, product owner's explicit choice — "log all 4 as Full-scope, build later" over building any now).** All four added to Section 15's MVP/Full table:
    - **Sound amplification**, modeled on the "Better Fishing" addon's approach to making sounds louder than WoW's normal channel-volume ceiling allows. The exact mechanism "Better Fishing" uses isn't confirmed — needs research before design, not guessed at. The most likely candidate (multiple simultaneous `PlaySoundFile` calls of the same file, layered) is noted as a starting hypothesis only.
    - **Slider value display.** Product owner screenshotted `UI/SettingsPanel.lua`'s Text & Labels category and pointed out the Font Size slider shows only its `8`/`24` endpoint labels, not the currently-selected value — true of every slider in the panel (Scale, Width, Height, Alert Cooldown, etc.), not specific to this one. Whether this needs real work or is a one-line `Settings.CreateSliderOptions` config gap is unconfirmed — check before building.
    - **Custom sound files.** `sound.custom_file_names` and the dropdown-population logic already exist (`registerSoundPathDropdown` in `UI/SettingsPanel.lua` reads it to build each sound-path dropdown's option list) — but there is no UI anywhere to actually add a new filename to that list. The old codebase had a real "Add File"/"Remove File" flow the product owner pointed at directly as the reference to port from, rather than designing one from scratch.
    - **Text & Labels two-column layout.** Current state: one long single-column stack of `createEditBoxRow`s in `buildTextLabelsCategory` (`UI/SettingsPanel.lua`) — every Stage N Prefix, Stage N Label, Out of Zone/Ambush/Pack Ambush Prefix and Label each gets its own full-width row, causing a long vertical scroll (product owner's screenshot showed the Text & Labels category scrolled off-screen). Product owner's own mockup (a second screenshot, same settings open) shows the fix directly: pair each Prefix field with its corresponding Label field on the *same row* — Prefix in a left column, Label in a right column (e.g. "Stage 3 Prefix" | "Stage 3 Label" side by side) — instead of two separate stacked full-width rows. The dropdowns/font pickers/Font Size slider above the field list are unaffected, staying full-width as they are now. This is the most concretely-specified of the four (a ready visual reference, not just a description) — the most likely first pick whenever this batch gets picked up.

44. **Built HuntScanner achievement signals (2026-09-01) — the Section 15 full-scope row that was previously blocked on the product owner not being able to test achievement progress; a live hunt with a completable achievement unblocked it.** New `Core/Adapters/AchievementAdapter.lua` is the sole Blizzard API boundary for `GetAchievementInfo`/`GetAchievementCriteriaInfoByID` (per Section 3's adapter-boundary rule — no other file calls these directly), with three pcall-guarded functions: `IsAchievementComplete`, `GetAchievementName`, `GetCriteriaLabelIfIncomplete`. `HuntScannerRuntime.lua` resolves each hunt's still-needed achievements from `PreyQuestData`'s already-carried-forward tables (`PREY_HUNT_MODE_ACHIEVEMENT_IDS_BY_DIFFICULTY`, `PREY_HUNT_ACHIEVEMENTS_BY_QUEST`) and attaches an `achievementNeeds` list to each hunt record, session-memoized per questID (same pattern as the expected-zone/reward caches — never a persistent store) and wiped wholesale on a new `ACHIEVEMENT_EARNED` dispatch category in `EventRuntime.lua` (earning any achievement can change multiple hunts' "still needed" answer at once, so a full wipe is simpler and cheap rather than trying to target just the relevant IDs). **Gating is on whole-achievement completion only, not per-criteria** — ported faithfully from the old codebase's own live-validated `TryAddMappedQuestAchievement` behavior rather than redesigned: these are account-wide meta achievements, so a hunt at a given difficulty is still a legitimate step toward the achievement even if this specific target's own criterion already happens to be done. Per-criteria completion (`GetCriteriaLabelIfIncomplete`) is used only to prefer a more specific tooltip label, never to decide inclusion. `HuntTablePanel.lua` renders the result as a badge (`Interface\AchievementFrame\UI-Achievement-TinyShield` + a count) docked directly above the Accept button — the product owner pointed out that space sits empty — with a hover tooltip listing the still-needed achievement names, same interaction pattern as the reward icons. New `hunt.achievement_signals_enabled` checkbox added to `UI/SettingsPanel.lua`'s Hunt Scanner category (the underlying setting and its `SettingsRuntime` enum/migration entries already existed from earlier scaffolding, just unused until now). Only the `icon_count` style is implemented, matching the one value `SettingsRuntime` currently allows for `hunt.achievement_signal_style`. `luacheck`: 0 warnings/0 errors across all touched files. **Not yet tested live** — next step is confirming against the product owner's actual in-progress achievement hunt that the badge appears, the count is correct, and it disappears once the achievement is earned (`ACHIEVEMENT_EARNED` cache wipe).

45. **Fixed achievement badges showing on every hunt of a difficulty, including already-killed targets (2026-09-01, first live test of Decision 44).** Product owner reported every offered Prey Hunt showed the achievement badge as needed — confirmed the underlying achievement itself is correctly detected as available/incomplete (the good half of the first test), but per-hunt filtering wasn't narrowing it further. Root cause: Decision 44's gating was whole-achievement completion only, ported from the old codebase's own `TryAddMappedQuestAchievement` — but the Mode I/II/III meta achievements each cover roughly 30 targets, so the achievement stays incomplete (and every hunt of that difficulty keeps showing the badge) until literally all of them are done, even for a target whose own kill was already credited. **Fix:** `HuntScannerRuntime.computeAchievementNeeds`'s `addNeedIfIncomplete` now also checks `AchievementAdapter.IsCriteriaComplete(achievementID, criteriaIDHint)` (a new adapter function, per-criteria via the same `...ByID` lookup `GetCriteriaLabelIfIncomplete` already used for tooltip text) and excludes the hunt if its own specific criterion is already done — a hunt only counts as still needed when BOTH the achievement overall isn't complete AND (it has no criterion to check, or that criterion specifically isn't done). Also this session: bumped `HuntTablePanel.lua`'s `ACHIEVEMENT_ICON_SIZE` from 16 to 32 per the product owner's request (icon only, not the count text) — the icon texture isn't clipped by its anchor frame's bounds, so it simply extends into the existing free space above the Accept button rather than needing a layout change. `DiagnosticsRuntime.BuildHuntInspectReport` (`/pd hinspect`) now lists each hunt's `achievementNeeds` count plus one line per still-needed achievement (ID + name), and a settings line for `hunt.achievement_signals_enabled`/`hunt.achievement_signal_style`, so a future mismatch between what the badge shows and what's actually needed can be diagnosed without re-deriving this from scratch. `luacheck`: 0 warnings/0 errors on all 4 touched files. **Not yet re-tested live** — next step is confirming the badge now only appears on hunts whose specific target is still outstanding.

46. **Fixed a second, narrower achievement-badge false positive found via `/pd hinspect`'s new output (2026-09-01, same day as items 44/45).** Product owner pasted a full `hinspect` dump: every Normal/Hard hunt correctly showed `achievementNeeds=0` except the one genuinely outstanding target (`Crusader Luxia Maxwell`, Normal), confirming Decision 45's per-criteria fix works correctly for the ~90 hunts PreyQuestData already maps. But 4 Nightmare hunts (questIDs 95021-95024) each showed `achievementNeeds=1 | Prey: Nightmare Mode III` despite the product owner confirming those specific targets are already killed and not on their real needed-kills list. Root cause: these 4 questIDs aren't in `PreyQuestData.PreyQuestData` at all (new content added after that table was last updated, per Decision 3's "can be revisited later" caveat) — `HuntScannerRuntime.resolveDifficulty`'s text-fallback still correctly identifies them as Nightmare, but with no table entry there's no `criteriaID`, so Decision 45's per-criteria check had nothing to check against, silently falling back to whole-achievement-only gating for just these 4 hunts — and Nightmare Mode III (covering ~30 targets) isn't fully done account-wide, so they always showed as needed regardless of this specific target's real status. **Fix:** `computeAchievementNeeds`'s Mode I/II/III bucket now requires a known `criteriaID` before running at all (`local modeIDs = criteriaID and ...`) — with no way to verify a specific hunt's own completion, it's now treated as unknown rather than guessed as needed, per CLAUDE.md Section 4's "never guess true/false" principle applied to this new concern. The explicit per-quest bucket (`PREY_HUNT_ACHIEVEMENTS_BY_QUEST`) is unaffected — it's a direct questID lookup that already correctly returns nothing for unmapped quests. **Follow-up, not done now:** `PreyQuestData.lua` is presumably missing table entries for these 4 (and possibly other) new-content quest IDs; adding them would let the badge cover these hunts precisely instead of silently skipping them, but that's a data-completeness task for whenever the product owner wants to source the real criteriaIDs, not a code change. Also this session: tightened the icon-to-count gap in `HuntTablePanel.lua` (`-2` → `-1` offset) per the product owner's request. `luacheck`: 0 warnings/0 errors on both touched files. **Not yet re-tested live.**

47. **Confirmed live: achievement badges now correctly track per-target completion (2026-09-01), and simplified to icon-only per the product owner's follow-up request.** The product owner confirmed the badge behaves correctly on the real Hunt Table after Decisions Log items 45/46. Follow-up: drop the in-row count text entirely, keep only the icon, and move the count + achievement names to the existing hover tooltip. `HuntTablePanel.lua`'s `row.achievementText` FontString is removed; `row.achievementIcon` now anchors directly to `row.achievementAnchor`'s `RIGHT` point instead of relative to the (now-gone) text. The tooltip's title line now reads "Achievements Needed (N)" so the count that used to be visible in the row is still visible on hover. `luacheck`: 0 warnings/0 errors.

48. **Built HuntScanner grouping/sorting with full collapsible headers, matching the old addon (2026-09-01).** The product owner picked the highest-effort of three offered scope options (sort+cluster only, headers with no collapse, or full collapsible headers) explicitly to match the old codebase's exact feature. Ported the old `Modules/HuntScanner.lua` algorithm (`SortRows`/the grouping block around its line 3740) faithfully into `HuntScannerRuntime.GetGroupedDisplayList()`, its sole owner per the architecture doc's file-responsibility table: sorts the flat hunt list by `hunt.sort_by`/`hunt.sort_direction` (zone/title/difficulty, each with the same cross-field tiebreaker the old code used), then — when `hunt.group_by` is `difficulty` or `zone` — clusters hunts under a header pseudo-entry (`isGroupHeader = true`) per group. **Preserved verbatim, not redesigned:** group *order* (not the hunts within a group) always lists Nightmare before Hard before Normal for difficulty grouping and alphabetical for zone grouping, regardless of `hunt.sort_direction` — the old code's bucket-order comparator never read that setting, and this rewrite keeps that exact behavior rather than "fixing" it into something the old addon's users never had. A collapsed group's real hunts are omitted from the returned list entirely (not just hidden), same as old. New `HuntScannerRuntime.ToggleGroupCollapsed(groupKey)` persists via `Settings.Set("hunt.collapsed_groups", ...)` (new setting, default `{}`, migrated from the old `huntScannerCollapsedGroups` key) rather than mutating state directly, keeping Settings as the only thing UI code writes through. `HuntTablePanel.lua` renders header entries via a new `applyGroupHeaderRow` (row: `"- Difficulty: Nightmare"`/`"+ Zone: The Coiled Isle"` style label, click toggles collapse) using a shorter `GROUP_HEADER_HEIGHT` (24px) than a real hunt row (56px) — since row height is no longer uniform, `Render()`'s per-row layout changed from a fixed `index * ROW_HEIGHT` offset to an accumulated running `yOffset`, and `MAX_ROWS` was bumped 20→24 for the extra header rows. The preview-hunt path (`hunt.preview_enabled`) deliberately stays flat/ungrouped — it exists for eyeballing size/scale/font, not group headers. `luacheck`: 0 warnings/0 errors across all 4 touched files. **Not yet tested live.**

49. **Added on-panel group/sort/direction controls, a zone display-name override, and article-insensitive zone sorting (2026-09-01, follow-up to item 48).** Product owner asked not to need Settings open just to change grouping/sorting. `HuntTablePanel.lua` gained three buttons in its header (`groupButton`/`sortButton`/`sortDirButton`, `ensurePanel()`) using the same cycle-through-on-click design as the old codebase's Group/Sort buttons (old code never had a direction button — this rewrite adds a third one for parity, since direction was the one piece still requiring Settings otherwise). All three read/write the exact same `hunt.group_by`/`sort_by`/`sort_direction` keys `HuntScannerRuntime` already uses, so they and the Settings UI panel stay in sync automatically via the existing `Settings.Subscribe` → re-render path — no new state, no new sync logic. New `updateHeaderControls()` refreshes the button labels (e.g. "Group: Difficulty", "^"/"v" for direction) every render. Scroll frame top shifted 36→58px to make room. Separately, product owner asked for two zone-naming fixes: (1) mapID 2561 displays Blizzard's own name "Quel'Thalas" (the broad continent map several hunts fall back to, per Decisions Log item 18 — that decision explicitly declined to override the *gameplay* zone-matching for this, since `isOnMap` stays Blizzard's authority regardless), which means nothing to most players, so it should show as "The Coiled Isle" instead — a presentation-only override, not the banned persistent questID→zone mapping, since it doesn't touch any gameplay decision; (2) zone sort/group order should ignore a leading "The " (e.g. "The Coiled Isle" sorts under C, not T). Implementation: new `HuntScannerRuntime.ResolveZoneDisplayName(mapID)` is now the **single** place zone names are resolved (a `ZONE_DISPLAY_NAME_OVERRIDES` table, checked before falling through to `MapContextAdapter.GetMapInfo`) — `HuntTablePanel.resolveZoneName` and `DiagnosticsRuntime.BuildHuntInspectReport` (`/pd hinspect`) both now delegate to it instead of querying `MapContextAdapter` directly, so the panel, sorting, and diagnostics can never show three different names for the same mapID (the exact duplicate-logic pattern CLAUDE.md Section 3 bans). A new `sortKeyIgnoringArticle()` strips a leading "The " **only** for the string actually compared during sort/group-order — never from the displayed name or a zone group's own header label/collapse key, which keep "The Coiled Isle" verbatim. `luacheck`: 0 warnings/0 errors across all 3 touched files. **Not yet tested live.**

50. **Added a name-matching fallback for achievement criteriaID resolution, closing the questID-not-in-PreyQuestData gap from Decisions Log item 46 (2026-09-02).** Product owner asked why new hunts need a manual `PreyQuestData` entry at all when the Hunt Table is already scanned live — answer: scanning gives real-time `questID`/`title`/coordinates, but the achievement **criteria ID** (the internal Blizzard achievement-system number a specific kill satisfies) isn't exposed by any quest-facing API; it has to be sourced externally and hardcoded once, which is exactly what `PreyQuestData`'s table does and why new content isn't in it until someone repeats that. Rather than leave that permanent, added a fallback: new `AchievementAdapter.GetAllCriteria(achievementID)` enumerates every criterion of an achievement (label + criteriaID, via `GetAchievementNumCriteria`/`GetAchievementCriteriaInfo`); `HuntScannerRuntime.resolveFallbackCriteriaID` matches the hunt's own quest title against those labels (normalized: lowercased, punctuation/whitespace stripped, then exact-or-substring match) when `PreyQuestData` has no entry for that questID, session-memoized per achievementID+questID. `computeAchievementNeeds`'s Mode I/II/III loop now resolves the table value first, this fallback second, per achievement (not sharing one fallback result across Mode I/II/III, since their criteria are separately numbered) — still skips the achievement entirely for this hunt if both come up empty, preserving item 46's "unverifiable is not the same as needed" rule rather than reverting to it. **Locale safety, explicitly checked because the product owner asked:** both strings being compared — the quest title (from `HuntTableAdapter`/`QuestApiAdapter`) and the criterion label (from the new `GetAllCriteria`) — are Blizzard's own live text in whatever locale the client is actually running; this code never hardcodes an English word to search for, it only strips punctuation/case/whitespace noise before comparing, so the match works the same in any locale without addon-side translation. **A separate, pre-existing locale gap was surfaced by this same question, not fixed here:** `HuntScannerRuntime.resolveDifficulty`'s own text-fallback (used when a questID isn't in `PreyQuestData` at all, same population as this fallback serves) searches hunt titles/descriptions for the literal English words `"nightmare"`/`"hard"`/`"normal"` (`DIFFICULTY_TOKENS`) — on a non-English client this would silently misdetect a new hunt's difficulty as "normal" (the function's own final fallback) instead of matching. This predates this session's achievement work and wasn't touched — flagged for a future pass, and worth localizing (via `LocalizationAdapter.L()`-driven token variants per locale, likely) rather than fixing reactively later. `luacheck`: 0 warnings/0 errors across both touched files. **Not yet tested live** — no non-English-client hunt to test against currently, and the specific 4 Nightmare questIDs this was built for are English-client content the product owner already confirmed by number, so this needs either a future new-content hunt or a locale switch to actually exercise the fallback path.

51. **Fixed the locale gap in `resolveDifficulty`'s text-fallback surfaced by item 50 (2026-09-02).** The fallback (used when a questID isn't in `PreyQuestData`, e.g. new content) searched hunt titles/descriptions only for the literal English words "nightmare"/"hard"/"normal" — on a non-English client this would never match, silently misdetecting difficulty as "normal" (the function's own final default) for any new hunt. **Ported the old codebase's own already-validated fix rather than inventing a new one**: `Modules/HuntScanner.lua`'s `AddToken` calls registered both the English word and `L["Nightmare"]`/`L["Hard"]`/`L["Normal"]` as match candidates — confirmed `Locales/*.lua` already carries real translations for exactly these three keys in 8 of the 11 bundled locales (deDE/frFR/esES/esMX/ptBR/itIT/ruRU/zhTW; e.g. `frFR.lua`: `L["Hard"] = "Difficile"`). `resolveDifficulty` now also checks each candidate string against `LocalizationAdapter.L("Nightmare"/"Hard"/"Normal")` — both an exact-case match (safe for scripts `string.lower()` can't case-fold, like Cyrillic/CJK) and an ASCII-lowercase match (extra robustness for Latin-script locales) — alongside the existing English-literal check. `LocalizationAdapter.L()` falls back to returning the key itself when a locale has no translation, so this is safe to call unconditionally. **Known, explicitly-not-fixed gap:** `koKR.lua`/`zhCN.lua` only have compound keys today (`"Normal Difficulty"`, not a plain `"Normal"`), so this fix doesn't fully cover those two locales — not something to guess a translation for per CLAUDE.md Section 7.1 (`L()`'s key-fallback means it degrades to the same English-literal behavior for those two, not a regression, just not a full fix). Needs a native speaker to add the plain three-word keys if this ever needs to work fully for Korean/Chinese clients. `luacheck`: 0 warnings/0 errors. **Not yet tested live** — no non-English-client session available to verify against; the fix is a faithful port of the old codebase's own field-tested approach, not a new, unverified design.

52. **Closed the last two open Hunt Panel cosmetic items: stable reward ordering and real `hunt.reward_display_style` differentiation (2026-09-02).** Product owner asked what was left before signing off the Hunt Panel; these two were the only remaining non-blocking items (achievement-earned live-testing stays open separately, pending a character reaching that stage). **Reward ordering:** `HuntScannerRuntime.RefreshFromAdapter` now sorts `rewardEntries` (by name, then quantity as a tiebreaker) right after either reward source (`HuntTableAdapter.GetRewardWidgets` or `QuestApiAdapter.GetQuestRewardSummary`) resolves — a hunt's reward row now always renders in the same order, regardless of which order Blizzard's own widget pool/tooltip happened to enumerate them in that pass. **`hunt.reward_display_style`:** since this setting was new to the rewrite (no old-codebase feature to port faithfully) and its exact visual meaning was never pinned down beyond "more compact than icon_inline," asked the product owner directly rather than guessing — confirmed: `icon_count` drops the per-icon quantity number (icons only, quantity still on hover), `text_only` replaces the icon row entirely with one comma-separated `"10x Reward A, 1000x Reward B, Bonus item reward"` line (new `HuntTablePanel.buildRewardText`). `applyRewardIcons` gained a `showQuantity` parameter (true for `icon_inline`, false for `icon_count`); a new `row.rewardText` FontString (hidden by default) occupies the same bottom-left space as the icon row for `text_only`. Both `applyRow` and `applyGroupHeaderRow` reset/dispatch this correctly since rows are recycled across renders. `luacheck`: 0 warnings/0 errors on both touched files. **Not yet tested live.**

53. **Removed the `text_only` reward display style after live testing (2026-09-02, same day it shipped in item 52).** Product owner tested all three styles: `icon_inline` and `icon_count` both work as designed (icon+quantity, and icons-only-with-hover respectively), but `text_only`'s plain comma-separated line "is not really viable" for this row. Removed rather than left dormant — deleted `HuntTablePanel.buildRewardText` and the `row.rewardText` FontString entirely (both `createRow` and `applyGroupHeaderRow`'s reset no longer reference it), simplified `applyRow`'s reward dispatch back to a single `applyRewardIcons(row, hunt, rewardStyle ~= "icon_count")` call, dropped `"text_only"` from `UI/SettingsPanel.lua`'s dropdown options and `SettingsRuntime.lua`'s `ENUM_FIELDS` allowed-values list. Anyone who already had `text_only` saved self-heals to the default `icon_inline` automatically the next time settings load — `SettingsRuntime.NormalizeAll`'s existing enum-validation behavior (an invalid/no-longer-allowed enum value falls back to the field's default) already covers this, no migration code needed. `luacheck`: 0 warnings/0 errors. **Confirmed live** — this removal followed directly from the product owner's own live test of the shipped feature, not a code-review guess.

54. **Fixed the `icon_inline`/`icon_count` styles being swapped from what their names say, and made reward order difficulty-independent, not just scan-independent (2026-09-02).** Product owner tested item 52/53's shipped behavior and reported: "Icons Inline" showed icon+quantity (they expected icons only) and "Icon + Count" showed icons only (they expected icon+quantity) — i.e. exactly backwards from the literal reading of each name. **Fixed** by flipping `HuntTablePanel.applyRow`'s dispatch: `applyRewardIcons(row, hunt, rewardStyle == "icon_count")` (was `~= "icon_count"`) — `icon_inline` is now icons-only (hover for quantity), `icon_count` is icon-plus-quantity-inline (still repeated on hover, unchanged tooltip behavior either way, since `tooltipQuantity` was already set unconditionally). Separately, the product owner also wants a reward's category to land in the same row position **regardless of difficulty** — item 52's name-based sort already made a single hunt's own row stable scan-to-scan, but different difficulties offer differently-*named* rewards (different currency/tier), so alphabetical order still shifted which slot a category landed in between difficulties. Sort key changed to category-first: new `REWARD_TYPE_SORT_PRIORITY = { currency = 1, item = 3 }` (anything else — money/XP, or the tooltip-fallback reward source, which carries no type field at all — buckets as `2`, "other," sitting between the two), read from Blizzard's own `.rewardType` field already present on `HuntTableAdapter.GetRewardWidgets`' output (Decisions Log item 19) but previously dropped when `HuntScannerRuntime` copied those widget rewards into `rewardEntries` — now preserved. Name/quantity remain as the tiebreaker only for two rewards sharing a category within the same hunt. **Judgment call, not confirmed with the product owner:** the exact bucket order (currency, then other/money-XP, then item) is a reasonable-seeming default, not something the settings catalog or old codebase specified — flag if the live result doesn't read well and the priority table is a one-line change. `luacheck`: 0 warnings/0 errors on both touched files. **Not yet tested live.**

55. **Replaced the generic type-based reward sort with the product owner's exact hand-specified order, after they asked whether chest-reward scanning had regressed (2026-09-02).** Product owner reported seeing every reward except the chest and asked directly whether `HuntTableAdapter.GetRewardWidgets`' item/container scanning (Decisions Log item 19) had been removed — confirmed it had not: the chest/bag is still fetched via the exact same `rewardType == "item"` widget path, unchanged by items 52/54. The real issue was item 54's own judgment-call bucket order (`currency`/`other`/`item`): it sorted all currencies together alphabetically, which happened to put a `"...Mistcrest"`-named currency *before* `"Preyseeker's Journey"` (M < P) — not what the product owner actually wanted once they specified it directly. **Replaced entirely** with a name-substring priority the product owner spelled out after looking at real reward names in-game: `"Coffer Key"` first, `"Preyseeker's Journey"` second, any `"Mistcrest"`-containing currency third (sorted alphabetically among themselves via the existing name tiebreaker), anything unmatched fourth, and anything containing `"Chest"` or `"Bag"` always last. New `HuntScannerRuntime.namedRewardPriority(name)` (case-insensitive substring match — these are proper nouns the product owner read directly off their own client, not something to localize) replaces the same-day `REWARD_TYPE_SORT_PRIORITY`/`rewardTypeSortPriority`; the now-unused `rewardType` field that item 54 had started copying onto `rewardEntries` was removed again since nothing reads it anymore. `luacheck`: 0 warnings/0 errors. **Not yet tested live** — including whether this actually resolves the chest's visibility, or whether a separate cause (e.g. `MAX_REWARD_ICONS`/row-width truncation) is also in play; flagged to the product owner to check via `/pd hinspect`'s per-hunt `rewards=N` count if the chest still doesn't show after this reorder.

56. **Root-caused the chest/bag reward missing entirely from every hunt, not just misordered (2026-09-02).** Product owner confirmed after item 55's reorder that the chest reward wasn't merely out of place — it never appeared in the panel at all for any hunt, despite being visible on the actual in-game quest. Working hypothesis, matching this project's recurring pattern of Blizzard UI widgets not being fully populated at the exact synchronous instant a caller reads them (`WidgetAdapter`'s mixin-hook retries, the Hunt Table staggered watch, etc.): `HuntTableAdapter.GetRewardWidgets`' single synchronous peek (`ShowWithQuest` → read `dialog.rewardPool` → `Hide`, no delay) can catch the reward pool before its item/container widget has finished populating, while the currency/money widgets are already there — and since `HuntScannerRuntime` cached that first peek's result **unconditionally** (`rewardWidgetsByDifficulty[difficulty]`, one peek per difficulty for the whole session), an incomplete first look permanently dropped the chest for every hunt of that difficulty afterward, with nothing to ever re-check it. **Fix:** the peek is now cross-checked against `QuestApiAdapter.GetQuestRewardSummary`'s independent `hasBonusItemReward` signal (`GetNumQuestLogRewards`, confirmed reliable pre-accept regardless of other quest data loading state, Decisions Log item 19) before being cached — if that signal says an item reward should exist but no `rewardType == "item"` entry was found in this peek, the result is used for just this one render pass (so currency/money still show immediately) but is **not** written into `rewardWidgetsByDifficulty`, leaving the difficulty free to be re-peeked on the next rescan instead of frozen incomplete. When incomplete, `hasBonusItemReward` falls through to `true` for that pass so the generic mystery-item placeholder shows in the meantime, rather than the chest slot going empty — self-corrects to the real icon once a later peek succeeds and caches. `luacheck`: 0 warnings/0 errors. **This is a hypothesis-driven fix, not a confirmed root cause** — no way to directly observe the dialog's reward-pool population timing without a live client. **Not yet tested live.** If the chest still doesn't appear after this, the next diagnostic step is a temporary raw dump of `dialog.rewardPool`'s widgets/fields for a hunt with a known-missing chest (same technique as the original widget-introspection work, Decisions Log item 19), not another guess.

57. **Found the real cause of the Nightmare-only missing chest: a 4-icon row cap, not the widget-timing race item 56 guessed at (2026-09-02).** Product owner reported the chest now shows for Normal and Hard but still not Nightmare, and that Nightmare hunts have 5 distinct rewards — pointing straight at `HuntTablePanel.lua`'s `MAX_REWARD_ICONS = 4`, which silently truncates anything past the 4th `displayEntries` slot. Since `namedRewardPriority` (item 55) always sorts the chest/bag reward last, a 5-reward difficulty always loses exactly that one to the cap — item 56's caching fix was solving a real but different problem (or masking this one for Normal/Hard, which apparently have ≤4 rewards) and wasn't the actual explanation for Nightmare specifically. **Fix:** bumped `MAX_REWARD_ICONS` 4→6 (one past the currently-known maximum of 5, for headroom). **Flagging, not yet fixing, a likely follow-on cosmetic issue:** at the default panel width (336px) and `icon_count`/`icon_inline` slot sizing, a fully-populated 5-icon row runs close to or past where the Accept button starts (previously discussed as a pre-existing risk at 4 icons; 5-6 makes it worse) — not confirmed live, but the pixel math makes it likely. Revisit panel-width/layout once the product owner confirms whether this is actually visible. `luacheck`: 0 warnings/0 errors. **Not yet tested live.**

58. **Achievement badge tooltip fixed to show the achievement's own name, not the kill-target's name (2026-09-03).** Product owner reported the badge tooltip was showing the person/mob name they needed to kill rather than the achievement it belonged to. Root cause: `HuntScannerRuntime.lua`'s `addNeedIfIncomplete` preferred `AchievementAdapter.GetCriteriaLabelIfIncomplete` (the criterion's own label, which for these kill-target achievements literally *is* the target's name) over `GetAchievementName`. This had been a deliberate design choice earlier in the rewrite ("matches the old codebase's tooltip behavior") but the product owner wants achievement names now. Fixed by always using `GetAchievementName`; the now-dead `GetCriteriaLabelIfIncomplete` adapter function was removed entirely rather than left unused. `luacheck`: 0 warnings/0 errors. **Confirmed live** as part of item 59's testing below.

59. **New override-achievement architecture for side-questline achievements outside the Mode I/II/III series, plus full live confirmation of the achievement system end-to-end (2026-09-02/03).** Live-testing item 58's fix surfaced 4 questIDs (95021-95024, a new side questline gated behind intro quest 96004) showing `achievementNeeds=0` — not a stale-data gap like the original 4 unmapped Nightmare questIDs (Decisions Log item 46), but a genuinely different problem: these targets don't appear in achievement 42703's criteria at all, because they belong to two entirely separate achievements (63451 "Scales for Days", 63452 "Fangs for the Memories") that `HuntScannerRuntime.lua` had no way to discover on its own — there's no Blizzard API mapping questID to achievementID, so an unknown achievement family can't be found by title-matching against achievements the addon doesn't already know to check. Resolved by cross-referencing the Plumber addon (installed alongside Preydator), which had already reverse-engineered this exact mapping in `Modules/HuntTable.lua` and `Modules/Shared/SharedData.lua` — confirmed a faster, more reliable source than Wowhead scraping for this class of gap (see memory `preydator-quest-achievement-mapping` for the reusable workflow). Added `PreyQuestData.PREY_HUNT_ACHIEVEMENT_OVERRIDES_BY_QUEST` (questID → achievementID) plus a new mutually-exclusive branch in `computeAchievementNeeds`: when a questID has an override, only that achievement is checked, never also the Mode series (reusing a criteriaID across unrelated achievements isn't safe, confirmed wrong here). The override branch also reuses the existing title-match fallback for its criteriaID, so future overrides only need the achievementID hand-sourced, not both numbers. `luacheck`: 0 warnings/0 errors across all touched files.

   **Confirmed live (2026-09-03), closing out every open item in the achievement row above:** product owner ran the full recommended test set — a standard Hard-tier per-boss hunt (existing code path, reconfirmed post-fix), `95022` (Fangs for the Memories, new override path), and `95023`/Batani the Scaled (Scales for Days, new override path). Two things confirmed simultaneously by completing only `95023`: (1) `95024`/Kadani the Claw's badge dropped to `achievementNeeds=0` on the very next `hinspect`, no `/reload` in between — closes the `ACHIEVEMENT_EARNED` cache-wipe path that Section 15 had marked tentative since 2026-09-01; (2) "Scales for Days" only requires killing one of its two paired targets, not both — a real, previously-unknown design detail about this specific achievement, not a bug. Also observed: Normal-tier hunts' `achievementNeeds` correctly dropped from 3 to 2 (Mode I achievement fell off) after the product owner completed an additional Normal hunt, confirming per-criteria gating continues to track correctly as real progress accrues. Full end-to-end hunt lifecycle (accept, bar stage tracking, ambush sound, turn-in) was also reconfirmed on this same newer-content hunt (`95023`), not just the original 30-target roster. **No known open items left in the achievement system.**

60. **Three more Hunt Panel/Settings Full-scope items closed in one session (2026-09-03): reward/Accept overlap fix, addon-wide slider value labels, preview grouping, and a Bar Colors reorganization.** Live-testing the achievement badge also surfaced the previously-flagged-but-unconfirmed reward-row/Accept-button overlap as real (both the achievement badge and Accept button, not just rewards) at narrow panel widths. Fixed with a width floor, not a row-layout redesign (matches the product owner's own proposed fix): `hunt.width`'s slider minimum raised from 200, plus a matching render-time `math.max` clamp in `HuntTablePanel.lua`'s `Render()` so anyone with an already-saved smaller value is protected too, not just future drags. Tuned twice live after the initial theoretical-worst-case value (420) turned out more conservative than needed: 270, then settled at 330 (default kept at the addon's original 336).

    Separately tackled the long-standing "sliders don't show their current value" Full-scope backlog item (flagged since 2026-08-28, explicitly unresearched — "check before building"). Confirmed live that Blizzard's native `Settings.CreateSlider` has no built-in support for this at all (only fixed min/max endpoint labels). Built via `initializer:InitFrame` (pcall-wrapped at the hook-registration level too, not just the handler, since a wrong method-name guess would throw immediately rather than fail gracefully) reading through `Settings.Subscribe` rather than hooking Blizzard's internal slider widget's drag event directly — sidesteps needing to know that widget's exact field name at all for the *update* mechanism. Positioning the label still needed *some* handle on the actual slider control: a first guess (`frame.Slider`) was live-confirmed wrong (label landed at the row's own far right edge, nowhere near the slider) — replaced with `findSliderDescendant`, a recursive search for the child with `GetObjectType() == "Slider"`, which works regardless of what Blizzard actually calls that field on this client build. That search found the draggable track specifically (not the wrapping control with both stepper arrows), so the first-pass 8px gap visually overlapped the increment arrow — widened to 28px once confirmed live. Also added value formatting keyed off each slider's own `step`: whole-number steps (Width, Height, Font Size) format as plain integers, fractional steps (Scale's 0.05) format to exactly 2 decimals (product owner: avoid raw float drift like `0.9000000000001` ever showing up). **Confirmed live and working** by the product owner across both rounds of correction.

    Also wired `HuntScannerRuntime.GetGroupedDisplayList` to accept an optional list-override parameter (defensively copied before sorting, so it never mutates a caller's table) so the Hunt Panel's Settings preview — previously deliberately flat/ungrouped (Decisions Log item 48) — now groups/sorts identically to the real panel, whether showing real cached hunts or the static placeholder rows.

    Unrelated small reorganization in the same session: "Link Border Color to Fill Color" moved from the separate "Bar Display" native category into "Bar Colors" itself (via the existing `createCheckboxRow` canvas helper), positioned above the color swatches it actually gates, since it only ever affected the Border Color swatch there anyway. Gained an immediate refresh call on toggle (now that it's co-located) rather than only updating the next time the tab is shown. **Confirmed live** (product owner: "the fill color does appear correctly"). `luacheck`: 0 warnings/0 errors across every touched file, all rounds.

### 19.1 Deployment & Branching Plan

You raised the real tradeoff correctly: doing this in the current `AddOns\Preydator` folder risks old-code bleed-through while testing (stray files WoW still loads alongside the new ones), but doing it in a totally separate folder means manually shuttling files back into the real git repo when it's done — which throws away history and is exactly the kind of manual, error-prone step this whole rewrite is trying to get away from.

**Recommendation: `git worktree`, not a second unconnected folder.** A worktree gives you a second physical directory checked out from a *branch of the same repository* — so you get the physical isolation of "a new directory" (WoW loads whichever folder you point it at, so old and new code are never mixed on disk) without losing the "one repository, one history" property that makes reintegration clean. Concretely:

1. In the existing D: repo, cut a new branch for the rewrite — e.g. `git checkout -b rewrite/v2-architecture` from whichever of `main`/`release`/`dev` you consider the true current baseline (given `dev` is the one you described as currently broken, I'd branch from `release` unless you tell me otherwise).
2. Create a worktree for that branch in a separate directory outside `AddOns\Preydator` — e.g. `git worktree add "D:\Dev\PreydatorRewrite" rewrite/v2-architecture`. This is still the same `.git` history; it's just a second checkout.
3. To test: point WoW at the worktree folder instead of the live `AddOns\Preydator` folder for that session (simplest is to swap which one is actually named/symlinked `Preydator` inside your `AddOns` directory — only one loads as "Preydator" at a time, so there's no risk of both copies loading together and colliding on the shared `_G.Preydator` global and SavedVariables). You don't need to run both simultaneously to compare them; toggle which folder is live when you want to test the rewrite vs. fall back to the last-known-good copy.
4. As real modules land, retire the old files with `git rm` in the same branch's commits (not just "stop editing them") — that way, when you eventually merge `rewrite/v2-architecture` back into your main line, git correctly deletes them from the target branch too, rather than leaving orphaned old files sitting untouched in history and in anyone else's checkout.
5. When the rewrite reaches parity and you're ready to cut over: a normal `git merge` (or a squash-merge if you'd rather collapse the rewrite's in-progress commit history into one clean commit) brings it into `main`, full history intact, no manual copying. Then `git worktree remove` cleans up the second directory.

This is the cleanest of the two options you were weighing: physical separation during testing (worktree's whole point), but the "bring it back into the main repo" step is a merge, not a manual file shuffle.

One practical note: WoW ties an addon's identity to its folder name matching its `.toc` filename, and the addon registers a single `_G.Preydator` global — so the two copies aren't meant to run side-by-side as two simultaneously-loaded addons without renaming one of them (folder, `.toc`, and the global). I wouldn't bother with that unless you specifically want to A/B them in the same game session; toggling which copy is live in `AddOns\` between test sessions is simpler and avoids the temporary-rename bookkeeping.

### 19.2 Hunt Row Layout — open questions before finalizing

The row structure (icon left, name/zone/rewards/accept stacked right, per `Hunt Table design template.png`) is locked into Section 4 and 5.6 above.

**Icon asset source — resolved by inspection.** I opened `Media/PreyHuntTableDifficulty_light.png` (709KB) and confirmed it's the exact source of all three skull icons in your template — it's one sprite sheet with the teal, gold, and red skull icons side by side on a transparent background. `hunt.difficulty_icon_set` (Section 5.6) will reference this existing file, sliced into three texture regions (one per difficulty) rather than three separate image files — no new art needed. Worth a quick sanity check on your end: the sheet is named `..._light.png`, which reads like it might be one variant of a light/dark pair — let me know if there's a `_dark` counterpart I should also account for (e.g. for a future dark-theme hunt panel), or if `_light` is just the file's only name and not indicating a variant set.

Both remaining behavior questions are now resolved:

1. **Reward row density — resolved: multiple icons inline.** The rewards row renders every reward as a small icon in a horizontal strip, not a "+N" summary. `hunt.reward_display_style` (Section 5.6) defaults to `icon_inline`; `icon_count` remains as a user-selectable, more compact fallback (`text_only` was tried and removed, Decisions Log item 53).
2. **Row click vs. Accept button — resolved: Accept button only.** The row itself is display-only; there's no click-to-preview. Only the Accept button (bottom-right) is interactive, and it accepts the hunt directly — no intermediate dialog preview step. `HuntTablePanel`'s description above reflects this.

`HuntTablePanel`'s render spec and the settings catalog are now fully locked in for this layout.

---

Once you've had a look, tell me where you want to start — I'd suggest bootstrap + State + Settings + the Adapters first, since literally everything else depends on those and they're the smallest possible slice to get running and testable.
