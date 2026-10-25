## Captures in-game screenshots (for Steam store shots and visual checks).
## Needs a real renderer, not --headless:
##   godot -s tools/screenshot.gd -- --out=shots --times=2.0,3.5,6 [--menu=title|none] [--seed=3]
## Saves shots/shot_<time>.png at 1920x1080 from a CPU-vs-CPU demo match.
extends SceneTree

var _times: Array[float] = [2.0]
var _out := "user://shots"
var _menu := "title"
var _seed := 3
var _elapsed := 0.0
var _main: Node


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		var k := arg.get_slice("=", 0)
		var v := arg.get_slice("=", 1)
		match k:
			"--out": _out = v
			"--menu": _menu = v
			"--seed": _seed = int(v)
			"--times":
				_times.clear()
				for t in v.split(","):
					_times.append(float(t))
	DirAccess.make_dir_recursive_absolute(_out)
	root.size = Vector2i(1920, 1080)
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)
	if _menu == "none":
		_main.call_deferred("_clear_menu")
		_main.get_node("GameView").call_deferred("start", Game.Mode.DEMO, _seed)


func _process(delta: float) -> bool:
	_elapsed += delta
	if not _times.is_empty() and _elapsed >= _times[0]:
		var t: float = _times.pop_front()
		var img := root.get_texture().get_image()
		var path := "%s/shot_%05.2f.png" % [_out, t]
		img.save_png(path)
		print("saved ", path)
	return _times.is_empty()
