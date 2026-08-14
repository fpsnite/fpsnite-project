extends CanvasLayer
## Esc opens a right drawer (slide-in animation) with room code, copy,
## leave and quit. Clicking the dimmed empty space closes it. The tree is
## paused while the drawer is open.

const DRAWER_WIDTH := 380.0

@onready var dim: ColorRect = $Dim
@onready var drawer: PanelContainer = $Drawer
@onready var room_code_label: Label = $Drawer/VBox/RoomCodeLabel

var _open := false
var _tween: Tween

func _ready() -> void:
	visible = false
	room_code_label.text = "ROOM CODE: %s" % Network.room_code()
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dim.color.a = 0.0
	dim.gui_input.connect(_on_dim_gui_input)
	drawer.position.x = _viewport_width() + 10.0
	_refresh_room_code_visibility()
	if Settings.open_drawer_on_return:
		Settings.open_drawer_on_return = false
		call_deferred("set_open", true)

## No reason to show the room code when playing solo: hide the code and the
## copy button while this client is the only one in the room.
func _refresh_room_code_visibility() -> void:
	var alone := true
	var lobby := get_tree().get_first_node_in_group("lobby")
	if lobby and "_characters" in lobby:
		alone = lobby._characters.size() <= 1
	$Drawer/VBox/RoomCodeLabel.visible = not alone
	$Drawer/VBox/CopyCodeButton.visible = not alone

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		set_open(not _open)
		get_viewport().set_input_as_handled()

func _viewport_width() -> float:
	return get_viewport().get_visible_rect().size.x

func set_open(open: bool) -> void:
	_open = open
	visible = open
	if open:
		_refresh_room_code_visibility()
	get_tree().paused = open
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if open else Input.MOUSE_MODE_CAPTURED
	dim.mouse_filter = Control.MOUSE_FILTER_STOP if open else Control.MOUSE_FILTER_IGNORE
	if _tween:
		_tween.kill()
	_tween = create_tween().set_parallel(true)
	_tween.tween_property(drawer, "position:x", (_viewport_width() - DRAWER_WIDTH) if open else (_viewport_width() + 10.0), 0.28) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT if open else Tween.EASE_IN)
	_tween.tween_property(dim, "color:a", 0.55 if open else 0.0, 0.28)
	if open:
		if $Drawer/VBox/CopyCodeButton.visible:
			$Drawer/VBox/CopyCodeButton.grab_focus()
		else:
			$Drawer/VBox/SettingsButton.grab_focus()

func _on_dim_gui_input(event: InputEvent) -> void:
	if _open and event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		set_open(false)

func _on_copy_code_pressed() -> void:
	DisplayServer.clipboard_set(Network.room_code())
	var button := $Drawer/VBox/CopyCodeButton
	button.text = "COPIED!"
	await get_tree().create_timer(1.5).timeout
	if is_inside_tree():
		button.text = "COPY ROOM CODE"

## Opens the settings page; the back button there returns to the game with
## this drawer open again. Must unpause before switching scenes or the new
## scene loads frozen.
func _on_settings_pressed() -> void:
	Settings.return_to_lobby = true
	Settings.open_drawer_on_return = true
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file("res://Scenes/settings_page.tscn")

func _on_leave_pressed() -> void:
	get_tree().paused = false
	Network.leave()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file("res://Scenes/mainui.tscn")

func _on_quit_pressed() -> void:
	get_tree().quit()
