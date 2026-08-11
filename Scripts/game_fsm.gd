class_name FSM
extends RefCounted
## Tiny finite state machine: states keyed by StringName with enter/exit/tick
## callables. Invalid callables are skipped safely.

signal state_changed(from: StringName, to: StringName)

var current: StringName = &""

var _states: Dictionary = {}

func add_state(state: StringName, enter: Callable = Callable(), exit: Callable = Callable(), tick: Callable = Callable()) -> void:
	_states[state] = {"enter": enter, "exit": exit, "tick": tick}

func change(state: StringName) -> void:
	if not _states.has(state) or state == current:
		return
	var from := current
	if _states.has(from) and _states[from]["exit"].is_valid():
		_states[from]["exit"].call()
	current = state
	if _states[state]["enter"].is_valid():
		_states[state]["enter"].call()
	state_changed.emit(from, state)

func tick(delta: float) -> void:
	if current in _states and _states[current]["tick"].is_valid():
		_states[current]["tick"].call(delta)
