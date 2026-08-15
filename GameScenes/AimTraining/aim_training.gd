extends Node3D
## Aim Training main instance: owns the hub and every arena, teleports the
## player between them (hub pads + arena exit pads), routes every scored hit
## to the currently active arena, tracks per-arena best scores, drives the
## HUD and the crosshair override, and handles global input (F to
## start/stop). The pause drawer (PauseMenu node) handles Esc - its LEAVE
## ROOM button returns to the main menu. Adding a new arena = a scene with
## an AimArena script + a unique arena_id + a hub pad with the same id.

@onready var player: CharacterBody3D = $AimPlayer
@onready var system: Node3D = $AimSystem
@onready var hud: CanvasLayer = $AimHUD
@onready var hub: AimHub = $Hub
@onready var close_arena: AimArena = $CloseArena
@onready var long_arena: AimArena = $LongArena
@onready var wall_arena: AimArena = $WallArena

var _arenas: Dictionary = {}
var _best_scores: Dictionary = {}
var _current: Node3D = null

func _ready() -> void:
	_arenas = {"close": close_arena, "long": long_arena, "wall": wall_arena}
	system.hit_scored.connect(_on_target_hit)
	# Training weapons never run out: duplicate each WeaponData and flag it
	# infinite so the shared weapon.gd treats them as never-empty.
	var weapon := player.get_node_or_null("CameraPivot/Camera3D/Weapon")
	if weapon:
		# Training weapons keep a finite mag (the reload loop stays relevant)
		# but an endless reserve: shoot the mag dry, auto-reload, never run
		# out. Duplicate each WeaponData so the shared resources stay untouched.
		for i in weapon.loadout.size():
			var data: WeaponData = weapon.loadout[i].duplicate() as WeaponData
			data.infinite_reserve_ammo = true
			weapon.loadout[i] = data
		# The weapon equipped itself (the knife) before the loadout was patched,
		# so re-equip it to point current_data at its infinite duplicate too -
		# otherwise the held weapon keeps the original finite data.
		weapon._equip(weapon.weapon_index)
	for arena_id: String in _arenas:
		var arena: AimArena = _arenas[arena_id]
		arena.score_changed.connect(hud.set_score)
		arena.state_changed.connect(_on_arena_state)
		arena.exit_requested.connect(_go_hub)
	for pad in get_tree().get_nodes_in_group("aim_pad"):
		var aim_pad: AimPad = pad
		aim_pad.activated.connect(_on_pad_activated)
	teleport_to("hub")

## Every scored hit lands here from the local aim system; only the active
## arena counts it, and only while it is running.
func _on_target_hit() -> void:
	var arena := _current as AimArena
	if arena and arena.running:
		arena.score_hit()

func _on_arena_state(_running: bool) -> void:
	_update_hint()
	_update_best()

func _on_pad_activated(pad_id: String) -> void:
	teleport_to(pad_id)

func _go_hub() -> void:
	teleport_to("hub")

## Moves the player to a hub/arena by id: stops any run in the arena being
## left, positions the player at the target spawn, and updates HUD +
## crosshair. Repeated entry (standing on a pad) is a no-op.
func teleport_to(arena_id: String) -> void:
	var target: Node3D = hub if arena_id == "hub" else _arenas.get(arena_id)
	if target == null or target == _current:
		return
	if _current is AimArena:
		(_current as AimArena).stop()
	_current = target
	player.global_position = target.to_global(target.player_spawn_local)
	player.rotation = Vector3.ZERO
	player.velocity = Vector3.ZERO
	var in_arena := target is AimArena
	Crosshair.set_override(in_arena)
	hud.set_score_visible(in_arena)
	if in_arena:
		system.reset_mode_stats()
		var arena := target as AimArena
		hud.set_title(arena.arena_name)
		hud.set_score(0)
		hud.set_best(_best_scores.get(arena.arena_id, 0))
	else:
		hud.set_title("MAIN HUB")
	_update_hint()

func _update_hint() -> void:
	var arena := _current as AimArena
	if arena == null:
		hud.set_hint("WALK ONTO A PAD TO START TRAINING")
	elif arena.running:
		hud.set_hint("PRESS F TO STOP")
	else:
		hud.set_hint("PRESS F TO START")

func _update_best() -> void:
	var arena := _current as AimArena
	if arena == null:
		return
	var best: int = _best_scores.get(arena.arena_id, 0)
	if arena.score > best:
		_best_scores[arena.arena_id] = arena.score
		hud.set_best(arena.score)
		hud.set_hint("NEW BEST %d - PRESS F TO START" % arena.score)

## Global input: F toggles the active arena (Esc opens the pause drawer -
## the PauseMenu node in this scene handles it, and the drawer's LEAVE ROOM
## button returns to the main menu).
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("interact") and _current is AimArena:
		(_current as AimArena).toggle()
