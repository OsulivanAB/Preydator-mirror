# Preydator Rewrite — Session Status / Handoff

Last updated: 2026-08-25. Read this before doing anything else in a fresh session — it's
the fastest way back to full context after a restart. This supplements, not replaces,
`CLAUDE.md` Section 0's reading list.

---

## 1. Where the code actually lives right now

- **`AddOns\Preydator`** (this folder — where WoW loads from) is git-linked to branch
  **`rewrite/v2-architecture`**, not `main`. Run `git branch --show-current` to confirm if
  unsure; don't assume `main` just because that's the usual default.
- **`D:\Dev\PreydatorLive`** — a separate worktree holding branch `main` (the live/stable
  shipped code), untouched, as a fallback/backup. Contains the real `.git` storage (it's
  the "main worktree" in git terms).
- **`D:\Dev\PreydatorRewrite`** — a stale, orphaned plain-file duplicate, no longer
  git-linked to anything. Safe to delete whenever; low priority.
- Everything below is **staged in git but not committed**. Nothing has been pushed
  anywhere. Confirm current staged state with `git status --short` before continuing —
  don't trust this list blindly if time has passed.

If `AddOns\Preydator` needs to flip back to `main` for real testing/release at some
point, see the "Deployment & Branching Plan" in `issues/rewrite_architecture.md` Section
19.1, and the mechanics/pitfalls in this session's memory (`git-worktree-move-gotchas` —
GitHub Desktop holds locks on this folder; close it before any move/rename attempt).

---

## 2. What's built, and confirmed working (not just lint-clean)

Per the architecture doc's build order (`CLAUDE.md` Section 14): bootstrap → State →
Settings → Adapters → Runtime → HuntScanner data/logic layer. All of the following now
exist, pass `luacheck` with **0 warnings / 0 errors across 20 files**, and — critically —
have been exercised against the live game, not just reviewed as code:

- `Preydator.lua` (bootstrap only, ~50 lines — nowhere near the 200-local ceiling)
- `Core/State.lua`, `Core/Settings.lua`
- `Core/Adapters/*.lua` (7 files): `QuestApiAdapter`, `MapContextAdapter`,
  `WidgetAdapter`, `SoundAdapter`, `SettingsStore`, `LocalizationAdapter`,
  `DiagnosticsAdapter`
- `Core/Runtime/*.lua` (7 files): `PreyContextRuntime`, `BarRuntime`, `SoundsRuntime`,
  `AlertsRuntime`, `DiagnosticsRuntime`, `EventRuntime`, `SettingsRuntime`
- `Modules/HuntScanner/{PreyQuestData,HuntTableAdapter,HuntScannerRuntime}.lua`

**In-game validation results (2026-08-25):**
- Full addon loads with **zero Lua errors** on login.
- Hunt Table pin scanning: all 15 live pins read correctly.
- `IsHuntTableActive()` correctly detects active/inactive.
- Difficulty resolution correct (via `PreyQuestData` primary + text-parse fallback).
- Zone resolution correct for all 15 hunts — **manually cross-checked by the product
  owner** against real zone IDs. Needed both the primary path
  (`C_TaskQuest.GetQuestZoneID`) and a coordinate-based fallback
  (`C_Map.GetMapInfoAtPosition` using each pin's own normalizedX/Y) — the primary alone
  returns nil for offered-but-unaccepted hunts.
- Accept → list shrinks by 1; abandon → full list of 15 re-offered. Confirmed working,
  no stuck state.

There is **no UI yet** — nothing renders on screen. All of the above was verified via
`/run` commands calling `Preydator:GetModule("X").Function()` directly in chat (see
memory: `preydator-ingame-verification` for the pattern — layer checks from raw/live data
down to fully-processed output so a failure narrows down *where* the pipeline breaks).

---

## 3. Bugs found and fixed via live testing this session

These were **only discoverable by actually playing the game** — luacheck and code review
caught none of them. Full detail in memory (`preydator-blizzard-api-quirks`,
`preydator-event-loop-incident`) but the short version:

1. **`IsHuntTableActive()` needed 3 OR'd signals, not 1.** A gossip-option spellID check
   alone only works in the brief instant gossip is open — useless once the map/pin view
   replaces it. Fixed with a 3-signal check (gossip spellID, target NPC ID, or pins simply
   being present).
2. **`C_TaskQuest.GetQuestZoneID` returns nil for unaccepted hunts**, even after calling
   `C_QuestLog.RequestLoadQuestByID`. Added a `C_Map.GetMapInfoAtPosition` fallback using
   the pin's own coordinates (a live API call, not the hardcoded coordinate-bucket
   heuristic the architecture doc says to drop — that's a different thing).
3. **`CovenantMissionFrame.MapTab:GetMapID()` is the correct current-patch call** — the
   old code's nested `MapTab.ScrollContainer`/`MapTab.MapCanvas` child lookup is stale
   (Blizzard restructured this since the old code was written).
4. **CRITICAL — hung the client once**: wiring `QUEST_DATA_LOAD_RESULT` to trigger a
   rescan, where the rescan itself re-issued `RequestLoadQuestByID` for all 15 quests
   unconditionally, created an unbounded feedback loop (event → rescan → new requests →
   more events → ...). Fixed with a once-per-questID guard
   (`requestedLoadForQuestID` in `HuntScannerRuntime.lua`). **Any future code that wires
   "async Blizzard request" + "event fired when it resolves" + "handler that can re-issue
   the same request" must be checked for this pattern before it ships, not after.**

---

## 4. What's NOT built yet

- **All of `UI/*.lua`**: `BarFrame.lua`, `SettingsPanel.lua`, `EditMode.lua`,
  `ReportWindow.lua`, `Launcher.lua`. Nothing visual exists.
- **`Modules/HuntScanner/HuntTablePanel.lua`** — the actual hunt-list UI rendering.
- HuntScanner grouping/sorting, achievement-signal matching, reward display — these are
  explicitly Full-scope-only per the architecture doc's Section 15 MVP table, not MVP.
  Not an oversight; don't build them yet without checking scope first.
- The old **`Modules/HuntScanner.lua`** (5045 lines) is still sitting in the tree,
  **only partially superseded** (~20-30%, the scan/list/select/zone core). Grouping,
  sorting, achievement matching, reward display, and panel rendering logic still only
  exist there. Don't `git rm` it until those are ported.
- Bloody Command / Echo of Predation: confirmed dead (Season 1 mechanics, patch 12.1
  discontinued them) but kept dormant, not removed — `sound.bloody_command_enabled`
  defaults `false`. See architecture doc Section 19, item 5, and memory
  `preydator-deprecated-mechanics`.

---

## 5. Next step

**`UI/BarFrame.lua`** is the natural next slice — it's the addon's core visual feature,
and `BarRuntime`/`State`/`Settings` are already built and ready to feed it.

Research on the old bar-rendering code was already gathered this session via a research
agent (source: `D:\Dev\PreydatorLive\Core\BarRuntime.lua`, ~1000 lines, plus
`Preydator.lua`'s `EnsureBar`/`ApplyBarSettings`/`UpdateBarDisplay` functions) but **was
not acted on before this break** — that research covered: frame hierarchy & texture/font
presets, horizontal-vs-vertical orientation math, drag & position persistence, the 9
`stage_label_mode` values' actual layout logic, tick mark positioning, and why "Edit Mode
integration" in the old code is really just an `EditModeManagerFrame:IsShown()` check
(no real Blizzard Edit Mode system registration). If starting fresh, either re-run that
research (it's cheap, ~2 minutes) or ask about it directly — the findings weren't saved
verbatim to a file, only summarized in this conversation.

Also worth deciding early: `bar.accessibility_theme` (deuteranopia/protanopia presets) is
genuinely new work — the old code has zero accessibility color logic to port, confirmed
by the research agent's grep. This will need real design, not porting.

---

## 6. Housekeeping

- `.vscode/settings.json` has an uncommitted local change (Lua language server WoW-API
  annotations) — not made by Claude, left as-is, harmless.
- Nothing has been committed this session. Whenever a commit is wanted, it should follow
  `.github/commit-template.md` per `CLAUDE.md` Section 11, signed as RagingAltoholic.
