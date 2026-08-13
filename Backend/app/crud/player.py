"""Player persistence helpers."""
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.models.player import Player


def get_by_id(db: Session, player_id: int) -> Player | None:
    return db.get(Player, player_id)


def get_by_discord_id(db: Session, discord_id: int) -> Player | None:
    return db.execute(select(Player).where(Player.discord_id == discord_id)).scalar_one_or_none()


def get_by_token_hash(db: Session, token_hash: str) -> Player | None:
    return db.execute(select(Player).where(Player.auth_token_hash == token_hash)).scalar_one_or_none()


def get_by_name(db: Session, name: str) -> Player | None:
    normalized = name.strip().lower()
    return db.execute(select(Player).where(func.lower(Player.name) == normalized)).scalar_one_or_none()


def create(db: Session, name: str, password_hash: str, skin_index: int = 0) -> Player:
    player = Player(name=name, password_hash=password_hash, skin_index=skin_index)
    db.add(player)
    db.commit()
    db.refresh(player)
    return player