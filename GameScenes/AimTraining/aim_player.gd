extends CharacterBody3D
## Local single-player FPS controller for the Aim Training scene - no
## networking. Mirrors the Source-engine movement model of player_instance.gd
## (ground friction, accel, air-strafe cap, crouch with eye-height lerp, jump)
## so the training feel matches a real match. Everything runs on the main
## thread here; the real player feeds the same math through Fusion payloads.

const JUMP_GRAVITY := 22.0
const GROUND_ACCEL := 14.0
const GROUND_FRICTION := 10.0
const AIR_ACCEL := 2.2
const AIR_CAP := 0.85
const CROUCH_SPEED := 2.5
const STAND_HEIGHT := 2.0
const CROUCH_HEIGHT := 1.0
const STAND_EYE := 1.6
const CROUCH_EYE := 0.9
const CROUCH_LERP_SPEED := 10.0

## Stand-ins for the fields weapon.gd reads off its owner - keeps _can_act
## and the camera/crosshair wiring identical to player_instance.
var player_id := 0
var spectating := false
var crouching := false

var walk_speed := 5.0
var sprint_speed := 9.0
@export var jump_velocity := 6.5

@onready var camera_pivot: Node3D = $CameraPivot
@onready var camera_3d: Camera3D = $CameraPivot/Camera3D
@onready var collision_shape: CollisionShape3D = $CollisionShape3D

var _prev_jump_pressed := false

func _ready() -> void:
	add_to_group("aim_player")
	camera_3d.current = true
	camera_3d.make_current()
	_capture_mouse()
	get_window().focus_entered.connect(_capture_mouse)

func _capture_mouse() -> void:
	if get_window().has_focus():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _physics_process(delta: float) -> void:
	if not get_window().has_focus() and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	crouching = Input.is_action_pressed("crouch")
	var jump_held := Input.is_action_pressed("jump")
	var jump_press := jump_held and not _prev_jump_pressed
	_prev_jump_pressed = jump_held

	var speed := CROUCH_SPEED if crouching else (sprint_speed if Input.is_action_pressed("sprint") else walk_speed)
	var wish_dir := (transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()

	if not is_on_floor():
		velocity.y -= JUMP_GRAVITY * delta
	elif jump_press:
		velocity.y = jump_velocity

	if is_on_floor():
		_apply_ground_friction(delta)
		if input_dir != Vector2.ZERO:
			_accelerate(wish_dir, speed, GROUND_ACCEL, delta)
	else:
		_accelerate(wish_dir, speed, AIR_ACCEL, delta, AIR_CAP)

	move_and_slide()
	_update_crouch(delta)
	_update_crosshair_spread()

## Source-engine ground friction: exponential decay of horizontal velocity
## when no movement input is held.
func _apply_ground_friction(delta_time: float) -> void:
	var h_speed := Vector2(velocity.x, velocity.z).length()
	if h_speed <= 0.0:
		return
	var drop := h_speed * GROUND_FRICTION * delta_time
	var scale := maxf(h_speed - drop, 0.0) / h_speed
	velocity.x *= scale
	velocity.z *= scale

## Quake/Source acceleration: only add speed toward the wish direction, up to
## the target speed, capped per-frame in the air.
func _accelerate(wish_dir: Vector3, target_speed: float, accel: float,
		delta_time: float, cap: float = -1.0) -> void:
	var current_speed := Vector3(velocity.x, 0.0, velocity.z).dot(wish_dir)
	var add_speed := target_speed - current_speed
	if add_speed <= 0.0:
		return
	var accel_speed := accel * target_speed * delta_time
	if cap > 0.0:
		accel_speed = minf(accel_speed, cap * target_speed)
	accel_speed = minf(accel_speed, add_speed)
	velocity.x += accel_speed * wish_dir.x
	velocity.z += accel_speed * wish_dir.z

## Crouch presentation: lerp capsule height (feet stay anchored) and the eye
## height, matching player_instance's _update_crouch without the hitboxes.
func _update_crouch(delta: float) -> void:
	var shape := collision_shape.shape as CapsuleShape3D
	if shape:
		var target_h := CROUCH_HEIGHT if crouching else STAND_HEIGHT
		shape.height = lerpf(shape.height, target_h, delta * CROUCH_LERP_SPEED)
		collision_shape.position.y = -1.0 + shape.height / 2.0
	camera_pivot.position.y = lerpf(camera_pivot.position.y,
		CROUCH_EYE if crouching else STAND_EYE, delta * CROUCH_LERP_SPEED)

## Same movement-spread feed as player_instance so the crosshair reacts to
## sprinting/jumping in training too.
func _update_crosshair_spread() -> void:
	var crosshair := get_node_or_null("/root/Crosshair")
	if crosshair == null:
		return
	var ratio: float = clampf(Vector2(velocity.x, velocity.z).length() / sprint_speed, 0.0, 1.0)
	crosshair.set_movement_spread(ratio)
