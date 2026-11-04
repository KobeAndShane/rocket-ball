extends SceneTree
## Content tool: writes one CosmeticItem.tres per catalog entry.
## Run with:
##   godot --headless --path . --script res://tools/CosmeticBuilder.gd

func _initialize() -> void:
	var target: String = ProjectSettings.globalize_path(CosmeticLibrary.ITEM_DIR)
	var dir_err: Error = DirAccess.make_dir_recursive_absolute(target)
	if dir_err != OK and dir_err != ERR_ALREADY_EXISTS:
		push_error("Could not create %s (%d)" % [target, dir_err])
		quit(1)
		return
	var saved: int = 0
	for item: CosmeticItem in CosmeticLibrary.build_defaults():
		var path: String = "%s/%s.tres" % [CosmeticLibrary.ITEM_DIR, item.id]
		var err: Error = ResourceSaver.save(item, path)
		if err == OK:
			saved += 1
		else:
			push_error("Failed to save %s (%d)" % [path, err])
	print("CosmeticBuilder: saved %d items to %s" % [saved, CosmeticLibrary.ITEM_DIR])
	quit(0 if saved >= CosmeticLibrary.SLOTS.size() else 1)
