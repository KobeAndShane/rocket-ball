# Gravity Shift

Rocket League-style car soccer built in **Godot 4** — with a twist: the arena's
gravity rotates every 30 seconds. Floor, walls and ceiling are all valid pitches,
so every shift forces players to re-read the field and re-plan their aerials.

## Features

- **Gravity-shift gameplay** — `GravityManager` owns a single source of truth for
  gravity direction and strength; every surface is playable and goals stay
  reachable in all four orientations.
- **Car physics** — throttle, steering, handbrake, jump, double jump, air roll,
  pitch/yaw and a boost meter, all tuned through `Resource` files.
- **Match flow** — kickoff countdown, goal pause, replays, overtime and
  configurable match rules (`MatchRules.tres`).
- **Game modes and mutators** — free play plus composable mutators (big ball,
  low gravity, no boost, fast/random shifts, unlimited boost).
- **Bots** — gravity-aware prediction, roles and reaction delay across
  difficulty tiers for offline 3v3 matches.
- **Networking** — server-authoritative ENet multiplayer with 60 Hz snapshots,
  client-side prediction and a net debug overlay.
- **Matchmaking and ranking** — Glicko-2 ratings, seasons and a matchmaking
  service.
- **Progression** — XP, cosmetics and a season pass backed by local profiles.
- **Training and replays** — drill library, tutorial controller and a replay
  recorder/browser.
- **Settings and accessibility** — remappable controls, colour-blind shaders,
  UI scaling, subtitles and audio options.
- **Presentation** — pooled VFX, procedural audio with adaptive music and an
  announcer mix, plus a chase/ball/free camera rig.

## Requirements

- **Godot 4.4 or newer** (the performance report was captured on 4.4.1 stable,
  Forward+ / Vulkan).
- Jolt Physics is used for the 3D simulation at 120 Hz (bundled with Godot 4.4+).

## Getting started

1. Install Godot 4.4+.
2. Open this folder in the editor (`project.godot`).
3. Let the first import finish, then press **F5** to run.

The main scene is the menu, `res://ui/Main.tscn`; matches load `res://match/Match.tscn`.

## Controls

All bindings can be remapped in the in-game settings.

| Action | Default key |
| --- | --- |
| Throttle / reverse | `W` / `S` |
| Steer left / right | `A` / `D` |
| Jump | `Space` |
| Boost | `Shift` |
| Handbrake | `Ctrl` |
| Air roll | `E` |
| Pitch up / down | `Up` / `Down` |
| Yaw left / right | `Left` / `Right` |
| Ball cam | `Q` |
| Look behind | `R` |
| Reset car | `R` |
| Debug gravity / overlay | `G` / `F3` |
| Pause | `Esc` |

## Tests

The project ships with a dependency-free headless test runner:

```sh
godot --headless --path . res://tests/TestRunner.tscn
```

It exits with code `0` when every test passes and `1` otherwise. Networking
smoke tests live in `tests/NetSmoke.tscn`.

## Developer tools

| Tool | Purpose | Invocation |
| --- | --- | --- |
| `tools/BalanceSim.tscn` | Runs many headless bot matches per gravity orientation and writes CSV + JSON summaries. | `godot --headless --fixed-fps 120 --path . res://tools/BalanceSim.tscn -- --sim-matches=1000 --orientation=0 --seconds=20` |
| `tools/GoalProbe.tscn` | Sanity-checks that every goal is reachable in each orientation. | `godot --headless --path . res://tools/GoalProbe.tscn` |
| `tools/PerfHarness.tscn` | Samples a real 3v3 bot match and writes a performance report. | `godot --headless --path . res://tools/PerfHarness.tscn -- --frames=600 --warmup=120` |

## Project layout

```
autoload/       GravityManager, Events bus, Settings, NetManager, Meta, Audio
car/            Car scene/script, tuning resources, boost and input
ball/           Ball scene/script and tuning
arena/          Arena, goals, boost pads and arena themes
match/          MatchController, match rules and kickoff flow
camera/         Chase, ball and free camera modes
bots/           Bot brain and difficulty tiers
net/            Prediction, snapshot codec, input buffer, debug overlay
matchmaking/    Glicko-2, matchmaker and matchmaking service
mutators/       Composable match mutators
cosmetics/      Item definitions and library
training/       Drills, drill library and training controller
replay/         Recording, storage, player and browser
ui/             Menus, HUD, previews and rank icons
vfx/            VFX service, shaders and effects
audio/          Procedural audio library, match audio and announcer WAVs
tests/          Headless test runner and net smoke tests
tools/          Balance, goal and performance harnesses
tasks/          Build task specifications (01-19)
docs/           Audio design and performance reports
```

## Design notes

- Gravity is never read from `ProjectSettings` at runtime; everything resolves
  through `GravityManager` (`gravity_dir`, `gravity_strength`, `up`).
- Physics runs in `_physics_process` / `_integrate_forces`; visuals and cameras
  consume interpolated transforms.
- Tuning lives in `Resource` files (`CarTuning.tres`, `BallTuning.tres`,
  `MatchRules.tres`) instead of magic numbers.
- Systems talk through the `Events` signal bus.
- The server owns ball, score, timer and gravity phase; clients predict only
  their own car.

## Documentation

- [`docs/audio.md`](docs/audio.md) — mix, buses and announcer design.
- [`docs/perf-report.md`](docs/perf-report.md) — measured performance results.
- [`PROMPT.md`](PROMPT.md) — master brief and architecture rules.
- [`tasks/`](tasks/) — implementation task list from core physics to launch QA.
