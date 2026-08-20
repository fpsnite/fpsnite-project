"""Stats + leaderboard API schemas."""
from pydantic import BaseModel, Field

LEADERBOARD_STATS = ("kills", "wins", "level", "coins", "playtime_seconds", "xp")


class MatchResultIn(BaseModel):
    kills: int = Field(ge=0)
    deaths: int = Field(ge=0)
    won: bool = False
    duration_seconds: int = Field(ge=0, default=0)


class StatsOut(BaseModel):
    kills: int
    deaths: int
    wins: int
    playtime_seconds: int
    level: int
    xp: int


class LeaderboardEntry(BaseModel):
    account_id: str
    name: str
    value: int
    level: int
    is_online: bool


class MatchResultOut(BaseModel):
    coins_earned: int
    xp_earned: int
    level: int
    xp: int
    total_coins: int