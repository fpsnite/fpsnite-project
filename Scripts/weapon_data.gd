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
## When set, the magazine never empties: firing costs no ammo and reloading
## is never needed (the HUD shows infinity instead of the counter).
@export var infinite_ammo := false
## Mag stays finite (drains and must be reloaded) but the reserve never runs
## out - the reload just refills the mag forever. Aim training uses this so
## the mag/reload loop still matters without ever running dry.
@export var infinite_reserve_ammo := false

@export_group("Feel")
## Extra spread cone (degrees) at full movement speed; lerped from
## spread_rad by the player's current speed - CS:GO-style accuracy loss
## while moving.
@export var moving_spread_deg := 0.0
## Upward camera pitch kick (degrees) applied per shot - weapon recoil.
@export var recoil_kick_deg := 0.0

# --- Shotguns / multi-pellet ---
## Number of hitscan rays fired per shot (shotgun = 3 pellets, each with its
## own spread jitter and its own bullet visual).
@export var pellets := 1

# --- Melee weapons ---
@export var melee := false
@export var melee_damage := 55.0
@export var melee_range := 2.5
@export var melee_time := 0.45  # swing duration / cooldown

# --- Visuals ---
@export var viewmodel: PackedScene  # has a "Muzzle" Marker3D for ranged guns
