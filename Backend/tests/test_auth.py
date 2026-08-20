"""Auth + player profile API tests (accounts and profile)."""


def test_register_creates_account(client):
    resp = client.post("/api/auth/register", json={"name": "azumi", "password": "hunter2"})
    assert resp.status_code == 201
    body = resp.json()
    assert body["name"] == "azumi"
    assert body["current_skin"] == 0
    assert len(body["account_id"]) == 16
    assert "id" not in body
    assert "password" not in body
    assert body["coins"] == 0
    assert body["level"] == 1
    assert body["is_online"] is False


def test_register_rejects_duplicate_name_case_insensitive(client):
    client.post("/api/auth/register", json={"name": "azumi", "password": "hunter2"})
    resp = client.post("/api/auth/register", json={"name": "AZUMI", "password": "other"})
    assert resp.status_code == 409
    assert resp.json()["detail"]["code"] == "NAME_TAKEN"


def test_register_validates_inputs(client):
    assert client.post("/api/auth/register", json={"name": "  ", "password": "x"}).status_code == 422
    assert client.post("/api/auth/register", json={"name": "ok", "password": "ab"}).status_code == 422


def test_login_with_correct_password(client):
    client.post("/api/auth/register", json={"name": "kaito", "password": "hunter2"})
    resp = client.post("/api/auth/login", json={"name": "Kaito", "password": "hunter2"})
    assert resp.status_code == 200
    assert resp.json()["name"] == "kaito"


def test_login_with_wrong_password(client):
    client.post("/api/auth/register", json={"name": "kaito", "password": "hunter2"})
    resp = client.post("/api/auth/login", json={"name": "kaito", "password": "wrong"})
    assert resp.status_code == 401
    assert resp.json()["detail"]["code"] == "INVALID_CREDENTIALS"


def test_get_profile(client):
    created = client.post("/api/auth/register", json={"name": "sora", "password": "hunter2"}).json()
    resp = client.get(f"/api/players/{created['account_id']}")
    assert resp.status_code == 200
    assert resp.json()["name"] == "sora"


def test_get_profile_not_found(client):
    resp = client.get("/api/players/0000000000000000")
    assert resp.status_code == 404


def test_patch_skin_and_locker(client):
    client.post("/api/auth/register", json={"name": "ren", "password": "hunter2"})
    issued = client.post("/api/auth/token", json={"name": "ren", "password": "hunter2"}).json()
    headers = {"Authorization": f"Bearer {issued['token']}"}
    account_id = issued["player"]["account_id"]
    resp = client.patch(
        f"/api/players/{account_id}",
        json={"current_skin": 3, "skins_locker": [0, 3]},
        headers=headers,
    )
    assert resp.status_code == 200
    assert resp.json()["current_skin"] == 3
    assert resp.json()["skins_locker"] == [0, 3]
    assert resp.json()["name"] == "ren"

    fetched = client.get(f"/api/players/{account_id}").json()
    assert fetched["current_skin"] == 3