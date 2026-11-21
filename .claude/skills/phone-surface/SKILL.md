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
- **Multi-touch:** each lane tracks its own pointer id. `grab` / `release` give
  touch ownership, so two devices never fight over a lane.
- **Flick:** a fast release jumps the lane on the next bar. The "armed" ring clears
  when the lane reaches its target, or after 5 s.
- **Two-finger tap:** back to the playing deck's side (`stable`).
- Wrap `setPointerCapture` in try/catch: it throws for synthetic test events.
- **CSS class names:** the element-state classes (for example `isArmed`) must never
  equal the name of a styled child element (for example `armedRing`). A clash once
  hid a whole lane.
- **Orientation:** in portrait, the lanes are three vertical columns (A at the top,
  B at the bottom), so three fingers can each slide one. In landscape they are
  horizontal rows (A on the left, B on the right). `body.vertical` toggles from
  `matchMedia("(orientation: portrait)")`, and drag maths uses the matching axis.
- The lane tint blends by share: blue when all A, orange when all B.

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
  `build/TouchJockey.app/Contents/Resources/Surface/` and reload the phone.
- Run the design plugin's state gate on the page after edits (the Stop hook asks for it).
- Test in the browser pane at about 440×956 (portrait) and 956×440 (landscape).
  Desktop browsers can't reproduce the iOS quirks above, so ask for a phone screenshot.
