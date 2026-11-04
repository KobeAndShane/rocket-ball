# MASTER PROMPT: Rocket League: Gravity Shift (Godot 4)

You are a senior Godot 4 gameplay and netcode engineer. Build **Gravity Shift**, a Rocket League-style car-soccer game where the arena's gravity rotates every 30 seconds. Work through the task files in `tasks/` **in order**. Do not start a task until the previous task's "Done when" list passes.

## 1. Game concept
Cars play soccer with a giant ball inside a rounded arena. Every 30 seconds gravity rotates to a new "down" direction (floor, wall, ceiling, opposite wall). Every surface is a pitch. Goals stay reachable in every orientation. Players constantly re-read the field, so wall and aerial play is the main skill.

## 2. Technical targets
| Item | Target |
|---|---|
| Engine | Godot 4.4 or newer, GDScript first, C# or GDExtension only for proven hotspots |
| Physics | Jolt Physics (Project Settings > Physics > 3D > Physics Engine = Jolt) |
| Physics tick | 120 Hz (`physics_ticks_per_second = 120`) |
| Render | Forward+ on PC, Mobile or Compatibility renderer as fallback option |
| Framerate | 60 FPS on mid-range hardware, 120 FPS on good hardware |
| Players | up to 6 (3v3), dedicated or listen server, server-authoritative |
| Network | ENet via `MultiplayerAPI`, 60 Hz state snapshots, client-side prediction |

## 3. Architecture rules (apply to every task)
1. **One source of truth for gravity.** A `GravityManager` autoload holds `gravity_dir: Vector3` and `gravity_strength: float`. Nothing else reads `ProjectSettings` gravity. Set `gravity_scale = 0` on all rigid bodies and apply gravity manually in `_integrate_forces`.
2. **Local "up" everywhere.** Never hardcode `Vector3.UP`. Use `-GravityManager.gravity_dir` or `GravityManager.up`.
3. **Physics in `_physics_process` or `_integrate_forces` only.** Visuals and cameras read interpolated transforms.
4. **Data-driven.** Tuning values live in `Resource` files (`CarTuning.tres`, `BallTuning.tres`, `MatchRules.tres`), never magic numbers in scripts.
5. **Signals up, calls down.** Systems communicate through a small `Events` autoload (signal bus) to avoid tight coupling.
6. **Deterministic where it matters.** Server owns ball, score, timer, gravity phase. Clients predict only their own car.
7. **Optimise from day one.** Follow the performance rules in `tasks/17-performance.md` while building, not only at the end.
8. **Typed GDScript.** Use static typing (`var x: float`, `func f() -> void`), it is faster and safer.

## 4. Recommended project layout
```
res://
  autoload/        GravityManager.gd, Events.gd, Settings.gd, NetManager.gd
  car/             Car.tscn, Car.gd, CarTuning.tres, BoostComponent.gd
  ball/            Ball.tscn, Ball.gd, BallTuning.tres
  arena/           Arena.tscn, BoostPad.tscn, Goal.tscn
  match/           MatchController.gd, MatchRules.tres, Kickoff.gd
  camera/          ChaseCamera.tscn, ChaseCamera.gd
  ui/              HUD.tscn, menus/, theme/
  bots/            BotBrain.gd, BotTiers.tres
  net/             Prediction.gd, Snapshot.gd, Lobby.gd
  meta/            Profile.gd, Ranking.gd, Shop.gd, Cosmetics/
  audio/           buses, banks, sfx/, music/
  vfx/             particles, shaders
  tests/           GUT tests
```

## 5. Task order
| # | File | Phase |
|---|---|---|
| 01 | `tasks/01-vehicle-physics.md` | Core |
| 02 | `tasks/02-ball-physics.md` | Core |
| 03 | `tasks/03-arena-and-goals.md` | Core |
| 04 | `tasks/04-gravity-shift.md` | Core (the twist) |
| 05 | `tasks/05-match-rules.md` | Core |
| 06 | `tasks/06-camera.md` | Supporting |
| 07 | `tasks/07-hud-feedback.md` | Supporting |
| 08 | `tasks/08-game-modes.md` | Supporting |
| 09 | `tasks/09-bots-ai.md` | Supporting |
| 10 | `tasks/10-networking.md` | Systems |
| 11 | `tasks/11-matchmaking-ranking.md` | Systems |
| 12 | `tasks/12-progression-customization.md` | Systems |
| 13 | `tasks/13-training-tutorials.md` | Systems |
| 14 | `tasks/14-settings-accessibility.md` | Systems |
| 15 | `tasks/15-visual-effects.md` | Polish |
| 16 | `tasks/16-audio.md` | Polish |
| 17 | `tasks/17-performance.md` | Polish |
| 18 | `tasks/18-playtesting-balance.md` | Polish |
| 19 | `tasks/19-qa-launch.md` | Polish |

## 6. Working method for each task
1. Read the task file fully.
2. List the files you will create or change.
3. Implement the smallest playable slice first, then expand through the checklist.
4. Write or update tests listed in the task.
5. Run the "Done when" checks and report results.
6. Commit with message `task-NN: <summary>`.

## 7. Definition of done for the whole project
- A 3v3 online match runs at 60+ FPS with stable gravity shifts for all clients.
- No gravity orientation favours one team (verified in Task 18).
- All settings, accessibility options and tutorials work.
- Builds export cleanly for Windows, Linux and at least one console or mobile target if scoped.
