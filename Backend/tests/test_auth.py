"""Auth + player profile API tests (accounts and profile)."""


def test_register_creates_account(client):
    resp = client.post("/api/auth/register", json={"name": "azumi", "password": "hunter2"})
    assert resp.status_code == 201
    body = resp.json()
    assert body["name"] == "azumi"
    assert body["skin_index"] == 0
    assert "id" in body
    assert "password" not in body


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
    resp = client.get(f"/api/players/{created['id']}")
    assert resp.status_code == 200
    assert resp.json()["name"] == "sora"


def test_get_profile_not_found(client):
    resp = client.get("/api/players/99999")
    assert resp.status_code == 404


def test_patch_skin_index(client):
    client.post("/api/auth/register", json={"name": "ren", "password": "hunter2"})
    issued = client.post("/api/auth/token", json={"name": "ren", "password": "hunter2"}).json()
    headers = {"Authorization": f"Bearer {issued['token']}"}
    player_id = issued["player"]["id"]
    resp = client.patch(f"/api/players/{player_id}", json={"skin_index": 3}, headers=headers)
    assert resp.status_code == 200
    assert resp.json()["skin_index"] == 3
    assert resp.json()["name"] == "ren"

    fetched = client.get(f"/api/players/{player_id}").json()
    assert fetched["skin_index"] == 3
