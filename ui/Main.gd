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


func _ready() -> void:
	NetManager.match_started.connect(_on_net_match_started)
	if NetManager.dedicated_server:
		_start_dedicated_server()
		return
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build()
	Events.profile_changed.connect(_refresh_profile)
	Events.network_status_changed.connect(_on_network_status)
	Events.notification.connect(_on_notification)
	Events.player_joined.connect(func(_id: int, _name: String) -> void: _refresh_online())
	Events.player_left.connect(func(_id: int) -> void: _refresh_online())
	_refresh_profile()
	_show_home()


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
	# Left column: identity and navigation.
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(390.0, 0.0)
	left.add_theme_constant_override("separation", 10)
	hbox.add_child(left)
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
	profile_label.text = "PILOT  %s\nLEVEL %d   %s   %d credits\nMatches %d   Wins %d   Goals %d" % [
		str(p.get("name", "Pilot")),
		int(p.get("level", 1)),
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
	content.add_child(_body("Cosmetics never change hitboxes or gameplay stats. Credits: %d" % int(Meta.profile.get("credits", 0))))
	content.add_child(_spacer(6))
	var types := ["body", "wheel", "boost", "decal", "explosion", "antenna", "trail"]
	for type: String in types:
		content.add_child(_section(type.to_upper()))
		var grid := GridContainer.new()
		grid.columns = 1
		grid.add_theme_constant_override("h_separation", 10)
		for item: Dictionary in Meta.catalog:
			if str(item["type"]) != type:
				continue
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 10)
			var owned: bool = Meta.owns(str(item["id"]))
			var equipped: bool = Meta.equipped(type) == str(item["id"])
			var name_lbl := _label(str(item["name"]), 15, Color(0.85, 0.92, 1.0))
			name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(name_lbl)
			var rarity_lbl := _label(str(item["rarity"]), 12, _rarity_color(str(item["rarity"])))
			row.add_child(rarity_lbl)
			var btn := Button.new()
			btn.custom_minimum_size = Vector2(130.0, 36.0)
			if equipped:
				btn.text = "EQUIPPED"
				btn.disabled = true
			elif owned:
				btn.text = "EQUIP"
				btn.pressed.connect(func() -> void:
					Meta.equip(str(item["id"]))
					_show_locker()
				)
			else:
				btn.text = "%d cr" % int(item["price"])
				btn.disabled = int(Meta.profile.get("credits", 0)) < int(item["price"])
				btn.pressed.connect(func() -> void:
					if Meta.purchase(str(item["id"])):
						_show_locker()
				)
			row.add_child(btn)
			grid.add_child(row)
		content.add_child(grid)


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
	btn.text = "CLAIM %d" % int(entry["reward"])
	btn.disabled = not bool(state["done"])
	btn.pressed.connect(func() -> void:
		if Meta.claim_challenge(entry):
			_show_challenges()
			_refresh_profile()
	)
	row.add_child(btn)
	return row


func _show_ranked() -> void:
	_clear_content()
	content.add_child(_heading("RANKED"))
	var placed: int = int(Meta.profile.get("placement_matches", 0))
	content.add_child(_body("Season %d   MMR %d   Peak %d\nRank: %s\nPlacement matches: %d / 10" % [
		int(Meta.profile.get("season", 1)),
		int(Meta.profile.get("mmr", 1000)),
		int(Meta.profile.get("peak_mmr", 1000)),
		Meta.rank_name(),
		mini(placed, 10),
	]))
	content.add_child(_spacer(8))
	content.add_child(_body("Matchmaking uses Elo with provisional K-factors for new players, then settles to K=16. Parties are matched on average MMR."))
	content.add_child(_nav_button("FIND RANKED MATCH", func() -> void: _start_match(3, 2, "Ranked")))
	content.add_child(_section("RANK ICONS"))
	var tiers := ["Bronze", "Silver", "Gold", "Platinum", "Diamond", "Champion", "Grand Champion"]
	for t: String in tiers:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		var dot := ColorRect.new()
		dot.custom_minimum_size = Vector2(16.0, 16.0)
		dot.color = _tier_color(t)
		row.add_child(dot)
		row.add_child(_label(t, 15, _tier_color(t)))
		content.add_child(row)


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
