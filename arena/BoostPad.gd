class_name BoostPad
extends Area3D
## Boost pickup. Lives on any arena surface; the car layer triggers it.
## Large pads give 100 boost / 10 s respawn, small pads 12 boost / 4 s.

@export var large: bool = false

var inward_normal: Vector3 = Vector3.UP
var respawn_time: float = 4.0
var boost_amount: float = 12.0
var _active: bool = true
var _timer: float = 0.0
var _mesh: MeshInstance3D


func setup(p_position: Vector3, p_inward_normal: Vector3, p_large: bool) -> void:
	position = p_position
	inward_normal = p_inward_normal.normalized()
	large = p_large
	respawn_time = 10.0 if large else 4.0
	boost_amount = 100.0 if large else 12.0
	collision_layer = 8
	collision_mask = 2
	monitoring = true
	monitorable = true
	add_to_group("boost_pads")
	set_process(false)

	var radius: float = 1.6 if large else 0.9
	var shape := BoxShape3D.new()
	shape.size = Vector3(radius * 2.0, 1.2, radius * 2.0)
	var collider := CollisionShape3D.new()
	collider.name = "PadTrigger"
	collider.shape = shape
	add_child(collider)

	_mesh = MeshInstance3D.new()
	_mesh.name = "PadMesh"
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = radius
	cylinder.bottom_radius = radius
	cylinder.height = 0.08
	cylinder.radial_segments = 20
	_mesh.mesh = cylinder
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.55, 0.05) if large else Color(1.0, 0.85, 0.15)
	mat.emission_enabled = true
	mat.emission = mat.albedo_color
	mat.emission_energy_multiplier = 2.0 if large else 1.2
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color.a = 0.85
	_mesh.material_override = mat
	add_child(_mesh)

	# Local +Y points into the arena, away from the surface.
	var quat := Quaternion(Vector3.UP, inward_normal)
	basis = Basis(quat)
	body_entered.connect(_on_body_entered)


func _process(delta: float) -> void:
	if _active:
		return
	_timer -= delta
	if _timer <= 0.0:
		_respawn()


func _on_body_entered(body: Node3D) -> void:
	if not _active:
		return
	if body is Car:
		var car := body as Car
		if car.boost != null:
			car.boost.add(boost_amount)
			Events.event_feed.emit("+%d boost" % int(boost_amount))
		_active = false
		_timer = respawn_time
		monitoring = false
		_mesh.visible = false
		set_process(true)


func _respawn() -> void:
	_active = true
	monitoring = true
	_mesh.visible = true
	set_process(false)
