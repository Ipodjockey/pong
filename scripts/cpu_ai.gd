## CPU opponent. Pure logic: reads a PongSim and returns an axis value in
## [-1, 1] for one paddle. Seedable so CPU-vs-CPU runs are reproducible.
extends RefCounted

const PongSim := preload("res://scripts/sim.gd")

enum Difficulty { EASY, NORMAL, HARD }

## reaction: seconds before reacting to a new ball direction.
## speed: fraction of full paddle speed.
## predict: follow the projected impact point (with wall bounces) instead of the ball.
## aim: max paddle offset used to angle returns (0 = flat, 1 = paddle edge).
## mistake: chance to misjudge a return at serve speed; scales with speed squared,
##   which is what guarantees rallies eventually end.
const PRESETS := {
	Difficulty.EASY: {"reaction": 0.30, "speed": 0.55, "predict": false, "aim": 0.3, "mistake": 0.10},
	Difficulty.NORMAL: {"reaction": 0.18, "speed": 0.80, "predict": true, "aim": 0.55, "mistake": 0.05},
	Difficulty.HARD: {"reaction": 0.10, "speed": 1.00, "predict": true, "aim": 0.85, "mistake": 0.02},
}

var side: int
var cfg: Dictionary
var rng := RandomNumberGenerator.new()
var _target_y := PongSim.HEIGHT / 2.0
var _react_timer := 0.0
var _last_dir := 0.0
var _error := 0.0


func _init(paddle_side: int, difficulty: int = Difficulty.NORMAL, seed_value: int = -1) -> void:
	side = paddle_side
	cfg = PRESETS[difficulty]
	if seed_value < 0:
		rng.randomize()
	else:
		rng.seed = seed_value


func get_input(sim: PongSim, dt: float) -> float:
	var dir := signf(sim.ball_vel.x)
	if dir != _last_dir:
		# New trajectory: wait a human-ish reaction time and pick a fresh aim error.
		_last_dir = dir
		_react_timer = cfg.reaction
		var reach := (PongSim.PADDLE_H + PongSim.BALL_SIZE) / 2.0
		_error = -rng.randf_range(-cfg.aim, cfg.aim) * reach
		var speed_ratio := sim.ball_speed() / PongSim.BALL_START_SPEED
		if rng.randf() < cfg.mistake * speed_ratio * speed_ratio:
			_error = reach * rng.randf_range(1.1, 1.6) * (1.0 if rng.randf() < 0.5 else -1.0)

	if _react_timer > 0.0:
		_react_timer -= dt
	else:
		var incoming := (side == PongSim.LEFT and dir < 0.0) or (side == PongSim.RIGHT and dir > 0.0)
		if incoming:
			var y: float = _predict_y(sim) if cfg.predict else sim.ball_pos.y
			_target_y = y + _error
		else:
			_target_y = PongSim.HEIGHT / 2.0

	var diff := _target_y - sim.paddle_y[side]
	if absf(diff) < 6.0:
		return 0.0
	return clampf(diff / 40.0, -1.0, 1.0) * cfg.speed


## Where the ball will cross this paddle's face, unfolding wall bounces.
func _predict_y(sim: PongSim) -> float:
	var dir := 1.0 if side == PongSim.LEFT else -1.0
	var face_x := PongSim.paddle_x(side) + dir * (PongSim.PADDLE_W + PongSim.BALL_SIZE) / 2.0
	if is_zero_approx(sim.ball_vel.x):
		return sim.ball_pos.y
	var t := (face_x - sim.ball_pos.x) / sim.ball_vel.x
	if t < 0.0:
		return sim.ball_pos.y
	var half := PongSim.BALL_SIZE / 2.0
	var span := PongSim.HEIGHT - PongSim.BALL_SIZE
	var y := fposmod(sim.ball_pos.y + sim.ball_vel.y * t - half, 2.0 * span)
	if y > span:
		y = 2.0 * span - y
	return y + half
