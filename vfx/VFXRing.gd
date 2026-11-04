class_name VFXRing
extends Node3D
## Pooled expanding shockwave ring. One mesh per pool node, re-used by scaling
## and fading. Used for goals, demolitions and gravity-shift ripples.

var mesh_instance: MeshInstance3D
var material: StandardMaterial3D

var _duration: float = 0.8
var _elapsed: float = 0.0
var _start_scale: float = 0.3
var _end_scale: float = 3.0
var _energy: float = 5.0
var _active: bool = false
var _prewarmed: bool = false


func configure(radius: float = 3.0, thickness: float = 0.16) -> void:
	mesh_instance = MeshInstance3D.new()
	mesh_instance.name = "RingMesh"
	var torus := TorusMesh.new()
	torus.inner_radius = maxf(radius - thickness, 0.1)
	torus.outer_radius = radius
	torus.rings = 40
	torus.ring_segments = 12
	mesh_instance.mesh = torus
	material = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.emission_enabled = true
	material.emission = Color(0.2, 0.8, 1.0)
	material.emission_energy_multiplier = 4.0
	material.albedo_color = Color(0.2, 0.8, 1.0, 0.8)
	mesh_instance.material_override = material
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mesh_instance)
	visible = false
	set_process(false)


func play(
		at: Vector3,
		color: Color,
		start_scale: float,
		end_scale: float,
		duration: float,
		up: Vector3
) -> void:
	if mesh_instance == null:
		return
	_duration = maxf(duration, 0.08)
	_elapsed = 0.0
	_start_scale = maxf(start_scale, 0.02)
	_end_scale = maxf(end_scale, _start_scale)
	_active = true
	global_transform = Transform3D(_basis_from_up(up), at)
	scale = Vector3.ONE * _start_scale
	material.albedo_color = Color(color.r, color.g, color.b, 0.8)
	material.emission = color
	material.emission_energy_multiplier = _energy
	visible = true
	set_process(true)


func prewarm() -> void:
	_prewarmed = true
	visible = false
	set_process(false)


func is_prewarmed() -> bool:
	return _prewarmed


func is_active() -> bool:
	return _active


func _process(delta: float) -> void:
	if not _active:
		return
	_elapsed += delta
	var t: float = clampf(_elapsed / _duration, 0.0, 1.0)
	var eased: float = 1.0 - pow(1.0 - t, 3.0)
	scale = Vector3.ONE * lerpf(_start_scale, _end_scale, eased)
	material.albedo_color.a = 0.85 * (1.0 - t)
	material.emission_energy_multiplier = _energy * (1.0 - t)
	if t >= 1.0:
		visible = false
		_active = false
		set_process(false)


func _basis_from_up(up: Vector3) -> Basis:
	var y: Vector3 = up.normalized()
	if y.length_squared() < 0.001:
		y = GravityManager.up
	var reference: Vector3 = Vector3.FORWARD if absf(y.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT
	var x: Vector3 = reference.cross(y).normalized()
	var z: Vector3 = x.cross(y).normalized()
	return Basis(x, y, z)
