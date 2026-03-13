# Preydator

Preydator is a World of Warcraft addon that tracks your active Prey Hunt stage, displays a customizable progress bar, and plays stage-based audio cues.

Current release: `v1.5.0`

## Quick start

1. Install the addon in:

   `Interface/AddOns/Preydator/`

2. Optional: add your own sound files in:

   `Interface/AddOns/Preydator/sounds/`

3. Reload your UI with `/reload`.

4. Open settings with `/pd options` (or `/preydator options`).
5. Open Blizzard Edit Mode to use the compact Preydator quick-settings window while positioning the bar.

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
- Enable **Show in Edit Mode preview** to keep the bar visible while Blizzard Edit Mode is open so you can position it more reliably with custom UI layouts.

## Using custom audio files

1. Put your `.ogg` files in:
   `Interface/AddOns/Preydator/sounds/`
2. Open options: `/pd options`
3. In **Custom Sound Files**:
   - Type the filename (examples: `my-alert`, `my_alert.ogg`, or full path)
   - Click **Add File**
4. Select the file in stage/ambush dropdowns.

Input behavior:

- `.ogg` is optional when typing; it is appended automatically.
- Names with spaces are not supported.
- Full prefix path is accepted: `Interface\\AddOns\\Preydator\\sounds\\...`
- Default files are protected and cannot be removed.

Default bundled files:

- `predator-alert.ogg`
- `predator-ambush.ogg`
- `predator-torment.ogg`
- `predator-kill.ogg`

## What you can customize in settings

- Bar lock/unlock and on-screen position
- Only show in prey zone
- Show in Edit Mode preview
- Compact Edit Mode quick settings for common layout adjustments
- Scale, width, height, font size
- Texture preset and colors (bar, title, percent text)
- Stage names and out-of-zone label
- Ambush custom text (full override of ambush display text)
- Percent display style, in-bar percent layering, and tick mark layering
- Sound enable/disable, channel, and sound enhancement
- Stage 1/2/3 sound selection and ambush sound selection
- Custom sound file add/remove controls in options
- Test buttons for each stage sound
- Reset all settings to defaults

## Settings layout

- The main settings panel is organized into tabs to reduce clutter.
- Slider controls show the current value and allow direct typed entry in addition to dragging.
- Existing installs keep their saved values during settings UI migrations.

Sound defaults:

- Ambush default sound is `predator-kill.ogg`.

## Slash commands

- `/preydator options` or `/pd options` - open addon settings
- `/preydator inspect` or `/pd inspect` - print live diagnostic state
- `/preydator show` - force show bar
- `/preydator hide` - return to auto visibility
- `/preydator toggle` - toggle force show
- `/preydator mem` - print memory usage snapshot
- `/preydator debug <on|off|show|clear>` - debug logging controls

Note: debug logging is off by default on load.
