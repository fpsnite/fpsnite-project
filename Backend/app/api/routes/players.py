"""Account endpoints: register, login, token issuance/validation, profiles,
player info, presence heartbeats.

Tokens are the game's credential: the client stores the raw token locally and
sends it as `Authorization: Bearer <token>`; the DB only ever sees sha256.
v2 public identifier is `account_id` (numeric id is internal).
"""
from fastapi import APIRouter, HTTPException, status

from app.api.dependencies import CurrentPlayer, DbDep, get_current_player, resolve_player_or_404
from app.crud import player as player_crud
from app.models.player import Player
from app.schemas.player import LoginIn, PlayerOut, PlayerUpdate, PresenceIn, RegisterIn, TokenOut
from app.services.auth import hash_password, hash_token, generate_token, verify_password
from app.services.errors import APIError, ErrorCodes
from app.services.presence import set_presence

router = APIRouter(tags=["auth"])


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


## Full v2 player info (identity + coins + skins + stats + level + presence).
@router.get("/players/{account_id}", response_model=PlayerOut)
def get_player(account_id: str, db: DbDep = None) -> PlayerOut:
    return PlayerOut.model_validate(resolve_player_or_404(db, account_id))


## Player may only update their own profile (Bearer token must match).
@router.patch("/players/{account_id}", response_model=PlayerOut)
def update_profile(
    account_id: str, body: PlayerUpdate, player: CurrentPlayer = None, db: DbDep = None
) -> PlayerOut:
    if player.account_id != account_id:
        raise APIError(ErrorCodes.FORBIDDEN, "Not your profile.", status_code=403)
    if body.current_skin is not None:
        player.current_skin = body.current_skin
    if body.skins_locker is not None:
        player.skins_locker = list(dict.fromkeys(body.skins_locker))
    db.commit()
    db.refresh(player)
    return PlayerOut.model_validate(player)


## Presence heartbeat: the game reports online / in-lobby / in-game state.
@router.post("/players/{account_id}/presence", response_model=PlayerOut)
def update_presence(
    account_id: str, body: PresenceIn, player: CurrentPlayer = None, db: DbDep = None
) -> PlayerOut:
    if player.account_id != account_id:
        raise APIError(ErrorCodes.FORBIDDEN, "Not your profile.", status_code=403)
    updated = set_presence(
        db, player, online=body.online, in_lobby=body.in_lobby, in_game=body.in_game
    )
    return PlayerOut.model_validate(updated)