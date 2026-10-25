## Headless walk through the real game flow: title, options, 1P match to the
## game over screen, pause/resume via the pause action, rematch, main menu.
##   godot --headless --fixed-fps 120 -s tests/ui_smoke.gd
extends SceneTree

var main: Node
var game: Node # the Game autoload (not resolvable at compile time under -s)
var _failures := 0


func _initialize() -> void:
	_run()


func _run() -> void:
	game = root.get_node("Game")
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await _frames(5)
	check(main.screen == main.Screen.TITLE, "starts on title")
	check(game.mode == game.Mode.DEMO and main.view.running, "demo plays behind title")

	main.show_options()
	await _frames(2)
	check(main.screen == main.Screen.OPTIONS, "options opens")
	_press_action("ui_cancel")
	await _frames(2)
	check(main.screen == main.Screen.TITLE, "ui_cancel leaves options")

	game.win_score = 1
	main.start_match(game.Mode.VS_CPU)
	await _frames(2)
	check(main.screen == main.Screen.PLAYING and game.mode == game.Mode.VS_CPU, "1P match starts")
	check(main.view.ais[0] == null and main.view.ais[1] != null, "left is human, right is CPU")

	_press_action("pause")
	await _frames(2)
	check(main.screen == main.Screen.PAUSED and paused, "pause action pauses")
	var t: float = main.view.sim.time
	await _frames(30)
	check(main.view.sim.time == t, "sim frozen while paused")
	_press_action("pause")
	await _frames(2)
	check(main.screen == main.Screen.PLAYING and not paused, "pause action resumes")

	# Human idles, CPU should take the single point.
	var frames := 0
	while main.screen != main.Screen.GAME_OVER and frames < 120 * 60:
		await process_frame
		frames += 1
	check(main.screen == main.Screen.GAME_OVER, "reaches game over")
	check(main.view.sim.winner == 1, "idle human loses to CPU")

	main.start_match(game.Mode.VS_LOCAL)
	await _frames(2)
	check(main.view.ais[0] == null and main.view.ais[1] == null, "2P has no CPU")
	main.show_title()
	await _frames(2)
	check(main.screen == main.Screen.TITLE and game.mode == game.Mode.DEMO, "back to title with demo")

	print("\n%s" % ("UI SMOKE PASSED" if _failures == 0 else "%d FAILURE(S)" % _failures))
	main.queue_free()
	await _frames(2)
	quit(0 if _failures == 0 else 1)


func check(cond: bool, msg: String) -> void:
	print("%s %s" % ["ok  " if cond else "FAIL", msg])
	if not cond:
		_failures += 1


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _press_action(action: String) -> void:
	var e := InputEventAction.new()
	e.action = action
	e.pressed = true
	Input.parse_input_event(e)
