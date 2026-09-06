# Preydator

Preydator is a focused Prey Hunt companion addon for World of Warcraft: a customizable
progress bar, Predator-inspired audio cues, and a Hunt Table panel, all built on real
Blizzard quest/widget data.

Current release: `v4.0.0` — a complete rewrite of the addon on a new, more reliable
foundation. See `CHANGELOG.md` for the full list of what's new.

## Known Limitations

- **Default Blizzard prey icon can briefly reappear during combat.** If it happens to show
  itself while you're in combat, Preydator can't hide it again until combat ends — this is
  a WoW restriction on addons touching UI during combat, not a bug. It corrects itself the
  moment combat ends.
- **Rare zone-detection flicker.** In a small number of unusual zone shapes, the bar may
  briefly flicker right at the very start of a hunt before it settles.
- **"Dialog" sound channel can cut alerts short.** If Sound Channel (Settings → Sound &
  Alerts) is set to "Dialog," two alerts firing close together can cut each other off —
  that's how WoW's Dialog channel behaves for every addon. Use "Master" or "SFX" if you
  want overlapping alerts to always play in full.
- **Korean/Chinese difficulty detection is incomplete.** For a hunt not yet in the addon's
  internal data, Normal/Hard/Nightmare detection from the quest text only works reliably on
  English-language quest titles right now; Korean and Simplified Chinese aren't fully
  covered. Everything else (UI text, other locales) works normally. If you're fluent in
  either and want to help, see **Issues and feedback** below.

## What Preydator tracks

- Your active Prey Hunt and its stage transitions, live
- Whether you're in the prey's zone, with a fallback label when you're not
- Stage-based progress (Blizzard doesn't expose a true percent-complete for Prey Hunts, so
  Preydator maps each stage to a percentage instead):
  - `Quarters`: `25 / 50 / 75 / 100`
  - `Thirds`: `0 / 33 / 66 / 100`
- Ambushes and this season's Mob Scanner mechanics (Pack Ambush, Exploding Corpse Snakes),
  each with their own sound and a brief bar-text change
- Hunt Table availability, rewards, and (where applicable) Prey achievement progress

## Stage flow

1. **Scent in the Wind**
2. **Blood in the Shadows**
3. **Echoes of the Kill**
4. **Feast of the Fang**

## Settings

Preydator's settings live in Blizzard's own Options window: **Escape → Options → AddOns →
Preydator**, or type `/preydator`. Categories:

- **General** — enable/disable the bar, sounds, and Hunt Scanner; lock the bar; hide the
  minimap button; show/hide Blizzard's own prey icon
- **Bar Display** — texture, size, scale, orientation (horizontal/vertical), percent display
  mode, ticks
- **Bar Colors** — fill/background/border/percent/title colors, accessibility color presets
- **Text & Labels** — stage labels, prefixes/suffixes, ambush and Pack Ambush text, fonts
- **Sound & Alerts** — stage/ambush/Pack Ambush/Exploding Corpse Snakes sounds, sound
  channel, alert cooldown, Amplify Alert Sounds
- **Hunt Scanner** — Hunt Table panel layout, grouping/sorting, reward display style,
  achievement badges
- **Advanced** — custom sound file add/remove, reset actions, diagnostics toggles

## Hunt Table panel

Opens automatically while you're interacting with a Hunt Table NPC. Shows each available
hunt's difficulty icon, name, zone, and reward icons (hover any icon for its full name),
plus an Accept button. Group hunts by difficulty or zone and sort them in either direction
directly from the panel — no need to open Settings.

## Sounds

Bundled default sound files:

- `predator-alert.ogg`, `predator-snarl-01.ogg`, `predator-torment.ogg`, `predator-kill.ogg`
  — stage 1-4 sounds
- `well-we-ve-prepared-a-trap-for-this-predator.ogg` — ambush
- `predator-kills-its-prey-to-survive.ogg` — Pack Ambush
- `echo-of-predation.ogg` — Exploding Corpse Snakes

### Custom sounds

Place your own `.ogg` file in:

```text
Interface/AddOns/Preydator/sounds/
```

Then add it via Settings → Advanced → Add Custom Sound File, and it'll appear in every
sound picker. The bundled default files above can't be removed.

## Diagnostics (`/pd`)

Useful mainly for troubleshooting or filing a bug report:

- `/pd inspect [bs]` — general addon state
- `/pd qinspect [questID] [bs]` — the active (or a specific) Prey quest
- `/pd hinspect [bs]` — current Hunt Table snapshot
- `/pd pinspect [bs]` — progress-tracking state
- `/pd sinspect [bs]` — recent sound-alert attempts (played/blocked, and why)
- `/pd ninspect [bs]` — recent nearby-mob nameplate trace (needs Settings → Advanced →
  "Record Nameplates Seen During Hunts")
- `/pd iinspect [bs]` — default prey icon suppression trace
- `/pd zinspect [bs]` — zone-detection trace
- `/pd segments` — toggle the bar's progress-segment mode (quarters/thirds); macro-friendly

Add a trailing `bs` to any command to also send the report to BugSack if you have it
installed.

## Issues and feedback

Please report bugs, feature requests, or visual/audio issues — and if you'd like to help
translate Preydator into Korean or Simplified Chinese, let us know there too:

**[https://github.com/RagingAltoholic/Preydator/issues](https://github.com/RagingAltoholic/Preydator/issues)**
