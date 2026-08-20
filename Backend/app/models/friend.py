"""Friendship model."""
from datetime import datetime

from sqlalchemy import DateTime, String, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column
from sqlalchemy.sql import func

from app.db.session import Base

STATUS_REQUESTED = "requested"
STATUS_ACCEPTED = "accepted"
STATUS_DECLINED = "declined"


class Friendship(Base):
    __tablename__ = "friendships"
    __table_args__ = (
        UniqueConstraint("requester_account_id", "addressee_account_id", name="uq_friendship_pair"),
    )

    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    ## account_id of whoever sent the request.
    requester_account_id: Mapped[str] = mapped_column(String(16), index=True)
    ## account_id of whoever received the request.
    addressee_account_id: Mapped[str] = mapped_column(String(16), index=True)
    status: Mapped[str] = mapped_column(String(16), default=STATUS_REQUESTED)
    created_at: Mapped[datetime] = mapped_column(server_default=func.now())