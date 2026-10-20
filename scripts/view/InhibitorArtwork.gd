class_name InhibitorArtwork
extends Node2D

const IDLE_FRAMES := 8
const BEGIN_FRAMES := 8
const ACTIVE_FRAMES := 4
const FPS := 8.0
const CELL_ART_SCALE := 60.0 / 64.0

enum State { IDLE, CHARGING, ACTIVE }

var body: Sprite2D
var eye: EyeAnimator
var _state := State.IDLE
var _time := 0.0
var _charge_time := 0.0
var _charged := false
var _charge_forward := true
var _activate_after_charge := false

func _ready() -> void:
	body = Sprite2D.new()
	body.name = "Body"
	body.scale = Vector2.ONE * CELL_ART_SCALE
	body.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(body)
	eye = EyeAnimator.new()
	eye.name = "Eye"
	eye.configure("res://scenes/animation/eye_idle(1).png", "res://scenes/animation/eye_blink(1).png", 10, 1)
	eye.scale = Vector2.ONE * CELL_ART_SCALE
	eye.z_index = 2
	add_child(eye)
	_set_strip("res://scenes/animation/Invalidate_idle(1).png", IDLE_FRAMES)

func _process(delta: float) -> void:
	if body == null:
		return
	match _state:
		State.IDLE:
			_time += delta
			body.frame = int(_time * FPS) % IDLE_FRAMES
		State.ACTIVE:
			_time += delta
			body.frame = int(_time * FPS) % ACTIVE_FRAMES
		State.CHARGING:
			_charge_time = clampf(_charge_time + delta * (1.0 if _charge_forward else -1.0), 0.0, float(BEGIN_FRAMES) / FPS)
			body.frame = clampi(int(_charge_time * FPS), 0, BEGIN_FRAMES - 1)
			if _charge_forward and _charge_time >= float(BEGIN_FRAMES) / FPS:
				_charged = true
				if _activate_after_charge:
					_activate_after_charge = false
					_state = State.ACTIVE
					_time = 0.0
					_set_strip("res://scenes/animation/Invalidating(1).png", ACTIVE_FRAMES)
			if not _charge_forward and _charge_time <= 0.0:
				_charged = false
				_state = State.IDLE
				_time = 0.0

func refresh_state(has_rear_block: bool, has_front_block: bool, is_self_inhibited: bool) -> void:
		var should_activate := has_rear_block and has_front_block and not is_self_inhibited
		if should_activate:
			if not _charged:
				_activate_after_charge = true
				if _state != State.CHARGING:
					_state = State.CHARGING
					_charge_forward = true
					_charge_time = 0.0
					_set_strip("res://scenes/animation/Invalidate_begin(1).png", BEGIN_FRAMES)
				return
			if _state != State.ACTIVE:
				_state = State.ACTIVE
				_time = 0.0
				_set_strip("res://scenes/animation/Invalidating(1).png", ACTIVE_FRAMES)
			return
		if has_rear_block:
			if _state == State.ACTIVE:
				_state = State.CHARGING
				_charge_forward = true
				_charge_time = float(BEGIN_FRAMES) / FPS
				_set_strip("res://scenes/animation/Invalidate_begin(1).png", BEGIN_FRAMES)
				return
			if not _charged and _state != State.CHARGING:
				_state = State.CHARGING
				_charge_forward = true
				_charge_time = 0.0
				_set_strip("res://scenes/animation/Invalidate_begin(1).png", BEGIN_FRAMES)
			elif _state == State.CHARGING:
				_charge_forward = true
			return
		if _state == State.CHARGING or _charged:
			_activate_after_charge = false
			_state = State.CHARGING
			_charge_forward = false
			_charge_time = maxf(_charge_time, float(BEGIN_FRAMES) / FPS if _charged else _charge_time)
			_set_strip("res://scenes/animation/Invalidate_begin(1).png", BEGIN_FRAMES)
		else:
			_state = State.IDLE
			_time = 0.0
			_set_strip("res://scenes/animation/Invalidate_idle(1).png", IDLE_FRAMES)

func set_direction(direction: int) -> void:
	# The block direction is the sensing (detector) direction; the suppression
	# output is the opposite side. Rotate the artwork 180° so the displayed
	# art faces the actual suppression target (the rear side).
	rotation = posmod(direction + 2, 4) * (PI / 2.0)

func _set_strip(path: String, frame_count: int) -> void:
	if body.texture != null and body.texture.resource_path == path and body.hframes == frame_count:
		return
	body.texture = load(path)
	body.hframes = frame_count
	body.frame = 0
