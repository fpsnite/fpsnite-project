"""Match-result processing: coins/XP rewards, level ups, stat tracking."""
from sqlalchemy.orm import Session

from app.core.config import settings
from app.models.player import Player


def apply_match_result(
    db: Session,
    player: Player,
    kills: int,
    deaths: int,
    won: bool,
    duration_seconds: int,
) -> Player:
    coins_earned = kills * settings.coins_per_kill + (settings.coins_per_win if won else 0)
    xp_earned = kills * settings.xp_per_kill + (settings.xp_per_win if won else settings.xp_per_loss)

    player.kills += kills
    player.deaths += deaths
    if won:
        player.wins += 1
    player.playtime_seconds += duration_seconds
    player.coins += coins_earned
    player.xp += xp_earned

    while player.xp >= player.level * settings.xp_per_level:
        player.xp -= player.level * settings.xp_per_level
        player.level += 1

    db.commit()
    db.refresh(player)
    return player