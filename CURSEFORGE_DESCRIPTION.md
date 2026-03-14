# Preydator

Track the hunt. Hear the danger. Own your layout.

Preydator is a retail World of Warcraft addon built specifically for Prey Hunts. It gives you clear stage tracking, cinematic Predator-style audio cues, and a fully customizable progress bar that works with modern Edit Mode workflows.

## Why players use Preydator

- Real-time prey stage tracking using Blizzard quest/widget APIs
- Clean, compact progress bar designed for practical in-combat readability
- Deep visual customization without bloated menus
- Strong audio controls with stage-based sound cues and ambush alerts
- Reliable behavior across custom UI layouts and Edit Mode presets

## Stage flow

1. Scent in the Wind
2. Blood in the Shadows
3. Echoes of the Kill
4. Feast of the Fang

Blizzard does not expose true percentage completion for Prey Hunts. Preydator tracks stage transitions directly, with clear fallback progress display options.

## Major features (v1.6.0)

- New Prey Currency Tracker window
- New Warband currency table with sorting and realm grouping
- Approved-currency allow-list tracking for:
	- Remnant of Anguish (`3392`)
	- Voidlight Marl (`3316`)
	- Adventurer Dawncrest (`3383`)
	- Veteran Dawncrest (`3341`)
	- Champion Dawncrest (`3343`)
- Session delta tracking and configurable gain/spend color indicators
- In-page Currencies controls for tracked IDs, hunt cost context, and panel layout sliders
- Theme support for currency windows (`Light`, `Brown`, `Dark`)
- One-time What's New splash for currency feature rollout

- Tabbed settings UI: General, Display, Text, Audio, Advanced
- Edit Mode quick-settings window with click-to-open behavior
- Vertical bar mode with dedicated settings: orientation, fill direction, vertical scale, text side/alignment, and vertical percent controls
- Label system with prefix/suffix modes (centered, left/right, separate, none)
- Percent display modes including Above Ticks behavior using per-tick labels
- Text Display row placement for stage names (Above Bar / Below Bar)
- Tick color, border color, and linked border-to-fill behavior
- Optional spark line at the fill edge (toggleable)
- Adjustable bar width, height, scale, and font size
- Stage 1-4 sound selection plus Ambush sound selection
- Built-in test buttons for stage sounds and ambush alerts
- Custom sound file management directly in settings
- Optional hide of default prey icon with stage 4 map fallback behavior
- Debug and diagnostics tools available in UI and slash commands

## Roadmap progress

- Epic 1: Approved Currency Ledger (MVP) - Completed
- Epic 2: Hunt Source Scanner - Planned
- Epic 3: Weekly Hunt Cap Tracker - Planned
- Epic 4: Achievement Gap Highlighter - Planned
- Epic 5: Reward Intelligence / Cost Context - In progress

## Slash commands

- /pd options
- /pd inspect
- /pd show
- /pd hide
- /pd toggle
- /pd mem
- /pd debug <on|off|show|clear>

## Custom audio

Drop your own .ogg files into:

Interface/AddOns/Preydator/sounds/

Then assign them in the Audio tab.

## Support and feedback

Report bugs or request features:
https://github.com/RagingAltoholic/Preydator/issues
