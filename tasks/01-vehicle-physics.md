
# Task 01: Vehicle physics and controls
**Phase:** Core | **Depends on:** none

## Goal
A car that feels responsive and arcade-like, driving on any surface and flying in the air.

## Godot approach
- `Car` is a `RigidBody3D` (not `VehicleBody3D`, which is too floaty for this genre). Set `gravity_scale = 0`, apply gravity in `_integrate_forces(state)` using `GravityManager.gravity_dir`.
- Use 4 `RayCast3D` or `PhysicsDirectSpaceState3D.intersect_ray` calls (one per wheel) to detect ground, compute suspension and "wheels on surface" state.
- Use a simple box or convex hull collider, not a mesh collider.
- Stick-to-surface force: when 3+ wheels touch, apply a small force along the surface normal so cars hold walls.

## Checklist
- [ ] Throttle, brake, reverse, steering with speed-sensitive turn rate
- [ ] Handbrake / drift with reduced lateral grip
- [ ] Jump, double jump (timed window), dodge/flip in 8 directions
- [ ] Air control: pitch, yaw, roll, plus air roll button
- [ ] `BoostComponent`: meter 0-100, consumption rate, boost force, supersonic threshold
- [ ] Input actions in `InputMap` (`throttle`, `brake`, `steer_left/right`, `jump`, `boost`, `handbrake`, `air_roll`, `ball_cam`, etc.)
- [ ] Remappable bindings saved via `Settings` autoload
- [ ] `CarTuning.tres` resource holds all numbers
- [ ] Car state enum: `GROUNDED`, `AIRBORNE`, `DODGING`, `DEMOLISHED`

## Optimisation notes
- Sleep disabled, but use `can_sleep = false` only on cars and ball.
- Cache `get_world_3d().direct_space_state` once per frame.
- Use collision layers: `car`, `ball`, `arena`, `pad`, `goal`. Wheel rays hit `arena` only.

## Done when
- Car drives up a wall and onto the ceiling when gravity is manually flipped by a debug key.
- Double jump and dodge feel consistent at 120 Hz.
- Unit tests cover boost meter, jump window and dodge direction mapping.
