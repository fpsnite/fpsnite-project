class_name AimTrackingTarget
extends Area3D
## Moving practice target for the tracking arenas (mesh/collision live in
## aim_tracking_target.tscn; the script only tints the scene material with
## target_color). Patrols random waypoints inside its exported bounds with a
## sinusoidal bob. Every hit flashes it (white emission flash + small scale
## bump) and deals 1 damage; at hp hits it pops (scale animation) and
## teleports to a fresh spot with full hp. Collision layer 2 (hit by the
## local aim system raycast). Idle until set_active(true) - the arena
## freezes them when not running.

signal target_hit(at: Vector3)

@export var speed := 2.5
@export var bob_amp := 0.15
@export var min_pos := Vector3(-5, 1, -5)
@export var max_pos := Vector3(5, 3, 5)
@export var target_color := Color(1, 0.45, 0.2)
@export var hp := 1
@export var hit_flash_color := Color(1, 1, 1, 1)

@onready var _visual: MeshInstance3D = $Visual

var active := false
var hp_current := 1

var _material: StandardMaterial3D
var _base_energy := 1.6
var _waypoint := Vector3.ZERO
var _phase := 0.0
var _stuck_accum := 0.0
var _scale_tween: Tween
var _flash_tween: Tween

func _ready() -> void:
	collision_mask = 0
	hp_current = hp
	_material = _visual.material_override.duplicate() as StandardMaterial3D
	_material.albedo_color = target_color
	_material.emission = target_color
	_visual.material_override = _material
	_base_energy = _material.emission_energy_multiplier
	_pick_waypoint()

func _physics_process(delta: float) -> void:
	if not active:
		return
	_phase += delta * speed
	var goal := _waypoint
	goal.y = _waypoint.y + sin(_phase) * bob_amp
	var to_goal := goal - position
	if to_goal.length() < 0.25:
		_stuck_accum += delta
		if _stuck_accum > 1.0:
			_stuck_accum = 0.0
			_pick_waypoint()
	else:
		_stuck_accum = 0.0
		position += to_goal.normalized() * speed * delta

func _rand_point() -> Vector3:
	return Vector3(
		randf_range(min_pos.x, max_pos.x),
		randf_range(min_pos.y, max_pos.y),
		randf_range(min_pos.z, max_pos.z))

func _pick_waypoint() -> void:
	_waypoint = _rand_point()

## Called by the local aim system on a hit. Flashes, takes damage, and pops
## away once hp hits zero. Returns true when the hit was lethal (target died).
func hit(at: Vector3) -> bool:
	target_hit.emit(at)
	_flash()
	hp_current -= 1
	if hp_current <= 0:
		_kill()
		return true
	_bump()
	return false

## White emission flash that decays back to the target color.
func _flash() -> void:
	_material.emission = hit_flash_color
	_material.emission_energy_multiplier = _base_energy * 3.0
	if _flash_tween and _flash_tween.is_valid():
		_flash_tween.kill()
	_flash_tween = create_tween()
	_flash_tween.tween_property(_material, "emission_energy_multiplier", _base_energy, 0.16)
	_flash_tween.parallel().tween_property(_material, "emission", target_color, 0.16)

## Small quick pulse on a non-lethal hit.
func _bump() -> void:
	_kill_scale_tween()
	scale = Vector3.ONE * 1.18
	_scale_tween = create_tween()
	_scale_tween.tween_property(self, "scale", Vector3.ONE, 0.1) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

## Lethal hit: pop animation + respawn somewhere fresh with full hp.
func _kill() -> void:
	_pop()
	position = _rand_point()
	_pick_waypoint()
	hp_current = hp

func _pop() -> void:
	_kill_scale_tween()
	scale = Vector3.ONE * 1.5
	_scale_tween = create_tween()
	_scale_tween.tween_property(self, "scale", Vector3.ONE, 0.18) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _kill_scale_tween() -> void:
	if _scale_tween and _scale_tween.is_valid():
		_scale_tween.kill()

func set_active(value: bool) -> void:
	active = value
	if value:
		_stuck_accum = 0.0
		_pick_waypoint()
