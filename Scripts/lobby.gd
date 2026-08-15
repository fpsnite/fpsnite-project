extends Node3D
## Lobby: FusionSpawner + skin registry. The master client spawns players
## (state authority: server, input authority: the matching player) and owns
## the authoritative skin registry, synced to everyone via broadcast RPCs.

const PlayerScene := preload("res://Scenes/player_instance.tscn")

const ROOM_HALF := 12.0  # usable spawn area inside the walls

var _characters: Dictionary = {}  # player_id -> player node

var _skin_registry: Dictionary = {}  # player_id -> skin index

var _number_registry: Dictionary = {}  # player_id -> player number (0..456)

@onready var spawner: FusionSpawner = $FusionSpawner

func _ready() -> void:
	add_to_group("lobby")
	get_tree().paused = false
	print("[NET] arena loaded at mode '%s' (max %d players)" % [
		Settings.pending_mode, GameModes.max_players(Settings.pending_mode)])
	Fusion.register_broadcast_receiver(self)
	spawner.add_spawnable_scene(PlayerScene)
	spawner.spawned.connect(_on_spawner_spawned)
	spawner.despawned.connect(_on_spawner_despawned)
	Fusion.player_joined.connect(_on_player_joined)
	Fusion.player_left.connect(_on_player_left)
	_install_map()
	if Fusion.is_master_client():
		call_deferred("_spawn_existing_players")
	Fusion.room_joined.connect(_on_room_joined)

## Instances the mode's map scene under GameArena (weapon_system.gd reads
## ../GameArena for spawn points). Custom maps replace the box room and the
## lobby's own lighting so the map's environment and sky take over.
func _install_map() -> void:
	var path := GameModes.map_scene(Settings.pending_mode)
	var scene := load(path) as PackedScene
	if scene == null:
		print("[NET] ERROR: cannot load map '%s'" % path)
		return
	$GameArena.add_child(scene.instantiate())
	print("[NET] map loaded: '%s' (mode '%s')" % [path, Settings.pending_mode])
	if GameModes.uses_custom_map(Settings.pending_mode):
		_switch_to_custom_map()

func _switch_to_custom_map() -> void:
	var room := get_node_or_null("Room")
	if room:
		room.queue_free()
	var env := get_node_or_null("WorldEnvironment")
	if env:
		env.queue_free()
	var sun := get_node_or_null("DirectionalLight3D")
	if sun:
		sun.queue_free()
	for child in get_children():
		if child is OmniLight3D:
			child.queue_free()

func _on_room_joined() -> void:
	if Fusion.is_master_client():
		call_deferred("_spawn_existing_players")

func _exit_tree() -> void:
	Fusion.unregister_broadcast_receiver(self)

# --- Spawning (master only) ---

func _log(msg: String) -> void:
	Network.last_log = msg
	print("[NET] " + msg)

## Spawns everyone already in the room once the scene finished its own setup
## (spawner.spawn add_child's, which fails while _ready is still running).
func _spawn_existing_players() -> void:
	for pid in Network.room_player_ids():
		_spawn_player(pid)
	if not _characters.has(Fusion.get_local_player_id()):
		_spawn_player(Fusion.get_local_player_id())

func _on_player_joined(player_id: int, user_id: String) -> void:
	var feed := get_tree().get_first_node_in_group("kill_feed")
	if feed:
		feed.add_event(&"joined", player_id)
	if Fusion.is_master_client():
		print("[NET] player joined (%d) - spawning for them" % player_id)
		_spawn_player(player_id)
	else:
		print("[NET] player joined (%d) - waiting for master spawn" % player_id)

func _on_player_left(player_id: int, is_inactive: bool) -> void:
	var feed := get_tree().get_first_node_in_group("kill_feed")
	if feed:
		feed.add_event(&"left", player_id)
	if not Fusion.is_master_client():
		return
	var character: Node = _characters.get(player_id)
	if character:
		print("[NET] player left (%d) - despawning their character" % player_id)
		spawner.despawn(character)
	else:
		print("[NET] player left (%d) - no character found" % player_id)
	_characters.erase(player_id)
	_skin_registry.erase(player_id)
	_number_registry.erase(player_id)

func _spawn_player(player_id: int) -> void:
	if _characters.has(player_id):
		return
	# Position is set via the pre-spawn callable: the native spawner bakes the
	# node's transform into the replicated state when it goes live, so any
	# assignment after spawn() returns gets reset to the spawner's origin.
	var spawn_point := _spawn_point_for(player_id)
	print("[NET] spawning player %d -> spawn_point=%s" % [player_id, spawn_point])
	var player := spawner.spawn(PlayerScene, func(p: Node) -> void:
		p.global_position = spawn_point
		print("[NET] preSpawn: player.global_position=%s parent=%s" % [p.global_position, p.get_parent().get_path()]))
	if player == null:
		print("[NET] ERROR: spawn returned null for player %d" % player_id)
		return
	_characters[player_id] = player
	_configure_player(player, player_id)
	player.refresh_identity()
	_assign_number(player_id, player)
	for pid in _skin_registry:
		Fusion.rpc(submit_skin, pid, _skin_registry[pid])

## Assigns a random, unique player number (000-456) as Squid Game's game
## master does, and syncs it to every client via a broadcast RPC.
func _assign_number(player_id: int, player: Node) -> void:
	var number := -1
	while number < 0 or _number_registry.values().has(number):
		number = randi() % 457
	_number_registry[player_id] = number
	player.apply_number(number)
	Fusion.rpc(submit_number, player_id, number)

func _configure_player(player: Node, player_id: int) -> void:
	player.player_id = player_id
	player.global_position = _spawn_point_for(player_id)
	player.get_node("FusionServerReplicator").set_input_authority(player_id)
	_apply_mode_weapons(player)
	print("[NET] _configure_player: player %d global_position=%s" % [player_id, player.global_position])

## Each game mode has its own weapon pool (see game_modes.gd): replace the
## spawned player's default loadout with the mode's weapons, then re-equip so
## current_data points into the new pool (the default knife was equipped on
## _ready, before the loadout was swapped).
func _apply_mode_weapons(player: Node) -> void:
	var pool := GameModes.weapon_pool(Settings.pending_mode)
	if pool.is_empty():
		return
	var weapon := player.get_node_or_null("CameraPivot/Camera3D/Weapon")
	if weapon == null:
		return
	weapon.loadout = pool
	weapon._equip(weapon._find_melee_index())
	print("[NET] mode weapons applied: %s (%d weapons)" % [Settings.pending_mode, pool.size()])

## Picks the Marker3D spawn point for a player (stable per player id, wraps
## around when there are more players than markers). Custom maps supply their
## own markers; the default arena falls back to the scene's SpawnPoints.
func _spawn_point_for(player_id: int) -> Vector3:
	var markers: Array[Marker3D] = []
	for child in $SpawnPoints.get_children():
		if child is Marker3D:
			markers.append(child)
	for map_node in $GameArena.get_children():
		if map_node.has_method("get_spawn_markers"):
			var map_markers := map_node.get_spawn_markers() as Array[Marker3D]
			if not map_markers.is_empty():
				markers = map_markers
			break
	if markers.is_empty():
		return Vector3(randf_range(-ROOM_HALF, ROOM_HALF), 1.0, randf_range(-ROOM_HALF, ROOM_HALF))
	return markers[player_id % markers.size()].global_position

## Returns the player's display name (local fallback for remote players).
func _player_name(player_id: int) -> String:
	if player_id == Fusion.get_local_player_id():
		return Network.player_name
	var character: Node = _characters.get(player_id)
	if character:
		var label: Label3D = character.get_node_or_null("PlayerNameLabel")
		if label and not label.text.is_empty() and label.text != "[PlayerName]":
			return label.text
	return "Player %d" % player_id

# --- Replication callbacks (all clients) ---

func _on_spawner_spawned(node: Node) -> void:
	var pid: int = node.get_node("FusionServerReplicator").get_input_authority()
	if pid <= 0:
		print("[NET] spawner.spawned: node without input authority yet")
		return
	print("[NET] spawner.spawned: player %d" % pid)
	_characters[pid] = node
	if _skin_registry.has(pid):
		node.apply_skin(_skin_registry[pid])
	if _number_registry.has(pid):
		node.apply_number(_number_registry[pid])

func _on_spawner_despawned(node: Node) -> void:
	for pid in _characters:
		if _characters[pid] == node:
			print("[NET] spawner.despawned: player %d" % pid)
			_characters.erase(pid)
			break

# --- Skins (broadcast RPCs) ---

@rpc("any_peer", "call_local")
func submit_skin(player_id: int, skin_index: int) -> void:
	var character: Node = _characters.get(player_id)
	if character:
		character.apply_skin(skin_index)
	if Fusion.is_master_client():
		_skin_registry[player_id] = skin_index

@rpc("any_peer", "call_local")
func submit_number(player_id: int, number: int) -> void:
	var character: Node = _characters.get(player_id)
	if character:
		character.apply_number(number)
	if Fusion.is_master_client():
		_number_registry[player_id] = number
