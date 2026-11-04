class_name Goal
extends Area3D
## Goal trigger + visual frame. Recess geometry is part of the Arena.

signal scored(scoring_team: int)

const BALL_LAYER := 1 << 2
const GOAL_LAYER := 1 << 4

@export var defending_team: int = 1
@export var goal_width: float = 12.0
@export var goal_height: float = 8.0
@export var goal_depth: float = 6.0
@export var enabled: bool = true

var _latched: bool = false
var _frame_material: StandardMaterial3D
var _net_material: ShaderMaterial


func _ready() -> void:
	collision_layer = GOAL_LAYER
	collision_mask = BALL_LAYER
	monitoring = true
	monitorable = false
	body_entered.connect(_on_body_entered)
	_build_trigger()
	_build_visuals()


func _build_trigger() -> void:
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(goal_width, goal_height, goal_depth)
	shape.shape = box
	shape.position = Vector3(0.0, 0.0, goal_depth * 0.5)
	add_child(shape)


func _build_visuals() -> void:
	var team_color := Color(0.18, 0.64, 1.0) if defending_team == 1 else Color(1.0, 0.42, 0.16)
	_frame_material = StandardMaterial3D.new()
	_frame_material.albedo_color = team_color
	_frame_material.emission_enabled = true
	_frame_material.emission = team_color
	_frame_material.emission_energy_multiplier = 2.4
	_frame_material.metallic = 0.6
	_frame_material.roughness = 0.25
	var frame_specs := [
		[Vector3(-goal_width * 0.5, 0.0, 0.0), Vector3(0.4, goal_height + 0.4, 0.7)],
		[Vector3(goal_width * 0.5, 0.0, 0.0), Vector3(0.4, goal_height + 0.4, 0.7)],
		[Vector3(0.0, goal_height * 0.5, 0.0), Vector3(goal_width + 0.4, 0.4, 0.7)],
		[Vector3(0.0, -goal_height * 0.5, 0.0), Vector3(goal_width + 0.4, 0.4, 0.7)],
	]
	for spec: Array in frame_specs:
		var mesh_node := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = spec[1]
		mesh_node.mesh = mesh
		mesh_node.material_override = _frame_material
		mesh_node.position = spec[0]
		add_child(mesh_node)
	_net_material = ShaderMaterial.new()
	_net_material.shader = load("res://vfx/net.gdshader")
	_net_material.set_shader_parameter("net_color", Color(team_color.r, team_color.g, team_color.b, 0.28))
	_net_material.set_shader_parameter("cells_x", goal_width)
	_net_material.set_shader_parameter("cells_y", goal_height)
	var back := MeshInstance3D.new()
	var back_mesh := PlaneMesh.new()
	back_mesh.size = Vector2(goal_width, goal_height)
	back.mesh = back_mesh
	back.material_override = _net_material
	back.position = Vector3(0.0, 0.0, goal_depth - 0.04)
	add_child(back)
	for side: float in [-1.0, 1.0]:
		var side_mesh := MeshInstance3D.new()
		var plane := PlaneMesh.new()
		plane.size = Vector2(goal_depth, goal_height)
		side_mesh.mesh = plane
		side_mesh.material_override = _net_material
		side_mesh.position = Vector3(side * goal_width * 0.5, 0.0, goal_depth * 0.5)
		side_mesh.rotation_degrees = Vector3(0.0, 90.0, 0.0)
		add_child(side_mesh)
	var glow := OmniLight3D.new()
	glow.light_color = team_color
	glow.light_energy = 2.2
	glow.omni_range = 14.0
	glow.position = Vector3(0.0, 0.0, goal_depth * 0.6)
	add_child(glow)


func _on_body_entered(body: Node) -> void:
	if not enabled or _latched:
		return
	if not (body is Ball):
		return
	_latched = true
	var scoring_team: int = 3 - defending_team
	var ball := body as Ball
	Events.goal_scored.emit(scoring_team, ball.last_hitter_id)
	scored.emit(scoring_team)


func reset_latch() -> void:
	_latched = false


func apply_theme(theme: ArenaTheme) -> void:
	if theme == null or _frame_material == null:
		return
	var team_color := Settings.get_color("a11y/team1_color") if defending_team == 1 and Settings.get_bool("a11y/team_color_override") else Color(0.18, 0.64, 1.0)
	if defending_team == 2:
		team_color = Settings.get_color("a11y/team2_color") if Settings.get_bool("a11y/team_color_override") else Color(1.0, 0.42, 0.16)
	_frame_material.albedo_color = team_color
	_frame_material.emission = team_color
	if _net_material != null:
		_net_material.set_shader_parameter("net_color", Color(team_color.r, team_color.g, team_color.b, 0.28))


func set_enabled(value: bool) -> void:
	enabled = value
	if value:
		_latched = false
