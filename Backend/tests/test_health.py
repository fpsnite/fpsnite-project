"""Smoke tests for the API."""
from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)


def test_root():
    resp = client.get("/")
    assert resp.status_code == 200
    assert resp.json()["app"] == "FPS NITE Backend"


def test_health():
    resp = client.get("/api/health")
    assert resp.status_code == 200
    assert resp.json()["status"] == "ok"


def test_health_db():
    resp = client.get("/api/health/db")
    assert resp.status_code == 200
    assert resp.json()["status"] == "ok"
