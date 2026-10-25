## Top-level flow: title (with a CPU-vs-CPU demo behind it), options, match,
## pause and game over. Menus are built in code and fully gamepad navigable.
extends Node

enum Screen { TITLE, OPTIONS, PLAYING, PAUSED, GAME_OVER }

const FONT_PATH := "res://art/font.ttf"

@onready var view: Node2D = $GameView
@onready var ui: CanvasLayer = $UI

var screen := Screen.TITLE
var _root: Control # current menu, replaced on every screen change
var _theme := Theme.new()


func _ready() -> void:
	_theme.default_font_size = 56
	if ResourceLoader.exists(FONT_PATH):
		_theme.default_font = load(FONT_PATH)
	view.finished.connect(_on_match_finished)
	show_title()

	# Headless smoke test: `godot --headless -- --autoplay=SECONDS` plays a
	# CPU-vs-CPU match for that long, then quits with code 0.
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--autoplay="):
			view.start(Game.Mode.DEMO, 1)
			get_tree().create_timer(float(arg.get_slice("=", 1))).timeout.connect(func():
				print("autoplay finished: sim time %.1f s, score %s" % [view.sim.time, view.sim.score])
				get_tree().quit())


func _notification(what: int) -> void:
	# Alt-tab, Steam overlay focus steal, etc.
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and screen == Screen.PLAYING:
		show_pause()


func _unhandled_input(event: InputEvent) -> void:
	match screen:
		Screen.PLAYING:
			if event.is_action_pressed("pause"):
				show_pause()
				get_viewport().set_input_as_handled()
		Screen.PAUSED:
			if event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel"):
				resume()
				get_viewport().set_input_as_handled()
		Screen.OPTIONS:
			if event.is_action_pressed("ui_cancel"):
				Audio.play("menu_back")
				_close_options()
				get_viewport().set_input_as_handled()


# --- Screens ---------------------------------------------------------------

func show_title() -> void:
	_unpause()
	screen = Screen.TITLE
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if Game.mode != Game.Mode.DEMO or not view.running:
		view.start(Game.Mode.DEMO)
	Audio.play_music("music_menu")
	var menu := _menu("PONG", "", [
		["1 Player", func(): start_match(Game.Mode.VS_CPU)],
		["2 Players", func(): start_match(Game.Mode.VS_LOCAL)],
		["Options", show_options],
		["Quit", func(): get_tree().quit()],
	], true)
	var hint := _label("P1: W / S or gamepad 1     P2: Up / Down or gamepad 2     Pause: Esc / Start", 28)
	hint.modulate.a = 0.6
	hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	hint.offset_top = -110
	hint.offset_bottom = -60
	menu.add_child(hint)


func show_options() -> void:
	screen = Screen.OPTIONS
	var rows: Array = []
	rows.append([_cycle_text("Difficulty", Game.DIFFICULTY_NAMES[Game.difficulty]), func(b: Button):
		Game.difficulty = (Game.difficulty + 1) % Game.DIFFICULTY_NAMES.size()
		b.text = _cycle_text("Difficulty", Game.DIFFICULTY_NAMES[Game.difficulty])])
	rows.append([_cycle_text("Points to win", str(Game.win_score)), func(b: Button):
		var i := (Game.WIN_SCORE_CHOICES.find(Game.win_score) + 1) % Game.WIN_SCORE_CHOICES.size()
		Game.win_score = Game.WIN_SCORE_CHOICES[i]
		b.text = _cycle_text("Points to win", str(Game.win_score))])
	rows.append(["slider", "Master volume", "master_volume"])
	rows.append(["slider", "Music volume", "music_volume"])
	rows.append(["slider", "Effects volume", "sfx_volume"])
	rows.append([_cycle_text("Fullscreen", "On" if Game.fullscreen else "Off"), func(b: Button):
		Game.toggle_fullscreen()
		b.text = _cycle_text("Fullscreen", "On" if Game.fullscreen else "Off")])
	rows.append(["Back", func(_b): _close_options()])
	_menu("OPTIONS", "", rows, true)


func _close_options() -> void:
	Game.save_settings()
	show_title()


func start_match(mode: Game.Mode) -> void:
	_unpause()
	_clear_menu()
	screen = Screen.PLAYING
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	Audio.play("game_start")
	Audio.play_music("music_loop")
	view.start(mode)


func show_pause() -> void:
	screen = Screen.PAUSED
	get_tree().paused = true
	Game.paused_changed.emit(true)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_menu("PAUSED", "", [
		["Resume", resume],
		["Restart", func(): start_match(Game.mode)],
		["Main Menu", show_title],
	], true)


func resume() -> void:
	_clear_menu()
	screen = Screen.PLAYING
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	_unpause()


## Unpauses the tree and, if it was paused, tells listeners (audio, graphics).
func _unpause() -> void:
	if get_tree().paused:
		get_tree().paused = false
		Game.paused_changed.emit(false)


func _on_match_finished(winner: int) -> void:
	screen = Screen.GAME_OVER
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Audio.stop_music()
	var title: String
	if Game.mode == Game.Mode.VS_CPU:
		title = "YOU WIN!" if Game.is_human(winner) else "CPU WINS"
	else:
		title = "PLAYER %d WINS!" % (winner + 1)
	var score: Array = view.sim.score
	_menu(title, "%d  -  %d" % [score[0], score[1]], [
		["Rematch", func(): start_match(Game.mode)],
		["Main Menu", show_title],
	], true)


# --- Menu building -----------------------------------------------------------

## Builds a centered menu. Each item is [text, callable] for a button (the
## callable may take the Button as an argument), or ["slider", text, Game property]
## for a 0..1 volume slider.
func _menu(title: String, subtitle: String, items: Array, dim_background: bool) -> Control:
	_clear_menu()
	_root = Control.new()
	_root.theme = _theme
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui.add_child(_root)

	if dim_background:
		var shade := ColorRect.new()
		shade.color = Color(0, 0, 0, 0.6)
		shade.set_anchors_preset(Control.PRESET_FULL_RECT)
		_root.add_child(shade)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(center)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 18)
	center.add_child(box)

	box.add_child(_label(title, 160))
	if subtitle != "":
		box.add_child(_label(subtitle, 72))
	var spacer := Control.new()
	spacer.custom_minimum_size.y = 40
	box.add_child(spacer)

	var focusables: Array[Control] = []
	for item in items:
		if item[0] == "slider":
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 24)
			var l := _label(item[1], 44)
			l.custom_minimum_size.x = 420
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			row.add_child(l)
			var s := HSlider.new()
			s.min_value = 0.0
			s.max_value = 1.0
			s.step = 0.1
			s.value = Game.get(item[2])
			s.custom_minimum_size = Vector2(420, 48)
			s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			var prop: String = item[2]
			s.value_changed.connect(func(v: float):
				Game.set(prop, v)
				Audio.apply_volumes()
				Audio.play("menu_move"))
			row.add_child(s)
			box.add_child(row)
			focusables.append(s)
		else:
			var b := Button.new()
			b.text = item[0]
			b.custom_minimum_size = Vector2(640, 0)
			b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			var cb: Callable = item[1]
			b.pressed.connect(func():
				Audio.play("menu_select")
				if cb.get_argument_count() == 1:
					cb.call(b)
				else:
					cb.call())
			box.add_child(b)
			focusables.append(b)

	if not focusables.is_empty():
		focusables[0].grab_focus()
		# Connect after the initial grab so opening a menu doesn't make a move sound.
		for c in focusables:
			c.focus_entered.connect(func(): Audio.play("menu_move"))
	return _root


func _clear_menu() -> void:
	if _root:
		_root.queue_free()
		_root = null


func _label(text: String, size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", size)
	return l


func _cycle_text(name: String, value: String) -> String:
	return "%s:  %s" % [name, value]
