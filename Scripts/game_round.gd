extends Node
## Round system for the lobby (Red Light Green Light tournament).
## The master client drives an FSM:
##   WAITING -> STARTING -> PLAYING -> INTERMISSION -> STARTING -> ... -> VICTORY
## Elimination persists across rounds: only win-zone finishers survive a round.
## Clients mirror state + light via broadcast RPCs for the HUD and the freeze.

const MENU_SCENE := "res://mainui.tscn"

enum State { WAITING = 0, STARTING = 1, PLAYING = 2, INTERMISSION = 3, VICTORY = 4 }

## Emitted on the master when a round's game timer ends (used by the lobby to
## award +1 to every survivor). Clients receive scores via submit_score.
signal round_finished
## Emitted on the master when a player reaches the WinArea mid-round (used
## by the lobby to award +1 immediately and teleport the winner away).
signal player_won(player_id: int)

@export var min_players := 2
@export var grace_time := 10.0  # hidden join window after min players is reached
@export var countdown_time := 5.0
@export var play_time := 60.0
@export var green_time := 5.0
@export var red_time := 3.5
@export var intermission_time := 10.0
@export var victory_delay := 8.0
@export var move_threshold := 0.6  # meters of travel during red light before the reset penalty
# Per-round difficulty curve (round 1 uses the base values above).
@export var speed_increase := 0.10  # +10% move speed per round
@export var game_time_decrease := 5.0  # -5s game timer per round
@export var green_time_decrease := 0.5  # -0.5s green per round
@export var red_time_decrease := 0.5  # -0.5s red per round
@export var min_game_time := 20.0
@export var min_green_time := 1.0
@export var min_red_time := 1.0

var _fsm := FSM.new()
var _mirror_state: int = State.WAITING
var _is_green := false
var _remaining := 0.0
var _light_remaining := 0.0
var _wait_hold := 0.0
var _last_second := -1

## The round about to be played (starts at 1, increments at intermission).
var current_round := 1
var _champion_pid := -1
var _round_green := 5.0  # effective light times for the current round
var _round_red := 3.5

## GameArena elimination/win state, master-authoritative, mirrored on all
## clients via the submit_* broadcast RPCs.
## eliminated: players dead for the rest of the match (spectate until the end).
## winners:    players who reached the win zone in any round - they survive.
## sitting_out: players who joined mid-match; they spectate until the next round.
var eliminated: Dictionary = {}
var winners: Dictionary = {}
var sitting_out: Dictionary = {}
var _light_snapshots: Dictionary = {}  # player_id -> Vector2 (x, z) at red-light onset

@onready var status_label: Label = get_node("../RoundHUD/StatusLabel")
@onready var timer_label: Label = get_node("../RoundHUD/TimerLabel")
@onready var light_label: Label = get_node("../RoundHUD/LightLabel")

## GameArena nodes (absent on maps without an arena) - all gameplay checks
## no-op when they are missing.
@onready var detection_area: Area3D = get_node_or_null("../GameArena/PlayerDetectionArea")
@onready var win_area: Area3D = get_node_or_null("../GameArena/WinArea")
@onready var indicator_mesh: MeshInstance3D = get_node_or_null("../GameArena/IndicatorMesh")

var _indicator_material: StandardMaterial3D

func _ready() -> void:
	add_to_group("round")
	Fusion.register_broadcast_receiver(self)
	Fusion.player_joined.connect(_on_player_joined)
	Fusion.player_left.connect(_on_player_left)
	_fsm.add_state(&"waiting", _enter_waiting, Callable(), _tick_waiting)
	_fsm.add_state(&"starting", _enter_starting, Callable(), _tick_countdown)
	_fsm.add_state(&"playing", _enter_playing, Callable(), _tick_playing)
	_fsm.add_state(&"intermission", _enter_intermission, Callable(), _tick_intermission)
	_fsm.add_state(&"victory", _enter_victory, Callable(), _tick_victory)
	_indicator_material = StandardMaterial3D.new()
	_indicator_material.emission_enabled = true
	_indicator_material.emission_energy_multiplier = 2.0
	if indicator_mesh:
		indicator_mesh.material_override = _indicator_material
	_apply_indicator()
	if Fusion.is_master_client():
		_fsm.change(&"waiting")
	else:
		_apply_ui()

func _exit_tree() -> void:
	Fusion.unregister_broadcast_receiver(self)

func _process(delta: float) -> void:
	if not is_inside_tree():
		return
	if Fusion.is_master_client():
		_fsm.tick(delta)
		_apply_ui()
		if _mirror_state == State.PLAYING:
			_check_red_light_violations()
			_check_wins()
	_debug_timer -= delta
	if _debug_timer <= 0.0:
		_debug_timer = 0.2
		_update_debug()

var _debug_timer := 0.0

## Bottom-left status line: "NNNN ms  [FPS]" (ping milliseconds, frames per
## second) in plain white at 65% opacity.
func _update_debug() -> void:
	var dbg: Label = get_node_or_null("../RoundHUD/DebugLabel")
	if dbg == null:
		return
	var fps := Engine.get_frames_per_second()
	var ping := "-" if not Fusion.is_connected_to_photon() else "%.0f" % (Fusion.get_rtt() * 1000.0)
	dbg.text = "%s ms  %d" % [ping, fps]

# --- API used by gameplay (player_instance, lobby, spectate) ---

func is_round_active() -> bool:
	return _mirror_state == State.PLAYING

func is_red_light() -> bool:
	return _mirror_state == State.PLAYING and not _is_green

## Move speed multiplier for the current round (round 1 = 1.0).
func speed_scale() -> float:
	return 1.0 + (current_round - 1) * speed_increase

# --- FSM states (master only) ---

## Match start: reset all tournament state. Everyone waits in the lobby
## spawn area; the arena teleport happens when the round actually starts.
func _enter_waiting() -> void:
	_last_second = -1
	_is_green = true
	_reset_round_state()
	_broadcast_state(State.WAITING)
	_broadcast_light()

## Hidden grace window: nothing is shown, late joiners can still hop in.
func _tick_waiting(delta: float) -> void:
	if not Fusion.is_in_room():
		return
	var players := Fusion.get_room().get_players().size()
	if players >= min_players:
		_wait_hold += delta
		if _wait_hold >= grace_time:
			_fsm.change(&"starting")
	else:
		_wait_hold = 0.0

func _enter_starting() -> void:
	_remaining = countdown_time
	_last_second = -1
	_is_green = true
	_broadcast_state(State.STARTING)
	_broadcast_light()

func _tick_countdown(delta: float) -> void:
	_remaining -= delta
	if _remaining <= 0.0:
		_fsm.change(&"playing")
		return
	_broadcast_if_second(State.STARTING)

## Round start: sitting-out joiners become alive, everyone teleports to the
## start line, and the game timer + light phases are set for this round's
## difficulty level.
func _enter_playing() -> void:
	_revive_sitting_out()
	_remaining = _round_game_time()
	_round_green = _round_light_time(green_time, green_time_decrease, min_green_time)
	_round_red = _round_light_time(red_time, red_time_decrease, min_red_time)
	_light_remaining = _round_green
	_is_green = true
	_last_second = -1
	var lobby := get_tree().get_first_node_in_group("lobby")
	if lobby and lobby.has_method("teleport_to_start_line"):
		lobby.teleport_to_start_line()
	_broadcast_state(State.PLAYING)
	_broadcast_light()

func _tick_playing(delta: float) -> void:
	_remaining -= delta
	_light_remaining -= delta
	if _light_remaining <= 0.0:
		_is_green = not _is_green
		_light_remaining = _round_green if _is_green else _round_red
		if _is_green:
			_light_snapshots.clear()
		else:
			_snapshot_positions()
		_broadcast_light()
	if _remaining <= 0.0:
		_sweep_eliminations()
		round_finished.emit()
		if winners.size() <= 1:
			_champion_pid = winners.keys()[0] if winners.size() == 1 else -1
			_fsm.change(&"victory")
		else:
			_fsm.change(&"intermission")
		return
	_broadcast_if_second(State.PLAYING)

## Time between rounds: the survivors stand around while the difficulty is
## tuned up for the next round.
func _enter_intermission() -> void:
	_last_second = -1
	_is_green = true
	current_round += 1
	_remaining = intermission_time
	_broadcast_state(State.INTERMISSION)
	_broadcast_light()

func _tick_intermission(delta: float) -> void:
	_remaining -= delta
	if _remaining <= 0.0:
		_fsm.change(&"starting")
		return
	_broadcast_if_second(State.INTERMISSION)

## Only one player left (or none survived): show the champion, then send
## everyone back to the main menu.
func _enter_victory() -> void:
	_last_second = -1
	_is_green = true
	_remaining = victory_delay
	_broadcast_state(State.VICTORY)
	_broadcast_light()
	Fusion.rpc(submit_victory, _champion_pid)
	Fusion.rpc(submit_feed, &"champion", _champion_pid)

func _tick_victory(delta: float) -> void:
	_remaining -= delta
	if _remaining <= 0.0:
		return_to_menu()

func return_to_menu() -> void:
	get_tree().paused = false
	Fusion.rpc(submit_return_to_menu)
	get_tree().change_scene_to_file(MENU_SCENE)

# --- Difficulty scaling ---

func _round_game_time() -> float:
	return maxf(min_game_time, play_time - (current_round - 1) * game_time_decrease)

func _round_light_time(base: float, decrease: float, floor: float) -> float:
	return maxf(floor, base - (current_round - 1) * decrease)

# --- Networking ---

func _broadcast_state(state_id: int) -> void:
	_sync_state_mirror(state_id, _remaining)
	Fusion.rpc(sync_round_state, state_id, _remaining)

func _broadcast_light() -> void:
	_apply_indicator()
	Fusion.rpc(sync_light, _is_green)

func _broadcast_if_second(state_id: int) -> void:
	var sec := ceili(_remaining)
	if sec != _last_second:
		_last_second = sec
		_broadcast_state(state_id)

@rpc("any_peer", "call_local")
func sync_round_state(state_id: int, remaining: float) -> void:
	if Fusion.is_master_client():
		return
	if state_id != State.PLAYING:
		_is_green = true
	_sync_state_mirror(state_id, remaining)

@rpc("any_peer", "call_local")
func sync_light(is_green: bool) -> void:
	if Fusion.is_master_client():
		return
	_is_green = is_green
	_apply_ui()
	_apply_indicator()

func _sync_state_mirror(state_id: int, remaining: float) -> void:
	_mirror_state = state_id
	_remaining = remaining
	_apply_ui()
	_apply_indicator()

## Players joining mid-match spectate (eliminated) until the next round starts.
func _on_player_joined(player_id: int, _extra: Variant) -> void:
	if Fusion.is_master_client():
		if _mirror_state != State.WAITING:
			sitting_out[player_id] = true
			Fusion.rpc(submit_elimination, player_id)
	else:
		_apply_ui()

## A leaver stops counting toward the tournament.
func _on_player_left(player_id: int, _extra: Variant) -> void:
	if Fusion.is_master_client():
		eliminated.erase(player_id)
		winners.erase(player_id)
		sitting_out.erase(player_id)
		_light_snapshots.erase(player_id)
	else:
		_apply_ui()

# --- GameArena gameplay (master authoritative) ---

## Red light onset: remember where every player stands. Anyone still inside
## the detection area who moves beyond move_threshold during the red light
## gets reset back to the start of the arena.
func _snapshot_positions() -> void:
	_light_snapshots.clear()
	var lobby := get_tree().get_first_node_in_group("lobby")
	if lobby == null:
		return
	for pid in lobby._characters:
		var body: Node3D = lobby._characters[pid]
		_light_snapshots[pid] = Vector2(body.global_position.x, body.global_position.z)

func _check_red_light_violations() -> void:
	if _is_green or detection_area == null:
		return
	for body in detection_area.get_overlapping_bodies():
		if not (body is CharacterBody3D):
			continue
		var pid := _player_id_of(body)
		if pid <= 0 or eliminated.has(pid) or winners.has(pid):
			continue
		if not _light_snapshots.has(pid):
			continue
		var pos := Vector2(body.global_position.x, body.global_position.z)
		if pos.distance_to(_light_snapshots[pid]) > move_threshold:
			_penalize(pid)

## Red-light violation: teleport the player back to the start line and re-snap
## them there so standing still keeps them safe for the rest of this phase.
func _penalize(player_id: int) -> void:
	var lobby := get_tree().get_first_node_in_group("lobby")
	if lobby == null:
		return
	lobby.reset_player_to_start(player_id)
	Fusion.rpc(submit_feed, &"strike", player_id)
	var character: Node = lobby._characters.get(player_id)
	if character:
		_light_snapshots[player_id] = Vector2(character.global_position.x, character.global_position.z)

func _check_wins() -> void:
	if win_area == null:
		return
	for body in win_area.get_overlapping_bodies():
		if not (body is CharacterBody3D):
			continue
		var pid := _player_id_of(body)
		if pid > 0 and not eliminated.has(pid) and not winners.has(pid):
			_declare_win(pid)

func _player_id_of(body: Node) -> int:
	var rep: Node = body.get_node_or_null("FusionServerReplicator")
	return rep.get_input_authority() if rep else 0

func _eliminate(player_id: int) -> void:
	if eliminated.has(player_id) or winners.has(player_id):
		return
	eliminated[player_id] = true
	_light_snapshots.erase(player_id)
	Fusion.rpc(submit_elimination, player_id)

func _declare_win(player_id: int) -> void:
	if eliminated.has(player_id) or winners.has(player_id):
		return
	winners[player_id] = true
	player_won.emit(player_id)
	Fusion.rpc(submit_win, player_id)
	Fusion.rpc(submit_feed, &"win", player_id)

## Game timer ended: everyone who never reached the win zone is eliminated.
func _sweep_eliminations() -> void:
	var lobby := get_tree().get_first_node_in_group("lobby")
	if lobby == null:
		return
	for pid in lobby._characters:
		if eliminated.has(pid) or winners.has(pid):
			continue
		_eliminate(pid)

## Sitting-out players (mid-match joiners) become alive for this round.
func _revive_sitting_out() -> void:
	if sitting_out.is_empty():
		return
	for pid in sitting_out.keys():
		Fusion.rpc(submit_alive, pid)
	sitting_out.clear()

## Match reset: full wipe of elimination/win state, back to a fresh match.
func _reset_round_state() -> void:
	eliminated.clear()
	winners.clear()
	sitting_out.clear()
	_light_snapshots.clear()
	current_round = 1
	_champion_pid = -1
	Fusion.rpc(submit_round_reset)

@rpc("any_peer", "call_local")
func submit_elimination(player_id: int) -> void:
	eliminated[player_id] = true
	sitting_out.erase(player_id)
	var lobby := get_tree().get_first_node_in_group("lobby")
	var character: Node = lobby._characters.get(player_id) if lobby else null
	if character and character.has_method("become_eliminated"):
		character.become_eliminated()
	if player_id == Fusion.get_local_player_id():
		var spec := get_node_or_null("../SpectateManager")
		if spec and not spec._active:
			spec.toggle_spectate()

@rpc("any_peer", "call_local")
func submit_win(player_id: int) -> void:
	winners[player_id] = true

@rpc("any_peer", "call_local")
func submit_alive(player_id: int) -> void:
	eliminated.erase(player_id)
	sitting_out.erase(player_id)
	var lobby := get_tree().get_first_node_in_group("lobby")
	var character: Node = lobby._characters.get(player_id) if lobby else null
	if character and character.has_method("become_alive"):
		character.become_alive()

@rpc("any_peer", "call_local")
func submit_round_reset() -> void:
	eliminated.clear()
	winners.clear()
	sitting_out.clear()
	_light_snapshots.clear()
	current_round = 1
	_champion_pid = -1
	var lobby := get_tree().get_first_node_in_group("lobby")
	if lobby == null:
		return
	for pid in lobby._characters:
		var character: Node = lobby._characters[pid]
		if character.has_method("become_alive"):
			character.become_alive()
	var spec := get_node_or_null("../SpectateManager")
	if spec and spec._active:
		spec.toggle_spectate()

@rpc("any_peer", "call_local")
func submit_victory(champion_pid: int) -> void:
	_champion_pid = champion_pid
	_apply_ui()

## Kill feed event (strike/win/champion) - every client shows it locally.
@rpc("any_peer", "call_local")
func submit_feed(kind: StringName, player_id: int) -> void:
	var feed := get_tree().get_first_node_in_group("kill_feed")
	if feed:
		feed.add_event(kind, player_id)

@rpc("any_peer")
func submit_return_to_menu() -> void:
	if Fusion.is_master_client():
		return
	get_tree().paused = false
	get_tree().change_scene_to_file(MENU_SCENE)

## Doll light on the arena indicator: green while PLAYING + green light,
## red otherwise (the doll is watching between rounds).
func _apply_indicator() -> void:
	if _indicator_material == null:
		return
	var is_green_phase := _mirror_state == State.PLAYING and _is_green
	_indicator_material.emission = Color(0.3, 1.0, 0.3) if is_green_phase else Color(1.0, 0.2, 0.2)

# --- HUD ---

func _apply_ui() -> void:
	match _mirror_state:
		State.WAITING:
			var count := Fusion.get_room().get_players().size() if Fusion.is_in_room() else 0
			status_label.text = "WAITING FOR PLAYERS  (%d/%d)" % [count, Network.MAX_PLAYERS]
			timer_label.text = ""
			light_label.text = ""
		State.STARTING:
			status_label.text = "GET READY  -  ROUND %d" % current_round
			timer_label.text = str(ceili(_remaining))
			light_label.text = ""
		State.PLAYING:
			status_label.text = "ROUND %d  -  GO!" % current_round
			timer_label.text = str(ceili(_remaining))
			light_label.text = "GREEN LIGHT" if _is_green else "RED LIGHT"
			light_label.add_theme_color_override("font_color", Color(0.3, 0.9, 0.4) if _is_green else Color(0.9, 0.2, 0.2))
		State.INTERMISSION:
			status_label.text = "ROUND %d NEXT" % current_round
			timer_label.text = str(ceili(_remaining))
			light_label.text = ""
		State.VICTORY:
			if _champion_pid <= 0:
				status_label.text = "NO ONE SURVIVED"
			else:
				var number := 0
				var lobby := get_tree().get_first_node_in_group("lobby")
				if lobby:
					number = int(lobby._number_registry.get(_champion_pid, 0))
				status_label.text = "CHAMPION: #%03d" % number
			timer_label.text = "returning to menu in %d" % ceili(_remaining)
			light_label.text = ""
