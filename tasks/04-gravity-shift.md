# Task 04: Gravity-shift mechanic (the twist)
**Phase:** Core | **Depends on:** 01-03

## Goal
Gravity rotates every 30 s with a smooth, readable, fair transition.

## Godot approach
- `GravityManager` autoload owns:
  - `gravity_dir: Vector3`, `up: Vector3`
  - `phase_index: int`, `time_to_shift: float`
  - `signal shift_warning(seconds_left, next_dir)`, `signal shift_started`, `signal shift_finished`
- Gravity phase cycle stored as an array of `Vector3`. Order and interval from `MatchRules.tres`.
- **Transition (2 s):** lerp `gravity_dir` with `slerp` between old and new directions. Bodies keep receiving gravity from the blended vector, so motion stays continuous.
- Camera and HUD rotate to match (see Tasks 06, 07).
- In multiplayer the **server** advances the phase and broadcasts `phase_index` + server tick; clients derive blend locally.

## Checklist
- [ ] Phase timer with visible countdown (starts a 5 s warning)
- [ ] Gravity blend over 2 s with easing
- [ ] Cars, ball, boost pads all follow `GravityManager.up`
- [ ] Airborne cars: keep velocity, gravity blends underneath them
- [ ] Cars on surface that becomes "ceiling": detach smoothly, no snap
- [ ] Optional: brief boost refill pulse at each shift to reward the transition
- [ ] Per-match settings: interval, fixed or random order, transition length, enabled phases
- [ ] Debug overlay showing gravity vector and phase

## Fairness rules
- Shifts are announced to both teams at the same server tick.
- Ball and cars are never teleported.
- Goal axis unaffected (see Task 03).

## Optimisation notes
- Gravity is read from a single cached `Vector3`. Do not call methods per body per frame.

## Done when
- 10-minute soak test with no cars stuck on a surface after a shift.
- Transition feels smooth at 60 and 120 FPS.
- Tests: phase order, interval timing, deterministic phase from seed.
