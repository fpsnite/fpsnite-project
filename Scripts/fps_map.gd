extends Node3D
## Default FFA/TDM arena map (fps_map.tscn). Spawn points live in three
## Marker3D folders: FFASpawns (FFA / aim), TeamASpawns (TDM blue) and
## TeamBSpawns (TDM red).
## get_spawn_markers() hands the FFA markers to lobby.gd (initial spawns) and
## weapon_system.gd (respawns), matching the custom-map contract; the team
## variant gives lobby/weapon_system the per-side markers for TDM.

func get_spawn_markers() -> Array[Marker3D]:
	return _markers_in("FFASpawns")

func get_spawn_markers_for_team(team: int) -> Array[Marker3D]:
	if team == 0:
		return _markers_in("TeamASpawns")
	elif team == 1:
		return _markers_in("TeamBSpawns")
	return _markers_in("FFASpawns")

func _markers_in(folder_name: String) -> Array[Marker3D]:
	var out: Array[Marker3D] = []
	var folder := get_node_or_null(folder_name)
	if folder == null:
		return out
	for child in folder.get_children():
		if child is Marker3D:
			out.append(child)
	return out