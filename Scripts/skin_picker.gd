extends CanvasLayer
## Skin picker: lists skins from res://skins/ and broadcasts the choice.
## Emits skin_chosen so the owner can update its own preview instantly.

signal skin_chosen(index: int)

@onready var panel: PanelContainer = get_node("Root/SkinPanel")
@onready var skin_list: VBoxContainer = get_node("Root/SkinPanel/VBox/SkinList")

func _ready() -> void:
	_build_list()

func _build_list() -> void:
	for i in Skins.count():
		var button := Button.new()
		button.text = Skins.skin_name(i)
		button.custom_minimum_size = Vector2(100, 44)
		button.pressed.connect(_on_skin_pressed.bind(i))
		skin_list.add_child(button)

func _on_skin_pressed(index: int) -> void:
	Settings.skin_index = index
	Settings.save_settings()
	skin_chosen.emit(index)
	Backend.update_skin(index)
	if Fusion.is_in_room():
		var lobby := get_tree().get_first_node_in_group("lobby")
		if lobby:
			Fusion.rpc(lobby.submit_skin, Fusion.get_local_player_id(), index)
	panel.visible = false

func _on_open_pressed() -> void:
	panel.visible = not panel.visible
