class_name HudIndicators
extends Control
## Off-screen ball and teammate arrows. This is the only HUD piece that redraws
## per frame; it does no allocations beyond the draw primitives.

var camera: Camera3D
var ball: Ball
var local_car: Car
var teammates: Array[Car] = []
var opponents: Array[Car] = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _process(_delta: float) -> void:
	if visible:
		queue_redraw()


func _draw() -> void:
	if camera == null or not is_instance_valid(camera) or ball == null:
		return
	var vp: Vector2 = get_viewport_rect().size
	var margin: float = 54.0
	_draw_target(ball.global_position, Color(1.0, 0.9, 0.35), vp, margin, 9.0, true)
	for car: Car in teammates:
		if car == local_car or car.state == Car.State.DEMOLISHED:
			continue
		_draw_target(car.global_position, car.team_color(), vp, margin, 6.0, false)


func _draw_target(world_pos: Vector3, color: Color, vp: Vector2, margin: float, radius: float, is_ball: bool) -> void:
	var behind: bool = camera.is_position_behind(world_pos)
	var screen: Vector2 = camera.unproject_position(world_pos)
	var on_screen: bool = not behind and screen.x > margin and screen.x < vp.x - margin and screen.y > margin and screen.y < vp.y - margin
	if on_screen:
		if is_ball:
			draw_circle(screen, radius, Color(color.r, color.g, color.b, 0.55))
			draw_arc(screen, radius + 3.0, 0.0, TAU, 24, Color(color.r, color.g, color.b, 0.9), 2.0)
		else:
			draw_circle(screen, radius, Color(color.r, color.g, color.b, 0.7))
		return
	var center: Vector2 = vp * 0.5
	var dir: Vector2 = screen - center
	if behind:
		dir = -dir
	if dir.length_squared() < 0.001:
		dir = Vector2.DOWN
	dir = dir.normalized()
	var edge_point: Vector2 = center
	var t_x: float = 1e20
	var t_y: float = 1e20
	if absf(dir.x) > 0.001:
		t_x = ((vp.x - margin) - center.x) / dir.x if dir.x > 0.0 else (margin - center.x) / dir.x
	if absf(dir.y) > 0.001:
		t_y = ((vp.y - margin) - center.y) / dir.y if dir.y > 0.0 else (margin - center.y) / dir.y
	var t: float = minf(t_x, t_y)
	edge_point = center + dir * t
	var perp := Vector2(-dir.y, dir.x)
	var tip: Vector2 = edge_point + dir * 14.0
	var p1: Vector2 = edge_point + perp * 9.0
	var p2: Vector2 = edge_point - perp * 9.0
	draw_colored_polygon(PackedVector2Array([tip, p1, p2]), Color(color.r, color.g, color.b, 0.9))
	if is_ball:
		draw_circle(edge_point, 5.0, color)
