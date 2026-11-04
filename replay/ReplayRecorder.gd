class_name ReplayRecorder
extends Node
## Samples a live match into a ReplayData stream. Inputs are stored as changed
## rows at physics rate; compact car/ball snapshots are stored every 30 ticks.

const MAX_SEGMENT_SECONDS := 150.0
const MAX_INPUT_ROWS := 60000

var match_ref: MatchController
var data: ReplayData
var recording: bool = false
var last_path: String = ""
var _tick: int = 0
var _last_signature: Dictionary = {}
var _started: bool = false


func _ready() -> void:
	process_physics_priority = 100


func setup(controller: MatchController) -> void:
	match_ref = controller


func start() -> void:
	if match_ref == null:
		return
	data = ReplayData.new()
	data.created = Time.get_unix_time_from_system()
	data.mode = match_ref.rules.mode_name if match_ref.rules != null else "Standard"
	data.tick_rate = int(ProjectSettings.get_setting("physics/common/physics_ticks_per_second", 120))
	data.physics_version = str(Engine.get_version_info().get("string", "unknown"))
	data.seed_value = match_ref.get("_match_seed")
	data.score1 = match_ref.score1
	data.score2 = match_ref.score2
	var cars: Array = match_ref.cars
	var initial_cars: Array = []
	for car: Car in cars:
		initial_cars.append(ReplayData.initial_car(car))
	data.initial = {
		"cars": initial_cars,
		"ball": ReplayData.encode_ball(match_ref.ball),
		"phase": GravityManager.phase_index,
		"gravity_dir": [GravityManager.gravity_dir.x, GravityManager.gravity_dir.y, GravityManager.gravity_dir.z],
		"loadout": match_ref.local_car.get_loadout() if match_ref.local_car != null else {},
	}
	if _started:
		data.initial["continued"] = true
	_tick = 0
	_last_signature.clear()
	recording = true
	_started = true
	_capture_snapshot()


func _physics_process(_delta: float) -> void:
	if not recording or match_ref == null or data == null:
		return
	if match_ref.state == MatchController.State.POSTGAME:
		finish_and_save()
		return
	_tick += 1
	_capture_inputs()
	if _tick % ReplayData.SNAPSHOT_STRIDE == 0:
		_capture_snapshot()
	if float(_tick) / float(data.tick_rate) >= MAX_SEGMENT_SECONDS:
		finish_and_save()
		start()


func _capture_inputs() -> void:
	if data.inputs.size() >= MAX_INPUT_ROWS:
		return
	for car: Car in match_ref.cars:
		var sig := _signature(car)
		if str(_last_signature.get(car.car_id, "")) == sig:
			continue
		_last_signature[car.car_id] = sig
		data.add_input(_tick, car)


func _signature(car: Car) -> String:
	var flags := 0
	if car.input.jump_pressed:
		flags |= 1
	if car.input.jump_held:
		flags |= 2
	if car.input.boost:
		flags |= 4
	if car.input.handbrake:
		flags |= 8
	if car.input.air_roll:
		flags |= 16
	return "%0.3f|%0.3f|%0.3f|%0.3f|%0.3f|%d" % [
		snappedf(car.input.throttle, 0.02),
		snappedf(car.input.steer, 0.02),
		snappedf(car.input.pitch, 0.02),
		snappedf(car.input.yaw, 0.02),
		snappedf(car.input.roll, 0.02),
		flags,
	]


func _capture_snapshot() -> void:
	if data == null or match_ref == null:
		return
	data.add_snapshot(_tick, match_ref.cars, match_ref.ball, GravityManager.phase_index, match_ref.score1, match_ref.score2)
	data.score1 = match_ref.score1
	data.score2 = match_ref.score2


func finish_and_save() -> String:
	if data == null:
		return ""
	if recording:
		_capture_snapshot()
	recording = false
	data.duration = float(_tick) / float(maxi(data.tick_rate, 1))
	if data.duration < 0.75 or data.inputs.is_empty():
		return ""
	var path := ReplayStorage.save(data)
	if path != "":
		last_path = path
		Events.replay_saved.emit(path)
		Events.notification.emit("Replay saved: %s" % path.get_file())
	return path
