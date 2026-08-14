class_name WeaponData
extends Resource
## Static weapon definition. New weapons are pure data: add a .tres next to
## the existing ones (rifle.tres, knife.tres) and drop it into a player's
## loadout - no code changes needed.

@export var weapon_id: String = "rifle"
@export var weapon_name: String = "Rifle"

# --- Ranged weapons ---
@export var auto := true  # hold to keep firing
@export var damage := 30.0
@export var headshot_multiplier := 2.0
@export var fire_rate := 11.0  # shots per second
@export var spread_rad := 0.012  # random cone per shot (client-applied, cosmetic)
@export var range := 200.0
@export var mag_size := 30
@export var reserve_ammo := 90
@export var reload_time := 2.0

# --- Melee weapons ---
@export var melee := false
@export var melee_damage := 55.0
@export var melee_range := 2.5
@export var melee_time := 0.45  # swing duration / cooldown

# --- Visuals ---
@export var viewmodel: PackedScene  # has a "Muzzle" Marker3D for ranged guns
