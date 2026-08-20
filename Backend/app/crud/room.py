"""Room registry persistence helpers."""
from datetime import datetime, timedelta, timezone

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core.config import settings
from app.models.room import Room


def _utcnow_naive() -> datetime:
    """Naive UTC now - matches DateTime columns (no tz) on SQLite + Postgres."""
    return datetime.now(timezone.utc).replace(tzinfo=None)


def get(db: Session, code: str) -> Room | None:
    return db.get(Room, code)


def upsert_heartbeat(
    db: Session,
    code: str,
    mode: str,
    host_account_id: str | None,
    players: list[dict],
) -> Room:
    room = db.get(Room, code)
    if room is None:
        room = Room(
            code=code,
            mode=mode,
            host_account_id=host_account_id,
            players=players,
            player_count=len(players),
        )
        db.add(room)
    else:
        room.mode = mode
        room.host_account_id = host_account_id
        room.players = players
        room.player_count = len(players)
    db.commit()
    db.refresh(room)
    return room


def list_active(db: Session, limit: int = 50) -> list[Room]:
    cutoff = _utcnow_naive() - timedelta(seconds=settings.room_stale_seconds)
    rows = db.execute(
        select(Room).where(Room.updated_at >= cutoff).order_by(Room.player_count.desc()).limit(limit)
    ).scalars()
    return list(rows)


def is_stale(db: Session, room: Room) -> bool:
    cutoff = _utcnow_naive() - timedelta(seconds=settings.room_stale_seconds)
    return room.updated_at < cutoff