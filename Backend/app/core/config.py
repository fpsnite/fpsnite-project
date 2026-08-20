"""Application settings loaded from environment / .env file."""
import os
from functools import lru_cache
from pathlib import Path

from dotenv import load_dotenv

BASE_DIR = Path(__file__).resolve().parents[2]
load_dotenv(BASE_DIR / ".env")


@lru_cache
def get_settings() -> "Settings":
    return Settings()


class Settings:
    """Runtime configuration for the FPS NITE backend."""

    app_name: str = "FPS NITE Backend"
    app_version: str = "0.2.0"
    api_prefix: str = "/api"

    database_url: str = os.getenv("DATABASE_URL", "sqlite:///./fpsnite.db")

    ## Economy / progression tunables.
    coins_per_kill: int = int(os.getenv("COINS_PER_KILL", "10"))
    coins_per_win: int = int(os.getenv("COINS_PER_WIN", "50"))
    xp_per_kill: int = int(os.getenv("XP_PER_KILL", "25"))
    xp_per_win: int = int(os.getenv("XP_PER_WIN", "150"))
    xp_per_loss: int = int(os.getenv("XP_PER_LOSS", "50"))
    xp_per_level: int = int(os.getenv("XP_PER_LEVEL", "1000"))
    room_stale_seconds: int = int(os.getenv("ROOM_STALE_SECONDS", "60"))

    ## Price per skin index (skins not listed are not purchasable).
    skin_prices: dict[str, int] = {
        "0": 0,   # default skin, always owned
        "1": 100,
        "2": 200,
        "3": 300,
        "4": 500,
    }

    cors_origins: list[str] = [
        o.strip()
        for o in os.getenv("CORS_ORIGINS", "http://localhost:5173,http://localhost:3000").split(",")
        if o.strip()
    ]

    discord_bot_token: str = os.getenv("DISCORD_BOT_TOKEN", "")

    @property
    def is_prod(self) -> bool:
        return os.getenv("ENV", "development").lower() == "production"


settings = get_settings()
