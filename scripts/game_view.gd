## Runs a match: feeds input/CPU into the PongSim at the fixed physics rate,
## forwards sim events to the Game signal bus, and draws the playfield.
## Drawing is the Neon Arcade look: palette in scripts/vfx/palette.gd,
## effects in scripts/vfx/vfx.gd.
extends Node2D

const PongSim := preload("res://scripts/sim.gd")
const CpuAI := preload("res://scripts/cpu_ai.gd")
const Palette := preload("res://scripts/vfx/palette.gd")
const Vfx := preload("res://scripts/vfx/vfx.gd")
const FONT_PATH := "res://art/font.ttf"
const DEMO_RESTART_DELAY := 2.0

signal finished(winner: int)

var sim: PongSim
var ais: Array = [null, null] # CpuAI per side, null when human-controlled
var running := false
var font: Font
var vfx: Vfx

# Previous tick's positions, so drawing can interpolate between physics ticks
# on high refresh rate monitors.
var _prev_ball := Vector2.ZERO
var _prev_paddles: Array[float] = [0.0, 0.0]


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	font = load(FONT_PATH) if ResourceLoader.exists(FONT_PATH) else ThemeDB.fallback_font
	vfx = Vfx.new(self)
	add_child(vfx)


func start(mode: Game.Mode, seed_value := -1) -> void:
	Game.mode = mode
	var cpu_difficulty: int = Game.difficulty
	var points := Game.win_score
	if mode == Game.Mode.DEMO:
		cpu_difficulty = CpuAI.Difficulty.HARD
		points = 5
	sim = PongSim.new(seed_value, points)
	for side in [PongSim.LEFT, PongSim.RIGHT]:
		ais[side] = null if Game.is_human(side) else CpuAI.new(side, cpu_difficulty)
	_snap_interpolation()
	running = true
	queue_redraw()
	Game.match_started.emit(mode)


func stop() -> void:
	running = false


## Ball position to draw this frame (interpolated between physics ticks).
func ball_draw_pos() -> Vector2:
	return _prev_ball.lerp(sim.ball_pos, Engine.get_physics_interpolation_fraction())


func paddle_draw_y(side: int) -> float:
	return lerpf(_prev_paddles[side], sim.paddle_y[side], Engine.get_physics_interpolation_fraction())


func _physics_process(delta: float) -> void:
	if not running or sim == null:
		return
	_prev_ball = sim.ball_pos
	_prev_paddles = sim.paddle_y.duplicate()

	var inputs := [0.0, 0.0]
	for side in [PongSim.LEFT, PongSim.RIGHT]:
		inputs[side] = ais[side].get_input(sim, delta) if ais[side] else _human_axis(side)

	for e in sim.step(inputs, delta):
		match e.type:
			"serve":
				_snap_interpolation()
				Game.serve.emit(e.toward)
			"paddle_hit":
				Game.paddle_hit.emit(e.side, e.pos, e.speed)
			"wall_bounce":
				Game.wall_bounce.emit(e.pos)
			"score":
				_snap_interpolation()
				Game.scored.emit(e.side, e.score)
			"match_over":
				running = false
				Game.match_over.emit(e.winner)
				if Game.mode == Game.Mode.DEMO:
					get_tree().create_timer(DEMO_RESTART_DELAY).timeout.connect(_restart_demo)
				else:
					finished.emit(e.winner)


func _process(_delta: float) -> void:
	queue_redraw()


func _human_axis(side: int) -> float:
	var axis := 0.0
	if side == PongSim.LEFT or Game.mode == Game.Mode.VS_CPU:
		axis += Input.get_axis("p1_up", "p1_down")
	if side == PongSim.RIGHT or Game.mode == Game.Mode.VS_CPU:
		axis += Input.get_axis("p2_up", "p2_down")
	return clampf(axis, -1.0, 1.0)


func _snap_interpolation() -> void:
	_prev_ball = sim.ball_pos
	_prev_paddles = sim.paddle_y.duplicate()


func _restart_demo() -> void:
	if Game.mode == Game.Mode.DEMO and not running:
		start(Game.Mode.DEMO)


func _draw() -> void:
	if sim == null:
		return
	vfx.draw_background(self)

	# Top and bottom walls, on the screen edges where the ball bounces.
	var wall := Palette.hdr(Palette.WALL, Palette.GLOW_SOFT)
	draw_rect(Rect2(0.0, 0.0, PongSim.WIDTH, 8.0), wall)
	draw_rect(Rect2(0.0, PongSim.HEIGHT - 8.0, PongSim.WIDTH, 8.0), wall)

	# Center net.
	var y := 32.0
	while y < PongSim.HEIGHT - 32.0:
		draw_rect(Rect2(PongSim.WIDTH / 2.0 - 4.0, y, 8.0, 32.0), Palette.NET)
		y += 56.0

	# Scores, faint so they never hide the ball; they pop in the scorer's color.
	for side in [PongSim.LEFT, PongSim.RIGHT]:
		var cx := PongSim.WIDTH / 2.0 + (-240.0 if side == PongSim.LEFT else 240.0)
		var k := vfx.score_scale(side)
		var col := Palette.SCORE.lerp(Palette.hdr(Palette.side_color(side), 1.4), (k - 1.0) * 2.0)
		vfx.draw_number(self, sim.score[side], Vector2(cx, 130.0), 22.0 * k, col)

	vfx.draw_rings(self)
	vfx.draw_trail(self)

	# Paddles.
	for side in [PongSim.LEFT, PongSim.RIGHT]:
		var center := Vector2(PongSim.paddle_x(side), paddle_draw_y(side))
		var size := Vector2(PongSim.PADDLE_W, PongSim.PADDLE_H)
		draw_rect(Rect2(center - size / 2.0, size), vfx.paddle_color(side))
		# Bright core keeps the paddle's edges crisp inside its glow.
		var core := Vector2(8.0, PongSim.PADDLE_H - 16.0)
		draw_rect(Rect2(center - core / 2.0, core), Palette.hdr(Color.WHITE.lerp(Palette.side_color(side), 0.4), 1.2))

	# Ball (hidden while waiting to serve, except a blink).
	if sim.winner < 0 and (not sim.is_serving() or fmod(sim.serve_timer, 0.4) > 0.2):
		var b := Vector2(PongSim.BALL_SIZE, PongSim.BALL_SIZE) * vfx.ball_scale()
		draw_rect(Rect2(ball_draw_pos() - b / 2.0, b), vfx.ball_color())

	vfx.draw_sparks(self)
