class_name AimWallTarget
extends Area3D
## Practice disc for the wall arena (mesh/collision/billboard rotation live
## in aim_wall_target.tscn). Sits just in front of the practice wall. Every
## hit flashes it (white emission flash + small scale bump) and deals 1
## damage; at hp hits it pops (scale animation) and emits target_killed -
## the arena then hides it and spawns the next one at a random wall point.
## Collision layer 2 so the aim system raycast hits it before the wall.

signal target_killed(at: Vector3)

@export var target_color := Color(1, 0.25, 0.2)
@export var hp := 1
@export var hit_flash_color := Color(1, 1, 1, 1)

@onready var _visual: MeshInstance3D = $Visual

var hp_current := 1

var _material: StandardMaterial3D
var _base_energy := 2.0
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

## Resets the disc (scale + full hp) before the arena shows it again.
func reset() -> void:
	_kill_scale_tween()
	scale = Vector3.ONE
	hp_current = hp

## Called by the local aim system on a hit. Flashes, takes damage, and pops
## away once hp hits zero. Returns true when the hit was lethal (target died).
func hit(at: Vector3) -> bool:
	_flash()
	hp_current -= 1
	if hp_current <= 0:
		_kill(at)
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

func _kill(at: Vector3) -> void:
	_pop()
	hp_current = hp
	target_killed.emit(at)

func _pop() -> void:
	_kill_scale_tween()
	scale = Vector3.ONE * 1.5
	_scale_tween = create_tween()
	_scale_tween.tween_property(self, "scale", Vector3.ONE, 0.18) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _kill_scale_tween() -> void:
	if _scale_tween and _scale_tween.is_valid():
		_scale_tween.kill()
