---
name: audio-engine
description: How Touch Jockey's audio engine, beat analysis, sync and mixer gain model work. Use when changing TJCore (MixEngine, Deck, BeatAnalyzer, AnalysisCache, Library) or anything that affects timing, sync or levels.
---

# Touch Jockey audio engine (TJCore)

## Signal path (per deck, `Deck.swift`)

player → `AVAudioUnitTimePitch` (tempo change with key lock) → three parallel band
filters (24 dB/oct: low < 200 Hz, mid, high > 2.5 kHz) → per-band mixer gains → deck
output mixer → main mixer.

## Skill ladder (`SkillLadder.swift`)

- One level per technique: blend (`handoff`, `mixer`), timing (`snap`, `free`),
  tempo (`sync`). `MixEngine.ladder`, changed with `setLevel` / `setLadder`. The app
  saves it and broadcasts it as `ladder` in `state`.
- A new level: a `SkillLevel` case (in ladder order) with its `technique`, its text in
  `Settings.swift`, and the engine behaviour. Guard behaviour on the level, not on UI.
- **Switching blend level must not jump the sound.** `setLadder` hands over: lanes →
  EQ positions (`eqPosition(forGain:)`), or the mixer's per-band A/B balance (playing
  decks only) → lanes, then the mixer resets. `mixer_test.sh` measures the jump.

## Gain model (`MixEngine.applyGains`)

```
                handoff level   mixer level
band gain   =   lane gain       EQ gain                    (each band's mixer node)
deck volume =   1               fader gain × crossfader    (each deck's output node)
```

- **Handoff level:** the mixer is held neutral (stored values too) and `setEQ`,
  `setVolume`, `setCrossfader` are ignored. **Mixer level:** the lanes are bypassed and
  `setLane`, `flick`, `backToStable` are ignored.
- **Lanes**, one per band, run from 0 (deck A) to 1 (deck B), with equal power
  (A = cos, B = sin). The phone moves them. Flick jumps a lane on the next bar
  (`snap`) or now over `freeFlickRamp` (20 ms, `free`); a new `setLane` cancels a ramp.
- **EQ** position 0…1: +6 dB at the top, 0 dB at the centre, −30 dB lower down,
  and a kill in the bottom 2%.
- **Fader** taper: position squared. **Crossfader**: both decks full at the centre.
- At the handoff level only the lanes finish a handoff. When every lane reaches the
  incoming deck's side, the outgoing deck stops on the next bar and the roles swap.
  **The lanes stay where they are**, because decks have fixed positions.
- At the mixer level the roles swap when the outgoing deck stops or pauses while the
  incoming deck plays (`checkMixerSwap`, also polled from `syncTick`), so SYNC follows
  the deck you hear.

## Timing and sync

- Beat positions come from the player's sample time (`Deck.position()`), converted
  with the track's `BeatGrid`. Scheduled starts use host time from the outgoing
  deck's `lastRenderTime` (`hostTime(ofNextBoundary:)`).
- **SYNC** sets the incoming deck's rate to the master's BPM ÷ its own. The time-stretcher
  runs about 0.1% off the rate it's given, so `syncTick` runs a PI phase lock at 30 Hz
  (gains 0.3 / 0.08, correction clamped to ±1%). It locks in about 3 s, to within
  0.001 beats. Re-test alignment after changing it.
- Transport follows CDJ conventions: CUE, PLAY/PAUSE, SYNC/MASTER. CUE snaps to the
  nearest beat.

## Beat analysis (`BeatAnalyzer.swift`)

- Onset envelope weighted towards the kick, at about 200 Hz, then a comb search over
  70–180 BPM.
- Each candidate is scored by the **average** onset at its predicted beats. Never use
  a sum: it favours fast tempos. A log-Gaussian preference centred on 125 BPM decides
  between half and double tempo.
- The fine pass searches **every phase** again. A coarse phase is meaningless a
  quarter-BPM away.
- `confidence` below 0.25 means the tempo is a guess. The UI marks it "?".

## Caches: bump the version whenever derivation changes

- `AnalysisCache` (`~/Library/Application Support/TouchJockey/analysis/`): its
  `version` is part of the cache key. **Bump it** whenever the analysis output or
  method changes, or users keep stale results.
- The library cache file is versioned by name (`library-v2.json`). Bump the name
  when cached fields or how they are derived change.
