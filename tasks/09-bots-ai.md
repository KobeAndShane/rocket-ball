# Task 09: Bots and AI
**Phase:** Supporting | **Depends on:** 01-05

## Godot approach
- `BotBrain` produces the same input struct a human does (`throttle`, `steer`, `jump`, `boost`, `pitch/yaw/roll`). Bots never bypass physics.
- Decision layer: simple state machine or utility AI: `KICKOFF`, `CHASE`, `DEFEND`, `GRAB_BOOST`, `ROTATE_BACK`.
- Steering: aim at a predicted ball position (simulate ball for 1-2 s using the same gravity).
- All maths in local-gravity frame (`up = GravityManager.up`).

## Checklist
- [ ] Ball prediction using current and upcoming gravity
- [ ] Gravity-aware navigation (knows to drive on walls and ceiling)
- [ ] Role system: striker, support, goalie
- [ ] Difficulty tiers via `BotTiers.tres` (reaction delay, aim error, boost use, aerial skill)
- [ ] Bot teammates for solo play, disconnect fill-in
- [ ] Bot runs at reduced update rate (e.g. 30 Hz) to save CPU

## Done when
- Bot-only 3v3 match runs 5 minutes without stuck bots.
- Rookie loses to Pro more than 70% of the time over 20 simulated matches.
