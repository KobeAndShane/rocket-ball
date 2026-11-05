extends Node3D
class_name Arena
## Procedural rounded-box arena (Task 03). Every inner edge and corner is
## filleted so cars can drive the entire surface. Goals sit on the +-X faces;
## gravity rotates around X, so goals are never floor or ceiling.

@export var half_extents: Vector3 = Vector3(30.0, 18.0, 22.0)
@export var fillet_radius: float = 4.0
@export var goal_width: float = 10.0
@export var goal_height: float = 6.0

const AXES: Array[Vector3] = [Vector3.RIGHT, Vector3.UP, Vector3.BACK]


func _ready() -> void:
	_build_shell()
	_build_goals()
	_build_pads()
	_build_environment()


func _build_shell() -> void:
	var mesh := generate_shell_mesh(half_extents, fillet_radius)
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "ArenaMesh"
	mesh_instance.mesh = mesh
	add_child(mesh_instance)

	var body := StaticBody3D.new()
	body.name = "ArenaBody"
	body.collision_layer = 1
	body.collision_mask = 0
	var collider := CollisionShape3D.new()
	collider.name = "ArenaCollider"
	var shape := mesh.create_trimesh_shape()
	# The shell is a single thin surface; colliding with both sides stops fast
	# cars or the ball from tunnelling through it.
	shape.backface_collision = true
	collider.shape = shape
	body.add_child(collider)
	add_child(body)


func _build_goals() -> void:
	for team: int in [0, 1]:
		var goal := Goal.new()
		goal.name = "GoalBlue" if team == 0 else "GoalOrange"
		var color := Color(0.15, 0.45, 1.0) if team == 0 else Color(1.0, 0.42, 0.1)
		goal.setup(team, color)
		var depth: float = goal.depth
		if team == 0:
			goal.position = Vector3(-half_extents.x + depth * 0.5 - 0.1, 0.0, 0.0)
		else:
			goal.position = Vector3(half_extents.x - depth * 0.5 + 0.1, 0.0, 0.0)
			goal.rotation.y = PI
		add_child(goal)


func _build_pads() -> void:
	for entry: Dictionary in pad_layout(half_extents, fillet_radius):
		var pad := BoostPad.new()
		pad.name = "BoostPad"
		pad.setup(
			entry["position"] as Vector3,
			entry["normal"] as Vector3,
			bool(entry["large"])
		)
		add_child(pad)


func _build_environment() -> void:
	var world_env := WorldEnvironment.new()
	world_env.name = "WorldEnvironment"
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.06, 0.09, 0.16)
	sky_mat.sky_horizon_color = Color(0.16, 0.18, 0.24)
	sky_mat.ground_bottom_color = Color(0.03, 0.03, 0.05)
	sky_mat.ground_horizon_color = Color(0.12, 0.12, 0.16)
	sky.sky_material = sky_mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.9
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	world_env.environment = env
	add_child(world_env)

	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-58.0, -38.0, 0.0)
	sun.light_energy = 1.25
	sun.shadow_enabled = true
	add_child(sun)

	var fill := OmniLight3D.new()
	fill.name = "ArenaFill"
	fill.position = Vector3(0.0, 0.0, 0.0)
	fill.omni_range = 55.0
	fill.light_energy = 1.1
	fill.light_color = Color(0.6, 0.75, 1.0)
	add_child(fill)


## Build the inward-facing rounded-box surface. Six flat insets + twelve
## quarter-cylinder edge strips + eight spherical corner octants.
func generate_shell_mesh(half: Vector3, radius: float) -> ArrayMesh:
	var r: float = clampf(radius, 0.05, minf(half.x, minf(half.y, half.z)) * 0.49)
	var h: Array[float] = [half.x, half.y, half.z]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# Flat faces.
	for axis: int in 3:
		for sign_value: int in [-1, 1]:
			var u_axis: int = (axis + 1) % 3
			var v_axis: int = (axis + 2) % 3
			var eu: float = h[u_axis] - r
			var ev: float = h[v_axis] - r
			var n: Vector3 = AXES[axis] * float(sign_value)
			var center: Vector3 = n * h[axis]
			var corners: Array[Vector3] = [
				center - AXES[u_axis] * eu - AXES[v_axis] * ev,
				center + AXES[u_axis] * eu - AXES[v_axis] * ev,
				center + AXES[u_axis] * eu + AXES[v_axis] * ev,
				center - AXES[u_axis] * eu + AXES[v_axis] * ev,
			]
			var normals: Array[Vector3] = [-n, -n, -n, -n]
			_add_quad(st, corners, normals)

	# Twelve edge fillets.
	for i: int in 3:
		for j: int in range(i + 1, 3):
			var k: int = 3 - i - j
			for si: int in [-1, 1]:
				for sj: int in [-1, 1]:
					var center := Vector3.ZERO
					center[i] = float(si) * (h[i] - r)
					center[j] = float(sj) * (h[j] - r)
					var ek: float = h[k] - r
					var steps: int = 6
					for a: int in steps:
						var phi0: float = TAU * 0.25 * float(a) / float(steps)
						var phi1: float = TAU * 0.25 * float(a + 1) / float(steps)
						var corners: Array[Vector3] = [
							_edge_point(center, i, j, k, si, sj, phi0, -ek, r),
							_edge_point(center, i, j, k, si, sj, phi0, ek, r),
							_edge_point(center, i, j, k, si, sj, phi1, ek, r),
							_edge_point(center, i, j, k, si, sj, phi1, -ek, r),
						]
						var normals: Array[Vector3] = [
							-_edge_dir(i, j, si, sj, phi0),
							-_edge_dir(i, j, si, sj, phi0),
							-_edge_dir(i, j, si, sj, phi1),
							-_edge_dir(i, j, si, sj, phi1),
						]
						_add_quad(st, corners, normals)

	# Eight spherical corner patches.
	var c_steps: int = 5
	for sx: int in [-1, 1]:
		for sy: int in [-1, 1]:
			for sz: int in [-1, 1]:
				var center := Vector3(
					float(sx) * (half.x - r),
					float(sy) * (half.y - r),
					float(sz) * (half.z - r)
				)
				for a: int in c_steps:
					var u0: float = TAU * 0.25 * float(a) / float(c_steps)
					var u1: float = TAU * 0.25 * float(a + 1) / float(c_steps)
					for b: int in c_steps:
						var v0: float = TAU * 0.25 * float(b) / float(c_steps)
						var v1: float = TAU * 0.25 * float(b + 1) / float(c_steps)
						var corners: Array[Vector3] = [
							center + _corner_dir(sx, sy, sz, u0, v0) * r,
							center + _corner_dir(sx, sy, sz, u1, v0) * r,
							center + _corner_dir(sx, sy, sz, u1, v1) * r,
							center + _corner_dir(sx, sy, sz, u0, v1) * r,
						]
						var normals: Array[Vector3] = [
							-_corner_dir(sx, sy, sz, u0, v0),
							-_corner_dir(sx, sy, sz, u1, v0),
							-_corner_dir(sx, sy, sz, u1, v1),
							-_corner_dir(sx, sy, sz, u0, v1),
						]
						_add_quad(st, corners, normals)

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.23, 0.25, 0.31)
	mat.metallic = 0.55
	mat.roughness = 0.35
	st.set_material(mat)
	return st.commit()


func _edge_point(
	center: Vector3,
	i: int,
	j: int,
	k: int,
	si: int,
	sj: int,
	phi: float,
	offset: float,
	radius: float
) -> Vector3:
	return center + _edge_dir(i, j, si, sj, phi) * radius + AXES[k] * offset


func _edge_dir(i: int, j: int, si: int, sj: int, phi: float) -> Vector3:
	return (AXES[i] * (float(si) * cos(phi)) + AXES[j] * (float(sj) * sin(phi))).normalized()


func _corner_dir(sx: int, sy: int, sz: int, u: float, v: float) -> Vector3:
	return Vector3(
		float(sx) * cos(u),
		float(sy) * sin(u) * cos(v),
		float(sz) * sin(u) * sin(v)
	).normalized()


func _add_quad(
	st: SurfaceTool, positions: Array[Vector3], normals: Array[Vector3]
) -> void:
	# Godot treats clockwise triangles as front faces, so the winding must be
	# clockwise when viewed from the side the normal points to (inside the arena).
	var cross: Vector3 = (positions[1] - positions[0]).cross(positions[3] - positions[0])
	var avg_normal: Vector3 = (normals[0] + normals[1] + normals[2] + normals[3]).normalized()
	if cross.dot(avg_normal) > 0.0:
		var p_tmp: Vector3 = positions[1]
		positions[1] = positions[3]
		positions[3] = p_tmp
		var n_tmp: Vector3 = normals[1]
		normals[1] = normals[3]
		normals[3] = n_tmp

	var order: Array[int] = [0, 1, 2, 0, 2, 3]
	for idx: int in order:
		st.set_normal(normals[idx])
		st.add_vertex(positions[idx])


func get_spawn_transform(team: int, slot: int = 0) -> Transform3D:
	var floor_y: float = -half_extents.y + 1.0
	var z_positions: Array[float] = [-6.0, 0.0, 6.0]
	var z: float = z_positions[slot % z_positions.size()]
	var x: float = -half_extents.x + 6.0 if team == 0 else half_extents.x - 6.0
	var forward: Vector3 = Vector3.RIGHT if team == 0 else Vector3.LEFT
	return transform_from_up_forward(Vector3(x, floor_y, z), Vector3.UP, forward)


static func transform_from_up_forward(pos: Vector3, up: Vector3, forward: Vector3) -> Transform3D:
	var up_n: Vector3 = up.normalized()
	var fwd: Vector3 = forward - up_n * forward.dot(up_n)
	if fwd.length_squared() < 0.0001:
		fwd = Vector3.FORWARD
	fwd = fwd.normalized()
	var z_axis: Vector3 = -fwd
	var x_axis: Vector3 = up_n.cross(z_axis).normalized()
	return Transform3D(Basis(x_axis, up_n, z_axis), pos)


## 6 large pads + 28 small pads. The pattern is identical on all four
## gravity-rotatable faces, so the layout is mirror symmetric.
static func pad_layout(half: Vector3, r: float) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var inward_normals: Array[Vector3] = [
		Vector3.UP, Vector3.DOWN, Vector3.BACK, Vector3.FORWARD,
	]
	for n: Vector3 in inward_normals:
		var vertical: bool = absf(n.y) < 0.5
		var extent_n: float = half.z if vertical else half.y
		var e_u: float = half.x - r - 2.0
		var e_v: float = (half.y if vertical else half.z) - r - 2.0
		var u_axis: Vector3 = Vector3.RIGHT
		var v_axis: Vector3 = Vector3.UP if vertical else Vector3.BACK
		var surface_point: Vector3 = -n * extent_n + n * 0.35

		var large_uv: Array[Vector2] = []
		if vertical:
			large_uv.append(Vector2(0.0, 0.0))
		else:
			large_uv.append(Vector2(-0.5, 0.0))
			large_uv.append(Vector2(0.5, 0.0))
		for uv: Vector2 in large_uv:
			result.append({
				"position": surface_point + u_axis * uv.x * e_u + v_axis * uv.y * e_v,
				"normal": n,
				"large": true,
			})

		var small_uv: Array[Vector2] = []
		small_uv.assign([
			Vector2(-0.55, 0.0),
			Vector2(0.55, 0.0),
			Vector2(-0.25, 0.55),
			Vector2(0.25, 0.55),
			Vector2(-0.25, -0.55),
			Vector2(0.25, -0.55),
			Vector2(0.0, 0.28),
		])
		for uv: Vector2 in small_uv:
			result.append({
				"position": surface_point + u_axis * uv.x * e_u + v_axis * uv.y * e_v,
				"normal": n,
				"large": false,
			})
	return result
