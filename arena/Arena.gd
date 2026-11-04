class_name Arena
extends Node3D
## Procedurally built rounded arena. Every face is drivable, goals sit on the
## Z axis so gravity never turns a goal into floor or ceiling.

const HALF_EXTENTS := Vector3(30.0, 15.0, 40.0)
const FILLET_RADIUS := 1.3
const WALL_THICKNESS := 1.0
const GOAL_WIDTH := 12.0
const GOAL_HEIGHT := 8.0
const GOAL_DEPTH := 6.0
const SPAWN_HEIGHT := 0.92

const GOAL_SCENE := preload("res://arena/Goal.tscn")
const PAD_SCENE := preload("res://arena/BoostPad.tscn")

@export var theme: ArenaTheme
@export var rules: MatchRules
@export var build_environment: bool = true
@export var build_pads: bool = true

var goals: Array[Goal] = []
var pads: Array[BoostPad] = []
var spawn_markers: Array[Transform3D] = []

var _geometry: StaticBody3D
var _pad_root: Node3D
var _floor_mat: StandardMaterial3D
var _wall_mat: StandardMaterial3D
var _trim_mat: StandardMaterial3D
var _pad_layout: Array[Dictionary] = []


func _ready() -> void:
	if theme == null:
		theme = load("res://arena/ArenaTheme.tres") as ArenaTheme
	if rules == null:
		rules = load("res://match/MatchRules.tres") as MatchRules
	_build_materials()
	_build_geometry()
	_build_goals()
	if build_pads:
		_build_pads()
	_build_spawn_markers()
	if build_environment:
		_build_environment()


func configure(new_rules: MatchRules, new_theme: ArenaTheme = null) -> void:
	rules = new_rules
	if new_theme != null:
		theme = new_theme


## Swap the visual theme at kickoff without rebuilding collision.
func apply_theme(new_theme: ArenaTheme) -> void:
	if new_theme == null:
		return
	theme = new_theme
	if _floor_mat == null:
		return
	_floor_mat.albedo_color = theme.floor_color
	_floor_mat.emission = theme.trim_color * 0.035
	_wall_mat.albedo_color = theme.wall_color
	_trim_mat.albedo_color = theme.trim_color
	_trim_mat.emission = theme.trim_color
	for node: Node in get_children():
		if node is WorldEnvironment:
			var env := (node as WorldEnvironment).environment
			if env != null and env.sky != null and env.sky.sky_material is ProceduralSkyMaterial:
				var sky_mat := env.sky.sky_material as ProceduralSkyMaterial
				sky_mat.sky_top_color = theme.sky_top
				sky_mat.sky_horizon_color = theme.sky_bottom
				sky_mat.ground_bottom_color = theme.sky_top
				sky_mat.ground_horizon_color = theme.sky_bottom
			if env != null:
				env.ambient_light_color = theme.ambient_color
				env.ambient_light_energy = theme.ambient_energy
				env.fog_light_color = theme.sky_bottom
				env.fog_enabled = theme.fog_enabled
				env.fog_density = theme.fog_density
		elif node is DirectionalLight3D:
			(node as DirectionalLight3D).light_energy = theme.sun_energy
		elif node is OmniLight3D:
			var light := node as OmniLight3D
			light.light_color = theme.accent_color if light.name.begins_with("Accent") else theme.trim_color
	for goal: Goal in goals:
		if goal != null:
			goal.apply_theme(theme)


func theme_names() -> Array[String]:
	return ["Neon Grid", "Cryo Ice", "Solar Lava"]


func _build_materials() -> void:
	_floor_mat = StandardMaterial3D.new()
	_floor_mat.albedo_color = theme.floor_color
	_floor_mat.metallic = 0.25
	_floor_mat.roughness = 0.55
	_floor_mat.emission_enabled = true
	_floor_mat.emission = theme.trim_color * 0.035
	_wall_mat = StandardMaterial3D.new()
	_wall_mat.albedo_color = theme.wall_color
	_wall_mat.metallic = 0.35
	_wall_mat.roughness = 0.42
	_trim_mat = StandardMaterial3D.new()
	_trim_mat.albedo_color = theme.trim_color
	_trim_mat.emission_enabled = true
	_trim_mat.emission = theme.trim_color
	_trim_mat.emission_energy_multiplier = 2.6
	_trim_mat.metallic = 0.7
	_trim_mat.roughness = 0.2


func _build_geometry() -> void:
	_geometry = StaticBody3D.new()
	_geometry.name = "Geometry"
	_geometry.collision_layer = 1
	_geometry.collision_mask = 0
	add_child(_geometry)
	var h := HALF_EXTENTS
	var t := WALL_THICKNESS
	# Floor and ceiling.
	_add_box(Vector3(0.0, -(h.y + t * 0.5), 0.0), Vector3(h.x * 2.0, t, h.z * 2.0), _floor_mat)
	_add_box(Vector3(0.0, h.y + t * 0.5, 0.0), Vector3(h.x * 2.0, t, h.z * 2.0), _wall_mat)
	# Long side walls.
	_add_box(Vector3(-(h.x + t * 0.5), 0.0, 0.0), Vector3(t, h.y * 2.0, h.z * 2.0), _wall_mat)
	_add_box(Vector3(h.x + t * 0.5, 0.0, 0.0), Vector3(t, h.y * 2.0, h.z * 2.0), _wall_mat)
	# Goal end walls with an opening.
	for s: float in [-1.0, 1.0]:
		_add_end_wall(s)
		_add_goal_recess(s)
	# 12 filleted edges.
	var r := FILLET_RADIUS
	for sy: float in [-1.0, 1.0]:
		for sx: float in [-1.0, 1.0]:
			_add_cylinder(Vector3(sx * (h.x - r), sy * (h.y - r), 0.0), r, h.z * 2.0, 2, _wall_mat)
	for sy: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			_add_cylinder(Vector3(0.0, sy * (h.y - r), sz * (h.z - r)), r, h.x * 2.0, 0, _wall_mat)
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			_add_cylinder(Vector3(sx * (h.x - r), 0.0, sz * (h.z - r)), r, h.y * 2.0, 1, _wall_mat)
	# 8 rounded corners.
	for sx: float in [-1.0, 1.0]:
		for sy: float in [-1.0, 1.0]:
			for sz: float in [-1.0, 1.0]:
				_add_sphere(Vector3(sx * (h.x - r), sy * (h.y - r), sz * (h.z - r)), r, _wall_mat)
	_add_trim_bands()


func _add_end_wall(s: float) -> void:
	var h := HALF_EXTENTS
	var t := WALL_THICKNESS
	var gw := GOAL_WIDTH
	var gh := GOAL_HEIGHT
	var z := s * (h.z + t * 0.5)
	var side_width: float = h.x - gw * 0.5
	var side_center: float = gw * 0.5 + side_width * 0.5
	_add_box(Vector3(-side_center, 0.0, z), Vector3(side_width, h.y * 2.0, t), _wall_mat)
	_add_box(Vector3(side_center, 0.0, z), Vector3(side_width, h.y * 2.0, t), _wall_mat)
	var above_height: float = h.y - gh * 0.5
	var above_center: float = gh * 0.5 + above_height * 0.5
	_add_box(Vector3(0.0, above_center, z), Vector3(gw, above_height, t), _wall_mat)
	_add_box(Vector3(0.0, -above_center, z), Vector3(gw, above_height, t), _wall_mat)


func _add_goal_recess(s: float) -> void:
	var gw := GOAL_WIDTH
	var gh := GOAL_HEIGHT
	var gd := GOAL_DEPTH
	var hz := HALF_EXTENTS.z
	var mid_z: float = s * (hz + gd * 0.5)
	# Back wall.
	_add_box(Vector3(0.0, 0.0, s * (hz + gd + 0.25)), Vector3(gw, gh, 0.5), _wall_mat)
	# Sides.
	_add_box(Vector3(-(gw * 0.5 + 0.25), 0.0, mid_z), Vector3(0.5, gh, gd), _wall_mat)
	_add_box(Vector3(gw * 0.5 + 0.25, 0.0, mid_z), Vector3(0.5, gh, gd), _wall_mat)
	# Top and bottom.
	_add_box(Vector3(0.0, gh * 0.5 + 0.25, mid_z), Vector3(gw, 0.5, gd), _wall_mat)
	_add_box(Vector3(0.0, -(gh * 0.5 + 0.25), mid_z), Vector3(gw, 0.5, gd), _wall_mat)


func _add_trim_bands() -> void:
	var h := HALF_EXTENTS
	var inset: float = 0.04
	var band := 0.16
	for s: float in [-1.0, 1.0]:
		# Glowing lines where the four long fillets meet the flat faces.
		_add_visual_box(Vector3(0.0, s * (h.y - FILLET_RADIUS), s * 0.0), Vector3(h.x * 2.0, band, band), _trim_mat)
	# Goal line bands.
	for s: float in [-1.0, 1.0]:
		_add_visual_box(Vector3(0.0, -h.y + inset + 0.09, s * (h.z - inset)), Vector3(GOAL_WIDTH + 1.0, 0.05, 0.18), _trim_mat)
	# Four long emissive accent rails make the arena orientation readable from
	# every gravity phase without relying on a single floor.
	for sx: float in [-1.0, 1.0]:
		for sy: float in [-1.0, 1.0]:
			_add_visual_box(
				Vector3(sx * (h.x - inset - 0.10), sy * (h.y - inset - 0.10), 0.0),
				Vector3(0.10, 0.10, h.z * 2.0 - 0.8),
				_trim_mat
			)


func _add_box(center: Vector3, size: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = center
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(mi)
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	cs.position = center
	_geometry.add_child(cs)


func _add_visual_box(center: Vector3, size: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = center
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


func _add_cylinder(center: Vector3, radius: float, length: float, axis: int, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius
	cm.height = length
	cm.radial_segments = 28
	cm.rings = 1
	mi.mesh = cm
	mi.material_override = mat
	mi.position = center
	var rot := Vector3.ZERO
	if axis == 0:
		rot = Vector3(0.0, 0.0, 90.0)
	elif axis == 2:
		rot = Vector3(90.0, 0.0, 0.0)
	mi.rotation_degrees = rot
	add_child(mi)
	var cs := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = length
	cs.shape = shape
	cs.position = center
	cs.rotation_degrees = rot
	_geometry.add_child(cs)


func _add_sphere(center: Vector3, radius: float, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = radius
	sm.height = radius * 2.0
	sm.radial_segments = 24
	sm.rings = 12
	mi.mesh = sm
	mi.material_override = mat
	mi.position = center
	add_child(mi)
	var cs := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = radius
	cs.shape = shape
	cs.position = center
	_geometry.add_child(cs)


func _build_goals() -> void:
	for s: float in [-1.0, 1.0]:
		var goal := GOAL_SCENE.instantiate() as Goal
		goal.defending_team = 1 if s < 0.0 else 2
		goal.goal_width = GOAL_WIDTH
		goal.goal_height = GOAL_HEIGHT
		goal.goal_depth = GOAL_DEPTH
		goal.position = Vector3(0.0, 0.0, s * HALF_EXTENTS.z)
		if s < 0.0:
			goal.rotation.y = PI
		add_child(goal)
		goals.append(goal)


func _build_pads() -> void:
	if rules == null or not rules.boost_pads_enabled:
		return
	_pad_root = Node3D.new()
	_pad_root.name = "BoostPads"
	add_child(_pad_root)
	_pad_layout = _make_pad_layout()
	var id := 0
	for entry: Dictionary in _pad_layout:
		var pad := PAD_SCENE.instantiate() as BoostPad
		pad.pad_id = id
		pad.large = bool(entry["large"])
		pad.amount = rules.boost_pad_amount_large if pad.large else rules.boost_pad_amount_small
		pad.respawn_time = rules.large_pad_respawn if pad.large else rules.small_pad_respawn
		pad.surface_normal = entry["normal"]
		pad.transform = Transform3D(_basis_from_up(entry["normal"]), entry["pos"])
		_pad_root.add_child(pad)
		pads.append(pad)
		id += 1


## 6 large + 28 small, mirror symmetric across X and Z (goal axis).
func _make_pad_layout() -> Array[Dictionary]:
	var h := HALF_EXTENTS
	var layout: Array[Dictionary] = []
	# Large pads.
	layout.append(_pad_entry(Vector3(0.0, -h.y, 0.0), Vector3.UP, true))
	layout.append(_pad_entry(Vector3(0.0, h.y, 0.0), Vector3.DOWN, true))
	layout.append(_pad_entry(Vector3(-h.x, 0.0, 0.0), Vector3.RIGHT, true))
	layout.append(_pad_entry(Vector3(h.x, 0.0, 0.0), Vector3.LEFT, true))
	layout.append(_pad_entry(Vector3(0.0, 11.0, -h.z), Vector3.BACK, true))
	layout.append(_pad_entry(Vector3(0.0, 11.0, h.z), Vector3.FORWARD, true))
	# 8 small on floor, mirrored on ceiling.
	for x: float in [-12.0, 12.0]:
		for z: float in [-30.0, -12.0, 12.0, 30.0]:
			layout.append(_pad_entry(Vector3(x, -h.y, z), Vector3.UP, false))
			layout.append(_pad_entry(Vector3(x, h.y, z), Vector3.DOWN, false))
	# 4 small on each long wall.
	for x: float in [-h.x, h.x]:
		var n: Vector3 = Vector3.RIGHT if x < 0.0 else Vector3.LEFT
		for y: float in [-7.0, 7.0]:
			for z: float in [-20.0, 20.0]:
				layout.append(_pad_entry(Vector3(x, y, z), n, false))
	# 2 small above each goal.
	for z: float in [-h.z, h.z]:
		var n2: Vector3 = Vector3.BACK if z < 0.0 else Vector3.FORWARD
		for x: float in [-14.0, 14.0]:
			layout.append(_pad_entry(Vector3(x, 10.0, z), n2, false))
	return layout


func _pad_entry(surface_point: Vector3, normal: Vector3, large: bool) -> Dictionary:
	return {"pos": surface_point + normal * 0.12, "normal": normal, "large": large}


func _basis_from_up(up: Vector3) -> Basis:
	var y := up.normalized()
	var ref := Vector3.FORWARD if absf(y.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT
	var x := ref.cross(y).normalized()
	var z := x.cross(y).normalized()
	return Basis(x, y, z)


func _build_spawn_markers() -> void:
	spawn_markers.clear()
	var xs := [-9.0, 0.0, 9.0]
	for team in [1, 2]:
		for i in 3:
			var side: float = -1.0 if team == 1 else 1.0
			var forward := Vector3(0.0, 0.0, -side)
			var pos := Vector3(xs[i], -HALF_EXTENTS.y + SPAWN_HEIGHT, side * (HALF_EXTENTS.z - 5.0))
			spawn_markers.append(Transform3D(_basis_facing(forward, GravityManager.up), pos))


func _basis_facing(forward: Vector3, up: Vector3) -> Basis:
	var y := up.normalized()
	var z := -forward.normalized()
	var x := y.cross(z).normalized()
	z = x.cross(y).normalized()
	return Basis(x, y, z)


func get_spawn_transform(team: int, index: int) -> Transform3D:
	var base: int = 0 if team == 1 else 3
	var idx: int = base + clampi(index, 0, 2)
	if idx < spawn_markers.size():
		return spawn_markers[idx]
	return Transform3D(Basis.IDENTITY, Vector3(0.0, 0.0, 30.0))


func get_ball_spawn() -> Vector3:
	return Vector3.ZERO


func is_position_inside(pos: Vector3, margin: float = 0.0) -> bool:
	var h := HALF_EXTENTS
	return absf(pos.x) < h.x + margin and absf(pos.y) < h.y + margin and absf(pos.z) < h.z + margin


func is_pad_layout_symmetric(epsilon: float = 0.05) -> bool:
	if _pad_layout.is_empty():
		_pad_layout = _make_pad_layout()
	for entry: Dictionary in _pad_layout:
		var p: Vector3 = entry["pos"]
		var mirrored := [Vector3(-p.x, p.y, p.z), Vector3(p.x, p.y, -p.z), Vector3(-p.x, p.y, -p.z)]
		for m: Vector3 in mirrored:
			var found := false
			for other: Dictionary in _pad_layout:
				if bool(other["large"]) != bool(entry["large"]):
					continue
				if (other["pos"] as Vector3).distance_to(m) <= epsilon:
					found = true
					break
			if not found:
				return false
	return true


func pad_layout() -> Array[Dictionary]:
	if _pad_layout.is_empty():
		_pad_layout = _make_pad_layout()
	return _pad_layout


func _build_environment() -> void:
	var world_env := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = theme.sky_top
	sky_mat.sky_horizon_color = theme.sky_bottom
	sky_mat.ground_bottom_color = theme.sky_top
	sky_mat.ground_horizon_color = theme.sky_bottom
	sky_mat.sun_angle_max = 18.0
	sky.sky_material = sky_mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_color = theme.ambient_color
	env.ambient_light_energy = theme.ambient_energy
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.glow_enabled = true
	env.glow_intensity = 0.7
	env.glow_bloom = 0.12
	env.fog_enabled = theme.fog_enabled
	env.fog_light_color = theme.sky_bottom
	env.fog_density = theme.fog_density
	world_env.environment = env
	add_child(world_env)
	# One interior probe captures the emissive trim and goal accents for the car
	# and ball PBR materials without a costly per-frame update.
	var probe := ReflectionProbe.new()
	probe.name = "ArenaReflectionProbe"
	probe.size = Vector3(HALF_EXTENTS.x * 2.0, HALF_EXTENTS.y * 2.0, HALF_EXTENTS.z * 2.0)
	probe.interior = true
	probe.box_projection = true
	probe.update_mode = ReflectionProbe.UPDATE_ONCE
	add_child(probe)
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-58.0, -38.0, 0.0)
	sun.light_color = Color(1.0, 0.96, 0.9)
	sun.light_energy = theme.sun_energy
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 120.0
	add_child(sun)
	var fill := OmniLight3D.new()
	fill.name = "FillLight"
	fill.position = Vector3(0.0, 0.0, 0.0)
	fill.light_color = theme.trim_color
	fill.light_energy = 0.6
	fill.omni_range = 90.0
	add_child(fill)
	for s: float in [-1.0, 1.0]:
		var accent := OmniLight3D.new()
		accent.name = "AccentLight%s" % ("A" if s < 0.0 else "B")
		accent.position = Vector3(s * 17.0, 8.0, 0.0)
		accent.light_color = theme.accent_color
		accent.light_energy = 0.42
		accent.omni_range = 34.0
		accent.shadow_enabled = false
		add_child(accent)
