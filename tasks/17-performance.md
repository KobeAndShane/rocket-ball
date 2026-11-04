# Task 17: Performance and optimisation
**Phase:** Polish | **Depends on:** 01-16 (apply continuously)

## Targets
60 FPS minimum on mid-range hardware (e.g. GTX 1060 / integrated modern APU), 120 FPS on good hardware, load under 10 s.

## Physics
- [ ] 120 Hz tick, verify the physics step never exceeds ~4 ms
- [ ] Few bodies: 6 cars + 1 ball + static arena
- [ ] Primitive or convex colliders for dynamic bodies, concave only for static arena
- [ ] Collision layers/masks minimal
- [ ] Physics interpolation enabled for rendering (`physics_interpolation` in project settings)

## Rendering
- [ ] Profile with Godot Profiler, Monitors and RenderDoc
- [ ] `MultiMeshInstance3D` for pads, crowd, repeated props
- [ ] Occlusion culling and visibility ranges for crowd and details
- [ ] LOD for car meshes, mesh simplification for arena props
- [ ] Baked lightmaps, limit real-time shadows to one directional cascade
- [ ] Reduce overdraw from transparent effects
- [ ] Offer FSR / render-scale options

## Scripts
- [ ] Static typing everywhere
- [ ] No allocations in `_physics_process` (reuse arrays and vectors)
- [ ] Use signals instead of polling
- [ ] Move hot loops (bot prediction, snapshot packing) to C# or GDExtension only if profiling proves it
- [ ] Object pools for particles, event feed items, HUD markers

## Loading and memory
- [ ] Threaded loading (`ResourceLoader.load_threaded_request`)
- [ ] Compress textures (VRAM compression, mipmaps), use atlases
- [ ] Track memory with the Monitors panel

## Network stress
- [ ] Test with 150 ms ping, 5% loss, 30 ms jitter
- [ ] Bandwidth cap check

## Done when
- A performance report (frame time, physics time, memory, bandwidth) is committed to `docs/perf-report.md` and meets targets.
