"""Token auth API tests: issuance, validation, authorization, rotation."""


def _register_and_token(client, name="taro", password="hunter2"):
    client.post("/api/auth/register", json={"name": name, "password": password})
    resp = client.post("/api/auth/token", json={"name": name, "password": password})
    assert resp.status_code == 200
    return resp.json()


def _auth_headers(token):
    return {"Authorization": f"Bearer {token}"}


def test_token_issued_with_profile(client):
    body = _register_and_token(client)
    assert len(body["token"]) >= 30
    assert body["player"]["name"] == "taro"
    assert "auth_token_hash" not in body["player"]
    assert "id" not in body["player"]
    assert "account_id" in body["player"]


def test_token_issuance_rejects_wrong_password(client):
    client.post("/api/auth/register", json={"name": "taro", "password": "hunter2"})
    resp = client.post("/api/auth/token", json={"name": "taro", "password": "wrong"})
    assert resp.status_code == 401
    assert resp.json()["detail"]["code"] == "INVALID_CREDENTIALS"


def test_me_with_valid_token(client):
    body = _register_and_token(client)
    resp = client.post("/api/auth/me", headers=_auth_headers(body["token"]))
    assert resp.status_code == 200
    assert resp.json()["name"] == "taro"


def test_me_with_invalid_token(client):
    resp = client.post("/api/auth/me", headers=_auth_headers("garbage-token"))
    assert resp.status_code == 401
    assert resp.json()["detail"]["code"] == "INVALID_TOKEN"


def test_me_without_header(client):
    resp = client.post("/api/auth/me")
    assert resp.status_code == 401


def test_patch_requires_own_token(client):
    a = _register_and_token(client, "alice")
    b = _register_and_token(client, "bob")
    alice_id, bob_id = a["player"]["account_id"], b["player"]["account_id"]

    resp = client.patch(f"/api/players/{alice_id}", json={"current_skin": 3})
    assert resp.status_code == 401

    resp = client.patch(f"/api/players/{alice_id}", json={"current_skin": 3}, headers=_auth_headers(b["token"]))
    assert resp.status_code == 403

    resp = client.patch(f"/api/players/{alice_id}", json={"current_skin": 3}, headers=_auth_headers(a["token"]))
    assert resp.status_code == 200
    assert resp.json()["current_skin"] == 3


def test_token_rotation_invalidates_old_token(client):
    first = _register_and_token(client)
    second = _register_and_token(client)
    assert first["token"] != second["token"]

    resp = client.post("/api/auth/me", headers=_auth_headers(first["token"]))
    assert resp.status_code == 401

    resp = client.post("/api/auth/me", headers=_auth_headers(second["token"]))
    assert resp.status_code == 200


def test_discord_account_can_auth_with_issued_token(client):
    from app.db.session import SessionLocal
    from app.services.discord_register import create_account_from_discord

    db = SessionLocal()
    try:
        player, token, _ = create_account_from_discord(db, discord_id=2001)
    finally:
        db.close()
    assert token

    resp = client.post("/api/auth/me", headers=_auth_headers(token))
    assert resp.status_code == 200
    assert resp.json()["account_id"] == player.account_id
    assert resp.json()["name"] == player.name