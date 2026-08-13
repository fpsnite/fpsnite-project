extends Node
## Global toast notifications (autoload "Toasts"). One toast scene instance
## (Scenes/toast.tscn) is created at startup and REUSED for every message:
## only the label text changes. Messages are queued and shown one at a time
## at the top-left, sliding in (left -> right), holding, then sliding out
## (right -> left). Renders on canvas layer 0: above the 3D world, below all
## UI layers, so it never blocks clicks.
## Usage: Toasts.show_message("text")

const ToastScene: PackedScene = preload("res://Scenes/toast.tscn")
const TOAST_LAYER := 0
const MARGIN := 20.0
const HOLD_TIME := 2.5
const SLIDE_TIME := 0.18

var _layer: CanvasLayer
var _toast: PanelContainer
var _label: Label
var _queue: Array[String] = []
var _active := false

func _log(msg: String) -> void:
	print("[TOAST] toasts: " + msg)

func _ready() -> void:
	_layer = CanvasLayer.new()
	_layer.name = "ToastLayer"
	_layer.layer = TOAST_LAYER
	add_child(_layer)
	_toast = ToastScene.instantiate() as PanelContainer
	_layer.add_child(_toast)
	_label = _toast.get_node("ToastLabel") as Label
	_toast.visible = false
	_log("toast layer ready (layer=%d)" % TOAST_LAYER)

func show_message(message: String) -> void:
	_queue.append(message)
	_log("toast queued (%d pending): '%s'" % [_queue.size(), message])
	_pump()

func _pump() -> void:
	if _active or _queue.is_empty():
		return
	_active = true
	var message: String = _queue.pop_front()
	_log("toast showing (%d pending): '%s'" % [_queue.size(), message])
	_label.text = message
	_toast.visible = true
	await get_tree().process_frame
	_toast.position = Vector2(-_toast.size.x, MARGIN)
	await _slide_to(Vector2(MARGIN, MARGIN))
	await get_tree().create_timer(HOLD_TIME).timeout
	await _slide_to(Vector2(-_toast.size.x, MARGIN))
	_toast.visible = false
	_active = false
	_pump()

func _slide_to(target: Vector2) -> void:
	var tw := create_tween()
	tw.tween_property(_toast, "position", target, SLIDE_TIME)
	tw.set_trans(Tween.TRANS_QUAD)