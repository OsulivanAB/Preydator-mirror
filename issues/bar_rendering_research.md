# Bar Rendering Research — Old Implementation vs. New Architecture

Source material (read-only, live/stable worktree):
- `D:\Dev\PreydatorLive\Core\BarRuntime.lua` (968 lines) — `ApplyBarSettings` + `UpdateBarDisplay`
- `D:\Dev\PreydatorLive\Preydator.lua` — `EnsureBar` (~2405-2629), `GetStageLabel` (~812), `barPositionUtil` (~2317-2381), `Preydator.ResolveVerticalTextAnchor`/`GetRenderedVerticalPercent` (~1286-1406), `DEFAULTS` table (~215-347), constants (~29-105), `GetBarRuntimeContext` (~5897-5963)
- `D:\Dev\PreydatorLive\Modules\Settings.lua` — options-UI constants and the accessibility-theme feature (~97-260, ~1429-1482)
- `D:\Dev\PreydatorLive\Core\SettingsRuntime.lua` — `SyncBarPointToBackup`/`RestoreBarPointFromBackup` (~402-442), `NormalizeDisplaySettings`

Compared against: `d:\Program Files\World of Warcraft\_retail_\Interface\AddOns\Preydator\issues\rewrite_architecture.md` (Sections 4 `Core/Runtime/BarRuntime.lua` / `UI/BarFrame.lua`, 5.2 Bar Display, 5.3 Text/Label Styling, Appendix reference to "9 values", Section 12 Performance Budget).

---

## 1. Frame hierarchy & texture/font presets

Built once in `EnsureBar()` (`Preydator.lua:2405-2629`), then continually re-styled by `ApplyBarSettings()` (`Core/BarRuntime.lua:92-509`). All child regions are parented directly to one root frame, `UI.barFrame` (`CreateFrame("Frame", "PreydatorProgressBar", UIParent)`, `Preydator.lua:2422`):

| Region | Type | Created | Notes |
|---|---|---|---|
| `UI.barFrame` | `Frame` | `Preydator.lua:2422` | Root; `SetFrameStrata("MEDIUM")`, `SetFrameLevel(5)`, `SetClampedToScreen(true)`, `RegisterForDrag("LeftButton")` |
| `UI.barFrame.BackgroundTexture` | Texture (`"background"` layer) | `Preydator.lua:2561-2565` | Inset by `FILL_INSET` (3px) on all sides; solid color from `settings.bgColor` |
| `UI.barFill` | Texture (`"artwork"` layer) | `Preydator.lua:2567-2573` | The actual progress fill; texture asset swapped per `settings.textureKey`; `SetHorizTile(false)`/`SetVertTile(false)` |
| `UI.barSpark` | Texture (`"overlay"` layer, sublevel 3) | `Preydator.lua:2575-2580` | A **static** 2px-wide/tall colored rectangle placed at the fill's leading edge — NOT an animated glow; hidden by default |
| `UI.barBorder` | `Frame` w/ `BackdropTemplate` | `Preydator.lua:2582-2590` | `edgeFile = "Interface\Tooltips\UI-Tooltip-Border"`, `edgeSize = 12`; border color mirrors fill color unless `borderColorLinked == false` |
| `UI.stageText` | FontString (`"overlay"`, `GameFontNormal` template) | `Preydator.lua:2592-2595` | The "prefix" or combined-label text region |
| `UI.stageSuffixText` | FontString (`"overlay"`, `GameFontNormal` template) | `Preydator.lua:2597-2601` | The "suffix" text region; hidden by default |
| `UI.barText` | FontString (`"overlay"` layer, sublevel 9, `GameFontHighlightSmall` template) | `Preydator.lua:2603-2606` | The percent-complete text |
| `UI.barAlignmentDot` | Texture (`"OVERLAY"`, sublevel 7) | `Preydator.lua:2608-2613` | Dev/debug alignment aid; always `:Hide()`d immediately in both `EnsureBar` and every `ApplyBarSettings` call (`Core/BarRuntime.lua:351-355`) — dead visual, kept only as a leftover hook |
| `UI.barTickMarks[1..3]` | Textures (`"overlay"`, sublevel 4) | `Preydator.lua:2615-2621` | One per `MAX_TICK_MARKS` (=3) |
| `UI.barTickLabels[1..3]` | FontStrings (`"overlay"`, sublevel 8, `GameFontHighlightSmall`) | `Preydator.lua:2622-2625` | Percent labels next to tick marks |

**Texture presets** (`Preydator.lua:174-179`):
```lua
local TEXTURE_PRESETS = {
    default = "Interface\\TARGETINGFRAME\\UI-StatusBar",
    flat = "Interface\\Buttons\\WHITE8x8",
    raid = "Interface\\RaidFrame\\Raid-Bar-Hp-Fill",
    classic = "Interface\\PaperDollInfoFrame\\UI-Character-Skills-Bar",
}
```
Applied in `Core/BarRuntime.lua:177`: `UI.barFill:SetTexture(constants.TEXTURE_PRESETS[settings.textureKey] or constants.TEXTURE_PRESETS.default)`. Mirrored as user-facing dropdown labels in `Modules/Settings.lua:97-102` (`TEXTURE_OPTIONS`: Default / Flat / Raid HP Fill / Classic Skill Bar). This matches the new doc's `bar.texture_key` enum (4 options) exactly — no gap here, just confirms the concrete asset paths to port.

**Font presets** (`Preydator.lua:181-186`):
```lua
local FONT_PRESETS = {
    frizqt = "Fonts\\FRIZQT__.TTF",
    arialn = "Fonts\\ARIALN.TTF",
    skurri = "Fonts\\SKURRI.TTF",
    morpheus = "Fonts\\MORPHEUS.TTF",
}
```
Applied separately per text region: `titleFontKey` for `stageText`/`stageSuffixText`, `percentFontKey` for `barText` and both tick labels (`Core/BarRuntime.lua:226-228, 290-291, 314-315, 327-328`). **Locale override**: `ResolveLocaleSafeFont` (`Core/BarRuntime.lua:24-34`) forces `STANDARD_TEXT_FONT` instead of the user's chosen preset when the client locale is `ruRU`, `koKR`, `zhCN`, or `zhTW` (the bundled Western fonts don't have those glyphs). This override is applied to *every* text region's font resolution, unconditionally, before font-size math. **This must be ported** — it's easy to silently drop in a from-scratch UI file and would silently break CJK/Cyrillic clients.

Font size math is always `round((fontSize or default) * frameScale)` with a floor: `math.max(8, ...)` for stage/suffix text (`BarRuntime.lua:228, 291`), `math.max(8, round((fontSize-1)*frameScale))` for the percent text (one point smaller, `BarRuntime.lua:315`), and `math.max(7, round((fontSize-4)*frameScale))` for tick labels (four points smaller, floor of 7, `BarRuntime.lua:328`).

---

## 2. Horizontal vs. vertical orientation math

Orientation is a single setting (`settings.orientation`, `"horizontal"`|`"vertical"`, `Core/BarRuntime.lua:115, 649`) that branches nearly every geometry calculation. Key divergences:

**Sizing** (`ApplyBarSettings`, `Core/BarRuntime.lua:117-141`): vertical mode clamps `verticalWidth` to 10-60 and `verticalHeight` to 100-350 (a tall narrow bar); horizontal clamps `horizontalWidth` to 100-350 and `horizontalHeight` to 10-60 (a wide short bar) — literally swapped ranges, not a shared clamp. Scale is likewise a *separate* setting per orientation (`settings.scale` vs `settings.verticalScale`), both clamped 0.5-2.

**Fill growth axis** (`UpdateBarDisplay`, `Core/BarRuntime.lua:664-676`):
```lua
if isVertical then
    UI.barFill:SetWidth(innerFillWidth)
    UI.barFill:SetHeight(math.max(1, height))
    if settings.verticalFillDirection == constants.FILL_DIRECTION_DOWN then
        UI.barFill:SetPoint("TOPLEFT", UI.barFrame, "TOPLEFT", fillInset, -fillInset)
    else
        UI.barFill:SetPoint("BOTTOMLEFT", UI.barFrame, "BOTTOMLEFT", fillInset, fillInset)
    end
else
    UI.barFill:SetPoint("BOTTOMLEFT", UI.barFrame, "BOTTOMLEFT", fillInset, fillInset)
    UI.barFill:SetWidth(math.max(1, width))
    UI.barFill:SetHeight(innerFillHeight)
end
```
Horizontal always grows rightward from a fixed bottom-left anchor. Vertical grows either up-from-bottom (`FILL_DIRECTION_UP`, default) or down-from-top (`FILL_DIRECTION_DOWN`) — the anchor point itself flips, not just a texture flip.

**No rotation of the fill texture itself** — only text gets rotated (see below). The bar shape change is achieved purely through width/height swaps and anchor-point choice.

**Vertical text rotation**: `ApplyVerticalLabelRotation` (`Core/BarRuntime.lua:36-50`) calls `fontString:SetRotation(math.pi/2)` (left side) or `-math.pi/2` (right side) whenever orientation is vertical, and `SetRotation(0)` otherwise. `ResolveVerticalLabelJustifyH` (`Core/BarRuntime.lua:52-77`) then picks `LEFT`/`RIGHT`/`CENTER` justification based on side + whether the vertical anchor point starts with `TOP`/`BOTTOM`. There's also a **fallback for FontStrings without `SetRotation`** (older/atypical font objects): `ToVerticalText` (`Core/BarRuntime.lua:79-90`) manually inserts a `\n` between every character to fake vertical text, invoked from `LabelOut()` in `UpdateBarDisplay` (`Core/BarRuntime.lua:806-811`) only when `orientation == VERTICAL and not UI.stageText.SetRotation`.

**Vertical percent rendering** additionally routes through `Preydator.GetRenderedVerticalPercent(pct, fillDirection)` (`Preydator.lua:1286-1292`), which inverts the percent (`100 - pct`) when fill direction is `down`, before using it for tick-mark Y positioning — the raw stage-progress percent and the "rendered" (screen-space) percent are deliberately different values in vertical/down mode.

**Tick sizing**: horizontal ticks are thin vertical bars spanning the fill's inner height (`tickMark:SetSize(tickWidth, innerTickHeight)`, `BarRuntime.lua:395`); vertical ticks are thin horizontal bars spanning the inner width (`SetSize(innerTickWidth, tickWidth)`, `BarRuntime.lua:388`) — same 90°-rotation relationship as the fill axis swap, but done by swapping width/height arguments rather than any actual texture rotation.

---

## 3. Drag & position persistence

**Draggability wiring** (`EnsureBar`, `Preydator.lua:2422-2517`):
- `createdBar:RegisterForDrag("LeftButton")` at creation.
- `OnDragStart`: only calls `self:StartMoving()` if `settings and not settings.locked` (`Preydator.lua:2502-2507`) — the lock setting is checked here, not by disabling the drag registration.
- `OnDragStop`: calls `StopMovingOrSizing()` then `SaveBarPosition(self)` (`Preydator.lua:2509-2517`), but only if a drag actually started (`self.PreydatorWasDragging` flag, set in `OnDragStart` and cleared at the top of every `OnMouseDown`).
- Mouse is only receptive at all when `UI.barFrame:EnableMouse(...)` is toggled true, which itself is re-evaluated every `UpdateBarDisplay()` call (`Core/BarRuntime.lua:713-720`) based on: bar unlocked, OR stage-4 map-click fallback active, OR Edit Mode preview active. So a locked bar with no stage-4/EditMode condition has mouse input disabled entirely, independent of the `OnDragStart` lock check — **two separate lock gates for the same behavior**.

**Persisted shape** — `settings.point` (`DEFAULTS.point = { anchor = "CENTER", relativePoint = "CENTER", x = 0, y = 472 }`, `Preydator.lua:216`):
```lua
local function SaveBarPosition(self)
    settings.point.anchor = "CENTER"
    settings.point.relativePoint = "CENTER"
    local frameCenterX, frameCenterY = self:GetCenter()
    local parentCenterX, parentCenterY = UIParent:GetCenter()
    settings.point.x, settings.point.y = barPositionUtil.ClampToScreen(
        frameCenterX - parentCenterX, frameCenterY - parentCenterY, frameWidth, frameHeight)
    ...
    self:SetPoint("CENTER", UIParent, "CENTER", settings.point.x, settings.point.y)
end
```
(`Preydator.lua:2439-2470`). Both `anchor` and `relativePoint` are **hardcoded to `"CENTER"`** at both save and apply time (`ApplyBarSettings`, `Core/BarRuntime.lua:142-148, 170` also force-normalizes any stored non-CENTER value back to CENTER) — the frame is always positioned as a `CENTER`-to-`UIParent CENTER` offset pair `(x, y)`, never any of the other 7 anchor points, despite `point.anchor`/`point.relativePoint` existing as if they were general-purpose.

`x`/`y` are always run through `barPositionUtil.ClampToScreen` (`Preydator.lua:2326-2344`), which keeps the frame's edges at least an 8px margin inside `UIParent`'s bounds, falling back to the hardcoded default `(0, 472)` if `UIParent` has no size yet.

**Backup mirror**: every position save also calls `SettingsRuntime:SyncBarPointToBackup(settings)` (`Core/SettingsRuntime.lua:402-415`), which copies `point.x`/`point.y` into flat top-level fields `settings.barPointX`/`settings.barPointY`. `RestoreBarPointFromBackup` (`Core/SettingsRuntime.lua:417-442`) uses those flat fields to repair `settings.point` **only** if `point.x`/`point.y` are missing/invalid — a corruption-recovery path, not a second source of truth. New code should probably keep an equivalent recovery mechanism if migration risk is a concern, but doesn't need the exact flat-field shape.

**Default point oddity worth flagging for the rewrite**: `barPositionUtil.GetDefaultPoint(frameWidth, frameHeight)` (`Preydator.lua:2322-2324`) ignores both parameters and always returns the two fixed constants `(0, 472)` — the "center the bar based on its own size" idea implied by the parameter names doesn't actually happen; every caller passing computed width/height gets the same fixed point regardless.

**Reset action**: `barPositionUtil.Reset()` (`Preydator.lua:2365-2381`) sets `point.anchor`/`relativePoint` back to CENTER, recomputes `x,y` via `GetDefaultPoint` (i.e. back to `0, 472`), syncs the backup, then calls `ApplyBarSettings()` + `UpdateBarDisplay()` — this is the "Reset Bar Position" action referenced in the new doc's Section 5.8 action list.

---

## 4. `stage_label_mode` — the 9 values

Confirmed exactly 9 enum values (`Preydator.lua:57-65`, mirrored as `constants.LABEL_MODE_*` at `Preydator.lua:5630-5638`, with UI strings at `Modules/Settings.lua:244-253`):

| Value | UI label (`Modules/Settings.lua:245-253`) | Horizontal layout behavior (`Core/BarRuntime.lua:801-949`) |
|---|---|---|
| `center` (`LABEL_MODE_CENTER`, default) | "Centered" | `stageText` shows `prefix + " " + suffix` (combined), centered above/below bar; `stageSuffixText` always hidden |
| `left` (`LABEL_MODE_LEFT`) | "Left (Prefix only)" | `stageText` shows prefix only, left-justified; suffix text hidden |
| `left_combined` (`LABEL_MODE_LEFT_COMBINED`) | "Left (Prefix + Suffix)" | `stageText` shows the combined `prefix + " " + suffix` string, left-justified; suffix text hidden |
| `left_suffix` (`LABEL_MODE_LEFT_SUFFIX`) | "Left (Suffix only)" | `stageText` shows suffix only, left-justified; suffix text hidden |
| `right` (`LABEL_MODE_RIGHT`) | "Right (Suffix only)" | `stageText` hidden; `stageSuffixText` shows suffix only, right-justified |
| `right_combined` (`LABEL_MODE_RIGHT_COMBINED`) | "Right (Prefix + Suffix)" | `stageText` hidden; `stageSuffixText` shows the combined string, right-justified |
| `right_prefix` (`LABEL_MODE_RIGHT_PREFIX`) | "Right (Prefix only)" | `stageText` hidden; `stageSuffixText` shows prefix only, right-justified |
| `separate` (`LABEL_MODE_SEPARATE`) | "Separate (Prefix + Suffix)" | `stageText` = prefix (left-anchored region), `stageSuffixText` = suffix (right-anchored region) — the only mode that uses *both* regions simultaneously for distinct content |
| `none` (`LABEL_MODE_NONE`) | "No Text" | Both `stageText` and `stageSuffixText` hidden, text cleared |

**Anchor positions** for `stageText`/`stageSuffixText` in horizontal mode also depend on `labelRowPosition` (`above`/`below` the bar) — e.g. for `left`/`left_combined`/`left_suffix`/`separate`, `stageText` anchors `BOTTOMLEFT→TOPLEFT +2,+4` when row is "above" vs `TOPLEFT→BOTTOMLEFT +2,-4` when "below" (`Core/BarRuntime.lua:263-267`).

**Critical override not mentioned in the new doc**: in `UpdateBarDisplay`, vertical orientation **unconditionally overrides the user's chosen mode to `LABEL_MODE_SEPARATE`** regardless of what `stageLabelMode` is set to:
```lua
local labelMode = settings.stageLabelMode or constants.LABEL_MODE_CENTER
if settings.orientation == constants.ORIENTATION_VERTICAL then
    labelMode = constants.LABEL_MODE_SEPARATE
end
```
(`Core/BarRuntime.lua:801-804`). So all 9 values are only meaningfully distinct in horizontal mode; vertical mode's actual text layout is governed entirely by the separate `verticalTextAlign`/`verticalTextSide`/`verticalPercentSide` settings (see Section 2 above and `ApplyBarSettings`'s vertical branch, `Core/BarRuntime.lua:234-257, 295-300`). The rewrite's `bar.orientation`/`text.stage_label_mode` split in the settings catalog should make this override explicit (either keep it, or deliberately decide to let vertical mode honor the label mode too).

**Naming bug confirmed** (already flagged by the new arch doc, Section 5.3 footnote, and verified true in code): `settings.stageLabels` (`DEFAULTS.stageLabels`, `Preydator.lua:246-251`) holds the actual stage **suffix** text shown on the bar (fed through `GetStageLabel()`, `Preydator.lua:812-821`, and used as `suffixText = label` in `UpdateBarDisplay`, `Core/BarRuntime.lua:780`), while `settings.stageSuffixLabels` (`DEFAULTS.stageSuffixLabels`, `Preydator.lua:330-335`) is actually used as the **prefix**: `prefixText = (settings.stageSuffixLabels and settings.stageSuffixLabels[stage]) or ""` (`Core/BarRuntime.lua:779`). The names are swapped relative to what they do. The new doc's `text.stage_prefix`/`text.stage_suffix` naming (Section 5.3) correctly fixes this — confirmed as a real, not cosmetic, bug in the old code.

---

## 5. Tick mark positioning

Tick counts and percents come from `settings.progressSegments` (`"quarters"` or `"thirds"`), resolved via two parallel lookup tables (`Preydator.lua:43-46, 159-172`):
```lua
local BAR_TICK_PCTS_BY_SEGMENT = {
    quarters = { 25, 50, 75 },
    thirds   = { 33, 66 },
}
local STAGE_PCT_BY_SEGMENT = {
    quarters = { [1]=25, [2]=50, [3]=75, [4]=100 },
    thirds   = { [1]=0,  [2]=33, [3]=66, [4]=100 },
}
```
`MAX_TICK_MARKS = 3` (`Preydator.lua:31`) — the tick-mark slot array is always 3 long; "thirds" mode simply leaves the 3rd slot's percent as `nil` (no tick rendered there), handled generically by `hasTick = tickPercents[index] ~= nil` (`Core/BarRuntime.lua:324`).

**Horizontal positioning** (`Core/BarRuntime.lua:357-397`):
```lua
local innerTickWidth = math.max(0, barWidth - (2 * fillInset))
...
x = fillInset + math.floor((innerTickWidth * (pct / 100)) + 0.5)
x = math.floor((x / tickWidth) + 0.5) * tickWidth   -- tickWidth = 1, effectively a no-op round
...
if pct == 100 then
    tickMark:SetPoint("BOTTOMLEFT", UI.barFrame, "BOTTOMLEFT", barWidth - fillInset - tickWidth, fillInset)
else
    tickMark:SetPoint("BOTTOMLEFT", UI.barFrame, "BOTTOMLEFT", x, fillInset)
end
```
i.e. tick X position is a straight linear interpolation across the *inner* (inset-adjusted) bar width, with a special-cased flush-right placement at exactly 100% to avoid clipping past the border.

**Vertical positioning** additionally runs the percent through `Preydator.GetRenderedVerticalPercent(pct, verticalFillDirection)` first (inverting it under `FILL_DIRECTION_DOWN`) before doing the equivalent Y-axis interpolation against `innerTickHeight`, with the same 100%-edge special case (`Core/BarRuntime.lua:364-396`).

**Tick percent number labels** are a *separate* concern from the tick mark lines themselves and have their own visibility rules layered on top of `settings.showTicks`:
- Horizontal: tick labels only show when `percentDisplayMode` is `above_ticks` or `under_ticks` (`Core/BarRuntime.lua:454-459`), with placement (`above`/`below` the bar, and 0%/100%/middle edge cases) computed separately (`Core/BarRuntime.lua:433-447`).
- Vertical: tick labels are gated by a *different* setting, `settings.showVerticalTickPercent`, not `showTicks`/`percentDisplayMode` at all (`Core/BarRuntime.lua:409-413, 450-453`) — when shown, they can render either centered on the fill's leading edge, or pinned to the left/right side at each tick's height, per `settings.verticalPercentSide` (`Core/BarRuntime.lua:414-432`).

---

## 6. "Edit Mode" integration

Confirmed: **this is not Blizzard's real Edit Mode system** (no `EditModeManagerFrame:RegisterSystem`/`EditModeSystemMixin` usage anywhere in the bar code). It is exactly what was suspected — a bare `_G.EditModeManagerFrame:IsShown()` truthiness check, used in three independent places, each gating something different:

1. **`UpdateBarDisplay`'s `IsEditModePreviewEnabled()`** (`Core/BarRuntime.lua:564-571`):
   ```lua
   local function IsEditModePreviewEnabled()
       if settings.showInEditMode ~= true then return false end
       local active = ctx.isEditModePreviewActive and ctx.isEditModePreviewActive()
       return active and true or false
   end
   ```
   where `ctx.isEditModePreviewActive` is wired to `function() return editModeFrame and editModeFrame.IsShown and editModeFrame:IsShown() end` (`Preydator.lua:5917-5920`). This gates: (a) forcing the bar visible even with no active quest/out-of-zone (`shouldShow` in `Core/BarRuntime.lua:579`), (b) the placeholder text `"Preydator (Edit Mode Preview)"` shown in place of the current zone name (`Core/BarRuntime.lua:772-774`), and (c) enabling mouse input on the bar (`allowEditModeClickOpen`, `Core/BarRuntime.lua:714, 719`) purely so it can be clicked while Blizzard's real Edit Mode window is open.

2. **`OnMouseDown`** (`Preydator.lua:2484-2499`): reads `EditModeManagerFrame:IsShown()` directly to decide whether a click should be treated as "possibly opening Preydator's own settings window" (records click start position/time for a tap-vs-drag distinction) vs. the normal stage-4 map-click-fallback behavior.

3. **`OnMouseUp`** (`Preydator.lua:2529-2559`): if `EditModeManagerFrame:IsShown()`, checks whether the mouse-down-to-mouse-up motion was a short tap (≤3px movement, ≤0.20s) and if so opens Preydator's `EditMode` module window (`editModeModule:ShowWindow()`) or falls back to `OpenOptionsPanel()` — i.e. **while Blizzard's Edit Mode is open, clicking the Preydator bar opens Preydator's own quick-settings window**, purely as a discoverability affordance timed to when the player is already repositioning their UI. Outside of Blizzard Edit Mode, a left-click at stage 4 instead tries to open the prey quest on the map (`TryOpenPreyQuestOnMap()`).

No `EditModeSystemMixin`, no registration with Blizzard's layout-manager save/restore, no participation in Edit Mode's "Reset to Default Layout" or preset system. It's purely a visibility/interactivity hook keyed off Blizzard's Edit Mode being open.

---

## 7. Accessibility color theming — NOT net-new; this is the biggest gap

**The new architecture doc's claim (Section 5.2: `bar.accessibility_theme` "One-click colorblind preset" ... Section 15: "Accessibility bar-color presets ... net-new work, not a port") is incorrect.** A grep for `deuteranopia|protanopia|accessib` across the live worktree turns up a fully-implemented feature already shipping in `Modules/Settings.lua`:

```lua
local BAR_ACCESSIBILITY_OPTIONS = {
    default = { text = L["Default"] },
    deuteranopia = { text = L["Deuteranopia"] },
    protanopia = { text = L["Protanopia"] },
}

local BAR_ACCESSIBILITY_PRESETS = {
    deuteranopia = {
        fillColor = { 0.90, 0.60, 0.10, 1.00 },
        borderColor = { 0.90, 0.60, 0.10, 1.00 },
        titleColor = { 1.00, 0.74, 0.00, 1.00 },
        percentColor = { 1.00, 1.00, 1.00, 1.00 },
        tickColor = { 0.65, 0.68, 0.84, 1.00 },
        bgColor = { 0.06, 0.07, 0.14, 0.88 },
        borderColorLinked = false,
    },
    protanopia = {
        fillColor = { 0.00, 0.72, 0.82, 1.00 },
        borderColor = { 0.00, 0.72, 0.82, 1.00 },
        titleColor = { 0.00, 0.88, 1.00, 1.00 },
        percentColor = { 1.00, 1.00, 1.00, 1.00 },
        tickColor = { 0.50, 0.74, 0.80, 1.00 },
        bgColor = { 0.03, 0.10, 0.13, 0.88 },
        borderColorLinked = false,
    },
}
```
(`Modules/Settings.lua:119-144`), applied by:
```lua
local function ApplyBarAccessibilityTheme(key)
    local preset = BAR_ACCESSIBILITY_PRESETS[key]
    if not preset then
        db.fillColor = CloneColor(defaults.fillColor, db.fillColor)
        ... -- reset every bar color field to its default
        db.barAccessibilityTheme = "default"
    else
        db.fillColor = CloneColor(preset.fillColor, db.fillColor)
        ... -- overwrite every bar color field from the preset
        db.borderColorLinked = preset.borderColorLinked == true
        db.barAccessibilityTheme = key
    end
    api.NormalizeColorSettings()
    api.ApplyBarSettings()
    api.RequestBarRefresh()
end
```
(`Modules/Settings.lua:1457-1482`), wired to a dropdown at `Modules/Settings.lua:1716-1719`, with a `db.barAccessibilityTheme` field defaulted to `"default"` if missing (`Modules/Settings.lua:1435-1437`). It is a **one-shot color-field overwrite** (fill/border/title/percent/tick/bg colors + border-link flag), not a live/persistent "theme mode" — picking a preset just bulk-writes the existing individual color settings once, so a user who later tweaks one color manually silently drifts away from the preset with no re-sync. There is a separate, more elaborate `deuteranopia`/`protanopia` pair used for the Hunt Table panel theme (`THEME_EDITOR_PRESETS`/`GetAllThemeOptions`, `Modules/Settings.lua:147-173`, plus `Modules/HuntScanner.lua:636-660` and `Modules/CurrencyTracker.lua:192-206`) — that's a distinct, richer 9-color palette system for panel chrome, not the bar.

**Correction needed in the architecture doc**: this is a **port target**, not new work — the bar-color preset values above should be carried into `bar.accessibility_theme`'s three enum values verbatim (or deliberately revised), and the "one-click, overwrite-in-place" semantics (vs. a live persistent theme) should be a conscious decision for the rewrite, not an oversight.

---

## Gaps / Conflicts vs. new architecture doc

1. **Accessibility theme is not net-new (Section 7 above).** The doc's Sections 5.2/15 both assert this is fresh work; it already exists, fully implemented, in `Modules/Settings.lua:119-144, 1457-1482`. Correct the doc and treat this as a straight port (with the "overwrite once" semantics as an explicit design choice to keep or fix).

2. **Vertical orientation silently overrides `stage_label_mode` to `separate`** (`Core/BarRuntime.lua:801-804`). The settings catalog (Section 5.3) lists `text.stage_label_mode` as a general "Horizontal label layout mode," which is accurate, but doesn't call out that vertical mode ignores it entirely in favor of `verticalTextAlign`/`verticalTextSide`/`verticalPercentSide`. The rewrite should decide explicitly whether to keep this override or unify the two orientation's label systems.

3. **Two lock/drag gates for one behavior.** `settings.locked` disables `StartMoving()` in `OnDragStart` (`Preydator.lua:2503`), but mouse input to the frame is independently re-enabled/disabled every `UpdateBarDisplay` tick based on `not settings.locked` OR′d with two unrelated conditions (`Core/BarRuntime.lua:713-720`). The new doc's `general.lock_bar` (Section 5.1) describes it as gating "Bar mouse-down handler," but the real old behavior is two separate checks that happen to overlap. Worth collapsing to one gate in the rewrite rather than porting the duplication.

4. **Default value / naming mismatch**: old `settings.locked` defaults to `true` (`Preydator.lua:226`); the new doc's `general.lock_bar` defaults to `false` (Section 5.1). This is a real behavior change (bar drag is locked out-of-the-box today; the rewrite would ship unlocked by default) — confirm this is intentional before porting, since it wasn't called out as a deliberate default flip anywhere in the doc.

5. **`GetDefaultPoint(frameWidth, frameHeight)` ignores its parameters** (`Preydator.lua:2322-2324`) and always returns the fixed constants `(0, 472)`. Any future rewrite implementation that assumes the default point is computed from frame size (e.g. "always centered regardless of bar dimensions") would be porting a bug that never actually did that — worth deciding whether to keep the fixed-point behavior or actually implement size-aware centering.

6. **No animation on the spark line.** New doc Section 12 says: "the only per-frame-adjacent code is `UI/BarFrame.lua`'s spark-line animation, if enabled, and even that is a WoW animation-group (`AnimationGroup`), not a scripted `OnUpdate`." The **old code has no animation at all** — `UI.barSpark` is a plain static texture repositioned to the fill's leading edge on every `ApplyBarSettings`/`UpdateBarDisplay` call (`Preydator.lua:2575-2580`, `Core/BarRuntime.lua:191-203, 678-704`). If the rewrite wants an actual pulsing/animated spark, that's new visual work, not a port — the doc's phrasing reads as if it's describing existing behavior when it's actually describing a planned enhancement.

7. **`stageLabels`/`stageSuffixLabels` naming inversion is confirmed real** (already flagged by the doc's own Section 5.3 footnote) — `stageLabels` is the visible suffix text, `stageSuffixLabels` is actually the prefix (`Core/BarRuntime.lua:779-780`, `Preydator.lua:812-821, 246-251, 330-335`). The doc's renamed `text.stage_prefix`/`text.stage_suffix` fields correctly resolve this; just confirming the migration mapping needs to cross the streams (old `stageSuffixLabels` → new `stage_prefix`; old `stageLabels` → new `stage_suffix`).

8. **Duplicate width/height/scale clamping logic exists in two places** already: `barPositionUtil.GetCurrentDimensions()` (`Preydator.lua:2346-2363`) and the equivalent inline block at the top of `ApplyBarSettings` (`Core/BarRuntime.lua:117-141`) independently reimplement the same orientation-based clamp-and-fallback math. This is exactly the class of duplication the new doc's Principle 2 (Section 2) is meant to eliminate — `UI/BarFrame.lua`/`BarRuntime.lua` in the rewrite should have exactly one function that computes effective bar width/height, not two.

9. **Locale-safe font override is easy to miss when porting.** `ResolveLocaleSafeFont` (`Core/BarRuntime.lua:24-34`) silently substitutes `STANDARD_TEXT_FONT` for `ruRU`/`koKR`/`zhCN`/`zhTW` regardless of the user's `text.title_font_key`/`text.percent_font_key` choice. Nothing in the new doc's Section 5.3 (font settings) or Section 13 (Localization Contract) calls this out explicitly — worth adding as an explicit requirement so `UI/BarFrame.lua` doesn't ship CJK/Cyrillic-breaking font rendering.

10. **`UI.barAlignmentDot` is fully dead code** (`Preydator.lua:2608-2613`, immediately hidden and re-hidden every `ApplyBarSettings`, `Core/BarRuntime.lua:351-355`) and the old `showAlignmentDot` setting is already listed in the new doc's "not carried forward" list (Section 18) — confirms no action needed here, just noting the region should not be recreated at all in `UI/BarFrame.lua`.

11. **Two independent lock-position backup mechanisms** (`settings.point` nested table + `settings.barPointX`/`barPointY` flat backup, `Core/SettingsRuntime.lua:402-442`) exist purely for corruption recovery. The new doc's `Core/State.lua`/`Core/Settings.lua` split doesn't mention this pattern; worth deciding whether the rewrite needs an equivalent recovery path or whether stronger `SettingsRuntime.NormalizeAll` field-by-field validation (already promised in Section 11) makes the flat-field backup unnecessary.

12. **Tick label visibility uses two unrelated settings depending on orientation** — horizontal ticks' percent labels are gated by `settings.percentDisplay` (`above_ticks`/`under_ticks`), vertical ticks' percent labels are gated by an entirely separate boolean, `settings.showVerticalTickPercent` (`Core/BarRuntime.lua:409-413, 454-459`). The settings catalog (Section 5.2) doesn't list `showVerticalTickPercent` at all — it's missing from the new doc's settings catalog entirely and needs to be added (as `bar.vertical_show_tick_percent` or similar) if vertical-mode tick percent labels are to be kept.
