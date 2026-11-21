# Notes for agents working on Touch Jockey

Touch Jockey is a DJ app **for beginners**. A Mac-only Swift engine does the audio;
phones and tablets are touch controllers through a web page the Mac serves.
`README.md` covers the features and architecture, and links the design doc.

The detailed rules live in project skills, one per area, in `.claude/skills/`.
Load the relevant skill before working in that area:

| Skill | Use it when |
| --- | --- |
| [`ui-design`](.claude/skills/ui-design/SKILL.md) | adding or changing controls, panels, **tooltips**, help icons, colours, layout or modals |
| [`build-and-test`](.claude/skills/build-and-test/SKILL.md) | building, launching, relaunching or testing the app or the engine |
| [`audio-engine`](.claude/skills/audio-engine/SKILL.md) | changing TJCore: decks, mixer gains, sync, beat analysis, caches |
| [`phone-surface`](.claude/skills/phone-surface/SKILL.md) | changing the phone/tablet page, the WebSocket protocol, or iOS web app behaviour |
| [`repo-workflow`](.claude/skills/repo-workflow/SKILL.md) | creating worktrees, merging branches, committing or pushing |

The essentials, if nothing else:

- Build with `./build.sh` (no Xcode). Don't launch a second copy of the app while
  the user's is running: it owns ports 8080 and 8081.
- Commit and push only when the user asks.
