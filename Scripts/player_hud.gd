extends CanvasLayer
## Bottom-center HUD: player number, sprint stamina, health bar, ammo and the
## equipped weapon name. Reads state from the local player instance (which the
## server drives through WeaponSystem's sync_health / ammo signals).

@onready var sprint_bar: ProgressBar = $Box/SprintRow/SprintBar
@onready var force_label: Label = $Box/ForceLabel
@onready var health_bar: ProgressBar = $Box/HealthRow/HealthBar
@onready var ammo_label: Label = $Box/AmmoLabel
@onready var weapon_label: Label = $Box/WeaponLabel
@onready var damage_flash: ColorRect = $DamageFlash

var _flash_tween: Tween

func _ready() -> void:
	var weapon_system := get_tree().get_first_node_in_group("weapon_system")
	if weapon_system:
		weapon_system.local_damage_taken.connect(_on_local_damage_taken)

func _process(_delta: float) -> void:
	var lobby := get_tree().get_first_node_in_group("lobby")
	var player: Node = lobby._characters.get(Fusion.get_local_player_id()) if lobby else null
	if player == null:
		return
	sprint_bar.value = player.stamina
	force_label.text = _format_number(player.player_number)
	health_bar.value = player.health
	var weapon := player.get_node_or_null("CameraPivot/Weapon")
	if weapon:
		weapon_label.text = weapon.current_data.weapon_name
		if weapon.reloading:
			ammo_label.text = "RELOADING..."
		else:
			ammo_label.text = "%d / %d" % [weapon.mag, weapon.reserve]

func _on_local_damage_taken(_damage: float) -> void:
	if _flash_tween and _flash_tween.is_valid():
		_flash_tween.kill()
	damage_flash.color.a = 0.35
	_flash_tween = create_tween()
	_flash_tween.tween_property(damage_flash, "color:a", 0.0, 0.4)

func _format_number(number: int) -> String:
	return "%03d" % number