extends CanvasLayer
## Kill feed: recent match events (joins, leaves, kills, headshots, respawns)
## stacked on the right side. Newest line goes on top, and each line fades
## out a few seconds after it appears.

const MAX_LINES := 6
const HOLD_TIME := 5.0
const FADE_TIME := 1.5

@onready var box: VBoxContainer = $Root/Box

func _ready() -> void:
	add_to_group("kill_feed")

## kind: "joined", "left", "kill", "headshot", "respawn".
## "kill"/"headshot" additionally take the victim's player id.
func add_event(kind: StringName, player_id: int, target_id: int = 0) -> void:
	var prefix := _prefix_for(player_id)
	match kind:
		&"joined":
			_add_line("%s joined the room" % prefix, Color(0.6, 0.9, 0.65))
		&"left":
			_add_line("%s left the room" % prefix, Color(0.75, 0.75, 0.75))
		&"kill":
			_add_line("%s killed %s" % [prefix, _prefix_for(target_id)], Color(1.0, 0.85, 0.3))
		&"headshot":
			_add_line("%s HEADSHOT %s" % [prefix, _prefix_for(target_id)], Color(1.0, 0.45, 0.3))
		&"respawn":
			_add_line("%s respawned" % prefix, Color(0.55, 0.85, 1.0))

func _prefix_for(player_id: int) -> String:
	var number := 0
	var lobby := get_tree().get_first_node_in_group("lobby")
	if lobby:
		number = int(lobby._number_registry.get(player_id, 0))
	return "[#%03d]" % number

func _add_line(text: String, color: Color) -> void:
	while box.get_child_count() >= MAX_LINES:
		var oldest := box.get_child(box.get_child_count() - 1)
		box.remove_child(oldest)
		oldest.queue_free()
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	label.size_flags_horizontal = Control.SIZE_SHRINK_END
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	label.add_theme_constant_override("outline_size", 4)
	label.add_theme_font_size_override("font_size", 15)
	box.add_child(label)
	box.move_child(label, 0)
	var tween := create_tween()
	tween.tween_interval(HOLD_TIME)
	tween.tween_property(label, "modulate:a", 0.0, FADE_TIME)
	tween.tween_callback(label.queue_free)
