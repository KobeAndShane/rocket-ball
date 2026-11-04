# Task 15: Visual effects and art polish
**Phase:** Polish | **Depends on:** 01-14

## Checklist
- [ ] Gravity-shift effect: arena edge glow, colour tint, particle ripple, subtle chromatic aberration pulse
- [ ] Boost flames, ball trail, impact sparks, supersonic trail
- [ ] Goal explosions and celebrations
- [ ] Demolition effect
- [ ] Arena lighting, reflection probes, emissive accents
- [ ] Car and ball materials (PBR, team colour masks)
- [ ] Arena themes (at least 3)

## Godot approach
- `GPUParticles3D` for big effects, shared `ParticleProcessMaterial` resources. Pool effect nodes, never `instantiate()` per hit.
- Shaders in Godot shading language for tint and glow. Keep to one full-screen pass.
- Pre-warm particles during loading to avoid first-use hitches.

## Done when
- Effects stay readable and do not hide the ball. Frame time cost of all effects under 2 ms on target hardware.
