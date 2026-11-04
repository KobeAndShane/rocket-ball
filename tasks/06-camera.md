# Task 06: Camera system
**Phase:** Supporting | **Depends on:** 01-05

## Goal
A chase camera that stays readable while the world rotates.

## Godot approach
- `ChaseCamera` (`Camera3D` on a pivot `Node3D`) updated in `_process` using **interpolated** car transform.
- Camera "up" vector comes from `GravityManager.up`, smoothed with `slerp`.
- Ball cam: look-at toward the ball with a blend to car forward.

## Checklist
- [ ] Ball cam and car cam toggle
- [ ] Smooth camera rotation during gravity shift (no snap, no roll flip)
- [ ] Adjustable FOV, distance, height, angle, stiffness, swivel speed
- [ ] Look-behind button
- [ ] Spring-arm style collision avoidance with arena walls
- [ ] Goal replay cameras (orbit, sideline, ball chase)
- [ ] Spectator and free camera
- [ ] Reduced-motion mode: shorter, damped rotation (see Task 14)

## Done when
- No gimbal flips or sudden jumps during any of the 4 gravity transitions.
- Settings persist between sessions.
