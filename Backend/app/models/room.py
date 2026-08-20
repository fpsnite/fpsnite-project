"""Live room registry (heartbeat-driven)."""
from datetime import datetime

from sqlalchemy import JSON, DateTime, Integer, String
from sqlalchemy.orm import Mapped, mapped_column
from sqlalchemy.sql import func

from app.db.session import Base


class Room(Base):
    __tablename__ = "rooms"

    ## 5-char room code (the Photon room name), the natural key.
    code: Mapped[str] = mapped_column(String(5), primary_key=True)
    mode: Mapped[str] = mapped_column(String(16), default="ffa")
    host_account_id: Mapped[str | None] = mapped_column(String(16), nullable=True)
    ## [{account_id, name}] currently reported in the room.
    players: Mapped[list] = mapped_column(JSON, default=list)
    player_count: Mapped[int] = mapped_column(Integer, default=0)
    created_at: Mapped[datetime] = mapped_column(server_default=func.now())
    ## Refreshed by every heartbeat; rooms older than the TTL are stale.
    updated_at: Mapped[datetime] = mapped_column(server_default=func.now(), onupdate=func.now())