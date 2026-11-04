class_name VFXService
extends Node3D
## Pooled match effects. Every effect node is created once during loading and
## replayed by VFXService, so a goal or hit never allocates particles mid-game.
##
## Visual language:
##  - edge glow + tint/chromatic pulse make a gravity shift readable;
##  - warm team-coloured sparks reward ball hits;
##  - expanding rings and bursts celebrate goals/demolitions;
##  - all big effects are GPUParticles3D with a fixed particle budget.

const BURST_SCRIPT := preload("res://vfx/VFXBurst.gd")
const RING_SCRIPT := preload("res://vfx/VFXRing.gd")
const OVERLAY_SHADER := preload("res://vfx/gravity_shift_overlay.gdshader")
const DEFAULT_THEME := preload("res://arena/ArenaTheme.tres")

const IMPACT_POOL_SIZE := 10
const GOAL_POOL_SIZE := 2
const DEMO_POOL_SIZE := 3
const RING_POOL_SIZE := 6

const IMPACT_PARTICLES := 22
const GOAL_PARTICLES := 90
const DEMO_PARTICLES := 64
const SHIFT_PARTICLES := 140

var arena: Arena
var context: Node
var theme: ArenaTheme

var overlay_layer: CanvasLayer
var overlay_rect: ColorRect
var overlay_material: ShaderMaterial

var _impact_pool: Array[VFXBurst] = []
var _goal_pool: Array[VFXBurst] = []
var _demo_pool: Array[VFXBurst] = []
var _rings: Array[VFXRing] = []
var _shift_ripple: VFXBurst
var _rim_root: Node3D
var _rim_material: StandardMaterial3D

var _impact_cursor: int = 0
var _goal_cursor: int = 0
var _demo_cursor: int = 0
var _ring_cursor: int = 0

var _warning_active: bool = false
var _warning_elapsed: float = 0.0
var _warning_duration: float = 0.0
var _warning_color := Color(0.2, 0.8, 1.0)

var _shift_active: bool = false
var _shift_elapsed: float = 0.0
var _shift_duration: float = 0.0
var _shift_color := Color(0.2, 0.8, 1.0)

var _celebrate_active: bool = false
var _celebrate_elapsed: float = 0.0
var _celebrate_duration: float = 0.0
var _celebrate_color := Color.WHITE

var _events_connected: bool = false
var _prewarmed: bool = false


func setup(match_context: Node = null, arena_node: Arena = null, theme_override: ArenaTheme = null) -> void:
	context = match_context
	arena = arena_node
	if theme_override != null:
		theme = theme_override
	elif arena != null and arena.theme != null:
		theme = arena.theme
	if theme == null:
		theme = DEFAULT_THEME
	if _rim_material != null:
		_refresh_rim_color()


func _ready() -> void:
	if theme == null:
		theme = DEFAULT_THEME
	_build_rim()
	_build_overlay()
	_build_pools()
	_connect_events()
	prewarm()


func _exit_tree() -> void:
	_disconnect_events()


func _connect_events() -> void:
	if _events_connected:
		return
	_events_connected = true
	Events.ball_hit.connect(_on_ball_hit)
	Events.goal_explosion.connect(_on_goal_explosion)
	Events.car_demolished.connect(_on_car_demolished)
	Events.gravity_shift_warning.connect(_on_shift_warning)
	Events.gravity_shift_started.connect(_on_shift_started)
	Events.gravity_shift_finished.connect(_on_shift_finished)


func _disconnect_events() -> void:
	if not _events_connected:
		return
	_events_connected = false
	if Events.ball_hit.is_connected(_on_ball_hit):
		Events.ball_hit.disconnect(_on_ball_hit)
	if Events.goal_explosion.is_connected(_on_goal_explosion):
		Events.goal_explosion.disconnect(_on_goal_explosion)
	if Events.car_demolished.is_connected(_on_car_demolished):
		Events.car_demolished.disconnect(_on_car_demolished)
	if Events.gravity_shift_warning.is_connected(_on_shift_warning):
		Events.gravity_shift_warning.disconnect(_on_shift_warning)
	if Events.gravity_shift_started.is_connected(_on_shift_started):
		Events.gravity_shift_started.disconnect(_on_shift_started)
	if Events.gravity_shift_finished.is_connected(_on_shift_finished):
		Events.gravity_shift_finished.disconnect(_on_shift_finished)


# --- setup -------------------------------------------------------------------

func _build_rim() -> void:
	_rim_root = Node3D.new()
	_rim_root.name = "ArenaEdgeGlow"
	_rim_root.visible = false
	add_child(_rim_root)
	_rim_material = StandardMaterial3D.new()
	_rim_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_rim_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_rim_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_rim_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_rim_material.emission_enabled = true
	_rim_material.emission = Color(0.2, 0.8, 1.0)
	_rim_material.emission_energy_multiplier = 4.0
	_rim_material.albedo_color = Color(0.2, 0.8, 1.0, 0.8)
	var h := Arena.HALF_EXTENTS
	var inset: float = 0.10
	var thickness: float = 0.12
	# 12 glowing edges of the box arena. Kept deliberately inside the walls so
	# the lines are never hidden by the collision surfaces.
	for sy: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			_add_rim_box(Vector3(0.0, sy * (h.y - inset), sz * (h.z - inset)), Vector3(h.x * 2.0, thickness, thickness))
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			_add_rim_box(Vector3(sx * (h.x - inset), 0.0, sz * (h.z - inset)), Vector3(thickness, h.y * 2.0, thickness))
	for sx: float in [-1.0, 1.0]:
		for sy: float in [-1.0, 1.0]:
			_add_rim_box(Vector3(sx * (h.x - inset), sy * (h.y - inset), 0.0), Vector3(thickness, thickness, h.z * 2.0))
	_refresh_rim_color()


func _add_rim_box(at: Vector3, size: Vector3) -> void:
	var mesh_node := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh_node.mesh = box
	mesh_node.material_override = _rim_material
	mesh_node.position = at
	mesh_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_rim_root.add_child(mesh_node)


func _build_overlay() -> void:
	overlay_layer = CanvasLayer.new()
	overlay_layer.name = "VFXOverlay"
	overlay_layer.layer = 5 # above the 3D world, below the HUD (layer 10)
	add_child(overlay_layer)
	overlay_rect = ColorRect.new()
	overlay_rect.name = "ShiftTint"
	overlay_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay_rect.visible = false
	overlay_material = ShaderMaterial.new()
	overlay_material.shader = OVERLAY_SHADER
	overlay_material.set_shader_parameter("tint_color", Color(0.2, 0.8, 1.0))
	overlay_material.set_shader_parameter("intensity", 0.0)
	overlay_material.set_shader_parameter("aberration", 0.0)
	overlay_rect.material = overlay_material
	overlay_layer.add_child(overlay_rect)


func _build_pools() -> void:
	for i in IMPACT_POOL_SIZE:
		var burst := _make_burst("ImpactBurst_%d" % i, IMPACT_PARTICLES, 0.55, 0.20, 0.35, true, 15.0, 0.0, 7.0)
		_impact_pool.append(burst)
	for i in GOAL_POOL_SIZE:
		var burst := _make_burst("GoalBurst_%d" % i, GOAL_PARTICLES, 1.55, 0.52, 1.15, true, 22.0, 3.2, 3.0)
		_goal_pool.append(burst)
	for i in DEMO_POOL_SIZE:
		var burst := _make_burst("DemoBurst_%d" % i, DEMO_PARTICLES, 1.05, 0.40, 0.75, true, 18.0, 2.2, 9.0)
		_demo_pool.append(burst)
	_shift_ripple = _make_burst("ShiftRipple", SHIFT_PARTICLES, 1.20, 0.28, 1.0, true, 26.0, 0.0, 0.0)
	for i in RING_POOL_SIZE:
		var ring := RING_SCRIPT.new() as VFXRing
		ring.name = "ShockRing_%d" % i
		ring.configure(3.0, 0.20)
		add_child(ring)
		_rings.append(ring)


func _make_burst(
		node_name: String,
		particles: int,
		lifetime: float,
		size: float,
		radius: float,
		additive: bool,
		speed: float,
		light_power: float,
		gravity_strength: float
) -> VFXBurst:
	var burst := BURST_SCRIPT.new() as VFXBurst
	burst.name = node_name
	burst.configure(particles, lifetime, size, radius, additive, speed, light_power, gravity_strength)
	add_child(burst)
	return burst


# --- public effects ----------------------------------------------------------

func play_impact(at: Vector3, strength: float, hitter_id: int = -1) -> void:
	if _impact_pool.is_empty():
		return
	var strength_ratio: float = clampf(strength / 26.0, 0.30, 1.0)
	var color: Color = _car_color(hitter_id)
	var burst := _impact_pool[_impact_cursor % _impact_pool.size()]
	_impact_cursor = (_impact_cursor + 1) % _impact_pool.size()
	burst.play(at, color, strength_ratio)


func play_goal(team: int, at: Vector3) -> void:
	var color: Color = A11y.team_color(team)
	if not _goal_pool.is_empty():
		var burst := _goal_pool[_goal_cursor % _goal_pool.size()]
		_goal_cursor = (_goal_cursor + 1) % _goal_pool.size()
		burst.play(at, color, 1.0)
	if not _rings.is_empty():
		var ring := _rings[_ring_cursor % _rings.size()]
		_ring_cursor = (_ring_cursor + 1) % _rings.size()
		ring.play(at, color, 0.35, 5.5, 0.85, GravityManager.up)
	_start_celebration(color, 0.85)


func play_demolition(at: Vector3, team: int = 0) -> void:
	var color: Color = A11y.team_color(team) if team > 0 else Color(1.0, 0.62, 0.22)
	color = color.lerp(Color(1.0, 0.45, 0.12), 0.35)
	if not _demo_pool.is_empty():
		var burst := _demo_pool[_demo_cursor % _demo_pool.size()]
		_demo_cursor = (_demo_cursor + 1) % _demo_pool.size()
		burst.play(at, color, 1.0)
	if not _rings.is_empty():
		var ring := _rings[_ring_cursor % _rings.size()]
		_ring_cursor = (_ring_cursor + 1) % _rings.size()
		ring.play(at, color, 0.20, 2.8, 0.55, GravityManager.up)


func play_gravity_shift(from_dir: Vector3, to_dir: Vector3, duration: float) -> void:
	_warning_active = false
	_shift_active = true
	_shift_elapsed = 0.0
	_shift_duration = maxf(duration, 0.25)
	_shift_color = _direction_color(to_dir)
	if theme != null:
		_shift_color = _shift_color.lerp(theme.trim_color, 0.22)
	_refresh_rim_color()
	_rim_root.visible = true
	if _shift_ripple != null:
		var center: Vector3 = arena.global_position if arena != null else Vector3.ZERO
		_shift_ripple.play(center, _shift_color, 1.0)
	if not _rings.is_empty() and not _reduced_motion():
		var ring := _rings[_ring_cursor % _rings.size()]
		_ring_cursor = (_ring_cursor + 1) % _rings.size()
		ring.play(center_of_arena(), _shift_color, 0.25, 6.5, _shift_duration * 0.85, GravityManager.up)
	# Do not leave a stale goal tint on top of a shift.
	_celebrate_active = false


func play_warning(next_dir: Vector3, seconds_left: float = 5.0) -> void:
	if _shift_active:
		return
	_warning_active = true
	_warning_elapsed = 0.0
	_warning_duration = clampf(seconds_left, 0.5, 2.5)
	_warning_color = _direction_color(next_dir)
	_refresh_rim_color()
	_rim_root.visible = true


func center_of_arena() -> Vector3:
	if arena != null:
		return arena.global_position
	return Vector3.ZERO


func active_effect_count() -> int:
	var count := 0
	for burst: VFXBurst in _impact_pool:
		if burst.is_active():
			count += 1
	for burst: VFXBurst in _goal_pool:
		if burst.is_active():
			count += 1
	for burst: VFXBurst in _demo_pool:
		if burst.is_active():
			count += 1
	if _shift_ripple != null and _shift_ripple.is_active():
		count += 1
	for ring: VFXRing in _rings:
		if ring.is_active():
			count += 1
	return count


func pool_sizes() -> Dictionary:
	return {
		"impacts": _impact_pool.size(),
		"goals": _goal_pool.size(),
		"demolitions": _demo_pool.size(),
		"rings": _rings.size(),
		"total_particles": IMPACT_PARTICLES * IMPACT_POOL_SIZE
				+ GOAL_PARTICLES * GOAL_POOL_SIZE
				+ DEMO_PARTICLES * DEMO_POOL_SIZE
				+ SHIFT_PARTICLES,
	}


func is_prewarmed() -> bool:
	return _prewarmed


func is_shift_active() -> bool:
	return _shift_active


func is_warning_active() -> bool:
	return _warning_active


func rim_visible() -> bool:
	return _rim_root != null and _rim_root.visible


# --- event handlers ----------------------------------------------------------

func _on_ball_hit(strength: float, position: Vector3, hitter_id: int) -> void:
	if strength < 2.0:
		return
	play_impact(position, strength, hitter_id)


func _on_goal_explosion(team: int, position: Vector3) -> void:
	play_goal(team, position)


func _on_car_demolished(victim_id: int, _attacker_id: int) -> void:
	var car := _find_car(victim_id)
	if car == null:
		return
	play_demolition(car.global_position, car.team)


func _on_shift_warning(seconds_left: float, next_dir: Vector3) -> void:
	play_warning(next_dir, seconds_left)


func _on_shift_started(from_dir: Vector3, to_dir: Vector3, duration: float) -> void:
	play_gravity_shift(from_dir, to_dir, duration)


func _on_shift_finished(_phase_index: int) -> void:
	_end_shift()


# --- animation ---------------------------------------------------------------

func _process(delta: float) -> void:
	_update_warning(delta)
	_update_shift(delta)
	_update_celebration(delta)


func _update_warning(delta: float) -> void:
	if not _warning_active or _shift_active:
		return
	_warning_elapsed += delta
	var t: float = clampf(_warning_elapsed / maxf(_warning_duration, 0.01), 0.0, 1.0)
	var pulse: float = sin(t * PI) * 0.75 + 0.25
	var flash: float = _flash_scale()
	_rim_material.emission_energy_multiplier = 1.4 * pulse * flash
	_rim_material.albedo_color = Color(_warning_color.r, _warning_color.g, _warning_color.b, 0.35 * pulse)
	if t >= 1.0:
		_warning_active = false
		if not _shift_active:
			_rim_root.visible = false


func _update_shift(delta: float) -> void:
	if not _shift_active:
		return
	_shift_elapsed += delta
	var t: float = clampf(_shift_elapsed / maxf(_shift_duration, 0.01), 0.0, 1.0)
	var wave: float = sin(t * PI)
	var pulse: float = (0.55 + 0.45 * sin(t * PI * 3.0)) * wave
	var flash: float = _flash_scale()
	_rim_material.emission_energy_multiplier = (2.0 + 7.0 * pulse) * flash
	_rim_material.albedo_color = Color(_shift_color.r, _shift_color.g, _shift_color.b, 0.35 + 0.45 * pulse)
	var aberration: float = 0.0 if _reduced_motion() else wave * flash * 0.70
	_apply_overlay(_shift_color, wave * flash * 0.17, aberration)
	if t >= 1.0:
		_end_shift()


func _update_celebration(delta: float) -> void:
	if _shift_active or not _celebrate_active:
		return
	_celebrate_elapsed += delta
	var t: float = clampf(_celebrate_elapsed / maxf(_celebrate_duration, 0.01), 0.0, 1.0)
	var wave: float = sin(t * PI)
	_apply_overlay(_celebrate_color, wave * _flash_scale() * 0.10, 0.0)
	if t >= 1.0:
		_celebrate_active = false
		if not _shift_active:
			_apply_overlay(Color.WHITE, 0.0, 0.0)


func _end_shift() -> void:
	_shift_active = false
	_shift_elapsed = 0.0
	_rim_root.visible = false
	if not _celebrate_active:
		_apply_overlay(Color.WHITE, 0.0, 0.0)


func _start_celebration(color: Color, duration: float) -> void:
	_celebrate_active = true
	_celebrate_elapsed = 0.0
	_celebrate_duration = maxf(duration, 0.1)
	_celebrate_color = color


func _apply_overlay(color: Color, intensity: float, aberration: float) -> void:
	if overlay_rect == null or overlay_material == null:
		return
	overlay_material.set_shader_parameter("tint_color", color)
	overlay_material.set_shader_parameter("intensity", clampf(intensity, 0.0, 1.0))
	overlay_material.set_shader_parameter("aberration", clampf(aberration, 0.0, 1.0))
	overlay_rect.visible = intensity > 0.001 or aberration > 0.001


func _refresh_rim_color() -> void:
	if _rim_material == null:
		return
	var color: Color = _shift_color if _shift_active else (_warning_color if _warning_active else _theme_trim())
	_rim_material.emission = color
	_rim_material.albedo_color = Color(color.r, color.g, color.b, 0.65)
	_rim_material.emission_energy_multiplier = 4.0


func prewarm() -> void:
	for burst: VFXBurst in _impact_pool:
		burst.prewarm()
	for burst: VFXBurst in _goal_pool:
		burst.prewarm()
	for burst: VFXBurst in _demo_pool:
		burst.prewarm()
	if _shift_ripple != null:
		_shift_ripple.prewarm()
	for ring: VFXRing in _rings:
		ring.prewarm()
	_prewarmed = true


# --- helpers -----------------------------------------------------------------

func _theme_trim() -> Color:
	if theme != null:
		return theme.trim_color
	return Color(0.2, 0.8, 1.0)


func _direction_color(direction: Vector3) -> Color:
	# Readable colour coding for the gravity phase being entered. Directions are
	# intentionally compared against the four canonical phase axes, not UP.
	if direction.y < -0.5:
		return Color(0.18, 0.72, 1.0) # floor / blue
	if direction.y > 0.5:
		return Color(1.0, 0.64, 0.18) # ceiling / amber
	if direction.x < -0.5:
		return Color(0.28, 1.0, 0.62) # wall A / green
	return Color(0.78, 0.38, 1.0) # wall B / violet


func _car_color(car_id: int) -> Color:
	var car := _find_car(car_id)
	if car != null:
		return A11y.team_color(car.team).lerp(Color(1.0, 0.92, 0.55), 0.35)
	return Color(1.0, 0.82, 0.35)


func _find_car(car_id: int) -> Car:
	if car_id < 0 or context == null:
		return null
	var cars_variant: Variant = context.get("cars")
	if cars_variant is Array:
		for entry: Variant in cars_variant:
			if entry is Car and (entry as Car).car_id == car_id:
				return entry as Car
	var single: Variant = context.get("car")
	if single is Car and (single as Car).car_id == car_id:
		return single as Car
	return null


func _flash_scale() -> float:
	return clampf(A11y.flash_scale(), 0.0, 1.5)


func _reduced_motion() -> bool:
	return Settings.get_bool("a11y/reduced_motion")
