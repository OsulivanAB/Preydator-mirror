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
    SoundsRuntime.lua                  -- stage/ambush/Bloody Command/Echo sound resolution + playback
    AlertsRuntime.lua                  -- chat-text-driven ambush / Bloody Command detection
    DiagnosticsRuntime.lua             -- debug snapshot assembly (qinspect/pinspect/inspect)
    EventRuntime.lua                   -- the single event dispatcher (Section 7)
    SettingsRuntime.lua                -- settings validation/normalization (called only by SettingsStore)

UI/
  BarFrame.lua                        -- bar frame creation + rendering from BarRuntime snapshots
  EditMode.lua                        -- quick-settings window + Edit Mode integration
  SettingsPanel.lua                   -- options UI (general/bar/text/progress/sound categories)
  ThemeEditor.lua                     -- [full-feature] custom theme editor UI
  ReportWindow.lua                    -- generic scrollable report viewer (reused as-is conceptually)
  Launcher.lua                        -- minimap button + Addon Compartment integration

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
**Responsibility:** pure computation — turns `State.GetSnapshot()` + `Settings` into a bar view-model (`{fillPercent, stageLabelText, color, tickPositions, ...}`). Does **not** touch a single Blizzard frame or texture — that's `UI/BarFrame.lua`'s job entirely. This is the single biggest structural change from the old code, where `Core/BarRuntime.lua` is actually ~1,000 lines of direct frame/texture/font manipulation despite its "Runtime" name.
**Reads:** `Core/State.lua`, `Core/Settings.lua`.
**Writes:** nothing (pure function of its inputs).
**Publishes:** `ComputeBarViewModel()`.

### Core/Runtime/SoundsRuntime.lua
**Responsibility:** resolves which sound path plays for a given stage/ambush/Bloody Command/Echo event, honoring user overrides vs. protected defaults, and anti-spam cooldown gating. Calls `SoundAdapter.Play` for actual playback — never `PlaySoundFile` directly.
**Reads:** `Core/Settings.lua`, `Core/State.lua` (for stage-transition detection).
**Writes:** its own cooldown-tracking state (last-played timestamps) — not shared state.
**Publishes:** `PlayStageSound(stage)`, `PlayAmbushSound()`, `PlayBloodyCommandSound()`, `PlayEchoOfPredationSound()`.

### Core/Runtime/AlertsRuntime.lua
**Responsibility:** chat-text pattern matching for ambush/Bloody Command triggers (`CHAT_MSG_SYSTEM`/`MONSTER_SAY`/etc.), gated by settings + restricted-instance + active-prey-context. Calls into `SoundsRuntime` and `State` — never touches chat frames or UI.
**Publishes:** `HandleChatEvent(event, msg)`.

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
**Responsibility:** `CreateFrame` calls, texture/font/color application, and rendering — consumes `BarRuntime.ComputeBarViewModel()` output and nothing else. Never reads `State` or `Settings` directly.
**Publishes:** `EnsureBar()`, `Render(viewModel)`.

### UI/EditMode.lua, UI/SettingsPanel.lua, UI/ThemeEditor.lua, UI/ReportWindow.lua, UI/Launcher.lua
Each renders from and writes back through `Core/Settings.lua`'s public API only. `ReportWindow.lua` and `EditMode.lua` were already the two cleanest UI-adjacent files in the old codebase (generic, hunt-agnostic, properly using the sanctioned API surface) — they carry forward with minimal structural change, just relocated under `UI/`.

### Modules/HuntScanner/HuntTableAdapter.lua
**Responsibility:** the only file that touches `CovenantMissionFrame`, `AdventureMapQuestChoiceDialog`, gossip/interaction-manager state, and the Adventure Map pin pool. Returns validated hunt records `{questID, title, rawDifficultyText, zoneMapIDFromPin, rewardWidgets}` — nothing downstream touches these Blizzard objects directly.
**Publishes:** `GetOfferedHunts()`, `OpenHuntDialog(questID)`, `AcceptHunt(questID)`.

### Modules/HuntScanner/HuntScannerRuntime.lua
**Responsibility:** parses adapter output into hunt domain objects, derives and caches each hunt's **expected zone** at scan time (Section 8), handles grouping/sorting, and delegates selection to the adapter. Does not create or touch a single frame.
**Reads:** `HuntTableAdapter`, `Core/Settings.lua`.
**Writes:** its own hunt-list state and the expected-zone cache (published for `PreyContextRuntime` to read).
**Publishes:** `GetHuntList()`, `SelectHunt(questID)`, `GetExpectedZone(questID)`.

### Modules/HuntScanner/HuntTablePanel.lua
**Responsibility:** renders `HuntScannerRuntime.GetHuntList()` as the hunt panel. **Only the Accept button is interactive** — it calls `HuntScannerRuntime.SelectHunt(questID)`. The rest of the row (icon, name, zone, rewards) is display-only; there is no row-click-to-preview behavior. `HuntTableAdapter`'s dialog-preview call (`OpenHuntDialog`) stays available on the adapter for possible future use (e.g. a tooltip), but the panel does not wire it to anything today.

**Row layout (confirmed design, per `Hunt Table design template.png`):** each hunt row is a fixed two-column layout — a difficulty icon on the left, and a four-line info stack on the right:

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
| `general.lock_bar` | boolean | `false` | Prevents dragging the bar frame | Bar mouse-down handler | `UI/BarFrame` | Drag lock UI, `UI/EditMode` | Yes | Cosmetic |
| `general.only_show_in_prey_zone` | boolean | `false` | Hides the bar entirely outside the prey zone | Every `BarRuntime.ComputeBarViewModel` call | `BarRuntime` | `UI/SettingsPanel` | Yes | Cosmetic |
| `general.disable_default_prey_icon` | boolean | `false` | Suppresses Blizzard's built-in prey icon overlay | Widget-shown hook | `WidgetAdapter` | `UI/SettingsPanel` | Yes | Cosmetic |
| `general.schema_version` | number | current version constant | Settings schema version gate | Every `SettingsStore.Load()` | `SettingsStore` | `SettingsStore` only | No (internal) | **Required** — corrupting this breaks migration |

### 5.2 Bar Display

| Name | Type | Default | Purpose | Read by | Written by | Configurable |
|---|---|---|---|---|---|---|
| `bar.orientation` | enum(`horizontal`,`vertical`) | `horizontal` | Bar layout mode | `BarRuntime` | Settings UI | Yes |
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
| `bar.show_ticks` | boolean | `true` | Tick-mark visibility | `BarRuntime` | Settings UI | Yes |
| `bar.show_spark_line` | boolean | `false` | Animated fill-edge spark | `UI/BarFrame` | Settings UI | Yes |
| `bar.percent_display` | enum(`inside`,`above_bar`,`above_ticks`,`under_ticks`,`below_bar`,`off`) | `inside` | Percent text placement, horizontal mode | `BarRuntime` | Settings UI | Yes |
| `bar.progress_segments` | enum(`quarters`,`thirds`) | `quarters` | Tick/segment division for progress fallback | `PreyContextRuntime`, `BarRuntime` | Settings UI | Yes |
| `bar.vertical_fill_direction` | enum(`up`,`down`) | `up` | Fill direction, vertical mode | `UI/BarFrame` | Settings UI | Yes |
| `bar.vertical_text_side` | enum(`left`,`right`) | `right` | Text side, vertical mode | `UI/BarFrame` | Settings UI | Yes |
| `bar.show_in_edit_mode` | boolean | `true` | Show bar during Blizzard Edit Mode | `UI/BarFrame` | Settings UI | Yes |

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
| `text.bloody_command_prefix` | string | localized default | Bloody Command alert prefix | `BarRuntime` | Settings UI | Yes |
| `text.bloody_command_suffix_template` | string | `{bloodyCommandSourceName}` token | Bloody Command alert suffix | `BarRuntime` | Settings UI | Yes |
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
| `sound.bloody_command_enabled` / `bloody_command_path` | boolean / string | `true` / protected default | Bloody Command alert sound | `SoundsRuntime` | Settings UI | Yes | Cosmetic |
| `sound.echo_of_predation_path` | string | protected default | Echo of Predation alert sound | `SoundsRuntime` | Settings UI | Yes | Cosmetic |
| `sound.custom_file_names` | list\<string\> | seeded from protected defaults | User-added sound files available in pickers | `SoundsRuntime` | Settings UI (`Add`/`Remove File`) | Yes | Cosmetic |
| `sound.alert_cooldown_seconds` | number | `30` | Anti-spam cooldown shared by ambush/Echo triggers | `SoundsRuntime` | Internal (fixed) | No | **Required** — prevents alert spam under rapid trigger conditions |

### 5.6 Hunt Scanner / Hunt Table

| Name | Type | Default | Purpose | Read by | Written by | Configurable |
|---|---|---|---|---|---|---|
| `hunt.enabled` | boolean | `true` | Master toggle | `HuntScannerRuntime` | Settings UI | Yes |
| `hunt.panel_side` | enum(`left`,`right`) | `right` | Screen anchor side | `HuntTablePanel` | Settings UI | Yes |
| `hunt.group_by` | enum(`none`,`difficulty`,`zone`) | `difficulty` | Grouping mode | `HuntScannerRuntime` | Settings UI / panel button | Yes |
| `hunt.sort_by` | enum(`difficulty`,`zone`,`title`) | `zone` | Sort field | `HuntScannerRuntime` | Settings UI / panel button | Yes |
| `hunt.sort_direction` | enum(`asc`,`desc`) | `asc` | Sort direction | `HuntScannerRuntime` | Settings UI | Yes |
| `hunt.reward_display_style` | enum(`icon_inline`,`icon_count`,`text_only`) | `icon_inline` | Reward row format — `icon_inline` shows every reward as a small icon strip on the rewards line (confirmed default, per Section 19.2); `icon_count`/`text_only` remain as fallback/compact options for narrow panel widths | `HuntTablePanel` | Settings UI | Yes |
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
| `debug.bloody_command_verbose` | boolean | `false` | Extra logging for Bloody Command path specifically | Yes | Cosmetic |

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
| `predator-kills-its-prey-to-survive.ogg` | Bloody Command trigger |
| `echo-of-predation.ogg` | Echo of Predation trigger |
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
| BarRuntime + UI/BarFrame | ✅ | ✅ |
| SoundsRuntime + AlertsRuntime (stage/ambush/Bloody Command/Echo) | ✅ | ✅ |
| DiagnosticsRuntime + UI/ReportWindow + slash debug commands | ✅ | ✅ |
| HuntScanner: scan, list, select, expected-zone derivation | ✅ | ✅ |
| HuntScanner: grouping/sorting/reward display | — | ✅ |
| HuntScanner: achievement signals/badges | — | ✅ |
| Accessibility bar-color presets (`bar.accessibility_theme`) | ✅ (cheap, high value) | ✅ |
| Full theme system + ThemeEditor UI | — | ✅ |
| Settings profiles (multiple named profiles) | — | ✅ |
| UI/EditMode quick-settings window | ✅ | ✅ |
| UI/Launcher (minimap/compartment button) | ✅ | ✅ |
| Full locale translations (beyond enUS) | partial (framework required, translations can lag) | ✅ |

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

local CHAT_EVENTS = {
    CHAT_MSG_SYSTEM = true,
    CHAT_MSG_MONSTER_SAY = true,
    CHAT_MSG_MONSTER_YELL = true,
    CHAT_MSG_MONSTER_EMOTE = true,
    CHAT_MSG_RAID_BOSS_EMOTE = true,
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

    if CHAT_EVENTS[event] then
        local alerts = Preydator:GetModule("AlertsRuntime")
        if alerts then alerts.HandleChatEvent(event, ...) end
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

1. **Reward row density — resolved: multiple icons inline.** The rewards row renders every reward as a small icon in a horizontal strip, not a "+N" summary. `hunt.reward_display_style` (Section 5.6) defaults to `icon_inline`; `icon_count`/`text_only` remain as user-selectable fallbacks for a narrower panel.
2. **Row click vs. Accept button — resolved: Accept button only.** The row itself is display-only; there's no click-to-preview. Only the Accept button (bottom-right) is interactive, and it accepts the hunt directly — no intermediate dialog preview step. `HuntTablePanel`'s description above reflects this.

`HuntTablePanel`'s render spec and the settings catalog are now fully locked in for this layout.

---

Once you've had a look, tell me where you want to start — I'd suggest bootstrap + State + Settings + the Adapters first, since literally everything else depends on those and they're the smallest possible slice to get running and testable.
