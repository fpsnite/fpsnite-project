extends CanvasLayer
## World-to-screen damage numbers. Pooled labels (no instantiation in hot
## paths), world position -> camera unproject, float up + fade out.

const POOL_SIZE := 24

var _labels: Array[Label] = []
var _cursor := 0

func _ready() -> void:
	add_to_group("damage_numbers")
	for i in POOL_SIZE:
		var label := Label.new()
		label.add_theme_font_size_override("font_size", 26)
		label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
		label.add_theme_constant_override("outline_size", 6)
		label.add_theme_constant_override("shadow_outline_size", 2)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.visible = false
		add_child(label)
		_labels.append(label)

func spawn_number(amount: float, world_position: Vector3, color: Color, big := false) -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var label := _labels[_cursor]
	_cursor = (_cursor + 1) % POOL_SIZE
	label.text = "%d" % roundi(amount)
	label.add_theme_color_override("font_color", color)
	label.add_theme_font_size_override("font_size", 34 if big else 26)
	label.reset_size()
	var screen := camera.unproject_position(world_position)
	var jitter := Vector2(randf_range(-16.0, 16.0), randf_range(-6.0, 6.0))
	label.position = screen - Vector2(label.size.x / 2.0, label.size.y / 2.0) + jitter
	label.visible = true
	label.modulate.a = 1.0
	var tween := label.create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "position:y", label.position.y - 60.0, 0.8) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "modulate:a", 0.0, 0.65) \
		.set_delay(0.15).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.chain().tween_callback(func() -> void:
		label.visible = false
	)
	return