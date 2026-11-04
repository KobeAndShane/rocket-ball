extends Control
## Main menu and all non-match panels (modes, settings, online, locker, challenges, ranked).

const MATCH_SCENE := preload("res://match/Match.tscn")
const MATCH_RULES := preload("res://match/MatchRules.tres")

var content: VBoxContainer
var profile_label: Label
var status_label: Label
var _updating: bool = false
var _match: MatchController
var _mode_description: Label
var _queue_status: Label
var _preview_loadout: Dictionary = {}


func _ready() -> void:
	NetManager.match_started.connect(_on_net_match_started)
	if NetManager.dedicated_server:
		_start_dedicated_server()
		return
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	CosmeticLibrary.preload_async()
	_build()
	Events.profile_changed.connect(_refresh_profile)
	Events.network_status_changed.connect(_on_network_status)
	Events.notification.connect(_on_notification)
	Events.level_up.connect(_on_level_up)
	Events.player_joined.connect(func(_id: int, _name: String) -> void: _refresh_online())
	Events.player_left.connect(func(_id: int) -> void: _refresh_online())
	Matchmaking.queue_changed.connect(_on_queue_changed)
	Matchmaking.queue_progress.connect(_on_queue_progress)
	Matchmaking.match_found.connect(_on_matchmaking_found)
	_refresh_profile()
	_show_home()


func _on_level_up(level: int) -> void:
	if status_label != null:
		status_label.text = "Level %d reached" % level
	_refresh_profile()


func _build() -> void:
	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = load("res://vfx/menu_background.gdshader")
	bg.material = mat
	add_child(bg)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 54)
	margin.add_theme_constant_override("margin_right", 54)
	margin.add_theme_constant_override("margin_top", 40)
	margin.add_theme_constant_override("margin_bottom", 40)
	add_child(margin)
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 34)
	margin.add_child(hbox)
	# Left column: identity and navigation. Wrapped in a scroll so the growing
	# progression pages never push the profile card off-screen.
	var left_scroll := ScrollContainer.new()
	left_scroll.custom_minimum_size = Vector2(390.0, 0.0)
	left_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	hbox.add_child(left_scroll)
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 10)
	left_scroll.add_child(left)
	var title := _label("GRAVITY", 54, Color(0.92, 0.98, 1.0))
	title.add_theme_constant_override("outline_size", 10)
	left.add_child(title)
	var title2 := _label("SHIFT", 54, Color(0.15, 0.85, 1.0))
	title2.add_theme_constant_override("outline_size", 10)
	left.add_child(title2)
	var sub := _label("Car soccer. Every surface is a pitch.", 15, Color(0.6, 0.72, 0.85))
	left.add_child(sub)
	left.add_child(_spacer(14))
	left.add_child(_nav_button("QUICK PLAY  -  3v3", _quick_play))
	left.add_child(_nav_button("1v1", func() -> void: _start_match(1, 1, "1v1")))
	left.add_child(_nav_button("2v2", func() -> void: _start_match(2, 1, "2v2")))
	left.add_child(_nav_button("FREE PLAY", _start_free_play))
	left.add_child(_nav_button("PRIVATE MATCH", _show_private))
	left.add_child(_nav_button("TRAINING", _open_training))
	left.add_child(_nav_button("RANKED", _show_ranked))
	left.add_child(_nav_button("ONLINE", _show_online))
	left.add_child(_nav_button("LOCKER", _show_locker))
	left.add_child(_nav_button("CHALLENGES", _show_challenges))
	left.add_child(_nav_button("PROFILE & STATS", _show_profile))
	left.add_child(_nav_button("SEASON PASS", _show_season_pass))
	left.add_child(_nav_button("SETTINGS", _show_settings))
	left.add_child(_nav_button("QUIT", func() -> void: get_tree().quit()))
	left.add_child(_spacer(10))
	var profile_panel := PanelContainer.new()
	profile_panel.add_theme_stylebox_override("panel", _style(Color(0.03, 0.05, 0.1, 0.75), Color(0.15, 0.7, 1.0, 0.35), 10))
	left.add_child(profile_panel)
	profile_label = _label("", 14, Color(0.72, 0.82, 0.95))
	profile_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	profile_panel.add_child(profile_label)
	# Right column: contextual panel.
	var right_panel := PanelContainer.new()
	right_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_panel.add_theme_stylebox_override("panel", _style(Color(0.02, 0.035, 0.075, 0.82), Color(0.15, 0.7, 1.0, 0.3), 16))
	hbox.add_child(right_panel)
	var right_margin := MarginContainer.new()
	right_margin.add_theme_constant_override("margin_left", 30)
	right_margin.add_theme_constant_override("margin_right", 30)
	right_margin.add_theme_constant_override("margin_top", 24)
	right_margin.add_theme_constant_override("margin_bottom", 24)
	right_panel.add_child(right_margin)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right_margin.add_child(scroll)
	content = VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 10)
	scroll.add_child(content)
	status_label = _label("Ready", 13, Color(0.5, 0.75, 0.9))
	status_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	status_label.offset_left = -420.0
	status_label.offset_top = -32.0
	status_label.offset_right = -24.0
	status_label.offset_bottom = -8.0
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(status_label)


func _refresh_profile() -> void:
	if profile_label == null:
		return
	var p: Dictionary = Meta.profile
	profile_label.text = "PILOT  %s\nLEVEL %d   SEASON PASS %d   %s\n%d credits\nMatches %d   Wins %d   Goals %d" % [
		str(p.get("name", "Pilot")),
		int(p.get("level", 1)),
		Meta.season_pass_level(),
		Meta.rank_name(),
		int(p.get("credits", 0)),
		int(p.get("matches", 0)),
		int(p.get("wins", 0)),
		int(p.get("goals", 0)),
	]


func _refresh_online() -> void:
	if content == null or not content.has_meta("online"):
		return
	_show_online()


func _on_network_status(text: String) -> void:
	if status_label != null:
		status_label.text = text


func _on_notification(text: String) -> void:
	if status_label != null:
		status_label.text = text
		var tw := create_tween()
		tw.tween_interval(4.0)
		tw.tween_property(status_label, "modulate:a", 0.55, 0.5)


# --- Navigation --------------------------------------------------------------

func _clear_content() -> void:
	content.remove_meta("online")
	content.remove_meta("ranked")
	_queue_status = null
	_preview_loadout.clear()
	for child in content.get_children():
		child.queue_free()


func _show_home() -> void:
	_clear_content()
	content.add_child(_heading("WELCOME TO THE SHIFT"))
	content.add_child(_body("Gravity rotates every 30 seconds. The floor becomes a wall, the wall becomes the ceiling. Goals stay at the ends of the arena, so the only constant is your car."))
	content.add_child(_spacer(8))
	content.add_child(_bullet("Drive on any surface", "Wheels stick to walls and ceilings. Gravity is your compass, not your limit."))
	content.add_child(_bullet("Read the shift", "A five second warning shows the next gravity direction. Use it to reposition."))
	content.add_child(_bullet("Boost, jump, dodge", "Classic car-soccer controls with a full air-control system."))
	content.add_child(_bullet("Play your way", "1v1, 2v2, 3v3, free play, or a private match with stacking mutators."))
	content.add_child(_spacer(10))
	var hint := _label("Quick Play starts a 3v3 match with bots. Press Esc in a match to pause.", 14, Color(0.55, 0.7, 0.85))
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(hint)


func _show_settings() -> void:
	_clear_content()
	content.add_child(_heading("SETTINGS"))
	content.add_child(_body("Changes apply immediately and are saved to user://settings.cfg."))
	content.add_child(_section("VIDEO"))
	content.add_child(_option("Window mode", "video/window_mode", ["Windowed", "Fullscreen", "Exclusive fullscreen"]))
	content.add_child(_option("Quality", "video/quality", ["Low", "Medium", "High", "Ultra"]))
	content.add_child(_option("MSAA", "video/msaa", ["Off", "2x", "4x", "8x"]))
	content.add_child(_option("Upscaler", "video/upscaler", ["Off", "FSR 1.0"]))
	content.add_child(_slider("Render scale", "video/render_scale", 0.5, 1.5, 0.05))
	content.add_child(_slider("FPS cap (0 = unlimited)", "video/fps_cap", 0.0, 240.0, 30.0))
	content.add_child(_check("VSync", "video/vsync"))
	content.add_child(_section("AUDIO"))
	content.add_child(_slider("Master", "audio/master", 0.0, 1.0, 0.01))
	content.add_child(_slider("Music", "audio/music", 0.0, 1.0, 0.01))
	content.add_child(_slider("SFX", "audio/sfx", 0.0, 1.0, 0.01))
	content.add_child(_slider("Announcer", "audio/announcer", 0.0, 1.0, 0.01))
	content.add_child(_section("CAMERA & ACCESSIBILITY"))
	content.add_child(_slider("Field of view", "camera/fov", 70.0, 120.0, 1.0))
	content.add_child(_slider("Camera distance", "camera/distance", 4.0, 12.0, 0.1))
	content.add_child(_slider("Camera height", "camera/height", 0.5, 5.0, 0.1))
	content.add_child(_check("Ball cam", "camera/ball_cam"))
	content.add_child(_check("Reduced motion", "a11y/reduced_motion"))
	content.add_child(_check("Keep camera horizon fixed", "a11y/fixed_horizon"))
	content.add_child(_slider("Screen shake", "a11y/screen_shake", 0.0, 1.0, 0.05))
	content.add_child(_slider("Flash intensity", "a11y/flash_intensity", 0.5, 1.5, 0.05))
	content.add_child(_slider("UI scale", "a11y/ui_scale", 0.7, 1.5, 0.05))
	content.add_child(_slider("Text size", "a11y/text_scale", 0.8, 1.5, 0.05))
	content.add_child(_option("Colourblind mode", "a11y/colorblind_mode", ["Off", "Deuteranopia", "Protanopia", "Tritanopia"]))
	content.add_child(_check("High contrast HUD", "a11y/high_contrast"))
	content.add_child(_check("Subtitles", "a11y/subtitles"))
	content.add_child(_section("CONTROLS"))
	content.add_child(_slider("Controller deadzone", "controls/deadzone", 0.0, 0.5, 0.01))
	content.add_child(_slider("Steer sensitivity", "controls/steer_sensitivity", 0.5, 2.0, 0.05))
	content.add_child(_spacer(12))
	var reset := _nav_button("RESET TO DEFAULTS", func() -> void:
		Settings.reset_to_defaults()
		_show_settings()
	)
	content.add_child(reset)


func _show_online() -> void:
	_clear_content()
	content.set_meta("online", true)
	content.add_child(_heading("ONLINE"))
	var status := "Offline" if NetManager.is_offline else ("Hosting" if NetManager.is_server else "Connected")
	content.add_child(_body("Session: %s   Peers: %d" % [status, NetManager.players.size()]))
	content.add_child(_spacer(6))
	var name_row := HBoxContainer.new()
	name_row.add_child(_label("Name", 15, Color(0.7, 0.82, 0.95)))
	var name_edit := LineEdit.new()
	name_edit.text = str(Meta.profile.get("name", "Pilot"))
	name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_edit.text_submitted.connect(func(text: String) -> void:
		Meta.set_player_name(text)
		_refresh_profile()
	)
	name_row.add_child(name_edit)
	content.add_child(name_row)
	var ip_row := HBoxContainer.new()
	ip_row.add_child(_label("Address", 15, Color(0.7, 0.82, 0.95)))
	var ip_edit := LineEdit.new()
	ip_edit.text = "127.0.0.1"
	ip_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ip_row.add_child(ip_edit)
	ip_row.add_child(_label("Port", 15, Color(0.7, 0.82, 0.95)))
	var port_edit := LineEdit.new()
	port_edit.text = "7777"
	port_edit.custom_minimum_size = Vector2(90.0, 0.0)
	ip_row.add_child(port_edit)
	content.add_child(ip_row)
	content.add_child(_spacer(4))
	content.add_child(_section("LOBBY"))
	if NetManager.players.is_empty():
		content.add_child(_body("No peers connected."))
	else:
		for peer_id: int in NetManager.players.keys():
			var entry: Dictionary = NetManager.players[peer_id]
			var you := " (you)" if peer_id == NetManager.local_peer_id else ""
			var ready_text := "READY" if bool(entry.get("ready", false)) else "not ready"
			content.add_child(_body("#%d  %s%s   Team %d   %s" % [
				peer_id,
				str(entry.get("name", "Pilot")),
				you,
				int(entry.get("team", 1)),
				ready_text,
			]))
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 12)
	var host_btn := _nav_button("HOST", func() -> void:
		var err := NetManager.host(int(port_edit.text))
		if err == OK:
			_show_online()
		else:
			status_label.text = "Host failed: %d" % err
	)
	host_btn.custom_minimum_size = Vector2(140.0, 46.0)
	buttons.add_child(host_btn)
	var join_btn := _nav_button("JOIN", func() -> void:
		var err := NetManager.join(ip_edit.text, int(port_edit.text))
		if err != OK:
			status_label.text = "Join failed: %d" % err
		else:
			_show_online()
	)
	join_btn.custom_minimum_size = Vector2(140.0, 46.0)
	buttons.add_child(join_btn)
	var start_btn := _nav_button("START 3v3", func() -> void:
		if NetManager.is_server and not NetManager.is_offline:
			_start_match(3, 1, "Online Host")
	)
	start_btn.custom_minimum_size = Vector2(180.0, 46.0)
	start_btn.disabled = NetManager.is_offline or not NetManager.is_server
	buttons.add_child(start_btn)
	content.add_child(buttons)
	var lobby_buttons := HBoxContainer.new()
	lobby_buttons.add_theme_constant_override("separation", 12)
	var local_ready: bool = bool(NetManager.players.get(NetManager.local_peer_id, {}).get("ready", false))
	var ready_btn := _nav_button("UNREADY" if local_ready else "READY", func() -> void:
		NetManager.set_ready(NetManager.local_peer_id, not local_ready)
		_show_online()
	)
	ready_btn.custom_minimum_size = Vector2(160.0, 42.0)
	ready_btn.disabled = NetManager.is_offline
	lobby_buttons.add_child(ready_btn)
	var invite_btn := _nav_button("INVITE ALL", func() -> void:
		NetManager.invite_all()
		_show_online()
	)
	invite_btn.custom_minimum_size = Vector2(160.0, 42.0)
	invite_btn.disabled = not NetManager.is_server or NetManager.is_offline
	lobby_buttons.add_child(invite_btn)
	var leave_btn := _nav_button("LEAVE", func() -> void:
		NetManager.leave()
		_show_online()
	)
	leave_btn.custom_minimum_size = Vector2(140.0, 42.0)
	leave_btn.disabled = NetManager.is_offline
	lobby_buttons.add_child(leave_btn)
	content.add_child(lobby_buttons)
	content.add_child(_spacer(8))
	var ready_hint := "All players ready." if NetManager.is_lobby_ready() else "The host can start at any time; empty slots are filled by bots."
	content.add_child(_body(ready_hint))
	content.add_child(_slider("Test latency (ms)", "net/test_latency", 0.0, 300.0, 10.0))
	content.add_child(_slider("Test packet loss (%)", "net/test_loss", 0.0, 30.0, 1.0))
	content.add_child(_body("Networking is server-authoritative. Host a listen server or run a headless server with --headless --server."))


func _show_locker() -> void:
	_clear_content()
	content.add_child(_heading("LOCKER"))
	content.add_child(_body("Cosmetics never change hitboxes or gameplay stats. Preview anything, then equip what you own. Credits: %d" % int(Meta.profile.get("credits", 0))))
	if _preview_loadout.is_empty():
		_preview_loadout = (Meta.profile.get("loadout", {}) as Dictionary).duplicate(true)
	_preview_loadout = CosmeticLibrary.sanitize_loadout(_preview_loadout)
	var preview := CarPreview.new()
	preview.name = "LockerPreview"
	preview.apply_loadout(_preview_loadout)
	content.add_child(preview)
	var preview_actions := HBoxContainer.new()
	preview_actions.add_theme_constant_override("separation", 10)
	var restore := _small_button("RESTORE EQUIPPED", func() -> void:
		_preview_loadout = (Meta.profile.get("loadout", {}) as Dictionary).duplicate(true)
		_show_locker()
	, 190)
	preview_actions.add_child(restore)
	preview_actions.add_child(_label("Drag-free turntable preview", 13, Color(0.55, 0.7, 0.85)))
	content.add_child(preview_actions)

	content.add_child(_spacer(6))
	content.add_child(_section("LOADOUT PRESETS"))
	var presets: Array = Meta.profile.get("loadout_presets", [])
	for index in presets.size():
		var preset: Dictionary = presets[index]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var lbl := _label(str(preset.get("name", "Preset")), 15, Color(0.85, 0.92, 1.0))
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(lbl)
		var load_index: int = index
		var load_btn := _small_button("LOAD", func() -> void:
			Meta.apply_loadout_preset(load_index)
			_preview_loadout = (Meta.profile.get("loadout", {}) as Dictionary).duplicate(true)
			_show_locker()
		)
		load_btn.disabled = bool(preset.get("loadout", {}).is_empty())
		row.add_child(load_btn)
		var del_btn := _small_button("DELETE", func() -> void:
			if Meta.delete_loadout_preset(load_index):
				_show_locker()
		)
		del_btn.disabled = presets.size() <= 1
		row.add_child(del_btn)
		content.add_child(row)
	var save_row := HBoxContainer.new()
	save_row.add_theme_constant_override("separation", 10)
	var name_edit := LineEdit.new()
	name_edit.placeholder_text = "Preset name"
	name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_edit.custom_minimum_size = Vector2(180.0, 34.0)
	save_row.add_child(name_edit)
	save_row.add_child(_small_button("SAVE CURRENT", func() -> void:
		Meta.save_loadout_preset(name_edit.text)
		_show_locker()
	, 170))
	content.add_child(save_row)

	content.add_child(_spacer(6))
	content.add_child(_section("CATALOG"))
	var types := ["body", "wheel", "boost", "decal", "explosion", "antenna", "trail"]
	for type: String in types:
		var header := HBoxContainer.new()
		var type_lbl := _label(type.to_upper(), 13, Color(0.3, 0.8, 1.0))
		type_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		header.add_child(type_lbl)
		var equipped_id: String = Meta.equipped(type)
		if equipped_id != Meta.default_item_for(type):
			var unequip_type: String = type
			header.add_child(_small_button("UNEQUIP", func() -> void:
				Meta.unequip(unequip_type)
				_preview_loadout = (Meta.profile.get("loadout", {}) as Dictionary).duplicate(true)
				_show_locker()
			))
		content.add_child(header)
		for item: Dictionary in Meta.catalog:
			if str(item["type"]) != type:
				continue
			content.add_child(_locker_row(item, preview))



func _show_challenges() -> void:
	_clear_content()
	content.add_child(_heading("CHALLENGES"))
	content.add_child(_body("Daily challenges reset every day. Weekly challenges reset on Monday."))
	content.add_child(_section("DAILY"))
	for entry: Dictionary in Meta.daily_challenges:
		content.add_child(_challenge_row(entry))
	content.add_child(_section("WEEKLY"))
	for entry: Dictionary in Meta.weekly_challenges:
		content.add_child(_challenge_row(entry))


func _challenge_row(entry: Dictionary) -> Control:
	var state := Meta.challenge_state(entry)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var lbl := _label(str(entry["text"]), 15, Color(0.85, 0.92, 1.0))
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(lbl)
	var prog := _label("%d / %d" % [int(state["progress"]), int(state["target"])], 13, Color(0.6, 0.8, 1.0))
	row.add_child(prog)
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(110.0, 34.0)
	btn.text = "CLAIMED" if bool(state["claimed"]) else ("CLAIM %d" % int(entry["reward"]))
	btn.disabled = (not bool(state["done"])) or bool(state["claimed"])
	btn.pressed.connect(func() -> void:
		if Meta.claim_challenge(entry):
			_show_challenges()
			_refresh_profile()
	)
	row.add_child(btn)
	return row


func _locker_row(item: Dictionary, preview: CarPreview) -> Control:
	var id: String = str(item["id"])
	var type: String = str(item["type"])
	var owned: bool = Meta.owns(id)
	var equipped: bool = Meta.equipped(type) == id
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var name_lbl := _label(str(item["name"]), 15, Color(0.85, 0.92, 1.0))
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.tooltip_text = str(item.get("description", ""))
	row.add_child(name_lbl)
	row.add_child(_label(str(item["rarity"]), 12, _rarity_color(str(item["rarity"]))))
	var view_btn := _small_button("PREVIEW", func() -> void:
		_preview_loadout[type] = id
		preview.apply_loadout(_preview_loadout)
	, 96)
	row.add_child(view_btn)
	if equipped:
		var equipped_btn := Button.new()
		equipped_btn.text = "EQUIPPED"
		equipped_btn.custom_minimum_size = Vector2(130.0, 34.0)
		equipped_btn.disabled = true
		row.add_child(equipped_btn)
	elif owned:
		var equip_btn := _small_button("EQUIP", func() -> void:
			Meta.equip(id)
			_preview_loadout[type] = id
			_show_locker()
		, 130)
		row.add_child(equip_btn)
	elif bool(item.get("season_only", false)):
		var season_btn := Button.new()
		season_btn.text = "SEASON PASS"
		season_btn.custom_minimum_size = Vector2(130.0, 34.0)
		season_btn.disabled = true
		row.add_child(season_btn)
	else:
		var reason: String = Meta.purchase_block_reason(id)
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(130.0, 34.0)
		if reason == "":
			btn.text = "%d cr" % int(item["price"])
			btn.pressed.connect(func() -> void:
				if Meta.purchase(id):
					_show_locker()
			)
		elif reason.begins_with("Reach level"):
			btn.text = "LVL %d" % int(item.get("unlock_level", 1))
			btn.disabled = true
		elif reason == "Not enough credits":
			btn.text = "%d cr" % int(item["price"])
			btn.disabled = true
		else:
			btn.text = reason
			btn.disabled = true
		row.add_child(btn)
	return row


func _show_profile() -> void:
	_clear_content()
	content.add_child(_heading("PROFILE & STATS"))
	var summary := Meta.career_summary()
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 18)
	var icon := RankIcon.new()
	icon.setup(maxi(Meta.tier_index_for_mmr(float(summary["mmr"])), 0), Meta.division_for_mmr(float(summary["mmr"])), 58.0)
	top.add_child(icon)
	var identity := VBoxContainer.new()
	identity.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var name_row := HBoxContainer.new()
	name_row.add_child(_label("Name", 14, Color(0.65, 0.78, 0.92)))
	var name_edit := LineEdit.new()
	name_edit.text = str(summary["name"])
	name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_edit.custom_minimum_size = Vector2(180.0, 34.0)
	name_edit.text_submitted.connect(func(text: String) -> void:
		Meta.set_player_name(text)
		_refresh_profile()
		_show_profile()
	)
	name_row.add_child(name_edit)
	identity.add_child(name_row)
	identity.add_child(_label("LEVEL %d   %d / %d XP   %s" % [
		int(summary["level"]), int(summary["xp"]), int(summary["xp_needed"]), str(summary["rank"]),
	], 17, Color(0.45, 0.9, 1.0)))
	identity.add_child(_progress_bar(float(summary["xp_ratio"]), Color(0.2, 0.85, 1.0)))
	top.add_child(identity)
	content.add_child(top)

	content.add_child(_section("CAREER"))
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 4)
	grid.add_child(_stat_cell("Matches", str(summary["matches"])))
	grid.add_child(_stat_cell("Wins", str(summary["wins"])))
	grid.add_child(_stat_cell("Losses", str(summary["losses"])))
	grid.add_child(_stat_cell("Win rate", "%.0f%%" % (float(summary["win_rate"]) * 100.0)))
	grid.add_child(_stat_cell("Goals", str(summary["goals"])))
	grid.add_child(_stat_cell("Saves", str(summary["saves"])))
	grid.add_child(_stat_cell("Assists", str(summary["assists"])))
	grid.add_child(_stat_cell("Shots", str(summary["shots"])))
	grid.add_child(_stat_cell("Demolitions", str(summary["demolitions"])))
	grid.add_child(_stat_cell("MVPs", str(summary["mvp_count"])))
	grid.add_child(_stat_cell("Best win streak", str(summary["best_win_streak"])))
	grid.add_child(_stat_cell("Playtime", str(summary["playtime_text"])))
	grid.add_child(_stat_cell("Boost used", "%d" % int(float(summary["boost_used"]))))
	grid.add_child(_stat_cell("Credits", str(summary["credits"])))
	grid.add_child(_stat_cell("Total XP", str(summary["total_xp"])))
	content.add_child(grid)

	content.add_child(_section("COMPETITIVE"))
	var ranked := GridContainer.new()
	ranked.columns = 3
	ranked.add_theme_constant_override("h_separation", 18)
	ranked.add_child(_stat_cell("MMR", "%d" % int(float(summary["mmr"]))))
	ranked.add_child(_stat_cell("RD", "%d" % int(float(summary["rd"]))))
	ranked.add_child(_stat_cell("Peak", "%d" % int(float(summary["peak_mmr"]))))
	ranked.add_child(_stat_cell("Ranked", str(summary["ranked_matches"])))
	ranked.add_child(_stat_cell("Casual", str(summary["casual_matches"])))
	ranked.add_child(_stat_cell("Season", str(summary["season"])))
	content.add_child(ranked)
	var history: Array = Meta.profile.get("season_history", [])
	if not history.is_empty():
		content.add_child(_section("SEASON HISTORY"))
		for entry: Dictionary in history:
			content.add_child(_body("Season %d   %d MMR peak   %d matches   %d wins" % [
				int(entry.get("season", 0)),
				int(entry.get("peak_mmr", 0)),
				int(entry.get("matches", 0)),
				int(entry.get("wins", 0)),
			]))
	content.add_child(_spacer(8))
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 10)
	actions.add_child(_small_button("EDIT LOADOUT", _show_locker, 180))
	actions.add_child(_small_button("SEASON PASS", _show_season_pass, 180))
	content.add_child(actions)


func _show_season_pass() -> void:
	_clear_content()
	var progress := Meta.season_pass_progress()
	content.add_child(_heading("SEASON PASS"))
	content.add_child(_body("Season %d   Level %d / %d   %d season XP" % [
		int(Meta.profile.get("season", 1)),
		int(progress["level"]),
		Meta.SEASON_PASS_LEVELS,
		int(progress["xp"]),
	]))
	content.add_child(_progress_bar(float(progress["ratio"]), Color(1.0, 0.72, 0.25)))
	var premium_active: bool = bool(progress["premium"])
	if premium_active:
		content.add_child(_label("PREMIUM TRACK ACTIVE", 15, Color(1.0, 0.78, 0.3)))
	else:
		var premium_btn := _small_button("UNLOCK PREMIUM TRACK - %d cr" % Meta.PREMIUM_PASS_COST, func() -> void:
			if Meta.purchase_premium_pass():
				_show_season_pass()
				_refresh_profile()
		, 320)
		premium_btn.disabled = int(Meta.profile.get("credits", 0)) < Meta.PREMIUM_PASS_COST
		content.add_child(premium_btn)
	content.add_child(_body("Free and premium tracks both level up from match XP. Rewards are cosmetics and credits only."))
	content.add_child(_section("REWARD TRACK"))
	for level in range(1, Meta.SEASON_PASS_LEVELS + 1):
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var level_lbl := _label("LVL %02d" % level, 14, Color(0.55, 0.82, 1.0))
		level_lbl.custom_minimum_size = Vector2(64.0, 0.0)
		row.add_child(level_lbl)
		row.add_child(_season_reward_cell(level, false, Meta.season_reward(level, false)))
		row.add_child(_season_reward_cell(level, true, Meta.season_reward(level, true)))
		content.add_child(row)


func _show_ranked() -> void:
	_clear_content()
	content.set_meta("ranked", true)
	content.add_child(_heading("COMPETITIVE"))
	var progress := Meta.rank_progress()
	var identity := HBoxContainer.new()
	identity.add_theme_constant_override("separation", 16)
	var icon := RankIcon.new()
	icon.setup(maxi(int(progress["tier_index"]), 0), int(progress["division"]), 62.0)
	identity.add_child(icon)
	var identity_text := VBoxContainer.new()
	identity_text.add_theme_constant_override("separation", 1)
	identity_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var rank_color: Color = RankIcon.color_for_tier(int(progress["tier_index"]))
	identity_text.add_child(_label(Meta.rank_name(), 26, rank_color))
	identity_text.add_child(_label("MMR %d   RD +/-%d   Peak %d" % [
		int(Meta.profile.get("mmr", 1000)),
		int(round(float(Meta.profile.get("rd", 350.0)))),
		int(Meta.profile.get("peak_mmr", 1000)),
	], 15, Color(0.72, 0.82, 0.95)))
	identity.add_child(identity_text)
	content.add_child(identity)
	var place_left := Meta.placement_remaining()
	var season_line := "Season %d   %d days left   %d matches   %d wins" % [
		int(Meta.profile.get("season", 1)),
		int(ceil(Meta.season_time_left() / 86400.0)),
		int(Meta.profile.get("season_matches", 0)),
		int(Meta.profile.get("season_wins", 0)),
	]
	content.add_child(_body(season_line))
	if place_left > 0:
		var done: int = Meta.PLACEMENT_MATCHES - place_left
		content.add_child(_label("PLACEMENTS  %d / %d   -   Unranked" % [done, Meta.PLACEMENT_MATCHES], 14, Color(1.0, 0.82, 0.35)))
	else:
		content.add_child(_label("NEXT  %s   (%d / %d MMR)" % [
			str(progress["next"]),
			int(progress["mmr_into_tier"]),
			int(progress["tier_size"]),
		], 14, Color(0.55, 0.85, 1.0)))
	var cooldown := Meta.leaver_cooldown_remaining()
	if cooldown > 0.0:
		content.add_child(_label("LEAVER COOLDOWN  %d s remaining" % int(ceil(cooldown)), 14, Color(1.0, 0.4, 0.3)))
	if Meta.is_flagged_smurf():
		content.add_child(_label("SMURF PROTECTION  accelerated rating gains active", 13, Color(1.0, 0.7, 0.3)))
	content.add_child(_spacer(8))
	content.add_child(_section("MATCHMAKING"))
	if Matchmaking.in_queue:
		_queue_status = _label(Matchmaking.status_text(), 15, Color(0.45, 0.9, 1.0))
		_queue_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		content.add_child(_queue_status)
		var cancel_btn := _nav_button("CANCEL QUEUE", func() -> void: Matchmaking.cancel())
		cancel_btn.custom_minimum_size = Vector2(220.0, 42.0)
		content.add_child(cancel_btn)
		content.add_child(_body("The search window widens 20 MMR per second. Queue lockouts apply after abandoning a ranked match."))
	else:
		var queue_buttons := HBoxContainer.new()
		queue_buttons.add_theme_constant_override("separation", 12)
		var ranked_btn := _nav_button("FIND RANKED MATCH", func() -> void: Matchmaking.queue_ranked())
		ranked_btn.custom_minimum_size = Vector2(260.0, 46.0)
		queue_buttons.add_child(ranked_btn)
		var casual_btn := _nav_button("FIND CASUAL MATCH", func() -> void: Matchmaking.queue_casual())
		casual_btn.custom_minimum_size = Vector2(260.0, 46.0)
		queue_buttons.add_child(casual_btn)
		content.add_child(queue_buttons)
		content.add_child(_string_option("Region", "net/region", ["Auto", "Europe", "North America", "Asia", "South America", "Oceania"], ["auto", "eu", "na", "asia", "sa", "oce"]))
		content.add_child(_string_option("Party MMR", "net/mmr_rule", ["Average", "Maximum"], ["avg", "max"]))
		content.add_child(_slider("Max ping (ms)", "net/max_ping", 40.0, 300.0, 10.0))
		content.add_child(_body("Ranked uses Glicko-2 with 10 placement matches. Casual records stats without changing ranked MMR. Parties queue as one entry using the selected average or max rule."))
	content.add_child(_section("RANK ICONS"))
	for i in Meta.RANK_TIERS.size():
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		var tier_icon := RankIcon.new()
		tier_icon.setup(i, 3, 40.0)
		row.add_child(tier_icon)
		var color := RankIcon.color_for_tier(i)
		var name_lbl := _label(str(Meta.RANK_TIERS[i]), 15, color)
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_lbl)
		var range_lbl := _label("%d - %d MMR" % [i * Meta.TIER_SIZE, (i + 1) * Meta.TIER_SIZE], 12, Color(0.55, 0.65, 0.8))
		row.add_child(range_lbl)
		content.add_child(row)

	# Queue status ticker.
	if _queue_status != null:
		_queue_status.text = Matchmaking.status_text()


func _on_queue_changed() -> void:
	if content != null and content.has_meta("ranked"):
		_show_ranked()


func _on_queue_progress(_elapsed: float, _size: int) -> void:
	if _queue_status != null and is_instance_valid(_queue_status) and Matchmaking.in_queue:
		_queue_status.text = Matchmaking.status_text()


func _on_matchmaking_found(info: Dictionary) -> void:
	if _match != null:
		return
	var rules := MATCH_RULES.duplicate() as MatchRules
	var teams: Array = info.get("team_mmr", [1000.0, 1000.0])
	var local_team: int = clampi(int(info.get("local_team", 0)), 0, 1)
	rules.team_size = clampi(int(info.get("team_size", Settings.get_int("game/team_size"))), 1, 3)
	rules.ranked = bool(info.get("ranked", false))
	rules.mode_name = "Ranked" if rules.ranked else "Casual"
	rules.mode_id = "ranked" if rules.ranked else "casual"
	rules.team_mmr = float(teams[local_team]) if teams.size() > local_team else float(Meta.profile.get("mmr", 1000.0))
	rules.opponent_mmr = float(teams[1 - local_team]) if teams.size() > 1 - local_team else 1000.0
	rules.opponent_rd = 200.0
	rules.region = str(info.get("region", "auto"))
	rules.match_id = "%d-%d" % [Time.get_ticks_msec(), randi()]
	rules.fill_with_bots = true
	rules.bot_tier = clampi(int(round((rules.opponent_mmr - 700.0) / 500.0)), 0, 3)
	if NetManager.is_server and not NetManager.is_offline:
		NetManager.team_size = rules.team_size
		NetManager.broadcast_match_start(_rules_to_dict(rules))
	_launch(rules)


func _show_private() -> void:
	_clear_content()
	content.add_child(_heading("PRIVATE MATCH"))
	content.add_child(_body("Choose a format, a bot difficulty and any combination of mutators. Mutators are applied to a fresh copy of the rules at kickoff, so they never change your saved defaults."))
	content.add_child(_section("FORMAT"))
	var team := OptionButton.new()
	for label: String in ["1v1", "2v2", "3v3"]:
		team.add_item(label)
	team.selected = 2
	team.custom_minimum_size = Vector2(160.0, 36.0)
	content.add_child(team)
	var tier := OptionButton.new()
	for label: String in ["Rookie", "Pro", "All-Star", "Champion"]:
		tier.add_item(label)
	tier.selected = 1
	tier.custom_minimum_size = Vector2(160.0, 36.0)
	content.add_child(tier)
	var interval := OptionButton.new()
	for label: String in ["20 s shifts", "30 s shifts", "45 s shifts"]:
		interval.add_item(label)
	interval.selected = 1
	interval.custom_minimum_size = Vector2(160.0, 36.0)
	content.add_child(interval)
	var theme_pick := OptionButton.new()
	for label: String in ["Neon Grid", "Cryo Ice", "Solar Lava"]:
		theme_pick.add_item(label)
	theme_pick.selected = 0
	theme_pick.custom_minimum_size = Vector2(160.0, 36.0)
	content.add_child(theme_pick)
	content.add_child(_section("MUTATORS"))
	var checks: Dictionary = {}
	for entry: Dictionary in MutatorLibrary.catalog():
		var check := CheckButton.new()
		check.text = "%s - %s" % [str(entry["name"]), str(entry["description"])]
		check.add_theme_font_size_override("font_size", 13)
		check.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		content.add_child(check)
		checks[str(entry["id"])] = check
	content.add_child(_spacer(10))
	content.add_child(_nav_button("START PRIVATE MATCH", func() -> void:
		var ids: Array = []
		for id: Variant in checks.keys():
			if (checks[id] as CheckButton).button_pressed:
				ids.append(id)
		var selected := MutatorLibrary.validate(MutatorLibrary.build(ids))
		var rules := MATCH_RULES.duplicate() as MatchRules
		rules.team_size = team.selected + 1
		rules.bot_tier = tier.selected
		rules.mode_name = "Private"
		rules.mode_id = "private"
		rules.mutators = selected
		rules.gravity_interval = [20.0, 30.0, 45.0][interval.selected]
		rules.arena_theme_index = theme_pick.selected
		rules.fill_with_bots = true
		_launch(rules)
	))
	content.add_child(_nav_button("BACK", _show_home))


func _start_free_play() -> void:
	var rules := MATCH_RULES.duplicate() as MatchRules
	rules.team_size = 1
	rules.match_duration = 3600.0
	rules.overtime_enabled = false
	rules.replay_enabled = false
	rules.fill_with_bots = false
	rules.mode_name = "Free Play"
	rules.mode_id = "free_play"
	rules.free_play = true
	_launch(rules)


func _open_training() -> void:
	if ResourceLoader.exists("res://training/Training.tscn"):
		get_tree().change_scene_to_file("res://training/Training.tscn")
	else:
		_start_match(1, 0, "Free Play")


# --- Match launch ------------------------------------------------------------

func _quick_play() -> void:
	_start_match(int(Settings.get_setting("game/team_size")), int(Settings.get_setting("game/bot_difficulty")), "Standard")


func _start_match(team_size: int, bot_tier: int, mode_name: String) -> void:
	var rules := MATCH_RULES.duplicate() as MatchRules
	rules.team_size = team_size
	rules.bot_tier = bot_tier
	rules.mode_name = mode_name
	rules.mode_id = mode_name.to_lower().replace(" ", "_")
	rules.fill_with_bots = true
	if NetManager.is_server and not NetManager.is_offline:
		NetManager.team_size = team_size
		NetManager.broadcast_match_start(_rules_to_dict(rules))
	_launch(rules)


## Headless/dedicated server: no menu, no camera, no HUD. All cars start as
## bots and are handed to clients as they connect.
func _start_dedicated_server() -> void:
	var rules := MATCH_RULES.duplicate() as MatchRules
	rules.team_size = NetManager.team_size
	rules.bot_tier = 1
	rules.fill_with_bots = true
	rules.mode_name = "Dedicated"
	var node := MATCH_SCENE.instantiate() as MatchController
	node.rules = rules
	node.auto_start = true
	node.headless_mode = true
	node.spawn_camera = false
	node.spawn_hud = false
	node.all_bots = true
	_match = node
	NetManager.broadcast_match_start(_rules_to_dict(rules))
	add_child(node)
	Events.network_status_changed.emit("Dedicated server ready")


func _on_net_match_started(data: Dictionary) -> void:
	if _match != null:
		return
	var rules := MATCH_RULES.duplicate() as MatchRules
	_apply_rules_dict(rules, data)
	_launch(rules)


func _rules_to_dict(rules: MatchRules) -> Dictionary:
	return {
		"mode_name": rules.mode_name,
		"mode_id": rules.mode_id,
		"team_size": rules.team_size,
		"match_duration": rules.match_duration,
		"score_limit": rules.score_limit,
		"overtime_enabled": rules.overtime_enabled,
		"kickoff_countdown": rules.kickoff_countdown,
		"goal_pause": rules.goal_pause,
		"replay_enabled": rules.replay_enabled,
		"replay_duration": rules.replay_duration,
		"fill_with_bots": rules.fill_with_bots,
		"bot_tier": rules.bot_tier,
		"friendly_fire": rules.friendly_fire,
		"demolition_enabled": rules.demolition_enabled,
		"free_play": rules.free_play,
		"unstuck_time": rules.unstuck_time,
		"arena_theme_index": rules.arena_theme_index,
		"ranked": rules.ranked,
		"match_id": rules.match_id,
		"region": rules.region,
		"team_mmr": rules.team_mmr,
		"opponent_mmr": rules.opponent_mmr,
		"opponent_rd": rules.opponent_rd,
		"gravity_interval": rules.gravity_interval,
		"gravity_transition": rules.gravity_transition,
		"gravity_warning": rules.gravity_warning,
		"random_gravity": rules.random_gravity,
		"gravity_strength": rules.gravity_strength,
		"enabled_phases": rules.enabled_phases,
		"ball_radius_scale": rules.ball_radius_scale,
		"ball_mass_scale": rules.ball_mass_scale,
		"boost_pads_enabled": rules.boost_pads_enabled,
		"no_boost": rules.no_boost,
		"unlimited_boost": rules.unlimited_boost,
	}


func _apply_rules_dict(rules: MatchRules, data: Dictionary) -> void:
	rules.mode_name = str(data.get("mode_name", rules.mode_name))
	rules.mode_id = str(data.get("mode_id", rules.mode_id))
	rules.team_size = int(data.get("team_size", rules.team_size))
	rules.match_duration = float(data.get("match_duration", rules.match_duration))
	rules.score_limit = int(data.get("score_limit", rules.score_limit))
	rules.overtime_enabled = bool(data.get("overtime_enabled", rules.overtime_enabled))
	rules.kickoff_countdown = float(data.get("kickoff_countdown", rules.kickoff_countdown))
	rules.goal_pause = float(data.get("goal_pause", rules.goal_pause))
	rules.replay_enabled = bool(data.get("replay_enabled", rules.replay_enabled))
	rules.replay_duration = float(data.get("replay_duration", rules.replay_duration))
	rules.fill_with_bots = bool(data.get("fill_with_bots", rules.fill_with_bots))
	rules.bot_tier = int(data.get("bot_tier", rules.bot_tier))
	rules.friendly_fire = bool(data.get("friendly_fire", rules.friendly_fire))
	rules.demolition_enabled = bool(data.get("demolition_enabled", rules.demolition_enabled))
	rules.free_play = bool(data.get("free_play", rules.free_play))
	rules.unstuck_time = float(data.get("unstuck_time", rules.unstuck_time))
	rules.arena_theme_index = int(data.get("arena_theme_index", rules.arena_theme_index))
	rules.ranked = bool(data.get("ranked", rules.ranked))
	rules.match_id = str(data.get("match_id", rules.match_id))
	rules.region = str(data.get("region", rules.region))
	rules.team_mmr = float(data.get("team_mmr", rules.team_mmr))
	rules.opponent_mmr = float(data.get("opponent_mmr", rules.opponent_mmr))
	rules.opponent_rd = float(data.get("opponent_rd", rules.opponent_rd))
	rules.gravity_interval = float(data.get("gravity_interval", rules.gravity_interval))
	rules.gravity_transition = float(data.get("gravity_transition", rules.gravity_transition))
	rules.gravity_warning = float(data.get("gravity_warning", rules.gravity_warning))
	rules.random_gravity = bool(data.get("random_gravity", rules.random_gravity))
	rules.gravity_strength = float(data.get("gravity_strength", rules.gravity_strength))
	var phases: Variant = data.get("enabled_phases", null)
	if phases is Array:
		var converted: Array[bool] = []
		for value: Variant in phases:
			converted.append(bool(value))
		rules.enabled_phases = converted
	rules.ball_radius_scale = float(data.get("ball_radius_scale", rules.ball_radius_scale))
	rules.ball_mass_scale = float(data.get("ball_mass_scale", rules.ball_mass_scale))
	rules.boost_pads_enabled = bool(data.get("boost_pads_enabled", rules.boost_pads_enabled))
	rules.no_boost = bool(data.get("no_boost", rules.no_boost))
	rules.unlimited_boost = bool(data.get("unlimited_boost", rules.unlimited_boost))


func _launch(rules: MatchRules) -> void:
	if _match != null:
		return
	var node := MATCH_SCENE.instantiate() as MatchController
	node.rules = rules
	node.auto_start = true
	_match = node
	visible = false
	add_child(node)


func _on_match_loaded() -> void:
	pass


# --- Helpers -----------------------------------------------------------------

func _label(text: String, size: int, color: Color) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.modulate = color
	lbl.add_theme_font_size_override("font_size", size)
	lbl.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.8))
	lbl.add_theme_constant_override("outline_size", 4)
	return lbl


func _heading(text: String) -> Label:
	var lbl := _label(text, 30, Color(0.9, 0.97, 1.0))
	lbl.add_theme_constant_override("outline_size", 8)
	return lbl


func _section(text: String) -> Label:
	var lbl := _label(text, 13, Color(0.3, 0.8, 1.0))
	return lbl


func _body(text: String) -> Label:
	var lbl := _label(text, 15, Color(0.66, 0.76, 0.9))
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return lbl


func _bullet(title: String, text: String) -> Control:
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 0)
	vbox.add_child(_label(title, 17, Color(0.35, 0.85, 1.0)))
	var b := _body(text)
	vbox.add_child(b)
	return vbox


func _spacer(height: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0.0, height)
	return c


func _season_reward_cell(level: int, premium: bool, reward: Dictionary) -> Control:
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(245.0, 0.0)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var header: String = "PREMIUM" if premium else "FREE"
	var color: Color = Color(1.0, 0.78, 0.3) if premium else Color(0.5, 0.85, 1.0)
	box.add_child(_label("%s  %s" % [header, str(reward.get("label", ""))], 12, color))
	var claimed: bool = Meta.season_reward_claimed(level, premium)
	var unlocked: bool = level <= Meta.season_pass_level()
	var premium_ok: bool = (not premium) or bool(Meta.profile.get("premium_pass", false))
	var btn_text: String = "CLAIM"
	var disabled: bool = false
	if claimed:
		btn_text = "CLAIMED"
		disabled = true
	elif not unlocked:
		btn_text = "LOCKED"
		disabled = true
	elif not premium_ok:
		btn_text = "PREMIUM"
		disabled = true
	var btn := _small_button(btn_text, func() -> void:
		if Meta.claim_season_reward(level, premium):
			_show_season_pass()
			_refresh_profile()
	, 100)
	btn.disabled = disabled
	box.add_child(btn)
	return box


func _progress_bar(value: float, color: Color) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.max_value = 1.0
	bar.value = clampf(value, 0.0, 1.0)
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0.0, 18.0)
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	fill.set_corner_radius_all(6)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.05, 0.09, 0.15, 0.9)
	bg.set_corner_radius_all(6)
	bar.add_theme_stylebox_override("fill", fill)
	bar.add_theme_stylebox_override("background", bg)
	return bar


func _stat_cell(label: String, value: String) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	box.add_child(_label(value, 18, Color(0.9, 0.97, 1.0)))
	box.add_child(_label(label, 12, Color(0.55, 0.68, 0.82)))
	return box


func _small_button(text: String, callback: Callable, width: float = 120.0) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(width, 34.0)
	btn.add_theme_font_size_override("font_size", 13)
	btn.pressed.connect(callback)
	return btn


func _nav_button(text: String, callback: Callable) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(330.0, 46.0)
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.add_theme_font_size_override("font_size", 17)
	btn.add_theme_stylebox_override("normal", _style(Color(0.04, 0.07, 0.13, 0.85), Color(0.15, 0.55, 0.85, 0.35), 8))
	btn.add_theme_stylebox_override("hover", _style(Color(0.07, 0.14, 0.22, 0.95), Color(0.15, 0.85, 1.0, 0.8), 8))
	btn.pressed.connect(callback)
	return btn


func _slider(text: String, key: String, min_v: float, max_v: float, step: float) -> Control:
	var vbox := VBoxContainer.new()
	var row := HBoxContainer.new()
	var lbl := _label(text, 14, Color(0.78, 0.87, 0.97))
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(lbl)
	var value_lbl := _label("", 14, Color(0.45, 0.85, 1.0))
	row.add_child(value_lbl)
	vbox.add_child(row)
	var slider := HSlider.new()
	slider.min_value = min_v
	slider.max_value = max_v
	slider.step = step
	slider.value = Settings.get_float(key)
	value_lbl.text = _format_value(slider.value, step)
	slider.value_changed.connect(func(v: float) -> void:
		if _updating:
			return
		Settings.set_setting(key, v)
		value_lbl.text = _format_value(v, step)
	)
	vbox.add_child(slider)
	return vbox


func _option(text: String, key: String, items: Array) -> Control:
	var row := HBoxContainer.new()
	var lbl := _label(text, 14, Color(0.78, 0.87, 0.97))
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(lbl)
	var option := OptionButton.new()
	option.custom_minimum_size = Vector2(220.0, 36.0)
	for item: String in items:
		option.add_item(item)
	option.selected = int(Settings.get_setting(key))
	option.item_selected.connect(func(index: int) -> void:
		if not _updating:
			Settings.set_setting(key, index)
	)
	row.add_child(option)
	return row


func _string_option(text: String, key: String, labels: Array, values: Array) -> Control:
	var row := HBoxContainer.new()
	var lbl := _label(text, 14, Color(0.78, 0.87, 0.97))
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(lbl)
	var option := OptionButton.new()
	option.custom_minimum_size = Vector2(220.0, 36.0)
	for item: String in labels:
		option.add_item(item)
	var current := str(Settings.get_setting(key))
	var selected: int = values.find(current)
	option.selected = maxi(selected, 0)
	option.item_selected.connect(func(index: int) -> void:
		if not _updating and index >= 0 and index < values.size():
			Settings.set_setting(key, values[index])
			if key == "net/region" or key == "net/mmr_rule":
				_apply_matchmaking_settings()
	)
	row.add_child(option)
	return row


func _apply_matchmaking_settings() -> void:
	Matchmaking.refresh_settings()


func _check(text: String, key: String) -> Control:
	var check := CheckButton.new()
	check.text = text
	check.button_pressed = Settings.get_bool(key)
	check.add_theme_font_size_override("font_size", 14)
	check.toggled.connect(func(on: bool) -> void:
		if not _updating:
			Settings.set_setting(key, on)
	)
	return check


func _format_value(v: float, step: float) -> String:
	if step >= 1.0:
		return "%d" % int(v)
	return "%.2f" % v


func _style(bg: Color, border: Color, radius: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = 12.0
	sb.content_margin_right = 12.0
	sb.content_margin_top = 6.0
	sb.content_margin_bottom = 6.0
	return sb


func _rarity_color(rarity: String) -> Color:
	match rarity:
		"uncommon":
			return Color(0.4, 0.95, 0.55)
		"rare":
			return Color(0.35, 0.7, 1.0)
		"epic":
			return Color(0.8, 0.45, 1.0)
		"legendary":
			return Color(1.0, 0.72, 0.25)
		_:
			return Color(0.7, 0.75, 0.8)


func _tier_color(tier: String) -> Color:
	match tier:
		"Bronze":
			return Color(0.72, 0.45, 0.25)
		"Silver":
			return Color(0.75, 0.8, 0.85)
		"Gold":
			return Color(1.0, 0.82, 0.25)
		"Platinum":
			return Color(0.35, 0.9, 0.85)
		"Diamond":
			return Color(0.4, 0.7, 1.0)
		"Champion":
			return Color(0.75, 0.4, 1.0)
		_:
			return Color(1.0, 0.5, 0.25)
