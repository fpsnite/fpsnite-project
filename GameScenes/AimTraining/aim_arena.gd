class_name AimArena
extends Node3D
## Base class for every training arena. Owns the shared arena contract:
## scoring (score_hit counts only while running), the start/stop state
## machine (start/stop/toggle driven by the main instance's interact input),
## the exit pad back to the hub, and the exported player spawn point.
## Subclasses implement _on_start/_on_stop and add their own targets.

signal score_changed(score: int)
signal state_changed(running: bool)
signal exit_requested()

@export var arena_id := "arena"
@export var arena_name := "Arena"
@export var player_spawn_local := Vector3(0, 1, 6)

var score := 0
var running := false

func _ready() -> void:
	# The exit pad back to the hub is a scene child named ExitPad (unique
	# name); the base only wires it to the exit_requested signal.
	var pad := get_node_or_null("%ExitPad") as AimPad
	if pad:
		pad.activated.connect(_on_exit_pad_activated)

func _on_exit_pad_activated(_pad_id: String) -> void:
	exit_requested.emit()

## One scored hit - ignored while the arena is not running.
func score_hit() -> void:
	if running:
		score += 1
		score_changed.emit(score)

func start() -> void:
	if running:
		return
	running = true
	score = 0
	score_changed.emit(0)
	state_changed.emit(true)
	_on_start()

func stop() -> void:
	if not running:
		return
	running = false
	state_changed.emit(false)
	_on_stop()

func toggle() -> void:
	if running:
		stop()
	else:
		start()

## Virtual: subclass hook for run begin/end (start targets, spawn first
## one-shot, etc).
func _on_start() -> void:
	pass

func _on_stop() -> void:
	pass
