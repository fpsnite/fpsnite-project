class_name AimHub
extends Node3D
## Main hub: the player spawns here and walks onto one of the three
## teleporter pads (scene children) to enter an arena. Holds only the player
## spawn export - all room/pad building lives in AimRoom/AimPad children.

@export var player_spawn_local := Vector3(0, 1, 0)
