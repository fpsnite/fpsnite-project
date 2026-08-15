class_name GameModes
## Single source of truth for game modes: max players, display names, kill
## targets, and helpers. Applies to every room (party + play flow) - the room
## master kicks newcomers when a room is at its mode's cap, and the ready-up
## flow uses the same table.

const MODES := {
	"ffa":  {"name": "Free For All",  "max_players": 8, "kill_target": 0},
	"tdm":  {"name": "Team Deathmatch", "max_players": 8, "kill_target": 15},
	"1v1":  {"name": "1v1",           "max_players": 2, "kill_target": 10},
	"aim":  {"name": "Aim Training",  "max_players": 1, "kill_target": 0},
}

## Solo modes (aim training) can never run with another player in the room.
static func is_solo(mode_id: String) -> bool:
	return mode_id == "aim"

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

static func is_known(mode_id: String) -> bool:
	return MODES.has(mode_id)
