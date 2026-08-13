extends CanvasLayer
## Full-screen 50% opaque overlay shown while the lobby loads (from launch)
## or during room transitions (create/join/leave/kick). Blocks input via the
## ColorRect's default mouse_filter, so nothing can be clicked mid-transition.

@onready var loading_label: Label = %LoadingLabel

func _ready() -> void:
	add_to_group("loading_overlay")
	visible = false

func show_loading(message: String = "") -> void:
	if message != "":
		loading_label.text = message
	visible = true

func hide_loading() -> void:
	visible = false