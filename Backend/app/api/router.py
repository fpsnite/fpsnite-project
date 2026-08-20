"""Aggregates all API sub-routers."""
from fastapi import APIRouter

from app.api.routes import currency, friends, games, health, leaderboard, players, rooms, stats

api_router = APIRouter()
api_router.include_router(health.router)
api_router.include_router(players.router)
api_router.include_router(friends.router)
api_router.include_router(leaderboard.router)
api_router.include_router(currency.router)
api_router.include_router(stats.router)
api_router.include_router(games.router)
api_router.include_router(rooms.router)