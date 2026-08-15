extends CanvasLayer
## Bottom-center HUD: player number, sprint stamina, health + shield bars,
## equipped weapon name, mag bar and ammo count, plus a weapon slot bar
## (bottom-right) and a top-left kills / players-alive counter.
## Reads state from the local player instance (which the server drives
## through WeaponSystem's sync_health broadcasts) and the round's kill
## scores.

@onready var sprint_bar: ProgressBar = $Box/SprintRow/SprintBar
@onready var force_label: Label = $Box/ForceLabel
@onready var health_bar: ProgressBar = $Box/HealthRow/HealthBar
@onready var shield_bar: ProgressBar = $Box/ShieldRow/ShieldBar
@onready var ammo_label: Label = $Box/AmmoLabel
@onready var mag_bar: ProgressBar = $Box/MagRow/MagBar
@onready var weapon_label: Label = $Box/WeaponLabel
@onready var damage_flash: ColorRect = $DamageFlash

var _flash_tween: Tween
var _weapon_bar: HBoxContainer
var _slot_labels: Array[Label] = []
var _kills_label: Label
var _alive_label: Label
var _last_kills := -1
var _pop_tween: Tween

func _ready() -> void:
	var weapon_system := get_tree().get_first_node_in_group("weapon_system")
	if weapon_system:
		weapon_system.local_damage_taken.connect(_on_local_damage_taken)
	_make_weapon_bar()
	_make_match_labels()

## Bottom-right weapon slots, built from the loadout once the local weapon
## node exists: "1 RIFLE", "3 KNIFE" - the active slot is highlighted.
func _make_weapon_bar() -> void:
	_weapon_bar = HBoxContainer.new()
	_weapon_bar.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_weapon_bar.offset_left = -420.0
	_weapon_bar.offset_top = -70.0
	_weapon_bar.offset_right = -16.0
	_weapon_bar.offset_bottom = -16.0
	_weapon_bar.add_theme_constant_override("separation", 10)
	_weapon_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_weapon_bar)

## Top-left kills / alive counter, styled like the rest of the HUD.
func _make_match_labels() -> void:
	var font := load("res://Fonts/dimbo/Dimbo Regular.ttf")
	_kills_label = Label.new()
	_kills_label.position = Vector2(26, 16)
	_kills_label.add_theme_font_override("font", font)
	_kills_label.add_theme_font_size_override("font_size", 30)
	_kills_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_kills_label.add_theme_constant_override("outline_size", 8)
	_kills_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_kills_label)
	_alive_label = Label.new()
	_alive_label.position = Vector2(26, 60)
	_alive_label.add_theme_font_override("font", font)
	_alive_label.add_theme_font_size_override("font_size", 22)
	_alive_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_alive_label.add_theme_constant_override("outline_size", 6)
	_alive_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_alive_label)

func _process(_delta: float) -> void:
	var lobby := get_tree().get_first_node_in_group("lobby")
	var player: Node = lobby._characters.get(Fusion.get_local_player_id()) if lobby else null
	_update_match_labels(lobby)
	if player == null:
		return
	sprint_bar.value = player.stamina
	force_label.text = _format_number(player.player_number)
	health_bar.value = player.health
	shield_bar.value = player.shield
	var weapon := player.get_node_or_null("CameraPivot/Camera3D/Weapon")
	if weapon:
		weapon_label.text = weapon.current_data.weapon_name.to_upper()
		_update_ammo(weapon)
		_update_mag_bar(weapon)
		_update_weapon_bar(weapon)

func _update_ammo(weapon: Node) -> void:
	if weapon.current_data.infinite_ammo:
		ammo_label.text = "INFINITE"
		ammo_label.add_theme_color_override("font_color", Color(1, 0.9, 0.45, 1))
	elif weapon.reloading:
		ammo_label.text = "RELOADING..."
		ammo_label.add_theme_color_override("font_color", Color(1, 0.9, 0.45, 1))
	elif weapon.current_data.infinite_reserve_ammo:
		ammo_label.text = "%d / INF" % weapon.mag
		ammo_label.add_theme_color_override("font_color", Color(1, 0.9, 0.45, 1))
	elif weapon.mag <= 0 and weapon.reserve <= 0:
		ammo_label.text = "NO AMMO"
		ammo_label.add_theme_color_override("font_color", Color(1, 0.3, 0.3))
	elif weapon.mag <= 0:
		ammo_label.text = "EMPTY - PRESS R TO RELOAD"
		ammo_label.add_theme_color_override("font_color", Color(1, 0.9, 0.45, 1))
	else:
		ammo_label.text = "%d / %d" % [weapon.mag, weapon.reserve]
		ammo_label.add_theme_color_override("font_color", Color(1, 0.9, 0.45, 1))

## Mag bar: max = the weapon's mag size, value = current mag. While reloading
## the bar fills up as the reload progresses instead of snapping full.
func _update_mag_bar(weapon: Node) -> void:
	var mag_size := maxf(weapon.current_data.mag_size, 1)
	mag_bar.max_value = mag_size
	if weapon.reloading:
		var progress: float = 1.0 - weapon._reload_left / maxf(weapon.current_data.reload_time, 0.001)
		mag_bar.value = weapon.mag + (mag_size - weapon.mag) * progress
	else:
		mag_bar.value = weapon.mag

## Kills (from the round's replicated score table) and the number of players
## still alive in this match (characters not spectating).
func _update_match_labels(lobby: Node) -> void:
	var round := get_tree().get_first_node_in_group("round")
	if round and round.has_method("get_kill_score"):
		var kills := int(round.get_kill_score(Fusion.get_local_player_id()))
		_kills_label.text = "KILLS  %d" % kills
		if kills > _last_kills and _last_kills >= 0:
			_pop_kills()
		_last_kills = kills
	var total := 0
	var alive := 0
	if lobby:
		for pid in lobby._characters:
			var character: Node = lobby._characters[pid]
			total += 1
			if not (character.get("spectating") as bool):
				alive += 1
	_alive_label.text = "ALIVE  %d/%d" % [alive, total]

## (Re)builds the slot labels once, then only updates the highlight.
func _update_weapon_bar(weapon: Node) -> void:
	if _slot_labels.size() != weapon.loadout.size():
		_rebuild_slots(weapon)
	for i in _slot_labels.size():
		var active: bool = i == weapon.weapon_index
		_slot_labels[i].modulate = Color(1, 1, 1, 1) if active else Color(1, 1, 1, 0.45)
		_slot_labels[i].add_theme_color_override("font_color",
			Color(1, 0.85, 0.3) if active else Color(1, 1, 1))

func _rebuild_slots(weapon: Node) -> void:
	for child in _weapon_bar.get_children():
		child.queue_free()
	_slot_labels.clear()
	for i in weapon.loadout.size():
		var data: Resource = weapon.loadout[i]
		var slot_number: int = 3 if data.melee else i + 1
		var label := Label.new()
		label.text = "%d  %s" % [slot_number, data.weapon_name.to_upper()]
		label.add_theme_font_size_override("font_size", 20)
		label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
		label.add_theme_constant_override("outline_size", 6)
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_weapon_bar.add_child(label)
		_slot_labels.append(label)

func _pop_kills() -> void:
	if _pop_tween and _pop_tween.is_valid():
		_pop_tween.kill()
	_kills_label.scale = Vector2.ONE * 1.3
	_pop_tween = create_tween()
	_pop_tween.tween_property(_kills_label, "scale", Vector2.ONE, 0.18) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _on_local_damage_taken(_damage: float) -> void:
	if _flash_tween and _flash_tween.is_valid():
		_flash_tween.kill()
	damage_flash.color.a = 0.35
	_flash_tween = create_tween()
	_flash_tween.tween_property(damage_flash, "color:a", 0.0, 0.4)

func _format_number(number: int) -> String:
	return "%03d" % number