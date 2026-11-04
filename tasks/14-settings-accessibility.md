# Task 14: Settings and accessibility
**Phase:** Systems | **Depends on:** 06, 07

## Checklist
- [ ] Video: resolution, window mode, quality presets, FPS cap, VSync, MSAA / FSR / TAA, render scale
- [ ] Audio: master, music, SFX, voice, announcer buses
- [ ] Controls: remap, deadzones, sensitivity curves, controller calibration
- [ ] Colourblind modes (deuteranopia, protanopia, tritanopia) via post-process shader
- [ ] Team colour overrides
- [ ] **Reduced motion:** slower and damped gravity camera rotation, option to keep the camera horizon fixed
- [ ] Screen-shake and flash intensity sliders
- [ ] Subtitles, text size, UI scale, high-contrast HUD
- [ ] Chat filters and mute
- [ ] Settings saved in `user://settings.cfg` via `ConfigFile`, applied at boot

## Done when
- Every setting persists, applies live where possible, and has a reset-to-default.
