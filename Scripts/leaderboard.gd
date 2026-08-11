extends CanvasLayer
## Top-right leaderboard: one row per player (name + score), sorted by score.
## Reads the lobby's character list and score registry; scores are granted by
## the master when a round finishes (all players in the room +1).

@onready var rows_box: VBoxContainer = $Root/Panel/Margin/Rows

var _row_labels: Dictionary = {}  # player_id -> Label

func _process(_delta: float) -> void:
	var round: Node = get_tree().get_first_node_in_group("round")
	visible = round != null and round.is_round_active()
	if not visible:
		return
	var lobby := get_tree().get_first_node_in_group("lobby")
	if lobby == null:
		return
	var entries: Array[Dictionary] = []
	for pid: int in lobby._characters:
		var character: Node = lobby._characters[pid]
		entries.append({
			"id": pid,
			"name": _name_for(character),
			"score": int(lobby._score_registry.get(pid, 0)),
		})
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a["score"] > b["score"])
	_sync_rows(entries)

func _name_for(character: Node) -> String:
	var label: Label3D = character.get_node_or_null("PlayerNameLabel")
	if label and not label.text.is_empty() and label.text != "[PlayerName]":
		return label.text
	return "Player %d" % character.player_id

func _sync_rows(entries: Array[Dictionary]) -> void:
	for key in _row_labels:
		_row_labels[key].visible = false
	var rank := 1
	for entry in entries:
		var pid: int = entry["id"]
		var label: Label = _row_labels.get(pid)
		if label == null:
			label = _make_row()
			_row_labels[pid] = label
		var text := "%d.  %s  %s" % [
			rank,
			str(entry["name"]).rpad(22),
			str(entry["score"]).lpad(4),
		]
		if label.text != text:
			label.text = text
		label.visible = true
		rank += 1

func _make_row() -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", Color(1, 1, 1))
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	label.add_theme_constant_override("outline_size", 6)
	rows_box.add_child(label)
	return label
