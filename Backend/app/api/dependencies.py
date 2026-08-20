"""Shared FastAPI dependencies: DB session + current-player resolution."""
from typing import Annotated

from fastapi import Depends, Header
from sqlalchemy.orm import Session

from app.crud import player as player_crud
from app.models.player import Player
from app.services.auth import hash_token
from app.services.errors import APIError, ErrorCodes


def get_db() -> Session:
    from app.db.session import SessionLocal

    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()


DbDep = Annotated[Session, Depends(get_db)]


def _bearer_token(authorization: str | None) -> str:
    if not authorization or not authorization.startswith("Bearer "):
        raise APIError(ErrorCodes.MISSING_TOKEN, "Missing token.", status_code=401)
    token = authorization.removeprefix("Bearer ").strip()
    if not token:
        raise APIError(ErrorCodes.MISSING_TOKEN, "Missing token.", status_code=401)
    return token


def get_current_player(
    authorization: Annotated[str | None, Header()] = None,
    db: DbDep = None,
) -> Player:
    """401 unless the Bearer token matches a player."""
    player = player_crud.get_by_token_hash(db, hash_token(_bearer_token(authorization)))
    if player is None:
        raise APIError(ErrorCodes.INVALID_TOKEN, "Invalid token.", status_code=401)
    return player


CurrentPlayer = Annotated[Player, Depends(get_current_player)]


def resolve_player_or_404(db: Session, account_id: str) -> Player:
    player = player_crud.get_by_account_id(db, account_id)
    if player is None:
        raise APIError(ErrorCodes.NOT_FOUND, "Player not found.", status_code=404)
    return player