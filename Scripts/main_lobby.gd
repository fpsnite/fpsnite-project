extends Node3D
## Main menu lobby (Part 3: dynamic podiums). The lobby IS a room: on load we
## auto-connect to Photon and create a hidden party room at the current mode.
## "Create Party" reveals the room code (read-only + copy button); "Join Party"
## switches rooms by code. Room members appear on the 8 podium slots with
## their name + skin; skins sync via a broadcast RPC.

const MAX_PODIUMS := 8

var _podium_previews: Array[Node3D] = []
var _podium_stages: Array[MeshInstance3D] = []
var _skin_registry: Dictionary = {}  # player_id -> skin index
var _in_room := false
## True from the first room_left until the follow-up (join/create) resolves
## via room_joined or room_op_failed. The Fusion plugin can emit room_left
## twice per leave (once at leave start, once after the leave completes) - a
## second emission must not restart the flow or it would overwrite a pending
## join with a fresh hidden room.
var _leave_pending := false
var _selected_mode := "test"
var _pending_join := ""
var _pending_mode := ""
var _reveal_code := false
## Bumped on every show/hide so a delayed hide can't kill an overlay that a
## newer transition re-showed.
var _overlay_token := 0

func _log(msg: String) -> void:
	print("[NET] main_lobby: " + msg)

func _ready() -> void:
	add_to_group("lobby")
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if Settings.player_name.is_empty():
		Settings.player_name = "Player %06d" % randi_range(0, 999999)
		Settings.save_settings()
	Network.player_name = Settings.player_name
	_collect_podiums()
	_show_local_preview()
	Fusion.register_broadcast_receiver(self)
	Network.connected_to_photon.connect(_on_connected_to_photon)
	Network.connection_failed.connect(_on_connection_failed)
	Network.room_joined.connect(_on_room_joined)
	Network.room_left.connect(_on_room_left)
	Network.player_joined.connect(_on_player_joined)
	Network.player_left.connect(_on_player_left)
	Network.room_op_failed.connect(_on_room_op_failed)
	_log("ready, name='%s', podiums=%d, mode='%s' - creating hidden lobby room" % [
		Network.player_name, _podium_previews.size(), _selected_mode])
	_show_loading_overlay(true)
	if Fusion.is_in_room():
		# The illusion lobby room already exists (autoload created it): the
		# load is done, hide the overlay right away.
		_hide_loading_overlay()
	Network.connect_to_photon()

func _exit_tree() -> void:
	Fusion.unregister_broadcast_receiver(self)

# --- Loading overlay ---

## The 50% opaque full-screen overlay (Scenes/LoadingOverlay.tscn) covers the
## lobby while the initial room is created and during room transitions.
## Every show gets a token-guarded 8s safety hide, so a failed join/leave or
## a dead network can never leave the player stuck behind it. Success hides
## earlier via _on_room_joined / _on_connection_failed. A hide is deferred if
## the overlay has been up for less than MIN_OVERLAY_MS, so fast transitions
## (sub-second joins) still flash the LOADING screen instead of being skipped.
const MIN_OVERLAY_MS := 600

## Monotonic ms of the last _show_loading_overlay call; -1 if never shown.
var _overlay_shown_ms := -1

func _show_loading_overlay(offline_toast := false) -> void:
	_overlay_token += 1
	var token := _overlay_token
	_overlay_shown_ms = Time.get_ticks_msec()
	var overlay := get_tree().get_first_node_in_group("loading_overlay")
	if overlay:
		overlay.show_loading()
	else:
		_log("WARNING: loading overlay not found")
	_log("loading overlay shown (token=%d)" % token)
	get_tree().create_timer(8.0).timeout.connect(func() -> void:
		if _overlay_token == token:
			_log("loading overlay timeout: hiding")
			_do_hide_loading_overlay()
			if offline_toast:
				Toasts.show_message("Could not connect to the server - playing offline"))

func _hide_loading_overlay() -> void:
	if _overlay_shown_ms >= 0:
		var elapsed := Time.get_ticks_msec() - _overlay_shown_ms
		if elapsed < MIN_OVERLAY_MS:
			var token := _overlay_token
			get_tree().create_timer(float(MIN_OVERLAY_MS - elapsed) / 1000.0).timeout.connect(func() -> void:
				if _overlay_token == token:
					_do_hide_loading_overlay())
			_log("loading overlay hide deferred (+%d ms)" % (MIN_OVERLAY_MS - elapsed))
			return
	_do_hide_loading_overlay()

func _do_hide_loading_overlay() -> void:
	_overlay_token += 1
	var overlay := get_tree().get_first_node_in_group("loading_overlay")
	if overlay:
		overlay.hide_loading()
	_log("loading overlay hidden")

## The 8 static podiums each carry a PlayerPreview; we drive those instead
## of spawning characters, so the menu stays light.
func _collect_podiums() -> void:
	var slots := get_node_or_null("LobbySlots")
	if slots == null:
		_log("WARNING: LobbySlots node not found, podiums disabled")
		return
	for child in slots.get_children():
		var preview: Node3D = child.get_node_or_null("PlayerPreview")
		if preview:
			_podium_previews.append(preview)
			_podium_stages.append(child.get_node_or_null("Stage") as MeshInstance3D)
	for preview in _podium_previews:
		preview.visible = false
	for stage in _podium_stages:
		stage.visible = false

# --- Party lifecycle ---

## Always end up in a room: after connecting we create one (hidden) unless a
## join is pending.
func _on_connected_to_photon() -> void:
	if _pending_join != "":
		var code := _pending_join
		_pending_join = ""
		_log("connected, joining room '%s'" % code)
		Network.join_room(code)
		return
	var code := Network.random_code()
	_log("connected, creating lobby room '%s' (mode '%s')" % [code, _selected_mode])
	Network.create_room(code)

## Create Party: the room already exists (lobby = room), so reveal its code.
func create_party() -> void:
	if Fusion.is_in_room():
		_log("party already exists: room '%s' (mode '%s')" % [Network.room_code(), _selected_mode])
		Toasts.show_message("Party ready - code %s" % Network.room_code())
		var hud := get_tree().get_first_node_in_group("lobby_hud")
		if hud:
			hud.show_party_code(Network.room_code())
		return
	_reveal_code = true
	if Network.is_connected_to_photon():
		var code := Network.random_code()
		_log("creating party room '%s'" % code)
		Network.create_room(code)
	else:
		_log("connecting to Photon for party")
		Network.connect_to_photon()

## Join Party: leave the current lobby room, then join the pasted code's room.
func join_game(code: String) -> void:
	code = code.strip_edges().to_upper()
	if code.length() != 5:
		_log("join rejected: '%s' is not a 5-character code" % code)
		Toasts.show_message("Invalid code - must be 5 characters")
		return
	_pending_join = code
	if Fusion.is_in_room():
		_log("leaving current room to join '%s'" % code)
		_show_loading_overlay()
		Network.leave()
	elif Network.is_connected_to_photon():
		_log("joining room '%s'" % code)
		_pending_join = ""
		_show_loading_overlay()
		Network.join_room(code)
	else:
		_log("connecting to Photon to join '%s'" % code)
		_show_loading_overlay()
		Network.connect_to_photon()

## Leave Party: as master, leaving dissolves the room (kicks everyone in it).
## We then immediately create a fresh hidden room - the illusion of having
## left, while the lobby stays a room.
func leave_party() -> void:
	if not Fusion.is_in_room():
		_log("leave_party: not in a room")
		return
	_log("leaving party room '%s' (master=%s) - kicking everyone and creating a fresh room" % [
		Network.room_code(), Fusion.is_master_client()])
	if Fusion.is_master_client():
		Toasts.show_message("Party closed - everyone kicked")
	else:
		Toasts.show_message("Left the party")
	var hud := get_tree().get_first_node_in_group("lobby_hud")
	if hud:
		hud.hide_code_box()
	_show_loading_overlay()
	Network.leave()

## Changing the game mode recreates the lobby room at that mode (the party is
## always at the current mode).
func set_mode(mode_id: String) -> void:
	if mode_id == _selected_mode:
		return
	_selected_mode = mode_id
	_log("mode set to '%s'" % mode_id)
	if Fusion.is_in_room():
		_pending_mode = mode_id
		_log("recreating room at mode '%s'" % mode_id)
		_show_loading_overlay()
		Network.leave()

func _on_connection_failed(reason: String) -> void:
	_leave_pending = false
	_log("connection failed: %s" % reason)
	_hide_loading_overlay()
	Toasts.show_message("Connection failed: %s" % reason)
	var hud := get_tree().get_first_node_in_group("lobby_hud")
	if hud:
		hud.show_message("Connection failed: %s" % reason)
		hud.set_party_intent(false)

func _on_room_joined() -> void:
	_leave_pending = false
	_in_room = true
	_hide_loading_overlay()
	var room = Fusion.get_room()
	if room == null:
		_log("ERROR: room_joined fired but Fusion.get_room() is null")
		return
	var ids: Array[int] = []
	for p in room.get_players():
		ids.append(p.get_number())
	_log("room joined '%s' as player %d (master=%s, mode='%s') players=%d ids=%s" % [
		room.get_room_name(), Fusion.get_local_player_id(),
		Fusion.is_master_client(), _selected_mode, ids.size(), ids])
	_refresh_podiums()
	var hud := get_tree().get_first_node_in_group("lobby_hud")
	# Publish the local player's skin once so everyone sees it.
	Fusion.rpc(submit_skin, Fusion.get_local_player_id(), Settings.skin_index)
	if _reveal_code:
		_reveal_code = false
		if hud:
			hud.show_party_code(room.get_room_name())
	elif hud:
		hud.hide_code_box()

func _on_room_left() -> void:
	if _leave_pending:
		_log("room_left ignored (leave already in flight)")
		return
	_leave_pending = true
	_in_room = false
	_log("left room")
	_show_loading_overlay()
	for preview in _podium_previews:
		preview.visible = false
	for stage in _podium_stages:
		stage.visible = false
	var hud := get_tree().get_first_node_in_group("lobby_hud")
	if hud:
		hud.set_party_buttons(false)
	if _pending_join != "":
		var code := _pending_join
		_pending_join = ""
		_log("joining room '%s' after leaving" % code)
		Network.join_room(code)
		return
	if _pending_mode != "":
		_pending_mode = ""
		var code := Network.random_code()
		_log("recreating room at mode '%s' (code '%s')" % [_selected_mode, code])
		Network.create_room(code)
		return
	# Kicked / dissolved / left: back to the local look, then create a fresh
	# hidden room so the lobby stays a room (new code, hidden - the illusion
	# of having left).
	if hud:
		hud.set_party_intent(false)
	var fresh := Network.random_code()
	_log("creating fresh hidden room '%s'" % fresh)
	Network.create_room(fresh)

## A join/create never completed (bad code, network hiccup, timeout): get
## back into a room and tell the player, so they are never stuck outside one.
func _on_room_op_failed(code: String) -> void:
	_leave_pending = false
	_log("room op failed for '%s' - creating fresh hidden room" % code)
	_hide_loading_overlay()
	Toasts.show_message("Could not enter room %s" % code)
	var hud := get_tree().get_first_node_in_group("lobby_hud")
	if hud:
		hud.set_party_intent(false)
	Network.create_room(Network.random_code())

func _on_player_joined(player_id: int) -> void:
	_log("player joined lobby (id=%d, in_room=%s, master=%s, players=%d)" % [
		player_id, _in_room, Fusion.is_master_client(), Network.room_player_ids().size()])
	if player_id != Fusion.get_local_player_id():
		Toasts.show_message("%s joined" % _player_name(player_id))
	_refresh_podiums()

func _on_player_left(player_id: int) -> void:
	_skin_registry.erase(player_id)
	_log("player left lobby (id=%d, remaining=%d)" % [player_id, Network.room_player_ids().size()])
	if player_id != Fusion.get_local_player_id():
		Toasts.show_message("%s left" % _player_name(player_id))
	_refresh_podiums()

# --- Podium assignment ---

## Menu idle state: the local player always stands on podium 1 (slot 0)
## until a room join re-assigns all slots. Only that slot's stage shows.
func _show_local_preview() -> void:
	if _podium_previews.is_empty():
		return
	for i in _podium_previews.size():
		_podium_previews[i].visible = i == 0
		if i < _podium_stages.size():
			_podium_stages[i].visible = i == 0
	var preview: Node3D = _podium_previews[0]
	preview.update_name(Network.player_name)
	preview.apply_skin(Settings.skin_index)
	_log("local preview shown on podium 0 ('%s', skin %d)" % [Network.player_name, Settings.skin_index])

## Sorted player ids -> podium index 0..7. Everyone in the room gets a
## podium; empty slots hide both the stage mesh and the preview.
func _refresh_podiums() -> void:
	if not Fusion.is_in_room():
		_log("refresh_podiums skipped: not in room")
		return
	var ids: Array[int] = []
	for p in Fusion.get_room().get_players():
		ids.append(p.get_number())
	ids.sort()
	var occupied := 0
	for i in _podium_previews.size():
		var preview: Node3D = _podium_previews[i]
		var stage := _podium_stages[i] if i < _podium_stages.size() else null
		if i < ids.size():
			var pid := ids[i]
			preview.visible = true
			if stage:
				stage.visible = true
			preview.update_name(_player_name(pid))
			var skin: int = _skin_registry.get(pid, Settings.skin_index if pid == Fusion.get_local_player_id() else 0)
			preview.apply_skin(skin)
			occupied += 1
		else:
			preview.visible = false
			if stage:
				stage.visible = false
	_log("podiums refreshed: %d/%d occupied, ids=%s, skins=%s" % [
		occupied, _podium_previews.size(), ids, _skin_registry])
	var hud := get_tree().get_first_node_in_group("lobby_hud")
	if hud:
		hud.set_party_buttons(true, ids.size())

## Current room members as [{id, name}], sorted by player id. Used by the
## HUD player list and the drawer Players tab.
func get_player_list() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not Fusion.is_in_room():
		return result
	var ids: Array[int] = []
	for p in Fusion.get_room().get_players():
		ids.append(p.get_number())
	ids.sort()
	for pid in ids:
		result.append({"id": pid, "name": _player_name(pid)})
	return result

func _player_name(player_id: int) -> String:
	if player_id == Fusion.get_local_player_id():
		return Network.player_name
	for p in Fusion.get_room().get_players():
		if p.get_number() == player_id:
			var name: String = p.get_name()
			if name.is_empty():
				name = p.get_user_id()
			if not name.is_empty():
				return name
			break
	return "Player %06d" % (player_id * 48271 % 1000000)

# --- Skin sync (broadcast RPC) ---

@rpc("any_peer", "call_local")
func submit_skin(player_id: int, skin_index: int) -> void:
	_log("submit_skin RPC: player %d -> skin %d" % [player_id, skin_index])
	_skin_registry[player_id] = skin_index
	_refresh_podiums()

# --- Kick (master only) ---

## The Fusion wrapper has no server-side disconnect command, so kicking is a
## soft kick: the host RPCs the target, and the target cooperates by leaving
## into a fresh hidden room.
func request_kick(target_id: int) -> void:
	if not Fusion.is_master_client():
		_log("kick rejected: only the host can kick")
		return
	if target_id == Fusion.get_local_player_id():
		_log("kick rejected: cannot kick yourself")
		return
	_log("host kicking player %d" % target_id)
	Toasts.show_message("Kicked %s" % _player_name(target_id))
	Fusion.rpc_to_player(target_id, kick_player, target_id)
	_skin_registry.erase(target_id)

@rpc("any_peer", "call_local")
func kick_player(target_id: int) -> void:
	_log("kick_player RPC received (sender=%d, target=%d)" % [Fusion.get_rpc_sender(), target_id])
	if target_id != Fusion.get_local_player_id():
		return
	_log("you were kicked by the host - leaving room")
	_show_loading_overlay()
	Toasts.show_message("You were kicked by the host")
	var hud := get_tree().get_first_node_in_group("lobby_hud")
	if hud:
		hud.show_kicked_message()
	Network.leave()
