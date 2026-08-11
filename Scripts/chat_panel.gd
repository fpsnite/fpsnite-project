extends Control
## Chat overlay for the game scene. Hidden until T opens it; the panel and
## its input stay open (Enter sends without closing, so you can keep typing)
## until Esc or T closes it. While the chat is open the local player's game
## input (movement, look, spectate) is blocked and the mouse is released so
## the LineEdit works. Messages are broadcast via submit_chat.

const MAX_MESSAGES := 100

var open := false
var _message_count := 0
var _panel_style: StyleBoxFlat

@onready var panel: Panel = $Panel
@onready var history: RichTextLabel = $Panel/VBox/History
@onready var input_edit: LineEdit = $Panel/VBox/InputRow/Input

func _ready() -> void:
	add_to_group("chat")
	Fusion.register_broadcast_receiver(self)
	_panel_style = panel.get_theme_stylebox("panel").duplicate()
	panel.add_theme_stylebox_override("panel", _panel_style)
	history.bbcode_enabled = true
	history.scroll_following = true
	input_edit.text_submitted.connect(_on_submitted)
	input_edit.gui_input.connect(_on_input_gui)
	set_open(false)

func _exit_tree() -> void:
	Fusion.unregister_broadcast_receiver(self)

## Read by player_instance / third_person_camera / spectate to freeze the
## controls while typing.
func is_open() -> bool:
	return open

func toggle() -> void:
	set_open(not open)

func set_open(value: bool) -> void:
	open = value
	panel.visible = open
	input_edit.visible = open
	if open:
		input_edit.grab_focus()
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		_panel_style.bg_color = Color(0.08, 0.1, 0.12, 0.92)
	else:
		input_edit.release_focus()
		_release_mouse()
		_panel_style.bg_color = Color(0.08, 0.1, 0.12, 0.45)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("chat"):
		toggle()
		get_viewport().set_input_as_handled()

## Esc while typing closes the chat (and doesn't open the pause menu).
func _on_input_gui(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		set_open(false)
		get_viewport().set_input_as_handled()

## Enter sends the message but keeps the chat open and keeps the input
## focused; the panel only hides via Esc or T.
func _on_submitted(text: String) -> void:
	var trimmed := text.strip_edges()
	if not trimmed.is_empty() and Fusion.is_in_room():
		Fusion.rpc(submit_chat, Fusion.get_local_player_id(), Network.player_name, trimmed)
	input_edit.clear()
	input_edit.grab_focus()

## Closing the chat hands the mouse back to the local player's camera (only
## while the window is focused, mirroring player_instance._capture_mouse).
func _release_mouse() -> void:
	if not get_window().has_focus():
		return
	var lobby := get_tree().get_first_node_in_group("lobby")
	if lobby == null:
		return
	var character: Node = lobby._characters.get(Fusion.get_local_player_id())
	if character and character.replicator.has_input_authority():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

@rpc("any_peer", "call_local")
func submit_chat(player_id: int, sender_name: String, text: String) -> void:
	var number := 0
	var lobby := get_tree().get_first_node_in_group("lobby")
	if lobby:
		number = int(lobby._number_registry.get(player_id, 0))
	var prefix := "[#%03d] %s" % [number, sender_name] if not sender_name.is_empty() else "[#%03d]" % number
	append_message(prefix, text)

func append_message(prefix: String, text: String) -> void:
	var safe_text := text.replace("[", "[lb]").replace("]", "[rb]")
	history.append_text("[color=#9be89b]%s[/color] %s\n" % [prefix, safe_text])
	_message_count += 1
	if _message_count > MAX_MESSAGES:
		history.remove_paragraph(0)
		_message_count -= 1
