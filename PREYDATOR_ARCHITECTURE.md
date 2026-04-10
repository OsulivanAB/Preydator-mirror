# Preydator Architecture Guide

This file documents practical extension points and guardrails for ongoing development.

---

# 1. Execution Model

1. `Preydator.toc` loads addon files.
2. `Preydator.lua` initializes shared runtime state and settings.
3. Core runtimes normalize and expose cross-feature helpers.
4. Event runtime dispatches events to registered modules.
5. Modules execute feature-specific behavior.

---

# 2. Primary Components

## 2.1 Core Runtime Files

- `Core/EventRuntime.lua`: event dispatch and event-path guardrails.
- `Core/PreyContextRuntime.lua`: map and prey-context helpers.
- `Core/SoundsRuntime.lua`: sound file validation, resolution, playback helpers.
- `Core/SettingsRuntime.lua`: settings normalization and defaults behavior.
- `Core/BarRuntime.lua`: bar rendering and placement logic.
- `Core/Alerts.lua`: alert pathways used by runtime behavior.
- `Core/DebugRuntime.lua`: diagnostics helpers.

## 2.2 Feature Modules

- `Modules/HuntScanner.lua`: prey/hunt scan logic.
- `Modules/Settings.lua`: options UI and user-facing configuration.
- `Modules/SlashCommands.lua`: command routing.
- `Modules/ProfileManager.lua`: profile operations.
- `Modules/EditMode.lua`: bar edit/placement interactions.
- `Modules/CurrencyTracker.lua`: currency integration.
- `Modules/DebugInspect.lua`: debug inspection tooling.

---

# 3. State and Settings Model

- Runtime state is centralized in `Preydator.lua` (`state`).
- User preferences are centralized in `Preydator.lua` (`settings`).
- Modules should consume and update through existing pathways instead of ad hoc tables.

Guardrails:

- Do not add new top-level globals.
- Do not duplicate authoritative state in multiple modules.

---

# 4. Event Flow and Performance

- Event dispatch fans out from central runtime to module `OnEvent` handlers.
- Keep per-event work minimal.
- Gate expensive work by active hunt context and zone checks.
- Avoid repeated table allocations in high-frequency handlers.

---

# 5. Zone and Context Gating

- Use canonicalized map checks through `Core/PreyContextRuntime.lua`.
- For hunt-limited features, require active prey quest and hunt-zone match.
- Avoid stale context assumptions after zone transitions.

---

# 6. Sound Pipeline

- Sound configuration should remain settings-driven.
- Default bundled sounds should remain protected from deletion.
- Custom sounds should be validated through runtime rules.
- Encounter-triggered sounds should include anti-spam behavior.

---

# 7. Pattern for New NPC Encounter Sounds

For requests like `npc=248365` (Echo of Predation):

Required conditions:

1. Active prey hunt context is valid.
2. Player is currently in the hunt zone (if requested).
3. Encounter signal identifies target NPC reliably.
4. Sound trigger ignores quest stage when stage-independent behavior is required.
5. Trigger respects cooldown/one-shot anti-spam policy.

Recommended implementation shape:

- Add encounter eligibility helper.
- Add deterministic trigger function.
- Add debug log lines for gating decisions.
- Keep feature settings-driven where feasible.

---

# 8. Documentation and Release Discipline

When behavior changes:

1. Update `README.md` for user-visible behavior.
2. Update `CHANGELOG.md` with versioned notes.
3. Keep architecture docs aligned to prevent drift.

---

# 9. Validation Checklist

Before finalizing a change:

- Verify no writes occurred outside allowed folders.
- Verify event handlers remain lightweight.
- Verify nil-safe behavior under missing API values.
- Verify zone gating works during transitions.
- Verify sound trigger anti-spam behavior.
- Verify docs reflect implementation.
