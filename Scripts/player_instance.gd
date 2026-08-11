extends CharacterBody3D
## Networked third-person controller (Fusion Client-Server, PLAYER_PREDICTED).
## Movement runs in on_process_input on both the predicting client and the server.

@export var walk_speed := 5.0
@export var sprint_speed := 9.0
@export var jump_velocity := 5.0
@export var sprint_fov := 85.0

const STAMINA_DRAIN := 30.0
const STAMINA_REGEN := 25.0
const STAMINA_LOCK_MIN := 20.0
## Stronger than the project's default gravity: snappier, realistic jumps -
## quicker rise and a faster return to the floor.
const JUMP_GRAVITY := 14.0

@onready var replicator: FusionServerReplicator = $FusionServerReplicator
@onready var mesh_pivot: Node3D = $MeshPivot
@onready var camera_3d: Camera3D = $CameraPivot/Camera3D
@onready var player_name_label: Label3D = $PlayerNameLabel
@onready var back_bling_label: Label3D = $BackBlingLabel

var player_id := 0
var spectating := false
var player_number := 0  # assigned by the lobby master, 000-456
var speed_scale := 1.0  # per-round difficulty multiplier set by the lobby

var _prev_jump_pressed := false
var _round: Node
var _base_fov := 75.0
var _current_fov := 75.0
var _sprint_active := false
var _sprint_locked := false

## HUD state, driven on the main thread, read by player_hud.
var stamina := 100.0

func _ready() -> void:
	_round = get_tree().get_first_node_in_group("round")
	_base_fov = camera_3d.fov
	_current_fov = camera_3d.fov
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
	if replicator.has_input_authority() and not spectating and not _chat_open():
		var target_fov := sprint_fov if _sprint_active else _base_fov
		_current_fov = lerpf(_current_fov, target_fov, 1.0 - exp(-10.0 * delta))
		camera_3d.fov = _current_fov

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
		_sprint_active = _can_sprint()
		if _sprint_active:
			stamina = maxf(stamina - STAMINA_DRAIN * delta, 0.0)
			if stamina <= 0.0:
				_sprint_active = false
				_sprint_locked = true
		else:
			stamina = minf(stamina + STAMINA_REGEN * delta, 100.0)
		replicator.queue_input(delta, _create_input())
	replicator.process_input_queue(delta)

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
	buf.resize(14)
	var input_dir := Vector2.ZERO
	if not spectating and not _chat_open():
		input_dir = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	buf.encode_float(0, input_dir.x)
	buf.encode_float(4, input_dir.y)
	buf.encode_float(8, rotation.y)
	buf.encode_u8(12, 1 if _sprint_active else 0)
	var jump_pressed := Input.is_action_pressed("jump")
	buf.encode_u8(13, 1 if jump_pressed and not _prev_jump_pressed else 0)
	_prev_jump_pressed = jump_pressed
	return buf

func _on_process_input(tick: int, delta_time: float, payload: PackedByteArray, is_new: bool) -> void:
	if payload.size() < 14:
		return
	var input_dir := Vector2(payload.decode_float(0), payload.decode_float(4))
	rotation.y = payload.decode_float(8)
	var sprinting := payload.decode_u8(12) == 1
	var jump_press := payload.decode_u8(13) == 1

	var speed := (sprint_speed if sprinting else walk_speed) * speed_scale
	var direction := transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)
	direction.y = 0.0
	direction = direction.normalized() if direction.length_squared() > 0.0 else Vector3.ZERO

	## Runs on the Fusion simulation thread on the server - never touch the
	## scene tree here (get_tree/group lookups) or the main thread deadlocks.
	if not is_on_floor():
		velocity.y -= JUMP_GRAVITY * delta_time
	elif jump_press:
		velocity.y = jump_velocity

	if direction:
		velocity.x = direction.x * speed
		velocity.z = direction.z * speed
	else:
		velocity.x = move_toward(velocity.x, 0.0, speed)
		velocity.z = move_toward(velocity.z, 0.0, speed)

	move_and_slide()

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
	back_bling_label.text = _format_number(number)

func _format_number(number: int) -> String:
	return "%03d" % number

# --- Elimination (driven by game_round via broadcast RPCs) ---

## Killed by the doll during red light: the body disappears locally and the
## owner is auto-put into spectate mode if the scene has a SpectateManager.
func become_eliminated() -> void:
	spectating = true
	mesh_pivot.visible = false
	player_name_label.visible = false
	back_bling_label.visible = false

## Next round: alive again (mesh restored, input allowed). If the local
## player was spectating, game_round stops the spectate mode for them.
func become_alive() -> void:
	spectating = false
	mesh_pivot.visible = true
	player_name_label.visible = true
	back_bling_label.visible = true
