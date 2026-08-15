class_name GameModes
## Single source of truth for game modes: max players, display names, kill
## targets, and helpers. Applies to every room (party + play flow) - the room
## master kicks newcomers when a room is at its mode's cap, and the ready-up
## flow uses the same table.

## Default arena used by every mode that doesn't pick its own map.
const DEFAULT_ARENA := "res://Scenes/fps_map.tscn"

const MODES := {
	"ffa":  {"name": "Free For All",  "max_players": 8, "min_players": 2, "kill_target": 0,
		"map": DEFAULT_ARENA,
		"weapons": ["res://Resources/Weapons/rifle.tres",
			"res://Resources/Weapons/shotgun.tres",
			"res://Resources/Weapons/knife.tres"]},
	"tdm":  {"name": "Team Deathmatch", "max_players": 8, "min_players": 4, "kill_target": 15,
		"map": DEFAULT_ARENA,
		"weapons": ["res://Resources/Weapons/rifle.tres",
			"res://Resources/Weapons/knife.tres"]},
	"1v1":  {"name": "1v1",           "max_players": 2, "min_players": 2, "kill_target": 15,
		"map": "res://GameScenes/1v1Map/map.tscn",
		"weapons": ["res://Resources/Weapons/rifle.tres",
			"res://Resources/Weapons/knife.tres"]},
	"aim":  {"name": "Aim Training",  "max_players": 1, "min_players": 1, "kill_target": 0,
		"map": DEFAULT_ARENA,
		"weapons": ["res://Resources/Weapons/rifle.tres",
			"res://Resources/Weapons/knife.tres"]},
	"build": {"name": "Free Build",   "max_players": 1, "min_players": 1, "kill_target": 0,
		"map": "res://GameScenes/FreeBuild/free_build.tscn",
		"weapons": ["res://Resources/Weapons/rifle.tres",
			"res://Resources/Weapons/shotgun.tres",
			"res://Resources/Weapons/knife.tres"],
		"infinite_ammo": true},
}

## Solo modes (aim training, free build) can never run with another player
## in the room.
static func is_solo(mode_id: String) -> bool:
	return mode_id == "aim" or mode_id == "build"

## Free Build is the creative sandbox: infinite health + sprint, no damage.
static func is_build(mode_id: String) -> bool:
	return mode_id == "build"

## Kill target for the mode: 0 = endless (FFA / aim), >0 = first-to-X wins.
static func kill_target(mode_id: String) -> int:
	return int(MODES.get(mode_id, {}).get("kill_target", 0))

## True for team-based modes (TDM) where team damage should be blocked.
static func is_team_mode(mode_id: String) -> bool:
	return mode_id == "tdm"

## True for 1v1 — individual kills, no teams, first-to-X.
static func is_1v1(mode_id: String) -> bool:
	return mode_id == "1v1"

const COUNTDOWN_SECONDS := 5

static func mode_name(mode_id: String) -> String:
	return str(MODES.get(mode_id, {}).get("name", mode_id.to_upper()))

static func max_players(mode_id: String) -> int:
	return int(MODES.get(mode_id, {}).get("max_players", 8))

## Minimum players that must be in the room before the ready countdown can
## start: everyone ready AND at least this many players in the room.
static func min_players(mode_id: String) -> int:
	return int(MODES.get(mode_id, {}).get("min_players", 1))

## The mode's weapon pool as WeaponData resources: players spawn with exactly
## these weapons (replacing the default loadout). Empty = keep the default.
## Modes with "infinite_ammo" get duplicated copies flagged never-empty, so
## the shared .tres files stay untouched.
static func weapon_pool(mode_id: String) -> Array[WeaponData]:
	var pool: Array[WeaponData] = []
	var infinite: bool = bool(MODES.get(mode_id, {}).get("infinite_ammo", false))
	for path: String in MODES.get(mode_id, {}).get("weapons", []):
		var data := load(path) as WeaponData
		if data == null:
			continue
		if infinite:
			data = data.duplicate() as WeaponData
			data.infinite_ammo = true
		pool.append(data)
	return pool

static func is_known(mode_id: String) -> bool:
	return MODES.has(mode_id)

## The map scene a mode's match runs on (instanced under GameArena by lobby.gd).
static func map_scene(mode_id: String) -> String:
	return str(MODES.get(mode_id, {}).get("map", DEFAULT_ARENA))

## True when the mode runs on a custom map instead of the default box arena.
static func uses_custom_map(mode_id: String) -> bool:
	return map_scene(mode_id) != DEFAULT_ARENA
