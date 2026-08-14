extends CharacterBody3D
## Networked FPS controller (Fusion Client-Server, PLAYER_PREDICTED).
## Movement runs in on_process_input on both the predicting client and the server.
## The local player's body is hidden (first-person view) - only remote
## players render their bodies.

@export var walk_speed := 5.0
@export var sprint_speed := 9.0
@export var jump_velocity := 5.0

const STAMINA_DRAIN := 30.0
const STAMINA_REGEN := 25.0
const STAMINA_LOCK_MIN := 20.0
## Stronger than the project's default gravity: snappier, realistic jumps -
## quick rise and a fast return to the floor (no "moon" floatiness).
const JUMP_GRAVITY := 22.0

## CS:GO / Source-engine style acceleration model.
## Ground: accelerate toward max speed, friction stops you when idle.
## Air: accel is intentionally low -> this is what produces "air strafing".
const GROUND_ACCEL := 14.0
const GROUND_FRICTION := 10.0
const AIR_ACCEL := 2.2
## Caps how much speed you can gain from air-strafe input per frame.
const AIR_CAP := 0.85

## Crouch: lerped capsule height (no popping), slower speed, lower eye.
const CROUCH_SPEED := 2.5
const STAND_HEIGHT := 2.0
const CROUCH_HEIGHT := 1.0
const STAND_EYE := 1.6
const CROUCH_EYE := 0.9
const CROUCH_LERP_SPEED := 10.0

@onready var replicator: FusionServerReplicator = $FusionServerReplicator
@onready var mesh_pivot: Node3D = $MeshPivot
@onready var camera_3d: Camera3D = $CameraPivot/Camera3D
@onready var camera_pivot: Node3D = $CameraPivot
@onready var collision_shape: CollisionShape3D = $CollisionShape3D
@onready var body_hitbox: Area3D = $BodyHitbox
@onready var head_hitbox: Area3D = $HeadHitbox
@onready var player_name_label: Label3D = $PlayerNameLabel
@onready var back_bling_label: Label3D = $BackBlingLabel if has_node("BackBlingLabel") else null

var player_id := 0
var spectating := false
var player_number := 0  # assigned by the lobby master, 000-456
var speed_scale := 1.0  # per-round difficulty multiplier set by the lobby

## Combat state, written by the server (WeaponSystem) via sync_health.
var health := 100.0
## Shield absorbs damage before health; written by the server like health.
var shield := 100.0

## Crouch state, written by the Fusion sim callback (from the input payload)
## on both the predicting client and the server, so everyone agrees. The
## main thread lerps the capsule/eye/hitboxes toward this flag.
var crouching := false

var _prev_jump_pressed := false
var _round: Node
var sprint_active := false  # read by FirstPersonCamera for the sprint FOV
var _sprint_locked := false

## HUD state, driven on the main thread, read by player_hud.
var stamina := 100.0

func _ready() -> void:
	_round = get_tree().get_first_node_in_group("round")
	replicator.spawned.connect(_on_replicator_spawned)
	replicator.on_process_input.connect(_on_process_input)
	get_window().focus_entered.connect(_on_window_focused)

func _on_window_focused() -> void:
	if replicator.has_input_authority():
		_capture_mouse()

## If the window loses focus while the mouse is captured, the cursor turns
## invisible on Windows and the game stops receiving input (frozen, Esc dead).
## Release capture while unfocused so the player can always click back in.
func _process(delta: float) -> void:
	if not get_window().has_focus() and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

## Sprinting is disabled once stamina hits 0 and stays locked until the bar
## regens to STAMINA_LOCK_MIN, so the speed/FOV don't stutter at low values.
func _can_sprint() -> bool:
	if _sprint_locked and stamina < STAMINA_LOCK_MIN:
		return false
	if stamina <= 0.0:
		_sprint_locked = true
		return false
	if stamina >= STAMINA_LOCK_MIN:
		_sprint_locked = false
	return Input.is_action_pressed("sprint")

func _physics_process(delta: float) -> void:
	if replicator.has_input_authority():
		if not spectating and not camera_3d.current:
			camera_3d.current = true
		sprint_active = _can_sprint()
		if sprint_active:
			stamina = maxf(stamina - STAMINA_DRAIN * delta, 0.0)
			if stamina <= 0.0:
				sprint_active = false
				_sprint_locked = true
		else:
			stamina = minf(stamina + STAMINA_REGEN * delta, 100.0)
		replicator.queue_input(delta, _create_input())
	replicator.process_input_queue(delta)
	_update_crouch(delta)
	if replicator.has_input_authority():
		_update_crosshair_spread()

func _unhandled_input(event: InputEvent) -> void:
	if not replicator.has_input_authority():
		return
	if event is InputEventMouseButton and event.pressed and not _chat_open():
		_capture_mouse()

# --- Fusion lifecycle ---

func _on_replicator_spawned() -> void:
	refresh_identity()

func refresh_identity() -> void:
	player_id = replicator.get_input_authority()
	if player_id <= 0:
		player_id = Fusion.get_local_player_id()
	if replicator.has_input_authority():
		Network.last_log = "player %d: input authority granted" % player_id
		print("[NET] player %d: input authority granted, initializing camera/skin" % player_id)
		camera_3d.current = true
		_capture_mouse()
		player_name_label.text = Network.player_name
		# First-person view: never render your own body (remote players still
		# see it, since visibility is only hidden locally).
		mesh_pivot.visible = false
		player_name_label.visible = false
		if back_bling_label:
			back_bling_label.visible = false
		_submit_skin(Settings.skin_index)
	else:
		camera_3d.current = false
		player_name_label.text = _remote_player_name()

## Capturing the mouse while the window is unfocused silently fails and then
## no input events arrive (the cursor is hidden but not captured) - the game
## feels frozen. Only capture when focused, and re-capture on focus.
func _capture_mouse() -> void:
	if _chat_open():
		return
	if get_window().has_focus():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _remote_player_name() -> String:
	for p in Fusion.get_room().get_players():
		if p.get_number() == player_id:
			var name: String = p.get_name()
			if name.is_empty():
				name = p.get_user_id()
			if name.is_empty():
				name = "Player %06d" % (player_id * 48271 % 1000000)
			return name
	return "?"

## True while the chat input is open - game controls are frozen then.
func _chat_open() -> bool:
	var chat := get_tree().get_first_node_in_group("chat")
	return chat != null and chat.is_open()

# --- Input ---

func _create_input() -> PackedByteArray:
	var buf := PackedByteArray()
	buf.resize(15)
	var input_dir := Vector2.ZERO
	if not spectating and not _chat_open():
		input_dir = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	buf.encode_float(0, input_dir.x)
	buf.encode_float(4, input_dir.y)
	buf.encode_float(8, rotation.y)
	buf.encode_u8(12, 1 if sprint_active else 0)
	var jump_pressed := Input.is_action_pressed("jump")
	buf.encode_u8(13, 1 if jump_pressed and not _prev_jump_pressed else 0)
	_prev_jump_pressed = jump_pressed
	buf.encode_u8(14, 1 if Input.is_action_pressed("crouch") else 0)
	return buf

func _on_process_input(tick: int, delta_time: float, payload: PackedByteArray, is_new: bool) -> void:
	if payload.size() < 15:
		return
	var input_dir := Vector2(payload.decode_float(0), payload.decode_float(4))
	rotation.y = payload.decode_float(8)
	var sprinting := payload.decode_u8(12) == 1
	var jump_press := payload.decode_u8(13) == 1
	crouching = payload.decode_u8(14) == 1

	# CS:GO / Source-engine acceleration model. Deterministic math only - this
	# runs on the Fusion simulation thread on both the predicting client and
	# the server, so never touch the scene tree here.
	var speed := (CROUCH_SPEED if crouching else (sprint_speed if sprinting else walk_speed)) * speed_scale
	var wish_dir := (transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()

	if not is_on_floor():
		velocity.y -= JUMP_GRAVITY * delta_time
	elif jump_press:
		velocity.y = jump_velocity

	if is_on_floor():
		# Friction runs every ground tick (not just when idle) - this is what
		# keeps velocity aligned with the wish direction. Without it, any
		# small yaw/view mismatch accumulates as lateral drift while moving.
		_apply_ground_friction(delta_time)
		if input_dir != Vector2.ZERO:
			_accelerate(wish_dir, speed, GROUND_ACCEL, delta_time)
	else:
		# Low air accel + per-frame cap = the classic air-strafe feel.
		_accelerate(wish_dir, speed, AIR_ACCEL, delta_time, AIR_CAP)

	move_and_slide()

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
## the target speed. Scaled by how much you're already moving that way - this
## is what makes strafe-jumping/air-strafing work.
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

## Main-thread crouch presentation: lerp the capsule height (feet stay
## anchored), the eye height, and the body/head hitboxes so hitscan matches
## the visual body. Driven by the `crouching` flag the sim thread writes.
## On the master this runs for every player (their payloads set the flag);
## on plain clients only the local body matters for rendering.
func _update_crouch(delta: float) -> void:
	var shape := collision_shape.shape as CapsuleShape3D
	if shape:
		var target_h := CROUCH_HEIGHT if crouching else STAND_HEIGHT
		shape.height = lerpf(shape.height, target_h, delta * CROUCH_LERP_SPEED)
		collision_shape.position.y = -1.0 + shape.height / 2.0
	camera_pivot.position.y = lerpf(camera_pivot.position.y,
		CROUCH_EYE if crouching else STAND_EYE, delta * CROUCH_LERP_SPEED)
	body_hitbox.scale.y = lerpf(body_hitbox.scale.y, 0.6 / 1.4, delta * CROUCH_LERP_SPEED)
	body_hitbox.position.y = lerpf(body_hitbox.position.y, -0.7, delta * CROUCH_LERP_SPEED)
	head_hitbox.scale.y = lerpf(head_hitbox.scale.y, 0.25 / 0.454, delta * CROUCH_LERP_SPEED)
	head_hitbox.position.y = lerpf(head_hitbox.position.y, -0.6, delta * CROUCH_LERP_SPEED)

## Feeds the Crosshair autoload with the current movement speed ratio so the
## crosshair gap widens while moving, like CS:GO.
func _update_crosshair_spread() -> void:
	var crosshair := get_node_or_null("/root/Crosshair")
	if crosshair == null:
		return
	var ratio: float = clampf(Vector2(velocity.x, velocity.z).length() / sprint_speed, 0.0, 1.0)
	crosshair.set_movement_spread(ratio)

# --- Visual sync (broadcast RPCs) ---

func _submit_skin(index: int) -> void:
	apply_skin(index)
	var lobby := get_tree().get_first_node_in_group("lobby")
	if lobby:
		Fusion.rpc(lobby.submit_skin, player_id, index)

func apply_skin(index: int) -> void:
	var material := Skins.material_at(index)
	if material == null:
		return
	for child in mesh_pivot.get_children():
		if child is MeshInstance3D:
			child.material_override = material

## Shows the player's number on their back bling and exposes it to the HUD.
## Always 3 digits: 7 -> "007", 42 -> "042", 456 -> "456".
func apply_number(number: int) -> void:
	player_number = number
	if back_bling_label:
		back_bling_label.text = _format_number(number)

func _format_number(number: int) -> String:
	return "%03d" % number

# --- Elimination (driven by game_round via broadcast RPCs) ---

## Killed by the doll during red light: the body disappears locally and the
## owner is auto-put into spectate mode if the scene has a SpectateManager.
func become_eliminated() -> void:
	spectating = true
	_set_body_visible(false)

## Killed by weapon fire (server-driven). Body hidden, collisions dropped so
## dead players neither block movement nor eat bullets; the local player's
## viewmodel is hidden too. Respawn handled by WeaponSystem.
func become_dead() -> void:
	spectating = true
	_set_body_visible(false)
	set_deferred("collision_layer", 0)
	_weapon_visible(false)

## Next round: alive again (mesh restored, input allowed). If the local
## player was spectating, game_round stops the spectate mode for them.
func become_alive() -> void:
	spectating = false
	_set_body_visible(true)
	set_deferred("collision_layer", 1)
	_weapon_visible(true)

## Teleport + revive, driven by the server's broadcast_respawn.
func respawn_at(position: Vector3, rotation_y: float) -> void:
	global_position = position
	rotation.y = rotation_y
	become_alive()

func _weapon_visible(visible_flag: bool) -> void:
	if not replicator.has_input_authority():
		return
	var weapon := get_node_or_null("CameraPivot/Weapon")
	if weapon:
		weapon.visible = visible_flag

## Local FPS players never see their own body - not even when spectate mode
## stops and tries to restore it. Remote bodies are always visible.
func _set_body_visible(visible_flag: bool) -> void:
	var hidden := not visible_flag
	if replicator.has_input_authority():
		hidden = true
	mesh_pivot.visible = not hidden
	player_name_label.visible = not hidden
	if back_bling_label:
		back_bling_label.visible = not hidden
