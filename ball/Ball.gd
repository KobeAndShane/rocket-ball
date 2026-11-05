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
var _cooldown_ids: Array[int] = []
var _last_hit_position := Vector3.ZERO
var _last_hit_strength: float = 0.0
var _time_since_hit: float = 999.0
var last_hitter_id: int = -1
var _trail: GPUParticles3D
var _trail_process: ParticleProcessMaterial


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
		_apply_ball_material(mesh_node)
	_build_trail()


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


func _apply_ball_material(mesh_node: MeshInstance3D) -> void:
	var shader := load("res://vfx/ball_panel.gdshader") as Shader
	if shader == null:
		return
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("base_color", Color(0.84, 0.88, 0.96))
	material.set_shader_parameter("seam_color", Color(0.16, 0.68, 1.0))
	material.set_shader_parameter("seam_glow", 0.85)
	mesh_node.material_override = material


func _build_trail() -> void:
	_trail = GPUParticles3D.new()
	_trail.name = "BallTrail"
	_trail.amount = 56
	_trail.lifetime = 0.48
	_trail.one_shot = false
	_trail.explosiveness = 0.0
	_trail.randomness = 0.45
	_trail.fixed_fps = 60
	_trail.interpolate = true
	_trail.local_coords = false
	_trail.emitting = false
	_trail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_trail.visibility_aabb = AABB(Vector3(-40.0, -30.0, -50.0), Vector3(80.0, 60.0, 100.0))
	_trail_process = ParticleProcessMaterial.new()
	_trail_process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	_trail_process.emission_sphere_radius = tuning.radius * 0.55
	_trail_process.direction = Vector3.UP
	_trail_process.spread = 180.0
	_trail_process.initial_velocity_min = 0.4
	_trail_process.initial_velocity_max = 2.2
	_trail_process.gravity = Vector3.ZERO
	_trail_process.damping_min = 0.8
	_trail_process.damping_max = 2.0
	_trail_process.scale_min = 0.28
	_trail_process.scale_max = 0.72
	_trail_process.color = Color(0.38, 0.78, 1.0, 1.0)
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1.0, 1.0, 1.0, 0.75))
	gradient.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
	var ramp := GradientTexture1D.new()
	ramp.gradient = gradient
	_trail_process.color_ramp = ramp
	_trail.process_material = _trail_process
	var quad := QuadMesh.new()
	quad.size = Vector2(0.42, 0.42)
	_trail.draw_pass_1 = quad
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.billboard_keep_scale = true
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.vertex_color_use_as_albedo = true
	material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	var glow_gradient := Gradient.new()
	glow_gradient.set_color(0, Color(1.0, 1.0, 1.0, 1.0))
	glow_gradient.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
	var glow_texture := GradientTexture2D.new()
	glow_texture.gradient = glow_gradient
	glow_texture.fill = GradientTexture2D.FILL_RADIAL
	glow_texture.fill_from = Vector2(0.5, 0.5)
	glow_texture.fill_to = Vector2(1.0, 0.5)
	glow_texture.width = 32
	glow_texture.height = 32
	material.albedo_texture = glow_texture
	_trail.material_override = material
	add_child(_trail)


func _physics_process(delta: float) -> void:
	_time_since_hit += delta
	var i: int = 0
	while i < _cooldown_ids.size():
		var key: int = _cooldown_ids[i]
		var remaining: float = float(_hit_cooldowns.get(key, 0.0)) - delta
		if remaining <= 0.0:
			_hit_cooldowns.erase(key)
			_cooldown_ids.remove_at(i)
		else:
			_hit_cooldowns[key] = remaining
			i += 1
	_update_trail()


func _update_trail() -> void:
	if _trail == null:
		return
	var speed: float = linear_velocity.length()
	var threshold: float = maxf(tuning.max_speed * 0.22, 9.0)
	_trail.emitting = speed >= threshold
	if _trail.emitting:
		_trail.amount_ratio = clampf(speed / maxf(tuning.max_speed, 1.0), 0.18, 1.0)


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
		if not _hit_cooldowns.has(key):
			_cooldown_ids.append(key)
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
	_cooldown_ids.clear()
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


## Network snapshots: position, orientation, linear and angular velocity.
func get_snapshot_state() -> Dictionary:
	return {
		"p": global_position,
		"q": global_transform.basis.get_rotation_quaternion(),
		"v": linear_velocity,
		"w": angular_velocity,
	}


func set_snapshot_state(state: Dictionary) -> void:
	if state.is_empty():
		return
	var p: Vector3 = state.get("p", global_position)
	var q: Quaternion = state.get("q", Quaternion.IDENTITY)
	global_transform = Transform3D(Basis(q).orthonormalized(), p)
	linear_velocity = state.get("v", Vector3.ZERO)
	angular_velocity = state.get("w", Vector3.ZERO)
	sleeping = false


## Client-side: snapshots own the ball; disable local collision/goal logic.
func set_network_ghost(enabled: bool) -> void:
	if enabled:
		freeze = true
		collision_layer = 0
		collision_mask = 0
	else:
		freeze = false
		collision_layer = BALL_LAYER
		collision_mask = BALL_MASK


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
