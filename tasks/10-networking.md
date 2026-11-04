# Task 10: Networking and multiplayer
**Phase:** Systems | **Depends on:** 01-09

## Godot approach
- `ENetMultiplayerPeer`, dedicated headless server (`--headless` export) or listen server.
- **Server authoritative** for ball, score, timer, gravity phase, demos.
- Clients send **inputs** (tick-stamped) at physics rate. Server simulates, sends **snapshots** at 60 Hz (delta compressed).
- Client-side prediction for own car, reconciliation by replaying unacknowledged inputs after each snapshot.
- Remote cars and ball: snapshot interpolation with 2-3 tick buffer. Optional ball extrapolation or soft prediction on touch.
- Use unreliable channels for snapshots and inputs, reliable for events (goal, phase change).

## Checklist
- [ ] Network tick counter shared by server and clients
- [ ] Input buffer and redundancy (send last 3 inputs per packet)
- [ ] Snapshot format: quantised positions, packed quaternions (smallest-three), velocity
- [ ] Prediction and reconciliation with smoothing of small errors
- [ ] Gravity phase sync via server tick
- [ ] Lobby, party, invites, ready check
- [ ] Reconnect handling and disconnect penalty
- [ ] Server-side validation: speed limits, boost use, input rate
- [ ] Network debug overlay: ping, loss, tick error, bandwidth
- [ ] Artificial latency and loss tool (for tests)

## Optimisation notes
- Target under 30 KB/s per client.
- Use `PackedByteArray` and `StreamPeerBuffer` for custom serialisation, avoid Dictionaries in hot paths.
- Physics must be deterministic enough on server and client to keep reconciliation small (same tick rate, same Jolt version).

## Done when
- Playable at 120 ms ping and 3% loss with no visible rubber-banding on own car.
- 3v3 test with 6 clients stable for 20 minutes.
