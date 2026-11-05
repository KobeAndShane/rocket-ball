extends Node
## Central signal bus ("signals up, calls down"). Systems never look each other
## up directly for gameplay events; they publish here instead.

# Match flow
signal match_state_changed(state: int)
signal kickoff_started()
signal countdown_changed(seconds_left: int)
signal match_ended(blue_score: int, orange_score: int)
signal goal_scored(scoring_team: int)
signal score_changed(blue_score: int, orange_score: int)
signal timer_changed(seconds_left: int)
signal overtime_started()

# Player / world
signal car_state_changed(car: Node, new_state: int)
signal car_demolished(car: Node, by: Node)
signal boost_changed(player_id: int, amount: float)
signal ball_hit(strength: float)

# UI
signal event_feed(text: String)
signal ui_prompt(text: String, duration: float)
signal gravity_phase_changed(phase_index: int, dir: Vector3)
