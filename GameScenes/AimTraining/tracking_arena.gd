class_name TrackingArena
extends AimArena
## Close/long tracking arena - one script, two instances. Spawns `target_count`
## patrolling AimTrackingTargets inside the exported bounds and runs them
## while the arena is running. The close arena uses a small box + slow
## targets; the long arena a big shallow box + faster, farther targets.

@export var target_count := 3
@export var target_speed_min := 2.0
@export var target_speed_max := 3.0
@export var half_x := 5.0
@export var half_z := 5.0
@export var y_min := 1.2
@export var y_max := 2.8
@export var target_color := Color(1, 0.45, 0.2)
@export var target_hp := 1

const TARGET_SCENE := preload("res://GameScenes/AimTraining/aim_tracking_target.tscn")

var _targets: Array[AimTrackingTarget] = []

func _ready() -> void:
	super()
	for i in target_count:
		_spawn_target()

func _spawn_target() -> void:
	var target: AimTrackingTarget = TARGET_SCENE.instantiate()
	target.speed = randf_range(target_speed_min, target_speed_max)
	target.hp = target_hp
	target.min_pos = Vector3(-half_x, y_min, -half_z)
	target.max_pos = Vector3(half_x, y_max, half_z)
	target.target_color = target_color
	add_child(target)
	target.position = _rand_point()
	_targets.append(target)

func _rand_point() -> Vector3:
	return Vector3(
		randf_range(-half_x, half_x),
		randf_range(y_min, y_max),
		randf_range(-half_z, half_z))

func _on_start() -> void:
	for target in _targets:
		target.set_active(true)

func _on_stop() -> void:
	for target in _targets:
		target.set_active(false)
