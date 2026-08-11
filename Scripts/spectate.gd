extends Node3D
## Spectate mode: H toggles it. Hides your own body (locally), freezes your
## input, and follows the selected player with a dedicated camera.
## Prev/next buttons cycle through the other players in the room.

var _active := false
var _target_ids: Array = []
var _target_index := 0

@onready var camera: Camera3D = $SpectateCamera
@onready var ui: CanvasLayer = get_node("../SpectateUI")
@onready var spectate_label: Label = ui.get_node("TopBox/SpectateLabel")
@onready var name_label: Label = ui.get_node("TopBox/PlayerNameLabel")

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("spectate"):
		var chat := get_tree().get_first_node_in_group("chat")
		if chat and chat.is_open():
			return
		toggle_spectate()

func _process(delta: float) -> void:
	if not _active:
		return
	var round_node := get_tree().get_first_node_in_group("round")
	if not _target_ids.is_empty() and round_node and round_node.eliminated.has(_target_ids[_target_index % _target_ids.size()]):
		_cycle(1)
		return
	var target := current_target()
	if target == null:
		_stop()
		return
	var desired: Vector3 = target.global_position + Vector3(0.0, 2.4, 3.4)
	camera.global_position = camera.global_position.lerp(desired, 1.0 - exp(-8.0 * delta))
	camera.look_at(target.global_position + Vector3(0.0, 1.1, 0.0))
	name_label.text = target.get_node("PlayerNameLabel").text

# --- Public API (UI buttons) ---

func toggle_spectate() -> void:
	if _active:
		_stop()
	else:
		_rebuild_targets()
		if _target_ids.is_empty():
			return
		_target_index = 0
		_start()

func spectate_prev() -> void:
	_cycle(-1)

func spectate_next() -> void:
	_cycle(1)

# --- Internals ---

func _cycle(step: int) -> void:
	if not _active:
		return
	_rebuild_targets()
	if _target_ids.is_empty():
		_stop()
		return
	_target_index = (_target_index + step) % _target_ids.size()
	if _target_index < 0:
		_target_index += _target_ids.size()

## Cycle targets are the players still in the match - eliminated players are
## skipped so spectating only follows survivors.
func _rebuild_targets() -> void:
	_target_ids.clear()
	var lobby := get_tree().get_first_node_in_group("lobby")
	if lobby == null:
		return
	var round_node := get_tree().get_first_node_in_group("round")
	var local_pid := Fusion.get_local_player_id()
	for pid in lobby._characters:
		if pid != local_pid:
			if round_node and round_node.eliminated.has(pid):
				continue
			_target_ids.append(pid)

func _start() -> void:
	_active = true
	_hide_local_body(true)
	camera.current = true
	ui.visible = true
	spectate_label.text = "SPECTATING"
	name_label.text = ""

func _stop() -> void:
	_active = false
	_hide_local_body(false)
	camera.current = false
	_restore_local_camera()
	ui.visible = false

func _hide_local_body(hidden: bool) -> void:
	var player := _local_player()
	if player == null:
		return
	player.spectating = hidden
	player.get_node("MeshPivot").visible = not hidden
	player.get_node("PlayerNameLabel").visible = not hidden

func _restore_local_camera() -> void:
	var player := _local_player()
	if player == null:
		return
	var cam: Camera3D = player.get_node("CameraPivot/Camera3D")
	cam.current = true

func _local_player() -> Node:
	var lobby := get_tree().get_first_node_in_group("lobby")
	if lobby == null:
		return null
	return lobby._characters.get(Fusion.get_local_player_id())

func current_target() -> Node:
	var lobby := get_tree().get_first_node_in_group("lobby")
	if lobby == null or _target_ids.is_empty():
		return null
	return lobby._characters.get(_target_ids[_target_index % _target_ids.size()])
