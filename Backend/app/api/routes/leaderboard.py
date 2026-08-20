"""Leaderboard endpoints: top players by a stat column."""
from fastapi import APIRouter, HTTPException
from sqlalchemy import func, select

from app.api.dependencies import DbDep
from app.models.player import Player
from app.schemas.stats import LEADERBOARD_STATS, LeaderboardEntry

router = APIRouter(prefix="/leaderboard", tags=["leaderboard"])


@router.get("", response_model=list[LeaderboardEntry])
def leaderboard(stat: str = "kills", limit: int = 20, db: DbDep = None) -> list[LeaderboardEntry]:
    if stat not in LEADERBOARD_STATS:
        raise HTTPException(status_code=422, detail={"code": "INVALID_STAT", "message": "Unknown leaderboard stat."})
    if not 1 <= limit <= 100:
        limit = 20
    column = getattr(Player, stat)
    rows = db.execute(
        select(Player).order_by(func.coalesce(column, 0).desc(), Player.name.asc()).limit(limit)
    ).scalars()
    return [
        LeaderboardEntry(
            account_id=p.account_id,
            name=p.name,
            value=int(getattr(p, stat)),
            level=p.level,
            is_online=p.is_online,
        )
        for p in rows
    ]