"""Friends API tests: request -> accept -> list -> remove, auth enforcement."""


def _mk(client, name):
    client.post("/api/auth/register", json={"name": name, "password": "hunter2"})
    body = client.post("/api/auth/token", json={"name": name, "password": "hunter2"}).json()
    return body["token"], body["player"]["account_id"]


def _auth(token):
    return {"Authorization": f"Bearer {token}"}


def test_friend_flow(client):
    t_a, id_a = _mk(client, "alice")
    t_b, id_b = _mk(client, "bob")

    # request
    r = client.post(f"/api/friends/{id_b}/request", headers=_auth(t_a))
    assert r.status_code == 201
    assert r.json()["status"] == "requested"

    # duplicate request
    r = client.post(f"/api/friends/{id_b}/request", headers=_auth(t_a))
    assert r.status_code == 409

    # bob sees incoming request
    r = client.get("/api/friends/requests", headers=_auth(t_b))
    assert r.status_code == 200
    assert [x["requester_account_id"] for x in r.json()] == [id_a]

    # bob accepts
    r = client.post(f"/api/friends/{id_a}/accept", headers=_auth(t_b))
    assert r.status_code == 200
    assert r.json()["account_id"] == id_a

    # both list each other
    r = client.get("/api/friends", headers=_auth(t_a))
    assert [x["account_id"] for x in r.json()] == [id_b]
    r = client.get("/api/friends", headers=_auth(t_b))
    assert [x["account_id"] for x in r.json()] == [id_a]

    # removing works from either side
    r = client.delete(f"/api/friends/{id_b}", headers=_auth(t_a))
    assert r.status_code == 204
    r = client.get("/api/friends", headers=_auth(t_a))
    assert r.json() == []


def test_decline_request(client):
    t_a, id_a = _mk(client, "carol")
    t_b, id_b = _mk(client, "dave")
    client.post(f"/api/friends/{id_b}/request", headers=_auth(t_a))
    r = client.post(f"/api/friends/{id_a}/decline", headers=_auth(t_b))
    assert r.status_code == 200
    assert r.json()["status"] == "declined"
    assert client.get("/api/friends", headers=_auth(t_a)).json() == []


def test_friend_requests_require_auth(client):
    r = client.post("/api/friends/abcdef0000000001/request")
    assert r.status_code == 401


def test_cannot_friend_self(client):
    t_a, id_a = _mk(client, "eve")
    r = client.post(f"/api/friends/{id_a}/request", headers=_auth(t_a))
    assert r.status_code == 400


def test_friend_target_must_exist(client):
    t_a, _ = _mk(client, "frank")
    r = client.post("/api/friends/0000000000000000/request", headers=_auth(t_a))
    assert r.status_code == 404