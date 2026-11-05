extends Node3D
## Bootstraps the playable scene: arena, ball, car, chase camera, HUD and the
## match controller. Everything is assembled at runtime from .tscn scenes.

const ARENA_SCENE := preload("res://arena/Arena.tscn")
const BALL_SCENE := preload("res://ball/Ball.tscn")
const CAR_SCENE := preload("res://car/Car.tscn")
const CAMERA_SCENE := preload("res://camera/ChaseCamera.tscn")
const HUD_SCENE := preload("res://ui/HUD.tscn")
const RULES_PATH := "res://match/MatchRules.tres"

var arena: Arena
var ball: Ball
var car: Car
var chase_camera: ChaseCamera
var hud: HUD
var match_controller: MatchController


func _ready() -> void:
	var rules := load(RULES_PATH) as MatchRules
	GravityManager.configure(
		rules.phases,
		rules.shift_interval,
		rules.shift_warning,
		rules.shift_transition,
		rules.gravity_strength,
		rules.random_shifts,
		rules.seed_value,
		rules.boost_refill_on_shift
	)

	arena = ARENA_SCENE.instantiate() as Arena
	add_child(arena)

	ball = BALL_SCENE.instantiate() as Ball
	add_child(ball)

	car = CAR_SCENE.instantiate() as Car
	car.team = 0
	car.player_id = 1
	add_child(car)

	chase_camera = CAMERA_SCENE.instantiate() as ChaseCamera
	add_child(chase_camera)
	chase_camera.setup(car, ball)

	hud = HUD_SCENE.instantiate() as HUD
	add_child(hud)
	hud.bind(car, ball)

	match_controller = MatchController.new()
	match_controller.name = "MatchController"
	add_child(match_controller)
	var cars: Array[Car] = [car]
	match_controller.setup(arena, ball, cars, rules)
	match_controller.start_match()
