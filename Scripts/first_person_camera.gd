extends Node3D
class_name FirstPersonCamera
## FPS camera controller. Attach this script to the CameraPivot node (direct
## child of the player root, positioned at eye height).
##   PlayerInstance (root, rotates for YAW, network-synced)
##     CameraPivot (this node, rotates for PITCH)
##       Camera3D (held at origin + head bob; FOV driven here)
## Look input only applies to the local player (input authority), so remote
## bodies never fight the replicated rotation. The player's own body is
## hidden by player_instance.gd - only other players are visible.

# --- Tunables -------------------------------------------------------------

@export_group("Sensitivity")
## Hipfire sensitivity lives in Settings (Settings > Controls tab) along with
## per-axis (sens_x/sens_y) and ADS multipliers; controller sens stays here.
@export var controller_sensitivity: float = 2.5
@export var invert_y: bool = false

@export_group("Pitch Clamping")
@export var min_pitch_deg: float = -85.0  # look down limit
@export var max_pitch_deg: float = 85.0   # look up limit

@export_group("Field of View")
@export var base_fov: float = 75.0
@export var sprint_fov: float = 85.0
@export var aim_fov: float = 55.0
@export var fov_smoothing: float = 10.0

@export_group("Head Bob")
@export var head_bob_amount: float = 0.045
@export var head_bob_speed: float = 9.0
@export var head_bob_smoothing: float = 12.0

# --- Internal state ---------------------------------------------------------

var _yaw: float = 0.0
var _pitch: float = 0.0
var _is_aiming: bool = false
var _bob_time: float = 0.0
var _bob_current: float = 0.0

@onready var _player_root: Node3D = get_parent()
@onready var camera: Camera3D = $Camera3D

func _ready() -> void:
	_yaw = _player_root.rotation.y
	camera.fov = base_fov

func _can_control() -> bool:
	var rep := _player_root.get_node_or_null("FusionServerReplicator")
	if rep != null and not rep.has_input_authority():
		return false
	var chat := get_tree().get_first_node_in_group("chat")
	if chat and chat.is_open():
		return false
	return true

func _unhandled_input(event: InputEvent) -> void:
	if not _can_control():
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var sens := Settings.mouse_sensitivity
		if _is_aiming:
			sens *= Settings.ads_sensitivity_multiplier
		_apply_look_delta(event.relative.x, event.relative.y, sens,
			Settings.sens_x, Settings.sens_y)
	if event.is_action_pressed("aim"):
		_is_aiming = true
	elif event.is_action_released("aim"):
		_is_aiming = false

func _process(delta: float) -> void:
	if _can_control():
		# Controller stick look (polled every frame, not just on input events)
		var look_vec := Input.get_vector("look_left", "look_right", "look_up", "look_down")
		if look_vec != Vector2.ZERO:
			var sens := controller_sensitivity * delta * 0.01
			if _is_aiming:
				sens *= Settings.ads_sensitivity_multiplier
			_apply_look_delta(look_vec.x * 100.0, look_vec.y * 100.0, sens,
				Settings.sens_x, Settings.sens_y)
	_update_view(delta)

func _apply_look_delta(dx: float, dy: float, sens: float,
		sens_x: float = 1.0, sens_y: float = 1.0) -> void:
	_yaw -= dx * sens * sens_x
	_pitch -= dy * sens * sens_y * (-1.0 if invert_y else 1.0)
	_pitch = clampf(_pitch, deg_to_rad(min_pitch_deg), deg_to_rad(max_pitch_deg))

func _update_view(delta: float) -> void:
	# Remote bodies are rotated by the Fusion simulation thread - never touch
	# their transforms here, or the replicated yaw jitters.
	if not _can_control():
		return
	# Yaw rotates the player body, pitch rotates only this pivot.
	var body_rot := _player_root.rotation
	body_rot.y = lerp_angle(body_rot.y, _yaw, 1.0 - exp(-25.0 * delta))
	_player_root.rotation = body_rot
	rotation.x = lerp_angle(rotation.x, _pitch, 1.0 - exp(-25.0 * delta))
	rotation.y = 0.0
	rotation.z = 0.0

	_update_fov(delta)
	_update_head_bob(delta)

func _update_fov(delta: float) -> void:
	var sprint := false
	if _player_root.get("sprint_active") is bool:
		sprint = _player_root.sprint_active
	var target_fov := aim_fov if _is_aiming else (sprint_fov if sprint else base_fov)
	camera.fov = lerpf(camera.fov, target_fov, 1.0 - exp(-fov_smoothing * delta))

func _update_head_bob(delta: float) -> void:
	var body := _player_root as CharacterBody3D
	var h_speed := Vector2(body.velocity.x, body.velocity.z).length()
	if body.is_on_floor() and h_speed > 0.5:
		_bob_time += delta * head_bob_speed * clampf(h_speed / 5.0, 0.5, 2.0)
		var bob_target := 1.0
		_bob_current = lerpf(_bob_current, bob_target, 1.0 - exp(-head_bob_smoothing * delta))
	else:
		_bob_current = lerpf(_bob_current, 0.0, 1.0 - exp(-head_bob_smoothing * delta))
	var bob := head_bob_amount * _bob_current
	camera.position = Vector3(sin(_bob_time * 2.0) * bob * 0.5, sin(_bob_time) * bob, 0.0)