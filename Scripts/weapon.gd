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
var _flash: OmniLight3D
var _flash_left := 0.0

func _ready() -> void:
	_owner = get_parent().get_parent() as CharacterBody3D
	_tracers = _make_tracer_pool()
	_flash = OmniLight3D.new()
	_flash.light_color = Color(1.0, 0.85, 0.4)
	_flash.light_energy = 2.0
	_flash.omni_range = 3.0
	_flash.visible = false
	_equip(0)

func _process(delta: float) -> void:
	_flash_left = maxf(_flash_left - delta, 0.0)
	_flash.visible = _flash_left > 0.0
	if not _can_act():
		return
	if current_data.melee:
		_swing_left = maxf(_swing_left - delta, 0.0)
		if Input.is_action_just_pressed("fire") and _cooldown <= 0.0 and _swing_left <= 0.0:
			_melee_attack()
	else:
		_cooldown = maxf(_cooldown - delta, 0.0)
		if reloading:
			_reload_left -= delta
			if _reload_left <= 0.0:
				_finish_reload()
		elif Input.is_action_just_pressed("reload") and mag < current_data.mag_size and reserve > 0:
			_start_reload()
		elif Input.is_action_pressed("fire") and _cooldown <= 0.0 and mag > 0:
			_shoot()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_weapon") and _can_act():
		_equip(weapon_index + 1)

func _can_act() -> bool:
	return _owner != null \
		and _owner.replicator.has_input_authority() \
		and not _owner.spectating \
		and not _owner._chat_open()

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
		if _flash.get_parent():
			_flash.get_parent().remove_child(_flash)
		_viewmodel.add_child(_flash)
	mag = current_data.mag_size
	reserve = current_data.reserve_ammo
	reloading = false
	weapon_changed.emit(current_data.weapon_name)
	ammo_changed.emit(mag, reserve)

# --- Firing ---

func _shot_origin() -> Vector3:
	if _muzzle != null:
		return _muzzle.global_position
	return _owner.camera_3d.global_position

func _shoot() -> void:
	_cooldown = 1.0 / maxf(current_data.fire_rate, 0.1)
	mag -= 1
	ammo_changed.emit(mag, reserve)
	var camera: Camera3D = _owner.camera_3d
	var basis: Basis = camera.global_transform.basis
	var spread := current_data.spread_rad
	var direction: Vector3 = (basis * Vector3(
		randf_range(-spread, spread), randf_range(-spread, spread), -1.0)).normalized()
	var sys := get_tree().get_first_node_in_group("weapon_system")
	if sys:
		sys.request_shoot(_owner.player_id, _shot_origin(), direction, current_data.weapon_id)
	_show_muzzle_flash()

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

func _show_muzzle_flash() -> void:
	_flash.visible = true
	_flash_left = 0.03

# --- Reloading ---

func _start_reload() -> void:
	reloading = true
	_reload_left = current_data.reload_time
	ammo_changed.emit(mag, reserve)

func _finish_reload() -> void:
	var need := current_data.mag_size - mag
	var take := mini(need, reserve)
	mag += take
	reserve -= take
	reloading = false
	ammo_changed.emit(mag, reserve)

# --- Visuals driven by broadcast_hit (server result) ---

## Draws the tracer from the muzzle to the confirmed hit point.
func show_tracer(from: Vector3, to: Vector3) -> void:
	var instance := _tracers[_tracer_index]
	_tracer_index = (_tracer_index + 1) % _tracers.size()
	var mesh: ImmediateMesh = instance.mesh
	mesh.clear_surfaces()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	mesh.surface_add_vertex(from)
	mesh.surface_add_vertex(to)
	mesh.surface_end()
	instance.visible = true
	instance.get_tree().create_timer(TRACER_LIFE).timeout \
		.connect(_on_tracer_timeout.bind(instance))

func _on_tracer_timeout(instance: MeshInstance3D) -> void:
	instance.visible = false

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