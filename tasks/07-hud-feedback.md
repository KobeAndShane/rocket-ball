# Task 07: HUD and player feedback
**Phase:** Supporting | **Depends on:** 05, 06

## Godot approach
- `Control`-based HUD in a `CanvasLayer`. Update on signals, not every frame.
- Use `TextureProgressBar` for boost, `Label` for timer and score.

## Checklist
- [ ] Boost meter, score, match timer
- [ ] Gravity-shift countdown bar and an arrow showing the next "down"
- [ ] Speed readout and supersonic indicator
- [ ] World-space name tags with team colour (use `Label3D` or projected `Control`)
- [ ] Off-screen ball and teammate indicators
- [ ] Event feed: goals, saves, demos, assists
- [ ] Centre-screen prompts for shift warning ("Gravity shifting in 3...")
- [ ] HUD scales with UI scale setting
- [ ] HUD rotates or re-anchors correctly with camera (stays screen-upright)

## Optimisation notes
- Avoid per-frame `Label.text` assignment when the value is unchanged.
- Use one atlas for HUD icons.

## Done when
- HUD is readable at 1080p and 4K, on 16:9 and ultrawide.
