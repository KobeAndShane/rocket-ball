# Task 18: Playtesting and balance
**Phase:** Polish | **Depends on:** 01-17

## Checklist
- [ ] Tune shift interval (try 20, 30, 45 s), boost amounts, ball speed, transition length
- [ ] Prove orientation fairness: run 1000 bot matches per orientation, win rate of both teams within 48-52%
- [ ] Find and fix exploits: corner traps, goal-line stalls, wall-ceiling stuck positions, demo spam
- [ ] Add "unstuck" rule: auto-reset if a car is immobile for 5 s
- [ ] Closed beta with telemetry: heatmaps, goal locations, shift-time goals, quit points
- [ ] Survey: motion sickness, readability, fun
- [ ] Iterate on feedback and log every change in `docs/balance-log.md`

## Godot approach
- Headless simulation mode (`--headless --sim-matches=N`) that runs bot matches fast and writes CSV results.

## Done when
- Fairness criteria met and top 10 exploit reports resolved.
