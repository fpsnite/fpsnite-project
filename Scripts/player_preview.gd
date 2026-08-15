extends Node3D
## Podium preview character for the main menu. Shows the selected skin,
## slowly spins, and displays the typed player name.

@onready var mesh_pivot: Node3D = $MeshPivot
@onready var name_label: Label3D = $PlayerNameLabel
@onready var ready_label: Label3D = $PlayerNameLabel2

func _ready() -> void:
	apply_skin(Settings.skin_index)
	set_ready(false)

func _process(delta: float) -> void:
	rotate_y(delta * 0.6)

func apply_skin(index: int) -> void:
	var material := Skins.material_at(index)
	if material == null:
		return
	for child in mesh_pivot.get_children():
		if child is MeshInstance3D:
			child.material_override = material

func update_name(player_name: String) -> void:
	name_label.text = player_name

## Lobby ready-state marker above the preview: green READY / red UNREADY.
func set_ready(ready: bool) -> void:
	if ready:
		ready_label.text = "READY"
		ready_label.modulate = Color(0.35, 1.0, 0.4)
	else:
		ready_label.text = "UNREADY"
		ready_label.modulate = Color(1.0, 0.35, 0.35)
