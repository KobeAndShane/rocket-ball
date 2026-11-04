class_name Glicko2
extends RefCounted
## Glicko-2 rating maths (Mark Glickman's paper).
##
## Ratings use the familiar 1000-centred display scale. Internally every value
## is converted to the Glicko-2 (mu, phi) space. New players start with a high
## rating deviation so placements settle quickly; established players move less.

const SCALE := 173.7178
const TAU := 0.5
const EPSILON := 0.000001
const MIN_RD := 30.0
const MAX_RD := 350.0
const MIN_RATING := 0.0
const MAX_RATING := 5000.0

var rating: float = 1000.0
var rd: float = 350.0
var volatility: float = 0.06


func _init(start_rating: float = 1000.0, start_rd: float = 350.0, start_volatility: float = 0.06) -> void:
	rating = start_rating
	rd = clampf(start_rd, MIN_RD, MAX_RD)
	volatility = clampf(start_volatility, 0.01, 1.0)


static func from_dict(data: Dictionary) -> Glicko2:
	return Glicko2.new(
		float(data.get("rating", data.get("mmr", 1000.0))),
		float(data.get("rd", 350.0)),
		float(data.get("volatility", 0.06)),
	)


func to_dict() -> Dictionary:
	return {"rating": rating, "rd": rd, "volatility": volatility}


## `score` is 1.0 for a win, 0.5 for a draw, 0.0 for a loss.
func update(opponent_rating: float, opponent_rd: float, score: float) -> Dictionary:
	var mu: float = (rating - 1500.0) / SCALE
	var phi: float = rd / SCALE
	var mu_j: float = (opponent_rating - 1500.0) / SCALE
	var phi_j: float = clampf(opponent_rd, MIN_RD, MAX_RD) / SCALE
	var g: float = 1.0 / sqrt(1.0 + 3.0 * phi_j * phi_j / (PI * PI))
	var expected: float = 1.0 / (1.0 + exp(-g * (mu - mu_j)))
	var clamped_score: float = clampf(score, 0.0, 1.0)
	var v: float = 1.0 / maxf(g * g * expected * (1.0 - expected), 0.000001)
	var delta: float = v * g * (clamped_score - expected)
	var a: float = log(volatility * volatility)
	var A: float = a
	var B: float = 0.0
	if delta * delta > phi * phi + v:
		B = log(delta * delta - phi * phi - v)
	else:
		var k: int = 1
		while _f(a - float(k) * TAU, delta, phi, v, a) < 0.0 and k < 100:
			k += 1
		B = a - float(k) * TAU
	var f_a: float = _f(A, delta, phi, v, a)
	var f_b: float = _f(B, delta, phi, v, a)
	while absf(B - A) > EPSILON:
		var C: float = A + (A - B) * f_a / maxf(f_b - f_a, 0.0000001)
		var f_c: float = _f(C, delta, phi, v, a)
		if f_c * f_b <= 0.0:
			A = B
			f_a = f_b
		else:
			f_a *= 0.5
		B = C
		f_b = f_c
	var new_volatility: float = clampf(exp(A * 0.5), 0.01, 1.0)
	var phi_star: float = sqrt(phi * phi + new_volatility * new_volatility)
	var new_phi: float = 1.0 / sqrt(1.0 / (phi_star * phi_star) + 1.0 / v)
	var new_mu: float = mu + new_phi * new_phi * g * (clamped_score - expected)
	var old_rating: float = rating
	rating = clampf(new_mu * SCALE + 1500.0, MIN_RATING, MAX_RATING)
	rd = clampf(new_phi * SCALE, MIN_RD, MAX_RD)
	volatility = new_volatility
	return {
		"rating": rating,
		"rd": rd,
		"volatility": volatility,
		"delta": rating - old_rating,
	}


func _f(x: float, delta: float, phi: float, v: float, a: float) -> float:
	var ex: float = exp(x)
	var numerator: float = ex * (delta * delta - phi * phi - v - ex)
	var denominator: float = 2.0 * pow(phi * phi + v + ex, 2.0)
	return numerator / maxf(denominator, 0.0000001) - (x - a) / (TAU * TAU)
