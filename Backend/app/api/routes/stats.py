"""Stats endpoints: snapshot + match-result reporting."""
from fastapi import APIRouter

from app.api.dependencies import CurrentPlayer, DbDep, resolve_player_or_404
from app.core.config import settings
from app.schemas.stats import MatchResultIn, MatchResultOut, StatsOut
from app.services.stats import apply_match_result

router = APIRouter(tags=["stats"])


@router.get("/players/{account_id}/stats", response_model=StatsOut)
def get_stats(account_id: str, db: DbDep = None) -> StatsOut:
    player = resolve_player_or_404(db, account_id)
    return StatsOut(
        kills=player.kills,
        deaths=player.deaths,
        wins=player.wins,
        playtime_seconds=player.playtime_seconds,
        level=player.level,
        xp=player.xp,
    )


@router.post("/players/{account_id}/match-result", response_model=MatchResultOut)
def report_match_result(
    account_id: str, body: MatchResultIn, player: CurrentPlayer = None, db: DbDep = None
) -> MatchResultOut:
    updated = apply_match_result(
        db,
        player,
        kills=body.kills,
        deaths=body.deaths,
        won=body.won,
        duration_seconds=body.duration_seconds,
    )
    coins_earned = body.kills * settings.coins_per_kill + (settings.coins_per_win if body.won else 0)
    xp_earned = body.kills * settings.xp_per_kill + (settings.xp_per_win if body.won else settings.xp_per_loss)
    return MatchResultOut(
        coins_earned=coins_earned,
        xp_earned=xp_earned,
        level=updated.level,
        xp=updated.xp,
        total_coins=updated.coins,
    )