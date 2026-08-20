"""Presence updates (client heartbeats)."""
from sqlalchemy.orm import Session

from app.models.player import Player


def set_presence(
    db: Session,
    player: Player,
    online: bool | None = None,
    in_lobby: bool | None = None,
    in_game: bool | None = None,
) -> Player:
    if online is not None:
        player.is_online = online
    if in_lobby is not None:
        player.in_lobby = in_lobby
    if in_game is not None:
        player.in_game = in_game
    db.commit()
    db.refresh(player)
    return player