extends Control
## Settings page: Graphics tab (fps limit, resolution, fullscreen)
## and Keybinds tab (capture a key to rebind). Changes apply immediately.

const ACTIONS := [
	["move_left", "Move Left"],
	["move_right", "Move Right"],
	["move_forward", "Move Forward"],
	["move_back", "Move Back"],
	["sprint", "Sprint"],
	["jump", "Jump"],
	["chat", "Chat"],
]

@onready var fps_option: OptionButton = %FpsOption
@onready var resolution_option: OptionButton = %ResolutionOption
@onready var fullscreen_check: CheckButton = %FullscreenCheck
@onready var scaling_slider: HSlider = %ScalingSlider
@onready var scaling_value_label: Label = %ScalingValueLabel
@onready var keybinds_box: VBoxContainer = %KeybindsBox
@onready var status_label: Label = %StatusLabel

var _awaiting_action := ""
var _keybind_buttons: Dictionary = {}

func _ready() -> void:
	get_tree().paused = false
	_fill_options()
	_build_keybind_rows()
	_load_current_values()

func _fill_options() -> void:
	fps_option.clear()
	fps_option.add_item("Unlimited", 0)
	for fps in [30, 60, 120, 144, 240]:
		fps_option.add_item(str(fps), fps)

	resolution_option.clear()
	for res: Vector2i in [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080), Vector2i(2560, 1440)]:
		resolution_option.add_item("%dx%d" % [res.x, res.y])
		resolution_option.set_item_metadata(resolution_option.item_count - 1, res)

func _load_current_values() -> void:
	fps_option.select(fps_option.get_item_index(Settings.fps_limit))
	var res_index := 0
	for i in resolution_option.item_count:
		if resolution_option.get_item_metadata(i) == Settings.resolution:
			res_index = i
	resolution_option.select(res_index)
	fullscreen_check.set_pressed_no_signal(Settings.fullscreen)
	scaling_slider.set_value_no_signal(Settings.scaling_3d)
	_update_scaling_label(Settings.scaling_3d)

func _build_keybind_rows() -> void:
	for entry: Array in ACTIONS:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 20)
		var label := Label.new()
		label.custom_minimum_size = Vector2(300, 0)
		label.add_theme_font_size_override("font_size", 20)
		label.text = entry[1]
		row.add_child(label)
		var button := Button.new()
		button.custom_minimum_size = Vector2(220, 44)
		button.text = _action_key_name(entry[0])
		button.pressed.connect(_on_keybind_pressed.bind(entry[0]))
		row.add_child(button)
		keybinds_box.add_child(row)
		_keybind_buttons[entry[0]] = button

func _action_key_name(action: String) -> String:
	var events := InputMap.action_get_events(action)
	if events.is_empty():
		return "?"
	var key_event: InputEventKey = events[0]
	return key_event.as_text()

func _on_keybind_pressed(action: String) -> void:
	_awaiting_action = action
	status_label.text = "Press a key for %s... (Esc to cancel)" % action
	status_label.visible = true

func _unhandled_input(event: InputEvent) -> void:
	if _awaiting_action.is_empty():
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var action := _awaiting_action
		_awaiting_action = ""
		var keycode: Key = event.physical_keycode
		if keycode == KEY_ESCAPE:
			status_label.text = "Keybind cancelled."
			return
		Settings.set_keybind(action, keycode)
		_keybind_buttons[action].text = _action_key_name(action)
		status_label.visible = false

func _on_reset_keybinds_pressed() -> void:
	Settings.reset_keybinds()
	for action in _keybind_buttons:
		_keybind_buttons[action].text = _action_key_name(action)
	status_label.visible = false

func _on_fps_option_selected(index: int) -> void:
	Settings.fps_limit = fps_option.get_item_id(index)
	Settings.apply_graphics()
	Settings.save_settings()

func _on_resolution_option_selected(index: int) -> void:
	Settings.resolution = resolution_option.get_item_metadata(index)
	Settings.apply_graphics()
	Settings.save_settings()

func _on_fullscreen_toggled(toggled: bool) -> void:
	Settings.fullscreen = toggled
	Settings.apply_graphics()
	Settings.save_settings()

func _on_scaling_slider_changed(value: float) -> void:
	Settings.scaling_3d = value
	Settings.apply_graphics()
	Settings.save_settings()
	_update_scaling_label(value)

func _update_scaling_label(value: float) -> void:
	scaling_value_label.text = "%.0f%%" % (value * 100.0)

func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://Scenes/mainui.tscn")
