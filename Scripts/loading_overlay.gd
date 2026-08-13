extends CanvasLayer
## Full-screen 50% opaque overlay shown while the lobby loads (from launch)
## or during room transitions (create/join/leave/kick). Fades in/out over
## FADE_TIME; input is blocked for the whole fade because the Shade's default
## mouse_filter is STOP, and is only released once the fade-out completes.

const FADE_TIME := 0.25

@onready var shade: ColorRect = %Shade
@onready var loading_label: Label = %LoadingLabel

var _fade_tween: Tween

func _ready() -> void:
	add_to_group("loading_overlay")
	shade.modulate = Color(1, 1, 1, 0)
	loading_label.modulate = Color(1, 1, 1, 0)
	visible = false

func show_loading(message: String = "") -> void:
	if message != "":
		loading_label.text = message
	visible = true
	_fade_to(1.0)

func hide_loading() -> void:
	_fade_to(0.0, true)

## Tweens shade + label alpha to the target. When fading out, the layer is
## hidden (input unblocked) only after the fade completes; a new show while
## fading replaces the tween, so the overlay never pops mid-transition.
func _fade_to(alpha: float, hide_at_end := false) -> void:
	if _fade_tween and _fade_tween.is_valid():
		_fade_tween.kill()
	_fade_tween = create_tween()
	_fade_tween.set_trans(Tween.TRANS_SINE)
	_fade_tween.set_ease(Tween.EASE_IN_OUT)
	_fade_tween.tween_property(shade, "modulate:a", alpha, FADE_TIME)
	_fade_tween.parallel().tween_property(loading_label, "modulate:a", alpha, FADE_TIME)
	if hide_at_end:
		_fade_tween.tween_callback(_on_fade_out_finished)

func _on_fade_out_finished() -> void:
	visible = false