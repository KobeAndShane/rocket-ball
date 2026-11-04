class_name CarPreview
extends SubViewportContainer
## Small turntable car preview used by the locker. It renders a frozen car in a
## private viewport so menu cosmetics can be previewed without starting a match.

const CAR_SCENE := preload("res://car/Car.tscn")

var car: Car
var viewport: SubViewport
var _loadout: Dictionary = {}
var _turntable: Node3D


func _ready() -> void:
	stretch = true
	custom_minimum_size = Vector2(0.0, 270.0)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	viewport = SubViewport.new()
	viewport.name = "PreviewViewport"
	viewport.size = Vector2i(720, 380)
	viewport.own_world_3d = true
	viewport.transparent_bg = false
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	_build_stage()
	_turntable = Node3D.new()
	_turntable.name = "Turntable"
	viewport.add_child(_turntable)
	car = CAR_SCENE.instantiate() as Car
	car.frozen = true
	car.auto_respawn = false
	car.control_mode = Car.DriveMode.NETWORK
	car.team = 1
	_turntable.add_child(car)
	car.position = Vector3(0.0, 0.72, 0.0)
	car.set_physics_process(false)
	if _loadout.is_empty():
		_loadout = CosmeticLibrary.default_loadout()
	car.apply_cosmetics(_loadout)


func _process(delta: float) -> void:
	if _turntable != null:
		_turntable.rotate_y(delta * 0.55)


func apply_loadout(loadout: Dictionary) -> void:
	_loadout = CosmeticLibrary.sanitize_loadout(loadout)
	if is_instance_valid(car):
		car.apply_cosmetics(_loadout)


func current_loadout() -> Dictionary:
	return _loadout.duplicate(true)


func _build_stage() -> void:
	var env_node := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.015, 0.03, 0.06)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.45, 0.65, 0.95)
	env.ambient_light_energy = 0.7
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.6
	env_node.environment = env
	viewport.add_child(env_node)

	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-52.0, -38.0, 0.0)
	key.light_energy = 1.4
	key.light_color = Color(0.85, 0.92, 1.0)
	key.shadow_enabled = true
	viewport.add_child(key)

	var rim := OmniLight3D.new()
	rim.position = Vector3(-3.2, 2.6, -2.0)
	rim.light_color = Color(0.15, 0.8, 1.0)
	rim.light_energy = 4.0
	rim.omni_range = 8.0
	viewport.add_child(rim)

	var camera := Camera3D.new()
	camera.position = Vector3(5.2, 3.1, 5.8)
	camera.fov = 42.0
	viewport.add_child(camera)
	camera.look_at(Vector3(0.0, 0.65, 0.0))

	var floor_mesh := MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 3.2
	cylinder.bottom_radius = 3.2
	cylinder.height = 0.08
	cylinder.radial_segments = 48
	floor_mesh.mesh = cylinder
	floor_mesh.position = Vector3(0.0, 0.0, 0.0)
	var floor_mat := StandardMaterial3D.new()
	floor_mat.albedo_color = Color(0.04, 0.07, 0.12)
	floor_mat.metallic = 0.6
	floor_mat.roughness = 0.4
	floor_mat.emission_enabled = true
	floor_mat.emission = Color(0.05, 0.35, 0.55)
	floor_mat.emission_energy_multiplier = 0.25
	floor_mesh.material_override = floor_mat
	viewport.add_child(floor_mesh)

	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 3.1
	torus.outer_radius = 3.24
	torus.rings = 64
	torus.ring_segments = 8
	ring.mesh = torus
	ring.position = Vector3(0.0, 0.03, 0.0)
	var ring_mat := StandardMaterial3D.new()
	ring_mat.albedo_color = Color(0.2, 0.85, 1.0)
	ring_mat.emission_enabled = true
	ring_mat.emission = Color(0.2, 0.85, 1.0)
	ring_mat.emission_energy_multiplier = 2.0
	ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring.material_override = ring_mat
	viewport.add_child(ring)
