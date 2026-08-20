"""Friendship persistence helpers."""
from sqlalchemy import and_, or_, select
from sqlalchemy.orm import Session

from app.models.friend import STATUS_ACCEPTED, STATUS_REQUESTED, Friendship


def get_pair(db: Session, account_a: str, account_b: str) -> Friendship | None:
    """Any friendship edge between two accounts, in either direction."""
    return db.execute(
        select(Friendship).where(
            or_(
                and_(
                    Friendship.requester_account_id == account_a,
                    Friendship.addressee_account_id == account_b,
                ),
                and_(
                    Friendship.requester_account_id == account_b,
                    Friendship.addressee_account_id == account_a,
                ),
            )
        )
    ).scalar_one_or_none()


def get_outgoing_request(db: Session, account_id: str, other: str) -> Friendship | None:
    return db.execute(
        select(Friendship).where(
            Friendship.requester_account_id == account_id,
            Friendship.addressee_account_id == other,
            Friendship.status == STATUS_REQUESTED,
        )
    ).scalar_one_or_none()


def get_incoming_request(db: Session, account_id: str, other: str) -> Friendship | None:
    return db.execute(
        select(Friendship).where(
            Friendship.requester_account_id == other,
            Friendship.addressee_account_id == account_id,
            Friendship.status == STATUS_REQUESTED,
        )
    ).scalar_one_or_none()


def list_accepted_ids(db: Session, account_id: str) -> list[str]:
    """account_ids of everyone this player has an accepted friendship with."""
    rows = db.execute(
        select(Friendship).where(
            or_(
                Friendship.requester_account_id == account_id,
                Friendship.addressee_account_id == account_id,
            ),
            Friendship.status == STATUS_ACCEPTED,
        )
    ).scalars()
    ids: list[str] = []
    for row in rows:
        friend = (
            row.addressee_account_id
            if row.requester_account_id == account_id
            else row.requester_account_id
        )
        ids.append(friend)
    return ids


def list_incoming_ids(db: Session, account_id: str) -> list[str]:
    rows = db.execute(
        select(Friendship).where(
            Friendship.addressee_account_id == account_id,
            Friendship.status == STATUS_REQUESTED,
        )
    ).scalars()
    return [r.requester_account_id for r in rows]


def create_request(db: Session, requester: str, addressee: str) -> Friendship:
    friendship = Friendship(
        requester_account_id=requester,
        addressee_account_id=addressee,
        status=STATUS_REQUESTED,
    )
    db.add(friendship)
    db.commit()
    db.refresh(friendship)
    return friendship