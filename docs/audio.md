# Audio design and mix

The match mix is built from procedural streams in `audio/AudioLibrary.gd`, with
imported announcer WAVs in `audio/announcer/`. Nothing is generated during a
match frame: loops and cues are cached the first time they are requested.

## Buses

| Bus | Default trim | Send | Role |
| --- | --- | --- | --- |
| Master | 0 dB | — | Final limiter (`-0.4 dBFS` ceiling) |
| Music | -3 dB | Master | Three adaptive layers, side-chain compressed |
| SFX | -1 dB | Master | Engines, impacts, crowd, shift cues |
| Voice | -2 dB | Master | Reserved for voice chat / player voice |
| Announcer | -2 dB | Master | Goal, overtime, demolition and praise lines |

`Audio` (autoload) adds an `AudioEffectLimiter` to Master and an
`AudioEffectCompressor` to Music whose side-chain is the Announcer bus. The
compressor ducks the music automatically for every callout without changing the
player's saved Music volume.

## Voice budget

| Source | Voices | Notes |
| --- | --- | --- |
| Engine loops | 1 per car (6 max in 3v3) | `AudioStreamPlayer3D`, `max_polyphony = 1` |
| Ball impacts | 8 pooled | 3D, `max_polyphony = 1`, round-robin |
| Announcer | 3 pooled | Non-positional, Announcer bus |
| Music | 3 | Calm / tense / overtime, always looping and crossfaded |
| Crowd | 1 loop + 1 cheer | Ambience and goal/overtime reaction |
| Shift cues | 2 | Rising warning and flip whoosh |

Total worst case is 24 concurrent voices, all capped at one instance per node.

## Engine

`MatchAudio.engine_pitch()` maps normalised speed and boost to a `0.72..1.76`
pitch range. `engine_volume_db()` maps the same values from `-24 dB` to `-4 dB`
before 3D attenuation. The local car sits at the listener, so it remains clear;
remote cars fade naturally with `ATTENUATION_INVERSE_DISTANCE` (`unit_size` 11 m,
`max_distance` 80 m). Doppler tracking uses the physics step for stable pitch
under 120 Hz physics.

## Impacts

`MatchAudio.tier_for_strength()` selects three tiers:

- `< 8` → `ball_light`
- `8..21.99` → `ball_medium`
- `>= 22` → `ball_heavy`

Hits are positioned in 3D and pitched slightly upward with strength. Eight
pooled voices prevent a pile-up in goal-mouth scrambles.

## Gravity shifts

- `Events.gravity_shift_warning` starts the 4 s rising tone on the Voice bus.
- `Events.gravity_shift_started` stops the warning, plays the whoosh and fires
  the "Gravity shift!" announcer line.
- `Events.gravity_shift_finished` clears the cue state.

## Adaptive music

`MatchAudio.music_state_for()` is a pure mapping used by the service and tests:

- overtime (state 5 or `in_overtime`) → `music_overtime`
- goal pause / replay → `music_tense`
- playing with ≤ 45 s left, or ≤ 90 s and a one-goal game → `music_tense`
- everything else → `music_calm`

The three layers are already playing; only their volumes move (`18 dB/s`). A
new match snaps to the correct layer so kickoff never starts with a silent
music bus.

## Announcer and subtitles

`AudioLibrary.ANNOUNCER_FILES` maps generated SAPI WAVs for goal, overtime,
demolition, nice shot, what a save, gravity shift and countdown. If a WAV is
missing or not imported, `AudioLibrary` synthesises a formant placeholder so
the mix still works on a clean checkout or unsupported platform.

Every announcer line also emits `Events.show_subtitle` with the text from
`AudioLibrary.announcer_line_for()`, so the HUD subtitle system mirrors the
audio for accessibility.

Praise lines are throttled to one every 7 s to keep the announcer from
chattering over gameplay.

## Done-when checks

Automated coverage in `tests/TestRunner.gd`:

- all five buses exist and route through Master;
- Master has a limiter and Music has an Announcer side-chain compressor;
- bus trims stay at or below unity for headroom;
- generated streams are cached and music loops;
- engine pitch/volume rise with speed and boost;
- three impact tiers and all shift/goal/overtime/countdown callouts fire;
- music switches to the overtime layer and crowd lifts during overtime.
