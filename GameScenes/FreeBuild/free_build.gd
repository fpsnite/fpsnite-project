extends Node3D
## Free Build map: a wide, flat, walled arena ready for the grid building
## system (flat floor at y=0, walls 12m tall, 1m-aligned bounds). Collision
## is plain box shapes baked into this scene.
## Spawn points live under the "Spawners" folder as Marker3D (Pspawn1);
## get_spawn_markers() hands them to lobby.gd (initial spawns) and
## weapon_system.gd (respawns).

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