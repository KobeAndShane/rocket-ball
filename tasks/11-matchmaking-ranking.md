# Task 11: Matchmaking and ranking
**Phase:** Systems | **Depends on:** 10

## Checklist
- [ ] Casual and ranked queues
- [ ] MMR using Glicko-2 or Elo, with uncertainty for new players
- [ ] 10 placement matches
- [ ] Rank tiers and divisions, rank icons
- [ ] Region selection, ping-based matching, expanding search window
- [ ] Party matchmaking using average or max MMR rule
- [ ] Seasons with soft reset
- [ ] Leaver and smurf handling

## Godot approach
- Matchmaking service is **external** (small backend: Nakama, PlayFab, Steam lobbies, or a custom service). Godot talks via `HTTPRequest` or WebSocket.
- Game servers report results to the backend with a signed payload.

## Done when
- Simulated 1000-player queue produces matches within target time and balanced MMR spread.
