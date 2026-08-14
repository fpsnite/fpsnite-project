class_name GameModes
## Single source of truth for game modes: max players, display names, and
## helpers. Applies to every room (party + play flow) - the room master kicks
## newcomers when a room is at its mode's cap, and the ready-up flow uses the
## same table.

const MODES := {
	"ffa": {"name": "Free For All", "max_players": 8},
	"tdm": {"name": "Team Deathmatch", "max_players": 8},
	"test": {"name": "Test Mode", "max_players": 4},
}

const COUNTDOWN_SECONDS := 5

static func mode_name(mode_id: String) -> String:
	return str(MODES.get(mode_id, {}).get("name", mode_id.to_upper()))

static func max_players(mode_id: String) -> int:
	return int(MODES.get(mode_id, {}).get("max_players", 8))

static func is_known(mode_id: String) -> bool:
	return MODES.has(mode_id)
