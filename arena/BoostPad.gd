class_name BoostPad
extends Area3D
## Pickup pad. Small pads respawn fast, large pads give full boost.

signal collected(pad_id: int, car_id: int)
signal respawned(pad_id: int)

const CAR_LAYER := 1 << 1
const PAD_LAYER := 1 << 3

@export var pad_id: int = 0
@export var large: bool = false
@export var amount: float = 12.0
@export var respawn_time: float = 4.0
@export var surface_normal: Vector3 = Vector3.UP

var active: bool = true
var _timer: float = 0.0
var _mesh: MeshInstance3D
var _shape: CollisionShape3D
var _material: StandardMaterial3D
var _pulse: float = 0.0


func _ready() -> void:
	collision_layer = PAD_LAYER
	collision_mask = CAR_LAYER
	monitoring = true
	monitorable = false
	body_entered.connect(_on_body_entered)
	_mesh = get_node_or_null("PadMesh") as MeshInstance3D
	_shape = get_node_or_null("CollisionShape3D") as CollisionShape3D
	_apply_size()
	_material = StandardMaterial3D.new()
	var color := Color(1.0, 0.62, 0.1) if large else Color(0.1, 0.85, 1.0)
	_material.albedo_color = color
	_material.emission_enabled = true
	_material.emission = color
	_material.emission_energy_multiplier = 2.0 if large else 1.2
	_material.metallic = 0.2
	_material.roughness = 0.4
	if _mesh != null:
		_mesh.material_override = _material
	# Arena renders all pads through two MultiMesh instances. Standalone pads
	# (tests, editor) keep their own mesh.
	if bool(get_meta("shared_visual", false)):
		if _mesh != null:
			_mesh.visible = false
		set_process(false)


func _apply_size() -> void:
	var radius: float = 1.8 if large else 1.1
	if _mesh != null and _mesh.mesh is CylinderMesh:
		var cm := _mesh.mesh as CylinderMesh
		cm.top_radius = radius
		cm.bottom_radius = radius
		cm.height = 0.22
	if _shape != null and _shape.shape is CylinderShape3D:
		var cs := _shape.shape as CylinderShape3D
		cs.radius = radius
		cs.height = 0.5


func _physics_process(delta: float) -> void:
	if active:
		return
	_timer -= delta
	if _timer <= 0.0:
		_respawn()


func _process(delta: float) -> void:
	if not active or _mesh == null:
		return
	_pulse += delta * (3.0 if large else 2.0)
	var energy: float = (1.6 if large else 1.0) + sin(_pulse) * 0.35
	if _material != null:
		_material.emission_energy_multiplier = energy


func _on_body_entered(body: Node) -> void:
	if not active or not (body is Car):
		return
	collect(body as Car)


func collect(car: Car) -> void:
	if not active:
		return
	if car.boost_component != null:
		car.boost_component.add(amount, large)
	active = false
	_timer = respawn_time
	visible = false
	# Area3D forbids direct monitoring changes inside its own signal callback.
	set_deferred("monitoring", false)
	if _shape != null:
		_shape.set_deferred("disabled", true)
	Events.pad_collected.emit(pad_id, car.car_id)
	collected.emit(pad_id, car.car_id)


func _respawn() -> void:
	active = true
	_timer = 0.0
	visible = true
	set_deferred("monitoring", true)
	if _shape != null:
		_shape.set_deferred("disabled", false)
	Events.pad_respawned.emit(pad_id)
	respawned.emit(pad_id)


func reset() -> void:
	active = true
	_timer = 0.0
	visible = true
	set_deferred("monitoring", true)
	if _shape != null:
		_shape.set_deferred("disabled", false)
