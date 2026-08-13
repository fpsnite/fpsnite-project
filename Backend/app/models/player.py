"""Player account model."""
from datetime import datetime

from sqlalchemy import BigInteger, Integer, String
from sqlalchemy.orm import Mapped, mapped_column
from sqlalchemy.sql import func

from app.db.session import Base


class Player(Base):
    __tablename__ = "players"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    name: Mapped[str] = mapped_column(String(24), unique=True, index=True)
    password_hash: Mapped[str] = mapped_column(String(255))
    skin_index: Mapped[int] = mapped_column(Integer, default=0)
    discord_id: Mapped[int | None] = mapped_column(BigInteger, unique=True, nullable=True)
    ## sha256 of the session token the game stores (token itself never saved).
    auth_token_hash: Mapped[str | None] = mapped_column(String(64), unique=True, nullable=True)
    created_at: Mapped[datetime] = mapped_column(server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(server_default=func.now(), onupdate=func.now())