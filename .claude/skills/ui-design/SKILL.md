---
name: ui-design
description: Touch Jockey UI rules for the Mac window and the phone page. Use when adding or changing any control, panel, tooltip, help text, colour, layout or modal in Touch Jockey.
---

# Touch Jockey UI design

Touch Jockey is a DJ app **for beginners**. The UI has to teach without cluttering
the screen, and leave as much room as possible for DJing.

## Help for beginners

- Put explanations in **ⓘ help icons** (`InfoTip("…")` in `Tooltip.swift`), placed
  next to the thing they explain. They open on click. Never put explainer text permanently in the layout.
- Users can switch help icons off in Settings → Display, or View → Show Help Icons
  (`infoTipsKey`). Nothing should depend on them being on.
- Help text is markdown: **bold** for terms, short paragraphs separated by a blank
  line, and numbered steps where order matters. Write for someone learning house,
  progressive house and melodic techno.

## Tooltips

- Put tooltips **only on controls that aren't intuitive for a beginner**: say what
  the control does, or warn about a consequence that isn't visible (for example
  "the music stops" or "if that deck is playing, it stops").
- **No tooltips on obvious controls.** That includes Done, Copy, the clear-search ✕,
  navigation that leads to a titled section with its own help icon (such as the
  Settings sidebar), and anything whose label already says it all.
- A tooltip appears **only after the pointer has rested on the control, without
  moving, for 1 second**, and hides on any movement or press. That's what `.tip("…")`
  does (`StillTipModifier`). It matters most on sliders, which the pointer sits on
  while they're in use.
- **ⓘ help icons open only when clicked** (`InfoTip`, `ClickTipModifier`), never on
  hover. They stay open while being read; clicking the ⓘ again, opening another one, or Esc closes them. Help text must say
  "click the ⓘ", not "hover".
- `.tip(text, delay:)` (a fixed-delay hover tip) is no longer used; avoid it.
- Tooltips draw on a layer over the whole window, so panels can't clip them. A
  separate window or sheet needs its own layer: `.tooltipScope(name)`.

## Look

- Dark theme with bright, colour-coded borders.
  - Deck A is blue (`TJ.a`) and deck B orange (`TJ.b`).
  - Bands (`TJ.band(_:)`): high is sky, mid lavender, low rose.
  - Gold (`TJ.gold`) is for timing, accents and section labels (`Cap(text:)`).
- Corners: 10 px on containers, 6 px on controls. No pill shapes, which waste space.
- One font family.
  - Mac app: the system font through `.font(.tj(size, weight:))`, so text scales with
    ⌘+ / ⌘− (`UIScale`).
  - Phone page: Inter, with tabular figures for numbers.
- Use the app's own controls rather than native-looking ones: `Panel`, `.tjButton(color, filled:)`,
  `MixerSlider`, `CueButton`. Pop-ups and sheets use `.modalStyle(color)` (a bright border).

## Layout

- Decks have **fixed positions**: A on the left (or on top), B on the right (or below),
  on every screen. Don't reorder by role (outgoing or incoming); show the role with a
  label instead.
- Main window, top to bottom: deck cards, a compact timeline (fixed height), the
  mixer, the **library as a full-width sortable table** (it takes the remaining
  height), then the status line.
- Keep the main window for DJing. Rarely needed options go in the Settings window
  (⌘,, `Settings.swift`).
- The window opens full screen on the laptop's built-in display (`WindowPlacement.swift`).
- Check that layouts still fit at 140% text size and at the minimum window size
  (about 1240×760 pt).
