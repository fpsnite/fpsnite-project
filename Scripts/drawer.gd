extends CanvasLayer
## Lobby slide-in drawer: Esc toggles, clicking the dimmed empty space closes
## it. Three tabs: Info (account info + profile link), Misc (settings, logout,
## quit) and Players (everyone in the current room, with a host-only KICK
## button). The player list refreshes on open and on room join/leave events.

signal drawer_closed

const DRAWER_WIDTH := 380.0

@onready var dim: ColorRect = $Dim
@onready var panel: PanelContainer = $Panel
@onready var tab_bar: TabBar = %DrawerTabBar
@onready var tab_container: TabContainer = %DrawerTabs
@onready var info_name_label: Label = %InfoNameLabel
@onready var info_status_label: Label = %InfoStatusLabel
@onready var info_region_label: Label = %InfoRegionLabel
@onready var info_session_label: Label = %InfoSessionLabel
@onready var profile_button: Button = %ProfileButton
@onready var players_hint: Label = %PlayersHintLabel
@onready var player_list: VBoxContainer = %DrawerPlayerList

var _open := false
var _tween: Tween

func _log(msg: String) -> void:
	print("[DRAWER] drawer: " + msg)

func _ready() -> void:
	set_visible(false)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dim.color.a = 0.0
	dim.gui_input.connect(_on_dim_gui_input)
	panel.position.x = _viewport_width() + 10.0
	tab_bar.tab_changed.connect(func(index: int) -> void: tab_container.current_tab = index)
	tab_container.current_tab = 0
	tab_bar.current_tab = 0
	profile_button.pressed.connect(_on_profile_pressed)
	%SettingsButton.pressed.connect(_on_settings_pressed)
	%LogoutButton.pressed.connect(_on_logout_pressed)
	Network.player_joined.connect(func(_player_id: int) -> void: _refresh_players())
	Network.player_left.connect(func(_player_id: int) -> void: _refresh_players())
	_log("ready, tabs=%d" % tab_bar.tab_count)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		toggle()
		get_viewport().set_input_as_handled()

func _viewport_width() -> float:
	return get_viewport().get_visible_rect().size.x

func toggle() -> void:
	set_open(not _open)

func set_open(open: bool) -> void:
	set_visible(open)
	_open = open
	dim.mouse_filter = Control.MOUSE_FILTER_STOP if open else Control.MOUSE_FILTER_IGNORE
	if open:
		_refresh_info()
		_refresh_players()
	if _tween:
		_tween.kill()
	_tween = create_tween().set_parallel(true)
	_tween.tween_property(panel, "position:x", (_viewport_width() - DRAWER_WIDTH) if open else (_viewport_width() + 10.0), 0.28) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT if open else Tween.EASE_IN)
	_tween.tween_property(dim, "color:a", 0.55 if open else 0.0, 0.28)
	if open:
		tab_bar.grab_focus()

func _on_dim_gui_input(event: InputEvent) -> void:
	if _open and event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		set_open(false)
		drawer_closed.emit()

func _on_quit_pressed() -> void:
	get_tree().quit()

func _on_profile_pressed() -> void:
	set_open(false)
	get_tree().change_scene_to_file("res://Scenes/User Profile.tscn")

func _on_settings_pressed() -> void:
	set_open(false)
	get_tree().change_scene_to_file("res://Scenes/settings_page.tscn")

func _on_logout_pressed() -> void:
	set_open(false)
	Backend.clear_token()
	Settings.auth_token = ""
	Settings.player_id = -1
	Settings.save_settings()
	_log("logged out, returning to launcher")
	get_tree().change_scene_to_file("res://Scenes/Launcher.tscn")

# --- Info tab ---

func _refresh_info() -> void:
	var logged_in := Backend.player_id >= 0
	info_name_label.text = "Name: %s" % Settings.player_name
	info_status_label.text = "Status: %s" % ("Active (ID %d)" % Backend.player_id if logged_in else "Offline")
	info_region_label.text = "Region: Local"
	if Fusion.is_connected_to_photon():
		info_session_label.text = "Session ID: %d" % Fusion.get_local_player_id()
	else:
		info_session_label.text = "Session: not connected"
	_log("info refreshed (logged_in=%s)" % logged_in)

# --- Players tab ---

## Everyone in the current room as rows; KICK only shows on the host's client
## and never on the player's own row.
func _refresh_players() -> void:
	for child in player_list.get_children():
		child.queue_free()
	var lobby := get_tree().get_first_node_in_group("lobby")
	var players: Array[Dictionary] = []
	if lobby and lobby.has_method("get_player_list"):
		players = lobby.get_player_list()
	players_hint.text = "Not in a room" if players.is_empty() else ""
	players_hint.visible = players.is_empty()
	for p in players:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var label := Label.new()
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.add_theme_font_size_override("font_size", 20)
		label.text = p.name
		row.add_child(label)
		var kick := Button.new()
		kick.text = "KICK"
		kick.visible = Fusion.is_master_client() and p.id != Fusion.get_local_player_id()
		kick.pressed.connect(_on_kick_pressed.bind(p.id))
		row.add_child(kick)
		player_list.add_child(row)
	_log("players refreshed: %d" % players.size())

func _on_kick_pressed(target_id: int) -> void:
	_log("kick pressed for player %d" % target_id)
	var lobby := get_tree().get_first_node_in_group("lobby")
	if lobby:
		lobby.request_kick(target_id)
	else:
		_log("ERROR: no node in group 'lobby' for kick")