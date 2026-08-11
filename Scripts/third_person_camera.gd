extends Node3D
class_name ThirdPersonCamera
## Fortnite-style third-person camera controller. Attach this script to the
## CameraPivot node (direct child of the player root).
##   PlayerInstance (root, rotates for YAW, network-synced)
##     CameraPivot (this node, rotates for PITCH, at head height)
##       Camera3D (position driven by arm length + shoulder offset)
## Look input only applies to the local player (input authority), so remote
## bodies never fight the replicated rotation.

# --- Tunables -------------------------------------------------------------

@export_group("Sensitivity")
@export var mouse_sensitivity: float = 0.0025
@export var controller_sensitivity: float = 2.5
@export var invert_y: bool = false

@export_group("Pitch Clamping")
@export var min_pitch_deg: float = -60.0  # look down limit
@export var max_pitch_deg: float = 75.0   # look up limit

@export_group("Camera Rig")
@export var shoulder_offset: Vector3 = Vector3(0.5, 0.0, 0.0)  # over-the-shoulder
@export var arm_length: float = 4.0        # default distance behind the pivot
@export var min_arm_length: float = 0.3    # closest the camera gets on collision
@export var camera_height_offset: float = 0.0
@export var position_smoothing: float = 20.0  # higher = snappier follow
@export var rotation_smoothing: float = 25.0

@export_group("Collision")
@export var collision_mask: int = 1
@export var collision_margin: float = 0.2  # padding so the camera doesn't clip

@export_group("Aim / Zoom")
@export var enable_aim_zoom: bool = true
@export var aim_arm_length: float = 1.8
@export var zoom_speed: float = 10.0

# --- Internal state ---------------------------------------------------------

var _yaw: float = 0.0
var _pitch: float = 0.0
var _current_arm_length: float
var _target_arm_length: float
var _is_aiming: bool = false

@onready var _player_root: Node3D = get_parent()
@onready var camera: Camera3D = $Camera3D

func _ready() -> void:
	_target_arm_length = arm_length
	_current_arm_length = arm_length
	_yaw = _player_root.rotation.y

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
		_apply_look_delta(event.relative.x, event.relative.y, mouse_sensitivity)
	if enable_aim_zoom:
		if event.is_action_pressed("aim"):
			_is_aiming = true
		elif event.is_action_released("aim"):
			_is_aiming = false

func _process(delta: float) -> void:
	if _can_control():
		# Controller stick look (polled every frame, not just on input events)
		var look_vec := Input.get_vector("look_left", "look_right", "look_up", "look_down")
		if look_vec != Vector2.ZERO:
			_apply_look_delta(look_vec.x * 100.0, look_vec.y * 100.0, controller_sensitivity * delta * 0.01)
		_target_arm_length = aim_arm_length if _is_aiming else arm_length
	_update_camera(delta)

func _apply_look_delta(dx: float, dy: float, sens: float) -> void:
	_yaw -= dx * sens
	_pitch -= dy * sens * (-1.0 if invert_y else 1.0)
	_pitch = clampf(_pitch, deg_to_rad(min_pitch_deg), deg_to_rad(max_pitch_deg))

func _update_camera(delta: float) -> void:
	# Remote bodies are rotated by the Fusion simulation thread - never touch
	# their transforms here, or the replicated yaw jitters.
	if not _can_control():
		return
	# Yaw rotates the player body, pitch rotates only this pivot.
	var body_rot := _player_root.rotation
	body_rot.y = lerp_angle(body_rot.y, _yaw, 1.0 - exp(-rotation_smoothing * delta))
	_player_root.rotation = body_rot
	rotation.x = lerp_angle(rotation.x, _pitch, 1.0 - exp(-rotation_smoothing * delta))
	rotation.y = 0.0
	rotation.z = 0.0

	# Smoothly interpolate the arm length (zoom / collision).
	_current_arm_length = lerp(_current_arm_length, _resolve_collision_length(), 1.0 - exp(-position_smoothing * delta))

	var desired_local_pos := Vector3(shoulder_offset.x, camera_height_offset, _current_arm_length)
	camera.position = camera.position.lerp(desired_local_pos, 1.0 - exp(-position_smoothing * delta))
	camera.rotation = Vector3.ZERO  # the pivot already handles pitch

func _resolve_collision_length() -> float:
	# Fresh ray query every frame (reacts instantly to arm changes instead of
	# a static RayCast3D node's cached state).
	var from := global_transform.origin + global_transform.basis * Vector3(shoulder_offset.x, camera_height_offset, 0.0)
	var to := global_transform.origin + global_transform.basis * Vector3(shoulder_offset.x, camera_height_offset, _target_arm_length)
	var space_state := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = collision_mask
	query.exclude = [_player_root]  # don't clip against the player's own body
	var result := space_state.intersect_ray(query)
	if result:
		var hit_distance := from.distance_to(result.position)
		return clampf(hit_distance - collision_margin, min_arm_length, _target_arm_length)
	return _target_arm_length
