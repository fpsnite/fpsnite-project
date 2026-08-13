extends CanvasLayer
## HUD for the main menu lobby (LobbyUI.tscn root). Wires the tab bar to the
## tab container, PLAY -> game-mode popup, the party box (Create/Join Party +
## code entry with copy/join), and the live FPS/ping counter in the
## bottom-left RegionText label. The lobby logic lives on the mainui root
## (main_lobby.gd, group "lobby"): the lobby is always a room, created hidden
## on load; Create Party reveals its code, Join Party switches rooms by code.

@onready var tab_bar: TabBar = %TabBar
@onready var tab_container: TabContainer = %TabContainer
@onready var popup: Control = %PopupPanel
@onready var game_mode_text: Label = %GameModeText
@onready var region_text: Label = %RegionText
@onready var mode_grid: GridContainer = %ModeGrid
@onready var play_button: Button = %PlayButton
@onready var code_box: HBoxContainer = %CodeBox
@onready var code_edit: LineEdit = %CodeEdit
@onready var code_action_button: Button = %CodeActionButton
@onready var create_party_button: Button = %CreatePartyButton
@onready var join_party_button: Button = %JoinPartyButton
@onready var leave_party_button: Button = %LeavePartyButton

var _counter_accum := 0.0
var _counter_log_accum := 0.0
## Default mode for quick tests (fps test map); changed by clicking a card.
var selected_mode_id := "test"
var _code_box_mode := "copy"
## True after the player explicitly clicked Create/Join Party: the Leave
## button shows immediately (even while still alone) instead of the local
## illusion. Cleared on leave, kick/dissolve, or connection failure.
var _party_intent := false

func _log(msg: String) -> void:
	print("[HUD] lobby_hud: " + msg)

func _ready() -> void:
	add_to_group("lobby_hud")
	tab_bar.tab_changed.connect(func(index: int) -> void: tab_container.current_tab = index)
	tab_container.current_tab = 0
	tab_bar.current_tab = 0
	play_button.pressed.connect(_on_game_mode_button_pressed)
	create_party_button.pressed.connect(_on_create_party_pressed)
	join_party_button.pressed.connect(_on_join_party_pressed)
	leave_party_button.pressed.connect(_on_leave_party_pressed)
	code_action_button.pressed.connect(_on_code_action_pressed)
	var cards := mode_grid.get_children()
	for card in cards:
		card.selected.connect(_on_mode_selected)
	game_mode_text.text = "Test Mode"
	_log("ready: tabs=%d mode cards=%d, default mode='%s' (test/fps map)" % [tab_bar.tab_count, cards.size(), selected_mode_id])

func _process(delta: float) -> void:
	_counter_accum += delta
	if _counter_accum < 0.25:
		return
	_counter_accum = 0.0
	var connected := Fusion.is_connected_to_photon()
	var ping := "-" if not connected else "%.0f" % (Fusion.get_rtt() * 1000.0)
	region_text.text = "%s ms  %d" % [ping, Engine.get_frames_per_second()]
	_counter_log_accum += 0.25
	if _counter_log_accum >= 15.0:
		_counter_log_accum = 0.0
		_log("counter: %s ms, %d fps, connected=%s, in_room=%s" % [
			ping, Engine.get_frames_per_second(), connected, Fusion.is_in_room()])

# --- Popup / game mode ---

func _on_game_mode_button_pressed() -> void:
	popup.visible = not popup.visible
	_log("game mode popup toggled: %s" % ("open" if popup.visible else "closed"))

func _on_close_button_pressed() -> void:
	popup.visible = false
	_log("game mode popup closed")

func _on_mode_selected(mode_id: String) -> void:
	selected_mode_id = mode_id
	_log("mode selected: '%s'" % mode_id)
	game_mode_text.text = mode_id.to_upper()
	popup.visible = false
	var lobby := get_tree().get_first_node_in_group("lobby")
	if lobby:
		lobby.set_mode(mode_id)
	else:
		_log("ERROR: no node in group 'lobby' for set_mode")

# --- Party box ---

## In a party (explicit Create/Join intent, or in a room with 2+ players):
## only Leave Party shows. Otherwise - alone in the auto-created hidden room
## or outside a room - it looks local: Create/Join show.
func set_party_buttons(in_room: bool, player_count: int = 0) -> void:
	var party := _party_intent or (in_room and player_count >= 2)
	create_party_button.visible = not party
	join_party_button.visible = not party
	leave_party_button.visible = party
	_log("party buttons: %s (players=%d, intent=%s)" % ["leave" if party else "create/join", player_count, _party_intent])

## Explicit party intent; used by main_lobby to restore the local look after
## a kick/dissolve or connection failure.
func set_party_intent(value: bool) -> void:
	_party_intent = value
	_log("party intent: %s" % value)

func hide_code_box() -> void:
	code_box.visible = false
	code_action_button.visible = true
	_log("code box hidden")

## Generic notice in the code box (connection failures, kicked, etc.); the
## fresh room flow hides it on the next room join.
func show_message(message: String) -> void:
	_show_notice(message)
	_log("message shown: '%s'" % message)

func show_kicked_message() -> void:
	_show_notice("KICKED by host - creating new room...")
	_log("kicked message shown")

func _show_notice(message: String) -> void:
	_code_box_mode = "message"
	code_edit.text = message
	code_edit.editable = false
	code_action_button.visible = false
	code_box.visible = true

func _on_leave_party_pressed() -> void:
	_log("leave party pressed (mode='%s')" % selected_mode_id)
	_party_intent = false
	set_party_buttons(false, 0)
	var lobby := get_tree().get_first_node_in_group("lobby")
	if lobby:
		lobby.leave_party()
	else:
		_log("ERROR: no node in group 'lobby' for leave_party")

func _on_create_party_pressed() -> void:
	_log("create party pressed (mode='%s')" % selected_mode_id)
	_party_intent = true
	set_party_buttons(true, 1)
	var lobby := get_tree().get_first_node_in_group("lobby")
	if lobby:
		lobby.create_party()
	else:
		_log("ERROR: no node in group 'lobby' for create_party")

func _on_join_party_pressed() -> void:
	_log("join party pressed (mode='%s')" % selected_mode_id)
	_party_intent = true
	set_party_buttons(true, 1)
	_code_box_mode = "join"
	code_edit.text = ""
	code_edit.editable = true
	code_action_button.text = "JOIN"
	code_action_button.visible = true
	code_box.visible = true
	code_edit.grab_focus()
	_log("party code box shown (join mode)")

## Called by main_lobby once a party room exists (or already existed).
func show_party_code(code: String) -> void:
	_code_box_mode = "copy"
	code_edit.text = code
	code_edit.editable = false
	code_action_button.text = "COPY CODE"
	code_action_button.visible = true
	code_box.visible = true
	_log("party code box shown (copy mode): '%s'" % code)

func _on_code_action_pressed() -> void:
	if _code_box_mode == "copy":
		DisplayServer.clipboard_set(code_edit.text)
		code_action_button.text = "COPIED!"
		_log("code copied to clipboard: '%s'" % code_edit.text)
		get_tree().create_timer(1.5).timeout.connect(func() -> void:
			if _code_box_mode == "copy":
				code_action_button.text = "COPY CODE")
		return
	var code := code_edit.text.strip_edges()
	if code.length() != 5:
		code_action_button.text = "INVALID CODE"
		_log("join rejected: code must be 5 characters")
		Toasts.show_message("Invalid code - must be 5 characters")
		return
	code_box.visible = false
	_party_intent = true
	set_party_buttons(true, 1)
	var lobby := get_tree().get_first_node_in_group("lobby")
	if lobby:
		lobby.join_game(code)
	else:
		_log("ERROR: no node in group 'lobby' to join")
