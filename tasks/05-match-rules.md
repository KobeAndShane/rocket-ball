# Task 05: Match rules and game loop
**Phase:** Core | **Depends on:** 01-04

## Goal
A complete match from kickoff to results.

## Godot approach
- `MatchController` is a state machine: `LOBBY > COUNTDOWN > PLAYING > GOAL_PAUSE > REPLAY > OVERTIME > POSTGAME`.
- Use an enum plus `match` blocks. Emit state changes via `Events`.
- `MatchRules.tres` holds time, overtime, mutators.

## Checklist
- [ ] Kickoff: spawn cars at markers, freeze, 3-2-1 countdown, release
- [ ] 5:00 timer, pause on goal, resume on kickoff
- [ ] Gravity phase resets to floor on kickoff, timer restarts
- [ ] Score tracking and goal events
- [ ] Overtime golden goal
- [ ] Demolition: supersonic collision destroys opponent, respawn after 3 s
- [ ] Postgame screen: scores, MVP, stats (goals, saves, assists, shots)
- [ ] Stats collector listening to `Events`

## Done when
- Full offline match plays start to finish with correct scoring and overtime.
- Tests: timer, overtime trigger, demo respawn, score reset.
