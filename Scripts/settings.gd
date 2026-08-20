extends Node
## Persistent settings: graphics + keybind overrides, saved to user://settings.cfg.
## A second instance on the same machine can use its own profile - separate
## login token, player name, skin and graphics - by setting FPSNITE_PROFILE=2
## (env var) or passing --profile 2 on the command line. It then reads/writes
## user://settings_2.cfg, so two instances never fight over the same token.

var save_path := "user://settings.cfg"

const DEFAULT_KEYBINDS := {
	"move_left": KEY_A,
	"move_right": KEY_D,
	"move_forward": KEY_W,
	"move_back": KEY_S,
	"sprint": KEY_SHIFT,
	"jump": KEY_SPACE,
	"crouch": KEY_CTRL,
	"chat": KEY_T,
	"reload": KEY_R,
	"next_weapon": KEY_Q,
	"prev_weapon": KEY_E,
	"knife": KEY_3,
	"weapon_slot_1": KEY_1,
	"weapon_slot_2": KEY_2,
	"weapon_slot_3": KEY_3,
	"interact": KEY_F,
}

var fps_limit := 0
var resolution := Vector2i(1920, 1080)
var fullscreen := false
var scaling_3d := 1.0
var keybinds: Dictionary = {}
var skin_index := 0
var player_name := ""
## Account session (persisted so the launcher auto-logs in next start).
## v2: the public identifier is the hex account_id (the numeric row id is
## internal to the backend and never stored client-side).
var account_id := ""
## Login token from Discord /register - the credential the backend accepts.
var auth_token := ""

## Mouse look (Settings > Controls tab), applied live by FirstPersonCamera.
## Stored as percentages (0-100%): 100% = the default sensitivity. 0% means
## no look movement at all, 100% is the normal value, up to 100% the max.
var mouse_sensitivity_pct := 100.0
var ads_sensitivity_pct := 60.0
var sens_x_pct := 100.0
var sens_y_pct := 100.0

## Defaults for the Settings > Controls "reset" button.
const CONTROLS_DEFAULTS := {
	"mouse_sensitivity_pct": 100.0,
	"ads_sensitivity_pct": 60.0,
	"sens_x_pct": 100.0,
	"sens_y_pct": 100.0,
}

## Transient navigation flags for the settings-page round trip (not saved):
## set by the pause drawer so the settings back button returns to the game
## (and reopens the drawer) instead of the main menu.
var return_to_lobby := false
var open_drawer_on_return := false
## Exact scene path the settings back button should return to (set by the
## pause drawer to the current scene, e.g. aim training). Takes priority over
## return_to_lobby.
var return_to_scene := ""
## Transient snapshot of the main menu's party intent, taken when the menu
## unloads (settings round trip): reapplied on reload so the party UI look
## (Leave + code) survives the trip instead of falling back to Create/Join.
var return_menu_party := false

## Transient game-state passthrough (not saved): the mode the arena match is
## running at, set by the menu right before the scene switch.
var pending_mode := "ffa"
## The last game mode a match was started in (saved): the main menu restores
## it, so returning from a match keeps the same game selected.
var last_mode := "ffa"

func _init() -> void:
	var profile := OS.get_environment("FPSNITE_PROFILE").strip_edges()
	if profile.is_empty():
		profile = _profile_from_args(OS.get_cmdline_user_args())
	if profile.is_empty():
		profile = _profile_from_args(OS.get_cmdline_args())
	if not profile.is_empty():
		save_path = "user://settings_%s.cfg" % profile

## Scans for --profile <name> / --profile=<name>. Scanned on both the user
## args (after --) and the full engine args, so it works whether the args
## come from a launch script, an env var, or the editor's "Run Multiple
## Instances" per-instance field.
func _profile_from_args(args: PackedStringArray) -> String:
	for i in args.size():
		if args[i] == "--profile" and i + 1 < args.size():
			return args[i + 1].strip_edges()
		if args[i].begins_with("--profile="):
			return args[i].get_slice("=", 1).strip_edges()
	return ""

func _ready() -> void:
	load_settings()
	apply_graphics()
	apply_keybinds()

## Emergency close: Alt+F4 quits the app immediately from any screen.
func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo or not key.alt_pressed:
		return
	if key.keycode == KEY_F4 or key.keycode == KEY_F4 | KEY_MASK_ALT:
		get_tree().quit()

func apply_graphics() -> void:
	if fullscreen:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(resolution)
	Engine.max_fps = fps_limit
	get_viewport().scaling_3d_scale = scaling_3d

func apply_keybinds() -> void:
	for action: String in DEFAULT_KEYBINDS:
		InputMap.action_erase_events(action)
		var keycode: Key = keybinds.get(action, DEFAULT_KEYBINDS[action])
		var event := InputEventKey.new()
		event.physical_keycode = keycode
		InputMap.action_add_event(action, event)

func set_keybind(action: String, keycode: Key) -> void:
	keybinds[action] = keycode
	apply_keybinds()
	save_settings()

func reset_keybinds() -> void:
	keybinds.clear()
	apply_keybinds()
	save_settings()

func save_settings() -> void:
	var config := ConfigFile.new()
	config.set_value("graphics", "fps_limit", fps_limit)
	config.set_value("graphics", "resolution", resolution)
	config.set_value("graphics", "fullscreen", fullscreen)
	config.set_value("graphics", "scaling_3d", scaling_3d)
	config.set_value("keybinds", "actions", keybinds)
	config.set_value("skins", "index", skin_index)
	config.set_value("player", "name", player_name)
	config.set_value("player", "last_mode", last_mode)
	config.set_value("account", "account_id", account_id)
	config.set_value("account", "auth_token", auth_token)
	for key: String in CONTROLS_DEFAULTS:
		config.set_value("controls", key, get(key))
	config.save(save_path)

func load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(save_path) != OK:
		return
	fps_limit = config.get_value("graphics", "fps_limit", 0)
	resolution = config.get_value("graphics", "resolution", Vector2i(1920, 1080))
	fullscreen = config.get_value("graphics", "fullscreen", false)
	scaling_3d = config.get_value("graphics", "scaling_3d", 1.0)
	var saved: Dictionary = config.get_value("keybinds", "actions", {})
	for action in saved:
		keybinds[action] = saved[action]
	skin_index = config.get_value("skins", "index", 0)
	player_name = config.get_value("player", "name", "")
	last_mode = config.get_value("player", "last_mode", "ffa")
	account_id = config.get_value("account", "account_id", "")
	auth_token = config.get_value("account", "auth_token", "")
	for key: String in CONTROLS_DEFAULTS:
		set(key, config.get_value("controls", key, CONTROLS_DEFAULTS[key]))
