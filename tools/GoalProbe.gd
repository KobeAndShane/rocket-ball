extends Node

const MATCH := preload("res://match/Match.tscn")


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var rules := MatchRules.new()
	rules.team_size = 0
	rules.fill_with_bots = false
	rules.kickoff_countdown = 0.01
	rules.goal_pause = 0.1
	rules.match_duration = 10.0
	rules.replay_enabled = false
	rules.overtime_enabled = false
	var m := MATCH.instantiate() as MatchController
	m.rules = rules
	m.auto_start = false
	m.headless_mode = true
	m.spawn_camera = false
	m.spawn_hud = false
	m.all_bots = true
	add_child(m)
	await get_tree().process_frame
	m.start_match()
	await get_tree().create_timer(0.2).timeout
	var space := m.get_world_3d().direct_space_state
	var q := PhysicsShapeQueryParameters3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 2.0
	q.shape = sphere
	q.transform = Transform3D(Basis.IDENTITY, Vector3(0.0, -12.0, 36.0))
	q.collision_mask = 0xFFFFFFFF
	var hits := space.intersect_shape(q, 16)
	for h: Dictionary in hits:
		var node := h.get("collider") as Node
		print("PROBE HIT at 36: ", node.get_path() if node != null else "?", " type=", node.get_class() if node != null else "?")
	var geom := m.arena.get_node_or_null("Geometry")
	if geom != null:
		for child: Node in geom.get_children():
			var cs := child as CollisionShape3D
			if cs == null:
				continue
			print("PROBE SHAPE ", cs.shape.get_class(), " pos=", cs.global_position, " size=", _shape_desc(cs.shape))
	var ray := PhysicsRayQueryParameters3D.create(Vector3(0.0, -12.0, 30.0), Vector3(0.0, -12.0, 50.0))
	ray.collision_mask = 0xFFFFFFFF
	var rhit := space.intersect_ray(ray)
	if not rhit.is_empty():
		print("PROBE RAY: ", rhit.get("collider"), " pos=", rhit.get("position"))
	m.ball.freeze = false
	m.ball.global_position = Vector3(0.0, -12.0, 36.0)
	m.ball.linear_velocity = Vector3(0.0, 0.0, 25.0)
	var scored := 0
	Events.goal_scored.connect(func(_t: int, _s: int) -> void: scored += 1)
	for i in 180:
		await get_tree().physics_frame
		if i % 10 == 0:
			var bodies := m.ball.get_colliding_bodies()
			var names: Array[String] = []
			for b: Node in bodies:
				names.append(str(b.get_path()))
			print("PROBE i=%d ball=%s vel=%s v=%.1f freeze=%s grav=%s up=%s state=%d score=%d-%d goals=%d contacts=%s" % [
				i, str(m.ball.global_position), str(m.ball.linear_velocity),
				m.ball.linear_velocity.length(), str(m.ball.freeze),
				str(GravityManager.gravity_dir), str(GravityManager.up),
				int(m.state), m.score1, m.score2, scored, str(names),
			])
	print("PROBE END ball=%s score=%d-%d goals=%d" % [str(m.ball.global_position), m.score1, m.score2, scored])
	get_tree().quit()


func _shape_desc(shape: Shape3D) -> String:
	if shape is BoxShape3D:
		return str((shape as BoxShape3D).size)
	if shape is CylinderShape3D:
		var c := shape as CylinderShape3D
		return "r=%.1f h=%.1f" % [c.radius, c.height]
	if shape is SphereShape3D:
		return "r=%.1f" % (shape as SphereShape3D).radius
	return "?"
