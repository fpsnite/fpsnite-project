extends Control
## User profile page: shows the account name (editable locally - it drives the
## in-lobby display name), account status + region, back to the main menu,
## and logout which clears the session and returns to the launcher.

@onready var back_button: Button = %BackButton
@onready var user_input: LineEdit = %UserInput
@onready var save_button: Button = %SaveNameButton
@onready var status_label: Label = %StatusValueLabel
@onready var region_label: Label = %RegionValueLabel
@onready var logout_button: Button = %LogoutButton

func _log(msg: String) -> void:
	print("[PROFILE] user_profile: " + msg)

func _ready() -> void:
	get_tree().paused = false
	back_button.pressed.connect(_on_back_pressed)
	save_button.pressed.connect(_apply_name)
	user_input.text_submitted.connect(func(_t: String) -> void: _apply_name())
	logout_button.pressed.connect(_on_logout_pressed)
	var logged_in := Backend.player_id >= 0
	var name := Backend.player_name if logged_in and not Backend.player_name.is_empty() else Settings.player_name
	user_input.text = name
	status_label.text = "Account Status : %s" % ("Active (ID %d)" % Backend.player_id if logged_in else "Offline")
	region_label.text = "Region : Local"
	_log("ready: name='%s', logged_in=%s" % [name, logged_in])

func _apply_name() -> void:
	var name := user_input.text.strip_edges()
	if name.is_empty():
		_log("name rejected: empty")
		return
	Settings.player_name = name
	Settings.save_settings()
	Network.player_name = name
	_log("name set to '%s'" % name)

func _on_back_pressed() -> void:
	_log("back to main menu")
	get_tree().change_scene_to_file("res://Scenes/mainui.tscn")

func _on_logout_pressed() -> void:
	Backend.clear_token()
	Settings.auth_token = ""
	Settings.player_id = -1
	Settings.save_settings()
	_log("logged out, returning to launcher")
	get_tree().change_scene_to_file("res://Scenes/Launcher.tscn")