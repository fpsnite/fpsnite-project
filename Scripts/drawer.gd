extends CanvasLayer
## Reusable right slide-in drawer: Esc toggles, clicking the dimmed empty
## space closes it (emits drawer_closed). No pause/mouse logic — menus own that.

signal drawer_closed

const DRAWER_WIDTH := 380.0

@onready var dim: ColorRect = $Dim
@onready var panel: PanelContainer = $Panel

var _open := false
var _tween: Tween

func _ready() -> void:
	set_visible(false)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dim.color.a = 0.0
	dim.gui_input.connect(_on_dim_gui_input)
	panel.position.x = _viewport_width() + 10.0

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		toggle()
		get_viewport().set_input_as_handled()

func _viewport_width() -> float:
	return get_viewport().get_visible_rect().size.x

func toggle() -> void:
	set_open(not _open)

func set_open(open: bool) -> void:
	set_visible(open)
	_open = open
	dim.mouse_filter = Control.MOUSE_FILTER_STOP if open else Control.MOUSE_FILTER_IGNORE
	if _tween:
		_tween.kill()
	_tween = create_tween().set_parallel(true)
	_tween.tween_property(panel, "position:x", (_viewport_width() - DRAWER_WIDTH) if open else (_viewport_width() + 10.0), 0.28) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT if open else Tween.EASE_IN)
	_tween.tween_property(dim, "color:a", 0.55 if open else 0.0, 0.28)
	if open:
		$Panel/VBox/QuitButton.grab_focus()

func _on_dim_gui_input(event: InputEvent) -> void:
	if _open and event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		set_open(false)
		drawer_closed.emit()

func _on_quit_pressed() -> void:
	get_tree().quit()
