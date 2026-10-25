## Autoload "Game": match settings, persisted options, input map, and the
## gameplay event bus that graphics and audio listen to.
extends Node

enum Mode { VS_CPU, VS_LOCAL, DEMO }

const SETTINGS_PATH := "user://settings.cfg"
const WIN_SCORE_CHOICES: Array[int] = [5, 7, 11, 15, 21]
const DIFFICULTY_NAMES: Array[String] = ["Easy", "Normal", "Hard"]

## Emitted by the game view for every simulation event.
## side: 0 = left (player 1), 1 = right (player 2 / CPU).
signal match_started(mode: Mode)
signal serve(toward: int)
signal paddle_hit(side: int, pos: Vector2, speed: float)
signal wall_bounce(pos: Vector2)
signal scored(side: int, score: Array)
signal match_over(winner: int)
signal paused_changed(paused: bool)

var mode: Mode = Mode.VS_CPU

# Persisted settings.
var difficulty := 1
var win_score := 11
var master_volume := 1.0
var music_volume := 0.6
var sfx_volume := 1.0
var fullscreen := true


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_input()
	load_settings()
	apply_display()


## True when this side is driven by a human in the current mode.
func is_human(side: int) -> bool:
	match mode:
		Mode.VS_CPU:
			return side == 0
		Mode.VS_LOCAL:
			return true
	return false


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		return
	difficulty = clampi(cfg.get_value("game", "difficulty", difficulty), 0, 2)
	win_score = cfg.get_value("game", "win_score", win_score)
	if win_score not in WIN_SCORE_CHOICES:
		win_score = 11
	master_volume = clampf(cfg.get_value("audio", "master", master_volume), 0.0, 1.0)
	music_volume = clampf(cfg.get_value("audio", "music", music_volume), 0.0, 1.0)
	sfx_volume = clampf(cfg.get_value("audio", "sfx", sfx_volume), 0.0, 1.0)
	fullscreen = cfg.get_value("display", "fullscreen", fullscreen)


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("game", "difficulty", difficulty)
	cfg.set_value("game", "win_score", win_score)
	cfg.set_value("audio", "master", master_volume)
	cfg.set_value("audio", "music", music_volume)
	cfg.set_value("audio", "sfx", sfx_volume)
	cfg.set_value("display", "fullscreen", fullscreen)
	cfg.save(SETTINGS_PATH)


func apply_display() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var target := DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
	if DisplayServer.window_get_mode() != target:
		DisplayServer.window_set_mode(target)


func toggle_fullscreen() -> void:
	fullscreen = not fullscreen
	apply_display()
	save_settings()


func _unhandled_input(event: InputEvent) -> void:
	# Alt+Enter and F11 toggle fullscreen everywhere, as PC players expect.
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F11 or (event.keycode == KEY_ENTER and event.alt_pressed):
			toggle_fullscreen()
			get_viewport().set_input_as_handled()


## Input actions are defined here instead of project.godot so they stay readable.
## Player 1: W/S, first gamepad. Player 2: arrow keys, second gamepad.
## In 1-player mode the game view also lets player 1 use player 2's controls.
func _setup_input() -> void:
	_add_action("p1_up", [_key(KEY_W), _joy_button(0, JOY_BUTTON_DPAD_UP), _joy_axis(0, JOY_AXIS_LEFT_Y, -1.0)])
	_add_action("p1_down", [_key(KEY_S), _joy_button(0, JOY_BUTTON_DPAD_DOWN), _joy_axis(0, JOY_AXIS_LEFT_Y, 1.0)])
	_add_action("p2_up", [_key(KEY_UP), _joy_button(1, JOY_BUTTON_DPAD_UP), _joy_axis(1, JOY_AXIS_LEFT_Y, -1.0)])
	_add_action("p2_down", [_key(KEY_DOWN), _joy_button(1, JOY_BUTTON_DPAD_DOWN), _joy_axis(1, JOY_AXIS_LEFT_Y, 1.0)])
	_add_action("pause", [_key(KEY_ESCAPE), _key(KEY_P), _joy_button(-1, JOY_BUTTON_START)])


func _add_action(action: String, events: Array) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action, 0.25)
	for e in events:
		InputMap.action_add_event(action, e)


func _key(code: Key) -> InputEventKey:
	var e := InputEventKey.new()
	e.physical_keycode = code
	return e


func _joy_button(device: int, button: JoyButton) -> InputEventJoypadButton:
	var e := InputEventJoypadButton.new()
	e.device = device
	e.button_index = button
	return e


func _joy_axis(device: int, axis: JoyAxis, value: float) -> InputEventJoypadMotion:
	var e := InputEventJoypadMotion.new()
	e.device = device
	e.axis = axis
	e.axis_value = value
	return e
