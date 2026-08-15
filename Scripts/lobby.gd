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
	if Fusion.is_master_client():
		call_deferred("_spawn_existing_players")
	Fusion.room_joined.connect(_on_room_joined)

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
	print("[NET] spawning player %d" % player_id)
	var player := spawner.spawn(PlayerScene)
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
	player.position = _spawn_point_for(player_id)
	player.get_node("FusionServerReplicator").set_input_authority(player_id)

## Picks the Marker3D spawn point for a player (stable per player id, wraps
## around when there are more players than markers). Falls back to a random
## spot if the scene has no markers.
func _spawn_point_for(player_id: int) -> Vector3:
	var markers: Array[Node3D] = []
	for child in $SpawnPoints.get_children():
		if child is Marker3D:
			markers.append(child)
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
