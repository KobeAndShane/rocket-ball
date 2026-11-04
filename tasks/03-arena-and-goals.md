# Task 03: Arena and goals
**Phase:** Core | **Depends on:** 01, 02

## Goal
A rounded arena where every surface is drivable and every goal is reachable in any gravity direction.

## Design rules
- The arena is a box with large-radius fillets on **every** edge and corner (no flat 90-degree seams).
- Goals sit on two opposing faces of the arena along one axis. Gravity only rotates around the axis **perpendicular** to the goal axis, so goal faces are never floor or ceiling.
- Gravity cycle: floor > wall A > ceiling > wall B > floor. Goals stay at the far ends.

## Godot approach
- Build the arena in Blender, export `.glb`, and import with separate collision meshes (`-col` suffix) using `ConcavePolygonShape3D` for static geometry only.
- Static arena uses `StaticBody3D` on layer `arena`.
- `BoostPad.tscn` is an `Area3D` plus mesh. Pad positions defined symmetrically by a `Marker3D` set.

## Checklist
- [ ] Arena mesh with smooth fillets and a matching collision mesh
- [ ] Two goals with trigger volumes and back nets
- [ ] Boost pad layout: 6 large pads, 28 small pads (tune), mirrored for fairness
- [ ] Pad respawn timers (small ~4 s, large ~10 s)
- [ ] Pads re-orient with gravity (see Task 04)
- [ ] Kickoff spawn markers for each team, up to 3 per side
- [ ] Arena themes via swappable materials

## Optimisation notes
- Bake collision from a simplified mesh, not the render mesh.
- Use `MultiMeshInstance3D` for boost pad visuals.
- Use baked lighting (`LightmapGI`) or a single directional light plus a few omni lights.

## Done when
- A car can drive the entire arena surface without catching on seams.
- Pad layout is mirror-symmetric (script check passes).
