extends Node3D
## Player-side weapon controller (modular). The loadout is an exported array of
## WeaponData resources - swap/add .tres files to change weapons, no code edits.
##
## All damage is SERVER-AUTHORITATIVE: this node only handles input, cooldowns,
## ammo/reload and cosmetic visuals (viewmodel swap, muzzle flash, tracer
## lines). Every shot is forwarded as a request to the WeaponSystem node, which
## (on the master) resolves the hit and broadcasts the result back.

const TRACER_POOL := 16
const TRACER_LIFE := 0.06
const BULLET_POOL := 10
const BULLET_TIME := 0.05

signal ammo_changed(mag: int, reserve: int)
signal weapon_changed(weapon_name: String)

@export var loadout: Array[WeaponData] = []

var current_data: WeaponData
var mag := 0
var reserve := 0
var reloading := false
var weapon_index := 0

var _cooldown := 0.0
var _reload_left := 0.0
var _swing_left := 0.0
var _viewmodel: Node3D
var _muzzle: Node3D
var _owner: CharacterBody3D
var _tracers: Array[MeshInstance3D] = []
var _tracer_index := 0
var _bullets: Array[Node3D] = []
var _bullet_index := 0
var _shoot_tween: Tween
var _reload_tween: Tween
var _melee_index := 0

func _ready() -> void:
	_owner = _find_owner()
	_tracers = _make_tracer_pool()
	_bullets = _make_bullet_pool()
	_melee_index = _find_melee_index()
	_equip(_melee_index)

## The Weapon node sits under CameraPivot/Camera3D, so walk up until we hit
## the player's CharacterBody3D root (owner of replicator/camera/health).
func _find_owner() -> CharacterBody3D:
	var node: Node = get_parent()
	while node != null:
		if node is CharacterBody3D:
			return node
		node = node.get_parent()
	return null

## Index of the melee weapon in the loadout (the knife), used as the
## default equipped weapon and the target of the "knife" bind.
func _find_melee_index() -> int:
	for i in loadout.size():
		if loadout[i].melee:
			return i
	return 0

func _process(delta: float) -> void:
	if not _can_act():
		return
	if current_data.melee:
		_cooldown = maxf(_cooldown - delta, 0.0)
		_swing_left = maxf(_swing_left - delta, 0.0)
		if Input.is_action_just_pressed("fire") and _cooldown <= 0.0 and _swing_left <= 0.0:
			_melee_attack()
	else:
		_cooldown = maxf(_cooldown - delta, 0.0)
		if reloading:
			_reload_left -= delta
			if _reload_left <= 0.0:
				_finish_reload()
		elif Input.is_action_just_pressed("reload") \
				and not current_data.infinite_ammo and mag < current_data.mag_size \
				and (current_data.infinite_reserve_ammo or reserve > 0):
			_start_reload()
		elif Input.is_action_pressed("fire") and _cooldown <= 0.0:
			if mag > 0:
				_shoot()
			elif not current_data.infinite_ammo \
					and (current_data.infinite_reserve_ammo or reserve > 0):
				# Empty trigger: auto-reload immediately instead of dry-firing.
				_start_reload()

func _unhandled_input(event: InputEvent) -> void:
	if not _can_act():
		return
	# Direct slot select (1/2/3): the slot bar's numbers match loadout indexes.
	for i in loadout.size():
		if event.is_action_pressed("weapon_slot_%d" % (i + 1)):
			_equip(i)
			return
	if event.is_action_pressed("next_weapon"):
		_equip(weapon_index + 1)
	elif event.is_action_pressed("prev_weapon"):
		_equip(weapon_index - 1 + loadout.size())
	elif event.is_action_pressed("knife"):
		_equip(_melee_index)

func _can_act() -> bool:
	if _owner == null:
		return false
	# Networked players act only with input authority. Offline scenes (aim
	# training) have no replicator - treat them as always in control.
	if "replicator" in _owner and not _owner.replicator.has_input_authority():
		return false
	if "spectating" in _owner and _owner.spectating:
		return false
	if _owner.has_method("_chat_open") and _owner._chat_open():
		return false
	return true

func _equip(index: int) -> void:
	weapon_index = index % loadout.size()
	current_data = loadout[weapon_index]
	if _viewmodel != null:
		_viewmodel.queue_free()
	_viewmodel = null
	_muzzle = null
	if current_data.viewmodel:
		_viewmodel = current_data.viewmodel.instantiate()
		add_child(_viewmodel)
		_muzzle = _viewmodel.get_node_or_null("Muzzle")
	_rebuild_bullets()
	_notify_crosshair_style()
	mag = current_data.mag_size
	reserve = current_data.reserve_ammo
	reloading = false
	weapon_changed.emit(current_data.weapon_name)
	ammo_changed.emit(mag, reserve)

## The crosshair shape follows the weapon: rifle = classic four lines,
## shotgun = squared corner brackets (no fill), knife/melee = ring + point.
func _notify_crosshair_style() -> void:
	var crosshair := get_node_or_null("/root/Crosshair")
	if crosshair and crosshair.has_method("set_style"):
		var style := "dot" if current_data.melee \
			else ("square" if current_data.weapon_id == "shotgun" else "default")
		crosshair.set_style(style)

# --- Firing ---

func _shot_origin() -> Vector3:
	if _muzzle != null:
		return _muzzle.global_position
	return _owner.camera_3d.global_position

func _shoot() -> void:
	_cooldown = 1.0 / maxf(current_data.fire_rate, 0.1)
	if not current_data.infinite_ammo:
		mag -= 1
	ammo_changed.emit(mag, reserve)
	var camera: Camera3D = _owner.camera_3d
	var basis: Basis = camera.global_transform.basis
	# CS:GO-style accuracy: spread lerps from the base cone to the moving cone
	# by current speed. Cosmetic only - the server validates with its own
	# weapons table. Shotguns fire `pellets` rays, each with its own jitter.
	var h_speed := Vector2(_owner.velocity.x, _owner.velocity.z).length()
	var speed_ratio := clampf(h_speed / 9.0, 0.0, 1.0)
	var spread := lerpf(current_data.spread_rad,
		deg_to_rad(current_data.moving_spread_deg), speed_ratio)
	var sys := get_tree().get_first_node_in_group("weapon_system")
	for i in maxi(current_data.pellets, 1):
		var direction: Vector3 = (basis * Vector3(
			randf_range(-spread, spread), randf_range(-spread, spread), -1.0)).normalized()
		if sys:
			sys.request_shoot(_owner.player_id, _shot_origin(), direction, current_data.weapon_id)
	_animate_shoot()
	_apply_recoil()
	_notify_crosshair_shot()

## Upward camera kick per shot (weapon recoil).
func _apply_recoil() -> void:
	if current_data.recoil_kick_deg <= 0.0 or _owner == null:
		return
	var cam := _owner.get_node_or_null("CameraPivot") as FirstPersonCamera
	if cam:
		cam.add_recoil(current_data.recoil_kick_deg)

## The CS:GO-style crosshair kicks outward on each shot.
func _notify_crosshair_shot() -> void:
	var crosshair := get_node_or_null("/root/Crosshair")
	if crosshair:
		crosshair.add_shot_kick()

func _melee_attack() -> void:
	_cooldown = current_data.melee_time
	_swing_left = current_data.melee_time
	if _viewmodel != null:
		var tween := create_tween()
		tween.tween_property(_viewmodel, "rotation:x", 1.2, 0.12) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.tween_property(_viewmodel, "rotation:x", 0.0, 0.3) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var sys := get_tree().get_first_node_in_group("weapon_system")
	if sys:
		var camera: Camera3D = _owner.camera_3d
		sys.request_melee(_owner.player_id, _shot_origin(), -camera.global_transform.basis.z,
			current_data.weapon_id)

## Viewmodel recoil: quick kick back + muzzle-up on the gun model, then a
## smooth return. Each shot restarts the animation (rapid fire never stacks).
func _animate_shoot() -> void:
	if _viewmodel == null:
		return
	if _shoot_tween and _shoot_tween.is_valid():
		_shoot_tween.kill()
	_shoot_tween = create_tween()
	_shoot_tween.tween_property(_viewmodel, "position:z", 0.07, 0.045) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_shoot_tween.parallel().tween_property(_viewmodel, "rotation:x", -0.09, 0.045) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_shoot_tween.tween_property(_viewmodel, "position:z", 0.0, 0.12) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_shoot_tween.parallel().tween_property(_viewmodel, "rotation:x", 0.0, 0.12) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

## Reload animation part 1: the gun dips down (mag swap) while the reload
## timer runs; _finish_reload springs it back up.
func _animate_reload_down() -> void:
	if _viewmodel == null:
		return
	if _reload_tween and _reload_tween.is_valid():
		_reload_tween.kill()
	_reload_tween = create_tween()
	_reload_tween.set_parallel(true)
	_reload_tween.tween_property(_viewmodel, "position:y", -0.16, 0.14) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_reload_tween.tween_property(_viewmodel, "rotation:x", 0.55, 0.14) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

## Reload animation part 2: the gun returns to the ready pose.
func _animate_reload_up() -> void:
	if _viewmodel == null:
		return
	if _reload_tween and _reload_tween.is_valid():
		_reload_tween.kill()
	_reload_tween = create_tween()
	_reload_tween.set_parallel(true)
	_reload_tween.tween_property(_viewmodel, "position:y", 0.0, 0.12) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_reload_tween.tween_property(_viewmodel, "rotation:x", 0.0, 0.12) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

# --- Reloading ---

func _start_reload() -> void:
	reloading = true
	_reload_left = current_data.reload_time
	_animate_reload_down()
	ammo_changed.emit(mag, reserve)

func _finish_reload() -> void:
	var need := current_data.mag_size - mag
	var take := need if current_data.infinite_reserve_ammo else mini(need, reserve)
	mag += take
	if not current_data.infinite_reserve_ammo:
		reserve -= take
	reloading = false
	_animate_reload_up()
	ammo_changed.emit(mag, reserve)

# --- Visuals driven by broadcast_hit (server result) ---

## Draws the tracer from the muzzle to the confirmed hit point. Pooled
## instances carry a hide token so a reused tracer's stale hide timer can
## never hide a newer line mid-display.
func show_tracer(from: Vector3, to: Vector3) -> void:
	var instance := _tracers[_tracer_index]
	_tracer_index = (_tracer_index + 1) % _tracers.size()
	var token: int = int(instance.get_meta("hide_token", 0)) + 1
	instance.set_meta("hide_token", token)
	var mesh: ImmediateMesh = instance.mesh
	mesh.clear_surfaces()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	mesh.surface_add_vertex(from)
	mesh.surface_add_vertex(to)
	mesh.surface_end()
	instance.visible = true
	instance.get_tree().create_timer(TRACER_LIFE).timeout.connect(func() -> void:
		if int(instance.get_meta("hide_token", -1)) == token:
			instance.visible = false)

## Animates a glowing bullet from the muzzle to the resolved hit point over
## ~50ms. Purely cosmetic - the bullet is a small emissive cylinder flying
## nose-first along a straight line, matching the tracer line's path.
func show_bullet(from: Vector3, to: Vector3) -> void:
	var instance := _bullets[_bullet_index]
	_bullet_index = (_bullet_index + 1) % _bullets.size()
	if instance.has_meta("bullet_tween") and (instance.get_meta("bullet_tween") as Tween).is_valid():
		(instance.get_meta("bullet_tween") as Tween).kill()
	var direction := (to - from).normalized()
	var up := Vector3.UP if absf(direction.y) < 0.9 else Vector3.RIGHT
	instance.global_position = from
	# Guard against point-blank hits: look_at needs a non-zero forward.
	if to.distance_to(from) > 0.01:
		instance.look_at(to, up)
	instance.visible = true
	var tween := create_tween()
	instance.set_meta("bullet_tween", tween)
	tween.tween_property(instance, "global_position", to, BULLET_TIME).set_ease(Tween.EASE_IN)
	tween.tween_callback(func() -> void: instance.visible = false)

func muzzle_global_position() -> Vector3:
	return _shot_origin()

func _make_tracer_pool() -> Array[MeshInstance3D]:
	var pool: Array[MeshInstance3D] = []
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(1.0, 0.85, 0.35)
	material.emission_enabled = true
	material.emission = Color(1.0, 0.85, 0.35)
	material.emission_energy_multiplier = 2.0
	for i in TRACER_POOL:
		var instance := MeshInstance3D.new()
		instance.mesh = ImmediateMesh.new()
		instance.material_override = material
		instance.visible = false
		add_child(instance)
		pool.append(instance)
	return pool

## Pooled bullet visuals: each is a Node3D wrapper around one emissive mesh.
## Rifles fire little cylinders (child pre-rotated so the long Y axis maps to
## the wrapper's -Z, which look_at() points toward the target). Shotguns fire
## chunky rectangle pellets (BoxMesh, long axis already on Z - no child
## rotation needed).
func _make_bullet_pool() -> Array[Node3D]:
	var pool: Array[Node3D] = []
	var is_shotgun: bool = current_data != null and current_data.weapon_id == "shotgun"
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(1.0, 0.95, 0.7)
	material.emission_enabled = true
	material.emission = Color(1.0, 0.85, 0.4)
	material.emission_energy_multiplier = 3.0
	for i in BULLET_POOL:
		var root := Node3D.new()
		var instance := MeshInstance3D.new()
		if is_shotgun:
			var box := BoxMesh.new()
			box.size = Vector3(0.07, 0.07, 0.14)
			instance.mesh = box
		else:
			var cylinder := CylinderMesh.new()
			cylinder.top_radius = 0.02
			cylinder.bottom_radius = 0.02
			cylinder.height = 0.09
			instance.mesh = cylinder
			instance.rotation.x = -PI / 2
		instance.material_override = material
		root.add_child(instance)
		root.visible = false
		add_child(root)
		pool.append(root)
	return pool

## Rebuilds the bullet pool when the weapon changes (mesh shape differs
## between rifle cylinders and shotgun pellets).
func _rebuild_bullets() -> void:
	for bullet in _bullets:
		bullet.queue_free()
	_bullets = _make_bullet_pool()
