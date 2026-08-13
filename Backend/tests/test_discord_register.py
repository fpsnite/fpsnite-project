"""Discord /register account creation tests."""
from app.db.session import SessionLocal
from app.models.player import Player
from app.services.auth import hash_token
from app.services.discord_register import create_account_from_discord, rotate_token_for_discord


def _fresh_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()


def test_creates_account_with_generated_token():
    for db in _fresh_db():
        player, token, error = create_account_from_discord(db, discord_id=1001)
        assert error is None
        assert player is not None
        assert player.discord_id == 1001
        assert token and len(token) >= 30
        assert player.auth_token_hash == hash_token(token)  # hashed, not plaintext


def test_generated_username_is_used_when_name_taken():
    for db in _fresh_db():
        p1, _, _ = create_account_from_discord(db, discord_id=1002, username="spike")
        assert p1.name == "spike"
        p2, _, err = create_account_from_discord(db, discord_id=1003, username="spike")
        assert err is None
        assert p2.name != "spike"  # retried with a suffix


def test_rejects_second_account_for_same_discord_user():
    for db in _fresh_db():
        p1, _, _ = create_account_from_discord(db, discord_id=1004)
        p2, _, error = create_account_from_discord(db, discord_id=1004)
        assert error == "ALREADY_LINKED"
        assert p2 is None
        assert p1.discord_id == 1004


def test_case_insensitive_username_collision_gets_suffix():
    for db in _fresh_db():
        create_account_from_discord(db, discord_id=1005, username="Neon")
        p2, _, err = create_account_from_discord(db, discord_id=1006, username="neon")
        assert err is None
        assert p2.name.lower() != "neon"


def test_existing_discord_link_found_via_db_lookup():
    for db in _fresh_db():
        p1, _, _ = create_account_from_discord(db, discord_id=1008)
        linked = db.get(Player, p1.id)
        assert linked.discord_id == 1008


def test_rotate_token_replaces_old_token():
    for db in _fresh_db():
        player, old_token, _ = create_account_from_discord(db, discord_id=1009)
        rotated, new_token = rotate_token_for_discord(db, discord_id=1009)
        assert rotated is not None
        assert new_token != old_token
        assert player.auth_token_hash == hash_token(new_token)
        assert player.auth_token_hash != hash_token(old_token)


def test_rotate_token_for_unlinked_user_returns_nothing():
    for db in _fresh_db():
        player, token = rotate_token_for_discord(db, discord_id=999999)
        assert player is None
        assert token is None