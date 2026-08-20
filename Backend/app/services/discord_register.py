"""Account creation via Discord /register.

Shared by the Discord cog and tests. The bot never touches the API: it writes
through the same ORM, so linking a Discord ID is not exposed as a public
endpoint (no way for an attacker to claim another user's Discord link).
Accounts created here are login-token accounts - the token is the credential
the game client accepts, shown to the user exactly once.
"""
import random
import secrets
import string

from sqlalchemy.orm import Session

from app.crud import player as player_crud
from app.models.player import Player
from app.services.auth import hash_password, hash_token, generate_token, generate_account_id

_USERNAME_ALPHABET = string.digits
_MAX_USERNAME_RETRIES = 8


def create_account_from_discord(
    db: Session,
    discord_id: int,
    username: str | None = None,
) -> tuple[Player | None, str | None, str | None]:
    """Create (or refuse) an account for a Discord user.

    Returns (player, generated_token, error_code). On success player and
    token are set; on failure error_code is one of:
      "ALREADY_LINKED" - this Discord user already has an account.
      "NAME_TAKEN"     - requested username collided after all retries.
    """
    existing = player_crud.get_by_discord_id(db, discord_id)
    if existing is not None:
        return None, None, "ALREADY_LINKED"

    if username is None:
        username = _generate_username()
    token = generate_token()

    created = None
    for _ in range(_MAX_USERNAME_RETRIES):
        if player_crud.get_by_name(db, username) is not None:
            username = _generate_username()
            continue
        created = Player(
            account_id=generate_account_id(),
            name=username,
            password_hash=hash_password(secrets.token_urlsafe(9)),
            auth_token_hash=hash_token(token),
            discord_id=discord_id,
        )
        db.add(created)
        db.commit()
        db.refresh(created)
        break

    if created is None:
        return None, None, "NAME_TAKEN"
    return created, token, None


def rotate_token_for_discord(db: Session, discord_id: int) -> tuple[Player | None, str | None]:
    """Re-issue a login token for a linked account (e.g. the user lost it).

    The old token stops working immediately. Returns (player, new_token).
    """
    player = player_crud.get_by_discord_id(db, discord_id)
    if player is None:
        return None, None
    token = generate_token()
    player.auth_token_hash = hash_token(token)
    db.commit()
    db.refresh(player)
    return player, token


def _generate_username() -> str:
    return "Player" + "".join(random.choices(_USERNAME_ALPHABET, k=6))