# Wong (Godot 4.3)

Open this folder in Godot 4.3+ (project.godot) and press F5.

## Layout
| Path | What |
|---|---|
| scripts/sim.gd | Pure simulation (PongSim): paddles, ball, swept collision, speed cap, scoring. No rendering/audio/input. Seedable. |
| scripts/cpu_ai.gd | CPU opponent, Easy / Normal / Hard. Pure, seedable. |
| scripts/game.gd | Autoload `Game`: settings (saved to user://settings.cfg), input map, event signals. |
| scripts/audio.gd | Autoload `Audio`: plays audio/sfx/<event>.ogg (+ _2, _3 variants) and audio/music/*.ogg. |
| scripts/game_view.gd | Runs the sim at 120 Hz, forwards events to `Game` signals, draws the field (graphics layer owns this). |
| scripts/main.gd | Screens: title (CPU demo behind it), options, match, pause, game over. |
| scenes/main.tscn | Root scene, includes WorldEnvironment (2D glow). |
| tests/ | Headless tests. |

## Gameplay numbers (1920x1080 logical, letterboxed)
Paddle 24x160 at 1100 px/s. Ball 24 px, serves at 720 px/s, +6% per paddle hit, capped at 2200 px/s.
Return angle depends on where the ball hits the paddle (flat at center, up to 55 deg at the edge).
Serve after 1 s, toward whoever conceded. First to N wins (5/7/11/15/21, default 11).

## Controls
P1: W/S, gamepad 1 (stick or d-pad). P2: Up/Down, gamepad 2. In 1-player mode either set works.
Pause: Esc, P, or Start (also auto-pauses on focus loss, e.g. alt-tab). Fullscreen: F11 or Alt+Enter.

## Event signals (Game autoload)
match_started(mode), serve(toward), paddle_hit(side, pos, speed), wall_bounce(pos),
scored(side, score), match_over(winner), paused_changed(paused). Side 0 = left/P1, 1 = right/P2/CPU.

## Tests
    godot --headless --editor --quit                       # first time: import assets
    godot --headless -s tests/run_tests.gd                 # sim + AI tests (~12 s)
    godot --headless --fixed-fps 120 -s tests/ui_smoke.gd  # full menu/match flow
    godot --headless --fixed-fps 120 -- --autoplay=120     # run the real game CPU-vs-CPU for 120 s
All exit 0 on success.

## Steam (later)
Add the GodotSteam GDExtension, init it in an autoload, and hook achievements to the Game signals.
