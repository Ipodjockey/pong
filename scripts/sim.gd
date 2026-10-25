## Pure Pong simulation. No rendering, audio, input or scene tree access, so it
## can run headless and be stepped deterministically from tests.
##
## Usage:
##   var sim := PongSim.new(seed, points_to_win)
##   var events := sim.step([left_axis, right_axis], 1.0 / 120.0)
## Axis values are in [-1, 1], negative is up. Each event is a Dictionary with a
## "type" key: "serve", "paddle_hit", "wall_bounce", "score", "match_over".
extends RefCounted

const WIDTH := 1920.0
const HEIGHT := 1080.0
const PADDLE_W := 24.0
const PADDLE_H := 160.0
const PADDLE_MARGIN := 80.0 # distance from screen edge to paddle center
const PADDLE_SPEED := 1100.0
const BALL_SIZE := 24.0
const BALL_START_SPEED := 720.0
const BALL_SPEEDUP := 1.06 # multiplier per paddle hit
const BALL_MAX_SPEED := 2200.0
const MAX_BOUNCE_ANGLE := deg_to_rad(55.0)
const MAX_SERVE_ANGLE := deg_to_rad(30.0)
const SERVE_DELAY := 1.0
const MAX_SUBSTEP_DIST := 6.0 # far below paddle width + ball size, so no tunneling

const LEFT := 0
const RIGHT := 1

var rng := RandomNumberGenerator.new()
var points_to_win: int
var paddle_y: Array[float] = [HEIGHT / 2.0, HEIGHT / 2.0]
var paddle_vel: Array[float] = [0.0, 0.0]
var ball_pos := Vector2(WIDTH / 2.0, HEIGHT / 2.0)
var ball_vel := Vector2.ZERO
var score: Array[int] = [0, 0]
var serve_timer := SERVE_DELAY
var serve_to := LEFT
var winner := -1
var rally_hits := 0
var time := 0.0

var _events: Array[Dictionary] = []


## seed_value < 0 picks a random seed.
func _init(seed_value: int = -1, win_score: int = 11) -> void:
	if seed_value < 0:
		rng.randomize()
	else:
		rng.seed = seed_value
	points_to_win = win_score
	serve_to = rng.randi_range(LEFT, RIGHT)


static func paddle_x(side: int) -> float:
	return PADDLE_MARGIN if side == LEFT else WIDTH - PADDLE_MARGIN


func is_serving() -> bool:
	return winner < 0 and ball_vel == Vector2.ZERO


func ball_speed() -> float:
	return ball_vel.length()


func step(inputs: Array, dt: float) -> Array[Dictionary]:
	_events = []
	if winner >= 0:
		return _events
	time += dt
	for side in [LEFT, RIGHT]:
		var axis := clampf(float(inputs[side]), -1.0, 1.0)
		if is_nan(axis):
			axis = 0.0
		paddle_vel[side] = axis * PADDLE_SPEED
		paddle_y[side] = clampf(paddle_y[side] + paddle_vel[side] * dt, PADDLE_H / 2.0, HEIGHT - PADDLE_H / 2.0)

	if ball_vel == Vector2.ZERO:
		serve_timer -= dt
		if serve_timer <= 0.0:
			_serve()
		return _events

	_move_ball(dt)
	return _events


func _serve() -> void:
	var angle := rng.randf_range(-MAX_SERVE_ANGLE, MAX_SERVE_ANGLE)
	var dir := -1.0 if serve_to == LEFT else 1.0
	ball_pos = Vector2(WIDTH / 2.0, HEIGHT / 2.0)
	ball_vel = Vector2(cos(angle) * dir, sin(angle)) * BALL_START_SPEED
	rally_hits = 0
	_events.append({"type": "serve", "toward": serve_to})


func _move_ball(dt: float) -> void:
	var steps := maxi(1, ceili(ball_vel.length() * dt / MAX_SUBSTEP_DIST))
	var sub_dt := dt / steps
	var half := BALL_SIZE / 2.0
	for i in steps:
		ball_pos += ball_vel * sub_dt

		if ball_pos.y - half < 0.0:
			ball_pos.y = half
			ball_vel.y = absf(ball_vel.y)
			_events.append({"type": "wall_bounce", "pos": ball_pos})
		elif ball_pos.y + half > HEIGHT:
			ball_pos.y = HEIGHT - half
			ball_vel.y = -absf(ball_vel.y)
			_events.append({"type": "wall_bounce", "pos": ball_pos})

		if ball_vel.x < 0.0 and _touches_paddle(LEFT):
			_bounce(LEFT)
		elif ball_vel.x > 0.0 and _touches_paddle(RIGHT):
			_bounce(RIGHT)

		if ball_pos.x + half < 0.0:
			_point(RIGHT)
			return
		if ball_pos.x - half > WIDTH:
			_point(LEFT)
			return


func _touches_paddle(side: int) -> bool:
	var px := paddle_x(side)
	# Once the ball's center is behind the paddle's center line it's a miss;
	# this stops edge clips from "saving" a ball that already got past.
	if (side == LEFT and ball_pos.x < px) or (side == RIGHT and ball_pos.x > px):
		return false
	var reach_x := (PADDLE_W + BALL_SIZE) / 2.0
	var reach_y := (PADDLE_H + BALL_SIZE) / 2.0
	return absf(ball_pos.x - px) <= reach_x and absf(ball_pos.y - paddle_y[side]) <= reach_y


func _bounce(side: int) -> void:
	var reach_y := (PADDLE_H + BALL_SIZE) / 2.0
	var offset := clampf((ball_pos.y - paddle_y[side]) / reach_y, -1.0, 1.0)
	var angle := offset * MAX_BOUNCE_ANGLE
	var speed := minf(ball_vel.length() * BALL_SPEEDUP, BALL_MAX_SPEED)
	var dir := 1.0 if side == LEFT else -1.0
	ball_vel = Vector2(cos(angle) * dir, sin(angle)) * speed
	ball_pos.x = paddle_x(side) + dir * (PADDLE_W + BALL_SIZE) / 2.0
	rally_hits += 1
	_events.append({"type": "paddle_hit", "side": side, "pos": ball_pos, "speed": speed, "offset": offset})


func _point(side: int) -> void:
	score[side] += 1
	_events.append({"type": "score", "side": side, "score": score.duplicate(), "pos": ball_pos})
	ball_pos = Vector2(WIDTH / 2.0, HEIGHT / 2.0)
	ball_vel = Vector2.ZERO
	if score[side] >= points_to_win:
		winner = side
		_events.append({"type": "match_over", "winner": side, "score": score.duplicate()})
		return
	serve_to = 1 - side # serve toward whoever conceded
	serve_timer = SERVE_DELAY
