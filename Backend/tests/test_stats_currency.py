"""Leaderboard, currency, stats and presence API tests."""


def _mk(client, name, password="hunter2"):
    client.post("/api/auth/register", json={"name": name, "password": password})
    body = client.post("/api/auth/token", json={"name": name, "password": password}).json()
    return body["token"], body["player"]["account_id"]


def _auth(token):
    return {"Authorization": f"Bearer {token}"}


def _report(client, token, account_id, kills=1, deaths=0, won=False, duration=60):
    return client.post(
        f"/api/players/{account_id}/match-result",
        json={"kills": kills, "deaths": deaths, "won": won, "duration_seconds": duration},
        headers=_auth(token),
    )


def test_match_result_awards_coins_and_xp(client):
    t, aid = _mk(client, "mario")
    r = _report(client, t, aid, kills=2, deaths=1, won=True, duration=120)
    assert r.status_code == 200
    body = r.json()
    assert body["coins_earned"] == 2 * 10 + 50  # 70
    assert body["xp_earned"] == 2 * 25 + 150  # 200
    assert body["level"] == 1
    assert body["total_coins"] == 70

    stats = client.get(f"/api/players/{aid}/stats").json()
    assert stats["kills"] == 2
    assert stats["deaths"] == 1
    assert stats["wins"] == 1
    assert stats["playtime_seconds"] == 120
    assert stats["level"] == 1
    assert stats["xp"] == 200


def test_match_result_levels_up(client):
    t, aid = _mk(client, "luigi")
    r = _report(client, t, aid, kills=100, won=True)  # 100*25+150 = 2650 xp
    body = r.json()
    # Level 1 costs 1000 xp, level 2 costs 2000 xp -> 2650 reaches level 2 (1650 leftover)
    assert body["level"] == 2
    assert body["xp"] == 1650


def test_leaderboard_orders_by_stat(client):
    t_a, aid_a = _mk(client, "topguy")
    t_b, aid_b = _mk(client, "midguy")
    _report(client, t_a, aid_a, kills=5, won=True)
    _report(client, t_b, aid_b, kills=2, won=True)

    r = client.get("/api/leaderboard?stat=kills&limit=100")
    assert r.status_code == 200
    rows = r.json()
    ids = [x["account_id"] for x in rows]
    assert ids.index(aid_a) < ids.index(aid_b)  # 5 kills ranks above 2
    entry = next(x for x in rows if x["account_id"] == aid_a)
    assert entry["value"] == 5
    assert "name" in entry


def test_leaderboard_invalid_stat(client):
    r = client.get("/api/leaderboard?stat=bogus")
    assert r.status_code == 422


def test_currency_spend_insufficient(client):
    t, aid = _mk(client, "poor")
    r = client.post(
        f"/api/players/{aid}/coins/spend", json={"amount": 100}, headers=_auth(t)
    )
    assert r.status_code == 400
    assert r.json()["detail"]["code"] == "INSUFFICIENT_COINS"


def test_currency_spend_ok_after_earning(client):
    t, aid = _mk(client, "rich")
    _report(client, t, aid, kills=10, won=True)  # 150 coins
    r = client.post(
        f"/api/players/{aid}/coins/spend", json={"amount": 50}, headers=_auth(t)
    )
    assert r.status_code == 200
    assert r.json()["coins"] == 100


def test_buy_skin_and_equip(client):
    t, aid = _mk(client, "fashion")
    _report(client, t, aid, kills=50, won=True)  # 550 coins
    r = client.post(
        f"/api/players/{aid}/skins/buy", json={"skin_index": 3}, headers=_auth(t)
    )
    assert r.status_code == 200
    body = r.json()
    assert body["current_skin"] == 3
    assert 3 in body["skins_locker"]
    assert body["coins"] == 550 - 300

    profile = client.get(f"/api/players/{aid}").json()
    assert profile["current_skin"] == 3


def test_buy_skin_insufficient_coins(client):
    t, aid = _mk(client, "brokefashion")
    r = client.post(
        f"/api/players/{aid}/skins/buy", json={"skin_index": 4}, headers=_auth(t)
    )
    assert r.status_code == 400


def test_presence_heartbeat(client):
    t, aid = _mk(client, "present")
    r = client.post(
        f"/api/players/{aid}/presence",
        json={"online": True, "in_lobby": True, "in_game": False},
        headers=_auth(t),
    )
    assert r.status_code == 200
    body = r.json()
    assert body["is_online"] is True
    assert body["in_lobby"] is True
    assert body["in_game"] is False


def test_presence_requires_own_token(client):
    t_a, aid_a = _mk(client, "p1")
    t_b, _ = _mk(client, "p2")
    r = client.post(
        f"/api/players/{aid_a}/presence", json={"online": True}, headers=_auth(t_b)
    )
    assert r.status_code == 403