# Wong

A Pong-style arcade game in Godot 4.3 (GDScript): one or two players or vs CPU (Easy, Normal,
Hard), with a Neon Arcade look, music and sound. Steam release is a later idea.

Follow the hub's `standards.md` (ipodjockey/hub), including "Game projects only". See
`README.md` for layout, gameplay numbers, controls and signals.

## About the hub

This repo is one of the owner's projects. The hub repo (`ipodjockey/hub`) holds what they share:
the development standards (`standards.md`), the list of projects and their status (`projects.md`)
and reusable task prompts (`prompts/`). Cross-project work, such as rolling out a new standard,
is done from the hub.

Claude projects can't message each other, so when the hub changes this repo or a rule it follows,
it leaves a dated note in `HUB-NOTES.md`. At the start of every session, read the notes under
"New", do or flag what they ask, then move them to "Done". If this project's status changes,
update its line in the hub's `projects.md`, or say so in `HANDOFF.md` if the hub isn't available.

## Where things are

| Path | What |
| --- | --- |
| `scripts/sim.gd` | Pure simulation (`PongSim`): paddles, ball, collision, scoring. No rendering, audio or input. Seedable. |
| `scripts/cpu_ai.gd` | CPU opponent, pure and seedable. |
| `scripts/game.gd` | Autoload `Game`: settings (`user://settings.cfg`), input map, event signals. |
| `scripts/audio.gd` | Autoload `Audio`: plays `audio/sfx/<event>.ogg` and `audio/music/*.ogg`. |
| `scripts/game_view.gd` | Runs the sim at 120 Hz, forwards events, draws the field. |
| `scripts/main.gd` | Screens: title, options, match, pause, game over. |
| `scripts/vfx/` | Palette, UI theme and effects. |
| `scenes/main.tscn` | Root scene. |
| `tests/` | Headless tests: `run_tests.gd` (sim + AI), `ui_smoke.gd` (menus and match), `qa_tests.gd` (soak and edge cases). |
| `tools/` | `screenshot.gd` (store shots), `store_art.py` (logo and Steam images, needs Pillow + numpy). |
| `art/`, `audio/` | Font (OFL licence in `art/font_OFL.txt`), title image, music and sound effects. |

## How to test

```sh
godot --headless --editor --quit                          # first time: import assets
godot --headless -s tests/run_tests.gd                    # sim + AI tests
godot --headless --fixed-fps 120 -s tests/ui_smoke.gd     # menu and match flow
godot --headless --fixed-fps 120 -s tests/qa_tests.gd     # soak and edge cases
```
All exit 0 on success.

## Refactoring notes

Refactor by the hub's `refactoring.md` (run it with the hub's `prompts/refactor.md`).

- **Contracts:** `user://settings.cfg` keys (players' saved settings); scene and node paths in
  `scenes/main.tscn`; autoload names `Game` and `Audio`; the `Game` signal names and arguments
  that graphics and audio listen to; sound file names (`audio/sfx/<event>.ogg` and variants); the
  input map; the gameplay numbers in `README.md`; command-line flags (`--autoplay`, and
  `tools/screenshot.gd`'s `--out`, `--times`, `--menu`, `--seed`).
- **Safety net:** the three headless test scripts above, before and after every step. Sim and AI are
  seedable, so a fixed seed must give the same result. For visuals, compare `tools/screenshot.gd`
  shots with the same `--seed` (needs a real renderer). No CI yet.
- **Scarce resource:** frame time; the sim runs at a fixed 120 Hz. Watch per-frame allocations
  and work in the wrong loop.
- **Conventions:** GDScript with `##` purpose headers; `sim.gd` and `cpu_ai.gd` stay pure (no
  rendering, audio or input); gameplay events go through `Game` signals; colours from
  `scripts/vfx/palette.gd`. No addons or new dependencies without approval.
