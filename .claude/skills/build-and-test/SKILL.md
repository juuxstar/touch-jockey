---
name: build-and-test
description: How to build, run and test Touch Jockey on this Mac (Command Line Tools only, no Xcode). Use before building, launching, relaunching or testing the app or its engine.
---

# Build and test Touch Jockey

## Build

- `./build.sh` (release) or `./build.sh debug`. It calls `swiftc` directly, builds
  `TJCore` as a static library, and assembles `build/TouchJockey.app` with the
  official icon, plus `build/tj-analyze`.
- Only the Command Line Tools are installed (Swift 5.8, macOS 13.3 SDK). `swift build`,
  SwiftPM and XCTest don't work. `Package.swift` exists for when Xcode is installed.
- Expected warnings: deprecations of `commonMetadata`, `stringValue` and `duration`
  in `Deck.swift` and `Library.swift`. Add no new ones.

## Run and relaunch

- `open build/TouchJockey.app`. If it's already running, `open` only brings it to
  the front: quit it first (`osascript -e 'quit app "TouchJockey"'`), or use
  Restart (⌥⌘R) in the app.
- A quit is cancelled (error `-128`, "User cancelled") when a sheet or dialog is
  open, such as Settings. Don't force-quit: tell the user, or wait.
- The app owns ports **8080** (HTTP) and **8081** (WebSocket), so only one copy can
  run. The user is often running it; don't launch a second copy, and don't drive
  their session (the phone page or the WebSocket) without saying so.
- Developer launch arguments: `--a <file> --b <file> --volume 0.15` preload decks
  and set a quiet master volume.
- The app scans `~/Music` but skips Apple Music, iTunes and GarageBand folders,
  which would trigger a macOS media-library prompt.

## Test

- **Engine tests** are small swiftc executables that link `build/obj/libTJCore.a`:
  - Create `MixEngine()` and set `engine.mainMixerNode.outputVolume = 0` (muted).
  - Load tracks from `~/Music/serenity` with `mix.load(url:into:)`, and drive
    `RunLoop.main`.
  - See `scripts/mixer_test.sh`, and run it after engine changes.
- **Beat analysis:** run `build/tj-analyze <files…>` on known tracks. Levels is 126 BPM,
  Cola 122. To check a beat phase, compare the first-beat time against the kick onsets.
- **WebSocket protocol:** `scripts/drive.py` speaks the phone protocol (standard
  library only) and needs the app running.
- **Phone page:** it's served from the app bundle. Copying `Surface/index.html` into
  `build/TouchJockey.app/Contents/Resources/Surface/` updates a running app without
  a rebuild. Check it in the browser pane at the iPhone's size (about 440×956 portrait).
- **Looking at the Mac window:** screen capture isn't permitted here, so you can't
  screenshot the app window. Say so when a change hasn't been seen.
