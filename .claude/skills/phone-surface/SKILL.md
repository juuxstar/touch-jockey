---
name: phone-surface
description: How the Touch Jockey phone/tablet web surface works, its WebSocket protocol, and iOS home-screen web app quirks. Use when changing Surface/index.html, ControlServer, the state broadcast, or AppModel's message handling.
---

# Touch Jockey phone surface

## Pieces

- `Sources/TouchJockey/Surface/index.html`: one self-contained page. It has no
  build step and no npm.
- `ControlServer.swift`: plain HTTP on 8080 for static files, and a WebSocket on 8081
  (browsers can't send UDP).
- `AppModel.handle(_:_:)` handles messages. `AppModel.tick()` broadcasts `state`
  about 30 times a second.
- The full protocol table is in `README.md`. Keep it in sync when you add messages.

## Touch handling rules

- **Relative drags:** a lane moves by how far the finger travels, never jumping to
  where it lands. The travel width is the lane minus its label and readout areas
  (`--x0` / `--x1`).
- **Multi-touch:** each lane and mixer control tracks its own pointer id. `grab` /
  `release` give touch ownership, so two devices never fight over a control. Lanes
  send `band`; mixer controls send `control` (`eq:A:low`, `vol:B`, `xfade`), and
  `AppModel.handle` checks the owner before applying `lane`, `eq`, `volume`, `xfade`.
- **Two screens by blend level:** `state.ladder.blend` is `handoff` (the lanes) or
  `mixer` (two channel strips, VOL next to the centre, and a crossfader along the
  bottom). `renderMixer` swaps them live; leave the lanes screen as it is.
- **Mixer controls** use the same look as the Mac's `MixerSlider`: a bordered level
  container, a fill (from the bottom for VOL, from the centre for EQ), an indicator
  line, the readout inside, and a dashed `isKill` state. Double-tap resets.
- **Flick:** a release faster than about 550 px/s over the last 80 ms (screen pixels, not
  lane lengths) jumps the lane on the next bar. The knob moves to its target at once, hollow
  and gold, while the lane tint still shows what is heard, and a gold fill counts down to the
  bar. The armed state clears when the lane reaches its target, or after 5 s.
- **Two-finger tap:** back to the playing deck's side (`stable`).
- Wrap `setPointerCapture` in try/catch: it throws for synthetic test events.
- **CSS class names:** the element-state classes (for example `isArmed`, `isHeld`,
  `isKill`) must never equal the name of a styled child element (for example
  `armedRing`, `mxLine`). A clash once hid a whole lane.
- **Orientation:** in portrait, the lanes are three vertical columns (A at the top,
  B at the bottom), so three fingers can each slide one. In landscape they are
  horizontal rows (A on the left, B on the right). `body.vertical` toggles from
  `matchMedia("(orientation: portrait)")`, and drag maths uses the matching axis.
- The lane tint blends by share: blue when all A, orange when all B.

- **Never trust pointerup to arrive.** iOS sometimes drops it (notifications, the app
  switcher, system gestures, lost capture), and a control held by a lost finger ignores every
  later touch. `releaseAll()` lets go on `lostpointercapture`, when a touch event reports no
  fingers left, when the page is hidden, and on reconnect. On the Mac, a phone's `hello` on a
  new connection frees what its old connection owned.

## Devices, per-deck controls and self-update

- On connect the page sends `hello` with a stable `device` id (kept in localStorage)
  and its `kind`. `state.devices` lists `{id, name, deck}`; each page finds itself by id.
- At the mixer level with two or more devices, each shows deck `A`, `B` or `both`
  (`assign`, or Settings → Connect on the Mac). `body.oneDeck` / `deckA` / `deckB`
  hide the other channel and the other track's header.
- **Self-update:** `ControlServer` replaces `__TJ_PAGE_VERSION__` in `index.html` with
  a hash of the file as served, and `state.page` carries the current hash. A page whose
  stamp differs reloads itself, but never while a finger is on a control. So a new build
  (or a page copied into the bundle) reaches every phone on its own; no manual reload.
- The gear in the footer opens a small menu (this device's name, the laptop's address,
  Reload). Touch targets there and on the deck buttons are at least 44 px tall.

## iOS home-screen web app quirks

- Don't use `viewport-fit=cover`. iOS 26 blurs whatever is drawn under the status
  bar. Keep the page out of the status-bar and home-bar areas, with
  `apple-mobile-web-app-status-bar-style` set to `black`.
- iOS reports a wrong `100vh` in home-screen apps. Size the body from
  `window.innerHeight` on load, resize and orientation change.
- iOS ignores the manifest's orientation lock, so support **portrait and landscape**.
- iOS reads status-bar and manifest settings only when the page is added to the
  Home Screen. **After changing them, the user must delete the icon and add it again.**
- There are no haptics in any iOS browser. Android Chrome has crude `navigator.vibrate`.
  Haptics need a native iOS app later.
- HTTPS-only APIs (Wake Lock, service workers, Android's install prompt) don't work
  over plain-http LAN. Wrap them in try/catch.

## Checking

- The page is served live from the app bundle. Copy it into
  `build/TouchJockey.app/Contents/Resources/Surface/` (or run `./build.sh`), and the
  phones reload themselves within about 2 s. Server-side Swift changes still need an
  app restart.
- Run the design plugin's state gate on the page after edits (the Stop hook asks for it).
- Test in the browser pane at about 440×956 (portrait) and 956×440 (landscape).
  Desktop browsers can't reproduce the iOS quirks above, so ask for a phone screenshot.
