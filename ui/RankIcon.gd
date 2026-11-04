class_name RankIcon
extends Control
## Small procedural rank badge. No textures or external assets required, so the
## same icon scales from the menu to the post-game scoreboard.

const TIER_COLORS: Array[Color] = [
	Color(0.72, 0.45, 0.25), # Bronze
	Color(0.75, 0.80, 0.85), # Silver
	Color(1.00, 0.82, 0.25), # Gold
	Color(0.35, 0.90, 0.85), # Platinum
	Color(0.40, 0.70, 1.00), # Diamond
	Color(0.75, 0.40, 1.00), # Champion
	Color(1.00, 0.50, 0.25), # Grand Champion
]

@export var tier: int = 0
@export var division: int = 1
@export var icon_size: float = 46.0


func _ready() -> void:
	custom_minimum_size = Vector2(icon_size, icon_size)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	queue_redraw()


func setup(tier_index: int, division_index: int, pixels: float = 46.0) -> void:
	tier = clampi(tier_index, 0, TIER_COLORS.size() - 1)
	division = clampi(division_index, 1, 3)
	icon_size = maxf(pixels, 16.0)
	custom_minimum_size = Vector2(icon_size, icon_size)
	queue_redraw()


static func color_for_tier(tier_index: int) -> Color:
	return TIER_COLORS[clampi(tier_index, 0, TIER_COLORS.size() - 1)]


func _draw() -> void:
	var side: float = minf(size.x, size.y)
	if side <= 2.0:
		return
	var origin := (size - Vector2(side, side)) * 0.5
	var color := color_for_tier(tier)
	var outer := _shield(origin, side, 0.98)
	var inner := _shield(origin, side, 0.78)
	draw_colored_polygon(outer, Color(0.02, 0.035, 0.07, 0.92))
	var closed: PackedVector2Array = outer.duplicate()
	closed.append(outer[0])
	draw_polyline(closed, color.darkened(0.15), maxf(2.0, side * 0.055), true)
	draw_colored_polygon(inner, color.darkened(0.42))
	var glow := _shield(origin, side, 0.62)
	draw_colored_polygon(glow, color)
	# Division chevrons: one to three bars under the tier glyph.
	var bar_w: float = side * 0.09
	var gap: float = side * 0.055
	var total: float = division * bar_w + (division - 1) * gap
	var start_x: float = origin.x + (side - total) * 0.5
	var y: float = origin.y + side * 0.69
	for i in division:
		var rect := Rect2(Vector2(start_x + i * (bar_w + gap), y), Vector2(bar_w, side * 0.045))
		draw_rect(rect, Color(0.03, 0.05, 0.09, 0.9))
	# Grand Champion gets a crown notch.
	if tier == TIER_COLORS.size() - 1:
		var crown := PackedVector2Array([
			origin + Vector2(side * 0.34, side * 0.30),
			origin + Vector2(side * 0.42, side * 0.20),
			origin + Vector2(side * 0.50, side * 0.30),
			origin + Vector2(side * 0.58, side * 0.20),
			origin + Vector2(side * 0.66, side * 0.30),
		])
		draw_polyline(crown, Color(1.0, 0.95, 0.75), maxf(1.5, side * 0.035), true)


func _shield(origin: Vector2, side: float, scale_value: float) -> PackedVector2Array:
	var points := PackedVector2Array([
		Vector2(0.50, 0.06),
		Vector2(0.86, 0.20),
		Vector2(0.86, 0.58),
		Vector2(0.50, 0.94),
		Vector2(0.14, 0.58),
		Vector2(0.14, 0.20),
	])
	var out := PackedVector2Array()
	for point: Vector2 in points:
		out.append(origin + (point - Vector2(0.5, 0.5)) * side * scale_value + Vector2(side, side) * 0.5)
	return out
