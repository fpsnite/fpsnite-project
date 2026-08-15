class_name WallArena
extends AimArena
## One-shot wall arena: the big practice wall (PracticeWall scene node) sits
## across the far end. While running, exactly one glowing disc target exists
## at a random point on the wall; one hit despawns it and spawns the next
## after a short delay. Wall dimensions are read from the scene node at
## runtime so the target bounds always match what you build in the editor.

@export var spawn_delay := 0.4
@export var target_color := Color(1, 0.25, 0.2)
@export var target_margin := 0.6
@export var target_hp := 1

const WALL_TARGET_SCENE := preload("res://GameScenes/AimTraining/aim_wall_target.tscn")

var _wall: StaticBody3D
var _wall_half_x := 6.0
var _wall_top := 7.0
var _wall_front_z := -5.7

var _target: AimWallTarget
var _respawn_delay := 0.0

func _ready() -> void:
	super()
	_wall = $PracticeWall
	var collision := _wall.get_node_or_null("CollisionShape3D")
	if collision and collision.shape is BoxShape3D:
		var size: Vector3 = collision.shape.size
		_wall_half_x = size.x * 0.5
		_wall_top = size.y
		# The wall face that faces the player (the box is size.z thick along Z).
		_wall_front_z = _wall.position.z - size.z * 0.5
	_target = WALL_TARGET_SCENE.instantiate()
	_target.target_color = target_color
	_target.hp = target_hp
	add_child(_target)
	_target.target_killed.connect(_on_target_killed)
	_target.visible = false

func _on_start() -> void:
	_spawn_target()

func _on_stop() -> void:
	_target.visible = false
	_respawn_delay = 0.0

func _process(delta: float) -> void:
	if running and _respawn_delay > 0.0:
		_respawn_delay -= delta
		if _respawn_delay <= 0.0:
			_target.visible = false
			_spawn_target()

## Random point on the wall face, just in front of it so the ray hits the
## target before the wall.
func _spawn_target() -> void:
	var point := Vector3(
		randf_range(-_wall_half_x + target_margin, _wall_half_x - target_margin),
		randf_range(0.9, _wall_top - target_margin),
		_wall_front_z - 0.08)
	_target.position = point
	_target.reset()
	_target.visible = true

## The disc died (hp hits): let the pop play out, then respawn.
func _on_target_killed(_at: Vector3) -> void:
	if running:
		_respawn_delay = spawn_delay
