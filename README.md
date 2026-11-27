# Touch Jockey

A beginner DJ tool, and a DJ **learning tool**. The Mac does all the audio; phones
and tablets are touch controllers. Beginners start on simplified controls: a
transition is three **handoff lanes** (lows, mids, highs) that move energy from
the outgoing track to the incoming one, and a flicked lane swaps on the next bar.
Each simplified control is swapped for the real one (a two-channel mixer with EQ,
volume faders and a crossfader; flicks that land when you flick) once the user
steps that technique up on the [learning ladder](#learning-ladder).

Design doc: <https://claude.ai/artifact/DciH8vHF7wfWi2PrbkKuY8>

## Status: milestone 1 ("prove the feel")

Working:

- Beat analysis on load (BPM and first downbeat), under a second per track.
- Two decks: sync with key lock, and a phase lock that keeps the beats aligned within a millisecond.
- The incoming track starts on the outgoing track's next bar or phrase.
- **Cue a match** on the incoming deck loads a library track that suits the outgoing one (tempo within 6%, the best Camelot key match there is, no other version of the same song) at bar 1. Each press offers a different one.
- Three-band handoff with 24 dB/octave crossovers at 200 Hz and 2.5 kHz and equal-power lanes.
- Flick to swap a band on the next bar. When every lane reaches the incoming side, the handoff finishes on the next bar and the decks swap roles. A deck playing on its own is always the outgoing deck (at the handoff level the lanes follow it), so the start buttons sit on the deck that is waiting.
- A learning ladder (Settings → Your skills): blend with the handoff lanes or the full mixer, and Flick snapped to the bar or free. See [Learning ladder](#learning-ladder).
- A handoff scorecard after every handoff at the handoff level; clean handoffs unlock Free timing (5) and the CUE buttons (10). See [Unlocks](#unlocks).
- Guide practice: **Go practice** on a transition chapter parks two tracks (the ones loaded, or a tempo- and key-matched pair from the library) on phrase lines, the outgoing one four phrases from its end; at the mixer level it also resets the mixer (EQs centred, outgoing fader up, incoming fader down, or for the crossfader chapter both faders up and the crossfader on the outgoing side). The practice bar has Reset and New pair.
- A conventional two-channel mixer at the mixer level: per-deck HIGH/MID/LOW EQ (kill at the bottom, 0 dB at the centre, +6 dB at the top), a volume fader per deck, and a crossfader. Mixer and lanes never act at once (see [Gain model](#gain-model)).
- Speakers and headphones (Settings → Audio): each deck gets a headphones button that sends it to the headphones before the bands, lanes and faders, so a deck silent in the speakers is still heard there; a cue-mix slider beside the mixer sets what the headphones play (cued decks, the speaker mix, or both). Separate devices are joined in a private aggregate device; a device with four or more outputs can carry the headphones on channels 3–4.
- Web surface for any phone or tablet:
  - relative drags and multi-touch
  - touch ownership, so two devices never fight over a lane or a mixer control
  - at the mixer level, a mixer screen (two channel strips and a crossfader) instead of the lanes
  - two-finger tap to go back to the outgoing track
  - beat and bar display
- Mac window:
  - load tracks
  - start, cue and stop
  - Play all (or **Space**): both decks start together, beats lined up
  - a **line-up** view: both whole tracks stacked; drag the waiting track under the playing one to plan the bar it comes in on (snapped to phrases), and the engine starts it there by itself (`MixEngine.plannedEntry`)
  - a shared timeline of both decks that zooms from 12 to 128 bars, so a whole blend fits; with both decks stopped it lines them up as Play all will start them, and a dragged deck snaps to the beat, bar or phrase depending on the zoom
  - a blend panel: at the handoff level the phone's lanes (with mouse sliders and Flick, shown read-only while a phone is connected), Back to and Stop all; at the mixer level two channel strips (EQ and volume fader) and a crossfader
  - a status-line indicator of connected phones; click it for the QR code
  - opens full screen on the laptop's built-in display
- Settings window (**⌘,**, or the gear in the status line), so the main window keeps its space for DJing:
  - Connect a phone: QR code, address, steps, connected count
  - Your skills: the learning ladder, one level per technique
  - Display: text size (80-160%) and help icons
  - Library: music folder, rescan, re-analyse all tracks
  - Playback: SYNC on by default, keep the Mac awake while a deck plays
  - Audio: the speakers' and the headphones' output devices
  - App: version and restart

Not yet built (see the design doc's milestones):

- Library with search
- Timeline with sections
- Transition window
- Tension pad, loops and moments
- More learning features (beat-matching by ear, lessons)
- Native iOS app with haptics

## Run it

```bash
./build.sh
open build/TouchJockey.app
```

Load a track into each deck from the window. Then open Settings (**⌘,**, or click
**0 connected** in the status line), scan the QR code with a phone on the same Wi-Fi, tap **Start A**, then
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
scripts/mixer_test.sh                          # muted engine test of the blend levels, hand-overs, role swap and Flick timing
scripts/coach_test.sh                          # handoff scorecard and unlocks, no audio
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
    Deck.swift             player → time-pitch (key lock) → 3 band filters → band gains; headphone cue send
    AudioOutputs.swift     output devices; the private speakers + headphones aggregate device
    MixEngine.swift        two decks, handoff lanes, flicks, role swap, phase lock; EQ, faders, crossfader
    SkillLadder.swift      the learning ladder: techniques and their levels
    HandoffCoach.swift     scores a handoff (HandoffReport); SkillProgress and its unlocks
    ControlServer.swift    HTTP for the surface (8080) + WebSocket for control (8081)
  TouchJockey/             the Mac app
    App.swift              window (SwiftUI)
    MixerPanel.swift       the blend panel: handoff lanes or mixer by level; MixerSlider
    Settings.swift         Settings sheet (incl. Your skills) and its UserDefaults keys
    WindowPlacement.swift  full screen on the built-in display at launch
    AppModel.swift         connects engine, window and surfaces; 30 Hz state broadcast
    Surface/index.html     the web surface served to phones and tablets
  tj-analyze/              command-line beat analysis
scripts/drive.py           test driver that speaks the surface protocol
scripts/mixer_test.*       muted engine test of the blend levels (links build/obj/libTJCore.a)
scripts/outputs_test.*     muted engine test of speakers + headphones (needs a second output device)
```

### Learning ladder

`SkillLadder` (TJCore) holds the user's level on each technique; the app saves it in
UserDefaults (`skillLadder`) and the user changes it in **Settings → Your skills**,
up or down at any time.

| Technique | Levels (beginner first) |
| --- | --- |
| Blend | `handoff`: the phone's lanes do the blend, the mixer is held neutral. `mixer`: EQ, faders and crossfader; the lanes are bypassed. |
| Bass-swap timing | `snap`: a Flick lands on the next bar. `free`: a Flick lands now, with a 20 ms ramp. |
| Tempo | `sync`: SYNC matches tempo and beat. (Beat-matching by ear comes later.) |
| Reading the waveform | `single`: each deck's waveform in its own colour, the bright core the bass. `spectrum`: coloured by frequency (red bass, green mids, blue highs), as in club DJ software. |

A new level is one `SkillLevel` case plus its text in `Settings.swift` and whatever
behaviour it changes.

### Unlocks

Some levels and controls are earned. `HandoffCoach` (TJCore) scores each handoff at
the handoff blend level from the lanes as heard, in the outgoing deck's beats; the
engine reports it through `onHandoffReport` when the roles swap (or when the old
track ends first). A handoff is **clean** when it passes all five checks:

| Check | Passes when |
| --- | --- |
| Came in on a phrase line | the incoming track started within a beat of a phrase line (32 beats) |
| Bass swap on a phrase line | LOWS last crossed half-way within a bar (4 beats) of a phrase line; the detail says how many bars early or late |
| Basslines together under a bar | LOWS spent under 4 beats between 0.2 and 0.8 |
| Blend over 8 bars or more | 32+ beats from the first lane leaving the old track to the finish |
| Finished before the track ran out | the lanes finished before the old track's last beat |

At **free** timing the report also gives the bass swap's offset from the nearest bar
line in milliseconds.

`SkillProgress` (TJCore) counts clean handoffs and holds the unlocks, saved in
UserDefaults (`skillProgress`): **Free** timing after 5, the **CUE** buttons after 10.
A locked level can't be chosen (Settings shows a lock and how many handoffs are left).
**I already DJ: unlock everything** in Your skills lifts every lock; turning it off
locks again what wasn't earned. Settings saved before unlocks existed keep their levels:
`free` timing grants Free, and `free` or `mixer` grants CUE.

**Switching blend level never jumps the sound.** Handoff → mixer sets each deck's
EQ to the gain its lane was giving that band (faders full, crossfader centred);
gains below the EQ's lowest step (about −29 dB) round to that step or a kill.
Mixer → handoff sets each lane to the A/B balance the mixer was giving that band
(EQ × fader × crossfader), counting only playing decks, then resets the mixer.
Lanes are equal power, so a band turned down on both decks comes back to full
level: the balance is kept, not the overall level. A band silent on every playing
deck goes to a stopped deck's side, so it stays silent.

### Gain model

Each deck's signal path is player → time-pitch → three band filters → band
gains → deck output → speaker bus → router → main mixer (see Outputs in the audio-engine skill). Which layer drives those nodes depends on the
blend level:

```
                handoff level          mixer level
band gain   =   lane gain              EQ gain                    (each band's AVAudioMixerNode)
deck volume =   1                      fader gain × crossfader    (each deck's output AVAudioMixerNode)
```

- **Lane gain**: equal power along the lane, A = cos(x·π/2), B = sin(x·π/2).
- **EQ gain**: control position 0…1. The upper half is 0 to +6 dB, the lower half
  0 to −30 dB (both linear in dB), and the bottom 2% is a full kill.
- **Fader gain**: position squared, so half-way is about −12 dB.
- **Crossfader gain**: both decks full at the centre. Towards one side, the other
  deck fades out over that half with a quarter-sine: A = cos((x−0.5)·π) for
  x > 0.5, B = sin(x·π) for x < 0.5. Smooth, with no dip in the middle.

At the handoff level, the lanes finish a handoff: when all three reach the
incoming side, the outgoing deck stops on the next bar, paused on that bar (so
PLAY or bringing it back in carries on from there), and the roles swap. The
mixer ignores input. At the mixer level, the roles swap when the outgoing deck
stops or pauses while the incoming deck plays (so the deck you hear is the
master and SYNC follows it), and lane, flick and stable messages are ignored.
Stop all leaves the mixer alone.

### Surface protocol (JSON over the WebSocket)

From a surface:

| Message | Meaning |
| --- | --- |
| `grab` / `release` + `band` or `control` | A finger is on or off a control: a lane (`band`), or `control` = `eq:A:low`, `vol:B`, `xfade`. While grabbed, other devices can't move it. |
| `lane` + `band` + `v` | Lane value from 0 (deck A) to 1 (deck B). Handoff level only. |
| `flick` + `band` + `to` | Jump the band to 0 or 1: on the next bar (`snap`) or now (`free`). Handoff level only. |
| `stable` | Everything back to the outgoing track. Handoff level only. |
| `play` | Start the outgoing deck. |
| `cue` + `every` | Start the incoming deck on the next multiple of `every` beats. |
| `eq` + `deck` + `band` + `v` | EQ position from 0 (kill) through 0.5 (unity) to 1 (+6 dB). `deck` is 0/1 or `"A"`/`"B"`. |
| `volume` + `deck` + `v` | Channel fader from 0 (silent) to 1 (full). |
| `xfade` + `v` | Crossfader from 0 (A only) through 0.5 (both full) to 1 (B only). |
| `hello` + `device` + `kind` | Sent on connect: a stable id the page keeps in its storage, and `iPhone`, `iPad`, `Android phone`… |
| `assign` + `deck` | This device's mixer controls: `"A"`, `"B"` or `"both"`. |

`eq`, `volume` and `xfade` work at the mixer level only.

From the Mac, about 30 times a second: `state`, with roles, lanes, lane owners,
both decks (title, artist, BPM, playing, beat), the outgoing beat and BPM,
`startsIn` (beats until the incoming deck starts), and the mixer: `eq` (per deck,
`{low, mid, high}`), `volume` (per deck) and `xfade`, on the same scales as the
messages above, and `ladder` (`{"blend": "handoff" | "mixer", "timing": "snap" | "free",
"tempo": "sync"}`). `owners` maps control ids (a band, or `eq:A:low` and so on) to
the client holding them. `devices` lists the surfaces that said hello
(`{id, name, deck}`), and `page` is the phone page's version: the server stamps the
version into the page it serves, and a surface whose stamp differs reloads itself
(once no finger is on a control), so a new build reaches every phone on its own.
