extends Node
## Main menu for Red Light Green Light multiplayer (Photon Fusion).
## Create room = host; join room = enter the 5-character code.

@onready var player_name_edit: LineEdit = %PlayerNameEdit
@onready var room_code_edit: LineEdit = %RoomCodeEdit
@onready var join_panel: VBoxContainer = %JoinPanel
@onready var status_label: Label = %StatusLabel
@onready var preview: Node3D = get_node("PlayerPreview")

var _creating := false
var _join_code := ""

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_node("Drawer").toggle()
		get_viewport().set_input_as_handled()

func _ready() -> void:
	get_tree().paused = false
	Network.connected_to_photon.connect(_on_connected_to_photon)
	Network.connection_failed.connect(_on_connection_failed)
	Network.room_joined.connect(_on_room_joined)
	player_name_edit.text_changed.connect(func(_text: String) -> void: _update_preview_name())
	get_node("SkinPicker").skin_chosen.connect(_on_skin_chosen)
	if Settings.player_name.is_empty():
		Settings.player_name = "Player %06d" % randi_range(0, 999999)
		Settings.save_settings()
	player_name_edit.text = Settings.player_name
	Network.player_name = Settings.player_name
	_update_preview_name()
	if not Network.lost_message.is_empty():
		status_label.text = Network.lost_message
		Network.lost_message = ""

func _update_preview_name() -> void:
	var name_text := player_name_edit.text.strip_edges()
	preview.update_name(name_text if not name_text.is_empty() else "YOUR NAME")

func _on_skin_chosen(index: int) -> void:
	preview.apply_skin(index)

func _on_create_room_pressed() -> void:
	if not _valid_name():
		return
	_creating = true
	status_label.text = "Connecting to Photon..."
	Network.connect_to_photon()

func _on_join_room_pressed() -> void:
	join_panel.visible = not join_panel.visible
	if join_panel.visible:
		room_code_edit.grab_focus()

func _on_join_pressed() -> void:
	if not _valid_name():
		return
	_join_code = room_code_edit.text.strip_edges().to_upper()
	if _join_code.length() != 5:
		status_label.text = "Enter the 5-character room code."
		return
	status_label.text = "Connecting to Photon..."
	Network.connect_to_photon()

func _on_connected_to_photon() -> void:
	if _creating:
		var code := Network.random_code()
		status_label.text = "Hosting room %s - share this code!" % code
		Network.create_room(code)
	else:
		status_label.text = "Joining room %s..." % _join_code
		Network.join_room(_join_code)
		_join_timeout()

func _join_timeout() -> void:
	await get_tree().create_timer(10.0).timeout
	if not is_inside_tree():
		return
	if not Fusion.is_in_room():
		status_label.text = "Room not found."

func _on_room_joined() -> void:
	if _name_taken_in_room():
		status_label.text = "That username is already in this room."
		Network.leave()
		return
	status_label.text = "Entering lobby..."
	get_tree().change_scene_to_file("res://Scenes/lobby.tscn")

## Rejects the join if another player in the room already uses this username
## (case-insensitive). The host can never collide: they join an empty room.
func _name_taken_in_room() -> bool:
	if not Fusion.is_in_room():
		return false
	var my_name := Network.player_name.strip_edges().to_lower()
	for p in Fusion.get_room().get_players():
		if p.get_number() == Fusion.get_local_player_id():
			continue
		if p.get_name().strip_edges().to_lower() == my_name:
			return true
	return false

func _on_connection_failed(reason: String) -> void:
	if not Network.lost_message.is_empty():
		status_label.text = Network.lost_message
	else:
		status_label.text = "Connection failed: %s" % reason
	_creating = false

func _on_settings_pressed() -> void:
	get_tree().change_scene_to_file("res://Scenes/settings_page.tscn")

func _valid_name() -> bool:
	var name_text := player_name_edit.text.strip_edges()
	if name_text.is_empty():
		name_text = "Player %06d" % randi_range(0, 999999)
		player_name_edit.text = name_text
	Network.player_name = name_text
	if Settings.player_name != name_text:
		Settings.player_name = name_text
		Settings.save_settings()
	status_label.text = ""
	return true
