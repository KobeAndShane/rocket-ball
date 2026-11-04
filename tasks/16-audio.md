# Task 16: Audio design
**Phase:** Polish | **Depends on:** 01-14

## Checklist
- [ ] Engine sound: pitch and volume driven by speed and boost (looping `AudioStreamPlayer3D` with pitch scaling)
- [ ] Ball hit sounds with 3+ impact tiers
- [ ] Gravity-shift cue: rising tone during warning, whoosh at the flip
- [ ] Crowd ambience and reactions, announcer lines
- [ ] Adaptive music (calm, tense, overtime) using `AudioStreamInteractive` or bus crossfades
- [ ] UI sounds
- [ ] Audio buses: Master, Music, SFX, Voice, Announcer, with ducking on goals
- [ ] 3D audio with sensible attenuation and Doppler

## Optimisation notes
- Limit simultaneous voices (`max_polyphony`). Use compressed OGG for music, WAV for short SFX.

## Done when
- Mix is balanced with all buses at default and sounds are never clipping.
