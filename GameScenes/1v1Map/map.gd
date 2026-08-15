extends Node3D
## 1v1 map built around the imported fps_tps arena GLB (visuals only - the
## glTF importer generates no physics, so collision lives in this scene as
## invisible box shapes: a floor slab at y=0 and four edge walls).
## Spawn points live under the "Spawners" folder (older builds used "Node")
## as Marker3D (Pspawn1/Pspawn2); get_spawn_markers() hands them to lobby.gd
## (initial spawns) and weapon_system.gd (respawns).

func get_spawn_markers() -> Array[Marker3D]:
	var out: Array[Marker3D] = []
	var folder := get_node_or_null("Spawners")
	if folder == null:
		folder = get_node_or_null("Node")
	if folder == null:
		return out
	for child in folder.get_children():
		if child is Marker3D:
			out.append(child)
	return out
