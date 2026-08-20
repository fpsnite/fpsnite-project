extends Node3D
## Server-authoritative combat. The MASTER client is the server: every shot /
## melee from any client arrives here as an RPC, the master resolves the
## hitscan (against world geometry + player hitboxes), applies damage to its
## authoritative health table and broadcasts the outcome to every client
## (tracers, damage numbers, kill feed, deaths, respawns).
##
## Clients never trust their own raycasts or health - they only send requests.

signal local_damage_taken(damage: float)
## Emitted on all clients when a player dies (killer_id, target_id).
## game_round.gd listens to count kills toward the match score.
signal player_killed(killer_id: int, target_id: int)

const MAX_HEALTH := 100.0
## Shield absorbs damage before health (a second bar, drained first).
const MAX_SHIELD := 100.0
const RESPAWN_TIME := 3.0
const BODY_LAYER := 4   # BodyHitbox area
const HEAD_LAYER := 8   # HeadHitbox area
const WORLD_LAYER := 1

const WEAPONS_DIR := "res://Resources/Weapons"

var _weapons: Dictionary = {}       # weapon_id -> WeaponData (authoritative tables)
var _health: Dictionary = {}        # player_id -> float
var _shield: Dictionary = {}        # player_id -> float (absorbs damage first)
var _dead: Dictionary = {}          # player_id -> bool
var _last_shot_ms: Dictionary = {}  # player_id -> int, rate limiting
var _spawn_points: Array[Marker3D] = []
var _map: Node = null               # the active map node (spawn marker source)
var _lobby: Node
var _holes: BulletHoles

func _ready() -> void:
	add_to_group("weapon_system")
	_lobby = get_tree().get_first_node_in_group("lobby")
	# Every .tres in Resources/Weapons becomes an authoritative table - each
	# weapon's own damage, fire rate, headshot multiplier, range and melee
	# stats are used, no per-weapon code to maintain.
	for path in _list_weapon_tres():
		var data := load(path) as WeaponData
		if data != null:
			_weapons[data.weapon_id] = data
	_holes = BulletHoles.new()
	add_child(_holes)
	Fusion.register_broadcast_receiver(self)
	Fusion.player_joined.connect(_on_player_joined)
	Fusion.player_left.connect(_on_player_left)
	call_deferred("_collect_spawn_points")

func _list_weapon_tres() -> Array[String]:
	var paths: Array[String] = []
	var dir := DirAccess.open(WEAPONS_DIR)
	if dir == null:
		push_warning("weapon_system: cannot open %s" % WEAPONS_DIR)
		return paths
	for file in dir.get_files():
		if file.ends_with(".tres"):
			paths.append(WEAPONS_DIR.path_join(file))
	return paths

func _exit_tree() -> void:
	Fusion.unregister_broadcast_receiver(self)

func _collect_spawn_points() -> void:
	_spawn_points.clear()
	_map = null
	var arena := get_node_or_null("../GameArena")
	if arena == null:
		return
	# The map lives under GameArena. Prefer its marker API (fps_map exposes
	# get_spawn_markers / get_spawn_markers_for_team; custom maps expose
	# get_spawn_markers); fall back to legacy FFASpawns folders directly
	# under the arena, then the scene's own SpawnPoints.
	for map_node in arena.get_children():
		if map_node.has_method("get_spawn_markers") \
				or map_node.has_method("get_spawn_markers_for_team"):
			_map = map_node
			_spawn_points = _map_spawn_markers(-1)
			return
	var ffa := arena.get_node_or_null("FFASpawns")
	if ffa != null:
		for child in ffa.get_children():
			if child is Marker3D:
				_spawn_points.append(child)
		return
	var scene_points := get_node_or_null("SpawnPoints")
	if scene_points != null:
		for child in scene_points.get_children():
			if child is Marker3D:
				_spawn_points.append(child)

## Resolve a respawn position: team modes use the map's per-team markers so
## each side respawns on its own end; everything else uses the FFA set.
## Positions are derived from the map node's to_global() - Marker3D
## global_position can be stale under plain Node marker folders (FreeBuild).
func _respawn_point_for(player_id: int) -> Vector3:
	var team := _team_for(player_id)
	var markers := _map_spawn_markers(team)
	if markers.is_empty():
		markers = _spawn_points
	if markers.is_empty():
		return Vector3(0.0, 1.0, 0.0)
	var marker: Marker3D = markers.pick_random()
	if _map is Node3D:
		return (_map as Node3D).to_global(marker.position)
	return marker.global_position

func _map_spawn_markers(team: int) -> Array[Marker3D]:
	if _map == null:
		return []
	if _map.has_method("get_spawn_markers_for_team"):
		var team_markers := _map.get_spawn_markers_for_team(team) as Array[Marker3D]
		if not team_markers.is_empty():
			return team_markers
	if _map.has_method("get_spawn_markers"):
		return _map.get_spawn_markers() as Array[Marker3D]
	return []

func _team_for(player_id: int) -> int:
	if not GameModes.is_team_mode(Settings.pending_mode):
		return -1
	var round_node := get_tree().get_first_node_in_group("round")
	if round_node == null or not round_node.has_method("get_team"):
		return -1
	return round_node.get_team(player_id)

func _on_player_joined(player_id: int, _user_id: String) -> void:
	_health[player_id] = MAX_HEALTH
	_shield[player_id] = MAX_SHIELD
	_dead[player_id] = false

func _on_player_left(player_id: int, _is_inactive: bool) -> void:
	_health.erase(player_id)
	_shield.erase(player_id)
	_dead.erase(player_id)
	_last_shot_ms.erase(player_id)

# --- Requests from clients (any peer) ---

func request_shoot(shooter_id: int, origin: Vector3, direction: Vector3, weapon_id: String) -> void:
	Fusion.rpc(request_shoot_rpc, shooter_id, origin, direction, weapon_id)

func request_melee(shooter_id: int, origin: Vector3, direction: Vector3, weapon_id: String) -> void:
	Fusion.rpc(request_melee_rpc, shooter_id, origin, direction, weapon_id)

@rpc("any_peer", "call_local")
func request_shoot_rpc(shooter_id: int, origin: Vector3, direction: Vector3, weapon_id: String) -> void:
	if not Fusion.is_master_client():
		return
	if _dead.get(shooter_id, false):
		return
	var data: WeaponData = _weapons.get(weapon_id)
	if data == null or data.melee:
		return
	if not _rate_limited(shooter_id, 1.0 / maxf(data.fire_rate, 0.1)):
		return
	_resolve_shot(shooter_id, origin, direction, data, data.damage)

@rpc("any_peer", "call_local")
func request_melee_rpc(shooter_id: int, origin: Vector3, direction: Vector3, weapon_id: String) -> void:
	if not Fusion.is_master_client():
		return
	if _dead.get(shooter_id, false):
		return
	var data: WeaponData = _weapons.get(weapon_id)
	if data == null or not data.melee:
		return
	if not _rate_limited(shooter_id, data.melee_time):
		return
	var shot := data.duplicate() as WeaponData
	shot.range = data.melee_range
	_resolve_shot(shooter_id, origin, direction, shot, data.melee_damage)

func _rate_limited(shooter_id: int, interval: float) -> bool:
	var now := Time.get_ticks_msec()
	if now - int(_last_shot_ms.get(shooter_id, -1000000)) < int(interval * 1000.0):
		return false
	_last_shot_ms[shooter_id] = now
	return true

# --- Hit resolution (master only) ---

func _resolve_shot(shooter_id: int, origin: Vector3, direction: Vector3, data: WeaponData, base_damage: float) -> void:
	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(origin, origin + direction * data.range)
	query.collision_mask = WORLD_LAYER | BODY_LAYER | HEAD_LAYER
	query.collide_with_areas = true
	query.exclude = _exclusions_for(shooter_id)
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		Fusion.rpc(broadcast_hit, shooter_id, 0, 0.0, false,
			origin + direction * data.range, Vector3.ZERO, data.weapon_id)
		return
	var position: Vector3 = hit.position
	var collider: Object = hit.collider
	if collider is Area3D:
		var target: Node = collider.get_parent()
		if target == null or not ("player_id" in target) \
			or not target.has_method("become_dead"):
			Fusion.rpc(broadcast_hit, shooter_id, 0, 0.0, false,
				position, hit.normal, data.weapon_id)
			return
		var target_id: int = target.player_id
		if target_id == shooter_id or _dead.get(target_id, false):
			Fusion.rpc(broadcast_hit, shooter_id, 0, 0.0, false,
				position, hit.normal, data.weapon_id)
			return
		# Team damage guard: same-team hits do nothing in TDM.
		if _same_team(shooter_id, target_id):
			Fusion.rpc(broadcast_hit, shooter_id, 0, 0.0, false,
				position, hit.normal, data.weapon_id)
			return
		var headshot: bool = collider.name == "HeadHitbox"
		var damage: float = base_damage * (data.headshot_multiplier if headshot else 1.0)
		_apply_damage(shooter_id, target_id, damage, headshot, position, hit.normal, data.weapon_id)
	else:
		Fusion.rpc(broadcast_hit, shooter_id, 0, 0.0, false,
			position, hit.normal, data.weapon_id)

## Returns true if both players are on the same team (TDM only).
func _same_team(id_a: int, id_b: int) -> bool:
	var round_node := get_tree().get_first_node_in_group("round")
	if round_node == null:
		return false
	if not round_node.has_method("get_team"):
		return false
	return round_node.get_team(id_a) == round_node.get_team(id_b)

func _exclusions_for(shooter_id: int) -> Array[RID]:
	var shooter: Node = _character(shooter_id)
	if shooter == null:
		return []
	var rids: Array[RID] = [shooter.get_rid()]
	var body_hitbox := shooter.get_node_or_null("BodyHitbox")
	if body_hitbox:
		rids.append(body_hitbox.get_rid())
	var head_hitbox := shooter.get_node_or_null("HeadHitbox")
	if head_hitbox:
		rids.append(head_hitbox.get_rid())
	return rids

func _apply_damage(killer_id: int, target_id: int, damage: float, headshot: bool,
		position: Vector3, normal: Vector3, weapon_id: String) -> void:
	# Free Build is a creative sandbox: damage never lands (infinite health).
	if GameModes.is_build(Settings.pending_mode):
		return
	Fusion.rpc(broadcast_hit, killer_id, target_id, damage, headshot,
		position, normal, weapon_id)
	# Shield absorbs damage first; only overflow reaches health.
	var shield_hp := float(_shield.get(target_id, MAX_SHIELD))
	var shield_taken := minf(shield_hp, damage)
	shield_hp -= shield_taken
	_shield[target_id] = shield_hp
	var hp := float(_health.get(target_id, MAX_HEALTH)) - (damage - shield_taken)
	if hp <= 0.0 and not _dead.get(target_id, false):
		_dead[target_id] = true
		_health[target_id] = 0.0
		_shield[target_id] = 0.0
		Fusion.rpc(sync_health, target_id, 0.0, 0.0)
		Fusion.rpc(broadcast_death, killer_id, target_id, headshot)
	else:
		_health[target_id] = maxf(hp, 0.0)
		Fusion.rpc(sync_health, target_id, _health[target_id], _shield[target_id])

# --- Broadcasts (all peers) ---

@rpc("any_peer", "call_local")
func broadcast_hit(shooter_id: int, target_id: int, damage: float, headshot: bool,
		position: Vector3, normal: Vector3, _weapon_id: String) -> void:
	var local_id := Fusion.get_local_player_id()
	if shooter_id != local_id:
		return
	var shooter := _character(shooter_id)
	if shooter == null:
		return
	var weapon := shooter.get_node_or_null("CameraPivot/Camera3D/Weapon")
	# Bullets visuals (tracer + flying bullet) are ranged-only: knife swings
	# must not draw a shot line to the hit point.
	if weapon and not weapon.current_data.melee:
		weapon.show_tracer(weapon.muzzle_global_position(), position)
		weapon.show_bullet(weapon.muzzle_global_position(), position)
	# Missed everything (wall/floor): leave a bullet hole, except for melee
	# swings - bullets only. The server's word on the surface normal is used.
	if target_id == 0 and not normal.is_zero_approx() \
			and (weapon == null or not weapon.current_data.melee):
		_holes.spawn(position, normal)
	if damage > 0.0:
		var numbers := get_tree().get_first_node_in_group("damage_numbers")
		if numbers:
			numbers.spawn_number(damage, position,
				Color(1.0, 0.75, 0.1) if headshot else Color(1.0, 1.0, 1.0), headshot)

@rpc("any_peer", "call_local")
func sync_health(target_id: int, hp: float, shield: float) -> void:
	var character := _character(target_id)
	if character == null:
		return
	if target_id == Fusion.get_local_player_id() and hp < character.health:
		local_damage_taken.emit(character.health - hp)
	character.health = hp
	character.shield = shield

@rpc("any_peer", "call_local")
func broadcast_death(killer_id: int, target_id: int, headshot: bool) -> void:
	var feed := get_tree().get_first_node_in_group("kill_feed")
	if feed:
		feed.add_event(&"headshot" if headshot else &"kill", killer_id, target_id)
	var character := _character(target_id)
	if character:
		character.become_dead()
	player_killed.emit(killer_id, target_id)
	# FFA: instant respawn. TDM/1v1: delayed respawn with spectate option.
	var round_node := get_tree().get_first_node_in_group("round")
	var mode: String = round_node.get_mode() if round_node and round_node.has_method("get_mode") else "ffa"
	if mode == "ffa":
		# Instant respawn for FFA — no spectate
		get_tree().create_timer(0.5).timeout \
			.connect(func() -> void: request_respawn(target_id), CONNECT_ONE_SHOT)
	elif target_id == Fusion.get_local_player_id():
		get_tree().create_timer(RESPAWN_TIME).timeout \
			.connect(_on_respawn_timeout, CONNECT_ONE_SHOT)

func _on_respawn_timeout() -> void:
	request_respawn(Fusion.get_local_player_id())

func request_respawn(player_id: int) -> void:
	Fusion.rpc(request_respawn_rpc, player_id)

@rpc("any_peer", "call_local")
func request_respawn_rpc(player_id: int) -> void:
	if not Fusion.is_master_client():
		return
	if not _dead.get(player_id, false):
		return
	# No respawns after the match has ended (end screen is up).
	var round_node := get_tree().get_first_node_in_group("round")
	if round_node and round_node.has_method("is_match_over") and round_node.is_match_over():
		return
	_dead[player_id] = false
	_health[player_id] = MAX_HEALTH
	_shield[player_id] = MAX_SHIELD
	var position := _respawn_point_for(player_id)
	Fusion.rpc(broadcast_respawn, player_id, position, randf() * TAU)
	Fusion.rpc(sync_health, player_id, MAX_HEALTH, MAX_SHIELD)

@rpc("any_peer", "call_local")
func broadcast_respawn(player_id: int, position: Vector3, rotation_y: float) -> void:
	var character := _character(player_id)
	if character:
		character.respawn_at(position, rotation_y)

func _character(player_id: int) -> Node:
	if _lobby == null:
		_lobby = get_tree().get_first_node_in_group("lobby")
	return _lobby._characters.get(player_id) if _lobby else null
