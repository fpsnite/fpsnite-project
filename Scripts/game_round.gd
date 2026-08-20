extends Node
## Combat match manager for multiplayer modes (FFA / TDM / 1v1).
## The master client drives an FSM:
##   WAITING → STARTING → PLAYING → VICTORY → (return to menu)
## FFA is endless (no first-to-X, play until everyone leaves).
## TDM is first-to-15 team kills; 1v1 is first-to-10 individual kills.
## Aim training is handled by its own scene — this script only manages
## multiplayer combat modes.

const MENU_SCENE := "res://Scenes/mainui.tscn"

## Slow-motion burst when a match ends, then the end screen.
const SLOWMO_SCALE := 0.25
const SLOWMO_DURATION := 1.5

enum State { WAITING = 0, STARTING = 1, PLAYING = 2, VICTORY = 3 }

signal kill_scored(killer_id: int)

@export var min_players := 2
@export var grace_time := 5.0
@export var countdown_time := 5.0
@export var victory_delay := 8.0

var _fsm := FSM.new()
var _mirror_state: int = State.WAITING
var _remaining := 0.0
var _last_second := -1
var _current_mode := "ffa"
var _champion_pid := -1
var _champion_team := -1

## Team assignment: player_id → team_index (0 = blue, 1 = red).
## TDM assigns alternating teams on join. 1v1 assigns based on join order.
## FFA uses no teams.
var _teams: Dictionary = {}
## Kill scores: player_id → kill count.
var _kill_scores: Dictionary = {}
## Death scores: player_id → death count (for the backend match report).
var _death_scores: Dictionary = {}

@onready var status_label: Label = get_node("../RoundHUD/StatusLabel")
@onready var timer_label: Label = get_node("../RoundHUD/TimerLabel")
@onready var light_label: Label = get_node("../RoundHUD/LightLabel")

var _weapon_system: Node = null
var _end_screen: CanvasLayer = null
var _end_screen_shown := false
## Elapsed playing time (seconds), tracked for the backend match-result
## report. Reset when a match starts, frozen at victory.
var _match_elapsed := 0.0

## True once the master FSM started. The FSM broadcasts RPCs (scores, teams,
## state) - those are safe only after the lobby's spawn gate finished, so the
## start is polled from _process instead of _ready.
var _fsm_started := false
## Players whose score/team seeds still await their spawn (join happens before
## their scene loads; broadcasting earlier would be dropped as unknown RPCs).
var _pending_seeds: Array[int] = []

## Free Build disables the round entirely (no FSM, scores, teams or end
## screen). The node stays in the "round" group so consumers get safe
## defaults; the round HUD labels are hidden.
var _disabled := false
var _registered := false

func _ready() -> void:
	add_to_group("round")
	_current_mode = Settings.pending_mode
	_disabled = GameModes.is_build(_current_mode)
	if _disabled:
		status_label.visible = false
		timer_label.visible = false
		light_label.visible = false
		return
	Fusion.register_broadcast_receiver(self)
	_registered = true
	Fusion.player_joined.connect(_on_player_joined)
	Fusion.player_left.connect(_on_player_left)
	_end_screen = get_node_or_null("../RoundEnd")
	_fsm.add_state(&"waiting", _enter_waiting, Callable(), _tick_waiting)
	_fsm.add_state(&"starting", _enter_starting, Callable(), _tick_countdown)
	_fsm.add_state(&"playing", _enter_playing, Callable(), _tick_playing)
	_fsm.add_state(&"victory", _enter_victory, Callable(), _tick_victory)
	call_deferred("_find_weapon_system")
	if Fusion.is_master_client():
		pass  # FSM starts via _try_start_fsm once the lobby spawns everyone
	else:
		_apply_ui()

func _find_weapon_system() -> void:
	_weapon_system = get_tree().get_first_node_in_group("weapon_system")
	if _weapon_system and _weapon_system.has_signal("player_killed"):
		_weapon_system.player_killed.connect(_on_player_killed)

## Master only: initialize kill scores (and teams for team modes) for the
## players already in the room. player_joined only fires for newcomers, and
## _reset_match_state wipes these dicts, so every match start re-seeds them.
func _seed_existing_players() -> void:
	for pid in Network.room_player_ids():
		_kill_scores[pid] = 0
		_death_scores[pid] = 0
		Fusion.rpc(submit_kill_score, pid, 0)
		Fusion.rpc(submit_death_score, pid, 0)
	if _current_mode in ["tdm", "1v1"]:
		_assign_teams()

func _exit_tree() -> void:
	if _registered:
		Fusion.unregister_broadcast_receiver(self)

func _process(delta: float) -> void:
	if not is_inside_tree():
		return
	_update_debug_tick(delta)
	if _disabled:
		return
	# Elapsed playing time accumulates on EVERY client (the mirrored state is
	# the same everywhere), so the backend match report carries a real
	# duration for non-hosts too, not just the master's FSM tick.
	if _mirror_state == State.PLAYING:
		_match_elapsed += delta
	if Fusion.is_master_client():
		_try_start_fsm()
		if not _pending_seeds.is_empty():
			_flush_pending_seeds()
		_fsm.tick(delta)
		_apply_ui()

var _debug_timer := 0.0

func _update_debug_tick(delta: float) -> void:
	_debug_timer -= delta
	if _debug_timer <= 0.0:
		_debug_timer = 0.2
		_update_debug()

func _update_debug() -> void:
	var dbg: Label = get_node_or_null("../RoundHUD/DebugLabel")
	if dbg == null:
		return
	var fps := Engine.get_frames_per_second()
	var ping := "-" if not Fusion.is_connected_to_photon() else "%.0f" % (Fusion.get_rtt() * 1000.0)
	dbg.text = "%s ms  %d" % [ping, fps]

# --- Public API ---

func is_round_active() -> bool:
	if _disabled:
		return false
	return _mirror_state == State.PLAYING

## True once the match has ended (no kills / respawns should happen).
func is_match_over() -> bool:
	if _disabled:
		return false
	return _mirror_state == State.VICTORY

func is_red_light() -> bool:
	return false

func speed_scale() -> float:
	return 1.0

func get_team(player_id: int) -> int:
	return _teams.get(player_id, 0)

func get_kill_score(player_id: int) -> int:
	return int(_kill_scores.get(player_id, 0))

func get_mode() -> String:
	return _current_mode

# --- FSM states (master only) ---

## Master only: the round's RPC broadcasts are safe only after the lobby's
## spawn gate finished (every peer's match scene loaded + receivers
## registered). Poll the lobby instead of broadcasting from _ready, which
## would race peers still loading.
func _try_start_fsm() -> void:
	if _fsm_started:
		return
	if not Fusion.is_master_client() or not Fusion.is_in_room():
		return
	var lobby := get_tree().get_first_node_in_group("lobby")
	if lobby == null:
		return
	for pid in Network.room_player_ids():
		if not lobby.has_spawned(pid):
			return
	_fsm_started = true
	_flush_pending_seeds()
	_fsm.change(&"waiting")

func _enter_waiting() -> void:
	_last_second = -1
	_match_elapsed = 0.0
	_reset_match_state()
	# Re-seed scores/teams for whoever is in the room: player_joined won't
	# re-fire for players present when the scene loaded, and reset above
	# wipes teams each round. Runs on the master before the first spawn.
	_seed_existing_players()
	_broadcast_state(State.WAITING)

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

var _wait_hold := 0.0

func _enter_starting() -> void:
	_remaining = countdown_time
	_last_second = -1
	_broadcast_state(State.STARTING)

func _tick_countdown(delta: float) -> void:
	_remaining -= delta
	if _remaining <= 0.0:
		_fsm.change(&"playing")
		return
	_broadcast_if_second(State.STARTING)

func _enter_playing() -> void:
	_remaining = 0.0 if _current_mode == "ffa" else GameModes.kill_target(_current_mode) * 30.0
	_last_second = -1
	_broadcast_state(State.PLAYING)

func _tick_playing(delta: float) -> void:
	if _current_mode != "ffa":
		_remaining -= delta
		if _remaining <= 0.0:
			_finish_match()
			return
	# Check win condition (TDM / 1v1)
	if _current_mode in ["tdm", "1v1"] and _check_victory():
		return
	_broadcast_if_second(State.PLAYING)

func _check_victory() -> bool:
	var target := GameModes.kill_target(_current_mode)
	if target <= 0:
		return false
	if _current_mode == "tdm":
		var team_scores := _team_kill_totals()
		if team_scores.get(0, 0) >= target or team_scores.get(1, 0) >= target:
			_champion_team = 0 if team_scores.get(0, 0) >= target else 1
			_fsm.change(&"victory")
			return true
	elif _current_mode == "1v1":
		for pid in _kill_scores:
			if int(_kill_scores[pid]) >= target:
				_champion_pid = pid
				_fsm.change(&"victory")
				return true
	return false

func _finish_match() -> void:
	# Timeout: whoever is ahead wins
	if _current_mode == "tdm":
		var team_scores := _team_kill_totals()
		_champion_team = 0 if team_scores.get(0, 0) >= team_scores.get(1, 0) else 1
	elif _current_mode == "1v1":
		var best_score := -1
		for pid in _kill_scores:
			if int(_kill_scores[pid]) > best_score:
				best_score = int(_kill_scores[pid])
				_champion_pid = pid
	_fsm.change(&"victory")

func _enter_victory() -> void:
	_last_second = -1
	_remaining = victory_delay
	_broadcast_state(State.VICTORY)
	Fusion.rpc(submit_victory, _champion_pid, _champion_team)
	_start_slowmo()

## Slow-mo on the final kill: master starts it locally and mirrors it to
## every client. Each client restores the time scale on its own timer.
func _start_slowmo() -> void:
	sync_slowmo(SLOWMO_SCALE, SLOWMO_DURATION)
	Fusion.rpc(sync_slowmo, SLOWMO_SCALE, SLOWMO_DURATION)

@rpc("any_peer", "call_local")
func sync_slowmo(scale: float, duration: float) -> void:
	Engine.time_scale = scale
	get_tree().create_timer(duration, true, false, true).timeout \
		.connect(func() -> void: Engine.time_scale = 1.0, CONNECT_ONE_SHOT)

func _tick_victory(delta: float) -> void:
	_remaining -= delta
	if _remaining <= 0.0:
		return_to_menu()

func return_to_menu() -> void:
	get_tree().paused = false
	Engine.time_scale = 1.0
	Fusion.rpc(submit_return_to_menu)
	get_tree().change_scene_to_file(MENU_SCENE)

# --- Team assignment (master only, TDM / 1v1) ---

func _assign_teams() -> void:
	if _current_mode not in ["tdm", "1v1"]:
		return
	# Seed from the actual room members (plus any known ids) - the dict is
	# only populated via submit_team RPCs, so iterating it alone would never
	# assign the first players a team.
	var pids := Network.room_player_ids()
	for pid in _teams:
		if not pids.has(pid):
			pids.append(pid)
	pids.sort()
	for i in pids.size():
		var team: int
		if _current_mode == "tdm":
			team = i % 2
		else:
			team = i
		if _teams.get(pids[i], -1) != team:
			_teams[pids[i]] = team
			Fusion.rpc(submit_team, pids[i], team)

# --- Kill scoring (master only) ---

func _on_player_killed(killer_id: int, target_id: int) -> void:
	if not Fusion.is_master_client():
		return
	if killer_id > 0:
		_kill_scores[killer_id] = int(_kill_scores.get(killer_id, 0)) + 1
		Fusion.rpc(submit_kill_score, killer_id, int(_kill_scores[killer_id]))
		kill_scored.emit(killer_id)
	if target_id > 0:
		_death_scores[target_id] = int(_death_scores.get(target_id, 0)) + 1
		Fusion.rpc(submit_death_score, target_id, int(_death_scores[target_id]))

func _team_kill_totals() -> Dictionary:
	var totals := {0: 0, 1: 0}
	for pid in _kill_scores:
		var team: int = _teams.get(pid, 0)
		totals[team] = totals.get(team, 0) + int(_kill_scores[pid])
	return totals

# --- Player join / leave (master only) ---

func _on_player_joined(player_id: int, _extra: Variant) -> void:
	if Fusion.is_master_client():
		_kill_scores[player_id] = 0
		_death_scores[player_id] = 0
		# The newcomer joins before their match scene loads - broadcast their
		# seeds (and team) only once the lobby spawned them (see _flush_pending_seeds).
		if not _pending_seeds.has(player_id):
			_pending_seeds.append(player_id)
		_flush_pending_seeds()
	else:
		_apply_ui()

func _on_player_left(player_id: int, _extra: Variant) -> void:
	if Fusion.is_master_client():
		_kill_scores.erase(player_id)
		_death_scores.erase(player_id)
		_teams.erase(player_id)
		_pending_seeds.erase(player_id)
		if _current_mode in ["tdm", "1v1"]:
			_assign_teams()
	else:
		_apply_ui()

## Master only: broadcast a joined player's score/team seeds once the lobby
## has spawned them - i.e. their scene acked - so no broadcast RPC ever lands
## on a peer still loading its match scene.
func _flush_pending_seeds() -> void:
	if not Fusion.is_master_client():
		return
	var lobby := get_tree().get_first_node_in_group("lobby")
	if lobby == null:
		return
	var i := 0
	while i < _pending_seeds.size():
		var pid: int = _pending_seeds[i]
		if lobby.has_spawned(pid):
			if _current_mode in ["tdm", "1v1"]:
				_assign_teams()
			Fusion.rpc(submit_kill_score, pid, 0)
			Fusion.rpc(submit_death_score, pid, 0)
			_pending_seeds.remove_at(i)
		else:
			i += 1

# --- Networking ---

func _broadcast_state(state_id: int) -> void:
	_sync_state_mirror(state_id, _remaining)
	Fusion.rpc(sync_round_state, state_id, _remaining, _current_mode)

func _broadcast_if_second(state_id: int) -> void:
	var sec := ceili(_remaining) if _remaining > 0.0 else 0
	if sec != _last_second:
		_last_second = sec
		_broadcast_state(state_id)

@rpc("any_peer", "call_local")
func sync_round_state(state_id: int, remaining: float, mode: String) -> void:
	if Fusion.is_master_client():
		return
	_sync_state_mirror(state_id, remaining)
	_current_mode = mode

func _sync_state_mirror(state_id: int, remaining: float) -> void:
	_mirror_state = state_id
	_remaining = remaining
	_apply_ui()

@rpc("any_peer", "call_local")
func submit_team(player_id: int, team: int) -> void:
	_teams[player_id] = team
	_apply_ui()

@rpc("any_peer", "call_local")
func submit_kill_score(player_id: int, score: int) -> void:
	_kill_scores[player_id] = score
	_apply_ui()

@rpc("any_peer", "call_local")
func submit_death_score(player_id: int, score: int) -> void:
	_death_scores[player_id] = score

@rpc("any_peer", "call_local")
func submit_victory(champion_pid: int, champion_team: int) -> void:
	_champion_pid = champion_pid
	_champion_team = champion_team
	_apply_ui()
	# Report the finished match to the backend (fire-and-forget, local player
	# only): kills/deaths for stats + leaderboard, win flag for coins/xp.
	if _current_mode != "ffa":
		var local := Fusion.get_local_player_id()
		if local <= 0:
			return
		var won := champion_pid == local
		if champion_team >= 0:
			won = _teams.get(local, -1) == champion_team
		var duration := int(_match_elapsed)
		Backend.report_match_result(
			int(_kill_scores.get(local, 0)),
			int(_death_scores.get(local, 0)),
			won,
			duration)

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
	Engine.time_scale = 1.0
	get_tree().change_scene_to_file(MENU_SCENE)

## Match reset: wipe all scores, teams, and champion state.
func _reset_match_state() -> void:
	_kill_scores.clear()
	_death_scores.clear()
	_teams.clear()
	_champion_pid = -1
	_champion_team = -1
	Fusion.rpc(submit_match_reset)

@rpc("any_peer", "call_local")
func submit_match_reset() -> void:
	_kill_scores.clear()
	_death_scores.clear()
	_teams.clear()
	_champion_pid = -1
	_champion_team = -1
	_mirror_state = State.WAITING
	_apply_ui()

# --- HUD ---

func _apply_ui() -> void:
	if _mirror_state != State.VICTORY:
		_end_screen_shown = false
		if _end_screen:
			_end_screen.hide_result()
	match _mirror_state:
		State.WAITING:
			var count := Fusion.get_room().get_players().size() if Fusion.is_in_room() else 0
			status_label.text = "WAITING FOR PLAYERS  (%d/%d)" % [count, Network.MAX_PLAYERS]
			timer_label.text = ""
			light_label.text = ""
		State.STARTING:
			status_label.text = "GET READY  -  %s" % GameModes.mode_name(_current_mode).to_upper()
			timer_label.text = str(ceili(_remaining))
			light_label.text = ""
		State.PLAYING:
			status_label.text = _score_text()
			timer_label.text = _timer_text()
			light_label.text = ""
		State.VICTORY:
			status_label.text = _winner_text()
			timer_label.text = "returning to menu in %d" % ceili(_remaining)
			light_label.text = ""
			_show_end_screen()
			_update_end_countdown()

## Shows the VICTORY / DEFEAT / DRAW screen once per match end (every client).
func _show_end_screen() -> void:
	if _end_screen == null or _end_screen_shown:
		return
	_end_screen_shown = true
	var local := Fusion.get_local_player_id()
	var draw := _champion_pid <= 0
	var won := not draw and _champion_pid == local
	var winner_name := _player_name(_champion_pid) if not draw else ""
	_end_screen.show_result(draw, won, winner_name, _1v1_score_text())

func _update_end_countdown() -> void:
	if _end_screen:
		_end_screen.update_countdown(ceili(_remaining))

func _score_text() -> String:
	if _current_mode == "ffa":
		return _ffa_score_text()
	elif _current_mode == "tdm":
		return _tdm_score_text()
	elif _current_mode == "1v1":
		return _1v1_score_text()
	return "PLAYING"

func _ffa_score_text() -> String:
	var lobby := get_tree().get_first_node_in_group("lobby")
	if lobby == null:
		return "FFA"
	var entries: Array[Dictionary] = []
	for pid in lobby._characters:
		entries.append({
			"name": _player_name(pid),
			"score": int(_kill_scores.get(pid, 0)),
		})
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a["score"] > b["score"])
	var parts: PackedStringArray = []
	for i in mini(3, entries.size()):
		parts.append("%s %d" % [entries[i]["name"], entries[i]["score"]])
	return "FFA  " + " | ".join(parts) if parts.size() > 0 else "FFA"

func _tdm_score_text() -> String:
	var ts := _team_kill_totals()
	return "BLUE %d  -  RED %d" % [ts.get(0, 0), ts.get(1, 0)]

func _1v1_score_text() -> String:
	var lobby := get_tree().get_first_node_in_group("lobby")
	if lobby == null:
		return "1v1"
	var pids: Array[int] = []
	for pid in lobby._characters:
		pids.append(pid)
	pids.sort()
	if pids.size() < 2:
		return "1v1"
	return "%s %d  -  %s %d" % [
		_player_name(pids[0]), int(_kill_scores.get(pids[0], 0)),
		_player_name(pids[1]), int(_kill_scores.get(pids[1], 0))]

func _timer_text() -> String:
	if _current_mode == "ffa":
		return ""
	if _remaining > 0.0:
		var total := ceili(_remaining)
		return "%d:%02d" % [total / 60, total % 60]
	return ""

func _winner_text() -> String:
	if _current_mode == "tdm":
		if _champion_team < 0:
			return "DRAW"
		return "%s WINS" % ("BLUE" if _champion_team == 0 else "RED")
	elif _current_mode == "1v1":
		if _champion_pid <= 0:
			return "DRAW"
		return "%s WINS" % _player_name(_champion_pid)
	return "MATCH OVER"

func _player_name(player_id: int) -> String:
	var lobby := get_tree().get_first_node_in_group("lobby")
	if lobby == null:
		return "P%d" % player_id
	return lobby._player_name(player_id)

func _player_count() -> int:
	return Network.room_player_ids().size() if Fusion.is_in_room() else 0
