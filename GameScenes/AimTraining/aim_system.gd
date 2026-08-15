extends Node3D
## Local hit resolution for the Aim Training scene - no networking. Lives in
## the "weapon_system" group so weapon.gd forwards shots here exactly like
## the real server; instead of RPCs it raycasts immediately against world
## geometry (layer 1) and practice targets (layer 2), then shows the tracer,
## the animated bullet, and scores.
##
## Debug mode (F3): draws the fired ray (red = miss, green = target hit) and
## the true crosshair ray without bullet spread (blue), plus console details
## per shot - so you can see exactly what the hitscan hit vs where you were
## aiming.

signal hit_scored()

const WORLD_LAYER := 1
const TARGET_LAYER := 2
const RANGE := 200.0
const MELEE_RANGE := 2.5
const DEBUG_LINE_POOL := 8
const DEBUG_LINE_LIFE := 0.6

@export var debug_raycast := false

var _debug_lines: Array[MeshInstance3D] = []
var _debug_line_index := 0
var _holes: BulletHoles
## Shots queued by weapon.gd (which runs in _process) and resolved here in
## _physics_process: raycasting against direct_space_state outside the
## physics step can stall the main thread, causing random hitches when firing.
var _pending: Array[Array] = []

## Accuracy tracking: every non-melee shot (each pellet counts as a shot) vs
## how many connected with a target. The `mode_*` pair resets when switching
## arenas/modes; the plain pair accumulates for the whole aim-training
## session (the "global" number in the HUD).
var shots_fired := 0
var shots_hit := 0
var mode_shots_fired := 0
var mode_shots_hit := 0

## Called by the main instance when the player teleports into an arena - the
## per-mode accuracy restarts, the session-global keeps counting.
func reset_mode_stats() -> void:
	mode_shots_fired = 0
	mode_shots_hit = 0

func _ready() -> void:
	add_to_group("weapon_system")
	_debug_lines = _make_debug_pool()
	_holes = BulletHoles.new()
	add_child(_holes)

func _physics_process(_delta: float) -> void:
	if _pending.is_empty():
		return
	var batch := _pending
	_pending = []
	for shot in batch:
		_resolve_hit(shot[0], shot[1], shot[2], shot[3])

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo \
			and event.keycode == KEY_F3:
		debug_raycast = not debug_raycast
		print("[AIM] raycast debug: %s" % ("ON" if debug_raycast else "OFF"))

## Entry point called by weapon.gd for every rifle/pistol shot.
func request_shoot(_shooter_id: int, origin: Vector3, direction: Vector3, _weapon_id: String) -> void:
	shots_fired += 1
	mode_shots_fired += 1
	_pending.append([origin, direction, RANGE, false])

## Entry point called by weapon.gd for knife swings (no bullet visual).
func request_melee(_shooter_id: int, origin: Vector3, forward: Vector3, _weapon_id: String) -> void:
	_pending.append([origin, forward, MELEE_RANGE, true])

func _resolve_hit(origin: Vector3, direction: Vector3, range: float, melee: bool) -> void:
	# The muzzle (real gun barrel) sits ~0.5m right of the camera axis, so a
	# hitscan from the muzzle lands off the crosshair. This is single-player
	# local hitscan, so resolve from the camera center - the exact point the
	# tracer/bullet visuals start - what you aim at is what you hit.
	var cam := _aim_camera()
	var visual_from: Vector3 = origin
	if cam:
		visual_from = cam.global_position + (-cam.global_transform.basis.z) * 0.3
	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(visual_from, visual_from + direction * range)
	query.collision_mask = WORLD_LAYER | TARGET_LAYER
	query.collide_with_areas = true
	var hit := space.intersect_ray(query)
	var collider: Object = hit.get("collider") if not hit.is_empty() else null
	var hit_point: Vector3 = hit.get("position") if not hit.is_empty() else visual_from + direction * range
	var hit_normal: Vector3 = hit.get("normal") if not hit.is_empty() else Vector3.ZERO
	var is_target := collider is Area3D and collider.has_method("hit")
	if is_target:
		shots_hit += 1
		mode_shots_hit += 1
		# Score only when the hit actually killed the target - damage on a
		# still-alive target (multi-hp discs) is not a point.
		if collider.hit(hit_point):
			hit_scored.emit()
	elif not melee and not hit_normal.is_zero_approx():
		# Bullet struck a wall - leave a fading bullet hole behind.
		_holes.spawn(hit_point, hit_normal)
	var player := get_tree().get_first_node_in_group("aim_player")
	var weapon: Node = null
	if player:
		weapon = player.get_node_or_null("CameraPivot/Camera3D/Weapon")
	if weapon:
		if weapon.has_method("show_tracer"):
			weapon.show_tracer(visual_from, hit_point)
		if not melee and weapon.has_method("show_bullet"):
			weapon.show_bullet(visual_from, hit_point)
	if debug_raycast:
		_debug_shot(visual_from, direction, range, hit_point, is_target, melee)

## Debug overlay: the fired ray (red miss / green hit) and the spread-free
## center camera ray (blue) with a console summary per shot.
func _debug_shot(origin: Vector3, direction: Vector3, range: float,
		hit_point: Vector3, is_target: bool, melee: bool) -> void:
	var cam := _aim_camera()
	var line_color := Color(0.2, 1.0, 0.3) if is_target else Color(1.0, 0.25, 0.25)
	var what := "HIT target" if is_target else "MISS"
	_draw_debug_line(origin, hit_point, line_color)
	if cam:
		var center_dir := -cam.global_transform.basis.z
		var center_query := PhysicsRayQueryParameters3D.create(
			cam.global_position, cam.global_position + center_dir * range)
		center_query.collision_mask = WORLD_LAYER | TARGET_LAYER
		center_query.collide_with_areas = true
		var center_hit := get_world_3d().direct_space_state.intersect_ray(center_query)
		var center_point: Vector3 = center_hit.get("position") \
			if not center_hit.is_empty() else cam.global_position + center_dir * range
		var center_collider: Object = center_hit.get("collider") if not center_hit.is_empty() else null
		var center_on_target := center_collider is Area3D and center_collider.has_method("hit")
		_draw_debug_line(cam.global_position, center_point, Color(0.3, 0.55, 1.0))
		print("[AIM] %s at %.1fm%s | center ray -> %s" % [
			what, origin.distance_to(hit_point), " (melee)" if melee else "",
			"target" if center_on_target else "wall/empty"])

func _aim_camera() -> Camera3D:
	var player := get_tree().get_first_node_in_group("aim_player")
	if player == null:
		return null
	return player.get_node_or_null("CameraPivot/Camera3D") as Camera3D

## Pooled persistent debug lines, hidden after DEBUG_LINE_LIFE.
func _draw_debug_line(from: Vector3, to: Vector3, color: Color) -> void:
	var instance := _debug_lines[_debug_line_index]
	_debug_line_index = (_debug_line_index + 1) % _debug_lines.size()
	var material := instance.material_override as StandardMaterial3D
	material.albedo_color = color
	material.emission = color
	var mesh: ImmediateMesh = instance.mesh
	mesh.clear_surfaces()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	mesh.surface_add_vertex(from)
	mesh.surface_add_vertex(to)
	mesh.surface_end()
	instance.visible = true
	if instance.has_meta("line_tween") and (instance.get_meta("line_tween") as Tween).is_valid():
		(instance.get_meta("line_tween") as Tween).kill()
	var tween := create_tween()
	instance.set_meta("line_tween", tween)
	tween.tween_interval(DEBUG_LINE_LIFE)
	tween.tween_callback(func() -> void: instance.visible = false)

func _make_debug_pool() -> Array[MeshInstance3D]:
	var pool: Array[MeshInstance3D] = []
	for i in DEBUG_LINE_POOL:
		var instance := MeshInstance3D.new()
		instance.mesh = ImmediateMesh.new()
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.emission_enabled = true
		instance.material_override = material
		instance.visible = false
		add_child(instance)
		pool.append(instance)
	return pool
