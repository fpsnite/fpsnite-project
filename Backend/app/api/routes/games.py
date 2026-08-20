"""Game mode catalog endpoints (static metadata served by the backend)."""
from fastapi import APIRouter

from app.schemas.game import GameOut

router = APIRouter(prefix="/games", tags=["games"])

DEFAULT_ARENA = "res://Scenes/fps_map.tscn"

MODES: dict[str, GameOut] = {
    "ffa": GameOut(
        id="ffa", name="Free For All", max_players=8, min_players=2, kill_target=0,
        map=DEFAULT_ARENA,
        weapons=["res://Resources/Weapons/rifle.tres", "res://Resources/Weapons/shotgun.tres", "res://Resources/Weapons/knife.tres"],
    ),
    "tdm": GameOut(
        id="tdm", name="Team Deathmatch", max_players=8, min_players=4, kill_target=15,
        map=DEFAULT_ARENA,
        weapons=["res://Resources/Weapons/rifle.tres", "res://Resources/Weapons/knife.tres"],
        team_mode=True,
    ),
    "1v1": GameOut(
        id="1v1", name="1v1", max_players=2, min_players=2, kill_target=15,
        map="res://GameScenes/1v1Map/map.tscn",
        weapons=["res://Resources/Weapons/rifle.tres", "res://Resources/Weapons/knife.tres"],
    ),
    "aim": GameOut(
        id="aim", name="Aim Training", max_players=1, min_players=1, kill_target=0,
        map=DEFAULT_ARENA,
        weapons=["res://Resources/Weapons/rifle.tres", "res://Resources/Weapons/knife.tres"],
        solo=True,
    ),
    "build": GameOut(
        id="build", name="Free Build", max_players=1, min_players=1, kill_target=0,
        map="res://GameScenes/FreeBuild/free_build.tscn",
        weapons=["res://Resources/Weapons/rifle.tres", "res://Resources/Weapons/shotgun.tres", "res://Resources/Weapons/knife.tres"],
        infinite_ammo=True,
        solo=True,
    ),
}


@router.get("", response_model=list[GameOut])
def list_games() -> list[GameOut]:
    return list(MODES.values())


@router.get("/{mode_id}", response_model=GameOut)
def get_game(mode_id: str) -> GameOut:
    from fastapi import HTTPException

    game = MODES.get(mode_id)
    if game is None:
        raise HTTPException(status_code=404, detail={"code": "NOT_FOUND", "message": "Unknown game mode."})
    return game