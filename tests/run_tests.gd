## Headless simulation tests. Run from the project root:
##   godot --headless -s tests/run_tests.gd
## Exits with code 0 when every test passes, 1 otherwise.
extends SceneTree

const PongSim := preload("res://scripts/sim.gd")
const CpuAI := preload("res://scripts/cpu_ai.gd")
const DT := 1.0 / 120.0

var _failures := 0
var _current := ""


func _init() -> void:
	for t in [
		"test_determinism",
		"test_paddle_clamp",
		"test_no_tunneling_at_max_speed",
		"test_edge_hit_angles",
		"test_speed_cap",
		"test_ball_stays_in_bounds",
		"test_scoring_and_serve",
		"test_match_over",
		"test_difficulty_ordering",
		"test_matches_terminate",
	]:
		_current = t
		call(t)
	print("\n%s" % ("ALL TESTS PASSED" if _failures == 0 else "%d FAILURE(S)" % _failures))
	quit(0 if _failures == 0 else 1)


func check(cond: bool, msg: String) -> void:
	if not cond:
		_failures += 1
		printerr("FAIL [%s] %s" % [_current, msg])


func ok() -> void:
	print("ok   %s" % _current)


## Plays a whole CPU-vs-CPU match. Returns {winner, score, time, events}.
func play_match(seed_value: int, diff_left: int, diff_right: int, win := 11, max_time := 1800.0) -> Dictionary:
	var sim := PongSim.new(seed_value, win)
	var ais := [CpuAI.new(PongSim.LEFT, diff_left, seed_value + 1), CpuAI.new(PongSim.RIGHT, diff_right, seed_value + 2)]
	var counts := {}
	while sim.winner < 0 and sim.time < max_time:
		var inputs := [ais[0].get_input(sim, DT), ais[1].get_input(sim, DT)]
		for e in sim.step(inputs, DT):
			counts[e.type] = counts.get(e.type, 0) + 1
	return {"winner": sim.winner, "score": sim.score, "time": sim.time, "events": counts}


func test_determinism() -> void:
	var a := play_match(42, CpuAI.Difficulty.NORMAL, CpuAI.Difficulty.HARD)
	var b := play_match(42, CpuAI.Difficulty.NORMAL, CpuAI.Difficulty.HARD)
	check(a.winner >= 0, "match did not finish")
	check(a.score == b.score and is_equal_approx(a.time, b.time) and a.events == b.events,
		"same seed produced different matches: %s vs %s" % [a, b])
	ok()


func test_paddle_clamp() -> void:
	var sim := PongSim.new(1)
	for i in 600:
		sim.step([-1.0, 1.0], DT)
	check(is_equal_approx(sim.paddle_y[0], PongSim.PADDLE_H / 2.0), "left paddle not clamped at top: %f" % sim.paddle_y[0])
	check(is_equal_approx(sim.paddle_y[1], PongSim.HEIGHT - PongSim.PADDLE_H / 2.0), "right paddle not clamped at bottom: %f" % sim.paddle_y[1])
	ok()


func test_no_tunneling_at_max_speed() -> void:
	# Fire the ball at max speed at each paddle with large frame times too.
	for side in [PongSim.LEFT, PongSim.RIGHT]:
		for dt in [DT, 1.0 / 30.0, 0.1]:
			var sim := PongSim.new(1)
			sim.ball_pos = Vector2(PongSim.WIDTH / 2.0, PongSim.HEIGHT / 2.0)
			var dir := -1.0 if side == PongSim.LEFT else 1.0
			sim.ball_vel = Vector2(dir * PongSim.BALL_MAX_SPEED, 0.0)
			var hit := false
			for i in 200:
				for e in sim.step([0.0, 0.0], dt):
					if e.type == "paddle_hit" and e.side == side:
						hit = true
					if e.type == "score":
						check(false, "ball tunneled through side %d at dt=%f" % [side, dt])
				if hit:
					break
			check(hit, "no hit registered for side %d at dt=%f" % [side, dt])
			check(signf(sim.ball_vel.x) == -dir, "ball not reflected for side %d" % side)
	ok()


func test_edge_hit_angles() -> void:
	# Hitting the paddle edge deflects steeply; the center deflects flat.
	var results := {}
	for off in [0.0, 0.95]:
		var sim := PongSim.new(1)
		var reach := (PongSim.PADDLE_H + PongSim.BALL_SIZE) / 2.0
		sim.ball_pos = Vector2(400.0, sim.paddle_y[0] + off * reach)
		sim.ball_vel = Vector2(-1000.0, 0.0)
		for i in 60:
			sim.step([0.0, 0.0], DT)
			if sim.ball_vel.x > 0.0:
				break
		results[off] = absf(sim.ball_vel.angle())
	check(results[0.0] < 0.01, "center hit not flat: %f" % results[0.0])
	check(results[0.95] > deg_to_rad(45.0), "edge hit not steep: %f" % rad_to_deg(results[0.95]))
	check(results[0.95] <= PongSim.MAX_BOUNCE_ANGLE + 0.001, "edge hit exceeds max angle")
	ok()


func test_speed_cap() -> void:
	var sim := PongSim.new(3)
	sim.ball_vel = Vector2(-PongSim.BALL_START_SPEED, 0.0)
	var max_seen := 0.0
	# Two perfect walls of paddles: keep both paddles tracking the ball.
	for i in 120 * 60:
		var inputs := [
			clampf((sim.ball_pos.y - sim.paddle_y[0]) / 20.0, -1, 1),
			clampf((sim.ball_pos.y - sim.paddle_y[1]) / 20.0, -1, 1)]
		sim.step(inputs, DT)
		max_seen = maxf(max_seen, sim.ball_speed())
	check(max_seen <= PongSim.BALL_MAX_SPEED + 0.01, "speed exceeded cap: %f" % max_seen)
	check(max_seen >= PongSim.BALL_MAX_SPEED - 0.01, "speed never reached cap: %f" % max_seen)
	ok()


func test_ball_stays_in_bounds() -> void:
	var sim := PongSim.new(7, 1000)
	var ais := [CpuAI.new(0, CpuAI.Difficulty.EASY, 8), CpuAI.new(1, CpuAI.Difficulty.EASY, 9)]
	var half := PongSim.BALL_SIZE / 2.0
	for i in 120 * 300:
		sim.step([ais[0].get_input(sim, DT), ais[1].get_input(sim, DT)], DT)
		if sim.ball_pos.y < half - 0.001 or sim.ball_pos.y > PongSim.HEIGHT - half + 0.001:
			check(false, "ball out of vertical bounds: %s" % sim.ball_pos)
			break
	ok()


func test_scoring_and_serve() -> void:
	var sim := PongSim.new(5)
	sim.serve_timer = 0.0
	sim.serve_to = PongSim.RIGHT
	sim.step([0.0, 0.0], DT) # serves
	check(sim.ball_vel.x > 0.0, "serve went the wrong way")
	sim.paddle_y[1] = PongSim.PADDLE_H / 2.0 # move right paddle out of the way
	sim.ball_vel = Vector2(1500.0, 0.0)
	sim.ball_pos.y = PongSim.HEIGHT - 50.0
	var scored := -1
	for i in 240:
		for e in sim.step([0.0, -1.0], DT):
			if e.type == "score":
				scored = e.side
		if scored >= 0:
			break
	check(scored == PongSim.LEFT, "left should score, got %d" % scored)
	check(sim.score[0] == 1 and sim.score[1] == 0, "bad score %s" % [sim.score])
	check(sim.is_serving(), "ball should wait for serve")
	check(sim.serve_to == PongSim.RIGHT, "should serve toward the conceding player")
	ok()


func test_match_over() -> void:
	var r := play_match(11, CpuAI.Difficulty.HARD, CpuAI.Difficulty.EASY, 5)
	check(r.winner >= 0, "match never ended")
	check(r.score[r.winner] == 5, "winner score should equal points to win: %s" % [r.score])
	check(r.events.get("match_over", 0) == 1, "expected exactly one match_over event")
	ok()


func test_difficulty_ordering() -> void:
	var pairs := [[CpuAI.Difficulty.HARD, CpuAI.Difficulty.EASY], [CpuAI.Difficulty.HARD, CpuAI.Difficulty.NORMAL], [CpuAI.Difficulty.NORMAL, CpuAI.Difficulty.EASY]]
	for p in pairs:
		var wins := 0
		var n := 20
		for s in n:
			# Alternate sides so side bias doesn't skew results.
			var strong_left := s % 2 == 0
			var r := play_match(100 + s, p[0] if strong_left else p[1], p[1] if strong_left else p[0])
			if r.winner == (PongSim.LEFT if strong_left else PongSim.RIGHT):
				wins += 1
		print("     difficulty %d beat %d in %d/%d matches" % [p[0], p[1], wins, n])
		check(wins > n * 0.6, "difficulty %d should clearly beat %d (won %d/%d)" % [p[0], p[1], wins, n])
	ok()


func test_matches_terminate() -> void:
	# Even two hard CPUs must finish a match in reasonable time (no endless rallies).
	var longest := 0.0
	for s in 10:
		var r := play_match(500 + s, CpuAI.Difficulty.HARD, CpuAI.Difficulty.HARD)
		check(r.winner >= 0, "hard vs hard did not finish (seed %d)" % (500 + s))
		longest = maxf(longest, r.time)
	print("     longest hard-vs-hard match: %.0f s" % longest)
	check(longest < 900.0, "hard vs hard match too long: %f s" % longest)
	ok()
