"""Account endpoints: register, login, token issuance/validation, profiles.

Tokens are the game's credential: the client stores the raw token locally and
sends it as `Authorization: Bearer <token>`; the DB only ever sees sha256.
"""
from typing import Annotated

from fastapi import APIRouter, Depends, Header, HTTPException, status
from sqlalchemy.orm import Session

from app.crud import player as player_crud
from app.models.player import Player
from app.schemas.player import LoginIn, PlayerOut, PlayerUpdate, RegisterIn, TokenOut
from app.services.auth import hash_password, hash_token, generate_token, verify_password

router = APIRouter(tags=["auth"])


def _get_db() -> Session:
    from app.db.session import SessionLocal

    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()


DbDep = Annotated[Session, Depends(_get_db)]


def _bearer_token(authorization: str | None) -> str:
    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(status_code=401, detail={"code": "INVALID_TOKEN", "message": "Missing token."})
    token = authorization.removeprefix("Bearer ").strip()
    if not token:
        raise HTTPException(status_code=401, detail={"code": "INVALID_TOKEN", "message": "Missing token."})
    return token


def get_current_player(
    authorization: Annotated[str | None, Header()] = None,
    db: DbDep = None,
) -> Player:
    """401 unless the Bearer token matches a player."""
    player = player_crud.get_by_token_hash(db, hash_token(_bearer_token(authorization)))
    if player is None:
        raise HTTPException(status_code=401, detail={"code": "INVALID_TOKEN", "message": "Invalid token."})
    return player


CurrentPlayer = Annotated[Player, Depends(get_current_player)]


@router.post("/auth/register", response_model=PlayerOut, status_code=201)
def register(body: RegisterIn, db: DbDep = None) -> PlayerOut:
    if player_crud.get_by_name(db, body.name) is not None:
        raise HTTPException(status_code=409, detail={"code": "NAME_TAKEN", "message": "That username is taken."})
    player = player_crud.create(db, name=body.name, password_hash=hash_password(body.password))
    return PlayerOut.model_validate(player)


@router.post("/auth/login", response_model=PlayerOut)
def login(body: LoginIn, db: DbDep = None) -> PlayerOut:
    player = player_crud.get_by_name(db, body.name)
    if player is None or not verify_password(body.password, player.password_hash):
        raise HTTPException(
            status_code=401, detail={"code": "INVALID_CREDENTIALS", "message": "Wrong username or password."}
        )
    return PlayerOut.model_validate(player)


## Issues (or rotates) a login token. Only this response ever contains the
## raw token; the DB stores its sha256.
@router.post("/auth/token", response_model=TokenOut)
def issue_token(body: LoginIn, db: DbDep = None) -> TokenOut:
    player = player_crud.get_by_name(db, body.name)
    if player is None or not verify_password(body.password, player.password_hash):
        raise HTTPException(
            status_code=401, detail={"code": "INVALID_CREDENTIALS", "message": "Wrong username or password."}
        )
    token = generate_token()
    player.auth_token_hash = hash_token(token)
    db.commit()
    return TokenOut(token=token, player=PlayerOut.model_validate(player))


## Token validation used by the game's "connecting" and auto-login flow.
@router.post("/auth/me", response_model=PlayerOut)
def me(player: CurrentPlayer = None) -> PlayerOut:
    return PlayerOut.model_validate(player)


@router.get("/players/{player_id}", response_model=PlayerOut)
def get_profile(player_id: int, db: DbDep = None) -> PlayerOut:
    player = player_crud.get_by_id(db, player_id)
    if player is None:
        raise HTTPException(status_code=404, detail={"code": "NOT_FOUND", "message": "Player not found."})
    return PlayerOut.model_validate(player)


## Player may only update their own profile (Bearer token must match).
@router.patch("/players/{player_id}", response_model=PlayerOut)
def update_profile(player_id: int, body: PlayerUpdate, player: CurrentPlayer = None, db: DbDep = None) -> PlayerOut:
    if player.id != player_id:
        raise HTTPException(status_code=403, detail={"code": "FORBIDDEN", "message": "Not your profile."})
    player.skin_index = body.skin_index
    db.commit()
    db.refresh(player)
    return PlayerOut.model_validate(player)