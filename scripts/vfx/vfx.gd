## Neon Arcade effects: ball trail, hit sparks, paddle flash, ball squash,
## goal shockwave, score pop, scrolling grid and screen shake.
## Purely cosmetic: listens to the Game signals and never touches the sim.
## game_view.gd owns one of these and calls its draw_* helpers from _draw, so
## everything shares one canvas and the 2D glow.
extends Node

const Palette := preload("res://scripts/vfx/palette.gd")
const PongSim := preload("res://scripts/sim.gd")

const TRAIL_MIN := 6
const TRAIL_MAX := 22
const SPARKS_PADDLE := 18
const SPARKS_WALL := 8
const SPARK_DRAG := 6.0 # per second, exponential
const SHAKE_HIT := Vector2(6.0, 0.12) # amplitude px, duration s
const SHAKE_GOAL := Vector2(14.0, 0.28)
const FLASH_TIME := 0.06
const SQUASH_TIME := 0.12
const RING_TIME := 0.6
const POP_TIME := 0.3
const GRID_STEP := 80.0
const GRID_SPEED := 30.0 # px per second
# Blocky 3x5 score digits, like the 1972 cabinet (and no slashed zero).
const DIGITS := [
	"111101101101111", "010110010010111", "111001111100111", "111001111001111",
	"101101111001001", "111100111001111", "111100111101111", "111001001001001",
	"111101111101111", "111101111001111",
]

var view: Node2D # the GameView this decorates

var trail: Array[Vector2] = []
var trail_color := Palette.BALL
var sparks: Array[Dictionary] = []
var rings: Array[Dictionary] = []
var paddle_flash: Array[float] = [0.0, 0.0]
var score_pop: Array[float] = [0.0, 0.0]
var squash := 0.0
var grid_scroll := 0.0

var _shake_amp := 0.0
var _shake_time := 0.0
var _shake_left := 0.0
var _rng := RandomNumberGenerator.new()
var _vignette: GradientTexture2D


func _init(game_view: Node2D) -> void:
	view = game_view
	name = "Vfx"


func _ready() -> void:
	Game.match_started.connect(func(_mode): reset())
	Game.serve.connect(func(_toward): _clear_trail())
	Game.paddle_hit.connect(_on_paddle_hit)
	Game.wall_bounce.connect(_on_wall_bounce)
	Game.scored.connect(_on_scored)

	var g := Gradient.new()
	g.set_color(0, Color(Palette.BG, 0.0))
	g.set_color(1, Color(Palette.BG, 0.92))
	g.add_point(0.55, Color(Palette.BG, 0.0))
	_vignette = GradientTexture2D.new()
	_vignette.gradient = g
	_vignette.fill = GradientTexture2D.FILL_RADIAL
	_vignette.fill_from = Vector2(0.5, 0.5)
	_vignette.fill_to = Vector2(1.0, 1.0)
	_vignette.width = 256
	_vignette.height = 144


func reset() -> void:
	_clear_trail()
	sparks.clear()
	rings.clear()
	paddle_flash = [0.0, 0.0]
	score_pop = [0.0, 0.0]
	squash = 0.0
	_shake_left = 0.0
	view.position = Vector2.ZERO


func _process(delta: float) -> void:
	grid_scroll = fmod(grid_scroll + GRID_SPEED * delta, GRID_STEP)

	for i in 2:
		paddle_flash[i] = maxf(0.0, paddle_flash[i] - delta)
		score_pop[i] = maxf(0.0, score_pop[i] - delta)
	squash = maxf(0.0, squash - delta)

	var drag := exp(-SPARK_DRAG * delta)
	for s in sparks:
		s.pos += s.vel * delta
		s.vel *= drag
		s.life -= delta
	sparks = sparks.filter(func(s): return s.life > 0.0)

	for r in rings:
		r.t += delta
	rings = rings.filter(func(r): return r.t < RING_TIME)

	var sim: PongSim = view.sim
	if sim and view.running and not sim.is_serving():
		trail.push_front(view.ball_draw_pos())
		var t := clampf(sim.ball_speed() / PongSim.BALL_MAX_SPEED, 0.0, 1.0)
		var max_len := int(lerpf(TRAIL_MIN, TRAIL_MAX, t))
		if trail.size() > max_len:
			trail.resize(max_len)

	if _shake_left > 0.0:
		_shake_left = maxf(0.0, _shake_left - delta)
		var a := _shake_amp * (_shake_left / _shake_time)
		view.position = Vector2(_rng.randf_range(-a, a), _rng.randf_range(-a, a))
	elif view.position != Vector2.ZERO:
		view.position = Vector2.ZERO


# --- Events ----------------------------------------------------------------

func _on_paddle_hit(side: int, pos: Vector2, _speed: float) -> void:
	var col := Palette.side_color(side)
	paddle_flash[side] = FLASH_TIME
	squash = SQUASH_TIME
	trail_color = col
	_spark(pos, Vector2(1.0 if side == PongSim.LEFT else -1.0, 0.0), col, SPARKS_PADDLE, 1.1)
	_shake(SHAKE_HIT)


func _on_wall_bounce(pos: Vector2) -> void:
	var dir := Vector2(0.0, 1.0 if pos.y < PongSim.HEIGHT / 2.0 else -1.0)
	_spark(pos, dir, Palette.WALL, SPARKS_WALL, 1.3)


func _on_scored(side: int, _score: Array) -> void:
	var col := Palette.side_color(side)
	# The ball left through the far side from the scorer.
	var exit_x := PongSim.WIDTH if side == PongSim.LEFT else 0.0
	var y: float = trail[0].y if not trail.is_empty() else PongSim.HEIGHT / 2.0
	rings.append({"pos": Vector2(exit_x, y), "t": 0.0, "col": col})
	_spark(Vector2(exit_x, y), Vector2(-1.0 if side == PongSim.LEFT else 1.0, 0.0), col, 28, 1.4)
	score_pop[side] = POP_TIME
	_shake(SHAKE_GOAL)
	_clear_trail()


func _spark(pos: Vector2, dir: Vector2, col: Color, count: int, spread: float) -> void:
	for i in count:
		var v := dir.rotated(_rng.randf_range(-spread, spread)) * _rng.randf_range(300.0, 1000.0)
		var life := _rng.randf_range(0.25, 0.4)
		sparks.append({"pos": pos, "vel": v, "life": life, "max": life, "col": col})


func _shake(amp_time: Vector2) -> void:
	if not _shake_enabled():
		return
	# A stronger shake overrides a weaker one still running, never the reverse.
	var current := _shake_amp * (_shake_left / _shake_time) if _shake_left > 0.0 else 0.0
	if amp_time.x >= current:
		_shake_amp = amp_time.x
		_shake_time = amp_time.y
		_shake_left = amp_time.y


func _shake_enabled() -> bool:
	return Game.get("screen_shake") != false


func _clear_trail() -> void:
	trail.clear()
	trail_color = Palette.BALL


# --- Drawing (called from GameView._draw) ------------------------------------

func draw_background(ci: CanvasItem) -> void:
	var pad := 64.0 # covers the edges while shaking
	var w := PongSim.WIDTH
	var h := PongSim.HEIGHT
	ci.draw_rect(Rect2(-pad, -pad, w + pad * 2.0, h + pad * 2.0), Palette.BG)
	var x := 0.0
	while x <= w:
		ci.draw_line(Vector2(x, -pad), Vector2(x, h + pad), Palette.GRID, 2.0)
		x += GRID_STEP
	var y := -GRID_STEP + grid_scroll
	while y <= h + pad:
		ci.draw_line(Vector2(-pad, y), Vector2(w + pad, y), Palette.GRID, 2.0)
		y += GRID_STEP
	ci.draw_texture_rect(_vignette, Rect2(-pad, -pad, w + pad * 2.0, h + pad * 2.0), false)


func draw_rings(ci: CanvasItem) -> void:
	for r in rings:
		var k: float = r.t / RING_TIME
		var col: Color = Palette.hdr(r.col, Palette.GLOW_SOFT)
		col.a = 1.0 - k
		ci.draw_arc(r.pos, 40.0 + k * 520.0, 0.0, TAU, 64, col, 2.0 + 10.0 * (1.0 - k))


func draw_trail(ci: CanvasItem) -> void:
	var n := trail.size()
	for i in range(n - 1, 0, -1):
		var k := 1.0 - float(i) / n
		var s := PongSim.BALL_SIZE * (0.35 + 0.65 * k)
		var col := Palette.hdr(trail_color, 1.0 + k)
		col.a = k * 0.55
		ci.draw_rect(Rect2(trail[i] - Vector2(s, s) / 2.0, Vector2(s, s)), col)


func paddle_color(side: int) -> Color:
	if paddle_flash[side] > 0.0:
		return Palette.hdr(Color.WHITE, Palette.GLOW * 1.3)
	return Palette.hdr(Palette.side_color(side))


func ball_scale() -> float:
	return 1.0 + 0.3 * (squash / SQUASH_TIME)


func ball_color() -> Color:
	# White core, tinted slightly toward whoever hit it last so the glow carries the color.
	return Palette.hdr(Palette.BALL.lerp(trail_color, 0.25))


func score_scale(side: int) -> float:
	return 1.0 + 0.4 * (score_pop[side] / POP_TIME)


## Draws a number in block digits centered on center, each block block px.
func draw_number(ci: CanvasItem, value: int, center: Vector2, block: float, col: Color) -> void:
	var text := str(value)
	var gap := block
	var total := text.length() * 3.0 * block + (text.length() - 1) * gap
	var origin := center - Vector2(total / 2.0, 2.5 * block)
	for d in text.length():
		var pattern: String = DIGITS[int(text[d])]
		var dx := d * (3.0 * block + gap)
		for i in 15:
			if pattern[i] == "1":
				ci.draw_rect(Rect2(origin + Vector2(dx + (i % 3) * block, (i / 3) * block), Vector2(block, block)), col)


func draw_sparks(ci: CanvasItem) -> void:
	for s in sparks:
		var col: Color = Palette.hdr(s.col, Palette.GLOW_SOFT * 1.5)
		col.a = clampf(s.life / s.max, 0.0, 1.0)
		ci.draw_rect(Rect2(s.pos - Vector2(3, 3), Vector2(6, 6)), col)
