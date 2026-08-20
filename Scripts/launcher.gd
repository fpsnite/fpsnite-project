extends Control
## Token launcher: paste your Discord login token once, then the game connects.
## The CONNECTING screen is a loading screen: a progress bar fills with
## staged messages while the token is validated against the backend. The
## scene never switches before the bar completes (~2s), so the loading
## screen is actually seen. On success we jump straight into the main menu.

const LOAD_TIME := 2.0

@onready var token_field: LineEdit = %TokenField
@onready var connect_button: Button = %Connect
@onready var status_label: Label = %Status
@onready var login_panel: VBoxContainer = %LoginPanel
@onready var connecting_panel: VBoxContainer = %ConnectingPanel
@onready var connecting_label: Label = %ConnectingLabel
@onready var stage_label: Label = %ConnectingHint
@onready var load_progress: ProgressBar = %LoadProgress

var _elapsed := 0.0
var _auth_done := false
var _auth_ok := false
var _auth_player := {}
var _auth_error := ""
var _dot_timer := 0.0
var _dots := 0
var _finished := false

func _ready() -> void:
	connect_button.pressed.connect(_on_connect_pressed)
	token_field.text_submitted.connect(func(_t: String) -> void: _on_connect_pressed())
	Backend.account_ready.connect(_on_account_ready)
	Backend.auth_failed.connect(_on_auth_failed)
	if not Settings.auth_token.is_empty():
		_connect_with(Settings.auth_token)
	else:
		_show_login()

func _process(delta: float) -> void:
	if not connecting_panel.visible or _finished:
		return
	_elapsed += delta
	_dot_timer += delta
	load_progress.value = clampf(_elapsed / LOAD_TIME, 0.0, 1.0) * 100.0
	stage_label.text = _stage_text(load_progress.value)
	if _dot_timer >= 0.4:
		_dot_timer = 0.0
		_dots = (_dots + 1) % 4
		connecting_label.text = "CONNECTING" + ".".repeat(_dots)
	if _elapsed >= LOAD_TIME and _auth_done:
		_finish()

func _stage_text(progress: float) -> String:
	if progress < 25.0:
		return "connecting to server..."
	if progress < 50.0:
		return "validating login token..."
	if progress < 75.0:
		return "loading player profile..."
	return "entering game..."

func _on_connect_pressed() -> void:
	var token := token_field.text.strip_edges()
	if token.is_empty():
		status_label.text = "Enter your login token from the Discord bot."
		return
	_connect_with(token)

func _connect_with(token: String) -> void:
	_elapsed = 0.0
	_auth_done = false
	_auth_ok = false
	_auth_player = {}
	_auth_error = ""
	_finished = false
	_dots = 0
	_dot_timer = 0.0
	load_progress.value = 0.0
	stage_label.text = "connecting to server..."
	connecting_label.text = "CONNECTING."
	connecting_panel.visible = true
	login_panel.visible = false
	Backend.login_with_token(token)

func _on_account_ready(player: Dictionary) -> void:
	_auth_done = true
	_auth_ok = true
	_auth_player = player
	if _elapsed >= LOAD_TIME:
		_finish()

func _on_auth_failed(code: String, message: String) -> void:
	print("[BACKEND] auth failed: %s - %s" % [code, message])
	_auth_error = message
	if code == "INVALID_TOKEN" and not Settings.auth_token.is_empty():
		Settings.auth_token = ""
		Settings.account_id = ""
		Settings.save_settings()
	token_field.text = ""
	_finish()

func _finish() -> void:
	if _finished:
		return
	_finished = true
	if _auth_ok:
		Settings.auth_token = Backend.auth_token
		Settings.account_id = _auth_player["account_id"]
		Settings.player_name = _auth_player["name"]
		if _auth_player.has("current_skin") and _auth_player["current_skin"] != Settings.skin_index:
			Settings.skin_index = _auth_player["current_skin"]
		Settings.save_settings()
		get_tree().change_scene_to_file("res://Scenes/mainui.tscn")
	else:
		status_label.text = _auth_error
		_show_login()

func _show_login() -> void:
	connecting_panel.visible = false
	load_progress.value = 0.0
	login_panel.visible = true
	token_field.grab_focus()