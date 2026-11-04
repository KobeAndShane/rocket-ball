# Task 02: Ball physics
**Phase:** Core | **Depends on:** 01

## Goal
A heavy, bouncy ball with predictable, satisfying hits.

## Godot approach
- `Ball` is a `RigidBody3D` with `SphereShape3D`, `gravity_scale = 0`, custom gravity in `_integrate_forces`.
- Physics material: bounce around 0.6, low friction. Tune in `BallTuning.tres`.
- Continuous collision detection on (`continuous_cd = true`) to prevent tunnelling at high speed.
- Clamp max speed in `_integrate_forces`.

## Checklist
- [ ] Mass, bounce, friction, linear and angular damping, max speed
- [ ] Car-to-ball impulse: use contact point and relative velocity, add upward bias along local up for pop hits
- [ ] Spin transfer from hit offset
- [ ] Ball bounces correctly on walls, ceiling and curved corners
- [ ] `Goal` detection via `Area3D`, emits `Events.goal_scored(team)`
- [ ] `reset_to_kickoff()` function (position, velocity, spin)
- [ ] Ball radius and scale configurable for the "big ball" mutator

## Optimisation notes
- Only one ball body, so keep the collider simple.
- Do not use `_process` for ball logic. Visual mesh interpolation only.

## Done when
- Ball never tunnels through wall or goal at max speed.
- Hits feel consistent under gravity in all 4 orientations.
- Tests: max speed clamp, goal event fires once per goal.
