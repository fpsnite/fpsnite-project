extends Node
## Photon Fusion networking wrapper (replaces ENet).
## Flow: connect_to_photon() → create_room(code) / join_room(code) → room_joined signal.
## Room code = room name. Host = master client.

signal connected_to_photon
signal connection_failed(reason: String)
signal room_joined
signal room_left
signal player_joined(player_id: int)
signal player_left(player_id: int)
signal master_client_changed
## A join/create was retried for ROOM_OP_TIMEOUT_MS without Fusion accepting
## it (e.g. bad room code). The emitted code was never entered.
signal room_op_failed(code: String)

const MAX_PLAYERS := 8
const CODE_CHARS := "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
## Fusion rejects join/create while it is still finishing a leave (internal
## state LeavingRoom - indistinguishable from Connected via the public API,
## both report connection status ConnectedToPhoton). Retry until accepted so
## the leave -> join/create race in the lobby can never drop a request.
const ROOM_OP_TIMEOUT_MS := 5000
const ROOM_OP_RETRY_SEC := 0.15
const CONN_CONNECTED_TO_PHOTON := 2

var player_name := ""
var last_log := ""

var _pending_join := ""
var _pending_create := ""
var _pending_create_options: FusionRoomOptions
var _room_op_running := false

## True when the client chose to leave (pause drawer), so an unexpected
## disconnect redirects to the main menu instead of a silent freeze.
var intentional_leave := false
## Set when a disconnect kicked the player back to the main menu; the main
## menu shows it once.
var lost_message := ""
var _redirecting := false

func _log(msg: String) -> void:
	last_log = msg
	print("[NET] " + msg)

func _ready() -> void:
	_log("network.gd ready")
	Fusion.connection_status_changed.connect(_on_connection_status_changed)
	Fusion.connected_to_photon.connect(func() -> void:
		_log("connected to Photon")
		connected_to_photon.emit())
	Fusion.connection_failed.connect(func(reason: String) -> void:
		_log("connection FAILED: %s" % reason)
		connection_failed.emit(reason))
	Fusion.room_joined.connect(func() -> void:
		_log("room joined: '%s' player=%d master=%s players=%d" % [
			Fusion.get_room().get_room_name(), Fusion.get_local_player_id(),
			Fusion.is_master_client(), _room_size()])
		room_joined.emit())
	Fusion.room_left.connect(func() -> void:
		_log("left room")
		room_left.emit())
	Fusion.player_joined.connect(func(id: int, user_id: String) -> void:
		_log("player joined: id=%d user_id='%s' players=%d" % [id, user_id, _room_size()])
		player_joined.emit(id))
	Fusion.player_left.connect(func(id: int, inactive: bool) -> void:
		_log("player left: id=%d inactive=%s players=%d" % [id, inactive, _room_size()])
		player_left.emit(id))
	Fusion.master_client_changed.connect(func(a: int, b: int) -> void:
		_log("master client changed: %d -> %d" % [a, b])
		master_client_changed.emit())

func _on_connection_status_changed(status: int) -> void:
	_log("connection status: %s" % _status_name(status))
	if status != 0:
		return
	if intentional_leave:
		intentional_leave = false
		return
	if _redirecting:
		return
	var current := get_tree().current_scene
	if current == null or current.name == "mainui":
		return
	_redirecting = true
	lost_message = "Connection lost"
	get_tree().paused = false
	call_deferred("_redirect_to_menu")

## Kicked out by a connection error: back to the main menu with a notice.
func _redirect_to_menu() -> void:
	get_tree().change_scene_to_file("res://Scenes/mainui.tscn")

func _status_name(status: int) -> String:
	match status:
		0:
			return "Disconnected"
		1:
			return "ConnectingToPhoton"
		2:
			return "ConnectedToPhoton"
		3:
			return "JoiningRoom"
		4:
			return "InRoom"
		5:
			return "Error"
	return "Unknown(%d)" % status

func _room_size() -> int:
	if not Fusion.is_in_room():
		return 0
	return Fusion.get_room().get_players().size()

func connect_to_photon() -> void:
	_redirecting = false
	Fusion.connect_to_photon(player_name, "", "")

func is_connected_to_photon() -> bool:
	return Fusion.is_connected_to_photon()

func create_room(code: String) -> void:
	var options := FusionRoomOptions.new()
	options.set_max_players(MAX_PLAYERS)
	options.set_is_open(true)
	options.set_is_visible(true)
	_pending_create = code
	_pending_create_options = options
	_pending_join = ""
	_run_room_op()

func join_room(code: String) -> void:
	_pending_join = code
	_pending_create = ""
	_run_room_op()

## Deferred room op: calls Fusion.join_room/create_room on a small retry loop
## until the call is accepted (is_in_room) or the deadline passes. Fusion
## rejects ops while the previous leave is still settling, and the public API
## cannot distinguish that moment from "ready", so retrying is the only
## reliable way to never lose a pending join/create.
func _run_room_op() -> void:
	if _room_op_running:
		return
	_room_op_running = true
	var deadline := Time.get_ticks_msec() + ROOM_OP_TIMEOUT_MS
	while Time.get_ticks_msec() < deadline:
		if _pending_join.is_empty() and _pending_create.is_empty():
			break
		if not Fusion.is_in_room() and Fusion.get_connection_status() == CONN_CONNECTED_TO_PHOTON:
			if not _pending_join.is_empty():
				Fusion.join_room(_pending_join)
			elif not _pending_create.is_empty():
				Fusion.create_room(_pending_create, _pending_create_options)
		await get_tree().create_timer(ROOM_OP_RETRY_SEC).timeout
		if Fusion.is_in_room():
			break
	_room_op_running = false
	if not Fusion.is_in_room() and not (_pending_join.is_empty() and _pending_create.is_empty()):
		var failed := _pending_join if not _pending_join.is_empty() else _pending_create
		_pending_join = ""
		_pending_create = ""
		_log("room op failed for '%s' - never entered a room" % failed)
		room_op_failed.emit(failed)

func leave() -> void:
	if Fusion.is_in_room():
		intentional_leave = true
		Fusion.leave_room()

func is_host() -> bool:
	return Fusion.is_master_client()

func local_player_id() -> int:
	return Fusion.get_local_player_id()

func room_code() -> String:
	if not Fusion.is_in_room():
		return ""
	return Fusion.get_room().get_room_name()

func room_player_ids() -> Array[int]:
	var ids: Array[int] = []
	if not Fusion.is_in_room():
		return ids
	for player in Fusion.get_room().get_players():
		ids.append(player.get_number())
	return ids

func random_code() -> String:
	var code := ""
	for i in 5:
		code += CODE_CHARS[randi() % CODE_CHARS.length()]
	return code
