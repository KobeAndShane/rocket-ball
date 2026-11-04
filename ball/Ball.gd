class_name Ball
extends RigidBody3D
## Heavy arcade ball. Custom gravity, CCD, speed clamps and hit impulses.

const ARENA_LAYER := 1
const CAR_LAYER := 1 << 1
const BALL_LAYER := 1 << 2
const GOAL_LAYER := 1 << 4
const BALL_MASK := ARENA_LAYER | CAR_LAYER | GOAL_LAYER

@export var tuning: BallTuning

var _hit_cooldowns: Dictionary = {}
var _last_hit_position := Vector3.ZERO
var _last_hit_strength: float = 0.0
var _time_since_hit: float = 999.0
var last_hitter_id: int = -1


func _ready() -> void:
	if tuning == null:
		tuning = load("res://ball/BallTuning.tres") as BallTuning
	_apply_tuning()
	can_sleep = false
	continuous_cd = true
	collision_layer = BALL_LAYER
	collision_mask = BALL_MASK
	contact_monitor = true
	max_contacts_reported = 8
	gravity_scale = 0.0
	if get_node_or_null("CollisionShape3D") != null:
		var s := (get_node("CollisionShape3D") as CollisionShape3D).shape
		if s is SphereShape3D:
			(s as SphereShape3D).radius = tuning.radius
	var mesh_node := get_node_or_null("BallMesh") as MeshInstance3D
	if mesh_node != null and mesh_node.mesh is SphereMesh:
		var sphere := mesh_node.mesh as SphereMesh
		sphere.radius = tuning.radius
		sphere.height = tuning.radius * 2.0


func _apply_tuning() -> void:
	mass = tuning.mass
	linear_damp = tuning.linear_damping
	angular_damp = tuning.angular_damping
	var mat := physics_material_override
	if mat == null:
		mat = PhysicsMaterial.new()
		physics_material_override = mat
	mat.bounce = tuning.bounce
	mat.friction = tuning.friction


func _physics_process(delta: float) -> void:
	_time_since_hit += delta
	for key: Variant in _hit_cooldowns.keys():
		_hit_cooldowns[key] = float(_hit_cooldowns[key]) - delta


func _integrate_forces(ps: PhysicsDirectBodyState3D) -> void:
	var dt: float = ps.step
	ps.linear_velocity += GravityManager.gravity_dir * GravityManager.gravity_strength * dt
	_handle_contacts(ps)
	# Speed clamps keep CCD and gameplay predictable.
	if ps.linear_velocity.length() > tuning.max_speed:
		ps.linear_velocity = ps.linear_velocity.normalized() * tuning.max_speed
	if ps.angular_velocity.length() > tuning.max_angular_speed:
		ps.angular_velocity = ps.angular_velocity.normalized() * tuning.max_angular_speed


func _handle_contacts(ps: PhysicsDirectBodyState3D) -> void:
	var count := ps.get_contact_count()
	for i in count:
		var collider := ps.get_contact_collider_object(i)
		if not (collider is Car):
			continue
		var car := collider as Car
		if car.state == Car.State.DEMOLISHED:
			continue
		var key: int = car.car_id
		var cd: float = float(_hit_cooldowns.get(key, 0.0))
		if cd > 0.0:
			continue
		var rel: Vector3 = car.linear_velocity - ps.linear_velocity
		var rel_speed: float = rel.length()
		if rel_speed < tuning.min_hit_speed:
			continue
		_hit_cooldowns[key] = tuning.hit_cooldown
		var contact: Vector3 = ps.get_contact_collider_position(i)
		var offset: Vector3 = contact - ps.transform.origin
		var impulse: Vector3 = rel * tuning.hit_gain * tuning.mass
		# Pop the ball along local up for readable, satisfying hits.
		var car_up: Vector3 = car.global_transform.basis.y.normalized()
		var pop_dir: Vector3 = (GravityManager.up * 0.65 + car_up * 0.35).normalized()
		impulse += pop_dir * tuning.pop_up_impulse * minf(rel_speed / 10.0, 2.5) * tuning.mass
		ps.apply_impulse(impulse, offset)
		# Spin transfer from hit offset.
		var spin: Vector3 = offset.cross(rel) * tuning.spin_transfer * tuning.mass
		ps.apply_torque_impulse(spin)
		_last_hit_position = contact
		_last_hit_strength = rel_speed
		_time_since_hit = 0.0
		last_hitter_id = car.car_id
		Events.ball_hit.emit(rel_speed, contact, car.car_id)


func reset_to_kickoff(center: Vector3, height_offset: float = -1.0) -> void:
	var h: float = tuning.kickoff_height if height_offset < 0.0 else height_offset
	global_transform = Transform3D(Basis.IDENTITY, center + GravityManager.up * h)
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	sleeping = false
	_hit_cooldowns.clear()
	last_hitter_id = -1
	Events.ball_reset.emit()


func set_radius(new_radius: float, new_mass: float = -1.0) -> void:
	tuning.radius = new_radius
	if new_mass > 0.0:
		tuning.mass = new_mass
	_apply_tuning()
	var shape_node := get_node_or_null("CollisionShape3D") as CollisionShape3D
	if shape_node != null and shape_node.shape is SphereShape3D:
		(shape_node.shape as SphereShape3D).radius = new_radius
	var mesh_node := get_node_or_null("BallMesh") as MeshInstance3D
	if mesh_node != null and mesh_node.mesh is SphereMesh:
		var sphere := mesh_node.mesh as SphereMesh
		sphere.radius = new_radius
		sphere.height = new_radius * 2.0
	mass = tuning.mass


func get_speed() -> float:
	return linear_velocity.length()


func last_hit_info() -> Dictionary:
	return {
		"position": _last_hit_position,
		"strength": _last_hit_strength,
		"time_since": _time_since_hit,
	}


func get_predicted_steps(steps: int, dt: float) -> Array[Vector3]:
	var out: Array[Vector3] = []
	var p := global_position
	var v := linear_velocity
	var g := GravityManager.gravity_dir * GravityManager.gravity_strength
	for i in steps:
		v += g * dt
		p += v * dt
		out.append(p)
	return out
