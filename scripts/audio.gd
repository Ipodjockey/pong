## Autoload "Audio": plays sound effects by event name and handles music.
## Files live at res://audio/sfx/<name>.ogg (variants <name>_2.ogg, <name>_3.ogg ...
## are picked at random) and res://audio/music/<name>.ogg. Missing files are
## skipped silently so audio can be swapped or added at any time.
extends Node

const PongSim := preload("res://scripts/sim.gd")
const SFX_DIR := "res://audio/sfx/"
const MUSIC_DIR := "res://audio/music/"
const POOL_SIZE := 12
const MUSIC_BUS_OFFSET_DB := -8.0 # music sits under the effects
const MUSIC_FADE := 0.6

var _sfx_cache := {} # name -> Array[AudioStream]
var _pool: Array[AudioStreamPlayer] = []
var _next := 0
var _music: AudioStreamPlayer
var _music_name := ""
var _music_tween: Tween


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_bus("Music")
	_ensure_bus("SFX")
	for i in POOL_SIZE:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_pool.append(p)
	_music = AudioStreamPlayer.new()
	_music.bus = "Music"
	add_child(_music)
	apply_volumes()

	Game.serve.connect(func(_toward): _gameplay_sfx("ball_serve"))
	Game.paddle_hit.connect(_on_paddle_hit)
	Game.wall_bounce.connect(func(_pos): _gameplay_sfx("wall_bounce"))
	Game.scored.connect(_on_scored)
	Game.match_over.connect(_on_match_over)
	Game.paused_changed.connect(func(_p): play("pause"))


func play(sfx_name: String, pitch := 1.0, volume_db := 0.0) -> void:
	var streams := _streams(sfx_name)
	if streams.is_empty():
		return
	var p := _pool[_next]
	_next = (_next + 1) % POOL_SIZE
	p.stream = streams[randi() % streams.size()]
	p.pitch_scale = pitch
	p.volume_db = volume_db
	p.play()


func play_music(music_name: String) -> void:
	if music_name == _music_name and _music.playing:
		return
	_music_name = music_name
	var path := MUSIC_DIR + music_name + ".ogg"
	if not ResourceLoader.exists(path):
		stop_music()
		return
	var stream: AudioStream = load(path)
	if stream is AudioStreamOggVorbis:
		stream.loop = true
	_music.stream = stream
	_music.volume_db = -40.0
	_music.play()
	_fade_music_to(0.0)


func stop_music() -> void:
	_music_name = ""
	if _music.playing:
		_fade_music_to(-40.0).tween_callback(_music.stop)


func apply_volumes() -> void:
	_set_bus("Master", Game.master_volume)
	_set_bus("Music", Game.music_volume, MUSIC_BUS_OFFSET_DB)
	_set_bus("SFX", Game.sfx_volume)


func _fade_music_to(db: float) -> Tween:
	if _music_tween:
		_music_tween.kill()
	_music_tween = create_tween()
	_music_tween.tween_property(_music, "volume_db", db, MUSIC_FADE)
	return _music_tween


func _streams(sfx_name: String) -> Array:
	if not _sfx_cache.has(sfx_name):
		var list: Array[AudioStream] = []
		var path := SFX_DIR + sfx_name + ".ogg"
		if ResourceLoader.exists(path):
			list.append(load(path))
			var i := 2
			while ResourceLoader.exists("%s%s_%d.ogg" % [SFX_DIR, sfx_name, i]):
				list.append(load("%s%s_%d.ogg" % [SFX_DIR, sfx_name, i]))
				i += 1
		_sfx_cache[sfx_name] = list
	return _sfx_cache[sfx_name]


# The title screen runs a CPU-vs-CPU demo behind the menu; keep that one quiet.
func _gameplay_sfx(sfx_name: String, pitch := 1.0) -> void:
	if Game.mode != Game.Mode.DEMO:
		play(sfx_name, pitch)


func _on_paddle_hit(_side: int, _pos: Vector2, speed: float) -> void:
	# Pitch rises gently as the rally speeds up.
	var t := inverse_lerp(PongSim.BALL_START_SPEED, PongSim.BALL_MAX_SPEED, speed)
	_gameplay_sfx("paddle_hit", lerpf(1.0, 1.25, clampf(t, 0.0, 1.0)))


func _on_scored(side: int, _score: Array) -> void:
	if Game.mode == Game.Mode.VS_CPU and not Game.is_human(side):
		_gameplay_sfx("score_opponent")
	else:
		_gameplay_sfx("score_player")


func _on_match_over(winner: int) -> void:
	if Game.mode == Game.Mode.VS_CPU and not Game.is_human(winner):
		_gameplay_sfx("game_over_lose")
	else:
		_gameplay_sfx("game_over_win")


func _ensure_bus(bus: String) -> void:
	if AudioServer.get_bus_index(bus) == -1:
		AudioServer.add_bus()
		var idx := AudioServer.bus_count - 1
		AudioServer.set_bus_name(idx, bus)
		AudioServer.set_bus_send(idx, "Master")


func _set_bus(bus: String, linear: float, offset_db := 0.0) -> void:
	var idx := AudioServer.get_bus_index(bus)
	AudioServer.set_bus_volume_db(idx, linear_to_db(linear) + offset_db)
	AudioServer.set_bus_mute(idx, linear <= 0.001)

