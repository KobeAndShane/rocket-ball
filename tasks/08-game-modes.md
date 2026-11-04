# Task 08: Game modes
**Phase:** Supporting | **Depends on:** 05

## Checklist
- [ ] 1v1, 2v2, 3v3 standard
- [ ] Free play (no timer, no opponents)
- [ ] Private match with custom `MatchRules`
- [ ] Mutators as composable `Resource` modifiers:
  - low gravity, big ball, fast shift, random shift, no boost, unlimited boost
- [ ] Mode select menu and mode descriptions
- [ ] Splitscreen local 2-player (optional, uses `SubViewport` per player; watch performance)

## Godot approach
- `MutatorBase.gd` with `apply(rules, world)` and `remove()`. Mutators stack by order.

## Done when
- Each mutator can be toggled in a private match and takes effect at kickoff.
