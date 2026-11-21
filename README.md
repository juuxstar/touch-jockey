# Touch Jockey

A beginner DJ tool. The Mac does all the audio; phones and tablets are touch
controllers. Instead of faders and EQ knobs, a transition is three **handoff
lanes** (lows, mids, highs) that move energy from the outgoing track to the
incoming one. Flick a lane and it swaps on the next bar.

Design doc: <https://claude.ai/artifact/DciH8vHF7wfWi2PrbkKuY8>

## Status: milestone 1 ("prove the feel")

Working:

- Beat analysis on load (BPM and first downbeat), under a second per track.
- Two decks: sync with key lock, and a phase lock that keeps the beats aligned within a millisecond.
- The incoming track starts on the outgoing track's next bar or phrase.
- Three-band handoff with 24 dB/octave crossovers at 200 Hz and 2.5 kHz and equal-power lanes.
- Flick to swap a band on the next bar. When every lane reaches the incoming side, the handoff finishes on the next bar and the decks swap roles.
- Web surface for any phone or tablet:
  - relative drags and multi-touch
  - touch ownership, so two devices never fight over a lane
  - two-finger tap to go back to the outgoing track
  - beat and bar display
- Mac window:
  - load tracks
  - start, cue and stop
  - lanes as sliders, for testing without a phone
  - a status-line indicator of connected phones; click it for the QR code
- Settings window (**⌘,**, or the gear in the status line), so the main window keeps its space for DJing:
  - Connect a phone: QR code, address, steps, connected count
  - Display: text size (80-160%) and help icons
  - Library: music folder, rescan, re-analyse all tracks
  - Playback: SYNC on by default, keep the Mac awake while a deck plays
  - App: version and restart

Not yet built (see the design doc's milestones):

- Library with search
- Timeline with sections
- Transition window
- Tension pad, loops and moments
- Headphone cue
- Learning features
- Native iOS app with haptics

## Run it

```bash
./build.sh
open build/TouchJockey.app
```

Load a track into each deck from the window. Then open Settings (**⌘,**, or click
**0 connected** in the status line), scan the QR code with a phone on the same Wi-Fi, turn the phone sideways, tap **Start A**, then
**Bring in B next phrase**, and drag the lanes.

### Keyboard shortcuts

| Keys | Action |
| --- | --- |
| **⌘,** | Settings |
| **⌘+** / **⌘−** / **⌘0** | Bigger, smaller, actual-size text |
| **⌘F** | Search the library |
| **⌥⌘R** | Restart Touch Jockey |
| **Esc** / **Return** | Close Settings |

Developer shortcuts:

```bash
open build/TouchJockey.app --args --volume 0.3 --a "path/to/a.mp3" --b "path/to/b.mp3"
build/tj-analyze ~/Music/serenity/*/*/*.mp3    # check the beat analysis
scripts/drive.py                               # scripted handoff over the WebSocket, like a phone
```

## Building

`build.sh` compiles with `swiftc` and assembles `build/TouchJockey.app`, with the
official icon from `../branding`. There are no third-party dependencies.

`Package.swift` describes the same targets for SwiftPM and Xcode. However,
`swift build` needs a full Xcode install. On this Mac there are only the Command
Line Tools (Swift 5.8, macOS 13.3 SDK), and SwiftPM fails there looking up the
platform path. Once Xcode is installed, pin its version in `.xcode-version`.

## Architecture

```
Sources/
  TJCore/                  audio and networking, no UI
    BeatAnalyzer.swift     onset envelope + comb search → BPM and first downbeat
    Deck.swift             player → time-pitch (key lock) → 3 band filters → band gains
    MixEngine.swift        two decks, handoff lanes, flicks, role swap, phase lock
    ControlServer.swift    HTTP for the surface (8080) + WebSocket for control (8081)
  TouchJockey/             the Mac app
    App.swift              window (SwiftUI)
    Settings.swift         Settings sheet and its UserDefaults keys
    AppModel.swift         connects engine, window and surfaces; 30 Hz state broadcast
    Surface/index.html     the web surface served to phones and tablets
  tj-analyze/              command-line beat analysis
scripts/drive.py           test driver that speaks the surface protocol
```

### Surface protocol (JSON over the WebSocket)

From a surface:

| Message | Meaning |
| --- | --- |
| `grab` / `release` + `band` | A finger is on or off a lane. While grabbed, other devices can't move that lane. |
| `lane` + `band` + `v` | Lane value from 0 (all outgoing) to 1 (all incoming). |
| `flick` + `band` + `to` | Jump the band to 0 or 1 on the next bar. |
| `stable` | Everything back to the outgoing track. |
| `play` | Start the outgoing deck. |
| `cue` + `every` | Start the incoming deck on the next multiple of `every` beats. |

From the Mac, about 30 times a second: `state`, with roles, lanes, lane owners,
both decks (title, artist, BPM, playing, beat), the outgoing beat and BPM, and
`startsIn` (beats until the incoming deck starts).
