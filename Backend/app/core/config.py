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
    app_version: str = "0.1.0"
    api_prefix: str = "/api"

    database_url: str = os.getenv("DATABASE_URL", "sqlite:///./fpsnite.db")

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
