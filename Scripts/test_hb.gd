extends Node3D


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.


var last_tick := 0

func _process(_delta):
	var now := Time.get_ticks_msec()

	if last_tick != 0:
		var gap := now - last_tick

		if gap > 200:
			print("MAIN LOOP GAP: ", gap, " ms")

	last_tick = now
