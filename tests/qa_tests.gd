## QA tests: soak invariants, frame-time robustness, corner hits, settings
## corruption and pause/menu signal flow. Run from the project root:
##   godot --headless --fixed-fps 120 -s tests/qa_tests.gd
## Set QA_SOAK_MATCHES (default 200) for a longer nightly soak, e.g. 1000.
## Exits with code 0 when every test passes, 1 otherwise.
extends SceneTree

const PongSim := preload("res://scripts/sim.gd")
const CpuAI := preload("res://scripts/cpu_ai.gd")
const DT := 1.0 / 120.0
const STALL_LIMIT := 30.0 # seconds without a paddle hit, serve or score

var _failures := 0
var _current := ""
var _failures_at_start := 0
var game: Node # the Game autoload (not resolvable at compile time under -s)


func _initialize() -> void:
	_run()


func _run() -> void:
	game = root.get_node("Game")
	for t in [
		"test_soak_invariants",
		"test_variable_frame_times",
		"test_corner_hits",
		"test_no_events_after_match_over",
		"test_inputs_out_of_range",
		"test_rally_lengths",
		"test_corrupted_settings",
	]:
		_current = t
		_failures_at_start = _failures
		call(t)
	_current = "test_pause_menu_signals"
	_failures_at_start = _failures
	await test_pause_menu_signals()
	print("\n%s" % ("ALL QA TESTS PASSED" if _failures == 0 else "%d FAILURE(S)" % _failures))
	quit(0 if _failures == 0 else 1)


func check(cond: bool, msg: String) -> bool:
	if not cond:
		_failures += 1
		printerr("FAIL [%s] %s" % [_current, msg])
	return cond


func ok() -> void:
	print("%s %s" % ["ok  " if _failures == _failures_at_start else "FAIL", _current])


## Checks every invariant that must hold after any step. Returns "" or a reason.
func invariant_error(sim: PongSim) -> String:
	var half := PongSim.BALL_SIZE / 2.0
	var eps := 0.001
	if not (is_finite(sim.ball_pos.x) and is_finite(sim.ball_pos.y) and is_finite(sim.ball_vel.x) and is_finite(sim.ball_vel.y)):
		return "non-finite ball state pos=%s vel=%s" % [sim.ball_pos, sim.ball_vel]
	if sim.ball_pos.y < half - eps or sim.ball_pos.y > PongSim.HEIGHT - half + eps:
		return "ball outside vertical bounds: %s" % sim.ball_pos
	if sim.ball_pos.x < -half - eps or sim.ball_pos.x > PongSim.WIDTH + half + eps:
		return "ball outside horizontal bounds without scoring: %s" % sim.ball_pos
	if sim.ball_speed() > PongSim.BALL_MAX_SPEED + 0.01:
		return "ball over speed cap: %f" % sim.ball_speed()
	for side in [PongSim.LEFT, PongSim.RIGHT]:
		var y: float = sim.paddle_y[side]
		if y < PongSim.PADDLE_H / 2.0 - eps or y > PongSim.HEIGHT - PongSim.PADDLE_H / 2.0 + eps:
			return "paddle %d out of bounds: %f" % [side, y]
		if sim.score[side] > sim.points_to_win:
			return "score above points to win: %s" % [sim.score]
	if sim.winner < 0 and sim.ball_vel != Vector2.ZERO and absf(sim.ball_vel.x) < 1.0:
		return "ball has no horizontal speed (can't reach a paddle): %s" % sim.ball_vel
	return ""


## Plays one match with full invariant checks. Returns stats or {"error": ...}.
func soak_match(seed_value: int, diff_left: int, diff_right: int, win: int, dt_fn := Callable()) -> Dictionary:
	var sim := PongSim.new(seed_value, win)
	var ais := [CpuAI.new(PongSim.LEFT, diff_left, seed_value * 3 + 1), CpuAI.new(PongSim.RIGHT, diff_right, seed_value * 3 + 2)]
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var last_activity := 0.0
	var rally_start := 0.0
	var longest_rally := 0.0
	var longest_rally_hits := 0
	var hits := 0
	while sim.winner < 0:
		var dt: float = dt_fn.call(rng) if dt_fn.is_valid() else DT
		var inputs := [ais[0].get_input(sim, dt), ais[1].get_input(sim, dt)]
		for e in sim.step(inputs, dt):
			match e.type:
				"paddle_hit":
					last_activity = sim.time
					hits += 1
				"serve":
					last_activity = sim.time
					rally_start = sim.time
					hits = 0
				"score":
					last_activity = sim.time
					if sim.time - rally_start > longest_rally:
						longest_rally = sim.time - rally_start
						longest_rally_hits = hits
		var err := invariant_error(sim)
		if err != "":
			return {"error": "%s at t=%.3f" % [err, sim.time]}
		if sim.time - last_activity > STALL_LIMIT:
			return {"error": "ball stalled for %.0f s at t=%.1f pos=%s vel=%s" % [STALL_LIMIT, sim.time, sim.ball_pos, sim.ball_vel]}
		if sim.time > 3600.0:
			return {"error": "match lasted over an hour"}
	return {"time": sim.time, "score": sim.score, "longest_rally": longest_rally, "longest_rally_hits": longest_rally_hits}


func test_soak_invariants() -> void:
	var n := int(OS.get_environment("QA_SOAK_MATCHES")) if OS.get_environment("QA_SOAK_MATCHES") != "" else 200
	var longest := 0.0
	var t0 := Time.get_ticks_msec()
	for i in n:
		var seed_value := 10000 + i
		var r := soak_match(seed_value, i % 3, (i / 3) % 3, Game_win_choice(i))
		if not check(not r.has("error"), "seed %d (%d vs %d): %s" % [seed_value, i % 3, (i / 3) % 3, r.get("error")]):
			continue
		longest = maxf(longest, r.time)
	print("     %d matches, longest %.0f s sim time, %.1f s wall" % [n, longest, (Time.get_ticks_msec() - t0) / 1000.0])
	ok()


func Game_win_choice(i: int) -> int:
	return [5, 7, 11, 15, 21][i % 5]


func test_variable_frame_times() -> void:
	# The game steps at a fixed 120 Hz, but the sim must stay sane if it is ever
	# driven with jittery or huge frame times (hitches, debugger breaks).
	var jitter := func(rng: RandomNumberGenerator) -> float:
		var r := rng.randf()
		if r < 0.01:
			return 0.25 # hitch
		return rng.randf_range(1.0 / 240.0, 1.0 / 30.0)
	for i in 30:
		var r := soak_match(20000 + i, CpuAI.Difficulty.HARD, CpuAI.Difficulty.NORMAL, 7, jitter)
		check(not r.has("error"), "seed %d: %s" % [20000 + i, r.get("error")])
	ok()


func test_corner_hits() -> void:
	# Fire the ball at every point along and just past each paddle's edges, from
	# several angles. Each shot must end in exactly one clean return or one score,
	# never a double hit, a stuck ball or a ball returned from behind the paddle.
	var reach_y := (PongSim.PADDLE_H + PongSim.BALL_SIZE) / 2.0
	var shots := 0
	for side in [PongSim.LEFT, PongSim.RIGHT]:
		var dir := -1.0 if side == PongSim.LEFT else 1.0
		for paddle_at in [PongSim.PADDLE_H / 2.0, PongSim.HEIGHT / 2.0, PongSim.HEIGHT - PongSim.PADDLE_H / 2.0]:
			for k in range(-60, 61):
				var off: float = k / 50.0 # -1.2 .. 1.2 of reach
				for ang_deg in [-50.0, -20.0, 0.0, 20.0, 50.0]:
					for speed in [PongSim.BALL_START_SPEED, PongSim.BALL_MAX_SPEED]:
						shots += 1
						var sim := PongSim.new(1)
						sim.paddle_y[side] = paddle_at
						var ang: float = deg_to_rad(ang_deg)
						var vel: Vector2 = Vector2(cos(ang) * dir, sin(ang)) * speed
						# Start 0.25 s away from the impact point, back along the path.
						var target: Vector2 = Vector2(PongSim.paddle_x(side) - dir * (PongSim.PADDLE_W + PongSim.BALL_SIZE) / 2.0, paddle_at + off * reach_y)
						sim.ball_pos = target - vel * 0.25
						sim.ball_pos.y = clampf(sim.ball_pos.y, PongSim.BALL_SIZE, PongSim.HEIGHT - PongSim.BALL_SIZE)
						sim.ball_vel = vel
						var hits := 0
						var scored := false
						for f in 240:
							for e in sim.step([0.0, 0.0], DT):
								if e.type == "paddle_hit":
									hits += 1
									if not check(signf(sim.ball_vel.x) == -dir, "return goes the wrong way"):
										return
								if e.type == "score":
									scored = true
							var err := invariant_error(sim)
							if not check(err == "", "side %d off %.2f ang %d: %s" % [side, off, ang_deg, err]):
								return
							if scored or (hits > 0 and absf(sim.ball_pos.x - PongSim.WIDTH / 2.0) < 200.0):
								break
						if not check(hits <= 1, "double hit: side %d paddle %.0f off %.2f ang %d speed %.0f" % [side, paddle_at, off, ang_deg, speed]):
							return
						if not check(hits == 1 or scored, "ball neither returned nor scored: side %d off %.2f ang %d" % [side, off, ang_deg]):
							return
	print("     %d shots" % shots)
	ok()


func test_no_events_after_match_over() -> void:
	var sim := PongSim.new(9, 1)
	var ais := [CpuAI.new(0, CpuAI.Difficulty.EASY, 1), CpuAI.new(1, CpuAI.Difficulty.HARD, 2)]
	while sim.winner < 0:
		sim.step([ais[0].get_input(sim, DT), ais[1].get_input(sim, DT)], DT)
	var score := sim.score.duplicate()
	var t := sim.time
	for i in 600:
		check(sim.step([1.0, -1.0], DT).is_empty(), "events emitted after match over")
	check(sim.score == score and sim.time == t, "state changed after match over")
	ok()


func test_inputs_out_of_range() -> void:
	# Stacked inputs (keyboard + stick) can exceed 1; NaN must never poison state.
	var sim := PongSim.new(4)
	var y0: float = sim.paddle_y[0]
	sim.step([5.0, -5.0], DT)
	check(absf(sim.paddle_y[0] - y0 - PongSim.PADDLE_SPEED * DT) < 0.01, "input above 1 not clamped")
	sim.step([NAN, 0.0], DT)
	check(is_finite(sim.paddle_y[0]), "NaN input corrupted paddle position: %f" % sim.paddle_y[0])
	ok()


func test_rally_lengths() -> void:
	# Not a pass/fail gate on fun, but flags rallies long enough to feel endless.
	var worst := 0.0
	var worst_hits := 0
	for i in 20:
		var r := soak_match(30000 + i, CpuAI.Difficulty.HARD, CpuAI.Difficulty.HARD, 11)
		if r.has("error"):
			check(false, r.error)
			continue
		if r.longest_rally > worst:
			worst = r.longest_rally
			worst_hits = r.longest_rally_hits
	print("     longest hard-vs-hard rally: %.0f s, %d hits" % [worst, worst_hits])
	check(worst < 180.0, "a single rally lasted %.0f s" % worst)
	ok()


func test_corrupted_settings() -> void:
	var path: String = game.SETTINGS_PATH
	var backup := FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else ""
	var defaults := {"difficulty": 1, "win_score": 11, "master_volume": 1.0, "music_volume": 0.6, "sfx_volume": 1.0, "fullscreen": true}
	var cases := {
		"garbage bytes": "\u00ff\u00fe not a config [[[ = ]",
		"wrong types": "[game]\ndifficulty=\"hard\"\nwin_score=\"eleven\"\n[audio]\nmaster=\"loud\"\n[display]\nfullscreen=\"yes\"\n",
		"out of range": "[game]\ndifficulty=99\nwin_score=-3\n[audio]\nmaster=7.0\nmusic=-1.0\n",
		"empty": "",
		"one bad value": "[game]\ndifficulty=\"hard\"\n[audio]\nmusic=0.3\n",
	}
	for name in cases:
		for k in defaults:
			game.set(k, defaults[k])
		var f := FileAccess.open(path, FileAccess.WRITE)
		f.store_string(cases[name])
		f.close()
		game.load_settings()
		check(game.difficulty is int and game.difficulty >= 0 and game.difficulty <= 2, "%s: bad difficulty %s" % [name, game.difficulty])
		check(game.win_score in game.WIN_SCORE_CHOICES, "%s: bad win_score %s" % [name, game.win_score])
		check(game.master_volume is float and game.master_volume >= 0.0 and game.master_volume <= 1.0, "%s: bad master volume %s" % [name, game.master_volume])
		check(game.music_volume is float and game.music_volume >= 0.0 and game.music_volume <= 1.0, "%s: bad music volume %s" % [name, game.music_volume])
		check(game.fullscreen is bool, "%s: bad fullscreen %s" % [name, game.fullscreen])
		if name == "one bad value":
			# One bad entry must not stop the rest of the file from loading.
			check(is_equal_approx(game.music_volume, 0.3), "one bad value: valid music volume was not loaded (got %s)" % game.music_volume)
	# Restore whatever was there before.
	if backup != "":
		var f := FileAccess.open(path, FileAccess.WRITE)
		f.store_string(backup)
		f.close()
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	for k in defaults:
		game.set(k, defaults[k])
	ok()


func test_pause_menu_signals() -> void:
	# Leaving the pause menu by any route must tell listeners the game is unpaused,
	# or audio/graphics that react to pause (muffled music, dimmed field) get stuck.
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await _frames(3)
	var states: Array[bool] = []
	var record := func(p: bool): states.append(p)
	game.paused_changed.connect(record)

	for route in ["Restart", "Main Menu"]:
		main.start_match(game.Mode.VS_CPU)
		await _frames(2)
		states.clear()
		main.show_pause()
		await _frames(2)
		if route == "Restart":
			main.start_match(game.mode)
		else:
			main.show_title()
		await _frames(2)
		check(not paused, "%s: tree still paused" % route)
		check(not states.is_empty() and states[-1] == false, "%s from pause menu never emitted paused_changed(false); got %s" % [route, states])

	# Focus loss must pause only during play, never on menus.
	main.show_title()
	await _frames(2)
	main._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	await _frames(2)
	check(main.screen == main.Screen.TITLE, "focus loss on title changed screen")

	game.paused_changed.disconnect(record)
	main.queue_free()
	await _frames(2)
	ok()


func _frames(n: int) -> void:
	for i in n:
		await process_frame
