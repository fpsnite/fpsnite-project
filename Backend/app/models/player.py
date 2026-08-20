"""Player account model."""
from datetime import datetime

from sqlalchemy import JSON, BigInteger, Boolean, Integer, String
from sqlalchemy.orm import Mapped, mapped_column
from sqlalchemy.sql import func

from app.db.session import Base


class Player(Base):
    __tablename__ = "players"

    ## Internal autoincrement PK. Never exposed in API responses (v2 uses account_id).
    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    ## Public 16-char hex UID (secrets.token_hex(8)); the v2 identifier.
    account_id: Mapped[str] = mapped_column(String(16), unique=True, index=True)
    name: Mapped[str] = mapped_column(String(24), unique=True, index=True)
    password_hash: Mapped[str] = mapped_column(String(255))
    discord_id: Mapped[int | None] = mapped_column(BigInteger, unique=True, nullable=True)
    ## sha256 of the session token the game stores (token itself never saved).
    auth_token_hash: Mapped[str | None] = mapped_column(String(64), unique=True, nullable=True)

    ## Currency + cosmetics.
    coins: Mapped[int] = mapped_column(Integer, default=0)
    current_skin: Mapped[int] = mapped_column(Integer, default=0)
    skins_locker: Mapped[list] = mapped_column(JSON, default=list)

    ## Match stats.
    kills: Mapped[int] = mapped_column(Integer, default=0)
    deaths: Mapped[int] = mapped_column(Integer, default=0)
    wins: Mapped[int] = mapped_column(Integer, default=0)
    playtime_seconds: Mapped[int] = mapped_column(Integer, default=0)

    ## Progression.
    level: Mapped[int] = mapped_column(Integer, default=1)
    xp: Mapped[int] = mapped_column(Integer, default=0)

    ## Presence (set by client heartbeats).
    is_online: Mapped[bool] = mapped_column(Boolean, default=False)
    in_lobby: Mapped[bool] = mapped_column(Boolean, default=False)
    in_game: Mapped[bool] = mapped_column(Boolean, default=False)

    created_at: Mapped[datetime] = mapped_column(server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(server_default=func.now(), onupdate=func.now())