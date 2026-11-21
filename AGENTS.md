# Notes for agents working on Touch Jockey

Touch Jockey is a DJ app **for beginners**. A Mac-only Swift engine does the audio;
phones and tablets are touch controllers through a web page the Mac serves.
See `README.md` for the architecture and the design doc linked there for the plan.

## Building and running

- Build with `./build.sh`. Only the Command Line Tools are installed (Swift 5.8,
  no Xcode), so `swift build`, SwiftPM and XCTest don't work; the script calls
  `swiftc` directly and assembles `build/TouchJockey.app`.
- The running app owns ports 8080 (HTTP) and 8081 (WebSocket). Don't launch a
  second copy while the user's is running; test the engine with a muted
  command-line harness that links `build/obj/libTJCore.a` (see `scripts/mixer_test.sh`).
- The phone page (`Sources/TouchJockey/Surface/index.html`) is served from the
  app bundle, so copying it into `build/TouchJockey.app/Contents/Resources/Surface/`
  updates a running app without a rebuild.

## Repository layout

- `~/code/touch-jockey/dev` is the main checkout (branch `main`).
- Worktrees for parallel work go in sibling folders, for example `~/code/touch-jockey/mixer`.
- Branding (the official TJ ligature icon) lives in `~/code/touch-jockey/branding`.
- Commit messages end with a `Co-Authored-By:` line for the model that helped.

## UI rules

### Help for beginners
- Put explanations in **ⓘ help icons** (`InfoTip("…")`) placed next to the thing
  they explain, never as permanent text in the layout. They can be switched off in
  Settings / View → Show Help Icons.
- Help text uses markdown: **bold** for terms, short paragraphs separated by a blank line.

### Tooltips
- Put tooltips **only on controls that aren't intuitive for a beginner**: what a
  control does, or a consequence that isn't visible (for example "the music stops").
  Obvious buttons get none: Done, Copy, clear-search ✕, navigation that already
  has a titled section with its own help icon.
- A tooltip appears **only after the pointer has rested on the control, without
  moving, for 1 second**, and hides on any movement or press. That's what `.tip("…")`
  does (`StillTipModifier` in `Tooltip.swift`). It matters most on sliders, which
  the pointer sits on while they're being used.
- The only exception is the ⓘ help icons, whose whole purpose is to show help on
  hover; they use `.tip(text, delay:)` with a short delay.

### Look
- Dark theme; bright, colour-coded borders. Deck A is blue (`TJ.a`), deck B orange
  (`TJ.b`); bands: high sky, mid lavender, low rose (`TJ.band(_:)`); gold for timing
  and accents.
- Corners: 10 px on containers, 6 px on controls. No pill shapes.
- One font family. Use `.font(.tj(size, weight:))` in the Mac app so text scales
  with ⌘+ / ⌘−; the phone page uses Inter.
- Use the app's own controls (`.tjButton`, `MixerSlider`, `Panel`, `.modalStyle`),
  not native-looking ones. Pop-ups get a bright border.
- Decks have **fixed positions**: A left/top, B right/bottom, everywhere.
- Keep screen space for DJing: rarely needed options go in the Settings window (⌘,).
