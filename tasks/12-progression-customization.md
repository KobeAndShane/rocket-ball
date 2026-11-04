# Task 12: Progression and customization
**Phase:** Systems | **Depends on:** 05, 10

## Checklist
- [ ] Player level and XP from match results
- [ ] Cosmetics: car bodies, wheels, boost trails, decals, goal explosions, antennas
- [ ] Inventory and loadout presets
- [ ] Unlock-based store (cosmetic only, no gameplay stat changes)
- [ ] Daily and weekly challenges
- [ ] Season pass with free and premium tracks
- [ ] Player profile and stats page

## Godot approach
- Cosmetics are `Resource` definitions (`CosmeticItem.tres`) with a scene and metadata. Load on demand with `ResourceLoader.load_threaded_request`.
- Save data as JSON or `ConfigFile`, with a version field and migration function. Cloud sync through the backend.
- Hitbox is fixed per body class so cosmetics never change gameplay.

## Done when
- Equip, unequip and preview work in menu and in match, loadout replicates to other clients.
