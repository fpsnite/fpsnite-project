extends Node
## Persistent settings: graphics + keybind overrides, saved to user://settings.cfg.

const SAVE_PATH := "user://settings.cfg"

const DEFAULT_KEYBINDS := {
	"move_left": KEY_A,
	"move_right": KEY_D,
	"move_forward": KEY_W,
	"move_back": KEY_S,
	"sprint": KEY_SHIFT,
	"jump": KEY_SPACE,
	"chat": KEY_T,
}

var fps_limit := 0
var resolution := Vector2i(1920, 1080)
var fullscreen := false
var scaling_3d := 1.0
var keybinds: Dictionary = {}
var skin_index := 0
var player_name := ""

## Transient navigation flags for the settings-page round trip (not saved):
## set by the pause drawer so the settings back button returns to the game
## (and reopens the drawer) instead of the main menu.
var return_to_lobby := false
var open_drawer_on_return := false

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
	config.save(SAVE_PATH)

func load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(SAVE_PATH) != OK:
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
