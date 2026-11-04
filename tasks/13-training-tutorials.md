# Task 13: Training and tutorials
**Phase:** Systems | **Depends on:** 01-09

## Checklist
- [ ] Onboarding: drive, boost, jump, dodge, ball touch
- [ ] Gravity-shift tutorial with guided drills ("drive up the wall", "score while upside down")
- [ ] Training packs: shots, saves, wall plays, aerials, shift drills
- [ ] Training editor: place ball, set velocity, save as pack
- [ ] Replay browser: save, load, scrub, free camera

## Godot approach
- Replays store **inputs + initial state + seed**, not full states, and re-simulate. Pin physics version for compatibility, or store compact snapshots every N ticks as a fallback.
- Training scripts use a small `DrillBase` class with `setup()`, `check_success()`, `reset()`.

## Done when
- A new player can finish onboarding in under 10 minutes and reach their first goal.
