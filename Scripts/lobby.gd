extends Node3D
## Lobby: FusionSpawner + skin registry. The master client spawns players
## (state authority: server, input authority: the matching player) and owns
## the authoritative skin registry, synced to everyone via broadcast RPCs.

const PlayerScene := preload("res://Scenes/player_instance.tscn")

const ROOM_HALF := 12.0  # usable spawn area inside the walls

## If a peer never acks scene-ready (edge case), the master spawns everyone
## anyway after this long, matching the old immediate-spawn behavior.
const SCENE_READY_FALLBACK_SEC := 3.0

## Players below this height have fallen out of the world and get rescued.
const FALL_RESCUE_Y := -15.0
## Minimum time between auto-rescues per player (avoids a loop if the spawn
## point is itself broken/void).
const FALL_RESCUE_COOLDOWN_MS := 3000

var _characters: Dictionary = {}  # player_id -> player node

var _skin_registry: Dictionary = {}  # player_id -> skin index

var _name_registry: Dictionary = {}  # player_id -> display name (explicit sync)

var _scene_ready: Dictionary = {}  # player_id -> true once their scene acked

var _spawn_fallback: SceneTreeTimer

var _rescue_cooldown: Dictionary = {}  # player_id -> last rescue msec

@onready var spawner: FusionSpawner = $FusionSpawner

func _ready() -> void:
	add_to_group("lobby")
	get_tree().paused = false
	Backend.update_presence(true, false, true)
	print("[NET] arena loaded at mode '%s' (max %d players)" % [
		Settings.pending_mode, GameModes.max_players(Settings.pending_mode)])
	Fusion.register_broadcast_receiver(self)
	spawner.add_spawnable_scene(PlayerScene)
	spawner.spawned.connect(_on_spawner_spawned)
	spawner.despawned.connect(_on_spawner_despawned)
	Fusion.player_joined.connect(_on_player_joined)
	Fusion.player_left.connect(_on_player_left)
	Fusion.room_joined.connect(_on_room_joined)
	_install_map()
	# Scene-ready handshake: every client acks once its match scene is loaded
	# and its receivers are registered. The master spawns (and thus broadcasts
	# names/skins/weapons) only after ALL peers acked - otherwise a broadcast
	# RPC arriving at a peer whose scene is still loading gets dropped by
	# Fusion as an "unknown ID". The master considers itself ready; the name
	# publish moved to spawn time (both sides), see _spawn_player and
	# _on_spawner_spawned.
	if Fusion.is_master_client():
		_scene_ready[Fusion.get_local_player_id()] = true
	call_deferred("_send_scene_ready")
	_arm_spawn_fallback()

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
	var map_node := $GameArena.get_child($GameArena.get_child_count() - 1)
	print("[NET] map loaded: '%s' (mode '%s') arena_global=%s map_global=%s" % [
		path, Settings.pending_mode, $GameArena.global_position, map_node.global_position])
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
	# The match scene usually loads while already in the room (room_joined
	# already fired), so this is a no-op then; if it does fire, re-run the
	# gate - spawns still wait for everyone's scene-ready ack.
	if Fusion.is_master_client():
		_maybe_spawn_all()

# --- Scene-ready handshake ---

## Client -> master (targeted, so it never hits peers still loading): this
## client's match scene finished loading and its receivers are registered.
## The master spawns players only after every room member acked.
func _send_scene_ready() -> void:
	var room := Fusion.get_room()
	if room == null or not Fusion.is_in_room():
		return
	var master_id: int = room.get_master_client_id()
	if master_id <= 0:
		return
	Fusion.rpc_to_player(master_id, Callable(self, "submit_scene_ready"),
		Fusion.get_local_player_id())

@rpc("any_peer", "call_local")
func submit_scene_ready(player_id: int) -> void:
	if not Fusion.is_master_client():
		return
	var was_ready := _scene_ready.has(player_id)
	_scene_ready[player_id] = true
	print("[NET] scene ready: player %d (%d/%d)" % [
		player_id, _scene_ready.size(), Network.room_player_ids().size()])
	if not was_ready and player_id != Fusion.get_local_player_id():
		# The newcomer missed the broadcasts sent before their scene loaded:
		# re-send everyone's name and skin now that they can receive them.
		for pid in _name_registry:
			Fusion.rpc(submit_name, pid, _name_registry[pid])
		for pid in _skin_registry:
			Fusion.rpc(submit_skin, pid, _skin_registry[pid])
	_maybe_spawn_all()

## Master: spawn everyone once every current room member acked scene-ready.
func _maybe_spawn_all() -> void:
	if not Fusion.is_master_client():
		return
	for pid in Network.room_player_ids():
		if not _scene_ready.has(pid):
			return
	_log("all %d player(s) scene-ready - spawning" % _scene_ready.size())
	_spawn_existing_players()

## Fallback: if a peer never acks (e.g. never loads the match scene), spawn
## anyway after a timeout so the match is never stuck. Idempotent - already
## spawned players are skipped.
func _arm_spawn_fallback() -> void:
	if _spawn_fallback != null:
		_spawn_fallback.timeout.disconnect(_on_spawn_fallback)
	_spawn_fallback = get_tree().create_timer(SCENE_READY_FALLBACK_SEC)
	_spawn_fallback.timeout.connect(_on_spawn_fallback)

func _on_spawn_fallback() -> void:
	if not Fusion.is_master_client() or not is_inside_tree():
		return
	var before := _characters.size()
	_spawn_existing_players()
	if _characters.size() > before:
		_log("spawned %d player(s) via scene-ready fallback" % (_characters.size() - before))

func _exit_tree() -> void:
	Fusion.unregister_broadcast_receiver(self)

# --- Spawning (master only) ---

func _log(msg: String) -> void:
	Network.last_log = msg
	print("[NET] " + msg)

## True once this player's character exists locally (i.e. the master's spawn
## gate finished and spawned them - so their scene acked and every broadcast
## receiver is registered). game_round.gd uses this to defer its own seeds.
func has_spawned(player_id: int) -> bool:
	return _characters.has(player_id)

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
		print("[NET] player joined (%d) - waiting for their scene-ready ack" % player_id)
		_scene_ready.erase(player_id)
		# They'll be spawned by submit_scene_ready (or the fallback timer if
		# they never load the match scene).
		_arm_spawn_fallback()
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
	_name_registry.erase(player_id)
	_scene_ready.erase(player_id)
	# The unacked player is gone - respawn anyone still waiting on them.
	_maybe_spawn_all()

func _spawn_player(player_id: int) -> void:
	if _characters.has(player_id):
		return
	# Spawn at the FusionSpawner's origin (native, reliable), then teleport to
	# the map's spawn marker. The pre-spawn callable could not position the
	# node: it runs before the node is in the tree, and the native spawner
	# bakes the transform when the object goes live - so the player ended up
	# stranded at the spawner origin (far from the map). The deferred teleport
	# runs after the node is live and tracked, and the master (state
	# authority) replicates the corrected transform to every client.
	var spawn_point := _spawn_point_for(player_id)
	print("[NET] spawning player %d -> spawn_point=%s" % [player_id, spawn_point])
	var player := spawner.spawn(PlayerScene)
	if player == null:
		print("[NET] ERROR: spawn returned null for player %d" % player_id)
		return
	print("[NET] SPAWN-DEBUG mode=%s map=%s arena_global=%s map_node=%s marker_global=%s player_global=%s player_parent=%s parent_global=%s" % [
		Settings.pending_mode,
		GameModes.map_scene(Settings.pending_mode),
		$GameArena.global_position,
		_get_map_node_path(),
		spawn_point,
		player.global_position,
		player.get_parent().get_path() if player.get_parent() else "<none>",
		player.get_parent().global_position if player.get_parent() else "<none>"])
	print("[NET] player %d spawned: initial global_position=%s" % [player_id, player.global_position])
	_characters[player_id] = player
	_configure_player(player, player_id)
	_teleport_player(player, spawn_point)
	# The master's own spawn fires spawned BEFORE input authority is assigned
	# (see _on_spawner_spawned), so publish its name here instead. Safe to
	# broadcast: spawning only happens after every peer acked scene-ready.
	if player_id == Fusion.get_local_player_id():
		Fusion.rpc(submit_name, player_id, Network.player_name)
	player.refresh_identity()
	for pid in _skin_registry:
		Fusion.rpc(submit_skin, pid, _skin_registry[pid])

## Teleports a freshly spawned player to their spawn point once the node is
## live (deferred - beats the spawner's go-live transform bake). Idempotent.
func _teleport_player(player: Node, spawn_point: Vector3) -> void:
	call_deferred("_apply_spawn_position", player, spawn_point)

func _get_map_node_path() -> String:
	if $GameArena.get_child_count() == 0:
		return "<no map instanced>"
	return $GameArena.get_child(0).get_path()

func _process(_delta: float) -> void:
	if not is_inside_tree():
		return
	# Auto-rescue: any player who fell out of the world is teleported back to
	# their spawn point (master is state authority, so it replicates). Gated
	# by a cooldown so a broken spawn point can't cause a teleport loop.
	if Fusion.is_master_client():
		var now := Time.get_ticks_msec()
		for pid in _characters:
			var player: Node = _characters[pid]
			if is_instance_valid(player) \
					and player.global_position.y < FALL_RESCUE_Y \
					and now - int(_rescue_cooldown.get(pid, -1000000)) > FALL_RESCUE_COOLDOWN_MS:
				_rescue_cooldown[pid] = now
				print("[NET] player %d fell below y=%.0f - teleporting to spawn" % [pid, FALL_RESCUE_Y])
				_apply_spawn_position(player, _spawn_point_for(pid))

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"debug_teleport"):
		_teleport_local_to_spawn()

## Debug: teleport the local player back to their spawn point (F3). Falls
## into the void in Free Build until the map/spawn placement is fixed.
func _teleport_local_to_spawn() -> void:
	var pid := Fusion.get_local_player_id()
	print("[NET] debug teleport requested for player %d" % pid)
	if Fusion.is_master_client():
		var player: Node = _characters.get(pid)
		if player:
			_apply_spawn_position(player, _spawn_point_for(pid))
		else:
			print("[NET] debug teleport: no character for player %d" % pid)
	else:
		var room := Fusion.get_room()
		if room != null:
			Fusion.rpc_to_player(room.get_master_client_id(),
				Callable(self, "debug_teleport_me"), pid)

## Master only: teleports the requested player's character to their spawn
## point (state authority - the corrected transform replicates to everyone).
@rpc("any_peer", "call_local")
func debug_teleport_me(player_id: int) -> void:
	if not Fusion.is_master_client():
		return
	var player: Node = _characters.get(player_id)
	if player:
		print("[NET] debug teleport: master teleporting player %d" % player_id)
		_apply_spawn_position(player, _spawn_point_for(player_id))

func _apply_spawn_position(player: Node, spawn_point: Vector3) -> void:
	if is_instance_valid(player) and is_inside_tree():
		player.global_position = spawn_point
		if player is CharacterBody3D:
			player.velocity = Vector3.ZERO
		print("[NET] player %d teleported to spawn_point=%s (now global_position=%s)" % [
			player.get("player_id"), spawn_point, player.global_position])
	# Delayed check: catches anything that repositions the player after the
	# teleport (replication reset, authority fight, physics).
	get_tree().create_timer(1.0).timeout.connect(
		func() -> void:
			if is_instance_valid(player) and is_inside_tree():
				print("[NET] player %d after 1s: global_position=%s (expected ~%s)" % [
					player.get("player_id"), player.global_position, spawn_point]),
		CONNECT_ONE_SHOT)

func _configure_player(player: Node, player_id: int) -> void:
	player.player_id = player_id
	player.get_node("FusionServerReplicator").set_input_authority(player_id)
	# The spawned signal can fire on the master BEFORE input authority is
	# assigned (see the guard in _on_spawner_spawned), so the master applies
	# the mode weapon pool here for every node it spawns. Remote replicas are
	# covered by _on_spawner_spawned instead.
	_apply_mode_weapons(player)
	print("[NET] _configure_player: player %d (position set via pre-spawn callable)" % player_id)

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

## Picks the world-space spawn point for a player (stable per player id,
## wraps around when there are more players than markers). Custom maps supply
## their own markers via get_spawn_markers(); team modes ask the map for
## per-team markers (TeamASpawns/TeamBSpawns) so each team starts on its own
## side. Falls back to the scene's SpawnPoints, then a random point inside
## the room. Positions come from the map node's to_global() - NEVER from
## Marker3D.global_position, which can be stale for markers nested under
## plain Node folders (see the FreeBuild spawn bug).
func _spawn_point_for(player_id: int) -> Vector3:
	var team := _team_for(player_id)
	var points := _map_spawn_points(team)
	if points.is_empty():
		points = _scene_spawn_points()
	if points.is_empty():
		return Vector3(randf_range(-ROOM_HALF, ROOM_HALF), 1.0, randf_range(-ROOM_HALF, ROOM_HALF))
	var point := points[player_id % points.size()]
	print("[NET] spawn point lookup: team=%d points=%d arena_global=%s -> spawn_point=%s" % [
		team, points.size(), $GameArena.global_position, point])
	return point

## World-space spawn points from the active map. global_position on the
## markers can be stale (transform cache computed before the instanced scene
## entered the tree), so positions are derived from the map node, whose
## global transform reads correctly.
func _map_spawn_points(team: int) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for map_node in $GameArena.get_children():
		if not map_node is Node3D:
			continue
		var map3d := map_node as Node3D
		print("[NET] _map_spawn_points: map '%s' at global=%s" % [map_node.name, map3d.global_position])
		var markers := _map_markers(map3d, team)
		for marker in markers:
			out.append(map3d.to_global(marker.position))
		if not out.is_empty():
			return out
	return []

## The active map's marker set. Team modes pass the player's team so the map
## can return its per-side markers; non-team modes get the map's FFA set.
func _map_markers(map_node: Node3D, team: int) -> Array[Marker3D]:
	var out: Array[Marker3D] = []
	if map_node.has_method("get_spawn_markers_for_team"):
		var team_markers := map_node.get_spawn_markers_for_team(team) as Array[Marker3D]
		if not team_markers.is_empty():
			return team_markers
		# An empty team set means this map has no per-team spawns - fall
		# through to its generic marker set below.
	if map_node.has_method("get_spawn_markers"):
		var map_markers := map_node.get_spawn_markers() as Array[Marker3D]
		if not map_markers.is_empty():
			return map_markers
	return out

func _scene_spawn_points() -> Array[Vector3]:
	var out: Array[Vector3] = []
	var folder := $SpawnPoints as Node3D
	if folder == null:
		return out
	for child in folder.get_children():
		if child is Marker3D:
			out.append(folder.to_global((child as Marker3D).position))
	return out

## The player's team index (0 = blue, 1 = red) for team modes, else -1.
func _team_for(player_id: int) -> int:
	if not GameModes.is_team_mode(Settings.pending_mode):
		return -1
	var round_node := get_tree().get_first_node_in_group("round")
	if round_node == null or not round_node.has_method("get_team"):
		return -1
	return round_node.get_team(player_id)

## Returns the player's display name. Prefers the explicitly-synced name
## registry (Photon doesn't reliably expose names), falling back to the
## name label and finally a deterministic placeholder.
func _player_name(player_id: int) -> String:
	if player_id == Fusion.get_local_player_id():
		return Network.player_name
	if _name_registry.has(player_id):
		return _name_registry[player_id]
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
	print("[NET] spawner.spawned: player %d at global_position=%s (master=%s)" % [
		pid, node.global_position, Fusion.is_master_client()])
	_characters[pid] = node
	# Clients publish their own name here (their replica's spawn is gated
	# behind the master's all-acked spawn, so every peer is registered). The
	# master's own node is covered by _spawn_player instead.
	if pid == Fusion.get_local_player_id():
		Fusion.rpc(submit_name, pid, Network.player_name)
	# Every master-spawned node already got its mode weapon pool in
	# _configure_player; here only remote replicas need it (they have no
	# _configure_player pass). This avoids double-equipping on the master.
	if not Fusion.is_master_client():
		_apply_mode_weapons(node)
	if _skin_registry.has(pid):
		node.apply_skin(_skin_registry[pid])
	if _name_registry.has(pid):
		node.apply_name(_name_registry[pid])

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

# --- Names (broadcast RPCs) ---

## Photon room players don't reliably expose the connecting player's name
## (get_name()/get_user_id() come back empty), so names are synced explicitly,
## exactly like skins.
@rpc("any_peer", "call_local")
func submit_name(player_id: int, name: String) -> void:
	if name.is_empty():
		return
	_name_registry[player_id] = name
	var character: Node = _characters.get(player_id)
	if character:
		character.apply_name(name)

# --- Weapons (broadcast RPCs) ---

## Applies a loadout index on a player's weapon node on every client, so a
## weapon switch by the input owner is visible on all replicas.
@rpc("any_peer", "call_local")
func submit_weapon(player_id: int, index: int) -> void:
	var character: Node = _characters.get(player_id)
	if character == null:
		return
	var weapon := character.get_node_or_null("CameraPivot/Camera3D/Weapon")
	if weapon == null or not weapon.has_method("_equip"):
		return
	# from_remote suppresses the re-broadcast: _equip broadcasts on input
	# authority, so the call_local echo of this RPC would otherwise loop.
	weapon._equip(index, true)
