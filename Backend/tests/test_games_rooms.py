"""Games catalog and rooms registry API tests."""


def _mk(client, name):
    client.post("/api/auth/register", json={"name": name, "password": "hunter2"})
    body = client.post("/api/auth/token", json={"name": name, "password": "hunter2"}).json()
    return body["token"], body["player"]["account_id"]


def _auth(token):
    return {"Authorization": f"Bearer {token}"}


def test_games_catalog(client):
    r = client.get("/api/games")
    assert r.status_code == 200
    modes = {g["id"] for g in r.json()}
    assert modes == {"ffa", "tdm", "1v1", "aim", "build"}
    ffa = next(g for g in r.json() if g["id"] == "ffa")
    assert ffa["max_players"] == 8
    assert ffa["kill_target"] == 0


def test_get_single_game(client):
    r = client.get("/api/games/tdm")
    assert r.status_code == 200
    assert r.json()["name"] == "Team Deathmatch"
    assert r.json()["team_mode"] is True


def test_get_unknown_game(client):
    assert client.get("/api/games/bogus").status_code == 404


def test_room_heartbeat_and_list(client):
    t, aid = _mk(client, "hosty")
    r = client.post(
        "/api/rooms/heartbeat",
        json={"code": "ABC12", "mode": "ffa", "players": [{"account_id": aid, "name": "hosty"}]},
        headers=_auth(t),
    )
    assert r.status_code == 200
    assert r.json()["code"] == "ABC12"
    assert r.json()["player_count"] == 1

    r = client.get("/api/rooms")
    assert r.status_code == 200
    codes = [x["code"] for x in r.json()]
    assert "ABC12" in codes

    r = client.get("/api/rooms/ABC12")
    assert r.status_code == 200
    assert r.json()["mode"] == "ffa"


def test_room_not_found(client):
    assert client.get("/api/rooms/ZZZZZ").status_code == 404