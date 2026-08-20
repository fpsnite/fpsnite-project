"""Game mode catalog API schemas (static)."""
from pydantic import BaseModel


class GameOut(BaseModel):
    id: str
    name: str
    max_players: int
    min_players: int
    kill_target: int
    map: str
    weapons: list[str]
    infinite_ammo: bool = False
    solo: bool = False
    team_mode: bool = False