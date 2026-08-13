"""Aggregates all API sub-routers."""
from fastapi import APIRouter

from app.api.routes import health, players

api_router = APIRouter()
api_router.include_router(health.router)
api_router.include_router(players.router)
