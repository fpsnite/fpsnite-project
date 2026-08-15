extends CanvasLayer
## Aim Training HUD: arena title (top-center), live score (top-left, pops on
## increase) with the session best underneath, a contextual hint line
## (bottom-center), and full weapon info (bottom-left): equipped weapon name,
## mag bar, ammo count with reload/empty states, plus a weapon slot bar
## (bottom-right). Pure presentation - the main instance drives the score/title
## through set_* methods; weapon state is polled from the local aim player.

@onready var title_label: Label = %TitleLabel
@onready var score_label: Label = %ScoreLabel
@onready var best_label: Label = %BestLabel
@onready var hint_label: Label = %HintLabel
@onready var ammo_label: Label = %AmmoLabel
@onready var weapon_label: Label = %WeaponLabel
@onready var mag_bar: ProgressBar = %MagBar
@onready var system: Node3D = get_node("../AimSystem")

var _last_score := -1
var _pop_tween: Tween
var _weapon_bar: HBoxContainer
var _slot_labels: Array[Label] = []
var _active_slot := -1
var _fps_label: Label
var _mode_acc_label: Label
var _global_acc_label: Label

func _ready() -> void:
	add_to_group("aim_hud")
	_make_weapon_bar()
	_make_stat_labels()

func _make_stat_labels() -> void:
	var small := LabelSettings.new()
	small.font_size = 18
	small.font_color = Color(1, 1, 1, 0.8)
	small.outline_size = 4
	small.outline_color = Color(0, 0, 0, 0.5)
	_fps_label = Label.new()
	_fps_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_fps_label.offset_left = -200.0
	_fps_label.offset_top = 16.0
	_fps_label.offset_right = -16.0
	_fps_label.offset_bottom = 48.0
	_fps_label.label_settings = small
	_fps_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_fps_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fps_label)
	_mode_acc_label = Label.new()
	_mode_acc_label.offset_left = 26.0
	_mode_acc_label.offset_top = 116.0
	_mode_acc_label.offset_right = 260.0
	_mode_acc_label.offset_bottom = 140.0
	_mode_acc_label.label_settings = small
	_mode_acc_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_mode_acc_label)
	_global_acc_label = Label.new()
	_global_acc_label.offset_left = 26.0
	_global_acc_label.offset_top = 140.0
	_global_acc_label.offset_right = 260.0
	_global_acc_label.offset_bottom = 164.0
	_global_acc_label.label_settings = small
	_global_acc_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_global_acc_label)

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

func _process(_delta: float) -> void:
	_fps_label.text = "FPS %d" % Engine.get_frames_per_second()
	_mode_acc_label.text = "ACCURACY %s" % _accuracy(system.mode_shots_fired, system.mode_shots_hit)
	_global_acc_label.text = "GLOBAL %s" % _accuracy(system.shots_fired, system.shots_hit)
	var player := get_tree().get_first_node_in_group("aim_player")
	if player == null:
		return
	var weapon := player.get_node_or_null("CameraPivot/Camera3D/Weapon")
	if weapon == null:
		return
	weapon_label.text = weapon.current_data.weapon_name.to_upper()
	_update_ammo(weapon)
	mag_bar.max_value = maxf(weapon.current_data.mag_size, 1)
	if weapon.reloading:
		# The bar fills up as the reload progresses instead of snapping full.
		var progress: float = 1.0 - weapon._reload_left / maxf(weapon.current_data.reload_time, 0.001)
		mag_bar.value = weapon.mag + (weapon.current_data.mag_size - weapon.mag) * progress
	else:
		mag_bar.value = weapon.mag
	_update_slots(weapon)

## Bullets that hit a target as a percentage of bullets fired; "--" before
## the first shot of a set.
func _accuracy(fired: int, hit: int) -> String:
	if fired <= 0:
		return "--%"
	return "%d%%" % roundf(100.0 * hit / fired)

## Mag / reserve / reload states. Red "NO AMMO" when the mag is empty and
## there is nothing left in the reserve; "30 / INF" when the reserve is
## endless (aim training) - the mag still drains and reloads.
func _update_ammo(weapon: Node) -> void:
	if weapon.current_data.infinite_ammo:
		ammo_label.text = "INFINITE"
		_ammo_red(false)
	elif weapon.reloading:
		ammo_label.text = "RELOADING..."
		_ammo_red(false)
	elif weapon.current_data.infinite_reserve_ammo:
		ammo_label.text = "%d / INF" % weapon.mag
		_ammo_red(false)
	elif weapon.mag <= 0 and weapon.reserve <= 0:
		ammo_label.text = "NO AMMO"
		_ammo_red(true)
	elif weapon.mag <= 0:
		ammo_label.text = "EMPTY - PRESS R TO RELOAD"
		_ammo_red(false)
	else:
		ammo_label.text = "%d / %d" % [weapon.mag, weapon.reserve]
		_ammo_red(false)

func _ammo_red(red: bool) -> void:
	ammo_label.label_settings.font_color = Color(1, 0.3, 0.3) if red else Color(1, 1, 1, 0.95)

## (Re)builds the slot labels once, then only updates the highlight when the
## active slot changes (avoiding per-frame theme cache invalidation).
func _update_slots(weapon: Node) -> void:
	if _slot_labels.size() != weapon.loadout.size():
		_rebuild_slots(weapon)
	if _active_slot == weapon.weapon_index:
		return
	_active_slot = weapon.weapon_index
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

func set_title(text: String) -> void:
	title_label.text = text

func set_score(score: int) -> void:
	score_label.text = str(score)
	if score > _last_score:
		_pop_score()
	_last_score = score

func set_best(best: int) -> void:
	best_label.text = "BEST %d" % best

func set_hint(text: String) -> void:
	hint_label.text = text

## The hub has no scoring - hide the score/best/accuracy pair there.
func set_score_visible(visible: bool) -> void:
	score_label.visible = visible
	best_label.visible = visible
	_mode_acc_label.visible = visible
	_global_acc_label.visible = visible

func _pop_score() -> void:
	if _pop_tween and _pop_tween.is_valid():
		_pop_tween.kill()
	score_label.scale = Vector2.ONE * 1.25
	_pop_tween = create_tween()
	_pop_tween.tween_property(score_label, "scale", Vector2.ONE, 0.18) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
