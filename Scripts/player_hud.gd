extends CanvasLayer
## Bottom-center HUD: the 3-digit player number and the sprint stamina bar.
## Reads stamina/player_number from the local player instance.

@onready var sprint_bar: ProgressBar = $Box/SprintRow/SprintBar
@onready var force_label: Label = $Box/ForceLabel

func _process(_delta: float) -> void:
	var lobby := get_tree().get_first_node_in_group("lobby")
	var player: Node = lobby._characters.get(Fusion.get_local_player_id()) if lobby else null
	if player == null:
		return
	sprint_bar.value = player.stamina
	force_label.text = _format_number(player.player_number)

func _format_number(number: int) -> String:
	return "%03d" % number
