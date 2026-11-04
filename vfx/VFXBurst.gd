class_name VFXBurst
extends Node3D
## One pre-built, reusable particle burst. VFXService pools these nodes and
## replays them with `play()` instead of instantiating particle systems at runtime.

var particles: GPUParticles3D
var light: OmniLight3D
var process_material: ParticleProcessMaterial
var mesh_material: StandardMaterial3D

var lifetime: float = 0.6
var particle_size: float = 0.2
var emission_radius: float = 0.4
var light_energy: float = 0.0
var gravity_scale: float = 6.0

var _busy: float = 0.0
var _active: bool = false
var _base_light_energy: float = 0.0
var _prewarmed: bool = false


func configure(
		max_particles: int,
		life: float,
		size: float,
		radius: float,
		additive: bool,
		burst_speed: float,
		light_power: float = 0.0,
		gravity_strength: float = 6.0
) -> void:
	lifetime = maxf(life, 0.05)
	particle_size = maxf(size, 0.02)
	emission_radius = maxf(radius, 0.02)
	_base_light_energy = maxf(light_power, 0.0)
	gravity_scale = gravity_strength

	particles = GPUParticles3D.new()
	particles.name = "Particles"
	particles.amount = maxi(max_particles, 4)
	particles.lifetime = lifetime
	particles.one_shot = true
	particles.explosiveness = 0.85
	particles.randomness = 0.35
	particles.fixed_fps = 60
	particles.interpolate = true
	particles.local_coords = false
	particles.emitting = false
	particles.visible = false
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	particles.draw_order = GPUParticles3D.DRAW_ORDER_VIEW_DEPTH
	particles.visibility_aabb = AABB(Vector3(-32.0, -32.0, -32.0), Vector3(64.0, 64.0, 64.0))
	add_child(particles)

	process_material = ParticleProcessMaterial.new()
	process_material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process_material.emission_sphere_radius = emission_radius
	process_material.direction = Vector3.UP
	process_material.spread = 180.0
	process_material.initial_velocity_min = burst_speed * 0.45
	process_material.initial_velocity_max = burst_speed
	process_material.gravity = Vector3.ZERO
	process_material.damping_min = 0.4
	process_material.damping_max = 1.8
	process_material.scale_min = 0.55
	process_material.scale_max = 1.0
	process_material.angular_velocity_min = -180.0
	process_material.angular_velocity_max = 180.0
	process_material.color = Color.WHITE
	process_material.color_ramp = _fade_ramp(false)
	process_material.scale_curve = _scale_curve()
	particles.process_material = process_material

	var quad := QuadMesh.new()
	quad.size = Vector2(particle_size, particle_size)
	particles.draw_pass_1 = quad
	mesh_material = _particle_material(additive)
	particles.material_override = mesh_material

	if _base_light_energy > 0.0:
		light = OmniLight3D.new()
		light.name = "Flash"
		light.light_color = Color.WHITE
		light.light_energy = 0.0
		light.omni_range = 14.0
		light.shadow_enabled = false
		add_child(light)

	set_process(false)


func play(at: Vector3, color: Color, strength: float = 1.0) -> void:
	if particles == null:
		return
	var amount: float = clampf(strength, 0.15, 1.0)
	global_position = at
	process_material.color = color
	process_material.gravity = GravityManager.gravity_dir * gravity_scale
	particles.amount_ratio = amount
	particles.restart()
	particles.emitting = true
	particles.visible = true
	_busy = lifetime + 0.12
	_active = true
	if light != null:
		light.light_color = color
		light.light_energy = _base_light_energy * amount
		set_process(true)
		visible = true
	else:
		set_process(true)


func stop() -> void:
	if particles != null:
		particles.emitting = false
		particles.visible = false
	if light != null:
		light.light_energy = 0.0
	_active = false
	visible = false
	set_process(false)


func prewarm() -> void:
	if particles == null:
		return
	# Preprocess the simulation so the first real burst does not have to build
	# up its particle buffer while the player is already in a kickoff.
	particles.preprocess = lifetime
	particles.amount_ratio = 0.02
	particles.restart()
	particles.emitting = false
	particles.visible = false
	_prewarmed = true
	visible = false


func is_prewarmed() -> bool:
	return _prewarmed


func is_active() -> bool:
	return _active


func _process(delta: float) -> void:
	if not _active:
		return
	_busy -= delta
	if light != null:
		light.light_energy = maxf(0.0, _base_light_energy * (_busy / maxf(lifetime, 0.05)))
	if _busy <= 0.0:
		stop()


func _fade_ramp(soft: bool) -> GradientTexture1D:
	var gradient := Gradient.new()
	gradient.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CUBIC
	gradient.set_color(0, Color(1.0, 1.0, 1.0, 1.0 if not soft else 0.9))
	gradient.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
	var texture := GradientTexture1D.new()
	texture.gradient = gradient
	return texture


func _scale_curve() -> CurveTexture:
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 1.0))
	curve.add_point(Vector2(0.7, 0.8))
	curve.add_point(Vector2(1.0, 0.05))
	var texture := CurveTexture.new()
	texture.curve = curve
	return texture


func _particle_material(additive: bool) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if additive else BaseMaterial3D.BLEND_MODE_MIX
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.billboard_keep_scale = true
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.vertex_color_use_as_albedo = true
	material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	material.albedo_texture = _soft_texture()
	return material


func _soft_texture() -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1.0, 1.0, 1.0, 1.0))
	gradient.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	texture.width = 32
	texture.height = 32
	return texture
