extends PanelContainer
class_name ModeCard

signal selected(mode_id: String)

@export var mode_id: String
@export var mode_name: String
@export var thumbnail: Texture2D


var is_selected: bool = false

func _ready() -> void:
	%GameModeText.text = mode_name
	#get_theme_stylebox("panel").set_texture(thumbnail)
	gui_input.connect(_on_gui_input)
	set_selected(false)

func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		print("ModeCard clicked: %s" % mode_id)
		selected.emit(mode_id)

func set_selected(value: bool) -> void:
	is_selected = value
	# swap stylebox for the white border look
	var style :StyleBox = get_theme_stylebox("panel").duplicate()
	style.border_color = Color.WHITE if value else Color(1, 1, 1, 0.15)
	style.border_width_left = 3 if value else 1
	style.border_width_right = 3 if value else 1
	style.border_width_top = 3 if value else 1
	style.border_width_bottom = 3 if value else 1
	add_theme_stylebox_override("panel", style)
