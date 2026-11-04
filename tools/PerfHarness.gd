extends Node
## Headless performance harness. Loads a real 3v3 bot match, samples Godot's
## performance monitors and writes a machine-readable report.
##
## Usage:
##   godot --headless --path . res://tools/PerfHarness.tscn -- --frames=600 --warmup=120
##
## The harness is deliberately boring: it runs the shipping match scene, not a
## synthetic benchmark, so physics, bots, audio and VFX are all part of the
## measurement.

const MATCH_SCENE := preload("res://match/Match.tscn")
const RULES := preload("res://match/MatchRules.tres")
const REPORT_PATH := "user://perf_report.json"

var frames: int = 600
var warmup: int = 120
var fps_cap: int = 0
var fixed_step: bool = false
var render_mode: bool = false
var match_ref: MatchController
var shift_events: Array[int] = []
var slow_frames: Array[Dictionary] = []
var _sample_index: int = 0
var _slow_frame_cap: int = 24


func _ready() -> void:
	_parse_args()
	call_deferred("_run")


func _parse_args() -> void:
	var args: PackedStringArray = OS.get_cmdline_args()
	args.append_array(OS.get_cmdline_user_args())
	for arg: String in args:
		if arg.begins_with("--frames="):
			frames = maxi(int(arg.get_slice("=", 1)), 30)
		elif arg.begins_with("--warmup="):
			warmup = maxi(int(arg.get_slice("=", 1)), 0)
		elif arg.begins_with("--fps-cap="):
			fps_cap = maxi(int(arg.get_slice("=", 1)), 0)
		elif arg == "--fixed-step":
			fixed_step = true
		elif arg == "--render":
			render_mode = true


func _fixed_fps_arg() -> int:
	var args: PackedStringArray = OS.get_cmdline_args()
	for i in args.size():
		var arg: String = args[i]
		if arg.begins_with("--fixed-fps="):
			return maxi(int(arg.get_slice("=", 1)), 0)
		if arg == "--fixed-fps" and i + 1 < args.size():
			return maxi(int(args[i + 1]), 0)
	return 0


func _on_gravity_shift_sample(_from: Vector3, _to: Vector3, _duration: float) -> void:
	shift_events.append(_sample_index)


func _run() -> void:
	await get_tree().process_frame
	# Uncapped by default so the measurement reflects CPU work instead of a
	# sleep-based frame limiter. Pass --fps-cap=60/120 to model a target.
	Engine.max_fps = fps_cap
	var load_start_us := Time.get_ticks_usec()
	var rules := RULES.duplicate() as MatchRules
	match_ref = MATCH_SCENE.instantiate() as MatchController
	match_ref.rules = rules
	match_ref.auto_start = true
	match_ref.headless_mode = not render_mode
	match_ref.spawn_camera = render_mode
	match_ref.spawn_hud = render_mode
	add_child(match_ref)
	Events.gravity_shift_started.connect(_on_gravity_shift_sample)

	var guard: int = 0
	while match_ref.state != MatchController.State.PLAYING and match_ref.state != MatchController.State.OVERTIME and guard < 900:
		await get_tree().process_frame
		guard += 1
	var load_to_playing_ms := float(Time.get_ticks_usec() - load_start_us) / 1000.0
	for i in warmup:
		await get_tree().process_frame

	var frame_samples: Array[float] = []
	var process_samples: Array[float] = []
	var physics_samples: Array[float] = []
	var fps_samples: Array[float] = []
	var step_samples: Array[float] = []
	var cpu_step_samples: Array[float] = []
	var wall_start_us := Time.get_ticks_usec()
	var physics_start := Engine.get_physics_frames()
	var prev_physics := physics_start
	var last_us := wall_start_us
	for i in frames:
		_sample_index = i
		await get_tree().process_frame
		var now_us := Time.get_ticks_usec()
		var now_physics := Engine.get_physics_frames()
		var steps_this_frame: int = now_physics - prev_physics
		prev_physics = now_physics
		var frame_ms := float(now_us - last_us) / 1000.0
		last_us = now_us
		frame_samples.append(frame_ms)
		step_samples.append(float(steps_this_frame))
		# Wall-clock CPU per simulated 120 Hz tick. In fixed-step mode exactly
		# one tick runs per rendered frame, which makes this a direct physics
		# step measurement. Real-time mode includes idle/wait time.
		var cpu_ms: float = frame_ms / float(maxi(steps_this_frame, 1))
		cpu_step_samples.append(cpu_ms)
		if cpu_ms > 4.0 and slow_frames.size() < _slow_frame_cap:
			slow_frames.append({
				"index": i,
				"ms": cpu_ms,
				"phase": GravityManager.phase_index,
				"transitioning": GravityManager.transitioning,
				"state": match_ref.get_state_name(),
			})
		process_samples.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
		physics_samples.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
		fps_samples.append(Performance.get_monitor(Performance.TIME_FPS))
	var wall_us := Time.get_ticks_usec() - wall_start_us
	var wall_seconds := maxf(float(wall_us) / 1000000.0, 0.000001)
	var physics_frames := Engine.get_physics_frames() - physics_start
	var effective_physics_hz := float(physics_frames) / wall_seconds
	var physics_steps: float = float(physics_frames) / float(maxi(frames, 1))
	var fixed_fps := _fixed_fps_arg()
	var cpu_step_stats := _stats(cpu_step_samples)
	var over_4ms: int = 0
	var over_budget: int = 0
	var worst_ms: float = 0.0
	var worst_index: int = -1
	for i in cpu_step_samples.size():
		var v: float = cpu_step_samples[i]
		if v > 4.0:
			over_4ms += 1
		if v > 1000.0 / 120.0:
			over_budget += 1
		if v > worst_ms:
			worst_ms = v
			worst_index = i

	var counts := _count_scene(match_ref)
	var report := {
		"engine": {
			"godot": str(Engine.get_version_info().get("string", "")),
			"renderer": str(ProjectSettings.get_setting("rendering/renderer/rendering_method", "")),
			"physics_engine": str(ProjectSettings.get_setting("physics/3d/physics_engine", "")),
			"headless": DisplayServer.get_name() == "headless",
		},
		"sample": {
			"frames": frames,
			"warmup_frames": warmup,
			"fps_cap": fps_cap,
			"fixed_fps": fixed_fps,
			"fixed_step": fixed_step,
			"render_mode": render_mode,
			"load_to_playing_ms": load_to_playing_ms,
			"state": match_ref.get_state_name(),
			"cars": match_ref.cars.size(),
			"wall_seconds": wall_seconds,
			"simulated_seconds": float(physics_frames) / 120.0,
			"physics_frames": physics_frames,
			"physics_steps_per_rendered_frame": physics_steps,
			"frames_over_4ms": over_4ms,
			"frames_over_833ms": over_budget,
			"worst_step_index": worst_index,
			"worst_step_ms": worst_ms,
			"gravity_shift_samples": shift_events,
			"slow_frames": slow_frames,
		},
		"measurement": {
			"mode": "fixed-step" if fixed_step or fixed_fps > 0 else "real-time",
			"note": "cpu_ms_per_physics_step is wall-clock CPU per simulated 120 Hz tick. Fixed-step mode runs exactly one tick per frame; real-time mode includes idle/wait time and is an upper bound.",
			"monitor_note": "Performance.TIME_PHYSICS_PROCESS is retained for comparison but over-reports in headless mode (it can exceed wall-clock frame time), so the wall-clock field is authoritative.",
		},
		"frame_time_ms": _stats(frame_samples),
		"process_time_ms": _stats(process_samples),
		"physics_time_ms": _stats(physics_samples),
		"cpu_ms_per_physics_step": cpu_step_stats,
		"physics_steps_per_frame": _stats(step_samples),
		"physics_rate_hz": effective_physics_hz,
		"fps": _stats(fps_samples),
		"memory_mb": Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0,
		"objects": counts,
		"render": {
			"draw_calls": int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
			"primitives": int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)),
			"objects": int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)),
		},
		"settings": {
			"physics_ticks_per_second": int(ProjectSettings.get_setting("physics/common/physics_ticks_per_second", 0)),
			"physics_interpolation": bool(ProjectSettings.get_setting("physics/common/physics_interpolation", false)),
			"occlusion_culling": bool(ProjectSettings.get_setting("rendering/occlusion_culling/use_occlusion_culling", false)),
			"physics_steps_per_frame": int(ProjectSettings.get_setting("physics/common/max_physics_steps_per_frame", 0)),
		},
		"network": _measure_bandwidth(),
	}

	var json := JSON.stringify(report, "  ")
	var file := FileAccess.open(REPORT_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(json)
		file.close()
	print("PERF_JSON_BEGIN")
	print(json)
	print("PERF_JSON_END")
	print("PERF PASS  frame_avg=%.3fms  frame_p95=%.3fms  cpu_step_avg=%.3fms  cpu_step_p95=%.3fms  physics_hz=%.1f  memory=%.1fMB" % [
		float(report["frame_time_ms"]["avg"]),
		float(report["frame_time_ms"]["p95"]),
		float(cpu_step_stats["avg"]),
		float(cpu_step_stats["p95"]),
		effective_physics_hz,
		float(report["memory_mb"]),
	])
	Engine.max_fps = 0
	match_ref.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().quit(0)


func _stats(values: Array[float]) -> Dictionary:
	if values.is_empty():
		return {"avg": 0.0, "p50": 0.0, "p95": 0.0, "p99": 0.0, "max": 0.0}
	var sorted := values.duplicate()
	sorted.sort()
	var total := 0.0
	for v: float in sorted:
		total += v
	return {
		"avg": total / float(sorted.size()),
		"p50": sorted[clampi(int(floor(float(sorted.size()) * 0.50)), 0, sorted.size() - 1)],
		"p95": sorted[clampi(int(floor(float(sorted.size()) * 0.95)), 0, sorted.size() - 1)],
		"p99": sorted[clampi(int(floor(float(sorted.size()) * 0.99)), 0, sorted.size() - 1)],
		"max": sorted[sorted.size() - 1],
	}


func _count_scene(root: Node) -> Dictionary:
	var counts := {
		"rigid_bodies": 0,
		"static_bodies": 0,
		"areas": 0,
		"collision_shapes": 0,
		"concave_shapes": 0,
		"mesh_instances": 0,
		"multimesh_instances": 0,
		"gpu_particles": 0,
		"cpu_particles": 0,
		"audio_players": 0,
		"audio_players_3d": 0,
		"labels_3d": 0,
		"lights": 0,
	}
	var layer_counts: Dictionary = {}
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		for child: Node in node.get_children():
			stack.append(child)
		if node is RigidBody3D:
			counts["rigid_bodies"] = int(counts["rigid_bodies"]) + 1
			var layer := str((node as RigidBody3D).collision_layer)
			layer_counts[layer] = int(layer_counts.get(layer, 0)) + 1
		elif node is StaticBody3D:
			counts["static_bodies"] = int(counts["static_bodies"]) + 1
		elif node is Area3D:
			counts["areas"] = int(counts["areas"]) + 1
		if node is CollisionShape3D:
			counts["collision_shapes"] = int(counts["collision_shapes"]) + 1
			var shape := (node as CollisionShape3D).shape
			if shape is ConcavePolygonShape3D:
				counts["concave_shapes"] = int(counts["concave_shapes"]) + 1
		if node is MultiMeshInstance3D:
			counts["multimesh_instances"] = int(counts["multimesh_instances"]) + 1
		elif node is MeshInstance3D:
			counts["mesh_instances"] = int(counts["mesh_instances"]) + 1
		if node is GPUParticles3D:
			counts["gpu_particles"] = int(counts["gpu_particles"]) + 1
		elif node is CPUParticles3D:
			counts["cpu_particles"] = int(counts["cpu_particles"]) + 1
		if node is AudioStreamPlayer3D:
			counts["audio_players_3d"] = int(counts["audio_players_3d"]) + 1
		elif node is AudioStreamPlayer:
			counts["audio_players"] = int(counts["audio_players"]) + 1
		if node is Label3D:
			counts["labels_3d"] = int(counts["labels_3d"]) + 1
		if node is Light3D:
			counts["lights"] = int(counts["lights"]) + 1
	counts["collision_layers"] = layer_counts
	counts["tree_nodes"] = _node_count(root)
	return counts


func _node_count(root: Node) -> int:
	var total: int = 1
	for child: Node in root.get_children():
		total += _node_count(child)
	return total


func _measure_bandwidth() -> Dictionary:
	var meta := {
		"state": int(match_ref.state),
		"score1": match_ref.score1,
		"score2": match_ref.score2,
		"time_left": match_ref.time_left,
		"countdown": match_ref.countdown,
		"overtime": match_ref.overtime_time,
	}
	var snapshot := SnapshotCodec.encode(NetManager.server_tick, GravityManager.phase_index, match_ref.cars, match_ref.ball, meta)
	var input := CarInput.new()
	var burst: Array[CarInput] = [input, input, input]
	var input_packet := InputBuffer.pack(burst)
	# UDP/IPv4 header + ENet framing allowance. Payload sizes are exact.
	var overhead := 36
	var snapshot_wire: int = snapshot.size() + overhead
	var input_wire: int = input_packet.size() + overhead
	var snapshot_bps: float = float(snapshot_wire) * NetManager.SNAPSHOT_RATE
	var input_bps: float = float(input_wire) * NetManager.TICK_RATE
	return {
		"snapshot_payload_bytes": snapshot.size(),
		"snapshot_wire_bytes": snapshot_wire,
		"snapshot_kbps_per_client": snapshot_bps / 1024.0,
		"server_egress_kbps_6_clients": snapshot_bps * 6.0 / 1024.0,
		"input_payload_bytes": input_packet.size(),
		"input_wire_bytes": input_wire,
		"input_kbps_per_client": input_bps / 1024.0,
		"total_kbps_per_client": (snapshot_bps + input_bps) / 1024.0,
	}
