# Preydator Rewrite — Session Status / Handoff

Last updated: 2026-09-02. Read this before doing anything else in a fresh session — it's
the fastest way back to full context after a restart. This supplements, not replaces,
`CLAUDE.md` Section 0's reading list.

---

## 0. 2026-09-02 session at a glance

Focus: achievement signals (Epic 4) and HuntScanner grouping/sorting, both previously
Full-scope/parked items — unblocked because the product owner now has a live hunt with a
completable achievement. Full narrative in Sections 5b/5c below; Decisions Log items 44-57
in `issues/rewrite_architecture.md` have the complete design reasoning for every item here.

**Shipped and live-confirmed today:**
- Achievement badges on the Hunt Table panel (icon-only, hover for count + names), gated
  correctly on per-target completion, with a name-matching fallback for hunts not yet in
  `PreyQuestData`.
- HuntScanner grouping/sorting with full collapsible headers, plus on-panel Group/Sort/
  Direction buttons — all settings confirmed persisting across `/reload` and a full relog.
- Zone display-name override ("The Coiled Isle" instead of Blizzard's "Quel'Thalas") and
  article-insensitive zone sort/group order.
- Reward row fixes: stable ordering (Coffer Key → Preyseeker's Journey → Mistcrest →
  other → chest/bag always last), a corrected `reward_display_style` (icon_inline vs.
  icon_count), a caching bug that could permanently drop the chest/bag reward for a whole
  difficulty, and a 4-icon row cap that was truncating Nightmare's 5th reward.
- A locale gap in `resolveDifficulty`'s text-fallback (ported the old addon's own
  `L["Nightmare"]`/`L["Hard"]`/`L["Normal"]` fix rather than inventing one).

**Removed:** the `text_only` reward display style — built, live-tested, and rejected by
the product owner as not a viable look, same session.

**Still open, Hunt-Panel-specific:**
1. Achievement-earned live-update path (`ACHIEVEMENT_EARNED` cache wipe) — blocked on the
   product owner's second test account reaching a completable achievement, not on code.
2. Possible reward-row/Accept-button visual overlap at default panel width now that up to
   6 reward icons can render — flagged from pixel math, not yet confirmed live.
3. `PreyQuestData` still lacks entries for 4 new Nightmare questIDs (95021-95024) — the
   name-matching fallback covers them functionally, so this is optional data cleanup now,
   not a gap.
4. `koKR`/`zhCN` difficulty-detection locale fix is partial — those two locales lack a
   plain "Normal"/"Hard"/"Nightmare" translation key (only compound keys like "Normal
   Difficulty" exist today); needs a native speaker, not a guessed translation.

**luacheck: 0 warnings / 0 errors across the whole active `.toc` load list** as of the end
of this session (397 pre-existing warnings remain, all confined to old off-`.toc` monolith
files not touched this session — `Modules/Settings.lua`, `Modules/SlashCommands.lua`,
`Modules/HuntScanner.lua`). No warning-561 concern anywhere.

**Nothing committed.** See Section 6 (Housekeeping) — this branch has no commits at all
yet; everything since the rewrite began is still sitting in the working tree.

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
exist, pass `luacheck` with **0 warnings / 0 errors across the 23 files actually in the
active `.toc` load list**, and — critically — have been exercised against the live game,
not just reviewed as code:

- `Preydator.lua` (bootstrap only, ~50 lines — nowhere near the 200-local ceiling)
- `Core/State.lua`, `Core/Settings.lua`
- `Core/Adapters/*.lua` (7 files): `QuestApiAdapter`, `MapContextAdapter`,
  `WidgetAdapter`, `SoundAdapter`, `SettingsStore`, `LocalizationAdapter`,
  `DiagnosticsAdapter`
- `Core/Runtime/*.lua` (7 files): `PreyContextRuntime`, `BarRuntime`, `SoundsRuntime`,
  `AlertsRuntime`, `DiagnosticsRuntime`, `EventRuntime`, `SettingsRuntime`
- `Modules/HuntScanner/{PreyQuestData,HuntTableAdapter,HuntScannerRuntime}.lua`

**`UI/BarFrame.lua` — in-game confirmed working (2026-08-27):** bar is created, is
draggable, shows the Edit Mode preview correctly, and its position survives a `/reload`
(re-moving it after switching characters is expected — that's a profiles gap, not a bug,
see the Decisions Log). Orientation (`bar.orientation = vertical`) was **not** testable in
that pass — no in-game way yet to flip the setting — see the `UI/SettingsPanel.lua` callout
below, which exists specifically to unblock that. See `issues/rewrite_architecture.md`
Decisions Log items 6-8 for the design decisions behind `BarFrame.lua` (label-mode-in-
vertical-mode unification, single lock/mouse gate, event-driven Edit Mode hook, simplified
position schema, and the "looks like the old bar" clarification — new render code, old
default *values*, both deliberate). `bar.show_spark_line` is explicitly **not implemented
yet**, a real open item, not an oversight (see item 7's last bullet).

**`UI/SettingsPanel.lua` — in-game confirmed working (2026-08-27):** the in-game options UI.
Uses Blizzard's modern Settings API for most categories (General — on the root page, not a
subcategory, Bar Display, Sound & Alerts, Hunt Scanner) plus three small custom-canvas
categories (Bar Colors, Text & Labels, Advanced) for controls the native API doesn't
support (color swatches, free text, action buttons). Reachable via Escape → Options →
AddOns → Preydator, or `/preydator`. Every category, the color picker, the accessibility
theme preset, text editing, and every Advanced button were exercised live with no errors.
See `issues/rewrite_architecture.md` Decisions Log items 9-11 for the full design reasoning
and the Section 5.8 action-button resolution (Reset Hunt Table Position is explicitly not
built — blocked on `HuntTablePanel.lua` not existing yet). One open, non-blocking item: a
taint error when opening a Sound & Alerts dropdown, root cause unconfirmed — see Section 3.

**`Modules/HuntScanner/HuntTablePanel.lua` — in-game tested, two bugs found and fixed
(2026-08-27):** the hunt-list UI. MVP row subset only (icon + name + zone + Accept, no
rewards line — Full-scope per Section 15). Also added: `HuntScannerRuntime.Subscribe()`
(new, mirrors `State.lua`/`Settings.lua`'s pattern) so the panel reacts to hunt-list
changes without the panel registering its own raw WoW events.
1. **Panel docked to a fixed screen edge instead of Blizzard's own Hunt Table UI.** Fixed
   to anchor to `CovenantMissionFrame` (the Adventure Map frame the pins live on) per
   `hunt.panel_side`, falling back to a screen edge only if that frame isn't shown.
2. **Difficulty icons looked squished.** The first-pass texcoords assumed the 3 skull
   icons filled three full-height thirds of the sprite sheet; actually viewing the image
   (`media/PreyHuntTableDifficulty_light.png`) showed they sit in a narrow band with wide
   transparent margins above/below — mapping the full height in squished the visible art
   down to a sliver. Re-cropped per-icon after visual inspection; still an eyeballed crop,
   may need one more nudge.

**Round 2 (still 2026-08-27):** docking and icons confirmed fixed by the product owner.
3. **Panel stayed empty the whole time the Hunt Table was open, only picked up real hunts
   after closing it — took seven rounds of incremental patching to actually resolve, and
   the pattern itself became the issue.** Rounds 1-7 each fixed something real (a missing
   staggered rescan schedule; `GOSSIP_CLOSED` not reliably correlating with
   `CovenantMissionFrame`'s visibility; the noisy `UPDATE_UI_WIDGET`/`UPDATE_ALL_UI_WIDGETS`
   trigger the old code actually relies on; an undebounced `QUEST_DATA_LOAD_RESULT` causing
   a genuine spam/thrashing loop — dozens of rescans/renders per second) but each round
   surfaced the *next* missing piece, because the old codebase's mechanism is one coherent
   state machine, not independent parts that can be reconstructed piecemeal. The product
   owner correctly called this out as reactive patching rather than holistic development
   after round 7. **Resolved (2026-08-27) by a full, deliberate port** — not a redesign —
   of the old `Modules/HuntScanner.lua` interaction-tracking state machine into
   `Core/Runtime/EventRuntime.lua`: the `huntInteractionActive` flag,
   `syncNoisyEventSubscriptions`, and the exact debounce-then-staggered-burst logic of
   `queueInteractionSnapshotPasses` (debounce = `0.15s`, matching the old code's own
   constant exactly — an earlier guess of `0.5s` was wrong), plus faithful per-event
   dispatch for every relevant WoW event. **Explicitly not ported**, per the product
   owner's direction: the old panel's own *rendering* — `HuntTablePanel.lua` is untouched
   by this port, still the freshly-designed panel built earlier. Also caught in the
   process: `UPDATE_UI_WIDGET`/`UPDATE_ALL_UI_WIDGETS` had been registered since round 4
   but never added to `HANDLED_EVENTS`, so every firing was silently dropped before
   dispatch — dead code the whole time, not a contributor to the spam either way.

   **The full port then regressed the bug (panel didn't render even after clicking a
   quest pin)** — this was a real design flaw in the old code itself, not a porting
   mistake. A pasted debug-log trace (2026-08-27) proved `GOSSIP_SHOW`/
   `PLAYER_INTERACTION_MANAGER_FRAME_SHOW` both make one synchronous check the instant
   they fire (a gossip-option scan / `CovenantMissionFrame:IsShown()`), decide
   `huntInteractionActive` once from that single result, and never recheck —
   `CovenantMissionFrame:IsShown()` is proven still `false` even on its own `..._SHOW`
   event and only flips `true` several seconds later, so the old mechanism only ever
   *appeared* to work because an unrelated `QUEST_DATA_LOAD_RESULT` firing coincidentally
   landed after that delay. **Fixed (2026-08-27) by removing the single-check assumption
   entirely**, not by porting more of the old code: both events now start a staggered
   *watch* (`beginHuntTableWatch`, reusing the same `0.05`–`10.00`s schedule) where every
   pass — immediate plus each delay — re-evaluates `HuntTableAdapter.IsHuntTableActive()`
   fresh, so whichever pass lands after the frame is actually visible is the one that
   activates tracking. The two adapter helpers the port had added
   (`IsMissionFrameVisible()`, `HasHuntTableGossipOption()`) were exactly the kind of
   single-instant check that caused the regression, so both were removed again —
   `EventRuntime.lua` now reads only the one already-robust `IsHuntTableActive()` signal,
   repeatedly. Full design detail in `issues/rewrite_architecture.md` Decisions Log item 12.

   **Re-tested in-game (2026-08-27, later same session): still does not render.** The
   staggered-watch fix did not resolve the symptom — no luck, panel stayed empty/hidden
   through the whole interaction. This means the working theory (the only problem was a
   single stale synchronous check) is **not fully confirmed** — either something is
   still wrong with the watch/check logic itself, or the deeper problem is upstream of it
   (see Section 5 "Next step" for the concrete, prioritized diagnostic plan for next
   session — the fastest next move is confirming with a fresh, minimal print whether
   `GOSSIP_SHOW`/`PLAYER_INTERACTION_MANAGER_FRAME_SHOW` fire at all for this specific NPC
   interaction, since if they don't, the whole watch mechanism never starts regardless of
   how correct its internal logic is). Session paused here for the night at the product
   owner's request; nothing further attempted after this point today.
4. **Icons no longer squished but looked low-resolution.** Likely inherent, not a bug: the
   source art is a detailed painted skull (glows/gradients), not flat vector art, so it
   reads softer than a crisp icon once downsampled to a small display size. Bumped
   `ICON_SIZE` 40→48 (fits within the existing 56px row height) to give it a bit more room;
   this won't fully eliminate the softness, which is close to the ceiling of what this
   source asset can do at icon size. Superseded shortly after by the icon-sheet
   replacement below anyway.

**Icon sheet replaced with three separate files (2026-08-27).** Rather than continuing to
tune texcoords against the shared `PreyHuntTableDifficulty_light.png` sheet (two rounds of
correction already), the product owner supplied `media/Preydator_{Normal,Hard,Nightmare}_
Difficulty.png` — pre-cropped, one file per difficulty. `HuntTablePanel.lua` now does a
plain `SetTexture(path)` per difficulty (`DIFFICULTY_ICON_PATHS`), no texcoord math left at
all. **Confirmed looking good in-game** by the product owner.

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

As of 2026-08-25 there was **no UI yet** — nothing rendered on screen; `UI/BarFrame.lua`
now exists (see the callout above) but has not itself been through a live-game pass. All
of the 2026-08-25 results below were verified via
`/run` commands calling `Preydator:GetModule("X").Function()` directly in chat (see
memory: `preydator-ingame-verification` for the pattern — layer checks from raw/live data
down to fully-processed output so a failure narrows down *where* the pipeline breaks).

---

## 2b. `UI/BarFrame.lua` bugs found via live testing after `SettingsPanel.lua` unblocked
orientation testing (2026-08-27, same day)

Three real bugs, all fixed:

1. **Vertical-mode label text sat ~70px away from the bar, either side.** Root cause:
   `applyLabelRegionAnchor` anchored an EDGE point of the fontstring (e.g. `BOTTOMLEFT`)
   then called `SetRotation` — but WoW rotates a region around its own CENTER, not the
   anchor point, so an edge-anchored, auto-sized (text-length-dependent) fontstring swings
   away from the intended spot by roughly half its own length once rotated. Fixed by
   anchoring via the fontstring's own CENTER instead — rotation is then invisible to the
   anchor math regardless of text length. The same latent bug existed in
   `applyPercentText`'s `above_bar`/`below_bar` branches; fixed there too, and simplified so
   only the `inside` percent-display mode rotates at all (above/below sit in open space and
   don't need it).
2. **Releasing a drag snapped the bar to a different position.** Root cause:
   `SetPoint`'s offset arguments are interpreted in the *calling frame's own effective
   scale*, but `SavePosition` computed the offset via `GetCenter()` deltas (which are
   scale-independent/absolute) and fed that same number straight back into
   `frame:SetPoint(...)` unchanged — any scale other than exactly matching the frame's
   current scale (which includes the player's overall UI scale, almost never exactly 1.0)
   silently re-scaled the position.
3. **Moving the horizontal or vertical scale slider re-centered the bar,** independent of
   lock state. Same root cause as #2: an existing anchor's offset is continuously
   re-resolved against the frame's *current* scale, so calling `frame:SetScale(...)` alone
   (no `SetPoint`) shifts where the existing offset numbers land on screen.

Fix for both #2 and #3: `BarFrame.ApplyPosition`/`SavePosition` now divide the stored
absolute `bar.position_x`/`position_y` by `frame:GetScale()` before passing to `SetPoint`,
and `Render()` calls `ApplyPosition` every render (after `SetScale`), not just on
drag/creation — so a scale change alone always re-derives the correct screen position.
**Confirmed fixed in-game** by the product owner (2026-08-27) — drag/scale/Edit-Mode-
preview/reload-persistence-of-*something* all work now.

**4. CRITICAL, found right after the above: the bar reset to its default position on every
`/reload`.** Not a position-specific bug — `UI/BarFrame.lua`'s self-init called
`RequestRender()` (which reads `Settings.Get(...)`) synchronously at file-load time,
before `ADDON_LOADED`/SavedVariables population, so `Core/Settings.lua`'s cache got
permanently stuck on default values for the whole session (Section 12 of the architecture
doc: the cache loads once and is never re-read). See Decisions Log item 10 for the full
explanation — this affected every setting, not just position, it just happened to be most
visible there. Fixed by deferring the first `RequestRender()` to `PLAYER_LOGIN`; the same
precaution was applied to `UI/SettingsPanel.lua`'s whole category-registration block as a
precaution (unconfirmed whether it was actually affected, but free to fix since Options
can't open before `PLAYER_LOGIN` anyway). **Any future `UI/*.lua` file with file-scope
self-init must gate its first Settings/State read behind `PLAYER_LOGIN` — this is now a
standing rule, not a one-off patch.** Not yet re-verified in-game.

**5. UX change, not a bug:** `UI/SettingsPanel.lua`'s General checkboxes (enable bar/
sounds/hunt, lock bar, etc.) now live directly on the root "Preydator" page instead of a
separate "General" subcategory tab — the product owner pointed out the root page was
otherwise empty. `buildGeneralCategory` → `buildGeneralSettings`, registers straight onto
the root category object.

**6. Dragging the bar "bounced"/snapped to odd locations relative to the mouse, but only
for roughly the first minute after login/reload, consistently reproducible.** Root cause:
`Render()` unconditionally re-anchors the frame to its *stored* position every time it
runs (needed for the scale-slider fix, #3 above) — but `Render()` also fires on every
State/Settings change, and quest-log/zone events fire frequently in the ~60s right after
`PLAYER_ENTERING_WORLD` while things settle. Each of those firing *during* an active drag
yanked the frame back to its last-saved position, fighting `StartMoving()`'s mouse-follow —
hence "bounces for about a minute, then stops" (once the post-login event storm quiets
down, `Render()` stops firing mid-drag). Fixed with a `frame.isDragging` flag set in
`OnDragStart`/cleared in `OnDragStop`; `Render()` skips the re-anchor step while it's true.
**Confirmed fixed in-game** by the product owner (2026-08-27).

**Bar positioning is now fully confirmed working end-to-end**: create, drag (no bounce,
any time after login), scale slider (no recenter), reload persistence (real data, not
stale defaults), Edit Mode preview. This closes out the position-bug chain from this
session (items 1-4 and 6 above).

**Taint bug — RESOLVED (2026-08-28).** The `ADDON_ACTION_FORBIDDEN`/`SpellStopCasting`
error (via `ToggleGameMenu` on Escape) turned out to reproduce on two independent
triggers, not just Hunt Table interaction as the prior session had narrowed it to: a
plain relog with zero Hunt Table interaction also reproduced it (a `/reload` alone never
did). Root-caused via systematic elimination (whole `Modules/HuntScanner/*` set, then
`WidgetAdapter.lua`'s `hooksecurefunc` hook, then `BarFrame.lua`'s `EditModeManagerFrame`
hook — all ruled out) to `UI/SettingsPanel.lua`'s "Reset All Settings" button registering
its confirmation dialog into Blizzard's shared `_G.StaticPopupDialogs` table. Neither
deferring that registration to `PLAYER_LOGIN` nor removing its `hideOnEscape` field fixed
it — the table write itself was the trigger, not timing or any one field. Fixed by
replacing it with `ensureResetConfirmFrame()`, a small Preydator-owned confirm frame that
never touches any Blizzard global table. Confirmed clean in-game across all three original
repro paths (plain reload, full relog, Hunt Table interaction) plus the rebuilt "Reset All
Settings" flow itself. Full elimination method and reasoning in `issues/rewrite_architecture.md`
Decisions Log item 14, and in memory `preydator-taint-staticpopupdialogs` (reusable
methodology for any future Preydator taint report). The separate minor `ADDON_ACTION_FORBIDDEN`
sighting on a Sound & Alerts dropdown (Section 5, prior sessions) was not specifically
re-tested but is very likely the same now-fixed root cause, since it's the same
`SettingsPanel.lua` file — flag if it recurs. The one-off `ADDON_ACTION_BLOCKED`/
`SetAvatarTexture` (Guild Roster) sighting was never reproduced a second time and stays
unexplained, but is a different addon interaction (Guild Roster Manager) and not currently
blocking anything.

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

- **`UI/EditMode.lua`, `UI/ReportWindow.lua`, `UI/Launcher.lua`** — `UI/BarFrame.lua` and
  `UI/SettingsPanel.lua` are now both built (2026-08-27; `SettingsPanel` not yet in-game
  verified, see Section 2). `bar.accessibility_theme`'s dropdown in `SettingsPanel.lua`
  calls `Core/Settings.lua`'s new `ApplyBarAccessibilityTheme(themeKey)`, which now carries
  the actual ported preset data (`BAR_ACCESSIBILITY_PRESETS`, the deuteranopia/protanopia
  RGBA values from the old code) and bulk-overwrites the six `bar.*_color` fields + the
  border-link flag in one call — this was initially missed while building `SettingsPanel`
  (the dropdown existed but only stored the enum) and was caught and fixed in the same
  session, so it's not a loose end.
- HuntScanner grouping/sorting, achievement-signal matching, reward display — these are
  explicitly Full-scope-only per the architecture doc's Section 15 MVP table, not MVP.
  Not an oversight; don't build them yet without checking scope first.
- The old **`Modules/HuntScanner.lua`** (5045 lines) is still sitting in the tree,
  **only partially superseded now** (the scan/list/select/zone core AND the new
  `Modules/HuntScanner/HuntTablePanel.lua` — icon/name/zone/Accept rows only — now live
  outside it). Grouping, sorting, achievement matching, and reward display logic still
  only exist there. Don't `git rm` it until those are ported.
- **SUPERSEDED, don't trust this bullet's old framing:** Bloody Command / Echo of Predation
  were originally Season 1 mechanics kept dormant (`sound.bloody_command_enabled` defaulted
  `false`). That's no longer current — both have live Season 2 successors, Pack Ambush and
  Exploding Corpse Snakes, fully renamed and defaulting `true` (Decisions Log items 33/34).
  See memory `preydator-season2-mechanic-names` for current state, not
  `preydator-deprecated-mechanics` (also marked superseded).
- **Ambush/Pack-Ambush text on the bar itself is not wired end-to-end.** The settings
  for it exist (`text.ambush_prefix`, `text.ambush_suffix_template`, the Pack Ambush
  equivalents), but `AlertsRuntime.lua` today only plays sounds — it never writes to
  `Core/State.lua`, and `State.lua` has no field for "ambush currently active." `BarFrame`
  therefore has no signal to temporarily swap the label text on. Needs: a new `State`
  field (+ setter, probably with an expiry timestamp so it clears itself), an
  `AlertsRuntime` write when a trigger fires, and a `BarRuntime` branch to surface it in
  the view-model. Not built yet; explicitly descoped from the `UI/BarFrame.lua` work
  rather than guessed at, since the duration/timeout behavior isn't decided.

---

## 5. Next step

**`UI/BarFrame.lua` and `UI/SettingsPanel.lua` are both fully in-game confirmed** as of
2026-08-27 — creation, drag, scale, colors, dropdowns, text editing, accessibility theme,
Advanced actions, reload persistence, and the whole position-bug chain (Sections 2b and 3)
are closed out. `bar.orientation = vertical` was specifically verified live (the original
reason this settings panel got built). The `ADDON_ACTION_FORBIDDEN`/`SpellStopCasting`
taint error is now **resolved** (2026-08-28, see Section 2 bottom) — `SettingsPanel.lua`'s
"Reset All Settings" dialog no longer registers into `_G.StaticPopupDialogs`.

**RESOLVED (2026-08-28): the Hunt Table panel now renders.** A temporary event-name print
at the top of `EventRuntime.HandleEvent` (diagnostic step 1 from the prior plan) confirmed
the trigger events fire, and showed the actual root cause: this NPC's real interaction
flow is `GOSSIP_SHOW` → `PLAYER_INTERACTION_MANAGER_FRAME_SHOW` → `GOSSIP_CLOSED` →
`PLAYER_INTERACTION_MANAGER_FRAME_HIDE`, all within about one frame, *before*
`CovenantMissionFrame` (the actual map) ever opens — gossip closing here is an
intermediate UI transition (gossip → map), not the player leaving. The previous design
treated `GOSSIP_CLOSED`/`..._HIDE` as an immediate "player left" signal
(`hidePanel()`), which bumped the watch's sequence token and cancelled the in-flight
staggered watch from the `SHOW` event a moment earlier — killing the mechanism before any
pass ever got a chance to see the map become visible. Not a rendering bug at all. Fixed in
`Core/Runtime/EventRuntime.lua`: all five lifecycle events (`GOSSIP_SHOW`,
`PLAYER_INTERACTION_MANAGER_FRAME_SHOW`, `GOSSIP_CLOSED`,
`PLAYER_INTERACTION_MANAGER_FRAME_HIDE`, `QUEST_FINISHED`) now trigger the same
re-checking watch (`HUNT_RECHECK_EVENTS`, merged from the old separate watch/hide sets) —
`HuntTableAdapter.IsHuntTableActive()`'s 3-signal check is the single source of truth for
enter/leave, never a raw event name. Also fixed in the same pass: `checkHuntInteraction()`
now rescans on the active→inactive transition too (previously only while staying active,
so leaving via this path left a stale list on screen).

**Follow-on bug found and fixed during live confirmation:** once active, `UPDATE_UI_WIDGET`/
`UPDATE_ALL_UI_WIDGETS` (which fire for *any* UI widget change anywhere in the game) stayed
registered for the full open-ended duration of `huntInteractionActive` — and since "pins
visible" alone can sustain that indefinitely just from leaving the map open, the noisy
widget events kept firing and re-scanning forever even with no further genuine NPC
interaction. Per the product owner, the underlying pin data barely changes (weekly, or on
prey completion), so this was pure waste. Fixed: `beginHuntTableWatch()` now
auto-unregisters the noisy widget events once its bounded window (`WATCH_DELAYS`' last
entry, ~10s) concludes; a fresh `HUNT_RECHECK_EVENTS` event re-arms both the watch and
noisy-event listening from scratch. Confirmed live: only a single one-shot
`UPDATE_UI_WIDGET` now, not a continuous loop. Panel visibility itself is unaffected by
this — it's driven by `huntInteractionActive`/the last fetched list, not by the listener.

Full reasoning in `issues/rewrite_architecture.md` Decisions Log item 15.

**"Scanning and displaying" phase — CONFIRMED COMPLETE (2026-08-28).** Full checklist
verified live by the product owner: hunt list populates correctly, icon-per-difficulty
accuracy is correct across all quests, `hunt.panel_side`/`width`/`height`/`scale`/
`font_size` all react live from `SettingsPanel.lua` (including the new
`hunt.preview_enabled` toggle, Decisions Log item 16), and Accept → abandon → accept a new
hunt all work with no issues.

Also built this session, not originally planned: a **"Preview Hunt Panel" checkbox**
(Settings → Preydator → Hunt Scanner) that force-shows the real panel — docked beside the
Settings window while it's open, using real cached hunts or 3 placeholder rows — so
layout/scale/font changes are visible without leaving Settings. Auto-unchecks itself when
Settings closes (reversed from an initial "stays on" design after live testing showed that
wasn't actually wanted). See Decisions Log item 16 for the full design history.

**"Zones" phase — CONFIRMED COMPLETE (2026-08-28).** The queued "Quel'Thalas" issue was
root-caused, not just patched: `C_TaskQuest.GetQuestZoneID` returns the broad
continent/region map (`2561`, "Quel'Thalas") for these Hunt quests rather than the
specific leaf zone the pin — and the player, once there — is actually in (e.g. `2512`,
"The Coiled Isle"). Fixed in `HuntScannerRuntime.RefreshFromAdapter()` by making the
pin-coordinate-based lookup (`MapContextAdapter.GetMapInfoAtPosition`) the primary zone
source instead of the fallback, with quest metadata (`GetQuestZoneID`) only used when
position data isn't available — resolves 12 of 15 live-tested hunts to their specific
zone now, no regression on the other 3. For those remaining 3, live testing proved
*both* signals (quest metadata **and** direct position lookup) independently agree on
`2561` — Blizzard's own API has no more specific zone for those particular hunts, so this
isn't a bug to keep chasing; a hardcoded per-quest override to force something more
specific would reintroduce the exact stale-mapping pattern `CLAUDE.md` Section 4 bans.
Full reasoning in `issues/rewrite_architecture.md` Decisions Log item 18.

**"Rewards" phase — CONFIRMED COMPLETE (2026-08-28), including real item/container icons.**
Two safe data sources feed `HuntTablePanel.lua`'s reward icons (icon + quantity, hover for
full name — new, the old codebase never had per-icon hover): `QuestApiAdapter.GetQuestRewardSummary`
(currency/money/XP, via `QuestUtils_AddQuestRewardsToTooltip` against the real shared
`GameTooltip` — a custom-built scratch tooltip crashes on container rewards) as the
baseline, and `HuntTableAdapter.GetRewardWidgets` (real icon/name/quantity for *every*
reward including the actual chest/bag, via `Blizzard`'s own `.rewardType` field —
`"currency"` vs `"item"` — no name-guessing) as the preferred source once available.
The old codebase's own comments flagged this exact widget-introspection technique as a
repeat taint offender ("has repeatedly tainted Blizzard tooltip/money arithmetic paths");
confirmed live, twice, that a strictly *read-only* extraction (`type()`/`GetText()`/
`GetTexture()` only, zero arithmetic on scraped values) does not reproduce it — first for
a single peek, then again for 3 rapid back-to-back peeks (the real per-difficulty caching
pattern, `HuntScannerRuntime.rewardWidgetsByDifficulty` — one peek per difficulty covers
all 15 offered hunts, since rewards are identical within a difficulty and only rotate
every 2 completions/week per the product owner). Full reasoning, including the exact field
names confirmed for this client build, in `issues/rewrite_architecture.md` Decisions Log
item 19 and memory `preydator-safe-widget-introspection`.

`hunt.reward_display_style`'s three catalog values (`icon_inline`/`icon_count`/`text_only`)
were **not yet actually differentiated** as of this point in the session — **closed out
2026-09-02, see Decisions Log item 52** for the final design (confirmed with the product
owner rather than guessed, since this setting is new to the rewrite with no old-addon
feature to port).

**Achievements moved to Full-scope (2026-08-28), not a scope regret — a real testing
constraint.** The product owner can't currently test achievement progress on this account
(would need a different account/region/level, e.g. activating a family member's account).
Matches Section 15's existing Full-scope classification anyway, so this isn't a deviation
from the architecture, just confirms the phase order in practice.

**Next MVP milestone: live end-to-end Prey Hunt tracking** (accept → bar shows/updates
stage+percent progress → ambush sound on chat trigger → zone-based show/hide → turn-in
clears state) — the product owner's own call for what comes next, and genuinely
unconfirmed territory: nothing this session (or apparently since the 2026-08-25 initial
build pass) has live-tested `PreyContextRuntime`/`BarRuntime`/`SoundsRuntime` against a
real active hunt. Everything tested so far was either UI mechanics (drag/scale/Edit Mode,
2026-08-27) or Hunt Table scanning/accepting (this session) — not "is the bar/sound
correct while actually doing a hunt."

**Found and fixed before/during that test (2026-08-28): two settings that visibly did
nothing, same root cause shape.** `general.only_show_in_prey_zone` (bar didn't appear in
the correct zone) and `general.disable_default_prey_icon` (Blizzard's own prey icon stayed
visible) — both traced to `SoundsRuntime.PlayStageSound`/`WidgetAdapter.SuppressDefaultPreyIcon`
being fully built (from the 2026-08-25 pass) but never actually *called* from anywhere.
`PreyContextRuntime.RefreshPreyContext()` now calls both on every refresh (both
self-guard/are idempotent, safe every tick); icon suppression only applies while a hunt is
actively tracked, so it correctly un-suppresses when tracking stops. Ambush sound was
already correctly wired (`AlertsRuntime` → `SoundsRuntime.PlayAmbushSound`); Bloody
Command/Echo of Predation remain intentionally dormant (Decisions Log item 5). Neither fix
has been live-confirmed yet (found via code audit while investigating the zone-bar report,
not yet re-tested in-game) — that's the immediate next step.

**Built the same session: `Core/SlashCommands.lua`, a `/pd inspect|qinspect|hinspect|pinspect [bs]`
diagnostic command** (matches the old codebase's exact convention, `bs` = also dispatch to
BugSack via `geterrorhandler()`, the pattern validated during the rewards phase). Reuses
`DiagnosticsRuntime`'s `BuildGeneralInspectReport`/`BuildProgressInspectReport`/
`BuildQuestInspectReport` (built 2026-08-25, never wired to a command until now) plus a new
`BuildHuntInspectReport` (Hunt Table active-state, raw pin count vs. scanned list with
each hunt's zone/reward summary, and `EventRuntime`'s otherwise-invisible private
interaction-tracking state via a new `GetHuntTrackingDebugState()` getter). `ainspect`
(achievement) not built — Full-scope, not testable on this account right now. Full
reasoning in `issues/rewrite_architecture.md` Decisions Log item 20.

**Live Prey Hunt stage/progress tracking — root-caused and fixed (2026-08-28), through two
rounds.** Round 1: `/pd wdebug` found the widget hook never installed
(`mixinHooked=false` despite the mixin existing) because the one-shot `ADDON_LOADED`
trigger ran before it was ready; `WidgetAdapter.GetWidgetStage()` now retries every call.
Also: ambush detection redesigned from a real live chat log to key off Blizzard's own
"Ambushed!" system message instead of guessing prey dialogue phrasing (which both missed
the real ambush and would have false-matched an unrelated NPC's line in the same log); the
quest's "Hunt your Prey" objective reaching `finished` now also force-confirms the final
stage as a widget-independent safety net; `sound.alert_cooldown_seconds` exposed in
Settings for the first time, 30→60s default. Full reasoning in Decisions Log item 21.

**Round 2 (still 2026-08-28): the bar still didn't update without a zone change.**
`Setup` turned out to essentially never fire this session at all (`widgetSnapshot` stayed
`nil` even with `mixinHooked=true`) — a new deep field dump added to `/pd wdebug` found
`progressState`/`tooltip` sitting as plain, always-current fields directly on the live
widget frame, no `Setup` call needed at all. `WidgetAdapter.GetWidgetStage()` now reads
these live off the frame as the preferred source (confirmed live: data is now always
accurate on demand) — but the bar still needed something to actually call
`RefreshPreyContext()` more often than incidental context events did. Rejected registering
`UPDATE_UI_WIDGET`/`UPDATE_ALL_UI_WIDGETS` for the whole tracked-hunt duration (unbounded,
unlike Hunt Table's already-fixed bounded watch) in favor of a plain, bounded
`C_Timer.NewTicker` (2s interval, `EventRuntime.lua`) that starts/stops with whether a hunt
is actively tracked. Full reasoning in Decisions Log item 22.

**CONFIRMED LIVE (2026-08-28): the round-2 fix worked — full stage 1→2→3→4 sequence
tracked correctly with no zone change needed, sounds played on each transition, bar hit
100%/stage 4 at the finish. The live Prey Hunt progress-tracking MVP milestone is
functionally complete.** One more gap found in the same test and fixed: an ambush leading
directly into the stage 3→4 transition played no sound, because the ambush gate required
`stage < 4` and the polling ticker had already raced ahead to stage 4 by the time the chat
message was processed. Removed the stage upper bound entirely (the "Ambushed!" system
message is already authoritative on its own) rather than trying to tune the race. Not yet
re-tested live.

**Two more found live right after, both fixed:**
1. A lingering glow/shine "aura" stayed visible on the default prey icon even after
   suppression hid the icon itself. Checked the old codebase's `main` branch for its
   suppression logic — it explicitly cancelled a separate `effectController` system;
   `WidgetAdapter.lua`'s `stopFrameAnimations` now does the same (via the widget's own
   `ClearEffects()` method, confirmed present) plus stops this client's actual animation
   sub-fields (the old code's hardcoded field names didn't match current structure).
2. Stage-transition sounds were replaying on every `/reload` for a hunt already past
   stage 1, regardless of current location — the previously-parked tradeoff (Decisions Log
   item 21) got resolved in favor of fixing it, since it caused a real, confusing symptom
   live. `SoundsRuntime`'s first-observation-per-quest-per-session now baselines silently
   instead of playing.

Also added **`/pd sinspect [bs]`** (product owner's request): shows the last 12 sound
play attempts (trigger, played/blocked, and why if blocked) — `SoundsRuntime` now records
every `playPath` call, not just successful ones.

**`sinspect` immediately proved its worth: caught a real ambush with zero sound.** Live log
showed `Ambushed!` in chat but `sinspect` showed *zero* ambush attempts at all (not even a
blocked one) — meaning `AlertsRuntime`'s `event == "CHAT_MSG_SYSTEM"` gate itself rejected
it before ever checking the message. "Ambushed!" is plausibly delivered as a different
event type (not confirmed which). Broadening to check every `CHAT_TRIGGER_EVENTS` type
would have reintroduced the exact false-positive already fixed once (Astalor Bloodsworn's
own "I suspect an ambush" dialogue) — fixed properly instead by requiring an *empty
sender* (no NPC-name attribution) alongside the "ambush" text match, which
distinguishes the real notification from any NPC's own dialogue regardless of event type.
Also closed the diagnostic blind spot that let this slip past `sinspect` in the first
place: `PlayAmbushSound`/`PlayBloodyCommandSound` now record a "blocked" entry even when
their own `_enabled` setting check stops them before reaching `playPath`.

**Ambush detection redesigned entirely (2026-08-28) — chat-message matching abandoned,
replaced with nameplate-based detection.** The sender-based chat fix above still didn't
work when re-tested live, and the wide-net diagnostic that followed it (a dozen extra
`CHAT_MSG_*` types plus `RaidNotice_AddMessage`/`UIErrorsFrame:AddMessage` hooks) also
caught nothing against a confirmed real ambush — three chat-based attempts in a row,
conclusively no chat/banner API reliably exposes "Ambushed!" in current content. Product
owner proposed the fix: detect the prey mob's own presence directly (RareScanner/
SilverDragon-style) instead of waiting on a message. `EventRuntime.lua` now registers
`NAME_PLATE_UNIT_ADDED` and forwards to a new `AlertsRuntime.HandleNameplateEvent(unit)`,
which compares the newly-visible nameplate's name against `state.preyTargetName` and plays
the ambush sound on a match. The old chat-matching function and the entire TEMP wide-net
block are removed. Full reasoning in Decisions Log item 30. **Not yet re-tested live** —
needs the product owner to trigger a real ambush and confirm the sound plays.

**Icon flash/pulse fix re-done (2026-08-28) — the previous fix (hooking
`PlayGainProgressAnim`) proved incomplete when re-tested live.** The icon still pulsed on
every progress gain. Root cause, more precisely this time: Blizzard's generic UIWidget
container can also show the icon through its own layout/pooling code, entirely separate
from the PreyHunt-specific mixin method that was hooked. Rather than chasing individual
Blizzard methods one at a time again, `WidgetAdapter.lua` now hooks the icon frame's own
`OnShow` script directly (`HookScript("OnShow", ...)`, a standard taint-safe pattern) —
this catches the icon becoming visible regardless of which code path caused it. The now-
redundant `PlayGainProgressAnim` hook was removed (single-source-of-truth, `OnShow` is a
strict superset of what it caught). **Current suppression behavior is still hardcoded, not
configurable** — a future toggle for users who want to see the flash is still a real
Full-scope follow-up, not built now. Full reasoning in Decisions Log item 31. **Not yet
re-tested live.**

**Also wired live (2026-08-28): `HuntScannerRuntime.OnPreyQuestEnded` was never actually
called from anywhere.** Product owner completed two Normal-difficulty hunts and correctly
expected the cached reward data to refresh (rewards can rotate on completion). Wired via
`EventRuntime.lua`'s `QUEST_TURNED_IN` dispatch, gated on `PreyQuestData`'s static table to
confirm it was a real Prey Hunt. Now clears the *entire* `rewardWidgetsByDifficulty` cache
(all 3 difficulties, not just the completed one) on any completion — deliberately not
trying to pin down which single difficulty changed, per the product owner's own "small
cost, just always do it" call. Full reasoning in Decisions Log item 27. Not yet
re-tested live.

**Also fixed live (2026-08-28): the bar was not appearing on The Coiled Isle for an active
Nightmare hunt the player was genuinely standing in.** Product owner correctly diagnosed
this themselves from `/pd inspect`/`/pd qinspect` output: `inPreyZone=false` even though
`isOnMap=true`, because `PreyContextRuntime`'s zone pre-filter (Section 8) was
short-circuiting to false and never reaching the authoritative check at all. Root cause:
the pre-filter's `expectedZone ~= playerMapID` was a raw equality check, but
`expectedZoneMapID` for this hunt had resolved to the broad continent map (2561,
Quel'Thalas — `HuntScannerRuntime`'s `GetQuestZoneID` fallback path) while `playerMapID`
was the specific leaf zone nested inside it (2512, The Coiled Isle) — always a mismatch by
raw equality even though the player was correctly in the zone. Fixed by adding
`MapContextAdapter.DoesMapContain(ancestorMapID, mapID)` (walks the `parentMapID` chain up
to 10 hops) and only short-circuiting the pre-filter to false when the maps are both
unequal *and* not nested.

**Re-tested live (2026-08-28) — found the same bug in the opposite direction, on a
different hunt (Janoa the Fang, Voidstorm).** This time `expectedZoneMapID=2479` (from the
Hunt Table pin's own position-based lookup, resolving to a specific named sub-area) was
*narrower* than `playerMapID=2405` (Voidstorm, the broader zone `GetBestMapForUnit`
reports) — the reverse of the Coiled Isle case, so the one-directional `DoesMapContain`
fix didn't cover it. This also silently broke the brand-new nameplate ambush detection
(below), since it also gates on `inPreyZone`. Fixed with a symmetric
`MapContextAdapter.AreMapsRelated(mapIDA, mapIDB)` (checks `DoesMapContain` both ways),
now used in place of the one-directional check. Full reasoning in Decisions Log items 29
and 32. **Not yet re-tested live.**

**A real ambush confirmed the nameplate sound fires (2026-08-28), which surfaced a design
problem, not a bug.** `/pd sinspect` showed 3 `trigger=ambush` attempts within ~41 seconds
(2 played, 1 correctly blocked by the 35s cooldown) — the cooldown gate working as
designed. But the product owner recognized the sound that fired was triggered by "Pack
Hunter" (a Season 2 mob, confirmed to replace **Bloody Command**, not Echo of Predation —
correcting an earlier same-session guess), not the hunt's own prey — and found it wrong to
route a mob unrelated to the true ambush mechanic through that same sound.

**Built a proper Mob Scanner instead of continuing to patch the ambush path (2026-08-28).**
Per the product owner's direction: Season 1's Bloody Command and Echo of Predation are
**renamed** (not kept alongside) to their real Season 2 identities — **Pack Ambush**
(mobs: Pack Scout, Pack Hunter) and **Exploding Corpse Snakes** (mob: Venom-Bloated
Python) — each gets its own dedicated, player-configurable sound
(`sound.pack_ambush_enabled`/`_path`, new `sound.exploding_corpse_snakes_enabled`/`_path`),
and both are detected the same nameplate-based way as the true ambush. `AlertsRuntime.HandleNameplateEvent`
now runs two independent checks per nameplate: the true-ambush check, and a new Mob Scanner
check with its own rule specified directly by the product owner — gated on
`QuestApiAdapter.GetQuestIsOnMap()` queried directly (bypassing the bar's `inPreyZone`
pre-filter entirely, sidestepping the two zone-hierarchy bugs above), and allowed for the
hunt's **entire duration**, not gated to specific stages ("unlike the ambushes they can
trigger until we are all the way done"). Not difficulty-gated either — the old Bloody
Command's nightmare-only restriction wasn't confirmed to carry over, and under-triggering
is worse than over-triggering here.

**A third zone false negative found immediately after (2026-08-28, Zul'Aman) — this time it
was the true-ambush sound itself, not the bar.** `isOnMap=True` and a confirmed real ambush
(stage genuinely advanced 1→2), but no sound — because the true-ambush check still gated on
`state.inPreyZone` (the same pre-filtered value Decisions 29/32 already patched twice for
the bar), not on `GetQuestIsOnMap()` directly like the Mob Scanner already does. Fixed the
same way: the true-ambush check now queries `GetQuestIsOnMap()` directly too. Full reasoning
in Decisions Log item 35.

**Resolved (2026-08-28): the bar now trusts isOnMap directly too, same as both sound
triggers.** Asked the product owner first, since the pre-rewrite codebase had a documented
opposite-direction bug (`isOnMap` true from broad quest-log membership alone, no real zone
match — a Zul'Aman hunt's bar showing while standing in Eversong Woods, the same zone
involved in this session's own bug). Product owner's only concern was whether calling
`GetQuestIsOnMap()` directly, every refresh, would be resource-intensive — confirmed it's
two lightweight pcall-guarded quest-log lookups, actually cheaper than the up-to-10-hop
`parentMapID` walk the removed pre-filter did. `PreyContextRuntime.RefreshPreyContext()`'s
zone-gating step no longer reads `expectedZoneMapID`/`playerMapID` at all —
`MapContextAdapter.DoesMapContain`/`AreMapsRelated` are now dead code and were deleted.
`expectedZoneMapID` is still captured/stored for Hunt Table zone display and diagnostics,
just no longer used as an `inPreyZone` gate. Accepted tradeoff: if the old
Eversong-Woods-style false positive resurfaces, the fix is scoped to one function. Full
reasoning in Decisions Log item 36. **Not yet re-tested live.**

**Confirmed working end-to-end (2026-08-28) except one new bug: the default prey icon
reappears with stale progress on hunt turn-in.** Product owner confirmed everything from
this session's fixes checked out from start to finish, then found this: `general.disable_default_prey_icon`
correctly hides the icon during a hunt, but turning the hunt in makes it visibly reappear
showing its last progress state — even though Blizzard's own icon is never shown at all
without an active hunt (product owner's own domain knowledge). Root cause: `PreyContextRuntime`'s
two early-return branches were explicitly un-suppressing (calling `WidgetAdapter`'s
un-suppress path, which itself calls `frame:Show()`) every time a hunt ended, trying to
"restore" an icon that never needed restoring. Fixed by removing both un-suppress call
sites — suppression is now only ever touched while a hunt is actively tracked. Full
reasoning in Decisions Log item 37. **Not yet re-tested live.**

**Restricted-instance audit, requested explicitly by the product owner (2026-08-28): "no
part of Prey is to function in any instanced zones."** Full audit found this already
comprehensively covered, not a gap — `PreyContextRuntime.RefreshPreyContext()` (master
gate), `EventRuntime`'s FAIL-CLOSED dispatch step (re-checks independently before every
event, including nameplate events), `EventRuntime.checkHuntInteraction()` (blocks Hunt
Table scanning, the taint-sensitive part), `AlertsRuntime.HandleNameplateEvent` (double
-checks directly), and `SoundsRuntime.playPath()` (final gate before any sound, regardless
of caller). No code changes needed — formalized as an explicit MVP acceptance line in
Section 15, with the full audit written up inline in Section 9 ("Fail-Closed Behavior in
Restricted Instances").

**Continuing toward MVP (2026-08-28): built `UI/Launcher.lua`, descoped `UI/EditMode.lua`
and `UI/ReportWindow.lua`.** Before porting either unbuilt MVP-table item wholesale, audited
what they'd actually add: `EditMode.lua`'s core function (auto-unlock + drag the bar during
Blizzard Edit Mode) turned out to already be built into `UI/BarFrame.lua`
(`EnableMouse((not lockBar) or editModeActive)`, from earlier bar work); its remaining
piece — a floating quick-settings mini-window — is a straight duplicate of
`UI/SettingsPanel.lua`'s existing General/Bar Display categories. `ReportWindow.lua` is
superseded by the `/pd` chat+BugSack flow, used successfully all session. Both descoped
from MVP (moved to Full-scope if still wanted) rather than built redundantly.
`UI/Launcher.lua` **was** built — nothing already covers a minimap/Addon Compartment entry
point: LibDataBroker/LibDBIcon optional integration (OptionalDeps, not bundled) with a
custom-drawn fallback button, left-click opens Settings (`SettingsPanel.OpenSettings()`,
new public function, shared with `/preydator`), right-click prints the general inspect
report to chat. New settings `general.minimap_hidden`/`minimap_angle`, with old
`currencyMinimapButton`/`currencyMinimapAngle` migrated forward. Full reasoning in
Decisions Log item 38.

**CONFIRMED (2026-08-28): the minimap button works live** — left-click opens Settings,
right-click prints the quick inspect report, both as built. Product owner also confirmed
`UI/EditMode.lua`'s descope directly: the desired behavior really is just "drag the bar
during Edit Mode, then return to whatever the lock checkbox says" — already fully covered
by `UI/BarFrame.lua`, no floating settings window wanted at all, not even later as
Full-scope. Both Section 15 rows are closed out for good. Full reasoning in Decisions Log
item 39.

**A real ambush miss (2026-08-28, the actual prey objective) — root cause still unknown,
but the diagnostic blind spot around it is fixed.** `/pd sinspect` showed zero entries at
all for the missed attempt (found the same mob again shortly after and it worked that
time). Zero entries meant `SoundsRuntime.PlayAmbushSound()` was never even called —
`AlertsRuntime.HandleNameplateEvent`'s own gates (polling active, restricted instance,
active quest, sounds enabled, `isOnMap`) all ran *before* the prey-name match check and
none of them recorded anything when they blocked, the same blind spot Decision 19 already
fixed once for `SoundsRuntime`'s own internal gates. Product owner theorized it might be
"old chat wiring" reacting differently since the mob spoke in chat the first time but not
the second — checked directly (grepped every active file for `CHAT_MSG`/chat event
registration) and confirmed zero live chat listeners remain anywhere, so it isn't literally
that. **Fixed the blind spot, not yet the underlying cause:** reordered the function so the
name-match check happens first (unrelated nameplates still bail with no logging, so this
doesn't spam the history), then every gate that can block a *confirmed* match now logs a
specific reason via a new `SoundsRuntime.RecordBlockedAttempt(key, detail)`. Next real
occurrence, `/pd sinspect` will show exactly which gate stopped it instead of nothing at
all — including whether the chat-dialogue correlation the product owner noticed lines up
with a real `isOnMap`/quest-state hiccup, rather than guessing further. Full reasoning in
Decisions Log item 40. **Not yet re-tested live.**

**Built an opt-in nameplate trace so the product owner can record and share raw data, not
just wait for another miss (2026-08-28).** `/pd sinspect` only ever sees actual
`PlayXSound` attempts — silent if a nameplate never even reached a match (e.g. if the
`NAME_PLATE_UNIT_ADDED` event never fired at all for the prey, still not ruled out).
Wired up `debug.pack_ambush_verbose` (existed as a Settings checkbox since the Decision 34
rename, never actually connected to anything) into a real 50-entry trace: every nameplate
seen while a hunt is active, with name/timestamp/match-status, readable via new
`/pd ninspect [bs]`. Off by default — the product owner turns it on, goes and finds the
mob, then dumps the trace. Full reasoning in Decisions Log item 41.

**ROOT CAUSE FOUND (2026-08-28), using the nameplate trace above.** The product owner ran
`/pd ninspect` across a couple of hunts and spotted it directly: a `name=Unknown | no
match` entry for the exact moment the real prey's nameplate first appeared, followed later
by the same mob's nameplate correctly matching once its real name had resolved. This is a
well-documented WoW timing quirk — `NAME_PLATE_UNIT_ADDED` can fire before the client has
cached a unit's name yet, most commonly for a mob that just became visible/spawned (exactly
what an ambush is). The one-shot name comparison happened to run during that window and
never got a second chance. Not chat, not old wiring, not zone/isOnMap — a pure client-side
name-caching race, invisible without the raw trace built specifically because `/pd
sinspect` alone couldn't see this class of miss. **Fix:** `AlertsRuntime.lua` now tracks
units seen as `"Unknown"` (keyed by unit token + `UnitGUID`, 30s bounded expiry) and
listens for Blizzard's own `UNIT_NAME_UPDATE` event to recheck once the name resolves,
GUID-verified since nameplate tokens are pooled/reused. This also retroactively explains
why finding the mob a second time always "just worked" throughout this whole session's
debugging saga — the second encounter's name had already resolved by then, disguising the
timing race as something else every previous time. Full reasoning in Decisions Log item
42.

**CONFIRMED LIVE (2026-08-28): two full Prey Hunts, start to finish, no errors.** All
sounds working (ambush, Pack Ambush, Exploding Corpse Snakes), nameplate scanning
issue-free, and the Hunt Table's reward cache updates correctly after completion (the
Decisions Log item 27 fix, confirmed live for the first time). The prey-icon-on-turn-in fix
(Decision 37) is also now confirmed — not seen again across 6 Prey Hunts since it landed.
**Every fix from this session is now live-confirmed. No known open bugs.**

The now-fully-replaced chat-text detection path (`isBloodyCommandMessage`, `CHAT_TRIGGER_EVENTS`,
`HandleChatEvent`) is deleted, not left dormant — along with `EventRuntime.lua`'s entire
`CHAT_EVENTS` dispatch category, since nothing consumed it anymore. Settings renamed
end-to-end (`SettingsStore`/`SettingsRuntime`/`UI/SettingsPanel.lua`), including updating
the old-schema migration path so an upgrading `main`-branch user's real Bloody Command
preference carries forward into the new Pack Ambush settings instead of being dropped.
Full reasoning in Decisions Log item 34. **Not yet re-tested live.**

**One item intentionally left unfixed, needs the product owner's call:**
`SoundsRuntime`'s stage-sound anti-replay tracking is session-lifetime only, so a hunt
already past stage 1 replays that stage's sound on every `/reload` — fixing it means the
very first stage of a genuinely *new* hunt would go silent instead (can't distinguish the
two cases with current state). Parked pending a decision on which tradeoff is preferred.

**Update (2026-09-02): every item in this paragraph except the bar items is now closed.**
HuntScanner grouping/sorting shipped and was live-confirmed (Decisions Log items 48-49,
Section 5c). Reward ordering and `hunt.reward_display_style` differentiation both shipped
the same day as this update (Decisions Log item 52) — the Hunt Panel itself has no known
open items left except achievement-earned live-testing (Section 5b/5c), which is blocked on
the product owner's character reaching that stage, not on code. Still genuinely open,
unrelated to the Hunt Panel: deciding `bar.show_spark_line`'s fate (Decisions Log item 7)
and the ambush/Pack-Ambush bar-text wiring (`text.ambush_prefix`/`pack_ambush_prefix`
settings exist but `BarRuntime` never reads them). `UI/EditMode.lua` is permanently closed
(Decisions Log item 39, not a deferred item), and `UI/Launcher.lua` is built and confirmed
working — neither belongs on this open-items list anymore.

**Four more Full-scope items logged 2026-08-28 (product owner's explicit choice: log now,
build later, not this session):** sound amplification (modeled on the "Better Fishing"
addon, exact mechanism not yet researched); slider value-number display in
`UI/SettingsPanel.lua` (every slider currently shows only its min/max endpoints, not the
current value); custom sound files — a real "Add File"/"Remove File" UI (the backing
`sound.custom_file_names` data/dropdown plumbing already exists, just no way to add to it;
product owner pointed at the old codebase as the reference to port); and the Text & Labels
category's two-column layout (currently one long single-column scroll — product owner
provided both a screenshot of the problem and a mockup of the fix: pair each Prefix field
with its Label field on the same row instead of stacking them). Full detail, including the
mockup's exact layout, in Decisions Log item 43 — that item is the one to read before
picking any of these four up.

See `issues/rewrite_architecture.md` Decisions Log items 6-19 for the full design
reasoning (accessibility-theme correction and fix, `BarFrame`'s fresh-design rationale, the
label-mode/lock-gate/Edit-Mode/position-schema decisions, `SettingsPanel`'s
native-API-plus-hybrid-canvas design, the critical PLAYER_LOGIN-deferral rule for any
future file with file-scope self-init, `HuntTablePanel`'s MVP-scope/Subscribe/auto-dock
decisions, the "modern appearance"/vertical-orientation scope calls, the
`StaticPopupDialogs` taint fix, the Hunt Table interaction-tracking root cause/fix, the
`hunt.preview_enabled` Settings-preview toggle, the zone-resolution root cause/fix, and the
reward display build including the taint-safety verification for real item/container
icons), and `issues/bar_rendering_research.md` for the old-code research several of those
decisions were based on.

---

## 5b. Achievement signals built (2026-09-01) — the account-level blocker cleared

The product owner now has a live hunt with a completable achievement, unblocking the one
Section 15 full-scope item that had been explicitly parked for lack of a way to test it
(see the "Achievements moved to Full-scope" note in Section 5 above). Built this session,
per Decisions Log item 44 in `issues/rewrite_architecture.md` (full design reasoning
there):

- New `Core/Adapters/AchievementAdapter.lua` — sole Blizzard API boundary for
  `GetAchievementInfo`/`GetAchievementCriteriaInfoByID`.
- `HuntScannerRuntime.lua` resolves each hunt's still-needed achievements from
  `PreyQuestData`'s existing tables, session-memoized per questID, wiped wholesale on a new
  `ACHIEVEMENT_EARNED` event (`EventRuntime.lua`).
- Gating is whole-achievement completion only (not per-criteria) — ported faithfully from
  the old codebase's own live-validated behavior, not redesigned.
- `HuntTablePanel.lua` renders an icon+count badge directly above each row's Accept button
  (the product owner pointed out that space was empty) with a hover tooltip listing names.
- New `hunt.achievement_signals_enabled` checkbox in `UI/SettingsPanel.lua`'s Hunt Scanner
  category (the setting itself already existed from earlier scaffolding).
- `luacheck`: 0 warnings/0 errors across all 5 touched/new files
  (`Core/Adapters/AchievementAdapter.lua`, `Modules/HuntScanner/HuntScannerRuntime.lua`,
  `Core/Runtime/EventRuntime.lua`, `Modules/HuntScanner/HuntTablePanel.lua`,
  `UI/SettingsPanel.lua`). No warning-561 concern anywhere (`Preydator.lua` bootstrap is
  still ~50 lines).

**First live test (2026-09-01) — achievement detection itself confirmed correct, but the
badge showed on every hunt of a difficulty, including already-killed targets.** Root cause
and fix in Decisions Log item 45: gating was whole-achievement completion only, but the
Mode I/II/III meta achievements each cover ~30 targets, so they stay incomplete (badge
showing everywhere) until literally all are done. `HuntScannerRuntime.computeAchievementNeeds`
now also gates on this hunt's own per-criteria completion (new `AchievementAdapter.IsCriteriaComplete`)
-- a hunt only counts as needed when both the achievement overall AND this specific
target's own criterion are incomplete. Same round: `ACHIEVEMENT_ICON_SIZE` doubled
(16→32, icon only, not the count text) per the product owner's request, and
`/pd hinspect` now lists each hunt's `achievementNeeds` (count + one line per achievement
ID/name) plus the relevant settings, for future troubleshooting. **Not yet re-tested
live** -- next step is confirming the badge now only appears on hunts whose specific
target is still outstanding, and that the enlarged icon looks right.

**Second round (2026-09-01, same day): `/pd hinspect`'s new output immediately proved its
worth.** Product owner pasted a full dump — confirmed Decision 45's fix works correctly for
the ~90 hunts `PreyQuestData` already maps (only the one genuinely outstanding target,
Crusader Luxia Maxwell/Normal, showed a need; everything else correctly showed 0). But 4
Nightmare hunts (questIDs 95021-95024, not in `PreyQuestData` at all -- new content added
since that table was last updated) still showed needed for Nightmare Mode III despite those
specific targets already being killed. Cause: no table entry means no `criteriaID`, so the
per-criteria check had nothing to verify against and silently fell back to
whole-achievement-only gating for just these 4. Fixed (Decisions Log item 46):
`computeAchievementNeeds`'s Mode I/II/III bucket now requires a known `criteriaID` before
running at all -- unverifiable is now treated as "don't show," not "guess needed." Also
tightened the achievement icon-to-count gap (`-2` → `-1`) per feedback. **Follow-up, not
done now:** `PreyQuestData.lua` is likely missing entries for these 4 (and maybe other)
new questIDs -- adding them would let the badge cover these hunts precisely instead of
skipping them, whenever the product owner wants to source the real criteriaIDs.

**CONFIRMED LIVE (2026-09-01): achievement badges now work correctly on the real Hunt
Table.** Product owner confirmed the per-criteria fixes (Decisions Log items 45/46)
resolved the false positives. Follow-up requested and built same session: dropped the
in-row count text, icon-only now, count + achievement names moved entirely to the hover
tooltip (title line reads "Achievements Needed (N)"). Full reasoning in Decisions Log item
47.

**Marked tentatively complete (2026-09-01), not fully closed.** The product owner is
testing on their only account with an in-progress achievement, so the one thing still
unverified is the `ACHIEVEMENT_EARNED` cache-wipe path -- does the badge actually disappear
the instant the achievement is earned -- since that's a single, non-repeatable real-world
event they can't safely retry if it doesn't work (a second test account is in progress for
exactly this). Everything else (badge display, gating correctness, tooltip, icon-only
layout) is live-confirmed. Revisit this one path once the second account is ready, or if a
stale badge is ever reported after a real completion. The only other known gap is the 4
unmapped Nightmare questIDs (95021-95024) noted above -- a `PreyQuestData.lua` data
task, not a bug.

## 5c. HuntScanner grouping/sorting built (2026-09-01) — full collapsible headers

Next item picked off the open-items list (Section 5's "HuntScanner grouping/sorting...
remain open Full-scope items"). Product owner chose the highest-effort of three offered
options: full collapsible group headers matching the old addon's exact feature, not just
sort-and-cluster or static headers. Full design/porting reasoning in Decisions Log item 48
of `issues/rewrite_architecture.md`; short version:

- `HuntScannerRuntime.GetGroupedDisplayList()` (new) is the sole owner of grouping/sorting,
  faithfully porting the old `Modules/HuntScanner.lua` algorithm rather than redesigning it
  -- including preserving the old code's quirk that group *order* (Nightmare, then Hard,
  then Normal for difficulty; alphabetical for zone) never actually read
  `hunt.sort_direction`, only the hunts *within* a group do.
- New `HuntScannerRuntime.ToggleGroupCollapsed(groupKey)` persists through
  `Settings.Set("hunt.collapsed_groups", ...)` (new setting, migrated from the old
  `huntScannerCollapsedGroups` key).
- `HuntTablePanel.lua` gained a shorter header-row style (24px vs. a real hunt row's 56px)
  and switched from fixed `index * ROW_HEIGHT` row positions to an accumulated `yOffset`,
  since row height is no longer uniform. `MAX_ROWS` bumped 20→24 for the extra header rows.
- The `hunt.preview_enabled` preview path deliberately stays flat/ungrouped.
- `luacheck`: 0 warnings/0 errors across `HuntScannerRuntime.lua`, `HuntTablePanel.lua`,
  `SettingsStore.lua`, `SettingsRuntime.lua`.

**Not yet tested live** -- next step is confirming in-game that both grouping modes
(difficulty/zone), all three sort fields/directions, and collapse/expand (including that
it persists across a reload) work as expected.

**Follow-up, same day: on-panel controls + zone naming fixes (Decisions Log item 49).**
Product owner didn't want to need Settings open just to change grouping/sorting -- added
three cycle-through buttons directly on the Hunt Table panel (Group/Sort/Direction), all
writing through the same `hunt.group_by`/`sort_by`/`sort_direction` settings
`HuntScannerRuntime` already reads, so they and Settings stay in sync automatically.
Separately: mapID 2561 was displaying Blizzard's own name "Quel'Thalas" (meaningless to
most players) -- now shows "The Coiled Isle" via a new, single-source-of-truth
`HuntScannerRuntime.ResolveZoneDisplayName()` that both the panel and `/pd hinspect` route
through. Zone sorting/grouping also now ignores a leading "The " when deciding order (but
never in the displayed text) -- "The Coiled Isle" sorts under C, not T.

**CONFIRMED LIVE (2026-09-01): the three panel buttons work, and every setting involved
(group/sort/direction, plus collapsed-group state) persists correctly across both a
`/reload` and a full relog.** HuntScanner grouping/sorting (Decisions Log items 48-49) is
now fully closed out -- no known open items on this feature.

**Achievement name-matching fallback added (2026-09-02), closing the "new hunts need a
manual PreyQuestData entry" gap from earlier.** Product owner asked why scanning doesn't
already give us everything needed -- it does for questID/title/zone, but not the
achievement criteriaID (a Blizzard achievement-system number, not quest data, with no
API mapping a questID to it directly) -- that's what `PreyQuestData`'s static table sources
by hand. New `AchievementAdapter.GetAllCriteria()` + `HuntScannerRuntime.resolveFallbackCriteriaID()`
now match a hunt's own title against its achievement's criteria labels (normalized
text match) when the static table has no entry, instead of leaving the gap permanent.
Confirmed locale-safe by construction (both compared strings are Blizzard's own live
client-locale text, nothing addon-hardcoded). **Surfaced, not fixed, a separate pre-existing
locale gap:** `resolveDifficulty`'s own text-fallback searches for the literal English
words "nightmare"/"hard"/"normal" -- would misdetect on a non-English client. Flagged for a
future pass. Full reasoning in Decisions Log item 50. **Not yet tested live** -- no current
hunt/locale combination to exercise the fallback path against.

**The surfaced locale gap itself is now fixed (2026-09-02, Decisions Log item 51).**
`resolveDifficulty`'s text-fallback now also matches against
`LocalizationAdapter.L("Nightmare"/"Hard"/"Normal")`, not just the literal English words --
ported directly from the old codebase's own already-validated `AddToken` approach rather
than invented fresh. Confirmed `Locales/*.lua` already has real translations for these
exact keys in 8 of 11 locales. `koKR.lua`/`zhCN.lua` only have compound keys ("Normal
Difficulty") today -- explicitly left as a known gap for a native speaker to fill, not
guessed at. **Not yet tested live** (no non-English client available) -- but this is a
faithful port of the old addon's own field-tested fix, not new/unverified design.

**Reward ordering + `reward_display_style` differentiation shipped (2026-09-02, Decisions
Log item 52), closing out the Hunt Panel.** Product owner asked what was left before
signing off -- these two cosmetic items were the only remaining ones.
`HuntScannerRuntime.RefreshFromAdapter` now sorts `rewardEntries` by name (quantity as
tiebreaker) so a hunt's reward row always renders in the same order. Since
`hunt.reward_display_style` is new to the rewrite (no old-addon feature to port), its
visual meaning was confirmed with the product owner rather than guessed: `icon_count`
drops the per-icon quantity number (icons only, quantity still on hover), `text_only`
replaces the icon row with one comma-separated line
(`"10x Reward A, 1000x Reward B, Bonus item reward"`).

**Live test, same day: `text_only` rejected; `icon_inline`/`icon_count` turned out to be
swapped, not confirmed-correct as first recorded here.** Product owner tried all three --
`text_only`'s plain comma-separated line was called "not really viable" for this row and
**removed entirely (Decisions Log item 53)**, not left dormant:
`HuntTablePanel.buildRewardText` and `row.rewardText` are deleted, `applyRow`'s reward
dispatch is back to a single `applyRewardIcons` call, and `text_only` is gone from both the
Settings dropdown and `SettingsRuntime`'s allowed-values list (anyone with it already saved
self-heals to `icon_inline` automatically). The other two were then found to behave
backwards from their names ("Icons Inline" showed icon+quantity, "Icon + Count" showed
icons only) -- **corrected in the same session (Decisions Log item 54)** by flipping
`applyRow`'s dispatch condition: `icon_inline` is now icons-only (hover for quantity),
`icon_count` is icon-plus-quantity-inline (still repeated on hover).

**Also from item 54: reward order needed to be difficulty-independent, not just
scan-independent.** Item 52's name-based sort made one hunt's own row stable, but different
difficulties have differently-named rewards, so the same reward *category* could still
land in a different slot between difficulties. Sort key is now category-first (`currency` /
`item`, from Blizzard's own `.rewardType` field, now preserved instead of dropped; anything
untyped buckets as "other" in between), name/quantity only as a tiebreaker within one
category. **The exact bucket order is a judgment call, not confirmed with the product
owner** -- flag if it doesn't look right live, it's a one-line change. **Not yet tested
live for either fix in this update.**

**Reward sort replaced again, same day (Decisions Log item 55) -- product owner asked if
chest-reward scanning had regressed.** They reported seeing every reward except the chest
and asked directly. Confirmed no: `HuntTableAdapter.GetRewardWidgets`' item/container
scanning (Decisions Log item 19) is untouched. The actual issue was item 54's own
type-based bucket order sorting all currencies together alphabetically, which put a
`"...Mistcrest"` currency before `"Preyseeker's Journey"` -- not the intended result once
spelled out. Replaced with the product owner's exact hand-specified order: `"Coffer Key"`
first, `"Preyseeker's Journey"` second, any `"Mistcrest"`-named currency third (alphabetical
among themselves), unmatched fourth, anything with `"Chest"`/`"Bag"` always last. New
`HuntScannerRuntime.namedRewardPriority()` (case-insensitive name-substring match) replaces
the same-day type-based version; the now-unused `rewardType` field item 54 added was
removed again. **Not yet tested live** -- including whether this actually fixes the
chest's visibility or something else (e.g. row-width truncation) is also involved; flagged
to check `/pd hinspect`'s per-hunt `rewards=N` count if it's still not showing.

**Chest/bag reward missing entirely, not just misordered -- root-caused (2026-09-02,
Decisions Log item 56).** Product owner confirmed after item 55's reorder that the chest
never showed at all for any hunt, despite being visible on the real quest. Working
hypothesis (matches this project's recurring "Blizzard widget not populated yet at the
instant we read it" pattern): `HuntTableAdapter.GetRewardWidgets`' single synchronous peek
can catch the reward pool before its item/container widget finishes populating, and since
the result was cached **unconditionally** per difficulty for the whole session, one
incomplete first peek permanently dropped the chest with nothing to ever re-check it.
**Fix:** cross-check the peek against `QuestApiAdapter.GetQuestRewardSummary`'s independent
`hasBonusItemReward` signal (reliable pre-accept) before caching -- if it says an item
should exist but wasn't found, use the peek for just this render pass (falls through to
the generic mystery placeholder in the meantime) but don't lock it into the cache, so the
next rescan gets another chance. **Not a confirmed root cause, just the best-fitting
hypothesis** -- if the chest is still missing after this, next step is a raw diagnostic
dump of the dialog's reward-pool widgets for a known-missing hunt, not another guess.
**Not yet tested live.**

**Real cause of the Nightmare-only missing chest found: a 4-icon row cap, not item 56's
widget-timing race (2026-09-02, Decisions Log item 57).** Product owner reported the chest
now shows for Normal/Hard but not Nightmare, and Nightmare has 5 distinct rewards --
pointed straight at `HuntTablePanel.MAX_REWARD_ICONS = 4`, which silently truncates
anything past the 4th slot. Since the chest always sorts last (item 55's
`namedRewardPriority`), any 5-reward difficulty always loses exactly that one. Bumped to 6
(one past the known max of 5). **Flagged, not fixed:** a fully-populated 5-icon row likely
runs close to or past the Accept button at the default 336px panel width -- not confirmed
live, but the pixel math makes it plausible. Revisit if the product owner sees actual
overlap. **Not yet tested live.**

**Hunt Panel signed off (2026-09-02), one item carried forward, pending re-confirmation of
today's corrections.** With `text_only` removed and the display-style/ordering bugs fixed,
the Hunt Panel has no known open items left except the achievement-earned live-update path
(Section 5b/5c) -- blocked on the product owner's character reaching that stage, not on
anything code-side -- plus confirming today's two corrections actually look right in-game.

## 6. Housekeeping

- `.vscode/settings.json` has an uncommitted local change (Lua language server WoW-API
  annotations) — not made by Claude, left as-is, harmless.
- Nothing has been committed this session. Whenever a commit is wanted, it should follow
  `.github/commit-template.md` per `CLAUDE.md` Section 11, signed as RagingAltoholic.
