extends Node3D
## 1v1 fight arena: a closed box with floor and 14m walls (static collision
## baked into the scene). Spawn points live under the "Node" folder as
## Marker3D (Pspawn1/Pspawn2); get_spawn_markers() hands them to lobby.gd
## (initial spawns) and weapon_system.gd (respawns).

func get_spawn_markers() -> Array[Marker3D]:
	var out: Array[Marker3D] = []
	var folder := get_node_or_null("Node")
	if folder == null:
		return out
	for child in folder.get_children():
		if child is Marker3D:
			out.append(child)
	return out