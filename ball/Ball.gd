extends RigidBody3D
class_name Ball
## Heavy, bouncy ball with custom gravity, speed clamping and car-hit impulses.
## Task 02.

@export var tuning: BallTuning

var _hit_cooldowns: Dictionary = {}


func _ready() -> void:
	if tuning == null:
		tuning = load("res://ball/BallTuning.tres") as BallTuning
	gravity_scale = 0.0
	mass = tuning.mass
	can_sleep = false
	continuous_cd = true
	contact_monitor = true
	max_contacts_reported = 8
	linear_damp = tuning.linear_damp
	angular_damp = tuning.angular_damp
	collision_layer = 4
	collision_mask = 1 | 2
	add_to_group("ball")
	_build_body()


func _build_body() -> void:
	var shape := SphereShape3D.new()
	shape.radius = tuning.radius
	var collider := CollisionShape3D.new()
	collider.name = "Sphere"
	collider.shape = shape
	add_child(collider)

	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "BallMesh"
	var sphere := SphereMesh.new()
	sphere.radius = tuning.radius
	sphere.height = tuning.radius * 2.0
	sphere.radial_segments = 32
	sphere.rings = 16
	mesh_instance.mesh = sphere
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.95, 0.95, 0.98)
	mat.metallic = 0.2
	mat.roughness = 0.25
	mesh_instance.material_override = mat
	add_child(mesh_instance)

	var pm := PhysicsMaterial.new()
	pm.bounce = tuning.bounce
	pm.friction = tuning.friction
	physics_material_override = pm


func _integrate_forces(body_state: PhysicsDirectBodyState3D) -> void:
	body_state.apply_central_force(
		GravityManager.gravity_dir * GravityManager.gravity_strength * mass
	)
	body_state.linear_velocity = clamp_velocity(body_state.linear_velocity, tuning.max_speed)
	_process_hits(body_state)


func _process_hits(body_state: PhysicsDirectBodyState3D) -> void:
	var delta: float = body_state.step
	for key: Variant in _hit_cooldowns.keys():
		_hit_cooldowns[key] = maxf(0.0, float(_hit_cooldowns[key]) - delta)

	var count: int = body_state.get_contact_count()
	for i: int in count:
		var other: Object = body_state.get_contact_collider_object(i)
		if not (other is Car):
			continue
		var car := other as Car
		if car.state == Car.State.DEMOLISHED:
			continue
		var id: int = car.get_instance_id()
		if float(_hit_cooldowns.get(id, 0.0)) > 0.0:
			continue

		var offset: Vector3 = body_state.get_contact_local_position(i) - body_state.transform.origin
		if offset.length_squared() < 0.0001:
			continue
		# Push from the contact point through the ball's centre.
		var push_dir: Vector3 = -offset.normalized()
		var car_velocity: Vector3 = body_state.get_contact_collider_velocity_at_position(i)
		var relative: Vector3 = car_velocity - body_state.linear_velocity
		var closing: float = relative.dot(push_dir)
		if closing < 1.0:
			continue

		# `power` is a velocity change; scale by mass to turn it into an impulse.
		var power: float = minf(closing * tuning.hit_transfer, tuning.max_hit_impulse)
		var impulse: Vector3 = push_dir * power
		impulse += GravityManager.up * power * tuning.pop_bias
		impulse *= mass
		body_state.apply_impulse(impulse, offset)
		body_state.apply_torque_impulse(
			offset.cross(impulse) * tuning.spin_transfer
		)
		_hit_cooldowns[id] = tuning.hit_cooldown
		Events.ball_hit.emit(power)


func reset_to_kickoff(position: Vector3) -> void:
	global_position = position
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	_hit_cooldowns.clear()


static func clamp_velocity(velocity: Vector3, max_speed: float) -> Vector3:
	if max_speed <= 0.0:
		return Vector3.ZERO
	var speed := velocity.length()
	if speed > max_speed:
		return velocity * (max_speed / speed)
	return velocity
