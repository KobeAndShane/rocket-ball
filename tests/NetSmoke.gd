extends Node
## Headless end-to-end network smoke test.
##
## Start a dedicated server, then run:
##   godot --headless --path . res://tests/NetSmoke.tscn
## The scene joins 127.0.0.1, waits for the server's match start, and verifies
## that snapshots, roster assignment and prediction wiring all come up.

const MATCH_SCENE := preload("res://match/Match.tscn")
const RULES := preload("res://match/MatchRules.tres")

var snapshots: int = 0
var match_scene: MatchController
var elapsed: float = 0.0
var _started: bool = false
var _failed: bool = false


func _ready() -> void:
	var latency: int = 0
	var loss: float = 0.0
	var args: PackedStringArray = OS.get_cmdline_args()
	args.append_array(OS.get_cmdline_user_args())
	for arg: String in args:
		if arg.begins_with("--smoke-latency="):
			latency = int(arg.get_slice("=", 1))
		elif arg.begins_with("--smoke-loss="):
			loss = float(arg.get_slice("=", 1))
	if latency > 0 or loss > 0.0:
		NetManager.set_simulated_network(latency, loss)
	NetManager.snapshot_received.connect(_on_snapshot)
	NetManager.match_started.connect(_on_match_started)
	NetManager.connection_failed.connect(_on_connection_failed)
	var err := NetManager.join("127.0.0.1", 7777)
	if err != OK:
		_fail("join returned %d" % err)


func _on_snapshot(_snapshot: Dictionary) -> void:
	snapshots += 1


func _on_match_started(data: Dictionary) -> void:
	if match_scene != null:
		return
	var rules := RULES.duplicate() as MatchRules
	rules.team_size = int(data.get("team_size", 3))
	rules.fill_with_bots = bool(data.get("fill_with_bots", true))
	rules.match_duration = float(data.get("match_duration", 300.0))
	match_scene = MATCH_SCENE.instantiate() as MatchController
	match_scene.rules = rules
	match_scene.auto_start = true
	match_scene.headless_mode = true
	match_scene.spawn_camera = false
	match_scene.spawn_hud = false
	add_child(match_scene)
	_started = true


func _on_connection_failed() -> void:
	_fail("connection failed")


func _process(delta: float) -> void:
	elapsed += delta
	if elapsed > 8.0:
		set_process(false)
		var ok: bool = _started and snapshots > 20 and match_scene != null and match_scene.local_car != null
		if ok:
			print("NET SMOKE PASS  snapshots=%d  local_car=%d  state=%s  ping=%d" % [
				snapshots,
				match_scene.local_car.car_id,
				match_scene.get_state_name(),
				NetManager.get_ping_ms(),
			])
		else:
			print("NET SMOKE FAIL  started=%s snapshots=%d local_car=%s" % [
				str(_started),
				snapshots,
				str(match_scene.local_car.car_id) if match_scene != null and match_scene.local_car != null else "none",
			])
		get_tree().quit(0 if ok else 1)


func _fail(reason: String) -> void:
	if _failed:
		return
	_failed = true
	print("NET SMOKE FAIL  %s" % reason)
	get_tree().quit(1)
