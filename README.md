# Preydator

Preydator is a World of Warcraft addon that tracks your active Prey Hunt stage, displays a customizable progress bar, and plays stage-based audio cues.

## Quick start

1. Install the addon in:

   `Interface/AddOns/Preydator/`

2. Optional: add your own sound files in:

   `Interface/AddOns/Preydator/sounds/`

3. Reload your UI with `/reload`.

4. Open settings with `/pd options` (or `/preydator options`).

## Stage flow shown by the bar

Preydator follows this hunt progression:

1. Scent in the Wind
2. Blood in the Shadows
3. Echoes of the Kill
4. Feast of the Fang

Behavior flow:

- No active prey -> normal hidden/idle behavior depending on your settings
- Active prey but wrong zone -> out-of-zone label
- Stage 1 -> Stage 2 -> Stage 3 -> Stage 4
- Stage 4 always displays as `100%`

Optional behavior:

- Enable **Only show in prey zone** to hide the bar until you enter the correct prey zone.

## Using your own audio clips

Drop your custom files into:

- `Interface/AddOns/Preydator/sounds/predator-alert.ogg`
- `Interface/AddOns/Preydator/sounds/predator-ambush.ogg`
- `Interface/AddOns/Preydator/sounds/predator-torment.ogg`
- `Interface/AddOns/Preydator/sounds/predator-kill.ogg`

Notes:

- Keep the exact filenames above.
- Use `.ogg` format.
- Reload UI after replacing audio files.

## What you can customize in settings

- Bar lock/unlock and on-screen position
- Only show in prey zone
- Scale, width, height, font size
- Texture preset and colors (bar, title, percent text)
- Stage names and out-of-zone label
- Percent display style and tick marks
- Sound enable/disable, channel, and sound enhancement
- Test buttons for each stage sound
- Reset all settings to defaults

## Slash commands

- `/preydator options` or `/pd options` - open addon settings
- `/preydator inspect` or `/pd inspect` - print live diagnostic state
- `/preydator show` - force show bar
- `/preydator hide` - return to auto visibility
- `/preydator toggle` - toggle force show
- `/preydator mem` - print memory usage snapshot
- `/preydator debug <on|off|show|clear>` - debug logging controls
