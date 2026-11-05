class_name Goal
extends Area3D
## Goal trigger. Fires once per ball entry; reset at kickoff. Teams:
## team 0 = blue (defends -X), team 1 = orange (defends +X).

@export var team: int = 0
@export var goal_size: Vector2 = Vector2(10.0, 6.0)
@export var depth: float = 2.6

var _scored: bool = false


func setup(p_team: int, panel_color: Color) -> void:
	team = p_team
	collision_layer = 16
	collision_mask = 4
	monitoring = true
	monitorable = true

	var shape := BoxShape3D.new()
	shape.size = Vector3(depth, goal_size.y, goal_size.x)
	var collider := CollisionShape3D.new()
	collider.name = "GoalTrigger"
	collider.shape = shape
	add_child(collider)

	var panel := MeshInstance3D.new()
	panel.name = "GoalPanel"
	var box := BoxMesh.new()
	box.size = Vector3(0.2, goal_size.y, goal_size.x)
	panel.mesh = box
	panel.position = Vector3(-depth * 0.5 + 0.15, 0.0, 0.0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = panel_color
	mat.emission_enabled = true
	mat.emission = panel_color
	mat.emission_energy_multiplier = 1.4
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color.a = 0.55
	panel.material_override = mat
	add_child(panel)

	body_entered.connect(_on_body_entered)
	Events.kickoff_started.connect(reset)


func _on_body_entered(body: Node3D) -> void:
	if _scored:
		return
	if body is Ball:
		_scored = true
		Events.goal_scored.emit(1 - team)


func reset() -> void:
	_scored = false
