"""Run the Discord bot inside the FastAPI process (same event loop as uvicorn).

Used by app.main's lifespan so a single Render service serves the API and
the bot together. The bot is optional: without DISCORD_BOT_TOKEN it is
simply skipped. Requires uvicorn with a single worker (Render's default,
WEB_CONCURRENCY=1) - multiple workers would each try to log in with the
same token. The standalone entrypoint `python -m bot` still works too.
"""
import asyncio
import logging

import discord

from app.core.config import settings
from bot.main import build_bot

logger = logging.getLogger(__name__)


class BotRunner:
    def __init__(self) -> None:
        self._client: discord.Client | None = None
        self._task: asyncio.Task | None = None

    @property
    def enabled(self) -> bool:
        return bool(settings.discord_bot_token.strip())

    async def start(self) -> None:
        if not self.enabled:
            logger.warning("DISCORD_BOT_TOKEN not set - Discord bot disabled")
            return
        self._client = build_bot()
        self._task = asyncio.create_task(self._run_bot(settings.discord_bot_token.strip()))
        logger.info("Discord bot started as background task")

    async def _run_bot(self, token: str) -> None:
        try:
            await self._client.start(token)
        except asyncio.CancelledError:
            raise
        except Exception:
            # Keep the API alive; the task exception is logged loudly.
            logger.exception("Discord bot stopped with an error")

    async def stop(self) -> None:
        if self._client is not None:
            await self._client.close()
        if self._task is not None:
            self._task.cancel()
            try:
                await self._task
            except (asyncio.CancelledError, Exception):
                pass


bot_runner = BotRunner()